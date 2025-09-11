#!/usr/bin/env python3
import re
import argparse
import os
import tempfile

COMMENT_PREFIXES = ("#", "//", "/*", "*", ";")
current_section = None
inside_macro = False

SECTION_ALIASES = {".text", ".data", ".bss", ".rodata", ".sdata", ".sbss", ".tdata", ".tbss"}
SPECIAL_TEXT_DIRECTIVES = {".globl", ".extern", ".type", ".size"}

def detect_section_from_section_operands(operands: str) -> str | None:
    if not operands:
        return None
    head = operands.strip().split(",", 1)[0].strip()
    return head.strip('"').strip("'")

def split_code_comment(line: str):
    for delim in ("//", "#", ";"):
        if delim in line:
            idx = line.index(delim)
            return line[:idx].rstrip(), line[idx:]
    return line.rstrip(), ""

def ensure_comment_tabstop(base: str, comment: str, stops: int = 3) -> str:
    if not comment:
        return base
    line = base
    while line.count("\t") < stops:
        line += "\t"
    return line + comment

def format_instruction(code: str, comment: str, extra_indent: bool = False) -> str:
    parts = code.strip().split(None, 1)
    mnemonic = parts[0]
    operands = parts[1] if len(parts) > 1 else ""
    # Always one leading tab. Pad mnemonic differently inside macros.
    width = 7 if not extra_indent else 9  # slightly wider inside macros
    line = "\t" + f"{mnemonic:<{width}}"
    if operands:
        line += "\t" + operands
    return ensure_comment_tabstop(line, comment)

def set_section_if_applicable(directive: str, operands: str):
    global current_section
    if directive == ".section":
        current_section = detect_section_from_section_operands(operands)
    elif directive in SECTION_ALIASES:
        current_section = directive

def format_directive(code: str, comment: str, extra_indent: bool = False) -> str:
    global current_section, inside_macro
    parts = code.strip().split(None, 1)
    directive = parts[0]
    operands = parts[1] if len(parts) > 1 else ""

    # Section tracking
    set_section_if_applicable(directive, operands)

    # Macro tracking
    if directive == ".macro":
        inside_macro = True
    elif directive == ".endm":
        inside_macro = False

    # Special text directives flush-left
    if current_section == ".text" and directive in SPECIAL_TEXT_DIRECTIVES:
        line = directive
        if operands:
            line += "\t" + operands
        return ensure_comment_tabstop(line, comment)

    # Macro directives flush-left
    if directive in (".macro", ".endm"):
        line = directive
        if operands:
            line += "\t" + operands
        return ensure_comment_tabstop(line, comment)

    # Normal directive
    line = ("\t" * (2 if extra_indent else 0)) + directive
    if operands:
        line += "\t" + operands
    return ensure_comment_tabstop(line, comment)

def format_data_inline(label: str, directive_code: str, comment: str) -> str:
    parts = directive_code.strip().split(None, 1)
    directive = parts[0]
    operands = parts[1] if len(parts) > 1 else ""
    base = "\t" + label + ":" + "\t" + f"{directive:<8}"
    if operands:
        base += "\t" + operands
    return ensure_comment_tabstop(base, comment)

def is_label_only(code: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.]+:\s*", code.strip()))

def is_label_prefixed(code: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9_.]+:\s+", code.strip()))

def is_numeric_local_label(code: str) -> bool:
    return bool(re.match(r"^[0-9]+:\s*$", code.strip()))

def is_directive(code: str) -> bool:
    return code.strip().startswith(".")

def fix_indentation(infile, outfile):
    with open(infile, "r") as f:
        raw_lines = [ln.rstrip("\n") for ln in f]

    out = []
    i = 0
    prev_blank = False
    global current_section, inside_macro
    current_section = None
    inside_macro = False

    while i < len(raw_lines):
        raw = raw_lines[i]

        if not raw.strip():
            if not prev_blank:
                out.append("")
            prev_blank = True
            i += 1
            continue
        prev_blank = False

        if raw.lstrip().startswith(COMMENT_PREFIXES):
            out.append(raw)
            i += 1
            continue

        code, comment = split_code_comment(raw)

        # Numeric local label → always flush-left
        if is_numeric_local_label(code):
            out.append(code.strip())
            if comment:
                out.append(comment)
            i += 1
            continue

        # Label-only
        if is_label_only(code):
            label = code.strip()[:-1]
            if current_section == ".text":
                out.append(label + ":")  # flush-left
                if comment:
                    out.append(comment)
            else:
                out.append("\t" + label + ":")  # indented outside .text
                if comment:
                    out.append(comment)
            i += 1
            continue

        # Label + something
        if is_label_prefixed(code):
            label, rest = code.strip().split(":", 1)
            rest = rest.strip()
            if current_section == ".text":
                out.append(label + ":")
                if rest:
                    if is_directive(rest):
                        out.append(format_directive(rest, comment, extra_indent=inside_macro))
                    else:
                        out.append(format_instruction(rest, comment, extra_indent=inside_macro))
                elif comment:
                    out.append(comment)
            else:
                if is_directive(rest):
                    out.append(format_data_inline(label, rest, comment))
                else:
                    out.append("\t" + label + ":")
                    if rest:
                        out.append(format_instruction(rest, comment))
                    elif comment:
                        out.append(comment)
            i += 1
            continue

        # Directive
        if is_directive(code):
            out.append(format_directive(code, comment, extra_indent=inside_macro))
            i += 1
            continue

        # Instruction
        if code.strip():
            out.append(format_instruction(code, comment, extra_indent=inside_macro))
            i += 1
            continue

        out.append(raw)
        i += 1

    with open(outfile, "w") as f:
        f.write("\n".join(out) + "\n")

def main():
    p = argparse.ArgumentParser(description="Indent GNU as (RISC-V) with .text vs non-.text rules (tabs only).")
    p.add_argument("infile")
    p.add_argument("outfile", nargs="?")
    p.add_argument("--inplace", action="store_true", help="Modify the file in place")
    args = p.parse_args()

    if args.inplace:
        fd, tmp = tempfile.mkstemp()
        os.close(fd)
        fix_indentation(args.infile, tmp)
        os.replace(tmp, args.infile)
    else:
        out = args.outfile if args.outfile else args.infile
        fix_indentation(args.infile, out)

if __name__ == "__main__":
    main()
