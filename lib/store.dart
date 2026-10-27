import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef DbRow = Map<String, Object?>;
String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String now() => DateTime.now().toUtc().toIso8601String();

class CoachStore extends ChangeNotifier {
  final Database db;
  CoachStore(this.db);
  static Future<CoachStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final location =
        path ?? p.join(await f.getDatabasesPath(), 'badminton-coach-v2.db');
    final database = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (d, version) async {
          for (final sql in schema) {
            await d.execute(sql);
          }
        },
      ),
    );
    return CoachStore(database);
  }

  static const schema = <String>[
    'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE students (id TEXT PRIMARY KEY, name TEXT NOT NULL, age INTEGER NOT NULL CHECK(age BETWEEN 1 AND 100), hand TEXT NOT NULL CHECK(hand IN ("右手","左手")), experience INTEGER NOT NULL CHECK(experience >= 0 AND experience <= age), notes TEXT NOT NULL, created TEXT NOT NULL)',
    'CREATE TABLE videos (id TEXT PRIMARY KEY, student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE, title TEXT NOT NULL, path TEXT NOT NULL UNIQUE, duration_ms INTEGER NOT NULL CHECK(duration_ms > 0), created TEXT NOT NULL)',
    'CREATE TABLE assessments (id TEXT PRIMARY KEY, student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE, video_id TEXT REFERENCES videos(id) ON DELETE SET NULL, ratings TEXT NOT NULL, issues TEXT NOT NULL, notes TEXT NOT NULL, created TEXT NOT NULL)',
    'CREATE TABLE plans (id TEXT PRIMARY KEY, student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE, assessment_id TEXT REFERENCES assessments(id) ON DELETE SET NULL, drill_ids TEXT NOT NULL, created TEXT NOT NULL)',
    'CREATE TABLE practices (id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE, completed TEXT NOT NULL, effort INTEGER NOT NULL CHECK(effort BETWEEN 1 AND 5), notes TEXT NOT NULL, created TEXT NOT NULL)',
    'CREATE TABLE snapshots (id TEXT PRIMARY KEY, video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE, path TEXT NOT NULL UNIQUE, position_ms INTEGER NOT NULL, frame_index INTEGER NOT NULL, strokes TEXT NOT NULL, created TEXT NOT NULL)',
    'CREATE TABLE garbage (path TEXT PRIMARY KEY)',
    'CREATE INDEX video_student ON videos(student_id)',
    'CREATE INDEX assessment_student ON assessments(student_id)',
    'CREATE INDEX plan_student ON plans(student_id)',
    'CREATE INDEX practice_plan ON practices(plan_id)',
    'CREATE INDEX snapshot_video ON snapshots(video_id)',
  ];
  Future<bool> consented() async => (await db.query(
    'settings',
    where: 'key = ?',
    whereArgs: ['consent'],
  )).isNotEmpty;
  Future<void> consent() async {
    await db.insert('settings', {
      'key': 'consent',
      'value': 'yes',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<List<DbRow>> students() =>
      db.query('students', orderBy: 'created DESC');
  Future<DbRow?> student(String id) async {
    final rows = await db.query('students', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveStudent(DbRow value) async {
    final existing = await student(value['id'] as String);
    if (existing == null) {
      await db.insert('students', value);
    } else {
      await db.update(
        'students',
        value,
        where: 'id = ?',
        whereArgs: [value['id']],
      );
    }
    notifyListeners();
  }

  Future<List<DbRow>> videos({String? studentId}) => db.rawQuery(
    'SELECT v.*, s.name AS student_name FROM videos v JOIN students s ON s.id=v.student_id ${studentId == null ? '' : 'WHERE v.student_id=?'} ORDER BY v.created DESC',
    studentId == null ? [] : [studentId],
  );
  Future<void> addVideo(DbRow value) async {
    await db.insert('videos', value);
    notifyListeners();
  }

  Future<List<DbRow>> snapshots(String id) => db.query(
    'snapshots',
    where: 'video_id = ?',
    whereArgs: [id],
    orderBy: 'created DESC',
  );
  Future<void> addSnapshot(DbRow value) async {
    await db.insert('snapshots', value);
    notifyListeners();
  }

  Future<List<DbRow>> assessments(String id) => db.query(
    'assessments',
    where: 'student_id = ?',
    whereArgs: [id],
    orderBy: 'created DESC',
  );
  Future<void> saveAssessment({
    required String studentId,
    String? videoId,
    required List<int> ratings,
    required List<String> issues,
    required String notes,
    required List<String> drillIds,
  }) async {
    if (ratings.length != 7 || ratings.any((x) => x < 0 || x > 2)) {
      throw ArgumentError('評估需要七個有效觀察值');
    }
    final id = newId(), date = now();
    await db.transaction((tx) async {
      await tx.insert('assessments', {
        'id': id,
        'student_id': studentId,
        'video_id': videoId,
        'ratings': jsonEncode(ratings),
        'issues': jsonEncode(issues.toSet().toList()),
        'notes': notes,
        'created': date,
      });
      if (drillIds.isNotEmpty) {
        await tx.insert('plans', {
          'id': newId(),
          'student_id': studentId,
          'assessment_id': id,
          'drill_ids': jsonEncode(drillIds.toSet().take(3).toList()),
          'created': date,
        });
      }
    });
    notifyListeners();
  }

  Future<List<DbRow>> plans({String? studentId}) => db.rawQuery(
    'SELECT p.*, s.name AS student_name FROM plans p JOIN students s ON s.id=p.student_id ${studentId == null ? '' : 'WHERE p.student_id=?'} ORDER BY p.created DESC',
    studentId == null ? [] : [studentId],
  );
  Future<List<DbRow>> practices(String id) => db.query(
    'practices',
    where: 'plan_id = ?',
    whereArgs: [id],
    orderBy: 'created DESC',
  );
  Future<void> logPractice(
    String planId,
    List<String> completed,
    int effort,
    String notes,
  ) async {
    await db.transaction((tx) async {
      final rows = await tx.query(
        'plans',
        where: 'id = ?',
        whereArgs: [planId],
      );
      if (rows.isEmpty) {
        throw StateError('訓練計劃已不存在');
      }
      final allowed = (jsonDecode(rows.first['drill_ids'] as String) as List)
          .cast<String>()
          .toSet();
      if (completed.isEmpty ||
          completed.toSet().length != completed.length ||
          !allowed.containsAll(completed)) {
        throw ArgumentError('請選擇計劃內已完成嘅練習');
      }
      if (effort < 1 || effort > 5) {
        throw ArgumentError('請填寫 1–5 嘅練習感受');
      }
      await tx.insert('practices', {
        'id': newId(),
        'plan_id': planId,
        'completed': jsonEncode(completed),
        'effort': effort,
        'notes': notes,
        'created': now(),
      });
    });
    notifyListeners();
  }

  Future<void> deleteStudent(String id) async {
    await db.transaction((tx) async {
      final paths = await tx.rawQuery(
        'SELECT path FROM videos WHERE student_id=? UNION SELECT s.path FROM snapshots s JOIN videos v ON s.video_id=v.id WHERE v.student_id=?',
        [id, id],
      );
      for (final row in paths) {
        await tx.insert(
          'garbage',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await tx.delete('students', where: 'id = ?', whereArgs: [id]);
    });
    await collectGarbage();
    notifyListeners();
  }

  Future<void> deleteVideo(String id) async {
    await db.transaction((tx) async {
      final paths = await tx.rawQuery(
        'SELECT path FROM videos WHERE id=? UNION SELECT path FROM snapshots WHERE video_id=?',
        [id, id],
      );
      for (final row in paths) {
        await tx.insert(
          'garbage',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await tx.delete('videos', where: 'id = ?', whereArgs: [id]);
    });
    await collectGarbage();
    notifyListeners();
  }

  Future<void> collectGarbage() async {
    for (final row in await db.query('garbage')) {
      final path = row['path'] as String;
      final live = await db.rawQuery(
        'SELECT path FROM videos WHERE path=? UNION SELECT path FROM snapshots WHERE path=?',
        [path, path],
      );
      if (live.isNotEmpty) {
        await db.delete('garbage', where: 'path=?', whereArgs: [path]);
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        await db.delete('garbage', where: 'path=?', whereArgs: [path]);
      } on FileSystemException {
        /* Retry on next startup. */
      }
    }
  }

  Future<void> close() => db.close();
}
