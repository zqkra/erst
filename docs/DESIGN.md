# Design

The owner's rules and the Paper file "Erst" (page "02 App") guide the interface. Check Apple's System Settings and Screen Time before adding new controls or layouts.

## Principles

- Native macOS 26 Liquid Glass, always dark. Use `.glassEffect`, `GlassEffectContainer`, `.glass`, and `.glassProminent` where appropriate.
- Every overlay screen is one rounded glass surface. The host gives it a fixed size and dims the desktop outside it; the screen paints nothing beyond that surface.
- Flat and clean. No glows, gradients, colored shadows, bevels, status dots, middle-dot separators, or monospaced interface text.
- Butter is the only accent. Coral and orange indicate activity data; coral also marks destructive actions and errors.
- The captured screen is the content. Keep floating controls quiet and copy short.
- Schibsted Grotesk everywhere, including controls and synthetic preview frames.

## Tokens (`ErstUI/Theme`)

Views use named tokens for colors, typography, spacing, radii, and control geometry. Theme colors do not change with the system's light appearance.

| Token | Value | Use |
|---|---|---|
| `Color.erstGround` | `#0E0E0F` | Solid fallback for offscreen panels and the app icon |
| `Color.erstSurface` | primary text at 4.5% | Grouped content |
| `Color.erstText` | `#F4F2EE` | Primary text |
| `Color.erstSecondary` | `#9B988F` | Secondary text |
| `Color.erstButter` | `#F8D677` | Accent, selection, primary actions |
| `Color.erstInk` | `#1A1A1A` | Labels on butter |
| `Color.erstOrange` | `#F6A563` | Activity data |
| `Color.erstCoral` | `#EF7A68` | Activity data, destructive actions, errors |
| `Color.erstHairline` | primary text at 9% | Quiet dividers |
| `Color.erstFrameBackdrop` | black at 52% | Letterbox behind an aspect-fit frame |
| `Color.erstControlScrim` | black at 28% | Quiet grouping inside a glass surface |
| `Color.erstSelection` | butter at 18% | Settings sidebar selection |
| `Color.erstDisabledFill` | white at 8% | Disabled primary action fill |
| `Color.erstStorageText` / `erstStoragePreviews` | butter at 55% / 30% | Storage composition |
| `Radius.window` | 26 | Windows |
| `Radius.panel` | 30 | Floating timeline, search, and moment panels |
| `Radius.group` | 18 | Grouped content |
| `Radius.control` | capsule | Buttons and controls |
| `Spacing` | 4, 8, 12, 16, 20, 24, 32, 44 | Layout spacing |

`SettingsLayout`, `ControlMetrics`, and `HeatMetrics` name shared dimensions. Icon proportions and mark geometry live in Theme. Heat levels use a dark track, muted coral, coral, orange, and butter.

`GlassSurface` names the tint and lift shared by every floating surface: `.regular` glass tinted dark, a black shadow at 30% opacity with radius 8 and y 4. Reduce Transparency swaps the glass for `.regularMaterial`; offscreen snapshots swap it for the solid ground. Capsules use the same tint.

Schibsted Grotesk is bundled under `ErstUI/Resources/Fonts` and registered from the resource bundle before rendering. Display tracking tightens as size grows; body tracking is zero.

| Style | Size / weight / tracking |
|---|---|
| `display` | 56 / semibold / -0.04em |
| `title` | 22 / semibold / -0.02em |
| `headline` | 15 / semibold / -0.01em |
| `body` | 13 / regular / 0 |
| `caption` | 12 / regular / 0 |
| `welcomeTitle` / `stepTitle` | 32 / bold / -0.025em, 30 / bold / -0.025em (onboarding only) |
| `lead` | 15 / regular / 0 (onboarding sentences) |

## Screens

| Screen | Surface | Key parts |
|---|---|---|
| Timeline | Floating glass panel, about 80% by 90% of the visible frame | Captured frame inside the surface, search capsule, dock, source, app segment chips, heat, fixed playhead, zoom, Now |
| Search | Floating glass panel, about 65% by 65% of the visible frame, capped at 1080 by 720 | Query, app and time filters, result grid with cards top aligned per row; the selected card sits on a primary text 8% platter of radius 16 and the hovered card on 4%, a press settles a card to 98%; thumbnails keep a hairline edge and mark matched lines with butter 40% highlighter fills, no outline; matched words in butter medium on a butter 16% wash, adjacent words marked as one phrase |
| Moment | Floating glass panel, about 80% by 90% of the visible frame | Captured frame with live text and filmstrip on the left, inspector on the right, highlighter marks on the frame over lines with a search term; Text on screen reads as blocks (stacked short items as quiet chips, lists whose rows carry a value on the right as entries with the title leading, the value trailing in quiet figures, and the detail line under the title, wrapped lines joined into paragraphs in primary text at 80% only when the line above fills its column, rows and smaller print a step smaller in secondary; text too thin to see and fragments of one line are cleaned first) with faded edges instead of a scroll bar, and expands over the inspector, folding the title and details away with a 0.32 s critically damped spring, and one full-width action row: the page action and Copy text share the width equally at the extra-large control size, with the reminder bell a circle of the same height |
| Menu bar | Native menu bar window material, 320 wide | No title (the menu bar icon already says it is Erst); recorder state only when paused or missing a permission, time on screen, storage kept today, heat from midnight to now with every sixth hour and "Now" under it, "Most used today", then Open Timeline, Search, Activity, Pause for an Hour (Resume Recording while paused or switched off), and Settings and Quit Erst under their own separator. While an update waits, a row above Settings says "Update to Erst 0.1.1" ("Updating Erst…" while it downloads, "Relaunch to Update" once it is ready) with a 7 point butter dot at its trailing edge, and opens Settings on About. Text starts 16 from the edge. A row highlights under the pointer or the arrow keys (one highlight, as in a menu) with primary text at 10% in a radius 6 shape inset 6 from the edge, 16% while pressed; Return runs it |
| Activity | Window with native material | Day, Week, Month, date stepping, time total, category chart, apps and websites |
| Settings | Native split view with grouped forms | General, Storage, Privacy, Agents, Shortcuts, About Erst |
| Onboarding | Window 600 by 560 on the ground color, title bar transparent so the art reaches the top | Welcome, permissions, timeline, search, agents, ready (Paper page "03 Install & Setup"). The welcome is the brand art below over a 32 bold line and one sentence. Each later step: a 30 bold title, a 15 regular sentence, what to do, and a footer with the small e (30) that heats one part per step, "Step n of 4" or "All set", and the action. Permissions and agents are rows on quiet platters (radius 16, no outline) with a 38 icon, a 15 semibold title, a 13 subtitle, and at the trailing edge Allowed or Connected with a butter check, a glass action, or a quiet note. Agents suggests Claude Code and Codex only (Cursor stays in Settings), each with its own app icon from this Mac, or a quiet symbol when its app is not here. The timeline and search steps draw the shortcut as keycaps (72 high, radius 14, 3 deep) that turn butter when the user presses the real shortcut, with Skip until then. Ready shows where Erst lives and the two shortcuts as small keycaps |
| Installer | Finder window 660 by 400 from `dist/Erst.dmg` | The installer art below, the app icon (128) centered at 172, 177 where the echoes start, Applications at 484, 283 inside the e's mouth, and "Drag Erst into Applications" 13 regular `#9B988F` centered on the clean ground at the bottom. Finder draws its own item labels dark over any background picture |

### Brand art

The welcome, the onboarding footer's e, and the installer background are drawn the way the app icon was made, so they match it: `HeatCanvas` (in `ErstUI/Brand`) draws the shapes in white on black, blurs them like diffusing heat, adds zero-mean camera grain, and maps the result through the icon's thermal palette (`HeatPalette`: ground, `#2A1715`, `#72413A`, `#C36557`, `#D5745D`, `#F4A263`, `#FAC371`, `#FCD27B`). Echo rings cool with distance by getting thinner and dimmer, never by changing hue. No glows, vignettes, or fades are laid over the art; the only fade is heat dying out above the installer's caption.

The welcome plays once: the mark comes into focus on a horizon, the horizon draws out from it, then sixteen echoes leave 45 ms apart. Each is launched fast and slows as it spreads (about 0.95 s), so it starts smeared, wide and dim, and sharpens as it settles, which is motion blur along its own path, and it leaves hot and cools to its resting heat. The copy arrives 0.55 s in with the usual arrival. Reduce Motion shows the rested art at once. The installer background is rendered by `ErstSnapshots --installer-background` from the same code.

The README images (`docs/images/`) are composed in Paper, page "04 README", in the look of the launch film: a Jost 500 headline at 56 and a Jost 400 line at 24 over out-of-focus echoes, with the real screens from `ErstSnapshots` floating in the middle, and the wordmark in Inter Tight 600 on the hero. `brand/tools/readme_art.py` renders their heat backgrounds with the same method as `HeatCanvas` and cuts the overlay panels out of the snapshots; run `swift run ErstSnapshots` first, then `uv run --with numpy --with pillow --with scipy python brand/tools/readme_art.py`, and export each artboard at 1x.

### Window titles

Titles sit next to the app name, so they drop the app name that many apps append after a separator (hyphen, en dash, em dash, middle dot, pipe). A title that holds only the app name, or nothing, leaves the app name to stand in once. The Timeline source, segment chips, Search result cards, and the Moment inspector follow the rule.

### Timeline

A frame-indexed scrubber. Every kept frame takes the same width. Consecutive frames of one app, and of one site in a browser, form a segment chip with the app icon. Idle time takes no width, so a pause only shows as the pause chip between sessions. The selected capture fills the glass surface with aspect fill, under a top scrim (height 120, `#0E0E0F` at 70% to 0%) and a bottom scrim (height 340, 0% to 55% at 60% to 80%).

- Search capsule: centered, 16 from the top, width 560 capped at 45% of the surface, height 46, radius 23, native glass tinted `#1C1C1E` at 55%, inner hairline 0.5 `#FFFFFF24`, shadow black 22% y 8 blur 24. Horizontal padding 18, gap 12: mark 20 butter, placeholder "Search everything you saw" 15 regular white 72%, shortcut "Command-K" 13 white 50%.
- Search opens inside the timeline from the capsule, Command-K, or /. One critically damped spring (0.38 s in, 0.24 s out) drives it with the top edge fixed: the capsule first widens into the panel's 74 high query band while its words fade and the mark slides onto the query field, then the band drops to search's own size and its parts arrive in reading order (query, divider, filters, results) as it drops. The frame dims with black at 42% and the dock sinks 28 and fades. Escape or a click on the dim runs it back into the capsule. With Reduce Motion the panel only fades.
- Dock: inset 20 left, right, and bottom, height 194, radius 30, native glass tinted `#18181A` at 62%, inner hairline 0.5 `#FFFFFF24`, shadow black 30% y 16 blur 40. Padding 18 top, 16 bottom, 24 sides, row gap 14.
- Row 1, height 38, items centered: source, then the time block (clock and date) centered on the playhead, then actions right aligned. Source is the app icon 30 with radius 8 and a column with the window title 14 semibold `#F4F2EE` and the site host or app name 12 regular `#9B988F`, one line each. An app that is not installed on this Mac uses a letter tile instead: `#2C2C2E` radius 8 with its initial in 17 semibold `#F4F2EE`. The clock is `HH:mm:ss` 24 medium `#F4F2EE` with -0.01em tracking, the date `EEEE, d MMM` 13 regular `#9B988F` 10 after the clock on the same baseline. Actions are one capsule `#FFFFFF14` radius 19 height 38 with 6 horizontal padding and gap 2: copy image (`square.on.square`), Live Text (`text.viewfinder`), open in app (`arrow.up.forward.app`), each 40 by 30 with 17 point glyphs in `#F2EFE8`.
- Row 2, height 104: track and zoom column. The track is the dock inner width minus 176 and 16, clipped. The zoom column is 176 wide, gap 10, bottom aligned with the track.
- Chips sit at y 0, height 22, 4 apart. Fill `#FFFFFF0F` radius 11, leading padding 4, gap 6, icon 14 radius 4, app name 11 medium `#E6E2D9`, detail (the site host or the cleaned window title) 11 regular white 52% truncated at the chip end. The chip under the playhead uses fill butter 14%, radius 6, butter name at 11 semibold, and butter 70% detail. When a chip start scrolls out on the left, its content holds at the track's left edge plus 4. The detail, then the name, hide when the chip is too narrow; the icon hides below 22 wide. The chip icon follows the source icon: a letter tile when the app is not installed. A segment that starts a session is preceded by a 70 wide pause chip with 135 degree stripes (white 7%, 4 on 4 off, radius 11) and "Paused" 11 regular `#8E8B84` with 8 leading padding.
- A chip is a stretch of use, not a segment (`TimelineTrack.chipRuns`). Neighbouring segments of one app always share one chip, so moving between sites or windows of one app reads as one continuous chip named after its longest stretch. A glance, another app on screen for less than 15 seconds (from its first frame to the next app's), joins its neighbours, both of them when they are the same app, so passing through an app does not cut the chip. Time decides, never frames: an app read quietly for minutes keeps few frames and still gets its chip. A pause between sessions is never crossed, the last stretch is never a glance, the selected chip names exactly the app and site under the playhead, and Shift-arrow steps from chip to chip.
- Heat sits at y 32, height 44: one bar per frame, width points per frame minus 1 (minimum 1), top corners radius 1.5, bottom aligned at y 76. A bar's level is its activity: the kept frames within 30 seconds on each side of it, itself included, each weighing `min(1, change ratio / 0.05)` the way the menu bar heat weighs a frame. Level 1 starts at 1, then 2, 3, 4.5, and 6, so a busy minute reaches butter and a frame kept alone stays dark. Six levels step both height and color: `#2A2A2D` at 10 high, `#5A3330` at 16.5, `#B8574A` at 23, `#EF7A68` at 29.5, `#F6A563` at 36, and `#F8D677` at 42.5 for levels 0 through 5. Selection lives in the chip and the playhead, never in the heat.
- Hour labels sit at y 86: `HH:00` 11 regular `#7E7B74` at the first frame of each hour, skipped when closer than 48 to the previous label.
- Playhead: fixed at the track's horizontal center. A 2 by 56 butter line radius 1 at y 26, and a 12 point butter knob at y 22 with a 3 point `#141416` ring at 90%.
- Zoom column: scale capsule (`#FFFFFF0F` radius 17 height 34, padding 3) with four equal items 1h, 6h, Day, and Month, 12 regular white 60%; the selected preset is a pill `#FFFFFF24` radius 14 with a black 20% y 1 blur 2 shadow and 12 medium white text. The dock opens on 6h, so a named scale is always selected after a load. Each preset fits the frames around the playhead into the track width, clamped 2 to 24 points per frame. Now is a butter capsule height 34 radius 17 with 13 semibold `#1A1A1A`, at 50% opacity on the latest frame.
- Month replaces the frames with the calendar month of the selected frame: one column per day across the track, one row per wall-clock hour from midnight at the top, between y 24 and 80. Hours draw in the heat colors, levelled against the busiest hour of the month so days compare; runs of one level draw as one block in a column of radius 3, and hours still to come are the quiet color at 40%. The month name sits at the top left in 11 medium and the pointed hour at the top right (the hovered one while the pointer is over the grid). Day numbers sit at y 86, weekends dimmer, today brighter, and the selected day in butter semibold; under 18 points per column only odd dates are numbered. The selected day gets a white 8% band behind its column, the hovered day 5%, and the pointed hour a butter 1.5 ring over a 4 point `#141416` ring, so it reads on butter heat. The frame closest to the middle of the pointed hour fills the screen.

The date opens a popover with a graphical date picker and Today and Yesterday. Left and Right step one frame, Shift with them one segment, Return opens the Moment, Escape closes. At Month, Left and Right step one day, Shift with them one week, Up and Down one hour, and Return or a second click on the pointed hour opens its frames at 1h; scrolling sideways steps days and up or down steps hours. A click selects the nearest frame, scrolling snaps to it, and pinch or Command plus and minus zoom. Only the user's own scrolling and dragging select frames: when AppKit moves the track during a layout or a resize, the playhead goes back to the selection, so the timeline always opens on the newest frame. Keyboard actions never animate.

### Settings

The sidebar is a native source list (`List` in the sidebar style), so macOS draws its material, hover, selection, and keyboard focus. It lists each destination once, with About Erst in its own group at the end. The selection fills with butter at 18% under white text, and icons are secondary gray, butter on the selected row. The window starts at 900 by 600 points. Controls inherit Schibsted and butter while keeping native macOS behavior. Switches are butter when on.

- General: Launch at login, Record the screen, Capture every (1, 2, 5, 10 seconds), Compression (Faster, Smaller). No explanatory captions.
- Storage: usage card with screens, text, and previews; History with full quality, lighter copy (including Forever), and the final action (Keep the text, Delete everything); Never use more than (including No limit); the service's data folder with Show in Finder.
- Privacy: Never record these apps. Add app is one menu of eligible running regular apps, sorted by name with real icons, then Choose... for an app in `/Applications`. Excluded apps can be removed. The only caption is "Password fields are never recorded." Erase the last hour opens "Erase the last hour?" with "This removes the screens and text Erst kept in the last hour.", Erase, and Cancel.
- Agents: service-provided names and connection states, Connect or Disconnect for installed clients, inline coral errors, How far back (including All history), a Terminal group, and one Copy MCP config row under Other agents. Copy changes to Copied for two seconds. Terminal shows whether a terminal finds the `erst` command (Ready in any terminal, at /usr/local/bin/erst; Not installed; Points to another copy of Erst) with Install, Remove, or Update, then three example commands, each with what it does and a copy button that turns into a butter check for two seconds, and a footer that says agents that run commands can use it too.
- Shortcuts: the fixed global, timeline, and search keys.
- About Erst: app icon, name, version, then Updates, then one sentence and copyright. Updates is one grouped section (Paper page "02 App", "10 Settings · About" states): a status row with a 13 medium title, a 12 secondary detail, and one action at the trailing edge, then the two switches "Check for updates automatically" and "Download and install updates automatically" (off and disabled while checks are off), and a footer saying where updates come from. The status row reads "Erst is up to date" and "Checked today at 17:42" with a small bordered Check Now; "Erst 0.1.1 is available", "Released 2 days ago. 9.8 MB", the release notes one per line in secondary text, and the butter Update and Relaunch; while downloading, the size so far, a butter linear progress bar, and Cancel; then "Erst 0.1.1 is ready" with Relaunch to Update. Nothing about updates ever opens a window on its own.

Settings saves through `MemoryService.update` after a 300 ms debounce. Apps, agent installation state, MCP configuration, and the data folder come from the system or services.

## Interaction and verification

- Option-Space opens the timeline, the way into everything. Search opens from it (the capsule, Command-K, or /) and Escape returns to the timeline; Option-Shift-Space opens search directly. Escape closes panels. Search shows the newest moment of each recent visit before anything is typed.
- Timeline arrows step one frame; Shift-arrow steps one segment. At Month they step days, weeks with Shift, and hours with Up and Down. The track scrolls under a fixed playhead, clicking selects the nearest frame, and scroll, pinch, or Command plus and minus scrub and zoom. Keyboard actions never animate.
- Surfaces assemble in reading order (`Motion` in `ErstUI/Theme`). One critically damped spring (0.42 s) drives a surface; each part starts 8% of its progress after the one before (about 17 ms) and settles over 60% of it, rising 12 points from its edge out of an 8 point blur that reads as motion blur, or growing from 98% when centered. Blur goes only on text and images: a part that holds glass or an AppKit view only fades and moves, because blurring glass renders it flat. The timeline brings its frame into focus whenever a frame arrives after none, then the capsule from above and the dock from below; search brings its glass, query, divider, filters, and results; a moment its header, frame, inspector, title, details, and text; Activity and each onboarding step their rows. Recent visits and matches cascade in when they replace each other, while results refined during typing swap in place. The overlay's dim fades in over 0.16 s and out over 0.14 s, and focus returns to the previous app at once, so a key typed during the fade lands there. Typed and scrubbed changes never animate.
- Respect Reduce Motion and Reduce Transparency. Native glass becomes `.regularMaterial` when transparency is reduced.
- `erstOpaquePanels` supplies solid surfaces for offscreen snapshots. Settings uses the same confirmation copy in its native alert and its snapshot-only opaque confirmation view, since native alerts render in a separate window.
- `ErstSnapshots` hosts screens in real windows and writes 2x PNGs to `.erst-dev/snapshots/`. It waits for a screen to load before it captures, so a debounced search is never photographed empty. Overlay screens render at their hosted size over a neutral sample desktop with the dim layer, so the floating surface and its shadow are visible. Coverage: three menu states, six onboarding steps, timeline mid-history, at the latest frame, zoomed to one hour, and empty, search with selected results and both empty states, a moment opened from search, activity day and week, all six Settings destinations, erase confirmation, About while up to date, with an update available, and while it downloads, and the menu with an update waiting.
- Preview captures use Core Text in Schibsted and plain shapes. There is no fake macOS menu bar or vector font.
