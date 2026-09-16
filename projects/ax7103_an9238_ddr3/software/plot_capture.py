from argparse import ArgumentParser
from pathlib import Path
import struct

p = ArgumentParser(description="Plot or export packed AN9238 samples")
p.add_argument("file", type=Path)
p.add_argument("--count", type=int, default=4096)
p.add_argument("--csv", type=Path)
a = p.parse_args()
raw = a.file.read_bytes()
n = min(a.count, len(raw) // 4)
words = struct.unpack_from(f"<{n}I", raw)
ch0 = [w & 0xFFF for w in words]
ch1 = [(w >> 16) & 0xFFF for w in words]
if a.csv:
    with a.csv.open("w", encoding="utf-8") as f:
        f.write("index,ch0,ch1\n")
        for i, (x, y) in enumerate(zip(ch0, ch1)):
            f.write(f"{i},{x},{y}\n")
try:
    import matplotlib.pyplot as plt
except ImportError:
    print("matplotlib is not installed; CSV export remains available")
else:
    plt.plot(ch0, label="CH0")
    plt.plot(ch1, label="CH1")
    plt.xlabel("sample")
    plt.ylabel("ADC code")
    plt.grid(True)
    plt.legend()
    plt.show()
