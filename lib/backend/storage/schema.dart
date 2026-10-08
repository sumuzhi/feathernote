/// SQLite DDL（原样移植 `server/src/db/schema.js:14-90`，**去掉 `kb_index`**）。
///
/// DDL 字符串被单测逐字断言，保证与原项目 schema 一致；
/// drift 的 table class 仅用于生成类型安全查询。
library;

/// 当前 schema 版本（承载于 `schema_meta`，与 drift 的 `schemaVersion` 双写以便对照）。
///
/// v2（IMPORT-PIPELINE-DESIGN §5.2）：meetings 新增 `import_*` 4 列，
/// `source` CHECK 放开 `imported`。v1 → v2 走 [kUpgradeV2Statements] 重建表。
const int kSchemaVersion = 2;

/// schema 版本键名。
const String kSchemaMetaVersionKey = 'schema_version';

/// 完整 DDL（全部 `IF NOT EXISTS`，幂等；已删除 `kb_index`）。
const String kSchemaSql = '''
-- ── 元信息（承载 schema 版本，便于未来增量迁移）──
CREATE TABLE IF NOT EXISTS schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- ── 会议主体 ──
CREATE TABLE IF NOT EXISTS meetings (
  id                TEXT    PRIMARY KEY,
  title             TEXT    NOT NULL,
  created_at        TEXT    NOT NULL,
  duration_ms       INTEGER NOT NULL DEFAULT 0,
  sample_rate       INTEGER NOT NULL DEFAULT 16000,
  speaker_count     INTEGER NOT NULL DEFAULT 0,
  minutes_md        TEXT,
  minutes_partial   INTEGER NOT NULL DEFAULT 0,
  minutes_error     TEXT,
  status            TEXT    NOT NULL DEFAULT 'recording',
  source            TEXT    NOT NULL DEFAULT 'microphone',
  finalize_status   TEXT    NOT NULL DEFAULT 'none',
  transcript_source TEXT    NOT NULL DEFAULT 'realtime',
  finalize_error    TEXT,
  audio_status      TEXT    NOT NULL DEFAULT 'none',
  audio_key         TEXT,
  audio_error       TEXT,
  audio_bytes       INTEGER NOT NULL DEFAULT 0,
  import_status     TEXT    NOT NULL DEFAULT 'none',
  import_error      TEXT,
  import_task_id    TEXT,
  import_meta_json  TEXT,
  CHECK (status IN ('recording','stopped','minutes_ready')),
  CHECK (source IN ('microphone','upload','imported')),
  CHECK (finalize_status IN ('none','pending','done','failed')),
  CHECK (transcript_source IN ('realtime','filetrans')),
  CHECK (audio_status IN ('none','uploading','done','failed')),
  CHECK (import_status IN ('none','import_pending','extracting','transcribing','minutes','done','failed'))
);
CREATE INDEX IF NOT EXISTS idx_meetings_created_at ON meetings(created_at DESC);

-- ── 逐字稿片段（结构规则、按序）──
CREATE TABLE IF NOT EXISTS transcript_segments (
  meeting_id   TEXT    NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  segment_id   TEXT    NOT NULL,
  ordinal      INTEGER NOT NULL,
  speaker_id   TEXT    NOT NULL,
  speaker_name TEXT,
  text         TEXT    NOT NULL DEFAULT '',
  start_time   INTEGER NOT NULL DEFAULT 0,
  end_time     INTEGER NOT NULL DEFAULT 0,
  confidence   REAL    NOT NULL DEFAULT 0.9,
  seq_start    INTEGER NOT NULL DEFAULT 0,
  seq_end      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (meeting_id, segment_id)
);
CREATE INDEX IF NOT EXISTS idx_segments_order
  ON transcript_segments(meeting_id, start_time, segment_id);

-- ── 说话人表 ──
CREATE TABLE IF NOT EXISTS speakers (
  meeting_id    TEXT    NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
  speaker_id    TEXT    NOT NULL,
  name          TEXT    NOT NULL,
  color_index   INTEGER NOT NULL DEFAULT 0,
  first_seen_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (meeting_id, speaker_id)
);

-- ── 终稿原始 JSON（审计 / 可重跑映射；不透明聚合件）──
CREATE TABLE IF NOT EXISTS filetrans_raw (
  meeting_id TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,
  json       TEXT NOT NULL,
  created_at TEXT NOT NULL
);
''';

/// 建表语句列表（按依赖顺序；供逐条执行与单测断言）。
const List<String> kSchemaStatements = <String>[
  'CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS meetings (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
      'created_at TEXT NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0, '
      'sample_rate INTEGER NOT NULL DEFAULT 16000, speaker_count INTEGER NOT NULL DEFAULT 0, '
      'minutes_md TEXT, minutes_partial INTEGER NOT NULL DEFAULT 0, minutes_error TEXT, '
      "status TEXT NOT NULL DEFAULT 'recording', source TEXT NOT NULL DEFAULT 'microphone', "
      "finalize_status TEXT NOT NULL DEFAULT 'none', transcript_source TEXT NOT NULL DEFAULT 'realtime', "
      'finalize_error TEXT, audio_status TEXT NOT NULL DEFAULT \'none\', audio_key TEXT, '
      'audio_error TEXT, audio_bytes INTEGER NOT NULL DEFAULT 0, '
      "import_status TEXT NOT NULL DEFAULT 'none', import_error TEXT, "
      'import_task_id TEXT, import_meta_json TEXT, '
      "CHECK (status IN ('recording','stopped','minutes_ready')), "
      "CHECK (source IN ('microphone','upload','imported')), "
      "CHECK (finalize_status IN ('none','pending','done','failed')), "
      "CHECK (transcript_source IN ('realtime','filetrans')), "
      "CHECK (audio_status IN ('none','uploading','done','failed')), "
      "CHECK (import_status IN ('none','import_pending','extracting','transcribing','minutes','done','failed')))",
  'CREATE INDEX IF NOT EXISTS idx_meetings_created_at ON meetings(created_at DESC)',
  'CREATE TABLE IF NOT EXISTS transcript_segments (meeting_id TEXT NOT NULL '
      'REFERENCES meetings(id) ON DELETE CASCADE, segment_id TEXT NOT NULL, '
      'ordinal INTEGER NOT NULL, speaker_id TEXT NOT NULL, speaker_name TEXT, '
      "text TEXT NOT NULL DEFAULT '', start_time INTEGER NOT NULL DEFAULT 0, "
      'end_time INTEGER NOT NULL DEFAULT 0, confidence REAL NOT NULL DEFAULT 0.9, '
      'seq_start INTEGER NOT NULL DEFAULT 0, seq_end INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (meeting_id, segment_id))',
  'CREATE INDEX IF NOT EXISTS idx_segments_order '
      'ON transcript_segments(meeting_id, start_time, segment_id)',
  'CREATE TABLE IF NOT EXISTS speakers (meeting_id TEXT NOT NULL '
      'REFERENCES meetings(id) ON DELETE CASCADE, speaker_id TEXT NOT NULL, '
      'name TEXT NOT NULL, color_index INTEGER NOT NULL DEFAULT 0, '
      'first_seen_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (meeting_id, speaker_id))',
  'CREATE TABLE IF NOT EXISTS filetrans_raw (meeting_id TEXT PRIMARY KEY '
      'REFERENCES meetings(id) ON DELETE CASCADE, json TEXT NOT NULL, created_at TEXT NOT NULL)',
];

/// 外键级联开关（子表删除依赖它）。
const String kForeignKeysOn = 'PRAGMA foreign_keys = ON';

/// v1（初版）的 meetings 建表语句（**逐字保留**，仅供迁移测试搭建 v1 存量库）。
///
/// 与 v2 的差异：无 `import_*` 4 列；`source` CHECK 不含 `'imported'`。
const List<String> kV1MeetingsStatements = <String>[
  'CREATE TABLE IF NOT EXISTS meetings (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
      'created_at TEXT NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0, '
      'sample_rate INTEGER NOT NULL DEFAULT 16000, speaker_count INTEGER NOT NULL DEFAULT 0, '
      'minutes_md TEXT, minutes_partial INTEGER NOT NULL DEFAULT 0, minutes_error TEXT, '
      "status TEXT NOT NULL DEFAULT 'recording', source TEXT NOT NULL DEFAULT 'microphone', "
      "finalize_status TEXT NOT NULL DEFAULT 'none', transcript_source TEXT NOT NULL DEFAULT 'realtime', "
      'finalize_error TEXT, audio_status TEXT NOT NULL DEFAULT \'none\', audio_key TEXT, '
      'audio_error TEXT, audio_bytes INTEGER NOT NULL DEFAULT 0, '
      "CHECK (status IN ('recording','stopped','minutes_ready')), "
      "CHECK (source IN ('microphone','upload')), "
      "CHECK (finalize_status IN ('none','pending','done','failed')), "
      "CHECK (transcript_source IN ('realtime','filetrans')), "
      "CHECK (audio_status IN ('none','uploading','done','failed')))",
];

/// v1 → v2 迁移语句（IMPORT-PIPELINE-DESIGN §5.2；按序执行）。
///
/// 为什么必须重建表：v1 DDL 有 `CHECK (source IN ('microphone','upload'))`，
/// SQLite 不能修改 CHECK 约束，只能建新表 → 拷贝 → 换名。
///
/// 顺序要点（drift 的 onUpgrade **不在事务中**执行，PRAGMA 生效）：
/// 1. `foreign_keys=OFF`：`DROP TABLE meetings` 会触发隐式 DELETE，
///    FK 开启时会级联清空 `transcript_segments` / `speakers` / `filetrans_raw`；
/// 2. 拷贝时新列给默认值（`'none'`, NULL），对既有行零影响；
/// 3. 重建索引 + `foreign_key_check` 自检 + 恢复 FK。
const List<String> kUpgradeV2Statements = <String>[
  'PRAGMA foreign_keys = OFF',
  'CREATE TABLE meetings_new (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
      'created_at TEXT NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0, '
      'sample_rate INTEGER NOT NULL DEFAULT 16000, speaker_count INTEGER NOT NULL DEFAULT 0, '
      'minutes_md TEXT, minutes_partial INTEGER NOT NULL DEFAULT 0, minutes_error TEXT, '
      "status TEXT NOT NULL DEFAULT 'recording', source TEXT NOT NULL DEFAULT 'microphone', "
      "finalize_status TEXT NOT NULL DEFAULT 'none', transcript_source TEXT NOT NULL DEFAULT 'realtime', "
      'finalize_error TEXT, audio_status TEXT NOT NULL DEFAULT \'none\', audio_key TEXT, '
      'audio_error TEXT, audio_bytes INTEGER NOT NULL DEFAULT 0, '
      "import_status TEXT NOT NULL DEFAULT 'none', import_error TEXT, "
      'import_task_id TEXT, import_meta_json TEXT, '
      "CHECK (status IN ('recording','stopped','minutes_ready')), "
      "CHECK (source IN ('microphone','upload','imported')), "
      "CHECK (finalize_status IN ('none','pending','done','failed')), "
      "CHECK (transcript_source IN ('realtime','filetrans')), "
      "CHECK (audio_status IN ('none','uploading','done','failed')), "
      "CHECK (import_status IN ('none','import_pending','extracting','transcribing','minutes','done','failed')))",
  'INSERT INTO meetings_new (id, title, created_at, duration_ms, sample_rate, '
      'speaker_count, minutes_md, minutes_partial, minutes_error, status, source, '
      'finalize_status, transcript_source, finalize_error, audio_status, audio_key, '
      'audio_error, audio_bytes, import_status, import_error, import_task_id, import_meta_json) '
      'SELECT id, title, created_at, duration_ms, sample_rate, speaker_count, '
      'minutes_md, minutes_partial, minutes_error, status, source, '
      'finalize_status, transcript_source, finalize_error, audio_status, audio_key, '
      "audio_error, audio_bytes, 'none', NULL, NULL, NULL FROM meetings",
  'DROP TABLE meetings',
  'ALTER TABLE meetings_new RENAME TO meetings',
  'CREATE INDEX IF NOT EXISTS idx_meetings_created_at ON meetings(created_at DESC)',
  'PRAGMA foreign_key_check',
  'PRAGMA foreign_keys = ON',
];
