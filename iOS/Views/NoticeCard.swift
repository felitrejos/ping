import SwiftUI

/// Inline tinted card used for status messages (errors, location prompts, calendar prompts).
/// Lives outside `ContentView` so the same component can be reused by future screens without
/// creating an internal dependency on the home view's file.
///
/// Both `title` and `message` are treated as `LocalizedStringKey` lookups. Literal callsites get
/// translated automatically; runtime strings (e.g. a system error description) fall through
/// SwiftUI's key-miss path and render verbatim.
struct NoticeCard: View {
    let title: String
    let message: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(.headline)
                if let message, !message.isEmpty {
                    Text(LocalizedStringKey(message))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
