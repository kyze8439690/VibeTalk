import Foundation
import CWhisper

final class WhisperTranscriber {

    private var ctx: OpaquePointer?
    private let modelManager = ModelManager()

    init?(modelPath: String) {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        if let ctx = whisper_init_from_file_with_params(modelPath, cparams) {
            self.ctx = ctx
            return
        }
        cparams.use_gpu = false
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            return nil
        }
        self.ctx = ctx
        Log.write("Whisper: GPU 初始化失败，已回落 CPU")
    }

    deinit {
        close()
    }

    func close() {
        if let ctx {
            whisper_free(ctx)
            self.ctx = nil
        }
    }

    func transcribe(_ samples: [Float], languages: [String] = ["zh", "en"]) -> String {
        guard let ctx, !samples.isEmpty else { return "" }

        let language = detectLanguage(samples, candidates: languages)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = 4
        params.no_timestamps = false
        params.single_segment = false
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true

        var audioCtx = Int32(samples.count / 320 + 128)
        audioCtx = min(1500, max(512, audioCtx))
        params.audio_ctx = audioCtx

        // 日文不注入中文术语 prompt，避免中文引导污染日文解码
        let prompt: String?
        if language == "ja" {
            prompt = nil
        } else {
            prompt = modelManager.buildPrompt(glossary: modelManager.loadGlossary())
        }

        let result: String
        if let prompt {
            result = language.withCString { langPtr in
                prompt.withCString { promptPtr in
                    params.language = langPtr
                    params.initial_prompt = promptPtr
                    return runFull(params, samples: samples)
                }
            }
        } else {
            result = language.withCString { langPtr in
                params.language = langPtr
                params.initial_prompt = nil
                return runFull(params, samples: samples)
            }
        }
        return sanitize(result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func runFull(_ params: whisper_full_params, samples: [Float]) -> String {
        samples.withUnsafeBufferPointer { buffer -> String in
            guard let base = buffer.baseAddress else { return "" }
            let rc = whisper_full(ctx, params, base, Int32(samples.count))
            guard rc == 0 else { return "" }
            var text = ""
            let nSegments = whisper_full_n_segments(ctx)
            for i in 0..<nSegments {
                if let segmentText = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: segmentText)
                }
            }
            return text
        }
    }

    private func sanitize(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v < 32 && v != 10 && v != 9 { return false }
            if v == 0xFF00 || v == 0xFFFE || v == 0xFFFF { return false }
            if v >= 0xFDD0 && v <= 0xFDEF { return false }
            if v & 0xFFFF == 0xFFFE || v & 0xFFFF == 0xFFFF { return false }
            return true
        })
    }

    private func detectLanguage(_ samples: [Float], candidates: [String]) -> String {
        guard let ctx else { return "zh" }
        let rc = samples.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return whisper_pcm_to_mel(ctx, base, Int32(samples.count), 4)
        }
        guard rc == 0 else { return candidates.first ?? "zh" }

        let langCount = Int(whisper_lang_max_id()) + 1
        var probs = [Float](repeating: 0, count: langCount)
        whisper_lang_auto_detect(ctx, 0, 4, &probs)

        var best = candidates.first ?? "zh"
        var bestProb: Float = -1
        for lang in candidates {
            let id = Int(whisper_lang_id(lang))
            guard id >= 0, id < langCount else { continue }
            if probs[id] > bestProb {
                bestProb = probs[id]
                best = lang
            }
        }
        Log.write(String(format: "Whisper: 检测语言=%@ (prob=%.3f, 候选=%@)", best, bestProb, candidates.joined(separator: ",")))
        return best
    }
}
