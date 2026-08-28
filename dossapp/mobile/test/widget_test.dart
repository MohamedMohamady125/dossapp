import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_athletic/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AquathleticApp());
    expect(find.text('Aquathletic'), findsOneWidget);
  });
}
