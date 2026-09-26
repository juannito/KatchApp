import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(AppInfo.name).font(.title.weight(.semibold))
            Text(L("Version %@", AppInfo.version)).foregroundStyle(.secondary)
            Text(L("Created by %@", AppInfo.author))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Local meeting recorder: press one button and get a live transcript with speaker separation. Everything runs on your Mac — no audio or text ever leaves it."))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            HStack(spacing: 12) {
                Text(L("Open source under the MIT license.")).foregroundStyle(.secondary)
                Link(L("Source code"), destination: AppInfo.repositoryURL)
                Link(L("Buy me a coffee ☕"), destination: AppInfo.coffeeURL)
            }
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Built with")).font(.headline)
                ForEach(AppInfo.credits) { c in
                    HStack(alignment: .firstTextBaseline) {
                        Link(c.name, destination: c.url).frame(width: 230, alignment: .leading)
                        Text(c.role).foregroundStyle(.secondary)
                        Spacer()
                        Text(c.license).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 560)
    }
}
