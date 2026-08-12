import SwiftUI

struct GlossaryEditorView: View {
    @State private var text: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("术语表")
                        .font(.headline)
                    Text("每行一个术语，识别时优先识别这些词，保存后立即生效")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(nonEmptyCount) 个术语")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .frame(minWidth: 400, minHeight: 360)

            HStack(spacing: 12) {
                Spacer()
                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 460)
        .onAppear {
            text = AppState.shared.glossaryText
        }
    }

    private var nonEmptyCount: Int {
        text.components(separatedBy: .newlines)
            .count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func save() {
        AppState.shared.saveGlossary(text)
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { saved = false }
        }
    }
}
