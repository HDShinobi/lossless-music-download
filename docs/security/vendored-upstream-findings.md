# Vendored upstream — known security findings (historical Go engine)

Phát hiện bởi automated security review khi vendor engine Go (commit b7ff9e91).
Engine này đã bị xoá trong phase 5; source lịch sử nằm trên rollback branch
`release/0.9.x-go`. Các finding và disposition dưới đây là ghi nhận tại thời điểm
review, không phải kết luận security về engine Rust hiện tại.

| # | Mức | File | Vấn đề |
|---|---|---|---|
| 1 | HIGH | `extension_runtime_http.go` (engine Go lịch sử) | SSRF via redirect bypass — `validateDomain` không re-validate mỗi hop redirect. Fix: set `CheckRedirect` re-validate trên `httpClient` + `downloadClient` (trong `newExtensionHTTPClient`). |
| 2 | MEDIUM | `extension_runtime_auth.go` (engine Go lịch sử) | SSRF / DNS-rebinding — validator chỉ check hostname, không resolve IP. Fix: `LookupIP` + reject loopback/link-local/RFC1918/::1/0.0.0.0, pin IP khi dial. |

## Disposition (2026-06-21)
- **Chưa khai thác được hiện tại:** chưa có extension nào chạy; sandbox whitelist domain theo manifest.
- **KHÔNG sửa file vendored** (giữ pristine để merge upstream không vỡ).
- **Xử lý khi:** wiring extension runtime (Phase 2) — hoặc gửi PR fix lên upstream SpotiFLAC. Nếu phải vá trước khi upstream fix: giữ patch ở file riêng / documented vendor-patch re-apply khi sync.
