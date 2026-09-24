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

// MARK: - Action card (tappable, for the empty state)

/// A full-width tappable card: icon, title, subtitle and a chevron. Used on the
/// landing screen so the ways to start don't crowd into a row of buttons that
/// wrap onto two lines on narrow phones.
struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
    }
}

// MARK: - Inline notes editor (scroll-friendly)

/// A notes field that stays cheap while it sits in a scrolling list. On iOS it
/// shows plain text and only mounts a live `TextEditor` once tapped, so a list
/// of stages or references isn't stacking dozens of `UITextView`s at once (the
/// classic cause of scroll stutter). On macOS it's always an editor — there's
/// no such cost there and click-to-type is expected.
struct InlineNotesEditor: View {
    @Binding var text: String
    var placeholder: String = "Add notes…"
    var minHeight: CGFloat = 70
    var maxHeight: CGFloat = 180
    /// Called on each edit (wire this to a debounced save).
    var onEdit: (() -> Void)? = nil
    /// Called when editing ends on iOS (wire this to an immediate save).
    var onCommit: (() -> Void)? = nil

    #if os(iOS)
    @State private var editing = false
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        content
            .padding(6)
            .background(Color.appTextBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if editing {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .onChange(of: text) { onEdit?() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused {
                        editing = false
                        onCommit?()
                    }
                }
        } else {
            Button {
                editing = true
                // The editor has to exist before focus can move to it.
                DispatchQueue.main.async { focused = true }
            } label: {
                Text(text.isEmpty ? placeholder : text)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .lineLimit(12)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #else
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
                .onChange(of: text) { onEdit?() }
        }
        #endif
    }
}
