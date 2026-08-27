import 'package:flutter_test/flutter_test.dart';

import 'package:stoox_employee_app/main.dart';

void main() {
  testWidgets('App starts', (tester) async {
    await tester.pumpWidget(const StooxEmployeeApp());
    await tester.pump();
    expect(find.byType(StooxEmployeeApp), findsOneWidget);
  });
}
