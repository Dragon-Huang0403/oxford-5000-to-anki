# Deckionary

A dictionary app powered by the **Oxford Advanced Learner's Dictionary (OALD10)** with FSRS spaced repetition, global quick search, and cross-device sync. Built with Flutter.

## Features

**Dictionary**
- Multi-tier search: exact match, variant spelling, suffix stripping, prefix autocomplete, fuzzy typo tolerance
- Full entries with pronunciations, verb forms, sense groups, examples, synonyms, word families, collocations, cross-references, phrasal verbs
- Oxford 3000/5000 and CEFR level indicators
- Search history with navigation back/forward

**Spaced Repetition (FSRS)**
- FSRS-4.5 scheduler with 4-level rating
- Configurable daily limits for new cards and reviews
- Auto-pronounce during review

**Audio**
- US/GB pronunciation playback from CDN
- Full offline audio download (~1.7 GB) cached in SQLite

**Quick Search (macOS)**
- Global hotkey (default Cmd+Shift+D, configurable) to show/hide from any app or desktop
- Clipboard auto-search: copies a word then press the hotkey
- Window appears on whichever desktop/display the mouse cursor is on
- Optional menu bar tray icon

**Sync**
- Google Sign-in via Firebase + Supabase
- Search history, review cards, and review logs sync across devices
- Works offline — syncs when connectivity resumes

**Platforms:** macOS, iOS, Android

## Prerequisites

Place `oald10.db` in `app/assets/` before building:

```bash
# Option A: Copy from project root (after running build_db.py)
cp oald10.db app/assets/oald10.db

# Option B: Download from R2
curl -o app/assets/oald10.db \
  https://r2.deckionary.com/db/oald10.db
```

The file is ~93 MB and not checked into git.

## Build & Run

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env.json
```

Without `env.json`, the app runs in local-only mode (no sync).

## Firebase & Supabase Setup

Required only for cross-device sync.

### Firebase

```bash
dart pub global activate flutterfire_cli
cd app
flutterfire configure
```

This generates `lib/firebase_options.dart` (gitignored). Enable **Authentication > Google** in the [Firebase Console](https://console.firebase.google.com).

### Google Sign-In (macOS)

Create an **iOS OAuth client ID** in [Google Cloud Console > Credentials](https://console.cloud.google.com/apis/credentials) with bundle ID `com.deckionary.deckionary`. Add the client ID to `macos/Runner/Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

### Supabase

```bash
cp env.example.json env.json
```

Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from **Supabase Dashboard > Settings > API**.

Enable **Firebase** as a third-party auth provider in **Supabase Dashboard > Auth > Third-party providers**.

Apply migrations:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

### macOS Signing

```bash
open macos/Runner.xcodeproj
```

In Xcode: **Runner target > Signing & Capabilities > Automatically manage signing > select Team**. Same for **RunnerTests**.

## Python Tools

The repo also includes Python tools for building the dictionary database, generating Anki decks, and exporting audio to Cloudflare R2.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install genanki flask opencc-python-reimplemented

python build_db.py          # Build oald10.db from macOS dictionary bundle
python app.py --port 8000   # Web dictionary browser
python anki/create_deck.py --5000  # Generate Anki deck
```

See `docs/` for detailed guides on the database schema, R2 export, and Anki generation.

## Project Structure

```
app/                    # Flutter app
  lib/
    features/
      dictionary/       # Search, autocomplete, entry display
      review/           # FSRS spaced repetition
      settings/         # App configuration
    core/
      database/         # Drift ORM, DAOs
      audio/            # Pronunciation playback & caching
      sync/             # Supabase sync service
  macos/                # macOS-specific (hotkey, tray, window)
  ios/                  # iOS target
  android/              # Android target

db/                     # Python: SQLite schema, parser, importer
anki/                   # Python: Anki deck generator
scripts/                # Python: R2 export & upload
docs/                   # Guides
```
