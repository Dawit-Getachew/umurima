import 'package:flutter_test/flutter_test.dart';

import 'package:umurima/main.dart';

void main() {
  testWidgets('Dashboard shows the gateway, backend and test controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(live: false));

    expect(find.text('Umurima AI Gateway'), findsOneWidget);
    expect(find.text('Gateway stopped'), findsOneWidget);
    expect(find.text('Start gateway'), findsOneWidget);
    expect(find.text("Set this phone's number"), findsOneWidget);
    expect(find.text('Checking AI backend...'), findsOneWidget);
    expect(find.text('Test a question'), findsOneWidget);
    expect(find.text('No farmer messages yet'), findsOneWidget);
  });

  testWidgets('Test question dialog offers example questions', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(live: false));

    await tester.tap(find.text('Test a question'));
    await tester.pumpAndSettle();

    expect(find.text('Test a farmer question'), findsOneWidget);
    expect(find.text('When should I plant maize?'), findsOneWidget);
  });
}
