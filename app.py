#!/usr/bin/env python3
"""
Flask API server for the OALD10 dictionary app.

Serves dictionary data, audio files, and batch audio manifests.

Usage:
    python app.py                  # start on port 8000
    python app.py --port 8080      # custom port
"""

import argparse

from flask import Flask, jsonify, render_template, request, Response

from db.query import connect, fuzzy_lookup, get_audio, search

app = Flask(__name__)

DB_PATH = "oald10.db"


def get_db():
    return connect(DB_PATH)


@app.after_request
def add_cors(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET'
    return response


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/search")
def api_search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify([])

    db = get_db()
    entries = fuzzy_lookup(db, q)
    if not entries:
        entries = search(db, f"{q}*", limit=20)

    results = []
    for e in entries:
        groups = []
        for g in e.groups:
            senses = []
            for s in g.senses:
                examples = []
                for ex in s.examples:
                    examples.append({
                        "text_plain": ex.text_plain,
                        "text_html": ex.text_html,
                        "text_zh": ex.text_zh,
                        "audio_gb": ex.audio_gb,
                        "audio_us": ex.audio_us,
                    })
                senses.append({
                    "sense_num": s.sense_num,
                    "cefr_level": s.cefr_level,
                    "grammar": s.grammar,
                    "labels": s.labels,
                    "variants": s.variants,
                    "definition": s.definition,
                    "definition_zh": s.definition_zh,
                    "examples": examples,
                    "xrefs": [
                        {"xref_type": x.xref_type, "target_word": x.target_word}
                        for x in s.xrefs
                    ],
                })
            groups.append({
                "topic_en": g.topic_en,
                "topic_zh": g.topic_zh,
                "senses": senses,
                "xrefs": [
                    {"xref_type": x.xref_type, "target_word": x.target_word}
                    for x in g.xrefs
                ],
            })

        verb_forms = [
            {
                "form_label": vf.form_label,
                "form_text": vf.form_text,
                "audio_gb": vf.audio_gb,
                "audio_us": vf.audio_us,
            }
            for vf in e.verb_forms
        ]

        results.append({
            "headword": e.headword,
            "pos": e.pos,
            "ipa_gb": e.ipa_gb,
            "ipa_us": e.ipa_us,
            "audio_gb": e.audio_gb,
            "audio_us": e.audio_us,
            "cefr_level": e.cefr_level,
            "ox3000": e.ox3000,
            "ox5000": e.ox5000,
            "groups": groups,
            "verb_forms": verb_forms,
            "card_type": e.card_type,
            "synonyms": [
                {"word": s.word, "group_title": s.group_title, "definition": s.definition}
                for s in e.synonyms
            ],
            "word_origin": e.word_origin,
            "word_origin_html": e.word_origin_html,
            "word_family": [
                {"word": wf.word, "pos": wf.pos, "opposite": wf.opposite}
                for wf in e.word_family
            ],
            "collocations": [
                {"category": c.category, "words": c.words}
                for c in e.collocations
            ],
            "xrefs": [
                {"xref_type": x.xref_type, "target_word": x.target_word}
                for x in e.xrefs
            ],
            "phrasal_verbs": e.phrasal_verbs,
            "extra_examples": [
                {"text_plain": ex.text_plain, "text_html": ex.text_html, "text_zh": ex.text_zh}
                for ex in e.extra_examples
            ],
        })

    db.close()
    return jsonify(results)


@app.route("/api/audio/<path:filename>")
def api_audio(filename):
    db = get_db()
    data = get_audio(db, filename)
    db.close()
    if data is None:
        return Response("Not found", status=404)
    return Response(data, mimetype="audio/mpeg",
                    headers={"Cache-Control": "public, max-age=31536000"})


@app.route("/api/audio-manifest/<word_set>")
def api_audio_manifest(word_set):
    """Return list of audio filenames for a word set.

    word_set: 'all', 'ox3000', 'ox5000'
    query params: type=word|sentence|both (default: both)
    """
    audio_type = request.args.get("type", "both")
    db = get_db()

    # Build entry filter
    if word_set == "ox3000":
        condition = "WHERE ox3000 = 1"
    elif word_set == "ox5000":
        condition = "WHERE ox5000 = 1 OR ox3000 = 1"
    elif word_set == "all":
        condition = ""
    else:
        db.close()
        return jsonify({"error": f"Unknown word set: {word_set}"}), 400

    raw = db  # already a sqlite3.Connection

    # Collect audio filenames
    files = set()

    if audio_type in ("word", "both"):
        # Word pronunciations
        rows = raw.execute(f"""
            SELECT DISTINCT p.audio_file FROM pronunciations p
            JOIN entries e ON p.entry_id = e.id
            {condition} AND p.audio_file != ''
        """).fetchall()
        files.update(r[0] for r in rows)

        # Verb form audio
        rows = raw.execute(f"""
            SELECT DISTINCT vf.audio_gb, vf.audio_us FROM verb_forms vf
            JOIN entries e ON vf.entry_id = e.id
            {condition}
        """).fetchall()
        for r in rows:
            if r[0]: files.add(r[0])
            if r[1]: files.add(r[1])

    if audio_type in ("sentence", "both"):
        # Example audio
        rows = raw.execute(f"""
            SELECT DISTINCT ex.audio_gb, ex.audio_us FROM examples ex
            JOIN senses s ON ex.sense_id = s.id
            JOIN entries e ON s.entry_id = e.id
            {condition}
        """).fetchall()
        for r in rows:
            if r[0]: files.add(r[0])
            if r[1]: files.add(r[1])

    # Get sizes
    manifest = []
    for filename in sorted(files):
        row = raw.execute(
            "SELECT LENGTH(data) FROM audio_files WHERE filename = ?",
            (filename,),
        ).fetchone()
        if row:
            manifest.append({"filename": filename, "size": row[0]})

    total_size = sum(f["size"] for f in manifest)
    db.close()

    return jsonify({
        "word_set": word_set,
        "audio_type": audio_type,
        "file_count": len(manifest),
        "total_size_bytes": total_size,
        "total_size_mb": round(total_size / (1024 * 1024), 1),
        "files": manifest,
    })


@app.route("/api/audio-batch")
def api_audio_batch():
    """Stream audio files as a tar archive.

    Query params:
      offset: start index (default 0)
      limit: number of files (default 5000)

    Client calls this in chunks to download all audio progressively.
    """
    import io
    import tarfile

    offset = int(request.args.get("offset", 0))
    limit = int(request.args.get("limit", 5000))

    db = get_db()
    rows = db.execute(
        "SELECT filename, data FROM audio_files ORDER BY filename LIMIT ? OFFSET ?",
        (limit, offset),
    ).fetchall()
    total = db.execute("SELECT COUNT(*) FROM audio_files").fetchone()[0]
    db.close()

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w') as tar:
        for row in rows:
            filename = row['filename']
            data = row['data']
            info = tarfile.TarInfo(name=filename)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))

    buf.seek(0)
    return Response(
        buf.getvalue(),
        mimetype="application/x-tar",
        headers={
            "X-Total-Files": str(total),
            "X-Offset": str(offset),
            "X-Limit": str(limit),
            "X-Batch-Count": str(len(rows)),
        },
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    app.run(host="0.0.0.0", port=args.port, debug=args.debug)
