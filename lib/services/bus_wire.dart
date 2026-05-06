import 'dart:convert';

/// Pure helpers that build the on-the-wire NATS payloads expected by
/// `@brain/core`'s `NatsBusService`. Kept separate from [Bus] so they
/// can be unit-tested without spinning up a broker or a dart_nats
/// client — the wire shape is the part that's most likely to drift
/// silently and break the dashboard's view of the device.
///
/// Wire format (must match `packages/core/src/bus/nats-bus.service.ts`):
///   subject = `<natsPrefix>.<sanitize(logical_topic)>`
///   body    = JSON({origin, message: brAIn-Message})
///   message.payload.content = JSON-encoded user payload
///
/// The dashboard's `AgentDirectory` reads `msg.payload.content` to
/// populate the Distributed pane, so a missing prefix OR a missing
/// `{origin, message}` wrapper makes the device invisible.

const String natsPrefix = 'brain';
const String agentAnnounceTopic = 'brain.agents.discover';

String sanitizeTopic(String topic) {
  return topic.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

String natsSubject(String logicalTopic) {
  return '$natsPrefix.${sanitizeTopic(logicalTopic)}';
}

/// Builds the on-wire body for a publish on [topic] originating from
/// [from]. [payload] is the user-supplied data; it lives in both
/// `message.payload.content` (string-encoded for legacy parsers) and
/// `message.metadata` (typed access).
Map<String, dynamic> buildWireBody({
  required String origin,
  required String from,
  required String topic,
  required Map<String, dynamic> payload,
  int criticality = 1,
  int? timestampMs,
  String? messageIdSuffix,
}) {
  final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final suffix = messageIdSuffix ?? topic;
  final message = <String, dynamic>{
    'id': '${DateTime.now().microsecondsSinceEpoch}-$suffix',
    'from': from,
    'topic': topic,
    'type': 'text',
    'criticality': criticality,
    'payload': {'content': jsonEncode(payload)},
    'metadata': payload,
    'timestamp': ts,
  };
  return <String, dynamic>{'origin': origin, 'message': message};
}

/// Builds the AgentAnnouncement payload + the wire body that wraps it.
Map<String, dynamic> buildAnnouncementWire({
  required String origin,
  required String deviceId,
  required String hostLabel,
  required int connectedAtMs,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final ann = <String, dynamic>{
    'agent_id': deviceId,
    'host': hostLabel,
    'pid': 0,
    'started_at': connectedAtMs,
    'types': <String>[],
    'ts': now,
  };
  return buildWireBody(
    origin: origin,
    from: 'agent:$deviceId',
    topic: agentAnnounceTopic,
    payload: ann,
    criticality: 0,
    timestampMs: now,
    messageIdSuffix: 'announce',
  );
}

/// Strips the `{origin, message}` wrapper from an inbound NATS body and
/// returns the inner `Message` as a JSON string — the shape existing
/// service callers (flash, tts) decode with their own `_decode`.
///
/// Returns null if the body isn't recognisable, so callers can ignore
/// silently rather than crash on noise.
String? unwrapInboundMessage(String raw) {
  if (raw.isEmpty) return null;
  try {
    final wire = jsonDecode(raw);
    if (wire is Map<String, dynamic> && wire['message'] != null) {
      return jsonEncode(wire['message']);
    }
    // Some publishers (legacy / tests) might send a bare Message — let
    // it through unchanged so existing decoders still see something.
    if (wire is Map<String, dynamic> && wire['payload'] != null) {
      return raw;
    }
  } catch (_) { /* not JSON */ }
  return null;
}
