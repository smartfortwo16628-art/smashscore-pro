import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'coaching.dart';
import 'main.dart';
import 'pose_analysis.dart';
import 'screens.dart';
import 'store.dart';
import 'video.dart';

class PoseBridge {
  static const channel = MethodChannel('hk.badminton.coach/pose');
  static final _progress = StreamController<Map<String, dynamic>>.broadcast();
  static bool _initialized = false;
  static Stream<Map<String, dynamic>> get progress {
    if (!_initialized) {
      _initialized = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'progress') {
          _progress.add(Map<String, dynamic>.from(call.arguments));
        }
      });
    }
    return _progress.stream;
  }

  static Future<Map<String, dynamic>> analyze(String path, String job) async =>
      (await channel.invokeMapMethod<String, dynamic>('analyze', {
        'path': path,
        'job': job,
      }))!;
  static Future<void> cancel(String job) async {
    try {
      await channel.invokeMethod<void>('cancel', {'job': job});
    } on PlatformException {
      /* The activity may already be gone. */
    }
  }
}

PoseReport _computeReport(Map<String, dynamic> input) => analyzePoses(
  input['native'] as Map<String, dynamic>,
  hand: input['hand'] as String,
  mirrored: input['mirrored'] as bool,
);

class PoseAnalysisScreen extends StatefulWidget {
  final DbRow video;
  final bool autoStart;
  const PoseAnalysisScreen(this.video, {super.key, this.autoStart = false});
  @override
  State<PoseAnalysisScreen> createState() => _PoseAnalysisState();
}

class _PoseAnalysisState extends State<PoseAnalysisScreen> {
  bool initialized = false,
      loading = true,
      running = false,
      mirrored = false,
      planBusy = false;
  String hand = '右手';
  String? job, error;
  int done = 0, total = 0;
  PoseReport? report;
  DbRow? saved;
  late final StreamSubscription<Map<String, dynamic>> subscription;
  @override
  void initState() {
    super.initState();
    subscription = PoseBridge.progress.listen((p) {
      if (mounted && running && p['job'] == job) {
        setState(() {
          done = (p['done'] as num).toInt();
          total = (p['total'] as num).toInt();
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      load();
    }
  }

  Future<void> load() async {
    final store = StoreScope.of(context);
    try {
      final student = await store.student(widget.video['student_id'] as String);
      final row = await store.latestPoseReport(widget.video['id'] as String);
      if (!mounted) return;
      final previous = row == null
          ? null
          : PoseReport.fromJson(jsonDecode(row['result'] as String));
      setState(() {
        hand = previous?.hand ?? (student?['hand'] as String?) ?? '右手';
        mirrored = previous?.mirrored ?? false;
        report = previous;
        saved = row;
        loading = false;
      });
      if (widget.autoStart && row == null) await start();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '讀取分析未完成：$e';
          loading = false;
        });
      }
    }
  }

  Future<void> start() async {
    if (running) return;
    final store = StoreScope.of(context);
    final currentJob = newId();
    setState(() {
      running = true;
      error = null;
      done = 0;
      total = 0;
      job = currentJob;
      report = null;
      saved = null;
    });
    try {
      final native = await PoseBridge.analyze(
        widget.video['path'] as String,
        currentJob,
      );
      if (!mounted || job != currentJob) return;
      final analysis = await compute(_computeReport, {
        'native': native,
        'hand': hand,
        'mirrored': mirrored,
      });
      if (!mounted || job != currentJob) return;
      final row = await store.savePoseReport(
        widget.video['id'] as String,
        analysis,
      );
      if (mounted) {
        setState(() {
          report = analysis;
          saved = row;
        });
      }
    } on PlatformException catch (e) {
      if (mounted && job == currentJob) {
        setState(() => error = e.message ?? '分析未完成，請重試。');
      }
    } catch (e) {
      if (mounted && job == currentJob) setState(() => error = '分析未完成：$e');
    } finally {
      if (mounted && (job == currentJob || job == null)) {
        setState(() {
          running = false;
          job = null;
        });
      }
    }
  }

  Future<void> stop() async {
    final id = job;
    if (id == null) return;
    // Invalidate first, so a completion racing with Cancel cannot persist a report.
    setState(() {
      job = null;
      error = '已停止分析；影片仍然保留。';
    });
    await PoseBridge.cancel(id);
  }

  Future<void> savePlan() async {
    if (saved == null || planBusy) return;
    final store = StoreScope.of(context);
    setState(() => planBusy = true);
    try {
      final id = await store.createPosePlan(saved!['id'] as String);
      final plans = await store.plans(
        studentId: widget.video['student_id'] as String,
      );
      final plan = plans.firstWhere((p) => p['id'] == id);
      if (!mounted) return;
      setState(() => saved = {...saved!, 'plan_id': id});
      go(context, PlanScreen(plan));
    } catch (e) {
      if (mounted) message(context, '練習未能儲存：$e');
    } finally {
      if (mounted) setState(() => planBusy = false);
    }
  }

  @override
  void dispose() {
    subscription.cancel();
    final id = job;
    if (id != null) unawaited(PoseBridge.cancel(id));
    super.dispose();
  }

  Widget panel(
    String title,
    String body, {
    IconData icon = Icons.info_outline,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xff087f70)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = report;
    final changed = r != null && (hand != r.hand || mirrored != r.mirrored);
    return Scaffold(
      appBar: AppBar(title: const Text('高遠球自動分析')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xff075f55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '睇動作，搵改善方向',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '免費・全程本機分析・實驗版',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('用固定鏡頭拍單一學員，頭頂至雙腳入鏡。模型會抽樣睇完整段片，搵疑似頭頂揮拍；唔需要自己逐項揀錯誤。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['右手', '左手']
                      .map(
                        (h) => ChoiceChip(
                          label: Text('$h持拍'),
                          selected: hand == h,
                          onSelected: running
                              ? null
                              : (_) => setState(() => hand = h),
                        ),
                      )
                      .toList(),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: mirrored,
                  title: const Text('影片左右鏡像'),
                  subtitle: const Text('例如自拍錄影儲存後左右倒轉；唔確定可對照骨架同持拍手。'),
                  onChanged: running
                      ? null
                      : (v) => setState(() => mirrored = v ?? false),
                ),
                if (changed)
                  const Text(
                    '設定已改；下面係上次報告，請重新分析以套用。',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
                if (running) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    total == 0
                        ? '正在啟動本機模型…'
                        : done >= total
                        ? '正在整理觀察同儲存報告…'
                        : '正在睇第 $done／$total 個抽樣影格',
                  ),
                  const Text('請留喺呢個畫面；長片同較慢手機會需要更多時間。離開 App 會停止分析。'),
                  OutlinedButton.icon(
                    onPressed: job == null ? null : stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止分析'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: start,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(r == null ? '開始自動分析' : '重新分析'),
                  ),
                if (error != null)
                  panel('分析未完成', error!, icon: Icons.error_outline),
                if (r != null) ...[
                  panel(
                    r.swings.isEmpty
                        ? '今次未有足夠依據'
                        : '找到 ${r.swings.length} 段疑似頭頂揮拍',
                    '全身可用影格 ${r.validFrames}/${r.frames.length}（${(r.coverage * 100).round()}%）；呢個係畫面可用比例，唔係技術分數。'
                    '\n分析設定：${r.hand}，${r.mirrored ? '鏡像' : '非鏡像'}。${r.precise ? '骨架對應原生影格索引。' : '時間係近似擷取，唔當作精確擊球時刻。'}'
                    '\n${r.insufficientReason ?? '已自動儲存。舉手峰值只供定位，未確認球拍接觸、出球種類或落點。'}',
                  ),
                  if (r.frames.any((f) => f.points.isNotEmpty))
                    OutlinedButton.icon(
                      onPressed: () => go(
                        context,
                        PoseEvidenceScreen(
                          video: widget.video,
                          report: r,
                          initialTime: r.swings.isEmpty
                              ? r.frames
                                    .firstWhere((f) => f.points.isNotEmpty)
                                    .time
                              : r.swings.first.peak,
                        ),
                      ),
                      icon: const Icon(Icons.accessibility_new),
                      label: const Text('查看骨架及影格'),
                    ),
                  ...r.swings.asMap().entries.map((entry) {
                    final s = entry.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '第 ${entry.key + 1} 段・${timeLabel(s.peak)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '觀察範圍 ${timeLabel(s.start)}–${timeLabel(s.end)}',
                            ),
                            Text(
                              '舉手峰值手肘夾角：${s.elbowAngle?.round() ?? '未能量度'}°（2D）',
                            ),
                            Text(
                              '揮拍後最大軀幹傾角：約 ${s.afterLean?.round() ?? '未能量度'}°（畫面垂直線）',
                            ),
                            Text(
                              '揮拍後雙腳中點位移：約 ${s.footTravel?.toStringAsFixed(2) ?? '未能量度'} 個軀幹長度（畫面位移，唔係回位分數）',
                            ),
                            if (s.hints.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text('今段未觸發保守觀察提示；唔代表所有技術正確。'),
                              ),
                            ...s.hints.map(
                              (h) => Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(h.detail),
                                    TextButton.icon(
                                      onPressed: () => go(
                                        context,
                                        PoseEvidenceScreen(
                                          video: widget.video,
                                          report: r,
                                          initialTime: h.time,
                                        ),
                                      ),
                                      icon: const Icon(Icons.search),
                                      label: Text('睇依據 ${timeLabel(h.time)}'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => go(
                                context,
                                PoseEvidenceScreen(
                                  video: widget.video,
                                  report: r,
                                  initialTime: s.peak,
                                ),
                              ),
                              child: const Text('重看呢段動作'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (r.drillIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('建議練習', style: Theme.of(context).textTheme.titleLarge),
                    const Text('按以上影像觀察配對；先同教練確認，再慢速試做。唔係傷患診斷。'),
                    ...drills
                        .where((d) => r.drillIds.contains(d.id))
                        .map(
                          (d) => panel(
                            d.title,
                            '口令：${d.cue}\n${d.practice}',
                            icon: Icons.sports_tennis,
                          ),
                        ),
                    FilledButton.icon(
                      onPressed: planBusy ? null : savePlan,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text(
                        planBusy
                            ? '正在處理…'
                            : saved?['plan_id'] != null
                            ? '查看已加入嘅練習計劃'
                            : '加入練習計劃及記錄改善',
                      ),
                    ),
                  ],
                  panel(
                    '呢啲仍然要教練確認',
                    '握拍手指／鬆緊、拍面、真正擊球點、3D 轉身幅度、剪刀步是否合適及戰術回位，'
                        '單靠人體骨架不能可靠判斷。呢個模型只追蹤一個人，多人、遮擋、鏡頭移動都可能認錯。'
                        '\n姿態辨識已接通；羽毛球觀察規則仍屬實驗性，未經兒童球技準確率驗證。',
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: running
                      ? null
                      : () => go(context, VideoScreen(widget.video)),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('開啟影片／手動慢放'),
                ),
              ],
            ),
    );
  }
}

class PoseEvidenceScreen extends StatefulWidget {
  final DbRow video;
  final PoseReport report;
  final int initialTime;
  const PoseEvidenceScreen({
    super.key,
    required this.video,
    required this.report,
    required this.initialTime,
  });
  @override
  State<PoseEvidenceScreen> createState() => _PoseEvidenceState();
}

class _PoseEvidenceState extends State<PoseEvidenceScreen> {
  late int selected = closestFrame(
    widget.report.frames.map((f) => f.time).toList(),
    widget.initialTime,
  );
  Map<String, dynamic>? image;
  String? error;
  bool busy = true, overlay = true;
  int request = 0;
  @override
  void initState() {
    super.initState();
    fetch(selected);
  }

  Future<void> fetch(int index) async {
    if (index < 0 || index >= widget.report.frames.length) return;
    final token = ++request;
    setState(() {
      selected = index;
      busy = true;
      error = null;
      image = null;
    });
    final f = widget.report.frames[index];
    try {
      final data = await MediaBridge.frame(
        widget.video['path'] as String,
        index: f.index < 0 ? null : f.index,
        position: f.time,
      );
      if (mounted && token == request) {
        setState(() {
          image = data;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = '影格未能開啟：$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.report.frames[selected];
    final data = image;
    final matching =
        data != null &&
        f.width > 0 &&
        f.height > 0 &&
        (((data['width'] as num) / (data['height'] as num)) -
                    f.width / f.height)
                .abs() <
            .02;
    return Scaffold(
      appBar: AppBar(title: Text('動作骨架・${timeLabel(f.time)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.all(50),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null) Text(error!),
          if (data != null)
            AspectRatio(
              aspectRatio: (data['width'] as num) / (data['height'] as num),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(data['bytes'] as Uint8List, fit: BoxFit.fill),
                  if (overlay && matching)
                    CustomPaint(
                      key: const Key('pose-overlay'),
                      painter: BodyPainter(f),
                    ),
                ],
              ),
            ),
          if (data != null && !matching) const Text('影格方向或尺寸未能對齊，已停用骨架覆蓋。'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('顯示可信身體關鍵點'),
            value: overlay,
            onChanged: (v) => setState(() => overlay = v),
          ),
          Text(
            '${selected + 1}/${widget.report.frames.length} 個抽樣影格・${widget.report.precise ? '原生影格對應' : '近似時間'}',
          ),
          Slider(
            value: selected.toDouble(),
            min: 0,
            max: (widget.report.frames.length - 1).clamp(1, 100000).toDouble(),
            onChanged: busy || widget.report.frames.length < 2
                ? null
                : (v) => fetch(v.round()),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || selected <= 0
                      ? null
                      : () => fetch(selected - 1),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('上一個'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || selected + 1 >= widget.report.frames.length
                      ? null
                      : () => fetch(selected + 1),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('下一個'),
                ),
              ),
            ],
          ),
          const Text(
            '只連接在畫面內、模型可信值至少 0.70 嘅點；可信值唔等於座標準確率。若骨架認錯人或認錯位置，請忽略該段評語。',
          ),
          FilledButton.icon(
            onPressed: () => go(
              context,
              VideoScreen(
                widget.video,
                initialPosition: (f.time - 1000).clamp(0, 180000).toInt(),
              ),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('由附近時間重播影片'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                go(context, FrameScreen(video: widget.video, position: f.time)),
            icon: const Icon(Icons.draw_outlined),
            label: const Text('開啟原片畫線標記'),
          ),
        ],
      ),
    );
  }
}

class BodyPainter extends CustomPainter {
  final PoseFrame frame;
  BodyPainter(this.frame);
  static const edges = [
    [11, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
    [11, 23],
    [12, 24],
    [23, 24],
    [23, 25],
    [25, 27],
    [24, 26],
    [26, 28],
    [27, 29],
    [29, 31],
    [28, 30],
    [30, 32],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    Offset location(int id) => Offset(
      frame.points[id]!.x * size.width,
      frame.points[id]!.y * size.height,
    );
    final outline = Paint()
      ..color = Colors.black87
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = const Color(0xff5bffc5)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final e in edges) {
      if (frame.points[e[0]]?.usable == true &&
          frame.points[e[1]]?.usable == true) {
        canvas.drawLine(location(e[0]), location(e[1]), outline);
        canvas.drawLine(location(e[0]), location(e[1]), line);
      }
    }
    for (final e in frame.points.entries) {
      if (e.value.usable) {
        canvas.drawCircle(location(e.key), 4, outline);
        canvas.drawCircle(location(e.key), 2.5, line);
      }
    }
  }

  @override
  bool shouldRepaint(BodyPainter oldDelegate) => oldDelegate.frame != frame;
}
