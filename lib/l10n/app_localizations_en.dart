// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Lossless Music';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabQueue => 'Queue';

  @override
  String get tabServer => 'Server';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabSettings => 'Settings';

  @override
  String get sourcesTitle => 'Sources & Extensions';

  @override
  String get tabInstalled => 'Installed';

  @override
  String get tabDiscover => 'Discover';

  @override
  String get tabPriority => 'Priority';

  @override
  String get noExtensions => 'No sources yet. Add one in Discover.';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get permissions => 'Permissions';

  @override
  String get permNetwork => 'Network';

  @override
  String get permStorage => 'Local storage';

  @override
  String get permFile => 'File write';

  @override
  String get removeExtension => 'Remove extension';

  @override
  String get settings => 'Settings';

  @override
  String sourcesInUse(int count) {
    return 'using $count sources';
  }

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get extNotFound => 'Extension not found';

  @override
  String get permNone => 'No special permissions';
}
