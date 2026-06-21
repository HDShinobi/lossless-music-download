class DownloadProgress {
  final String itemId, status;
  final double progress; // 0..1
  final int bytesReceived;
  const DownloadProgress({required this.itemId, required this.status, required this.progress, required this.bytesReceived});
  factory DownloadProgress.fromJson(Map<String, dynamic> j) => DownloadProgress(
        itemId: (j['item_id'] ?? j['id'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        bytesReceived: (j['bytes_received'] as num?)?.toInt() ?? 0,
      );
}
