import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class QueueService {
  QueueService._();

  static final QueueService instance = QueueService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'umurima_queue.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE incoming_messages ADD COLUMN last_error TEXT',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE incoming_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE outgoing_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipient TEXT NOT NULL,
        body TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<int> saveIncomingMessage({
    required String sender,
    required String body,
    required String status,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.insert('incoming_messages', {
      'sender': sender,
      'body': body,
      'status': status,
      'payload': jsonEncode(payload),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingIncomingMessages() async {
    final db = await database;

    return db.query(
      'incoming_messages',
      where: 'status = ?',
      whereArgs: ['pending_upload'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllIncomingMessages() async {
    final db = await database;

    return db.query('incoming_messages', orderBy: 'created_at DESC');
  }

  Future<int> markIncomingUploaded(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'uploaded', 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markIncomingReplied(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'replied', 'updated_at': now, 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records why a message could not be answered, so the failure is visible in
  /// the UI instead of disappearing into a debug log.
  Future<int> markIncomingFailed(int id, String reason) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'failed', 'updated_at': now, 'last_error': reason},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Claims a row before its upload starts, so the periodic retry sweep cannot
  /// pick up the same message and send it to the backend a second time.
  Future<int> markIncomingUploading(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'uploading', 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Releases a claimed row back to the queue after a failed upload.
  Future<int> markIncomingPending(int id, String reason) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'pending_upload', 'updated_at': now, 'last_error': reason},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns rows stranded in `uploading` by a crash or a killed isolate so the
  /// sweep can retry them.
  Future<int> recoverStalledUploads({
    Duration olderThan = const Duration(minutes: 5),
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(olderThan).toIso8601String();

    return db.update(
      'incoming_messages',
      {'status': 'pending_upload', 'updated_at': now.toIso8601String()},
      where: 'status = ? AND updated_at < ?',
      whereArgs: ['uploading', cutoff],
    );
  }

  /// Attach a reply object to an existing incoming message payload.
  /// The `reply` map should contain fields like `phone_number` and `message`.
  Future<int> addReplyToIncoming(int id, Map<String, dynamic> reply) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    final rows = await db.query(
      'incoming_messages',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return 0;

    final payloadStr = rows.first['payload'] as String? ?? '{}';
    final Map<String, dynamic> payload =
        jsonDecode(payloadStr) as Map<String, dynamic>;
    payload['reply'] = reply;

    return db.update(
      'incoming_messages',
      {'payload': jsonEncode(payload), 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> saveOutgoingTask({
    required String recipient,
    required String body,
    required String status,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.insert('outgoing_tasks', {
      'recipient': recipient,
      'body': body,
      'status': status,
      'payload': jsonEncode(payload),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingOutgoingTasks() async {
    final db = await database;

    return db.query(
      'outgoing_tasks',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<int> markOutgoingTaskCompleted(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    return db.update(
      'outgoing_tasks',
      {'status': 'sent', 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
