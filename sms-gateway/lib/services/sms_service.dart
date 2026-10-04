import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

import 'api_service.dart';
import 'background_service.dart';
import 'queue_service.dart';
import 'reply_dispatcher.dart';

/// SMS permission was refused. [permanent] means Android will not ask again, or
/// blocks the request outright (Android 15+ restricts SMS access for apps installed
/// from an APK), so the operator has to allow it in the app's settings.
class SmsPermissionDenied implements Exception {
  const SmsPermissionDenied({required this.permanent});

  final bool permanent;

  @override
  String toString() => 'SMS permission was not granted';
}

class SmsService {
  SmsService({
    QueueService? queueService,
    ApiClient? apiClient,
    Telephony? telephony,
  }) : _queueService = queueService ?? QueueService.instance,
       _apiClient = apiClient ?? ApiClient(),
       _telephony = telephony ?? Telephony.instance;

  final QueueService _queueService;
  final ApiClient _apiClient;
  final Telephony _telephony;
  final ReplyDispatcher _replyDispatcher = ReplyDispatcher();

  /// A permission dialog the user never answers, or a result another plugin
  /// swallows, must not leave the gateway half-started forever.
  static const Duration _promptTimeout = Duration(seconds: 90);

  /// Asks for SMS access through permission_handler, which owns its request and
  /// reports the real status. The telephony plugin's own request can lose its
  /// result and report a granted permission as refused.
  Future<PermissionStatus> requestSmsPermission() async {
    var status = await Permission.sms.status;
    if (status.isGranted) return status;
    try {
      status = await Permission.sms.request().timeout(_promptTimeout);
    } catch (e) {
      debugPrint('SMS permission request failed: $e');
    }
    return status;
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return (await requestSmsPermission()).isGranted;
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) {
        return true;
      }
      final requested = await Permission.ignoreBatteryOptimizations
          .request()
          .timeout(_promptTimeout);
      return requested.isGranted;
    } catch (e) {
      debugPrint('Battery optimization request failed: $e');
      return false;
    }
  }

  /// This SIM's own number, or null. Carriers often do not store it on the SIM,
  /// in which case the operator enters it on the dashboard.
  Future<String?> simNumber() async {
    if (!Platform.isAndroid) return null;
    try {
      final number = (await _telephony.line1Number)?.trim() ?? '';
      return number.isEmpty ? null : number;
    } catch (_) {
      return null;
    }
  }

  /// The SIM's operator name, for example "MTN Rwanda", or null.
  Future<String?> simOperatorName() async {
    if (!Platform.isAndroid) return null;
    try {
      final name = (await _telephony.simOperatorName)?.trim() ?? '';
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// Starts receiving and answering SMS.
  ///
  /// Throws when SMS permission is refused, since nothing works without it. The
  /// battery exemption and the background service are best effort; the returned
  /// warnings name the ones that failed, so the operator can see them.
  Future<List<String>> startListening({
    required Function(String sender, String message) onMessageReceived,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('The SMS gateway runs on Android only.');
    }

    final sms = await requestSmsPermission();
    if (!sms.isGranted) {
      throw SmsPermissionDenied(
        permanent: sms.isPermanentlyDenied || sms.isRestricted,
      );
    }

    final warnings = <String>[];
    if (!await requestBatteryOptimizationExemption()) {
      warnings.add(
        'battery optimization is on, so Android may pause the gateway',
      );
    }
    if (!await startBackgroundService()) {
      warnings.add(
        'the background service did not start, so SMS are answered '
        'only while the app is open',
      );
    }

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
    return warnings;
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
