# Testing Guide

## Unit & Golden Tests

Run all unit and golden tests:

```bash
flutter test
```

Run only golden tests:

```bash
flutter test test/golden/
```

Regenerate golden baselines (e.g. after intentional UI changes):

```bash
flutter test --update-goldens test/golden/
```

Golden files are stored alongside tests under `test/golden/goldens/`.

## Integration Tests (Patrol)

Patrol integration tests require a connected device or emulator:

```bash
flutter test integration_test/ -d <device-id>
```

Install the Patrol CLI:

```bash
dart pub global activate patrol_cli
```

Run Patrol tests via the patrol CLI:

```bash
patrol test
```

## Maestro UI Flows

Install Maestro CLI:

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

Run the smoke flow against a running app on a connected device:

```bash
maestro test .maestro/smoke.yaml
```

### Maestro MCP (Claude Code integration)

The `.mcp.json` at the project root registers the Maestro MCP server for Claude Code. Claude Code auto-discovers it.

If you need to register it manually:

```bash
claude mcp add maestro -- maestro mcp
```

## Dependencies

| Package      | Version | Purpose                       |
|--------------|---------|-------------------------------|
| alchemist    | ^0.14.0 | Golden test framework         |
| patrol       | ^4.6.0  | Integration test framework    |
| mocktail     | ^1.0.0  | Mocking for unit tests        |
| flutter_test | SDK     | Core test utilities           |

## E2E that (thu cong)

Quy trinh kiem thu luong tai nhac that su tu dau den cuoi (CI dung mock nen khong bao phu buoc nay):

1. Chay app tren thiet bi kem hoac emulator: `flutter run -d <device-id>`.
2. Vao **Cai dat** (tab Settings) → **Nguon & Extension** → tab **Kham pha** → bam **Doi** ben canh Nguon tong hop → dan URL cua mot registry that (vi du registry cong dong) → bam **Luu**.
3. Sau khi danh sach extension hien ra, chon mot extension loai **Tai** (Download) → bam **Cai**. Cho den khi hien "Da cai".
4. Chuyen sang tab **Da cai** → bat extension vua cai bang cong tac **Bat/Tat**.
5. Vao tab **Tim** → nhap ten bai hat → bam bieu tuong Tai ben canh ket qua. Thong bao "Da them vao hang doi" xuat hien.
6. Vao tab **Hang doi** → xac nhan thay thanh tien trinh cua bai vua yeu cau tai.
7. Doi den khi tien trinh hoan thanh → vao tab **Thu vien** → xac nhan thay file `.flac` (hoac dinh dang do extension ho tro) cung kich thuoc > 0.

**Luu y:** Cac buoc 2-7 phu thuoc vao extension va ket noi mang thuc, do do khong dua vao CI. Chi chay thu cong truoc khi phat hanh.

