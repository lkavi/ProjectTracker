import SwiftUI

/// Shown right after a project is created: explains how to turn the generic
/// template into a personalized one by handing the exported JSON to an AI
/// assistant along with the user's own dates, guidelines, and idea.
struct PersonalizeGuideView: View {
    let projectName: String
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("square.and.arrow.up",
         "Export this project",
         "Tap “Export JSON” below (also in the Projects menu → “Export for AI…”) and save the file somewhere handy."),
        ("bubble.left.and.text.bubble.right",
         "Open ChatGPT or Claude",
         "Start a new chat in any capable AI assistant — ChatGPT, Claude, or similar."),
        ("paperclip",
         "Upload the JSON file",
         "Attach the file you just exported so the assistant can read the template."),
        ("text.append",
         "Describe your project",
         "Give it your real stages or milestones and their deadlines, how each is weighted (if graded), any guidelines you must follow, and what your project is about. Ask it to break these down and personalize the template."),
        ("square.and.arrow.down",
         "Import the result",
         "Save the JSON the assistant returns, then come back and use Projects menu → “Import Project JSON…”. Your ticked-off progress is always preserved."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Personalize “\(projectName)”")
                    .font(.title2.bold())
                Text("Your new project starts from a generic template with placeholder dates. Tailor it to your own project in a few minutes:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Label(step.title, systemImage: step.icon)
                                    .font(.headline)
                                    .labelStyle(.titleAndIcon)
                                Text(step.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text("Prefer to skip? You can edit stages and tasks any time, or tailor the template later — the Projects menu always has Export and Import.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Maybe Later") { dismiss() }
                Spacer()
                Button {
                    onExport()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(width: 520, height: 620)
        #endif
    }
}

#Preview {
    PersonalizeGuideView(projectName: "My Research Project", onExport: {})
}
