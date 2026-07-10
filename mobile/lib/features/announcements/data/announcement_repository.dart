import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/announcement.dart';
import 'announcement_remote_data_source.dart';

/// Nối backend + bảng "đã-thấy" (Drift). Trả về các thông báo MỚI (chưa từng
/// hiển thị) để alarm poll báo; và danh sách đầy đủ cho UI.
class AnnouncementRepository {
  final AnnouncementRemoteDataSource _remote;
  final AppDatabase _db;

  AnnouncementRepository(this._remote, this._db);

  /// Lấy toàn bộ thông báo gần đây của [topics] (cho UI danh sách).
  Future<List<Announcement>> fetchAll(List<String> topics) async {
    final all = <Announcement>[];
    for (final t in topics) {
      try {
        all.addAll(await _remote.fetch(topic: t));
      } catch (_) {
        // Một chủ đề lỗi mạng không chặn các chủ đề khác.
      }
    }
    all.sort((a, b) => b.firstSeenAt.compareTo(a.firstSeenAt));
    return all;
  }

  /// Các thông báo CHƯA hiển thị (không có trong bảng seen). KHÔNG tự đánh dấu
  /// đã-thấy — caller gọi [markSeen] SAU khi hiển thị thành công để tránh mất
  /// tin nếu hiển thị lỗi.
  Future<List<Announcement>> fetchNewUnseen(List<String> topics) async {
    final fetched = await fetchAll(topics);
    if (fetched.isEmpty) return const [];

    final seen = await (_db.select(_db.seenAnnouncements)
          ..where((t) => t.contentHash.isIn(
              fetched.map((a) => a.contentHash).toList())))
        .get();
    final seenHashes = seen.map((r) => r.contentHash).toSet();
    return fetched.where((a) => !seenHashes.contains(a.contentHash)).toList();
  }

  /// Đánh dấu đã hiển thị (idempotent nhờ unique contentHash).
  Future<void> markSeen(Iterable<Announcement> items) async {
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAll(
        _db.seenAnnouncements,
        [
          for (final a in items)
            SeenAnnouncementsCompanion.insert(
              contentHash: a.contentHash,
              remoteId: a.id,
              seenAt: now,
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}
