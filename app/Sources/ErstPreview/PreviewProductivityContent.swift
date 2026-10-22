import CoreGraphics
import Foundation

extension PreviewContent {
    static func mail(_ variant: Int) -> [PreviewLineSpec] {
        let folders = ["Inbox", "Sent", "Drafts", "Archive", "Trash"]
        var specs = folders.enumerated().map { index, folder in
            line(folder, 100, 150 + CGFloat(index) * 44, 180, 17)
        }
        let messages = [
            ("Maya Chen", "Design system handoff", "09:38", "The spacing and type pages are ready."),
            ("Noah Park", "Re: inspector radius", "09:12", "Smaller radius matches the window."),
            ("Lea Fischer", "Notes from the review", "08:47", "Three items left before we ship."),
            ("Erst", "Your week in memory", "08:02", "42 moments kept, 1.8 hours on screen."),
            ("Maya Chen", "Search edge cases", "Yesterday", "Group results that belong together."),
        ]
        specs += [
            line("Inbox", 300, 118, 220, 27),
            line("5 messages", 300, 152, 220, 14),
        ]
        for (index, message) in messages.enumerated() {
            let y = 200 + CGFloat(index) * 78
            specs += [
                line(message.0, 300, y, 220, 16),
                line(message.2, 620, y, 90, 13),
                line(message.1, 300, y + 24, 400, 17),
                line(message.3, 300, y + 48, 400, 14),
            ]
        }
        let subject = variant % 2 == 0 ? "Design system handoff" : "Notes from the review"
        specs += [
            line(subject, 900, 148, 600, 30),
            line("Maya Chen", 900, 190, 240, 16),
            line("To Erst, 09:38", 900, 212, 300, 13),
            line("Hi Erst,", 900, 258, 200, 18),
            line("The spacing and type pages are ready for review.", 900, 292, 620, 18),
            line("Every screen uses the same four steps now.", 900, 324, 620, 18),
            line("The inspector still needs a smaller radius.", 900, 356, 620, 18),
            line("I changed it to 26, which matches the window.", 900, 388, 620, 18),
            line("Search highlights look right in the new build.", 900, 420, 620, 18),
            line("Can you check the empty state before Friday?", 900, 452, 620, 18),
            line("Thanks,", 900, 510, 200, 18),
            line("Maya", 900, 542, 200, 18),
        ]
        return specs
    }

    static func notes(_ variant: Int, title: String?) -> [PreviewLineSpec] {
        let folders = ["iCloud", "All iCloud", "Notes", "Work", "Ideas", "Erst"]
        var specs = folders.enumerated().map { index, folder in
            line(folder, 100, 140 + CGFloat(index) * 42, 180, 16)
        }
        specs.append(line("Today", 420, 122, 160, 24))
        let titles = [
            "Product notes", "Design review", "Launch checklist", "Search edge cases", "Reminders",
        ]
        let previews = [
            "The design system now covers spacing.",
            "Inspector radius and dock spacing.",
            "Two items left before we ship.",
            "Group results that belong together.",
            "One sentence and a date.",
        ]
        for index in 0..<titles.count {
            let y = 190 + CGFloat(index) * 48
            specs += [
                line(titles[index], 420, y, 320, 17),
                line(previews[index], 420, y + 22, 320, 13),
            ]
        }
        let noteTitle = title == "Design review" ? "Design review" : "Product notes"
        let bodies: [[String]] = [
            [
                "The design system now covers spacing, type, and color.",
                "Keep the timeline dock quiet. The frame is the content.",
                "Search should show the matched line, not just the page.",
                "Reminders need a date and one sentence. Nothing else.",
                "Storage: show what is kept, not what is deleted.",
                "Every empty state needs a next action.",
                "Privacy copy should name the thing being protected.",
                "Keyboard actions never animate.",
                "The inspector is part of the window, not a floating panel.",
            ],
            [
                "The inspector radius is smaller than the dock. Confirmed.",
                "Search cards need the matched line, not only the page.",
                "The new settings copy is shorter. Keep it.",
                "Reminders: one sentence, one date.",
                "The filmstrip should center the current moment.",
                "The design system now covers spacing, type, and color.",
                "Keyboard actions never animate.",
                "Every empty state needs a next action.",
                "Privacy copy should name the thing being protected.",
            ],
        ]
        specs += [
            line(noteTitle, 820, 140, 500, 32),
            line("Today at 15:04", 820, 180, 320, 13),
        ]
        for (index, text) in bodies[variant % bodies.count].enumerated() {
            specs.append(line(text, 820, 230 + CGFloat(index) * 32, 620, 18))
        }
        return specs
    }

    static func editor(_ variant: Int) -> [PreviewLineSpec] {
        let files = ["erst", "crates", "capture", "capture.rs", "diff.rs", "encoder", "store", "Cargo.toml"]
        var specs = [
            line("capture.rs", 380, 108, 110, 15),
            line("encoder.rs", 510, 108, 110, 15),
            line("store.rs", 640, 108, 110, 15),
        ]
        specs += files.enumerated().map { index, file in
            line(file, 120, 164 + CGFloat(index) * 32, 200, 15)
        }
        let code: [[String]] = [
            [
                " 1  use crate::diff::changed_tiles;", " 2",
                " 3  /// Keep a frame only when the screen changed enough.",
                " 4  pub fn should_keep(prev: &Frame, next: &Frame) -> bool {",
                " 5      let tiles = changed_tiles(prev, next, TILE_SIZE);",
                " 6      let ratio = tiles.len() as f32 / prev.tile_count() as f32;",
                " 7      ratio > KEEP_THRESHOLD || next.app != prev.app",
                " 8  }", " 9",
                "10  // Keep the design system tokens in one place.",
                "11  pub fn record(mut rx: Receiver<Frame>, enc: &mut Encoder) {",
                "12      let mut last: Option<Frame> = None;",
                "13      while let Some(frame) = rx.recv().await {",
                "14          if last.as_ref().map_or(true, |p| should_keep(p, &frame)) {",
                "15              enc.push(&frame).await;",
                "16              last = Some(frame);",
                "17          }",
                "18      }",
            ],
            [
                " 1  use crate::store::Store;", " 2",
                " 3  /// Group nearby frames into one result.",
                " 4  pub fn group(hits: Vec<Hit>, now_ms: i64) -> Vec<SearchHit> {",
                " 5      let mut out: Vec<SearchHit> = Vec::new();",
                " 6      for hit in hits {",
                " 7          if let Some(last) = out.last_mut() {",
                " 8              if last.overlaps(&hit, 600_000) {",
                " 9                  last.extend(hit);",
                "10                  continue;",
                "11              }",
                "12          }",
                "13          out.push(hit);",
                "14      }",
                "15      out",
                "16  }",
                "17",
                "18  // Query parsing lives in erst-core::query.",
            ],
        ]
        let selected = code[variant % code.count]
        specs += selected.enumerated().map { index, text in
            line(text, 400, 170 + CGFloat(index) * 26, 1100, 16)
        }
        let terminal = [
            "$ cargo test -p capture",
            "running 12 tests",
            "test diff::identical_frames_are_skipped ... ok",
            "test diff::cursor_blink_is_ignored ... ok",
            "test result: ok. 12 passed; 0 failed",
        ]
        specs += terminal.enumerated().map { index, text in
            line(text, 400, 694 + CGFloat(index) * 24, 1100, 14)
        }
        return specs
    }
}
