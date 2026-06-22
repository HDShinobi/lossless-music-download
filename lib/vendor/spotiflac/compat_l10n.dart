// Compat shim: provides context.l10n for vendored SpotiFLAC files.
// Supports 'vi' (default) and 'en'. Technical tokens (LUFS, RMS, Nyquist, dB,
// dBFS) are language-invariant. No em-dash used anywhere.

import 'package:flutter/material.dart';

extension AppLocalizationsX on BuildContext {
  AnalysisL10n get l10n =>
      AnalysisL10n(Localizations.localeOf(this).languageCode);
}

class AnalysisL10n {
  final String languageCode;

  const AnalysisL10n(this.languageCode);

  bool get _isVi => languageCode == 'vi';

  String get audioAnalysisTitle =>
      _isVi ? 'Phân tích chất lượng âm thanh' : 'Audio Quality Analysis';

  String get audioAnalysisDescription => _isVi
      ? 'Xác minh chất lượng không mất mát bằng phân tích phổ'
      : 'Verify lossless quality with spectrum analysis';

  String get audioAnalysisAnalyzing =>
      _isVi ? 'Đang phân tích âm thanh...' : 'Analyzing audio...';

  String get audioAnalysisRescan => _isVi ? 'Phân tích lại' : 'Re-analyze';

  String get audioAnalysisRescanning =>
      _isVi ? 'Đang phân tích lại âm thanh...' : 'Re-analyzing audio...';

  String get audioAnalysisCodec => 'Codec';

  String get audioAnalysisContainer => _isVi ? 'Định dạng chứa' : 'Container';

  String get audioAnalysisSampleRate =>
      _isVi ? 'Tần số lấy mẫu' : 'Sample Rate';

  String get audioAnalysisBitDepth => _isVi ? 'Độ sâu bit' : 'Bit Depth';

  String get audioAnalysisDecodedFormat =>
      _isVi ? 'Định dạng giải mã' : 'Decoded Format';

  String get audioAnalysisChannels => _isVi ? 'Kênh' : 'Channels';

  String get audioAnalysisMono => 'Mono';

  String get audioAnalysisStereo => 'Stereo';

  String get audioAnalysisDuration => _isVi ? 'Thời lượng' : 'Duration';

  String get audioAnalysisFileSize => _isVi ? 'Kích thước' : 'Size';

  String get audioAnalysisSamples => _isVi ? 'Mẫu' : 'Samples';

  String get audioAnalysisNyquist => 'Nyquist';

  String get audioAnalysisSpectralCutoff =>
      _isVi ? 'Ngưỡng phổ' : 'Spectral Cutoff';

  String get audioAnalysisPeak => _isVi ? 'Đỉnh (dBFS)' : 'Peak';

  String get audioAnalysisTruePeak => _isVi ? 'True Peak (dBTP)' : 'True Peak';

  String get audioAnalysisRms => 'RMS';

  String get audioAnalysisLufs => 'LUFS';

  String get audioAnalysisDynamicRange =>
      _isVi ? 'Dải động' : 'Dynamic Range';

  String get audioAnalysisClipping => _isVi ? 'Cắt clip' : 'Clipping';

  String get audioAnalysisNoClipping => _isVi ? 'Không cắt clip' : 'No clipping';

  String get audioAnalysisChannelStats =>
      _isVi ? 'Thống kê theo kênh' : 'Per-channel Stats';

  String get trackConvertBitrate => 'Bitrate';
}
