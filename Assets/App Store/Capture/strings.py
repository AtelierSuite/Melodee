"""Prints the app's own text for a key, so scenes can tap labels in any language.

    strings.py <language> <device> <key>...
"""

import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[3] / "Melodee" / "Localizable.xcstrings"


def value(localization, device):
    if "stringUnit" in localization:
        return localization["stringUnit"]["value"]
    variations = localization["variations"]["device"]
    return value(variations.get(device.lower(), variations["other"]), device)


strings = json.loads(CATALOG.read_text())["strings"]
language, device = sys.argv[1], sys.argv[2]
for key in sys.argv[3:]:
    print(value(strings[key]["localizations"][language], device))
