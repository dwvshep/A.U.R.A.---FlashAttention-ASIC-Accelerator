import re
import sys

if len(sys.argv) != 3:
    print("Usage: python extract_hex.py input.txt output.txt")
    sys.exit(1)

inp = sys.argv[1]
out = sys.argv[2]

hex_pattern = re.compile(r'\b([0-9a-fA-F]{16})\b')

with open(inp, 'r') as fin, open(out, 'w') as fout:
    for line in fin:
        m = hex_pattern.search(line)
        if m:
            fout.write(m.group(1).lower() + '\n')