import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' as nats;
import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import 'bus_wire.dart';

/// Bus connection state. The app driver listens on this to swap UIs.
enum BusState { idle, connecting, connected, error }

/// Thin wrapper around dart_nats that:
/// - Builds bus topic names from the device id (`mobile.<id>.<channel>`).
/// - Wraps every published payload in the brAIn message envelope so the
///   API + handlers see it like any other bus message.
/// - Surfaces a [ChangeNotifier] state so widgets can react to connect /
///   disconnect / error transitions without manual stream wiring.
class Bus extends ChangeNotifier {
  Bus({required this.deviceId});

  final String deviceId;

  // Wire-level constants live in [bus_wire.dart] so they can be
  // unit-tested without spinning up the broker.
  static const _agentAnnounceIntervalMs = 10000;

  nats.Client? _client;
  ConnectionInfo? _info;
  BusState _state = BusState.idle;
  String? _lastError;
  Timer? _announceTimer;
  int _connectedAt = 0;
  // Random per-connection origin id — must NOT match the API's own
  // origin (any non-colliding string works; UUID-ish is safest).
  late final String _originId = '${DateTime.now().microsecondsSinceEpoch}-${deviceId.substring(0, 8)}';

  BusState get state => _state;
  String? get lastError => _lastError;
  ConnectionInfo? get info => _info;
  bool get isConnected => _state == BusState.connected && _client != null;

  /// `mobile.<deviceId>` — the prefix every topic this device touches sits
  /// under. Keeping it stable lets the API spawn one virtual node per
  /// connected phone without coordinating ids ahead of time.
  String get prefix => 'mobile.$deviceId';

  Future<void> connect(ConnectionInfo info) async {
    await disconnect();
    _info = info;
    _setState(BusState.connecting);

    try {
      final client = nats.Client();
      final raw = Uri.parse(info.url);
      // dart_nats 0.6.x signs Uri instead of host+port — synthesize a
      // canonical one with default port 4222 if the input omitted it.
      final uri = raw.replace(port: raw.hasPort ? raw.port : 4222);
      await client.connect(
        uri,
        retry: false,
        connectOption: nats.ConnectOption(
          authToken: info.token,
          name: 'brain-mobile-$deviceId',
          verbose: false,
        ),
      );
      _client = client;
      _connectedAt = DateTime.now().millisecondsSinceEpoch;
      _setState(BusState.connected);
      // Announce ourselves once so listeners on `mobile.<id>.hello` see
      // we're up immediately (cheap connection ack).
      publish('hello', {
        'device_id': deviceId,
        'platform': defaultTargetPlatform.name,
        'ts': DateTime.now().toIso8601String(),
      });
      // Then surface as a "remote node" in the dashboard's Distributed
      // pane — same protocol brain-agent uses on desktop. Without this
      // the phone is invisible to AgentDirectory and the pane never
      // shows it as connected.
      _announce();
      _announceTimer = Timer.periodic(
        const Duration(milliseconds: _agentAnnounceIntervalMs),
        (_) => _announce(),
      );
    } catch (e) {
      _lastError = e.toString();
      _setState(BusState.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _connectedAt = 0;
    final c = _client;
    if (c != null) {
      try { await c.close(); } catch (_) { /* best-effort */ }
    }
    _client = null;
    _info = null;
    if (_state != BusState.idle) _setState(BusState.idle);
  }

  /// Publish a JSON payload on `<prefix>.<channel>`.
  void publish(String channel, Map<String, dynamic> payload, {int criticality = 1}) {
    final c = _client;
    if (c == null) return;
    final topic = '$prefix.$channel';
    final wireBody = buildWireBody(
      origin: _originId,
      from: 'mobile.$deviceId',
      topic: topic,
      payload: payload,
      criticality: criticality,
      messageIdSuffix: channel,
    );
    c.pubString(natsSubject(topic), jsonEncode(wireBody));
  }

  /// Periodic "I'm here" beacon on `brain.agents.discover` so the
  /// AgentDirectory in @brain/core sees the phone and the dashboard's
  /// Distributed pane lists it next to brain-agent peers.
  ///
  /// `agent_id` reuses [deviceId] so reconnects refresh the same row.
  /// `host` is the platform name + a short id suffix — Dashboard shows
  /// it as the friendly label. `types` is empty: the phone hosts no
  /// brAIn node types in the type-registry sense, it just publishes /
  /// subscribes raw topics.
  ///
  /// AgentDirectory parses `msg.payload.content`, so we MUST send the
  /// brAIn envelope shape — a raw JSON body would be silently ignored.
  void _announce() {
    final c = _client;
    if (c == null) return;
    final platform = defaultTargetPlatform.name;
    final shortId = deviceId.substring(0, 8);
    final wireBody = buildAnnouncementWire(
      origin: _originId,
      deviceId: deviceId,
      hostLabel: '$platform mobile · $shortId',
      connectedAtMs: _connectedAt,
    );
    c.pubString(natsSubject(agentAnnounceTopic), jsonEncode(wireBody));
  }

  /// Subscribe to a control channel under our prefix.
  ///
  /// Listens on the NATS-prefixed subject (`brain.mobile.<id>.<channel>`)
  /// and unwraps the framework's `{origin, message}` envelope, yielding
  /// just the inner brAIn `Message` as a JSON string — what existing
  /// callers (flash, tts) already expect via `_decode`.
  Stream<String>? subscribeControl(String channel) {
    final c = _client;
    if (c == null) return null;
    final sub = c.sub<dynamic>(natsSubject('$prefix.$channel'));
    return sub.stream
        .map((m) => m.string)
        .map(unwrapInboundMessage)
        .where((s) => s != null)
        .cast<String>();
  }

  void _setState(BusState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
