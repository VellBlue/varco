#!/usr/bin/env python3
"""Replaces the build machine's paths inside the engine files with neutral text of the SAME length.

Wine's binaries can contain the absolute paths of the machine that built them (source file names in assertions,
debug information). A safety net for the release package: the paths are rewritten in place, so every byte keeps its
position, and Mach-O files whose signature this breaks are signed again.

usage: scrub-paths.py <folder> [<home>]     (home defaults to $HOME)
"""
import os
import subprocess
import sys

MACHO_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def neutral(length, base):
    """`base` cut or padded with '_' to exactly `length` bytes."""
    return (base + "_" * length)[:length].encode()


def rules(home):
    h = home.rstrip("/").encode()
    out = []
    # longer, more specific prefixes first
    for sub, base in ((b"/WineBox/", "/opt/varco/engine/sources/"), (b"/Varco/", "/opt/varco/engine/build/")):
        old = h + sub
        out.append((old, neutral(len(old), base)))
    out.append((h + b"/", neutral(len(h) + 1, "/opt/varco/")))
    return out


def scrub(path, rep):
    with open(path, "rb") as f:
        data = f.read()
    new = data
    for old, repl in rep:
        assert len(old) == len(repl)
        new = new.replace(old, repl)
    if new != data:
        with open(path, "wb") as f:
            f.write(new)
        # a signed Mach-O no longer matches its signature: sign it again (ad hoc, like the linker does)
        if data[:4] in MACHO_MAGIC and b"invalid signature" in subprocess.run(["codesign", "-v", path], capture_output=True).stderr:
            subprocess.run(["codesign", "-f", "-s", "-", path], check=True, capture_output=True)
        return True
    return False


def main():
    root = sys.argv[1]
    home = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~")
    rep = rules(home)
    changed = 0
    for d, _, files in os.walk(root):
        for name in files:
            p = os.path.join(d, name)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            changed += scrub(p, rep)
    left = 0
    needle = home.rstrip("/").encode()
    for d, _, files in os.walk(root):
        for name in files:
            p = os.path.join(d, name)
            if not os.path.islink(p) and os.path.isfile(p):
                with open(p, "rb") as f:
                    left += needle in f.read()
    print(f"{changed} files rewritten, {left} still containing {home}")
    sys.exit(1 if left else 0)


if __name__ == "__main__":
    main()
