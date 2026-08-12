import Foundation

final class ModelManager {

    static let modelFileName = "ggml-medium-q8_0.bin"
    static let modelURLString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q8_0.bin"
    static let glossaryFileName = "glossary.txt"

    static let defaultGlossary: [String] = [
        "git commit", "push", "pull", "merge", "rebase", "branch", "stash", "PR", "CI",
        "API", "response", "null", "button", "onClick", "ViewModel", "Kotlin", "Swift",
        "logcat", "profile", "debug", "bug", "race condition", "重构", "函数", "掉帧", "耗时",
    ]

    var modelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VibeTalk").appendingPathComponent(Self.modelFileName)
    }

    var glossaryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VibeTalk").appendingPathComponent(Self.glossaryFileName)
    }

    var isModelReady: Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? Int else {
            return false
        }
        return size > 700_000_000
    }

    /// 读取术语表；文件不存在时写入默认术语并返回默认值
    func loadGlossary() -> [String] {
        let url = glossaryURL
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            let terms = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !terms.isEmpty {
                return terms
            }
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.defaultGlossary.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return Self.defaultGlossary
    }

    func saveGlossary(_ terms: [String]) {
        try? FileManager.default.createDirectory(at: glossaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? terms.joined(separator: "\n").write(to: glossaryURL, atomically: true, encoding: .utf8)
        Log.write("Glossary: 已保存 \(terms.count) 个术语")
    }

    /// 构建识别用 initial prompt：固定引导语 + 用户术语表
    func buildPrompt(glossary: [String]) -> String {
        "以下是简体中文和英文混合的编程技术内容，一律使用简体中文。常用术语：" +
        glossary.joined(separator: "、") + "。"
    }

    func download(progress: @escaping (Float) -> Void) async throws {
        let target = modelURL
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(Self.modelFileName + ".tmp")

        let url = URL(string: Self.modelURLString)!
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ModelManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            ])
        }

        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        var downloaded: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    progress(Float(downloaded) / Float(total))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }
        try handle.close()
        if total > 0 {
            progress(1.0)
        }

        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
