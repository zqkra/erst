# Roadmap

Tiers match [docs/PRICING.md](PRICING.md). Items marked License or Pro need that tier. Unmarked items are free.

## 0.1 Foundation (current)

- Record the main display, keep only the frames that changed, and encode them to HEVC segments.
- Read the text on every kept frame, store each distinct line once, and search it with full-text search.
- Track focus spans for activity: apps, window titles, browser URLs, and idle time.
- The app has a timeline, search, moment detail, a menu bar item, activity, settings, and onboarding.
- You can set reminders on a moment, and Erst sends local notifications.
- Retention keeps full-quality video for a set time, then a lighter copy, under a storage limit.
- Settings cover launch at login, capture interval (1, 2, 5, or 10 seconds), compression, excluded apps, and how far back agents read.
- Password fields are never recorded. Erase the last hour removes the screens and text for that hour, and their search entries, with secure delete.
- The `erst` CLI and MCP server ship inside the app. Settings > Agents connects Claude Code, Codex, and Cursor in one click.
- A stable self-signed identity keeps the Screen Recording permission across rebuilds. Notarized builds wait for an Apple Developer account.

## 0.2 Memory that helps

- "Where was I?" after lunch or a meeting: the last things you worked on, per app. (License)
- Automatic collections: every link, post, and video you saw, searchable by site and author. (License)
- Natural language questions answered by a local model. (License)
- A daily summary written to a journal, exportable to Notes or Markdown. (License)
- Time per project or client, exportable. (License)

### Privacy and agents

These left 0.1 because they did not work yet.

- Encrypted history: encrypt the database with SQLCipher and keep its key in the Keychain. Needs a SQLCipher build in place of the bundled SQLite, and a migration for existing databases.
- Skip private browser windows: do not record frames from private windows. Needs a private-window signal for each supported browser, tested in each one.
- Pause while sharing the screen: stop capture while a screen share runs. Needs a reliable signal for an active share, and a test that capture stops.
- Agents receive images: return screen images as MCP results. Needs an image result in `erst-cli`, a size limit, and the same history window that limits text results.
- Agents ask before each request: ask you before an agent reads your history. Needs a channel from the `erst mcp` process to the app, because each agent starts its own process.

## 0.3 Everywhere

- Encrypted sync between Macs. Needs encrypted history from 0.2, and a way to share its key between Macs. (Pro)
- An iPhone companion to search your history. Needs sync first, because the phone searches history that the Macs send. (Pro)
- Windows and Linux capture backends on the same Rust core. Needs a capture and OCR backend for each platform. The Rust core already has no platform code.
