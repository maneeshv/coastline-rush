"""Original seamless watercraft motor and spray loop; no downloaded samples."""
import math
import random
import struct
import wave
from pathlib import Path

rng = random.Random(419)
sr = 22050
count = sr * 2
noise = [rng.uniform(-1, 1) for _ in range(count)]
# A wrapping moving-average creates a smooth, exactly looping water bed.
spray = [sum(noise[(i + j) % count] for j in range(-4, 5)) / 9 for i in range(count)]
samples = []
for i in range(count):
    t = i / sr
    pulse = 0.82 + 0.18 * math.sin(2 * math.pi * 13 * t)
    motor = (math.sin(2 * math.pi * 72 * t) * 0.32
             + math.sin(2 * math.pi * 144 * t) * 0.13
             + math.sin(2 * math.pi * 216 * t) * 0.045) * pulse
    samples.append(motor + spray[i] * 0.28)
path = Path(__file__).resolve().parents[1] / 'Resources' / 'watercraft.wav'
with wave.open(str(path), 'w') as stream:
    stream.setnchannels(1)
    stream.setsampwidth(2)
    stream.setframerate(sr)
    stream.writeframes(b''.join(struct.pack('<h', int(value * 26000)) for value in samples))
print('Generated original seamless watercraft loop')
