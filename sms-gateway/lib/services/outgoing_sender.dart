import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

class OutgoingSender {
  OutgoingSender({Telephony? telephony})
    : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  String _normalizePhoneNumber(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    return cleaned.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  /// Checks, never requests: this also runs in background isolates, where there is
  /// no activity to show a dialog and the plugin's own request never completes.
  Future<bool> requestSendPermissions() async {
    return (await Permission.sms.status).isGranted;
  }

  Future<void> sendSms({
    required String to,
    required String message,
    void Function(SendStatus status)? onStatus,
  }) async {
    final normalizedTo = _normalizePhoneNumber(to);
    if (normalizedTo.isEmpty) {
      throw StateError('Recipient number is empty (raw: "$to")');
    }
    if (message.isEmpty) {
      throw StateError('Message body is empty');
    }

    final granted = await requestSendPermissions();
    if (!granted) {
      throw StateError('SEND_SMS permission is not granted');
    }

    // Always send multipart.
    //
    // `sendTextMessage` carries a single segment only: 160 characters with the
    // GSM-7 alphabet, but just 70 once the body needs UCS-2 — which any
    // accented letter, curly apostrophe or emoji forces. Anything longer is
    // dropped by the framework, and since we pass no PendingIntent there is no
    // error to observe. `divideMessage` returns a single part for short bodies,
    // so routing everything through multipart is correct at every length.
    await _telephony.sendSms(
      to: normalizedTo,
      message: message,
      isMultipart: true,
      statusListener: onStatus == null ? null : (status) => onStatus(status),
    );

    debugPrint('OutgoingSender: sent ${message.length} chars to $normalizedTo');
  }

  Future<void> sendByDefaultApp({
    required String to,
    required String message,
  }) async {
    await _telephony.sendSmsByDefaultApp(
      to: _normalizePhoneNumber(to),
      message: message,
    );
  }
}
