import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrain_gn/l10n/app_localizations.dart';
import 'package:terrain_gn/widgets/whatsapp_sheet.dart';

const parcel = {'id': 42, 'code': 'TGN-000042', 'locality': 'Kipé', 'prefecture': 'Ratoma', 'areaM2': 500, 'priceGnf': 450000000, 'verified': true};

Widget _host(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(body: WhatsAppSheet(parcel: parcel)),
    );

void main() {
  testWidgets('French sheet shows the plot summary and the WhatsApp action', (tester) async {
    await tester.pumpWidget(_host(const Locale('fr')));
    expect(find.text('Contacter via WhatsApp'), findsOneWidget);
    expect(find.text('TGN-000042'), findsOneWidget);
    expect(find.text('Kipé, Ratoma'), findsOneWidget);
    expect(find.textContaining(RegExp(r'450\s000\s000 GNF')), findsOneWidget);
    expect(find.text('Vérifié'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });

  testWidgets('English sheet uses the English label', (tester) async {
    await tester.pumpWidget(_host(const Locale('en')));
    expect(find.text('Connect via WhatsApp'), findsOneWidget);
    expect(find.text('450,000,000 GNF'), findsOneWidget);
  });
}
