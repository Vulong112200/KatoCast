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

@DriftDatabase(tables: [WeatherCache, FixedRoutePoints, Notes, NoteItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor cho test (in-memory) hoặc background isolate.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 → v2: thêm tính năng Ghi chú (notes + note_items).
          if (from < 2) {
            await m.createTable(notes);
            await m.createTable(noteItems);
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
