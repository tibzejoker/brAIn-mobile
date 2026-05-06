/// Connection details parsed from a brAIn join URI of the form
/// `brain://join?url=<nats-url>&token=<token>`.
///
/// We accept both the explicit `brain://` scheme (what the dashboard's
/// QR code emits) and a bare `nats://` URL (manual entry fallback).
class ConnectionInfo {
  const ConnectionInfo({required this.url, this.token});

  final String url;
  final String? token;

  /// Returns null if the input cannot be interpreted as a connection.
  static ConnectionInfo? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // brain://join?url=<nats-url>&token=<token>
    if (trimmed.startsWith('brain://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      final url = uri.queryParameters['url'];
      if (url == null || url.isEmpty) return null;
      final token = uri.queryParameters['token'];
      return ConnectionInfo(
        url: url,
        token: (token == null || token.isEmpty) ? null : token,
      );
    }

    // Bare nats:// (or ws://) URL — manual entry path.
    if (trimmed.startsWith('nats://') ||
        trimmed.startsWith('ws://') ||
        trimmed.startsWith('wss://')) {
      return ConnectionInfo(url: trimmed);
    }

    return null;
  }

  String toJoinUri() {
    final params = <String, String>{'url': url};
    if (token != null && token!.isNotEmpty) params['token'] = token!;
    return Uri(
      scheme: 'brain',
      host: 'join',
      queryParameters: params,
    ).toString();
  }
}
