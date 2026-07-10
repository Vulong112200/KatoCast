# KatoAssistant — Backend (FastAPI)

Theo dõi thông báo chính thức (JLPT, MBA, chủ đề tùy chỉnh): crawl whitelist nguồn GỐC → diff phát hiện mục MỚI → (tùy chọn) LLM phân loại/tóm tắt → lưu Postgres → expose REST cho app mobile poll 1 lần/ngày.

## Layering
`api/v1` → `services` → `repositories` → `models` (theo `CLAUDE.md`). Pydantic v2 DTO trong `schemas`.

## Chạy dev (SQLite, không cần Postgres)
```bash
cd backend
python -m venv .venv && . .venv/Scripts/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env          # để trống DATABASE_URL → dùng SQLite mặc định
python -m app.jobs.seed_sources        # nạp nguồn JLPT chính thức
uvicorn app.main:app --reload          # http://127.0.0.1:8000/docs
```
Bảng tự tạo khi khởi động (lifespan). Prod dùng Alembic: `alembic upgrade head`.

## Crawl
- Thủ công: `python -m app.jobs.daily_crawl [topic]` hoặc `POST /api/v1/crawl?topic=jlpt`.
- Cron 1/ngày: gọi lệnh trên bằng cron OS / Cloud Scheduler / GitHub Actions.

## API
- `GET /api/v1/announcements?topic=jlpt&since=<ISO8601>` → danh sách thông báo.
- `GET/POST /api/v1/watch-sources` → quản lý nguồn (thêm nguồn MBA của trường bạn).
- `GET /health`.

## Xác thực / chống fake
- Chỉ crawl nguồn trong `watch_sources` (whitelist chính thức). Mỗi mục kèm `source_url` + `source_domain` để kiểm chứng.
- `ANTHROPIC_API_KEY` có → dùng Claude Haiku phân loại khớp chủ đề + tóm tắt (không bịa dữ kiện). Không có key → rule-based (keyword + mốc ngày).

## Test
```bash
pytest
```

## Deploy gợi ý
Container uvicorn + Postgres managed (Neon/Supabase). Cron gọi `daily_crawl` (Cloud Scheduler/GitHub Actions). Không cần Redis cho v1.
