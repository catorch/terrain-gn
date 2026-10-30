import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';

/// Pushes the sign-in flow when needed. Returns true once the user is signed in.
Future<bool> ensureSignedIn(BuildContext context) async {
  if (session.signedIn) return true;
  return await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen())) ?? false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+224 ');
  final _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  String get _normalized => _phone.text.replaceAll(RegExp(r'[\s.-]'), '');

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = errorText(AppLocalizations.of(context), error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _start(String channel) {
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_normalized)) {
      setState(() => _error = AppLocalizations.of(context).phoneInvalid);
      return;
    }
    _run(() async {
      await api.post('/auth/otp/start', {'phone': _normalized, 'channel': channel});
      setState(() => _sentTo = _normalized);
    });
  }

  void _verify() => _run(() async {
        await session.save(await api.post('/auth/otp/verify', {'phone': _sentTo, 'code': _code.text.trim()}));
        // The server writes the WhatsApp message in the user's language, so keep it in sync.
        await api.patch('/me', {'locale': session.locale.languageCode});
        if (mounted) Navigator.of(context).pop(true);
      });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.signInTitle)),
      body: ListView(padding: const EdgeInsets.all(Space.lg), children: [
        Text(t.signInToContinue, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(labelText: t.phoneLabel, prefixIcon: const Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: Space.md),
        FilledButton(onPressed: _busy ? null : () => _start('sms'), child: Text(t.sendCodeSms)),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(onPressed: _busy ? null : () => _start('whatsapp'), icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18), label: Text(t.sendCodeWhatsapp)),
        if (_sentTo != null) ...[
          const SizedBox(height: Space.lg),
          Text(t.codeSentTo(_sentTo!), style: const TextStyle(color: Palette.muted)),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: t.codeLabel, counterText: ''),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: Space.md),
          FilledButton(onPressed: _busy ? null : _verify, child: Text(t.verifyCode)),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.md), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
      ]),
    );
  }
}
