import 'package:flutter_test/flutter_test.dart';

import 'package:brain_mobile/models/connection.dart';

void main() {
  group('ConnectionInfo.tryParse', () {
    test('parses brain://join with url + token', () {
      final info = ConnectionInfo.tryParse(
        'brain://join?url=nats%3A%2F%2F192.168.1.10%3A4222&token=abc',
      );
      expect(info, isNotNull);
      expect(info!.url, 'nats://192.168.1.10:4222');
      expect(info.token, 'abc');
    });

    test('accepts a bare nats:// URL', () {
      final info = ConnectionInfo.tryParse('nats://10.0.0.5:4222');
      expect(info, isNotNull);
      expect(info!.url, 'nats://10.0.0.5:4222');
      expect(info.token, isNull);
    });

    test('returns null for garbage', () {
      expect(ConnectionInfo.tryParse('hello world'), isNull);
      expect(ConnectionInfo.tryParse(''), isNull);
    });

    test('toJoinUri round-trips', () {
      const info = ConnectionInfo(url: 'nats://1.2.3.4:4222', token: 'xyz');
      final round = ConnectionInfo.tryParse(info.toJoinUri());
      expect(round!.url, info.url);
      expect(round.token, info.token);
    });
  });
}
