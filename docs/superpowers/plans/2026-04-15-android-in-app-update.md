# Android Play Store In-App Update — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, use Google Play's In-App Updates API to notify users and trigger flexible updates, while keeping GitHub-based updates for macOS/iOS.

**Architecture:** Platform-switch in `_checkForUpdate()`. Android path uses `in_app_update` package (Play Core wrapper) for flexible updates. Non-Android path unchanged (GitHub Releases). Custom dialog for both paths, reusing "skip this version" logic via SettingsDao.

**Tech Stack:** `in_app_update` Flutter package, Play Core AppUpdateManager, Riverpod

---

### Task 1: Add `in_app_update` dependency

**Files:**
- Modify: `app/pubspec.yaml:40-41`

- [ ] **Step 1: Add the package**

In `app/pubspec.yaml`, add under the `# App update` comment section:

```yaml
  # App update
  package_info_plus: any
  url_launcher: any
  in_app_update: any
```

- [ ] **Step 2: Install**

Run: `cd app && flutter pub get`
Expected: resolves successfully, no version conflicts

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "deps: add in_app_update for Play Store updates"
```

---

### Task 2: Create Play Store update service

**Files:**
- Create: `app/lib/core/update/play_store_update_service.dart`

- [ ] **Step 1: Create the service file**

Create `app/lib/core/update/play_store_update_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Check Google Play Store for an available update.
/// Returns the [AppUpdateInfo] if a flexible update is available, null otherwise.
/// Fails silently — update checks should never block the app.
Future<AppUpdateInfo?> checkPlayStoreUpdate() async {
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.flexibleUpdateAllowed) {
      return info;
    }
    return null;
  } catch (e) {
    debugPrint('Play Store update check failed: $e');
    return null;
  }
}

/// Start a flexible update download, then complete the install when downloaded.
/// Returns true if the update was started successfully.
Future<bool> startFlexibleUpdate() async {
  try {
    final result = await InAppUpdate.startFlexibleUpdate();
    if (result == AppUpdateResult.success) {
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    }
    return false;
  } catch (e) {
    debugPrint('Flexible update failed: $e');
    return false;
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && flutter analyze --fatal-warnings`
Expected: no errors related to the new file

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/update/play_store_update_service.dart
git commit -m "feat: add Play Store update service for Android"
```

---

### Task 3: Wire Android update flow into `app.dart`

**Files:**
- Modify: `app/lib/app.dart`

This is the main task. We platform-switch `_checkForUpdate()` so Android uses Play Store while other platforms use GitHub. We add a new `_showPlayStoreUpdateDialog()` that prompts the user and triggers the flexible update on accept.

- [ ] **Step 1: Add imports**

In `app/lib/app.dart`, add after the existing update imports (lines 14-15):

```dart
import 'core/update/play_store_update_service.dart';
```

The file already imports `dart:io` (line 2), `update_provider.dart` (line 14), and `update_service.dart` (line 15).

- [ ] **Step 2: Replace `_checkForUpdate()` with platform-switched version**

In `app/lib/app.dart`, replace the existing `_checkForUpdate()` method (lines 92-103) with:

```dart
  void _checkForUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        await _checkPlayStoreUpdate();
      } else {
        await _checkGitHubUpdate();
      }
    });
  }

  Future<void> _checkGitHubUpdate() async {
    final info = await ref.read(updateInfoProvider.future);
    if (info == null || !mounted) return;

    final dao = ref.read(settingsDaoProvider);
    final skipped = await dao.getSkippedVersion();
    if (skipped == info.latestVersion) return;

    if (mounted) _showUpdateDialog(info);
  }

  Future<void> _checkPlayStoreUpdate() async {
    final updateInfo = await checkPlayStoreUpdate();
    if (updateInfo == null || !mounted) return;

    final versionCode = updateInfo.availableVersionCode?.toString();
    if (versionCode != null) {
      final dao = ref.read(settingsDaoProvider);
      final skipped = await dao.getSkippedVersion();
      if (skipped == versionCode) return;
    }

    if (mounted) _showPlayStoreUpdateDialog(versionCode);
  }
```

- [ ] **Step 3: Add `_showPlayStoreUpdateDialog()` method**

In `app/lib/app.dart`, add after `_showUpdateDialog()` (after line 160):

```dart
  void _showPlayStoreUpdateDialog(String? versionCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: const Text(
          'A new version is available on Google Play. '
          'Would you like to update now?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (versionCode != null) {
                ref
                    .read(settingsDaoProvider)
                    .setSkippedVersion(versionCode);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Skip this version'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              startFlexibleUpdate();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Verify it compiles**

Run: `cd app && flutter analyze --fatal-warnings`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add app/lib/app.dart
git commit -m "feat: use Play Store in-app updates on Android"
```

---

### Task 4: Manual testing checklist

This cannot be automated — the Play Core API only works when the app is installed from Google Play (including internal testing track).

- [ ] **Step 1: Build and upload a new version**

Bump version in `app/pubspec.yaml` (e.g. `0.1.2+3`), build AAB, upload to internal testing track.

- [ ] **Step 2: Install the PREVIOUS version from Play Store**

Make sure testers have the older version installed via Play Store internal testing.

- [ ] **Step 3: Wait for Play Store to propagate the new version**

Can take a few hours for internal testing.

- [ ] **Step 4: Open the app and verify the update dialog appears**

Expected: "A new version is available on Google Play" dialog shows.

- [ ] **Step 5: Test "Skip this version"**

Tap "Skip this version" → close and reopen app → dialog should NOT appear again.

- [ ] **Step 6: Clear skip and test "Update"**

Clear app data or wait for next version bump → tap "Update" → Play Store flexible update should start downloading.

- [ ] **Step 7: Verify update completes**

After download finishes, the app should restart with the new version.
