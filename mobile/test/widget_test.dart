import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mutual_watch/app_state.dart';
import 'package:mutual_watch/main.dart';

void main() {
  testWidgets('Auth screen smoke test', (WidgetTester tester) async {
    final state = AppState()..loading = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    expect(find.text('Mutual Watch'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byIcon(Icons.login_rounded), findsOneWidget);
  });
}
