import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            MeetingsSettingsView()
                .tabItem { Label(L("Meetings"), systemImage: "video") }
            SummarySettingsView()
                .tabItem { Label(L("Summary"), systemImage: "text.badge.checkmark") }
        }
        .frame(width: 620)
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
    @State private var apps: [MeetingApp] = []
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section(L("Capture")) {
                Picker(L("System audio"), selection: $registry.captureMode) {
                    ForEach(CaptureMode.allCases) { m in Text(m.title).tag(m) }
                }
                .pickerStyle(.radioGroup)
                Text(L("With “only the meeting app”, MeetAI records just the audio of the meeting app it finds when you press Record (Zoom, Teams, your browser…). If none is running it records everything."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Meeting detection")) {
                Toggle(L("Ask to record when a meeting app starts using the microphone"), isOn: $registry.autoDetect)
                Toggle(L("Open MeetAI at login"), isOn: Binding(get: { launchAtLogin }, set: { registry.launchAtLogin = $0; launchAtLogin = registry.launchAtLogin }))
                Text(L("Detection only works while MeetAI is open. Opening it at login keeps it ready for every meeting."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Meeting apps")) {
                Text(L("Apps in this list are tagged as the meeting platform, captured on their own and watched for calls. Rename any app, or mark an app you use for meetings."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(apps) { app in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { app.isMeetingApp }, set: { registry.setMeetingApp(app.bundleID, $0); reload() }))
                            .labelsHidden()
                        TextField(app.bundleID, text: Binding(get: { app.name }, set: { registry.rename(app.bundleID, to: $0) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .onSubmit(reload)
                        Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if app.isRunning {
                            Label(L("running"), systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
                        }
                    }
                }
                Button(L("Refresh")) { reload() }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear {
            reload()
            launchAtLogin = registry.launchAtLogin
        }
    }

    private func reload() { apps = registry.allApps() }
}
