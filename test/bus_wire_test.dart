import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:brain_mobile/services/bus_wire.dart';

void main() {
  group('natsSubject + sanitizeTopic', () {
    test('prepends the framework prefix', () {
      expect(natsSubject('mobile.abc.flash'), 'brain.mobile.abc.flash');
    });

    test('replaces NATS-illegal characters with underscores', () {
      expect(sanitizeTopic('mobile.abc.flash with spaces'), 'mobile.abc.flash_with_spaces');
      expect(sanitizeTopic('chat.response.*'), 'chat.response._');
      expect(natsSubject('a b'), 'brain.a_b');
    });

    test('passes alnum / dot / dash / underscore through', () {
      expect(sanitizeTopic('a.b-c_d.e'), 'a.b-c_d.e');
    });
  });

  group('buildWireBody', () {
    test('matches the {origin, message} shape consumeRemote expects', () {
      final body = buildWireBody(
        origin: 'origin-1',
        from: 'mobile.dev-1',
        topic: 'mobile.dev-1.sensor.accel',
        payload: {'x': 1, 'y': 2, 'z': 3},
        criticality: 1,
        timestampMs: 1700000000000,
      );

      expect(body['origin'], 'origin-1');
      final m = body['message'] as Map<String, dynamic>;
      expect(m['from'], 'mobile.dev-1');
      expect(m['topic'], 'mobile.dev-1.sensor.accel');
      expect(m['type'], 'text');
      expect(m['criticality'], 1);
      expect(m['timestamp'], 1700000000000);
    });

    test('payload is JSON-encoded under message.payload.content AND duplicated under metadata', () {
      final body = buildWireBody(
        origin: 'o',
        from: 'f',
        topic: 't',
        payload: {'k': 'v'},
      );
      final m = body['message'] as Map<String, dynamic>;
      final payload = m['payload'] as Map<String, dynamic>;
      // content is the legacy stringly-typed channel — must be JSON of payload
      expect(payload['content'], isA<String>());
      expect(jsonDecode(payload['content'] as String), {'k': 'v'});
      // metadata is the typed mirror handlers actually read
      expect(m['metadata'], {'k': 'v'});
    });

    test('default criticality is 1', () {
      final body = buildWireBody(
        origin: 'o', from: 'f', topic: 't', payload: const {},
      );
      expect((body['message'] as Map)['criticality'], 1);
    });
  });

  group('buildAnnouncementWire', () {
    test('targets brain.agents.discover with the AgentAnnouncement shape', () {
      final body = buildAnnouncementWire(
        origin: 'o',
        deviceId: 'dev-aaaa1111-2222-3333-4444-555566667777',
        hostLabel: 'iOS mobile · dev-aaaa',
        connectedAtMs: 1700000000000,
        nowMs: 1700000005000,
      );

      final m = body['message'] as Map<String, dynamic>;
      expect(m['topic'], 'brain.agents.discover');
      expect(m['from'], startsWith('agent:'));

      final ann = m['metadata'] as Map<String, dynamic>;
      expect(ann['agent_id'], 'dev-aaaa1111-2222-3333-4444-555566667777');
      expect(ann['host'], 'iOS mobile · dev-aaaa');
      expect(ann['pid'], 0);
      expect(ann['started_at'], 1700000000000);
      expect(ann['ts'], 1700000005000);
      expect(ann['types'], <String>[]);
    });

    test('content matches metadata after JSON round-trip (AgentDirectory parses content)', () {
      final body = buildAnnouncementWire(
        origin: 'o', deviceId: 'd', hostLabel: 'h',
        connectedAtMs: 1, nowMs: 2,
      );
      final m = body['message'] as Map<String, dynamic>;
      final payload = m['payload'] as Map<String, dynamic>;
      final fromContent = jsonDecode(payload['content'] as String);
      expect(fromContent, m['metadata']);
    });
  });

  group('unwrapInboundMessage', () {
    test('strips the {origin, message} wrapper', () {
      final wire = jsonEncode({
        'origin': 'someone-else',
        'message': {
          'topic': 'mobile.x.flash',
          'payload': {'content': '{"on":true}'},
          'metadata': {'on': true},
        },
      });
      final out = unwrapInboundMessage(wire);
      expect(out, isNotNull);
      final inner = jsonDecode(out!) as Map<String, dynamic>;
      expect(inner['topic'], 'mobile.x.flash');
      expect(inner['metadata'], {'on': true});
    });

    test('passes a bare Message through unchanged (legacy producers)', () {
      final bare = jsonEncode({
        'topic': 't', 'payload': {'content': '{}'}, 'metadata': {},
      });
      expect(unwrapInboundMessage(bare), bare);
    });

    test('returns null for empty / malformed input', () {
      expect(unwrapInboundMessage(''), isNull);
      expect(unwrapInboundMessage('not json'), isNull);
      expect(unwrapInboundMessage('"just a string"'), isNull);
    });
  });
}
