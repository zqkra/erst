//! Named time zones, resolved with the IANA rules that chrono-tz embeds.
//!
//! The app passes its zone name (`TimeZone.current.identifier`). The rules come
//! from the crate and not from the host, so a query gives the same answer
//! whatever else the machine has installed.

use chrono::{DateTime, Offset, TimeZone as _, Utc};
use chrono_tz::Tz;

use crate::error::ErstError;

const MS_PER_SECOND: i64 = 1_000;

/// One named time zone that answers UTC offsets for any instant.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Zone(Tz);

impl Zone {
    /// Resolves an IANA name such as `America/New_York`.
    ///
    /// # Errors
    ///
    /// Returns [`ErstError::InvalidInput`] when the name is not in the zone
    /// database.
    pub(crate) fn named(name: &str) -> Result<Self, ErstError> {
        name.parse::<Tz>()
            .map(Self)
            .map_err(|_| ErstError::invalid(format!("unknown time zone {name:?}")))
    }

    /// The UTC offset at `at_ms` in milliseconds, positive east of Greenwich.
    pub(crate) fn offset_ms_at(&self, at_ms: i64) -> i64 {
        let Some(utc) = DateTime::<Utc>::from_timestamp_millis(at_ms) else {
            return 0;
        };
        let seconds = self
            .0
            .offset_from_utc_datetime(&utc.naive_utc())
            .fix()
            .local_minus_utc();
        i64::from(seconds) * MS_PER_SECOND
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use super::Zone;
    use crate::error::ErstError;

    /// 2026-11-01T06:00Z, when New York moves from EDT to EST.
    const NEW_YORK_FALL_BACK_MS: i64 = 1_793_512_800_000;

    #[test]
    fn named_zones_follow_their_daylight_saving_rules() {
        let zone = Zone::named("America/New_York").unwrap();
        assert_eq!(zone.offset_ms_at(NEW_YORK_FALL_BACK_MS - 1), -4 * 3_600_000);
        assert_eq!(zone.offset_ms_at(NEW_YORK_FALL_BACK_MS), -5 * 3_600_000);
    }

    #[test]
    fn half_hour_zones_keep_their_minutes() {
        let zone = Zone::named("Asia/Kolkata").unwrap();
        assert_eq!(zone.offset_ms_at(0), 5 * 3_600_000 + 30 * 60_000);
    }

    #[test]
    fn an_unknown_name_is_invalid_input() {
        let error = Zone::named("Mars/Olympus_Mons").unwrap_err();
        assert!(matches!(error, ErstError::InvalidInput { .. }), "{error}");
    }
}
