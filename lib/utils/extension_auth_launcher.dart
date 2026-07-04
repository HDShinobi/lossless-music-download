import 'package:url_launcher/url_launcher.dart';

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
      message.contains('precondition required');
}

/// Opens the pending browser-auth challenge for [extensionId], if any.
/// Returns true if a challenge was found and a browser was launched.
Future<bool> openPendingExtensionVerification(
  BackendBridge bridge,
  String extensionId,
) async {
  final normalizedId = extensionId.trim();
  if (normalizedId.isEmpty) return false;

  try {
    final pending = await bridge.getExtensionPendingAuth(normalizedId);
    final authUrl = pending?['auth_url']?.toString().trim() ?? '';
    if (authUrl.isEmpty) return false;

    final uri = Uri.tryParse(authUrl);
    if (uri == null) return false;

    var launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return launched;
  } catch (_) {
    return false;
  }
}
