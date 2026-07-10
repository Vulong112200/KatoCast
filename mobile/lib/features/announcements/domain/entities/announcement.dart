/// Một thông báo (kỳ thi JLPT / khoá MBA / chủ đề khác) do backend
/// KatoAssistant crawl từ nguồn GỐC chính thức, đã diff & (tùy chọn) xác thực.
///
/// `sourceUrl` + `sourceDomain` luôn là nguồn chính thức để người dùng tự kiểm
/// chứng (chống tin giả). `contentHash` ổn định theo nội dung → khoá chống báo
/// lại ở phía app.
class Announcement {
  final int id;
  final String topic; // jlpt | mba | custom
  final String title;
  final String summary;
  final String sourceUrl;
  final String sourceDomain;
  final DateTime firstSeenAt;
  final String contentHash;
  final bool verified;
  final double score;

  const Announcement({
    required this.id,
    required this.topic,
    required this.title,
    required this.summary,
    required this.sourceUrl,
    required this.sourceDomain,
    required this.firstSeenAt,
    required this.contentHash,
    required this.verified,
    required this.score,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: (json['id'] as num).toInt(),
      topic: json['topic'] as String? ?? 'custom',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      sourceDomain: json['source_domain'] as String? ?? '',
      firstSeenAt: DateTime.tryParse(json['first_seen_at'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now(),
      contentHash: json['content_hash'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
