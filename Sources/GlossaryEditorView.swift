import SwiftUI

struct GlossaryEditorView: View {
    @State private var terms: [String] = []
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("术语表")
                        .font(.headline)
                    Text("识别时作为引导词，优先识别这些术语。可用按钮调整顺序，保存后立即生效")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(nonEmptyCount) 个术语")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(terms.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        VStack(spacing: 2) {
                            Button {
                                move(from: i, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.plain)
                            .disabled(i == 0)
                            Button {
                                move(from: i, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.plain)
                            .disabled(i == terms.count - 1)
                        }
                        TextField("输入术语…", text: $terms[i])
                            .textFieldStyle(.plain)
                        Button {
                            terms.remove(at: i)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 340)

            HStack(spacing: 12) {
                Button {
                    terms.append("")
                } label: {
                    Label("添加术语", systemImage: "plus")
                }
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
        .frame(minWidth: 440, minHeight: 500)
        .onAppear {
            terms = AppState.shared.glossaryText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    private var nonEmptyCount: Int {
        terms.count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard target >= 0, target < terms.count else { return }
        terms.swapAt(index, target)
    }

    private func save() {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        terms = cleaned
        AppState.shared.saveGlossary(cleaned.joined(separator: "\n"))
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { saved = false }
        }
    }
}
