# Notch

A native macOS app that sits in the MacBook camera notch. Click the island, or press **⌃⌥Space**, to open it. There is no Dock icon. Quit from the sparkles menu in the menu bar.

## What it does

- **Home** shows the clock, calendar, to-dos, clipboard, capture, and system stats.
- **Chat** streams replies from an OpenAI-compatible API. Say “use DeepSeek” or paste an `sk-` key in chat to update Settings.
- **Clipboard** keeps recent copies and can explain, rewrite, summarize, translate, or fix them.
- **Capture** takes a full screen, a selection, or a window. System screenshots land here too.
- **Notes** is an inbox for notes and lecture recordings. Lectures are saved as Markdown in `Documents/Notch Lectures`.
- **Calendar** and **To-dos** sync with EventKit. To-dos live in Reminders. Deleted reminders stay in trash for 30 days.
- **Day** shows how far through the day you are.
- **Now Playing** sits in the header for Music, Spotify, and browser playback. Play, pause, skip, and scrub from the island.
- **Open apps** from chat. “Open Mail” or “check my inbox” launches the app and collapses the island.
- **Jev** is optional. A TypeSafe key in Settings can route “write this in Notes” and “find a YouTube video” before the message goes to chat.

**⌃⌥N** saves the current clipboard as a note.

## Requirements

macOS 14 or later, and Swift 6 (Xcode or the Command Line Tools).

## Build

```bash
./scripts/build.sh
open dist/Notch.app
```

The script writes `dist/Notch.app` and `dist/Notch.zip`. If Gatekeeper blocks a shared build, right-click the app and choose Open.

You can also open `Package.swift` in Xcode and run the Notch target.

## Setup

Open the island and click the gear.

Pick a chat provider and paste its API key. The key is stored in the Keychain.

| Provider | Base URL | Default model |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash` |
| OpenAI | `https://api.openai.com` | `gpt-4o-mini` |
| Groq | `https://api.groq.com/openai` | `llama-3.3-70b-versatile` |
| Ollama | `http://127.0.0.1:11434` | a model you have pulled |
| Custom | any `/v1/chat/completions` URL | your model id |

Ollama does not need a key. Jev uses a separate TypeSafe key and is only for routing, not for chat replies.

Calendar, Reminders, the microphone, screen capture, and control of Music, Spotify, or Notes are asked for when you use those features.

## Layout

```
Sources/Notch/
  Notch/      window, geometry, shape
  Features/   chat, media, calendar, capture, Jev
  Views/      island UI
scripts/build.sh
```
