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

/// MODULE 2 (Phase 2) — lộ trình cố định (nơi làm việc → nhà).
/// Bảng này dùng được NGAY để lưu danh sách toạ độ; phần quét POI là stub.
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

@DriftDatabase(tables: [WeatherCache, FixedRoutePoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor cho test (in-memory) hoặc background isolate.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'katocast.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
