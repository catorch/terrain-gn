import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/parcel_outline.dart';

typedef _Corner = ({double x, double y, double? accuracy});

class SubmitParcelScreen extends StatefulWidget {
  const SubmitParcelScreen({super.key});

  @override
  State<SubmitParcelScreen> createState() => _SubmitParcelScreenState();
}

class _SubmitParcelScreenState extends State<SubmitParcelScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _prefecture = TextEditingController();
  final _locality = TextEditingController();
  final _price = TextEditingController();
  final _titleRef = TextEditingController();
  final _idempotencyKey = newIdempotencyKey();
  final _corners = <_Corner>[];
  String _region = 'conakry';
  String _crs = 'EPSG:4326';
  Map<String, dynamic>? _check;
  Map<String, dynamic>? _created;
  String? _error;
  bool _busy = false;
  int _uploaded = 0;

  Map<String, dynamic> get _boundary => {
        'corners': [for (final c in _corners) [c.x, c.y]],
        'crs': _crs,
      };

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on ApiException catch (error) {
      if (error.code == 'PARCEL_OVERLAP') {
        setState(() => _check = {'ok': false, 'conflicts': [for (final c in error.body['conflicts'] as List) {...c as Map, 'blocking': true}]});
      } else {
        setState(() => _error = errorText(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addCorner(_Corner corner) => setState(() {
        _corners.add(corner);
        _check = null;
      });

  Future<void> _addGps() async {
    final t = AppLocalizations.of(context);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.locationDenied)));
      return;
    }
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
    _addCorner((x: position.longitude, y: position.latitude, accuracy: position.accuracy));
  }

  Future<void> _addManual() async {
    final t = AppLocalizations.of(context);
    final geographic = _crs == 'EPSG:4326';
    final first = TextEditingController(), second = TextEditingController();
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.cornerN(_corners.length + 1)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: first, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: InputDecoration(labelText: geographic ? t.latitude : t.easting)),
          const SizedBox(height: Space.sm),
          TextField(controller: second, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: InputDecoration(labelText: geographic ? t.longitude : t.northing)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(context, parse(first) != null && parse(second) != null),
            child: Text(t.add),
          ),
        ],
      ),
    );
    if (added != true) return;
    // People read latitude first; GeoJSON and the API want [longitude, latitude].
    final a = parse(first)!, b = parse(second)!;
    _addCorner(geographic ? (x: b, y: a, accuracy: null) : (x: a, y: b, accuracy: null));
  }

  void _runCheck() => _run(() async {
        final result = await api.post('/parcels/check', _boundary, null, true);
        setState(() => _check = result);
      });

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _run(() async {
      final created = await api.post(
        '/parcels',
        {
          'boundary': _boundary,
          'title': _title.text.trim(),
          'region': _region,
          'prefecture': _prefecture.text.trim(),
          'locality': _locality.text.trim(),
          'priceGnf': int.parse(_price.text.replaceAll(RegExp(r'\D'), '')),
          if (_titleRef.text.trim().isNotEmpty) 'titleRef': _titleRef.text.trim(),
        },
        _idempotencyKey,
      );
      setState(() => _created = created);
    });
  }

  Future<void> _uploadAll(String kind, List<XFile> files) => _run(() async {
        final id = _created!['id'];
        for (final file in files) {
          final bytes = await file.readAsBytes();
          final contentType = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
          final slot = await api.post('/parcels/$id/documents', {'kind': kind, 'contentType': contentType, 'sizeBytes': bytes.length});
          await api.upload(slot['uploadUrl'] as String, (slot['headers'] as Map).cast<String, String>(), bytes);
          await api.post('/parcels/$id/documents/${slot['documentId']}/complete', null, null, true);
          setState(() => _uploaded++);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.submitTitle)),
      body: _created == null ? _formView(t) : _documentsView(t),
    );
  }

  Widget _documentsView(AppLocalizations t) {
    final picker = ImagePicker();
    return ListView(padding: const EdgeInsets.all(Space.lg), children: [
      const Icon(Icons.check_circle, color: Palette.green, size: 56),
      const SizedBox(height: Space.md),
      Text(_created!['code'] as String, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: Space.sm),
      Text(t.submitted, textAlign: TextAlign.center),
      const SizedBox(height: Space.lg),
      // Compressed on the phone (R6.3): a 12 MP photo becomes ~200 KB before it touches mobile data.
      OutlinedButton.icon(
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(t.addPhotos),
        onPressed: _busy ? null : () async => _uploadAll('photo', await picker.pickMultiImage(maxWidth: 1280, imageQuality: 70)),
      ),
      const SizedBox(height: Space.sm),
      OutlinedButton.icon(
        icon: const Icon(Icons.description_outlined),
        label: Text(t.addTitleDeed),
        onPressed: _busy
            ? null
            : () async {
                // Slightly larger than photos so the deed's small print stays legible for the agent.
                final deed = await picker.pickImage(source: kIsWeb ? ImageSource.gallery : ImageSource.camera, maxWidth: 1600, imageQuality: 80);
                if (deed != null) await _uploadAll('title_deed', [deed]);
              },
      ),
      const SizedBox(height: Space.md),
      Text(_busy ? t.uploading : t.uploadedCount(_uploaded), textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted)),
      if (_error != null) Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Palette.danger)),
      const SizedBox(height: Space.lg),
      FilledButton(onPressed: _busy ? null : () => Navigator.of(context).pop(true), child: Text(t.done)),
    ]);
  }

  Widget _formView(AppLocalizations t) {
    String? required(String? value) => value == null || value.trim().isEmpty ? t.required : null;
    final text = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(Space.md), children: [
        TextFormField(controller: _title, decoration: InputDecoration(labelText: t.fieldTitle), validator: required, maxLength: 140),
        DropdownButtonFormField<String>(
          initialValue: _region,
          decoration: InputDecoration(labelText: t.fieldRegion),
          items: [for (final r in regions.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
          onChanged: (value) => setState(() => _region = value!),
        ),
        const SizedBox(height: Space.md),
        TextFormField(controller: _prefecture, decoration: InputDecoration(labelText: t.fieldPrefecture), validator: required),
        const SizedBox(height: Space.md),
        TextFormField(controller: _locality, decoration: InputDecoration(labelText: t.fieldLocality), validator: required),
        const SizedBox(height: Space.md),
        TextFormField(controller: _price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.fieldPrice), validator: required),
        const SizedBox(height: Space.md),
        TextFormField(controller: _titleRef, decoration: InputDecoration(labelText: t.fieldTitleRef)),
        const SizedBox(height: Space.lg),
        Text(t.boundaryTitle, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Space.xs),
        Text(t.boundaryHelp, style: text.bodyMedium?.copyWith(color: Palette.muted)),
        const SizedBox(height: Space.md),
        Text(t.coordinateSystem, style: text.labelLarge),
        const SizedBox(height: Space.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'EPSG:4326', label: Text('GPS')),
            ButtonSegment(value: 'EPSG:32628', label: Text('UTM 28N')),
            ButtonSegment(value: 'EPSG:32629', label: Text('UTM 29N')),
          ],
          selected: {_crs},
          // Mixed systems in one ring would be meaningless, so the choice locks once a marker is added.
          onSelectionChanged: _corners.isEmpty ? (value) => setState(() => _crs = value.first) : null,
        ),
        const SizedBox(height: Space.md),
        ParcelOutline(corners: [for (final c in _corners) [c.x, c.y]], geographic: _crs == 'EPSG:4326', height: 200),
        for (final (index, corner) in _corners.indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, backgroundColor: Palette.green, child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
            title: Text(t.cornerN(index + 1)),
            subtitle: Text('${corner.y.toStringAsFixed(6)}, ${corner.x.toStringAsFixed(6)}'
                '${corner.accuracy == null ? '' : '  ${t.gpsAccuracy(corner.accuracy!.round())}'}'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
              _corners.removeAt(index);
              _check = null;
            })),
          ),
        const SizedBox(height: Space.sm),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _crs == 'EPSG:4326' && !_busy ? _addGps : null, icon: const Icon(Icons.my_location), label: Text(t.addCornerGps))),
          const SizedBox(width: Space.sm),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _addManual, icon: const Icon(Icons.edit_location_alt_outlined), label: Text(t.addCornerManual))),
        ]),
        const SizedBox(height: Space.md),
        OutlinedButton(onPressed: _corners.length >= 3 && !_busy ? _runCheck : null, child: Text(t.checkBoundary)),
        if (_check != null) _CheckResult(check: _check!),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text(_error!, style: const TextStyle(color: Palette.danger))),
        const SizedBox(height: Space.lg),
        FilledButton(onPressed: _corners.length >= 3 && !_busy && _check?['ok'] != false ? _submit : null, child: Text(t.submit)),
        const SizedBox(height: Space.lg),
      ]),
    );
  }
}

class _CheckResult extends StatelessWidget {
  const _CheckResult({required this.check});

  final Map<String, dynamic> check;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final conflicts = (check['conflicts'] as List? ?? []).cast<Map>();
    final messages = <(String, bool)>[
      if (check['problem'] != null) (problemText(t, check['problem'] as String), true),
      for (final c in conflicts)
        c['blocking'] == true
            ? (t.boundaryBlocked(c['code'] as String, formatNumber(context, c['overlapM2'] as num)), true)
            : (t.boundarySoft(c['code'] as String, formatNumber(context, c['overlapM2'] as num)), false),
      if (check['ok'] == true && conflicts.isEmpty) (t.boundaryOk(formatNumber(context, check['areaM2'] as num)), false),
    ];
    return Column(children: [
      for (final (message, blocking) in messages)
        Container(
          margin: const EdgeInsets.only(top: Space.sm),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: blocking ? Palette.dangerSoft : (check['ok'] == true && conflicts.isEmpty ? Palette.greenSoft : Palette.warningSoft),
            borderRadius: BorderRadius.circular(Space.radius),
          ),
          child: Row(children: [
            Icon(blocking ? Icons.block : (conflicts.isEmpty ? Icons.check_circle_outline : Icons.warning_amber), color: blocking ? Palette.danger : (conflicts.isEmpty ? Palette.green : Palette.warning)),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(message)),
          ]),
        ),
    ]);
  }
}
