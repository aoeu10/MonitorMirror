import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 68))
                    .foregroundStyle(.blue.gradient)

                VStack(spacing: 8) {
                    Text("Monitor Mirror")
                        .font(.largeTitle.bold())
                    Text("Correct and privately share an angled monitor view between two nearby Apple devices.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 14) {
                    NavigationLink {
                        ViewerView()
                    } label: {
                        RoleCard(
                            title: "View Monitor",
                            subtitle: "Use this on the iPad. It creates the private pairing code.",
                            systemImage: "ipad.landscape"
                        )
                    }

                    NavigationLink {
                        SenderView()
                    } label: {
                        RoleCard(
                            title: "Share Monitor",
                            subtitle: "Use this on the iPhone mounted beside the monitor.",
                            systemImage: "iphone.gen3.camera"
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 620)

                Spacer()

                Label("No cloud, accounts, recordings, or analytics", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Monitor Mirror")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RoleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
