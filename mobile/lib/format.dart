import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';

const regions = {
  'conakry': 'Conakry',
  'boke': 'Boké',
  'kindia': 'Kindia',
  'mamou': 'Mamou',
  'labe': 'Labé',
  'faranah': 'Faranah',
  'kankan': 'Kankan',
  'nzerekore': "N'Zérékoré",
};

String _locale(BuildContext context) => Localizations.localeOf(context).languageCode;

String formatNumber(BuildContext context, num value) => NumberFormat.decimalPattern(_locale(context)).format(value.round());

String formatGnf(BuildContext context, num value) => '${formatNumber(context, value)} GNF';

String formatArea(BuildContext context, num value) => '${formatNumber(context, value)} m²';

String formatDate(BuildContext context, String iso) => DateFormat.yMMMd(_locale(context)).format(DateTime.parse(iso).toLocal());

String statusLabel(AppLocalizations t, String status) => switch (status) {
      'verified' => t.statusVerified,
      'reserved' => t.statusReserved,
      'sold' => t.statusSold,
      'rejected' => t.statusRejected,
      'withdrawn' => t.statusWithdrawn,
      _ => t.statusPending,
    };

/// Turns an API error code into a sentence; unknown codes still show the code for support.
String errorText(AppLocalizations t, Object error) {
  if (error is! ApiException) return t.genericError('APP');
  return switch (error.code) {
    'NETWORK' => t.networkError,
    'OTP_INVALID' => t.otpInvalid,
    'RATE_LIMITED' => t.rateLimited,
    'DUPLICATE_TITLE_REF' => t.duplicateTitleRef,
    'TOO_FEW_CORNERS' => t.problemCorners,
    'PARCEL_LOCKED' => t.parcelLocked,
    'PARCEL_NOT_AVAILABLE' => t.parcelNotAvailable,
    'PAYMENTS_NOT_CONFIGURED' || 'PAYMENT_PROVIDER_UNAVAILABLE' => t.paymentsUnavailable,
    'DEPOSIT_ABOVE_GATEWAY_LIMIT' => t.depositTooHigh,
    'BOUNDARY_INVALID' => problemText(t, error.body['problem'] as String?),
    _ => t.genericError(error.code),
  };
}

String problemText(AppLocalizations t, String? problem) => switch (problem) {
      'INVALID_GEOMETRY' => t.problemInvalid,
      'OUTSIDE_GUINEA' => t.problemOutside,
      'AREA_OUT_OF_RANGE' => t.problemArea,
      _ => t.problemCorners,
    };
