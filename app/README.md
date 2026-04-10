# Deckionary (Flutter)

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

## Firebase & Supabase Setup

Firebase and Supabase are required for cross-device sync (optional for local-only use).

### 1. Firebase

```bash
dart pub global activate flutterfire_cli
cd app
flutterfire configure
```

This generates `lib/firebase_options.dart` (gitignored). Re-run after adding platforms or changing the Firebase project.

Enable **Authentication > Google** in the [Firebase Console](https://console.firebase.google.com).

### 3. Google Sign-In (macOS)

Create an **iOS OAuth client ID** in [Google Cloud Console > Credentials](https://console.cloud.google.com/apis/credentials) with bundle ID `com.deckionary.deckionary`. Then add the client ID to `macos/Runner/Info.plist`:

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

### 4. macOS Signing

Open the Xcode project and enable development signing:

```bash
cd app
open macos/Runner.xcodeproj
```

In Xcode: **Runner target > Signing & Capabilities > check "Automatically manage signing" > select your Team**. Do the same for the **RunnerTests** target.

### 2. Supabase

Copy the example env file and fill in your project values:

```bash
cp env.example.json env.json
```

Get `SUPABASE_URL` and `SUPABASE_ANON_KEY` from **Supabase Dashboard > Settings > API**.

Enable **Firebase** as a third-party auth provider in **Supabase Dashboard > Auth > Third-party providers** (provide your Firebase project ID).

Apply database migrations:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

## Build & Run

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env.json
```

Without `env.json`, the app runs in local-only mode (no sync).
