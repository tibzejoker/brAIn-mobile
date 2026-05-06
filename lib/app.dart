import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/connection.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'services/bus.dart';
import 'services/device_id.dart';
import 'services/flash.dart';
import 'services/sensors.dart';
import 'services/tts.dart';

/// Top-level app: owns the [Bus] and the three subscribers (sensors,
/// flash, tts). Boots into the connect flow if no broker is wired up,
/// otherwise jumps straight to [HomeScreen].
class BrainMobileApp extends StatefulWidget {
  const BrainMobileApp({super.key});

  @override
  State<BrainMobileApp> createState() => _BrainMobileAppState();
}

class _BrainMobileAppState extends State<BrainMobileApp> {
  static const _prefLastUrl = 'brain.last_url';

  Bus? _bus;
  SensorsService? _sensors;
  FlashService? _flash;
  TtsService? _tts;
  String? _deviceId;
  String? _lastUrl;
  String? _connectError;
  bool _booting = true;
  // Global key so we can show snackbars from outside any widget that
  // sits below MaterialApp — the State.context above MaterialApp can't
  // reach ScaffoldMessenger.of() directly.
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final id = await DeviceId.get();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceId = id;
      _lastUrl = prefs.getString(_prefLastUrl);
      _booting = false;
    });
  }

  Future<void> _connect(ConnectionInfo info) async {
    final id = _deviceId;
    if (id == null) return;
    final bus = Bus(deviceId: id);
    final sensors = SensorsService(bus);
    final flash = FlashService(bus);
    final tts = TtsService(bus);

    try {
      await bus.connect(info);
    } catch (e, st) {
      // Surface to logs (Xcode console / `flutter logs`) and on-screen.
      debugPrint('connect failed: $e\n$st');
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Connect failed: $e'), duration: const Duration(seconds: 6)),
      );
      setState(() => _connectError = '$e');
      bus.dispose();
      return;
    }

    flash.start();
    await tts.start();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastUrl, info.url);

    if (!mounted) return;
    setState(() {
      _bus = bus;
      _sensors = sensors;
      _flash = flash;
      _tts = tts;
      _lastUrl = info.url;
    });
  }

  Future<void> _disconnect() async {
    _sensors?.dispose();
    await _flash?.stop();
    await _tts?.stop();
    await _bus?.disconnect();
    _bus?.dispose();
    if (!mounted) return;
    setState(() {
      _bus = null;
      _sensors = null;
      _flash = null;
      _tts = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'brAIn mobile',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: _booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_bus == null
              ? _ConnectFlow(lastUrl: _lastUrl, lastError: _connectError, onConnect: _connect)
              : HomeScreen(
                  bus: _bus!, sensors: _sensors!, flash: _flash!, tts: _tts!,
                  onDisconnect: _disconnect,
                )),
    );
  }
}

class _ConnectFlow extends StatelessWidget {
  const _ConnectFlow({required this.lastUrl, required this.lastError, required this.onConnect});
  final String? lastUrl;
  final String? lastError;
  final Future<void> Function(ConnectionInfo info) onConnect;

  Future<void> _open(BuildContext context) async {
    final info = await Navigator.of(context).push<ConnectionInfo>(
      MaterialPageRoute(builder: (_) => ConnectScreen(lastUrl: lastUrl)),
    );
    if (info != null) await onConnect(info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('brAIn mobile')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub, size: 64),
              const SizedBox(height: 16),
              const Text('Not connected to a broker', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan or paste join'),
                onPressed: () => _open(context),
              ),
              if (lastError != null) ...[
                const SizedBox(height: 24),
                SelectableText(
                  'Last error:\n$lastError',
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
