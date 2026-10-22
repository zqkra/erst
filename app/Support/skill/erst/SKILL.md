---
name: erst
description: >-
  Look things up in Erst, the user's private memory of their Mac screen: every word that was on
  screen, with the time, app, window, and web address. Use it whenever the user points at their own
  past on this Mac instead of describing it: "what was that article I read this morning", "find
  the error I saw in the terminal", "what was the price on that page", "what was I working on
  yesterday afternoon", "who sent me that link", "how long was I on YouTube today", "take me back
  to when I was looking at the invoice". Also use it to recover something the user saw but did not
  save, such as a command, an address, a number, or a message.
---

# Erst: the user's screen memory

Erst runs on this Mac and keeps the text that was on the screen, read every few seconds, together
with when it was there and which app, window, and page showed it. It never leaves the Mac. You
read it as text only; you never get screenshots.

Search it the way the user would remember it: by the words that were on the screen, the app, and
roughly when. It matches words, not meaning.

## Two ways in

Prefer the MCP tools when they are listed, because they respect how far back the user lets agents
look (Settings, Agents, How far back):

- `search_screen_history` with `query` and an optional `limit`: the moments that match, each with
  its `frame_id`, local time, app, window title, web address, and the matched lines.
- `get_moment` with a `frame_id`: every line of that moment, top to bottom and left to right.
- `activity_summary` with an optional `day` (`YYYY-MM-DD`): time on screen per category, app,
  and website for one day.

Without them, use the `erst` command. If the shell does not find it, run
`/Applications/Erst.app/Contents/Helpers/erst`, or ask the user to choose Install under Settings,
Agents, Terminal.

```sh
erst search <words> [--limit N] [--json]   # matching moments, newest first
erst moment <frame_id> [--json]            # every line of one moment, in reading order
erst activity [--day YYYY-MM-DD] [--json]  # one day's time per category, app, and website
erst stats [--json]                        # how much Erst holds and since when
```

Use `--json` whenever you parse the output.

## Writing a query

- Every word must appear in the same moment. The last word also matches as a prefix, so
  `invoice 2026` finds "invoice 20261103" and `kubern` finds "kubernetes".
- `"exact phrase"` matches those words together and in that order.
- `app:Safari`, `app:"Visual Studio Code"`, or a bundle ID such as `app:com.apple.Terminal` keeps
  one app. App names are matched whole, so use the name the app shows in its menu bar.
- `today`, `yesterday`, `since:2026-10-01`, and `until:2026-10-20` narrow by the user's local
  days. They only narrow: a query needs at least one word or phrase.

## Finding it

1. Start with the most distinctive words the user would have seen on screen: a name, a title, an
   error message, a number, a domain. Two or three good words beat a sentence.
2. Narrow with an app or a day when the user gives one. Broaden when nothing comes back: drop a
   word, try a synonym or another spelling, the other language the user works in, or a shorter
   prefix.
3. Read the best few moments with `get_moment` or `erst moment` before answering. A matched line
   alone often lacks the context the user needs, such as the rest of the message, the price next
   to the item, or the command after the error.
4. For "what was I doing" questions, start from the day's activity, then search inside the apps
   and hours it shows.

Several moments can show the same text over minutes. Search returns each one once, with when it
was first and last seen.

## Answering

- Give what was on the screen, quoted briefly, with the local time, the app, and the window title
  or web address. Include the address when there is one, so the user can open it again.
- Say plainly when nothing matched, and which words, apps, and days you tried.
- Never present a guess as something Erst holds. A match says the words were on screen, not that
  the user wrote or agreed with them.

## Care

This is the user's private history. Search only for what the question needs, keep unrelated
things you come across out of your answer, and do not send what you read anywhere else unless the
user asks. Erst skips password fields and the apps the user excluded, and it holds nothing while
recording was paused, so a missing moment may simply not exist.

## When it fails

- `command not found`: use the full path above.
- An error that the database is missing: Erst is not set up on this Mac yet; ask the user to open
  Erst once.
- Results stop at a certain date: that is the history the user allows agents, or the start of what
  Erst holds (`erst stats`).
