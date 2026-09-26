import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var language: AppLanguage

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
            Section(L("Diagnostics")) {
                LabeledContent(L("Log")) {
                    Button(L("Open app.log")) { store.reveal(AppLog.url) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}
