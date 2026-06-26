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
  String get downloadStarted => 'Added to queue';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get queueViewQueue => 'View Queue';

  @override
  String get queueEmpty => 'No downloads yet.';

  @override
  String get libraryEmpty => 'No downloads yet.';

  @override
  String libraryCount(int count) {
    return '$count files';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get libraryError => 'Could not load library.';

  @override
  String get unitMb => 'MB';

  @override
  String get queueError => 'Could not load queue.';

  @override
  String get settingAskBeforeDownload => 'Choose source before download';

  @override
  String get settingAskBeforeDownloadDesc =>
      'Show a sheet to pick source and quality for each download';

  @override
  String get downloadSheetSource => 'Source';

  @override
  String get downloadSheetQuality => 'Quality';

  @override
  String get downloadCta => 'Download';

  @override
  String get downloadSheetNoSources =>
      'No download source yet. Install one in Discover.';

  @override
  String get queueStatusQueued => 'In queue';

  @override
  String get queueStatusFailed => 'Failed · tap to retry';

  @override
  String get queueStatusDone => 'Verified · in Library';

  @override
  String get queueStatusFinalizing => 'Writing metadata...';

  @override
  String get libraryAll => 'All';

  @override
  String get libraryAlbums => 'Albums';

  @override
  String get librarySingles => 'Singles';

  @override
  String get serveBannerTitle => 'Serving via DLNA · WebDAV';

  @override
  String serveBannerSubtitle(int count) {
    return '$count tracks to other devices';
  }

  @override
  String albumTrackCount(int count) {
    return '$count tracks';
  }

  @override
  String get verifiedLossless => 'Genuine lossless';

  @override
  String get verifiedUnknown => 'Not verified';

  @override
  String get verifiedSpectrumNote =>
      'Illustrative spectrum. Full analysis coming.';

  @override
  String get verdictLossless => 'Lossless — looks genuine';

  @override
  String get verdictSuspect => 'Suspect lossy (low spectral cutoff)';

  @override
  String get verdictLossy => 'Lossy format';

  @override
  String get verdictInconclusive => 'Inconclusive';

  @override
  String get verdictHeuristicNote =>
      'Heuristic from the frequency spectrum — for reference only.';

  @override
  String get statFormat => 'Format';

  @override
  String get statSize => 'Size';

  @override
  String get statBitDepth => 'Bit depth';

  @override
  String get statSampleRate => 'Sample rate';

  @override
  String get statBitrate => 'Bitrate';

  @override
  String get verifiedServeTitle => 'Serve to other devices';

  @override
  String get serverRunning => 'Running';

  @override
  String get serverStopped => 'Stopped';

  @override
  String get serverStart => 'Start server';

  @override
  String get serverStop => 'Stop server';

  @override
  String get serverAddress => 'Address';

  @override
  String get serverFolder => 'Served folder';

  @override
  String get serverHint =>
      'Find this device in your DLNA player (PureBit, UAPP, Poweramp).';

  @override
  String get serverCopied => 'Address copied';

  @override
  String selectionCount(int count) {
    return '$count selected';
  }

  @override
  String batchAddedToQueue(int count) {
    return 'Queued $count for download';
  }

  @override
  String get selectionClear => 'Clear';

  @override
  String get loadingSharedLink => 'Loading shared link...';

  @override
  String get shareUrlNotRecognized => 'Link not recognized';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get recentSearchesClear => 'Clear all';

  @override
  String get searchSourceAll => 'All';

  @override
  String get downloadAll => 'Download all';

  @override
  String get noTracksFound => 'No tracks found';

  @override
  String get viewArtist => 'View artist';

  @override
  String get viewAlbum => 'View album';

  @override
  String get artistPopular => 'Popular';

  @override
  String get artistAlbums => 'Albums';

  @override
  String get artistSingles => 'Singles & EPs';

  @override
  String artistMonthlyListeners(String count) {
    return '$count monthly listeners';
  }

  @override
  String get artistReleases => 'Releases';

  @override
  String get artistCompilations => 'Compilations';

  @override
  String artistSectionCount(String title, int count) {
    return '$title ($count)';
  }

  @override
  String get inLibrary => 'In Library';

  @override
  String get downloadOptionsAll => 'Download everything';

  @override
  String get downloadOptionsAlbumsOnly => 'Albums only';

  @override
  String get downloadOptionsSinglesOnly => 'Singles & EPs only';

  @override
  String get downloadOptionsSelect => 'Select albums';

  @override
  String get librarySearchHint => 'Search library…';

  @override
  String get libraryNoResults => 'No tracks match';

  @override
  String get settingDownloadFolder => 'Download folder';

  @override
  String get settingEmbedMetadata => 'Embed metadata';

  @override
  String get settingEmbedMetadataDesc =>
      'Write tags (title, artist, year…) to downloaded files';

  @override
  String get settingEmbedCover => 'Embed cover art';

  @override
  String get settingEmbedCoverDesc => 'Include album artwork in file tags';

  @override
  String get settingEmbedLyrics => 'Embed lyrics';

  @override
  String get settingEmbedLyricsDesc => 'Include synced lyrics in file tags';

  @override
  String get settingDownloadFolderChange => 'Tap to change';

  @override
  String get settingDownloadFolderUpdated => 'Download folder updated';

  @override
  String get settingStoragePermissionTitle => 'Storage access needed';

  @override
  String get settingStoragePermissionBody =>
      'To save downloads to a folder you choose, allow \"All files access\" for Lossless Music in system settings.';

  @override
  String get settingStoragePermissionOpen => 'Open settings';

  @override
  String get commonCancel => 'Cancel';
}
