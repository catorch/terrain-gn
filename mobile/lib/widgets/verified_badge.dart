import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// The trust marker an agent switches on from Retool. Unverified plots get a neutral pill, never a lookalike.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verified, this.large = false});

  final bool verified;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = verified ? Palette.green : Palette.muted;
    return Semantics(
      label: verified ? t.verifiedBadge : t.pendingVerification,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
        decoration: BoxDecoration(color: verified ? Palette.greenSoft : Palette.sandDeep, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(verified ? Icons.verified_user : Icons.hourglass_top, size: large ? 18 : 14, color: color),
          const SizedBox(width: 4),
          Text(verified ? t.verifiedBadge : t.statusPending,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: large ? 14 : 12)),
        ]),
      ),
    );
  }
}
