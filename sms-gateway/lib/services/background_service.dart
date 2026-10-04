import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sync_service.dart';

final FlutterBackgroundService _service = FlutterBackgroundService();

Future<void> initializeBackgroundService() async {
  await _service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      isForegroundMode: true,
      autoStart: false,
      // Deliberately no `notificationChannelId`.
      //
      // The plugin only creates the notification channel when this is null
      // (BackgroundService.java:89-95); naming a channel makes it assume the
      // app already created that channel. Naming 'umurima_channel' without
      // creating it produced an invalid notification, so `startForeground`
      // threw CannotPostForegroundServiceNotificationException and Android
      // killed the process. Letting the plugin own the channel avoids
      // depending on flutter_local_notifications just to register one.
      initialNotificationTitle: 'Umurima service',
      initialNotificationContent: 'Listening for SMS',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
  );
}

Future<bool> startBackgroundService() async {
  try {
    final alreadyRunning = await _service.isRunning();
    if (alreadyRunning) {
      return true;
    }

    // Android 13+ needs this granted before the foreground-service notification
    // can be posted. Not fatal if refused, so don't block startup on it.
    final status = await Permission.notification.request();
    if (!status.isGranted) {
      debugPrint(
        'Notification permission not granted; the foreground service '
        'notification may be suppressed.',
      );
    }

    await initializeBackgroundService();
    await _service.startService();
    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('Failed to start background service: $e');
    return false;
  }
}

Future<bool> isBackgroundServiceRunning() async {
  try {
    return await _service.isRunning();
  } catch (_) {
    return false;
  }
}

Future<bool> stopBackgroundService() async {
  try {
    if (await _service.isRunning()) {
      // The plugin exposes control via `invoke`. Request service stop.
      _service.invoke('stopService');
      return true;
    }
    return false;
  } catch (e) {
    if (kDebugMode) debugPrint('Failed to stop background service: $e');
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  final sync = SyncService();
  sync.start();

  Timer.periodic(const Duration(seconds: 15), (timer) async {
    try {
      await sync.flushPendingIncoming();
      await sync.processPendingOutgoing();
    } catch (e) {
      if (kDebugMode) debugPrint('Background sync error: $e');
    }
  });

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }
}

@pragma('vm:entry-point')
bool _onIosBackground(ServiceInstance service) {
  return true;
}
