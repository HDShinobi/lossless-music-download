import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../providers/download_dir_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/onboarding_provider.dart';

/// First-launch onboarding: two setup steps, a download-source guide (the one
/// thing the app can't work without), then a short tour of the two features
/// unique to this app — spectral verify and DLNA cast.
///
/// The flow is advisory, not a hard gate: the source step deep-links to the
/// real Sources screen but the user can always finish and configure later.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _lastPage = 4; // 0..4 — five pages total

  final _controller = PageController();
  int _page = 0;

  bool _storageGranted = false;
  bool _notifGranted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStates();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // --- permission + folder wiring -------------------------------------------

  Future<void> _refreshPermissionStates() async {
    if (!Platform.isAndroid) {
      setState(() {
        _storageGranted = true;
        _notifGranted = true;
      });
      return;
    }
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final storage = sdk >= 30
        ? await Permission.manageExternalStorage.status
        : await Permission.storage.status;
    final notif = sdk >= 33
        ? await Permission.notification.status
        : PermissionStatus.granted;
    if (!mounted) return;
    setState(() {
      _storageGranted = storage.isGranted;
      _notifGranted = notif.isGranted;
    });
  }

  Future<void> _grantStorage() async {
    if (!Platform.isAndroid) {
      setState(() => _storageGranted = true);
      return;
    }
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permission =
        sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    setState(() => _storageGranted = status.isGranted);
  }

  Future<void> _enableNotifications() async {
    if (!Platform.isAndroid) {
      setState(() => _notifGranted = true);
      return;
    }
    final status = await Permission.notification.request();
    if (!mounted) return;
    setState(() => _notifGranted = status.isGranted);
  }

  Future<void> _pickFolder() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null || picked.isEmpty) return;
      final path = normalizePickedDirectory(picked);
      if (path == null) return;
      await ref.read(downloadDirControllerProvider.notifier).setDirectory(path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- navigation -----------------------------------------------------------

  void _next() {
    if (_page >= _lastPage) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _back() => _controller.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
    if (mounted) context.go(kPostOnboardingPath);
  }

  Future<void> _openSources() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
    if (mounted) context.go('/settings/sources');
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final isTour = _page >= 3; // verify + cast pages

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(cs, t, isTour),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _welcomePage(cs, t),
                  _preparePage(cs, t),
                  _sourcesPage(cs, t),
                  _verifyPage(cs, t),
                  _castPage(cs, t),
                ],
              ),
            ),
            _bottomBar(cs, t, isTour),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ColorScheme cs, AppLocalizations t, bool isTour) {
    Widget trailing;
    if (_page <= 1) {
      final progress = (_page + 1) / 2;
      trailing = SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
              strokeCap: StrokeCap.round,
            ),
            Center(
              child: Text(
                '${_page + 1}/2',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (isTour) {
      trailing = TextButton(
        onPressed: _finish,
        child: Text(t.onbSkip),
      );
    } else {
      trailing = const SizedBox(width: 44, height: 44);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_page > 0)
            IconButton.filledTonal(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back),
              style: IconButton.styleFrom(
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurfaceVariant,
              ),
            )
          else
            const SizedBox(width: 44, height: 44),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs, AppLocalizations t, bool isTour) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTour) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(2, (i) {
                final active = (_page - 3) == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: active ? 26 : 8,
                  decoration: BoxDecoration(
                    color: active
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _busy ? null : _next,
              child: Text(
                _page == _lastPage ? t.onbGetStarted : t.onbNext,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- pages ----------------------------------------------------------------

  Widget _pageShell({required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _iconCircle(ColorScheme cs, IconData icon, {bool soft = false}) {
    return Center(
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: soft
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 38, color: cs.primary),
      ),
    );
  }

  Widget _title(ColorScheme cs, String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
        ),
      );

  Widget _desc(ColorScheme cs, String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurfaceVariant),
      );

  Widget _welcomePage(ColorScheme cs, AppLocalizations t) {
    final locale = ref.watch(localeProvider).languageCode;
    return _pageShell(
      children: [
        const SizedBox(height: 24),
        Center(
          child: Icon(Icons.graphic_eq_rounded, size: 88, color: cs.primary),
        ),
        const SizedBox(height: 24),
        Text(
          t.appTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        _desc(cs, t.onbWelcomeSubtitle),
        const SizedBox(height: 28),
        _LanguageSegment(
          selected: locale,
          onSelect: (code) =>
              ref.read(localeProvider.notifier).set(Locale(code)),
        ),
      ],
    );
  }

  Widget _preparePage(ColorScheme cs, AppLocalizations t) {
    final folderAsync = ref.watch(downloadDirProvider);
    final folder = folderAsync.value;
    return _pageShell(
      children: [
        const SizedBox(height: 12),
        _iconCircle(cs, Icons.lock_open_rounded),
        const SizedBox(height: 20),
        _title(cs, t.onbPrepTitle),
        const SizedBox(height: 10),
        _desc(cs, t.onbPrepDesc),
        const SizedBox(height: 24),
        _PrepRow(
          icon: Icons.folder_rounded,
          title: t.onbPermStorage,
          subtitle: t.onbPermStorageDesc,
          done: _storageGranted,
          actionLabel: t.onbGrant,
          onAction: _grantStorage,
        ),
        const SizedBox(height: 10),
        _PrepRow(
          icon: Icons.notifications_rounded,
          title: t.onbPermNotif,
          subtitle: t.onbPermNotifDesc,
          done: _notifGranted,
          actionLabel: t.onbEnable,
          onAction: _enableNotifications,
        ),
        const SizedBox(height: 10),
        _PrepRow(
          icon: Icons.create_new_folder_rounded,
          title: t.onbFolder,
          subtitle: folder ?? '—',
          done: false,
          actionLabel: folder == null ? t.onbChoose : t.onbChange,
          onAction: _pickFolder,
        ),
      ],
    );
  }

  Widget _sourcesPage(ColorScheme cs, AppLocalizations t) {
    return _pageShell(
      children: [
        const SizedBox(height: 12),
        _iconCircle(cs, Icons.extension_rounded, soft: true),
        const SizedBox(height: 20),
        _title(cs, t.onbSourcesTitle),
        const SizedBox(height: 10),
        _desc(cs, t.onbSourcesDesc),
        const SizedBox(height: 20),
        _StepRow(cs, 1, t.onbSourcesStep1),
        _StepRow(cs, 2, t.onbSourcesStep2),
        _StepRow(cs, 3, t.onbSourcesStep3),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: cs.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.onbSourcesWarn,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _openSources,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(t.onbSourcesOpen),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _verifyPage(ColorScheme cs, AppLocalizations t) {
    return _pageShell(
      children: [
        const SizedBox(height: 12),
        _iconCircle(cs, Icons.verified_rounded, soft: true),
        const SizedBox(height: 20),
        _title(cs, t.onbVerifyTitle),
        const SizedBox(height: 10),
        _desc(cs, t.onbVerifyDesc),
        const SizedBox(height: 24),
        const _SpectrogramDemo(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.verdictLossless,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.onbVerifyVerdictSub,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _castPage(ColorScheme cs, AppLocalizations t) {
    return _pageShell(
      children: [
        const SizedBox(height: 12),
        _iconCircle(cs, Icons.cast_rounded, soft: true),
        const SizedBox(height: 20),
        _title(cs, t.onbCastTitle),
        const SizedBox(height: 10),
        _desc(cs, t.onbCastDesc),
        const SizedBox(height: 24),
        _CastRow(
          icon: Icons.tv_rounded,
          name: t.onbCastExampleTv,
          playingLabel: t.onbCastPlaying,
        ),
        const SizedBox(height: 10),
        _CastRow(icon: Icons.speaker_rounded, name: t.onbCastExampleSpeaker),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.celebration_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.onbReady,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _LanguageSegment extends StatelessWidget {
  const _LanguageSegment({required this.selected, required this.onSelect});

  final String selected;
  final void Function(String code) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // System default is intentionally omitted: the app persists a concrete
    // locale (vi/en), so onboarding offers the two shipped languages directly.
    const options = [('en', 'English'), ('vi', 'Tiếng Việt')];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final (code, label) in options)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelect(code),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected == code
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected == code
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrepRow extends StatelessWidget {
  const _PrepRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (done)
            Icon(Icons.check_circle_rounded, color: cs.primary)
          else
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 38),
              ),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow(this.cs, this.n, this.text);
  final ColorScheme cs;
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.icon, required this.name, this.playingLabel});

  final IconData icon;
  final String name;
  final String? playingLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = playingLabel != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(13),
        border: active ? Border.all(color: cs.primary) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: active ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                playingLabel!,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A static spectrogram illustration: bars tapering off toward the high end,
/// with a dashed line marking the ~22 kHz ceiling of genuine lossless.
class _SpectrogramDemo extends StatelessWidget {
  const _SpectrogramDemo();

  @override
  Widget build(BuildContext context) {
    const heights = [
      0.96, 0.88, 0.92, 0.80, 0.85, 0.72, 0.78, 0.66, 0.70,
      0.58, 0.63, 0.52, 0.60, 0.48, 0.55, 0.44, 0.50, 0.40,
    ];
    return Container(
      height: 92,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF0B1F14), Color(0xFF04150C)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in heights)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FractionallySizedBox(
                  heightFactor: h,
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(2)),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF1DB954), Color(0xFF7CFFB0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
