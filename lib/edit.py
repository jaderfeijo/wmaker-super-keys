#!/usr/bin/env python3
"""Small file-editing helper used by install.sh (kept in Python so the edits are exact and idempotent).

  edit.py block-add    FILE COMMENT_CHAR CONTENT_FILE [--before-exit] [--dry]
  edit.py block-remove FILE COMMENT_CHAR [--dry]
  edit.py wm-set       FILE KEYS_CONF STATE_FILE [--dry]     set Window Maker keys, remembering the old values
  edit.py wm-restore   FILE STATE_FILE [--dry]               put the remembered values back
"""
import json
import os
import re
import sys

NAME = "wmaker-super-keys"


def markers(comment):
    return f"{comment} >>> {NAME} >>>", f"{comment} <<< {NAME} <<<"


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return default


def write(path, text, dry):
    if dry:
        print(f"[dry-run] would write {path}")
        return
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def strip_block(text, comment):
    begin, end = markers(comment)
    pattern = re.compile(r"(?ms)^" + re.escape(begin) + r"\n.*?^" + re.escape(end) + r"\n?")
    text = pattern.sub("", text)
    return re.sub(r"\n{3,}", "\n\n", text).lstrip("\n")      # no blank lines left behind


def block_add(path, comment, content_file, before_exit, dry):
    begin, end = markers(comment)
    text = strip_block(read(path), comment)
    block = f"{begin}\n{read(content_file).rstrip()}\n{end}\n"
    if before_exit:
        match = list(re.finditer(r"(?m)^exit\s+0\s*$", text))
        if match:
            i = match[-1].start()
            text = text[:i] + block + text[i:]
            return write(path, text, dry)
    text = text.rstrip("\n")                  # drop the blank line(s) a previous block left behind
    write(path, (text + "\n\n" if text else "") + block, dry)


def block_remove(path, comment, dry):
    text = read(path, None)
    if text is None:
        return
    new = strip_block(text, comment)
    if new != text:
        write(path, new, dry)


def parse_conf(path):
    pairs = []
    for line in read(path).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        pairs.append((key.strip(), value.strip().rstrip(";").strip()))
    return pairs


def key_pattern(key):
    # a one-line value, or a parenthesised list that may span lines
    return re.compile(r"(?ms)^([ \t]*)" + re.escape(key) + r"[ \t]*=[ \t]*(\([^;]*?\)|[^;\n]*);[ \t]*\n?")


def wm_set(path, keys_conf, state_file, dry):
    text = read(path)
    if not text.strip():
        text = "{\n}\n"
    previous = json.loads(read(state_file, "{}"))
    if not os.path.exists(path + ".wmsk-backup") and os.path.exists(path) and not dry:
        with open(path + ".wmsk-backup", "w") as f:
            f.write(text)
    for key, value in parse_conf(keys_conf):
        match = key_pattern(key).search(text)
        if match:
            previous.setdefault(key, {"old": match.group(2).strip(), "new": value})
            text = text[:match.start()] + f"{match.group(1)}{key} = {value};\n" + text[match.end():]
        else:
            previous.setdefault(key, {"old": None, "new": value})
            close = text.rstrip().rfind("}")
            text = text[:close] + f"  {key} = {value};\n" + text[close:]
        previous[key]["new"] = value
    write(path, text, dry)
    write(state_file, json.dumps(previous, indent=1) + "\n", dry)


def wm_restore(path, state_file, dry):
    previous = json.loads(read(state_file, "{}"))
    text = read(path)
    for key, info in previous.items():
        match = key_pattern(key).search(text)
        if not match or match.group(2).strip() != info["new"]:
            print(f"left {key} alone (it was changed after the install)")
            continue
        replacement = "" if info["old"] is None else f"{match.group(1)}{key} = {info['old']};\n"
        text = text[:match.start()] + replacement + text[match.end():]
    if text.strip():
        write(path, text, dry)
    if not dry and os.path.exists(state_file):
        os.remove(state_file)


def main(argv):
    dry = "--dry" in argv
    before_exit = "--before-exit" in argv
    args = [a for a in argv if not a.startswith("--")]
    cmd = args[0] if args else ""
    if cmd == "block-add":
        block_add(args[1], args[2], args[3], before_exit, dry)
    elif cmd == "block-remove":
        block_remove(args[1], args[2], dry)
    elif cmd == "wm-set":
        wm_set(args[1], args[2], args[3], dry)
    elif cmd == "wm-restore":
        wm_restore(args[1], args[2], dry)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
