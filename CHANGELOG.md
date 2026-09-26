# Changelog

One entry per version. Minor (0.x.0) for new features, patch (0.x.y) for fixes.

## 0.9.0 — 2026-09-26

- Offline speaker refinement on Stop: a second diarization pass (Nemotron 3 offline preset) over the whole recording re-attributes every word while keeping live labels and names. Fixes first words sticking to the previous speaker. Toggle in Settings > Meetings; the model (~200 MB) downloads on first use.

## 0.8.0 — 2026-09-26

- Session detail shows the size on disk and has a permanent delete (audio, transcript, summary) that requires typing DELETE.

## 0.7.3 — 2026-09-26

- About: author links to x.com/juannito, bio and "buy me a coffee" note. README: install guide.

## 0.7.2 — 2026-09-26

- The theme button leaves the toolbar and floats at the top right of the content: no more ">>" overflow chevron while the sidebar animates.

## 0.7.1 — 2026-09-26

- Sidebar: the new-project and eye buttons are back in the toolbar; collapsing the panel leaves only the icon to reopen it. Tab shows or hides the panel (except while typing in a field).

## 0.7.0 — 2026-09-26

- Dark mode: sun/moon button in the header, System/Light/Dark in About, ⌥⌘D.
- About redesigned (window and Settings tab): language, theme, version, author, donate, source code, sessions and log folders with "Open", acknowledgments.
- Sidebar: new-project button moved to the History header; the eye button removed (hidden projects via the View menu, ⌥⌘H, or Settings).

## 0.6.0 — 2026-09-26

- The app is now **KatchApp** (formerly MeetAI). Bundle id `com.juannito.katchapp`, repo github.com/juannito/KatchApp. First launch migrates settings, keys and the `~/Documents/MeetAI` folder to `~/Documents/KatchApp`. macOS asks again for Microphone, System Audio Recording and Documents.

## 0.5.0 — 2026-09-26

- Platform tag: each meeting records the app it was held on (Zoom, Teams, Meet in Chrome/Safari, FaceTime, WhatsApp…), shown in History and the header.
- Per-app capture: by default only the meeting app's audio is recorded; "all system audio" option in Settings > Meetings.
- Meeting detection: when a meeting app starts using the microphone, KatchApp asks whether to record. "Open KatchApp at login" option.
- Editable meeting-app list (rename, mark unknown apps, unmark known ones).

## 0.4.1 — 2026-09-26

- Fix: overlapping sidebar rows (fixed heights for history, projects and contacts).

## 0.4.0 — 2026-09-26

- In-conversation search: opening a meeting with a search term highlights every match, shows "N of M matches" with arrows to jump between them (⌘G / ⇧⌘G) and starts at the newest one.

## 0.3.1 — 2026-09-26

- Search is case- and accent-insensitive and also covers the generated summary.

## 0.3.0 — 2026-09-26

- Sidebar redesign: projects are collapsible groups inside History (sessions without a project on top). Right-click a project to hide, unhide or show it in Finder. "+" button to create a project and an eye button to reveal hidden ones. The folder menu is gone.
- Sidebar search: filters meetings by title, project, speaker names and transcript text; also filters contacts.

## 0.2.0 — 2026-09-26

- Session history in the sidebar, save sheet with title, discard to Trash.
- Projects as folders, with filter and hidden projects (reset on every launch).
- Contacts with photo, voice fingerprint (CAM++), scored suggestions on save and **live** while recording, "This is me" contact.
- Create contacts from old sessions: the fingerprint is computed on demand from the audio.
- Meeting summaries with an LLM: Ollama (with model downloads from Settings), OpenAI-compatible and Anthropic; automatic on save or manual per session; editable instructions.
- Settings: language (English default, Spanish), sessions folder, projects, summary.
- About window with credits, MIT license, bio and Buy Me a Coffee.
- Fixes: clipped window, windowless launch caused by the Documents permission prompt, signing with a developer certificate and the microphone entitlement.

## 0.1.0 — 2026-09-26

- First version: microphone + system audio recording, live transcription (Parakeet TDT v3) and speaker separation (Nemotron 3 Diarization), all local. Markdown and JSON export.
