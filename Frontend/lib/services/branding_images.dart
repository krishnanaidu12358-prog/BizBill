import 'dart:typed_data';

import '../core/api_client.dart';

/// Loads a shop's logo / signature for printing and caches it in memory.
/// The URL carries a version (?v=...), so a new upload is fetched again.
class BrandingImages {
  BrandingImages._();

  /// Set once at start-up (main.dart) to the signed-in API client.
  static ApiClient? api;

  static final Map<String, Uint8List?> _cache = {};

  static Future<Uint8List?> load(String? url) async {
    if (url == null || url.isEmpty || api == null) return null;
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final bytes = await api!.getBytes(url);
      _cache[url] = bytes;
      return bytes;
    } catch (_) {
      // A missing logo must never stop a bill from printing.
      _cache[url] = null;
      return null;
    }
  }

  static void clear() => _cache.clear();
}
