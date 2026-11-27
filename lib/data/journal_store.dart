part of 'db.dart';

/// The `journal_metric` and `journal_field_def` tables and journal I/O, split
/// out of [LocalDb] by concern.
abstract final class JournalStore {
  /// journal_metric — the numeric half of a journal entry.
  ///
  /// The `journal` table holds a tag set and a note, which can only ever
  /// answer "did this happen today". A field that carries a NUMBER — three
  /// coffees, 700 ml of water, mood 4 out of 5 — carries a dose, and that is
  /// usually the actual question. Kept in its own table rather than as columns
  /// on `journal` so a user-defined field costs a row, not a migration.
  ///
  /// One row per (day, field): the value is the day's TOTAL for a dose-like
  /// field and the day's single reading for a rating.
  ///
  /// `at_min` is local minutes past midnight for the LATEST occurrence, and is
  /// null for anything without a meaningful time. It exists because when a
  /// dose landed can matter more than its size — the sleep-relevant fact about
  /// caffeine is the last cup, not the total.
  static Future<void> _createMetric(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_metric (
        date TEXT NOT NULL,
        field TEXT NOT NULL,
        value REAL NOT NULL,
        at_min INTEGER,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (date, field)
      )
    ''');
    // Correlations read one field across every day, so the index is on the
    // field first — the primary key already covers day-scoped reads.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_metric_field '
      'ON journal_metric(field, date)',
    );
  }

  /// journal_field_def — definitions for USER-INVENTED numeric fields only.
  ///
  /// Built-in fields live in `lib/data/journal_fields.dart` as code, because a
  /// definition that ships with the app should not be editable data. A custom
  /// field has nowhere else to record what its number means, and without a
  /// unit and a ceiling its values render as bare numbers and its entry has no
  /// bounds — so it gets a row.
  ///
  /// Deleting a definition deliberately does NOT delete its history: those
  /// readings were still real. They render unlabelled until the field is
  /// defined again.
  static Future<void> _createFieldDef(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_field_def (
        key TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        kind TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT '',
        max_value REAL NOT NULL,
        step REAL NOT NULL,
        has_time INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// Upsert one day's journal (tags JSON + note). Idempotent on date.
  static Future<void> put(String date, String tagsJson, String note) async {
    final db = await LocalDb.instance;
    await db.insert('journal', {
      'date': date,
      'tags_json': tagsJson,
      'note': note,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Recent journal rows, newest first. [sinceDaysEpoch] (a YYYY-MM-DD label) is
  /// an optional inclusive lower bound on `date`; [date] selects one exact day.
  static Future<List<Map<String, dynamic>>> entries({
    String? sinceDaysEpoch,
    String? date,
  }) async {
    final db = await LocalDb.instance;
    if (date != null) {
      return db.query('journal', where: 'date = ?', whereArgs: [date]);
    }
    if (sinceDaysEpoch != null) {
      return db.query(
        'journal',
        where: 'date >= ?',
        whereArgs: [sinceDaysEpoch],
        orderBy: 'date DESC',
      );
    }
    return db.query('journal', orderBy: 'date DESC');
  }

  /// Add answers to a night without replacing a note or another writer's tags.
  static Future<void> mergeTags(String date, List<String> tags) async {
    final db = await LocalDb.instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'journal',
        where: 'date = ?',
        whereArgs: [date],
      );
      final row = rows.isEmpty ? null : rows.single;
      final stored = jsonDecode((row?['tags_json'] as String?) ?? '[]') as List;
      await txn.insert('journal', {
        'date': date,
        'tags_json': jsonEncode({...stored.cast<String>(), ...tags}.toList()),
        'note': (row?['note'] as String?) ?? '',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Build 92 (Codex audit 12-13): one Journal edit in ONE transaction, as a
  /// patch. [changes] holds only the fields the editor changed (null clears
  /// one); [base] is what the editor read for them. Tags and note are written
  /// only when given (changed). Nothing is written when any changed field,
  /// tag list or note was changed by someone else since [base] was read (a
  /// band water tap while the editor was open): the names of those fields come
  /// back instead, and the caller shows the newer values.
  static Future<List<String>> saveEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  }) async {
    final db = await LocalDb.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'journal_metric',
        where: 'date = ?',
        whereArgs: [date],
      );
      final current = {
        for (final r in rows)
          r['field'] as String: JournalMetricValue(
            (r['value'] as num).toDouble(),
            atMinuteOfDay: (r['at_min'] as num?)?.toInt(),
          ),
      };
      final jr = await txn.query(
        'journal',
        where: 'date = ?',
        whereArgs: [date],
        limit: 1,
      );
      List<String> storedTags = const [];
      String storedNote = '';
      if (jr.isNotEmpty) {
        try {
          final t = jsonDecode((jr.first['tags_json'] as String?) ?? '[]');
          if (t is List) storedTags = [for (final x in t) x.toString()];
        } catch (_) {}
        storedNote = (jr.first['note'] as String?) ?? '';
      }
      final conflicts = <String>[
        for (final k in changes.keys)
          if (current[k] != base[k]) k,
        if (tags != null &&
            (storedTags.toSet().length !=
                    (baseTags ?? const []).toSet().length ||
                !storedTags.toSet().containsAll(baseTags ?? const [])))
          'tags',
        if (note != null && storedNote != (baseNote ?? '')) 'note',
      ];
      if (conflicts.isNotEmpty) return conflicts;
      for (final e in changes.entries) {
        if (e.value == null) {
          await txn.delete(
            'journal_metric',
            where: 'date = ? AND field = ?',
            whereArgs: [date, e.key],
          );
        } else {
          await txn.insert('journal_metric', {
            'date': date,
            'field': e.key,
            'value': e.value!.value,
            'at_min': e.value!.atMinuteOfDay,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      if (tags != null || note != null) {
        await txn.insert('journal', {
          'date': date,
          'tags_json': jsonEncode(tags ?? storedTags),
          'note': note ?? storedNote,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return const <String>[];
    });
  }

  /// One day's numeric fields, or an empty map when nothing was recorded.
  static Future<Map<String, JournalMetricValue>> metricsForDay(
    String date,
  ) async {
    final db = await LocalDb.instance;
    final rows = await db.query(
      'journal_metric',
      where: 'date = ?',
      whereArgs: [date],
    );
    return {
      for (final r in rows)
        r['field'] as String: JournalMetricValue(
          (r['value'] as num).toDouble(),
          atMinuteOfDay: (r['at_min'] as num?)?.toInt(),
        ),
    };
  }

  /// Numeric journal fields per day, oldest first, for the correlation pass.
  /// [sinceDaysEpoch] is an optional inclusive lower bound on `date`.
  static Future<Map<String, Map<String, JournalMetricValue>>> metricsByDay({
    String? sinceDaysEpoch,
  }) async {
    final db = await LocalDb.instance;
    final rows = sinceDaysEpoch == null
        ? await db.query('journal_metric', orderBy: 'date ASC')
        : await db.query(
            'journal_metric',
            where: 'date >= ?',
            whereArgs: [sinceDaysEpoch],
            orderBy: 'date ASC',
          );
    final out = <String, Map<String, JournalMetricValue>>{};
    for (final r in rows) {
      (out[r['date'] as String] ??= {})[r['field']
          as String] = JournalMetricValue(
        (r['value'] as num).toDouble(),
        atMinuteOfDay: (r['at_min'] as num?)?.toInt(),
      );
    }
    return out;
  }

  /// Custom field definitions, ordered by label.
  static Future<List<JournalFieldSpec>> fieldDefs() async {
    final db = await LocalDb.instance;
    final rows = await db.query('journal_field_def', orderBy: 'label ASC');
    return [
      for (final r in rows)
        JournalFieldSpec(
          key: r['key'] as String,
          label: r['label'] as String,
          kind: JournalFieldKind.values.firstWhere(
            (k) => k.name == r['kind'],
            // A row written by a newer build with a kind this one has never
            // heard of still renders as a dose rather than crashing the whole
            // journal screen.
            orElse: () => JournalFieldKind.dose,
          ),
          unit: r['unit'] as String,
          max: (r['max_value'] as num).toDouble(),
          step: (r['step'] as num).toDouble(),
          hasTime: ((r['has_time'] as num?)?.toInt() ?? 0) == 1,
          custom: true,
        ),
    ];
  }

  /// Create-only. A conflicting key THROWS instead of replacing: REPLACE
  /// would silently rewrite another definition's metadata (label, unit, kind)
  /// while its recorded history stayed — a field that means something else
  /// wearing the old rows. The UI rejects duplicates before it gets here; the
  /// throw is the race/programmatic-caller backstop.
  static Future<void> putFieldDef(JournalFieldSpec spec) async {
    final db = await LocalDb.instance;
    final exists = await db.query(
      'journal_field_def',
      where: 'key = ?',
      whereArgs: [spec.key],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      throw StateError('journal field already exists: ${spec.key}');
    }
    await db.insert('journal_field_def', {
      'key': spec.key,
      'label': spec.label,
      'kind': spec.kind.name,
      'unit': spec.unit,
      'max_value': spec.max,
      'step': spec.step,
      'has_time': spec.hasTime ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
