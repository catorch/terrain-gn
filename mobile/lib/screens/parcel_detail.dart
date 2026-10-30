import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/parcel_outline.dart';
import '../widgets/verified_badge.dart';
import '../widgets/whatsapp_sheet.dart';
import 'login.dart';
import 'reserve.dart';

class ParcelDetailScreen extends StatefulWidget {
  const ParcelDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends State<ParcelDetailScreen> {
  late Future<Map<String, dynamic>> _parcel = _fetch();

  Future<Map<String, dynamic>> _fetch() => api.get('/parcels/${widget.id}');

  Future<void> _reload() async {
    final next = _fetch();
    setState(() => _parcel = next);
    await next.catchError((_) => <String, dynamic>{});
  }

  Future<void> _withdraw() async {
    final t = AppLocalizations.of(context);
    try {
      await api.post('/parcels/${widget.id}/withdraw');
      await _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(t, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder(
      future: _parcel,
      builder: (context, snapshot) {
        final parcel = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(parcel?['code'] as String? ?? '')),
          body: switch (snapshot) {
            AsyncSnapshot(hasError: true) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(errorText(t, snapshot.error!)),
                  TextButton(onPressed: _reload, child: Text(t.retry)),
                ]),
              ),
            AsyncSnapshot(hasData: true) => RefreshIndicator(onRefresh: _reload, child: _Body(parcel: parcel!, onWithdraw: _withdraw)),
            _ => const Center(child: CircularProgressIndicator()),
          },
          bottomNavigationBar: parcel == null || parcel['isOwner'] == true
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (parcel['status'] == 'verified' && parcel['depositGnf'] != null) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.lock_outline),
                          label: Text(t.reserve(formatGnf(context, parcel['depositGnf'] as num))),
                          onPressed: () async {
                            if (!await ensureSignedIn(context) || !context.mounted) return;
                            final reserved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReserveScreen(parcel: parcel)));
                            if (reserved == true) _reload();
                          },
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                      FilledButton.icon(
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(t.contactSeller),
                        onPressed: () async {
                          if (await ensureSignedIn(context) && context.mounted) await showWhatsAppSheet(context, parcel);
                        },
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.parcel, required this.onWithdraw});

  final Map<String, dynamic> parcel;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final photos = (parcel['photos'] as List).cast<String>();
    final ring = ((parcel['boundary'] as Map)['coordinates'] as List).first as List;
    final centroid = (parcel['centroid'] as List).cast<num>();
    final verified = parcel['verified'] == true;
    final status = parcel['status'] as String;
    return ListView(padding: const EdgeInsets.all(Space.md), children: [
      if (photos.isNotEmpty) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(Space.radius),
          child: SizedBox(
            height: 220,
            child: PageView(children: [for (final url in photos) Image.network(url, fit: BoxFit.cover, cacheWidth: 1080)]),
          ),
        ),
        const SizedBox(height: Space.md),
      ],
      Text(parcel['title'] as String, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Space.xs),
      Text('${parcel['locality']}, ${parcel['prefecture']} · ${regions[parcel['region']]}', style: text.bodyLarge?.copyWith(color: Palette.muted)),
      const SizedBox(height: Space.md),
      Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(color: verified ? Palette.greenSoft : Palette.sandDeep, borderRadius: BorderRadius.circular(Space.radius)),
        child: Row(children: [
          VerifiedBadge(verified: verified, large: true),
          const SizedBox(width: Space.md),
          Expanded(child: Text(verified ? t.verifiedOn(formatDate(context, parcel['verifiedAt'] as String)) : t.pendingVerification)),
        ]),
      ),
      if (parcel['isOwner'] == true && status != 'verified') ...[
        const SizedBox(height: Space.sm),
        Text(statusLabel(t, status), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (parcel['rejectionReason'] != null) Text(t.rejectedReason(parcel['rejectionReason'] as String), style: const TextStyle(color: Palette.danger)),
      ],
      const SizedBox(height: Space.md),
      ParcelOutline(corners: [for (final p in ring) (p as List).map((v) => (v as num).toDouble()).toList()]),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: Text(t.openInMaps),
          onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${centroid[1]},${centroid[0]}'), mode: LaunchMode.externalApplication),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: Column(children: [
            _Fact(label: t.plotCode, value: parcel['code'] as String),
            _Fact(label: t.area, value: formatArea(context, parcel['areaM2'] as num)),
            _Fact(label: t.price, value: formatGnf(context, parcel['priceGnf'] as num), strong: true),
            if (parcel['depositGnf'] != null) _Fact(label: t.deposit, value: formatGnf(context, parcel['depositGnf'] as num)),
          ]),
        ),
      ),
      if (parcel['isOwner'] == true && (status == 'pending_verification' || status == 'verified')) ...[
        const SizedBox(height: Space.lg),
        OutlinedButton(onPressed: onWithdraw, style: OutlinedButton.styleFrom(foregroundColor: Palette.danger), child: Text(t.withdraw)),
      ],
    ]);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Palette.muted)),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: strong ? Palette.green : Palette.ink, fontSize: strong ? 17 : 15)),
        ]),
      );
}
