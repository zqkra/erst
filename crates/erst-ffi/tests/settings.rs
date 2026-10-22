//! The settings document: round trip, old documents, and interval clamping.

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod common;

use common::open_engine;
use erst_ffi::{FfiAfterLighterCopy, FfiAppRef, FfiCompression, FfiSettings};
use erst_store::Store;

type TestResult = Result<(), Box<dyn std::error::Error>>;

const SETTINGS_DOCUMENT_KEY: &str = "settings.v1";

#[test]
fn settings_survive_a_round_trip() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    assert_eq!(engine.settings()?, FfiSettings::default());

    let changed = FfiSettings {
        is_recording: false,
        launch_at_login: false,
        capture_interval_seconds: 5,
        compression: FfiCompression::Faster,
        full_quality_days: 14,
        lighter_copy_months: None,
        after_lighter_copy: FfiAfterLighterCopy::DeleteEverything,
        storage_limit_gigabytes: None,
        excluded_apps: vec![
            FfiAppRef {
                bundle_id: "com.1password.1password".to_owned(),
                name: "1Password".to_owned(),
            },
            FfiAppRef {
                bundle_id: "com.tinyspeck.slackmacgap".to_owned(),
                name: "Slack".to_owned(),
            },
        ],
        agent_history_days: None,
    };
    engine.update_settings(changed.clone())?;
    assert_eq!(engine.settings()?, changed);

    let reader = Store::open_read_only(&data_dir.join("erst.sqlite"))?;
    let raw = reader
        .settings()?
        .get(SETTINGS_DOCUMENT_KEY)
        .cloned()
        .expect("settings document is stored");
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    assert_eq!(value["is_recording"], serde_json::json!(false));
    assert_eq!(value["launch_at_login"], serde_json::json!(false));
    assert_eq!(value["capture_interval_seconds"], serde_json::json!(5));
    assert_eq!(value["compression"], serde_json::json!("faster"));
    assert_eq!(value["full_quality_days"], serde_json::json!(14));
    assert_eq!(value["lighter_copy_months"], serde_json::Value::Null);
    assert_eq!(
        value["after_lighter_copy"],
        serde_json::json!("delete_everything")
    );
    assert_eq!(value["storage_limit_gigabytes"], serde_json::Value::Null);
    assert_eq!(value["agent_history_days"], serde_json::Value::Null);
    assert!(value.get("agentHistoryDays").is_none());
    assert_eq!(
        reader.excluded_apps()?,
        vec![
            "com.1password.1password".to_owned(),
            "com.tinyspeck.slackmacgap".to_owned(),
        ]
    );

    // The capture loop only honors intervals between one and ten seconds.
    let mut fast = engine.settings()?;
    fast.capture_interval_seconds = 0;
    engine.update_settings(fast)?;
    assert_eq!(engine.settings()?.capture_interval_seconds, 1);

    let mut slow = engine.settings()?;
    slow.capture_interval_seconds = 60;
    engine.update_settings(slow)?;
    assert_eq!(engine.settings()?.capture_interval_seconds, 10);
    Ok(())
}

#[test]
fn loads_an_old_settings_document() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    let old = serde_json::json!({
        "is_recording": false,
        "capture_interval_seconds": "often",
        "compression": "faster",
        "full_quality_days": 14,
        "lighter_copy_months": null,
        "after_lighter_copy": "text_only",
        "storage_limit_gigabytes": 5,
        "excluded_apps": [],
        "agent_history_days": 30,
        "skip_unchanged_frames": true,
        "skip_private_windows": false,
        "skip_password_fields": false,
        "pause_while_sharing_screen": false,
        "encrypt_history": false,
        "agent_content": "text_and_images",
        "ask_before_agent_request": false,
        "unknown_future_key": {"nested": [1, 2, 3]}
    });
    let writer = Store::open(&data_dir.join("erst.sqlite"))?;
    writer.set_setting(SETTINGS_DOCUMENT_KEY, &old.to_string())?;

    let expected = FfiSettings {
        is_recording: false,
        capture_interval_seconds: 2,
        compression: FfiCompression::Faster,
        full_quality_days: 14,
        lighter_copy_months: None,
        after_lighter_copy: FfiAfterLighterCopy::KeepText,
        storage_limit_gigabytes: Some(5),
        excluded_apps: Vec::new(),
        agent_history_days: Some(30),
        ..FfiSettings::default()
    };
    assert_eq!(engine.settings()?, expected);
    Ok(())
}
