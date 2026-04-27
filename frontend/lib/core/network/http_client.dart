import 'api_client.dart';

// Compatibility shim for legacy imports if needed later.
class HttpClient extends ApiClient {
  HttpClient({required String baseUrl, required super.tokenStore})
      : super(baseUrl: baseUrl);
}
