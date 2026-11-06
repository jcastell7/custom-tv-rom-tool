#!/usr/bin/env python3
"""
uboot_env.py — decode / re-encode the Allwinner "hermes" u-boot environment
partition (env_a.img), with a verified byte-exact round-trip.

Format discovered empirically from the stock env_a.img backup
(docs/13-fastboot-trigger-no-fel.md):

  partition size : 262144  (0x40000, 256 KiB)
  CONFIG_ENV_SIZE: 131072  (0x20000, 128 KiB)   <- the env block
  layout         : [ CRC32 (4 bytes, little-endian) ][ env payload ... ]
                   CRC32 is the standard IEEE/zlib crc32 over payload =
                   bytes[4 : CONFIG_ENV_SIZE]   (verified: 0x250d0425)
  payload        : one leading 0x00 byte, then NUL-separated "key=val"
                   entries, a terminating 0x00, and 0x00 fill to the end
                   of the env block.
  tail           : bytes[CONFIG_ENV_SIZE : partition_size] are unused and
                   are preserved verbatim.

  NON-redundant (no 1-byte flags field; the leading 0x00 is inside the
  CRC'd payload and is reproduced verbatim).

This module is pure stdlib so it runs anywhere mkenvimage is unavailable.
"""
import binascii
import sys

ENV_SIZE = 0x20000          # CONFIG_ENV_SIZE
PART_SIZE = 0x40000         # env partition size on this device


def decode(raw: bytes):
    """Return (vars_dict, order_list, leading, tail) from a raw env image.

    vars_dict : {key: value}
    order     : keys in their on-disk order (so we can re-serialize exactly)
    leading   : bytes before the first key=val entry (the stock's single 0x00)
    tail      : bytes after the env block (unused padding, preserved verbatim)
    """
    if len(raw) < ENV_SIZE:
        raise ValueError(f"image too small: {len(raw)} < {ENV_SIZE}")
    payload = raw[4:ENV_SIZE]
    tail = raw[ENV_SIZE:]

    # Everything up to the first non-empty token is "leading" (stock: 0x00).
    # Then NUL-separated key=val, ending at a double-NUL.
    i = 0
    while i < len(payload) and payload[i] == 0:
        i += 1
    leading = payload[:i]

    vars_ = {}
    order = []
    body = payload[i:]
    for tok in body.split(b"\x00"):
        if tok == b"":
            break  # terminating NUL -> end of env
        s = tok.decode("latin-1")
        if "=" not in s:
            # malformed entry; keep it keyed to itself to avoid data loss
            k, v = s, ""
        else:
            k, v = s.split("=", 1)
        if k not in vars_:
            order.append(k)
        vars_[k] = v
    return vars_, order, leading, tail


def encode(vars_: dict, order: list, leading: bytes, tail: bytes) -> bytes:
    """Inverse of decode(): produce a full-size, CRC-correct env image."""
    body = bytearray()
    body += leading
    for k in order:
        body += f"{k}={vars_[k]}".encode("latin-1") + b"\x00"
    body += b"\x00"  # terminating NUL
    payload = bytes(body)
    if len(payload) > ENV_SIZE - 4:
        raise ValueError("env payload too large for CONFIG_ENV_SIZE")
    payload = payload + b"\x00" * ((ENV_SIZE - 4) - len(payload))
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    out = crc.to_bytes(4, "little") + payload + tail
    # pad/truncate to the real partition size
    if len(out) < PART_SIZE:
        out = out + b"\x00" * (PART_SIZE - len(out))
    return out[:PART_SIZE]


def verify_roundtrip(path: str) -> bool:
    raw = open(path, "rb").read()
    v, order, leading, tail = decode(raw)
    out = encode(v, order, leading, tail)
    ok = out == raw
    print(f"[roundtrip] {'OK (byte-exact)' if ok else 'MISMATCH'}  "
          f"vars={len(v)} env_size=0x{ENV_SIZE:x} part=0x{PART_SIZE:x}")
    if not ok:
        # locate first differing byte for debugging
        n = min(len(out), len(raw))
        for i in range(n):
            if out[i] != raw[i]:
                print(f"  first diff at 0x{i:x}: got {out[i]:02x} "
                      f"want {raw[i]:02x}")
                break
        if len(out) != len(raw):
            print(f"  length differs: got {len(out)} want {len(raw)}")
    return ok


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "print":
        raw = open(sys.argv[2], "rb").read()
        v, order, _, _ = decode(raw)
        for k in order:
            print(f"{k}={v[k]}")
    elif len(sys.argv) >= 3 and sys.argv[1] == "verify":
        sys.exit(0 if verify_roundtrip(sys.argv[2]) else 1)
    else:
        print("usage: uboot_env.py {print|verify} <env.img>", file=sys.stderr)
        sys.exit(2)
