import 'dart:convert';
import 'package:flutter/material.dart';
import 'coaching.dart';
import 'main.dart';
import 'store.dart';
import 'video.dart';

String dateLabel(Object? value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

void message(BuildContext c, String text) {
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
  }
}

Future<bool> perform(BuildContext c, Future<void> Function() operation) async {
  try {
    await operation();
    return true;
  } catch (e) {
    if (c.mounted) {
      message(c, '未能完成：$e');
    }
    return false;
  }
}

void go(BuildContext c, Widget page) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page));
Future<bool> confirm(BuildContext c, String title, String detail) =>
    showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    ).then((x) => x ?? false);

class QueryList extends StatelessWidget {
  final Future<List<DbRow>> future;
  final Widget Function(List<DbRow>) builder;
  const QueryList({super.key, required this.future, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<DbRow>>(
    future: future,
    builder: (c, s) {
      if (s.hasError) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text('未能讀取紀錄：${s.error}'),
        );
      }
      if (!s.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return builder(s.data!);
    },
  );
}

class EmptyPanel extends StatelessWidget {
  final String title, detail;
  final Widget? action;
  const EmptyPanel(this.title, this.detail, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.sports_tennis_rounded,
          size: 48,
          color: Color(0xff087f70),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 20), child: action!),
      ],
    ),
  );
}

class ConsentScreen extends StatefulWidget {
  final Future<void> Function() onAccept;
  const ConsentScreen({super.key, required this.onAccept});
  @override
  State<ConsentScreen> createState() => _ConsentState();
}

class _ConsentState extends State<ConsentScreen> {
  bool checked = false, busy = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          const Icon(
            Icons.sports_tennis_rounded,
            size: 64,
            color: Color(0xff087f70),
          ),
          const SizedBox(height: 20),
          Text(
            'Badminton\nAI Coach',
            style: Theme.of(c).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          const Text('睇清動作，一步一步進步。'),
          const SizedBox(height: 28),
          const Text(
            '離線訓練助手',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '• 學員資料、影片同訓練紀錄只儲存喺呢部手機。\n• 建議用學員暱稱，毋須真名、生日或聯絡資料。\n• 沒有登入、廣告、付費服務或雲端備份。\n• 移除 App 會清除本機資料；匯出圖片後由你自行保管。\n• 本版採用人工觀察及練習配對，未提供自動 AI 技術評分。',
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: checked,
            onChanged: busy
                ? null
                : (v) => setState(() => checked = v ?? false),
            title: const Text('我會取得學員及家長合適同意，並由成人保管呢部手機。'),
          ),
          FilledButton(
            onPressed: !checked || busy
                ? null
                : () async {
                    setState(() => busy = true);
                    final ok = await perform(c, widget.onAccept);
                    if (mounted && !ok) {
                      setState(() => busy = false);
                    }
                  },
            child: Text(busy ? '開啟中…' : '開始使用'),
          ),
        ],
      ),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(['訓練室', '學員', '影片', '練習紀錄'][tab]),
      actions: [
        IconButton(
          tooltip: '使用及私隱說明',
          onPressed: () => go(c, const HelpScreen()),
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
    body: IndexedStack(
      index: tab,
      children: const [
        Dashboard(),
        StudentsScreen(),
        VideosScreen(),
        PlansScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '訓練室',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '學員',
        ),
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          selectedIcon: Icon(Icons.video_library),
          label: '影片',
        ),
        NavigationDestination(icon: Icon(Icons.checklist), label: '練習'),
      ],
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xff075f55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日，練好一個細節。',
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '由正手高遠球開始\n觀察 → 選擇練習 → 記錄改善',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 12),
            Chip(
              label: Text('全離線・人工觀察 V1'),
              avatar: Icon(Icons.offline_bolt, size: 18),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: Text('技術教學', style: Theme.of(c).textTheme.titleLarge),
          ),
          TextButton(
            onPressed: () => go(c, const HelpScreen()),
            child: const Text('評估界線'),
          ),
        ],
      ),
      ...List.generate(
        lessons.length,
        (i) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(lessons[i].title),
            subtitle: Text(lessons[i].subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => go(c, LessonScreen(lessons[i])),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text('成人陪同練習；先熱身、保持場地乾爽，疲倦或唔舒服就休息。'),
    ],
  );
}

class LessonScreen extends StatelessWidget {
  final Lesson lesson;
  const LessonScreen(this.lesson, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(lesson.title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(lesson.subtitle, style: Theme.of(c).textTheme.headlineSmall),
        const SizedBox(height: 20),
        ...List.generate(
          lesson.steps.length,
          (i) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 16, child: Text('${i + 1}')),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      lesson.steps[i],
                      style: const TextStyle(fontSize: 17, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(lesson.reminder, style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('使用及私隱說明')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '影片可以觀察啲乜？',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text('清晰拍到全身時，可逐格記錄動作次序、補步次數、站穩及回位時間。2D 角度只描述鏡頭平面，不能當成真實 3D 角度。'),
        SizedBox(height: 20),
        Text(
          '邊啲要教練判斷？',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text('準備動作是否合適、手肘路徑、轉身幅度、擊球位置、剪刀步及回位，要連同來球、能力及戰術情境判斷。唔設一個人人適用嘅標準角度。'),
        SizedBox(height: 20),
        Text(
          '邊啲唔可以可靠自動判斷？',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text(assessmentLimit),
        SizedBox(height: 20),
        Text(
          '資料只存手機',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text(
          '本版沒有網絡權限，亦沒有分析追蹤、登入、廣告或雲端備份。匯入影片會複製到 App 私人儲存；刪除 App 會清除資料。刪除學員會連同其影片、截圖、評估及練習紀錄一併刪除。\n\n匯出標記圖片後，該副本由你自行保管，App 內刪除不會刪除已匯出副本。請使用手機螢幕鎖。',
        ),
        SizedBox(height: 20),
        Text(
          '拍攝建議：固定手機，光線足夠，全身連雙腳入鏡。匯入上限 3 分鐘／300 MiB；MP4 H.264 通常較易播放。逐格功能只會在原生解碼器能提供可靠影格索引時啟用。',
        ),
        SizedBox(height: 20),
        const Text('Badminton AI Coach 1.1.0\nML Kit 與雲端功能尚未啟用。'),
        TextButton(
          onPressed: () => showLicensePage(
            context: c,
            applicationName: 'Badminton AI Coach',
            applicationVersion: '1.1.0',
          ),
          child: const Text('開源授權'),
        ),
      ],
    ),
  );
}

class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final store = StoreScope.of(c);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => go(c, const StudentForm()),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('新增學員'),
            ),
          ),
        ),
        Expanded(
          child: QueryList(
            future: store.students(),
            builder: (rows) => rows.isEmpty
                ? const EmptyPanel('建立第一位學員', '用暱稱記錄，保護小朋友私隱。')
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (ctx, i) {
                      final s = rows[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text('${s['name']}'),
                          subtitle: Text(
                            '${s['age']} 歲・${s['hand']}・學習 ${s['experience']} 年',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => go(c, StudentDetail(s['id'] as String)),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class StudentForm extends StatefulWidget {
  final DbRow? student;
  const StudentForm({super.key, this.student});
  @override
  State<StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<StudentForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
    text: widget.student?['name'] as String?,
  );
  late final TextEditingController age = TextEditingController(
    text: '${widget.student?['age'] ?? 8}',
  );
  late final TextEditingController experience = TextEditingController(
    text: '${widget.student?['experience'] ?? 0}',
  );
  late final TextEditingController notes = TextEditingController(
    text: widget.student?['notes'] as String?,
  );
  late String hand = widget.student?['hand'] as String? ?? '右手';
  bool busy = false;
  @override
  void dispose() {
    for (final x in [name, age, experience, notes]) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(widget.student == null ? '新增學員' : '修改學員')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: name,
            maxLength: 30,
            decoration: const InputDecoration(labelText: '暱稱'),
            validator: (v) => v == null || v.trim().isEmpty ? '請填寫暱稱' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '年齡'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > 100 ? '請填寫 1–100' : null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: hand,
            decoration: const InputDecoration(labelText: '慣用手'),
            items: [
              '右手',
              '左手',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => hand = v ?? hand),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: experience,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '學習經驗（整年；不足一年填 0）'),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 0 || n > (int.tryParse(age.text) ?? 0)
                  ? '經驗不可超過年齡'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: notes,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '教練備註（避免填寫敏感資料）'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) {
                      return;
                    }
                    final store = StoreScope.of(c);
                    setState(() => busy = true);
                    final ok = await perform(
                      c,
                      () => store.saveStudent({
                        'id': widget.student?['id'] ?? newId(),
                        'name': name.text.trim(),
                        'age': int.parse(age.text),
                        'hand': hand,
                        'experience': int.parse(experience.text),
                        'notes': notes.text.trim(),
                        'created': widget.student?['created'] ?? now(),
                      }),
                    );
                    if (!mounted || !c.mounted) {
                      return;
                    }
                    if (ok) {
                      Navigator.pop(c);
                    } else {
                      setState(() => busy = false);
                    }
                  },
            child: Text(busy ? '儲存中…' : '儲存學員'),
          ),
        ],
      ),
    ),
  );
}

class StudentDetail extends StatelessWidget {
  final String id;
  const StudentDetail(this.id, {super.key});
  @override
  Widget build(BuildContext c) {
    final store = StoreScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('學員檔案')),
      body: FutureBuilder<DbRow?>(
        future: store.student(id),
        builder: (ctx, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('未能讀取學員'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snapshot.data;
          if (s == null) {
            return const Center(child: Text('學員已刪除'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('${s['name']}', style: Theme.of(c).textTheme.headlineMedium),
              Text('${s['age']} 歲・${s['hand']}・學習 ${s['experience']} 年'),
              if ('${s['notes']}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${s['notes']}'),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => go(c, AssessmentScreen(studentId: id)),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('新增高遠球評估'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => go(
                  c,
                  Scaffold(
                    appBar: AppBar(title: const Text('學員影片')),
                    body: VideosScreen(studentId: id),
                  ),
                ),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('影片及標記'),
              ),
              OutlinedButton.icon(
                onPressed: () => go(
                  c,
                  Scaffold(
                    appBar: AppBar(title: const Text('訓練計劃')),
                    body: PlansScreen(studentId: id),
                  ),
                ),
                icon: const Icon(Icons.checklist),
                label: const Text('訓練計劃及改善紀錄'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => go(c, StudentForm(student: s)),
                      child: const Text('修改資料'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final yes = await confirm(
                          c,
                          '刪除 ${s['name']}？',
                          '會刪除此學員所有本機影片、標記、評估及練習紀錄，無法復原。已匯出嘅圖片不受影響。',
                        );
                        if (!c.mounted || !yes) {
                          return;
                        }
                        if (await perform(c, () => store.deleteStudent(id)) &&
                            c.mounted) {
                          Navigator.pop(c);
                        }
                      },
                      child: const Text('刪除學員'),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Text('歷次觀察', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              QueryList(
                future: store.assessments(id),
                builder: (rows) => Column(
                  children: rows.isEmpty
                      ? [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('未有評估紀錄'),
                          ),
                        ]
                      : rows.map((a) {
                          final scores =
                              (jsonDecode(a['ratings'] as String) as List)
                                  .cast<int>();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateLabel(a['created']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...List.generate(
                                    areas.length,
                                    (i) => Text(
                                      '${areas[i]}：${ratings[scores[i]]}',
                                    ),
                                  ),
                                  if ('${a['notes']}'.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text('${a['notes']}'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AssessmentScreen extends StatefulWidget {
  final String studentId;
  final String? videoId;
  const AssessmentScreen({super.key, required this.studentId, this.videoId});
  @override
  State<AssessmentScreen> createState() => _AssessmentState();
}

class _AssessmentState extends State<AssessmentScreen> {
  final scores = List<int>.filled(7, 0);
  final issues = <String>{};
  final notes = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('正手高遠球・教練觀察')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '睇唔清就選「未能觀察」，唔好估。',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(assessmentLimit),
        const SizedBox(height: 20),
        ...List.generate(
          areas.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<int>(
              initialValue: scores[i],
              decoration: InputDecoration(labelText: areas[i]),
              items: List.generate(
                ratings.length,
                (j) => DropdownMenuItem(value: j, child: Text(ratings[j])),
              ),
              onChanged: busy
                  ? null
                  : (v) => setState(() => scores[i] = v ?? 0),
            ),
          ),
        ),
        Text('今次想改善嘅問題', style: Theme.of(c).textTheme.titleLarge),
        const Text('依序配對最多 3 個練習。由教練確認是否適合學員。'),
        ...drills.map(
          (d) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(d.issue),
            subtitle: Text(d.evidence),
            value: issues.contains(d.id),
            onChanged: busy
                ? null
                : (v) => setState(
                    () => v == true ? issues.add(d.id) : issues.remove(d.id),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: notes,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '觀察、拍攝角度及改善重點'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  final store = StoreScope.of(c);
                  setState(() => busy = true);
                  final ok = await perform(
                    c,
                    () => store.saveAssessment(
                      studentId: widget.studentId,
                      videoId: widget.videoId,
                      ratings: scores,
                      issues: issues.toList(),
                      notes: notes.text.trim(),
                      drillIds: planFor(issues).map((d) => d.id).toList(),
                    ),
                  );
                  if (!mounted || !c.mounted) {
                    return;
                  }
                  if (ok) {
                    message(c, issues.isEmpty ? '已儲存觀察紀錄' : '已儲存觀察及配對練習');
                    Navigator.pop(c);
                  } else {
                    setState(() => busy = false);
                  }
                },
          child: Text(busy ? '儲存中…' : '儲存觀察及配對練習'),
        ),
      ],
    ),
  );
}

class PlansScreen extends StatelessWidget {
  final String? studentId;
  const PlansScreen({super.key, this.studentId});
  @override
  Widget build(BuildContext c) => QueryList(
    future: StoreScope.of(c).plans(studentId: studentId),
    builder: (rows) => rows.isEmpty
        ? const Center(
            child: EmptyPanel('先觀察，再練習', '喺學員檔案新增評估，選擇想改善嘅問題，就會配對最多 3 項練習。'),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: rows
                .map(
                  (p) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.checklist)),
                      title: Text('${p['student_name']}・高遠球練習'),
                      subtitle: Text(dateLabel(p['created'])),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => go(c, PlanScreen(p)),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class PlanScreen extends StatefulWidget {
  final DbRow plan;
  const PlanScreen(this.plan, {super.key});
  @override
  State<PlanScreen> createState() => _PlanState();
}

class _PlanState extends State<PlanScreen> {
  final completed = <String>{};
  final notes = TextEditingController();
  int effort = 3;
  bool busy = false;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final store = StoreScope.of(c);
    final selected = (jsonDecode(widget.plan['drill_ids'] as String) as List)
        .cast<String>();
    final exercises = drills.where((d) => selected.contains(d.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.plan['student_name']}・練習')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '每次專注一至三項',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text('建議每週 2–3 次，每次約 5–10 分鐘，由成人按體力調整。先慢後快，疲倦或唔舒服就休息。'),
          const SizedBox(height: 16),
          ...exercises.map(
            (d) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: Theme.of(c).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    Text(
                      '教練口令：${d.cue}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xff075f55),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(d.practice),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('今次已完成'),
                      value: completed.contains(d.id),
                      onChanged: busy
                          ? null
                          : (v) => setState(
                              () => v == true
                                  ? completed.add(d.id)
                                  : completed.remove(d.id),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: effort,
            decoration: const InputDecoration(labelText: '學員覺得今次控制動作有幾順？'),
            items: List.generate(
              5,
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text(
                  '${i + 1} / 5${i == 0
                      ? '・仍然困難'
                      : i == 4
                      ? '・相當順暢'
                      : ''}',
                ),
              ),
            ),
            onChanged: busy ? null : (v) => setState(() => effort = v ?? 3),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: notes,
            maxLength: 800,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '改善紀錄／下次重點'),
          ),
          FilledButton(
            onPressed: busy || completed.isEmpty
                ? null
                : () async {
                    setState(() => busy = true);
                    final ok = await perform(
                      c,
                      () => store.logPractice(
                        widget.plan['id'] as String,
                        completed.toList(),
                        effort,
                        notes.text.trim(),
                      ),
                    );
                    if (!mounted || !c.mounted) {
                      return;
                    }
                    setState(() {
                      busy = false;
                      if (ok) {
                        completed.clear();
                        notes.clear();
                      }
                    });
                    if (ok) {
                      message(c, '已記錄今次練習');
                    }
                  },
            child: Text(busy ? '儲存中…' : '記錄今次練習'),
          ),
          const SizedBox(height: 24),
          Text('改善紀錄', style: Theme.of(c).textTheme.titleLarge),
          QueryList(
            future: store.practices(widget.plan['id'] as String),
            builder: (rows) => Column(
              children: rows
                  .map(
                    (r) => Card(
                      child: ListTile(
                        title: Text(
                          '${dateLabel(r['created'])}・自評 ${r['effort']}/5',
                        ),
                        subtitle: Text(
                          '完成 ${(jsonDecode(r['completed'] as String) as List).length} 項\n${r['notes']}',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
