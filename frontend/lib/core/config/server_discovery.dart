import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ServerDiscovery {
  const ServerDiscovery();

  Future<String?> find({required String preferredUrl}) async {
    final preferred = _normalize(preferredUrl);
    if (preferred != null && await _isBackend(preferred)) {
      return preferred;
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 350);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/health'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
            const Duration(milliseconds: 700),
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