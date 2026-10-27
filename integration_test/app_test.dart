import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:badminton_ai_coach/main.dart';
import 'package:badminton_ai_coach/store.dart';
import 'package:badminton_ai_coach/video.dart';
import 'fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android: local database, native indexed decoding, and coaching UI', (tester) async {
    final directory=await MediaBridge.directory();
    final clip=File('$directory/integration-fixture.mp4');await clip.writeAsBytes(base64Decode(fixtureBase64));
    final info=await MediaBridge.info(clip.path);
    expect(info['precise'],isTrue);expect(info['times'],List.generate(10,(i)=>i*100));
    final first=await MediaBridge.frame(clip.path,index:0);
    final second=await MediaBridge.frame(clip.path,index:1);
    expect(first['index'],0);expect(second['position'],100);expect(second['width'],160);
    expect(base64Encode(first['bytes']),isNot(base64Encode(second['bytes'])));
    await expectLater(MediaBridge.frame(clip.path,index:10),throwsA(anything));
    final dbPath='$directory/integration.db';
    var store=await CoachStore.open(path:dbPath);
    final sid=newId();
    await store.saveStudent({'id':sid,'name':'測試小羽','age':9,'hand':'右手','experience':1,'notes':'','created':now()});
    await store.saveAssessment(studentId:sid,ratings:List.filled(7,0),issues:['balance'],notes:'測試',drillIds:['balance']);
    final plan=(await store.plans(studentId:sid)).single;
    await store.logPractice(plan['id'] as String,['balance'],4,'改善');
    await store.close();store=await CoachStore.open(path:dbPath);
    expect((await store.practices(plan['id'] as String)).single['notes'],'改善');
    await tester.pumpWidget(CoachApp(store:store,consented:true));await tester.pumpAndSettle();
    expect(find.text('今日，練好一個細節。'),findsOneWidget);
    await tester.tap(find.byIcon(Icons.people_outline));await tester.pumpAndSettle();
    await tester.tap(find.text('測試小羽'));await tester.pumpAndSettle();
    expect(find.text('新增高遠球評估'),findsOneWidget);
    await store.deleteStudent(sid);
    await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
    await store.close();await clip.delete();
  });
}
