class ServerStatus {
  final bool running;
  final String? url;
  final String? name;
  const ServerStatus({required this.running, this.url, this.name});
  factory ServerStatus.fromJson(Map<String, dynamic> j) => ServerStatus(
        running: j['running'] as bool? ?? false,
        url: j['url'] as String?,
        name: j['name'] as String?,
      );
  static const stopped = ServerStatus(running: false);
}
