#!/usr/bin/env python3
"""Export raw HTML and audio filelist from Body.data for Cloudflare R2 upload."""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from db.importer import _build_index, _read_entry_at, BODY
from db.models import EntryData
from db.parser import parse_entry


def _collect_audio(entry: EntryData) -> set[str]:
    """Collect all audio filenames referenced by an entry."""
    files = set()
    if entry.audio_gb:
        files.add(entry.audio_gb)
    if entry.audio_us:
        files.add(entry.audio_us)
    for vf in entry.verb_forms:
        if vf.audio_gb:
            files.add(vf.audio_gb)
        if vf.audio_us:
            files.add(vf.audio_us)
    for g in entry.groups:
        for s in g.senses:
            for ex in s.examples:
                if ex.audio_gb:
                    files.add(ex.audio_gb)
                if ex.audio_us:
                    files.add(ex.audio_us)
    return files

EXPORT_DIR = Path("export")
HTML_DIR = EXPORT_DIR / "html"


def sanitize_filename(text: str) -> str:
    return re.sub(r'[^a-z0-9]+', '_', text.lower()).strip('_') or "unknown"


def main():
    HTML_DIR.mkdir(parents=True, exist_ok=True)

    print("Loading Body.data...", file=sys.stderr)
    body_data = BODY.read_bytes()

    print("Building word index...", file=sys.stderr)
    index = _build_index(body_data)
    print(f"  {len(index)} headwords found", file=sys.stderr)

    print("Exporting HTML files...", file=sys.stderr)
    all_audio_files: set[str] = set()
    used_filenames: set[str] = set()
    total_entries = 0
    failed = []

    for i, title in enumerate(sorted(index.keys())):
        if i % 1000 == 0 and i > 0:
            print(f"  {i}/{len(index)} headwords processed...", file=sys.stderr)

        try:
            html = _read_entry_at(body_data, index[title])
            entries = parse_entry(html)

            for entry_index, (entry, raw_html) in enumerate(entries):
                name = sanitize_filename(entry.headword)
                pos = sanitize_filename(entry.pos) if entry.pos else "none"
                filename = f"{name}__{pos}__{entry_index}.html"

                # Handle unlikely collisions
                if filename in used_filenames:
                    counter = 1
                    while f"{name}__{pos}__{entry_index}_{counter}.html" in used_filenames:
                        counter += 1
                    filename = f"{name}__{pos}__{entry_index}_{counter}.html"

                used_filenames.add(filename)
                (HTML_DIR / filename).write_text(raw_html, encoding="utf-8")

                all_audio_files |= _collect_audio(entry)
                total_entries += 1

        except Exception as e:
            failed.append((title, str(e)))

    # Write audio filelist (one filename per line, for rclone --files-from)
    audio_list = sorted(all_audio_files)
    (EXPORT_DIR / "audio_filelist.txt").write_text(
        "\n".join(audio_list) + "\n", encoding="utf-8"
    )

    print(f"\nExport complete:", file=sys.stderr)
    print(f"  HTML files:  {total_entries}", file=sys.stderr)
    print(f"  Audio files: {len(audio_list)}", file=sys.stderr)
    if failed:
        print(f"  Failed:      {len(failed)}", file=sys.stderr)
        for word, err in failed[:10]:
            print(f"    {word}: {err}", file=sys.stderr)


if __name__ == "__main__":
    main()
