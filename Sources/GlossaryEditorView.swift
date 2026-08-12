import SwiftUI

struct GlossaryEditorView: View {
    @State private var text: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每行一个术语，保存后立即生效")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 380, minHeight: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.4))
                )
            HStack {
                if saved {
                    Text("已保存")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
                Button("保存") {
                    AppState.shared.saveGlossary(text)
                    saved = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        await MainActor.run { saved = false }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .onAppear {
            text = AppState.shared.glossaryText
        }
    }
}
