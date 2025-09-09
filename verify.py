#!/usr/bin/env python3
import sys

def extract_payload(bmp_path, payload_size, bit_order="lsb"):
    with open(bmp_path, "rb") as f:
        data = f.read()

    # BMP header offset: bytes 10–13 little endian
    offset = int.from_bytes(data[10:14], "little")

    # Pixel data
    pixels = data[offset:]

    bits = []
    for byte in pixels:
        bits.append(byte & 1)
        if len(bits) >= payload_size * 8:
            break

    payload_bytes = bytearray()
    for i in range(0, len(bits), 8):
        b = 0
        for j in range(8):
            if bit_order == "lsb":
                b |= (bits[i + j] << j)      # LSB-first
            else:
                b |= (bits[i + j] << (7 - j))  # MSB-first
        payload_bytes.append(b)

    return payload_bytes


def main():
    if len(sys.argv) < 4:
        print("Usage: verify.py <output.bmp> <payload.bin> <payload_size>")
        sys.exit(1)

    bmp_file = sys.argv[1]
    payload_file = sys.argv[2]
    size = int(sys.argv[3])

    with open(payload_file, "rb") as f:
        original = f.read()

    extracted_lsb = extract_payload(bmp_file, size, "lsb")
    extracted_msb = extract_payload(bmp_file, size, "msb")

    if extracted_lsb == original:
        print("✅ Payload verified (LSB-first match)")
    elif extracted_msb == original:
        print("✅ Payload verified (MSB-first match)")
    else:
        print("❌ Payload mismatch in both modes")
        print("Original :", original[:16].hex())
        print("LSB-first:", extracted_lsb[:16].hex())
        print("MSB-first:", extracted_msb[:16].hex())
        # Show first mismatch in LSB-first for debugging
        for i, (a, b) in enumerate(zip(original, extracted_lsb)):
            if a != b:
                print(f"LSB mismatch at byte {i}: expected {a:02x}, got {b:02x}")
                break


if __name__ == "__main__":
    main()
