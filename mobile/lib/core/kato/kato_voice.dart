/// Giọng điệu của **Kato** — chú mèo Bengal lai mèo rừng ta (lông nâu sọc
/// trắng) mà app được đặt tên theo. Gom mọi câu mở đầu mang "nhân cách mèo"
/// vào một nơi để nhất quán, dễ chỉnh, dễ tắt.
///
/// Nguyên tắc "vừa phải, có cá tính": mỗi hàm trả về **một cụm mở đầu ngắn**
/// (đã kèm dấu cách ở cuối) để ghép vào ĐẦU body thông báo — phần số liệu/
/// thông tin thời tiết phía sau giữ NGUYÊN. Không thêm nhiều dòng, không đổi
/// nội dung dự báo.
///
/// Chọn biến thể theo [seed] (thường là phút của mốc dữ liệu) — thuần, tất
/// định, KHÔNG dùng `Random`/`DateTime.now()` để test được và chạy an toàn
/// trong background isolate.
class KatoVoice {
  const KatoVoice._();

  static String _pick(List<String> variants, int seed) =>
      variants[seed.abs() % variants.length];

  /// Sắp có mưa — Kato "đánh hơi" cơn mưa.
  static String rainIncoming(int seed) => _pick(const [
        'Kato ngửi thấy mùi mưa sắp tới 🐾 ',
        'Râu Kato rung rung báo mưa 🐾 ',
        'Kato mách nhỏ: trời sắp mưa đó nha 🐾 ',
      ], seed);

  /// Trời đang mưa — Kato cuộn tròn tránh mưa.
  static String raining(int seed) => _pick(const [
        'Kato đang cuộn tròn trốn mưa 🐈 ',
        'Ngoài trời đang mưa, Kato khuyên ở trong cho ấm 🐾 ',
        'Mưa rồi, Kato không thích ướt lông đâu 🐈 ',
      ], seed);

  /// Mưa sắp tạnh.
  static String rainStopping(int seed) => _pick(const [
        'Kato thấy mây đang tan dần 🐾 ',
        'Sắp tạnh rồi, Kato chuẩn bị đi dạo 🐈 ',
      ], seed);

  /// Trời đã tạnh / quang đãng.
  static String cleared(int seed) => _pick(const [
        'Kato vươn vai vì trời đã tạnh 🐾 ',
        'Trời tạnh rồi, Kato ra sưởi nắng đây 🐈 ',
      ], seed);

  /// Môi trường (nhiệt/ẩm) thay đổi mạnh — Kato là "cảm biến" nhạy.
  static String envChange(int seed) => _pick(const [
        'Kato hơi khó chịu vì không khí đổi nhanh 🐾 ',
        'Lông Kato dựng nhẹ — thời tiết đang đổi mạnh 🐈 ',
      ], seed);

  /// Có tin mới về chủ đề đang theo dõi (kỳ thi/khoá học) — Kato "tha tin về".
  static String announcement(int seed) => _pick(const [
        'Kato tha tin mới về cho sen đây 🐾 ',
        'Meo~ Kato hóng được tin mới nè 🐈 ',
        'Kato mang tin sen đang chờ về đây 🐾 ',
      ], seed);

  /// Câu chào mở đầu bản tin hằng ngày, phân biệt sáng/tối.
  static String digest({required bool morning, required int seed}) {
    return morning
        ? _pick(const [
            'Kato chào buổi sáng, sen ơi! ☀️🐾 ',
            'Kato dậy sớm hóng thời tiết cho bạn đây 🐾 ',
          ], seed)
        : _pick(const [
            'Kato tổng kết thời tiết chiều tối cho bạn 🌙🐾 ',
            'Chiều rồi, Kato điểm tin thời tiết nhé 🐾 ',
          ], seed);
  }
}
