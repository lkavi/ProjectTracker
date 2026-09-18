import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Cross-platform semantic colors

extension Color {
    /// Main window/screen background.
    static var appWindowBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemGroupedBackground)
        #endif
    }

    /// Secondary surface used for cards and header areas.
    static var appControlBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemGroupedBackground)
        #endif
    }

    /// Background for text input areas (TextEditor, notes box).
    static var appTextBackground: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.tertiarySystemGroupedBackground)
        #endif
    }
}

// MARK: - Typography (system text styles on both platforms)

extension Font {
    /// Section / status labels.
    static var appLabel: Font { .footnote.weight(.semibold) }
    /// Emphasised label variant.
    static var appLabelBold: Font { .footnote.bold() }
    /// Small secondary metadata (due dates, targets, weights).
    static var appMeta: Font { .caption }
}

// MARK: - Cross-platform toggle style

#if os(iOS)
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                    .font(.title3)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
#endif

extension View {
    /// Native checkbox on macOS; a circular check on iOS instead of the large switch.
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

// MARK: - Clipboard

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static var text: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
