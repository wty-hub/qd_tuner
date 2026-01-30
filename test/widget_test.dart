import 'package:flutter_test/flutter_test.dart';
import 'package:qd_tuner/main.dart';

void main() {
  testWidgets('Tuner smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const QdTunerApp());

    // Verify that the title is present.
    expect(find.text('GUITAR TUNER'), findsOneWidget);
    
    // Verify default note E is shown.
    expect(find.text('E'), findsWidgets);
  });
}
