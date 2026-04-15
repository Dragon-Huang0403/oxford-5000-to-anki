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
