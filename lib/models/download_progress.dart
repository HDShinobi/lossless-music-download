class DownloadProgress {
  final String itemId, status;
  final double progress; // 0..1
  final int bytesReceived;
  final int bytesTotal;
  final double speedMBps;
  const DownloadProgress({
    required this.itemId,
    required this.status,
    required this.progress,
    required this.bytesReceived,
    this.bytesTotal = 0,
    this.speedMBps = 0,
  });
  factory DownloadProgress.fromJson(Map<String, dynamic> j) => DownloadProgress(
        itemId: (j['item_id'] ?? j['id'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        bytesReceived: (j['bytes_received'] as num?)?.toInt() ?? 0,
        bytesTotal: (j['bytes_total'] as num?)?.toInt() ?? 0,
        speedMBps: (j['speed_mbps'] as num?)?.toDouble() ?? 0,
      );
}
