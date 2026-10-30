import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/account.dart';
import 'screens/listings.dart';
import 'screens/my_parcels.dart';
import 'services.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await session.restore();
  runApp(const TerrainApp());
}

class TerrainApp extends StatelessWidget {
  const TerrainApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: session.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const HomeShell(),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [ListingsScreen(), MyParcelsScreen(), AccountScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.landscape_outlined), selectedIcon: const Icon(Icons.landscape), label: t.tabListings),
          NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder), label: t.tabMine),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t.tabAccount),
        ],
      ),
    );
  }
}
