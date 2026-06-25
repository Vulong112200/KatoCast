import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/network_info.dart';
import '../notifications/notification_service.dart';
import '../permissions/permission_service.dart';

/// Dependency Injection trung tâm (Riverpod).
///
/// Các singleton hạ tầng được khai báo ở đây; feature provider `watch` chúng.
/// Đây là nơi duy nhất khởi tạo Dio/Drift/Notif cho main isolate —
/// background isolate (WorkManager) tự khởi tạo riêng vì không chia sẻ state.

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

final networkInfoProvider = Provider<NetworkInfo>(
  (ref) => NetworkInfoImpl(ref.watch(connectivityProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create());

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
