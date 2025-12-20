import 'package:flutter_test/flutter_test.dart';

import 'package:weview/main.dart';

void main() {
  testWidgets(
    'App renders title',
    (WidgetTester tester) async {
      await tester.pumpWidget(const WeViewApp());
      expect(find.text('WeView'), findsOneWidget);
    },
    skip: true, // WebView relies on platform views; run on a device/emulator.
  );
}
