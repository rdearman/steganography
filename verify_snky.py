import sys
import struct

def read_embedded_byte(f):
    """Reads one byte that has been embedded in the LSB of 8 subsequent bytes."""
    embedded_byte = 0
    for i in range(8):
        pixel_byte = f.read(1)
        if not pixel_byte:
            raise EOFError("Unexpected end of file while reading embedded data.")
        
        # Get the LSB of the pixel byte
        lsb = pixel_byte[0] & 1
        
        # Shift it to its correct position and add it to the result
        embedded_byte |= lsb << i
        
    return embedded_byte

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <bmp_file>")
        sys.exit(1)

    bmp_path = sys.argv[1]

    try:
        with open(bmp_path, 'rb') as f:
            # Read the BMP header to find the pixel data offset (bfOffBits)
            f.seek(10)
            bfOffBits_bytes = f.read(4)
            bfOffBits = struct.unpack('<I', bfOffBits_bytes)[0]
            
            print(f"Success! Found bfOffBits in {bmp_path} at position 54.")
            
            # Seek to the start of the pixel data to read the embedded header
            f.seek(bfOffBits)
            
            # Read and verify the magic bytes, one embedded byte at a time
            magic_bytes = bytearray()
            for _ in range(4):
                magic_bytes.append(read_embedded_byte(f))
                
            magic_bytes = bytes(magic_bytes)

            if magic_bytes == b'SNKY':
                # Unpack the magic bytes for a nice printout
                magic_unpacked = struct.unpack('4c', magic_bytes)
                print("Verified magic bytes: " + " ".join([f"0x{b:02X}" for b in magic_bytes]))
                
                # Read the next 4 bytes for the payload length
                payload_len_bytes = bytearray()
                for _ in range(4):
                    payload_len_bytes.append(read_embedded_byte(f))
                
                # Interpret them as a 32-bit unsigned little-endian integer
                payload_len = struct.unpack('<I', payload_len_bytes)[0]
                
                print(f"Payload size: {payload_len} bytes")
                
            else:
                print("Error: SNKY header not found or file is not valid.")
                
    except FileNotFoundError:
        print(f"Error: File not found at '{bmp_path}'")
    except EOFError as e:
        print(f"Error: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()
