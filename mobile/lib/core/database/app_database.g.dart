// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WeatherCacheTable extends WeatherCache
    with TableInfo<$WeatherCacheTable, WeatherCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeatherCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _locationKeyMeta = const VerificationMeta(
    'locationKey',
  );
  @override
  late final GeneratedColumn<String> locationKey = GeneratedColumn<String>(
    'location_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [locationKey, payloadJson, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weather_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<WeatherCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('location_key')) {
      context.handle(
        _locationKeyMeta,
        locationKey.isAcceptableOrUnknown(
          data['location_key']!,
          _locationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationKeyMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {locationKey};
  @override
  WeatherCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeatherCacheData(
      locationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_key'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $WeatherCacheTable createAlias(String alias) {
    return $WeatherCacheTable(attachedDatabase, alias);
  }
}

class WeatherCacheData extends DataClass
    implements Insertable<WeatherCacheData> {
  /// Khoá = "lat,lng" đã làm tròn 2 chữ số (gom các lần định vị gần nhau).
  final String locationKey;
  final String payloadJson;
  final DateTime fetchedAt;
  const WeatherCacheData({
    required this.locationKey,
    required this.payloadJson,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['location_key'] = Variable<String>(locationKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  WeatherCacheCompanion toCompanion(bool nullToAbsent) {
    return WeatherCacheCompanion(
      locationKey: Value(locationKey),
      payloadJson: Value(payloadJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory WeatherCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeatherCacheData(
      locationKey: serializer.fromJson<String>(json['locationKey']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'locationKey': serializer.toJson<String>(locationKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  WeatherCacheData copyWith({
    String? locationKey,
    String? payloadJson,
    DateTime? fetchedAt,
  }) => WeatherCacheData(
    locationKey: locationKey ?? this.locationKey,
    payloadJson: payloadJson ?? this.payloadJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  WeatherCacheData copyWithCompanion(WeatherCacheCompanion data) {
    return WeatherCacheData(
      locationKey: data.locationKey.present
          ? data.locationKey.value
          : this.locationKey,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeatherCacheData(')
          ..write('locationKey: $locationKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(locationKey, payloadJson, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeatherCacheData &&
          other.locationKey == this.locationKey &&
          other.payloadJson == this.payloadJson &&
          other.fetchedAt == this.fetchedAt);
}

class WeatherCacheCompanion extends UpdateCompanion<WeatherCacheData> {
  final Value<String> locationKey;
  final Value<String> payloadJson;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const WeatherCacheCompanion({
    this.locationKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WeatherCacheCompanion.insert({
    required String locationKey,
    required String payloadJson,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : locationKey = Value(locationKey),
       payloadJson = Value(payloadJson),
       fetchedAt = Value(fetchedAt);
  static Insertable<WeatherCacheData> custom({
    Expression<String>? locationKey,
    Expression<String>? payloadJson,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (locationKey != null) 'location_key': locationKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WeatherCacheCompanion copyWith({
    Value<String>? locationKey,
    Value<String>? payloadJson,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return WeatherCacheCompanion(
      locationKey: locationKey ?? this.locationKey,
      payloadJson: payloadJson ?? this.payloadJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (locationKey.present) {
      map['location_key'] = Variable<String>(locationKey.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeatherCacheCompanion(')
          ..write('locationKey: $locationKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixedRoutePointsTable extends FixedRoutePoints
    with TableInfo<$FixedRoutePointsTable, FixedRoutePoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixedRoutePointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _routeIdMeta = const VerificationMeta(
    'routeId',
  );
  @override
  late final GeneratedColumn<String> routeId = GeneratedColumn<String>(
    'route_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    routeId,
    latitude,
    longitude,
    seq,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixed_route_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<FixedRoutePoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('route_id')) {
      context.handle(
        _routeIdMeta,
        routeId.isAcceptableOrUnknown(data['route_id']!, _routeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_routeIdMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FixedRoutePoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FixedRoutePoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      routeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_id'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
    );
  }

  @override
  $FixedRoutePointsTable createAlias(String alias) {
    return $FixedRoutePointsTable(attachedDatabase, alias);
  }
}

class FixedRoutePoint extends DataClass implements Insertable<FixedRoutePoint> {
  final int id;

  /// Gom nhiều điểm thành 1 lộ trình (vd routeId = 'home_to_work').
  final String routeId;
  final double latitude;
  final double longitude;

  /// Thứ tự điểm trên lộ trình.
  final int seq;
  final String? label;
  const FixedRoutePoint({
    required this.id,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.seq,
    this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['route_id'] = Variable<String>(routeId);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['seq'] = Variable<int>(seq);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    return map;
  }

  FixedRoutePointsCompanion toCompanion(bool nullToAbsent) {
    return FixedRoutePointsCompanion(
      id: Value(id),
      routeId: Value(routeId),
      latitude: Value(latitude),
      longitude: Value(longitude),
      seq: Value(seq),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
    );
  }

  factory FixedRoutePoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FixedRoutePoint(
      id: serializer.fromJson<int>(json['id']),
      routeId: serializer.fromJson<String>(json['routeId']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      seq: serializer.fromJson<int>(json['seq']),
      label: serializer.fromJson<String?>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'routeId': serializer.toJson<String>(routeId),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'seq': serializer.toJson<int>(seq),
      'label': serializer.toJson<String?>(label),
    };
  }

  FixedRoutePoint copyWith({
    int? id,
    String? routeId,
    double? latitude,
    double? longitude,
    int? seq,
    Value<String?> label = const Value.absent(),
  }) => FixedRoutePoint(
    id: id ?? this.id,
    routeId: routeId ?? this.routeId,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    seq: seq ?? this.seq,
    label: label.present ? label.value : this.label,
  );
  FixedRoutePoint copyWithCompanion(FixedRoutePointsCompanion data) {
    return FixedRoutePoint(
      id: data.id.present ? data.id.value : this.id,
      routeId: data.routeId.present ? data.routeId.value : this.routeId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      seq: data.seq.present ? data.seq.value : this.seq,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FixedRoutePoint(')
          ..write('id: $id, ')
          ..write('routeId: $routeId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('seq: $seq, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, routeId, latitude, longitude, seq, label);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixedRoutePoint &&
          other.id == this.id &&
          other.routeId == this.routeId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.seq == this.seq &&
          other.label == this.label);
}

class FixedRoutePointsCompanion extends UpdateCompanion<FixedRoutePoint> {
  final Value<int> id;
  final Value<String> routeId;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<int> seq;
  final Value<String?> label;
  const FixedRoutePointsCompanion({
    this.id = const Value.absent(),
    this.routeId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.seq = const Value.absent(),
    this.label = const Value.absent(),
  });
  FixedRoutePointsCompanion.insert({
    this.id = const Value.absent(),
    required String routeId,
    required double latitude,
    required double longitude,
    required int seq,
    this.label = const Value.absent(),
  }) : routeId = Value(routeId),
       latitude = Value(latitude),
       longitude = Value(longitude),
       seq = Value(seq);
  static Insertable<FixedRoutePoint> custom({
    Expression<int>? id,
    Expression<String>? routeId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? seq,
    Expression<String>? label,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (routeId != null) 'route_id': routeId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (seq != null) 'seq': seq,
      if (label != null) 'label': label,
    });
  }

  FixedRoutePointsCompanion copyWith({
    Value<int>? id,
    Value<String>? routeId,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<int>? seq,
    Value<String?>? label,
  }) {
    return FixedRoutePointsCompanion(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      seq: seq ?? this.seq,
      label: label ?? this.label,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (routeId.present) {
      map['route_id'] = Variable<String>(routeId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixedRoutePointsCompanion(')
          ..write('id: $id, ')
          ..write('routeId: $routeId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('seq: $seq, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorIndexMeta = const VerificationMeta(
    'colorIndex',
  );
  @override
  late final GeneratedColumn<int> colorIndex = GeneratedColumn<int>(
    'color_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
    'remind_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatMeta = const VerificationMeta('repeat');
  @override
  late final GeneratedColumn<int> repeat = GeneratedColumn<int>(
    'repeat',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _weekdaysMaskMeta = const VerificationMeta(
    'weekdaysMask',
  );
  @override
  late final GeneratedColumn<int> weekdaysMask = GeneratedColumn<int>(
    'weekdays_mask',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    colorIndex,
    pinned,
    done,
    remindAt,
    repeat,
    weekdaysMask,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('color_index')) {
      context.handle(
        _colorIndexMeta,
        colorIndex.isAcceptableOrUnknown(data['color_index']!, _colorIndexMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    }
    if (data.containsKey('repeat')) {
      context.handle(
        _repeatMeta,
        repeat.isAcceptableOrUnknown(data['repeat']!, _repeatMeta),
      );
    }
    if (data.containsKey('weekdays_mask')) {
      context.handle(
        _weekdaysMaskMeta,
        weekdaysMask.isAcceptableOrUnknown(
          data['weekdays_mask']!,
          _weekdaysMaskMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      colorIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_index'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remind_at'],
      ),
      repeat: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat'],
      )!,
      weekdaysMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekdays_mask'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final int id;
  final String title;
  final String body;

  /// Index vào bảng màu note (kNoteColors); 0 = màu mặc định theo theme.
  final int colorIndex;

  /// Đang ghim sticky trên thanh thông báo.
  final bool pinned;

  /// Đã xong (chuyển vào khu lưu trữ, không hiện notification).
  final bool done;

  /// Thời điểm nhắc (null = không hẹn giờ). Với lặp ngày/tuần chỉ dùng
  /// giờ:phút (+ thứ theo weekdaysMask).
  final DateTime? remindAt;

  /// 0 = không lặp (một lần), 1 = hằng ngày, 2 = hằng tuần (theo weekdaysMask).
  final int repeat;

  /// Bit (weekday-1) theo DateTime.weekday: bit0=Thứ 2 … bit6=Chủ nhật.
  final int weekdaysMask;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NoteRow({
    required this.id,
    required this.title,
    required this.body,
    required this.colorIndex,
    required this.pinned,
    required this.done,
    this.remindAt,
    required this.repeat,
    required this.weekdaysMask,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['color_index'] = Variable<int>(colorIndex);
    map['pinned'] = Variable<bool>(pinned);
    map['done'] = Variable<bool>(done);
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<DateTime>(remindAt);
    }
    map['repeat'] = Variable<int>(repeat);
    map['weekdays_mask'] = Variable<int>(weekdaysMask);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      colorIndex: Value(colorIndex),
      pinned: Value(pinned),
      done: Value(done),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      repeat: Value(repeat),
      weekdaysMask: Value(weekdaysMask),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      colorIndex: serializer.fromJson<int>(json['colorIndex']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      done: serializer.fromJson<bool>(json['done']),
      remindAt: serializer.fromJson<DateTime?>(json['remindAt']),
      repeat: serializer.fromJson<int>(json['repeat']),
      weekdaysMask: serializer.fromJson<int>(json['weekdaysMask']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'colorIndex': serializer.toJson<int>(colorIndex),
      'pinned': serializer.toJson<bool>(pinned),
      'done': serializer.toJson<bool>(done),
      'remindAt': serializer.toJson<DateTime?>(remindAt),
      'repeat': serializer.toJson<int>(repeat),
      'weekdaysMask': serializer.toJson<int>(weekdaysMask),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NoteRow copyWith({
    int? id,
    String? title,
    String? body,
    int? colorIndex,
    bool? pinned,
    bool? done,
    Value<DateTime?> remindAt = const Value.absent(),
    int? repeat,
    int? weekdaysMask,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteRow(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    colorIndex: colorIndex ?? this.colorIndex,
    pinned: pinned ?? this.pinned,
    done: done ?? this.done,
    remindAt: remindAt.present ? remindAt.value : this.remindAt,
    repeat: repeat ?? this.repeat,
    weekdaysMask: weekdaysMask ?? this.weekdaysMask,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NoteRow copyWithCompanion(NotesCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      colorIndex: data.colorIndex.present
          ? data.colorIndex.value
          : this.colorIndex,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      done: data.done.present ? data.done.value : this.done,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      repeat: data.repeat.present ? data.repeat.value : this.repeat,
      weekdaysMask: data.weekdaysMask.present
          ? data.weekdaysMask.value
          : this.weekdaysMask,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('pinned: $pinned, ')
          ..write('done: $done, ')
          ..write('remindAt: $remindAt, ')
          ..write('repeat: $repeat, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    colorIndex,
    pinned,
    done,
    remindAt,
    repeat,
    weekdaysMask,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.colorIndex == this.colorIndex &&
          other.pinned == this.pinned &&
          other.done == this.done &&
          other.remindAt == this.remindAt &&
          other.repeat == this.repeat &&
          other.weekdaysMask == this.weekdaysMask &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotesCompanion extends UpdateCompanion<NoteRow> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> body;
  final Value<int> colorIndex;
  final Value<bool> pinned;
  final Value<bool> done;
  final Value<DateTime?> remindAt;
  final Value<int> repeat;
  final Value<int> weekdaysMask;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.pinned = const Value.absent(),
    this.done = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.repeat = const Value.absent(),
    this.weekdaysMask = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NotesCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.body = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.pinned = const Value.absent(),
    this.done = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.repeat = const Value.absent(),
    this.weekdaysMask = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NoteRow> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<int>? colorIndex,
    Expression<bool>? pinned,
    Expression<bool>? done,
    Expression<DateTime>? remindAt,
    Expression<int>? repeat,
    Expression<int>? weekdaysMask,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (colorIndex != null) 'color_index': colorIndex,
      if (pinned != null) 'pinned': pinned,
      if (done != null) 'done': done,
      if (remindAt != null) 'remind_at': remindAt,
      if (repeat != null) 'repeat': repeat,
      if (weekdaysMask != null) 'weekdays_mask': weekdaysMask,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NotesCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? body,
    Value<int>? colorIndex,
    Value<bool>? pinned,
    Value<bool>? done,
    Value<DateTime?>? remindAt,
    Value<int>? repeat,
    Value<int>? weekdaysMask,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      colorIndex: colorIndex ?? this.colorIndex,
      pinned: pinned ?? this.pinned,
      done: done ?? this.done,
      remindAt: remindAt ?? this.remindAt,
      repeat: repeat ?? this.repeat,
      weekdaysMask: weekdaysMask ?? this.weekdaysMask,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (colorIndex.present) {
      map['color_index'] = Variable<int>(colorIndex.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (repeat.present) {
      map['repeat'] = Variable<int>(repeat.value);
    }
    if (weekdaysMask.present) {
      map['weekdays_mask'] = Variable<int>(weekdaysMask.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('pinned: $pinned, ')
          ..write('done: $done, ')
          ..write('remindAt: $remindAt, ')
          ..write('repeat: $repeat, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NoteItemsTable extends NoteItems
    with TableInfo<$NoteItemsTable, NoteItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, noteId, content, done, seq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}note_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
    );
  }

  @override
  $NoteItemsTable createAlias(String alias) {
    return $NoteItemsTable(attachedDatabase, alias);
  }
}

class NoteItemRow extends DataClass implements Insertable<NoteItemRow> {
  final int id;
  final int noteId;
  final String content;
  final bool done;

  /// Thứ tự hiển thị trong checklist.
  final int seq;
  const NoteItemRow({
    required this.id,
    required this.noteId,
    required this.content,
    required this.done,
    required this.seq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['note_id'] = Variable<int>(noteId);
    map['content'] = Variable<String>(content);
    map['done'] = Variable<bool>(done);
    map['seq'] = Variable<int>(seq);
    return map;
  }

  NoteItemsCompanion toCompanion(bool nullToAbsent) {
    return NoteItemsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      content: Value(content),
      done: Value(done),
      seq: Value(seq),
    );
  }

  factory NoteItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteItemRow(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<int>(json['noteId']),
      content: serializer.fromJson<String>(json['content']),
      done: serializer.fromJson<bool>(json['done']),
      seq: serializer.fromJson<int>(json['seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<int>(noteId),
      'content': serializer.toJson<String>(content),
      'done': serializer.toJson<bool>(done),
      'seq': serializer.toJson<int>(seq),
    };
  }

  NoteItemRow copyWith({
    int? id,
    int? noteId,
    String? content,
    bool? done,
    int? seq,
  }) => NoteItemRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    content: content ?? this.content,
    done: done ?? this.done,
    seq: seq ?? this.seq,
  );
  NoteItemRow copyWithCompanion(NoteItemsCompanion data) {
    return NoteItemRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      content: data.content.present ? data.content.value : this.content,
      done: data.done.present ? data.done.value : this.done,
      seq: data.seq.present ? data.seq.value : this.seq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteItemRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('content: $content, ')
          ..write('done: $done, ')
          ..write('seq: $seq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, noteId, content, done, seq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteItemRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.content == this.content &&
          other.done == this.done &&
          other.seq == this.seq);
}

class NoteItemsCompanion extends UpdateCompanion<NoteItemRow> {
  final Value<int> id;
  final Value<int> noteId;
  final Value<String> content;
  final Value<bool> done;
  final Value<int> seq;
  const NoteItemsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.content = const Value.absent(),
    this.done = const Value.absent(),
    this.seq = const Value.absent(),
  });
  NoteItemsCompanion.insert({
    this.id = const Value.absent(),
    required int noteId,
    required String content,
    this.done = const Value.absent(),
    required int seq,
  }) : noteId = Value(noteId),
       content = Value(content),
       seq = Value(seq);
  static Insertable<NoteItemRow> custom({
    Expression<int>? id,
    Expression<int>? noteId,
    Expression<String>? content,
    Expression<bool>? done,
    Expression<int>? seq,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (content != null) 'content': content,
      if (done != null) 'done': done,
      if (seq != null) 'seq': seq,
    });
  }

  NoteItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? noteId,
    Value<String>? content,
    Value<bool>? done,
    Value<int>? seq,
  }) {
    return NoteItemsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      content: content ?? this.content,
      done: done ?? this.done,
      seq: seq ?? this.seq,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteItemsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('content: $content, ')
          ..write('done: $done, ')
          ..write('seq: $seq')
          ..write(')'))
        .toString();
  }
}

class $SeenAnnouncementsTable extends SeenAnnouncements
    with TableInfo<$SeenAnnouncementsTable, SeenAnnouncementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeenAnnouncementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<int> remoteId = GeneratedColumn<int>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<DateTime> seenAt = GeneratedColumn<DateTime>(
    'seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, contentHash, remoteId, seenAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seen_announcements';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeenAnnouncementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_seenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {contentHash},
  ];
  @override
  SeenAnnouncementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeenAnnouncementRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_id'],
      )!,
      seenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}seen_at'],
      )!,
    );
  }

  @override
  $SeenAnnouncementsTable createAlias(String alias) {
    return $SeenAnnouncementsTable(attachedDatabase, alias);
  }
}

class SeenAnnouncementRow extends DataClass
    implements Insertable<SeenAnnouncementRow> {
  final int id;
  final String contentHash;
  final int remoteId;
  final DateTime seenAt;
  const SeenAnnouncementRow({
    required this.id,
    required this.contentHash,
    required this.remoteId,
    required this.seenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content_hash'] = Variable<String>(contentHash);
    map['remote_id'] = Variable<int>(remoteId);
    map['seen_at'] = Variable<DateTime>(seenAt);
    return map;
  }

  SeenAnnouncementsCompanion toCompanion(bool nullToAbsent) {
    return SeenAnnouncementsCompanion(
      id: Value(id),
      contentHash: Value(contentHash),
      remoteId: Value(remoteId),
      seenAt: Value(seenAt),
    );
  }

  factory SeenAnnouncementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeenAnnouncementRow(
      id: serializer.fromJson<int>(json['id']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      remoteId: serializer.fromJson<int>(json['remoteId']),
      seenAt: serializer.fromJson<DateTime>(json['seenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'contentHash': serializer.toJson<String>(contentHash),
      'remoteId': serializer.toJson<int>(remoteId),
      'seenAt': serializer.toJson<DateTime>(seenAt),
    };
  }

  SeenAnnouncementRow copyWith({
    int? id,
    String? contentHash,
    int? remoteId,
    DateTime? seenAt,
  }) => SeenAnnouncementRow(
    id: id ?? this.id,
    contentHash: contentHash ?? this.contentHash,
    remoteId: remoteId ?? this.remoteId,
    seenAt: seenAt ?? this.seenAt,
  );
  SeenAnnouncementRow copyWithCompanion(SeenAnnouncementsCompanion data) {
    return SeenAnnouncementRow(
      id: data.id.present ? data.id.value : this.id,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeenAnnouncementRow(')
          ..write('id: $id, ')
          ..write('contentHash: $contentHash, ')
          ..write('remoteId: $remoteId, ')
          ..write('seenAt: $seenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, contentHash, remoteId, seenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeenAnnouncementRow &&
          other.id == this.id &&
          other.contentHash == this.contentHash &&
          other.remoteId == this.remoteId &&
          other.seenAt == this.seenAt);
}

class SeenAnnouncementsCompanion extends UpdateCompanion<SeenAnnouncementRow> {
  final Value<int> id;
  final Value<String> contentHash;
  final Value<int> remoteId;
  final Value<DateTime> seenAt;
  const SeenAnnouncementsCompanion({
    this.id = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.seenAt = const Value.absent(),
  });
  SeenAnnouncementsCompanion.insert({
    this.id = const Value.absent(),
    required String contentHash,
    required int remoteId,
    required DateTime seenAt,
  }) : contentHash = Value(contentHash),
       remoteId = Value(remoteId),
       seenAt = Value(seenAt);
  static Insertable<SeenAnnouncementRow> custom({
    Expression<int>? id,
    Expression<String>? contentHash,
    Expression<int>? remoteId,
    Expression<DateTime>? seenAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contentHash != null) 'content_hash': contentHash,
      if (remoteId != null) 'remote_id': remoteId,
      if (seenAt != null) 'seen_at': seenAt,
    });
  }

  SeenAnnouncementsCompanion copyWith({
    Value<int>? id,
    Value<String>? contentHash,
    Value<int>? remoteId,
    Value<DateTime>? seenAt,
  }) {
    return SeenAnnouncementsCompanion(
      id: id ?? this.id,
      contentHash: contentHash ?? this.contentHash,
      remoteId: remoteId ?? this.remoteId,
      seenAt: seenAt ?? this.seenAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<int>(remoteId.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<DateTime>(seenAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeenAnnouncementsCompanion(')
          ..write('id: $id, ')
          ..write('contentHash: $contentHash, ')
          ..write('remoteId: $remoteId, ')
          ..write('seenAt: $seenAt')
          ..write(')'))
        .toString();
  }
}

class $EventOverridesTable extends EventOverrides
    with TableInfo<$EventOverridesTable, EventOverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<int> sourceEventId = GeneratedColumn<int>(
    'source_event_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
    'topic',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('custom'),
  );
  static const VerificationMeta _sessionLabelMeta = const VerificationMeta(
    'sessionLabel',
  );
  @override
  late final GeneratedColumn<String> sessionLabel = GeneratedColumn<String>(
    'session_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _regStartMeta = const VerificationMeta(
    'regStart',
  );
  @override
  late final GeneratedColumn<DateTime> regStart = GeneratedColumn<DateTime>(
    'reg_start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _regEndMeta = const VerificationMeta('regEnd');
  @override
  late final GeneratedColumn<DateTime> regEnd = GeneratedColumn<DateTime>(
    'reg_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _examDateMeta = const VerificationMeta(
    'examDate',
  );
  @override
  late final GeneratedColumn<DateTime> examDate = GeneratedColumn<DateTime>(
    'exam_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultDateMeta = const VerificationMeta(
    'resultDate',
  );
  @override
  late final GeneratedColumn<DateTime> resultDate = GeneratedColumn<DateTime>(
    'result_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceEventId,
    topic,
    sessionLabel,
    regStart,
    regEnd,
    examDate,
    resultDate,
    note,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventOverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    }
    if (data.containsKey('topic')) {
      context.handle(
        _topicMeta,
        topic.isAcceptableOrUnknown(data['topic']!, _topicMeta),
      );
    }
    if (data.containsKey('session_label')) {
      context.handle(
        _sessionLabelMeta,
        sessionLabel.isAcceptableOrUnknown(
          data['session_label']!,
          _sessionLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionLabelMeta);
    }
    if (data.containsKey('reg_start')) {
      context.handle(
        _regStartMeta,
        regStart.isAcceptableOrUnknown(data['reg_start']!, _regStartMeta),
      );
    }
    if (data.containsKey('reg_end')) {
      context.handle(
        _regEndMeta,
        regEnd.isAcceptableOrUnknown(data['reg_end']!, _regEndMeta),
      );
    }
    if (data.containsKey('exam_date')) {
      context.handle(
        _examDateMeta,
        examDate.isAcceptableOrUnknown(data['exam_date']!, _examDateMeta),
      );
    }
    if (data.containsKey('result_date')) {
      context.handle(
        _resultDateMeta,
        resultDate.isAcceptableOrUnknown(data['result_date']!, _resultDateMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sourceEventId},
  ];
  @override
  EventOverrideRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventOverrideRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_event_id'],
      ),
      topic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic'],
      )!,
      sessionLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_label'],
      )!,
      regStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reg_start'],
      ),
      regEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reg_end'],
      ),
      examDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}exam_date'],
      ),
      resultDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}result_date'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EventOverridesTable createAlias(String alias) {
    return $EventOverridesTable(attachedDatabase, alias);
  }
}

class EventOverrideRow extends DataClass
    implements Insertable<EventOverrideRow> {
  final int id;
  final int? sourceEventId;
  final String topic;
  final String sessionLabel;
  final DateTime? regStart;
  final DateTime? regEnd;
  final DateTime? examDate;
  final DateTime? resultDate;
  final String note;
  final DateTime updatedAt;
  const EventOverrideRow({
    required this.id,
    this.sourceEventId,
    required this.topic,
    required this.sessionLabel,
    this.regStart,
    this.regEnd,
    this.examDate,
    this.resultDate,
    required this.note,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || sourceEventId != null) {
      map['source_event_id'] = Variable<int>(sourceEventId);
    }
    map['topic'] = Variable<String>(topic);
    map['session_label'] = Variable<String>(sessionLabel);
    if (!nullToAbsent || regStart != null) {
      map['reg_start'] = Variable<DateTime>(regStart);
    }
    if (!nullToAbsent || regEnd != null) {
      map['reg_end'] = Variable<DateTime>(regEnd);
    }
    if (!nullToAbsent || examDate != null) {
      map['exam_date'] = Variable<DateTime>(examDate);
    }
    if (!nullToAbsent || resultDate != null) {
      map['result_date'] = Variable<DateTime>(resultDate);
    }
    map['note'] = Variable<String>(note);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EventOverridesCompanion toCompanion(bool nullToAbsent) {
    return EventOverridesCompanion(
      id: Value(id),
      sourceEventId: sourceEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceEventId),
      topic: Value(topic),
      sessionLabel: Value(sessionLabel),
      regStart: regStart == null && nullToAbsent
          ? const Value.absent()
          : Value(regStart),
      regEnd: regEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(regEnd),
      examDate: examDate == null && nullToAbsent
          ? const Value.absent()
          : Value(examDate),
      resultDate: resultDate == null && nullToAbsent
          ? const Value.absent()
          : Value(resultDate),
      note: Value(note),
      updatedAt: Value(updatedAt),
    );
  }

  factory EventOverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventOverrideRow(
      id: serializer.fromJson<int>(json['id']),
      sourceEventId: serializer.fromJson<int?>(json['sourceEventId']),
      topic: serializer.fromJson<String>(json['topic']),
      sessionLabel: serializer.fromJson<String>(json['sessionLabel']),
      regStart: serializer.fromJson<DateTime?>(json['regStart']),
      regEnd: serializer.fromJson<DateTime?>(json['regEnd']),
      examDate: serializer.fromJson<DateTime?>(json['examDate']),
      resultDate: serializer.fromJson<DateTime?>(json['resultDate']),
      note: serializer.fromJson<String>(json['note']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceEventId': serializer.toJson<int?>(sourceEventId),
      'topic': serializer.toJson<String>(topic),
      'sessionLabel': serializer.toJson<String>(sessionLabel),
      'regStart': serializer.toJson<DateTime?>(regStart),
      'regEnd': serializer.toJson<DateTime?>(regEnd),
      'examDate': serializer.toJson<DateTime?>(examDate),
      'resultDate': serializer.toJson<DateTime?>(resultDate),
      'note': serializer.toJson<String>(note),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EventOverrideRow copyWith({
    int? id,
    Value<int?> sourceEventId = const Value.absent(),
    String? topic,
    String? sessionLabel,
    Value<DateTime?> regStart = const Value.absent(),
    Value<DateTime?> regEnd = const Value.absent(),
    Value<DateTime?> examDate = const Value.absent(),
    Value<DateTime?> resultDate = const Value.absent(),
    String? note,
    DateTime? updatedAt,
  }) => EventOverrideRow(
    id: id ?? this.id,
    sourceEventId: sourceEventId.present
        ? sourceEventId.value
        : this.sourceEventId,
    topic: topic ?? this.topic,
    sessionLabel: sessionLabel ?? this.sessionLabel,
    regStart: regStart.present ? regStart.value : this.regStart,
    regEnd: regEnd.present ? regEnd.value : this.regEnd,
    examDate: examDate.present ? examDate.value : this.examDate,
    resultDate: resultDate.present ? resultDate.value : this.resultDate,
    note: note ?? this.note,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EventOverrideRow copyWithCompanion(EventOverridesCompanion data) {
    return EventOverrideRow(
      id: data.id.present ? data.id.value : this.id,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      topic: data.topic.present ? data.topic.value : this.topic,
      sessionLabel: data.sessionLabel.present
          ? data.sessionLabel.value
          : this.sessionLabel,
      regStart: data.regStart.present ? data.regStart.value : this.regStart,
      regEnd: data.regEnd.present ? data.regEnd.value : this.regEnd,
      examDate: data.examDate.present ? data.examDate.value : this.examDate,
      resultDate: data.resultDate.present
          ? data.resultDate.value
          : this.resultDate,
      note: data.note.present ? data.note.value : this.note,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventOverrideRow(')
          ..write('id: $id, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('topic: $topic, ')
          ..write('sessionLabel: $sessionLabel, ')
          ..write('regStart: $regStart, ')
          ..write('regEnd: $regEnd, ')
          ..write('examDate: $examDate, ')
          ..write('resultDate: $resultDate, ')
          ..write('note: $note, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceEventId,
    topic,
    sessionLabel,
    regStart,
    regEnd,
    examDate,
    resultDate,
    note,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventOverrideRow &&
          other.id == this.id &&
          other.sourceEventId == this.sourceEventId &&
          other.topic == this.topic &&
          other.sessionLabel == this.sessionLabel &&
          other.regStart == this.regStart &&
          other.regEnd == this.regEnd &&
          other.examDate == this.examDate &&
          other.resultDate == this.resultDate &&
          other.note == this.note &&
          other.updatedAt == this.updatedAt);
}

class EventOverridesCompanion extends UpdateCompanion<EventOverrideRow> {
  final Value<int> id;
  final Value<int?> sourceEventId;
  final Value<String> topic;
  final Value<String> sessionLabel;
  final Value<DateTime?> regStart;
  final Value<DateTime?> regEnd;
  final Value<DateTime?> examDate;
  final Value<DateTime?> resultDate;
  final Value<String> note;
  final Value<DateTime> updatedAt;
  const EventOverridesCompanion({
    this.id = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.topic = const Value.absent(),
    this.sessionLabel = const Value.absent(),
    this.regStart = const Value.absent(),
    this.regEnd = const Value.absent(),
    this.examDate = const Value.absent(),
    this.resultDate = const Value.absent(),
    this.note = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  EventOverridesCompanion.insert({
    this.id = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.topic = const Value.absent(),
    required String sessionLabel,
    this.regStart = const Value.absent(),
    this.regEnd = const Value.absent(),
    this.examDate = const Value.absent(),
    this.resultDate = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime updatedAt,
  }) : sessionLabel = Value(sessionLabel),
       updatedAt = Value(updatedAt);
  static Insertable<EventOverrideRow> custom({
    Expression<int>? id,
    Expression<int>? sourceEventId,
    Expression<String>? topic,
    Expression<String>? sessionLabel,
    Expression<DateTime>? regStart,
    Expression<DateTime>? regEnd,
    Expression<DateTime>? examDate,
    Expression<DateTime>? resultDate,
    Expression<String>? note,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (topic != null) 'topic': topic,
      if (sessionLabel != null) 'session_label': sessionLabel,
      if (regStart != null) 'reg_start': regStart,
      if (regEnd != null) 'reg_end': regEnd,
      if (examDate != null) 'exam_date': examDate,
      if (resultDate != null) 'result_date': resultDate,
      if (note != null) 'note': note,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  EventOverridesCompanion copyWith({
    Value<int>? id,
    Value<int?>? sourceEventId,
    Value<String>? topic,
    Value<String>? sessionLabel,
    Value<DateTime?>? regStart,
    Value<DateTime?>? regEnd,
    Value<DateTime?>? examDate,
    Value<DateTime?>? resultDate,
    Value<String>? note,
    Value<DateTime>? updatedAt,
  }) {
    return EventOverridesCompanion(
      id: id ?? this.id,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      topic: topic ?? this.topic,
      sessionLabel: sessionLabel ?? this.sessionLabel,
      regStart: regStart ?? this.regStart,
      regEnd: regEnd ?? this.regEnd,
      examDate: examDate ?? this.examDate,
      resultDate: resultDate ?? this.resultDate,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<int>(sourceEventId.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (sessionLabel.present) {
      map['session_label'] = Variable<String>(sessionLabel.value);
    }
    if (regStart.present) {
      map['reg_start'] = Variable<DateTime>(regStart.value);
    }
    if (regEnd.present) {
      map['reg_end'] = Variable<DateTime>(regEnd.value);
    }
    if (examDate.present) {
      map['exam_date'] = Variable<DateTime>(examDate.value);
    }
    if (resultDate.present) {
      map['result_date'] = Variable<DateTime>(resultDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventOverridesCompanion(')
          ..write('id: $id, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('topic: $topic, ')
          ..write('sessionLabel: $sessionLabel, ')
          ..write('regStart: $regStart, ')
          ..write('regEnd: $regEnd, ')
          ..write('examDate: $examDate, ')
          ..write('resultDate: $resultDate, ')
          ..write('note: $note, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WeatherCacheTable weatherCache = $WeatherCacheTable(this);
  late final $FixedRoutePointsTable fixedRoutePoints = $FixedRoutePointsTable(
    this,
  );
  late final $NotesTable notes = $NotesTable(this);
  late final $NoteItemsTable noteItems = $NoteItemsTable(this);
  late final $SeenAnnouncementsTable seenAnnouncements =
      $SeenAnnouncementsTable(this);
  late final $EventOverridesTable eventOverrides = $EventOverridesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    weatherCache,
    fixedRoutePoints,
    notes,
    noteItems,
    seenAnnouncements,
    eventOverrides,
  ];
}

typedef $$WeatherCacheTableCreateCompanionBuilder =
    WeatherCacheCompanion Function({
      required String locationKey,
      required String payloadJson,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$WeatherCacheTableUpdateCompanionBuilder =
    WeatherCacheCompanion Function({
      Value<String> locationKey,
      Value<String> payloadJson,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$WeatherCacheTableFilterComposer
    extends Composer<_$AppDatabase, $WeatherCacheTable> {
  $$WeatherCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WeatherCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $WeatherCacheTable> {
  $$WeatherCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WeatherCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $WeatherCacheTable> {
  $$WeatherCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$WeatherCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WeatherCacheTable,
          WeatherCacheData,
          $$WeatherCacheTableFilterComposer,
          $$WeatherCacheTableOrderingComposer,
          $$WeatherCacheTableAnnotationComposer,
          $$WeatherCacheTableCreateCompanionBuilder,
          $$WeatherCacheTableUpdateCompanionBuilder,
          (
            WeatherCacheData,
            BaseReferences<_$AppDatabase, $WeatherCacheTable, WeatherCacheData>,
          ),
          WeatherCacheData,
          PrefetchHooks Function()
        > {
  $$WeatherCacheTableTableManager(_$AppDatabase db, $WeatherCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeatherCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeatherCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeatherCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> locationKey = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WeatherCacheCompanion(
                locationKey: locationKey,
                payloadJson: payloadJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String locationKey,
                required String payloadJson,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => WeatherCacheCompanion.insert(
                locationKey: locationKey,
                payloadJson: payloadJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WeatherCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WeatherCacheTable,
      WeatherCacheData,
      $$WeatherCacheTableFilterComposer,
      $$WeatherCacheTableOrderingComposer,
      $$WeatherCacheTableAnnotationComposer,
      $$WeatherCacheTableCreateCompanionBuilder,
      $$WeatherCacheTableUpdateCompanionBuilder,
      (
        WeatherCacheData,
        BaseReferences<_$AppDatabase, $WeatherCacheTable, WeatherCacheData>,
      ),
      WeatherCacheData,
      PrefetchHooks Function()
    >;
typedef $$FixedRoutePointsTableCreateCompanionBuilder =
    FixedRoutePointsCompanion Function({
      Value<int> id,
      required String routeId,
      required double latitude,
      required double longitude,
      required int seq,
      Value<String?> label,
    });
typedef $$FixedRoutePointsTableUpdateCompanionBuilder =
    FixedRoutePointsCompanion Function({
      Value<int> id,
      Value<String> routeId,
      Value<double> latitude,
      Value<double> longitude,
      Value<int> seq,
      Value<String?> label,
    });

class $$FixedRoutePointsTableFilterComposer
    extends Composer<_$AppDatabase, $FixedRoutePointsTable> {
  $$FixedRoutePointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FixedRoutePointsTableOrderingComposer
    extends Composer<_$AppDatabase, $FixedRoutePointsTable> {
  $$FixedRoutePointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FixedRoutePointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FixedRoutePointsTable> {
  $$FixedRoutePointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get routeId =>
      $composableBuilder(column: $table.routeId, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);
}

class $$FixedRoutePointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FixedRoutePointsTable,
          FixedRoutePoint,
          $$FixedRoutePointsTableFilterComposer,
          $$FixedRoutePointsTableOrderingComposer,
          $$FixedRoutePointsTableAnnotationComposer,
          $$FixedRoutePointsTableCreateCompanionBuilder,
          $$FixedRoutePointsTableUpdateCompanionBuilder,
          (
            FixedRoutePoint,
            BaseReferences<
              _$AppDatabase,
              $FixedRoutePointsTable,
              FixedRoutePoint
            >,
          ),
          FixedRoutePoint,
          PrefetchHooks Function()
        > {
  $$FixedRoutePointsTableTableManager(
    _$AppDatabase db,
    $FixedRoutePointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FixedRoutePointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FixedRoutePointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FixedRoutePointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> routeId = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String?> label = const Value.absent(),
              }) => FixedRoutePointsCompanion(
                id: id,
                routeId: routeId,
                latitude: latitude,
                longitude: longitude,
                seq: seq,
                label: label,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String routeId,
                required double latitude,
                required double longitude,
                required int seq,
                Value<String?> label = const Value.absent(),
              }) => FixedRoutePointsCompanion.insert(
                id: id,
                routeId: routeId,
                latitude: latitude,
                longitude: longitude,
                seq: seq,
                label: label,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FixedRoutePointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FixedRoutePointsTable,
      FixedRoutePoint,
      $$FixedRoutePointsTableFilterComposer,
      $$FixedRoutePointsTableOrderingComposer,
      $$FixedRoutePointsTableAnnotationComposer,
      $$FixedRoutePointsTableCreateCompanionBuilder,
      $$FixedRoutePointsTableUpdateCompanionBuilder,
      (
        FixedRoutePoint,
        BaseReferences<_$AppDatabase, $FixedRoutePointsTable, FixedRoutePoint>,
      ),
      FixedRoutePoint,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      required String title,
      Value<String> body,
      Value<int> colorIndex,
      Value<bool> pinned,
      Value<bool> done,
      Value<DateTime?> remindAt,
      Value<int> repeat,
      Value<int> weekdaysMask,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> body,
      Value<int> colorIndex,
      Value<bool> pinned,
      Value<bool> done,
      Value<DateTime?> remindAt,
      Value<int> repeat,
      Value<int> weekdaysMask,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeat => $composableBuilder(
    column: $table.repeat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<int> get repeat =>
      $composableBuilder(column: $table.repeat, builder: (column) => column);

  GeneratedColumn<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          NoteRow,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$AppDatabase, $NotesTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> colorIndex = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<int> repeat = const Value.absent(),
                Value<int> weekdaysMask = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                title: title,
                body: body,
                colorIndex: colorIndex,
                pinned: pinned,
                done: done,
                remindAt: remindAt,
                repeat: repeat,
                weekdaysMask: weekdaysMask,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String> body = const Value.absent(),
                Value<int> colorIndex = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<DateTime?> remindAt = const Value.absent(),
                Value<int> repeat = const Value.absent(),
                Value<int> weekdaysMask = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => NotesCompanion.insert(
                id: id,
                title: title,
                body: body,
                colorIndex: colorIndex,
                pinned: pinned,
                done: done,
                remindAt: remindAt,
                repeat: repeat,
                weekdaysMask: weekdaysMask,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      NoteRow,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$AppDatabase, $NotesTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$NoteItemsTableCreateCompanionBuilder =
    NoteItemsCompanion Function({
      Value<int> id,
      required int noteId,
      required String content,
      Value<bool> done,
      required int seq,
    });
typedef $$NoteItemsTableUpdateCompanionBuilder =
    NoteItemsCompanion Function({
      Value<int> id,
      Value<int> noteId,
      Value<String> content,
      Value<bool> done,
      Value<int> seq,
    });

class $$NoteItemsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteItemsTable> {
  $$NoteItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteItemsTable> {
  $$NoteItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteItemsTable> {
  $$NoteItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);
}

class $$NoteItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteItemsTable,
          NoteItemRow,
          $$NoteItemsTableFilterComposer,
          $$NoteItemsTableOrderingComposer,
          $$NoteItemsTableAnnotationComposer,
          $$NoteItemsTableCreateCompanionBuilder,
          $$NoteItemsTableUpdateCompanionBuilder,
          (
            NoteItemRow,
            BaseReferences<_$AppDatabase, $NoteItemsTable, NoteItemRow>,
          ),
          NoteItemRow,
          PrefetchHooks Function()
        > {
  $$NoteItemsTableTableManager(_$AppDatabase db, $NoteItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> noteId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<int> seq = const Value.absent(),
              }) => NoteItemsCompanion(
                id: id,
                noteId: noteId,
                content: content,
                done: done,
                seq: seq,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int noteId,
                required String content,
                Value<bool> done = const Value.absent(),
                required int seq,
              }) => NoteItemsCompanion.insert(
                id: id,
                noteId: noteId,
                content: content,
                done: done,
                seq: seq,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteItemsTable,
      NoteItemRow,
      $$NoteItemsTableFilterComposer,
      $$NoteItemsTableOrderingComposer,
      $$NoteItemsTableAnnotationComposer,
      $$NoteItemsTableCreateCompanionBuilder,
      $$NoteItemsTableUpdateCompanionBuilder,
      (
        NoteItemRow,
        BaseReferences<_$AppDatabase, $NoteItemsTable, NoteItemRow>,
      ),
      NoteItemRow,
      PrefetchHooks Function()
    >;
typedef $$SeenAnnouncementsTableCreateCompanionBuilder =
    SeenAnnouncementsCompanion Function({
      Value<int> id,
      required String contentHash,
      required int remoteId,
      required DateTime seenAt,
    });
typedef $$SeenAnnouncementsTableUpdateCompanionBuilder =
    SeenAnnouncementsCompanion Function({
      Value<int> id,
      Value<String> contentHash,
      Value<int> remoteId,
      Value<DateTime> seenAt,
    });

class $$SeenAnnouncementsTableFilterComposer
    extends Composer<_$AppDatabase, $SeenAnnouncementsTable> {
  $$SeenAnnouncementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeenAnnouncementsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeenAnnouncementsTable> {
  $$SeenAnnouncementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeenAnnouncementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeenAnnouncementsTable> {
  $$SeenAnnouncementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<DateTime> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);
}

class $$SeenAnnouncementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeenAnnouncementsTable,
          SeenAnnouncementRow,
          $$SeenAnnouncementsTableFilterComposer,
          $$SeenAnnouncementsTableOrderingComposer,
          $$SeenAnnouncementsTableAnnotationComposer,
          $$SeenAnnouncementsTableCreateCompanionBuilder,
          $$SeenAnnouncementsTableUpdateCompanionBuilder,
          (
            SeenAnnouncementRow,
            BaseReferences<
              _$AppDatabase,
              $SeenAnnouncementsTable,
              SeenAnnouncementRow
            >,
          ),
          SeenAnnouncementRow,
          PrefetchHooks Function()
        > {
  $$SeenAnnouncementsTableTableManager(
    _$AppDatabase db,
    $SeenAnnouncementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeenAnnouncementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeenAnnouncementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeenAnnouncementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<int> remoteId = const Value.absent(),
                Value<DateTime> seenAt = const Value.absent(),
              }) => SeenAnnouncementsCompanion(
                id: id,
                contentHash: contentHash,
                remoteId: remoteId,
                seenAt: seenAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String contentHash,
                required int remoteId,
                required DateTime seenAt,
              }) => SeenAnnouncementsCompanion.insert(
                id: id,
                contentHash: contentHash,
                remoteId: remoteId,
                seenAt: seenAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeenAnnouncementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeenAnnouncementsTable,
      SeenAnnouncementRow,
      $$SeenAnnouncementsTableFilterComposer,
      $$SeenAnnouncementsTableOrderingComposer,
      $$SeenAnnouncementsTableAnnotationComposer,
      $$SeenAnnouncementsTableCreateCompanionBuilder,
      $$SeenAnnouncementsTableUpdateCompanionBuilder,
      (
        SeenAnnouncementRow,
        BaseReferences<
          _$AppDatabase,
          $SeenAnnouncementsTable,
          SeenAnnouncementRow
        >,
      ),
      SeenAnnouncementRow,
      PrefetchHooks Function()
    >;
typedef $$EventOverridesTableCreateCompanionBuilder =
    EventOverridesCompanion Function({
      Value<int> id,
      Value<int?> sourceEventId,
      Value<String> topic,
      required String sessionLabel,
      Value<DateTime?> regStart,
      Value<DateTime?> regEnd,
      Value<DateTime?> examDate,
      Value<DateTime?> resultDate,
      Value<String> note,
      required DateTime updatedAt,
    });
typedef $$EventOverridesTableUpdateCompanionBuilder =
    EventOverridesCompanion Function({
      Value<int> id,
      Value<int?> sourceEventId,
      Value<String> topic,
      Value<String> sessionLabel,
      Value<DateTime?> regStart,
      Value<DateTime?> regEnd,
      Value<DateTime?> examDate,
      Value<DateTime?> resultDate,
      Value<String> note,
      Value<DateTime> updatedAt,
    });

class $$EventOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $EventOverridesTable> {
  $$EventOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionLabel => $composableBuilder(
    column: $table.sessionLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get regStart => $composableBuilder(
    column: $table.regStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get regEnd => $composableBuilder(
    column: $table.regEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get examDate => $composableBuilder(
    column: $table.examDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resultDate => $composableBuilder(
    column: $table.resultDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $EventOverridesTable> {
  $$EventOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topic => $composableBuilder(
    column: $table.topic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionLabel => $composableBuilder(
    column: $table.sessionLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get regStart => $composableBuilder(
    column: $table.regStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get regEnd => $composableBuilder(
    column: $table.regEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get examDate => $composableBuilder(
    column: $table.examDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resultDate => $composableBuilder(
    column: $table.resultDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventOverridesTable> {
  $$EventOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get topic =>
      $composableBuilder(column: $table.topic, builder: (column) => column);

  GeneratedColumn<String> get sessionLabel => $composableBuilder(
    column: $table.sessionLabel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get regStart =>
      $composableBuilder(column: $table.regStart, builder: (column) => column);

  GeneratedColumn<DateTime> get regEnd =>
      $composableBuilder(column: $table.regEnd, builder: (column) => column);

  GeneratedColumn<DateTime> get examDate =>
      $composableBuilder(column: $table.examDate, builder: (column) => column);

  GeneratedColumn<DateTime> get resultDate => $composableBuilder(
    column: $table.resultDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EventOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventOverridesTable,
          EventOverrideRow,
          $$EventOverridesTableFilterComposer,
          $$EventOverridesTableOrderingComposer,
          $$EventOverridesTableAnnotationComposer,
          $$EventOverridesTableCreateCompanionBuilder,
          $$EventOverridesTableUpdateCompanionBuilder,
          (
            EventOverrideRow,
            BaseReferences<
              _$AppDatabase,
              $EventOverridesTable,
              EventOverrideRow
            >,
          ),
          EventOverrideRow,
          PrefetchHooks Function()
        > {
  $$EventOverridesTableTableManager(
    _$AppDatabase db,
    $EventOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventOverridesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> sourceEventId = const Value.absent(),
                Value<String> topic = const Value.absent(),
                Value<String> sessionLabel = const Value.absent(),
                Value<DateTime?> regStart = const Value.absent(),
                Value<DateTime?> regEnd = const Value.absent(),
                Value<DateTime?> examDate = const Value.absent(),
                Value<DateTime?> resultDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => EventOverridesCompanion(
                id: id,
                sourceEventId: sourceEventId,
                topic: topic,
                sessionLabel: sessionLabel,
                regStart: regStart,
                regEnd: regEnd,
                examDate: examDate,
                resultDate: resultDate,
                note: note,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> sourceEventId = const Value.absent(),
                Value<String> topic = const Value.absent(),
                required String sessionLabel,
                Value<DateTime?> regStart = const Value.absent(),
                Value<DateTime?> regEnd = const Value.absent(),
                Value<DateTime?> examDate = const Value.absent(),
                Value<DateTime?> resultDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                required DateTime updatedAt,
              }) => EventOverridesCompanion.insert(
                id: id,
                sourceEventId: sourceEventId,
                topic: topic,
                sessionLabel: sessionLabel,
                regStart: regStart,
                regEnd: regEnd,
                examDate: examDate,
                resultDate: resultDate,
                note: note,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventOverridesTable,
      EventOverrideRow,
      $$EventOverridesTableFilterComposer,
      $$EventOverridesTableOrderingComposer,
      $$EventOverridesTableAnnotationComposer,
      $$EventOverridesTableCreateCompanionBuilder,
      $$EventOverridesTableUpdateCompanionBuilder,
      (
        EventOverrideRow,
        BaseReferences<_$AppDatabase, $EventOverridesTable, EventOverrideRow>,
      ),
      EventOverrideRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WeatherCacheTableTableManager get weatherCache =>
      $$WeatherCacheTableTableManager(_db, _db.weatherCache);
  $$FixedRoutePointsTableTableManager get fixedRoutePoints =>
      $$FixedRoutePointsTableTableManager(_db, _db.fixedRoutePoints);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$NoteItemsTableTableManager get noteItems =>
      $$NoteItemsTableTableManager(_db, _db.noteItems);
  $$SeenAnnouncementsTableTableManager get seenAnnouncements =>
      $$SeenAnnouncementsTableTableManager(_db, _db.seenAnnouncements);
  $$EventOverridesTableTableManager get eventOverrides =>
      $$EventOverridesTableTableManager(_db, _db.eventOverrides);
}
