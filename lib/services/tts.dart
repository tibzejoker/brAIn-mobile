import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'bus.dart';

/// Subscribes to `<prefix>.tts.speak` and reads the text aloud through
/// the device's native TTS engine.
///
/// Payload shape (envelope.metadata or payload.content as JSON):
///   { "text": "Bonjour", "voice": "fr-FR" }
///   { "text": "Hello", "rate": 0.5, "pitch": 1.0 }
///
/// `voice` accepts either a BCP-47 locale ("fr-FR") or a specific voice
/// name returned by `flutter_tts.getVoices`. Locales are simpler — leave
/// the user free to override with a name when they care.
class TtsService extends ChangeNotifier {
  TtsService(this.bus);

  final Bus bus;
  final FlutterTts _tts = FlutterTts();
  StreamSubscription<dynamic>? _sub;

  Future<void> start() async {
    _tts.setStartHandler(() => bus.publish('tts.status', {'state': 'speaking'}));
    _tts.setCompletionHandler(() => bus.publish('tts.status', {'state': 'spoken'}));
    _tts.setErrorHandler((msg) => bus.publish('tts.status', {'state': 'error', 'error': '$msg'}));

    final s = bus.subscribeControl('tts.speak');
    if (s == null) return;
    _sub = s.listen(_onMessage);

    // Publish the device's voice catalog so the brain (or chat node) can
    // pick one without round-tripping through the user.
    try {
      final voices = await _tts.getVoices;
      bus.publish('tts.voices', {'voices': voices ?? []}, criticality: 1);
    } catch (_) { /* getVoices flakes on some Android OEMs — non-fatal */ }
  }

  Future<void> _onMessage(String raw) async {
    final body = _decode(raw);
    if (body == null) return;
    final text = body['text'];
    if (text is! String || text.isEmpty) return;

    final voice = body['voice'];
    if (voice is String && voice.isNotEmpty) {
      // BCP-47 vs voice name: detect via the dash + length heuristic.
      // "fr-FR", "en-US" → setLanguage. "Audrey (Enhanced)" → setVoice.
      if (RegExp(r'^[a-z]{2,3}([-_][A-Za-z0-9]+)?$').hasMatch(voice)) {
        await _tts.setLanguage(voice.replaceAll('_', '-'));
      } else {
        await _tts.setVoice({'name': voice, 'locale': ''});
      }
    }
    if (body['rate'] is num) await _tts.setSpeechRate((body['rate'] as num).toDouble());
    if (body['pitch'] is num) await _tts.setPitch((body['pitch'] as num).toDouble());
    if (body['volume'] is num) await _tts.setVolume((body['volume'] as num).toDouble());

    await _tts.speak(text);
  }

  Map<String, dynamic>? _decode(String payload) {
    try {
      if (payload.isEmpty) return null;
      final outer = jsonDecode(payload);
      if (outer is! Map<String, dynamic>) return null;
      final meta = outer['metadata'];
      if (meta is Map<String, dynamic>) return meta;
      final content = outer['payload']?['content'];
      if (content is String) {
        final inner = jsonDecode(content);
        if (inner is Map<String, dynamic>) return inner;
        // Plain string in `content` → treat as raw text.
        return {'text': content};
      }
    } catch (_) { /* malformed */ }
    return null;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try { await _tts.stop(); } catch (_) { /* ignore */ }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
