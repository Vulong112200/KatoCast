import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cache thời tiết: lưu JSON thô của One Call 3.0 theo toạ độ (làm tròn) để
/// fallback khi offline.
class WeatherCache extends Table {
  /// Khoá = "lat,lng" đã làm tròn 2 chữ số (gom các lần định vị gần nhau).
  TextColumn get locationKey => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {locationKey};
}

/// MODULE 2 — lộ trình cố định (nơi làm việc → nhà). Lưu danh sách toạ độ;
/// quét POI dọc lộ trình qua Overpass/OSM (đã hoạt động đầy đủ).
class FixedRoutePoints extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Gom nhiều điểm thành 1 lộ trình (vd routeId = 'home_to_work').
  TextColumn get routeId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();

  /// Thứ tự điểm trên lộ trình.
  IntColumn get seq => integer()();
  TextColumn get label => text().nullable()();
}

/// Ghi chú cá nhân: text + checklist + nhắc hẹn + ghim sticky notification.
///
/// Row class đặt tên `NoteRow` để không đụng entity domain `Note`
/// (features/notes/domain/entities/note.dart).
@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Index vào bảng màu note (kNoteColors); 0 = màu mặc định theo theme.
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();

  /// Đang ghim sticky trên thanh thông báo.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// Đã xong (chuyển vào khu lưu trữ, không hiện notification).
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Thời điểm nhắc (null = không hẹn giờ). Với lặp ngày/tuần chỉ dùng
  /// giờ:phút (+ thứ theo weekdaysMask).
  DateTimeColumn get remindAt => dateTime().nullable()();

  /// 0 = không lặp (một lần), 1 = hằng ngày, 2 = hằng tuần (theo weekdaysMask).
  IntColumn get repeat => integer().withDefault(const Constant(0))();

  /// Bit (weekday-1) theo DateTime.weekday: bit0=Thứ 2 … bit6=Chủ nhật.
  IntColumn get weekdaysMask => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Mục checklist của một ghi chú.
@DataClassName('NoteItemRow')
class NoteItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId => integer()();
  TextColumn get content => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Thứ tự hiển thị trong checklist.
  IntColumn get seq => integer()();
}

/// Các thông báo (JLPT/MBA/…) ĐÃ hiển thị cho người dùng — để lần poll sau
/// KHÔNG báo lại. Khoá tự nhiên là `contentHash` (backend cấp, ổn định theo nội
/// dung); lưu thêm `remoteId`/`seenAt` để tiện dọn dẹp về sau.
@DataClassName('SeenAnnouncementRow')
class SeenAnnouncements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get contentHash => text()();
  IntColumn get remoteId => integer()();
  DateTimeColumn get seenAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {contentHash},
      ];
}

/// Bản SỬA/THÊM của người dùng cho lịch (ExamEvent). Người dùng luôn ưu tiên
/// hơn dữ liệu backend → dùng để ghi đè mốc ngày sai hoặc thêm mốc còn thiếu.
///
/// `sourceEventId` = id của ExamEvent backend đang ghi đè (null = event tự thêm,
/// không gắn với backend). Khoá tự nhiên `sourceEventId` (SQLite cho phép nhiều
/// NULL nên các event tự thêm không đụng nhau).
@DataClassName('EventOverrideRow')
class EventOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceEventId => integer().nullable()();
  TextColumn get topic => text().withDefault(const Constant('custom'))();
  TextColumn get sessionLabel => text()();
  DateTimeColumn get regStart => dateTime().nullable()();
  DateTimeColumn get regEnd => dateTime().nullable()();
  DateTimeColumn get examDate => dateTime().nullable()();
  DateTimeColumn get resultDate => dateTime().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {sourceEventId},
      ];
}

@DriftDatabase(tables: [
  WeatherCache,
  FixedRoutePoints,
  Notes,
  NoteItems,
  SeenAnnouncements,
  EventOverrides,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor cho test (in-memory) hoặc background isolate.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 → v2: thêm tính năng Ghi chú (notes + note_items).
          if (from < 2) {
            await m.createTable(notes);
            await m.createTable(noteItems);
          }
          // v2 → v3: theo dõi thông báo (JLPT/MBA…) — bảng đã-thấy.
          if (from < 3) {
            await m.createTable(seenAnnouncements);
          }
          // v3 → v4: lịch & mốc hạn — bản sửa/thêm của người dùng.
          if (from < 4) {
            await m.createTable(eventOverrides);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'katocast.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
