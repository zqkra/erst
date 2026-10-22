//! The persisted settings row: one JSON document with `snake_case` keys.
//!
//! The whole [`FfiSettings`] lives under the `settings.v1` key from `erst_core`.
//! Missing fields fall back to the defaults below, which match `ErstSettings.default`
//! in the Swift model. `erst-cli` reads `agent_history_days` out of this document,
//! so the field name is part of the contract.
//!
//! The document is read field by field. Unknown keys are ignored and a value
//! that no longer parses costs only its own default, so an old document keeps
//! every setting that is still valid.

use serde::de::DeserializeOwned;
use serde_json::{Map, Value};

use erst_core::MS_PER_DAY;

use crate::error::ErstError;
use crate::records::{FfiAfterLighterCopy, FfiAppRef, FfiCompression, FfiSettings};

/// Bytes in one gigabyte, decimal as storage screens report it.
pub(crate) const BYTES_PER_GIGABYTE: u64 = 1_000_000_000;

/// Days in the month used to convert `lighter_copy_months`.
pub(crate) const DAYS_PER_MONTH: i64 = 30;

/// Milliseconds in the month used to convert `lighter_copy_months`.
pub(crate) const MS_PER_MONTH: i64 = DAYS_PER_MONTH * MS_PER_DAY;

/// Shortest capture interval the app records, in seconds.
const MIN_CAPTURE_INTERVAL_SECONDS: u32 = 1;

/// Longest capture interval the app records, in seconds.
const MAX_CAPTURE_INTERVAL_SECONDS: u32 = 10;

/// The bundle identifier of the app excluded by default.
const DEFAULT_EXCLUDED_BUNDLE_ID: &str = "com.1password.1password";
/// The display name of the app excluded by default.
const DEFAULT_EXCLUDED_NAME: &str = "1Password";

impl Default for FfiSettings {
    fn default() -> Self {
        Self {
            is_recording: true,
            launch_at_login: true,
            capture_interval_seconds: 2,
            compression: FfiCompression::Smaller,
            full_quality_days: 7,
            lighter_copy_months: Some(3),
            after_lighter_copy: FfiAfterLighterCopy::KeepText,
            storage_limit_gigabytes: Some(20),
            excluded_apps: vec![FfiAppRef {
                bundle_id: DEFAULT_EXCLUDED_BUNDLE_ID.to_owned(),
                name: DEFAULT_EXCLUDED_NAME.to_owned(),
            }],
            agent_history_days: Some(7),
        }
    }
}

/// Decodes the stored document, falling back to the defaults when it is absent
/// or is not a JSON object.
pub(crate) fn decode(raw: Option<&String>) -> FfiSettings {
    let Some(raw) = raw else {
        return FfiSettings::default();
    };
    let Ok(value) = serde_json::from_str::<Value>(raw) else {
        return FfiSettings::default();
    };
    let Value::Object(object) = value else {
        return FfiSettings::default();
    };

    let mut settings = FfiSettings::default();
    settings.is_recording = field(&object, "is_recording", settings.is_recording);
    settings.launch_at_login = field(&object, "launch_at_login", settings.launch_at_login);
    settings.capture_interval_seconds = clamp_capture_interval(field(
        &object,
        "capture_interval_seconds",
        settings.capture_interval_seconds,
    ));
    settings.compression = field(&object, "compression", settings.compression);
    settings.full_quality_days = field(&object, "full_quality_days", settings.full_quality_days);
    settings.lighter_copy_months =
        field(&object, "lighter_copy_months", settings.lighter_copy_months);
    settings.after_lighter_copy = field(&object, "after_lighter_copy", settings.after_lighter_copy);
    settings.storage_limit_gigabytes = field(
        &object,
        "storage_limit_gigabytes",
        settings.storage_limit_gigabytes,
    );
    settings.excluded_apps = field(&object, "excluded_apps", settings.excluded_apps.clone());
    settings.agent_history_days = field(&object, "agent_history_days", settings.agent_history_days);
    settings
}

/// Encodes the settings for storage.
///
/// # Errors
///
/// Returns [`ErstError::InvalidInput`] when serde cannot encode the values.
pub(crate) fn encode(settings: &FfiSettings) -> Result<String, ErstError> {
    serde_json::to_string(settings).map_err(|error| ErstError::InvalidInput {
        message: format!("settings could not be encoded: {error}"),
    })
}

/// Keeps the capture interval inside the range the capture loop can honor.
pub(crate) fn clamp_capture_interval(seconds: u32) -> u32 {
    seconds.clamp(MIN_CAPTURE_INTERVAL_SECONDS, MAX_CAPTURE_INTERVAL_SECONDS)
}

/// Reads one field, falling back to `fallback` when it is missing or invalid.
///
/// A JSON `null` is a value like any other here: it parses for the `Option`
/// fields and means "no limit" there.
fn field<T: DeserializeOwned>(object: &Map<String, Value>, key: &str, fallback: T) -> T {
    object
        .get(key)
        .and_then(|value| serde_json::from_value(value.clone()).ok())
        .unwrap_or(fallback)
}
