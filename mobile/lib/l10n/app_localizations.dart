import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

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
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Terrain GN'**
  String get appTitle;

  /// No description provided for @tabListings.
  ///
  /// In en, this message translates to:
  /// **'Land'**
  String get tabListings;

  /// No description provided for @tabMine.
  ///
  /// In en, this message translates to:
  /// **'My plots'**
  String get tabMine;

  /// No description provided for @tabAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get tabAccount;

  /// No description provided for @allRegions.
  ///
  /// In en, this message translates to:
  /// **'All regions'**
  String get allRegions;

  /// No description provided for @verifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verifiedBadge;

  /// No description provided for @verifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified on site by a field agent on {date}'**
  String verifiedOn(String date);

  /// No description provided for @pendingVerification.
  ///
  /// In en, this message translates to:
  /// **'Awaiting field verification'**
  String get pendingVerification;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get statusPending;

  /// No description provided for @statusVerified.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get statusVerified;

  /// No description provided for @statusReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get statusReserved;

  /// No description provided for @statusSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get statusSold;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get statusWithdrawn;

  /// No description provided for @emptyListings.
  ///
  /// In en, this message translates to:
  /// **'No verified plots here yet.'**
  String get emptyListings;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network and try again.'**
  String get networkError;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({code}).'**
  String genericError(String code);

  /// No description provided for @plotCode.
  ///
  /// In en, this message translates to:
  /// **'Plot ID'**
  String get plotCode;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @deposit.
  ///
  /// In en, this message translates to:
  /// **'Reservation deposit'**
  String get deposit;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @contactSeller.
  ///
  /// In en, this message translates to:
  /// **'Contact the seller'**
  String get contactSeller;

  /// No description provided for @whatsappSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue on WhatsApp'**
  String get whatsappSheetTitle;

  /// No description provided for @whatsappSheetBody.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp will open with this summary ready to send to the seller.'**
  String get whatsappSheetBody;

  /// No description provided for @connectWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Connect via WhatsApp'**
  String get connectWhatsapp;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @whatsappSafety.
  ///
  /// In en, this message translates to:
  /// **'Never send money outside an agent-verified reservation.'**
  String get whatsappSafety;

  /// No description provided for @whatsappUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open WhatsApp.'**
  String get whatsappUnavailable;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to contact sellers and list your land.'**
  String get signInToContinue;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneLabel;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter your number with the country code, e.g. +224…'**
  String get phoneInvalid;

  /// No description provided for @sendCodeSms.
  ///
  /// In en, this message translates to:
  /// **'Get the code by SMS'**
  String get sendCodeSms;

  /// No description provided for @sendCodeWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Get the code on WhatsApp'**
  String get sendCodeWhatsapp;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get codeLabel;

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String codeSentTo(String phone);

  /// No description provided for @verifyCode.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get verifyCode;

  /// No description provided for @otpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Wrong or expired code.'**
  String get otpInvalid;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get rateLimited;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @myParcelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t listed any land yet.'**
  String get myParcelsEmpty;

  /// No description provided for @addParcel.
  ///
  /// In en, this message translates to:
  /// **'List a plot'**
  String get addParcel;

  /// No description provided for @submitTitle.
  ///
  /// In en, this message translates to:
  /// **'New plot'**
  String get submitTitle;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Listing title'**
  String get fieldTitle;

  /// No description provided for @fieldRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get fieldRegion;

  /// No description provided for @fieldPrefecture.
  ///
  /// In en, this message translates to:
  /// **'Prefecture'**
  String get fieldPrefecture;

  /// No description provided for @fieldLocality.
  ///
  /// In en, this message translates to:
  /// **'Neighbourhood or village'**
  String get fieldLocality;

  /// No description provided for @fieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (GNF)'**
  String get fieldPrice;

  /// No description provided for @fieldTitleRef.
  ///
  /// In en, this message translates to:
  /// **'Title or permit number (optional)'**
  String get fieldTitleRef;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @boundaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Boundary markers'**
  String get boundaryTitle;

  /// No description provided for @boundaryHelp.
  ///
  /// In en, this message translates to:
  /// **'Stand at each boundary marker and add your position, or type the coordinates from your survey plan, in order around the plot.'**
  String get boundaryHelp;

  /// No description provided for @addCornerGps.
  ///
  /// In en, this message translates to:
  /// **'Add my position'**
  String get addCornerGps;

  /// No description provided for @addCornerManual.
  ///
  /// In en, this message translates to:
  /// **'Type coordinates'**
  String get addCornerManual;

  /// No description provided for @cornerN.
  ///
  /// In en, this message translates to:
  /// **'Marker {n}'**
  String cornerN(int n);

  /// No description provided for @gpsAccuracy.
  ///
  /// In en, this message translates to:
  /// **'±{meters} m'**
  String gpsAccuracy(int meters);

  /// No description provided for @coordinateSystem.
  ///
  /// In en, this message translates to:
  /// **'Coordinate system'**
  String get coordinateSystem;

  /// No description provided for @latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitude;

  /// No description provided for @easting.
  ///
  /// In en, this message translates to:
  /// **'X (easting)'**
  String get easting;

  /// No description provided for @northing.
  ///
  /// In en, this message translates to:
  /// **'Y (northing)'**
  String get northing;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @checkBoundary.
  ///
  /// In en, this message translates to:
  /// **'Check boundary'**
  String get checkBoundary;

  /// No description provided for @boundaryOk.
  ///
  /// In en, this message translates to:
  /// **'Valid boundary: {area} m², no competing claim.'**
  String boundaryOk(String area);

  /// No description provided for @boundaryBlocked.
  ///
  /// In en, this message translates to:
  /// **'Overlaps plot {code} by {m2} m². This land is already claimed.'**
  String boundaryBlocked(String code, String m2);

  /// No description provided for @boundarySoft.
  ///
  /// In en, this message translates to:
  /// **'Touches plot {code} by {m2} m². An agent will check it on site.'**
  String boundarySoft(String code, String m2);

  /// No description provided for @problemInvalid.
  ///
  /// In en, this message translates to:
  /// **'The markers cross each other. Add them in order around the plot.'**
  String get problemInvalid;

  /// No description provided for @problemOutside.
  ///
  /// In en, this message translates to:
  /// **'This boundary is outside Guinea.'**
  String get problemOutside;

  /// No description provided for @problemArea.
  ///
  /// In en, this message translates to:
  /// **'The area must be between 50 m² and 500 ha.'**
  String get problemArea;

  /// No description provided for @problemCorners.
  ///
  /// In en, this message translates to:
  /// **'Add between 3 and 200 markers.'**
  String get problemCorners;

  /// No description provided for @duplicateTitleRef.
  ///
  /// In en, this message translates to:
  /// **'This title number is already used by another listing.'**
  String get duplicateTitleRef;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit for verification'**
  String get submit;

  /// No description provided for @submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted. A field agent will visit the plot before it is published.'**
  String get submitted;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get addPhotos;

  /// No description provided for @addTitleDeed.
  ///
  /// In en, this message translates to:
  /// **'Photo of the title deed'**
  String get addTitleDeed;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @uploadedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No files uploaded yet} =1{1 file uploaded} other{{count} files uploaded}}'**
  String uploadedCount(int count);

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Allow location access to add your position.'**
  String get locationDenied;

  /// No description provided for @withdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw listing'**
  String get withdraw;

  /// No description provided for @rejectedReason.
  ///
  /// In en, this message translates to:
  /// **'Rejected: {reason}'**
  String rejectedReason(String reason);

  /// No description provided for @parcelLocked.
  ///
  /// In en, this message translates to:
  /// **'This plot can no longer be changed.'**
  String get parcelLocked;

  /// No description provided for @reserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve with a {amount} deposit'**
  String reserve(String amount);

  /// No description provided for @reserveTitle.
  ///
  /// In en, this message translates to:
  /// **'Reserve this plot'**
  String get reserveTitle;

  /// No description provided for @reserveExplain.
  ///
  /// In en, this message translates to:
  /// **'Your deposit is collected by CinetPay and held until our team confirms the sale. The seller does not receive it directly.'**
  String get reserveExplain;

  /// No description provided for @payDeposit.
  ///
  /// In en, this message translates to:
  /// **'Pay the deposit by Mobile Money'**
  String get payDeposit;

  /// No description provided for @openPayment.
  ///
  /// In en, this message translates to:
  /// **'Open the payment page'**
  String get openPayment;

  /// No description provided for @checkPayment.
  ///
  /// In en, this message translates to:
  /// **'I\'ve paid, check again'**
  String get checkPayment;

  /// No description provided for @reservationPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your payment…'**
  String get reservationPending;

  /// No description provided for @reservationHeld.
  ///
  /// In en, this message translates to:
  /// **'Deposit secured. The plot is reserved for you.'**
  String get reservationHeld;

  /// No description provided for @reservationFailed.
  ///
  /// In en, this message translates to:
  /// **'The payment did not go through. You can try again.'**
  String get reservationFailed;

  /// No description provided for @reservationExpired.
  ///
  /// In en, this message translates to:
  /// **'The payment window closed. You can start again.'**
  String get reservationExpired;

  /// No description provided for @reservationReview.
  ///
  /// In en, this message translates to:
  /// **'Payment received. Our team is checking it and will contact you.'**
  String get reservationReview;

  /// No description provided for @reservationReleased.
  ///
  /// In en, this message translates to:
  /// **'Sale completed.'**
  String get reservationReleased;

  /// No description provided for @reservationRefunded.
  ///
  /// In en, this message translates to:
  /// **'Deposit refunded.'**
  String get reservationRefunded;

  /// No description provided for @parcelNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This plot is no longer available to reserve.'**
  String get parcelNotAvailable;

  /// No description provided for @paymentsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Payments are not available yet. Contact the seller on WhatsApp.'**
  String get paymentsUnavailable;

  /// No description provided for @depositTooHigh.
  ///
  /// In en, this message translates to:
  /// **'This deposit is above the Mobile Money limit.'**
  String get depositTooHigh;

  /// No description provided for @payoutWallet.
  ///
  /// In en, this message translates to:
  /// **'Payout wallet'**
  String get payoutWallet;

  /// No description provided for @payoutWalletHelp.
  ///
  /// In en, this message translates to:
  /// **'Where you receive a sale payment or a refund. A Guinean Orange Money or MTN number.'**
  String get payoutWalletHelp;

  /// No description provided for @walletPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting agent confirmation'**
  String get walletPending;

  /// No description provided for @walletVerified.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by an agent'**
  String get walletVerified;

  /// No description provided for @walletInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a Guinean number: +224 followed by 9 digits.'**
  String get walletInvalid;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;
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
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
