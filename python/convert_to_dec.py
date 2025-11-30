import struct

def hex_to_float(hex_string):
    """Convert hexadecimal string to floating point value"""
    # Convert hex string to bytes
    hex_bytes = bytes.fromhex(hex_string)
    # Convert bytes to float (little-endian)
    return struct.unpack('<f', hex_bytes)[0]

def process_row(hex_row):
    """Process a single row of 8 floating point values"""
    # Each FP value is 8 hex characters (32 bits = 4 bytes = 8 hex digits)
    fp_values = []
    for i in range(0, len(hex_row), 8):
        hex_value = hex_row[i:i+8]
        fp_value = hex_to_float(hex_value)
        fp_values.append(fp_value)
    return fp_values

def main(input_file, output_file):
    """Main function to read input file and write to output file"""
    try:
        # Read input file
        with open(input_file, 'r') as f:
            hex_data = f.read().strip()
        
        # Process each row
        rows = hex_data.split('\n')
        
        # Write to output file
        with open(output_file, 'w') as f:
            for i, row in enumerate(rows):
                if row.strip():  # Skip empty lines
                    decimal_values = process_row(row.strip())
                    
                    # Write all 8 values in a row
                    for j, val in enumerate(decimal_values):
                        f.write(f"{val:.6f}")
                        if j < len(decimal_values) - 1:
                            f.write(", ")
                    f.write("\n")
        
        print(f"Successfully converted {len(rows)} rows from {input_file} to {output_file}")
        
    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found.")
    except Exception as e:
        print(f"Error: {e}")

# Usage
if __name__ == "__main__":
    input_filename = "../mem/Q_32.mem"  # Change this to your input file name
    output_filename = "../mem/bitcheck.out"  # Change this to your desired output file name
    
    main(input_filename, output_filename)


