import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:light_sensor/light_sensor.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'bus.dart';

/// Coalesces samples from a stream into one publish per [interval] so a
/// 200 Hz sensor doesn't flood the bus. We keep only the latest sample —
/// motion data is essentially a "current value", losing intermediate ones
/// is fine for the typical brAIn use case (gesture / orientation hints).
class _Throttle<T> {
  _Throttle(this.interval, this.onEmit);

  final Duration interval;
  final void Function(T sample) onEmit;
  T? _last;
  Timer? _timer;
  StreamSubscription<T>? _sub;

  void start(Stream<T> source) {
    stop();
    _sub = source.listen((s) { _last = s; });
    _timer = Timer.periodic(interval, (_) {
      final s = _last;
      if (s != null) onEmit(s);
    });
  }

  void stop() {
    _timer?.cancel(); _timer = null;
    _sub?.cancel(); _sub = null;
    _last = null;
  }
}

/// Drives every "outgoing" sensor stream the app exposes. Each toggle is
/// independent so the user can keep accelerometer running but pause the
/// magnetometer if it's not relevant.
class SensorsService extends ChangeNotifier {
  SensorsService(this.bus);

  final Bus bus;

  // 100ms = 10Hz — what the user asked for and a reasonable default for
  // motion features without burning the radio.
  static const _accelInterval = Duration(milliseconds: 100);
  static const _gyroInterval = Duration(milliseconds: 100);
  static const _magInterval = Duration(milliseconds: 200);
  static const _batteryInterval = Duration(seconds: 30);

  bool accelEnabled = false;
  bool gyroEnabled = false;
  bool magEnabled = false;
  bool lightEnabled = false;
  bool batteryEnabled = false;

  _Throttle<AccelerometerEvent>? _accelTh;
  _Throttle<GyroscopeEvent>? _gyroTh;
  _Throttle<MagnetometerEvent>? _magTh;
  StreamSubscription<int>? _lightSub;
  Timer? _batteryTimer;

  void toggleAccel(bool on) {
    accelEnabled = on;
    if (on) {
      _accelTh = _Throttle<AccelerometerEvent>(_accelInterval, (e) {
        bus.publish('sensor.accel', {
          'x': e.x, 'y': e.y, 'z': e.z,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      })..start(accelerometerEventStream());
    } else {
      _accelTh?.stop(); _accelTh = null;
    }
    notifyListeners();
  }

  void toggleGyro(bool on) {
    gyroEnabled = on;
    if (on) {
      _gyroTh = _Throttle<GyroscopeEvent>(_gyroInterval, (e) {
        bus.publish('sensor.gyro', {
          'x': e.x, 'y': e.y, 'z': e.z,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      })..start(gyroscopeEventStream());
    } else {
      _gyroTh?.stop(); _gyroTh = null;
    }
    notifyListeners();
  }

  void toggleMag(bool on) {
    magEnabled = on;
    if (on) {
      _magTh = _Throttle<MagnetometerEvent>(_magInterval, (e) {
        bus.publish('sensor.magnetometer', {
          'x': e.x, 'y': e.y, 'z': e.z,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      })..start(magnetometerEventStream());
    } else {
      _magTh?.stop(); _magTh = null;
    }
    notifyListeners();
  }

  Future<void> toggleLight(bool on) async {
    lightEnabled = on;
    if (on) {
      // light_sensor only exposes Android. iOS returns no stream — bail
      // gracefully so the toggle stays "off" rather than spinning.
      final has = await LightSensor.hasSensor();
      if (!has) {
        lightEnabled = false;
        notifyListeners();
        return;
      }
      _lightSub = LightSensor.luxStream().listen((lux) {
        bus.publish('sensor.light', {
          'lux': lux,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      });
      // light_sensor is event-driven, no need for a throttle Timer — it
      // already only fires on change. Cap is "naturally throttled".
    } else {
      _lightSub?.cancel(); _lightSub = null;
    }
    notifyListeners();
  }

  Future<void> toggleBattery(bool on) async {
    batteryEnabled = on;
    if (on) {
      final battery = Battery();
      Future<void> tick() async {
        final level = await battery.batteryLevel;
        final state = await battery.batteryState;
        bus.publish('sensor.battery', {
          'level': level,
          'state': state.name,
          't': DateTime.now().millisecondsSinceEpoch,
        });
      }
      await tick();
      _batteryTimer = Timer.periodic(_batteryInterval, (_) => tick());
    } else {
      _batteryTimer?.cancel(); _batteryTimer = null;
    }
    notifyListeners();
  }

  void stopAll() {
    if (accelEnabled) toggleAccel(false);
    if (gyroEnabled) toggleGyro(false);
    if (magEnabled) toggleMag(false);
    if (lightEnabled) toggleLight(false);
    if (batteryEnabled) toggleBattery(false);
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
