import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ServerDiscovery {
  const ServerDiscovery();

  Future<String?> find({
    required String preferredUrl,
    String? fallbackUrl,
  }) async {
    final preferred = _normalize(preferredUrl);
    if (preferred != null && await _isBackend(preferred)) {
      return preferred;
    }

    // A saved LAN address may be stale; try the configured (hosted) backend
    // before scanning the local subnet.
    final fallback = fallbackUrl == null ? null : _normalize(fallbackUrl);
    if (fallback != null && fallback != preferred && await _isBackend(fallback)) {
      return fallback;
    }

    final hosts = await _localSubnetHosts();
    for (var index = 0; index < hosts.length; index += 32) {
      final batch = hosts.skip(index).take(32);
      final results = await Future.wait(batch.map(_probeHost));
      for (final result in results) {
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  Future<String?> _probeHost(String host) async {
    final url = 'http://$host:8000';
    return await _isBackend(url) ? url : null;
  }

  Future<bool> _isBackend(String baseUrl) async {
    // LAN probes stay fast so the subnet scan finishes quickly. A hosted
    // backend needs room for TLS and a cold start (Render free instances
    // take up to about a minute to wake).
    final remote = !_isLanUrl(baseUrl);
    final client = HttpClient()
      ..connectionTimeout = remote
          ? const Duration(seconds: 15)
          : const Duration(milliseconds: 350);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/health'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
            remote
                ? const Duration(seconds: 75)
                : const Duration(milliseconds: 700),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return false;
      }
      final body = await response.transform(utf8.decoder).join();
      final payload = jsonDecode(body);
      return payload is Map<String, dynamic> &&
          payload['status']?.toString() == 'ok';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _localSubnetHosts() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    final hosts = <String>{};
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4 || parts.first == '127') {
          continue;
        }
        final prefix = parts.take(3).join('.');
        for (var lastOctet = 1; lastOctet < 255; lastOctet++) {
          final host = '$prefix.$lastOctet';
          if (host != address.address) {
            hosts.add(host);
          }
        }
      }
    }
    return hosts.toList();
  }

  static bool _isLanUrl(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    if (host == 'localhost') return true;
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.contains(null)) return false;
    final a = parts[0]!, b = parts[1]!;
    return a == 10 ||
        a == 127 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  String? _normalize(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        (uri.path != '' && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    return uri.replace(path: '').toString().replaceFirst(RegExp(r'/$'), '');
  }
}