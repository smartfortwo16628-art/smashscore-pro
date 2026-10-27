import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_ai_coach/screens.dart';

void main() {
  testWidgets('consent requires an explicit checkbox before starting', (tester) async {
    var accepted=false;
    await tester.pumpWidget(MaterialApp(home:ConsentScreen(onAccept:() async {accepted=true;})));
    await tester.ensureVisible(find.text('開始使用'));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await tester.tap(find.byType(Checkbox));await tester.pump();
    await tester.tap(find.text('開始使用'));await tester.pump();
    expect(accepted,isTrue);
  });
  testWidgets('student form rejects an empty nickname', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:StudentForm()));
    await tester.ensureVisible(find.text('儲存學員'));await tester.tap(find.text('儲存學員'));
    await tester.pump();expect(find.text('請填寫暱稱'),findsOneWidget);
  });
}
