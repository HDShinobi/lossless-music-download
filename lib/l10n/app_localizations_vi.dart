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
}
