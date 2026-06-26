// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Lossless Music';

  @override
  String get tabSearch => 'Tìm';

  @override
  String get tabQueue => 'Hàng đợi';

  @override
  String get tabServer => 'Máy chủ';

  @override
  String get tabLibrary => 'Thư viện';

  @override
  String get tabSettings => 'Cài đặt';

  @override
  String get sourcesTitle => 'Nguồn & Extension';

  @override
  String get tabInstalled => 'Đã cài';

  @override
  String get tabDiscover => 'Khám phá';

  @override
  String get tabPriority => 'Ưu tiên';

  @override
  String get noExtensions => 'Chưa có nguồn nào. Thêm ở Khám phá.';

  @override
  String get comingSoon => 'Sắp có';

  @override
  String get permissions => 'Quyền truy cập';

  @override
  String get permNetwork => 'Mạng';

  @override
  String get permStorage => 'Lưu trữ cục bộ';

  @override
  String get permFile => 'Ghi file';

  @override
  String get removeExtension => 'Gỡ extension';

  @override
  String get settings => 'Cài đặt';

  @override
  String sourcesInUse(int count) {
    return 'đang dùng $count nguồn';
  }

  @override
  String get enabled => 'Bật';

  @override
  String get disabled => 'Tắt';

  @override
  String get extNotFound => 'Không tìm thấy extension';

  @override
  String get permNone => 'Không yêu cầu quyền đặc biệt';

  @override
  String get aggregatorSource => 'Nguồn tổng hợp';

  @override
  String get changeAggregator => 'Đổi';

  @override
  String get install => 'Cài';

  @override
  String get installed => 'Đã cài';

  @override
  String get installing => 'Đang cài...';

  @override
  String get allCategories => 'Tất cả';

  @override
  String get catDownload => 'Tải';

  @override
  String get catMetadata => 'Metadata';

  @override
  String get catLyrics => 'Lyrics';

  @override
  String get discoverEmpty => 'Chưa có extension nào. Kiểm tra nguồn tổng hợp.';

  @override
  String get discoverError => 'Không tải được danh sách. Kiểm tra nguồn/URL.';

  @override
  String get changeAggregatorTitle => 'Đổi nguồn tổng hợp';

  @override
  String get aggregatorUrlHint => 'Dán URL repos.json';

  @override
  String get save => 'Lưu';

  @override
  String get cancel => 'Huỷ';

  @override
  String get installFailed => 'Cài thất bại';

  @override
  String get invalidUrl => 'URL không hợp lệ';

  @override
  String get priorityIntro => 'Best-source thử lần lượt theo thứ tự này.';

  @override
  String get groupDownload => 'Tải';

  @override
  String get groupMetadata => 'Metadata';

  @override
  String get priorityEmpty => 'Chưa có nguồn nào cho mục này.';

  @override
  String get searchHint => 'Tìm bài hát, album...';

  @override
  String get searchEmpty => 'Không có kết quả.';

  @override
  String get searchNoSources => 'Chưa có nguồn nào. Vào Khám phá để cài.';

  @override
  String get searchError => 'Tìm kiếm lỗi.';

  @override
  String get download => 'Tải';

  @override
  String get downloadStarted => 'Đã thêm vào hàng đợi';

  @override
  String get downloadFailed => 'Tải thất bại';

  @override
  String get queueViewQueue => 'Xem Queue';

  @override
  String get queueEmpty => 'Chưa có tải nào.';

  @override
  String get libraryEmpty => 'Chưa tải bài nào.';

  @override
  String libraryCount(int count) {
    return '$count file';
  }

  @override
  String get refresh => 'Làm mới';

  @override
  String get libraryError => 'Không tải được thư viện.';

  @override
  String get unitMb => 'MB';

  @override
  String get queueError => 'Lỗi tải hàng đợi.';

  @override
  String get settingAskBeforeDownload => 'Chọn nguồn trước khi tải';

  @override
  String get settingAskBeforeDownloadDesc =>
      'Hiển thị bảng chọn nguồn và chất lượng cho mỗi lần tải';

  @override
  String get downloadSheetSource => 'Nguồn';

  @override
  String get downloadSheetQuality => 'Chất lượng';

  @override
  String get downloadCta => 'Tải xuống';

  @override
  String get downloadSheetNoSources =>
      'Chưa có nguồn tải. Cài extension tải trong Khám phá.';

  @override
  String get queueStatusQueued => 'Trong hàng đợi';

  @override
  String get queueStatusFailed => 'Lỗi · chạm để thử lại';

  @override
  String get queueStatusDone => 'Verified · đã vào Thư viện';

  @override
  String get queueStatusFinalizing => 'Đang ghi metadata...';

  @override
  String get libraryAll => 'Tất cả';

  @override
  String get libraryAlbums => 'Album';

  @override
  String get librarySingles => 'Single';

  @override
  String get serveBannerTitle => 'Phát qua DLNA · WebDAV';

  @override
  String serveBannerSubtitle(int count) {
    return '$count bài cho thiết bị khác';
  }

  @override
  String albumTrackCount(int count) {
    return '$count bài';
  }

  @override
  String get verifiedLossless => 'Lossless thật';

  @override
  String get verifiedUnknown => 'Chưa xác minh';

  @override
  String get verifiedSpectrumNote => 'Phổ minh hoạ. Phân tích đầy đủ sắp có.';

  @override
  String get verdictLossless => 'Lossless — có vẻ thật';

  @override
  String get verdictSuspect => 'Nghi lossy (cutoff phổ thấp)';

  @override
  String get verdictLossy => 'Định dạng lossy';

  @override
  String get verdictInconclusive => 'Chưa đủ dữ liệu';

  @override
  String get verdictHeuristicNote =>
      'Đánh giá dựa trên phổ tần — chỉ mang tính tham khảo.';

  @override
  String get statFormat => 'Định dạng';

  @override
  String get statSize => 'Dung lượng';

  @override
  String get statBitDepth => 'Độ sâu bit';

  @override
  String get statSampleRate => 'Tần số lấy mẫu';

  @override
  String get statBitrate => 'Bitrate';

  @override
  String get verifiedServeTitle => 'Phát cho thiết bị khác';

  @override
  String get serverRunning => 'Đang phát';

  @override
  String get serverStopped => 'Đã tắt';

  @override
  String get serverStart => 'Bật máy chủ';

  @override
  String get serverStop => 'Tắt máy chủ';

  @override
  String get serverAddress => 'Địa chỉ';

  @override
  String get serverFolder => 'Thư mục phát';

  @override
  String get serverHint =>
      'Tìm thiết bị này trong app phát nhạc DLNA (PureBit, UAPP, Poweramp).';

  @override
  String get serverCopied => 'Đã sao chép địa chỉ';

  @override
  String selectionCount(int count) {
    return '$count đã chọn';
  }

  @override
  String batchAddedToQueue(int count) {
    return 'Đã thêm $count bài vào hàng đợi';
  }

  @override
  String get selectionClear => 'Bỏ chọn';

  @override
  String get loadingSharedLink => 'Đang tải link đã chia sẻ...';

  @override
  String get shareUrlNotRecognized => 'Không nhận ra link này';

  @override
  String get recentSearches => 'Tìm kiếm gần đây';

  @override
  String get recentSearchesClear => 'Xóa tất cả';

  @override
  String get searchSourceAll => 'Tất cả';

  @override
  String get downloadAll => 'Tải tất cả';

  @override
  String get noTracksFound => 'Không tìm thấy bài hát';

  @override
  String get viewArtist => 'Xem nghệ sĩ';

  @override
  String get viewAlbum => 'Xem album';

  @override
  String get artistPopular => 'Phổ biến';

  @override
  String get artistAlbums => 'Album';

  @override
  String get artistSingles => 'Single & EP';

  @override
  String artistMonthlyListeners(String count) {
    return '$count người nghe mỗi tháng';
  }

  @override
  String get artistReleases => 'Mới phát hành';

  @override
  String get artistCompilations => 'Tuyển tập';

  @override
  String artistSectionCount(String title, int count) {
    return '$title ($count)';
  }

  @override
  String get inLibrary => 'Đã tải';

  @override
  String get downloadOptionsAll => 'Tải tất cả';

  @override
  String get downloadOptionsAlbumsOnly => 'Chỉ album';

  @override
  String get downloadOptionsSinglesOnly => 'Chỉ single & EP';

  @override
  String get downloadOptionsSelect => 'Chọn album';

  @override
  String get librarySearchHint => 'Tìm trong thư viện…';

  @override
  String get libraryNoResults => 'Không có kết quả';

  @override
  String get settingDownloadFolder => 'Thư mục tải về';

  @override
  String get settingEmbedMetadata => 'Ghi thẻ metadata';

  @override
  String get settingEmbedMetadataDesc =>
      'Ghi thông tin (tên bài, ca sĩ, năm…) vào file';

  @override
  String get settingEmbedCover => 'Ghi ảnh bìa';

  @override
  String get settingEmbedCoverDesc => 'Nhúng ảnh bìa album vào thẻ file';

  @override
  String get settingEmbedLyrics => 'Ghi lời bài hát';

  @override
  String get settingEmbedLyricsDesc => 'Nhúng lời bài hát đồng bộ vào file';

  @override
  String get settingDownloadFolderChange => 'Chạm để đổi';

  @override
  String get settingDownloadFolderUpdated => 'Đã cập nhật thư mục tải về';

  @override
  String get settingStoragePermissionTitle => 'Cần quyền truy cập bộ nhớ';

  @override
  String get settingStoragePermissionBody =>
      'Để lưu file vào thư mục bạn chọn, hãy cấp quyền \"Truy cập tất cả tệp\" cho Lossless Music trong cài đặt hệ thống.';

  @override
  String get settingStoragePermissionOpen => 'Mở cài đặt';

  @override
  String get commonCancel => 'Huỷ';
}
