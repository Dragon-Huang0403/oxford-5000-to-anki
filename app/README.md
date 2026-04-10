# Deckionary (Flutter)

See the [root README](../README.md) for full project documentation.

## Quick Start

```bash
# Ensure oald10.db is in assets/
cp ../oald10.db assets/oald10.db

flutter pub get
flutter run --dart-define-from-file=env.json
```

Without `env.json`, runs in local-only mode (no sync).

## macOS Quick Search

Press **Cmd+Shift+D** from any app to toggle the dictionary search window. Configure the hotkey and menu bar icon in Settings > Quick Search.

Requires macOS Accessibility permission (prompted automatically on first use).
