# Vendored upstream — known security findings (tracked, not yet fixed)

Phát hiện bởi automated security review khi vendor `go_backend/` (commit b7ff9e91).
Đây là code **upstream SpotiFLAC giữ pristine** (hướng A: không sửa để sync sạch).

| # | Mức | File | Vấn đề |
|---|---|---|---|
| 1 | HIGH | `go_backend/extension_runtime_http.go` | SSRF via redirect bypass — `validateDomain` không re-validate mỗi hop redirect. Fix: set `CheckRedirect` re-validate trên `httpClient` + `downloadClient` (trong `newExtensionHTTPClient`). |
| 2 | MEDIUM | `go_backend/extension_runtime_auth.go` | SSRF / DNS-rebinding — validator chỉ check hostname, không resolve IP. Fix: `LookupIP` + reject loopback/link-local/RFC1918/::1/0.0.0.0, pin IP khi dial. |

## Disposition (2026-06-21)
- **Chưa khai thác được hiện tại:** chưa có extension nào chạy; sandbox whitelist domain theo manifest.
- **KHÔNG sửa file vendored** (giữ pristine để merge upstream không vỡ).
- **Xử lý khi:** wiring extension runtime (Phase 2) — hoặc gửi PR fix lên upstream SpotiFLAC. Nếu phải vá trước khi upstream fix: giữ patch ở file riêng / documented vendor-patch re-apply khi sync.
