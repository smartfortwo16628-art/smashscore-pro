import 'dart:math' as math;

/// Experimental, explainable 2-D observations, not a trained badminton classifier.
/// All thresholds are review triggers, never child-specific correctness standards.
const poseRulesVersion = 'clear-observations-1';
const landmarkCutoff = .70;

class BodyPoint {
  final double x, y, confidence;
  const BodyPoint(this.x, this.y, this.confidence);
  bool get usable => x.isFinite && y.isFinite && confidence.isFinite &&
      confidence >= landmarkCutoff && x >= 0 && x <= 1 && y >= 0 && y <= 1;
}

class PoseFrame {
  final int time, index, width, height;
  final Map<int, BodyPoint> points;
  const PoseFrame(this.time, this.index, this.width, this.height, this.points);
  factory PoseFrame.fromJson(Map<String, dynamic> json) => PoseFrame(
    (json['t'] as num).toInt(), (json['index'] as num).toInt(),
    (json['width'] as num).toInt(), (json['height'] as num).toInt(),
    {for (final value in json['points'] as List)
      (value[0] as num).toInt(): BodyPoint((value[1] as num).toDouble(),
          (value[2] as num).toDouble(), (value[3] as num).toDouble())},
  );
  Map<String, dynamic> toJson() => {'t': time, 'index': index, 'width': width,
    'height': height, 'points': points.entries.map((e) =>
      [e.key, e.value.x, e.value.y, e.value.confidence]).toList()};
  math.Point<double>? point(int id) {
    final p = points[id];
    if (p == null || !p.usable || width <= 0 || height <= 0) return null;
    // Preserve pixel aspect ratio. Angles of unit-square coordinates are wrong.
    return math.Point(p.x * width, p.y * height);
  }
  math.Point<double>? middle(int a, int b) {
    final p = point(a), q = point(b);
    return p == null || q == null ? null : (p + q) * .5;
  }
  double? get torso {
    final a = middle(11, 12), b = middle(23, 24);
    return a == null || b == null ? null : a.distanceTo(b);
  }
  bool reliable(bool left) {
    if (width < 360 || height < 360 || (torso ?? 0) < 45) return false;
    return [11, 12, 23, 24, 25, 26, 27, 28, left ? 13 : 14, left ? 15 : 16]
        .every((id) => point(id) != null);
  }
}

double? jointAngle(math.Point<double>? a, math.Point<double>? b, math.Point<double>? c) {
  if (a == null || b == null || c == null) return null;
  final u = a - b, v = c - b;
  final length = u.magnitude * v.magnitude;
  if (length < 1e-6) return null;
  return math.acos(((u.x * v.x + u.y * v.y) / length).clamp(-1.0, 1.0)) * 180 / math.pi;
}

class PoseHint {
  final String id, title, detail, drill;
  final int time;
  const PoseHint(this.id, this.title, this.detail, this.drill, this.time);
  factory PoseHint.fromJson(Map<String, dynamic> j) => PoseHint(
      j['id'] as String, j['title'] as String, j['detail'] as String,
      j['drill'] as String, (j['time'] as num).toInt());
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'detail': detail,
    'drill': drill, 'time': time};
}

class SwingObservation {
  final int start, peak, end;
  final double? elbowAngle, preparationElbowHeight, afterLean, footTravel;
  final List<PoseHint> hints;
  const SwingObservation({required this.start, required this.peak, required this.end,
    this.elbowAngle, this.preparationElbowHeight, this.afterLean, this.footTravel,
    required this.hints});
  factory SwingObservation.fromJson(Map<String, dynamic> j) => SwingObservation(
    start: (j['start'] as num).toInt(), peak: (j['peak'] as num).toInt(), end: (j['end'] as num).toInt(),
    elbowAngle: (j['elbowAngle'] as num?)?.toDouble(),
    preparationElbowHeight: (j['preparationElbowHeight'] as num?)?.toDouble(),
    afterLean: (j['afterLean'] as num?)?.toDouble(), footTravel: (j['footTravel'] as num?)?.toDouble(),
    hints: (j['hints'] as List).map((x) => PoseHint.fromJson(Map<String, dynamic>.from(x))).toList(),
  );
  Map<String, dynamic> toJson() => {'start': start, 'peak': peak, 'end': end,
    'elbowAngle': elbowAngle, 'preparationElbowHeight': preparationElbowHeight,
    'afterLean': afterLean, 'footTravel': footTravel,
    'hints': hints.map((x) => x.toJson()).toList()};
}

class PoseReport {
  final String hand, model, rules;
  final bool mirrored, precise;
  final int duration, validFrames, failedFrames;
  final List<PoseFrame> frames;
  final List<SwingObservation> swings;
  final String? insufficientReason;
  const PoseReport({required this.hand, required this.mirrored, required this.model,
    required this.rules, required this.precise, required this.duration,
    required this.validFrames, required this.failedFrames, required this.frames,
    required this.swings, this.insufficientReason});
  double get coverage => frames.isEmpty ? 0 : validFrames / frames.length;
  List<String> get drillIds => swings.expand((s) => s.hints).map((h) => h.drill).toSet().take(3).toList();
  factory PoseReport.fromJson(Map<String, dynamic> j) => PoseReport(
    hand: j['hand'] as String, mirrored: j['mirrored'] == true, model: j['model'] as String,
    rules: j['rules'] as String, precise: j['precise'] == true, duration: (j['duration'] as num).toInt(),
    validFrames: (j['validFrames'] as num).toInt(), failedFrames: (j['failedFrames'] as num).toInt(),
    frames: (j['frames'] as List).map((x) => PoseFrame.fromJson(Map<String, dynamic>.from(x))).toList(),
    swings: (j['swings'] as List).map((x) => SwingObservation.fromJson(Map<String, dynamic>.from(x))).toList(),
    insufficientReason: j['insufficientReason'] as String?,
  );
  Map<String, dynamic> toJson() => {'hand': hand, 'mirrored': mirrored, 'model': model,
    'rules': rules, 'precise': precise, 'duration': duration, 'validFrames': validFrames,
    'failedFrames': failedFrames, 'frames': frames.map((x) => x.toJson()).toList(),
    'swings': swings.map((x) => x.toJson()).toList(), 'insufficientReason': insufficientReason};
}

PoseReport analyzePoses(Map<String, dynamic> native, {required String hand, bool mirrored = false}) {
  if (hand != '左手' && hand != '右手') throw ArgumentError('請選擇持拍手');
  final left = (hand == '左手') != mirrored;
  final shoulder = left ? 11 : 12, elbow = left ? 13 : 14, wrist = left ? 15 : 16;
  final otherShoulder = left ? 12 : 11, otherWrist = left ? 16 : 15;
  final frames = (native['frames'] as List)
      .map((x) => PoseFrame.fromJson(Map<String, dynamic>.from(x))).toList();
  for (var i = 1; i < frames.length; i++) {
    if (frames[i].time <= frames[i - 1].time) throw const FormatException('影格時間次序無效');
  }
  final valid = frames.where((f) => f.reliable(left)).toList();
  final result = <SwingObservation>[];
  String? reason;
  if (frames.isEmpty || valid.length < 12 || valid.length / frames.length < .60) {
    reason = '全身清晰影格不足，今次唔產生技術評語。請固定手機、拍單一學員，頭頂到雙腳留喺畫面內，並靠近少少。';
  } else {
    double reach(PoseFrame f) => (f.point(shoulder)!.y - f.point(wrist)!.y) / f.torso!;
    final groups = <List<PoseFrame>>[];
    var group = <PoseFrame>[];
    for (final f in valid) {
      if (reach(f) >= .45) {
        if (group.isNotEmpty && f.time - group.last.time > 375) {
          groups.add(group); group = [];
        }
        group.add(f);
      } else if (group.isNotEmpty) { groups.add(group); group = []; }
    }
    if (group.isNotEmpty) groups.add(group);
    for (final raised in groups) {
      if (raised.length < 2 || raised.last.time - raised.first.time > 2500) continue;
      final peak = raised.reduce((a, b) => reach(a) >= reach(b) ? a : b);
      if (result.isNotEmpty && peak.time - result.last.peak < 1000) continue;
      final before = valid.where((f) => f.time >= peak.time - 1500 && f.time <= peak.time - 250).toList();
      final after = valid.where((f) => f.time >= peak.time + 250 && f.time <= peak.time + 1750).toList();
      if (before.length < 3 || after.length < 4) continue;
      // A complete rise and lowering are needed. A still photo/held arm is not a swing.
      if (!before.any((f) => reach(f) < reach(peak) - .35) ||
          !after.any((f) => reach(f) < reach(peak) - .35)) continue;
      final window = valid.where((f) => f.time >= before.first.time && f.time <= after.last.time).toList();
      var continuous = true;
      for (var i = 1; i < window.length; i++) {
        final a = window[i - 1], b = window[i];
        final scale = a.torso! / b.torso!;
        if (b.time - a.time > 375 || scale < .60 || scale > 1.67 ||
            a.middle(23, 24)!.distanceTo(b.middle(23, 24)!) / a.torso! > .8) continuous = false;
      }
      if (!continuous) continue; // Occlusion, camera cut, or an identity jump: abstain.
      final prep = before.where((f) => f.time >= peak.time - 1000).toList();
      double height(PoseFrame f) => (f.point(shoulder)!.y - f.point(elbow)!.y) / f.torso!;
      final prepHeight = prep.isEmpty ? null : prep.map(height).reduce((a, b) => a + b) / prep.length;
      final lowElbows = prep.where((f) => height(f) < -.20).toList();
      final supportArm = prep.where((f) => f.point(otherWrist) != null).toList();
      double lean(PoseFrame f) {
        final d = f.middle(11, 12)! - f.middle(23, 24)!;
        return math.atan2(d.x.abs(), -d.y) * 180 / math.pi;
      }
      final leanFrames = after.where((f) => lean(f) > 25).toList();
      final maxLean = after.map(lean).reduce(math.max);
      final footTravel = after.first.middle(27, 28)!.distanceTo(after.last.middle(27, 28)!) / peak.torso!;
      final hints = <PoseHint>[];
      if (lowElbows.length >= 3 && lowElbows.length / prep.length >= .60) {
        hints.add(PoseHint('low_elbow', '準備時手肘較低',
          '${lowElbows.length}/${prep.length} 個準備影格，持拍手肘低於同側肩膊超過約 0.2 個軀幹長度。'
          '只屬鏡頭平面觀察；同教練重看片段，確認是否需要提早帶起手肘，唔好硬拉到指定角度。', 'elbow', lowElbows.first.time));
      }
      if (supportArm.length >= 3 && supportArm.length >= prep.length * .75 &&
          supportArm.every((f) => f.point(otherWrist)!.y > f.point(otherShoulder)!.y)) {
        hints.add(PoseHint('support_arm', '非持拍手未見抬過肩膊',
          '清晰嘅準備影格內，非持拍手腕都低於肩膊。可以重看準備時機，再由教練決定是否加入抬手定位練習。',
          'ready', supportArm.first.time));
      }
      if (leanFrames.length >= 3 && leanFrames.length / after.length >= .4) {
        hints.add(PoseHint('after_lean', '揮拍後軀幹傾斜較明顯',
          '揮拍後多個影格嘅肩髖中線偏離畫面垂直線超過 25°，最大約 ${maxLean.round()}°。'
          '鏡頭歪斜、合理移動亦會出現；唔代表已確定失平衡，請重看腳步同落地。', 'balance', leanFrames.first.time));
      }
      result.add(SwingObservation(start: before.first.time, peak: peak.time, end: after.last.time,
        elbowAngle: jointAngle(peak.point(shoulder), peak.point(elbow), peak.point(wrist)),
        preparationElbowHeight: prepHeight, afterLean: maxLean, footTravel: footTravel, hints: hints));
    }
    if (result.isEmpty) {
      reason = '辨識到人體姿態，但未找到完整、連續嘅頭頂揮拍片段。請拍低準備、揮拍同完成後約 2 秒；靜態舉手唔會當成已完成擊球。';
    }
  }
  return PoseReport(hand: hand, mirrored: mirrored, model: native['model'] as String,
    rules: poseRulesVersion, precise: native['precise'] == true,
    duration: (native['duration'] as num).toInt(), validFrames: valid.length,
    failedFrames: (native['failed'] as num).toInt(), frames: frames, swings: result,
    insufficientReason: reason);
}
