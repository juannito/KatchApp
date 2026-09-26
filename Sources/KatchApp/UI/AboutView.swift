import AppKit
import SwiftUI

/// About page in the Handy style: one row per fact, then acknowledgments.
struct AboutView: View {
    @EnvironmentObject var language: AppLanguage
    @EnvironmentObject var theme: AppTheme
    @EnvironmentObject var store: SessionStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.name).font(.title2.weight(.semibold))
                        Text(L("Local meeting recorder: press one button and get a live transcript with speaker separation. Everything runs on your Mac — no audio or text ever leaves it."))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section(L("About")) {
                Picker(L("Application language"), selection: $language.code) {
                    ForEach(AppLanguage.supported, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker(L("Application theme"), selection: $theme.mode) {
                    ForEach(AppTheme.Mode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(L("Version")) { Text("v\(AppInfo.version)").font(.body.monospaced()) }
                LabeledContent(L("Created by")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Link(AppInfo.author, destination: AppInfo.authorURL)
                        Text(language.code == "es" ? AppInfo.bioES : AppInfo.bioEN)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 380, alignment: .trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent(L("Support development")) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Link(destination: AppInfo.coffeeURL) { Label(L("Buy me a coffee"), systemImage: "cup.and.saucer") }
                            .buttonStyle(.borderedProminent)
                        Text(L("It helps me keep making things like this.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("Source code")) {
                    Link(L("View on GitHub"), destination: AppInfo.repositoryURL).buttonStyle(.bordered)
                    Text(L("MIT license")).font(.caption).foregroundStyle(.secondary)
                }
                directoryRow(L("Sessions folder"), url: store.rootURL)
                directoryRow(L("Log folder"), url: AppLog.url.deletingLastPathComponent())
            }
            Section(L("Acknowledgments")) {
                ForEach(AppInfo.credits) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Link(c.name, destination: c.url).font(.body.weight(.medium))
                            Spacer()
                            Text(c.license).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        }
                        Text(c.role).font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func directoryRow(_ title: String, url: URL) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(url.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button(L("Open")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}
