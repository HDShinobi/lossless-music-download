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
}
