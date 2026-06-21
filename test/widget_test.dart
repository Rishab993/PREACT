import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preact_app/core/bootstrap/preact_bootstrap.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PreactBootstrap());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
