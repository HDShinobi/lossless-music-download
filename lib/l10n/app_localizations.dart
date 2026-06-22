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
