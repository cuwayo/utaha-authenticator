#!/usr/bin/env python3
"""Appends keys to an ARB file safely.

The naive approach — splice text in before the final brace — repeatedly produced
invalid JSON because the previous entry's closing brace has no trailing comma.
This loads the file, adds the keys, and writes it back as valid JSON, so the
result is correct by construction.

Usage:
    python3 tool/add_arb_keys.py lib/l10n/app_en.arb keys.json

where keys.json is a list of [key, value, description] triples, or
[key, value, description, placeholderName] for a key with one String placeholder.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    arb_path = Path(sys.argv[1])
    keys_path = Path(sys.argv[2])

    # object_pairs_hook keeps insertion order, so the file stays in the order the
    # keys were added rather than being alphabetised.
    arb: dict[str, object] = json.loads(arb_path.read_text())
    entries: list[list[str]] = json.loads(keys_path.read_text())

    added = 0
    for entry in entries:
        key, value, description = entry[0], entry[1], entry[2]
        if key in arb:
            continue
        arb[key] = value
        meta: dict[str, object] = {"description": description}
        if len(entry) > 3 and entry[3]:
            meta["placeholders"] = {entry[3]: {"type": "String"}}
        arb[f"@{key}"] = meta
        added += 1

    arb_path.write_text(json.dumps(arb, ensure_ascii=False, indent=2) + "\n")
    print(f"added {added} keys to {arb_path}; total {len(arb)} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
