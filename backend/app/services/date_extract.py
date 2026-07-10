"""Regex trích mốc ngày từ văn bản thông báo (JP/VN/EN).

KHÔNG dùng LLM. Chuẩn hoá mọi định dạng về ISO (YYYY-MM-DD) và phỏng đoán NHÃN
(registration/exam/deadline/result) theo keyword lân cận. Nhãn chỉ là gợi ý →
UI phải ghi rõ "chưa kiểm chứng". Lịch CHUẨN lấy từ exam_events (seed), không từ đây.
"""

from __future__ import annotations

import re

# ── Từ khoá gán nhãn (window ±KW_WINDOW ký tự quanh ngày) ────────────────────
KW_WINDOW = 40

_LABEL_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    # thứ tự ưu tiên: deadline & result kiểm tra trước exam/registration để không bị nuốt
    ("deadline", ("締切", "締め切り", "〆切", "期限", "hạn chót", "hạn nộp", "deadline", "due")),
    ("result", ("結果", "発表", "合格発表", "kết quả", "result", "announce")),
    ("registration", ("申込", "申し込み", "出願", "受付", "登録", "申請", "đăng ký", "đăng kí", "registration", "apply", "application", "enrol")),
    ("exam", ("試験", "実施", "受験", "thi", "kỳ thi", "exam", "test")),
]

# ── Regex ngày ───────────────────────────────────────────────────────────────
# 2026年7月10日 · 令和8年7月10日
_JP_ERA = {"令和": 2018, "平成": 1988}
_RE_JP = re.compile(
    r"(?:(令和|平成)\s*(\d{1,2}|元)\s*年|(\d{4})\s*年)\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"
)
# 2026/07/10 · 2026-07-10 · 2026.7.10  (năm ở ĐẦU → không mơ hồ)
_RE_YMD = re.compile(r"(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})")
# 10/7/2026 · 10-7-2026 · 23.4.26  (ngày ở đầu, kiểu VN dd/mm/yyyy)
_RE_DMY = re.compile(r"(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})")


def _valid(y: int, m: int, d: int) -> bool:
    return 2000 <= y <= 2100 and 1 <= m <= 12 and 1 <= d <= 31


def _iso(y: int, m: int, d: int) -> str:
    return f"{y:04d}-{m:02d}-{d:02d}"


def _label_for(text: str, start: int, end: int) -> str:
    """Gán nhãn theo keyword GẦN ngày nhất (khoảng cách ký tự tới span ngày).
    Hoà nhau → theo thứ tự ưu tiên trong _LABEL_KEYWORDS."""
    lo = max(0, start - KW_WINDOW)
    hi = min(len(text), end + KW_WINDOW)
    window = text[lo:hi].lower()
    # vị trí span ngày tương đối trong window
    d_lo, d_hi = start - lo, end - lo
    best_label = "unknown"
    best_dist = None
    for prio, (label, kws) in enumerate(_LABEL_KEYWORDS):
        for kw in kws:
            k = kw.lower()
            idx = window.find(k)
            while idx != -1:
                # khoảng cách từ keyword tới span ngày (0 nếu chồng lấn)
                if idx + len(k) <= d_lo:
                    dist = d_lo - (idx + len(k))
                elif idx >= d_hi:
                    dist = idx - d_hi
                else:
                    dist = 0
                if best_dist is None or dist < best_dist:
                    best_dist, best_label = dist, label
                idx = window.find(k, idx + 1)
    return best_label


def extract_dates(text: str) -> list[dict]:
    """Trả danh sách {date: ISO, label, raw} theo thứ tự xuất hiện, đã khử trùng
    (date+label). Rỗng nếu không có ngày hợp lệ."""
    if not text:
        return []
    found: list[dict] = []
    seen: set[tuple[str, str]] = set()

    def _add(y: int, m: int, d: int, mstart: int, mend: int, raw: str) -> None:
        if not _valid(y, m, d):
            return
        iso = _iso(y, m, d)
        label = _label_for(text, mstart, mend)
        key = (iso, label)
        if key in seen:
            return
        seen.add(key)
        found.append({"date": iso, "label": label, "raw": raw.strip()})

    for mt in _RE_JP.finditer(text):
        era, era_y, west_y, mm, dd = mt.groups()
        if era:
            base = _JP_ERA.get(era, 0)
            yv = 1 if era_y == "元" else int(era_y)
            year = base + yv
        else:
            year = int(west_y)
        _add(year, int(mm), int(dd), mt.start(), mt.end(), mt.group(0))

    for mt in _RE_YMD.finditer(text):
        y, m, d = (int(g) for g in mt.groups())
        _add(y, m, d, mt.start(), mt.end(), mt.group(0))

    for mt in _RE_DMY.finditer(text):
        d, m, yy = (int(g) for g in mt.groups())
        year = yy + 2000 if yy < 100 else yy
        _add(year, m, d, mt.start(), mt.end(), mt.group(0))

    return found
