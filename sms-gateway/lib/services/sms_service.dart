import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

import 'api_service.dart';
import 'background_service.dart';
import 'queue_service.dart';
import 'reply_dispatcher.dart';

class SmsService {
  SmsService({
    QueueService? queueService,
    ApiClient? apiClient,
    Telephony? telephony,
  })  : _queueService = queueService ?? QueueService.instance,
        _apiClient = apiClient ?? ApiClient(),
        _telephony = telephony ?? Telephony.instance;

  final QueueService _queueService;
  final ApiClient _apiClient;
  final Telephony _telephony;
  final ReplyDispatcher _replyDispatcher = ReplyDispatcher();

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final permissionsGranted = await _telephony.requestSmsPermissions;
    return permissionsGranted ?? false;
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) {
      return true;
    }

    final requested = await Permission.ignoreBatteryOptimizations.request();
    return requested.isGranted;
  }

  Future<void> startListening({
    required Function(String sender, String message) onMessageReceived,
  }) async {
    if (!Platform.isAndroid) {
      debugPrint('SMS listener requested on a non-Android platform; skipping.');
      return;
    }

    final hasPermission = await requestPermissions();

    if (!hasPermission) {
      debugPrint('SMS permission was not granted.');
      return;
    }

    final batteryExempt = await requestBatteryOptimizationExemption();
    if (!batteryExempt) {
      debugPrint(
        'Battery optimization exemption was not granted; background SMS delivery may be unreliable on Android 8+.',
      );
    }

    await startBackgroundService();

    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        final String sender = message.address ?? '';
        final String body = message.body ?? '';

        debugPrint('SMS RECEIVED');
        debugPrint('Sender: $sender');
        debugPrint('Message: $body');

        unawaited(_persistIncomingMessage(sender, body));
        onMessageReceived(sender, body);
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }

  /// Stops background delivery.
  ///
  /// This writes a *persistent* flag on the Android side: until
  /// [startListening] runs again, `IncomingSmsReceiver` drops every SMS that
  /// arrives while the app is not in the foreground, across app restarts. Only
  /// call it when the operator explicitly asks to stop the gateway.
  void stopListening() {
    if (!Platform.isAndroid) {
      return;
    }

    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage _) {},
      listenInBackground: false,
    );
  }

  /// Deliberately does not call [stopListening]: tearing down the UI must not
  /// disable the gateway, which is the whole point of running in background.
  void dispose() {}

  Future<void> _persistIncomingMessage(String sender, String body) async {
    await ingestIncomingMessage(
      sender: sender,
      body: body,
      queueService: _queueService,
      apiClient: _apiClient,
      replyDispatcher: _replyDispatcher,
    );
  }
}

/// Stores an incoming SMS, forwards it to the backend and delivers the reply.
///
/// Shared by the foreground listener and the background isolate so both behave
/// identically — the two used to carry separate copies of this logic.
Future<void> ingestIncomingMessage({
  required String sender,
  required String body,
  required QueueService queueService,
  required ApiClient apiClient,
  required ReplyDispatcher replyDispatcher,
}) async {
  final payload = <String, dynamic>{
    'sender': sender,
    'body': body,
    'direction': 'incoming',
    'received_at': DateTime.now().toUtc().toIso8601String(),
  };

  final savedId = await queueService.saveIncomingMessage(
    sender: sender,
    body: body,
    status: 'pending_upload',
    payload: payload,
  );

  // Claim the row before the network call so the retry sweep cannot upload the
  // same message a second time while this request is in flight.
  await queueService.markIncomingUploading(savedId);

  final result = await apiClient.uploadIncoming(payload);

  if (!result.success) {
    debugPrint(
      'ingestIncomingMessage: upload failed '
      'status=${result.statusCode} message=${result.message}',
    );
    // Back to pending so the sweep retries it.
    await queueService.markIncomingPending(
      savedId,
      'Upload failed (${result.statusCode}): ${result.message}',
    );
    return;
  }

  await queueService.markIncomingUploaded(savedId);
  await replyDispatcher.dispatch(
    savedId: savedId,
    data: result.data,
    originalSender: sender,
  );
}

// Keep this as a top-level function so the Telephony plugin can invoke it when
// the app is no longer in the foreground. The `vm:entry-point` pragma is
// required: without it the AOT compiler drops the function from the callback
// table, `PluginUtilities.getCallbackHandle` returns null, and registering the
// listener throws in release builds even though debug builds work fine.
//
// Note this path also runs whenever the screen is locked, because the plugin
// treats a locked keyguard as "not foreground" even with the app on screen.
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) {
  final String sender = message.address ?? '';
  final String body = message.body ?? '';

  debugPrint('BACKGROUND SMS RECEIVED from $sender');

  unawaited(_saveBackgroundIncomingMessage(sender, body));
}

Future<void> _saveBackgroundIncomingMessage(String sender, String body) async {
  try {
    await ingestIncomingMessage(
      sender: sender,
      body: body,
      queueService: QueueService.instance,
      apiClient: ApiClient(),
      replyDispatcher: ReplyDispatcher(),
    );
  } catch (e, st) {
    // Nothing above us is awaiting this future, so swallowing here is the only
    // way the stack trace reaches the log at all.
    debugPrint('Background ingest failed for $sender: $e');
    debugPrint(st.toString());
  }
}