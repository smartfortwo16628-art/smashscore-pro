import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:badminton_ai_coach/store.dart';

void main() {
  late CoachStore store;
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir=await Directory.systemTemp.createTemp('coach-test-');
    store=await CoachStore.open(factory:databaseFactoryFfi,path:'${dir.path}/test.db');
    await store.saveStudent({'id':'s','name':'小羽','age':8,'hand':'左手','experience':1,'notes':'','created':now()});
  });
  tearDown(() async {await store.close();await dir.delete(recursive:true);});
  Future<void> assessment({String? video})=>store.saveAssessment(studentId:'s',videoId:video,ratings:List.filled(7,0),issues:['balance'],notes:'落地多踏一步',drillIds:['balance']);
  test('data and consent survive close and reopen', () async {
    await store.consent();
    await assessment();
    await store.close();
    store=await CoachStore.open(factory:databaseFactoryFfi,path:'${dir.path}/test.db');
    expect(await store.consented(),isTrue);
    expect((await store.students()).single['hand'],'左手');
    expect((await store.assessments('s')).single['notes'],'落地多踏一步');
    expect(await store.plans(studentId:'s'),hasLength(1));
  });
  test('invalid assessments do not leave partial plans', () async {
    await expectLater(store.saveAssessment(studentId:'missing',ratings:List.filled(7,0),issues:['balance'],notes:'',drillIds:['balance']),throwsA(isA<DatabaseException>()));
    expect(await store.plans(),isEmpty);
    await expectLater(store.saveAssessment(studentId:'s',ratings:[0],issues:[],notes:'',drillIds:[]),throwsArgumentError);
    expect(await store.assessments('s'),isEmpty);
  });
  test('practice validates plan membership and duplicates', () async {
    await assessment();final id=(await store.plans()).single['id'] as String;
    await expectLater(store.logPractice(id,['grip'],3,''),throwsArgumentError);
    await expectLater(store.logPractice(id,['balance','balance'],3,''),throwsArgumentError);
    await expectLater(store.logPractice(id,['balance'],6,''),throwsArgumentError);
    await store.logPractice(id,['balance'],4,'站得穩咗');
    expect(await store.practices(id),hasLength(1));
  });
  test('video deletion removes copies but keeps coaching history', () async {
    final video=File('${dir.path}/clip.mp4');await video.writeAsBytes([1]);
    final image=File('${dir.path}/mark.png');await image.writeAsBytes([2]);
    await store.addVideo({'id':'v','student_id':'s','title':'測試','path':video.path,'duration_ms':1000,'created':now()});
    await store.addSnapshot({'id':'i','video_id':'v','path':image.path,'position_ms':0,'frame_index':0,'strokes':'[]','created':now()});
    await assessment(video:'v');await store.deleteVideo('v');
    expect(await video.exists(),isFalse);expect(await image.exists(),isFalse);
    expect(await store.snapshots('v'),isEmpty);
    expect((await store.assessments('s')).single['video_id'],isNull);
    expect(await store.plans(),hasLength(1));
  });
  test('student cascade removes assessment, plan and practice', () async {
    await assessment();final id=(await store.plans()).single['id'] as String;
    await store.logPractice(id,['balance'],3,'');await store.deleteStudent('s');
    expect(await store.students(),isEmpty);expect(await store.assessments('s'),isEmpty);
    expect(await store.plans(),isEmpty);expect(await store.practices(id),isEmpty);
  });
}
