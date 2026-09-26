import Foundation

/// One-time migration from the app's previous name (MeetAI, bundle com.juannito.meetai).
enum Migration {
    private static let flag = "migratedFromMeetAI"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)

        // Settings (language, sessions folder, summary provider, meeting apps…).
        if let old = UserDefaults(suiteName: "com.juannito.meetai") {
            for (key, value) in old.dictionaryRepresentation()
            where !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple") && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // Sessions folder: ~/Documents/MeetAI -> ~/Documents/KatchApp (only when the user never chose a custom one).
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldRoot = docs.appendingPathComponent("MeetAI", isDirectory: true)
        let newRoot = docs.appendingPathComponent("KatchApp", isDirectory: true)
        if (defaults.string(forKey: SessionStore.rootDefaultsKey) ?? "").isEmpty,
            fm.fileExists(atPath: oldRoot.path), !fm.fileExists(atPath: newRoot.path)
        {
            do {
                try fm.moveItem(at: oldRoot, to: newRoot)
                AppLog.write("migrated sessions folder to \(newRoot.path)")
            } catch {
                AppLog.write("could not move sessions folder: \(error); using the old one")
                defaults.set(oldRoot.path, forKey: SessionStore.rootDefaultsKey)
            }
        }

        // API keys stored under the old Keychain service name.
        for account in ["openai", "anthropic"] where Keychain.get(account: account) == nil {
            if let value = Keychain.get(account: account, service: "MeetAI") { Keychain.set(value, account: account) }
        }
        AppLog.write("migration from MeetAI done")
    }
}
