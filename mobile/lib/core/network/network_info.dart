import 'package:connectivity_plus/connectivity_plus.dart';

/// Kiểm tra trạng thái kết nối — dùng ở repository để quyết định
/// gọi remote hay đọc cache (offline-first).
abstract class NetworkInfo {
  Future<bool> get isOnline;
}

class NetworkInfoImpl implements NetworkInfo {
  final Connectivity _connectivity;
  NetworkInfoImpl(this._connectivity);

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    // connectivity_plus 6.x trả về List<ConnectivityResult>.
    return results.any((r) => r != ConnectivityResult.none);
  }
}
