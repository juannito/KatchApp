import SwiftUI

/// Minutes panel for a saved session.
struct SummaryView: View {
    @EnvironmentObject var service: SummaryService
    @EnvironmentObject var settings: SummarySettings
    @EnvironmentObject var contacts: ContactStore
    let folder: URL
    @State private var summary: MeetingSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if service.isRunning(folder) {
                        ProgressView().controlSize(.small)
                        Text(L("Generating summary…")).foregroundStyle(.secondary)
                    } else {
                        Button(summary == nil ? L("Generate summary") : L("Regenerate")) { generate() }
                            .disabled(!settings.isConfigured)
                        if let summary {
                            Button(L("Copy summary")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(summary.markdown(), forType: .string)
                            }
                        }
                    }
                    Spacer()
                    if let summary {
                        Text("\(summary.provider) · \(summary.model)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let err = service.error(for: folder) {
                    Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if !settings.isConfigured {
                    Text(L("Summary provider is not configured. Open Settings > Summary.")).foregroundStyle(.secondary)
                }
                if let s = summary {
                    section(L("Summary")) { Text(s.summary).textSelection(.enabled) }
                    section(L("Decisions")) { bullets(s.decisions) }
                    section(L("Action items")) {
                        if s.actionItems.isEmpty {
                            Text(L("Nothing to report.")).foregroundStyle(.secondary)
                        } else {
                            ForEach(s.actionItems) { a in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.square").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.task).textSelection(.enabled)
                                        HStack(spacing: 10) {
                                            if let o = a.owner, !o.isEmpty { Label(o, systemImage: "person") }
                                            if let d = a.due, !d.isEmpty { Label(d, systemImage: "calendar") }
                                        }
                                        .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    section(L("Follow-ups")) { bullets(s.followUps) }
                } else if !service.isRunning(folder) {
                    Text(L("No summary yet.")).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { summary = SummaryService.read(at: folder) }
        .onChange(of: service.version) { _, _ in summary = SummaryService.read(at: folder) }
    }

    private func generate() {
        let names = Dictionary(uniqueKeysWithValues: contacts.contacts.map { ($0.id, $0.name) })
        service.generate(folder: folder, contactNames: names)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func bullets(_ items: [String]) -> some View {
        if items.isEmpty {
            Text(L("Nothing to report.")).foregroundStyle(.secondary)
        } else {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item).textSelection(.enabled)
                }
            }
        }
    }
}
