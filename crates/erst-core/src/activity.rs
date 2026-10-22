//! Activity aggregation: who was on screen, for how long, and when.

use std::collections::BTreeMap;

use crate::error::CoreError;
use crate::time::{
    MAX_BUCKETS, MS_PER_DAY, MS_PER_HOUR, TimeRange, local_day_buckets, local_day_count,
};
use crate::track::url_host;

/// Ranges up to this long get hour buckets. Longer ranges get day buckets.
const HOUR_BUCKETS_MAX_RANGE_MS: i64 = 3 * MS_PER_DAY;

/// Categories in the order that `categories` and the bucket fields use.
const CATEGORIES: [Category; 4] = [
    Category::Building,
    Category::Reading,
    Category::Talking,
    Category::Other,
];

/// A half-open interval `(start_ms, end_ms)`.
type Interval = (i64, i64);

/// One stretch of time spent in an app, optionally on a URL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Span {
    /// Bundle identifier of the app, for example `com.apple.Safari`.
    pub bundle_id: String,
    /// URL shown by the app, when it has one.
    pub url: Option<String>,
    /// Start time in Unix milliseconds.
    pub started_at: i64,
    /// End time in Unix milliseconds.
    pub ended_at: i64,
}

/// Coarse kind of work a span represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Category {
    /// Writing code, design, or notes.
    Building,
    /// Consuming pages, articles, books, or previews.
    Reading,
    /// Messages, mail, calls, and meetings.
    Talking,
    /// Everything else.
    Other,
}

/// Time spent in one app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppTotal {
    /// Bundle identifier.
    pub bundle_id: String,
    /// Total milliseconds on screen.
    pub ms: i64,
}

/// Time spent on one website host.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SiteTotal {
    /// Lowercase host without `www.`.
    pub host: String,
    /// Total milliseconds on screen.
    pub ms: i64,
}

/// The width of one activity bucket.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BucketKind {
    /// One hour from `range.start_ms`, unaffected by daylight saving.
    Hour,
    /// One local day, from one local midnight to the next.
    Day,
}

/// One bucket of activity, covering `[start_ms, end_ms)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ActivityBucket {
    /// Bucket start in Unix milliseconds.
    pub start_ms: i64,
    /// Bucket end in Unix milliseconds, exclusive.
    pub end_ms: i64,
    /// Milliseconds categorized as building.
    pub building_ms: i64,
    /// Milliseconds categorized as reading.
    pub reading_ms: i64,
    /// Milliseconds categorized as talking.
    pub talking_ms: i64,
    /// Milliseconds in the other category.
    pub other_ms: i64,
}

/// Aggregated activity over one range.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivitySummary {
    /// Range the summary covers.
    pub range: TimeRange,
    /// Milliseconds on screen. Every other total below adds up to this one.
    pub total_ms: i64,
    /// Per app totals, largest first, ties sorted by bundle identifier.
    pub apps: Vec<AppTotal>,
    /// Per website host totals, largest first, ties sorted by host.
    pub websites: Vec<SiteTotal>,
    /// Per category totals in enum order, including zero entries.
    pub categories: [(Category, i64); 4],
    /// Width of each bucket: one hour, or one local day for a long range.
    pub kind: BucketKind,
    /// Consecutive buckets covering `range`, in time order.
    pub buckets: Vec<ActivityBucket>,
}

/// Browsers. Their category comes from the site they show, and is reading otherwise.
const BROWSERS: &[&str] = &[
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "com.kagi.kagimacOS",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi",
    "app.zen-browser.zen",
    "company.thebrowser.Browser",
    "company.thebrowser.dia",
    "net.imput.helium",
    "org.chromium.Chromium",
    "org.mozilla.firefox",
];

/// Sites where people mostly write and talk, matched with their subdomains.
const TALKING_SITES: &[&str] = &[
    "discord.com",
    "mail.google.com",
    "meet.google.com",
    "messenger.com",
    "outlook.live.com",
    "outlook.office.com",
    "slack.com",
    "teams.microsoft.com",
    "telegram.org",
    "whatsapp.com",
    "zoom.us",
];

/// Sites where people mostly build things, matched with their subdomains.
const BUILDING_SITES: &[&str] = &[
    "127.0.0.1",
    "bitbucket.org",
    "chatgpt.com",
    "claude.ai",
    "crates.io",
    "developer.apple.com",
    "docs.rs",
    "figma.com",
    "github.com",
    "gitlab.com",
    "linear.app",
    "localhost",
    "netlify.com",
    "notion.so",
    "npmjs.com",
    "stackoverflow.com",
    "vercel.com",
];

/// Maps an app, and the site it shows when it is a browser, to its activity category.
///
/// A known site decides first, so `web.whatsapp.com` counts as talking in any browser. Then a
/// browser counts as reading, and other apps follow the built-in table documented in
/// `docs/ARCHITECTURE.md`. Unknown apps, including the empty identifier, are
/// [`Category::Other`]. `host` is a host as [`url_host`] returns it: lowercase, without `www.`.
pub fn categorize(bundle_id: &str, host: Option<&str>) -> Category {
    if let Some(host) = host {
        if matches_site(host, TALKING_SITES) {
            return Category::Talking;
        }
        if matches_site(host, BUILDING_SITES) {
            return Category::Building;
        }
    }
    if BROWSERS.contains(&bundle_id) {
        return Category::Reading;
    }
    match bundle_id {
        "com.anthropic.claudefordesktop"
        | "com.apple.dt.Xcode"
        | "com.apple.Terminal"
        | "com.exafunction.windsurf"
        | "com.figma.Desktop"
        | "com.googlecode.iterm2"
        | "com.jetbrains.intellij"
        | "com.linear"
        | "com.microsoft.VSCode"
        | "com.mitchellh.ghostty"
        | "com.openai.chat"
        | "com.sublimetext.4"
        | "com.t3tools.t3code"
        | "com.todesktop.230313mzl4w4u92"
        | "dev.zed.Zed"
        | "md.obsidian"
        | "notion.id" => Category::Building,
        "com.apple.Preview" | "com.apple.iBooksX" | "com.apple.news" => Category::Reading,
        "com.apple.FaceTime"
        | "com.apple.MobileSMS"
        | "com.apple.mail"
        | "com.hnc.Discord"
        | "com.microsoft.Outlook"
        | "com.microsoft.teams2"
        | "com.tinyspeck.slackmacgap"
        | "net.whatsapp.WhatsApp"
        | "org.whispersystems.signal-desktop"
        | "ru.keepcoder.Telegram"
        | "us.zoom.xos" => Category::Talking,
        _ => Category::Other,
    }
}

/// Whether `host` is one of `sites` or a subdomain of one.
fn matches_site(host: &str, sites: &[&str]) -> bool {
    sites.iter().any(|site| {
        host.strip_suffix(site)
            .is_some_and(|rest| rest.is_empty() || rest.ends_with('.'))
    })
}

/// Aggregates `spans` clipped to `range`.
///
/// Spans that overlap share their time: each moment belongs to the span that
/// started first, so every total counts it once and the totals add up. Buckets
/// are one hour wide for a range of up to three days. A longer range gets day
/// buckets that start at each local midnight in the zone `offset_ms_at`
/// describes, so a daylight saving day is 23 or 25 hours long.
///
/// # Errors
///
/// Returns [`CoreError::TooManyBuckets`] when the range needs more than
/// [`MAX_BUCKETS`] buckets, before any bucket is created.
pub fn summarize(
    spans: &[Span],
    range: TimeRange,
    offset_ms_at: impl Fn(i64) -> i64,
) -> Result<ActivitySummary, CoreError> {
    let (kind, bucket_ranges) = plan_buckets(range, &offset_ms_at)?;
    let mut buckets: Vec<ActivityBucket> = bucket_ranges
        .into_iter()
        .map(|bucket| ActivityBucket {
            start_ms: bucket.start_ms,
            end_ms: bucket.end_ms,
            ..ActivityBucket::default()
        })
        .collect();

    let mut total_ms = 0_i64;
    let mut by_app: BTreeMap<&str, i64> = BTreeMap::new();
    let mut by_site: BTreeMap<String, i64> = BTreeMap::new();
    let mut categories = CATEGORIES.map(|category| (category, 0_i64));
    for ((start, end), span) in owned_pieces(spans, range) {
        let ms = end.saturating_sub(start);
        let host = span.url.as_deref().and_then(url_host);
        let category = categorize(&span.bundle_id, host.as_deref());
        saturating_add_to(&mut total_ms, ms);
        saturating_add_to(by_app.entry(span.bundle_id.as_str()).or_default(), ms);
        if let Some(host) = host {
            saturating_add_to(by_site.entry(host).or_default(), ms);
        }
        saturating_add_to(&mut categories[category_index(category)].1, ms);
        split_across_buckets(&mut buckets, category, start, end);
    }

    Ok(ActivitySummary {
        range,
        total_ms,
        apps: sorted_apps(by_app),
        websites: sorted_websites(by_site),
        categories,
        kind,
        buckets,
    })
}

/// The bucket kind and the bucket ranges that cover `range`.
fn plan_buckets(
    range: TimeRange,
    offset_ms_at: &impl Fn(i64) -> i64,
) -> Result<(BucketKind, Vec<TimeRange>), CoreError> {
    if range.duration_ms() <= HOUR_BUCKETS_MAX_RANGE_MS {
        return Ok((BucketKind::Hour, hour_buckets(range)?));
    }
    let count = local_day_count(range, offset_ms_at);
    if count > u64::try_from(MAX_BUCKETS).unwrap_or(u64::MAX) {
        return Err(CoreError::TooManyBuckets { count });
    }
    Ok((BucketKind::Day, local_day_buckets(range, offset_ms_at)))
}

/// Hour buckets covering `range`, the last one clamped to its end.
fn hour_buckets(range: TimeRange) -> Result<Vec<TimeRange>, CoreError> {
    let count = hour_bucket_count(range)?;
    let starts =
        std::iter::successors(Some(range.start_ms), |start| start.checked_add(MS_PER_HOUR));
    Ok(starts
        .take(count)
        .map(|start_ms| TimeRange {
            start_ms,
            end_ms: start_ms.saturating_add(MS_PER_HOUR).min(range.end_ms),
        })
        .collect())
}

/// How many hour buckets cover `range`, or an error above the cap.
fn hour_bucket_count(range: TimeRange) -> Result<usize, CoreError> {
    let duration_ms = range.duration_ms().max(0);
    let count =
        u64::try_from(duration_ms.saturating_add(MS_PER_HOUR - 1) / MS_PER_HOUR).unwrap_or(0);
    let limit = u64::try_from(MAX_BUCKETS).unwrap_or(u64::MAX);
    if count > limit {
        return Err(CoreError::TooManyBuckets { count });
    }
    Ok(usize::try_from(count).unwrap_or(MAX_BUCKETS))
}

/// Splits the spans into pieces that do not overlap, each tied to its span.
///
/// The spans are clipped to `range` and visited in start order. A span keeps
/// only the part after the end of every span before it, so a moment that two
/// spans share goes to the span that started first.
fn owned_pieces(spans: &[Span], range: TimeRange) -> Vec<(Interval, &Span)> {
    let mut clipped: Vec<(Interval, &Span)> = spans
        .iter()
        .filter_map(|span| clip(span, range).map(|interval| (interval, span)))
        .collect();
    clipped.sort_by_key(|(interval, _)| *interval);
    let mut covered_until = range.start_ms;
    let mut pieces = Vec::with_capacity(clipped.len());
    for ((start, end), span) in clipped {
        let start = start.max(covered_until);
        if start < end {
            pieces.push(((start, end), span));
            covered_until = end;
        }
    }
    pieces
}

/// The part of a span inside `range`, or `None` when nothing is left.
fn clip(span: &Span, range: TimeRange) -> Option<Interval> {
    let start = span.started_at.max(range.start_ms);
    let end = span.ended_at.min(range.end_ms);
    (start < end).then_some((start, end))
}

/// Adds `[start, end)` to every bucket it touches, under `category`.
///
/// The interval must lie inside `range`, which the clipping guarantees.
fn split_across_buckets(buckets: &mut [ActivityBucket], category: Category, start: i64, end: i64) {
    let mut cursor = start;
    let mut index = buckets.partition_point(|bucket| bucket.end_ms <= cursor);
    while cursor < end {
        let Some(bucket) = buckets.get_mut(index) else {
            break;
        };
        let slice_end = end.min(bucket.end_ms);
        add_to_bucket(bucket, category, slice_end.saturating_sub(cursor));
        cursor = slice_end;
        index += 1;
    }
}

fn add_to_bucket(bucket: &mut ActivityBucket, category: Category, ms: i64) {
    let slot = match category {
        Category::Building => &mut bucket.building_ms,
        Category::Reading => &mut bucket.reading_ms,
        Category::Talking => &mut bucket.talking_ms,
        Category::Other => &mut bucket.other_ms,
    };
    saturating_add_to(slot, ms);
}

fn saturating_add_to(total: &mut i64, ms: i64) {
    *total = total.saturating_add(ms);
}

fn category_index(category: Category) -> usize {
    match category {
        Category::Building => 0,
        Category::Reading => 1,
        Category::Talking => 2,
        Category::Other => 3,
    }
}

fn sorted_apps(totals: BTreeMap<&str, i64>) -> Vec<AppTotal> {
    let mut apps: Vec<AppTotal> = totals
        .into_iter()
        .map(|(bundle_id, ms)| AppTotal {
            bundle_id: bundle_id.to_owned(),
            ms,
        })
        .collect();
    apps.sort_by(|left, right| {
        right
            .ms
            .cmp(&left.ms)
            .then_with(|| left.bundle_id.cmp(&right.bundle_id))
    });
    apps
}

fn sorted_websites(totals: BTreeMap<String, i64>) -> Vec<SiteTotal> {
    let mut websites: Vec<SiteTotal> = totals
        .into_iter()
        .map(|(host, ms)| SiteTotal { host, ms })
        .collect();
    websites.sort_by(|left, right| {
        right
            .ms
            .cmp(&left.ms)
            .then_with(|| left.host.cmp(&right.host))
    });
    websites
}

#[cfg(test)]
mod tests;
