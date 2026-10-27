import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_ai_coach/pose_analysis.dart';
import 'pose_fixture.dart';

void main() {
  test('angles account for video aspect ratio and reject zero-length limbs', () {
    final frame = PoseFrame(0,0,800,400,{
      11: const BodyPoint(.25,.25,1), 13: const BodyPoint(.5,.5,1), 15: const BodyPoint(.75,.25,1)});
    expect(jointAngle(frame.point(11),frame.point(13),frame.point(15)), closeTo(126.87,.01));
    expect(jointAngle(frame.point(11),frame.point(11),frame.point(15)), isNull);
  });
  test('complete motion yields timestamped observations and relevant drills', () {
    final r = analyzePoses(poseFixture(), hand:'右手');
    expect(r.swings, hasLength(1));
    expect(r.swings.single.peak, 2000);
    expect(r.drillIds, containsAll(['elbow','ready']));
    expect(r.drillIds, isNot(contains('grip')));
    expect(r.drillIds, isNot(contains('turn')));
  });
  test('left-handed motion uses the anatomical left arm', () {
    final left = analyzePoses(poseFixture(left:true), hand:'左手');
    final right = analyzePoses(poseFixture(), hand:'右手');
    expect(left.swings.single.peak, right.swings.single.peak);
    expect(left.drillIds, right.drillIds);
  });
  test('mirrored recording reverses anatomical labels without changing hand record', () {
    final r = analyzePoses(poseFixture(left:true), hand:'右手', mirrored:true);
    expect(r.swings, hasLength(1)); expect(r.hand,'右手');
    expect(analyzePoses(poseFixture(left:true), hand:'右手').swings, isEmpty);
  });
  test('occlusion and missing feet abstain instead of manufacturing advice', () {
    for (final input in [poseFixture(occluded:true), poseFixture(cropped:true), poseFixture(small:true)]) {
      final r = analyzePoses(input, hand:'右手');
      expect(r.swings,isEmpty); expect(r.drillIds,isEmpty); expect(r.insufficientReason,isNotNull);
    }
  });
  test('a held overhead arm is not counted as a swing', () {
    expect(analyzePoses(poseFixture(still:true), hand:'右手').swings,isEmpty);
  });
  test('camera cuts or identity jumps invalidate the motion window', () {
    expect(analyzePoses(poseFixture(cut:true), hand:'右手').swings,isEmpty);
  });
  test('clip ending at the raised arm does not invent follow-through findings', () {
    final input=poseFixture(); input['frames']=(input['frames'] as List).take(17).toList();
    expect(analyzePoses(input,hand:'右手').swings,isEmpty);
  });
  test('duplicate times are rejected rather than treated as motion', () {
    final input=poseFixture(); input['frames'][1]['t']=0;
    expect(()=>analyzePoses(input,hand:'右手'),throwsFormatException);
  });
  test('stored report retains evidence, provenance, handedness and recommendations', () {
    final r=analyzePoses(poseFixture(),hand:'右手');
    final copy=PoseReport.fromJson(jsonDecode(jsonEncode(r.toJson())));
    expect(copy.toJson(),r.toJson()); expect(copy.rules,poseRulesVersion);
  });
}
