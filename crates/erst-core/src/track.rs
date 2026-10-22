//! Timeline track: kept frames grouped into app and site segments.

/// Pauses longer than this start a new session: the track shows a wider gap there.
pub const SESSION_GAP_MS: i64 = 10 * 60 * 1_000;

/// What makes two frames belong to one segment.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SegmentKey {
    /// Bundle identifier of the app on screen.
    pub bundle_id: String,
    /// Site host for browser frames (lowercased, no leading `www.`), `None` otherwise.
    pub host: Option<String>,
}

/// One stretch of consecutive frames that the track draws as a single piece.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackSegment {
    /// App and site the frames share.
    pub key: SegmentKey,
    /// Index into the frames slice of the first frame, inclusive.
    pub first_index: usize,
    /// Index into the frames slice of the last frame, inclusive.
    pub last_index: usize,
    /// Capture time of the first frame in Unix milliseconds.
    pub started_at_ms: i64,
    /// Capture time of the last frame in Unix milliseconds.
    pub ended_at_ms: i64,
    /// True for the first segment and after a pause longer than [`SESSION_GAP_MS`].
    pub starts_session: bool,
}

/// Groups consecutive frames with the same key into segments.
///
/// `frames` is `(captured_at_ms, key)` in capture order. A frame joins the
/// current segment when its key matches and the pause since the previous frame
/// is at most [`SESSION_GAP_MS`]. Otherwise it starts a new segment, and a pause
/// longer than the gap also starts a new session.
pub fn group_segments(frames: &[(i64, SegmentKey)]) -> Vec<TrackSegment> {
    let mut segments: Vec<TrackSegment> = Vec::new();
    let mut previous_at: Option<i64> = None;
    for (index, (at_ms, key)) in frames.iter().enumerate() {
        let pause = previous_at.map(|previous| at_ms.saturating_sub(previous));
        let joins = segments.last().is_some_and(|segment| {
            segment.key == *key && pause.is_some_and(|pause| pause <= SESSION_GAP_MS)
        });
        let starts_session = pause.is_none_or(|pause| pause > SESSION_GAP_MS);
        if joins {
            if let Some(segment) = segments.last_mut() {
                segment.last_index = index;
                segment.ended_at_ms = *at_ms;
            }
        } else {
            segments.push(TrackSegment {
                key: key.clone(),
                first_index: index,
                last_index: index,
                started_at_ms: *at_ms,
                ended_at_ms: *at_ms,
                starts_session,
            });
        }
        previous_at = Some(*at_ms);
    }
    segments
}

/// The site host of a browser URL: lowercased, without scheme, port, or leading
/// `www.`.
///
/// Returns `None` for a value that is not an http or https URL, so a browser
/// frame showing a local file or an internal page has no site.
pub fn url_host(url: &str) -> Option<String> {
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return None;
    }
    let rest = match trimmed.split_once("://") {
        Some((scheme, rest)) => {
            if !is_web_scheme(scheme) {
                return None;
            }
            rest
        }
        None => match trimmed.split_once(':') {
            Some((scheme, rest)) if is_web_scheme(scheme) => rest,
            // A scheme without slashes, such as `about:blank` or `mailto:`, is
            // not a website. A host with a port has a dot before that colon,
            // which keeps `example.com:8443/x` a host.
            Some((scheme, _)) if !scheme.contains('.') => return None,
            _ => trimmed,
        },
    };
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    let host_port = authority
        .rsplit_once('@')
        .map_or(authority, |(_, host)| host);
    let host = if let Some(rest) = host_port.strip_prefix('[') {
        rest.split_once(']').map_or(rest, |(host, _)| host)
    } else {
        host_port
            .split_once(':')
            .map_or(host_port, |(host, _)| host)
    };
    let lowered = host.to_lowercase();
    let stripped = lowered.strip_prefix("www.").unwrap_or(&lowered);
    if stripped.is_empty() {
        None
    } else {
        Some(stripped.to_owned())
    }
}

fn is_web_scheme(scheme: &str) -> bool {
    scheme.eq_ignore_ascii_case("http") || scheme.eq_ignore_ascii_case("https")
}

#[cfg(test)]
mod tests;
