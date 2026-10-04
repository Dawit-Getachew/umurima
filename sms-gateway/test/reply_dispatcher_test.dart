import 'package:flutter_test/flutter_test.dart';

import 'package:umurima/services/reply_dispatcher.dart';

void main() {
  test('an urgent reply is parsed into SMS parts, in order', () {
    final reply = ReplyDispatcher.parse({
      'phone_number': '+250788000000',
      'message': '(1/2) Keep her in the shade. (2/2) Call the vet today.',
      'messages': ['(1/2) Keep her in the shade.', '(2/2) Call the vet today.'],
      'source': 'triage',
    }, fallbackTo: '+250700000000');

    expect(reply!.parts, ['(1/2) Keep her in the shade.', '(2/2) Call the vet today.']);
    expect(reply.source, 'triage');
    expect(reply.to, '+250788000000');
  });

  test('a single-message reply has no parts and falls back to the sender', () {
    final reply = ReplyDispatcher.parse(
      {'message': 'Plant in September.', 'messages': ['Plant in September.']},
      fallbackTo: '+250700000000',
    );

    expect(reply!.parts, isEmpty);
    expect(reply.message, 'Plant in September.');
    expect(reply.to, '+250700000000');
  });
}
