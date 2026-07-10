"""Xác thực + phân loại mục tin.

Nguyên tắc: LLM (nếu có key) CHỈ phân loại "có khớp chủ đề không" + tóm tắt.
KHÔNG bịa dữ kiện — title/url/nội dung luôn lấy nguyên từ nguồn.
Không có key → rule-based fallback dựa trên keyword của WatchSource.
"""

from __future__ import annotations

import json
import re

from app.core.config import get_settings

# Từ khoá mặc định theo chủ đề (bổ trợ cho keywords cấu hình trong WatchSource)
_TOPIC_KEYWORDS: dict[str, list[str]] = {
    "jlpt": ["jlpt", "日本語能力試験", "出願", "申込", "試験", "受験", "登録", "đăng ký", "kỳ thi"],
    "mba": ["mba", "master", "thạc sĩ", "admission", "出願", "募集", "tuyển sinh", "gmat"],
}

_DATE_RE = re.compile(
    r"(\d{4}[/年.\-]\d{1,2}[/月.\-]\d{1,2})|(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4})"
)


class VerifyResult:
    def __init__(self, matched: bool, score: float, summary: str) -> None:
        self.matched = matched
        self.score = score
        self.summary = summary


def _rule_based(topic: str, title: str, text: str, keywords: str) -> VerifyResult:
    haystack = f"{title}\n{text}".lower()
    kws = [k.strip().lower() for k in keywords.split("|") if k.strip()]
    kws += _TOPIC_KEYWORDS.get(topic, [])
    hits = sum(1 for k in kws if k and k.lower() in haystack)
    has_date = bool(_DATE_RE.search(f"{title}\n{text}"))
    # điểm: có keyword + có mốc ngày (thông báo lịch thường kèm ngày) → tin cậy hơn
    score = min(1.0, 0.25 * hits + (0.3 if has_date else 0.0))
    matched = hits > 0
    summary = title.strip()[:280]
    if topic == "mba" and "gmat" in haystack and (
        "not require" in haystack or "no gmat" in haystack or "miễn" in haystack
    ):
        summary = "⭐ Có thể KHÔNG yêu cầu GMAT — " + summary
    return VerifyResult(matched, round(score, 3), summary)


async def verify(topic: str, title: str, text: str, keywords: str = "") -> VerifyResult:
    settings = get_settings()
    if not settings.has_llm:
        return _rule_based(topic, title, text, keywords)

    try:
        from anthropic import AsyncAnthropic

        client = AsyncAnthropic(api_key=settings.anthropic_api_key)
        prompt = (
            f"Chủ đề quan tâm: {topic}.\n"
            f"Tiêu đề: {title}\n"
            f"Nội dung trích: {text[:1500]}\n\n"
            "Đây có phải thông báo CHÍNH THỨC khớp chủ đề trên không? "
            'Với MBA, để ý điều kiện "không yêu cầu GMAT". '
            "Chỉ dựa trên nội dung đã cho, KHÔNG suy đoán thêm dữ kiện. "
            'Trả về JSON: {"matched": bool, "score": 0..1, "summary": "1-2 câu tiếng Việt"}.'
        )
        msg = await client.messages.create(
            model=settings.verify_model,
            max_tokens=300,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        data = json.loads(m.group(0)) if m else {}
        return VerifyResult(
            matched=bool(data.get("matched", False)),
            score=float(data.get("score", 0.0)),
            summary=str(data.get("summary", title))[:280],
        )
    except Exception:
        # LLM lỗi/timeout → không được mất tin: dùng rule-based
        return _rule_based(topic, title, text, keywords)
