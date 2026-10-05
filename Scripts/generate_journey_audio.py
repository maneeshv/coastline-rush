"""Create original, deterministic synth ambiences and portal cues using stdlib."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
TAU = math.tau
DEST = Path(__file__).resolve().parents[1] / "Resources"


def write(name, duration, signal):
    samples = bytearray()
    for i in range(round(RATE * duration)):
        t = i / RATE
        value = max(-0.95, min(0.95, signal(t, duration)))
        samples.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(str(DEST / f"{name}.wav"), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(samples)


def ambience(world_index):
    # All oscillators use whole cycles over the loop, with a short seam envelope.
    roots = [110, 82.5, 98, 130.75, 146.75, 73.5]
    root = roots[world_index]
    ratios = [1, 1.5, 2, 2.375]

    def sample(t, duration):
        seam = min(1, t / 0.04, (duration - t) / 0.04)
        pad = sum(math.sin(TAU * (round(root * r * duration) / duration) * t
                           + 0.15 * math.sin(TAU * t / duration)) / (i + 2)
                  for i, r in enumerate(ratios))
        pulse = (0.5 + 0.5 * math.sin(TAU * t * (world_index + 2) / duration)) ** 6
        bell = math.sin(TAU * round(root * 6 * duration) / duration * t)
        shimmer = math.sin(TAU * 1760 * t) * math.sin(TAU * 0.25 * t)
        return seam * (0.19 * pad + 0.055 * pulse * bell + 0.01 * shimmer)
    return sample


for index, world in enumerate(["harbor", "orbit", "mars", "verdant", "cryo", "forge"]):
    write(f"ambient-{world}", 8, ambience(index))

rng = random.Random(42)


def portal(t, duration):
    x = t / duration
    swell = math.sin(math.pi * x) ** 1.8
    chirp = math.sin(TAU * (70 * t + 250 * t * t))
    air = rng.uniform(-1, 1)
    return swell * (0.27 * chirp + 0.065 * air + 0.10 * math.sin(TAU * 110 * t))


def arrival(t, duration):
    env = math.exp(-4 * t) * min(1, t / 0.02)
    return env * sum(math.sin(TAU * f * t) for f in [329.63, 493.88, 659.25]) * 0.16


def relic(t, duration):
    env = math.exp(-7 * t) * min(1, t / 0.006)
    return env * (0.22 * math.sin(TAU * 880 * t) + 0.13 * math.sin(TAU * 1320 * t))


write("portal", 1.6, portal)
write("arrival", 1.3, arrival)
write("relic", 0.65, relic)
print("Generated six world ambiences and three portal/relic cues.")
