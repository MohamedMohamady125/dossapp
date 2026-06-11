import 'package:flutter_test/flutter_test.dart';
import 'package:bism_academy/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BismApp());
    expect(find.text('BISM Academy'), findsOneWidget);
  });
}
