import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/di/providers.dart';
import '../../data/announcement_prefs_store.dart';
import '../../data/announcement_remote_data_source.dart';
import '../../data/announcement_repository.dart';
import '../../domain/entities/announcement.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  // AnnouncementRemoteDataSource() mặc định trỏ AppConfig.backendBaseUrl.
  return AnnouncementRepository(
    AnnouncementRemoteDataSource(),
    ref.watch(appDatabaseProvider),
  );
});

/// Danh sách thông báo theo các chủ đề đang theo dõi (cho UI).
final announcementsListProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) async {
  final prefs = await ref.watch(announcementPrefsProvider.future);
  final repo = ref.watch(announcementRepositoryProvider);
  return repo.fetchAll(prefs.topics);
});

/// Cài đặt theo dõi thông báo (đọc từ SharedPreferences).
final announcementPrefsProvider =
    FutureProvider.autoDispose<AnnouncementPrefs>((ref) {
  return AnnouncementPrefsStore().read();
});

/// Danh sách chủ đề khả dụng (từ AppConfig) — cho UI chọn.
final availableTopicsProvider = Provider<List<String>>(
  (ref) => AppConfig.announcementTopics,
);
