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

/// Start a flexible update download and auto-install when complete.
/// Returns true if the download was started successfully.
Future<bool> startFlexibleUpdate() async {
  try {
    final result = await InAppUpdate.startFlexibleUpdate();
    if (result != AppUpdateResult.success) return false;

    InAppUpdate.installUpdateListener.listen(
      (status) {
        if (status == InstallStatus.downloaded) {
          InAppUpdate.completeFlexibleUpdate();
        }
      },
      onError: (e) => debugPrint('Update listener error: $e'),
    );
    return true;
  } catch (e) {
    debugPrint('Flexible update failed: $e');
    return false;
  }
}
