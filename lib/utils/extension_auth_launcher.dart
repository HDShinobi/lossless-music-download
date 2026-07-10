import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/backend_bridge.dart';

/// Detects the "needs browser verification" family of errors extensions
/// raise when a signed-session challenge hasn't been completed yet (see
/// go_backend/extension_signed_session.go).
bool isExtensionVerificationRequired(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('verify_required') ||
      message.contains('verification_required') ||
      message.contains('verification required') ||
      message.contains('needsverification') ||
      message.contains('needs verification') ||
      message.contains('session is not authenticated') ||
      message.contains('unauthorized') ||
      message.contains('precondition required') ||
      _containsHttpStatusCode(message, '401') ||
      _containsHttpStatusCode(message, '428');
}

/// Matches an HTTP status [code] embedded in a lowercased error [message]
/// without misfiring on unrelated numbers (e.g. "downloaded 401 bytes").
/// Mirrors upstream SpotiFLAC's detection so a session that failed server-side
/// with a bare `HTTP 401`/`428` still opens the verification challenge.
bool _containsHttpStatusCode(String message, String code) {
  return message.contains('http $code') ||
      message.contains('http status $code') ||
      message.contains('status $code') ||
      message.contains('$code for ') ||
      message.contains('$code:') ||
      message.contains('$code;');
}

/// Opens the pending browser-auth challenge for [extensionId], if any.
/// Returns true if a challenge was found and a browser was launched.
///
/// [onAuthUri] is invoked with the resolved challenge URL before launching, so
/// the caller can surface a manual fallback (copy-link help dialog) when the
/// browser can't be opened — the URL is only known here.
Future<bool> openPendingExtensionVerification(
  BackendBridge bridge,
  String extensionId, {
  void Function(Uri authUri)? onAuthUri,
}) async {
  final normalizedId = extensionId.trim();
  if (normalizedId.isEmpty) return false;

  try {
    final pending = await bridge.getExtensionPendingAuth(normalizedId);
    final authUrl = pending?['auth_url']?.toString().trim() ?? '';
    if (authUrl.isEmpty) return false;

    final uri = Uri.tryParse(authUrl);
    if (uri == null) return false;
    onAuthUri?.call(uri);

    return _launchVerificationUrl(uri);
  } catch (_) {
    return false;
  }
}

/// Tries the in-app browser first, then an external app. Returns whether a
/// browser was launched.
Future<bool> _launchVerificationUrl(Uri uri) async {
  var launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!launched) {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return launched;
}

/// Shows a dialog with the verification [authUri] so the user can complete the
/// signed-session challenge manually — copying the link or retrying the
/// browser. Used as a fallback when the automatic launch fails
/// ([immediateFailure]) and as a nudge when verification is taking a while.
/// Mirrors upstream SpotiFLAC's showExtensionVerificationHelpDialog.
Future<void> showExtensionVerificationHelpDialog(
  BuildContext context,
  Uri authUri, {
  bool immediateFailure = false,
}) {
  final t = AppLocalizations.of(context);
  final title = immediateFailure
      ? t.extensionVerificationHelpTitleManual
      : t.extensionVerificationHelpTitleWaiting;
  final message = immediateFailure
      ? t.extensionVerificationHelpMessageManual
      : t.extensionVerificationHelpMessageWaiting;

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final dialogT = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  authUri.toString(),
                  maxLines: 4,
                  minLines: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogT.extensionVerificationClose),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: Text(dialogT.extensionVerificationCopyLink),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: authUri.toString()));
              ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                SnackBar(
                  content: Text(dialogT.extensionVerificationLinkCopied),
                ),
              );
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: Text(dialogT.extensionVerificationOpenBrowser),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_launchVerificationUrl(authUri));
            },
          ),
        ],
      );
    },
  );
}
