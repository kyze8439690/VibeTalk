import Foundation

enum WavReader {

    static func readFloatMono16k(path: String) -> [Float]? {
        guard let data = FileManager.default.contents(atPath: path), data.count > 44 else { return nil }

        let riff = String(decoding: data[0..<4], as: UTF8.self)
        guard riff == "RIFF" else { return nil }

        var offset = 12
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var pcmData: Data?

        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let chunkSize = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)
            }
            let contentStart = offset + 8
            guard contentStart + Int(chunkSize) <= data.count else { break }

            if chunkID == "fmt " {
                channels = data.withUnsafeBytes { ptr in
                    ptr.loadUnaligned(fromByteOffset: contentStart + 2, as: UInt16.self)
                }
                sampleRate = data.withUnsafeBytes { ptr in
                    ptr.loadUnaligned(fromByteOffset: contentStart + 4, as: UInt32.self)
                }
                bitsPerSample = data.withUnsafeBytes { ptr in
                    ptr.loadUnaligned(fromByteOffset: contentStart + 14, as: UInt16.self)
                }
            } else if chunkID == "data" {
                pcmData = data.subdata(in: contentStart..<(contentStart + Int(chunkSize)))
            }
            offset = contentStart + Int(chunkSize) + (Int(chunkSize) % 2)
        }

        guard let pcm = pcmData, channels == 1, sampleRate == 16000, bitsPerSample == 16 else {
            return nil
        }

        let count = pcm.count / 2
        var result = [Float](repeating: 0, count: count)
        pcm.withUnsafeBytes { ptr in
            for i in 0..<count {
                let sample = ptr.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)
                result[i] = Float(sample) / 32768.0
            }
        }
        return result
    }
}
