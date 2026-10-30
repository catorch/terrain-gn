import 'package:flutter/material.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import 'login.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _setLanguage(String code) async {
    await session.setLocale(Locale(code));
    if (session.signedIn) await api.patch('/me', {'locale': code}).catchError((_) => <String, dynamic>{});
  }

  Future<void> _signOut() async {
    await api.post('/auth/logout', {'refreshToken': session.refreshToken}).catchError((_) => <String, dynamic>{});
    await session.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(t.tabAccount)),
        body: ListView(padding: const EdgeInsets.all(Space.md), children: [
          if (session.signedIn)
            Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(session.user?['name'] as String? ?? session.user?['phone'] as String? ?? '')))
          else
            FilledButton(onPressed: () => ensureSignedIn(context), child: Text(t.signInTitle)),
          const SizedBox(height: Space.lg),
          Text(t.language, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Space.sm),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'fr', label: Text('Français')), ButtonSegment(value: 'en', label: Text('English'))],
            selected: {session.locale.languageCode},
            onSelectionChanged: (value) => _setLanguage(value.first),
          ),
          if (session.signedIn) ...[
            const SizedBox(height: Space.lg),
            const _PayoutWallet(),
            const SizedBox(height: Space.lg),
            OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout), label: Text(t.signOut)),
          ],
        ]),
      ),
    );
  }
}

/// Where sale payments and refunds go. Any change waits for an agent before money can move to it.
class _PayoutWallet extends StatefulWidget {
  const _PayoutWallet();

  @override
  State<_PayoutWallet> createState() => _PayoutWalletState();
}

class _PayoutWalletState extends State<_PayoutWallet> {
  late final _phone = TextEditingController(text: session.user?['payoutPhone'] as String? ?? '+224');
  late String _method = session.user?['payoutMethod'] as String? ?? 'OM_GN';
  String? _message;
  bool _busy = false;

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final phone = _phone.text.replaceAll(RegExp(r'[\s.-]'), '');
    if (!RegExp(r'^\+224\d{9}$').hasMatch(phone)) return setState(() => _message = t.walletInvalid);
    setState(() => _busy = true);
    try {
      await session.setUser(await api.patch('/me', {'payout': {'phone': phone, 'method': _method}}));
      _message = t.saved;
    } catch (error) {
      _message = errorText(t, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final verified = session.user?['payoutVerified'] == true;
    final hasWallet = session.user?['payoutPhone'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.payoutWallet, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Space.xs),
          Text(t.payoutWalletHelp, style: const TextStyle(color: Palette.muted)),
          if (hasWallet) ...[
            const SizedBox(height: Space.sm),
            Row(children: [
              Icon(verified ? Icons.verified_user : Icons.hourglass_top, size: 16, color: verified ? Palette.green : Palette.warning),
              const SizedBox(width: Space.xs),
              Text(verified ? t.walletVerified : t.walletPending, style: TextStyle(color: verified ? Palette.green : Palette.warning)),
            ]),
          ],
          const SizedBox(height: Space.md),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'OM_GN', label: Text('Orange Money')), ButtonSegment(value: 'MTN_GN', label: Text('MTN MoMo'))],
            selected: {_method},
            onSelectionChanged: (value) => setState(() => _method = value.first),
          ),
          const SizedBox(height: Space.sm),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t.phoneLabel)),
          const SizedBox(height: Space.sm),
          FilledButton(onPressed: _busy ? null : _save, child: Text(t.save)),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text(_message!, textAlign: TextAlign.center)),
        ]),
      ),
    );
  }
}
