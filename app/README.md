# Oxford Dictionary (Flutter)

## Prerequisites

Place `oald10.db` in `app/assets/` before building:

```bash
# Option A: Copy from project root (after running build_db.py)
cp oald10.db app/assets/oald10.db

# Option B: Download from R2
curl -o app/assets/oald10.db \
  https://r2.deckionary.com/db/oald10.db
```

The file is ~93 MB and not checked into git. CI pulls it from R2 automatically.

Audio files are streamed from R2 on demand and cached locally. Use Settings > "Download all audio" for full offline use (~1.7 GB).

## Build & Run

```bash
cd app
flutter pub get
flutter run
```
