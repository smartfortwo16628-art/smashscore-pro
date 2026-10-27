import 'dart:math' as math;

/// Synthetic joint trajectories for rule regression tests; never used by the app or accuracy claims.
Map<String, dynamic> poseFixture({bool left = false, bool still = false,
  bool occluded = false, bool cropped = false, bool cut = false, bool small = false}) {
  final frames = <Map<String, dynamic>>[];
  for (var i = 0; i <= 40; i++) {
    final time = i * 125;
    final rise = still ? .34 : .34 * math.exp(-math.pow((time - 2000) / 400, 2));
    final positions = <int, List<double>>{
      11: [.42,.36], 12: [.58,.36], 13: [.34,.43], 14: [.65, time >= 1750 && time <= 2250 ? .22 : .45],
      15: [.30,.52], 16: [.70,.48 - rise], 23: [.46,.60], 24: [.54,.60],
      25: [.45,.75], 26: [.55,.75], 27: [.42,.92], 28: [.60,.92],
    };
    final points = positions.entries.where((e) => !cropped || e.key != 28).map((e) {
      final id = left ? (e.key.isOdd ? e.key + 1 : e.key - 1) : e.key;
      final confidence = occluded && e.key == 16 ? .20 : .99;
      // One identity jump around the peak must break temporal analysis.
      final dx = cut && time == 2000 ? .25 : 0.0;
      return [id, e.value[0] + dx, e.value[1], confidence];
    }).toList();
    frames.add({'t': time, 'index': i, 'width': small ? 160 : 800,
      'height': small ? 160 : 800, 'points': points});
  }
  return {'model':'synthetic-test-only','sampleMs':125,'duration':5125,'precise':true,'failed':0,'frames':frames};
}
