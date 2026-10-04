import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:umurima/services/queue_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await QueueService.instance.close();
  });

  tearDown(() async {
    await QueueService.instance.close();
  });

  test('QueueService persists and updates pending incoming SMS', () async {
    final id = await QueueService.instance.saveIncomingMessage(
      sender: '+15551234567',
      body: 'hello from queue test',
      status: 'pending_upload',
      payload: {
        'sender': '+15551234567',
        'body': 'hello from queue test',
        'direction': 'incoming',
        'received_at': '2026-01-01T00:00:00.000Z',
      },
    );

    final pendingBefore = await QueueService.instance.getPendingIncomingMessages();
    expect(id, greaterThan(0));
    expect(pendingBefore, isNotEmpty);
    expect(pendingBefore.first['sender'], '+15551234567');

    final updatedRows = await QueueService.instance.markIncomingUploaded(id);
    expect(updatedRows, 1);

    final pendingAfter = await QueueService.instance.getPendingIncomingMessages();
    expect(pendingAfter, isEmpty);
  });
}
