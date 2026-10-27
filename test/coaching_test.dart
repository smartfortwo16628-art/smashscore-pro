import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_ai_coach/coaching.dart';
import 'package:badminton_ai_coach/video.dart';

void main() {
  test('plans prioritise foundations, deduplicate and cap workload', () {
    expect(
      planFor(['recover', 'grip', 'balance', 'ready', 'grip']).map((d) => d.id),
      ['grip', 'ready', 'balance'],
    );
    expect(planFor(['unknown']), isEmpty);
  });
  test('variable frame intervals use actual timestamps and choose nearest', () {
    const times = [0, 33, 90, 190];
    expect(closestFrame(times, -5), 0);
    expect(closestFrame(times, 60), 1);
    expect(closestFrame(times, 70), 2);
    expect(closestFrame(times, 140), 2);
    expect(closestFrame(times, 999), 3);
    expect(closestFrame([], 0), -1);
  });
}
