"""Test regex trích ngày (JP/VN/EN) + gán nhãn."""

from app.services.date_extract import extract_dates


def _dates(text: str) -> set[str]:
    return {d["date"] for d in extract_dates(text)}


def _labeled(text: str) -> set[tuple[str, str]]:
    return {(d["date"], d["label"]) for d in extract_dates(text)}


def test_japanese_ymd() -> None:
    assert "2026-07-10" in _dates("試験は2026年7月10日に実施")


def test_reiwa_era() -> None:
    # 令和8年 = 2026
    assert "2026-07-05" in _dates("令和8年7月5日 試験日")


def test_western_slash() -> None:
    assert "2026-07-05" in _dates("Exam date: 2026/07/05")


def test_vn_dmy() -> None:
    assert "2026-03-20" in _dates("đăng ký từ 20/3/2026")


def test_two_digit_year() -> None:
    assert "2026-04-23" in _dates("hạn 23/4/26")


def test_label_registration() -> None:
    assert ("2026-03-17", "registration") in _labeled("申込期間 2026/03/17")


def test_label_exam() -> None:
    assert ("2026-07-05", "exam") in _labeled("試験日 2026年7月5日")


def test_label_deadline() -> None:
    assert ("2026-04-07", "deadline") in _labeled("hạn chót nộp hồ sơ 7/4/2026")


def test_empty() -> None:
    assert extract_dates("") == []
    assert extract_dates("không có ngày nào") == []


def test_invalid_month_ignored() -> None:
    # 13 tháng không hợp lệ → bỏ
    assert "2026-13-01" not in _dates("2026/13/01")
