import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';
import 'queue_service.dart';
import 'package:flutter/foundation.dart';
import 'outgoing_sender.dart';
import 'reply_dispatcher.dart';

class SyncService {
  SyncService({
    QueueService? queueService,
    ApiClient? apiClient,
    Connectivity? connectivity,
  })  : _queueService = queueService ?? QueueService.instance,
        _apiClient = apiClient ?? ApiClient(),
        _connectivity = connectivity ?? Connectivity();

  final QueueService _queueService;
  final ApiClient _apiClient;
  final Connectivity _connectivity;
  final OutgoingSender _outgoingSender = OutgoingSender();
  final ReplyDispatcher _replyDispatcher = ReplyDispatcher();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _pollingTimer;

  void start() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      final hasNetwork = results.any((result) => result != ConnectivityResult.none);
      if (hasNetwork) {
        await flushPendingIncoming();
        await _pollOnceForOutgoing();
      }
    });
    // start periodic polling for outgoing tasks every 15 seconds by default
    _startPollingOutgoing(const Duration(seconds: 15));
  }

  void _startPollingOutgoing(Duration interval) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) async {
      try {
        await _pollOnceForOutgoing();
      } catch (e) {
        if (kDebugMode) debugPrint('Outgoing polling error: $e');
      }
    });
  }

  Future<void> _pollOnceForOutgoing() async {
    // device id should be provided via environment or config; use a placeholder
    const deviceId = String.fromEnvironment('DEVICE_ID', defaultValue: 'device-unknown');

    final result = await _apiClient.fetchOutgoing(deviceId);
    if (!result.success || result.data == null) {
      return;
    }

    final data = result.data;
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final taskId = item['task_id']?.toString() ?? '';
          final to = item['to']?.toString() ?? '';
          final message = item['message']?.toString() ?? '';

          if (taskId.isEmpty || to.isEmpty) continue;

          final payload = Map<String, dynamic>.from(item);

          // persist outgoing task
          await _queueService.saveOutgoingTask(
            recipient: to,
            body: message,
            status: 'pending',
            payload: payload,
          );
        }
      }

      // attempt to send any pending outgoing tasks
      await processPendingOutgoing();
    }
  }

  Future<void> flushPendingIncoming() async {
    // Reclaim anything a crashed isolate left mid-upload.
    await _queueService.recoverStalledUploads();

    final pending = await _queueService.getPendingIncomingMessages();
    if (pending.isEmpty) {
      return;
    }

    for (final item in pending) {
      final payload = item['payload'];
      final id = item['id'] as int?;

      if (payload is! String || id == null) {
        continue;
      }

      final Map<String, dynamic> decoded = _decodeJson(payload);
      final sender = (item['sender'] ?? decoded['sender'] ?? '').toString();

      await _queueService.markIncomingUploading(id);
      final result = await _apiClient.uploadIncoming(decoded);

      if (!result.success) {
        await _queueService.markIncomingPending(
          id,
          'Upload failed (${result.statusCode}): ${result.message}',
        );
        continue;
      }

      await _queueService.markIncomingUploaded(id);

      // This retry path used to stop here, throwing away a reply the backend
      // had already generated (and billed for).
      await _replyDispatcher.dispatch(
        savedId: id,
        data: result.data,
        originalSender: sender,
      );
    }
  }

  Future<void> flushPendingOutgoing() async {
    final pending = await _queueService.getPendingOutgoingTasks();
    if (pending.isEmpty) {
      return;
    }

    for (final item in pending) {
      final payload = item['payload'];
      final id = item['id'] as int?;

        if (payload is String && id != null) {
        final Map<String, dynamic> decoded = _decodeJson(payload);
        final result = await _apiClient.uploadOutgoing(decoded);

        if (result.success) {
          await _queueService.markOutgoingTaskCompleted(id);
        }
      }
    }
  }

  Future<void> processPendingOutgoing() async {
    final pending = await _queueService.getPendingOutgoingTasks();
    if (pending.isEmpty) return;

    for (final item in pending) {
      final payload = item['payload'];
      final id = item['id'] as int?;

      if (payload is String && id != null) {
        final Map<String, dynamic> decoded = _decodeJson(payload);
        final taskId = decoded['task_id']?.toString();
        final to = decoded['to']?.toString();
        final message = decoded['message']?.toString();

        if (to == null || message == null) continue;

        try {
          await _outgoingSender.sendSms(to: to, message: message);

          // mark completed locally
          await _queueService.markOutgoingTaskCompleted(id);

          // ack backend
          if (taskId != null && taskId.isNotEmpty) {
            final ack = {
              'task_id': taskId,
              'status': 'sent',
              'sent_at': DateTime.now().toUtc().toIso8601String(),
              'failure_reason': null,
            };
            await _apiClient.ackOutgoing(taskId, ack);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to send outgoing SMS to $to: $e');
          // leave pending for retry
          if (taskId != null && taskId.isNotEmpty) {
            final ack = {
              'task_id': taskId,
              'status': 'failed',
              'sent_at': DateTime.now().toUtc().toIso8601String(),
              'failure_reason': e.toString(),
            };
            await _apiClient.ackOutgoing(taskId, ack);
          }
        }
      }
    }
  }

  Map<String, dynamic> _decodeJson(String payload) {
    try {
      return Map<String, dynamic>.from(
        const JsonDecoder().convert(payload) as Map,
      );
    } catch (_) {
      return {'raw': payload};
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}
