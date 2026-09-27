import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            MeetingsSettingsView()
                .tabItem { Label(L("Meetings"), systemImage: "video") }
            ModelsSettingsView()
                .tabItem { Label(L("Models"), systemImage: "cpu") }
            SummarySettingsView()
                .tabItem { Label(L("Summary"), systemImage: "text.badge.checkmark") }
            AboutView()
                .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .frame(width: 640)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var language: AppLanguage
    @State private var newProjectName = ""

    private func createProject() {
        if store.createProject(newProjectName) != nil { newProjectName = "" }
    }

    var body: some View {
        Form {
            Section(L("General")) {
                Picker(L("Language"), selection: $language.code) {
                    ForEach(AppLanguage.supported, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
            }
            Section(L("Sessions")) {
                LabeledContent(L("Folder")) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(store.rootURL.path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 360, alignment: .trailing)
                        HStack {
                            Button(L("Choose folder…")) { store.chooseRootFolder() }
                            Button(L("Open in Finder")) { store.reveal(store.rootURL) }
                            Button(L("Reset")) { store.resetRoot() }
                                .disabled(store.rootURL == SessionStore.defaultRoot())
                        }
                    }
                }
                Text(L("Each meeting is saved in its own subfolder with transcript.md, transcript.json and audio.wav. Changing the folder does not move existing sessions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Projects")) {
                HStack {
                    TextField(L("Project name"), text: $newProjectName)
                        .onSubmit(createProject)
                    Button(L("New project"), action: createProject)
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if store.projects.isEmpty {
                    Text(L("No projects yet. Create one from the save dialog."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.projects, id: \.self) { p in
                    Toggle(isOn: Binding(get: { store.isHidden(p) }, set: { store.setHidden(p, $0) })) {
                        HStack {
                            Text(p)
                            if store.isHidden(p) {
                                Text(L("Hidden")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }
                Text(L("Hidden projects are left out of the sidebar and history until you enable “Show hidden projects” (handy when sharing your screen). The setting resets on every launch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("Diagnostics")) {
                LabeledContent(L("Log")) {
                    Button(L("Open app.log")) { store.reveal(AppLog.url) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct SummarySettingsView: View {
    @EnvironmentObject var settings: SummarySettings

    var body: some View {
        Form {
            Section(L("Summary")) {
                Picker(L("Provider"), selection: $settings.provider) {
                    ForEach(SummaryProvider.allCases) { p in Text(p.title).tag(p) }
                }
                Toggle(L("Generate a summary automatically when a meeting is saved"), isOn: $settings.autoSummary)
                    .disabled(settings.provider == .none)
            }
            switch settings.provider {
            case .none:
                EmptyView()
            case .ollama:
                Section("Ollama") {
                    TextField(L("Server URL"), text: $settings.ollamaURL)
                    TextField(L("Model"), text: $settings.ollamaModel)
                    OllamaModelStatusView()
                    Text(L("Ollama runs models on your Mac. Install it from ollama.com and pull a model, e.g. `ollama pull qwen3:8b`."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L("Suggested: qwen3:8b (best quality on 16 GB+), qwen3:4b (lighter), llama3.2 (fastest)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .openAI:
                Section("OpenAI-compatible") {
                    TextField(L("Base URL"), text: $settings.openAIBaseURL)
                    TextField(L("Model"), text: $settings.openAIModel)
                    SecureField(L("API key"), text: $settings.openAIKey)
                    Text(L("Works with OpenAI, LM Studio (http://localhost:1234/v1), OpenRouter, vLLM and any compatible server. Keys are stored in the Keychain."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .anthropic:
                Section("Anthropic") {
                    TextField(L("Model"), text: $settings.anthropicModel)
                    SecureField(L("API key"), text: $settings.anthropicKey)
                    Text(L("Keys are stored in the macOS Keychain."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Instructions")) {
                TextEditor(text: $settings.instructions)
                    .font(.body)
                    .frame(minHeight: 140)
                HStack {
                    Text(L("Instructions tell the model what the minutes should contain. The output format (summary, decisions, action items with owner and due date, follow-ups) is fixed."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Reset to default")) { settings.resetInstructions() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}


/// Shows whether the configured Ollama model is installed and offers to download it.
struct OllamaModelStatusView: View {
    @EnvironmentObject var settings: SummarySettings
    @State private var installed: [String]? = nil
    @State private var unreachable = false
    @State private var downloading = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var error: String?

    private var model: String { settings.ollamaModel.trimmingCharacters(in: .whitespaces) }
    private var isInstalled: Bool {
        guard let installed else { return false }
        return installed.contains(model) || installed.contains(model + ":latest")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if unreachable {
                    Label(L("Ollama is not running or unreachable at this URL."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if installed == nil {
                    ProgressView().controlSize(.small)
                } else if downloading {
                    ProgressView(value: progress).frame(width: 160)
                    Text(L("Downloading %@… %d%%", model, Int(progress * 100))).font(.callout)
                } else if isInstalled {
                    Label(L("Model “%@” is installed.", model), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if !model.isEmpty {
                    Label(L("Model “%@” is not installed.", model), systemImage: "arrow.down.circle").foregroundStyle(.secondary)
                    Button(L("Download")) { download() }
                }
                Spacer()
                Button(L("Refresh")) { refresh() }.disabled(downloading)
            }
            if let error {
                Text(L("Download failed: %@", error)).font(.caption).foregroundStyle(.red)
            }
            if let installed, !installed.isEmpty {
                Picker(L("Installed models"), selection: $settings.ollamaModel) {
                    if !isInstalled { Text(model).tag(model) }
                    ForEach(installed, id: \.self) { m in Text(m).tag(m) }
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: settings.ollamaURL) { _, _ in refresh() }
    }

    private func refresh() {
        let client = OllamaClient(baseURL: settings.ollamaURL)
        Task {
            do {
                let list = try await client.installedModels()
                installed = list
                unreachable = false
            } catch {
                installed = []
                unreachable = true
            }
        }
    }

    private func download() {
        let client = OllamaClient(baseURL: settings.ollamaURL)
        let name = model
        downloading = true
        progress = 0
        error = nil
        Task {
            do {
                try await client.pull(model: name) { p, s in
                    Task { @MainActor in
                        progress = p
                        status = s
                    }
                }
                AppLog.write("ollama pulled \(name)")
            } catch {
                self.error = error.localizedDescription
                AppLog.write("ollama pull failed \(name): \(error)")
            }
            downloading = false
            refresh()
        }
    }
}


struct MeetingsSettingsView: View {
    @EnvironmentObject var registry: MeetingAppRegistry
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section(L("Capture")) {
                Toggle(L("Capture system audio (Zoom, Meet, Teams, browser…)"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: RecordingSession.systemAudioDefaultsKey) as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: RecordingSession.systemAudioDefaultsKey) }))
                Picker(L("System audio"), selection: $registry.captureMode) {
                    ForEach(CaptureMode.allCases) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.radioGroup)
                Text(L("With “only the meeting app”, KatchApp records just the audio of the meeting app it finds when you press Record (Zoom, Teams, your browser…). If none is running it records everything."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Speakers")) {
                Toggle(L("Refine speakers when the recording stops"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: RecordingSession.refineDefaultsKey) as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: RecordingSession.refineDefaultsKey) }))
                Text(L("Runs a second, more accurate diarization pass over the whole recording and re-assigns each word. Takes a few seconds after you press Stop; the first time it downloads an extra model (~200 MB)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Meeting detection")) {
                Toggle(L("Ask to record when a meeting app starts using the microphone"), isOn: $registry.autoDetect)
                Toggle(L("Open KatchApp at login"), isOn: Binding(get: { launchAtLogin }, set: { registry.launchAtLogin = $0; launchAtLogin = registry.launchAtLogin }))
                Text(L("Detection only works while KatchApp is open. Opening it at login keeps it ready for every meeting."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { launchAtLogin = registry.launchAtLogin }
    }
}


/// Speech-recognition model picker. Switching reloads the models (download on first use).
struct ModelsSettingsView: View {
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var session: RecordingSession
    @State private var selected: AsrModelChoice = .current
    @State private var downloaded: Set<AsrModelChoice> = []
    @State private var sizes: [AsrModelChoice: Int64] = [:]
    @State private var confirmDelete: AsrModelChoice?

    private var busy: Bool {
        if case .loading = modelStore.state { return true }
        return session.status != .idle
    }

    var body: some View {
        Form {
            Section(L("Speech recognition")) {
                ForEach(AsrModelChoice.offered) { m in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected == m ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected == m ? Color.accentColor : Color.secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(m.title).fontWeight(.medium)
                                if modelStore.models?.asrChoice == m {
                                    Text(L("Active")).font(.caption).foregroundStyle(.green)
                                }
                                if downloaded.contains(m) {
                                    Text(L("Downloaded · %@", ByteCountFormatter.string(fromByteCount: sizes[m] ?? 0, countStyle: .file)))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(L("~%d MB download", m.sizeMB)).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Text(m.summary).font(.callout).foregroundStyle(.secondary)
                            Text(m.languages).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if downloaded.contains(m), modelStore.models?.asrChoice != m {
                            Button { confirmDelete = m } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help(L("Delete the downloaded files"))
                        }
                        Link(destination: m.repoURL) { Image(systemName: "arrow.up.right.square") }
                            .help(L("Model card"))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !busy { select(m) } }
                    .padding(.vertical, 4)
                }
                if case .loading(let step, let fraction) = modelStore.state {
                    HStack(spacing: 8) {
                        ProgressView(value: fraction).frame(width: 160)
                        Text(L(step)).font(.callout).foregroundStyle(.secondary)
                    }
                } else if session.status != .idle {
                    Text(L("Finish the current recording before switching models.")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Every model runs on the Neural Engine and gives word timestamps, which speaker separation and playback need. Whisper and Canary are not offered: they return text without per-word timing. Models are stored in ~/Library/Application Support/FluidAudio/Models."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Also loaded")) {
                LabeledContent("Nemotron 3 Diarization") { Text(L("Speaker separation, up to 8 voices")).foregroundStyle(.secondary) }
                LabeledContent("Silero VAD") { Text(L("Voice activity detection")).foregroundStyle(.secondary) }
                LabeledContent("CAM++") { Text(L("Voice fingerprints for contacts")).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear(perform: refresh)
        .onReceive(modelStore.$state) { _ in refresh() }
        .alert(L("Delete the downloaded files for %@?", confirmDelete?.title ?? ""), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("Delete"), role: .destructive) {
                if let m = confirmDelete { try? m.deleteDownload() }
                confirmDelete = nil
                refresh()
            }
            Button(L("Cancel"), role: .cancel) { confirmDelete = nil }
        } message: {
            Text(L("They will be downloaded again if you select this model later."))
        }
    }

    private func select(_ m: AsrModelChoice) {
        guard m != selected || modelStore.models?.asrChoice != m else { return }
        selected = m
        AsrModelChoice.current = m
        AppLog.write("asr model selected: \(m.rawValue)")
        Task { await modelStore.reload() }
    }

    private func refresh() {
        selected = .current
        Task.detached {
            let found = AsrModelChoice.allCases.filter { $0.isDownloaded }
            let d = Set(found)
            let s = Dictionary(uniqueKeysWithValues: found.map { ($0, $0.downloadedSize) })
            await MainActor.run {
                downloaded = d
                sizes = s
            }
        }
    }
}
