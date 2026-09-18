import SwiftUI

/// Coloured dot plus wording, e.g. "● In progress".
struct StatusBadge: View {
    let status: StageStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(status == .queued ? .secondary : status.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A quiet capsule tag such as "Due in 2 days" or "Target 17 Sep".
struct TagCapsule: View {
    let text: String
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(.caption.weight(tint == nil ? .regular : .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14))
            .foregroundStyle(tint ?? Color.secondary)
            .clipShape(Capsule())
    }
}

/// Section heading in the standard system style.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The card surface used throughout: neutral background, soft corners.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
