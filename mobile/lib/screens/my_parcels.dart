import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import 'listings.dart';
import 'login.dart';
import 'submit_parcel.dart';

class MyParcelsScreen extends StatefulWidget {
  const MyParcelsScreen({super.key});

  @override
  State<MyParcelsScreen> createState() => _MyParcelsScreenState();
}

class _MyParcelsScreenState extends State<MyParcelsScreen> {
  Future<Map<String, dynamic>>? _mine;

  Future<void> _reload() async {
    final next = api.get('/me/parcels');
    setState(() => _mine = next);
    await next.catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.signedIn) {
          return Scaffold(
            appBar: AppBar(title: Text(t.tabMine)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(t.signInToContinue, textAlign: TextAlign.center),
                  const SizedBox(height: Space.md),
                  FilledButton(onPressed: () => ensureSignedIn(context), child: Text(t.signInTitle)),
                ]),
              ),
            ),
          );
        }
        _mine ??= api.get('/me/parcels');
        return Scaffold(
          appBar: AppBar(title: Text(t.tabMine)),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(t.addParcel),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SubmitParcelScreen()));
              if (created == true) _reload();
            },
          ),
          body: FutureBuilder(
            future: _mine,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: TextButton(onPressed: _reload, child: Text('${errorText(t, snapshot.error!)}\n${t.retry}', textAlign: TextAlign.center)));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final items = (snapshot.data!['items'] as List).cast<Map<String, dynamic>>();
              return RefreshIndicator(
                onRefresh: _reload,
                child: items.isEmpty
                    ? ListView(children: [const SizedBox(height: 120), Center(child: Text(t.myParcelsEmpty))])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 96),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                        itemBuilder: (_, index) => ParcelCard(parcel: items[index], showStatus: true),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}
