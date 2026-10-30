import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';

class ReserveScreen extends StatefulWidget {
  const ReserveScreen({super.key, required this.parcel});

  final Map<String, dynamic> parcel;

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> with WidgetsBindingObserver {
  // One key per visit: retrying after a dropped response returns the same reservation instead of a second charge.
  String _key = newIdempotencyKey();
  Map<String, dynamic>? _reservation;
  Timer? _poll;
  String? _error;
  bool _busy = false;

  String? get _status => _reservation?['status'] as String?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  /// The buyer comes back from the checkout page: ask the API, which asks CinetPay.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _start() async {
    final t = AppLocalizations.of(context);
    if (_status == 'failed' || _status == 'expired') _key = newIdempotencyKey();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _reservation = await api.post('/parcels/${widget.parcel['id']}/reservations', null, _key);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
      await _openCheckout();
    } on ApiException catch (error) {
      _error = errorText(t, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCheckout() async {
    final url = _reservation?['paymentUrl'] as String?;
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _refresh() async {
    final id = _reservation?['id'];
    if (id == null || _status != 'pending_payment') return;
    try {
      final next = await api.get('/reservations/$id');
      if (!mounted) return;
      setState(() => _reservation = next);
      if (next['status'] != 'pending_payment') _poll?.cancel();
    } on ApiException {
      // Keep polling; a flaky connection is the normal case here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = widget.parcel;
    final (message, color, background) = switch (_status) {
      'pending_payment' => (t.reservationPending, Palette.warning, Palette.warningSoft),
      'held' => (t.reservationHeld, Palette.green, Palette.greenSoft),
      'needs_review' => (t.reservationReview, Palette.warning, Palette.warningSoft),
      'released' => (t.reservationReleased, Palette.green, Palette.greenSoft),
      'refunded' => (t.reservationRefunded, Palette.muted, Palette.sandDeep),
      'expired' => (t.reservationExpired, Palette.danger, Palette.dangerSoft),
      'failed' => (t.reservationFailed, Palette.danger, Palette.dangerSoft),
      _ => (null, Palette.ink, Palette.sand),
    };
    return Scaffold(
      appBar: AppBar(title: Text(t.reserveTitle)),
      body: ListView(padding: const EdgeInsets.all(Space.md), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['code'] as String, style: text.labelLarge?.copyWith(color: Palette.muted)),
              Text(p['title'] as String, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('${p['locality']}, ${p['prefecture']}', style: const TextStyle(color: Palette.muted)),
              const Divider(height: Space.lg),
              Text(t.deposit, style: const TextStyle(color: Palette.muted)),
              Text(formatGnf(context, p['depositGnf'] as num), style: text.headlineSmall?.copyWith(color: Palette.green, fontWeight: FontWeight.w800)),
              const SizedBox(height: Space.xs),
              Text('${t.price} : ${formatGnf(context, p['priceGnf'] as num)}', style: const TextStyle(color: Palette.muted)),
            ]),
          ),
        ),
        const SizedBox(height: Space.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline, size: 20, color: Palette.green),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(t.reserveExplain)),
        ]),
        if (message != null) ...[
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Space.radius)),
            child: Row(children: [
              if (_status == 'pending_payment') const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              if (_status == 'pending_payment') const SizedBox(width: Space.sm),
              Expanded(child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
        const SizedBox(height: Space.lg),
        if (_status == null || _status == 'failed' || _status == 'expired')
          FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.phone_android), label: Text(t.payDeposit)),
        if (_status == 'pending_payment') ...[
          FilledButton(onPressed: _openCheckout, child: Text(t.openPayment)),
          const SizedBox(height: Space.sm),
          OutlinedButton(onPressed: _refresh, child: Text(t.checkPayment)),
        ],
        if (_status != null && _status != 'pending_payment' && _status != 'failed' && _status != 'expired')
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t.done)),
      ]),
    );
  }
}
