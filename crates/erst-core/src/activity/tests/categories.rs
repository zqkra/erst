//! Which category an app, and the site a browser shows, belongs to.

use super::super::{Category, categorize};

#[test]
fn categorize_building_apps() {
    for bundle_id in [
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.jetbrains.intellij",
        "com.sublimetext.4",
        "md.obsidian",
        "com.linear",
        "notion.id",
    ] {
        assert_eq!(
            categorize(bundle_id, None),
            Category::Building,
            "{bundle_id}"
        );
    }
}

#[test]
fn categorize_reading_apps() {
    for bundle_id in [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.apple.Preview",
        "com.apple.iBooksX",
        "com.apple.news",
    ] {
        assert_eq!(
            categorize(bundle_id, None),
            Category::Reading,
            "{bundle_id}"
        );
    }
}

#[test]
fn categorize_talking_apps() {
    for bundle_id in [
        "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "us.zoom.xos",
        "com.apple.mail",
        "com.microsoft.teams2",
        "ru.keepcoder.Telegram",
        "com.apple.FaceTime",
    ] {
        assert_eq!(
            categorize(bundle_id, None),
            Category::Talking,
            "{bundle_id}"
        );
    }
}

#[test]
fn categorize_unknown_apps_as_other() {
    assert_eq!(categorize("com.example.Unknown", None), Category::Other);
    assert_eq!(categorize("", None), Category::Other);
    assert_eq!(
        categorize("com.apple.Safari.Extension", None),
        Category::Other
    );
}

#[test]
fn a_known_site_decides_the_category_in_any_browser() {
    assert_eq!(
        categorize("net.imput.helium", Some("web.whatsapp.com")),
        Category::Talking
    );
    assert_eq!(
        categorize("com.google.Chrome", Some("app.slack.com")),
        Category::Talking
    );
    assert_eq!(
        categorize("com.apple.Safari", Some("github.com")),
        Category::Building
    );
    assert_eq!(
        categorize("company.thebrowser.dia", Some("localhost")),
        Category::Building
    );
    assert_eq!(
        categorize("net.imput.helium", Some("x.com")),
        Category::Reading
    );
    assert_eq!(categorize("net.imput.helium", None), Category::Reading);
}

#[test]
fn a_site_matches_its_subdomains_but_not_lookalikes() {
    assert_eq!(
        categorize("com.apple.Safari", Some("gist.github.com")),
        Category::Building
    );
    assert_eq!(
        categorize("com.apple.Safari", Some("notgithub.com")),
        Category::Reading
    );
    assert_eq!(
        categorize("com.apple.Safari", Some("github.com.evil.io")),
        Category::Reading
    );
}
