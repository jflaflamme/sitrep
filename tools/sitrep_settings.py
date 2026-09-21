#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""sitrep_settings: read and write SITREP's settings file on a USB-connected Garmin watch.

Used by garmin-sitrep. Connect IQ keeps an app's settings in
GARMIN/Apps/SETTINGS/<name>.SET; this module decodes and rewrites that format and copies
the file over MTP with gio. Every write backs up the watch's copy first, to
$GARMIN_BACKUP_DIR (default $XDG_DATA_HOME/garmin-watch/backups).

File format (reverse engineered, big endian):
  ABCDABCD, u32 length, string table (u16 length incl. NUL, bytes, NUL)...
  DA7ADA7A, u32 length, one serialized value (normally a dictionary):
    00 null  01 int32  02 float  03 string (u32 offset into the table)
    05 array (u32 count, values)  09 bool (1 byte)  0B dictionary (u32 count, key/value pairs)
    0E int64  0F double  13 char (u32)
"""

import datetime
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import urllib.parse

GARMIN_USB_VENDOR = "091e"
STRING_MAGIC = b"\xab\xcd\xab\xcd"
DATA_MAGIC = b"\xda\x7a\xda\x7a"
DATA_HOME = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "garmin-watch")
BACKUP_ROOT = os.path.expanduser(os.environ.get("GARMIN_BACKUP_DIR") or os.path.join(DATA_HOME, "backups"))

T_NULL, T_INT, T_FLOAT, T_STRING, T_ARRAY, T_BOOL, T_DICT, T_LONG, T_DOUBLE, T_CHAR = \
    0x00, 0x01, 0x02, 0x03, 0x05, 0x09, 0x0B, 0x0E, 0x0F, 0x13


class Typed:
    """A value plus its serialized type, for types Python would otherwise merge."""

    def __init__(self, kind, value):
        self.kind, self.value = kind, value

    def __eq__(self, other):
        return isinstance(other, Typed) and (self.kind, self.value) == (other.kind, other.value)

    def __hash__(self):
        return hash((self.kind, self.value))

    def __repr__(self):
        name = {T_FLOAT: "float", T_LONG: "long", T_DOUBLE: "double", T_CHAR: "char"}[self.kind]
        return f"{name}({self.value!r})"


def decode(data):
    if data[:4] != STRING_MAGIC:
        raise ValueError("not a Connect IQ settings file (no string table)")
    slen = struct.unpack_from(">I", data, 4)[0]
    strings = data[8:8 + slen]
    pos = 8 + slen
    if data[pos:pos + 4] != DATA_MAGIC:
        raise ValueError("not a Connect IQ settings file (no data section)")
    pos += 8

    def string_at(off):
        n = struct.unpack_from(">H", strings, off)[0]
        return strings[off + 2:off + 2 + n].rstrip(b"\0").decode("utf-8")

    def value():
        nonlocal pos
        t = data[pos]
        pos += 1
        if t == T_NULL:
            return None
        if t == T_BOOL:
            pos += 1
            return bool(data[pos - 1])
        if t in (T_INT, T_FLOAT, T_STRING, T_CHAR):
            raw = data[pos:pos + 4]
            pos += 4
            if t == T_INT:
                return struct.unpack(">i", raw)[0]
            if t == T_FLOAT:
                return Typed(T_FLOAT, struct.unpack(">f", raw)[0])
            if t == T_STRING:
                return string_at(struct.unpack(">I", raw)[0])
            return Typed(T_CHAR, chr(struct.unpack(">I", raw)[0]))
        if t in (T_LONG, T_DOUBLE):
            raw = data[pos:pos + 8]
            pos += 8
            return Typed(t, struct.unpack(">q" if t == T_LONG else ">d", raw)[0])
        if t in (T_ARRAY, T_DICT):
            n = struct.unpack_from(">I", data, pos)[0]
            pos += 4
            if t == T_ARRAY:
                return [value() for _ in range(n)]
            result = {}
            for _ in range(n):
                key = value()
                result[key] = value()
            return result
        raise ValueError(f"unknown value type 0x{t:02x} at byte {pos - 1}")

    return value()


def encode(root):
    table = bytearray()
    offsets = {}
    body = bytearray()

    def string_ref(text):
        if text not in offsets:
            raw = text.encode("utf-8") + b"\0"
            offsets[text] = len(table)
            table.extend(struct.pack(">H", len(raw)) + raw)
        return offsets[text]

    def value(v):
        if v is None:
            body.append(T_NULL)
        elif isinstance(v, bool):
            body.extend(bytes([T_BOOL, int(v)]))
        elif isinstance(v, int):
            body.append(T_INT)
            body.extend(struct.pack(">i", v))
        elif isinstance(v, str):
            body.append(T_STRING)
            body.extend(struct.pack(">I", string_ref(v)))
        elif isinstance(v, Typed):
            body.append(v.kind)
            fmt = {T_FLOAT: ">f", T_LONG: ">q", T_DOUBLE: ">d"}.get(v.kind)
            body.extend(struct.pack(fmt, v.value) if fmt else struct.pack(">I", ord(v.value)))
        elif isinstance(v, list):
            body.append(T_ARRAY)
            body.extend(struct.pack(">I", len(v)))
            for item in v:
                value(item)
        elif isinstance(v, dict):
            body.append(T_DICT)
            body.extend(struct.pack(">I", len(v)))
            for key, item in v.items():
                value(key)
                value(item)
        else:
            raise ValueError(f"cannot store {v!r}")

    value(root)
    return (STRING_MAGIC + struct.pack(">I", len(table)) + bytes(table)
            + DATA_MAGIC + struct.pack(">I", len(body)) + bytes(body))


def show_value(key, v):
    if isinstance(v, int) and not isinstance(v, bool) and "color" in str(key).lower() and v >= 0:
        return f"{v}  (#{v:06X})"
    return repr(v)


def parse_new_value(key, old, text):
    """Read TEXT as the same type as the current value OLD."""
    if isinstance(old, bool):
        if text.lower() in ("true", "1", "on", "yes"):
            return True
        if text.lower() in ("false", "0", "off", "no"):
            return False
        raise ValueError(f"{key} is a boolean, use true or false")
    if isinstance(old, int):
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", text):
            return int(text[1:], 16)
        try:
            return int(text, 0)
        except ValueError:
            raise ValueError(f"{key} is a number, got {text!r}") from None
    if isinstance(old, str):
        return text
    if isinstance(old, Typed) and old.kind in (T_FLOAT, T_DOUBLE):
        return Typed(old.kind, float(text))
    if isinstance(old, Typed) and old.kind == T_LONG:
        return Typed(T_LONG, int(text, 0))
    raise ValueError(f"{key} has type {type(old).__name__}, which set cannot change")


def find_garmin_dir():
    def roots():
        return sorted(glob.glob(f"/run/user/{os.getuid()}/gvfs/mtp:host={GARMIN_USB_VENDOR}_*"))
    if not roots():
        try:
            out = subprocess.run(["gio", "mount", "-li"], capture_output=True, text=True, timeout=20).stdout
            for uri in set(re.findall(r"activation_root=(mtp://%s_\S+?/)" % GARMIN_USB_VENDOR, out)):
                subprocess.run(["gio", "mount", uri], capture_output=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            pass
    for root in roots():
        for storage in sorted(os.listdir(root)):
            candidate = next((os.path.join(root, storage, n) for n in os.listdir(os.path.join(root, storage))
                              if n.lower() == "garmin"), None)
            if candidate and os.path.isfile(os.path.join(candidate, "GarminDevice.xml")):
                return candidate
    return None


def child_dir(parent, name):
    match = next((n for n in os.listdir(parent) if n.lower() == name.lower()), None)
    return os.path.join(parent, match) if match else None


def settings_files(folder):
    return sorted(glob.glob(os.path.join(glob.escape(folder), "*.[Ss][Ee][Tt]")))


def read(path):
    with open(path, "rb") as fh:
        return decode(fh.read())


def copy_to_watch(src, dest):
    # gio speaks MTP directly; some FUSE MTP mounts have silently written empty files
    info = subprocess.run(["gio", "info", os.path.dirname(dest)], capture_output=True, text=True)
    uri = next((line.split(":", 1)[1].strip() for line in info.stdout.splitlines()
                if line.startswith("uri:")), "")
    if uri:
        subprocess.run(["gio", "copy", "--backup=none", "-T", src,
                        uri.rstrip("/") + "/" + urllib.parse.quote(os.path.basename(dest))], check=True)
    else:
        shutil.copyfile(src, dest)
    if not os.path.isfile(dest) or os.path.getsize(dest) != os.path.getsize(src):
        sys.exit("copy to the watch could not be verified (size differs); do not unplug, retry")


def backup(paths, label):
    folder = os.path.join(BACKUP_ROOT, f"ciq-{label}-{datetime.datetime.now():%Y%m%d-%H%M%S}")
    os.makedirs(folder)
    for path in paths:
        shutil.copyfile(path, os.path.join(folder, os.path.basename(path)))
    return folder


def settings_dir(writable=False):
    """GARMIN/Apps/SETTINGS on the watch; the watch has to be plugged in."""
    garmin = os.environ.get("GARMIN_WATCH_DIR") or find_garmin_dir()
    if not garmin:
        sys.exit("no Garmin watch found over USB (plug it in and allow file access)")
    apps = child_dir(garmin, "Apps")
    found = apps and child_dir(apps, "SETTINGS")
    if not found:
        sys.exit(f"no Apps/SETTINGS folder under {garmin}")
    return found


# no offline mirror or change queue in this module
def is_mirror(path):
    return False


def pending_files():
    return []


def mirror_file(local, relative):
    pass
