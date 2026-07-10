/// Lịch CÓ CẤU TRÚC của một kỳ thi / đợt tuyển sinh (mốc đăng ký → thi → kết quả).
///
/// Nguồn: backend `exam_events` (curated = lịch chuẩn đã kiểm chứng) HOẶC người
/// dùng tự thêm/sửa (lưu Drift `event_overrides`). `isUserVerified` = do người
/// dùng xác nhận/sửa → LUÔN ưu tiên & hiển thị "đã kiểm chứng".
///
/// Trạng thái còn hạn/hết hạn KHÔNG lưu ở đây — tính client-side (event_status).
class ExamEvent {
  /// id bản ghi backend (null nếu là event người dùng tự thêm, không gắn backend).
  final int? backendId;

  /// id bản ghi override local (null nếu chưa có bản sửa tay nào cho event này).
  final int? overrideId;

  final String topic; // jlpt | mba | custom
  final String sessionLabel;
  final DateTime? regStart;
  final DateTime? regEnd;
  final DateTime? examDate;
  final DateTime? resultDate;
  final String sourceUrl;
  final String sourceDomain;
  final bool curated;
  final String note;
  final DateTime? updatedAt;
  final bool isUserVerified;

  const ExamEvent({
    this.backendId,
    this.overrideId,
    required this.topic,
    required this.sessionLabel,
    this.regStart,
    this.regEnd,
    this.examDate,
    this.resultDate,
    this.sourceUrl = '',
    this.sourceDomain = '',
    this.curated = false,
    this.note = '',
    this.updatedAt,
    this.isUserVerified = false,
  });

  /// Đã có người kiểm chứng (curated backend hoặc người dùng sửa) → tin cậy cao.
  bool get isTrusted => curated || isUserVerified;

  static DateTime? _date(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }

  factory ExamEvent.fromJson(Map<String, dynamic> json) {
    return ExamEvent(
      backendId: (json['id'] as num?)?.toInt(),
      topic: json['topic'] as String? ?? 'custom',
      sessionLabel: json['session_label'] as String? ?? '',
      regStart: _date(json['registration_start']),
      regEnd: _date(json['registration_end']),
      examDate: _date(json['exam_date']),
      resultDate: _date(json['result_date']),
      sourceUrl: json['source_url'] as String? ?? '',
      sourceDomain: json['source_domain'] as String? ?? '',
      curated: json['curated'] as bool? ?? false,
      note: json['note'] as String? ?? '',
      updatedAt: _date(json['updated_at']),
    );
  }

  ExamEvent copyWith({
    int? backendId,
    int? overrideId,
    String? topic,
    String? sessionLabel,
    DateTime? regStart,
    DateTime? regEnd,
    DateTime? examDate,
    DateTime? resultDate,
    String? sourceUrl,
    String? sourceDomain,
    bool? curated,
    String? note,
    DateTime? updatedAt,
    bool? isUserVerified,
  }) {
    return ExamEvent(
      backendId: backendId ?? this.backendId,
      overrideId: overrideId ?? this.overrideId,
      topic: topic ?? this.topic,
      sessionLabel: sessionLabel ?? this.sessionLabel,
      regStart: regStart ?? this.regStart,
      regEnd: regEnd ?? this.regEnd,
      examDate: examDate ?? this.examDate,
      resultDate: resultDate ?? this.resultDate,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceDomain: sourceDomain ?? this.sourceDomain,
      curated: curated ?? this.curated,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      isUserVerified: isUserVerified ?? this.isUserVerified,
    );
  }
}
