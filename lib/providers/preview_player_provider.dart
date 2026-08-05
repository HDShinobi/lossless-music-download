import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight in-list preview player: streams a short (~30s) `preview_url`
/// snippet so users can listen before downloading.
///
/// Adapted from SpotiFLAC-Mobile's `preview_player_provider`, stripped of its
/// coupling to a full background music player (this fork has none). It owns a
/// single [AudioPlayer]; only one preview is ever active at a time, and it
/// stops automatically when the app goes to the background.
enum PreviewStatus { idle, loading, playing, paused }

class PreviewPlayerState {
  final String? activeUrl;
  final PreviewStatus status;
  final Duration position;
  final Duration duration;

  const PreviewPlayerState({
    this.activeUrl,
    this.status = PreviewStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  bool get isActive => activeUrl != null && activeUrl!.isNotEmpty;

  bool isActiveUrl(String? url) =>
      url != null && url.isNotEmpty && url == activeUrl;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  PreviewPlayerState copyWith({
    String? activeUrl,
    bool clearActiveUrl = false,
    PreviewStatus? status,
    Duration? position,
    Duration? duration,
  }) {
    return PreviewPlayerState(
      activeUrl: clearActiveUrl ? null : (activeUrl ?? this.activeUrl),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class PreviewPlayerController extends Notifier<PreviewPlayerState> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  AppLifecycleListener? _lifecycleListener;

  @override
  PreviewPlayerState build() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleState,
    );
    ref.onDispose(_disposePlayer);
    return const PreviewPlayerState();
  }

  void _handleAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.detached) {
      if (state.isActive) {
        unawaited(stop());
      }
    }
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final player = AudioPlayer(playerId: 'preview-player');
    player.setReleaseMode(ReleaseMode.stop);
    _attachListeners(player);
    _player = player;
    return player;
  }

  void _attachListeners(AudioPlayer player) {
    _subscriptions.add(
      player.onPlayerStateChanged.listen(_handlePlayerStateChanged),
    );
    _subscriptions.add(
      player.onPositionChanged.listen((position) {
        if (state.status == PreviewStatus.playing ||
            state.status == PreviewStatus.paused) {
          state = state.copyWith(position: position);
        }
      }),
    );
    _subscriptions.add(
      player.onDurationChanged.listen((duration) {
        state = state.copyWith(duration: duration);
      }),
    );
    _subscriptions.add(
      player.onPlayerComplete.listen((_) {
        state = const PreviewPlayerState();
      }),
    );
  }

  void _discardActivePlayer() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        player.dispose();
      } catch (_) {}
    }
  }

  void _handlePlayerStateChanged(PlayerState playerState) {
    switch (playerState) {
      case PlayerState.playing:
        state = state.copyWith(status: PreviewStatus.playing);
        break;
      case PlayerState.paused:
        if (state.isActive) {
          state = state.copyWith(status: PreviewStatus.paused);
        }
        break;
      case PlayerState.stopped:
      case PlayerState.completed:
      case PlayerState.disposed:
        break;
    }
  }

  /// Toggle preview for [url]: start it, or pause/resume if it's already active.
  Future<void> toggle(String? url) async {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;

    if (state.isActiveUrl(trimmed)) {
      if (state.status == PreviewStatus.playing) {
        await pause();
      } else if (state.status == PreviewStatus.paused) {
        await resume();
      }
      return;
    }

    await play(trimmed);
  }

  Future<void> play(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    state = PreviewPlayerState(
      activeUrl: trimmed,
      status: PreviewStatus.loading,
    );

    try {
      await _playOnPlayer(_ensurePlayer(), trimmed);
    } catch (_) {
      // Recreate the player once and retry — audioplayers occasionally leaves
      // a wedged native player after an error.
      _discardActivePlayer();
      try {
        await _playOnPlayer(_ensurePlayer(), trimmed);
      } catch (_) {
        _discardActivePlayer();
        state = const PreviewPlayerState();
        rethrow;
      }
    }
  }

  Future<void> _playOnPlayer(AudioPlayer player, String url) async {
    await player.stop();
    await player.play(UrlSource(url));
  }

  Future<void> pause() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.pause();
      state = state.copyWith(status: PreviewStatus.paused);
    } catch (_) {}
  }

  Future<void> resume() async {
    final player = _player;
    if (player == null || !state.isActive) return;
    try {
      await player.resume();
      state = state.copyWith(status: PreviewStatus.playing);
    } catch (_) {}
  }

  Future<void> stop() async {
    final player = _player;
    if (player == null) {
      state = const PreviewPlayerState();
      return;
    }
    try {
      await player.stop();
    } catch (_) {}
    state = const PreviewPlayerState();
  }

  void _disposePlayer() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    _discardActivePlayer();
  }
}

final previewPlayerProvider =
    NotifierProvider<PreviewPlayerController, PreviewPlayerState>(
      PreviewPlayerController.new,
    );
