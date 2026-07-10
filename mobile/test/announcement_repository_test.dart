import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katocast/core/database/app_database.dart';
import 'package:katocast/features/announcements/data/announcement_remote_data_source.dart';
import 'package:katocast/features/announcements/data/announcement_repository.dart';
import 'package:katocast/features/announcements/domain/entities/announcement.dart';

Announcement _ann(int id, String hash, {String topic = 'jlpt'}) => Announcement(
      id: id,
      topic: topic,
      title: 'Tin $id',
      summary: 'Tóm tắt $id',
      sourceUrl: 'https://www.jlpt.jp/e/news$id.html',
      sourceDomain: 'www.jlpt.jp',
      firstSeenAt: DateTime(2026, 7, 10, 8),
      contentHash: hash,
      verified: true,
      score: 0.8,
    );

/// Remote giả: trả danh sách cố định theo topic, không đụng mạng.
class _FakeRemote extends AnnouncementRemoteDataSource {
  final Map<String, List<Announcement>> byTopic;
  _FakeRemote(this.byTopic) : super();

  @override
  Future<List<Announcement>> fetch({
    required String topic,
    DateTime? since,
    int limit = 100,
  }) async =>
      byTopic[topic] ?? const [];
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forExecutor(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('schema v3 có bảng seen_announcements', () async {
    await db.select(db.seenAnnouncements).get(); // không ném lỗi = bảng tồn tại
  });

  test('fetchNewUnseen chỉ trả tin CHƯA thấy; markSeen ẩn ở lần sau', () async {
    final remote = _FakeRemote({
      'jlpt': [_ann(1, 'h1'), _ann(2, 'h2')],
    });
    final repo = AnnouncementRepository(remote, db);

    // Lần 1: cả 2 tin đều mới.
    final first = await repo.fetchNewUnseen(['jlpt']);
    expect(first.map((a) => a.contentHash), containsAll(['h1', 'h2']));

    // Đánh dấu đã thấy 1 tin.
    await repo.markSeen([first.firstWhere((a) => a.contentHash == 'h1')]);

    // Lần 2: chỉ còn tin chưa đánh dấu.
    final second = await repo.fetchNewUnseen(['jlpt']);
    expect(second.map((a) => a.contentHash), ['h2']);

    // Đánh dấu nốt → không còn tin mới.
    await repo.markSeen(second);
    expect(await repo.fetchNewUnseen(['jlpt']), isEmpty);
  });

  test('markSeen idempotent (insertOrIgnore theo contentHash)', () async {
    final repo = AnnouncementRepository(_FakeRemote(const {}), db);
    await repo.markSeen([_ann(1, 'h1')]);
    await repo.markSeen([_ann(1, 'h1')]); // không ném lỗi trùng unique
    final rows = await db.select(db.seenAnnouncements).get();
    expect(rows.length, 1);
  });
}
