# KatchApp

*[Versión en español](README.es.md)*

A 100% local meeting recorder for macOS. Press one button and get a live transcript (English and Spanish) with speakers separated as the meeting happens. Nothing leaves your Mac.

- **ASR:** NVIDIA Parakeet TDT 0.6B v3 (CoreML/ANE via FluidAudio), 25 languages, word-level timestamps.
- **Diarization:** NVIDIA Nemotron 3 Diarization (streaming, up to 8 speakers, CoreML).
- **VAD:** Silero v6 (CoreML).
- **Voice ID:** CAM++ speaker embeddings (CoreML) to recognise contacts across meetings.
- **Capture:** microphone (AVAudioEngine) + system audio (Core Audio process tap, macOS 14.4+, no virtual drivers).
- **Summaries (optional):** Ollama, any OpenAI-compatible server, or Anthropic.

Requirements: Apple Silicon, macOS 15+, Xcode 26 (to build). The first launch downloads ~1 GB of models into `~/Library/Application Support/FluidAudio/Models`.

## Author

**Juan ([@juannito](https://x.com/juannito))** — Freelance product designer & vibe coder. I design digital products end to end and build them with AI as my copilot; I'm obviously not a native Swift developer 🤷🏻‍♂️. If KatchApp is useful to you, [buy me a coffee](https://buymeacoffee.com/juannito) ☕ — it helps me keep making things like this.

## Install

There is no packaged download yet (a notarized build needs a paid Apple Developer account). Building it yourself takes a few minutes:

1. Requirements: a Mac with Apple Silicon, macOS 15 or newer, and [Xcode 26](https://apps.apple.com/app/xcode/id497799835) installed once (it provides the Swift toolchain and the CoreML frameworks).
2. Clone and build:

```bash
git clone https://github.com/juannito/KatchApp.git
cd KatchApp
scripts/build-app.sh          # builds dist/KatchApp.app (release), ~2 min the first time
open dist/KatchApp.app
```

3. Optionally move `dist/KatchApp.app` to `/Applications`.
4. On first launch the app downloads ~1 GB of models and compiles them for the Neural Engine (1–2 min). Later launches take under a second.
5. macOS will ask for Microphone, System Audio Recording and access to your Documents folder the first time you record. Grant all three.

The build script signs the app with an "Apple Development" certificate if you have one (keeps the privacy grants across rebuilds) and falls back to ad-hoc signing otherwise, which works fine for personal use.

### Development

```bash
swift build && .build/debug/KatchApp      # quick debug build
scripts/bump-version.sh X.Y.Z             # bump the version
```

## Usage

1. Wait until the footer says "Models ready".
2. Pick your sources: **Microphone** (you) and/or **System audio** (Zoom, Meet, Teams, browser).
3. **Record meeting** (⌘R). macOS asks for Microphone and "System Audio Recording" the first time.
4. Text shows up a few seconds after each pause; the speaker is assigned about a second later. While recording, known voices are suggested in the Speakers panel ("Looks like X (85%)") with a Confirm button.
5. Rename speakers in the right panel. The 🎤 icon marks the voice coming through your microphone.
6. **Stop.** The "Save meeting" sheet appears: give it a title, pick a project, link speakers to contacts (or create them), then Save. Discard sends the folder to the Trash.
7. Saved sessions live in the sidebar (**History**). Open one to re-read the transcript, rename or link speakers, change the title or project, copy the Markdown, open the audio or show it in Finder. Right-click to trash it.
8. **Search** (sidebar field): filters meetings by title, project, speaker names, transcript and summary text, case- and accent-insensitive. Opening a matching meeting highlights every hit, shows "N of M matches" and lets you jump between them (⌘G / ⇧⌘G), starting from the newest.
9. **Projects** are subfolders. Each project is a collapsible group in History; right-click it to hide it, unhide it or show it in Finder. Hidden projects vanish from the sidebar until you toggle "Show hidden projects" (eye button, ⌥⌘H), which resets on every launch — handy when sharing your screen. The folder button creates a project.
10. **Contacts and voice recognition.** Each contact stores a local voice fingerprint (CAM++ embedding, 192 floats), a photo, an optional "This is me" flag and the list of conversations they took part in. Linking a speaker of an old session computes the fingerprint on demand from `audio.wav`. Data lives in `contacts.json` and `avatars/` inside the sessions folder.
11. **Summaries (optional).** Settings > Summary: choose **Ollama** (local; the app lists installed models and downloads the one you pick), **OpenAI-compatible** (OpenAI, LM Studio, OpenRouter, vLLM) or **Anthropic**. API keys go to the Keychain. With "auto summary" on, minutes are generated on save; otherwise each session has a **Generate summary** button in its Summary tab. Output: summary, decisions, action items with owner and due date, follow-ups. Instructions are editable; the output format is fixed. Stored as `summary.md` and `summary.json`.
12. **Meeting platform, per-app capture and detection.** KatchApp looks at which processes have audio in Core Audio. Recordings are tagged with the active meeting app (Zoom, Teams, Meet in a browser, FaceTime, WhatsApp…). With "only the meeting app" (default) it captures just that app's audio instead of everything; if none is running it captures everything. Settings > Meetings can enable detection: when a meeting app starts using the microphone, KatchApp asks whether to record. "Open KatchApp at login" keeps it ready. The list of meeting apps is editable: rename, mark unknown apps, unmark known ones.
13. **Settings** (⌘,): language (English default, Spanish), theme (sun/moon button in the header, ⌥⌘D), sessions folder, projects, meetings, summary, About. Default sessions folder: `~/Documents/KatchApp/<project>/<date>/` with `transcript.md`, `transcript.json` and `audio.wav`.
14. **Tab** shows or hides the sidebar (except while typing in a text field).

## Headless self-test

```bash
scripts/make-test-audio.sh /tmp/dialog.wav        # synthetic two-voice dialog
.build/debug/KatchApp --selftest /tmp/dialog.wav   # runs the full pipeline and prints the result
.build/debug/KatchApp --audio-processes            # lists processes Core Audio knows about
.build/debug/KatchApp --summarize <session folder> [ollama model]
```

## Layout

```
Sources/KatchApp/
  Audio/     capture (system tap, microphone, resampler, mix bus, WAV, process list)
  Engine/    models, engine (VAD + ASR + diarization + attribution), session, stores, summaries, self-test
  Model/     transcript types, Markdown/JSON export, summary model
  UI/        SwiftUI
scripts/     build-app.sh, bump-version.sh, make-test-audio.sh
doc/         model and pipeline research
```

## Design decisions and known limits

- Cascade pipeline: ASR over voiced segments (VAD) + streaming diarization over the whole audio; each word goes to the speaker with the most activity in its interval. See `doc/research-realtime-stt-diarization.md`.
- At most 8 speakers (model limit). Extra voices are merged into existing ones.
- Without headphones the microphone re-captures the remote side; there is no echo cancellation yet. Headphones avoid it.
- Diarizer preset `low` (1 s latency, NVIDIA's reference streaming profile). Override with the `MEETAI_DIAR_PRESET` environment variable (`fast32`, `fast128`, `verylow`, `ultra`…).
- The streaming diarizer needs ~0.5–1 s to "discover" a new speaker, so someone's very first word can stick to the previous speaker. That is why, when you press Stop, KatchApp runs a second offline diarization pass over the whole recording (Nemotron 3 offline preset, best accuracy) and re-attributes every word while keeping the live labels and names. It takes about a second per minute of audio; turn it off in Settings > Meetings if you prefer an instant stop.
- First launch: downloads ~700 MB and compiles the models for the Neural Engine (1–2 min). Later launches take well under a second thanks to the CoreML cache.
- Diagnostic log: `~/Library/Logs/KatchApp/app.log`.
- The voice-suggestion threshold (`ContactStore.suggestThreshold`, 0.70) was calibrated with synthetic voices; real voices may warrant a lower value. Very similar TTS voices can be merged by the diarizer.
- Per-app capture and meeting detection were verified against Core Audio's process list, not yet against a live call on every platform.

## License

MIT. See `LICENSE`. Model licences are listed in the About window.
