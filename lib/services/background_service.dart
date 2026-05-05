import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'zone_monitor_service.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: 'slinter_channel',
      initialNotificationTitle: 'Slinter Running',
      initialNotificationContent: 'Monitoring silent zones',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  if (!(await service.isRunning())) {
    await service.startService();
  }
}

Future<void> stopBackgroundService() async {
  final service = FlutterBackgroundService();

  if (await service.isRunning()) {
    service.invoke('stopService');
  }
}

bool _isMonitoringStarted = false;

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('silentZonesBox');

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  if (!_isMonitoringStarted) {
    _isMonitoringStarted = true;

    final zoneService = ZoneMonitorService(service: service);
    await zoneService.startMonitoring();

    service.on('stopService').listen((event) {
      zoneService.stopMonitoring();
      service.stopSelf();
    });
  }
}
