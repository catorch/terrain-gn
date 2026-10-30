import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/verified_badge.dart';
import 'parcel_detail.dart';

class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key});

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  String? _region;
  int? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _load();
    });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_done && !reset)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.get('/parcels', query: {'region': _region, 'cursor': reset ? null : _cursor?.toString()});
      setState(() {
        if (reset) _items.clear();
        _items.addAll((page['items'] as List).cast<Map<String, dynamic>>());
        _cursor = page['nextCursor'] as int?;
        _done = _cursor == null;
      });
    } catch (error) {
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setRegion(String? region) {
    _region = region;
    _done = false;
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.landscape_rounded, color: Palette.green),
          const SizedBox(width: Space.sm),
          Text(t.appTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.md), children: [
            for (final entry in [MapEntry<String?, String>(null, t.allRegions), ...regions.entries])
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: ChoiceChip(label: Text(entry.value), selected: _region == entry.key, onSelected: (_) => _setRegion(entry.key)),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: _items.isEmpty && !_loading
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error != null ? errorText(t, _error!) : t.emptyListings, textAlign: TextAlign.center)),
                    if (_error != null) Center(child: TextButton(onPressed: () => _load(reset: true), child: Text(t.retry))),
                  ])
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Space.md),
                    itemCount: _items.length + (_loading ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                    itemBuilder: (context, index) => index == _items.length
                        ? const Center(child: Padding(padding: EdgeInsets.all(Space.md), child: CircularProgressIndicator()))
                        : ParcelCard(parcel: _items[index]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class ParcelCard extends StatelessWidget {
  const ParcelCard({super.key, required this.parcel, this.showStatus = false});

  final Map<String, dynamic> parcel;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final cover = parcel['coverUrl'] as String?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParcelDetailScreen(id: parcel['id'] as int))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 7,
            child: cover == null
                ? Container(color: Palette.sandDeep, child: const Icon(Icons.landscape_outlined, size: 48, color: Palette.muted))
                : Image.network(cover, fit: BoxFit.cover, cacheWidth: 720, errorBuilder: (_, _, _) => Container(color: Palette.sandDeep)),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(parcel['code'] as String, style: text.labelMedium?.copyWith(color: Palette.muted, letterSpacing: 0.5)),
                const Spacer(),
                if (showStatus && parcel['status'] != 'verified' && parcel['status'] != 'reserved')
                  Text(statusLabel(t, parcel['status'] as String), style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700))
                else ...[
                  // Reserved plots stay listed but must not read as available.
                  if (parcel['status'] == 'reserved')
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: Text(t.statusReserved, style: text.labelMedium?.copyWith(color: Palette.gold, fontWeight: FontWeight.w800)),
                    ),
                  VerifiedBadge(verified: parcel['verified'] == true),
                ],
              ]),
              const SizedBox(height: Space.xs),
              Text(parcel['title'] as String, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.xs),
              Text('${parcel['locality']}, ${parcel['prefecture']} · ${formatArea(context, parcel['areaM2'] as num)}', style: text.bodyMedium?.copyWith(color: Palette.muted)),
              const SizedBox(height: Space.sm),
              Text(formatGnf(context, parcel['priceGnf'] as num), style: text.titleMedium?.copyWith(color: Palette.green, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }
}
