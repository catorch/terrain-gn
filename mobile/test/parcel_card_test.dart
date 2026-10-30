import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrain_gn/l10n/app_localizations.dart';
import 'package:terrain_gn/screens/listings.dart';

Widget _card(String status) => MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: ParcelCard(parcel: {'id': 1, 'code': 'TGN-000011', 'status': status, 'verified': true, 'title': 'Terrain', 'locality': 'Koba', 'prefecture': 'Boffa', 'areaM2': 1597, 'priceGnf': 300000000, 'coverUrl': null}),
      ),
    );

void main() {
  testWidgets('a reserved plot is tagged so it does not read as available', (tester) async {
    await tester.pumpWidget(_card('reserved'));
    expect(find.text('Réservé'), findsOneWidget);
    expect(find.text('Vérifié'), findsOneWidget);
  });

  testWidgets('an available plot only shows the badge', (tester) async {
    await tester.pumpWidget(_card('verified'));
    expect(find.text('Réservé'), findsNothing);
  });
}
