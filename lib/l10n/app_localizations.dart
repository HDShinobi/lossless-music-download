import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Lossless Music'**
  String get appTitle;

  /// No description provided for @tabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// No description provided for @tabQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get tabQueue;

  /// No description provided for @tabServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get tabServer;

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @sourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sources & Extensions'**
  String get sourcesTitle;

  /// No description provided for @tabInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get tabInstalled;

  /// No description provided for @tabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tabDiscover;

  /// No description provided for @tabPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get tabPriority;

  /// No description provided for @noExtensions.
  ///
  /// In en, this message translates to:
  /// **'No sources yet. Add one in Discover.'**
  String get noExtensions;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @permNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get permNetwork;

  /// No description provided for @permStorage.
  ///
  /// In en, this message translates to:
  /// **'Local storage'**
  String get permStorage;

  /// No description provided for @permFile.
  ///
  /// In en, this message translates to:
  /// **'File write'**
  String get permFile;

  /// No description provided for @removeExtension.
  ///
  /// In en, this message translates to:
  /// **'Remove extension'**
  String get removeExtension;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sourcesInUse.
  ///
  /// In en, this message translates to:
  /// **'using {count} sources'**
  String sourcesInUse(int count);

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @extNotFound.
  ///
  /// In en, this message translates to:
  /// **'Extension not found'**
  String get extNotFound;

  /// No description provided for @permNone.
  ///
  /// In en, this message translates to:
  /// **'No special permissions'**
  String get permNone;

  /// No description provided for @aggregatorSource.
  ///
  /// In en, this message translates to:
  /// **'Aggregator source'**
  String get aggregatorSource;

  /// No description provided for @changeAggregator.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAggregator;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed;

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get installing;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allCategories;

  /// No description provided for @catDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get catDownload;

  /// No description provided for @catMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get catMetadata;

  /// No description provided for @catLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get catLyrics;

  /// No description provided for @discoverEmpty.
  ///
  /// In en, this message translates to:
  /// **'No extensions yet. Check the aggregator source.'**
  String get discoverEmpty;

  /// No description provided for @discoverError.
  ///
  /// In en, this message translates to:
  /// **'Could not load list. Check the source/URL.'**
  String get discoverError;

  /// No description provided for @changeAggregatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Change aggregator source'**
  String get changeAggregatorTitle;

  /// No description provided for @aggregatorUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste repos.json URL'**
  String get aggregatorUrlHint;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Install failed'**
  String get installFailed;

  /// No description provided for @invalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL'**
  String get invalidUrl;

  /// No description provided for @priorityIntro.
  ///
  /// In en, this message translates to:
  /// **'Best-source tries each in this order.'**
  String get priorityIntro;

  /// No description provided for @groupDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get groupDownload;

  /// No description provided for @groupMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get groupMetadata;

  /// No description provided for @priorityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sources for this group yet.'**
  String get priorityEmpty;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs, albums...'**
  String get searchHint;

  /// No description provided for @searchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results.'**
  String get searchEmpty;

  /// No description provided for @searchNoSources.
  ///
  /// In en, this message translates to:
  /// **'No sources yet. Install one in Discover.'**
  String get searchNoSources;

  /// No description provided for @searchError.
  ///
  /// In en, this message translates to:
  /// **'Search failed.'**
  String get searchError;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get downloadStarted;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @queueViewQueue.
  ///
  /// In en, this message translates to:
  /// **'View Queue'**
  String get queueViewQueue;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet.'**
  String get queueEmpty;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet.'**
  String get libraryEmpty;

  /// No description provided for @libraryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String libraryCount(int count);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @libraryError.
  ///
  /// In en, this message translates to:
  /// **'Could not load library.'**
  String get libraryError;

  /// No description provided for @unitMb.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get unitMb;

  /// No description provided for @queueError.
  ///
  /// In en, this message translates to:
  /// **'Could not load queue.'**
  String get queueError;

  /// No description provided for @settingAskBeforeDownload.
  ///
  /// In en, this message translates to:
  /// **'Choose source before download'**
  String get settingAskBeforeDownload;

  /// No description provided for @settingAskBeforeDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Show a sheet to pick source and quality for each download'**
  String get settingAskBeforeDownloadDesc;

  /// No description provided for @downloadSheetSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get downloadSheetSource;

  /// No description provided for @downloadSheetQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get downloadSheetQuality;

  /// No description provided for @downloadCta.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadCta;

  /// No description provided for @downloadSheetNoSources.
  ///
  /// In en, this message translates to:
  /// **'No download source yet. Install one in Discover.'**
  String get downloadSheetNoSources;

  /// No description provided for @queueStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'In queue'**
  String get queueStatusQueued;

  /// No description provided for @queueStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed · tap to retry'**
  String get queueStatusFailed;

  /// No description provided for @queueStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Verified · in Library'**
  String get queueStatusDone;

  /// No description provided for @queueStatusFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Writing metadata...'**
  String get queueStatusFinalizing;

  /// No description provided for @libraryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryAll;

  /// No description provided for @libraryAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get libraryAlbums;

  /// No description provided for @librarySingles.
  ///
  /// In en, this message translates to:
  /// **'Singles'**
  String get librarySingles;

  /// No description provided for @serveBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Serving via DLNA · WebDAV'**
  String get serveBannerTitle;

  /// No description provided for @serveBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks to other devices'**
  String serveBannerSubtitle(int count);

  /// No description provided for @discLabel.
  ///
  /// In en, this message translates to:
  /// **'Disc {number}'**
  String discLabel(int number);

  /// No description provided for @albumTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String albumTrackCount(int count);

  /// No description provided for @verifiedLossless.
  ///
  /// In en, this message translates to:
  /// **'Genuine lossless'**
  String get verifiedLossless;

  /// No description provided for @verifiedUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get verifiedUnknown;

  /// No description provided for @verifiedSpectrumNote.
  ///
  /// In en, this message translates to:
  /// **'Illustrative spectrum. Full analysis coming.'**
  String get verifiedSpectrumNote;

  /// No description provided for @verdictLossless.
  ///
  /// In en, this message translates to:
  /// **'Lossless — looks genuine'**
  String get verdictLossless;

  /// No description provided for @verdictSuspect.
  ///
  /// In en, this message translates to:
  /// **'Suspect lossy (low spectral cutoff)'**
  String get verdictSuspect;

  /// No description provided for @verdictLossy.
  ///
  /// In en, this message translates to:
  /// **'Lossy format'**
  String get verdictLossy;

  /// No description provided for @verdictInconclusive.
  ///
  /// In en, this message translates to:
  /// **'Inconclusive'**
  String get verdictInconclusive;

  /// No description provided for @verdictHeuristicNote.
  ///
  /// In en, this message translates to:
  /// **'Heuristic from the frequency spectrum — for reference only.'**
  String get verdictHeuristicNote;

  /// No description provided for @settingCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingCheckUpdate;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailableTitle;

  /// No description provided for @updateNewVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String updateNewVersionLabel(String version);

  /// No description provided for @updateDownloadInstall.
  ///
  /// In en, this message translates to:
  /// **'Download & install'**
  String get updateDownloadInstall;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get updateDownloading;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed. Please try again later.'**
  String get updateFailed;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterSong.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get filterSong;

  /// No description provided for @filterArtist.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get filterArtist;

  /// No description provided for @filterAlbum.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get filterAlbum;

  /// No description provided for @openingArtist.
  ///
  /// In en, this message translates to:
  /// **'Opening artist…'**
  String get openingArtist;

  /// No description provided for @openingAlbum.
  ///
  /// In en, this message translates to:
  /// **'Opening album…'**
  String get openingAlbum;

  /// No description provided for @entityNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find details to open'**
  String get entityNotFound;

  /// No description provided for @manageEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit metadata'**
  String get manageEdit;

  /// No description provided for @manageReEnrich.
  ///
  /// In en, this message translates to:
  /// **'Re-enrich (refetch tags)'**
  String get manageReEnrich;

  /// No description provided for @manageReplayGain.
  ///
  /// In en, this message translates to:
  /// **'Scan ReplayGain'**
  String get manageReplayGain;

  /// No description provided for @manageConvert.
  ///
  /// In en, this message translates to:
  /// **'Convert format'**
  String get manageConvert;

  /// No description provided for @manageDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete from device'**
  String get manageDelete;

  /// No description provided for @replayGainStarted.
  ///
  /// In en, this message translates to:
  /// **'Scanning loudness…'**
  String get replayGainStarted;

  /// No description provided for @replayGainDone.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain tags written'**
  String get replayGainDone;

  /// No description provided for @replayGainFailed.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain scan failed'**
  String get replayGainFailed;

  /// No description provided for @convertSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert format'**
  String get convertSheetTitle;

  /// No description provided for @convertBitrateLabel.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get convertBitrateLabel;

  /// No description provided for @convertStarted.
  ///
  /// In en, this message translates to:
  /// **'Converting…'**
  String get convertStarted;

  /// No description provided for @convertDone.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get convertDone;

  /// No description provided for @convertFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversion failed'**
  String get convertFailed;

  /// No description provided for @commonConvert.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get commonConvert;

  /// No description provided for @editSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit metadata'**
  String get editSheetTitle;

  /// No description provided for @editFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get editFieldTitle;

  /// No description provided for @editFieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get editFieldArtist;

  /// No description provided for @editFieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get editFieldAlbum;

  /// No description provided for @editFieldAlbumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album artist'**
  String get editFieldAlbumArtist;

  /// No description provided for @editFieldYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get editFieldYear;

  /// No description provided for @editFieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get editFieldGenre;

  /// No description provided for @editFieldTrack.
  ///
  /// In en, this message translates to:
  /// **'Track #'**
  String get editFieldTrack;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @editSaved.
  ///
  /// In en, this message translates to:
  /// **'Metadata saved'**
  String get editSaved;

  /// No description provided for @editFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save metadata'**
  String get editFailed;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this track?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The file will be permanently removed from this device.'**
  String get deleteConfirmBody;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @deleteDone.
  ///
  /// In en, this message translates to:
  /// **'Track deleted'**
  String get deleteDone;

  /// No description provided for @reEnrichStarted.
  ///
  /// In en, this message translates to:
  /// **'Refetching metadata…'**
  String get reEnrichStarted;

  /// No description provided for @reEnrichDone.
  ///
  /// In en, this message translates to:
  /// **'Metadata refreshed'**
  String get reEnrichDone;

  /// No description provided for @reEnrichFailed.
  ///
  /// In en, this message translates to:
  /// **'Re-enrich failed'**
  String get reEnrichFailed;

  /// No description provided for @statFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get statFormat;

  /// No description provided for @statSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get statSize;

  /// No description provided for @statBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit depth'**
  String get statBitDepth;

  /// No description provided for @statSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get statSampleRate;

  /// No description provided for @statBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get statBitrate;

  /// No description provided for @verifiedServeTitle.
  ///
  /// In en, this message translates to:
  /// **'Serve to other devices'**
  String get verifiedServeTitle;

  /// No description provided for @serverRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get serverRunning;

  /// No description provided for @serverStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get serverStopped;

  /// No description provided for @serverStart.
  ///
  /// In en, this message translates to:
  /// **'Start server'**
  String get serverStart;

  /// No description provided for @serverStop.
  ///
  /// In en, this message translates to:
  /// **'Stop server'**
  String get serverStop;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get serverAddress;

  /// No description provided for @serverFolder.
  ///
  /// In en, this message translates to:
  /// **'Served folder'**
  String get serverFolder;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'Find this device in your DLNA player (PureBit, UAPP, Poweramp).'**
  String get serverHint;

  /// No description provided for @serverCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get serverCopied;

  /// No description provided for @selectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectionCount(int count);

  /// No description provided for @batchAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Queued {count} for download'**
  String batchAddedToQueue(int count);

  /// No description provided for @selectionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get selectionClear;

  /// Snackbar shown when resolving a shared music URL
  ///
  /// In en, this message translates to:
  /// **'Loading shared link...'**
  String get loadingSharedLink;

  /// Shown when a shared URL cannot be resolved to tracks
  ///
  /// In en, this message translates to:
  /// **'Link not recognized'**
  String get shareUrlNotRecognized;

  /// Snackbar shown when a browser tab opens for an extension's signed-session verification
  ///
  /// In en, this message translates to:
  /// **'Opened browser to verify this source — try downloading again after signing in'**
  String get extensionVerificationOpened;

  /// Snackbar shown when an extension's browser verification succeeds
  ///
  /// In en, this message translates to:
  /// **'Verification complete — you can try downloading again'**
  String get extensionVerificationSucceeded;

  /// Snackbar shown when an extension's browser verification fails
  ///
  /// In en, this message translates to:
  /// **'Verification failed — please try again'**
  String get extensionVerificationFailed;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @recentSearchesClear.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get recentSearchesClear;

  /// No description provided for @searchSourceAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get searchSourceAll;

  /// No description provided for @downloadAll.
  ///
  /// In en, this message translates to:
  /// **'Download all'**
  String get downloadAll;

  /// No description provided for @noTracksFound.
  ///
  /// In en, this message translates to:
  /// **'No tracks found'**
  String get noTracksFound;

  /// No description provided for @viewArtist.
  ///
  /// In en, this message translates to:
  /// **'View artist'**
  String get viewArtist;

  /// No description provided for @viewAlbum.
  ///
  /// In en, this message translates to:
  /// **'View album'**
  String get viewAlbum;

  /// No description provided for @artistPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get artistPopular;

  /// No description provided for @artistAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get artistAlbums;

  /// No description provided for @artistSingles.
  ///
  /// In en, this message translates to:
  /// **'Singles & EPs'**
  String get artistSingles;

  /// No description provided for @artistMonthlyListeners.
  ///
  /// In en, this message translates to:
  /// **'{count} monthly listeners'**
  String artistMonthlyListeners(String count);

  /// No description provided for @artistReleases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get artistReleases;

  /// No description provided for @artistCompilations.
  ///
  /// In en, this message translates to:
  /// **'Compilations'**
  String get artistCompilations;

  /// No description provided for @artistSectionCount.
  ///
  /// In en, this message translates to:
  /// **'{title} ({count})'**
  String artistSectionCount(String title, int count);

  /// No description provided for @inLibrary.
  ///
  /// In en, this message translates to:
  /// **'In Library'**
  String get inLibrary;

  /// No description provided for @downloadOptionsAll.
  ///
  /// In en, this message translates to:
  /// **'Download everything'**
  String get downloadOptionsAll;

  /// No description provided for @downloadOptionsAlbumsOnly.
  ///
  /// In en, this message translates to:
  /// **'Albums only'**
  String get downloadOptionsAlbumsOnly;

  /// No description provided for @downloadOptionsSinglesOnly.
  ///
  /// In en, this message translates to:
  /// **'Singles & EPs only'**
  String get downloadOptionsSinglesOnly;

  /// No description provided for @downloadOptionsSelect.
  ///
  /// In en, this message translates to:
  /// **'Select albums'**
  String get downloadOptionsSelect;

  /// No description provided for @librarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search library…'**
  String get librarySearchHint;

  /// No description provided for @libraryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No tracks match'**
  String get libraryNoResults;

  /// No description provided for @settingDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Download folder'**
  String get settingDownloadFolder;

  /// No description provided for @settingEmbedMetadata.
  ///
  /// In en, this message translates to:
  /// **'Embed metadata'**
  String get settingEmbedMetadata;

  /// No description provided for @settingEmbedMetadataDesc.
  ///
  /// In en, this message translates to:
  /// **'Write tags (title, artist, year…) to downloaded files'**
  String get settingEmbedMetadataDesc;

  /// No description provided for @settingEmbedCover.
  ///
  /// In en, this message translates to:
  /// **'Embed cover art'**
  String get settingEmbedCover;

  /// No description provided for @settingEmbedCoverDesc.
  ///
  /// In en, this message translates to:
  /// **'Include album artwork in file tags'**
  String get settingEmbedCoverDesc;

  /// No description provided for @settingEmbedLyrics.
  ///
  /// In en, this message translates to:
  /// **'Embed lyrics'**
  String get settingEmbedLyrics;

  /// No description provided for @settingEmbedLyricsDesc.
  ///
  /// In en, this message translates to:
  /// **'Include synced lyrics in file tags'**
  String get settingEmbedLyricsDesc;

  /// No description provided for @lrcSidecarTitle.
  ///
  /// In en, this message translates to:
  /// **'Write .lrc lyrics file'**
  String get lrcSidecarTitle;

  /// No description provided for @lrcSidecarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save synced lyrics next to each download for external players'**
  String get lrcSidecarSubtitle;

  /// No description provided for @settingDownloadFolderChange.
  ///
  /// In en, this message translates to:
  /// **'Tap to change'**
  String get settingDownloadFolderChange;

  /// No description provided for @settingDownloadFolderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Download folder updated'**
  String get settingDownloadFolderUpdated;

  /// No description provided for @settingStoragePermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage access needed'**
  String get settingStoragePermissionTitle;

  /// No description provided for @settingStoragePermissionBody.
  ///
  /// In en, this message translates to:
  /// **'To save downloads to a folder you choose, allow \"All files access\" for Lossless Music in system settings.'**
  String get settingStoragePermissionBody;

  /// No description provided for @settingStoragePermissionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingStoragePermissionOpen;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Settings screen title for choosing which sources are used during download fallback
  ///
  /// In en, this message translates to:
  /// **'Fallback sources'**
  String get fallbackSourcesTitle;

  /// Explanatory header text on the fallback-sources settings screen
  ///
  /// In en, this message translates to:
  /// **'Unchecked sources are skipped during fallback.'**
  String get fallbackSourcesHeader;

  /// Settings screen title for choosing which extension supplies the Search suggestions feed
  ///
  /// In en, this message translates to:
  /// **'Suggestions source'**
  String get homeFeedSourceTitle;

  /// Settings screen subtitle explaining the suggestions source setting
  ///
  /// In en, this message translates to:
  /// **'Extension that supplies the Search suggestions feed'**
  String get homeFeedSourceSubtitle;

  /// Chooser option: automatically use the first enabled extension that supports suggestions
  ///
  /// In en, this message translates to:
  /// **'Auto (first available)'**
  String get homeFeedSourceAuto;

  /// Chooser option: disable the Search suggestions feed
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get homeFeedSourceOffLabel;

  /// Subtitle on a completed queue item showing which provider delivered the file
  ///
  /// In en, this message translates to:
  /// **'Downloaded via {service}'**
  String queueDownloadedVia(String service);

  /// Subtitle on a completed queue item when the winning provider differs from the originally requested one
  ///
  /// In en, this message translates to:
  /// **'Downloaded via {service} (fallback from {original})'**
  String queueDownloadedViaFallback(String service, String original);

  /// Lyrics viewer screen title
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsTitle;

  /// Empty state when a track has no lyrics
  ///
  /// In en, this message translates to:
  /// **'No lyrics found for this track.'**
  String get lyricsNotFound;

  /// Shown when the track is instrumental (backend returns [instrumental:true])
  ///
  /// In en, this message translates to:
  /// **'Instrumental track'**
  String get lyricsInstrumental;

  /// Track-detail menu action to open the lyrics viewer
  ///
  /// In en, this message translates to:
  /// **'View lyrics'**
  String get viewLyrics;

  /// Title of the help dialog shown when the verification browser could not be opened automatically
  ///
  /// In en, this message translates to:
  /// **'Verify this source'**
  String get extensionVerificationHelpTitleManual;

  /// Title of the help dialog shown while waiting for the user to finish browser verification
  ///
  /// In en, this message translates to:
  /// **'Waiting for verification'**
  String get extensionVerificationHelpTitleWaiting;

  /// Body of the verification help dialog when the browser could not be launched
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open the browser automatically. Copy the link below and open it to finish verification, then try downloading again.'**
  String get extensionVerificationHelpMessageManual;

  /// Body of the verification help dialog while waiting for the grant to complete
  ///
  /// In en, this message translates to:
  /// **'Finish the verification in your browser, then come back and try downloading again. If the page didn\'t open, use the link below.'**
  String get extensionVerificationHelpMessageWaiting;

  /// Verification help dialog action that copies the challenge URL
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get extensionVerificationCopyLink;

  /// Verification help dialog action that retries launching the challenge URL
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get extensionVerificationOpenBrowser;

  /// Verification help dialog dismiss action
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get extensionVerificationClose;

  /// Snackbar confirming the verification link was copied to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get extensionVerificationLinkCopied;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
