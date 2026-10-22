//! The user's agent history window, read from the app settings document.
//!
//! The MCP tools and the `erst` commands both apply it, because an agent can
//! read through either.
//!
//! The window fails closed. A missing document, a missing field, or an
//! explicit null means no window. A document that cannot be read blocks agent
//! reads, because an agent must never see more history than the app shows.

use std::collections::BTreeMap;

use anyhow::{Context, Result, anyhow};
use erst_core::settings::SETTINGS_KEY;
use erst_core::time::{MS_PER_DAY, TimeRange};
use erst_store::Store;
use serde_json::Value;

/// Field inside the settings document, in the `snake_case` contract.
const HISTORY_DAYS_FIELD: &str = "agent_history_days";

/// The error an agent sees while the window cannot be read.
const UNREADABLE_MESSAGE: &str = "Erst cannot read its agent history setting, so agent reads are blocked. Open Erst and save its settings to rewrite the setting.";

/// How far back agents may read. `None` means no limit.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HistoryWindow {
    pub days: Option<u32>,
}

impl HistoryWindow {
    /// No limit, used when the app has not written the setting.
    pub const UNLIMITED: Self = Self { days: None };

    /// Oldest timestamp agents may read, or `None` for no limit.
    pub fn cutoff_ms(self, now_ms: i64) -> Option<i64> {
        self.days
            .map(|days| now_ms.saturating_sub(i64::from(days).saturating_mul(MS_PER_DAY)))
    }

    /// The later of `since_ms` and the cutoff, so a query never reaches past the window.
    pub fn clamp_since(self, since_ms: Option<i64>, now_ms: i64) -> Option<i64> {
        match (since_ms, self.cutoff_ms(now_ms)) {
            (Some(since), Some(cutoff)) => Some(since.max(cutoff)),
            (since, cutoff) => since.or(cutoff),
        }
    }

    /// The part of `range` inside the window, or `None` when all of it is older.
    pub fn clip(self, range: TimeRange, now_ms: i64) -> Option<TimeRange> {
        match self.cutoff_ms(now_ms) {
            Some(cutoff) if range.end_ms <= cutoff => None,
            Some(cutoff) => Some(TimeRange {
                start_ms: range.start_ms.max(cutoff),
                end_ms: range.end_ms,
            }),
            None => Some(range),
        }
    }

    /// Whether a moment captured at `captured_at` is inside the window.
    pub fn allows(self, captured_at: i64, now_ms: i64) -> bool {
        self.cutoff_ms(now_ms)
            .is_none_or(|cutoff| captured_at >= cutoff)
    }

    /// Why an `erst` command saw less than everything, for stderr. `None` without a limit.
    pub fn note(self) -> Option<String> {
        self.days.map(|days| {
            format!(
                "Limited to the last {days} days by the Erst agent history setting (Settings, Agents)."
            )
        })
    }
}

/// Reads the window from the store settings.
///
/// # Errors
///
/// Fails when the settings cannot be read or the document is unreadable. The
/// tool answers with the error text, so the agent learns why it got nothing.
pub fn history_window(store: &Store) -> Result<HistoryWindow> {
    let settings = store
        .settings()
        .context("could not read the Erst settings")?;
    from_settings(&settings)
}

/// Reads the window from a settings map.
///
/// # Errors
///
/// Returns an error when the document is not a JSON object, or when the field
/// is present but is neither null nor a number of days.
pub fn from_settings(settings: &BTreeMap<String, String>) -> Result<HistoryWindow> {
    let Some(raw) = settings.get(SETTINGS_KEY) else {
        return Ok(HistoryWindow::UNLIMITED);
    };
    let Ok(Value::Object(object)) = serde_json::from_str::<Value>(raw) else {
        return Err(anyhow!(UNREADABLE_MESSAGE));
    };
    match object.get(HISTORY_DAYS_FIELD) {
        None | Some(Value::Null) => Ok(HistoryWindow::UNLIMITED),
        Some(value) => days_from(value)
            .map(|days| HistoryWindow { days: Some(days) })
            .ok_or_else(|| anyhow!(UNREADABLE_MESSAGE)),
    }
}

/// A whole number of days, or a non-negative fraction that is rounded down.
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)] // guarded: finite and non-negative
fn days_from(value: &Value) -> Option<u32> {
    if let Some(days) = value.as_u64() {
        return Some(u32::try_from(days).unwrap_or(u32::MAX));
    }
    let days = value.as_f64()?;
    (days.is_finite() && days >= 0.0)
        .then(|| u32::try_from(days.floor() as u64).unwrap_or(u32::MAX))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use std::collections::BTreeMap;

    use erst_core::settings::SETTINGS_KEY;
    use erst_core::time::{MS_PER_DAY, TimeRange};

    use super::{HISTORY_DAYS_FIELD, HistoryWindow, from_settings};

    fn settings(raw: &str) -> BTreeMap<String, String> {
        let mut map = BTreeMap::new();
        map.insert(String::from(SETTINGS_KEY), String::from(raw));
        map
    }

    #[test]
    fn missing_setting_means_no_limit() {
        let window = from_settings(&BTreeMap::new()).unwrap();
        assert_eq!(window, HistoryWindow::UNLIMITED);
        assert_eq!(window.cutoff_ms(1_000), None);
    }

    #[test]
    fn missing_field_means_no_limit() {
        let window = from_settings(&settings(r#"{"compression":"faster"}"#)).unwrap();
        assert_eq!(window.days, None);
    }

    #[test]
    fn snake_case_field_sets_the_cutoff() {
        let window = from_settings(&settings(r#"{"agent_history_days": 7}"#)).unwrap();
        assert_eq!(window.days, Some(7));
        assert_eq!(window.cutoff_ms(10 * MS_PER_DAY), Some(3 * MS_PER_DAY));
    }

    #[test]
    fn the_camel_case_spelling_is_not_read() {
        let window = from_settings(&settings(r#"{"agentHistoryDays": 30}"#)).unwrap();
        assert_eq!(window.days, None);
    }

    #[test]
    fn null_field_means_no_limit() {
        let window = from_settings(&settings(r#"{"agent_history_days": null}"#)).unwrap();
        assert_eq!(window.days, None);
        assert_eq!(window.cutoff_ms(1_000), None);
    }

    #[test]
    fn zero_days_is_a_window_that_ends_now() {
        let window = from_settings(&settings(r#"{"agent_history_days": 0}"#)).unwrap();
        assert_eq!(window.cutoff_ms(5_000), Some(5_000));
    }

    #[test]
    fn fractional_days_are_rounded_down() {
        let window = from_settings(&settings(r#"{"agent_history_days": 2.9}"#)).unwrap();
        assert_eq!(window.days, Some(2));
    }

    #[test]
    fn a_field_that_is_not_a_number_of_days_blocks_agent_reads() {
        for raw in [
            r#"{"agent_history_days": -3}"#,
            r#"{"agent_history_days": "seven"}"#,
            r#"{"agent_history_days": true}"#,
        ] {
            let error = from_settings(&settings(raw)).unwrap_err();
            assert!(
                error.to_string().contains("agent reads are blocked"),
                "{raw}"
            );
        }
    }

    #[test]
    fn malformed_settings_json_blocks_agent_reads() {
        let error = from_settings(&settings("not json")).unwrap_err();
        assert!(error.to_string().contains("agent reads are blocked"));
    }

    #[test]
    fn a_settings_document_that_is_not_an_object_blocks_agent_reads() {
        for raw in ["[]", "null", "42", "\"text\""] {
            assert!(from_settings(&settings(raw)).is_err(), "{raw}");
        }
    }

    #[test]
    fn since_is_clamped_to_the_window() {
        let week = HistoryWindow { days: Some(7) };
        let now = 10 * MS_PER_DAY;
        assert_eq!(week.clamp_since(None, now), Some(3 * MS_PER_DAY));
        assert_eq!(
            week.clamp_since(Some(MS_PER_DAY), now),
            Some(3 * MS_PER_DAY)
        );
        assert_eq!(
            week.clamp_since(Some(5 * MS_PER_DAY), now),
            Some(5 * MS_PER_DAY)
        );
        assert_eq!(HistoryWindow::UNLIMITED.clamp_since(Some(7), now), Some(7));
        assert_eq!(HistoryWindow::UNLIMITED.clamp_since(None, now), None);
    }

    #[test]
    fn ranges_and_moments_outside_the_window_are_refused() {
        let week = HistoryWindow { days: Some(7) };
        let now = 10 * MS_PER_DAY;
        let old = TimeRange {
            start_ms: 0,
            end_ms: 2 * MS_PER_DAY,
        };
        let straddling = TimeRange {
            start_ms: 2 * MS_PER_DAY,
            end_ms: 4 * MS_PER_DAY,
        };
        assert_eq!(week.clip(old, now), None);
        assert_eq!(
            week.clip(straddling, now),
            Some(TimeRange {
                start_ms: 3 * MS_PER_DAY,
                end_ms: 4 * MS_PER_DAY
            })
        );
        assert!(!week.allows(2 * MS_PER_DAY, now));
        assert!(week.allows(3 * MS_PER_DAY, now));
        assert!(HistoryWindow::UNLIMITED.allows(0, now));
        assert_eq!(HistoryWindow::UNLIMITED.note(), None);
        assert!(week.note().unwrap().contains("last 7 days"));
    }

    #[test]
    fn field_name_matches_the_documented_contract() {
        assert_eq!(HISTORY_DAYS_FIELD, "agent_history_days");
    }
}
