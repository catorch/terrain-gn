import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import 'verified_badge.dart';

Future<void> showWhatsAppSheet(BuildContext context, Map<String, dynamic> parcel) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WhatsAppSheet(parcel: parcel),
    );

/// Confirmation step before leaving the app: the buyer sees exactly what the seller will receive.
class WhatsAppSheet extends StatefulWidget {
  const WhatsAppSheet({super.key, required this.parcel});

  final Map<String, dynamic> parcel;

  @override
  State<WhatsAppSheet> createState() => _WhatsAppSheetState();
}

class _WhatsAppSheetState extends State<WhatsAppSheet> {
  bool _opening = false;

  Future<void> _open() async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _opening = true);
    try {
      // The server builds the link: it owns the seller's number, the wording and the lead log.
      final handoff = await api.post('/parcels/${widget.parcel['id']}/contact');
      final launched = await launchUrl(Uri.parse(handoff['url'] as String), mode: LaunchMode.externalApplication).catchError((_) => false);
      if (launched) return navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.whatsappUnavailable)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(t, error))));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = widget.parcel;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Palette.whatsapp, shape: BoxShape.circle),
            child: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 22),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text(t.whatsappSheetTitle, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: Space.sm),
        Text(t.whatsappSheetBody, style: text.bodyMedium?.copyWith(color: Palette.muted)),
        const SizedBox(height: Space.md),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(color: Palette.sand, borderRadius: BorderRadius.circular(Space.radius), border: Border.all(color: Palette.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p['code'] as String, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5))),
              VerifiedBadge(verified: p['verified'] == true),
            ]),
            const SizedBox(height: Space.sm),
            _SummaryLine(icon: Icons.place_outlined, label: t.location, value: '${p['locality']}, ${p['prefecture']}'),
            _SummaryLine(icon: Icons.straighten, label: t.area, value: formatArea(context, p['areaM2'] as num)),
            _SummaryLine(icon: Icons.payments_outlined, label: t.price, value: formatGnf(context, p['priceGnf'] as num), strong: true),
          ]),
        ),
        const SizedBox(height: Space.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.shield_outlined, size: 18, color: Palette.warning),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(t.whatsappSafety, style: text.bodySmall?.copyWith(color: Palette.warning))),
        ]),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Palette.whatsapp, foregroundColor: Palette.whatsappInk, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: _opening ? null : _open,
          icon: _opening
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.whatsappInk))
              : const FaIcon(FontAwesomeIcons.whatsapp, size: 22),
          label: Text(t.connectWhatsapp),
        ),
        const SizedBox(height: Space.sm),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
      ]),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label, required this.value, this.strong = false});

  final IconData icon;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: Palette.muted),
          const SizedBox(width: Space.sm),
          Text(label, style: const TextStyle(color: Palette.muted)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: strong ? Palette.green : Palette.ink)),
          ),
        ]),
      );
}
