import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// A single item's state as reported by the native download worker snapshot.
class NativeWorkerItemState {
  final String itemId;
  final String status;
  final double progress;
  final int bytesReceived;
  final int bytesTotal;
  final String? error;

  /// Extension that raised a verification_required error, as reported by the
  /// backend download result's `service` field. Null for other failures.
  final String? service;

  /// Service resolved during download, as populated by the native worker.
  /// Reflects the actual service that was used for the download.
  final String? resolvedService;

  const NativeWorkerItemState({
    required this.itemId,
    required this.status,
    required this.progress,
    required this.bytesReceived,
    required this.bytesTotal,
    this.error,
    this.service,
    this.resolvedService,
  });

  factory NativeWorkerItemState.fromJson(Map<String, dynamic> j) => NativeWorkerItemState(
        itemId: (j['item_id'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
        bytesReceived: (j['bytes_received'] as num?)?.toInt() ?? 0,
        bytesTotal: (j['bytes_total'] as num?)?.toInt() ?? 0,
        error: j['error']?.toString(),
        service: j['service']?.toString(),
        resolvedService: j['resolved_service']?.toString(),
      );
}

/// The full state of an in-progress (or just-finished) native worker run.
class NativeWorkerSnapshot {
  final String runId;
  final bool isRunning;
  final List<NativeWorkerItemState> items;

  const NativeWorkerSnapshot({
    required this.runId,
    required this.isRunning,
    required this.items,
  });

  factory NativeWorkerSnapshot.fromJson(Map<String, dynamic> j) => NativeWorkerSnapshot(
        runId: (j['run_id'] ?? '').toString(),
        isRunning: j['is_running'] == true,
        items: (j['items'] as List? ?? const [])
            .map((e) => NativeWorkerItemState.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Wraps a single item's identity + its already-built [DownloadRequest] JSON
/// into the envelope the native worker expects.
Map<String, dynamic> buildNativeWorkerRequest({
  required String itemId,
  required String trackName,
  required String artistName,
  required Map<String, dynamic> requestJson,
}) {
  return {
    'contract_version': 1,
    'item_id': itemId,
    'track_name': trackName,
    'artist_name': artistName,
    'request_json': jsonEncode(requestJson),
  };
}

/// Thin wrapper over the native (Kotlin) background download worker.
/// Only meaningful on Android; [isAvailable] is false everywhere else so
/// callers fall back to the existing Dart-only download path.
class NativeDownloadWorker {
  NativeDownloadWorker([MethodChannel? channel])
      : _c = channel ?? const MethodChannel('xyz.losslessmusic/native');
  final MethodChannel _c;

  bool get isAvailable => Platform.isAndroid;

  Future<void> start(List<Map<String, dynamic>> requests, {required String runId}) {
    return _c.invokeMethod('startNativeDownloadWorker', {
      'requestsJson': jsonEncode(requests),
      'settingsJson': jsonEncode({'run_id': runId}),
    });
  }

  Future<NativeWorkerSnapshot?> getSnapshot() async {
    final raw = await _c.invokeMethod<String>('getNativeDownloadWorkerSnapshot');
    if (raw == null || raw.isEmpty) return null;
    return NativeWorkerSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> stop() => _c.invokeMethod('stopNativeDownloadWorker');
}
