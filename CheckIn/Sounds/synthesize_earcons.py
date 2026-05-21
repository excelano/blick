#!/usr/bin/env python3
# synthesize_earcons.py
# CheckIn
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
#
# Generates the short earcons used by the state machine:
#   listening.wav     entry to active.listening      (rising glide, 200 ms)
#   thinking.wav      entry to active.processing     (soft pulse, 120 ms)
#   confirmation.wav  success on a confirmed write   (two-note chime, 240 ms)
#
# All are 44.1 kHz mono 16-bit PCM. They use a cosine-window envelope
# so attack and release are click-free, and they sit at modest amplitude so
# they don't fight with TTS or system audio.
#
# Run from the CheckIn/Sounds/ directory:
#   python3 synthesize_earcons.py

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
HERE = Path(__file__).parent


def envelope(n_samples: int) -> list[float]:
    """Cosine-window envelope: smooth attack and release, no clicks."""
    return [0.5 * (1 - math.cos(2 * math.pi * i / max(1, n_samples - 1)))
            for i in range(n_samples)]


def write_wav(path: Path, samples: list[float]) -> None:
    """Write float samples in [-1, 1] as 16-bit PCM mono WAV."""
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        clipped = [max(-1.0, min(1.0, s)) for s in samples]
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in clipped))


def listening() -> list[float]:
    """Rising glide 660 Hz to 880 Hz, 200 ms, moderate amplitude."""
    duration = 0.200
    n = int(SAMPLE_RATE * duration)
    env = envelope(n)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        progress = i / max(1, n - 1)
        freq = 660 + (880 - 660) * progress
        samples.append(0.45 * env[i] * math.sin(2 * math.pi * freq * t))
    return samples


def thinking() -> list[float]:
    """Soft single tone at 750 Hz, 120 ms, lower amplitude so it doesn't
    compete with the latency reassurance pool."""
    duration = 0.120
    n = int(SAMPLE_RATE * duration)
    env = envelope(n)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        samples.append(0.25 * env[i] * math.sin(2 * math.pi * 750 * t))
    return samples


def confirmation() -> list[float]:
    """Two-note ascending chime: 660 Hz then 990 Hz, each ~100 ms with a
    20 ms gap. Reads as a small affirmative event without competing with
    the success TTS that follows."""
    note_duration = 0.100
    gap_duration = 0.020
    n_note = int(SAMPLE_RATE * note_duration)
    n_gap = int(SAMPLE_RATE * gap_duration)
    env = envelope(n_note)
    samples: list[float] = []
    for freq in (660.0, 990.0):
        for i in range(n_note):
            t = i / SAMPLE_RATE
            samples.append(0.35 * env[i] * math.sin(2 * math.pi * freq * t))
        if freq == 660.0:
            samples.extend([0.0] * n_gap)
    return samples


def main() -> None:
    write_wav(HERE / "listening.wav", listening())
    write_wav(HERE / "thinking.wav", thinking())
    write_wav(HERE / "confirmation.wav", confirmation())
    for name in ("listening.wav", "thinking.wav", "confirmation.wav"):
        path = HERE / name
        with wave.open(str(path), "rb") as w:
            frames = w.getnframes()
            ms = round(frames / SAMPLE_RATE * 1000)
        print(f"{name}: {ms} ms, {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
