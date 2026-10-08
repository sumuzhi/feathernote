// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MeetingsTable extends Meetings
    with TableInfo<$MeetingsTable, MeetingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeetingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sampleRateMeta = const VerificationMeta(
    'sampleRate',
  );
  @override
  late final GeneratedColumn<int> sampleRate = GeneratedColumn<int>(
    'sample_rate',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(16000),
  );
  static const VerificationMeta _speakerCountMeta = const VerificationMeta(
    'speakerCount',
  );
  @override
  late final GeneratedColumn<int> speakerCount = GeneratedColumn<int>(
    'speaker_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _minutesMdMeta = const VerificationMeta(
    'minutesMd',
  );
  @override
  late final GeneratedColumn<String> minutesMd = GeneratedColumn<String>(
    'minutes_md',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minutesPartialMeta = const VerificationMeta(
    'minutesPartial',
  );
  @override
  late final GeneratedColumn<int> minutesPartial = GeneratedColumn<int>(
    'minutes_partial',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _minutesErrorMeta = const VerificationMeta(
    'minutesError',
  );
  @override
  late final GeneratedColumn<String> minutesError = GeneratedColumn<String>(
    'minutes_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('recording'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('microphone'),
  );
  static const VerificationMeta _finalizeStatusMeta = const VerificationMeta(
    'finalizeStatus',
  );
  @override
  late final GeneratedColumn<String> finalizeStatus = GeneratedColumn<String>(
    'finalize_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _transcriptSourceMeta = const VerificationMeta(
    'transcriptSource',
  );
  @override
  late final GeneratedColumn<String> transcriptSource = GeneratedColumn<String>(
    'transcript_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('realtime'),
  );
  static const VerificationMeta _finalizeErrorMeta = const VerificationMeta(
    'finalizeError',
  );
  @override
  late final GeneratedColumn<String> finalizeError = GeneratedColumn<String>(
    'finalize_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioStatusMeta = const VerificationMeta(
    'audioStatus',
  );
  @override
  late final GeneratedColumn<String> audioStatus = GeneratedColumn<String>(
    'audio_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _audioKeyMeta = const VerificationMeta(
    'audioKey',
  );
  @override
  late final GeneratedColumn<String> audioKey = GeneratedColumn<String>(
    'audio_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioErrorMeta = const VerificationMeta(
    'audioError',
  );
  @override
  late final GeneratedColumn<String> audioError = GeneratedColumn<String>(
    'audio_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioBytesMeta = const VerificationMeta(
    'audioBytes',
  );
  @override
  late final GeneratedColumn<int> audioBytes = GeneratedColumn<int>(
    'audio_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _importStatusMeta = const VerificationMeta(
    'importStatus',
  );
  @override
  late final GeneratedColumn<String> importStatus = GeneratedColumn<String>(
    'import_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _importErrorMeta = const VerificationMeta(
    'importError',
  );
  @override
  late final GeneratedColumn<String> importError = GeneratedColumn<String>(
    'import_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importTaskIdMeta = const VerificationMeta(
    'importTaskId',
  );
  @override
  late final GeneratedColumn<String> importTaskId = GeneratedColumn<String>(
    'import_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importMetaJsonMeta = const VerificationMeta(
    'importMetaJson',
  );
  @override
  late final GeneratedColumn<String> importMetaJson = GeneratedColumn<String>(
    'import_meta_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAt,
    durationMs,
    sampleRate,
    speakerCount,
    minutesMd,
    minutesPartial,
    minutesError,
    status,
    source,
    finalizeStatus,
    transcriptSource,
    finalizeError,
    audioStatus,
    audioKey,
    audioError,
    audioBytes,
    importStatus,
    importError,
    importTaskId,
    importMetaJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meetings';
  @override
  VerificationContext validateIntegrity(
    Insertable<MeetingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('sample_rate')) {
      context.handle(
        _sampleRateMeta,
        sampleRate.isAcceptableOrUnknown(data['sample_rate']!, _sampleRateMeta),
      );
    }
    if (data.containsKey('speaker_count')) {
      context.handle(
        _speakerCountMeta,
        speakerCount.isAcceptableOrUnknown(
          data['speaker_count']!,
          _speakerCountMeta,
        ),
      );
    }
    if (data.containsKey('minutes_md')) {
      context.handle(
        _minutesMdMeta,
        minutesMd.isAcceptableOrUnknown(data['minutes_md']!, _minutesMdMeta),
      );
    }
    if (data.containsKey('minutes_partial')) {
      context.handle(
        _minutesPartialMeta,
        minutesPartial.isAcceptableOrUnknown(
          data['minutes_partial']!,
          _minutesPartialMeta,
        ),
      );
    }
    if (data.containsKey('minutes_error')) {
      context.handle(
        _minutesErrorMeta,
        minutesError.isAcceptableOrUnknown(
          data['minutes_error']!,
          _minutesErrorMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('finalize_status')) {
      context.handle(
        _finalizeStatusMeta,
        finalizeStatus.isAcceptableOrUnknown(
          data['finalize_status']!,
          _finalizeStatusMeta,
        ),
      );
    }
    if (data.containsKey('transcript_source')) {
      context.handle(
        _transcriptSourceMeta,
        transcriptSource.isAcceptableOrUnknown(
          data['transcript_source']!,
          _transcriptSourceMeta,
        ),
      );
    }
    if (data.containsKey('finalize_error')) {
      context.handle(
        _finalizeErrorMeta,
        finalizeError.isAcceptableOrUnknown(
          data['finalize_error']!,
          _finalizeErrorMeta,
        ),
      );
    }
    if (data.containsKey('audio_status')) {
      context.handle(
        _audioStatusMeta,
        audioStatus.isAcceptableOrUnknown(
          data['audio_status']!,
          _audioStatusMeta,
        ),
      );
    }
    if (data.containsKey('audio_key')) {
      context.handle(
        _audioKeyMeta,
        audioKey.isAcceptableOrUnknown(data['audio_key']!, _audioKeyMeta),
      );
    }
    if (data.containsKey('audio_error')) {
      context.handle(
        _audioErrorMeta,
        audioError.isAcceptableOrUnknown(data['audio_error']!, _audioErrorMeta),
      );
    }
    if (data.containsKey('audio_bytes')) {
      context.handle(
        _audioBytesMeta,
        audioBytes.isAcceptableOrUnknown(data['audio_bytes']!, _audioBytesMeta),
      );
    }
    if (data.containsKey('import_status')) {
      context.handle(
        _importStatusMeta,
        importStatus.isAcceptableOrUnknown(
          data['import_status']!,
          _importStatusMeta,
        ),
      );
    }
    if (data.containsKey('import_error')) {
      context.handle(
        _importErrorMeta,
        importError.isAcceptableOrUnknown(
          data['import_error']!,
          _importErrorMeta,
        ),
      );
    }
    if (data.containsKey('import_task_id')) {
      context.handle(
        _importTaskIdMeta,
        importTaskId.isAcceptableOrUnknown(
          data['import_task_id']!,
          _importTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('import_meta_json')) {
      context.handle(
        _importMetaJsonMeta,
        importMetaJson.isAcceptableOrUnknown(
          data['import_meta_json']!,
          _importMetaJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MeetingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeetingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      sampleRate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_rate'],
      )!,
      speakerCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}speaker_count'],
      )!,
      minutesMd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}minutes_md'],
      ),
      minutesPartial: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minutes_partial'],
      )!,
      minutesError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}minutes_error'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      finalizeStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finalize_status'],
      )!,
      transcriptSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcript_source'],
      )!,
      finalizeError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finalize_error'],
      ),
      audioStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_status'],
      )!,
      audioKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_key'],
      ),
      audioError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_error'],
      ),
      audioBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_bytes'],
      )!,
      importStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_status'],
      )!,
      importError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_error'],
      ),
      importTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_task_id'],
      ),
      importMetaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_meta_json'],
      ),
    );
  }

  @override
  $MeetingsTable createAlias(String alias) {
    return $MeetingsTable(attachedDatabase, alias);
  }
}

class MeetingRow extends DataClass implements Insertable<MeetingRow> {
  /// 会议 ID（`mtg_...`）。
  final String id;

  /// 标题。
  final String title;

  /// 创建时间（ISO 8601 UTC）。
  final String createdAt;

  /// 时长（毫秒）。
  final int durationMs;

  /// 实际采样率。
  final int sampleRate;

  /// 说话人数量。
  final int speakerCount;

  /// 纪要 Markdown。
  final String? minutesMd;

  /// 纪要是否为残篇（0/1）。
  final int minutesPartial;

  /// 纪要生成失败原因。
  final String? minutesError;

  /// 状态：`recording` / `stopped` / `minutes_ready`。
  final String status;

  /// 来源：`microphone` / `upload`。
  final String source;

  /// 终稿状态。
  final String finalizeStatus;

  /// 逐字稿来源。
  final String transcriptSource;

  /// 终稿失败原因。
  final String? finalizeError;

  /// 音频归档状态。
  final String audioStatus;

  /// 归档 key / 本地路径。
  final String? audioKey;

  /// 归档失败原因。
  final String? audioError;

  /// 音频字节数。
  final int audioBytes;

  /// 导入处理状态（`none` / `import_pending` / `extracting` / `transcribing` /
  /// `minutes` / `done` / `failed`）。
  final String importStatus;

  /// 导入失败 / 取消原因。
  final String? importError;

  /// filetrans 任务 ID（恢复轮询用）。
  final String? importTaskId;

  /// 导入元信息 JSON（srcName / srcPath / kind / sizeBytes / durationMs / extractedPath）。
  final String? importMetaJson;
  const MeetingRow({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.sampleRate,
    required this.speakerCount,
    this.minutesMd,
    required this.minutesPartial,
    this.minutesError,
    required this.status,
    required this.source,
    required this.finalizeStatus,
    required this.transcriptSource,
    this.finalizeError,
    required this.audioStatus,
    this.audioKey,
    this.audioError,
    required this.audioBytes,
    required this.importStatus,
    this.importError,
    this.importTaskId,
    this.importMetaJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<String>(createdAt);
    map['duration_ms'] = Variable<int>(durationMs);
    map['sample_rate'] = Variable<int>(sampleRate);
    map['speaker_count'] = Variable<int>(speakerCount);
    if (!nullToAbsent || minutesMd != null) {
      map['minutes_md'] = Variable<String>(minutesMd);
    }
    map['minutes_partial'] = Variable<int>(minutesPartial);
    if (!nullToAbsent || minutesError != null) {
      map['minutes_error'] = Variable<String>(minutesError);
    }
    map['status'] = Variable<String>(status);
    map['source'] = Variable<String>(source);
    map['finalize_status'] = Variable<String>(finalizeStatus);
    map['transcript_source'] = Variable<String>(transcriptSource);
    if (!nullToAbsent || finalizeError != null) {
      map['finalize_error'] = Variable<String>(finalizeError);
    }
    map['audio_status'] = Variable<String>(audioStatus);
    if (!nullToAbsent || audioKey != null) {
      map['audio_key'] = Variable<String>(audioKey);
    }
    if (!nullToAbsent || audioError != null) {
      map['audio_error'] = Variable<String>(audioError);
    }
    map['audio_bytes'] = Variable<int>(audioBytes);
    map['import_status'] = Variable<String>(importStatus);
    if (!nullToAbsent || importError != null) {
      map['import_error'] = Variable<String>(importError);
    }
    if (!nullToAbsent || importTaskId != null) {
      map['import_task_id'] = Variable<String>(importTaskId);
    }
    if (!nullToAbsent || importMetaJson != null) {
      map['import_meta_json'] = Variable<String>(importMetaJson);
    }
    return map;
  }

  MeetingsCompanion toCompanion(bool nullToAbsent) {
    return MeetingsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      durationMs: Value(durationMs),
      sampleRate: Value(sampleRate),
      speakerCount: Value(speakerCount),
      minutesMd: minutesMd == null && nullToAbsent
          ? const Value.absent()
          : Value(minutesMd),
      minutesPartial: Value(minutesPartial),
      minutesError: minutesError == null && nullToAbsent
          ? const Value.absent()
          : Value(minutesError),
      status: Value(status),
      source: Value(source),
      finalizeStatus: Value(finalizeStatus),
      transcriptSource: Value(transcriptSource),
      finalizeError: finalizeError == null && nullToAbsent
          ? const Value.absent()
          : Value(finalizeError),
      audioStatus: Value(audioStatus),
      audioKey: audioKey == null && nullToAbsent
          ? const Value.absent()
          : Value(audioKey),
      audioError: audioError == null && nullToAbsent
          ? const Value.absent()
          : Value(audioError),
      audioBytes: Value(audioBytes),
      importStatus: Value(importStatus),
      importError: importError == null && nullToAbsent
          ? const Value.absent()
          : Value(importError),
      importTaskId: importTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(importTaskId),
      importMetaJson: importMetaJson == null && nullToAbsent
          ? const Value.absent()
          : Value(importMetaJson),
    );
  }

  factory MeetingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeetingRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      sampleRate: serializer.fromJson<int>(json['sampleRate']),
      speakerCount: serializer.fromJson<int>(json['speakerCount']),
      minutesMd: serializer.fromJson<String?>(json['minutesMd']),
      minutesPartial: serializer.fromJson<int>(json['minutesPartial']),
      minutesError: serializer.fromJson<String?>(json['minutesError']),
      status: serializer.fromJson<String>(json['status']),
      source: serializer.fromJson<String>(json['source']),
      finalizeStatus: serializer.fromJson<String>(json['finalizeStatus']),
      transcriptSource: serializer.fromJson<String>(json['transcriptSource']),
      finalizeError: serializer.fromJson<String?>(json['finalizeError']),
      audioStatus: serializer.fromJson<String>(json['audioStatus']),
      audioKey: serializer.fromJson<String?>(json['audioKey']),
      audioError: serializer.fromJson<String?>(json['audioError']),
      audioBytes: serializer.fromJson<int>(json['audioBytes']),
      importStatus: serializer.fromJson<String>(json['importStatus']),
      importError: serializer.fromJson<String?>(json['importError']),
      importTaskId: serializer.fromJson<String?>(json['importTaskId']),
      importMetaJson: serializer.fromJson<String?>(json['importMetaJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<String>(createdAt),
      'durationMs': serializer.toJson<int>(durationMs),
      'sampleRate': serializer.toJson<int>(sampleRate),
      'speakerCount': serializer.toJson<int>(speakerCount),
      'minutesMd': serializer.toJson<String?>(minutesMd),
      'minutesPartial': serializer.toJson<int>(minutesPartial),
      'minutesError': serializer.toJson<String?>(minutesError),
      'status': serializer.toJson<String>(status),
      'source': serializer.toJson<String>(source),
      'finalizeStatus': serializer.toJson<String>(finalizeStatus),
      'transcriptSource': serializer.toJson<String>(transcriptSource),
      'finalizeError': serializer.toJson<String?>(finalizeError),
      'audioStatus': serializer.toJson<String>(audioStatus),
      'audioKey': serializer.toJson<String?>(audioKey),
      'audioError': serializer.toJson<String?>(audioError),
      'audioBytes': serializer.toJson<int>(audioBytes),
      'importStatus': serializer.toJson<String>(importStatus),
      'importError': serializer.toJson<String?>(importError),
      'importTaskId': serializer.toJson<String?>(importTaskId),
      'importMetaJson': serializer.toJson<String?>(importMetaJson),
    };
  }

  MeetingRow copyWith({
    String? id,
    String? title,
    String? createdAt,
    int? durationMs,
    int? sampleRate,
    int? speakerCount,
    Value<String?> minutesMd = const Value.absent(),
    int? minutesPartial,
    Value<String?> minutesError = const Value.absent(),
    String? status,
    String? source,
    String? finalizeStatus,
    String? transcriptSource,
    Value<String?> finalizeError = const Value.absent(),
    String? audioStatus,
    Value<String?> audioKey = const Value.absent(),
    Value<String?> audioError = const Value.absent(),
    int? audioBytes,
    String? importStatus,
    Value<String?> importError = const Value.absent(),
    Value<String?> importTaskId = const Value.absent(),
    Value<String?> importMetaJson = const Value.absent(),
  }) => MeetingRow(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    durationMs: durationMs ?? this.durationMs,
    sampleRate: sampleRate ?? this.sampleRate,
    speakerCount: speakerCount ?? this.speakerCount,
    minutesMd: minutesMd.present ? minutesMd.value : this.minutesMd,
    minutesPartial: minutesPartial ?? this.minutesPartial,
    minutesError: minutesError.present ? minutesError.value : this.minutesError,
    status: status ?? this.status,
    source: source ?? this.source,
    finalizeStatus: finalizeStatus ?? this.finalizeStatus,
    transcriptSource: transcriptSource ?? this.transcriptSource,
    finalizeError: finalizeError.present
        ? finalizeError.value
        : this.finalizeError,
    audioStatus: audioStatus ?? this.audioStatus,
    audioKey: audioKey.present ? audioKey.value : this.audioKey,
    audioError: audioError.present ? audioError.value : this.audioError,
    audioBytes: audioBytes ?? this.audioBytes,
    importStatus: importStatus ?? this.importStatus,
    importError: importError.present ? importError.value : this.importError,
    importTaskId: importTaskId.present ? importTaskId.value : this.importTaskId,
    importMetaJson: importMetaJson.present
        ? importMetaJson.value
        : this.importMetaJson,
  );
  MeetingRow copyWithCompanion(MeetingsCompanion data) {
    return MeetingRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      sampleRate: data.sampleRate.present
          ? data.sampleRate.value
          : this.sampleRate,
      speakerCount: data.speakerCount.present
          ? data.speakerCount.value
          : this.speakerCount,
      minutesMd: data.minutesMd.present ? data.minutesMd.value : this.minutesMd,
      minutesPartial: data.minutesPartial.present
          ? data.minutesPartial.value
          : this.minutesPartial,
      minutesError: data.minutesError.present
          ? data.minutesError.value
          : this.minutesError,
      status: data.status.present ? data.status.value : this.status,
      source: data.source.present ? data.source.value : this.source,
      finalizeStatus: data.finalizeStatus.present
          ? data.finalizeStatus.value
          : this.finalizeStatus,
      transcriptSource: data.transcriptSource.present
          ? data.transcriptSource.value
          : this.transcriptSource,
      finalizeError: data.finalizeError.present
          ? data.finalizeError.value
          : this.finalizeError,
      audioStatus: data.audioStatus.present
          ? data.audioStatus.value
          : this.audioStatus,
      audioKey: data.audioKey.present ? data.audioKey.value : this.audioKey,
      audioError: data.audioError.present
          ? data.audioError.value
          : this.audioError,
      audioBytes: data.audioBytes.present
          ? data.audioBytes.value
          : this.audioBytes,
      importStatus: data.importStatus.present
          ? data.importStatus.value
          : this.importStatus,
      importError: data.importError.present
          ? data.importError.value
          : this.importError,
      importTaskId: data.importTaskId.present
          ? data.importTaskId.value
          : this.importTaskId,
      importMetaJson: data.importMetaJson.present
          ? data.importMetaJson.value
          : this.importMetaJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeetingRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('speakerCount: $speakerCount, ')
          ..write('minutesMd: $minutesMd, ')
          ..write('minutesPartial: $minutesPartial, ')
          ..write('minutesError: $minutesError, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('finalizeStatus: $finalizeStatus, ')
          ..write('transcriptSource: $transcriptSource, ')
          ..write('finalizeError: $finalizeError, ')
          ..write('audioStatus: $audioStatus, ')
          ..write('audioKey: $audioKey, ')
          ..write('audioError: $audioError, ')
          ..write('audioBytes: $audioBytes, ')
          ..write('importStatus: $importStatus, ')
          ..write('importError: $importError, ')
          ..write('importTaskId: $importTaskId, ')
          ..write('importMetaJson: $importMetaJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    createdAt,
    durationMs,
    sampleRate,
    speakerCount,
    minutesMd,
    minutesPartial,
    minutesError,
    status,
    source,
    finalizeStatus,
    transcriptSource,
    finalizeError,
    audioStatus,
    audioKey,
    audioError,
    audioBytes,
    importStatus,
    importError,
    importTaskId,
    importMetaJson,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeetingRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.durationMs == this.durationMs &&
          other.sampleRate == this.sampleRate &&
          other.speakerCount == this.speakerCount &&
          other.minutesMd == this.minutesMd &&
          other.minutesPartial == this.minutesPartial &&
          other.minutesError == this.minutesError &&
          other.status == this.status &&
          other.source == this.source &&
          other.finalizeStatus == this.finalizeStatus &&
          other.transcriptSource == this.transcriptSource &&
          other.finalizeError == this.finalizeError &&
          other.audioStatus == this.audioStatus &&
          other.audioKey == this.audioKey &&
          other.audioError == this.audioError &&
          other.audioBytes == this.audioBytes &&
          other.importStatus == this.importStatus &&
          other.importError == this.importError &&
          other.importTaskId == this.importTaskId &&
          other.importMetaJson == this.importMetaJson);
}

class MeetingsCompanion extends UpdateCompanion<MeetingRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> createdAt;
  final Value<int> durationMs;
  final Value<int> sampleRate;
  final Value<int> speakerCount;
  final Value<String?> minutesMd;
  final Value<int> minutesPartial;
  final Value<String?> minutesError;
  final Value<String> status;
  final Value<String> source;
  final Value<String> finalizeStatus;
  final Value<String> transcriptSource;
  final Value<String?> finalizeError;
  final Value<String> audioStatus;
  final Value<String?> audioKey;
  final Value<String?> audioError;
  final Value<int> audioBytes;
  final Value<String> importStatus;
  final Value<String?> importError;
  final Value<String?> importTaskId;
  final Value<String?> importMetaJson;
  final Value<int> rowid;
  const MeetingsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.speakerCount = const Value.absent(),
    this.minutesMd = const Value.absent(),
    this.minutesPartial = const Value.absent(),
    this.minutesError = const Value.absent(),
    this.status = const Value.absent(),
    this.source = const Value.absent(),
    this.finalizeStatus = const Value.absent(),
    this.transcriptSource = const Value.absent(),
    this.finalizeError = const Value.absent(),
    this.audioStatus = const Value.absent(),
    this.audioKey = const Value.absent(),
    this.audioError = const Value.absent(),
    this.audioBytes = const Value.absent(),
    this.importStatus = const Value.absent(),
    this.importError = const Value.absent(),
    this.importTaskId = const Value.absent(),
    this.importMetaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeetingsCompanion.insert({
    required String id,
    required String title,
    required String createdAt,
    this.durationMs = const Value.absent(),
    this.sampleRate = const Value.absent(),
    this.speakerCount = const Value.absent(),
    this.minutesMd = const Value.absent(),
    this.minutesPartial = const Value.absent(),
    this.minutesError = const Value.absent(),
    this.status = const Value.absent(),
    this.source = const Value.absent(),
    this.finalizeStatus = const Value.absent(),
    this.transcriptSource = const Value.absent(),
    this.finalizeError = const Value.absent(),
    this.audioStatus = const Value.absent(),
    this.audioKey = const Value.absent(),
    this.audioError = const Value.absent(),
    this.audioBytes = const Value.absent(),
    this.importStatus = const Value.absent(),
    this.importError = const Value.absent(),
    this.importTaskId = const Value.absent(),
    this.importMetaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<MeetingRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? createdAt,
    Expression<int>? durationMs,
    Expression<int>? sampleRate,
    Expression<int>? speakerCount,
    Expression<String>? minutesMd,
    Expression<int>? minutesPartial,
    Expression<String>? minutesError,
    Expression<String>? status,
    Expression<String>? source,
    Expression<String>? finalizeStatus,
    Expression<String>? transcriptSource,
    Expression<String>? finalizeError,
    Expression<String>? audioStatus,
    Expression<String>? audioKey,
    Expression<String>? audioError,
    Expression<int>? audioBytes,
    Expression<String>? importStatus,
    Expression<String>? importError,
    Expression<String>? importTaskId,
    Expression<String>? importMetaJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (speakerCount != null) 'speaker_count': speakerCount,
      if (minutesMd != null) 'minutes_md': minutesMd,
      if (minutesPartial != null) 'minutes_partial': minutesPartial,
      if (minutesError != null) 'minutes_error': minutesError,
      if (status != null) 'status': status,
      if (source != null) 'source': source,
      if (finalizeStatus != null) 'finalize_status': finalizeStatus,
      if (transcriptSource != null) 'transcript_source': transcriptSource,
      if (finalizeError != null) 'finalize_error': finalizeError,
      if (audioStatus != null) 'audio_status': audioStatus,
      if (audioKey != null) 'audio_key': audioKey,
      if (audioError != null) 'audio_error': audioError,
      if (audioBytes != null) 'audio_bytes': audioBytes,
      if (importStatus != null) 'import_status': importStatus,
      if (importError != null) 'import_error': importError,
      if (importTaskId != null) 'import_task_id': importTaskId,
      if (importMetaJson != null) 'import_meta_json': importMetaJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeetingsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? createdAt,
    Value<int>? durationMs,
    Value<int>? sampleRate,
    Value<int>? speakerCount,
    Value<String?>? minutesMd,
    Value<int>? minutesPartial,
    Value<String?>? minutesError,
    Value<String>? status,
    Value<String>? source,
    Value<String>? finalizeStatus,
    Value<String>? transcriptSource,
    Value<String?>? finalizeError,
    Value<String>? audioStatus,
    Value<String?>? audioKey,
    Value<String?>? audioError,
    Value<int>? audioBytes,
    Value<String>? importStatus,
    Value<String?>? importError,
    Value<String?>? importTaskId,
    Value<String?>? importMetaJson,
    Value<int>? rowid,
  }) {
    return MeetingsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      durationMs: durationMs ?? this.durationMs,
      sampleRate: sampleRate ?? this.sampleRate,
      speakerCount: speakerCount ?? this.speakerCount,
      minutesMd: minutesMd ?? this.minutesMd,
      minutesPartial: minutesPartial ?? this.minutesPartial,
      minutesError: minutesError ?? this.minutesError,
      status: status ?? this.status,
      source: source ?? this.source,
      finalizeStatus: finalizeStatus ?? this.finalizeStatus,
      transcriptSource: transcriptSource ?? this.transcriptSource,
      finalizeError: finalizeError ?? this.finalizeError,
      audioStatus: audioStatus ?? this.audioStatus,
      audioKey: audioKey ?? this.audioKey,
      audioError: audioError ?? this.audioError,
      audioBytes: audioBytes ?? this.audioBytes,
      importStatus: importStatus ?? this.importStatus,
      importError: importError ?? this.importError,
      importTaskId: importTaskId ?? this.importTaskId,
      importMetaJson: importMetaJson ?? this.importMetaJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sampleRate.present) {
      map['sample_rate'] = Variable<int>(sampleRate.value);
    }
    if (speakerCount.present) {
      map['speaker_count'] = Variable<int>(speakerCount.value);
    }
    if (minutesMd.present) {
      map['minutes_md'] = Variable<String>(minutesMd.value);
    }
    if (minutesPartial.present) {
      map['minutes_partial'] = Variable<int>(minutesPartial.value);
    }
    if (minutesError.present) {
      map['minutes_error'] = Variable<String>(minutesError.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (finalizeStatus.present) {
      map['finalize_status'] = Variable<String>(finalizeStatus.value);
    }
    if (transcriptSource.present) {
      map['transcript_source'] = Variable<String>(transcriptSource.value);
    }
    if (finalizeError.present) {
      map['finalize_error'] = Variable<String>(finalizeError.value);
    }
    if (audioStatus.present) {
      map['audio_status'] = Variable<String>(audioStatus.value);
    }
    if (audioKey.present) {
      map['audio_key'] = Variable<String>(audioKey.value);
    }
    if (audioError.present) {
      map['audio_error'] = Variable<String>(audioError.value);
    }
    if (audioBytes.present) {
      map['audio_bytes'] = Variable<int>(audioBytes.value);
    }
    if (importStatus.present) {
      map['import_status'] = Variable<String>(importStatus.value);
    }
    if (importError.present) {
      map['import_error'] = Variable<String>(importError.value);
    }
    if (importTaskId.present) {
      map['import_task_id'] = Variable<String>(importTaskId.value);
    }
    if (importMetaJson.present) {
      map['import_meta_json'] = Variable<String>(importMetaJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeetingsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('sampleRate: $sampleRate, ')
          ..write('speakerCount: $speakerCount, ')
          ..write('minutesMd: $minutesMd, ')
          ..write('minutesPartial: $minutesPartial, ')
          ..write('minutesError: $minutesError, ')
          ..write('status: $status, ')
          ..write('source: $source, ')
          ..write('finalizeStatus: $finalizeStatus, ')
          ..write('transcriptSource: $transcriptSource, ')
          ..write('finalizeError: $finalizeError, ')
          ..write('audioStatus: $audioStatus, ')
          ..write('audioKey: $audioKey, ')
          ..write('audioError: $audioError, ')
          ..write('audioBytes: $audioBytes, ')
          ..write('importStatus: $importStatus, ')
          ..write('importError: $importError, ')
          ..write('importTaskId: $importTaskId, ')
          ..write('importMetaJson: $importMetaJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TranscriptSegmentsTable extends TranscriptSegments
    with TableInfo<$TranscriptSegmentsTable, TranscriptSegmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TranscriptSegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _meetingIdMeta = const VerificationMeta(
    'meetingId',
  );
  @override
  late final GeneratedColumn<String> meetingId = GeneratedColumn<String>(
    'meeting_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meetings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _segmentIdMeta = const VerificationMeta(
    'segmentId',
  );
  @override
  late final GeneratedColumn<String> segmentId = GeneratedColumn<String>(
    'segment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speakerIdMeta = const VerificationMeta(
    'speakerId',
  );
  @override
  late final GeneratedColumn<String> speakerId = GeneratedColumn<String>(
    'speaker_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speakerNameMeta = const VerificationMeta(
    'speakerName',
  );
  @override
  late final GeneratedColumn<String> speakerName = GeneratedColumn<String>(
    'speaker_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _segmentTextMeta = const VerificationMeta(
    'segmentText',
  );
  @override
  late final GeneratedColumn<String> segmentText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<int> startTime = GeneratedColumn<int>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<int> endTime = GeneratedColumn<int>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.9),
  );
  static const VerificationMeta _seqStartMeta = const VerificationMeta(
    'seqStart',
  );
  @override
  late final GeneratedColumn<int> seqStart = GeneratedColumn<int>(
    'seq_start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _seqEndMeta = const VerificationMeta('seqEnd');
  @override
  late final GeneratedColumn<int> seqEnd = GeneratedColumn<int>(
    'seq_end',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    meetingId,
    segmentId,
    ordinal,
    speakerId,
    speakerName,
    segmentText,
    startTime,
    endTime,
    confidence,
    seqStart,
    seqEnd,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transcript_segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<TranscriptSegmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('meeting_id')) {
      context.handle(
        _meetingIdMeta,
        meetingId.isAcceptableOrUnknown(data['meeting_id']!, _meetingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_meetingIdMeta);
    }
    if (data.containsKey('segment_id')) {
      context.handle(
        _segmentIdMeta,
        segmentId.isAcceptableOrUnknown(data['segment_id']!, _segmentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_segmentIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('speaker_id')) {
      context.handle(
        _speakerIdMeta,
        speakerId.isAcceptableOrUnknown(data['speaker_id']!, _speakerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_speakerIdMeta);
    }
    if (data.containsKey('speaker_name')) {
      context.handle(
        _speakerNameMeta,
        speakerName.isAcceptableOrUnknown(
          data['speaker_name']!,
          _speakerNameMeta,
        ),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _segmentTextMeta,
        segmentText.isAcceptableOrUnknown(data['text']!, _segmentTextMeta),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('seq_start')) {
      context.handle(
        _seqStartMeta,
        seqStart.isAcceptableOrUnknown(data['seq_start']!, _seqStartMeta),
      );
    }
    if (data.containsKey('seq_end')) {
      context.handle(
        _seqEndMeta,
        seqEnd.isAcceptableOrUnknown(data['seq_end']!, _seqEndMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {meetingId, segmentId};
  @override
  TranscriptSegmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TranscriptSegmentRow(
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meeting_id'],
      )!,
      segmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}segment_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      speakerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speaker_id'],
      )!,
      speakerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speaker_name'],
      ),
      segmentText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      seqStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq_start'],
      )!,
      seqEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq_end'],
      )!,
    );
  }

  @override
  $TranscriptSegmentsTable createAlias(String alias) {
    return $TranscriptSegmentsTable(attachedDatabase, alias);
  }
}

class TranscriptSegmentRow extends DataClass
    implements Insertable<TranscriptSegmentRow> {
  /// 所属会议 ID。
  final String meetingId;

  /// 片段 ID（会议内唯一）。
  final String segmentId;

  /// 排序序号。
  final int ordinal;

  /// 说话人 ID。
  final String speakerId;

  /// 说话人展示名（可空）。
  final String? speakerName;

  /// 文本（落库列名 `text`）。
  final String segmentText;

  /// 起始时间（毫秒）。
  final int startTime;

  /// 结束时间（毫秒）。
  final int endTime;

  /// 置信度。
  final double confidence;

  /// 起始帧序号。
  final int seqStart;

  /// 结束帧序号。
  final int seqEnd;
  const TranscriptSegmentRow({
    required this.meetingId,
    required this.segmentId,
    required this.ordinal,
    required this.speakerId,
    this.speakerName,
    required this.segmentText,
    required this.startTime,
    required this.endTime,
    required this.confidence,
    required this.seqStart,
    required this.seqEnd,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['meeting_id'] = Variable<String>(meetingId);
    map['segment_id'] = Variable<String>(segmentId);
    map['ordinal'] = Variable<int>(ordinal);
    map['speaker_id'] = Variable<String>(speakerId);
    if (!nullToAbsent || speakerName != null) {
      map['speaker_name'] = Variable<String>(speakerName);
    }
    map['text'] = Variable<String>(segmentText);
    map['start_time'] = Variable<int>(startTime);
    map['end_time'] = Variable<int>(endTime);
    map['confidence'] = Variable<double>(confidence);
    map['seq_start'] = Variable<int>(seqStart);
    map['seq_end'] = Variable<int>(seqEnd);
    return map;
  }

  TranscriptSegmentsCompanion toCompanion(bool nullToAbsent) {
    return TranscriptSegmentsCompanion(
      meetingId: Value(meetingId),
      segmentId: Value(segmentId),
      ordinal: Value(ordinal),
      speakerId: Value(speakerId),
      speakerName: speakerName == null && nullToAbsent
          ? const Value.absent()
          : Value(speakerName),
      segmentText: Value(segmentText),
      startTime: Value(startTime),
      endTime: Value(endTime),
      confidence: Value(confidence),
      seqStart: Value(seqStart),
      seqEnd: Value(seqEnd),
    );
  }

  factory TranscriptSegmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TranscriptSegmentRow(
      meetingId: serializer.fromJson<String>(json['meetingId']),
      segmentId: serializer.fromJson<String>(json['segmentId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      speakerId: serializer.fromJson<String>(json['speakerId']),
      speakerName: serializer.fromJson<String?>(json['speakerName']),
      segmentText: serializer.fromJson<String>(json['segmentText']),
      startTime: serializer.fromJson<int>(json['startTime']),
      endTime: serializer.fromJson<int>(json['endTime']),
      confidence: serializer.fromJson<double>(json['confidence']),
      seqStart: serializer.fromJson<int>(json['seqStart']),
      seqEnd: serializer.fromJson<int>(json['seqEnd']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'meetingId': serializer.toJson<String>(meetingId),
      'segmentId': serializer.toJson<String>(segmentId),
      'ordinal': serializer.toJson<int>(ordinal),
      'speakerId': serializer.toJson<String>(speakerId),
      'speakerName': serializer.toJson<String?>(speakerName),
      'segmentText': serializer.toJson<String>(segmentText),
      'startTime': serializer.toJson<int>(startTime),
      'endTime': serializer.toJson<int>(endTime),
      'confidence': serializer.toJson<double>(confidence),
      'seqStart': serializer.toJson<int>(seqStart),
      'seqEnd': serializer.toJson<int>(seqEnd),
    };
  }

  TranscriptSegmentRow copyWith({
    String? meetingId,
    String? segmentId,
    int? ordinal,
    String? speakerId,
    Value<String?> speakerName = const Value.absent(),
    String? segmentText,
    int? startTime,
    int? endTime,
    double? confidence,
    int? seqStart,
    int? seqEnd,
  }) => TranscriptSegmentRow(
    meetingId: meetingId ?? this.meetingId,
    segmentId: segmentId ?? this.segmentId,
    ordinal: ordinal ?? this.ordinal,
    speakerId: speakerId ?? this.speakerId,
    speakerName: speakerName.present ? speakerName.value : this.speakerName,
    segmentText: segmentText ?? this.segmentText,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    confidence: confidence ?? this.confidence,
    seqStart: seqStart ?? this.seqStart,
    seqEnd: seqEnd ?? this.seqEnd,
  );
  TranscriptSegmentRow copyWithCompanion(TranscriptSegmentsCompanion data) {
    return TranscriptSegmentRow(
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      segmentId: data.segmentId.present ? data.segmentId.value : this.segmentId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      speakerId: data.speakerId.present ? data.speakerId.value : this.speakerId,
      speakerName: data.speakerName.present
          ? data.speakerName.value
          : this.speakerName,
      segmentText: data.segmentText.present
          ? data.segmentText.value
          : this.segmentText,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      seqStart: data.seqStart.present ? data.seqStart.value : this.seqStart,
      seqEnd: data.seqEnd.present ? data.seqEnd.value : this.seqEnd,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptSegmentRow(')
          ..write('meetingId: $meetingId, ')
          ..write('segmentId: $segmentId, ')
          ..write('ordinal: $ordinal, ')
          ..write('speakerId: $speakerId, ')
          ..write('speakerName: $speakerName, ')
          ..write('segmentText: $segmentText, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('confidence: $confidence, ')
          ..write('seqStart: $seqStart, ')
          ..write('seqEnd: $seqEnd')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    meetingId,
    segmentId,
    ordinal,
    speakerId,
    speakerName,
    segmentText,
    startTime,
    endTime,
    confidence,
    seqStart,
    seqEnd,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptSegmentRow &&
          other.meetingId == this.meetingId &&
          other.segmentId == this.segmentId &&
          other.ordinal == this.ordinal &&
          other.speakerId == this.speakerId &&
          other.speakerName == this.speakerName &&
          other.segmentText == this.segmentText &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.confidence == this.confidence &&
          other.seqStart == this.seqStart &&
          other.seqEnd == this.seqEnd);
}

class TranscriptSegmentsCompanion
    extends UpdateCompanion<TranscriptSegmentRow> {
  final Value<String> meetingId;
  final Value<String> segmentId;
  final Value<int> ordinal;
  final Value<String> speakerId;
  final Value<String?> speakerName;
  final Value<String> segmentText;
  final Value<int> startTime;
  final Value<int> endTime;
  final Value<double> confidence;
  final Value<int> seqStart;
  final Value<int> seqEnd;
  final Value<int> rowid;
  const TranscriptSegmentsCompanion({
    this.meetingId = const Value.absent(),
    this.segmentId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.speakerId = const Value.absent(),
    this.speakerName = const Value.absent(),
    this.segmentText = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.confidence = const Value.absent(),
    this.seqStart = const Value.absent(),
    this.seqEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TranscriptSegmentsCompanion.insert({
    required String meetingId,
    required String segmentId,
    required int ordinal,
    required String speakerId,
    this.speakerName = const Value.absent(),
    this.segmentText = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.confidence = const Value.absent(),
    this.seqStart = const Value.absent(),
    this.seqEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : meetingId = Value(meetingId),
       segmentId = Value(segmentId),
       ordinal = Value(ordinal),
       speakerId = Value(speakerId);
  static Insertable<TranscriptSegmentRow> custom({
    Expression<String>? meetingId,
    Expression<String>? segmentId,
    Expression<int>? ordinal,
    Expression<String>? speakerId,
    Expression<String>? speakerName,
    Expression<String>? segmentText,
    Expression<int>? startTime,
    Expression<int>? endTime,
    Expression<double>? confidence,
    Expression<int>? seqStart,
    Expression<int>? seqEnd,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (meetingId != null) 'meeting_id': meetingId,
      if (segmentId != null) 'segment_id': segmentId,
      if (ordinal != null) 'ordinal': ordinal,
      if (speakerId != null) 'speaker_id': speakerId,
      if (speakerName != null) 'speaker_name': speakerName,
      if (segmentText != null) 'text': segmentText,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (confidence != null) 'confidence': confidence,
      if (seqStart != null) 'seq_start': seqStart,
      if (seqEnd != null) 'seq_end': seqEnd,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TranscriptSegmentsCompanion copyWith({
    Value<String>? meetingId,
    Value<String>? segmentId,
    Value<int>? ordinal,
    Value<String>? speakerId,
    Value<String?>? speakerName,
    Value<String>? segmentText,
    Value<int>? startTime,
    Value<int>? endTime,
    Value<double>? confidence,
    Value<int>? seqStart,
    Value<int>? seqEnd,
    Value<int>? rowid,
  }) {
    return TranscriptSegmentsCompanion(
      meetingId: meetingId ?? this.meetingId,
      segmentId: segmentId ?? this.segmentId,
      ordinal: ordinal ?? this.ordinal,
      speakerId: speakerId ?? this.speakerId,
      speakerName: speakerName ?? this.speakerName,
      segmentText: segmentText ?? this.segmentText,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      confidence: confidence ?? this.confidence,
      seqStart: seqStart ?? this.seqStart,
      seqEnd: seqEnd ?? this.seqEnd,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (meetingId.present) {
      map['meeting_id'] = Variable<String>(meetingId.value);
    }
    if (segmentId.present) {
      map['segment_id'] = Variable<String>(segmentId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (speakerId.present) {
      map['speaker_id'] = Variable<String>(speakerId.value);
    }
    if (speakerName.present) {
      map['speaker_name'] = Variable<String>(speakerName.value);
    }
    if (segmentText.present) {
      map['text'] = Variable<String>(segmentText.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<int>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<int>(endTime.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (seqStart.present) {
      map['seq_start'] = Variable<int>(seqStart.value);
    }
    if (seqEnd.present) {
      map['seq_end'] = Variable<int>(seqEnd.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptSegmentsCompanion(')
          ..write('meetingId: $meetingId, ')
          ..write('segmentId: $segmentId, ')
          ..write('ordinal: $ordinal, ')
          ..write('speakerId: $speakerId, ')
          ..write('speakerName: $speakerName, ')
          ..write('segmentText: $segmentText, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('confidence: $confidence, ')
          ..write('seqStart: $seqStart, ')
          ..write('seqEnd: $seqEnd, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SpeakersTable extends Speakers
    with TableInfo<$SpeakersTable, SpeakerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpeakersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _meetingIdMeta = const VerificationMeta(
    'meetingId',
  );
  @override
  late final GeneratedColumn<String> meetingId = GeneratedColumn<String>(
    'meeting_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meetings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _speakerIdMeta = const VerificationMeta(
    'speakerId',
  );
  @override
  late final GeneratedColumn<String> speakerId = GeneratedColumn<String>(
    'speaker_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorIndexMeta = const VerificationMeta(
    'colorIndex',
  );
  @override
  late final GeneratedColumn<int> colorIndex = GeneratedColumn<int>(
    'color_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _firstSeenMsMeta = const VerificationMeta(
    'firstSeenMs',
  );
  @override
  late final GeneratedColumn<int> firstSeenMs = GeneratedColumn<int>(
    'first_seen_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    meetingId,
    speakerId,
    name,
    colorIndex,
    firstSeenMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'speakers';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpeakerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('meeting_id')) {
      context.handle(
        _meetingIdMeta,
        meetingId.isAcceptableOrUnknown(data['meeting_id']!, _meetingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_meetingIdMeta);
    }
    if (data.containsKey('speaker_id')) {
      context.handle(
        _speakerIdMeta,
        speakerId.isAcceptableOrUnknown(data['speaker_id']!, _speakerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_speakerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_index')) {
      context.handle(
        _colorIndexMeta,
        colorIndex.isAcceptableOrUnknown(data['color_index']!, _colorIndexMeta),
      );
    }
    if (data.containsKey('first_seen_ms')) {
      context.handle(
        _firstSeenMsMeta,
        firstSeenMs.isAcceptableOrUnknown(
          data['first_seen_ms']!,
          _firstSeenMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {meetingId, speakerId};
  @override
  SpeakerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpeakerRow(
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meeting_id'],
      )!,
      speakerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speaker_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_index'],
      )!,
      firstSeenMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_ms'],
      )!,
    );
  }

  @override
  $SpeakersTable createAlias(String alias) {
    return $SpeakersTable(attachedDatabase, alias);
  }
}

class SpeakerRow extends DataClass implements Insertable<SpeakerRow> {
  /// 所属会议 ID。
  final String meetingId;

  /// 说话人 ID（`spk_1` …）。
  final String speakerId;

  /// 展示名。
  final String name;

  /// 配色下标（0–5）。
  final int colorIndex;

  /// 首次出现时间（毫秒）。
  final int firstSeenMs;
  const SpeakerRow({
    required this.meetingId,
    required this.speakerId,
    required this.name,
    required this.colorIndex,
    required this.firstSeenMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['meeting_id'] = Variable<String>(meetingId);
    map['speaker_id'] = Variable<String>(speakerId);
    map['name'] = Variable<String>(name);
    map['color_index'] = Variable<int>(colorIndex);
    map['first_seen_ms'] = Variable<int>(firstSeenMs);
    return map;
  }

  SpeakersCompanion toCompanion(bool nullToAbsent) {
    return SpeakersCompanion(
      meetingId: Value(meetingId),
      speakerId: Value(speakerId),
      name: Value(name),
      colorIndex: Value(colorIndex),
      firstSeenMs: Value(firstSeenMs),
    );
  }

  factory SpeakerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpeakerRow(
      meetingId: serializer.fromJson<String>(json['meetingId']),
      speakerId: serializer.fromJson<String>(json['speakerId']),
      name: serializer.fromJson<String>(json['name']),
      colorIndex: serializer.fromJson<int>(json['colorIndex']),
      firstSeenMs: serializer.fromJson<int>(json['firstSeenMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'meetingId': serializer.toJson<String>(meetingId),
      'speakerId': serializer.toJson<String>(speakerId),
      'name': serializer.toJson<String>(name),
      'colorIndex': serializer.toJson<int>(colorIndex),
      'firstSeenMs': serializer.toJson<int>(firstSeenMs),
    };
  }

  SpeakerRow copyWith({
    String? meetingId,
    String? speakerId,
    String? name,
    int? colorIndex,
    int? firstSeenMs,
  }) => SpeakerRow(
    meetingId: meetingId ?? this.meetingId,
    speakerId: speakerId ?? this.speakerId,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
    firstSeenMs: firstSeenMs ?? this.firstSeenMs,
  );
  SpeakerRow copyWithCompanion(SpeakersCompanion data) {
    return SpeakerRow(
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      speakerId: data.speakerId.present ? data.speakerId.value : this.speakerId,
      name: data.name.present ? data.name.value : this.name,
      colorIndex: data.colorIndex.present
          ? data.colorIndex.value
          : this.colorIndex,
      firstSeenMs: data.firstSeenMs.present
          ? data.firstSeenMs.value
          : this.firstSeenMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpeakerRow(')
          ..write('meetingId: $meetingId, ')
          ..write('speakerId: $speakerId, ')
          ..write('name: $name, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('firstSeenMs: $firstSeenMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(meetingId, speakerId, name, colorIndex, firstSeenMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpeakerRow &&
          other.meetingId == this.meetingId &&
          other.speakerId == this.speakerId &&
          other.name == this.name &&
          other.colorIndex == this.colorIndex &&
          other.firstSeenMs == this.firstSeenMs);
}

class SpeakersCompanion extends UpdateCompanion<SpeakerRow> {
  final Value<String> meetingId;
  final Value<String> speakerId;
  final Value<String> name;
  final Value<int> colorIndex;
  final Value<int> firstSeenMs;
  final Value<int> rowid;
  const SpeakersCompanion({
    this.meetingId = const Value.absent(),
    this.speakerId = const Value.absent(),
    this.name = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.firstSeenMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpeakersCompanion.insert({
    required String meetingId,
    required String speakerId,
    required String name,
    this.colorIndex = const Value.absent(),
    this.firstSeenMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : meetingId = Value(meetingId),
       speakerId = Value(speakerId),
       name = Value(name);
  static Insertable<SpeakerRow> custom({
    Expression<String>? meetingId,
    Expression<String>? speakerId,
    Expression<String>? name,
    Expression<int>? colorIndex,
    Expression<int>? firstSeenMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (meetingId != null) 'meeting_id': meetingId,
      if (speakerId != null) 'speaker_id': speakerId,
      if (name != null) 'name': name,
      if (colorIndex != null) 'color_index': colorIndex,
      if (firstSeenMs != null) 'first_seen_ms': firstSeenMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpeakersCompanion copyWith({
    Value<String>? meetingId,
    Value<String>? speakerId,
    Value<String>? name,
    Value<int>? colorIndex,
    Value<int>? firstSeenMs,
    Value<int>? rowid,
  }) {
    return SpeakersCompanion(
      meetingId: meetingId ?? this.meetingId,
      speakerId: speakerId ?? this.speakerId,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      firstSeenMs: firstSeenMs ?? this.firstSeenMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (meetingId.present) {
      map['meeting_id'] = Variable<String>(meetingId.value);
    }
    if (speakerId.present) {
      map['speaker_id'] = Variable<String>(speakerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorIndex.present) {
      map['color_index'] = Variable<int>(colorIndex.value);
    }
    if (firstSeenMs.present) {
      map['first_seen_ms'] = Variable<int>(firstSeenMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpeakersCompanion(')
          ..write('meetingId: $meetingId, ')
          ..write('speakerId: $speakerId, ')
          ..write('name: $name, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('firstSeenMs: $firstSeenMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FiletransRawTable extends FiletransRaw
    with TableInfo<$FiletransRawTable, FiletransRawRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FiletransRawTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _meetingIdMeta = const VerificationMeta(
    'meetingId',
  );
  @override
  late final GeneratedColumn<String> meetingId = GeneratedColumn<String>(
    'meeting_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES meetings (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [meetingId, json, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'filetrans_raw';
  @override
  VerificationContext validateIntegrity(
    Insertable<FiletransRawRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('meeting_id')) {
      context.handle(
        _meetingIdMeta,
        meetingId.isAcceptableOrUnknown(data['meeting_id']!, _meetingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_meetingIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {meetingId};
  @override
  FiletransRawRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FiletransRawRow(
      meetingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meeting_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FiletransRawTable createAlias(String alias) {
    return $FiletransRawTable(attachedDatabase, alias);
  }
}

class FiletransRawRow extends DataClass implements Insertable<FiletransRawRow> {
  /// 所属会议 ID（主键）。
  final String meetingId;

  /// 原始 JSON 文本。
  final String json;

  /// 落库时间（ISO 8601 UTC）。
  final String createdAt;
  const FiletransRawRow({
    required this.meetingId,
    required this.json,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['meeting_id'] = Variable<String>(meetingId);
    map['json'] = Variable<String>(json);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  FiletransRawCompanion toCompanion(bool nullToAbsent) {
    return FiletransRawCompanion(
      meetingId: Value(meetingId),
      json: Value(json),
      createdAt: Value(createdAt),
    );
  }

  factory FiletransRawRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FiletransRawRow(
      meetingId: serializer.fromJson<String>(json['meetingId']),
      json: serializer.fromJson<String>(json['json']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'meetingId': serializer.toJson<String>(meetingId),
      'json': serializer.toJson<String>(json),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  FiletransRawRow copyWith({
    String? meetingId,
    String? json,
    String? createdAt,
  }) => FiletransRawRow(
    meetingId: meetingId ?? this.meetingId,
    json: json ?? this.json,
    createdAt: createdAt ?? this.createdAt,
  );
  FiletransRawRow copyWithCompanion(FiletransRawCompanion data) {
    return FiletransRawRow(
      meetingId: data.meetingId.present ? data.meetingId.value : this.meetingId,
      json: data.json.present ? data.json.value : this.json,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FiletransRawRow(')
          ..write('meetingId: $meetingId, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(meetingId, json, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FiletransRawRow &&
          other.meetingId == this.meetingId &&
          other.json == this.json &&
          other.createdAt == this.createdAt);
}

class FiletransRawCompanion extends UpdateCompanion<FiletransRawRow> {
  final Value<String> meetingId;
  final Value<String> json;
  final Value<String> createdAt;
  final Value<int> rowid;
  const FiletransRawCompanion({
    this.meetingId = const Value.absent(),
    this.json = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FiletransRawCompanion.insert({
    required String meetingId,
    required String json,
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : meetingId = Value(meetingId),
       json = Value(json),
       createdAt = Value(createdAt);
  static Insertable<FiletransRawRow> custom({
    Expression<String>? meetingId,
    Expression<String>? json,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (meetingId != null) 'meeting_id': meetingId,
      if (json != null) 'json': json,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FiletransRawCompanion copyWith({
    Value<String>? meetingId,
    Value<String>? json,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return FiletransRawCompanion(
      meetingId: meetingId ?? this.meetingId,
      json: json ?? this.json,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (meetingId.present) {
      map['meeting_id'] = Variable<String>(meetingId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FiletransRawCompanion(')
          ..write('meetingId: $meetingId, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MeetingsTable meetings = $MeetingsTable(this);
  late final $TranscriptSegmentsTable transcriptSegments =
      $TranscriptSegmentsTable(this);
  late final $SpeakersTable speakers = $SpeakersTable(this);
  late final $FiletransRawTable filetransRaw = $FiletransRawTable(this);
  late final MeetingDao meetingDao = MeetingDao(this as AppDatabase);
  late final SegmentDao segmentDao = SegmentDao(this as AppDatabase);
  late final SpeakerDao speakerDao = SpeakerDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    meetings,
    transcriptSegments,
    speakers,
    filetransRaw,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('transcript_segments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('speakers', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'meetings',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('filetrans_raw', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$MeetingsTableCreateCompanionBuilder = MeetingsCompanion Function({
  required String id,
  required String title,
  required String createdAt,
  Value<int> durationMs,
  Value<int> sampleRate,
  Value<int> speakerCount,
  Value<String?> minutesMd,
  Value<int> minutesPartial,
  Value<String?> minutesError,
  Value<String> status,
  Value<String> source,
  Value<String> finalizeStatus,
  Value<String> transcriptSource,
  Value<String?> finalizeError,
  Value<String> audioStatus,
  Value<String?> audioKey,
  Value<String?> audioError,
  Value<int> audioBytes,
  Value<String> importStatus,
  Value<String?> importError,
  Value<String?> importTaskId,
  Value<String?> importMetaJson,
  Value<int> rowid,
});
typedef $$MeetingsTableUpdateCompanionBuilder = MeetingsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> createdAt,
  Value<int> durationMs,
  Value<int> sampleRate,
  Value<int> speakerCount,
  Value<String?> minutesMd,
  Value<int> minutesPartial,
  Value<String?> minutesError,
  Value<String> status,
  Value<String> source,
  Value<String> finalizeStatus,
  Value<String> transcriptSource,
  Value<String?> finalizeError,
  Value<String> audioStatus,
  Value<String?> audioKey,
  Value<String?> audioError,
  Value<int> audioBytes,
  Value<String> importStatus,
  Value<String?> importError,
  Value<String?> importTaskId,
  Value<String?> importMetaJson,
  Value<int> rowid,
});

final class $$MeetingsTableReferences
    extends BaseReferences<_$AppDatabase, $MeetingsTable, MeetingRow> {
  $$MeetingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $TranscriptSegmentsTable,
    List<TranscriptSegmentRow>
  >
  _transcriptSegmentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.transcriptSegments,
        aliasName: 'meetings__id__transcript_segments__meeting_id',
      );

  $$TranscriptSegmentsTableProcessedTableManager get transcriptSegmentsRefs {
    final manager = $$TranscriptSegmentsTableTableManager(
      $_db,
      $_db.transcriptSegments,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transcriptSegmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpeakersTable, List<SpeakerRow>>
  _speakersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.speakers,
    aliasName: 'meetings__id__speakers__meeting_id',
  );

  $$SpeakersTableProcessedTableManager get speakersRefs {
    final manager = $$SpeakersTableTableManager(
      $_db,
      $_db.speakers,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_speakersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FiletransRawTable, List<FiletransRawRow>>
  _filetransRawRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.filetransRaw,
    aliasName: 'meetings__id__filetrans_raw__meeting_id',
  );

  $$FiletransRawTableProcessedTableManager get filetransRawRefs {
    final manager = $$FiletransRawTableTableManager(
      $_db,
      $_db.filetransRaw,
    ).filter((f) => f.meetingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_filetransRawRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MeetingsTableFilterComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get speakerCount => $composableBuilder(
    column: $table.speakerCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get minutesMd => $composableBuilder(
    column: $table.minutesMd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minutesPartial => $composableBuilder(
    column: $table.minutesPartial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get minutesError => $composableBuilder(
    column: $table.minutesError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalizeStatus => $composableBuilder(
    column: $table.finalizeStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcriptSource => $composableBuilder(
    column: $table.transcriptSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalizeError => $composableBuilder(
    column: $table.finalizeError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioStatus => $composableBuilder(
    column: $table.audioStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioKey => $composableBuilder(
    column: $table.audioKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioError => $composableBuilder(
    column: $table.audioError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioBytes => $composableBuilder(
    column: $table.audioBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importStatus => $composableBuilder(
    column: $table.importStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importError => $composableBuilder(
    column: $table.importError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importTaskId => $composableBuilder(
    column: $table.importTaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importMetaJson => $composableBuilder(
    column: $table.importMetaJson,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> transcriptSegmentsRefs(
    Expression<bool> Function($$TranscriptSegmentsTableFilterComposer f) f,
  ) {
    final $$TranscriptSegmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transcriptSegments,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TranscriptSegmentsTableFilterComposer(
            $db: $db,
            $table: $db.transcriptSegments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> speakersRefs(
    Expression<bool> Function($$SpeakersTableFilterComposer f) f,
  ) {
    final $$SpeakersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.speakers,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpeakersTableFilterComposer(
            $db: $db,
            $table: $db.speakers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> filetransRawRefs(
    Expression<bool> Function($$FiletransRawTableFilterComposer f) f,
  ) {
    final $$FiletransRawTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.filetransRaw,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FiletransRawTableFilterComposer(
            $db: $db,
            $table: $db.filetransRaw,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MeetingsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get speakerCount => $composableBuilder(
    column: $table.speakerCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get minutesMd => $composableBuilder(
    column: $table.minutesMd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minutesPartial => $composableBuilder(
    column: $table.minutesPartial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get minutesError => $composableBuilder(
    column: $table.minutesError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalizeStatus => $composableBuilder(
    column: $table.finalizeStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcriptSource => $composableBuilder(
    column: $table.transcriptSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalizeError => $composableBuilder(
    column: $table.finalizeError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioStatus => $composableBuilder(
    column: $table.audioStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioKey => $composableBuilder(
    column: $table.audioKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioError => $composableBuilder(
    column: $table.audioError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioBytes => $composableBuilder(
    column: $table.audioBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importStatus => $composableBuilder(
    column: $table.importStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importError => $composableBuilder(
    column: $table.importError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importTaskId => $composableBuilder(
    column: $table.importTaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importMetaJson => $composableBuilder(
    column: $table.importMetaJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeetingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeetingsTable> {
  $$MeetingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sampleRate => $composableBuilder(
    column: $table.sampleRate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get speakerCount => $composableBuilder(
    column: $table.speakerCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get minutesMd =>
      $composableBuilder(column: $table.minutesMd, builder: (column) => column);

  GeneratedColumn<int> get minutesPartial => $composableBuilder(
    column: $table.minutesPartial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get minutesError => $composableBuilder(
    column: $table.minutesError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get finalizeStatus => $composableBuilder(
    column: $table.finalizeStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transcriptSource => $composableBuilder(
    column: $table.transcriptSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finalizeError => $composableBuilder(
    column: $table.finalizeError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioStatus => $composableBuilder(
    column: $table.audioStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioKey =>
      $composableBuilder(column: $table.audioKey, builder: (column) => column);

  GeneratedColumn<String> get audioError => $composableBuilder(
    column: $table.audioError,
    builder: (column) => column,
  );

  GeneratedColumn<int> get audioBytes => $composableBuilder(
    column: $table.audioBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importStatus => $composableBuilder(
    column: $table.importStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importError => $composableBuilder(
    column: $table.importError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importTaskId => $composableBuilder(
    column: $table.importTaskId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importMetaJson => $composableBuilder(
    column: $table.importMetaJson,
    builder: (column) => column,
  );

  Expression<T> transcriptSegmentsRefs<T extends Object>(
    Expression<T> Function($$TranscriptSegmentsTableAnnotationComposer a) f,
  ) {
    final $$TranscriptSegmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.transcriptSegments,
          getReferencedColumn: (t) => t.meetingId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TranscriptSegmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.transcriptSegments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> speakersRefs<T extends Object>(
    Expression<T> Function($$SpeakersTableAnnotationComposer a) f,
  ) {
    final $$SpeakersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.speakers,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpeakersTableAnnotationComposer(
            $db: $db,
            $table: $db.speakers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> filetransRawRefs<T extends Object>(
    Expression<T> Function($$FiletransRawTableAnnotationComposer a) f,
  ) {
    final $$FiletransRawTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.filetransRaw,
      getReferencedColumn: (t) => t.meetingId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FiletransRawTableAnnotationComposer(
            $db: $db,
            $table: $db.filetransRaw,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MeetingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MeetingsTable,
          MeetingRow,
          $$MeetingsTableFilterComposer,
          $$MeetingsTableOrderingComposer,
          $$MeetingsTableAnnotationComposer,
          $$MeetingsTableCreateCompanionBuilder,
          $$MeetingsTableUpdateCompanionBuilder,
          (MeetingRow, $$MeetingsTableReferences),
          MeetingRow,
          PrefetchHooks Function({
            bool transcriptSegmentsRefs,
            bool speakersRefs,
            bool filetransRawRefs,
          })
        > {
  $$MeetingsTableTableManager(_$AppDatabase db, $MeetingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeetingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeetingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeetingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> sampleRate = const Value.absent(),
                Value<int> speakerCount = const Value.absent(),
                Value<String?> minutesMd = const Value.absent(),
                Value<int> minutesPartial = const Value.absent(),
                Value<String?> minutesError = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> finalizeStatus = const Value.absent(),
                Value<String> transcriptSource = const Value.absent(),
                Value<String?> finalizeError = const Value.absent(),
                Value<String> audioStatus = const Value.absent(),
                Value<String?> audioKey = const Value.absent(),
                Value<String?> audioError = const Value.absent(),
                Value<int> audioBytes = const Value.absent(),
                Value<String> importStatus = const Value.absent(),
                Value<String?> importError = const Value.absent(),
                Value<String?> importTaskId = const Value.absent(),
                Value<String?> importMetaJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeetingsCompanion(
                id: id,
                title: title,
                createdAt: createdAt,
                durationMs: durationMs,
                sampleRate: sampleRate,
                speakerCount: speakerCount,
                minutesMd: minutesMd,
                minutesPartial: minutesPartial,
                minutesError: minutesError,
                status: status,
                source: source,
                finalizeStatus: finalizeStatus,
                transcriptSource: transcriptSource,
                finalizeError: finalizeError,
                audioStatus: audioStatus,
                audioKey: audioKey,
                audioError: audioError,
                audioBytes: audioBytes,
                importStatus: importStatus,
                importError: importError,
                importTaskId: importTaskId,
                importMetaJson: importMetaJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String createdAt,
                Value<int> durationMs = const Value.absent(),
                Value<int> sampleRate = const Value.absent(),
                Value<int> speakerCount = const Value.absent(),
                Value<String?> minutesMd = const Value.absent(),
                Value<int> minutesPartial = const Value.absent(),
                Value<String?> minutesError = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> finalizeStatus = const Value.absent(),
                Value<String> transcriptSource = const Value.absent(),
                Value<String?> finalizeError = const Value.absent(),
                Value<String> audioStatus = const Value.absent(),
                Value<String?> audioKey = const Value.absent(),
                Value<String?> audioError = const Value.absent(),
                Value<int> audioBytes = const Value.absent(),
                Value<String> importStatus = const Value.absent(),
                Value<String?> importError = const Value.absent(),
                Value<String?> importTaskId = const Value.absent(),
                Value<String?> importMetaJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeetingsCompanion.insert(
                id: id,
                title: title,
                createdAt: createdAt,
                durationMs: durationMs,
                sampleRate: sampleRate,
                speakerCount: speakerCount,
                minutesMd: minutesMd,
                minutesPartial: minutesPartial,
                minutesError: minutesError,
                status: status,
                source: source,
                finalizeStatus: finalizeStatus,
                transcriptSource: transcriptSource,
                finalizeError: finalizeError,
                audioStatus: audioStatus,
                audioKey: audioKey,
                audioError: audioError,
                audioBytes: audioBytes,
                importStatus: importStatus,
                importError: importError,
                importTaskId: importTaskId,
                importMetaJson: importMetaJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeetingsTable, MeetingRow>(table),
                  $$MeetingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                transcriptSegmentsRefs = false,
                speakersRefs = false,
                filetransRawRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (transcriptSegmentsRefs) db.transcriptSegments,
                    if (speakersRefs) db.speakers,
                    if (filetransRawRefs) db.filetransRaw,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (transcriptSegmentsRefs)
                        await $_getPrefetchedData<
                          MeetingRow,
                          $MeetingsTable,
                          TranscriptSegmentRow
                        >(
                          currentTable: table,
                          referencedTable: $$MeetingsTableReferences
                              ._transcriptSegmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).transcriptSegmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (speakersRefs)
                        await $_getPrefetchedData<
                          MeetingRow,
                          $MeetingsTable,
                          SpeakerRow
                        >(
                          currentTable: table,
                          referencedTable: $$MeetingsTableReferences
                              ._speakersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).speakersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (filetransRawRefs)
                        await $_getPrefetchedData<
                          MeetingRow,
                          $MeetingsTable,
                          FiletransRawRow
                        >(
                          currentTable: table,
                          referencedTable: $$MeetingsTableReferences
                              ._filetransRawRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MeetingsTableReferences(
                                db,
                                table,
                                p0,
                              ).filetransRawRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.meetingId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MeetingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MeetingsTable,
      MeetingRow,
      $$MeetingsTableFilterComposer,
      $$MeetingsTableOrderingComposer,
      $$MeetingsTableAnnotationComposer,
      $$MeetingsTableCreateCompanionBuilder,
      $$MeetingsTableUpdateCompanionBuilder,
      (MeetingRow, $$MeetingsTableReferences),
      MeetingRow,
      PrefetchHooks Function({
        bool transcriptSegmentsRefs,
        bool speakersRefs,
        bool filetransRawRefs,
      })
    >;
typedef $$TranscriptSegmentsTableCreateCompanionBuilder =
    TranscriptSegmentsCompanion Function({
      required String meetingId,
      required String segmentId,
      required int ordinal,
      required String speakerId,
      Value<String?> speakerName,
      Value<String> segmentText,
      Value<int> startTime,
      Value<int> endTime,
      Value<double> confidence,
      Value<int> seqStart,
      Value<int> seqEnd,
      Value<int> rowid,
    });
typedef $$TranscriptSegmentsTableUpdateCompanionBuilder =
    TranscriptSegmentsCompanion Function({
      Value<String> meetingId,
      Value<String> segmentId,
      Value<int> ordinal,
      Value<String> speakerId,
      Value<String?> speakerName,
      Value<String> segmentText,
      Value<int> startTime,
      Value<int> endTime,
      Value<double> confidence,
      Value<int> seqStart,
      Value<int> seqEnd,
      Value<int> rowid,
    });

final class $$TranscriptSegmentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TranscriptSegmentsTable,
          TranscriptSegmentRow
        > {
  $$TranscriptSegmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('transcript_segments__meeting_id__meetings__id');

  $$MeetingsTableProcessedTableManager get meetingId {
    final $_column = $_itemColumn<String>('meeting_id')!;

    final manager = $$MeetingsTableTableManager(
      $_db,
      $_db.meetings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_meetingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TranscriptSegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $TranscriptSegmentsTable> {
  $$TranscriptSegmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get segmentId => $composableBuilder(
    column: $table.segmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get speakerId => $composableBuilder(
    column: $table.speakerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get speakerName => $composableBuilder(
    column: $table.speakerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seqStart => $composableBuilder(
    column: $table.seqStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seqEnd => $composableBuilder(
    column: $table.seqEnd,
    builder: (column) => ColumnFilters(column),
  );

  $$MeetingsTableFilterComposer get meetingId {
    final $$MeetingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableFilterComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptSegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $TranscriptSegmentsTable> {
  $$TranscriptSegmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get segmentId => $composableBuilder(
    column: $table.segmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get speakerId => $composableBuilder(
    column: $table.speakerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get speakerName => $composableBuilder(
    column: $table.speakerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seqStart => $composableBuilder(
    column: $table.seqStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seqEnd => $composableBuilder(
    column: $table.seqEnd,
    builder: (column) => ColumnOrderings(column),
  );

  $$MeetingsTableOrderingComposer get meetingId {
    final $$MeetingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableOrderingComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptSegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TranscriptSegmentsTable> {
  $$TranscriptSegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get segmentId =>
      $composableBuilder(column: $table.segmentId, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get speakerId =>
      $composableBuilder(column: $table.speakerId, builder: (column) => column);

  GeneratedColumn<String> get speakerName => $composableBuilder(
    column: $table.speakerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seqStart =>
      $composableBuilder(column: $table.seqStart, builder: (column) => column);

  GeneratedColumn<int> get seqEnd =>
      $composableBuilder(column: $table.seqEnd, builder: (column) => column);

  $$MeetingsTableAnnotationComposer get meetingId {
    final $$MeetingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableAnnotationComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptSegmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TranscriptSegmentsTable,
          TranscriptSegmentRow,
          $$TranscriptSegmentsTableFilterComposer,
          $$TranscriptSegmentsTableOrderingComposer,
          $$TranscriptSegmentsTableAnnotationComposer,
          $$TranscriptSegmentsTableCreateCompanionBuilder,
          $$TranscriptSegmentsTableUpdateCompanionBuilder,
          (TranscriptSegmentRow, $$TranscriptSegmentsTableReferences),
          TranscriptSegmentRow,
          PrefetchHooks Function({bool meetingId})
        > {
  $$TranscriptSegmentsTableTableManager(
    _$AppDatabase db,
    $TranscriptSegmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TranscriptSegmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TranscriptSegmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TranscriptSegmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> meetingId = const Value.absent(),
                Value<String> segmentId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> speakerId = const Value.absent(),
                Value<String?> speakerName = const Value.absent(),
                Value<String> segmentText = const Value.absent(),
                Value<int> startTime = const Value.absent(),
                Value<int> endTime = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<int> seqStart = const Value.absent(),
                Value<int> seqEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TranscriptSegmentsCompanion(
                meetingId: meetingId,
                segmentId: segmentId,
                ordinal: ordinal,
                speakerId: speakerId,
                speakerName: speakerName,
                segmentText: segmentText,
                startTime: startTime,
                endTime: endTime,
                confidence: confidence,
                seqStart: seqStart,
                seqEnd: seqEnd,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String meetingId,
                required String segmentId,
                required int ordinal,
                required String speakerId,
                Value<String?> speakerName = const Value.absent(),
                Value<String> segmentText = const Value.absent(),
                Value<int> startTime = const Value.absent(),
                Value<int> endTime = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<int> seqStart = const Value.absent(),
                Value<int> seqEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TranscriptSegmentsCompanion.insert(
                meetingId: meetingId,
                segmentId: segmentId,
                ordinal: ordinal,
                speakerId: speakerId,
                speakerName: speakerName,
                segmentText: segmentText,
                startTime: startTime,
                endTime: endTime,
                confidence: confidence,
                seqStart: seqStart,
                seqEnd: seqEnd,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TranscriptSegmentsTable, TranscriptSegmentRow>(
                    table,
                  ),
                  $$TranscriptSegmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({meetingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (meetingId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.meetingId,
                        referencedTable: $$TranscriptSegmentsTableReferences
                            ._meetingIdTable(db),
                        referencedColumn: $$TranscriptSegmentsTableReferences
                            ._meetingIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TranscriptSegmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TranscriptSegmentsTable,
      TranscriptSegmentRow,
      $$TranscriptSegmentsTableFilterComposer,
      $$TranscriptSegmentsTableOrderingComposer,
      $$TranscriptSegmentsTableAnnotationComposer,
      $$TranscriptSegmentsTableCreateCompanionBuilder,
      $$TranscriptSegmentsTableUpdateCompanionBuilder,
      (TranscriptSegmentRow, $$TranscriptSegmentsTableReferences),
      TranscriptSegmentRow,
      PrefetchHooks Function({bool meetingId})
    >;
typedef $$SpeakersTableCreateCompanionBuilder = SpeakersCompanion Function({
  required String meetingId,
  required String speakerId,
  required String name,
  Value<int> colorIndex,
  Value<int> firstSeenMs,
  Value<int> rowid,
});
typedef $$SpeakersTableUpdateCompanionBuilder = SpeakersCompanion Function({
  Value<String> meetingId,
  Value<String> speakerId,
  Value<String> name,
  Value<int> colorIndex,
  Value<int> firstSeenMs,
  Value<int> rowid,
});

final class $$SpeakersTableReferences
    extends BaseReferences<_$AppDatabase, $SpeakersTable, SpeakerRow> {
  $$SpeakersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('speakers__meeting_id__meetings__id');

  $$MeetingsTableProcessedTableManager get meetingId {
    final $_column = $_itemColumn<String>('meeting_id')!;

    final manager = $$MeetingsTableTableManager(
      $_db,
      $_db.meetings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_meetingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpeakersTableFilterComposer
    extends Composer<_$AppDatabase, $SpeakersTable> {
  $$SpeakersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get speakerId => $composableBuilder(
    column: $table.speakerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenMs => $composableBuilder(
    column: $table.firstSeenMs,
    builder: (column) => ColumnFilters(column),
  );

  $$MeetingsTableFilterComposer get meetingId {
    final $$MeetingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableFilterComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpeakersTableOrderingComposer
    extends Composer<_$AppDatabase, $SpeakersTable> {
  $$SpeakersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get speakerId => $composableBuilder(
    column: $table.speakerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenMs => $composableBuilder(
    column: $table.firstSeenMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$MeetingsTableOrderingComposer get meetingId {
    final $$MeetingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableOrderingComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpeakersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpeakersTable> {
  $$SpeakersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get speakerId =>
      $composableBuilder(column: $table.speakerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorIndex => $composableBuilder(
    column: $table.colorIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSeenMs => $composableBuilder(
    column: $table.firstSeenMs,
    builder: (column) => column,
  );

  $$MeetingsTableAnnotationComposer get meetingId {
    final $$MeetingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableAnnotationComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpeakersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpeakersTable,
          SpeakerRow,
          $$SpeakersTableFilterComposer,
          $$SpeakersTableOrderingComposer,
          $$SpeakersTableAnnotationComposer,
          $$SpeakersTableCreateCompanionBuilder,
          $$SpeakersTableUpdateCompanionBuilder,
          (SpeakerRow, $$SpeakersTableReferences),
          SpeakerRow,
          PrefetchHooks Function({bool meetingId})
        > {
  $$SpeakersTableTableManager(_$AppDatabase db, $SpeakersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SpeakersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SpeakersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SpeakersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> meetingId = const Value.absent(),
                Value<String> speakerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorIndex = const Value.absent(),
                Value<int> firstSeenMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpeakersCompanion(
                meetingId: meetingId,
                speakerId: speakerId,
                name: name,
                colorIndex: colorIndex,
                firstSeenMs: firstSeenMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String meetingId,
                required String speakerId,
                required String name,
                Value<int> colorIndex = const Value.absent(),
                Value<int> firstSeenMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpeakersCompanion.insert(
                meetingId: meetingId,
                speakerId: speakerId,
                name: name,
                colorIndex: colorIndex,
                firstSeenMs: firstSeenMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SpeakersTable, SpeakerRow>(table),
                  $$SpeakersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({meetingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (meetingId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.meetingId,
                        referencedTable: $$SpeakersTableReferences
                            ._meetingIdTable(db),
                        referencedColumn: $$SpeakersTableReferences
                            ._meetingIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SpeakersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpeakersTable,
      SpeakerRow,
      $$SpeakersTableFilterComposer,
      $$SpeakersTableOrderingComposer,
      $$SpeakersTableAnnotationComposer,
      $$SpeakersTableCreateCompanionBuilder,
      $$SpeakersTableUpdateCompanionBuilder,
      (SpeakerRow, $$SpeakersTableReferences),
      SpeakerRow,
      PrefetchHooks Function({bool meetingId})
    >;
typedef $$FiletransRawTableCreateCompanionBuilder =
    FiletransRawCompanion Function({
      required String meetingId,
      required String json,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$FiletransRawTableUpdateCompanionBuilder =
    FiletransRawCompanion Function({
      Value<String> meetingId,
      Value<String> json,
      Value<String> createdAt,
      Value<int> rowid,
    });

final class $$FiletransRawTableReferences
    extends BaseReferences<_$AppDatabase, $FiletransRawTable, FiletransRawRow> {
  $$FiletransRawTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MeetingsTable _meetingIdTable(_$AppDatabase db) =>
      db.meetings.createAlias('filetrans_raw__meeting_id__meetings__id');

  $$MeetingsTableProcessedTableManager get meetingId {
    final $_column = $_itemColumn<String>('meeting_id')!;

    final manager = $$MeetingsTableTableManager(
      $_db,
      $_db.meetings,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_meetingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FiletransRawTableFilterComposer
    extends Composer<_$AppDatabase, $FiletransRawTable> {
  $$FiletransRawTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MeetingsTableFilterComposer get meetingId {
    final $$MeetingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableFilterComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FiletransRawTableOrderingComposer
    extends Composer<_$AppDatabase, $FiletransRawTable> {
  $$FiletransRawTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MeetingsTableOrderingComposer get meetingId {
    final $$MeetingsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableOrderingComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FiletransRawTableAnnotationComposer
    extends Composer<_$AppDatabase, $FiletransRawTable> {
  $$FiletransRawTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MeetingsTableAnnotationComposer get meetingId {
    final $$MeetingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.meetingId,
      referencedTable: $db.meetings,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MeetingsTableAnnotationComposer(
            $db: $db,
            $table: $db.meetings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FiletransRawTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FiletransRawTable,
          FiletransRawRow,
          $$FiletransRawTableFilterComposer,
          $$FiletransRawTableOrderingComposer,
          $$FiletransRawTableAnnotationComposer,
          $$FiletransRawTableCreateCompanionBuilder,
          $$FiletransRawTableUpdateCompanionBuilder,
          (FiletransRawRow, $$FiletransRawTableReferences),
          FiletransRawRow,
          PrefetchHooks Function({bool meetingId})
        > {
  $$FiletransRawTableTableManager(_$AppDatabase db, $FiletransRawTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FiletransRawTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FiletransRawTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FiletransRawTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> meetingId = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FiletransRawCompanion(
                meetingId: meetingId,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String meetingId,
                required String json,
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FiletransRawCompanion.insert(
                meetingId: meetingId,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FiletransRawTable, FiletransRawRow>(table),
                  $$FiletransRawTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({meetingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (meetingId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.meetingId,
                        referencedTable: $$FiletransRawTableReferences
                            ._meetingIdTable(db),
                        referencedColumn: $$FiletransRawTableReferences
                            ._meetingIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FiletransRawTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FiletransRawTable,
      FiletransRawRow,
      $$FiletransRawTableFilterComposer,
      $$FiletransRawTableOrderingComposer,
      $$FiletransRawTableAnnotationComposer,
      $$FiletransRawTableCreateCompanionBuilder,
      $$FiletransRawTableUpdateCompanionBuilder,
      (FiletransRawRow, $$FiletransRawTableReferences),
      FiletransRawRow,
      PrefetchHooks Function({bool meetingId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MeetingsTableTableManager get meetings =>
      $$MeetingsTableTableManager(_db, _db.meetings);
  $$TranscriptSegmentsTableTableManager get transcriptSegments =>
      $$TranscriptSegmentsTableTableManager(_db, _db.transcriptSegments);
  $$SpeakersTableTableManager get speakers =>
      $$SpeakersTableTableManager(_db, _db.speakers);
  $$FiletransRawTableTableManager get filetransRaw =>
      $$FiletransRawTableTableManager(_db, _db.filetransRaw);
}
