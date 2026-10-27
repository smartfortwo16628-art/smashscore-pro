import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:badminton_ai_coach/main.dart';
import 'package:badminton_ai_coach/store.dart';
import 'package:badminton_ai_coach/video.dart';
import 'fixture.dart';
import 'pose_clip.dart';
import 'package:badminton_ai_coach/pose_screen.dart';
import 'package:badminton_ai_coach/pose_analysis.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: local database, native indexed decoding, and coaching UI',
    (tester) async {
      final directory = await MediaBridge.directory();
      final clip = File('$directory/integration-fixture.mp4');
      await clip.writeAsBytes(base64Decode(fixtureBase64));
      debugPrint('CHECK: native frame timeline');
      final info = await MediaBridge.info(clip.path);
      expect(info['precise'], isTrue);
      expect(info['times'], List.generate(10, (i) => i * 100));
      final first = await MediaBridge.frame(clip.path, index: 0);
      final second = await MediaBridge.frame(clip.path, index: 1);
      expect(first['index'], 0);
      expect(second['position'], 100);
      expect(second['width'], 160);
      expect(
        base64Encode(first['bytes']),
        isNot(base64Encode(second['bytes'])),
      );
      await expectLater(
        MediaBridge.frame(clip.path, index: 10),
        throwsA(anything),
      );
      debugPrint('CHECK: database persistence');
      final dbPath = '$directory/integration.db';
      var store = await CoachStore.open(path: dbPath);
      final sid = newId();
      await store.saveStudent({
        'id': sid,
        'name': '測試小羽',
        'age': 9,
        'hand': '右手',
        'experience': 1,
        'notes': '',
        'created': now(),
      });
      await store.addVideo({
        'id': 'fixture-video',
        'student_id': sid,
        'title': '合成測試影片',
        'path': clip.path,
        'duration_ms': 1000,
        'created': now(),
      });
      await store.saveAssessment(
        studentId: sid,
        ratings: List.filled(7, 0),
        issues: ['balance'],
        notes: '測試',
        drillIds: ['balance'],
      );
      final plan = (await store.plans(studentId: sid)).single;
      await store.logPractice(plan['id'] as String, ['balance'], 4, '改善');
      await store.close();
      store = await CoachStore.open(path: dbPath);
      expect(
        (await store.practices(plan['id'] as String)).single['notes'],
        '改善',
      );
      debugPrint('CHECK: coaching navigation');
      await tester.pumpWidget(CoachApp(store: store, consented: true));
      await tester.pumpAndSettle();
      expect(find.text('今日，練好一個細節。'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.people_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('測試小羽'));
      await tester.pumpAndSettle();
      expect(find.text('新增高遠球評估'), findsOneWidget);
      debugPrint('CHECK: playback and annotation');
      await tester.tap(find.text('影片及標記'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('合成測試影片'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('逐格／截圖及畫線'));
      await tester.tap(find.text('逐格／截圖及畫線'));
      await tester.pumpAndSettle();
      final canvas = find.byKey(const Key('annotation-canvas'));
      expect(canvas, findsOneWidget);
      await tester.drag(canvas, const Offset(30, 20));
      await tester.pump();
      await tester.ensureVisible(find.text('儲存截圖及標記'));
      await tester.tap(find.text('儲存截圖及標記'));
      // GPU readback and disk I/O can finish after the last scheduled UI frame.
      // Wait for the actual completion signal, not only animation settlement.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('已儲存標記截圖').evaluate().isNotEmpty ||
            find.textContaining('儲存未完成：').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(
        find.textContaining('儲存未完成：'),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join('\n'),
      );
      expect(find.text('已儲存標記截圖'), findsOneWidget);
      final snapshots = await store.snapshots('fixture-video');
      expect(snapshots, hasLength(1));
      final savedImage = File(snapshots.single['path'] as String);
      expect(await savedImage.exists(), isTrue);
      expect(jsonDecode(snapshots.single['strokes'] as String), isNotEmpty);
      debugPrint(
        'CHECK: bundled ML Kit inference with mobile and Wi-Fi data disabled',
      );
      final poseClip = File('$directory/pose-still-person.mp4');
      await poseClip.writeAsBytes(base64Decode(poseClipBase64));
      final progressEvents = <Map<String, dynamic>>[];
      final progressSubscription = PoseBridge.progress.listen(
        progressEvents.add,
      );
      final detected = await PoseBridge.analyze(
        poseClip.path,
        'real-model-test',
      );
      final poseReport = analyzePoses(detected, hand: '右手');
      expect(poseReport.frames, hasLength(24));
      expect(
        poseReport.frames
            .where((f) => f.points.values.where((p) => p.usable).length >= 12)
            .length,
        greaterThan(12),
      );
      expect(
        poseReport.swings,
        isEmpty,
        reason: 'A held yoga pose must never invent badminton swings',
      );
      expect(poseReport.drillIds, isEmpty);
      expect(progressEvents.last['done'], 24);
      await expectLater(
        PoseBridge.analyze('/sdcard/not-private.mp4', 'invalid-path'),
        throwsA(isA<PlatformException>()),
      );
      debugPrint('CHECK: native cancellation');
      final begun = Completer<void>();
      final cancellationListener = PoseBridge.progress.listen((p) {
        if (p['job'] == 'cancel-test' && !begun.isCompleted) begun.complete();
      });
      final cancelling = PoseBridge.analyze(poseClip.path, 'cancel-test');
      final cancellationExpectation = expectLater(
        cancelling,
        throwsA(isA<PlatformException>()),
      );
      await begun.future.timeout(const Duration(seconds: 15));
      await PoseBridge.cancel('cancel-test');
      await cancellationExpectation;
      await cancellationListener.cancel();
      await progressSubscription.cancel();
      debugPrint('CHECK: automatic report UI, persistence and body overlay');
      final poseVideo = <String, Object?>{
        'id': 'pose-video',
        'student_id': sid,
        'title': '公開姿態測試片',
        'path': poseClip.path,
        'duration_ms': 3000,
        'created': now(),
      };
      await store.addVideo(poseVideo);
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            home: PoseAnalysisScreen(poseVideo, autoStart: true),
          ),
        ),
      );
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('今次未有足夠依據').evaluate().isNotEmpty) break;
        if (find.text('分析未完成').evaluate().isNotEmpty) break;
      }
      expect(
        find.text('分析未完成'),
        findsNothing,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n'),
      );
      expect(find.text('今次未有足夠依據'), findsOneWidget);
      expect(await store.latestPoseReport('pose-video'), isNotNull);
      await tester.ensureVisible(find.text('查看骨架及影格'));
      await tester.tap(find.text('查看骨架及影格'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pose-overlay')), findsOneWidget);
      debugPrint('CHECK: deletion cleanup');
      await store.deleteStudent(sid);
      expect(await savedImage.exists(), isFalse);
      expect(await poseClip.exists(), isFalse);
      expect(await store.latestPoseReport('pose-video'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      expect(await clip.exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
