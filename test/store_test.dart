import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:badminton_ai_coach/store.dart';
import 'package:badminton_ai_coach/pose_analysis.dart';
import 'pose_fixture.dart';

void main() {
  late CoachStore store;
  late Directory dir;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('coach-test-');
    store = await CoachStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.db',
    );
    await store.saveStudent({
      'id': 's',
      'name': '小羽',
      'age': 8,
      'hand': '左手',
      'experience': 1,
      'notes': '',
      'created': now(),
    });
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> assessment({String? video}) => store.saveAssessment(
    studentId: 's',
    videoId: video,
    ratings: List.filled(7, 0),
    issues: ['balance'],
    notes: '落地多踏一步',
    drillIds: ['balance'],
  );
  test('data and consent survive close and reopen', () async {
    await store.consent();
    await assessment();
    await store.close();
    store = await CoachStore.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.db',
    );
    expect(await store.consented(), isTrue);
    expect((await store.students()).single['hand'], '左手');
    expect((await store.assessments('s')).single['notes'], '落地多踏一步');
    expect(await store.plans(studentId: 's'), hasLength(1));
  });
  test('invalid assessments do not leave partial plans', () async {
    await expectLater(
      store.saveAssessment(
        studentId: 'missing',
        ratings: List.filled(7, 0),
        issues: ['balance'],
        notes: '',
        drillIds: ['balance'],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.plans(), isEmpty);
    await expectLater(
      store.saveAssessment(
        studentId: 's',
        ratings: [0],
        issues: [],
        notes: '',
        drillIds: [],
      ),
      throwsArgumentError,
    );
    expect(await store.assessments('s'), isEmpty);
  });
  test('practice validates plan membership and duplicates', () async {
    await assessment();
    final id = (await store.plans()).single['id'] as String;
    await expectLater(
      store.logPractice(id, ['grip'], 3, ''),
      throwsArgumentError,
    );
    await expectLater(
      store.logPractice(id, ['balance', 'balance'], 3, ''),
      throwsArgumentError,
    );
    await expectLater(
      store.logPractice(id, ['balance'], 6, ''),
      throwsArgumentError,
    );
    await store.logPractice(id, ['balance'], 4, '站得穩咗');
    expect(await store.practices(id), hasLength(1));
  });
  test('video deletion removes copies but keeps coaching history', () async {
    final video = File('${dir.path}/clip.mp4');
    await video.writeAsBytes([1]);
    final image = File('${dir.path}/mark.png');
    await image.writeAsBytes([2]);
    await store.addVideo({
      'id': 'v',
      'student_id': 's',
      'title': '測試',
      'path': video.path,
      'duration_ms': 1000,
      'created': now(),
    });
    await store.addSnapshot({
      'id': 'i',
      'video_id': 'v',
      'path': image.path,
      'position_ms': 0,
      'frame_index': 0,
      'strokes': '[]',
      'created': now(),
    });
    await assessment(video: 'v');
    await store.deleteVideo('v');
    expect(await video.exists(), isFalse);
    expect(await image.exists(), isFalse);
    expect(await store.snapshots('v'), isEmpty);
    expect((await store.assessments('s')).single['video_id'], isNull);
    expect(await store.plans(), hasLength(1));
  });
  test('student cascade removes assessment, plan and practice', () async {
    await assessment();
    final id = (await store.plans()).single['id'] as String;
    await store.logPractice(id, ['balance'], 3, '');
    await store.deleteStudent('s');
    expect(await store.students(), isEmpty);
    expect(await store.assessments('s'), isEmpty);
    expect(await store.plans(), isEmpty);
    expect(await store.practices(id), isEmpty);
  });
  test('AI report persists, plan creation is idempotent, deletion clears body data', () async {
    final video=File('${dir.path}/pose.mp4'); await video.writeAsBytes([1]);
    await store.addVideo({'id':'pose-v','student_id':'s','title':'分析測試',
      'path':video.path,'duration_ms':5125,'created':now()});
    final report=analyzePoses(poseFixture(),hand:'右手');
    final row=await store.savePoseReport('pose-v',report);
    final id=await store.createPosePlan(row['id'] as String);
    expect(await store.createPosePlan(row['id'] as String),id);
    expect(await store.plans(),hasLength(1));
    await store.close();
    store=await CoachStore.open(factory:databaseFactoryFfi,path:'${dir.path}/test.db');
    expect((await store.latestPoseReport('pose-v'))!['plan_id'],id);
    await store.deleteVideo('pose-v');
    expect(await store.latestPoseReport('pose-v'),isNull);
    expect(await store.plans(),hasLength(1));
  });
  test('poor-quality analysis cannot create a targeted training plan', () async {
    await store.addVideo({'id':'pose-v','student_id':'s','title':'分析測試',
      'path':'${dir.path}/none.mp4','duration_ms':1000,'created':now()});
    final row=await store.savePoseReport('pose-v',analyzePoses(poseFixture(occluded:true),hand:'右手'));
    await expectLater(store.createPosePlan(row['id'] as String),throwsStateError);
    expect(await store.plans(),isEmpty);
  });
  test('version 1 database migration preserves students and coaching history', () async {
    final oldPath='${dir.path}/old.db';
    final old=await databaseFactoryFfi.openDatabase(oldPath,options:OpenDatabaseOptions(version:1,
      onCreate:(db,version) async {
        for(final sql in CoachStore.schema.where((sql)=>!CoachStore.poseSchema.contains(sql))) {await db.execute(sql);}
        await db.insert('students',{'id':'old','name':'原有學員','age':10,'hand':'左手','experience':2,'notes':'保留','created':now()});
      }));
    await old.close();
    final upgraded=await CoachStore.open(factory:databaseFactoryFfi,path:oldPath);
    expect((await upgraded.students()).single['notes'],'保留');
    expect(await upgraded.latestPoseReport('missing'),isNull);
    expect(await upgraded.db.getVersion(),2);
    await upgraded.close();
  });

}
