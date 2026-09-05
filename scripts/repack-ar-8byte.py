#!/usr/bin/env python3
"""Repack an `ar` archive so 64-bit object members are 8-byte aligned.

Zig's bundled ar writer pads members to even offsets only. Apple ld64
rejects 64-bit Mach-O members that are not 8-byte aligned:
    ld: 64-bit mach-o member 'x.o' not 8-byte aligned

This script rewrites the archive with every member aligned to 8 bytes
and drops any precomputed symbol index (`__.SYMDEF*`, `/`, `//`,
`/SYM64/`). All modern linkers (Apple ld64, GNU ld, lld) scan members
directly when an index is absent.
"""
import sys


def main(path: str) -> None:
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"!<arch>\n":
        raise SystemExit(f"{path}: not an ar archive")

    members: list[tuple[str, bytes]] = []
    pos = 8
    while pos < len(data):
        hdr = data[pos : pos + 60]
        if len(hdr) < 60 or hdr[58:60] != b"`\n":
            raise SystemExit(f"{path}: truncated member header at {pos}")
        name = hdr[0:16].decode("ascii").rstrip()
        size = int(hdr[48:58].decode("ascii").strip())
        body = data[pos + 60 : pos + 60 + size]
        pos += 60 + size + (size & 1)  # ar pads members to even offsets

        # BSD extended name: "#1/<len>" with the real name in the data
        # prefix.
        if name.startswith("#1/"):
            nlen = int(name[3:])
            real = body[:nlen].rstrip(b"\x00").decode("utf-8")
            body = body[nlen:]
        else:
            real = name.rstrip("/")

        # Drop precomputed symbol indexes and the long-name table; their
        # stored offsets are invalid after realignment anyway.
        if real in ("/", "//", "/SYM64/") or real.startswith("__.SYMDEF") or real.startswith("__SYMDEF"):
            continue
        members.append((real, body))

    out = [b"!<arch>\n"]
    for name, body in members:
        # BSD #1 extended-name style, exactly like /usr/bin/ar on macOS:
        # a fixed 20-byte zero-padded name prefix puts the object content
        # at (hdr + 60 + 20) which is 8-aligned whenever the header is.
        # Alignment padding rides inside the member size, as BSD ar does.
        nlen = 20
        if len(name) > nlen:
            raise SystemExit(f"{path}: member name too long: {name}")
        data = name.encode("utf-8") + b"\x00" * (nlen - len(name)) + body
        while (60 + len(data)) % 8 != 0:
            data += b"\n"
        out.append(
            f"#1/{nlen}".ljust(16).encode("ascii")
            + b"0".ljust(12)  # mtime (deterministic)
            + b"0".ljust(6)  # uid
            + b"0".ljust(6)  # gid
            + b"644".ljust(8)  # mode
            + str(len(data)).encode("ascii").ljust(10)
            + b"`\n"
        )
        out.append(data)

    with open(path, "wb") as f:
        f.write(b"".join(out))
    print(f"repacked {path}: {len(members)} members, 8-byte aligned, no index")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <archive.a>")
    main(sys.argv[1])
