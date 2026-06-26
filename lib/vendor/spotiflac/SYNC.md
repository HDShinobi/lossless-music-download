# SpotiFLAC Vendor Sync Guide

## Source

- Repo: `/Users/dinhvanhoang/Projects/SpotiFLAC-Mobile` (MIT, Copyright 2026 zarzet)
- Commit: `7b22bbf2`
- Upstream files vendored:
  - `lib/widgets/audio_analysis_widget.dart` (1953 lines)
  - `lib/widgets/settings_group.dart` (259 lines)

## Files in this directory

| File | Origin | Edits |
|------|--------|-------|
| `audio_analysis_widget.dart` | upstream `lib/widgets/audio_analysis_widget.dart` | 3-line header + import rewrites only (body verbatim) |
| `settings_group.dart` | upstream `lib/widgets/settings_group.dart` | 1-line header only (no spotiflac imports to rewrite; body verbatim) |
| `compat_l10n.dart` | NEW (ours) | provides `context.l10n` extension with all `audioAnalysis*` + `trackConvertBitrate` keys |
| `compat_platform_bridge.dart` | NEW (ours) | `PlatformBridge` stub for direct file paths |

## Exact import rewrites applied to `audio_analysis_widget.dart`

The complete manual transform is: prepend the 3-line header comment, then apply these
5 import-line substitutions (the ONLY changes to the file):

```
package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart        -> package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart
package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart -> package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart
package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart       -> package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart
package:ffmpeg_kit_flutter_new_full/level.dart             -> package:ffmpeg_kit_flutter_new_audio/level.dart
package:ffmpeg_kit_flutter_new_full/return_code.dart       -> package:ffmpeg_kit_flutter_new_audio/return_code.dart
package:spotiflac_android/widgets/settings_group.dart      -> settings_group.dart
package:spotiflac_android/l10n/l10n.dart                   -> compat_l10n.dart
package:spotiflac_android/services/platform_bridge.dart    -> compat_platform_bridge.dart
```

## Re-sync procedure

1. Copy the new upstream file over the vendored one:
   ```
   cp /path/to/SpotiFLAC-Mobile/lib/widgets/audio_analysis_widget.dart \
      lib/vendor/spotiflac/audio_analysis_widget.dart
   ```
2. Prepend the 3-line header:
   ```
   // Vendored from SpotiFLAC-Mobile (MIT) @ <new-commit>; see SYNC.md; only imports modified.
   ```
3. Apply the 8 import substitutions above (sed or manual edit of lines 6-16).
4. Similarly re-sync `settings_group.dart` (prepend header only).
5. Run `flutter analyze lib/vendor` -- must be clean.
6. If upstream added a new `context.l10n.X` key or `PlatformBridge` method, add it to the
   corresponding compat shim (`compat_l10n.dart` or `compat_platform_bridge.dart`).
7. Update the commit hash in this file and in the header comment.
8. Commit with `chore(vendor): re-sync SpotiFLAC @ <new-commit>`.

- share_intent_service.dart @ 7b22bbf2 (import only: spotiflac_android/utils/logger.dart → compat_logger.dart)

## Local modifications (re-apply after each upstream sync)
- Imports: `ffmpeg_kit_flutter_new_audio` → `ffmpeg_kit_flutter_new_full` (we bundle the full variant).
- `AudioAnalysisCard`: added optional `onAnalyzed(AudioAnalysisData)` callback, fired where `_data` is set (cache hit + fresh run), so VerifiedScreen can derive a conservative lossless verdict. Search `LOCAL ADDITION`.

## replaygain_service.dart / convert_service.dart (adapted, not verbatim)
- replaygain_service.dart: ports SpotiFLAC's ReplayGainService.applyToFile +
  the scanReplayGain() routine from ffmpeg_service.dart (EBU R128, -18 LUFS
  ref). Writes replaygain_track_gain/_peak via our BackendBridge.editFileMetadata.
- convert_service.dart: ports convertAudioFormat()'s per-format FFmpeg commands
  (libmp3lame/libopus/aac/flac/pcm). Uses ffmpeg_kit_full + -map_metadata 0 to
  carry tags. On upstream sync, re-diff against ffmpeg_service.dart.
