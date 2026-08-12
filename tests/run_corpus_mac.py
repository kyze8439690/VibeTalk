#!/usr/bin/env python3
"""whisper 转写语料测试（macOS 宿主端，快速调参用）

用法:
    python3 tests/run_corpus_mac.py [--language auto|zh|en] [--prompt "..."] [--threads 8]
"""
import argparse
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WHISPER_CLI = ROOT / "build-mac/bin/whisper-cli"
MODEL = Path.home() / ".cache/vibetalk/ggml-base-q8_0.bin"
CORPUS_DIR = ROOT / "tests/corpus"

DEFAULT_PROMPT = "以下是普通话和英文混合的内容。"


def normalize(s: str) -> str:
    s = s.lower()
    return "".join(c for c in s if c.isalnum() or "一" <= c <= "鿿")


def levenshtein(a: str, b: str) -> int:
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        curr = [i]
        for j, cb in enumerate(b, 1):
            curr.append(min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = curr
    return prev[-1]


def similarity(a: str, b: str) -> float:
    na, nb = normalize(a), normalize(b)
    if not na or not nb:
        return 0.0
    return 1.0 - levenshtein(na, nb) / max(len(na), len(nb))


def pcm_to_wav(pcm: Path, wav: Path):
    data = pcm.read_bytes()
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(data)


def transcribe(wav: Path, model: Path, language: str, prompt: str, threads: int) -> tuple[str, float]:
    cmd = [
        str(WHISPER_CLI), "-m", str(model), "-f", str(wav),
        "-l", language, "-t", str(threads),
        "--no-prints", "--no-timestamps", "--output-txt",
    ]
    if prompt:
        cmd += ["--prompt", prompt]
    txt_out = wav.with_suffix(".txt")
    txt_out.unlink(missing_ok=True)
    import time
    start = time.monotonic()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.monotonic() - start
    if proc.returncode != 0:
        return "", elapsed
    if txt_out.exists():
        return txt_out.read_text().strip(), elapsed
    return proc.stdout.strip(), elapsed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=str(MODEL), help="模型文件路径")
    parser.add_argument("--language", default="auto")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT)
    parser.add_argument("--threads", type=int, default=8)
    parser.add_argument("--min-sim", type=float, default=0.55)
    args = parser.parse_args()

    corpus = []
    for line in (CORPUS_DIR / "corpus.txt").read_text().splitlines():
        if line.strip():
            cid, text = line.split("\t", 1)
            corpus.append((cid.strip(), text.strip()))

    print(f"model: {Path(args.model).name}  language: {args.language}  prompt: {args.prompt!r}")
    print("=" * 60)

    failures = []
    total_sim = 0.0
    total_ms = 0.0
    with tempfile.TemporaryDirectory() as tmp:
        for cid, expected in corpus:
            wav = Path(tmp) / f"{cid}.wav"
            pcm_to_wav(CORPUS_DIR / f"{cid}.pcm", wav)
            actual, elapsed = transcribe(wav, Path(args.model), args.language, args.prompt, args.threads)
            sim = similarity(expected, actual)
            total_sim += sim
            total_ms += elapsed * 1000
            status = "PASS" if sim >= args.min_sim else "FAIL"
            print(f"[{status}] {cid}: sim={sim:.2f} {elapsed * 1000:.0f}ms")
            print(f"  期望: {expected}")
            print(f"  实际: {actual or '(空)'}")
            if sim < args.min_sim:
                failures.append(cid)

    n = len(corpus)
    print("=" * 60)
    print(f"平均相似度 {total_sim / n:.2f}, 平均耗时 {total_ms / n:.0f}ms, "
          f"{n - len(failures)}/{n} 通过 (阈值 {args.min_sim})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
