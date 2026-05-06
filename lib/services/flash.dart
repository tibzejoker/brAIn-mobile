import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:torch_light/torch_light.dart';

import 'bus.dart';

/// Subscribes to `<prefix>.flash` and toggles the device torch.
///
/// Payload shape (envelope `metadata` or JSON-encoded `payload.content`):
///   { "on": true }            – turn on
///   { "on": false }           – turn off
///   { "blink": 200, "n": 5 }  – blink n times, period ms
class FlashService extends ChangeNotifier {
  FlashService(this.bus);

  final Bus bus;
  StreamSubscription<dynamic>? _sub;
  bool _on = false;

  bool get isOn => _on;

  void start() {
    final s = bus.subscribeControl('flash');
    if (s == null) return;
    _sub = s.listen(_onMessage);
  }

  Future<void> _onMessage(String raw) async {
    final body = _decode(raw);
    if (body == null) return;

    if (body['on'] is bool) {
      await set(body['on'] as bool);
      return;
    }
    if (body['blink'] is num) {
      final period = (body['blink'] as num).toInt();
      final n = (body['n'] is num) ? (body['n'] as num).toInt() : 3;
      await _blink(period, n);
    }
  }

  /// Public — used by both the bus control handler and the in-app
  /// "turn on / turn off" button. Single source of truth so [_on] and
  /// the physical torch state stay aligned and listeners notify on
  /// every change (the manual button used to bypass this and the UI
  /// label was stuck).
  Future<void> set(bool on) async {
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      _on = on;
      notifyListeners();
      bus.publish('flash.status', {'on': on});
    } catch (e) {
      bus.publish('flash.status', {'error': e.toString()});
    }
  }

  Future<void> toggle() => set(!_on);

  Future<void> _blink(int periodMs, int n) async {
    for (var i = 0; i < n; i++) {
      await set(true);
      await Future<void>.delayed(Duration(milliseconds: periodMs));
      await set(false);
      await Future<void>.delayed(Duration(milliseconds: periodMs));
    }
  }

  Map<String, dynamic>? _decode(String payload) {
    try {
      if (payload.isEmpty) return null;
      final outer = jsonDecode(payload);
      if (outer is! Map<String, dynamic>) return null;
      // Prefer `metadata` (typed) over re-parsing `payload.content`.
      final meta = outer['metadata'];
      if (meta is Map<String, dynamic>) return meta;
      final content = outer['payload']?['content'];
      if (content is String) {
        final inner = jsonDecode(content);
        if (inner is Map<String, dynamic>) return inner;
      }
    } catch (_) { /* malformed — ignore */ }
    return null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (_on) {
      try { await TorchLight.disableTorch(); } catch (_) { /* ignore */ }
      _on = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
