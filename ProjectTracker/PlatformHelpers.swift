import SwiftUI

// MARK: - Cross-platform semantic colors

extension Color {
    /// Main window/screen background.
    static var appWindowBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }

    /// Secondary surface used for cards and header areas.
    static var appControlBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// Background for text input areas (TextEditor, notes box).
    static var appTextBackground: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.tertiarySystemBackground)
        #endif
    }
}

// MARK: - Cross-platform label fonts
// iOS gets rounded, easier-to-read labels; macOS keeps the terminal-mono look.

extension Font {
    /// Section / status labels ("ALL STAGES", "NOTES", status words).
    static var appLabel: Font {
        #if os(iOS)
        .system(.caption, design: .rounded).weight(.semibold)
        #else
        .caption.monospaced()
        #endif
    }

    /// Emphasised label variant.
    static var appLabelBold: Font {
        #if os(iOS)
        .system(.caption, design: .rounded).weight(.bold)
        #else
        .caption.monospaced().bold()
        #endif
    }

    /// Small secondary metadata (due dates, targets, weights).
    static var appMeta: Font {
        #if os(iOS)
        .system(.caption2, design: .rounded)
        #else
        .caption.monospaced()
        #endif
    }
}

// MARK: - Cross-platform toggle style

#if os(iOS)
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                    .font(.body)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
#endif

extension View {
    /// Checkbox style on macOS and iOS; avoids the large UISwitch on iPhone.
    @ViewBuilder func checkboxToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self.toggleStyle(CheckboxToggleStyle())
        #endif
    }

    /// One "Done" button above the iOS keyboard that dismisses it.
    /// Attach exactly once per presented hierarchy (tab root or sheet root) —
    /// SwiftUI merges every keyboard toolbar in scope, so attaching per-field
    /// shows duplicate buttons. No-op on macOS.
    @ViewBuilder func keyboardDismissToolbar() -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
        #else
        self
        #endif
    }
}
