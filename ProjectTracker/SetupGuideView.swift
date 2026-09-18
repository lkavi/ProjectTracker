import SwiftUI

/// Shown right after a project is created: the three ways to turn the
/// template into the user's real stages.
struct SetupGuideView: View {
    let projectName: String
    let onCopyPrompt: () -> Void
    let onImportClipboard: () -> Void
    let onEditStages: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your stages")
                    .font(.title2.bold())
                Text("“\(projectName)” starts from a template with placeholder dates. Three ways to make it yours:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    option(
                        number: 1,
                        title: "Let an AI assistant tailor it",
                        detail: "Copy a ready-made prompt, paste it into ChatGPT, Claude or any assistant, and answer its questions about your stages and deadlines. Then copy its reply and import it here."
                    ) {
                        HStack(spacing: 10) {
                            Button {
                                onCopyPrompt()
                                copied = true
                            } label: {
                                Label(copied ? "Prompt Copied" : "Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("copy-prompt-button")
                            Button("Import from Clipboard") {
                                dismiss()
                                onImportClipboard()
                            }
                        }
                    }

                    option(
                        number: 2,
                        title: "Edit the stages yourself",
                        detail: "Add, rename and reorder stages and tasks, and set each deadline and weighting."
                    ) {
                        Button("Edit Stages") {
                            dismiss()
                            onEditStages()
                        }
                        .accessibilityIdentifier("guide-edit-stages-button")
                    }

                    option(
                        number: 3,
                        title: "Import a project file",
                        detail: "Already have a Project Tracker file from a coursemate or an earlier export? Use Project menu → Import File…, or open the file from Files, Mail or Finder."
                    ) {
                        EmptyView()
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Not Now") { dismiss() }
                    .accessibilityIdentifier("guide-not-now-button")
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(width: 540, height: 560)
        #endif
    }

    @ViewBuilder
    private func option<Action: View>(number: Int, title: String, detail: String,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    SetupGuideView(projectName: "MSc Dissertation", onCopyPrompt: {}, onImportClipboard: {}, onEditStages: {})
}
