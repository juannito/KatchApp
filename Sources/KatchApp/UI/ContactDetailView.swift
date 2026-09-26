import SwiftUI

struct ContactDetailView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    let contact: Contact
    @Binding var selection: SidebarSelection?
    @State private var name = ""
    @State private var confirmDelete = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return f
    }()

    private var current: Contact { contacts.contact(contact.id) ?? contact }
    private var sessions: [SessionSummary] { store.sessions(withContact: contact.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                Button { contacts.chooseAvatar(for: contact.id) } label: {
                    AvatarView(contact: current, size: 96)
                }
                .buttonStyle(.plain)
                .help(L("Change photo…"))
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L("Name"), text: $name)
                        .font(.title.weight(.semibold))
                        .textFieldStyle(.plain)
                        .onSubmit { contacts.rename(contact.id, to: name) }
                    Text(L("Voice samples: %d", current.embeddings.count))
                        .foregroundStyle(.secondary)
                    Toggle(L("This is me"), isOn: Binding(get: { current.isMe }, set: { contacts.setMe(contact.id, $0) }))
                        .toggleStyle(.switch)
                    HStack {
                        Button(L("Change photo…")) { contacts.chooseAvatar(for: contact.id) }
                        Button(L("Delete contact"), role: .destructive) { confirmDelete = true }
                    }
                }
                Spacer()
            }
            Divider()
            Text(L("Conversations")).font(.headline)
            if sessions.isEmpty {
                Text(L("No conversations with this contact yet.")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessions) { s in
                            Button {
                                selection = .session(s.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title)
                                        Text("\(Self.dateFormatter.string(from: s.startedAt)) · \(TimeFormat.clock(s.duration))\(s.project.map { " · \($0)" } ?? "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { name = current.name }
        .alert(L("Delete contact “%@”?", current.name), isPresented: $confirmDelete) {
            Button(L("Delete"), role: .destructive) {
                contacts.delete(contact.id)
                selection = .live
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Sessions keep their transcripts; only the contact, its photo and voice samples are removed."))
        }
    }
}
