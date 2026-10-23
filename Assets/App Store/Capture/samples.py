"""Prints names from the sample library, as they appear in the app, for scenes to tap.

    samples.py <language> school <index>
    samples.py <language> album <key>
    samples.py <language> track <album key> <number>
    samples.py <language> playlist <index>
"""

import json
import sys
from pathlib import Path

LIBRARY = Path(__file__).resolve().parents[1] / "Seed" / "library.json"

library = json.loads(LIBRARY.read_text())
albums = {album["key"]: album for school in library["schools"] for album in school["albums"]}
language, kind, *arguments = sys.argv[1:]
if kind == "school":
    print(library["schools"][int(arguments[0])]["folder"][language])
elif kind == "album":
    print(albums[arguments[0]]["folder"][language])
elif kind == "track":
    number = int(arguments[1])
    print(f"{number:02d} {albums[arguments[0]]['tracks'][number - 1][language]}")
elif kind == "playlist":
    print(library["playlists"][int(arguments[0])]["name"][language])
else:
    sys.exit(__doc__)
