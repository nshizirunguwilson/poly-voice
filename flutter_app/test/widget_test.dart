import 'package:flutter_test/flutter_test.dart';
import 'package:polyvoice/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PolyVoiceApp());
    // Verify the splash screen appears
    expect(find.text('PolyVoice'), findsOneWidget);
  });
}
