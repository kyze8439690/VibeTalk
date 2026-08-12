import Foundation

final class ModelManager {

    static let modelFileName = "ggml-medium-q8_0.bin"
    static let modelURLString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q8_0.bin"

    var modelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VibeTalk").appendingPathComponent(Self.modelFileName)
    }

    var isModelReady: Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? Int else {
            return false
        }
        return size > 700_000_000
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
