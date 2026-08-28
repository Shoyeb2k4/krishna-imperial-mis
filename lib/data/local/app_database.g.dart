// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppMetaTable extends AppMeta with TableInfo<$AppMetaTable, AppMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppMetaTable createAlias(String alias) {
    return $AppMetaTable(attachedDatabase, alias);
  }
}

class AppMetaRow extends DataClass implements Insertable<AppMetaRow> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppMetaRow({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppMetaCompanion toCompanion(bool nullToAbsent) {
    return AppMetaCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppMetaRow copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppMetaRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppMetaRow copyWithCompanion(AppMetaCompanion data) {
    return AppMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetaRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppMetaCompanion extends UpdateCompanion<AppMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppMetaCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRowVersionMeta = const VerificationMeta(
    'baseRowVersion',
  );
  @override
  late final GeneratedColumn<int> baseRowVersion = GeneratedColumn<int>(
    'base_row_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inFlightSinceMeta = const VerificationMeta(
    'inFlightSince',
  );
  @override
  late final GeneratedColumn<DateTime> inFlightSince =
      GeneratedColumn<DateTime>(
        'in_flight_since',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    mutationId,
    actorUserId,
    entityType,
    entityId,
    op,
    payload,
    baseRowVersion,
    attemptCount,
    nextAttemptAt,
    status,
    lastError,
    createdAt,
    inFlightSince,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_row_version')) {
      context.handle(
        _baseRowVersionMeta,
        baseRowVersion.isAcceptableOrUnknown(
          data['base_row_version']!,
          _baseRowVersionMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('in_flight_since')) {
      context.handle(
        _inFlightSinceMeta,
        inFlightSince.isAcceptableOrUnknown(
          data['in_flight_since']!,
          _inFlightSinceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mutationId};
  @override
  SyncOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxRow(
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      ),
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      baseRowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_row_version'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      inFlightSince: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}in_flight_since'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxRow extends DataClass implements Insertable<SyncOutboxRow> {
  /// Generated once per intent and reused for every retry. This is the primary key
  /// precisely so the same intent can never be enqueued twice.
  final String mutationId;

  /// Who queued this intent.
  ///
  /// A shared Windows workstation in a hotel back office will see several people sign
  /// in and out of one installation. Without this column the queue is anonymous, and
  /// one user's device could push work another user created under authority they no
  /// longer hold — or never held. Sync only ever sends entries belonging to the signed-in
  /// user, and one user's queued work is never shown to, retried by or attributed to
  /// another (D-050).
  ///
  /// Nullable only for rows written before this column existed. Those are treated as
  /// unattributed and are never sent by anyone; they are surfaced for a human instead of
  /// being guessed at or quietly discarded.
  final String? actorUserId;
  final String entityType;
  final String entityId;

  /// `create` | `update` | `void_` | `correctBusinessDate` | `archive`
  final String op;

  /// The canonical document as JSON, including allocation lines.
  final String payload;

  /// The row version this intent was based on. Null only for creates.
  final int? baseRowVersion;
  final int attemptCount;
  final DateTime nextAttemptAt;

  /// See [OutboxStatus]: pending | inFlight | failed | conflict | blockedAuth | done.
  final String status;
  final String? lastError;

  /// When the intent was captured on this device. Forensic only — server timestamps
  /// are authoritative.
  final DateTime createdAt;

  /// When the entry was handed to the transport. Used by crash recovery to reclaim
  /// entries that were in flight when the app died.
  final DateTime? inFlightSince;
  const SyncOutboxRow({
    required this.mutationId,
    this.actorUserId,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payload,
    this.baseRowVersion,
    required this.attemptCount,
    required this.nextAttemptAt,
    required this.status,
    this.lastError,
    required this.createdAt,
    this.inFlightSince,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mutation_id'] = Variable<String>(mutationId);
    if (!nullToAbsent || actorUserId != null) {
      map['actor_user_id'] = Variable<String>(actorUserId);
    }
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || baseRowVersion != null) {
      map['base_row_version'] = Variable<int>(baseRowVersion);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || inFlightSince != null) {
      map['in_flight_since'] = Variable<DateTime>(inFlightSince);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      mutationId: Value(mutationId),
      actorUserId: actorUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(actorUserId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      op: Value(op),
      payload: Value(payload),
      baseRowVersion: baseRowVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRowVersion),
      attemptCount: Value(attemptCount),
      nextAttemptAt: Value(nextAttemptAt),
      status: Value(status),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      inFlightSince: inFlightSince == null && nullToAbsent
          ? const Value.absent()
          : Value(inFlightSince),
    );
  }

  factory SyncOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxRow(
      mutationId: serializer.fromJson<String>(json['mutationId']),
      actorUserId: serializer.fromJson<String?>(json['actorUserId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      op: serializer.fromJson<String>(json['op']),
      payload: serializer.fromJson<String>(json['payload']),
      baseRowVersion: serializer.fromJson<int?>(json['baseRowVersion']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
      status: serializer.fromJson<String>(json['status']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      inFlightSince: serializer.fromJson<DateTime?>(json['inFlightSince']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mutationId': serializer.toJson<String>(mutationId),
      'actorUserId': serializer.toJson<String?>(actorUserId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'payload': serializer.toJson<String>(payload),
      'baseRowVersion': serializer.toJson<int?>(baseRowVersion),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
      'status': serializer.toJson<String>(status),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'inFlightSince': serializer.toJson<DateTime?>(inFlightSince),
    };
  }

  SyncOutboxRow copyWith({
    String? mutationId,
    Value<String?> actorUserId = const Value.absent(),
    String? entityType,
    String? entityId,
    String? op,
    String? payload,
    Value<int?> baseRowVersion = const Value.absent(),
    int? attemptCount,
    DateTime? nextAttemptAt,
    String? status,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> inFlightSince = const Value.absent(),
  }) => SyncOutboxRow(
    mutationId: mutationId ?? this.mutationId,
    actorUserId: actorUserId.present ? actorUserId.value : this.actorUserId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    op: op ?? this.op,
    payload: payload ?? this.payload,
    baseRowVersion: baseRowVersion.present
        ? baseRowVersion.value
        : this.baseRowVersion,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    status: status ?? this.status,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    inFlightSince: inFlightSince.present
        ? inFlightSince.value
        : this.inFlightSince,
  );
  SyncOutboxRow copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxRow(
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      op: data.op.present ? data.op.value : this.op,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseRowVersion: data.baseRowVersion.present
          ? data.baseRowVersion.value
          : this.baseRowVersion,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      status: data.status.present ? data.status.value : this.status,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      inFlightSince: data.inFlightSince.present
          ? data.inFlightSince.value
          : this.inFlightSince,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxRow(')
          ..write('mutationId: $mutationId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('baseRowVersion: $baseRowVersion, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('inFlightSince: $inFlightSince')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    actorUserId,
    entityType,
    entityId,
    op,
    payload,
    baseRowVersion,
    attemptCount,
    nextAttemptAt,
    status,
    lastError,
    createdAt,
    inFlightSince,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxRow &&
          other.mutationId == this.mutationId &&
          other.actorUserId == this.actorUserId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.payload == this.payload &&
          other.baseRowVersion == this.baseRowVersion &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.status == this.status &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.inFlightSince == this.inFlightSince);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxRow> {
  final Value<String> mutationId;
  final Value<String?> actorUserId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String> payload;
  final Value<int?> baseRowVersion;
  final Value<int> attemptCount;
  final Value<DateTime> nextAttemptAt;
  final Value<String> status;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime?> inFlightSince;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.mutationId = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseRowVersion = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.status = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.inFlightSince = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String mutationId,
    this.actorUserId = const Value.absent(),
    required String entityType,
    required String entityId,
    required String op,
    required String payload,
    this.baseRowVersion = const Value.absent(),
    this.attemptCount = const Value.absent(),
    required DateTime nextAttemptAt,
    required String status,
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    this.inFlightSince = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mutationId = Value(mutationId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       op = Value(op),
       payload = Value(payload),
       nextAttemptAt = Value(nextAttemptAt),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<SyncOutboxRow> custom({
    Expression<String>? mutationId,
    Expression<String>? actorUserId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<String>? payload,
    Expression<int>? baseRowVersion,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? status,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? inFlightSince,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mutationId != null) 'mutation_id': mutationId,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (baseRowVersion != null) 'base_row_version': baseRowVersion,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (status != null) 'status': status,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (inFlightSince != null) 'in_flight_since': inFlightSince,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? mutationId,
    Value<String?>? actorUserId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? op,
    Value<String>? payload,
    Value<int?>? baseRowVersion,
    Value<int>? attemptCount,
    Value<DateTime>? nextAttemptAt,
    Value<String>? status,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime?>? inFlightSince,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      mutationId: mutationId ?? this.mutationId,
      actorUserId: actorUserId ?? this.actorUserId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      baseRowVersion: baseRowVersion ?? this.baseRowVersion,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      inFlightSince: inFlightSince ?? this.inFlightSince,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseRowVersion.present) {
      map['base_row_version'] = Variable<int>(baseRowVersion.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (inFlightSince.present) {
      map['in_flight_since'] = Variable<DateTime>(inFlightSince.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('mutationId: $mutationId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('baseRowVersion: $baseRowVersion, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('inFlightSince: $inFlightSince, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BusinessUnitsTable extends BusinessUnits
    with TableInfo<$BusinessUnitsTable, BusinessUnitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BusinessUnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Kolkata'),
  );
  static const VerificationMeta _businessDayCutoffMeta = const VerificationMeta(
    'businessDayCutoff',
  );
  @override
  late final GeneratedColumn<String> businessDayCutoff =
      GeneratedColumn<String>(
        'business_day_cutoff',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('05:00'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    kind,
    timezone,
    businessDayCutoff,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'business_units';
  @override
  VerificationContext validateIntegrity(
    Insertable<BusinessUnitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('business_day_cutoff')) {
      context.handle(
        _businessDayCutoffMeta,
        businessDayCutoff.isAcceptableOrUnknown(
          data['business_day_cutoff']!,
          _businessDayCutoffMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {orgId, code},
  ];
  @override
  BusinessUnitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BusinessUnitRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      businessDayCutoff: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_day_cutoff'],
      )!,
    );
  }

  @override
  $BusinessUnitsTable createAlias(String alias) {
    return $BusinessUnitsTable(attachedDatabase, alias);
  }
}

class BusinessUnitRow extends DataClass implements Insertable<BusinessUnitRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;

  /// `restaurant` | `hotel` | `other`
  final String kind;

  /// IANA zone for this property. Drives business-date derivation (D-019).
  final String timezone;

  /// `HH:mm`. Changing it affects future derivations only; persisted business dates on
  /// existing rows are never restated.
  final String businessDayCutoff;
  const BusinessUnitRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.kind,
    required this.timezone,
    required this.businessDayCutoff,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['kind'] = Variable<String>(kind);
    map['timezone'] = Variable<String>(timezone);
    map['business_day_cutoff'] = Variable<String>(businessDayCutoff);
    return map;
  }

  BusinessUnitsCompanion toCompanion(bool nullToAbsent) {
    return BusinessUnitsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      kind: Value(kind),
      timezone: Value(timezone),
      businessDayCutoff: Value(businessDayCutoff),
    );
  }

  factory BusinessUnitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BusinessUnitRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      kind: serializer.fromJson<String>(json['kind']),
      timezone: serializer.fromJson<String>(json['timezone']),
      businessDayCutoff: serializer.fromJson<String>(json['businessDayCutoff']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'kind': serializer.toJson<String>(kind),
      'timezone': serializer.toJson<String>(timezone),
      'businessDayCutoff': serializer.toJson<String>(businessDayCutoff),
    };
  }

  BusinessUnitRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    String? kind,
    String? timezone,
    String? businessDayCutoff,
  }) => BusinessUnitRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    kind: kind ?? this.kind,
    timezone: timezone ?? this.timezone,
    businessDayCutoff: businessDayCutoff ?? this.businessDayCutoff,
  );
  BusinessUnitRow copyWithCompanion(BusinessUnitsCompanion data) {
    return BusinessUnitRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      businessDayCutoff: data.businessDayCutoff.present
          ? data.businessDayCutoff.value
          : this.businessDayCutoff,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BusinessUnitRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind, ')
          ..write('timezone: $timezone, ')
          ..write('businessDayCutoff: $businessDayCutoff')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    kind,
    timezone,
    businessDayCutoff,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BusinessUnitRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.kind == this.kind &&
          other.timezone == this.timezone &&
          other.businessDayCutoff == this.businessDayCutoff);
}

class BusinessUnitsCompanion extends UpdateCompanion<BusinessUnitRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String> kind;
  final Value<String> timezone;
  final Value<String> businessDayCutoff;
  final Value<int> rowid;
  const BusinessUnitsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.timezone = const Value.absent(),
    this.businessDayCutoff = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BusinessUnitsCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    required String kind,
    this.timezone = const Value.absent(),
    this.businessDayCutoff = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt),
       kind = Value(kind);
  static Insertable<BusinessUnitRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? kind,
    Expression<String>? timezone,
    Expression<String>? businessDayCutoff,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (kind != null) 'kind': kind,
      if (timezone != null) 'timezone': timezone,
      if (businessDayCutoff != null) 'business_day_cutoff': businessDayCutoff,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BusinessUnitsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String>? kind,
    Value<String>? timezone,
    Value<String>? businessDayCutoff,
    Value<int>? rowid,
  }) {
    return BusinessUnitsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      timezone: timezone ?? this.timezone,
      businessDayCutoff: businessDayCutoff ?? this.businessDayCutoff,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (businessDayCutoff.present) {
      map['business_day_cutoff'] = Variable<String>(businessDayCutoff.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BusinessUnitsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('kind: $kind, ')
          ..write('timezone: $timezone, ')
          ..write('businessDayCutoff: $businessDayCutoff, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DepartmentsTable extends Departments
    with TableInfo<$DepartmentsTable, DepartmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DepartmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessUnitIdMeta = const VerificationMeta(
    'businessUnitId',
  );
  @override
  late final GeneratedColumn<String> businessUnitId = GeneratedColumn<String>(
    'business_unit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES business_units (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    businessUnitId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'departments';
  @override
  VerificationContext validateIntegrity(
    Insertable<DepartmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('business_unit_id')) {
      context.handle(
        _businessUnitIdMeta,
        businessUnitId.isAcceptableOrUnknown(
          data['business_unit_id']!,
          _businessUnitIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_businessUnitIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {businessUnitId, code},
  ];
  @override
  DepartmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DepartmentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
    );
  }

  @override
  $DepartmentsTable createAlias(String alias) {
    return $DepartmentsTable(attachedDatabase, alias);
  }
}

class DepartmentRow extends DataClass implements Insertable<DepartmentRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final String businessUnitId;
  const DepartmentRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.businessUnitId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    return map;
  }

  DepartmentsCompanion toCompanion(bool nullToAbsent) {
    return DepartmentsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      businessUnitId: Value(businessUnitId),
    );
  }

  factory DepartmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DepartmentRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
    };
  }

  DepartmentRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    String? businessUnitId,
  }) => DepartmentRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    businessUnitId: businessUnitId ?? this.businessUnitId,
  );
  DepartmentRow copyWithCompanion(DepartmentsCompanion data) {
    return DepartmentRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DepartmentRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('businessUnitId: $businessUnitId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    businessUnitId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DepartmentRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.businessUnitId == this.businessUnitId);
}

class DepartmentsCompanion extends UpdateCompanion<DepartmentRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String> businessUnitId;
  final Value<int> rowid;
  const DepartmentsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DepartmentsCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    required String businessUnitId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt),
       businessUnitId = Value(businessUnitId);
  static Insertable<DepartmentRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? businessUnitId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DepartmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String>? businessUnitId,
    Value<int>? rowid,
  }) {
    return DepartmentsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DepartmentsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SectionsTable extends Sections
    with TableInfo<$SectionsTable, SectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _departmentIdMeta = const VerificationMeta(
    'departmentId',
  );
  @override
  late final GeneratedColumn<String> departmentId = GeneratedColumn<String>(
    'department_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES departments (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    departmentId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sections';
  @override
  VerificationContext validateIntegrity(
    Insertable<SectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('department_id')) {
      context.handle(
        _departmentIdMeta,
        departmentId.isAcceptableOrUnknown(
          data['department_id']!,
          _departmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_departmentIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {departmentId, code},
  ];
  @override
  SectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      departmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}department_id'],
      )!,
    );
  }

  @override
  $SectionsTable createAlias(String alias) {
    return $SectionsTable(attachedDatabase, alias);
  }
}

class SectionRow extends DataClass implements Insertable<SectionRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final String departmentId;
  const SectionRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.departmentId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['department_id'] = Variable<String>(departmentId);
    return map;
  }

  SectionsCompanion toCompanion(bool nullToAbsent) {
    return SectionsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      departmentId: Value(departmentId),
    );
  }

  factory SectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SectionRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      departmentId: serializer.fromJson<String>(json['departmentId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'departmentId': serializer.toJson<String>(departmentId),
    };
  }

  SectionRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    String? departmentId,
  }) => SectionRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    departmentId: departmentId ?? this.departmentId,
  );
  SectionRow copyWithCompanion(SectionsCompanion data) {
    return SectionRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      departmentId: data.departmentId.present
          ? data.departmentId.value
          : this.departmentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SectionRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('departmentId: $departmentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    departmentId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SectionRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.departmentId == this.departmentId);
}

class SectionsCompanion extends UpdateCompanion<SectionRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String> departmentId;
  final Value<int> rowid;
  const SectionsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.departmentId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionsCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    required String departmentId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt),
       departmentId = Value(departmentId);
  static Insertable<SectionRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? departmentId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (departmentId != null) 'department_id': departmentId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String>? departmentId,
    Value<int>? rowid,
  }) {
    return SectionsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      departmentId: departmentId ?? this.departmentId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (departmentId.present) {
      map['department_id'] = Variable<String>(departmentId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SectionsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('departmentId: $departmentId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseCategoriesTable extends ExpenseCategories
    with TableInfo<$ExpenseCategoriesTable, ExpenseCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sectionIdMeta = const VerificationMeta(
    'sectionId',
  );
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
    'section_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sections (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _natureMeta = const VerificationMeta('nature');
  @override
  late final GeneratedColumn<String> nature = GeneratedColumn<String>(
    'nature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('operating'),
  );
  static const VerificationMeta _isSharedByDefaultMeta = const VerificationMeta(
    'isSharedByDefault',
  );
  @override
  late final GeneratedColumn<bool> isSharedByDefault = GeneratedColumn<bool>(
    'is_shared_by_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_shared_by_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    sectionId,
    nature,
    isSharedByDefault,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('nature')) {
      context.handle(
        _natureMeta,
        nature.isAcceptableOrUnknown(data['nature']!, _natureMeta),
      );
    }
    if (data.containsKey('is_shared_by_default')) {
      context.handle(
        _isSharedByDefaultMeta,
        isSharedByDefault.isAcceptableOrUnknown(
          data['is_shared_by_default']!,
          _isSharedByDefaultMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sectionId, code},
  ];
  @override
  ExpenseCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseCategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      nature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nature'],
      )!,
      isSharedByDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_shared_by_default'],
      )!,
    );
  }

  @override
  $ExpenseCategoriesTable createAlias(String alias) {
    return $ExpenseCategoriesTable(attachedDatabase, alias);
  }
}

class ExpenseCategoryRow extends DataClass
    implements Insertable<ExpenseCategoryRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final String sectionId;

  /// `operating` | `payroll` | `utility` | `other`
  final String nature;

  /// A hint for the entry screen — electricity is usually split between properties.
  /// Never a rule: the user always decides the actual allocation.
  final bool isSharedByDefault;
  const ExpenseCategoryRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.sectionId,
    required this.nature,
    required this.isSharedByDefault,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['section_id'] = Variable<String>(sectionId);
    map['nature'] = Variable<String>(nature);
    map['is_shared_by_default'] = Variable<bool>(isSharedByDefault);
    return map;
  }

  ExpenseCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ExpenseCategoriesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      sectionId: Value(sectionId),
      nature: Value(nature),
      isSharedByDefault: Value(isSharedByDefault),
    );
  }

  factory ExpenseCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseCategoryRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      nature: serializer.fromJson<String>(json['nature']),
      isSharedByDefault: serializer.fromJson<bool>(json['isSharedByDefault']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sectionId': serializer.toJson<String>(sectionId),
      'nature': serializer.toJson<String>(nature),
      'isSharedByDefault': serializer.toJson<bool>(isSharedByDefault),
    };
  }

  ExpenseCategoryRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    String? sectionId,
    String? nature,
    bool? isSharedByDefault,
  }) => ExpenseCategoryRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    sectionId: sectionId ?? this.sectionId,
    nature: nature ?? this.nature,
    isSharedByDefault: isSharedByDefault ?? this.isSharedByDefault,
  );
  ExpenseCategoryRow copyWithCompanion(ExpenseCategoriesCompanion data) {
    return ExpenseCategoryRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      nature: data.nature.present ? data.nature.value : this.nature,
      isSharedByDefault: data.isSharedByDefault.present
          ? data.isSharedByDefault.value
          : this.isSharedByDefault,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoryRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('nature: $nature, ')
          ..write('isSharedByDefault: $isSharedByDefault')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    sectionId,
    nature,
    isSharedByDefault,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseCategoryRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.sectionId == this.sectionId &&
          other.nature == this.nature &&
          other.isSharedByDefault == this.isSharedByDefault);
}

class ExpenseCategoriesCompanion extends UpdateCompanion<ExpenseCategoryRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String> sectionId;
  final Value<String> nature;
  final Value<bool> isSharedByDefault;
  final Value<int> rowid;
  const ExpenseCategoriesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.nature = const Value.absent(),
    this.isSharedByDefault = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseCategoriesCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    required String sectionId,
    this.nature = const Value.absent(),
    this.isSharedByDefault = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt),
       sectionId = Value(sectionId);
  static Insertable<ExpenseCategoryRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? sectionId,
    Expression<String>? nature,
    Expression<bool>? isSharedByDefault,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sectionId != null) 'section_id': sectionId,
      if (nature != null) 'nature': nature,
      if (isSharedByDefault != null) 'is_shared_by_default': isSharedByDefault,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String>? sectionId,
    Value<String>? nature,
    Value<bool>? isSharedByDefault,
    Value<int>? rowid,
  }) {
    return ExpenseCategoriesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      sectionId: sectionId ?? this.sectionId,
      nature: nature ?? this.nature,
      isSharedByDefault: isSharedByDefault ?? this.isSharedByDefault,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (nature.present) {
      map['nature'] = Variable<String>(nature.value);
    }
    if (isSharedByDefault.present) {
      map['is_shared_by_default'] = Variable<bool>(isSharedByDefault.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sectionId: $sectionId, ')
          ..write('nature: $nature, ')
          ..write('isSharedByDefault: $isSharedByDefault, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueCategoriesTable extends RevenueCategories
    with TableInfo<$RevenueCategoriesTable, RevenueCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessUnitIdMeta = const VerificationMeta(
    'businessUnitId',
  );
  @override
  late final GeneratedColumn<String> businessUnitId = GeneratedColumn<String>(
    'business_unit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES business_units (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    businessUnitId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('business_unit_id')) {
      context.handle(
        _businessUnitIdMeta,
        businessUnitId.isAcceptableOrUnknown(
          data['business_unit_id']!,
          _businessUnitIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_businessUnitIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {businessUnitId, code},
  ];
  @override
  RevenueCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueCategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
    );
  }

  @override
  $RevenueCategoriesTable createAlias(String alias) {
    return $RevenueCategoriesTable(attachedDatabase, alias);
  }
}

class RevenueCategoryRow extends DataClass
    implements Insertable<RevenueCategoryRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final String businessUnitId;
  const RevenueCategoryRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.businessUnitId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    return map;
  }

  RevenueCategoriesCompanion toCompanion(bool nullToAbsent) {
    return RevenueCategoriesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      businessUnitId: Value(businessUnitId),
    );
  }

  factory RevenueCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueCategoryRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
    };
  }

  RevenueCategoryRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    String? businessUnitId,
  }) => RevenueCategoryRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    businessUnitId: businessUnitId ?? this.businessUnitId,
  );
  RevenueCategoryRow copyWithCompanion(RevenueCategoriesCompanion data) {
    return RevenueCategoryRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueCategoryRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('businessUnitId: $businessUnitId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    businessUnitId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueCategoryRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.businessUnitId == this.businessUnitId);
}

class RevenueCategoriesCompanion extends UpdateCompanion<RevenueCategoryRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String> businessUnitId;
  final Value<int> rowid;
  const RevenueCategoriesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueCategoriesCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    required String businessUnitId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt),
       businessUnitId = Value(businessUnitId);
  static Insertable<RevenueCategoryRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? businessUnitId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String>? businessUnitId,
    Value<int>? rowid,
  }) {
    return RevenueCategoriesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VendorsTable extends Vendors with TableInfo<$VendorsTable, VendorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VendorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gstinMeta = const VerificationMeta('gstin');
  @override
  late final GeneratedColumn<String> gstin = GeneratedColumn<String>(
    'gstin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultCategoryIdMeta = const VerificationMeta(
    'defaultCategoryId',
  );
  @override
  late final GeneratedColumn<String> defaultCategoryId =
      GeneratedColumn<String>(
        'default_category_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _defaultBusinessUnitIdMeta =
      const VerificationMeta('defaultBusinessUnitId');
  @override
  late final GeneratedColumn<String> defaultBusinessUnitId =
      GeneratedColumn<String>(
        'default_business_unit_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    gstin,
    phone,
    address,
    defaultCategoryId,
    defaultBusinessUnitId,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vendors';
  @override
  VerificationContext validateIntegrity(
    Insertable<VendorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('gstin')) {
      context.handle(
        _gstinMeta,
        gstin.isAcceptableOrUnknown(data['gstin']!, _gstinMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('default_category_id')) {
      context.handle(
        _defaultCategoryIdMeta,
        defaultCategoryId.isAcceptableOrUnknown(
          data['default_category_id']!,
          _defaultCategoryIdMeta,
        ),
      );
    }
    if (data.containsKey('default_business_unit_id')) {
      context.handle(
        _defaultBusinessUnitIdMeta,
        defaultBusinessUnitId.isAcceptableOrUnknown(
          data['default_business_unit_id']!,
          _defaultBusinessUnitIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {orgId, code},
  ];
  @override
  VendorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VendorRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      gstin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gstin'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      defaultCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_category_id'],
      ),
      defaultBusinessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_business_unit_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $VendorsTable createAlias(String alias) {
    return $VendorsTable(attachedDatabase, alias);
  }
}

class VendorRow extends DataClass implements Insertable<VendorRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final String? gstin;
  final String? phone;
  final String? address;

  /// Optional. Pre-selects a category when this vendor is chosen during entry.
  ///
  /// Deliberately **not** a foreign key (D-049). A vendor is an organisation-global
  /// master; these two columns are operational conveniences, not ownership, visibility
  /// or authorisation. A foreign key would assert "the target must exist in this
  /// database", and on a per-user cache that is simply false: a manager scoped to one
  /// property legitimately holds vendors whose usual category belongs to the other. It
  /// also made the revoked-scope purge impossible without rewriting canonical vendor
  /// data, which D-049 §2 forbids.
  ///
  /// A dangling pointer here is therefore expected and harmless. It is resolved at the
  /// point of use by `Vendor.effectiveDefaultBusinessUnitId`, which filters through the
  /// caller's current authoritative scope and owns nothing.
  final String? defaultCategoryId;

  /// Optional. Pre-selects the property when this vendor is chosen during entry. Soft
  /// pointer, for the reasons above.
  final String? defaultBusinessUnitId;
  final String? notes;
  const VendorRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    this.gstin,
    this.phone,
    this.address,
    this.defaultCategoryId,
    this.defaultBusinessUnitId,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || gstin != null) {
      map['gstin'] = Variable<String>(gstin);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || defaultCategoryId != null) {
      map['default_category_id'] = Variable<String>(defaultCategoryId);
    }
    if (!nullToAbsent || defaultBusinessUnitId != null) {
      map['default_business_unit_id'] = Variable<String>(defaultBusinessUnitId);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  VendorsCompanion toCompanion(bool nullToAbsent) {
    return VendorsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      gstin: gstin == null && nullToAbsent
          ? const Value.absent()
          : Value(gstin),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      defaultCategoryId: defaultCategoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultCategoryId),
      defaultBusinessUnitId: defaultBusinessUnitId == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultBusinessUnitId),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory VendorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VendorRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      gstin: serializer.fromJson<String?>(json['gstin']),
      phone: serializer.fromJson<String?>(json['phone']),
      address: serializer.fromJson<String?>(json['address']),
      defaultCategoryId: serializer.fromJson<String?>(
        json['defaultCategoryId'],
      ),
      defaultBusinessUnitId: serializer.fromJson<String?>(
        json['defaultBusinessUnitId'],
      ),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'gstin': serializer.toJson<String?>(gstin),
      'phone': serializer.toJson<String?>(phone),
      'address': serializer.toJson<String?>(address),
      'defaultCategoryId': serializer.toJson<String?>(defaultCategoryId),
      'defaultBusinessUnitId': serializer.toJson<String?>(
        defaultBusinessUnitId,
      ),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  VendorRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    Value<String?> gstin = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> defaultCategoryId = const Value.absent(),
    Value<String?> defaultBusinessUnitId = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) => VendorRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    gstin: gstin.present ? gstin.value : this.gstin,
    phone: phone.present ? phone.value : this.phone,
    address: address.present ? address.value : this.address,
    defaultCategoryId: defaultCategoryId.present
        ? defaultCategoryId.value
        : this.defaultCategoryId,
    defaultBusinessUnitId: defaultBusinessUnitId.present
        ? defaultBusinessUnitId.value
        : this.defaultBusinessUnitId,
    notes: notes.present ? notes.value : this.notes,
  );
  VendorRow copyWithCompanion(VendorsCompanion data) {
    return VendorRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      gstin: data.gstin.present ? data.gstin.value : this.gstin,
      phone: data.phone.present ? data.phone.value : this.phone,
      address: data.address.present ? data.address.value : this.address,
      defaultCategoryId: data.defaultCategoryId.present
          ? data.defaultCategoryId.value
          : this.defaultCategoryId,
      defaultBusinessUnitId: data.defaultBusinessUnitId.present
          ? data.defaultBusinessUnitId.value
          : this.defaultBusinessUnitId,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VendorRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('gstin: $gstin, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('defaultCategoryId: $defaultCategoryId, ')
          ..write('defaultBusinessUnitId: $defaultBusinessUnitId, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    gstin,
    phone,
    address,
    defaultCategoryId,
    defaultBusinessUnitId,
    notes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VendorRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.gstin == this.gstin &&
          other.phone == this.phone &&
          other.address == this.address &&
          other.defaultCategoryId == this.defaultCategoryId &&
          other.defaultBusinessUnitId == this.defaultBusinessUnitId &&
          other.notes == this.notes);
}

class VendorsCompanion extends UpdateCompanion<VendorRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<String?> gstin;
  final Value<String?> phone;
  final Value<String?> address;
  final Value<String?> defaultCategoryId;
  final Value<String?> defaultBusinessUnitId;
  final Value<String?> notes;
  final Value<int> rowid;
  const VendorsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.gstin = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.defaultCategoryId = const Value.absent(),
    this.defaultBusinessUnitId = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VendorsCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.gstin = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.defaultCategoryId = const Value.absent(),
    this.defaultBusinessUnitId = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<VendorRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<String>? gstin,
    Expression<String>? phone,
    Expression<String>? address,
    Expression<String>? defaultCategoryId,
    Expression<String>? defaultBusinessUnitId,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (gstin != null) 'gstin': gstin,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (defaultCategoryId != null) 'default_category_id': defaultCategoryId,
      if (defaultBusinessUnitId != null)
        'default_business_unit_id': defaultBusinessUnitId,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VendorsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<String?>? gstin,
    Value<String?>? phone,
    Value<String?>? address,
    Value<String?>? defaultCategoryId,
    Value<String?>? defaultBusinessUnitId,
    Value<String?>? notes,
    Value<int>? rowid,
  }) {
    return VendorsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      gstin: gstin ?? this.gstin,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      defaultCategoryId: defaultCategoryId ?? this.defaultCategoryId,
      defaultBusinessUnitId:
          defaultBusinessUnitId ?? this.defaultBusinessUnitId,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (gstin.present) {
      map['gstin'] = Variable<String>(gstin.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (defaultCategoryId.present) {
      map['default_category_id'] = Variable<String>(defaultCategoryId.value);
    }
    if (defaultBusinessUnitId.present) {
      map['default_business_unit_id'] = Variable<String>(
        defaultBusinessUnitId.value,
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VendorsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('gstin: $gstin, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('defaultCategoryId: $defaultCategoryId, ')
          ..write('defaultBusinessUnitId: $defaultBusinessUnitId, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PaymentMethodsTable extends PaymentMethods
    with TableInfo<$PaymentMethodsTable, PaymentMethodRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentMethodsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requiresReferenceMeta = const VerificationMeta(
    'requiresReference',
  );
  @override
  late final GeneratedColumn<bool> requiresReference = GeneratedColumn<bool>(
    'requires_reference',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_reference" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    requiresReference,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payment_methods';
  @override
  VerificationContext validateIntegrity(
    Insertable<PaymentMethodRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('requires_reference')) {
      context.handle(
        _requiresReferenceMeta,
        requiresReference.isAcceptableOrUnknown(
          data['requires_reference']!,
          _requiresReferenceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {orgId, code},
  ];
  @override
  PaymentMethodRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentMethodRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      requiresReference: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_reference'],
      )!,
    );
  }

  @override
  $PaymentMethodsTable createAlias(String alias) {
    return $PaymentMethodsTable(attachedDatabase, alias);
  }
}

class PaymentMethodRow extends DataClass
    implements Insertable<PaymentMethodRow> {
  final String id;
  final String orgId;

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  final String code;

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  final bool requiresReference;
  const PaymentMethodRow({
    required this.id,
    required this.orgId,
    required this.code,
    required this.name,
    required this.sortOrder,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
    required this.requiresReference,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['requires_reference'] = Variable<bool>(requiresReference);
    return map;
  }

  PaymentMethodsCompanion toCompanion(bool nullToAbsent) {
    return PaymentMethodsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      code: Value(code),
      name: Value(name),
      sortOrder: Value(sortOrder),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
      requiresReference: Value(requiresReference),
    );
  }

  factory PaymentMethodRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentMethodRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      requiresReference: serializer.fromJson<bool>(json['requiresReference']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'requiresReference': serializer.toJson<bool>(requiresReference),
    };
  }

  PaymentMethodRow copyWith({
    String? id,
    String? orgId,
    String? code,
    String? name,
    int? sortOrder,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
    bool? requiresReference,
  }) => PaymentMethodRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    code: code ?? this.code,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
    requiresReference: requiresReference ?? this.requiresReference,
  );
  PaymentMethodRow copyWithCompanion(PaymentMethodsCompanion data) {
    return PaymentMethodRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      requiresReference: data.requiresReference.present
          ? data.requiresReference.value
          : this.requiresReference,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethodRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('requiresReference: $requiresReference')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    code,
    name,
    sortOrder,
    archivedAt,
    rowVersion,
    updatedAt,
    requiresReference,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentMethodRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.code == this.code &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt &&
          other.requiresReference == this.requiresReference);
}

class PaymentMethodsCompanion extends UpdateCompanion<PaymentMethodRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> code;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<bool> requiresReference;
  final Value<int> rowid;
  const PaymentMethodsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.requiresReference = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PaymentMethodsCompanion.insert({
    required String id,
    required String orgId,
    required String code,
    required String name,
    this.sortOrder = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.requiresReference = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       code = Value(code),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<PaymentMethodRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<bool>? requiresReference,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (requiresReference != null) 'requires_reference': requiresReference,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PaymentMethodsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? code,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<bool>? requiresReference,
    Value<int>? rowid,
  }) {
    return PaymentMethodsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      code: code ?? this.code,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: archivedAt ?? this.archivedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      requiresReference: requiresReference ?? this.requiresReference,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (requiresReference.present) {
      map['requires_reference'] = Variable<bool>(requiresReference.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentMethodsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('requiresReference: $requiresReference, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeriodLocksTable extends PeriodLocks
    with TableInfo<$PeriodLocksTable, PeriodLockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeriodLocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessUnitIdMeta = const VerificationMeta(
    'businessUnitId',
  );
  @override
  late final GeneratedColumn<String> businessUnitId = GeneratedColumn<String>(
    'business_unit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES business_units (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _periodKeyMeta = const VerificationMeta(
    'periodKey',
  );
  @override
  late final GeneratedColumn<String> periodKey = GeneratedColumn<String>(
    'period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closedByMeta = const VerificationMeta(
    'closedBy',
  );
  @override
  late final GeneratedColumn<String> closedBy = GeneratedColumn<String>(
    'closed_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reopenedByMeta = const VerificationMeta(
    'reopenedBy',
  );
  @override
  late final GeneratedColumn<String> reopenedBy = GeneratedColumn<String>(
    'reopened_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reopenedAtMeta = const VerificationMeta(
    'reopenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> reopenedAt = GeneratedColumn<DateTime>(
    'reopened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reopenReasonMeta = const VerificationMeta(
    'reopenReason',
  );
  @override
  late final GeneratedColumn<String> reopenReason = GeneratedColumn<String>(
    'reopen_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    businessUnitId,
    periodKey,
    state,
    closedBy,
    closedAt,
    reopenedBy,
    reopenedAt,
    reopenReason,
    rowVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'period_locks';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeriodLockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('business_unit_id')) {
      context.handle(
        _businessUnitIdMeta,
        businessUnitId.isAcceptableOrUnknown(
          data['business_unit_id']!,
          _businessUnitIdMeta,
        ),
      );
    }
    if (data.containsKey('period_key')) {
      context.handle(
        _periodKeyMeta,
        periodKey.isAcceptableOrUnknown(data['period_key']!, _periodKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_periodKeyMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('closed_by')) {
      context.handle(
        _closedByMeta,
        closedBy.isAcceptableOrUnknown(data['closed_by']!, _closedByMeta),
      );
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('reopened_by')) {
      context.handle(
        _reopenedByMeta,
        reopenedBy.isAcceptableOrUnknown(data['reopened_by']!, _reopenedByMeta),
      );
    }
    if (data.containsKey('reopened_at')) {
      context.handle(
        _reopenedAtMeta,
        reopenedAt.isAcceptableOrUnknown(data['reopened_at']!, _reopenedAtMeta),
      );
    }
    if (data.containsKey('reopen_reason')) {
      context.handle(
        _reopenReasonMeta,
        reopenReason.isAcceptableOrUnknown(
          data['reopen_reason']!,
          _reopenReasonMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PeriodLockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeriodLockRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      ),
      periodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_key'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      closedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}closed_by'],
      ),
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      ),
      reopenedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reopened_by'],
      ),
      reopenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reopened_at'],
      ),
      reopenReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reopen_reason'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
    );
  }

  @override
  $PeriodLocksTable createAlias(String alias) {
    return $PeriodLocksTable(attachedDatabase, alias);
  }
}

class PeriodLockRow extends DataClass implements Insertable<PeriodLockRow> {
  final String id;
  final String orgId;

  /// Null means every business unit.
  final String? businessUnitId;
  final String periodKey;
  final String state;
  final String? closedBy;
  final DateTime? closedAt;
  final String? reopenedBy;
  final DateTime? reopenedAt;
  final String? reopenReason;
  final int rowVersion;
  const PeriodLockRow({
    required this.id,
    required this.orgId,
    this.businessUnitId,
    required this.periodKey,
    required this.state,
    this.closedBy,
    this.closedAt,
    this.reopenedBy,
    this.reopenedAt,
    this.reopenReason,
    required this.rowVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    if (!nullToAbsent || businessUnitId != null) {
      map['business_unit_id'] = Variable<String>(businessUnitId);
    }
    map['period_key'] = Variable<String>(periodKey);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || closedBy != null) {
      map['closed_by'] = Variable<String>(closedBy);
    }
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<DateTime>(closedAt);
    }
    if (!nullToAbsent || reopenedBy != null) {
      map['reopened_by'] = Variable<String>(reopenedBy);
    }
    if (!nullToAbsent || reopenedAt != null) {
      map['reopened_at'] = Variable<DateTime>(reopenedAt);
    }
    if (!nullToAbsent || reopenReason != null) {
      map['reopen_reason'] = Variable<String>(reopenReason);
    }
    map['row_version'] = Variable<int>(rowVersion);
    return map;
  }

  PeriodLocksCompanion toCompanion(bool nullToAbsent) {
    return PeriodLocksCompanion(
      id: Value(id),
      orgId: Value(orgId),
      businessUnitId: businessUnitId == null && nullToAbsent
          ? const Value.absent()
          : Value(businessUnitId),
      periodKey: Value(periodKey),
      state: Value(state),
      closedBy: closedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(closedBy),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      reopenedBy: reopenedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(reopenedBy),
      reopenedAt: reopenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reopenedAt),
      reopenReason: reopenReason == null && nullToAbsent
          ? const Value.absent()
          : Value(reopenReason),
      rowVersion: Value(rowVersion),
    );
  }

  factory PeriodLockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeriodLockRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      businessUnitId: serializer.fromJson<String?>(json['businessUnitId']),
      periodKey: serializer.fromJson<String>(json['periodKey']),
      state: serializer.fromJson<String>(json['state']),
      closedBy: serializer.fromJson<String?>(json['closedBy']),
      closedAt: serializer.fromJson<DateTime?>(json['closedAt']),
      reopenedBy: serializer.fromJson<String?>(json['reopenedBy']),
      reopenedAt: serializer.fromJson<DateTime?>(json['reopenedAt']),
      reopenReason: serializer.fromJson<String?>(json['reopenReason']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'businessUnitId': serializer.toJson<String?>(businessUnitId),
      'periodKey': serializer.toJson<String>(periodKey),
      'state': serializer.toJson<String>(state),
      'closedBy': serializer.toJson<String?>(closedBy),
      'closedAt': serializer.toJson<DateTime?>(closedAt),
      'reopenedBy': serializer.toJson<String?>(reopenedBy),
      'reopenedAt': serializer.toJson<DateTime?>(reopenedAt),
      'reopenReason': serializer.toJson<String?>(reopenReason),
      'rowVersion': serializer.toJson<int>(rowVersion),
    };
  }

  PeriodLockRow copyWith({
    String? id,
    String? orgId,
    Value<String?> businessUnitId = const Value.absent(),
    String? periodKey,
    String? state,
    Value<String?> closedBy = const Value.absent(),
    Value<DateTime?> closedAt = const Value.absent(),
    Value<String?> reopenedBy = const Value.absent(),
    Value<DateTime?> reopenedAt = const Value.absent(),
    Value<String?> reopenReason = const Value.absent(),
    int? rowVersion,
  }) => PeriodLockRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    businessUnitId: businessUnitId.present
        ? businessUnitId.value
        : this.businessUnitId,
    periodKey: periodKey ?? this.periodKey,
    state: state ?? this.state,
    closedBy: closedBy.present ? closedBy.value : this.closedBy,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    reopenedBy: reopenedBy.present ? reopenedBy.value : this.reopenedBy,
    reopenedAt: reopenedAt.present ? reopenedAt.value : this.reopenedAt,
    reopenReason: reopenReason.present ? reopenReason.value : this.reopenReason,
    rowVersion: rowVersion ?? this.rowVersion,
  );
  PeriodLockRow copyWithCompanion(PeriodLocksCompanion data) {
    return PeriodLockRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      periodKey: data.periodKey.present ? data.periodKey.value : this.periodKey,
      state: data.state.present ? data.state.value : this.state,
      closedBy: data.closedBy.present ? data.closedBy.value : this.closedBy,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      reopenedBy: data.reopenedBy.present
          ? data.reopenedBy.value
          : this.reopenedBy,
      reopenedAt: data.reopenedAt.present
          ? data.reopenedAt.value
          : this.reopenedAt,
      reopenReason: data.reopenReason.present
          ? data.reopenReason.value
          : this.reopenReason,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeriodLockRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('periodKey: $periodKey, ')
          ..write('state: $state, ')
          ..write('closedBy: $closedBy, ')
          ..write('closedAt: $closedAt, ')
          ..write('reopenedBy: $reopenedBy, ')
          ..write('reopenedAt: $reopenedAt, ')
          ..write('reopenReason: $reopenReason, ')
          ..write('rowVersion: $rowVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    businessUnitId,
    periodKey,
    state,
    closedBy,
    closedAt,
    reopenedBy,
    reopenedAt,
    reopenReason,
    rowVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeriodLockRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.businessUnitId == this.businessUnitId &&
          other.periodKey == this.periodKey &&
          other.state == this.state &&
          other.closedBy == this.closedBy &&
          other.closedAt == this.closedAt &&
          other.reopenedBy == this.reopenedBy &&
          other.reopenedAt == this.reopenedAt &&
          other.reopenReason == this.reopenReason &&
          other.rowVersion == this.rowVersion);
}

class PeriodLocksCompanion extends UpdateCompanion<PeriodLockRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String?> businessUnitId;
  final Value<String> periodKey;
  final Value<String> state;
  final Value<String?> closedBy;
  final Value<DateTime?> closedAt;
  final Value<String?> reopenedBy;
  final Value<DateTime?> reopenedAt;
  final Value<String?> reopenReason;
  final Value<int> rowVersion;
  final Value<int> rowid;
  const PeriodLocksCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.periodKey = const Value.absent(),
    this.state = const Value.absent(),
    this.closedBy = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.reopenedBy = const Value.absent(),
    this.reopenedAt = const Value.absent(),
    this.reopenReason = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeriodLocksCompanion.insert({
    required String id,
    required String orgId,
    this.businessUnitId = const Value.absent(),
    required String periodKey,
    required String state,
    this.closedBy = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.reopenedBy = const Value.absent(),
    this.reopenedAt = const Value.absent(),
    this.reopenReason = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       periodKey = Value(periodKey),
       state = Value(state);
  static Insertable<PeriodLockRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? businessUnitId,
    Expression<String>? periodKey,
    Expression<String>? state,
    Expression<String>? closedBy,
    Expression<DateTime>? closedAt,
    Expression<String>? reopenedBy,
    Expression<DateTime>? reopenedAt,
    Expression<String>? reopenReason,
    Expression<int>? rowVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (periodKey != null) 'period_key': periodKey,
      if (state != null) 'state': state,
      if (closedBy != null) 'closed_by': closedBy,
      if (closedAt != null) 'closed_at': closedAt,
      if (reopenedBy != null) 'reopened_by': reopenedBy,
      if (reopenedAt != null) 'reopened_at': reopenedAt,
      if (reopenReason != null) 'reopen_reason': reopenReason,
      if (rowVersion != null) 'row_version': rowVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeriodLocksCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String?>? businessUnitId,
    Value<String>? periodKey,
    Value<String>? state,
    Value<String?>? closedBy,
    Value<DateTime?>? closedAt,
    Value<String?>? reopenedBy,
    Value<DateTime?>? reopenedAt,
    Value<String?>? reopenReason,
    Value<int>? rowVersion,
    Value<int>? rowid,
  }) {
    return PeriodLocksCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      periodKey: periodKey ?? this.periodKey,
      state: state ?? this.state,
      closedBy: closedBy ?? this.closedBy,
      closedAt: closedAt ?? this.closedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenReason: reopenReason ?? this.reopenReason,
      rowVersion: rowVersion ?? this.rowVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (periodKey.present) {
      map['period_key'] = Variable<String>(periodKey.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (closedBy.present) {
      map['closed_by'] = Variable<String>(closedBy.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (reopenedBy.present) {
      map['reopened_by'] = Variable<String>(reopenedBy.value);
    }
    if (reopenedAt.present) {
      map['reopened_at'] = Variable<DateTime>(reopenedAt.value);
    }
    if (reopenReason.present) {
      map['reopen_reason'] = Variable<String>(reopenReason.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeriodLocksCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('periodKey: $periodKey, ')
          ..write('state: $state, ')
          ..write('closedBy: $closedBy, ')
          ..write('closedAt: $closedAt, ')
          ..write('reopenedBy: $reopenedBy, ')
          ..write('reopenedAt: $reopenedAt, ')
          ..write('reopenReason: $reopenReason, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeriodLockEventsTable extends PeriodLockEvents
    with TableInfo<$PeriodLockEventsTable, PeriodLockEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeriodLockEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodLockIdMeta = const VerificationMeta(
    'periodLockId',
  );
  @override
  late final GeneratedColumn<String> periodLockId = GeneratedColumn<String>(
    'period_lock_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES period_locks (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    periodLockId,
    action,
    reason,
    actorId,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'period_lock_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeriodLockEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('period_lock_id')) {
      context.handle(
        _periodLockIdMeta,
        periodLockId.isAcceptableOrUnknown(
          data['period_lock_id']!,
          _periodLockIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodLockIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PeriodLockEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeriodLockEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      periodLockId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_lock_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $PeriodLockEventsTable createAlias(String alias) {
    return $PeriodLockEventsTable(attachedDatabase, alias);
  }
}

class PeriodLockEventRow extends DataClass
    implements Insertable<PeriodLockEventRow> {
  final String id;
  final String orgId;
  final String periodLockId;

  /// `close` | `reopen`
  final String action;

  /// Mandatory for a reopen. Enforced by the repository, which refuses an empty one.
  final String? reason;
  final String actorId;
  final DateTime occurredAt;
  const PeriodLockEventRow({
    required this.id,
    required this.orgId,
    required this.periodLockId,
    required this.action,
    this.reason,
    required this.actorId,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['period_lock_id'] = Variable<String>(periodLockId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['actor_id'] = Variable<String>(actorId);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  PeriodLockEventsCompanion toCompanion(bool nullToAbsent) {
    return PeriodLockEventsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      periodLockId: Value(periodLockId),
      action: Value(action),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      actorId: Value(actorId),
      occurredAt: Value(occurredAt),
    );
  }

  factory PeriodLockEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeriodLockEventRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      periodLockId: serializer.fromJson<String>(json['periodLockId']),
      action: serializer.fromJson<String>(json['action']),
      reason: serializer.fromJson<String?>(json['reason']),
      actorId: serializer.fromJson<String>(json['actorId']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'periodLockId': serializer.toJson<String>(periodLockId),
      'action': serializer.toJson<String>(action),
      'reason': serializer.toJson<String?>(reason),
      'actorId': serializer.toJson<String>(actorId),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  PeriodLockEventRow copyWith({
    String? id,
    String? orgId,
    String? periodLockId,
    String? action,
    Value<String?> reason = const Value.absent(),
    String? actorId,
    DateTime? occurredAt,
  }) => PeriodLockEventRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    periodLockId: periodLockId ?? this.periodLockId,
    action: action ?? this.action,
    reason: reason.present ? reason.value : this.reason,
    actorId: actorId ?? this.actorId,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  PeriodLockEventRow copyWithCompanion(PeriodLockEventsCompanion data) {
    return PeriodLockEventRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      periodLockId: data.periodLockId.present
          ? data.periodLockId.value
          : this.periodLockId,
      action: data.action.present ? data.action.value : this.action,
      reason: data.reason.present ? data.reason.value : this.reason,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeriodLockEventRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('periodLockId: $periodLockId, ')
          ..write('action: $action, ')
          ..write('reason: $reason, ')
          ..write('actorId: $actorId, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, orgId, periodLockId, action, reason, actorId, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeriodLockEventRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.periodLockId == this.periodLockId &&
          other.action == this.action &&
          other.reason == this.reason &&
          other.actorId == this.actorId &&
          other.occurredAt == this.occurredAt);
}

class PeriodLockEventsCompanion extends UpdateCompanion<PeriodLockEventRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> periodLockId;
  final Value<String> action;
  final Value<String?> reason;
  final Value<String> actorId;
  final Value<DateTime> occurredAt;
  final Value<int> rowid;
  const PeriodLockEventsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.periodLockId = const Value.absent(),
    this.action = const Value.absent(),
    this.reason = const Value.absent(),
    this.actorId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeriodLockEventsCompanion.insert({
    required String id,
    required String orgId,
    required String periodLockId,
    required String action,
    this.reason = const Value.absent(),
    required String actorId,
    required DateTime occurredAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       periodLockId = Value(periodLockId),
       action = Value(action),
       actorId = Value(actorId),
       occurredAt = Value(occurredAt);
  static Insertable<PeriodLockEventRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? periodLockId,
    Expression<String>? action,
    Expression<String>? reason,
    Expression<String>? actorId,
    Expression<DateTime>? occurredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (periodLockId != null) 'period_lock_id': periodLockId,
      if (action != null) 'action': action,
      if (reason != null) 'reason': reason,
      if (actorId != null) 'actor_id': actorId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeriodLockEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? periodLockId,
    Value<String>? action,
    Value<String?>? reason,
    Value<String>? actorId,
    Value<DateTime>? occurredAt,
    Value<int>? rowid,
  }) {
    return PeriodLockEventsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      periodLockId: periodLockId ?? this.periodLockId,
      action: action ?? this.action,
      reason: reason ?? this.reason,
      actorId: actorId ?? this.actorId,
      occurredAt: occurredAt ?? this.occurredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (periodLockId.present) {
      map['period_lock_id'] = Variable<String>(periodLockId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeriodLockEventsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('periodLockId: $periodLockId, ')
          ..write('action: $action, ')
          ..write('reason: $reason, ')
          ..write('actorId: $actorId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueTaxRatesTable extends RevenueTaxRates
    with TableInfo<$RevenueTaxRatesTable, RevenueTaxRateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueTaxRatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revenueCategoryIdMeta = const VerificationMeta(
    'revenueCategoryId',
  );
  @override
  late final GeneratedColumn<String> revenueCategoryId =
      GeneratedColumn<String>(
        'revenue_category_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES revenue_categories (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _rateBasisPointsMeta = const VerificationMeta(
    'rateBasisPoints',
  );
  @override
  late final GeneratedColumn<int> rateBasisPoints = GeneratedColumn<int>(
    'rate_basis_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _treatmentMeta = const VerificationMeta(
    'treatment',
  );
  @override
  late final GeneratedColumn<String> treatment = GeneratedColumn<String>(
    'treatment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveFromMeta = const VerificationMeta(
    'effectiveFrom',
  );
  @override
  late final GeneratedColumn<String> effectiveFrom = GeneratedColumn<String>(
    'effective_from',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveToMeta = const VerificationMeta(
    'effectiveTo',
  );
  @override
  late final GeneratedColumn<String> effectiveTo = GeneratedColumn<String>(
    'effective_to',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    revenueCategoryId,
    rateBasisPoints,
    treatment,
    effectiveFrom,
    effectiveTo,
    note,
    archivedAt,
    createdBy,
    createdAt,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_tax_rates';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueTaxRateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('revenue_category_id')) {
      context.handle(
        _revenueCategoryIdMeta,
        revenueCategoryId.isAcceptableOrUnknown(
          data['revenue_category_id']!,
          _revenueCategoryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revenueCategoryIdMeta);
    }
    if (data.containsKey('rate_basis_points')) {
      context.handle(
        _rateBasisPointsMeta,
        rateBasisPoints.isAcceptableOrUnknown(
          data['rate_basis_points']!,
          _rateBasisPointsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rateBasisPointsMeta);
    }
    if (data.containsKey('treatment')) {
      context.handle(
        _treatmentMeta,
        treatment.isAcceptableOrUnknown(data['treatment']!, _treatmentMeta),
      );
    } else if (isInserting) {
      context.missing(_treatmentMeta);
    }
    if (data.containsKey('effective_from')) {
      context.handle(
        _effectiveFromMeta,
        effectiveFrom.isAcceptableOrUnknown(
          data['effective_from']!,
          _effectiveFromMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveFromMeta);
    }
    if (data.containsKey('effective_to')) {
      context.handle(
        _effectiveToMeta,
        effectiveTo.isAcceptableOrUnknown(
          data['effective_to']!,
          _effectiveToMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevenueTaxRateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueTaxRateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      revenueCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revenue_category_id'],
      )!,
      rateBasisPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rate_basis_points'],
      )!,
      treatment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}treatment'],
      )!,
      effectiveFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_from'],
      )!,
      effectiveTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_to'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RevenueTaxRatesTable createAlias(String alias) {
    return $RevenueTaxRatesTable(attachedDatabase, alias);
  }
}

class RevenueTaxRateRow extends DataClass
    implements Insertable<RevenueTaxRateRow> {
  final String id;
  final String orgId;
  final String revenueCategoryId;

  /// Basis points: 1% = 100. Integers only — a rate never arrives as a float.
  final int rateBasisPoints;

  /// `inclusive` | `exclusive` | `none`
  final String treatment;

  /// `YYYY-MM-DD`, inclusive lower bound.
  final String effectiveFrom;

  /// `YYYY-MM-DD`, **exclusive** upper bound. Null means still in force.
  final String? effectiveTo;
  final String? note;
  final DateTime? archivedAt;
  final String createdBy;
  final DateTime createdAt;
  final int rowVersion;
  final DateTime updatedAt;
  const RevenueTaxRateRow({
    required this.id,
    required this.orgId,
    required this.revenueCategoryId,
    required this.rateBasisPoints,
    required this.treatment,
    required this.effectiveFrom,
    this.effectiveTo,
    this.note,
    this.archivedAt,
    required this.createdBy,
    required this.createdAt,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['revenue_category_id'] = Variable<String>(revenueCategoryId);
    map['rate_basis_points'] = Variable<int>(rateBasisPoints);
    map['treatment'] = Variable<String>(treatment);
    map['effective_from'] = Variable<String>(effectiveFrom);
    if (!nullToAbsent || effectiveTo != null) {
      map['effective_to'] = Variable<String>(effectiveTo);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['created_by'] = Variable<String>(createdBy);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RevenueTaxRatesCompanion toCompanion(bool nullToAbsent) {
    return RevenueTaxRatesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      revenueCategoryId: Value(revenueCategoryId),
      rateBasisPoints: Value(rateBasisPoints),
      treatment: Value(treatment),
      effectiveFrom: Value(effectiveFrom),
      effectiveTo: effectiveTo == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveTo),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      createdBy: Value(createdBy),
      createdAt: Value(createdAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory RevenueTaxRateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueTaxRateRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      revenueCategoryId: serializer.fromJson<String>(json['revenueCategoryId']),
      rateBasisPoints: serializer.fromJson<int>(json['rateBasisPoints']),
      treatment: serializer.fromJson<String>(json['treatment']),
      effectiveFrom: serializer.fromJson<String>(json['effectiveFrom']),
      effectiveTo: serializer.fromJson<String?>(json['effectiveTo']),
      note: serializer.fromJson<String?>(json['note']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'revenueCategoryId': serializer.toJson<String>(revenueCategoryId),
      'rateBasisPoints': serializer.toJson<int>(rateBasisPoints),
      'treatment': serializer.toJson<String>(treatment),
      'effectiveFrom': serializer.toJson<String>(effectiveFrom),
      'effectiveTo': serializer.toJson<String?>(effectiveTo),
      'note': serializer.toJson<String?>(note),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'createdBy': serializer.toJson<String>(createdBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RevenueTaxRateRow copyWith({
    String? id,
    String? orgId,
    String? revenueCategoryId,
    int? rateBasisPoints,
    String? treatment,
    String? effectiveFrom,
    Value<String?> effectiveTo = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
    String? createdBy,
    DateTime? createdAt,
    int? rowVersion,
    DateTime? updatedAt,
  }) => RevenueTaxRateRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
    rateBasisPoints: rateBasisPoints ?? this.rateBasisPoints,
    treatment: treatment ?? this.treatment,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    effectiveTo: effectiveTo.present ? effectiveTo.value : this.effectiveTo,
    note: note.present ? note.value : this.note,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RevenueTaxRateRow copyWithCompanion(RevenueTaxRatesCompanion data) {
    return RevenueTaxRateRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      revenueCategoryId: data.revenueCategoryId.present
          ? data.revenueCategoryId.value
          : this.revenueCategoryId,
      rateBasisPoints: data.rateBasisPoints.present
          ? data.rateBasisPoints.value
          : this.rateBasisPoints,
      treatment: data.treatment.present ? data.treatment.value : this.treatment,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      effectiveTo: data.effectiveTo.present
          ? data.effectiveTo.value
          : this.effectiveTo,
      note: data.note.present ? data.note.value : this.note,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueTaxRateRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('rateBasisPoints: $rateBasisPoints, ')
          ..write('treatment: $treatment, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('note: $note, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    revenueCategoryId,
    rateBasisPoints,
    treatment,
    effectiveFrom,
    effectiveTo,
    note,
    archivedAt,
    createdBy,
    createdAt,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueTaxRateRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.revenueCategoryId == this.revenueCategoryId &&
          other.rateBasisPoints == this.rateBasisPoints &&
          other.treatment == this.treatment &&
          other.effectiveFrom == this.effectiveFrom &&
          other.effectiveTo == this.effectiveTo &&
          other.note == this.note &&
          other.archivedAt == this.archivedAt &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class RevenueTaxRatesCompanion extends UpdateCompanion<RevenueTaxRateRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> revenueCategoryId;
  final Value<int> rateBasisPoints;
  final Value<String> treatment;
  final Value<String> effectiveFrom;
  final Value<String?> effectiveTo;
  final Value<String?> note;
  final Value<DateTime?> archivedAt;
  final Value<String> createdBy;
  final Value<DateTime> createdAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RevenueTaxRatesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.revenueCategoryId = const Value.absent(),
    this.rateBasisPoints = const Value.absent(),
    this.treatment = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.note = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueTaxRatesCompanion.insert({
    required String id,
    required String orgId,
    required String revenueCategoryId,
    required int rateBasisPoints,
    required String treatment,
    required String effectiveFrom,
    this.effectiveTo = const Value.absent(),
    this.note = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required String createdBy,
    required DateTime createdAt,
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       revenueCategoryId = Value(revenueCategoryId),
       rateBasisPoints = Value(rateBasisPoints),
       treatment = Value(treatment),
       effectiveFrom = Value(effectiveFrom),
       createdBy = Value(createdBy),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RevenueTaxRateRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? revenueCategoryId,
    Expression<int>? rateBasisPoints,
    Expression<String>? treatment,
    Expression<String>? effectiveFrom,
    Expression<String>? effectiveTo,
    Expression<String>? note,
    Expression<DateTime>? archivedAt,
    Expression<String>? createdBy,
    Expression<DateTime>? createdAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (revenueCategoryId != null) 'revenue_category_id': revenueCategoryId,
      if (rateBasisPoints != null) 'rate_basis_points': rateBasisPoints,
      if (treatment != null) 'treatment': treatment,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (effectiveTo != null) 'effective_to': effectiveTo,
      if (note != null) 'note': note,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueTaxRatesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? revenueCategoryId,
    Value<int>? rateBasisPoints,
    Value<String>? treatment,
    Value<String>? effectiveFrom,
    Value<String?>? effectiveTo,
    Value<String?>? note,
    Value<DateTime?>? archivedAt,
    Value<String>? createdBy,
    Value<DateTime>? createdAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RevenueTaxRatesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
      rateBasisPoints: rateBasisPoints ?? this.rateBasisPoints,
      treatment: treatment ?? this.treatment,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: effectiveTo ?? this.effectiveTo,
      note: note ?? this.note,
      archivedAt: archivedAt ?? this.archivedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      rowVersion: rowVersion ?? this.rowVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (revenueCategoryId.present) {
      map['revenue_category_id'] = Variable<String>(revenueCategoryId.value);
    }
    if (rateBasisPoints.present) {
      map['rate_basis_points'] = Variable<int>(rateBasisPoints.value);
    }
    if (treatment.present) {
      map['treatment'] = Variable<String>(treatment.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<String>(effectiveFrom.value);
    }
    if (effectiveTo.present) {
      map['effective_to'] = Variable<String>(effectiveTo.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueTaxRatesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('rateBasisPoints: $rateBasisPoints, ')
          ..write('treatment: $treatment, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('note: $note, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppMetaTable appMeta = $AppMetaTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $BusinessUnitsTable businessUnits = $BusinessUnitsTable(this);
  late final $DepartmentsTable departments = $DepartmentsTable(this);
  late final $SectionsTable sections = $SectionsTable(this);
  late final $ExpenseCategoriesTable expenseCategories =
      $ExpenseCategoriesTable(this);
  late final $RevenueCategoriesTable revenueCategories =
      $RevenueCategoriesTable(this);
  late final $VendorsTable vendors = $VendorsTable(this);
  late final $PaymentMethodsTable paymentMethods = $PaymentMethodsTable(this);
  late final $PeriodLocksTable periodLocks = $PeriodLocksTable(this);
  late final $PeriodLockEventsTable periodLockEvents = $PeriodLockEventsTable(
    this,
  );
  late final $RevenueTaxRatesTable revenueTaxRates = $RevenueTaxRatesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appMeta,
    syncOutbox,
    businessUnits,
    departments,
    sections,
    expenseCategories,
    revenueCategories,
    vendors,
    paymentMethods,
    periodLocks,
    periodLockEvents,
    revenueTaxRates,
  ];
}

typedef $$AppMetaTableCreateCompanionBuilder =
    AppMetaCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppMetaTableUpdateCompanionBuilder =
    AppMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppMetaTableFilterComposer
    extends Composer<_$AppDatabase, $AppMetaTable> {
  $$AppMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $AppMetaTable> {
  $$AppMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppMetaTable> {
  $$AppMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppMetaTable,
          AppMetaRow,
          $$AppMetaTableFilterComposer,
          $$AppMetaTableOrderingComposer,
          $$AppMetaTableAnnotationComposer,
          $$AppMetaTableCreateCompanionBuilder,
          $$AppMetaTableUpdateCompanionBuilder,
          (
            AppMetaRow,
            BaseReferences<_$AppDatabase, $AppMetaTable, AppMetaRow>,
          ),
          AppMetaRow,
          PrefetchHooks Function()
        > {
  $$AppMetaTableTableManager(_$AppDatabase db, $AppMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppMetaCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppMetaCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppMetaTable,
      AppMetaRow,
      $$AppMetaTableFilterComposer,
      $$AppMetaTableOrderingComposer,
      $$AppMetaTableAnnotationComposer,
      $$AppMetaTableCreateCompanionBuilder,
      $$AppMetaTableUpdateCompanionBuilder,
      (AppMetaRow, BaseReferences<_$AppDatabase, $AppMetaTable, AppMetaRow>),
      AppMetaRow,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      required String mutationId,
      Value<String?> actorUserId,
      required String entityType,
      required String entityId,
      required String op,
      required String payload,
      Value<int?> baseRowVersion,
      Value<int> attemptCount,
      required DateTime nextAttemptAt,
      required String status,
      Value<String?> lastError,
      required DateTime createdAt,
      Value<DateTime?> inFlightSince,
      Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> mutationId,
      Value<String?> actorUserId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> op,
      Value<String> payload,
      Value<int?> baseRowVersion,
      Value<int> attemptCount,
      Value<DateTime> nextAttemptAt,
      Value<String> status,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime?> inFlightSince,
      Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorUserId => $composableBuilder(
    column: $table.actorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get inFlightSince => $composableBuilder(
    column: $table.inFlightSince,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorUserId => $composableBuilder(
    column: $table.actorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get inFlightSince => $composableBuilder(
    column: $table.inFlightSince,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actorUserId => $composableBuilder(
    column: $table.actorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get baseRowVersion => $composableBuilder(
    column: $table.baseRowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get inFlightSince => $composableBuilder(
    column: $table.inFlightSince,
    builder: (column) => column,
  );
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxRow,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxRow,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxRow>,
          ),
          SyncOutboxRow,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mutationId = const Value.absent(),
                Value<String?> actorUserId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int?> baseRowVersion = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> inFlightSince = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                mutationId: mutationId,
                actorUserId: actorUserId,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payload: payload,
                baseRowVersion: baseRowVersion,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                status: status,
                lastError: lastError,
                createdAt: createdAt,
                inFlightSince: inFlightSince,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mutationId,
                Value<String?> actorUserId = const Value.absent(),
                required String entityType,
                required String entityId,
                required String op,
                required String payload,
                Value<int?> baseRowVersion = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                required DateTime nextAttemptAt,
                required String status,
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> inFlightSince = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                mutationId: mutationId,
                actorUserId: actorUserId,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payload: payload,
                baseRowVersion: baseRowVersion,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                status: status,
                lastError: lastError,
                createdAt: createdAt,
                inFlightSince: inFlightSince,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxRow,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxRow,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxRow>,
      ),
      SyncOutboxRow,
      PrefetchHooks Function()
    >;
typedef $$BusinessUnitsTableCreateCompanionBuilder =
    BusinessUnitsCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      required String kind,
      Value<String> timezone,
      Value<String> businessDayCutoff,
      Value<int> rowid,
    });
typedef $$BusinessUnitsTableUpdateCompanionBuilder =
    BusinessUnitsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String> kind,
      Value<String> timezone,
      Value<String> businessDayCutoff,
      Value<int> rowid,
    });

final class $$BusinessUnitsTableReferences
    extends
        BaseReferences<_$AppDatabase, $BusinessUnitsTable, BusinessUnitRow> {
  $$BusinessUnitsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$DepartmentsTable, List<DepartmentRow>>
  _departmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.departments,
    aliasName: 'business_units__id__departments__business_unit_id',
  );

  $$DepartmentsTableProcessedTableManager get departmentsRefs {
    final manager = $$DepartmentsTableTableManager(
      $_db,
      $_db.departments,
    ).filter((f) => f.businessUnitId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_departmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RevenueCategoriesTable, List<RevenueCategoryRow>>
  _revenueCategoriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.revenueCategories,
        aliasName: 'business_units__id__revenue_categories__business_unit_id',
      );

  $$RevenueCategoriesTableProcessedTableManager get revenueCategoriesRefs {
    final manager = $$RevenueCategoriesTableTableManager(
      $_db,
      $_db.revenueCategories,
    ).filter((f) => f.businessUnitId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _revenueCategoriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PeriodLocksTable, List<PeriodLockRow>>
  _periodLocksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.periodLocks,
    aliasName: 'business_units__id__period_locks__business_unit_id',
  );

  $$PeriodLocksTableProcessedTableManager get periodLocksRefs {
    final manager = $$PeriodLocksTableTableManager(
      $_db,
      $_db.periodLocks,
    ).filter((f) => f.businessUnitId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_periodLocksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BusinessUnitsTableFilterComposer
    extends Composer<_$AppDatabase, $BusinessUnitsTable> {
  $$BusinessUnitsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessDayCutoff => $composableBuilder(
    column: $table.businessDayCutoff,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> departmentsRefs(
    Expression<bool> Function($$DepartmentsTableFilterComposer f) f,
  ) {
    final $$DepartmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.departments,
      getReferencedColumn: (t) => t.businessUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DepartmentsTableFilterComposer(
            $db: $db,
            $table: $db.departments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> revenueCategoriesRefs(
    Expression<bool> Function($$RevenueCategoriesTableFilterComposer f) f,
  ) {
    final $$RevenueCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revenueCategories,
      getReferencedColumn: (t) => t.businessUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.revenueCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> periodLocksRefs(
    Expression<bool> Function($$PeriodLocksTableFilterComposer f) f,
  ) {
    final $$PeriodLocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.periodLocks,
      getReferencedColumn: (t) => t.businessUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLocksTableFilterComposer(
            $db: $db,
            $table: $db.periodLocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BusinessUnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $BusinessUnitsTable> {
  $$BusinessUnitsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessDayCutoff => $composableBuilder(
    column: $table.businessDayCutoff,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BusinessUnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BusinessUnitsTable> {
  $$BusinessUnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<String> get businessDayCutoff => $composableBuilder(
    column: $table.businessDayCutoff,
    builder: (column) => column,
  );

  Expression<T> departmentsRefs<T extends Object>(
    Expression<T> Function($$DepartmentsTableAnnotationComposer a) f,
  ) {
    final $$DepartmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.departments,
      getReferencedColumn: (t) => t.businessUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DepartmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.departments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> revenueCategoriesRefs<T extends Object>(
    Expression<T> Function($$RevenueCategoriesTableAnnotationComposer a) f,
  ) {
    final $$RevenueCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revenueCategories,
          getReferencedColumn: (t) => t.businessUnitId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.revenueCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> periodLocksRefs<T extends Object>(
    Expression<T> Function($$PeriodLocksTableAnnotationComposer a) f,
  ) {
    final $$PeriodLocksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.periodLocks,
      getReferencedColumn: (t) => t.businessUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLocksTableAnnotationComposer(
            $db: $db,
            $table: $db.periodLocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BusinessUnitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BusinessUnitsTable,
          BusinessUnitRow,
          $$BusinessUnitsTableFilterComposer,
          $$BusinessUnitsTableOrderingComposer,
          $$BusinessUnitsTableAnnotationComposer,
          $$BusinessUnitsTableCreateCompanionBuilder,
          $$BusinessUnitsTableUpdateCompanionBuilder,
          (BusinessUnitRow, $$BusinessUnitsTableReferences),
          BusinessUnitRow,
          PrefetchHooks Function({
            bool departmentsRefs,
            bool revenueCategoriesRefs,
            bool periodLocksRefs,
          })
        > {
  $$BusinessUnitsTableTableManager(_$AppDatabase db, $BusinessUnitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BusinessUnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BusinessUnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BusinessUnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<String> businessDayCutoff = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BusinessUnitsCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                kind: kind,
                timezone: timezone,
                businessDayCutoff: businessDayCutoff,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                required String kind,
                Value<String> timezone = const Value.absent(),
                Value<String> businessDayCutoff = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BusinessUnitsCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                kind: kind,
                timezone: timezone,
                businessDayCutoff: businessDayCutoff,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BusinessUnitsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                departmentsRefs = false,
                revenueCategoriesRefs = false,
                periodLocksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (departmentsRefs) db.departments,
                    if (revenueCategoriesRefs) db.revenueCategories,
                    if (periodLocksRefs) db.periodLocks,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (departmentsRefs)
                        await $_getPrefetchedData<
                          BusinessUnitRow,
                          $BusinessUnitsTable,
                          DepartmentRow
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessUnitsTableReferences
                              ._departmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessUnitsTableReferences(
                                db,
                                table,
                                p0,
                              ).departmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessUnitId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (revenueCategoriesRefs)
                        await $_getPrefetchedData<
                          BusinessUnitRow,
                          $BusinessUnitsTable,
                          RevenueCategoryRow
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessUnitsTableReferences
                              ._revenueCategoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessUnitsTableReferences(
                                db,
                                table,
                                p0,
                              ).revenueCategoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessUnitId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (periodLocksRefs)
                        await $_getPrefetchedData<
                          BusinessUnitRow,
                          $BusinessUnitsTable,
                          PeriodLockRow
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessUnitsTableReferences
                              ._periodLocksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessUnitsTableReferences(
                                db,
                                table,
                                p0,
                              ).periodLocksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessUnitId == item.id,
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

typedef $$BusinessUnitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BusinessUnitsTable,
      BusinessUnitRow,
      $$BusinessUnitsTableFilterComposer,
      $$BusinessUnitsTableOrderingComposer,
      $$BusinessUnitsTableAnnotationComposer,
      $$BusinessUnitsTableCreateCompanionBuilder,
      $$BusinessUnitsTableUpdateCompanionBuilder,
      (BusinessUnitRow, $$BusinessUnitsTableReferences),
      BusinessUnitRow,
      PrefetchHooks Function({
        bool departmentsRefs,
        bool revenueCategoriesRefs,
        bool periodLocksRefs,
      })
    >;
typedef $$DepartmentsTableCreateCompanionBuilder =
    DepartmentsCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      required String businessUnitId,
      Value<int> rowid,
    });
typedef $$DepartmentsTableUpdateCompanionBuilder =
    DepartmentsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String> businessUnitId,
      Value<int> rowid,
    });

final class $$DepartmentsTableReferences
    extends BaseReferences<_$AppDatabase, $DepartmentsTable, DepartmentRow> {
  $$DepartmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessUnitsTable _businessUnitIdTable(_$AppDatabase db) => db
      .businessUnits
      .createAlias('departments__business_unit_id__business_units__id');

  $$BusinessUnitsTableProcessedTableManager get businessUnitId {
    final $_column = $_itemColumn<String>('business_unit_id')!;

    final manager = $$BusinessUnitsTableTableManager(
      $_db,
      $_db.businessUnits,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SectionsTable, List<SectionRow>>
  _sectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sections,
    aliasName: 'departments__id__sections__department_id',
  );

  $$SectionsTableProcessedTableManager get sectionsRefs {
    final manager = $$SectionsTableTableManager(
      $_db,
      $_db.sections,
    ).filter((f) => f.departmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DepartmentsTableFilterComposer
    extends Composer<_$AppDatabase, $DepartmentsTable> {
  $$DepartmentsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessUnitsTableFilterComposer get businessUnitId {
    final $$BusinessUnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableFilterComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sectionsRefs(
    Expression<bool> Function($$SectionsTableFilterComposer f) f,
  ) {
    final $$SectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sections,
      getReferencedColumn: (t) => t.departmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SectionsTableFilterComposer(
            $db: $db,
            $table: $db.sections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DepartmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DepartmentsTable> {
  $$DepartmentsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessUnitsTableOrderingComposer get businessUnitId {
    final $$BusinessUnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableOrderingComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DepartmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DepartmentsTable> {
  $$DepartmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BusinessUnitsTableAnnotationComposer get businessUnitId {
    final $$BusinessUnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sectionsRefs<T extends Object>(
    Expression<T> Function($$SectionsTableAnnotationComposer a) f,
  ) {
    final $$SectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sections,
      getReferencedColumn: (t) => t.departmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DepartmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DepartmentsTable,
          DepartmentRow,
          $$DepartmentsTableFilterComposer,
          $$DepartmentsTableOrderingComposer,
          $$DepartmentsTableAnnotationComposer,
          $$DepartmentsTableCreateCompanionBuilder,
          $$DepartmentsTableUpdateCompanionBuilder,
          (DepartmentRow, $$DepartmentsTableReferences),
          DepartmentRow,
          PrefetchHooks Function({bool businessUnitId, bool sectionsRefs})
        > {
  $$DepartmentsTableTableManager(_$AppDatabase db, $DepartmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DepartmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DepartmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DepartmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DepartmentsCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                businessUnitId: businessUnitId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                required String businessUnitId,
                Value<int> rowid = const Value.absent(),
              }) => DepartmentsCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                businessUnitId: businessUnitId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DepartmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({businessUnitId = false, sectionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (sectionsRefs) db.sections],
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
                        if (businessUnitId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessUnitId,
                                    referencedTable:
                                        $$DepartmentsTableReferences
                                            ._businessUnitIdTable(db),
                                    referencedColumn:
                                        $$DepartmentsTableReferences
                                            ._businessUnitIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sectionsRefs)
                        await $_getPrefetchedData<
                          DepartmentRow,
                          $DepartmentsTable,
                          SectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$DepartmentsTableReferences
                              ._sectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DepartmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).sectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.departmentId == item.id,
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

typedef $$DepartmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DepartmentsTable,
      DepartmentRow,
      $$DepartmentsTableFilterComposer,
      $$DepartmentsTableOrderingComposer,
      $$DepartmentsTableAnnotationComposer,
      $$DepartmentsTableCreateCompanionBuilder,
      $$DepartmentsTableUpdateCompanionBuilder,
      (DepartmentRow, $$DepartmentsTableReferences),
      DepartmentRow,
      PrefetchHooks Function({bool businessUnitId, bool sectionsRefs})
    >;
typedef $$SectionsTableCreateCompanionBuilder =
    SectionsCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      required String departmentId,
      Value<int> rowid,
    });
typedef $$SectionsTableUpdateCompanionBuilder =
    SectionsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String> departmentId,
      Value<int> rowid,
    });

final class $$SectionsTableReferences
    extends BaseReferences<_$AppDatabase, $SectionsTable, SectionRow> {
  $$SectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DepartmentsTable _departmentIdTable(_$AppDatabase db) =>
      db.departments.createAlias('sections__department_id__departments__id');

  $$DepartmentsTableProcessedTableManager get departmentId {
    final $_column = $_itemColumn<String>('department_id')!;

    final manager = $$DepartmentsTableTableManager(
      $_db,
      $_db.departments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_departmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ExpenseCategoriesTable, List<ExpenseCategoryRow>>
  _expenseCategoriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.expenseCategories,
        aliasName: 'sections__id__expense_categories__section_id',
      );

  $$ExpenseCategoriesTableProcessedTableManager get expenseCategoriesRefs {
    final manager = $$ExpenseCategoriesTableTableManager(
      $_db,
      $_db.expenseCategories,
    ).filter((f) => f.sectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _expenseCategoriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SectionsTableFilterComposer
    extends Composer<_$AppDatabase, $SectionsTable> {
  $$SectionsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DepartmentsTableFilterComposer get departmentId {
    final $$DepartmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.departmentId,
      referencedTable: $db.departments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DepartmentsTableFilterComposer(
            $db: $db,
            $table: $db.departments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> expenseCategoriesRefs(
    Expression<bool> Function($$ExpenseCategoriesTableFilterComposer f) f,
  ) {
    final $$ExpenseCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenseCategories,
      getReferencedColumn: (t) => t.sectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpenseCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.expenseCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SectionsTable> {
  $$SectionsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DepartmentsTableOrderingComposer get departmentId {
    final $$DepartmentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.departmentId,
      referencedTable: $db.departments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DepartmentsTableOrderingComposer(
            $db: $db,
            $table: $db.departments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SectionsTable> {
  $$SectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$DepartmentsTableAnnotationComposer get departmentId {
    final $$DepartmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.departmentId,
      referencedTable: $db.departments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DepartmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.departments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> expenseCategoriesRefs<T extends Object>(
    Expression<T> Function($$ExpenseCategoriesTableAnnotationComposer a) f,
  ) {
    final $$ExpenseCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expenseCategories,
          getReferencedColumn: (t) => t.sectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpenseCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.expenseCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SectionsTable,
          SectionRow,
          $$SectionsTableFilterComposer,
          $$SectionsTableOrderingComposer,
          $$SectionsTableAnnotationComposer,
          $$SectionsTableCreateCompanionBuilder,
          $$SectionsTableUpdateCompanionBuilder,
          (SectionRow, $$SectionsTableReferences),
          SectionRow,
          PrefetchHooks Function({
            bool departmentId,
            bool expenseCategoriesRefs,
          })
        > {
  $$SectionsTableTableManager(_$AppDatabase db, $SectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> departmentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SectionsCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                departmentId: departmentId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                required String departmentId,
                Value<int> rowid = const Value.absent(),
              }) => SectionsCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                departmentId: departmentId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({departmentId = false, expenseCategoriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (expenseCategoriesRefs) db.expenseCategories,
                  ],
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
                        if (departmentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.departmentId,
                                    referencedTable: $$SectionsTableReferences
                                        ._departmentIdTable(db),
                                    referencedColumn: $$SectionsTableReferences
                                        ._departmentIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (expenseCategoriesRefs)
                        await $_getPrefetchedData<
                          SectionRow,
                          $SectionsTable,
                          ExpenseCategoryRow
                        >(
                          currentTable: table,
                          referencedTable: $$SectionsTableReferences
                              ._expenseCategoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SectionsTableReferences(
                                db,
                                table,
                                p0,
                              ).expenseCategoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sectionId == item.id,
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

typedef $$SectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SectionsTable,
      SectionRow,
      $$SectionsTableFilterComposer,
      $$SectionsTableOrderingComposer,
      $$SectionsTableAnnotationComposer,
      $$SectionsTableCreateCompanionBuilder,
      $$SectionsTableUpdateCompanionBuilder,
      (SectionRow, $$SectionsTableReferences),
      SectionRow,
      PrefetchHooks Function({bool departmentId, bool expenseCategoriesRefs})
    >;
typedef $$ExpenseCategoriesTableCreateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      required String sectionId,
      Value<String> nature,
      Value<bool> isSharedByDefault,
      Value<int> rowid,
    });
typedef $$ExpenseCategoriesTableUpdateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String> sectionId,
      Value<String> nature,
      Value<bool> isSharedByDefault,
      Value<int> rowid,
    });

final class $$ExpenseCategoriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow
        > {
  $$ExpenseCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SectionsTable _sectionIdTable(_$AppDatabase db) =>
      db.sections.createAlias('expense_categories__section_id__sections__id');

  $$SectionsTableProcessedTableManager get sectionId {
    final $_column = $_itemColumn<String>('section_id')!;

    final manager = $$SectionsTableTableManager(
      $_db,
      $_db.sections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExpenseCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nature => $composableBuilder(
    column: $table.nature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSharedByDefault => $composableBuilder(
    column: $table.isSharedByDefault,
    builder: (column) => ColumnFilters(column),
  );

  $$SectionsTableFilterComposer get sectionId {
    final $$SectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sectionId,
      referencedTable: $db.sections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SectionsTableFilterComposer(
            $db: $db,
            $table: $db.sections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nature => $composableBuilder(
    column: $table.nature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSharedByDefault => $composableBuilder(
    column: $table.isSharedByDefault,
    builder: (column) => ColumnOrderings(column),
  );

  $$SectionsTableOrderingComposer get sectionId {
    final $$SectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sectionId,
      referencedTable: $db.sections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SectionsTableOrderingComposer(
            $db: $db,
            $table: $db.sections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get nature =>
      $composableBuilder(column: $table.nature, builder: (column) => column);

  GeneratedColumn<bool> get isSharedByDefault => $composableBuilder(
    column: $table.isSharedByDefault,
    builder: (column) => column,
  );

  $$SectionsTableAnnotationComposer get sectionId {
    final $$SectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sectionId,
      referencedTable: $db.sections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow,
          $$ExpenseCategoriesTableFilterComposer,
          $$ExpenseCategoriesTableOrderingComposer,
          $$ExpenseCategoriesTableAnnotationComposer,
          $$ExpenseCategoriesTableCreateCompanionBuilder,
          $$ExpenseCategoriesTableUpdateCompanionBuilder,
          (ExpenseCategoryRow, $$ExpenseCategoriesTableReferences),
          ExpenseCategoryRow,
          PrefetchHooks Function({bool sectionId})
        > {
  $$ExpenseCategoriesTableTableManager(
    _$AppDatabase db,
    $ExpenseCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> nature = const Value.absent(),
                Value<bool> isSharedByDefault = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseCategoriesCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                sectionId: sectionId,
                nature: nature,
                isSharedByDefault: isSharedByDefault,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                required String sectionId,
                Value<String> nature = const Value.absent(),
                Value<bool> isSharedByDefault = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseCategoriesCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                sectionId: sectionId,
                nature: nature,
                isSharedByDefault: isSharedByDefault,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpenseCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sectionId = false}) {
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
                    if (sectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sectionId,
                                referencedTable:
                                    $$ExpenseCategoriesTableReferences
                                        ._sectionIdTable(db),
                                referencedColumn:
                                    $$ExpenseCategoriesTableReferences
                                        ._sectionIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$ExpenseCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpenseCategoriesTable,
      ExpenseCategoryRow,
      $$ExpenseCategoriesTableFilterComposer,
      $$ExpenseCategoriesTableOrderingComposer,
      $$ExpenseCategoriesTableAnnotationComposer,
      $$ExpenseCategoriesTableCreateCompanionBuilder,
      $$ExpenseCategoriesTableUpdateCompanionBuilder,
      (ExpenseCategoryRow, $$ExpenseCategoriesTableReferences),
      ExpenseCategoryRow,
      PrefetchHooks Function({bool sectionId})
    >;
typedef $$RevenueCategoriesTableCreateCompanionBuilder =
    RevenueCategoriesCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      required String businessUnitId,
      Value<int> rowid,
    });
typedef $$RevenueCategoriesTableUpdateCompanionBuilder =
    RevenueCategoriesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String> businessUnitId,
      Value<int> rowid,
    });

final class $$RevenueCategoriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevenueCategoriesTable,
          RevenueCategoryRow
        > {
  $$RevenueCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessUnitsTable _businessUnitIdTable(_$AppDatabase db) => db
      .businessUnits
      .createAlias('revenue_categories__business_unit_id__business_units__id');

  $$BusinessUnitsTableProcessedTableManager get businessUnitId {
    final $_column = $_itemColumn<String>('business_unit_id')!;

    final manager = $$BusinessUnitsTableTableManager(
      $_db,
      $_db.businessUnits,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RevenueTaxRatesTable, List<RevenueTaxRateRow>>
  _revenueTaxRatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.revenueTaxRates,
    aliasName: 'revenue_categories__id__revenue_tax_rates__revenue_category_id',
  );

  $$RevenueTaxRatesTableProcessedTableManager get revenueTaxRatesRefs {
    final manager =
        $$RevenueTaxRatesTableTableManager($_db, $_db.revenueTaxRates).filter(
          (f) => f.revenueCategoryId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _revenueTaxRatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RevenueCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueCategoriesTable> {
  $$RevenueCategoriesTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessUnitsTableFilterComposer get businessUnitId {
    final $$BusinessUnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableFilterComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> revenueTaxRatesRefs(
    Expression<bool> Function($$RevenueTaxRatesTableFilterComposer f) f,
  ) {
    final $$RevenueTaxRatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revenueTaxRates,
      getReferencedColumn: (t) => t.revenueCategoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueTaxRatesTableFilterComposer(
            $db: $db,
            $table: $db.revenueTaxRates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RevenueCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueCategoriesTable> {
  $$RevenueCategoriesTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessUnitsTableOrderingComposer get businessUnitId {
    final $$BusinessUnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableOrderingComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueCategoriesTable> {
  $$RevenueCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BusinessUnitsTableAnnotationComposer get businessUnitId {
    final $$BusinessUnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> revenueTaxRatesRefs<T extends Object>(
    Expression<T> Function($$RevenueTaxRatesTableAnnotationComposer a) f,
  ) {
    final $$RevenueTaxRatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revenueTaxRates,
      getReferencedColumn: (t) => t.revenueCategoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueTaxRatesTableAnnotationComposer(
            $db: $db,
            $table: $db.revenueTaxRates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RevenueCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueCategoriesTable,
          RevenueCategoryRow,
          $$RevenueCategoriesTableFilterComposer,
          $$RevenueCategoriesTableOrderingComposer,
          $$RevenueCategoriesTableAnnotationComposer,
          $$RevenueCategoriesTableCreateCompanionBuilder,
          $$RevenueCategoriesTableUpdateCompanionBuilder,
          (RevenueCategoryRow, $$RevenueCategoriesTableReferences),
          RevenueCategoryRow,
          PrefetchHooks Function({
            bool businessUnitId,
            bool revenueTaxRatesRefs,
          })
        > {
  $$RevenueCategoriesTableTableManager(
    _$AppDatabase db,
    $RevenueCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevenueCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevenueCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueCategoriesCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                businessUnitId: businessUnitId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                required String businessUnitId,
                Value<int> rowid = const Value.absent(),
              }) => RevenueCategoriesCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                businessUnitId: businessUnitId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({businessUnitId = false, revenueTaxRatesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (revenueTaxRatesRefs) db.revenueTaxRates,
                  ],
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
                        if (businessUnitId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessUnitId,
                                    referencedTable:
                                        $$RevenueCategoriesTableReferences
                                            ._businessUnitIdTable(db),
                                    referencedColumn:
                                        $$RevenueCategoriesTableReferences
                                            ._businessUnitIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (revenueTaxRatesRefs)
                        await $_getPrefetchedData<
                          RevenueCategoryRow,
                          $RevenueCategoriesTable,
                          RevenueTaxRateRow
                        >(
                          currentTable: table,
                          referencedTable: $$RevenueCategoriesTableReferences
                              ._revenueTaxRatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RevenueCategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).revenueTaxRatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.revenueCategoryId == item.id,
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

typedef $$RevenueCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueCategoriesTable,
      RevenueCategoryRow,
      $$RevenueCategoriesTableFilterComposer,
      $$RevenueCategoriesTableOrderingComposer,
      $$RevenueCategoriesTableAnnotationComposer,
      $$RevenueCategoriesTableCreateCompanionBuilder,
      $$RevenueCategoriesTableUpdateCompanionBuilder,
      (RevenueCategoryRow, $$RevenueCategoriesTableReferences),
      RevenueCategoryRow,
      PrefetchHooks Function({bool businessUnitId, bool revenueTaxRatesRefs})
    >;
typedef $$VendorsTableCreateCompanionBuilder =
    VendorsCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<String?> gstin,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> defaultCategoryId,
      Value<String?> defaultBusinessUnitId,
      Value<String?> notes,
      Value<int> rowid,
    });
typedef $$VendorsTableUpdateCompanionBuilder =
    VendorsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<String?> gstin,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> defaultCategoryId,
      Value<String?> defaultBusinessUnitId,
      Value<String?> notes,
      Value<int> rowid,
    });

class $$VendorsTableFilterComposer
    extends Composer<_$AppDatabase, $VendorsTable> {
  $$VendorsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gstin => $composableBuilder(
    column: $table.gstin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultCategoryId => $composableBuilder(
    column: $table.defaultCategoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultBusinessUnitId => $composableBuilder(
    column: $table.defaultBusinessUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VendorsTableOrderingComposer
    extends Composer<_$AppDatabase, $VendorsTable> {
  $$VendorsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gstin => $composableBuilder(
    column: $table.gstin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultCategoryId => $composableBuilder(
    column: $table.defaultCategoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultBusinessUnitId => $composableBuilder(
    column: $table.defaultBusinessUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VendorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VendorsTable> {
  $$VendorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get gstin =>
      $composableBuilder(column: $table.gstin, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get defaultCategoryId => $composableBuilder(
    column: $table.defaultCategoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultBusinessUnitId => $composableBuilder(
    column: $table.defaultBusinessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);
}

class $$VendorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VendorsTable,
          VendorRow,
          $$VendorsTableFilterComposer,
          $$VendorsTableOrderingComposer,
          $$VendorsTableAnnotationComposer,
          $$VendorsTableCreateCompanionBuilder,
          $$VendorsTableUpdateCompanionBuilder,
          (VendorRow, BaseReferences<_$AppDatabase, $VendorsTable, VendorRow>),
          VendorRow,
          PrefetchHooks Function()
        > {
  $$VendorsTableTableManager(_$AppDatabase db, $VendorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VendorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VendorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VendorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> gstin = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> defaultCategoryId = const Value.absent(),
                Value<String?> defaultBusinessUnitId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VendorsCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                gstin: gstin,
                phone: phone,
                address: address,
                defaultCategoryId: defaultCategoryId,
                defaultBusinessUnitId: defaultBusinessUnitId,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<String?> gstin = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> defaultCategoryId = const Value.absent(),
                Value<String?> defaultBusinessUnitId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VendorsCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                gstin: gstin,
                phone: phone,
                address: address,
                defaultCategoryId: defaultCategoryId,
                defaultBusinessUnitId: defaultBusinessUnitId,
                notes: notes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VendorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VendorsTable,
      VendorRow,
      $$VendorsTableFilterComposer,
      $$VendorsTableOrderingComposer,
      $$VendorsTableAnnotationComposer,
      $$VendorsTableCreateCompanionBuilder,
      $$VendorsTableUpdateCompanionBuilder,
      (VendorRow, BaseReferences<_$AppDatabase, $VendorsTable, VendorRow>),
      VendorRow,
      PrefetchHooks Function()
    >;
typedef $$PaymentMethodsTableCreateCompanionBuilder =
    PaymentMethodsCompanion Function({
      required String id,
      required String orgId,
      required String code,
      required String name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<bool> requiresReference,
      Value<int> rowid,
    });
typedef $$PaymentMethodsTableUpdateCompanionBuilder =
    PaymentMethodsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> code,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<bool> requiresReference,
      Value<int> rowid,
    });

class $$PaymentMethodsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresReference => $composableBuilder(
    column: $table.requiresReference,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PaymentMethodsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresReference => $composableBuilder(
    column: $table.requiresReference,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PaymentMethodsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentMethodsTable> {
  $$PaymentMethodsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get requiresReference => $composableBuilder(
    column: $table.requiresReference,
    builder: (column) => column,
  );
}

class $$PaymentMethodsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentMethodsTable,
          PaymentMethodRow,
          $$PaymentMethodsTableFilterComposer,
          $$PaymentMethodsTableOrderingComposer,
          $$PaymentMethodsTableAnnotationComposer,
          $$PaymentMethodsTableCreateCompanionBuilder,
          $$PaymentMethodsTableUpdateCompanionBuilder,
          (
            PaymentMethodRow,
            BaseReferences<
              _$AppDatabase,
              $PaymentMethodsTable,
              PaymentMethodRow
            >,
          ),
          PaymentMethodRow,
          PrefetchHooks Function()
        > {
  $$PaymentMethodsTableTableManager(
    _$AppDatabase db,
    $PaymentMethodsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentMethodsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentMethodsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentMethodsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> requiresReference = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaymentMethodsCompanion(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                requiresReference: requiresReference,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String code,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> requiresReference = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaymentMethodsCompanion.insert(
                id: id,
                orgId: orgId,
                code: code,
                name: name,
                sortOrder: sortOrder,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                requiresReference: requiresReference,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PaymentMethodsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentMethodsTable,
      PaymentMethodRow,
      $$PaymentMethodsTableFilterComposer,
      $$PaymentMethodsTableOrderingComposer,
      $$PaymentMethodsTableAnnotationComposer,
      $$PaymentMethodsTableCreateCompanionBuilder,
      $$PaymentMethodsTableUpdateCompanionBuilder,
      (
        PaymentMethodRow,
        BaseReferences<_$AppDatabase, $PaymentMethodsTable, PaymentMethodRow>,
      ),
      PaymentMethodRow,
      PrefetchHooks Function()
    >;
typedef $$PeriodLocksTableCreateCompanionBuilder =
    PeriodLocksCompanion Function({
      required String id,
      required String orgId,
      Value<String?> businessUnitId,
      required String periodKey,
      required String state,
      Value<String?> closedBy,
      Value<DateTime?> closedAt,
      Value<String?> reopenedBy,
      Value<DateTime?> reopenedAt,
      Value<String?> reopenReason,
      Value<int> rowVersion,
      Value<int> rowid,
    });
typedef $$PeriodLocksTableUpdateCompanionBuilder =
    PeriodLocksCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String?> businessUnitId,
      Value<String> periodKey,
      Value<String> state,
      Value<String?> closedBy,
      Value<DateTime?> closedAt,
      Value<String?> reopenedBy,
      Value<DateTime?> reopenedAt,
      Value<String?> reopenReason,
      Value<int> rowVersion,
      Value<int> rowid,
    });

final class $$PeriodLocksTableReferences
    extends BaseReferences<_$AppDatabase, $PeriodLocksTable, PeriodLockRow> {
  $$PeriodLocksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessUnitsTable _businessUnitIdTable(_$AppDatabase db) => db
      .businessUnits
      .createAlias('period_locks__business_unit_id__business_units__id');

  $$BusinessUnitsTableProcessedTableManager? get businessUnitId {
    final $_column = $_itemColumn<String>('business_unit_id');
    if ($_column == null) return null;
    final manager = $$BusinessUnitsTableTableManager(
      $_db,
      $_db.businessUnits,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PeriodLockEventsTable, List<PeriodLockEventRow>>
  _periodLockEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.periodLockEvents,
    aliasName: 'period_locks__id__period_lock_events__period_lock_id',
  );

  $$PeriodLockEventsTableProcessedTableManager get periodLockEventsRefs {
    final manager = $$PeriodLockEventsTableTableManager(
      $_db,
      $_db.periodLockEvents,
    ).filter((f) => f.periodLockId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _periodLockEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PeriodLocksTableFilterComposer
    extends Composer<_$AppDatabase, $PeriodLocksTable> {
  $$PeriodLocksTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get closedBy => $composableBuilder(
    column: $table.closedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reopenedBy => $composableBuilder(
    column: $table.reopenedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reopenedAt => $composableBuilder(
    column: $table.reopenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reopenReason => $composableBuilder(
    column: $table.reopenReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessUnitsTableFilterComposer get businessUnitId {
    final $$BusinessUnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableFilterComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> periodLockEventsRefs(
    Expression<bool> Function($$PeriodLockEventsTableFilterComposer f) f,
  ) {
    final $$PeriodLockEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.periodLockEvents,
      getReferencedColumn: (t) => t.periodLockId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLockEventsTableFilterComposer(
            $db: $db,
            $table: $db.periodLockEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeriodLocksTableOrderingComposer
    extends Composer<_$AppDatabase, $PeriodLocksTable> {
  $$PeriodLocksTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closedBy => $composableBuilder(
    column: $table.closedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reopenedBy => $composableBuilder(
    column: $table.reopenedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reopenedAt => $composableBuilder(
    column: $table.reopenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reopenReason => $composableBuilder(
    column: $table.reopenReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessUnitsTableOrderingComposer get businessUnitId {
    final $$BusinessUnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableOrderingComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PeriodLocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeriodLocksTable> {
  $$PeriodLocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get periodKey =>
      $composableBuilder(column: $table.periodKey, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get closedBy =>
      $composableBuilder(column: $table.closedBy, builder: (column) => column);

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<String> get reopenedBy => $composableBuilder(
    column: $table.reopenedBy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reopenedAt => $composableBuilder(
    column: $table.reopenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reopenReason => $composableBuilder(
    column: $table.reopenReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  $$BusinessUnitsTableAnnotationComposer get businessUnitId {
    final $$BusinessUnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessUnitId,
      referencedTable: $db.businessUnits,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessUnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.businessUnits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> periodLockEventsRefs<T extends Object>(
    Expression<T> Function($$PeriodLockEventsTableAnnotationComposer a) f,
  ) {
    final $$PeriodLockEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.periodLockEvents,
      getReferencedColumn: (t) => t.periodLockId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLockEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.periodLockEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeriodLocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeriodLocksTable,
          PeriodLockRow,
          $$PeriodLocksTableFilterComposer,
          $$PeriodLocksTableOrderingComposer,
          $$PeriodLocksTableAnnotationComposer,
          $$PeriodLocksTableCreateCompanionBuilder,
          $$PeriodLocksTableUpdateCompanionBuilder,
          (PeriodLockRow, $$PeriodLocksTableReferences),
          PeriodLockRow,
          PrefetchHooks Function({
            bool businessUnitId,
            bool periodLockEventsRefs,
          })
        > {
  $$PeriodLocksTableTableManager(_$AppDatabase db, $PeriodLocksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeriodLocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeriodLocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeriodLocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String?> businessUnitId = const Value.absent(),
                Value<String> periodKey = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> closedBy = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<String?> reopenedBy = const Value.absent(),
                Value<DateTime?> reopenedAt = const Value.absent(),
                Value<String?> reopenReason = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeriodLocksCompanion(
                id: id,
                orgId: orgId,
                businessUnitId: businessUnitId,
                periodKey: periodKey,
                state: state,
                closedBy: closedBy,
                closedAt: closedAt,
                reopenedBy: reopenedBy,
                reopenedAt: reopenedAt,
                reopenReason: reopenReason,
                rowVersion: rowVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                Value<String?> businessUnitId = const Value.absent(),
                required String periodKey,
                required String state,
                Value<String?> closedBy = const Value.absent(),
                Value<DateTime?> closedAt = const Value.absent(),
                Value<String?> reopenedBy = const Value.absent(),
                Value<DateTime?> reopenedAt = const Value.absent(),
                Value<String?> reopenReason = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeriodLocksCompanion.insert(
                id: id,
                orgId: orgId,
                businessUnitId: businessUnitId,
                periodKey: periodKey,
                state: state,
                closedBy: closedBy,
                closedAt: closedAt,
                reopenedBy: reopenedBy,
                reopenedAt: reopenedAt,
                reopenReason: reopenReason,
                rowVersion: rowVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PeriodLocksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({businessUnitId = false, periodLockEventsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (periodLockEventsRefs) db.periodLockEvents,
                  ],
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
                        if (businessUnitId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessUnitId,
                                    referencedTable:
                                        $$PeriodLocksTableReferences
                                            ._businessUnitIdTable(db),
                                    referencedColumn:
                                        $$PeriodLocksTableReferences
                                            ._businessUnitIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (periodLockEventsRefs)
                        await $_getPrefetchedData<
                          PeriodLockRow,
                          $PeriodLocksTable,
                          PeriodLockEventRow
                        >(
                          currentTable: table,
                          referencedTable: $$PeriodLocksTableReferences
                              ._periodLockEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PeriodLocksTableReferences(
                                db,
                                table,
                                p0,
                              ).periodLockEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.periodLockId == item.id,
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

typedef $$PeriodLocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeriodLocksTable,
      PeriodLockRow,
      $$PeriodLocksTableFilterComposer,
      $$PeriodLocksTableOrderingComposer,
      $$PeriodLocksTableAnnotationComposer,
      $$PeriodLocksTableCreateCompanionBuilder,
      $$PeriodLocksTableUpdateCompanionBuilder,
      (PeriodLockRow, $$PeriodLocksTableReferences),
      PeriodLockRow,
      PrefetchHooks Function({bool businessUnitId, bool periodLockEventsRefs})
    >;
typedef $$PeriodLockEventsTableCreateCompanionBuilder =
    PeriodLockEventsCompanion Function({
      required String id,
      required String orgId,
      required String periodLockId,
      required String action,
      Value<String?> reason,
      required String actorId,
      required DateTime occurredAt,
      Value<int> rowid,
    });
typedef $$PeriodLockEventsTableUpdateCompanionBuilder =
    PeriodLockEventsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> periodLockId,
      Value<String> action,
      Value<String?> reason,
      Value<String> actorId,
      Value<DateTime> occurredAt,
      Value<int> rowid,
    });

final class $$PeriodLockEventsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PeriodLockEventsTable,
          PeriodLockEventRow
        > {
  $$PeriodLockEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PeriodLocksTable _periodLockIdTable(_$AppDatabase db) => db
      .periodLocks
      .createAlias('period_lock_events__period_lock_id__period_locks__id');

  $$PeriodLocksTableProcessedTableManager get periodLockId {
    final $_column = $_itemColumn<String>('period_lock_id')!;

    final manager = $$PeriodLocksTableTableManager(
      $_db,
      $_db.periodLocks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_periodLockIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PeriodLockEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PeriodLockEventsTable> {
  $$PeriodLockEventsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PeriodLocksTableFilterComposer get periodLockId {
    final $$PeriodLocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodLockId,
      referencedTable: $db.periodLocks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLocksTableFilterComposer(
            $db: $db,
            $table: $db.periodLocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PeriodLockEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PeriodLockEventsTable> {
  $$PeriodLockEventsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PeriodLocksTableOrderingComposer get periodLockId {
    final $$PeriodLocksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodLockId,
      referencedTable: $db.periodLocks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLocksTableOrderingComposer(
            $db: $db,
            $table: $db.periodLocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PeriodLockEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeriodLockEventsTable> {
  $$PeriodLockEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  $$PeriodLocksTableAnnotationComposer get periodLockId {
    final $$PeriodLocksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.periodLockId,
      referencedTable: $db.periodLocks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeriodLocksTableAnnotationComposer(
            $db: $db,
            $table: $db.periodLocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PeriodLockEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeriodLockEventsTable,
          PeriodLockEventRow,
          $$PeriodLockEventsTableFilterComposer,
          $$PeriodLockEventsTableOrderingComposer,
          $$PeriodLockEventsTableAnnotationComposer,
          $$PeriodLockEventsTableCreateCompanionBuilder,
          $$PeriodLockEventsTableUpdateCompanionBuilder,
          (PeriodLockEventRow, $$PeriodLockEventsTableReferences),
          PeriodLockEventRow,
          PrefetchHooks Function({bool periodLockId})
        > {
  $$PeriodLockEventsTableTableManager(
    _$AppDatabase db,
    $PeriodLockEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeriodLockEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeriodLockEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeriodLockEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> periodLockId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeriodLockEventsCompanion(
                id: id,
                orgId: orgId,
                periodLockId: periodLockId,
                action: action,
                reason: reason,
                actorId: actorId,
                occurredAt: occurredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String periodLockId,
                required String action,
                Value<String?> reason = const Value.absent(),
                required String actorId,
                required DateTime occurredAt,
                Value<int> rowid = const Value.absent(),
              }) => PeriodLockEventsCompanion.insert(
                id: id,
                orgId: orgId,
                periodLockId: periodLockId,
                action: action,
                reason: reason,
                actorId: actorId,
                occurredAt: occurredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PeriodLockEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({periodLockId = false}) {
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
                    if (periodLockId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.periodLockId,
                                referencedTable:
                                    $$PeriodLockEventsTableReferences
                                        ._periodLockIdTable(db),
                                referencedColumn:
                                    $$PeriodLockEventsTableReferences
                                        ._periodLockIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$PeriodLockEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeriodLockEventsTable,
      PeriodLockEventRow,
      $$PeriodLockEventsTableFilterComposer,
      $$PeriodLockEventsTableOrderingComposer,
      $$PeriodLockEventsTableAnnotationComposer,
      $$PeriodLockEventsTableCreateCompanionBuilder,
      $$PeriodLockEventsTableUpdateCompanionBuilder,
      (PeriodLockEventRow, $$PeriodLockEventsTableReferences),
      PeriodLockEventRow,
      PrefetchHooks Function({bool periodLockId})
    >;
typedef $$RevenueTaxRatesTableCreateCompanionBuilder =
    RevenueTaxRatesCompanion Function({
      required String id,
      required String orgId,
      required String revenueCategoryId,
      required int rateBasisPoints,
      required String treatment,
      required String effectiveFrom,
      Value<String?> effectiveTo,
      Value<String?> note,
      Value<DateTime?> archivedAt,
      required String createdBy,
      required DateTime createdAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RevenueTaxRatesTableUpdateCompanionBuilder =
    RevenueTaxRatesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> revenueCategoryId,
      Value<int> rateBasisPoints,
      Value<String> treatment,
      Value<String> effectiveFrom,
      Value<String?> effectiveTo,
      Value<String?> note,
      Value<DateTime?> archivedAt,
      Value<String> createdBy,
      Value<DateTime> createdAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$RevenueTaxRatesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevenueTaxRatesTable,
          RevenueTaxRateRow
        > {
  $$RevenueTaxRatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RevenueCategoriesTable _revenueCategoryIdTable(_$AppDatabase db) =>
      db.revenueCategories.createAlias(
        'revenue_tax_rates__revenue_category_id__revenue_categories__id',
      );

  $$RevenueCategoriesTableProcessedTableManager get revenueCategoryId {
    final $_column = $_itemColumn<String>('revenue_category_id')!;

    final manager = $$RevenueCategoriesTableTableManager(
      $_db,
      $_db.revenueCategories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_revenueCategoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RevenueTaxRatesTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueTaxRatesTable> {
  $$RevenueTaxRatesTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rateBasisPoints => $composableBuilder(
    column: $table.rateBasisPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get treatment => $composableBuilder(
    column: $table.treatment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RevenueCategoriesTableFilterComposer get revenueCategoryId {
    final $$RevenueCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revenueCategoryId,
      referencedTable: $db.revenueCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.revenueCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueTaxRatesTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueTaxRatesTable> {
  $$RevenueTaxRatesTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rateBasisPoints => $composableBuilder(
    column: $table.rateBasisPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get treatment => $composableBuilder(
    column: $table.treatment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RevenueCategoriesTableOrderingComposer get revenueCategoryId {
    final $$RevenueCategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revenueCategoryId,
      referencedTable: $db.revenueCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueCategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.revenueCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueTaxRatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueTaxRatesTable> {
  $$RevenueTaxRatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<int> get rateBasisPoints => $composableBuilder(
    column: $table.rateBasisPoints,
    builder: (column) => column,
  );

  GeneratedColumn<String> get treatment =>
      $composableBuilder(column: $table.treatment, builder: (column) => column);

  GeneratedColumn<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$RevenueCategoriesTableAnnotationComposer get revenueCategoryId {
    final $$RevenueCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.revenueCategoryId,
          referencedTable: $db.revenueCategories,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.revenueCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$RevenueTaxRatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueTaxRatesTable,
          RevenueTaxRateRow,
          $$RevenueTaxRatesTableFilterComposer,
          $$RevenueTaxRatesTableOrderingComposer,
          $$RevenueTaxRatesTableAnnotationComposer,
          $$RevenueTaxRatesTableCreateCompanionBuilder,
          $$RevenueTaxRatesTableUpdateCompanionBuilder,
          (RevenueTaxRateRow, $$RevenueTaxRatesTableReferences),
          RevenueTaxRateRow,
          PrefetchHooks Function({bool revenueCategoryId})
        > {
  $$RevenueTaxRatesTableTableManager(
    _$AppDatabase db,
    $RevenueTaxRatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueTaxRatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevenueTaxRatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevenueTaxRatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> revenueCategoryId = const Value.absent(),
                Value<int> rateBasisPoints = const Value.absent(),
                Value<String> treatment = const Value.absent(),
                Value<String> effectiveFrom = const Value.absent(),
                Value<String?> effectiveTo = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueTaxRatesCompanion(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                rateBasisPoints: rateBasisPoints,
                treatment: treatment,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                note: note,
                archivedAt: archivedAt,
                createdBy: createdBy,
                createdAt: createdAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String revenueCategoryId,
                required int rateBasisPoints,
                required String treatment,
                required String effectiveFrom,
                Value<String?> effectiveTo = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                required String createdBy,
                required DateTime createdAt,
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RevenueTaxRatesCompanion.insert(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                rateBasisPoints: rateBasisPoints,
                treatment: treatment,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                note: note,
                archivedAt: archivedAt,
                createdBy: createdBy,
                createdAt: createdAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueTaxRatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({revenueCategoryId = false}) {
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
                    if (revenueCategoryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.revenueCategoryId,
                                referencedTable:
                                    $$RevenueTaxRatesTableReferences
                                        ._revenueCategoryIdTable(db),
                                referencedColumn:
                                    $$RevenueTaxRatesTableReferences
                                        ._revenueCategoryIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$RevenueTaxRatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueTaxRatesTable,
      RevenueTaxRateRow,
      $$RevenueTaxRatesTableFilterComposer,
      $$RevenueTaxRatesTableOrderingComposer,
      $$RevenueTaxRatesTableAnnotationComposer,
      $$RevenueTaxRatesTableCreateCompanionBuilder,
      $$RevenueTaxRatesTableUpdateCompanionBuilder,
      (RevenueTaxRateRow, $$RevenueTaxRatesTableReferences),
      RevenueTaxRateRow,
      PrefetchHooks Function({bool revenueCategoryId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppMetaTableTableManager get appMeta =>
      $$AppMetaTableTableManager(_db, _db.appMeta);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$BusinessUnitsTableTableManager get businessUnits =>
      $$BusinessUnitsTableTableManager(_db, _db.businessUnits);
  $$DepartmentsTableTableManager get departments =>
      $$DepartmentsTableTableManager(_db, _db.departments);
  $$SectionsTableTableManager get sections =>
      $$SectionsTableTableManager(_db, _db.sections);
  $$ExpenseCategoriesTableTableManager get expenseCategories =>
      $$ExpenseCategoriesTableTableManager(_db, _db.expenseCategories);
  $$RevenueCategoriesTableTableManager get revenueCategories =>
      $$RevenueCategoriesTableTableManager(_db, _db.revenueCategories);
  $$VendorsTableTableManager get vendors =>
      $$VendorsTableTableManager(_db, _db.vendors);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(_db, _db.paymentMethods);
  $$PeriodLocksTableTableManager get periodLocks =>
      $$PeriodLocksTableTableManager(_db, _db.periodLocks);
  $$PeriodLockEventsTableTableManager get periodLockEvents =>
      $$PeriodLockEventsTableTableManager(_db, _db.periodLockEvents);
  $$RevenueTaxRatesTableTableManager get revenueTaxRates =>
      $$RevenueTaxRatesTableTableManager(_db, _db.revenueTaxRates);
}
