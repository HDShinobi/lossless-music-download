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
      _isVi ? 'Phan tich chat luong am thanh' : 'Audio Quality Analysis';

  String get audioAnalysisDescription =>
      _isVi
          ? 'Xac minh chat luong khong mat mat bang phan tich pho'
          : 'Verify lossless quality with spectrum analysis';

  String get audioAnalysisAnalyzing =>
      _isVi ? 'Dang phan tich am thanh...' : 'Analyzing audio...';

  String get audioAnalysisRescan => _isVi ? 'Phan tich lai' : 'Re-analyze';

  String get audioAnalysisRescanning =>
      _isVi ? 'Dang phan tich lai am thanh...' : 'Re-analyzing audio...';

  String get audioAnalysisCodec => _isVi ? 'Codec' : 'Codec';

  String get audioAnalysisContainer =>
      _isVi ? 'Dinh dang chua' : 'Container';

  String get audioAnalysisSampleRate =>
      _isVi ? 'Tan so lay mau' : 'Sample Rate';

  String get audioAnalysisBitDepth => _isVi ? 'Do sau bit' : 'Bit Depth';

  String get audioAnalysisDecodedFormat =>
      _isVi ? 'Dinh dang giai ma' : 'Decoded Format';

  String get audioAnalysisChannels => _isVi ? 'Kenh' : 'Channels';

  String get audioAnalysisMono => _isVi ? 'Mono' : 'Mono';

  String get audioAnalysisStereo => _isVi ? 'Stereo' : 'Stereo';

  String get audioAnalysisDuration => _isVi ? 'Thoi luong' : 'Duration';

  String get audioAnalysisFileSize => _isVi ? 'Kich thuoc' : 'Size';

  String get audioAnalysisSamples => _isVi ? 'Mau' : 'Samples';

  String get audioAnalysisNyquist => 'Nyquist';

  String get audioAnalysisSpectralCutoff =>
      _isVi ? 'Nguong pho' : 'Spectral Cutoff';

  String get audioAnalysisPeak => _isVi ? 'Dinh (dBFS)' : 'Peak';

  String get audioAnalysisTruePeak => _isVi ? 'True Peak (dBTP)' : 'True Peak';

  String get audioAnalysisRms => 'RMS';

  String get audioAnalysisLufs => 'LUFS';

  String get audioAnalysisDynamicRange =>
      _isVi ? 'Dai dong' : 'Dynamic Range';

  String get audioAnalysisClipping =>
      _isVi ? 'Cat clip' : 'Clipping';

  String get audioAnalysisNoClipping =>
      _isVi ? 'Khong cat clip' : 'No clipping';

  String get audioAnalysisChannelStats =>
      _isVi ? 'Thong ke theo kenh' : 'Per-channel Stats';

  String get trackConvertBitrate => _isVi ? 'Bitrate' : 'Bitrate';
}
