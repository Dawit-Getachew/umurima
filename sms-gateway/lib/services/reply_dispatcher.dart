import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'outgoing_sender.dart';
import 'queue_service.dart';

/// A reply the backend asked us to deliver over SMS.
class SmsReply {
  const SmsReply({required this.to, required this.message, this.source});

  final String to;
  final String message;

  /// How the backend produced the answer (faq, cache, ai, triage, offline), shown
  /// on the dashboard. Never sent to the farmer.
  final String? source;
}

/// Turns a backend response into an outgoing SMS and records the outcome.
///
/// Every ingest path — foreground, background isolate and the retry sweep —
/// goes through here, so the reply handling cannot drift between them.
class ReplyDispatcher {
  ReplyDispatcher({
    QueueService? queueService,
    OutgoingSender? outgoingSender,
  })  : _queueService = queueService ?? QueueService.instance,
        _outgoingSender = outgoingSender ?? OutgoingSender();

  final QueueService _queueService;
  final OutgoingSender _outgoingSender;

  static const List<String> _messageKeys = <String>[
    'message',
    'body',
    'text',
    'content',
    'answer',
    'response',
    'reply',
  ];

  static const List<String> _recipientKeys = <String>[
    'phone_number',
    'to',
    'recipient',
    'msisdn',
    'sender',
    'address',
  ];

  /// Extracts the reply from [data], or null when the backend sent none.
  ///
  /// [fallbackTo] is the number the original SMS came from. It is used whenever
  /// the backend omits the recipient — which is common, since it is answering
  /// the number it was just called with.
  static SmsReply? parse(dynamic data, {required String fallbackTo}) {
    dynamic decoded = data;

    // Dio only decodes JSON when the response carries a JSON content type.
    // A text/plain body arrives here as a String.
    if (decoded is String) {
      final raw = decoded.trim();
      if (raw.isEmpty) {
        return null;
      }
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        // Not JSON — the body itself is the reply.
        return SmsReply(to: fallbackTo, message: raw);
      }
    }

    if (decoded is! Map) {
      return null;
    }

    final dynamic nested =
        decoded['reply'] ?? decoded['data'] ?? decoded['result'];
    final Map source = nested is Map ? nested : decoded;

    final message = _firstNonEmpty(source, _messageKeys);
    if (message == null) {
      return null;
    }

    final to = _firstNonEmpty(source, _recipientKeys) ??
        _firstNonEmpty(decoded, _recipientKeys) ??
        fallbackTo;
    if (to.isEmpty) {
      return null;
    }

    final answeredBy = _sourceOf(source) ?? _sourceOf(decoded);
    return SmsReply(to: to, message: message, source: answeredBy);
  }

  static String? _sourceOf(Map map) {
    final dynamic value = map['source'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static String? _firstNonEmpty(Map source, List<String> keys) {
    for (final key in keys) {
      final dynamic value = source[key];
      if (value == null || value is Map || value is List) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  /// Delivers the backend reply for incoming message [savedId] and records the
  /// outcome on that row. Returns true when the SMS was handed to the radio.
  Future<bool> dispatch({
    required int savedId,
    required dynamic data,
    required String originalSender,
  }) async {
    final reply = parse(data, fallbackTo: originalSender);

    if (reply == null) {
      debugPrint('ReplyDispatcher: no reply in backend response: $data');
      await _queueService.markIncomingFailed(
        savedId,
        'Backend response contained no reply text',
      );
      return false;
    }

    try {
      await _outgoingSender.sendSms(to: reply.to, message: reply.message);
    } catch (e) {
      debugPrint('ReplyDispatcher: send failed for #$savedId: $e');
      await _queueService.markIncomingFailed(savedId, 'Send failed: $e');
      return false;
    }

    await _queueService.addReplyToIncoming(
      savedId,
      <String, dynamic>{
        'phone_number': reply.to,
        'message': reply.message,
        if (reply.source != null) 'source': reply.source,
      },
    );
    await _queueService.markIncomingReplied(savedId);
    return true;
  }
}
