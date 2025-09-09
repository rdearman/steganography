#!/usr/bin/env python3
import sys
import re
import argparse
import os
import tempfile

def fix_indentation(infile, outfile):
    with open(infile, "r") as f:
        lines = f.readlines()

    fixed_lines = []
    for line in lines:
        raw = line.rstrip("\n")

        # Preserve blank lines as-is
        if not raw.strip():
            fixed_lines.append(raw)
            continue

        # Full-line comments → keep original
        stripped = raw.lstrip()
        if stripped.startswith(("#", "/*", "*", "//")):
            fixed_lines.append(raw)
            continue

        # Split off inline comment if present
        code, sep, comment = raw.partition("#")
        code = code.rstrip()
        comment = sep + comment if sep else ""

        # Labels → flush left
        if re.match(r"^[A-Za-z0-9_.]+:\s*$", code.strip()):
            new_line = code.strip() + ((" " if comment else "") + comment)
            fixed_lines.append(new_line)
            continue

        # Directives (start with .) → flush left
        if code.strip().startswith("."):
            new_line = code.strip() + ((" " if comment else "") + comment)
            fixed_lines.append(new_line)
            continue

        # Instructions → indent with 8 spaces
        if code.strip():
            new_line = "        " + code.strip() + ((" " if comment else "") + comment)
            fixed_lines.append(new_line)
            continue

        # Fallback: keep original
        fixed_lines.append(raw)

    with open(outfile, "w") as f:
        f.write("\n".join(fixed_lines) + "\n")

def main():
    parser = argparse.ArgumentParser(description="Fix indentation of RISC-V assembly files.")
    parser.add_argument("infile", help="Input assembly file")
    parser.add_argument("outfile", nargs="?", help="Output file (default: overwrite infile)")
    parser.add_argument("--inplace", action="store_true", help="Modify the file in place")

    args = parser.parse_args()

    if args.inplace:
        fd, tmpfile = tempfile.mkstemp()
        os.close(fd)
        fix_indentation(args.infile, tmpfile)
        os.replace(tmpfile, args.infile)
    else:
        outfile = args.outfile if args.outfile else args.infile
        fix_indentation(args.infile, outfile)

if __name__ == "__main__":
    main()
