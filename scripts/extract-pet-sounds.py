#!/usr/bin/env python3
"""홍보영상의 음악 없는 원본 효과음에서 지크용 WAV 두 개를 추출한다.

사용법: python3 scripts/extract-pet-sounds.py /path/to/effects.wav
기존 영상에서 직접 합성한 소리이며 외부 샘플·음성·라이선스 음악을 사용하지 않는다.
앱 실행과 빌드에는 이미 포함된 WAV만 필요하며 원본 영상은 필요하지 않다.
"""
from array import array
from pathlib import Path
import hashlib
import json
import math
import sys
import wave


def extract(source, destination, start, end):
    """효과음 구간을 원래 속도로 자르고 클릭 방지 페이드와 고정 피크 여유를 적용한다."""
    with wave.open(str(source), "rb") as audio:
        channels, width, rate, frames = audio.getparams()[:4]
        if (channels, width, rate) != (2, 2, 48000) or end * rate > frames:
            raise ValueError("48 kHz 스테레오 16비트 원본과 유효한 구간이 필요합니다")
        audio.setpos(round(start * rate))
        samples = array("h", audio.readframes(round((end - start) * rate)))
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(sample) for sample in samples)
    if not peak:
        raise ValueError("효과음 구간이 무음입니다")
    gain = 0.55 * 32767 / peak
    length = len(samples) // channels
    fade_frames = round(rate * 0.005)
    for frame in range(length):
        fade = min(1, frame / fade_frames, (length - 1 - frame) / fade_frames)
        for channel in range(channels):
            index = frame * channels + channel
            samples[index] = round(samples[index] * gain * fade)
    peak_out = max(abs(sample) for sample in samples) / 32767
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples)) / 32767
    if sys.byteorder != "little":
        samples.byteswap()
    with wave.open(str(destination), "wb") as audio:
        audio.setparams((channels, width, rate, length, "NONE", "not compressed"))
        audio.writeframes(samples.tobytes())
    return {"source_range_seconds": [start, end], "duration_seconds": length / rate,
            "peak": peak_out, "rms": rms, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


def main():
    """붙잡힘 단발·타자 반복 파일과 출처·검증 메타데이터를 번들 리소스 위치에 기록한다."""
    if len(sys.argv) != 2:
        raise SystemExit("사용법: python3 scripts/extract-pet-sounds.py /path/to/effects.wav")
    source = Path(sys.argv[1])
    output = Path(__file__).resolve().parents[1] / "Sources/ZCREBunny/Resources/Sounds"
    output.mkdir(parents=True, exist_ok=True)
    assets = {}
    for name, start, end in [("grab", 7.02, 7.62), ("typing", 8.8, 12.8)]:
        assets[name + ".wav"] = extract(source, output / (name + ".wav"), start, end)
    manifest = {"origin": "ZCRE Supporter promo v3.2 original synthesized effects track",
                "external_samples": [], "voices": False, "music_included": False,
                "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "sample_rate": 48000, "channels": 2, "pcm_bits": 16,
                "edge_fade_ms": 5, "assets": assets}
    (output / "provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(assets, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
