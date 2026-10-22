//! Reading and writing the one settings document, plus its excluded app table.

use super::Engine;
use crate::error::ErstError;
use crate::records::FfiSettings;
use erst_core::settings::SETTINGS_KEY;

use crate::settings::{clamp_capture_interval, decode, encode};

#[uniffi::export]
impl Engine {
    /// Everything the capture engine and the settings screen read.
    pub fn settings(&self) -> Result<FfiSettings, ErstError> {
        self.load_settings()
    }

    /// Stores the whole document and replaces the excluded app table.
    ///
    /// The capture interval is clamped to `1..=10` seconds before it is stored.
    pub fn update_settings(&self, mut settings: FfiSettings) -> Result<(), ErstError> {
        settings.capture_interval_seconds =
            clamp_capture_interval(settings.capture_interval_seconds);
        let encoded = encode(&settings)?;
        self.store.set_setting(SETTINGS_KEY, &encoded)?;
        let bundle_ids: Vec<String> = settings
            .excluded_apps
            .iter()
            .map(|app| app.bundle_id.clone())
            .collect();
        self.store.set_excluded_apps(&bundle_ids)?;
        Ok(())
    }
}

impl Engine {
    /// Loads the settings document, which is the source of every setting value.
    ///
    /// The excluded app table is a projection written by [`Engine::update_settings`]
    /// for SQL consumers; values always come from this document.
    pub(crate) fn load_settings(&self) -> Result<FfiSettings, ErstError> {
        let stored = self.store.settings()?;
        Ok(decode(stored.get(SETTINGS_KEY)))
    }
}
