import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/di/providers.dart';
import '../../data/announcement_prefs_store.dart';
import '../../data/announcement_remote_data_source.dart';
import '../../data/announcement_repository.dart';
import '../../data/event_remote_data_source.dart';
import '../../data/event_repository.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/exam_event.dart';

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

/// Repo lịch có cấu trúc (exam_events + bản sửa tay local).
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    EventRemoteDataSource(),
    ref.watch(appDatabaseProvider),
  );
});

/// Lịch & mốc hạn đã merge cho các chủ đề đang theo dõi (cho UI).
final examEventsProvider =
    FutureProvider.autoDispose<List<ExamEvent>>((ref) async {
  final prefs = await ref.watch(announcementPrefsProvider.future);
  final repo = ref.watch(eventRepositoryProvider);
  return repo.fetchMerged(prefs.topics);
});
