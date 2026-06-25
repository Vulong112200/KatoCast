---
name: sync-docs
description: Cập nhật documentation framework của KatoCast (CLAUDE.md + .claude/docs/) cho khớp với thay đổi code gần nhất — cấu trúc, chức năng, và luồng hoạt động. Dùng SAU KHI thêm/sửa/xóa code, hoặc khi user gõ /sync-docs.
---

# sync-docs — Đồng bộ tài liệu với code

Mục tiêu: giữ `CLAUDE.md` và 3 file trong `.claude/docs/` luôn phản ánh đúng code thực tế của KatoCast.
**Nguyên tắc:** docs phải khớp code. Nếu lệch → sửa docs, không sửa code.

## Bước 1 — Xác định thay đổi

Tìm những file đã thay đổi:
- Nếu là git repo: `git diff HEAD~1 --name-only` và `git status --short`.
- Nếu không phải git repo (hoặc mới khởi tạo): so sánh mtime — file source mới hơn `.claude/docs/structure.md` là file cần xét. Hỏi user nếu không rõ scope.

Phân loại:
- **Backend:** `backend/app/api/`, `services/`, `models/`, `schemas/`, `repositories/`, `core/`
- **Mobile:** `mobile/lib/features/`, `mobile/lib/core/`, `mobile/lib/shared/`
- File **mới tạo** / **bị xóa** / **đổi tên**

## Bước 2 — Cập nhật `CLAUDE.md` (root)

Đọc `CLAUDE.md`, cập nhật các bảng registry:
- **Key Features Registry**: thêm/sửa row, đổi status (📋→🚧→✅).
- **API Endpoints Summary**: thêm endpoint mới vào đúng group.
- **Database Models**: thêm table/field quan trọng + quan hệ.
- **Shared Utilities**: nếu thêm util/widget mới.
- **File quan trọng nhất**: bổ sung nếu có file core mới.

## Bước 3 — Cập nhật `.claude/docs/features.md`

- Feature mới → thêm section theo **format chuẩn** (Status / Backend / Mobile / Key logic) đã ghi đầu file.
- Feature hoàn thiện thêm → cập nhật "Key logic", đổi status.
- Cập nhật bảng **Database Tables Status** nếu thêm/sửa table.
- Cập nhật **Mobile Providers — State Map** nếu thêm provider.

## Bước 4 — Cập nhật `.claude/docs/structure.md`

- Thêm entry cho file/thư mục mới + comment ngắn mô tả mục đích.
- Xóa entry cho file đã bị xóa; sửa entry khi đổi tên.
- Giữ đúng định dạng cây thư mục hiện có.

## Bước 5 — Cập nhật `.claude/docs/callflows.md` (chỉ khi cần)

Chỉ cập nhật nếu có: flow mới, endpoint đổi logic, hoặc thêm step vào flow hiện có.
Mô tả theo chuỗi UI → provider → repository → backend service → repo → DB → response.

## Bước 6 — Báo cáo

Tóm tắt ngắn gọn: đã cập nhật file nào, section nào, thay đổi gì. Nếu không có gì cần cập nhật, nói rõ.

---
**Lưu ý:** không tự bịa nội dung. Chỉ ghi những gì thực sự có trong code. Đọc file nguồn trước khi mô tả.
