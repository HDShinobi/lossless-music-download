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
