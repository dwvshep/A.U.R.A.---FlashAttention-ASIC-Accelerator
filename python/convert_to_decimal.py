import struct
import argparse

def hex_to_float(hex_string):
    """Convert 8-hex-char big-endian or little-endian hex to float."""
    hex_bytes = bytes.fromhex(hex_string)
    return struct.unpack('<f', hex_bytes)[0]   # interpret as little-endian FP32


def process_row(hex_row):
    """Convert a row of 8 FP32 values from hex to decimals."""
    fp_values = []
    for i in range(0, len(hex_row), 8):
        hex_value = hex_row[i:i+8]
        fp_values.append(hex_to_float(hex_value))
    return fp_values


def convert_file(input_file, output_file):
    """Main conversion function."""
    try:
        with open(input_file, 'r') as f:
            rows = [line.strip() for line in f if line.strip()]

        with open(output_file, 'w') as out:
            for row in rows:
                decimal_values = process_row(row)
                out.write(", ".join(f"{v:.6f}" for v in decimal_values))
                out.write("\n")

        print(f"Converted {len(rows)} rows → {output_file}")

    except FileNotFoundError:
        print(f"ERROR: File not found: {input_file}")
    except Exception as e:
        print(f"ERROR: {e}")


def main():
    parser = argparse.ArgumentParser(description="Convert FP32 hex .mem file to decimal output.")
    parser.add_argument("input", help="Path to input .mem file (hex FP32)")
    parser.add_argument("output", help="Path to output .dec file (decimal FP32)")

    args = parser.parse_args()
    convert_file(args.input, args.output)


if __name__ == "__main__":
    main()
