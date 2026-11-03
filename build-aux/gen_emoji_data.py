#!/usr/bin/env python3
"""Generate Emozi's compact emoji database from Unicode + CLDR sources.

Output: a UTF-8 TSV, one line per *base* emoji, in Unicode order:

    group_index \t emoji \t name \t keywords \t variants \t version

* group_index  index into GROUPS below
* keywords     CLDR keywords joined with '|'
* variants     skin-tone variants joined with ',' (empty if none)
* version      emoji version the base was introduced in, e.g. "15.1"

The script fails loudly if the parsed counts do not match the totals in the
emoji-test.txt footer, so a malformed or truncated data update never ships.
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET

GROUPS = [
    "Smileys & Emotion",
    "People & Body",
    "Animals & Nature",
    "Food & Drink",
    "Travel & Places",
    "Activities",
    "Objects",
    "Symbols",
    "Flags",
]

TONE_NAMES = {
    "light skin tone",
    "medium-light skin tone",
    "medium skin tone",
    "medium-dark skin tone",
    "dark skin tone",
}

LINE_RE = re.compile(
    r"^(?P<cps>[0-9A-F ]+?)\s*;\s*(?P<status>[\w-]+)\s*#\s*\S+\s+E(?P<ver>[\d.]+)\s+(?P<name>.+)$"
)


def die(msg):
    print(f"gen_emoji_data: error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_emoji_test(path):
    entries = []  # (group, emoji, name, version)
    status_counts = {}
    footer_counts = {}
    group = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("# group:"):
                group = line.split(":", 1)[1].strip()
                continue
            m = re.match(r"^#\s*([\w-]+)\s*:\s*(\d+)\s*$", line)
            if m:
                footer_counts[m.group(1)] = int(m.group(2))
                continue
            if not line or line.startswith("#"):
                continue
            m = LINE_RE.match(line)
            if not m:
                die(f"unparseable line: {line!r}")
            status = m.group("status")
            status_counts[status] = status_counts.get(status, 0) + 1
            if status != "fully-qualified" or group == "Component":
                continue
            emoji = "".join(chr(int(cp, 16)) for cp in m.group("cps").split())
            entries.append((group, emoji, m.group("name").strip(), m.group("ver")))

    if not footer_counts:
        die("emoji-test.txt has no status-count footer (truncated file?)")
    for status, expected in footer_counts.items():
        got = status_counts.get(status, 0)
        if got != expected:
            die(f"status {status!r}: parsed {got}, footer says {expected}")
    return entries


def parse_cldr(paths):
    names, keywords = {}, {}
    for path in paths:
        root = ET.parse(path).getroot()
        for a in root.iter("annotation"):
            cp = a.get("cp")
            text = (a.text or "").strip()
            if not cp or not text:
                continue
            if a.get("type") == "tts":
                names.setdefault(cp, text)
            else:
                keywords.setdefault(cp, [k.strip() for k in text.split("|") if k.strip()])
    return names, keywords


def base_name(name):
    """Return the base emoji's name if `name` is a skin-tone variant, else None."""
    if ": " not in name:
        return None
    head, tail = name.split(": ", 1)
    parts = [p.strip() for p in tail.split(",")]
    rest = [p for p in parts if p not in TONE_NAMES]
    if len(rest) == len(parts):
        return None  # no tone component at all (e.g. "man: red hair")
    return f"{head}: {', '.join(rest)}" if rest else head


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--emoji-test", required=True)
    ap.add_argument("--cldr", action="append", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    entries = parse_emoji_test(args.emoji_test)
    cldr_names, cldr_keywords = parse_cldr(args.cldr)

    bases = []  # dicts, in file order
    by_name = {}
    orphans = []
    for group, emoji, name, ver in entries:
        if group not in GROUPS:
            die(f"unknown group {group!r}")
        bn = base_name(name)
        if bn is not None:
            # "kiss: person, person, light skin tone, ..." belongs to plain "kiss"
            base = by_name.get(bn) or by_name.get(bn.split(": ", 1)[0])
            if base is None:
                orphans.append(name)
            else:
                base["variants"].append(emoji)
                continue
        rec = {"group": GROUPS.index(group), "emoji": emoji, "name": name,
               "version": ver, "variants": []}
        bases.append(rec)
        by_name[name] = rec

    if orphans:
        die(f"{len(orphans)} skin-tone variants without a base, e.g. {orphans[:3]}")

    total = len(bases) + sum(len(b["variants"]) for b in bases)
    if total != len(entries):
        die(f"lost entries: {total} != {len(entries)}")

    def tsv_safe(s):
        if any(c in s for c in "\t\n"):
            die(f"tab/newline in field {s!r}")
        return s

    with open(args.output, "w", encoding="utf-8") as out:
        for b in bases:
            key = b["emoji"].replace("️", "")
            name = cldr_names.get(b["emoji"]) or cldr_names.get(key) or b["name"]
            kws = cldr_keywords.get(b["emoji"]) or cldr_keywords.get(key) or []
            kws = [k for k in kws if k.lower() != name.lower()]
            if any("|" in k for k in kws) or any("," in v for v in b["variants"]):
                die(f"separator collision in {b['name']!r}")
            out.write("\t".join(map(tsv_safe, [
                str(b["group"]), b["emoji"], name, "|".join(kws),
                ",".join(b["variants"]), b["version"],
            ])) + "\n")

    print(f"gen_emoji_data: {len(entries)} emojis, {len(bases)} base entries, "
          f"{total - len(bases)} skin-tone variants")


if __name__ == "__main__":
    main()
