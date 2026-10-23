"""Fills a Documents folder with the sample library the App Store screenshots show.

    seed.py --language <en|ja> --documents <dir> [--cache <dir>]

Every track is silent MP3 audio with real ID3 tags and a mesh gradient cover, so the
app reads titles, artists and artwork exactly as it would from a user's own files.
Encoded tracks are kept in the cache and reused while their tags and cover are unchanged.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

from artwork import cover_jpeg, rng_for

SEED_DIR = Path(__file__).resolve().parent
LANGUAGES = ("en", "ja")
NOTES = {
    "en": "{album}\n{artist}\n\nRecorded after hours at {school}.\n\nThank you for listening.\n",
    "ja": "{album}\n{artist}\n\n{school}にて放課後に収録。\n\nご清聴ありがとうございました。\n",
}
COVER_NAME = {"en": "Cover", "ja": "カバー"}
NOTES_NAME = {"en": "Liner Notes", "ja": "ライナーノーツ"}


def track_file_name(number, title):
    return f"{number:02d} {title}.mp3"


def duration_seconds(album_key, number):
    return rng_for(f"{album_key}-{number}-length").randint(158, 312)


def encode_track(destination, tags, cover, seconds, cache_dir):
    """Writes the track to `destination`, from the cache when it has already been encoded."""
    fingerprint = hashlib.sha256(
        json.dumps(tags, sort_keys=True, ensure_ascii=False).encode() + cover + str(seconds).encode()
    ).hexdigest()[:24]
    cached = cache_dir / f"{fingerprint}.mp3"
    if not cached.exists():
        cover_path = cache_dir / f"{fingerprint}.jpg"
        cover_path.write_bytes(cover)
        metadata = []
        for key, value in tags.items():
            metadata += ["-metadata", f"{key}={value}"]
        subprocess.run([
            "ffmpeg", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"anullsrc=r=22050:cl=mono:d={seconds}",
            "-i", str(cover_path),
            "-map", "0:a", "-map", "1:v",
            "-c:a", "libmp3lame", "-b:a", "32k", "-c:v", "copy",
            "-id3v2_version", "3",
            "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)",
            *metadata,
            str(cached),
        ], check=True)
        cover_path.unlink()
    shutil.copyfile(cached, destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--language", choices=LANGUAGES, required=True)
    parser.add_argument("--documents", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path("/tmp/melodee-capture-tracks"))
    arguments = parser.parse_args()
    language = arguments.language
    documents = arguments.documents
    cache_dir = arguments.cache
    cache_dir.mkdir(parents=True, exist_ok=True)

    library = json.loads((SEED_DIR / "library.json").read_text())
    tracks_by_key = {}

    for school in library["schools"]:
        school_dir = documents / school["folder"][language]
        for album in school["albums"]:
            album_dir = school_dir / album["folder"][language]
            album_dir.mkdir(parents=True, exist_ok=True)
            cover = cover_jpeg(album["key"], album["hues"])
            for number, title in enumerate(album["tracks"], start=1):
                path = album_dir / track_file_name(number, title[language])
                tags = {
                    "title": title[language],
                    "artist": album["artist"][language],
                    "album_artist": album["artist"][language],
                    "album": album["folder"][language],
                    "genre": album["genre"][language],
                    "date": str(album["year"]),
                    "track": f"{number}/{len(album['tracks'])}",
                }
                encode_track(path, tags, cover, duration_seconds(album["key"], number), cache_dir)
                tracks_by_key[(album["key"], number)] = path
            extras = album.get("extras", [])
            if "cover" in extras:
                (album_dir / f"{COVER_NAME[language]}.jpg").write_bytes(cover)
            if "notes" in extras:
                (album_dir / f"{NOTES_NAME[language]}.txt").write_text(NOTES[language].format(
                    album=album["folder"][language],
                    artist=album["artist"][language],
                    school=school["folder"][language],
                ))

    for single in library["singles"]:
        source = tracks_by_key[(single["album"], single["track"])]
        shutil.copyfile(source, documents / source.name.split(" ", 1)[1])

    for playlist in library["playlists"]:
        name = playlist["name"][language]
        files = [
            {"relativePath": str(tracks_by_key[(album_key, number)].relative_to(documents))}
            for album_key, number in playlist["tracks"]
        ]
        (documents / f"{name}.mpl").write_text(
            json.dumps({"files": files, "name": name}, ensure_ascii=False, indent=2, sort_keys=True)
        )
    print(f"seeded {documents}", file=sys.stderr)


if __name__ == "__main__":
    main()
