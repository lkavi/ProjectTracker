import SwiftUI

/// Paste a deadline table or list, see how many stages were found, then tidy
/// the draft in the stage editor before it replaces the current stages.
struct PasteDeadlinesView: View {
    let onSave: ([ProjectStage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var stages: [ProjectStage] = []
    @State private var reviewing = false

    private var result: DeadlineListParser.Result { DeadlineListParser.parse(text) }

    private let example = """
    Literature review – 17 Oct 2026 – 15%
    Methodology chapter – 21 Nov 2026
    • Choose methods
    • Ethics form
    Final report – 15 Apr 2027 – 70%
    """

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the deadline table or list from your handbook. Every line with a date becomes a stage; bullet points under a line become its tasks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(example)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .accessibilityIdentifier("deadline-list-field")
                }
                .frame(minHeight: 220)
                .background(Color.appTextBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1))

                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(result.stages.isEmpty ? .secondary : .primary)
                    .accessibilityIdentifier("deadline-list-summary")
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Paste a Deadline List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review Stages") {
                        stages = result.stages
                        reviewing = true
                    }
                    .disabled(result.stages.isEmpty)
                    .accessibilityIdentifier("review-stages-button")
                }
            }
            .navigationDestination(isPresented: $reviewing) {
                StageListEditor(stages: $stages)
                    .navigationTitle("Review Stages")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                onSave(StageListEditor.cleaned(stages))
                                dismiss()
                            }
                            .disabled(!StageListEditor.isValid(stages))
                            .accessibilityIdentifier("save-stages-button")
                        }
                    }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
    }

    private var summary: String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Nothing pasted yet."
        }
        let r = result
        var parts = [r.stages.isEmpty ? "No lines with a date found."
                                      : "Found \(r.stages.count) stage\(r.stages.count == 1 ? "" : "s") with dates."]
        if r.skippedLines > 0 {
            parts.append("\(r.skippedLines) line\(r.skippedLines == 1 ? "" : "s") without a date skipped.")
        }
        if !r.stages.isEmpty { parts.append("This replaces the current stages; you can tidy them first.") }
        return parts.joined(separator: " ")
    }
}

#Preview {
    PasteDeadlinesView { _ in }
}
