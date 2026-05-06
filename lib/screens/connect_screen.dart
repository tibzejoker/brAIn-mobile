import 'package:flutter/material.dart';

import '../models/connection.dart';
import 'scanner_screen.dart';

/// Pre-connection screen: scan a QR or paste a `brain://` / `nats://` URL.
/// Returns a [ConnectionInfo] on success.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.lastUrl});

  /// Pre-fill of the manual-entry field from the last successful join.
  final String? lastUrl;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _urlCtl;
  late final TextEditingController _tokenCtl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlCtl = TextEditingController(text: widget.lastUrl ?? 'nats://192.168.1.10:4222');
    _tokenCtl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final info = await Navigator.of(context).push<ConnectionInfo>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (info != null && mounted) {
      Navigator.of(context).pop(info);
    }
  }

  void _submitManual() {
    final url = _urlCtl.text.trim();
    final token = _tokenCtl.text.trim();
    final info = ConnectionInfo.tryParse(url);
    if (info == null) {
      setState(() => _error = 'URL not recognised — expected nats:// or brain://join?...');
      return;
    }
    Navigator.of(context).pop(ConnectionInfo(
      url: info.url,
      token: token.isEmpty ? info.token : token,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a brAIn')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Open the dashboard → Distributed pane to grab a QR or copy the join URL.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR'),
            onPressed: _scan,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Or paste manually', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtl,
            decoration: const InputDecoration(
              labelText: 'NATS URL',
              hintText: 'nats://192.168.1.10:4222',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtl,
            decoration: const InputDecoration(
              labelText: 'Token (optional)',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitManual,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
