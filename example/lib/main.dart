import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigma/sigma.dart';

// A demo: it keeps the key in the app so it can run on its own. A real app
// keeps the key on its server and asks the server for links.
// Run with --dart-define=SIGMA_CLOUD=… --dart-define=SIGMA_KEY=sgm_test_… to skip typing them.
const _cloud = String.fromEnvironment('SIGMA_CLOUD', defaultValue: 'http://localhost:3333');
const _key = String.fromEnvironment('SIGMA_KEY');

void main() => runApp(const MaterialApp(title: 'Sigma sheets', home: SheetsPage()));

Future<Map<String, dynamic>> _api(String cloud, String key, String path, {String method = 'GET'}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$cloud/api/v1/sigma/$path'));
    req.headers.set('Authorization', 'Bearer $key');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    if (res.statusCode >= 300) throw Exception(json['error'] ?? 'HTTP ${res.statusCode}');
    return json;
  } finally {
    client.close();
  }
}

class SheetsPage extends StatefulWidget {
  const SheetsPage({super.key});
  @override
  State<SheetsPage> createState() => _SheetsPageState();
}

class _SheetsPageState extends State<SheetsPage> {
  final _cloudField = TextEditingController(text: _cloud);
  final _keyField = TextEditingController(text: _key);
  List<Map<String, dynamic>> _docs = [];
  String _status = 'Enter the cloud and a Sigma key, then load your sheets.';

  @override
  void initState() {
    super.initState();
    if (_key.isNotEmpty) _load();
  }

  Future<void> _load() async {
    setState(() => _status = 'Loading…');
    try {
      final body = await _api(_cloudField.text, _keyField.text, 'documents');
      setState(() {
        _docs = (body['documents'] as List).cast<Map<String, dynamic>>();
        _status = '${_docs.length} sheets on ${_cloudField.text}';
      });
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sigma sheets')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _cloudField, decoration: const InputDecoration(labelText: 'Nimbus Cloud')),
          TextField(controller: _keyField, decoration: const InputDecoration(labelText: 'Sigma key (sgm_test_…)')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Load sheets')),
          const SizedBox(height: 12),
          Text(_status, style: Theme.of(context).textTheme.bodySmall),
          for (final d in _docs)
            ListTile(
              title: Text('${d['title']}'),
              subtitle: Text('${d['filename']} · #${d['id']}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SheetPage(cloud: _cloudField.text, apiKey: _keyField.text, id: d['id'] as int, title: '${d['title']}'),
              )),
            ),
        ]),
      );
}

class SheetPage extends StatefulWidget {
  const SheetPage({super.key, required this.cloud, required this.apiKey, required this.id, required this.title});
  final String cloud;
  final String apiKey;
  final int id;
  final String title;
  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  // In a real app: ask your server, which mints the link with its key.
  Future<String> _link() async =>
      (await _api(widget.cloud, widget.apiKey, 'documents/${widget.id}/link?mode=edit', method: 'POST'))['url'] as String;

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  // The editor's own header has the back arrow, title, save state and sharing.
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: SigmaSheet(
            link: _link,
            onError: (e) => _say('${e.code.name}: ${e.message}'),
          ),
        ),
      );
}
