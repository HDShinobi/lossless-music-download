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

  @override
  String get aggregatorSource => 'Aggregator source';

  @override
  String get changeAggregator => 'Change';

  @override
  String get install => 'Install';

  @override
  String get installed => 'Installed';

  @override
  String get installing => 'Installing...';

  @override
  String get allCategories => 'All';

  @override
  String get catDownload => 'Download';

  @override
  String get catMetadata => 'Metadata';

  @override
  String get catLyrics => 'Lyrics';

  @override
  String get discoverEmpty => 'No extensions yet. Check the aggregator source.';

  @override
  String get discoverError => 'Could not load list. Check the source/URL.';

  @override
  String get changeAggregatorTitle => 'Change aggregator source';

  @override
  String get aggregatorUrlHint => 'Paste repos.json URL';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get installFailed => 'Install failed';

  @override
  String get invalidUrl => 'Invalid URL';

  @override
  String get priorityIntro => 'Best-source tries each in this order.';

  @override
  String get groupDownload => 'Download';

  @override
  String get groupMetadata => 'Metadata';

  @override
  String get priorityEmpty => 'No sources for this group yet.';

  @override
  String get searchHint => 'Search songs, albums...';

  @override
  String get searchEmpty => 'No results.';

  @override
  String get searchNoSources => 'No sources yet. Install one in Discover.';

  @override
  String get searchError => 'Search failed.';

  @override
  String get download => 'Download';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get queueEmpty => 'No downloads in queue.';

  @override
  String get cancelDownload => 'Cancel download';
}
