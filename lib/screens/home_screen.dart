import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/connection.dart';
import '../services/bus.dart';
import '../services/flash.dart';
import '../services/sensors.dart';
import '../services/tts.dart';

/// Connected screen: status header + sensor toggles + manual flash/tts test
/// + disconnect.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.bus,
    required this.sensors,
    required this.flash,
    required this.tts,
    required this.onDisconnect,
  });

  final Bus bus;
  final SensorsService sensors;
  final FlashService flash;
  final TtsService tts;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('brAIn mobile'),
        actions: [
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: onDisconnect,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([bus, sensors, flash]),
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(bus: bus),
            const SizedBox(height: 16),
            const _SectionTitle('Sensors → bus'),
            _SensorTile(
              title: 'Accelerometer',
              subtitle: 'mobile.<id>.sensor.accel · 10 Hz',
              value: sensors.accelEnabled,
              onChanged: sensors.toggleAccel,
            ),
            _SensorTile(
              title: 'Gyroscope',
              subtitle: 'mobile.<id>.sensor.gyro · 10 Hz',
              value: sensors.gyroEnabled,
              onChanged: sensors.toggleGyro,
            ),
            _SensorTile(
              title: 'Magnetometer',
              subtitle: 'mobile.<id>.sensor.magnetometer · 5 Hz',
              value: sensors.magEnabled,
              onChanged: sensors.toggleMag,
            ),
            _SensorTile(
              title: 'Light (Android only)',
              subtitle: 'mobile.<id>.sensor.light · event-driven',
              value: sensors.lightEnabled,
              onChanged: sensors.toggleLight,
            ),
            _SensorTile(
              title: 'Battery',
              subtitle: 'mobile.<id>.sensor.battery · 30 s',
              value: sensors.batteryEnabled,
              onChanged: sensors.toggleBattery,
            ),
            const SizedBox(height: 16),
            const _SectionTitle('Remote control'),
            ListTile(
              leading: Icon(flash.isOn ? Icons.flashlight_on : Icons.flashlight_off),
              title: const Text('Flash'),
              subtitle: const Text('Subscribed to mobile.<id>.flash'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => flash.toggle(),
                    child: Text(flash.isOn ? 'turn off' : 'turn on'),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('TTS'),
              subtitle: const Text('Subscribed to mobile.<id>.tts.speak'),
              trailing: TextButton(
                onPressed: () async {
                  await FlutterTts().speak('Hello from your brAIn mobile node.');
                },
                child: const Text('test'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.bus});
  final Bus bus;

  @override
  Widget build(BuildContext context) {
    final info = bus.info;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bus.isConnected ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus.isConnected ? 'Connected' : bus.state.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (info != null)
                    Text(
                      info.url,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    'device: ${bus.deviceId.substring(0, 8)}…',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 11, letterSpacing: 0.06, color: Colors.grey, fontWeight: FontWeight.w600),
    ),
  );
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: onChanged,
    );
  }
}

// Avoid unused import warnings when ConnectionInfo isn't directly referenced.
// ignore: unused_element
ConnectionInfo? _unused;
