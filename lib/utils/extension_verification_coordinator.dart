import 'dart:async';

import '../providers/download_queue_provider.dart';
import 'extension_auth_launcher.dart';

/// The extension whose signed-session challenge must be completed for [entry]
/// to succeed: the backend-reported service when present (the error may come
/// from a fallback provider such as qobuz-web), else the chosen source.
/// Null when the failure is not a verification error.
String? verificationTargetFor(DownloadEntry entry) {
  if (!isExtensionVerificationRequired(entry.error ?? '')) return null;
  final target = (entry.verificationService ?? entry.service)?.trim() ?? '';
  return target.isEmpty ? null : target;
}

/// Coordinates browser-based signed-session verification for the download
/// queue (see go_backend/extension_signed_session.go for the flow): opens the
/// challenge for newly-failed items, keeps one challenge per extension at a
/// time, unblocks abandoned challenges after [timeout], and re-enqueues the
/// affected downloads once a grant arrives — mirroring upstream SpotiFLAC's
/// _handleVerificationRequiredDownload/_openVerificationAndWait.
class ExtensionVerificationCoordinator {
  ExtensionVerificationCoordinator({
    required this.openVerification,
    required this.retryItem,
    this.timeout = const Duration(minutes: 5),
  });

  /// Opens the pending browser challenge; returns whether a browser launched.
  final Future<bool> Function(String extensionId) openVerification;

  /// Re-enqueues a failed queue item by its id.
  final void Function(String itemId) retryItem;

  /// How long an opened challenge blocks re-opening while no grant arrives
  /// (matches the server-side challenge expiry).
  final Duration timeout;

  final Map<String, Timer> _pendingByExtension = {};

  // '<trackId>::<extensionId>' pairs already auto-retried once. A retried
  // item that fails verification again is left failed instead of looping
  // browser → grant → retry forever (upstream's _verificationRetriedItemIds).
  final Set<String> _autoRetried = {};

  /// Watches queue transitions; a newly-failed verification error opens the
  /// challenge for its extension unless one is already pending.
  void onQueueChanged(List<DownloadEntry>? previous, List<DownloadEntry> next) {
    final previousById = {
      for (final e in previous ?? const <DownloadEntry>[]) e.itemId: e
    };
    for (final entry in next) {
      // A completed download re-arms the once-per-session guard for its track,
      // so a later session expiry can verify + auto-retry the same track again.
      // Safe against loops: success never re-triggers verification, and a
      // download stuck in a failing verify loop never reaches 'done'.
      if (entry.status == 'done' &&
          previousById[entry.itemId]?.status != 'done') {
        _autoRetried.removeWhere((key) => key.startsWith('${entry.track.id}::'));
        continue;
      }
      if (entry.status != 'failed') continue;
      if (previousById[entry.itemId]?.status == 'failed') continue;
      final target = verificationTargetFor(entry);
      if (target == null) continue;
      if (_pendingByExtension.containsKey(target)) continue;
      _pendingByExtension[target] =
          Timer(timeout, () => _pendingByExtension.remove(target));
      unawaited(_open(target));
    }
  }

  /// Handles a completed spotiflac://session-grant exchange. On success,
  /// re-enqueues EVERY failed item once (per track).
  ///
  /// A batch (album/playlist) fires its availability checks against the shared
  /// signed session while it's still being verified: one track surfaces as a
  /// verify error (opening the challenge), but the rest fail with a transient
  /// error (e.g. "checkAvailability failed"). Retrying only the verify-error
  /// item left the rest of the album stuck until a manual retry (which then
  /// succeeds). Since a successful grant means the session is now valid, we
  /// re-drive all failed items — auto-fallback lands each on a working source.
  void onGrantCompleted(
    String extensionId,
    bool success,
    List<DownloadEntry> entries,
  ) {
    _clearPending(extensionId);
    if (!success) return;
    for (final entry in entries) {
      if (entry.status != 'failed') continue;
      if (!_autoRetried.add('${entry.track.id}::$extensionId')) continue;
      retryItem(entry.itemId);
    }
  }

  void dispose() {
    for (final timer in _pendingByExtension.values) {
      timer.cancel();
    }
    _pendingByExtension.clear();
  }

  Future<void> _open(String extensionId) async {
    var opened = false;
    try {
      opened = await openVerification(extensionId);
    } finally {
      if (!opened) _clearPending(extensionId);
    }
  }

  void _clearPending(String extensionId) {
    _pendingByExtension.remove(extensionId)?.cancel();
  }
}
