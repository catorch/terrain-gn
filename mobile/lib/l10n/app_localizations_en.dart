// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Terrain GN';

  @override
  String get tabListings => 'Land';

  @override
  String get tabMine => 'My plots';

  @override
  String get tabAccount => 'Account';

  @override
  String get allRegions => 'All regions';

  @override
  String get verifiedBadge => 'Verified';

  @override
  String verifiedOn(String date) {
    return 'Verified on site by a field agent on $date';
  }

  @override
  String get pendingVerification => 'Awaiting field verification';

  @override
  String get statusPending => 'Pending verification';

  @override
  String get statusVerified => 'Published';

  @override
  String get statusReserved => 'Reserved';

  @override
  String get statusSold => 'Sold';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusWithdrawn => 'Withdrawn';

  @override
  String get emptyListings => 'No verified plots here yet.';

  @override
  String get retry => 'Retry';

  @override
  String get networkError => 'No connection. Check your network and try again.';

  @override
  String genericError(String code) {
    return 'Something went wrong ($code).';
  }

  @override
  String get plotCode => 'Plot ID';

  @override
  String get location => 'Location';

  @override
  String get area => 'Area';

  @override
  String get price => 'Price';

  @override
  String get deposit => 'Reservation deposit';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get contactSeller => 'Contact the seller';

  @override
  String get whatsappSheetTitle => 'Continue on WhatsApp';

  @override
  String get whatsappSheetBody =>
      'WhatsApp will open with this summary ready to send to the seller.';

  @override
  String get connectWhatsapp => 'Connect via WhatsApp';

  @override
  String get cancel => 'Cancel';

  @override
  String get whatsappSafety =>
      'Never send money outside an agent-verified reservation.';

  @override
  String get whatsappUnavailable => 'Couldn\'t open WhatsApp.';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInToContinue =>
      'Sign in to contact sellers and list your land.';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneInvalid =>
      'Enter your number with the country code, e.g. +224…';

  @override
  String get sendCodeSms => 'Get the code by SMS';

  @override
  String get sendCodeWhatsapp => 'Get the code on WhatsApp';

  @override
  String get codeLabel => '6-digit code';

  @override
  String codeSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get verifyCode => 'Confirm';

  @override
  String get otpInvalid => 'Wrong or expired code.';

  @override
  String get rateLimited => 'Too many attempts. Wait a minute and try again.';

  @override
  String get signOut => 'Sign out';

  @override
  String get language => 'Language';

  @override
  String get myParcelsEmpty => 'You haven\'t listed any land yet.';

  @override
  String get addParcel => 'List a plot';

  @override
  String get submitTitle => 'New plot';

  @override
  String get fieldTitle => 'Listing title';

  @override
  String get fieldRegion => 'Region';

  @override
  String get fieldPrefecture => 'Prefecture';

  @override
  String get fieldLocality => 'Neighbourhood or village';

  @override
  String get fieldPrice => 'Price (GNF)';

  @override
  String get fieldTitleRef => 'Title or permit number (optional)';

  @override
  String get required => 'Required';

  @override
  String get boundaryTitle => 'Boundary markers';

  @override
  String get boundaryHelp =>
      'Stand at each boundary marker and add your position, or type the coordinates from your survey plan, in order around the plot.';

  @override
  String get addCornerGps => 'Add my position';

  @override
  String get addCornerManual => 'Type coordinates';

  @override
  String cornerN(int n) {
    return 'Marker $n';
  }

  @override
  String gpsAccuracy(int meters) {
    return '±$meters m';
  }

  @override
  String get coordinateSystem => 'Coordinate system';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get easting => 'X (easting)';

  @override
  String get northing => 'Y (northing)';

  @override
  String get add => 'Add';

  @override
  String get checkBoundary => 'Check boundary';

  @override
  String boundaryOk(String area) {
    return 'Valid boundary: $area m², no competing claim.';
  }

  @override
  String boundaryBlocked(String code, String m2) {
    return 'Overlaps plot $code by $m2 m². This land is already claimed.';
  }

  @override
  String boundarySoft(String code, String m2) {
    return 'Touches plot $code by $m2 m². An agent will check it on site.';
  }

  @override
  String get problemInvalid =>
      'The markers cross each other. Add them in order around the plot.';

  @override
  String get problemOutside => 'This boundary is outside Guinea.';

  @override
  String get problemArea => 'The area must be between 50 m² and 500 ha.';

  @override
  String get problemCorners => 'Add between 3 and 200 markers.';

  @override
  String get duplicateTitleRef =>
      'This title number is already used by another listing.';

  @override
  String get submit => 'Submit for verification';

  @override
  String get submitted =>
      'Submitted. A field agent will visit the plot before it is published.';

  @override
  String get addPhotos => 'Add photos';

  @override
  String get addTitleDeed => 'Photo of the title deed';

  @override
  String get uploading => 'Uploading…';

  @override
  String uploadedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files uploaded',
      one: '1 file uploaded',
      zero: 'No files uploaded yet',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Done';

  @override
  String get locationDenied => 'Allow location access to add your position.';

  @override
  String get withdraw => 'Withdraw listing';

  @override
  String rejectedReason(String reason) {
    return 'Rejected: $reason';
  }

  @override
  String get parcelLocked => 'This plot can no longer be changed.';

  @override
  String reserve(String amount) {
    return 'Reserve with a $amount deposit';
  }

  @override
  String get reserveTitle => 'Reserve this plot';

  @override
  String get reserveExplain =>
      'Your deposit is collected by CinetPay and held until our team confirms the sale. The seller does not receive it directly.';

  @override
  String get payDeposit => 'Pay the deposit by Mobile Money';

  @override
  String get openPayment => 'Open the payment page';

  @override
  String get checkPayment => 'I\'ve paid, check again';

  @override
  String get reservationPending => 'Waiting for your payment…';

  @override
  String get reservationHeld =>
      'Deposit secured. The plot is reserved for you.';

  @override
  String get reservationFailed =>
      'The payment did not go through. You can try again.';

  @override
  String get reservationExpired =>
      'The payment window closed. You can start again.';

  @override
  String get reservationReview =>
      'Payment received. Our team is checking it and will contact you.';

  @override
  String get reservationReleased => 'Sale completed.';

  @override
  String get reservationRefunded => 'Deposit refunded.';

  @override
  String get parcelNotAvailable =>
      'This plot is no longer available to reserve.';

  @override
  String get paymentsUnavailable =>
      'Payments are not available yet. Contact the seller on WhatsApp.';

  @override
  String get depositTooHigh => 'This deposit is above the Mobile Money limit.';

  @override
  String get payoutWallet => 'Payout wallet';

  @override
  String get payoutWalletHelp =>
      'Where you receive a sale payment or a refund. A Guinean Orange Money or MTN number.';

  @override
  String get walletPending => 'Awaiting agent confirmation';

  @override
  String get walletVerified => 'Confirmed by an agent';

  @override
  String get walletInvalid =>
      'Enter a Guinean number: +224 followed by 9 digits.';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';
}
