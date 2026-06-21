class DownloadProgress {
  final String itemId, status;
  final double progress; // 0..1
  final int bytesReceived;
  const DownloadProgress({required this.itemId, required this.status, required this.progress, required this.bytesReceived});
  factory DownloadProgress.fromJson(Map<String, dynamic> j) => DownloadProgress(
        itemId: (j['id'] ?? j['itemId'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        bytesReceived: (j['bytesReceived'] as num?)?.toInt() ?? 0,
      );
}
