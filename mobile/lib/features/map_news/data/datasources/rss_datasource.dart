import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../domain/repositories/news_repository.dart';

/// Đọc tin tức thời tiết/cảnh báo từ RSS (miễn phí, không cần API key).
///
/// Lưu ý: RSS không gắn toạ độ nên tin mang tính khu vực/chủ đề (thời tiết,
/// thiên tai) thay vì lọc chính xác theo bán kính GPS.
class RssDataSource {
  final Dio _dio;

  RssDataSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              responseType: ResponseType.plain,
            ));

  /// Nguồn RSS mặc định: chuyên mục thời tiết VnExpress.
  static const String defaultFeedUrl = 'https://vnexpress.net/rss/thoi-tiet.rss';

  /// Lấy danh sách tin từ một feed RSS. Trả [] nếu lỗi mạng/parse.
  Future<List<NewsItem>> fetchFeed({String? feedUrl, int limit = 20}) async {
    try {
      final res = await _dio.get<String>(feedUrl ?? defaultFeedUrl);
      final body = res.data;
      if (body == null || body.isEmpty) return [];

      final doc = XmlDocument.parse(body);
      final items = doc.findAllElements('item').take(limit);

      final out = <NewsItem>[];
      for (final item in items) {
        final title = _text(item, 'title');
        final link = _text(item, 'link');
        if (title == null || link == null) continue;
        out.add(NewsItem(
          title: title,
          url: link,
          publishedAt: _parseDate(_text(item, 'pubDate')),
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  String? _text(XmlElement parent, String tag) {
    final el = parent.findElements(tag).firstOrNull;
    final value = el?.innerText.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// RSS pubDate dạng RFC-822 (vd "Mon, 28 Jun 2026 10:00:00 +0700").
  /// Parse thủ công phần ngày/tháng/năm; lỗi → null.
  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    try {
      // "Mon, 28 Jun 2026 10:00:00 +0700"
      final parts = raw.split(' ');
      if (parts.length < 5) return null;
      final day = int.parse(parts[1]);
      final month = _months[parts[2]];
      final year = int.parse(parts[3]);
      if (month == null) return null;
      final time = parts[4].split(':');
      return DateTime(
        year,
        month,
        day,
        int.tryParse(time[0]) ?? 0,
        time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0,
      );
    } catch (_) {
      return null;
    }
  }

  static const Map<String, int> _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
}
