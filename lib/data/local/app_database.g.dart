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
  static const VerificationMeta _inputBasisMeta = const VerificationMeta(
    'inputBasis',
  );
  @override
  late final GeneratedColumn<String> inputBasis = GeneratedColumn<String>(
    'input_basis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueBandIdMeta = const VerificationMeta(
    'valueBandId',
  );
  @override
  late final GeneratedColumn<String> valueBandId = GeneratedColumn<String>(
    'value_band_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supplySubtypeIdMeta = const VerificationMeta(
    'supplySubtypeId',
  );
  @override
  late final GeneratedColumn<String> supplySubtypeId = GeneratedColumn<String>(
    'supply_subtype_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _premisesStatusCodeMeta =
      const VerificationMeta('premisesStatusCode');
  @override
  late final GeneratedColumn<String> premisesStatusCode =
      GeneratedColumn<String>(
        'premises_status_code',
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
    inputBasis,
    valueBandId,
    supplySubtypeId,
    premisesStatusCode,
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
    if (data.containsKey('input_basis')) {
      context.handle(
        _inputBasisMeta,
        inputBasis.isAcceptableOrUnknown(data['input_basis']!, _inputBasisMeta),
      );
    }
    if (data.containsKey('value_band_id')) {
      context.handle(
        _valueBandIdMeta,
        valueBandId.isAcceptableOrUnknown(
          data['value_band_id']!,
          _valueBandIdMeta,
        ),
      );
    }
    if (data.containsKey('supply_subtype_id')) {
      context.handle(
        _supplySubtypeIdMeta,
        supplySubtypeId.isAcceptableOrUnknown(
          data['supply_subtype_id']!,
          _supplySubtypeIdMeta,
        ),
      );
    }
    if (data.containsKey('premises_status_code')) {
      context.handle(
        _premisesStatusCodeMeta,
        premisesStatusCode.isAcceptableOrUnknown(
          data['premises_status_code']!,
          _premisesStatusCodeMeta,
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
      inputBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_basis'],
      ),
      valueBandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_band_id'],
      ),
      supplySubtypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supply_subtype_id'],
      ),
      premisesStatusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}premises_status_code'],
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

  /// Which figure the operator types under this rule: `inclusive_total` | `pre_tax`
  /// (D-080, D-097).
  ///
  /// **Nullable, and deliberately not backfilled.** Rules cached before v11 predate the
  /// concept and carry no authoritative answer; giving them one would be inventing a
  /// business fact about whether a recorded figure includes tax. A rule with no basis is
  /// *visibly incomplete* and the resolver refuses it (`RevenueTaxIncompleteRule`), which
  /// is the honest outcome.
  final String? inputBasis;
  final String? valueBandId;
  final String? supplySubtypeId;
  final String? premisesStatusCode;
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
    this.inputBasis,
    this.valueBandId,
    this.supplySubtypeId,
    this.premisesStatusCode,
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
    if (!nullToAbsent || inputBasis != null) {
      map['input_basis'] = Variable<String>(inputBasis);
    }
    if (!nullToAbsent || valueBandId != null) {
      map['value_band_id'] = Variable<String>(valueBandId);
    }
    if (!nullToAbsent || supplySubtypeId != null) {
      map['supply_subtype_id'] = Variable<String>(supplySubtypeId);
    }
    if (!nullToAbsent || premisesStatusCode != null) {
      map['premises_status_code'] = Variable<String>(premisesStatusCode);
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
      inputBasis: inputBasis == null && nullToAbsent
          ? const Value.absent()
          : Value(inputBasis),
      valueBandId: valueBandId == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBandId),
      supplySubtypeId: supplySubtypeId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplySubtypeId),
      premisesStatusCode: premisesStatusCode == null && nullToAbsent
          ? const Value.absent()
          : Value(premisesStatusCode),
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
      inputBasis: serializer.fromJson<String?>(json['inputBasis']),
      valueBandId: serializer.fromJson<String?>(json['valueBandId']),
      supplySubtypeId: serializer.fromJson<String?>(json['supplySubtypeId']),
      premisesStatusCode: serializer.fromJson<String?>(
        json['premisesStatusCode'],
      ),
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
      'inputBasis': serializer.toJson<String?>(inputBasis),
      'valueBandId': serializer.toJson<String?>(valueBandId),
      'supplySubtypeId': serializer.toJson<String?>(supplySubtypeId),
      'premisesStatusCode': serializer.toJson<String?>(premisesStatusCode),
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
    Value<String?> inputBasis = const Value.absent(),
    Value<String?> valueBandId = const Value.absent(),
    Value<String?> supplySubtypeId = const Value.absent(),
    Value<String?> premisesStatusCode = const Value.absent(),
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
    inputBasis: inputBasis.present ? inputBasis.value : this.inputBasis,
    valueBandId: valueBandId.present ? valueBandId.value : this.valueBandId,
    supplySubtypeId: supplySubtypeId.present
        ? supplySubtypeId.value
        : this.supplySubtypeId,
    premisesStatusCode: premisesStatusCode.present
        ? premisesStatusCode.value
        : this.premisesStatusCode,
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
      inputBasis: data.inputBasis.present
          ? data.inputBasis.value
          : this.inputBasis,
      valueBandId: data.valueBandId.present
          ? data.valueBandId.value
          : this.valueBandId,
      supplySubtypeId: data.supplySubtypeId.present
          ? data.supplySubtypeId.value
          : this.supplySubtypeId,
      premisesStatusCode: data.premisesStatusCode.present
          ? data.premisesStatusCode.value
          : this.premisesStatusCode,
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
          ..write('inputBasis: $inputBasis, ')
          ..write('valueBandId: $valueBandId, ')
          ..write('supplySubtypeId: $supplySubtypeId, ')
          ..write('premisesStatusCode: $premisesStatusCode, ')
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
    inputBasis,
    valueBandId,
    supplySubtypeId,
    premisesStatusCode,
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
          other.inputBasis == this.inputBasis &&
          other.valueBandId == this.valueBandId &&
          other.supplySubtypeId == this.supplySubtypeId &&
          other.premisesStatusCode == this.premisesStatusCode &&
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
  final Value<String?> inputBasis;
  final Value<String?> valueBandId;
  final Value<String?> supplySubtypeId;
  final Value<String?> premisesStatusCode;
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
    this.inputBasis = const Value.absent(),
    this.valueBandId = const Value.absent(),
    this.supplySubtypeId = const Value.absent(),
    this.premisesStatusCode = const Value.absent(),
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
    this.inputBasis = const Value.absent(),
    this.valueBandId = const Value.absent(),
    this.supplySubtypeId = const Value.absent(),
    this.premisesStatusCode = const Value.absent(),
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
    Expression<String>? inputBasis,
    Expression<String>? valueBandId,
    Expression<String>? supplySubtypeId,
    Expression<String>? premisesStatusCode,
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
      if (inputBasis != null) 'input_basis': inputBasis,
      if (valueBandId != null) 'value_band_id': valueBandId,
      if (supplySubtypeId != null) 'supply_subtype_id': supplySubtypeId,
      if (premisesStatusCode != null)
        'premises_status_code': premisesStatusCode,
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
    Value<String?>? inputBasis,
    Value<String?>? valueBandId,
    Value<String?>? supplySubtypeId,
    Value<String?>? premisesStatusCode,
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
      inputBasis: inputBasis ?? this.inputBasis,
      valueBandId: valueBandId ?? this.valueBandId,
      supplySubtypeId: supplySubtypeId ?? this.supplySubtypeId,
      premisesStatusCode: premisesStatusCode ?? this.premisesStatusCode,
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
    if (inputBasis.present) {
      map['input_basis'] = Variable<String>(inputBasis.value);
    }
    if (valueBandId.present) {
      map['value_band_id'] = Variable<String>(valueBandId.value);
    }
    if (supplySubtypeId.present) {
      map['supply_subtype_id'] = Variable<String>(supplySubtypeId.value);
    }
    if (premisesStatusCode.present) {
      map['premises_status_code'] = Variable<String>(premisesStatusCode.value);
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
          ..write('inputBasis: $inputBasis, ')
          ..write('valueBandId: $valueBandId, ')
          ..write('supplySubtypeId: $supplySubtypeId, ')
          ..write('premisesStatusCode: $premisesStatusCode, ')
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

class $ExpensesTable extends Expenses
    with TableInfo<$ExpensesTable, ExpenseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _txnNumberMeta = const VerificationMeta(
    'txnNumber',
  );
  @override
  late final GeneratedColumn<String> txnNumber = GeneratedColumn<String>(
    'txn_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _financialYearMeta = const VerificationMeta(
    'financialYear',
  );
  @override
  late final GeneratedColumn<int> financialYear = GeneratedColumn<int>(
    'financial_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _businessDateMeta = const VerificationMeta(
    'businessDate',
  );
  @override
  late final GeneratedColumn<String> businessDate = GeneratedColumn<String>(
    'business_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessDateSourceMeta =
      const VerificationMeta('businessDateSource');
  @override
  late final GeneratedColumn<String> businessDateSource =
      GeneratedColumn<String>(
        'business_date_source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('derived'),
      );
  static const VerificationMeta _accountingPeriodStartMeta =
      const VerificationMeta('accountingPeriodStart');
  @override
  late final GeneratedColumn<String> accountingPeriodStart =
      GeneratedColumn<String>(
        'accounting_period_start',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _accountingPeriodEndMeta =
      const VerificationMeta('accountingPeriodEnd');
  @override
  late final GeneratedColumn<String> accountingPeriodEnd =
      GeneratedColumn<String>(
        'accounting_period_end',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _visibilityMeta = const VerificationMeta(
    'visibility',
  );
  @override
  late final GeneratedColumn<String> visibility = GeneratedColumn<String>(
    'visibility',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('complete'),
  );
  static const VerificationMeta _documentTotalMinorMeta =
      const VerificationMeta('documentTotalMinor');
  @override
  late final GeneratedColumn<int> documentTotalMinor = GeneratedColumn<int>(
    'document_total_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _visibleAmountMinorMeta =
      const VerificationMeta('visibleAmountMinor');
  @override
  late final GeneratedColumn<int> visibleAmountMinor = GeneratedColumn<int>(
    'visible_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isSharedMeta = const VerificationMeta(
    'isShared',
  );
  @override
  late final GeneratedColumn<bool> isShared = GeneratedColumn<bool>(
    'is_shared',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_shared" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _vendorIdMeta = const VerificationMeta(
    'vendorId',
  );
  @override
  late final GeneratedColumn<String> vendorId = GeneratedColumn<String>(
    'vendor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentStatusMeta = const VerificationMeta(
    'paymentStatus',
  );
  @override
  late final GeneratedColumn<String> paymentStatus = GeneratedColumn<String>(
    'payment_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unpaid'),
  );
  static const VerificationMeta _paymentDateMeta = const VerificationMeta(
    'paymentDate',
  );
  @override
  late final GeneratedColumn<String> paymentDate = GeneratedColumn<String>(
    'payment_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentMethodIdMeta = const VerificationMeta(
    'paymentMethodId',
  );
  @override
  late final GeneratedColumn<String> paymentMethodId = GeneratedColumn<String>(
    'payment_method_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
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
  static const VerificationMeta _taxAmountMinorMeta = const VerificationMeta(
    'taxAmountMinor',
  );
  @override
  late final GeneratedColumn<int> taxAmountMinor = GeneratedColumn<int>(
    'tax_amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _voidedAtMeta = const VerificationMeta(
    'voidedAt',
  );
  @override
  late final GeneratedColumn<DateTime> voidedAt = GeneratedColumn<DateTime>(
    'voided_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voidedByMeta = const VerificationMeta(
    'voidedBy',
  );
  @override
  late final GeneratedColumn<String> voidedBy = GeneratedColumn<String>(
    'voided_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voidReasonMeta = const VerificationMeta(
    'voidReason',
  );
  @override
  late final GeneratedColumn<String> voidReason = GeneratedColumn<String>(
    'void_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingMutationIdMeta = const VerificationMeta(
    'pendingMutationId',
  );
  @override
  late final GeneratedColumn<String> pendingMutationId =
      GeneratedColumn<String>(
        'pending_mutation_id',
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
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
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
  static const VerificationMeta _scopeRevokedAtMeta = const VerificationMeta(
    'scopeRevokedAt',
  );
  @override
  late final GeneratedColumn<DateTime> scopeRevokedAt =
      GeneratedColumn<DateTime>(
        'scope_revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    txnNumber,
    financialYear,
    businessDate,
    businessDateSource,
    accountingPeriodStart,
    accountingPeriodEnd,
    visibility,
    documentTotalMinor,
    visibleAmountMinor,
    isShared,
    vendorId,
    paymentStatus,
    paymentDate,
    paymentMethodId,
    referenceNumber,
    notes,
    taxAmountMinor,
    createdBy,
    capturedAt,
    voidedAt,
    voidedBy,
    voidReason,
    pendingMutationId,
    rowVersion,
    serverUpdatedAt,
    updatedAt,
    scopeRevokedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseRow> instance, {
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
    if (data.containsKey('txn_number')) {
      context.handle(
        _txnNumberMeta,
        txnNumber.isAcceptableOrUnknown(data['txn_number']!, _txnNumberMeta),
      );
    }
    if (data.containsKey('financial_year')) {
      context.handle(
        _financialYearMeta,
        financialYear.isAcceptableOrUnknown(
          data['financial_year']!,
          _financialYearMeta,
        ),
      );
    }
    if (data.containsKey('business_date')) {
      context.handle(
        _businessDateMeta,
        businessDate.isAcceptableOrUnknown(
          data['business_date']!,
          _businessDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_businessDateMeta);
    }
    if (data.containsKey('business_date_source')) {
      context.handle(
        _businessDateSourceMeta,
        businessDateSource.isAcceptableOrUnknown(
          data['business_date_source']!,
          _businessDateSourceMeta,
        ),
      );
    }
    if (data.containsKey('accounting_period_start')) {
      context.handle(
        _accountingPeriodStartMeta,
        accountingPeriodStart.isAcceptableOrUnknown(
          data['accounting_period_start']!,
          _accountingPeriodStartMeta,
        ),
      );
    }
    if (data.containsKey('accounting_period_end')) {
      context.handle(
        _accountingPeriodEndMeta,
        accountingPeriodEnd.isAcceptableOrUnknown(
          data['accounting_period_end']!,
          _accountingPeriodEndMeta,
        ),
      );
    }
    if (data.containsKey('visibility')) {
      context.handle(
        _visibilityMeta,
        visibility.isAcceptableOrUnknown(data['visibility']!, _visibilityMeta),
      );
    }
    if (data.containsKey('document_total_minor')) {
      context.handle(
        _documentTotalMinorMeta,
        documentTotalMinor.isAcceptableOrUnknown(
          data['document_total_minor']!,
          _documentTotalMinorMeta,
        ),
      );
    }
    if (data.containsKey('visible_amount_minor')) {
      context.handle(
        _visibleAmountMinorMeta,
        visibleAmountMinor.isAcceptableOrUnknown(
          data['visible_amount_minor']!,
          _visibleAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_visibleAmountMinorMeta);
    }
    if (data.containsKey('is_shared')) {
      context.handle(
        _isSharedMeta,
        isShared.isAcceptableOrUnknown(data['is_shared']!, _isSharedMeta),
      );
    }
    if (data.containsKey('vendor_id')) {
      context.handle(
        _vendorIdMeta,
        vendorId.isAcceptableOrUnknown(data['vendor_id']!, _vendorIdMeta),
      );
    }
    if (data.containsKey('payment_status')) {
      context.handle(
        _paymentStatusMeta,
        paymentStatus.isAcceptableOrUnknown(
          data['payment_status']!,
          _paymentStatusMeta,
        ),
      );
    }
    if (data.containsKey('payment_date')) {
      context.handle(
        _paymentDateMeta,
        paymentDate.isAcceptableOrUnknown(
          data['payment_date']!,
          _paymentDateMeta,
        ),
      );
    }
    if (data.containsKey('payment_method_id')) {
      context.handle(
        _paymentMethodIdMeta,
        paymentMethodId.isAcceptableOrUnknown(
          data['payment_method_id']!,
          _paymentMethodIdMeta,
        ),
      );
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('tax_amount_minor')) {
      context.handle(
        _taxAmountMinorMeta,
        taxAmountMinor.isAcceptableOrUnknown(
          data['tax_amount_minor']!,
          _taxAmountMinorMeta,
        ),
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
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('voided_at')) {
      context.handle(
        _voidedAtMeta,
        voidedAt.isAcceptableOrUnknown(data['voided_at']!, _voidedAtMeta),
      );
    }
    if (data.containsKey('voided_by')) {
      context.handle(
        _voidedByMeta,
        voidedBy.isAcceptableOrUnknown(data['voided_by']!, _voidedByMeta),
      );
    }
    if (data.containsKey('void_reason')) {
      context.handle(
        _voidReasonMeta,
        voidReason.isAcceptableOrUnknown(data['void_reason']!, _voidReasonMeta),
      );
    }
    if (data.containsKey('pending_mutation_id')) {
      context.handle(
        _pendingMutationIdMeta,
        pendingMutationId.isAcceptableOrUnknown(
          data['pending_mutation_id']!,
          _pendingMutationIdMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
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
    if (data.containsKey('scope_revoked_at')) {
      context.handle(
        _scopeRevokedAtMeta,
        scopeRevokedAt.isAcceptableOrUnknown(
          data['scope_revoked_at']!,
          _scopeRevokedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      txnNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_number'],
      ),
      financialYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}financial_year'],
      ),
      businessDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_date'],
      )!,
      businessDateSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_date_source'],
      )!,
      accountingPeriodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_period_start'],
      ),
      accountingPeriodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_period_end'],
      ),
      visibility: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visibility'],
      )!,
      documentTotalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_total_minor'],
      ),
      visibleAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}visible_amount_minor'],
      )!,
      isShared: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_shared'],
      )!,
      vendorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vendor_id'],
      ),
      paymentStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_status'],
      )!,
      paymentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_date'],
      ),
      paymentMethodId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method_id'],
      ),
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      taxAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_amount_minor'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      voidedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}voided_at'],
      ),
      voidedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voided_by'],
      ),
      voidReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}void_reason'],
      ),
      pendingMutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_mutation_id'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      scopeRevokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scope_revoked_at'],
      ),
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class ExpenseRow extends DataClass implements Insertable<ExpenseRow> {
  /// Client-generated UUID v7, assigned before the server ever sees the row (D-008).
  /// This is the identity offline, and it never changes.
  final String id;
  final String orgId;

  /// `KI-EXP-26-27-000001`, issued by the server after it accepts the write.
  ///
  /// **Null until then, and never fabricated locally.** Two devices offline for a week
  /// would both invent `000042`. The interface shows a pending state instead.
  final String? txnNumber;
  final int? financialYear;
  final String businessDate;
  final String businessDateSource;
  final String? accountingPeriodStart;
  final String? accountingPeriodEnd;

  /// `complete` | `scoped`. See the library comment; this is the security model.
  final String visibility;

  /// The real invoice total — **only** on a complete record. Null on a scoped one, by
  /// check constraint, because it would give away the other property's share.
  final int? documentTotalMinor;

  /// What the lines this device holds add up to. On a complete record this equals
  /// [documentTotalMinor]; on a scoped one it is this user's share and is never
  /// presented as the invoice.
  final int visibleAmountMinor;

  /// Whether the document charges more than one business unit. Knowing that a bill is
  /// shared is authorised; knowing the other share is not.
  final bool isShared;
  final String? vendorId;
  final String paymentStatus;
  final String? paymentDate;
  final String? paymentMethodId;
  final String? referenceNumber;
  final String? notes;

  /// Informational only (D-018). Never enters a calculation.
  final int? taxAmountMinor;
  final String createdBy;
  final DateTime capturedAt;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  /// The queued intent that will deliver this row, if one is outstanding.
  ///
  /// Sync state is *derived* from the outbox through this link rather than copied into a
  /// column of its own, so the two can never disagree about whether something has been
  /// sent. Cleared in the same transaction that reconciles the server's answer.
  final String? pendingMutationId;
  final int rowVersion;
  final DateTime? serverUpdatedAt;
  final DateTime updatedAt;

  /// When a confirmed revocation removed this user's authority over every unit this
  /// document charges, and the row was kept anyway (D-068).
  ///
  /// Null on everything a user may browse. Non-null on exactly one kind of row: a
  /// document that still carries **unsynced work of its own** — a queued, failed,
  /// rejected or conflicted intent — at the moment its business unit was revoked.
  ///
  /// The purge deletes synced financial cache for a revoked unit; it does not delete
  /// somebody's unsent attempt, because that attempt exists nowhere else and the person
  /// who made it has to be able to see what happened to it. So the row survives, stamped
  /// with this, and is excluded from every canonical financial read — the ledger, the
  /// filtered query, the contribution totals. It remains reachable only through the
  /// pending / rejected / conflict workflow, for the actor who queued it.
  ///
  /// It is a **timestamp rather than a flag** so the retention is dateable: "kept since"
  /// is a fact about the row, and a bare boolean would not say when authority changed.
  final DateTime? scopeRevokedAt;
  const ExpenseRow({
    required this.id,
    required this.orgId,
    this.txnNumber,
    this.financialYear,
    required this.businessDate,
    required this.businessDateSource,
    this.accountingPeriodStart,
    this.accountingPeriodEnd,
    required this.visibility,
    this.documentTotalMinor,
    required this.visibleAmountMinor,
    required this.isShared,
    this.vendorId,
    required this.paymentStatus,
    this.paymentDate,
    this.paymentMethodId,
    this.referenceNumber,
    this.notes,
    this.taxAmountMinor,
    required this.createdBy,
    required this.capturedAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
    this.pendingMutationId,
    required this.rowVersion,
    this.serverUpdatedAt,
    required this.updatedAt,
    this.scopeRevokedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    if (!nullToAbsent || txnNumber != null) {
      map['txn_number'] = Variable<String>(txnNumber);
    }
    if (!nullToAbsent || financialYear != null) {
      map['financial_year'] = Variable<int>(financialYear);
    }
    map['business_date'] = Variable<String>(businessDate);
    map['business_date_source'] = Variable<String>(businessDateSource);
    if (!nullToAbsent || accountingPeriodStart != null) {
      map['accounting_period_start'] = Variable<String>(accountingPeriodStart);
    }
    if (!nullToAbsent || accountingPeriodEnd != null) {
      map['accounting_period_end'] = Variable<String>(accountingPeriodEnd);
    }
    map['visibility'] = Variable<String>(visibility);
    if (!nullToAbsent || documentTotalMinor != null) {
      map['document_total_minor'] = Variable<int>(documentTotalMinor);
    }
    map['visible_amount_minor'] = Variable<int>(visibleAmountMinor);
    map['is_shared'] = Variable<bool>(isShared);
    if (!nullToAbsent || vendorId != null) {
      map['vendor_id'] = Variable<String>(vendorId);
    }
    map['payment_status'] = Variable<String>(paymentStatus);
    if (!nullToAbsent || paymentDate != null) {
      map['payment_date'] = Variable<String>(paymentDate);
    }
    if (!nullToAbsent || paymentMethodId != null) {
      map['payment_method_id'] = Variable<String>(paymentMethodId);
    }
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || taxAmountMinor != null) {
      map['tax_amount_minor'] = Variable<int>(taxAmountMinor);
    }
    map['created_by'] = Variable<String>(createdBy);
    map['captured_at'] = Variable<DateTime>(capturedAt);
    if (!nullToAbsent || voidedAt != null) {
      map['voided_at'] = Variable<DateTime>(voidedAt);
    }
    if (!nullToAbsent || voidedBy != null) {
      map['voided_by'] = Variable<String>(voidedBy);
    }
    if (!nullToAbsent || voidReason != null) {
      map['void_reason'] = Variable<String>(voidReason);
    }
    if (!nullToAbsent || pendingMutationId != null) {
      map['pending_mutation_id'] = Variable<String>(pendingMutationId);
    }
    map['row_version'] = Variable<int>(rowVersion);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || scopeRevokedAt != null) {
      map['scope_revoked_at'] = Variable<DateTime>(scopeRevokedAt);
    }
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      txnNumber: txnNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(txnNumber),
      financialYear: financialYear == null && nullToAbsent
          ? const Value.absent()
          : Value(financialYear),
      businessDate: Value(businessDate),
      businessDateSource: Value(businessDateSource),
      accountingPeriodStart: accountingPeriodStart == null && nullToAbsent
          ? const Value.absent()
          : Value(accountingPeriodStart),
      accountingPeriodEnd: accountingPeriodEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(accountingPeriodEnd),
      visibility: Value(visibility),
      documentTotalMinor: documentTotalMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(documentTotalMinor),
      visibleAmountMinor: Value(visibleAmountMinor),
      isShared: Value(isShared),
      vendorId: vendorId == null && nullToAbsent
          ? const Value.absent()
          : Value(vendorId),
      paymentStatus: Value(paymentStatus),
      paymentDate: paymentDate == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentDate),
      paymentMethodId: paymentMethodId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMethodId),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      taxAmountMinor: taxAmountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(taxAmountMinor),
      createdBy: Value(createdBy),
      capturedAt: Value(capturedAt),
      voidedAt: voidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(voidedAt),
      voidedBy: voidedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(voidedBy),
      voidReason: voidReason == null && nullToAbsent
          ? const Value.absent()
          : Value(voidReason),
      pendingMutationId: pendingMutationId == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingMutationId),
      rowVersion: Value(rowVersion),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      updatedAt: Value(updatedAt),
      scopeRevokedAt: scopeRevokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeRevokedAt),
    );
  }

  factory ExpenseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      txnNumber: serializer.fromJson<String?>(json['txnNumber']),
      financialYear: serializer.fromJson<int?>(json['financialYear']),
      businessDate: serializer.fromJson<String>(json['businessDate']),
      businessDateSource: serializer.fromJson<String>(
        json['businessDateSource'],
      ),
      accountingPeriodStart: serializer.fromJson<String?>(
        json['accountingPeriodStart'],
      ),
      accountingPeriodEnd: serializer.fromJson<String?>(
        json['accountingPeriodEnd'],
      ),
      visibility: serializer.fromJson<String>(json['visibility']),
      documentTotalMinor: serializer.fromJson<int?>(json['documentTotalMinor']),
      visibleAmountMinor: serializer.fromJson<int>(json['visibleAmountMinor']),
      isShared: serializer.fromJson<bool>(json['isShared']),
      vendorId: serializer.fromJson<String?>(json['vendorId']),
      paymentStatus: serializer.fromJson<String>(json['paymentStatus']),
      paymentDate: serializer.fromJson<String?>(json['paymentDate']),
      paymentMethodId: serializer.fromJson<String?>(json['paymentMethodId']),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      notes: serializer.fromJson<String?>(json['notes']),
      taxAmountMinor: serializer.fromJson<int?>(json['taxAmountMinor']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      voidedAt: serializer.fromJson<DateTime?>(json['voidedAt']),
      voidedBy: serializer.fromJson<String?>(json['voidedBy']),
      voidReason: serializer.fromJson<String?>(json['voidReason']),
      pendingMutationId: serializer.fromJson<String?>(
        json['pendingMutationId'],
      ),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      scopeRevokedAt: serializer.fromJson<DateTime?>(json['scopeRevokedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'txnNumber': serializer.toJson<String?>(txnNumber),
      'financialYear': serializer.toJson<int?>(financialYear),
      'businessDate': serializer.toJson<String>(businessDate),
      'businessDateSource': serializer.toJson<String>(businessDateSource),
      'accountingPeriodStart': serializer.toJson<String?>(
        accountingPeriodStart,
      ),
      'accountingPeriodEnd': serializer.toJson<String?>(accountingPeriodEnd),
      'visibility': serializer.toJson<String>(visibility),
      'documentTotalMinor': serializer.toJson<int?>(documentTotalMinor),
      'visibleAmountMinor': serializer.toJson<int>(visibleAmountMinor),
      'isShared': serializer.toJson<bool>(isShared),
      'vendorId': serializer.toJson<String?>(vendorId),
      'paymentStatus': serializer.toJson<String>(paymentStatus),
      'paymentDate': serializer.toJson<String?>(paymentDate),
      'paymentMethodId': serializer.toJson<String?>(paymentMethodId),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'notes': serializer.toJson<String?>(notes),
      'taxAmountMinor': serializer.toJson<int?>(taxAmountMinor),
      'createdBy': serializer.toJson<String>(createdBy),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'voidedAt': serializer.toJson<DateTime?>(voidedAt),
      'voidedBy': serializer.toJson<String?>(voidedBy),
      'voidReason': serializer.toJson<String?>(voidReason),
      'pendingMutationId': serializer.toJson<String?>(pendingMutationId),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'scopeRevokedAt': serializer.toJson<DateTime?>(scopeRevokedAt),
    };
  }

  ExpenseRow copyWith({
    String? id,
    String? orgId,
    Value<String?> txnNumber = const Value.absent(),
    Value<int?> financialYear = const Value.absent(),
    String? businessDate,
    String? businessDateSource,
    Value<String?> accountingPeriodStart = const Value.absent(),
    Value<String?> accountingPeriodEnd = const Value.absent(),
    String? visibility,
    Value<int?> documentTotalMinor = const Value.absent(),
    int? visibleAmountMinor,
    bool? isShared,
    Value<String?> vendorId = const Value.absent(),
    String? paymentStatus,
    Value<String?> paymentDate = const Value.absent(),
    Value<String?> paymentMethodId = const Value.absent(),
    Value<String?> referenceNumber = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<int?> taxAmountMinor = const Value.absent(),
    String? createdBy,
    DateTime? capturedAt,
    Value<DateTime?> voidedAt = const Value.absent(),
    Value<String?> voidedBy = const Value.absent(),
    Value<String?> voidReason = const Value.absent(),
    Value<String?> pendingMutationId = const Value.absent(),
    int? rowVersion,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> scopeRevokedAt = const Value.absent(),
  }) => ExpenseRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    txnNumber: txnNumber.present ? txnNumber.value : this.txnNumber,
    financialYear: financialYear.present
        ? financialYear.value
        : this.financialYear,
    businessDate: businessDate ?? this.businessDate,
    businessDateSource: businessDateSource ?? this.businessDateSource,
    accountingPeriodStart: accountingPeriodStart.present
        ? accountingPeriodStart.value
        : this.accountingPeriodStart,
    accountingPeriodEnd: accountingPeriodEnd.present
        ? accountingPeriodEnd.value
        : this.accountingPeriodEnd,
    visibility: visibility ?? this.visibility,
    documentTotalMinor: documentTotalMinor.present
        ? documentTotalMinor.value
        : this.documentTotalMinor,
    visibleAmountMinor: visibleAmountMinor ?? this.visibleAmountMinor,
    isShared: isShared ?? this.isShared,
    vendorId: vendorId.present ? vendorId.value : this.vendorId,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paymentDate: paymentDate.present ? paymentDate.value : this.paymentDate,
    paymentMethodId: paymentMethodId.present
        ? paymentMethodId.value
        : this.paymentMethodId,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    notes: notes.present ? notes.value : this.notes,
    taxAmountMinor: taxAmountMinor.present
        ? taxAmountMinor.value
        : this.taxAmountMinor,
    createdBy: createdBy ?? this.createdBy,
    capturedAt: capturedAt ?? this.capturedAt,
    voidedAt: voidedAt.present ? voidedAt.value : this.voidedAt,
    voidedBy: voidedBy.present ? voidedBy.value : this.voidedBy,
    voidReason: voidReason.present ? voidReason.value : this.voidReason,
    pendingMutationId: pendingMutationId.present
        ? pendingMutationId.value
        : this.pendingMutationId,
    rowVersion: rowVersion ?? this.rowVersion,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    scopeRevokedAt: scopeRevokedAt.present
        ? scopeRevokedAt.value
        : this.scopeRevokedAt,
  );
  ExpenseRow copyWithCompanion(ExpensesCompanion data) {
    return ExpenseRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      txnNumber: data.txnNumber.present ? data.txnNumber.value : this.txnNumber,
      financialYear: data.financialYear.present
          ? data.financialYear.value
          : this.financialYear,
      businessDate: data.businessDate.present
          ? data.businessDate.value
          : this.businessDate,
      businessDateSource: data.businessDateSource.present
          ? data.businessDateSource.value
          : this.businessDateSource,
      accountingPeriodStart: data.accountingPeriodStart.present
          ? data.accountingPeriodStart.value
          : this.accountingPeriodStart,
      accountingPeriodEnd: data.accountingPeriodEnd.present
          ? data.accountingPeriodEnd.value
          : this.accountingPeriodEnd,
      visibility: data.visibility.present
          ? data.visibility.value
          : this.visibility,
      documentTotalMinor: data.documentTotalMinor.present
          ? data.documentTotalMinor.value
          : this.documentTotalMinor,
      visibleAmountMinor: data.visibleAmountMinor.present
          ? data.visibleAmountMinor.value
          : this.visibleAmountMinor,
      isShared: data.isShared.present ? data.isShared.value : this.isShared,
      vendorId: data.vendorId.present ? data.vendorId.value : this.vendorId,
      paymentStatus: data.paymentStatus.present
          ? data.paymentStatus.value
          : this.paymentStatus,
      paymentDate: data.paymentDate.present
          ? data.paymentDate.value
          : this.paymentDate,
      paymentMethodId: data.paymentMethodId.present
          ? data.paymentMethodId.value
          : this.paymentMethodId,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      notes: data.notes.present ? data.notes.value : this.notes,
      taxAmountMinor: data.taxAmountMinor.present
          ? data.taxAmountMinor.value
          : this.taxAmountMinor,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      voidedAt: data.voidedAt.present ? data.voidedAt.value : this.voidedAt,
      voidedBy: data.voidedBy.present ? data.voidedBy.value : this.voidedBy,
      voidReason: data.voidReason.present
          ? data.voidReason.value
          : this.voidReason,
      pendingMutationId: data.pendingMutationId.present
          ? data.pendingMutationId.value
          : this.pendingMutationId,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      scopeRevokedAt: data.scopeRevokedAt.present
          ? data.scopeRevokedAt.value
          : this.scopeRevokedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('txnNumber: $txnNumber, ')
          ..write('financialYear: $financialYear, ')
          ..write('businessDate: $businessDate, ')
          ..write('businessDateSource: $businessDateSource, ')
          ..write('accountingPeriodStart: $accountingPeriodStart, ')
          ..write('accountingPeriodEnd: $accountingPeriodEnd, ')
          ..write('visibility: $visibility, ')
          ..write('documentTotalMinor: $documentTotalMinor, ')
          ..write('visibleAmountMinor: $visibleAmountMinor, ')
          ..write('isShared: $isShared, ')
          ..write('vendorId: $vendorId, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('notes: $notes, ')
          ..write('taxAmountMinor: $taxAmountMinor, ')
          ..write('createdBy: $createdBy, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('voidedAt: $voidedAt, ')
          ..write('voidedBy: $voidedBy, ')
          ..write('voidReason: $voidReason, ')
          ..write('pendingMutationId: $pendingMutationId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scopeRevokedAt: $scopeRevokedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    orgId,
    txnNumber,
    financialYear,
    businessDate,
    businessDateSource,
    accountingPeriodStart,
    accountingPeriodEnd,
    visibility,
    documentTotalMinor,
    visibleAmountMinor,
    isShared,
    vendorId,
    paymentStatus,
    paymentDate,
    paymentMethodId,
    referenceNumber,
    notes,
    taxAmountMinor,
    createdBy,
    capturedAt,
    voidedAt,
    voidedBy,
    voidReason,
    pendingMutationId,
    rowVersion,
    serverUpdatedAt,
    updatedAt,
    scopeRevokedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.txnNumber == this.txnNumber &&
          other.financialYear == this.financialYear &&
          other.businessDate == this.businessDate &&
          other.businessDateSource == this.businessDateSource &&
          other.accountingPeriodStart == this.accountingPeriodStart &&
          other.accountingPeriodEnd == this.accountingPeriodEnd &&
          other.visibility == this.visibility &&
          other.documentTotalMinor == this.documentTotalMinor &&
          other.visibleAmountMinor == this.visibleAmountMinor &&
          other.isShared == this.isShared &&
          other.vendorId == this.vendorId &&
          other.paymentStatus == this.paymentStatus &&
          other.paymentDate == this.paymentDate &&
          other.paymentMethodId == this.paymentMethodId &&
          other.referenceNumber == this.referenceNumber &&
          other.notes == this.notes &&
          other.taxAmountMinor == this.taxAmountMinor &&
          other.createdBy == this.createdBy &&
          other.capturedAt == this.capturedAt &&
          other.voidedAt == this.voidedAt &&
          other.voidedBy == this.voidedBy &&
          other.voidReason == this.voidReason &&
          other.pendingMutationId == this.pendingMutationId &&
          other.rowVersion == this.rowVersion &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.updatedAt == this.updatedAt &&
          other.scopeRevokedAt == this.scopeRevokedAt);
}

class ExpensesCompanion extends UpdateCompanion<ExpenseRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String?> txnNumber;
  final Value<int?> financialYear;
  final Value<String> businessDate;
  final Value<String> businessDateSource;
  final Value<String?> accountingPeriodStart;
  final Value<String?> accountingPeriodEnd;
  final Value<String> visibility;
  final Value<int?> documentTotalMinor;
  final Value<int> visibleAmountMinor;
  final Value<bool> isShared;
  final Value<String?> vendorId;
  final Value<String> paymentStatus;
  final Value<String?> paymentDate;
  final Value<String?> paymentMethodId;
  final Value<String?> referenceNumber;
  final Value<String?> notes;
  final Value<int?> taxAmountMinor;
  final Value<String> createdBy;
  final Value<DateTime> capturedAt;
  final Value<DateTime?> voidedAt;
  final Value<String?> voidedBy;
  final Value<String?> voidReason;
  final Value<String?> pendingMutationId;
  final Value<int> rowVersion;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> scopeRevokedAt;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.txnNumber = const Value.absent(),
    this.financialYear = const Value.absent(),
    this.businessDate = const Value.absent(),
    this.businessDateSource = const Value.absent(),
    this.accountingPeriodStart = const Value.absent(),
    this.accountingPeriodEnd = const Value.absent(),
    this.visibility = const Value.absent(),
    this.documentTotalMinor = const Value.absent(),
    this.visibleAmountMinor = const Value.absent(),
    this.isShared = const Value.absent(),
    this.vendorId = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.notes = const Value.absent(),
    this.taxAmountMinor = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.voidedAt = const Value.absent(),
    this.voidedBy = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.pendingMutationId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.scopeRevokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String id,
    required String orgId,
    this.txnNumber = const Value.absent(),
    this.financialYear = const Value.absent(),
    required String businessDate,
    this.businessDateSource = const Value.absent(),
    this.accountingPeriodStart = const Value.absent(),
    this.accountingPeriodEnd = const Value.absent(),
    this.visibility = const Value.absent(),
    this.documentTotalMinor = const Value.absent(),
    required int visibleAmountMinor,
    this.isShared = const Value.absent(),
    this.vendorId = const Value.absent(),
    this.paymentStatus = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.paymentMethodId = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.notes = const Value.absent(),
    this.taxAmountMinor = const Value.absent(),
    required String createdBy,
    required DateTime capturedAt,
    this.voidedAt = const Value.absent(),
    this.voidedBy = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.pendingMutationId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    required DateTime updatedAt,
    this.scopeRevokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       businessDate = Value(businessDate),
       visibleAmountMinor = Value(visibleAmountMinor),
       createdBy = Value(createdBy),
       capturedAt = Value(capturedAt),
       updatedAt = Value(updatedAt);
  static Insertable<ExpenseRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? txnNumber,
    Expression<int>? financialYear,
    Expression<String>? businessDate,
    Expression<String>? businessDateSource,
    Expression<String>? accountingPeriodStart,
    Expression<String>? accountingPeriodEnd,
    Expression<String>? visibility,
    Expression<int>? documentTotalMinor,
    Expression<int>? visibleAmountMinor,
    Expression<bool>? isShared,
    Expression<String>? vendorId,
    Expression<String>? paymentStatus,
    Expression<String>? paymentDate,
    Expression<String>? paymentMethodId,
    Expression<String>? referenceNumber,
    Expression<String>? notes,
    Expression<int>? taxAmountMinor,
    Expression<String>? createdBy,
    Expression<DateTime>? capturedAt,
    Expression<DateTime>? voidedAt,
    Expression<String>? voidedBy,
    Expression<String>? voidReason,
    Expression<String>? pendingMutationId,
    Expression<int>? rowVersion,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? scopeRevokedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (txnNumber != null) 'txn_number': txnNumber,
      if (financialYear != null) 'financial_year': financialYear,
      if (businessDate != null) 'business_date': businessDate,
      if (businessDateSource != null)
        'business_date_source': businessDateSource,
      if (accountingPeriodStart != null)
        'accounting_period_start': accountingPeriodStart,
      if (accountingPeriodEnd != null)
        'accounting_period_end': accountingPeriodEnd,
      if (visibility != null) 'visibility': visibility,
      if (documentTotalMinor != null)
        'document_total_minor': documentTotalMinor,
      if (visibleAmountMinor != null)
        'visible_amount_minor': visibleAmountMinor,
      if (isShared != null) 'is_shared': isShared,
      if (vendorId != null) 'vendor_id': vendorId,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (notes != null) 'notes': notes,
      if (taxAmountMinor != null) 'tax_amount_minor': taxAmountMinor,
      if (createdBy != null) 'created_by': createdBy,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (voidedAt != null) 'voided_at': voidedAt,
      if (voidedBy != null) 'voided_by': voidedBy,
      if (voidReason != null) 'void_reason': voidReason,
      if (pendingMutationId != null) 'pending_mutation_id': pendingMutationId,
      if (rowVersion != null) 'row_version': rowVersion,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (scopeRevokedAt != null) 'scope_revoked_at': scopeRevokedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String?>? txnNumber,
    Value<int?>? financialYear,
    Value<String>? businessDate,
    Value<String>? businessDateSource,
    Value<String?>? accountingPeriodStart,
    Value<String?>? accountingPeriodEnd,
    Value<String>? visibility,
    Value<int?>? documentTotalMinor,
    Value<int>? visibleAmountMinor,
    Value<bool>? isShared,
    Value<String?>? vendorId,
    Value<String>? paymentStatus,
    Value<String?>? paymentDate,
    Value<String?>? paymentMethodId,
    Value<String?>? referenceNumber,
    Value<String?>? notes,
    Value<int?>? taxAmountMinor,
    Value<String>? createdBy,
    Value<DateTime>? capturedAt,
    Value<DateTime?>? voidedAt,
    Value<String?>? voidedBy,
    Value<String?>? voidReason,
    Value<String?>? pendingMutationId,
    Value<int>? rowVersion,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? scopeRevokedAt,
    Value<int>? rowid,
  }) {
    return ExpensesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      txnNumber: txnNumber ?? this.txnNumber,
      financialYear: financialYear ?? this.financialYear,
      businessDate: businessDate ?? this.businessDate,
      businessDateSource: businessDateSource ?? this.businessDateSource,
      accountingPeriodStart:
          accountingPeriodStart ?? this.accountingPeriodStart,
      accountingPeriodEnd: accountingPeriodEnd ?? this.accountingPeriodEnd,
      visibility: visibility ?? this.visibility,
      documentTotalMinor: documentTotalMinor ?? this.documentTotalMinor,
      visibleAmountMinor: visibleAmountMinor ?? this.visibleAmountMinor,
      isShared: isShared ?? this.isShared,
      vendorId: vendorId ?? this.vendorId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      taxAmountMinor: taxAmountMinor ?? this.taxAmountMinor,
      createdBy: createdBy ?? this.createdBy,
      capturedAt: capturedAt ?? this.capturedAt,
      voidedAt: voidedAt ?? this.voidedAt,
      voidedBy: voidedBy ?? this.voidedBy,
      voidReason: voidReason ?? this.voidReason,
      pendingMutationId: pendingMutationId ?? this.pendingMutationId,
      rowVersion: rowVersion ?? this.rowVersion,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scopeRevokedAt: scopeRevokedAt ?? this.scopeRevokedAt,
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
    if (txnNumber.present) {
      map['txn_number'] = Variable<String>(txnNumber.value);
    }
    if (financialYear.present) {
      map['financial_year'] = Variable<int>(financialYear.value);
    }
    if (businessDate.present) {
      map['business_date'] = Variable<String>(businessDate.value);
    }
    if (businessDateSource.present) {
      map['business_date_source'] = Variable<String>(businessDateSource.value);
    }
    if (accountingPeriodStart.present) {
      map['accounting_period_start'] = Variable<String>(
        accountingPeriodStart.value,
      );
    }
    if (accountingPeriodEnd.present) {
      map['accounting_period_end'] = Variable<String>(
        accountingPeriodEnd.value,
      );
    }
    if (visibility.present) {
      map['visibility'] = Variable<String>(visibility.value);
    }
    if (documentTotalMinor.present) {
      map['document_total_minor'] = Variable<int>(documentTotalMinor.value);
    }
    if (visibleAmountMinor.present) {
      map['visible_amount_minor'] = Variable<int>(visibleAmountMinor.value);
    }
    if (isShared.present) {
      map['is_shared'] = Variable<bool>(isShared.value);
    }
    if (vendorId.present) {
      map['vendor_id'] = Variable<String>(vendorId.value);
    }
    if (paymentStatus.present) {
      map['payment_status'] = Variable<String>(paymentStatus.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<String>(paymentDate.value);
    }
    if (paymentMethodId.present) {
      map['payment_method_id'] = Variable<String>(paymentMethodId.value);
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (taxAmountMinor.present) {
      map['tax_amount_minor'] = Variable<int>(taxAmountMinor.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (voidedAt.present) {
      map['voided_at'] = Variable<DateTime>(voidedAt.value);
    }
    if (voidedBy.present) {
      map['voided_by'] = Variable<String>(voidedBy.value);
    }
    if (voidReason.present) {
      map['void_reason'] = Variable<String>(voidReason.value);
    }
    if (pendingMutationId.present) {
      map['pending_mutation_id'] = Variable<String>(pendingMutationId.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (scopeRevokedAt.present) {
      map['scope_revoked_at'] = Variable<DateTime>(scopeRevokedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('txnNumber: $txnNumber, ')
          ..write('financialYear: $financialYear, ')
          ..write('businessDate: $businessDate, ')
          ..write('businessDateSource: $businessDateSource, ')
          ..write('accountingPeriodStart: $accountingPeriodStart, ')
          ..write('accountingPeriodEnd: $accountingPeriodEnd, ')
          ..write('visibility: $visibility, ')
          ..write('documentTotalMinor: $documentTotalMinor, ')
          ..write('visibleAmountMinor: $visibleAmountMinor, ')
          ..write('isShared: $isShared, ')
          ..write('vendorId: $vendorId, ')
          ..write('paymentStatus: $paymentStatus, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('paymentMethodId: $paymentMethodId, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('notes: $notes, ')
          ..write('taxAmountMinor: $taxAmountMinor, ')
          ..write('createdBy: $createdBy, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('voidedAt: $voidedAt, ')
          ..write('voidedBy: $voidedBy, ')
          ..write('voidReason: $voidReason, ')
          ..write('pendingMutationId: $pendingMutationId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scopeRevokedAt: $scopeRevokedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseAllocationsTable extends ExpenseAllocations
    with TableInfo<$ExpenseAllocationsTable, ExpenseAllocationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseAllocationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _expenseIdMeta = const VerificationMeta(
    'expenseId',
  );
  @override
  late final GeneratedColumn<String> expenseId = GeneratedColumn<String>(
    'expense_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES expenses (id) ON DELETE CASCADE',
    ),
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
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryLabelMeta = const VerificationMeta(
    'categoryLabel',
  );
  @override
  late final GeneratedColumn<String> categoryLabel = GeneratedColumn<String>(
    'category_label',
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
    expenseId,
    businessUnitId,
    departmentId,
    sectionId,
    categoryId,
    amountMinor,
    categoryLabel,
    sortOrder,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_allocations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseAllocationRow> instance, {
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
    if (data.containsKey('expense_id')) {
      context.handle(
        _expenseIdMeta,
        expenseId.isAcceptableOrUnknown(data['expense_id']!, _expenseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_expenseIdMeta);
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
    if (data.containsKey('section_id')) {
      context.handle(
        _sectionIdMeta,
        sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('category_label')) {
      context.handle(
        _categoryLabelMeta,
        categoryLabel.isAcceptableOrUnknown(
          data['category_label']!,
          _categoryLabelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_categoryLabelMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseAllocationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseAllocationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      expenseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_id'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
      departmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}department_id'],
      )!,
      sectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      categoryLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_label'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
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
  $ExpenseAllocationsTable createAlias(String alias) {
    return $ExpenseAllocationsTable(attachedDatabase, alias);
  }
}

class ExpenseAllocationRow extends DataClass
    implements Insertable<ExpenseAllocationRow> {
  final String id;
  final String orgId;
  final String expenseId;

  /// Deliberately **not** a foreign key to `business_units`, for exactly the reason
  /// given for [categoryId] below — they are two columns of one classification and the
  /// argument does not stop applying halfway along it.
  ///
  /// It was one, with `ON DELETE RESTRICT`, until the Phase 3 acceptance ran sign-out on
  /// a device that had synced an expense. `ScopeCachePurge` deletes the business units a
  /// user no longer holds — and at sign-out, all of them (D-053) — so the restrict fired
  /// and **sign-out threw**. On a shared back-office workstation that is the ordinary
  /// sequence, and it is the one D-054 added the control for.
  ///
  /// A foreign key asserts "the target exists in this database". On a per-user cache that
  /// is simply false: the purge removes the masters of a revoked unit while the expense
  /// lines already synced stay as history (D-048 — the purge is limited to server-owned
  /// *reference* data, and never touches anything a person typed). The server keeps the
  /// real key, where the assertion is true. Same reasoning as D-049 and D-062.
  final String businessUnitId;
  final String departmentId;
  final String sectionId;

  /// Deliberately **not** a foreign key to `expense_categories`.
  ///
  /// The full hierarchy is a per-user cache, and a category can legitimately be absent
  /// from it — a scope purge (D-048) removes the masters of a revoked unit while an
  /// expense line that was already synced remains as history. A real foreign key would
  /// make the purge impossible or the history deletable, and both are worse than a soft
  /// pointer. The server holds the real key; this is the same reasoning as D-049.
  final String categoryId;
  final int amountMinor;

  /// What the category was called when this was recorded (D-035). Reports show the
  /// current name; the document and the audit trail can show what was on screen.
  final String categoryLabel;
  final int sortOrder;
  final int rowVersion;
  final DateTime updatedAt;
  const ExpenseAllocationRow({
    required this.id,
    required this.orgId,
    required this.expenseId,
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.amountMinor,
    required this.categoryLabel,
    required this.sortOrder,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['expense_id'] = Variable<String>(expenseId);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    map['department_id'] = Variable<String>(departmentId);
    map['section_id'] = Variable<String>(sectionId);
    map['category_id'] = Variable<String>(categoryId);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['category_label'] = Variable<String>(categoryLabel);
    map['sort_order'] = Variable<int>(sortOrder);
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExpenseAllocationsCompanion toCompanion(bool nullToAbsent) {
    return ExpenseAllocationsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      expenseId: Value(expenseId),
      businessUnitId: Value(businessUnitId),
      departmentId: Value(departmentId),
      sectionId: Value(sectionId),
      categoryId: Value(categoryId),
      amountMinor: Value(amountMinor),
      categoryLabel: Value(categoryLabel),
      sortOrder: Value(sortOrder),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory ExpenseAllocationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseAllocationRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      expenseId: serializer.fromJson<String>(json['expenseId']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
      departmentId: serializer.fromJson<String>(json['departmentId']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      categoryLabel: serializer.fromJson<String>(json['categoryLabel']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
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
      'expenseId': serializer.toJson<String>(expenseId),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
      'departmentId': serializer.toJson<String>(departmentId),
      'sectionId': serializer.toJson<String>(sectionId),
      'categoryId': serializer.toJson<String>(categoryId),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'categoryLabel': serializer.toJson<String>(categoryLabel),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ExpenseAllocationRow copyWith({
    String? id,
    String? orgId,
    String? expenseId,
    String? businessUnitId,
    String? departmentId,
    String? sectionId,
    String? categoryId,
    int? amountMinor,
    String? categoryLabel,
    int? sortOrder,
    int? rowVersion,
    DateTime? updatedAt,
  }) => ExpenseAllocationRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    expenseId: expenseId ?? this.expenseId,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    departmentId: departmentId ?? this.departmentId,
    sectionId: sectionId ?? this.sectionId,
    categoryId: categoryId ?? this.categoryId,
    amountMinor: amountMinor ?? this.amountMinor,
    categoryLabel: categoryLabel ?? this.categoryLabel,
    sortOrder: sortOrder ?? this.sortOrder,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ExpenseAllocationRow copyWithCompanion(ExpenseAllocationsCompanion data) {
    return ExpenseAllocationRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      expenseId: data.expenseId.present ? data.expenseId.value : this.expenseId,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      departmentId: data.departmentId.present
          ? data.departmentId.value
          : this.departmentId,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      categoryLabel: data.categoryLabel.present
          ? data.categoryLabel.value
          : this.categoryLabel,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseAllocationRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('departmentId: $departmentId, ')
          ..write('sectionId: $sectionId, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('categoryLabel: $categoryLabel, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    expenseId,
    businessUnitId,
    departmentId,
    sectionId,
    categoryId,
    amountMinor,
    categoryLabel,
    sortOrder,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseAllocationRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.expenseId == this.expenseId &&
          other.businessUnitId == this.businessUnitId &&
          other.departmentId == this.departmentId &&
          other.sectionId == this.sectionId &&
          other.categoryId == this.categoryId &&
          other.amountMinor == this.amountMinor &&
          other.categoryLabel == this.categoryLabel &&
          other.sortOrder == this.sortOrder &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class ExpenseAllocationsCompanion
    extends UpdateCompanion<ExpenseAllocationRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> expenseId;
  final Value<String> businessUnitId;
  final Value<String> departmentId;
  final Value<String> sectionId;
  final Value<String> categoryId;
  final Value<int> amountMinor;
  final Value<String> categoryLabel;
  final Value<int> sortOrder;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExpenseAllocationsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.expenseId = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.departmentId = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.categoryLabel = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseAllocationsCompanion.insert({
    required String id,
    required String orgId,
    required String expenseId,
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
    required String categoryId,
    required int amountMinor,
    required String categoryLabel,
    this.sortOrder = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       expenseId = Value(expenseId),
       businessUnitId = Value(businessUnitId),
       departmentId = Value(departmentId),
       sectionId = Value(sectionId),
       categoryId = Value(categoryId),
       amountMinor = Value(amountMinor),
       categoryLabel = Value(categoryLabel),
       updatedAt = Value(updatedAt);
  static Insertable<ExpenseAllocationRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? expenseId,
    Expression<String>? businessUnitId,
    Expression<String>? departmentId,
    Expression<String>? sectionId,
    Expression<String>? categoryId,
    Expression<int>? amountMinor,
    Expression<String>? categoryLabel,
    Expression<int>? sortOrder,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (expenseId != null) 'expense_id': expenseId,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (departmentId != null) 'department_id': departmentId,
      if (sectionId != null) 'section_id': sectionId,
      if (categoryId != null) 'category_id': categoryId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (categoryLabel != null) 'category_label': categoryLabel,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseAllocationsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? expenseId,
    Value<String>? businessUnitId,
    Value<String>? departmentId,
    Value<String>? sectionId,
    Value<String>? categoryId,
    Value<int>? amountMinor,
    Value<String>? categoryLabel,
    Value<int>? sortOrder,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExpenseAllocationsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      expenseId: expenseId ?? this.expenseId,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      departmentId: departmentId ?? this.departmentId,
      sectionId: sectionId ?? this.sectionId,
      categoryId: categoryId ?? this.categoryId,
      amountMinor: amountMinor ?? this.amountMinor,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (expenseId.present) {
      map['expense_id'] = Variable<String>(expenseId.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (departmentId.present) {
      map['department_id'] = Variable<String>(departmentId.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (categoryLabel.present) {
      map['category_label'] = Variable<String>(categoryLabel.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('ExpenseAllocationsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('departmentId: $departmentId, ')
          ..write('sectionId: $sectionId, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('categoryLabel: $categoryLabel, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpensePeriodAllocationsTable extends ExpensePeriodAllocations
    with TableInfo<$ExpensePeriodAllocationsTable, ExpensePeriodAllocationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensePeriodAllocationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _expenseIdMeta = const VerificationMeta(
    'expenseId',
  );
  @override
  late final GeneratedColumn<String> expenseId = GeneratedColumn<String>(
    'expense_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES expenses (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _allocationIdMeta = const VerificationMeta(
    'allocationId',
  );
  @override
  late final GeneratedColumn<String> allocationId = GeneratedColumn<String>(
    'allocation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES expense_allocations (id) ON DELETE CASCADE',
    ),
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
  );
  static const VerificationMeta _accountingPeriodStartMeta =
      const VerificationMeta('accountingPeriodStart');
  @override
  late final GeneratedColumn<String> accountingPeriodStart =
      GeneratedColumn<String>(
        'accounting_period_start',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _accountingPeriodEndMeta =
      const VerificationMeta('accountingPeriodEnd');
  @override
  late final GeneratedColumn<String> accountingPeriodEnd =
      GeneratedColumn<String>(
        'accounting_period_end',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pnlDateMeta = const VerificationMeta(
    'pnlDate',
  );
  @override
  late final GeneratedColumn<String> pnlDate = GeneratedColumn<String>(
    'pnl_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pnlPeriodKeyMeta = const VerificationMeta(
    'pnlPeriodKey',
  );
  @override
  late final GeneratedColumn<String> pnlPeriodKey = GeneratedColumn<String>(
    'pnl_period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDerivedMeta = const VerificationMeta(
    'isDerived',
  );
  @override
  late final GeneratedColumn<bool> isDerived = GeneratedColumn<bool>(
    'is_derived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_derived" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
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
    expenseId,
    allocationId,
    businessUnitId,
    accountingPeriodStart,
    accountingPeriodEnd,
    amountMinor,
    pnlDate,
    pnlPeriodKey,
    isDerived,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_period_allocations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpensePeriodAllocationRow> instance, {
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
    if (data.containsKey('expense_id')) {
      context.handle(
        _expenseIdMeta,
        expenseId.isAcceptableOrUnknown(data['expense_id']!, _expenseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_expenseIdMeta);
    }
    if (data.containsKey('allocation_id')) {
      context.handle(
        _allocationIdMeta,
        allocationId.isAcceptableOrUnknown(
          data['allocation_id']!,
          _allocationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allocationIdMeta);
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
    if (data.containsKey('accounting_period_start')) {
      context.handle(
        _accountingPeriodStartMeta,
        accountingPeriodStart.isAcceptableOrUnknown(
          data['accounting_period_start']!,
          _accountingPeriodStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountingPeriodStartMeta);
    }
    if (data.containsKey('accounting_period_end')) {
      context.handle(
        _accountingPeriodEndMeta,
        accountingPeriodEnd.isAcceptableOrUnknown(
          data['accounting_period_end']!,
          _accountingPeriodEndMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountingPeriodEndMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('pnl_date')) {
      context.handle(
        _pnlDateMeta,
        pnlDate.isAcceptableOrUnknown(data['pnl_date']!, _pnlDateMeta),
      );
    } else if (isInserting) {
      context.missing(_pnlDateMeta);
    }
    if (data.containsKey('pnl_period_key')) {
      context.handle(
        _pnlPeriodKeyMeta,
        pnlPeriodKey.isAcceptableOrUnknown(
          data['pnl_period_key']!,
          _pnlPeriodKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pnlPeriodKeyMeta);
    }
    if (data.containsKey('is_derived')) {
      context.handle(
        _isDerivedMeta,
        isDerived.isAcceptableOrUnknown(data['is_derived']!, _isDerivedMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpensePeriodAllocationRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpensePeriodAllocationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      expenseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_id'],
      )!,
      allocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}allocation_id'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
      accountingPeriodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_period_start'],
      )!,
      accountingPeriodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accounting_period_end'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      pnlDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pnl_date'],
      )!,
      pnlPeriodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pnl_period_key'],
      )!,
      isDerived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_derived'],
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
  $ExpensePeriodAllocationsTable createAlias(String alias) {
    return $ExpensePeriodAllocationsTable(attachedDatabase, alias);
  }
}

class ExpensePeriodAllocationRow extends DataClass
    implements Insertable<ExpensePeriodAllocationRow> {
  final String id;
  final String orgId;
  final String expenseId;
  final String allocationId;
  final String businessUnitId;
  final String accountingPeriodStart;
  final String accountingPeriodEnd;
  final int amountMinor;

  /// Computed once and stored, never re-derived at read time (D-019).
  final String pnlDate;
  final String pnlPeriodKey;

  /// Whether the default rule produced this, or a person chose it. Drives the
  /// `expense.allocate_periods` capability check and what the audit trail says.
  final bool isDerived;
  final int rowVersion;
  final DateTime updatedAt;
  const ExpensePeriodAllocationRow({
    required this.id,
    required this.orgId,
    required this.expenseId,
    required this.allocationId,
    required this.businessUnitId,
    required this.accountingPeriodStart,
    required this.accountingPeriodEnd,
    required this.amountMinor,
    required this.pnlDate,
    required this.pnlPeriodKey,
    required this.isDerived,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['expense_id'] = Variable<String>(expenseId);
    map['allocation_id'] = Variable<String>(allocationId);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    map['accounting_period_start'] = Variable<String>(accountingPeriodStart);
    map['accounting_period_end'] = Variable<String>(accountingPeriodEnd);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['pnl_date'] = Variable<String>(pnlDate);
    map['pnl_period_key'] = Variable<String>(pnlPeriodKey);
    map['is_derived'] = Variable<bool>(isDerived);
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExpensePeriodAllocationsCompanion toCompanion(bool nullToAbsent) {
    return ExpensePeriodAllocationsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      expenseId: Value(expenseId),
      allocationId: Value(allocationId),
      businessUnitId: Value(businessUnitId),
      accountingPeriodStart: Value(accountingPeriodStart),
      accountingPeriodEnd: Value(accountingPeriodEnd),
      amountMinor: Value(amountMinor),
      pnlDate: Value(pnlDate),
      pnlPeriodKey: Value(pnlPeriodKey),
      isDerived: Value(isDerived),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory ExpensePeriodAllocationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpensePeriodAllocationRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      expenseId: serializer.fromJson<String>(json['expenseId']),
      allocationId: serializer.fromJson<String>(json['allocationId']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
      accountingPeriodStart: serializer.fromJson<String>(
        json['accountingPeriodStart'],
      ),
      accountingPeriodEnd: serializer.fromJson<String>(
        json['accountingPeriodEnd'],
      ),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      pnlDate: serializer.fromJson<String>(json['pnlDate']),
      pnlPeriodKey: serializer.fromJson<String>(json['pnlPeriodKey']),
      isDerived: serializer.fromJson<bool>(json['isDerived']),
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
      'expenseId': serializer.toJson<String>(expenseId),
      'allocationId': serializer.toJson<String>(allocationId),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
      'accountingPeriodStart': serializer.toJson<String>(accountingPeriodStart),
      'accountingPeriodEnd': serializer.toJson<String>(accountingPeriodEnd),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'pnlDate': serializer.toJson<String>(pnlDate),
      'pnlPeriodKey': serializer.toJson<String>(pnlPeriodKey),
      'isDerived': serializer.toJson<bool>(isDerived),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ExpensePeriodAllocationRow copyWith({
    String? id,
    String? orgId,
    String? expenseId,
    String? allocationId,
    String? businessUnitId,
    String? accountingPeriodStart,
    String? accountingPeriodEnd,
    int? amountMinor,
    String? pnlDate,
    String? pnlPeriodKey,
    bool? isDerived,
    int? rowVersion,
    DateTime? updatedAt,
  }) => ExpensePeriodAllocationRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    expenseId: expenseId ?? this.expenseId,
    allocationId: allocationId ?? this.allocationId,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    accountingPeriodStart: accountingPeriodStart ?? this.accountingPeriodStart,
    accountingPeriodEnd: accountingPeriodEnd ?? this.accountingPeriodEnd,
    amountMinor: amountMinor ?? this.amountMinor,
    pnlDate: pnlDate ?? this.pnlDate,
    pnlPeriodKey: pnlPeriodKey ?? this.pnlPeriodKey,
    isDerived: isDerived ?? this.isDerived,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ExpensePeriodAllocationRow copyWithCompanion(
    ExpensePeriodAllocationsCompanion data,
  ) {
    return ExpensePeriodAllocationRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      expenseId: data.expenseId.present ? data.expenseId.value : this.expenseId,
      allocationId: data.allocationId.present
          ? data.allocationId.value
          : this.allocationId,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      accountingPeriodStart: data.accountingPeriodStart.present
          ? data.accountingPeriodStart.value
          : this.accountingPeriodStart,
      accountingPeriodEnd: data.accountingPeriodEnd.present
          ? data.accountingPeriodEnd.value
          : this.accountingPeriodEnd,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      pnlDate: data.pnlDate.present ? data.pnlDate.value : this.pnlDate,
      pnlPeriodKey: data.pnlPeriodKey.present
          ? data.pnlPeriodKey.value
          : this.pnlPeriodKey,
      isDerived: data.isDerived.present ? data.isDerived.value : this.isDerived,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpensePeriodAllocationRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('allocationId: $allocationId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('accountingPeriodStart: $accountingPeriodStart, ')
          ..write('accountingPeriodEnd: $accountingPeriodEnd, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('pnlDate: $pnlDate, ')
          ..write('pnlPeriodKey: $pnlPeriodKey, ')
          ..write('isDerived: $isDerived, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    expenseId,
    allocationId,
    businessUnitId,
    accountingPeriodStart,
    accountingPeriodEnd,
    amountMinor,
    pnlDate,
    pnlPeriodKey,
    isDerived,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpensePeriodAllocationRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.expenseId == this.expenseId &&
          other.allocationId == this.allocationId &&
          other.businessUnitId == this.businessUnitId &&
          other.accountingPeriodStart == this.accountingPeriodStart &&
          other.accountingPeriodEnd == this.accountingPeriodEnd &&
          other.amountMinor == this.amountMinor &&
          other.pnlDate == this.pnlDate &&
          other.pnlPeriodKey == this.pnlPeriodKey &&
          other.isDerived == this.isDerived &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class ExpensePeriodAllocationsCompanion
    extends UpdateCompanion<ExpensePeriodAllocationRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> expenseId;
  final Value<String> allocationId;
  final Value<String> businessUnitId;
  final Value<String> accountingPeriodStart;
  final Value<String> accountingPeriodEnd;
  final Value<int> amountMinor;
  final Value<String> pnlDate;
  final Value<String> pnlPeriodKey;
  final Value<bool> isDerived;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExpensePeriodAllocationsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.expenseId = const Value.absent(),
    this.allocationId = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.accountingPeriodStart = const Value.absent(),
    this.accountingPeriodEnd = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.pnlDate = const Value.absent(),
    this.pnlPeriodKey = const Value.absent(),
    this.isDerived = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensePeriodAllocationsCompanion.insert({
    required String id,
    required String orgId,
    required String expenseId,
    required String allocationId,
    required String businessUnitId,
    required String accountingPeriodStart,
    required String accountingPeriodEnd,
    required int amountMinor,
    required String pnlDate,
    required String pnlPeriodKey,
    this.isDerived = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       expenseId = Value(expenseId),
       allocationId = Value(allocationId),
       businessUnitId = Value(businessUnitId),
       accountingPeriodStart = Value(accountingPeriodStart),
       accountingPeriodEnd = Value(accountingPeriodEnd),
       amountMinor = Value(amountMinor),
       pnlDate = Value(pnlDate),
       pnlPeriodKey = Value(pnlPeriodKey),
       updatedAt = Value(updatedAt);
  static Insertable<ExpensePeriodAllocationRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? expenseId,
    Expression<String>? allocationId,
    Expression<String>? businessUnitId,
    Expression<String>? accountingPeriodStart,
    Expression<String>? accountingPeriodEnd,
    Expression<int>? amountMinor,
    Expression<String>? pnlDate,
    Expression<String>? pnlPeriodKey,
    Expression<bool>? isDerived,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (expenseId != null) 'expense_id': expenseId,
      if (allocationId != null) 'allocation_id': allocationId,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (accountingPeriodStart != null)
        'accounting_period_start': accountingPeriodStart,
      if (accountingPeriodEnd != null)
        'accounting_period_end': accountingPeriodEnd,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (pnlDate != null) 'pnl_date': pnlDate,
      if (pnlPeriodKey != null) 'pnl_period_key': pnlPeriodKey,
      if (isDerived != null) 'is_derived': isDerived,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensePeriodAllocationsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? expenseId,
    Value<String>? allocationId,
    Value<String>? businessUnitId,
    Value<String>? accountingPeriodStart,
    Value<String>? accountingPeriodEnd,
    Value<int>? amountMinor,
    Value<String>? pnlDate,
    Value<String>? pnlPeriodKey,
    Value<bool>? isDerived,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExpensePeriodAllocationsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      expenseId: expenseId ?? this.expenseId,
      allocationId: allocationId ?? this.allocationId,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      accountingPeriodStart:
          accountingPeriodStart ?? this.accountingPeriodStart,
      accountingPeriodEnd: accountingPeriodEnd ?? this.accountingPeriodEnd,
      amountMinor: amountMinor ?? this.amountMinor,
      pnlDate: pnlDate ?? this.pnlDate,
      pnlPeriodKey: pnlPeriodKey ?? this.pnlPeriodKey,
      isDerived: isDerived ?? this.isDerived,
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
    if (expenseId.present) {
      map['expense_id'] = Variable<String>(expenseId.value);
    }
    if (allocationId.present) {
      map['allocation_id'] = Variable<String>(allocationId.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (accountingPeriodStart.present) {
      map['accounting_period_start'] = Variable<String>(
        accountingPeriodStart.value,
      );
    }
    if (accountingPeriodEnd.present) {
      map['accounting_period_end'] = Variable<String>(
        accountingPeriodEnd.value,
      );
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (pnlDate.present) {
      map['pnl_date'] = Variable<String>(pnlDate.value);
    }
    if (pnlPeriodKey.present) {
      map['pnl_period_key'] = Variable<String>(pnlPeriodKey.value);
    }
    if (isDerived.present) {
      map['is_derived'] = Variable<bool>(isDerived.value);
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
    return (StringBuffer('ExpensePeriodAllocationsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('allocationId: $allocationId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('accountingPeriodStart: $accountingPeriodStart, ')
          ..write('accountingPeriodEnd: $accountingPeriodEnd, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('pnlDate: $pnlDate, ')
          ..write('pnlPeriodKey: $pnlPeriodKey, ')
          ..write('isDerived: $isDerived, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpenseAttachmentsTable extends ExpenseAttachments
    with TableInfo<$ExpenseAttachmentsTable, ExpenseAttachmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseAttachmentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _expenseIdMeta = const VerificationMeta(
    'expenseId',
  );
  @override
  late final GeneratedColumn<String> expenseId = GeneratedColumn<String>(
    'expense_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES expenses (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<String> uploadState = GeneratedColumn<String>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('staged'),
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
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
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
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
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> uploadedAt = GeneratedColumn<DateTime>(
    'uploaded_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reclaimableAfterMeta = const VerificationMeta(
    'reclaimableAfter',
  );
  @override
  late final GeneratedColumn<DateTime> reclaimableAfter =
      GeneratedColumn<DateTime>(
        'reclaimable_after',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _uploadedByMeta = const VerificationMeta(
    'uploadedBy',
  );
  @override
  late final GeneratedColumn<String> uploadedBy = GeneratedColumn<String>(
    'uploaded_by',
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
    expenseId,
    fileName,
    contentType,
    byteSize,
    contentHash,
    localPath,
    uploadState,
    storagePath,
    attemptCount,
    nextAttemptAt,
    lastError,
    uploadedAt,
    reclaimableAfter,
    uploadedBy,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseAttachmentRow> instance, {
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
    if (data.containsKey('expense_id')) {
      context.handle(
        _expenseIdMeta,
        expenseId.isAcceptableOrUnknown(data['expense_id']!, _expenseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_expenseIdMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
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
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    }
    if (data.containsKey('reclaimable_after')) {
      context.handle(
        _reclaimableAfterMeta,
        reclaimableAfter.isAcceptableOrUnknown(
          data['reclaimable_after']!,
          _reclaimableAfterMeta,
        ),
      );
    }
    if (data.containsKey('uploaded_by')) {
      context.handle(
        _uploadedByMeta,
        uploadedBy.isAcceptableOrUnknown(data['uploaded_by']!, _uploadedByMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadedByMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  ExpenseAttachmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseAttachmentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      expenseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_state'],
      )!,
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}uploaded_at'],
      ),
      reclaimableAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reclaimable_after'],
      ),
      uploadedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploaded_by'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ExpenseAttachmentsTable createAlias(String alias) {
    return $ExpenseAttachmentsTable(attachedDatabase, alias);
  }
}

class ExpenseAttachmentRow extends DataClass
    implements Insertable<ExpenseAttachmentRow> {
  final String id;
  final String orgId;
  final String expenseId;
  final String fileName;
  final String contentType;
  final int byteSize;

  /// SHA-256 of the staged bytes, computed before upload and compared afterwards.
  final String contentHash;

  /// The app-private staging copy. Never a gallery or Downloads path: those can be
  /// moved, renamed or revoked by the OS between capture and upload.
  final String? localPath;

  /// `pending` | `uploaded` | `stagingReclaimed` | `failed`.
  /// One of [AttachmentUploadState]. The lifecycle lives in that enum, not here.
  final String uploadState;
  final String? storagePath;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime? uploadedAt;

  /// When the verified staging copy becomes eligible for reclamation — seven days after
  /// the server confirmed *and* the hash matched (AttachmentPolicy.stagingRetention).
  final DateTime? reclaimableAfter;
  final String uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ExpenseAttachmentRow({
    required this.id,
    required this.orgId,
    required this.expenseId,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    required this.contentHash,
    this.localPath,
    required this.uploadState,
    this.storagePath,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastError,
    this.uploadedAt,
    this.reclaimableAfter,
    required this.uploadedBy,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['expense_id'] = Variable<String>(expenseId);
    map['file_name'] = Variable<String>(fileName);
    map['content_type'] = Variable<String>(contentType);
    map['byte_size'] = Variable<int>(byteSize);
    map['content_hash'] = Variable<String>(contentHash);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['upload_state'] = Variable<String>(uploadState);
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt);
    }
    if (!nullToAbsent || reclaimableAfter != null) {
      map['reclaimable_after'] = Variable<DateTime>(reclaimableAfter);
    }
    map['uploaded_by'] = Variable<String>(uploadedBy);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExpenseAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return ExpenseAttachmentsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      expenseId: Value(expenseId),
      fileName: Value(fileName),
      contentType: Value(contentType),
      byteSize: Value(byteSize),
      contentHash: Value(contentHash),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      uploadState: Value(uploadState),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
      reclaimableAfter: reclaimableAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(reclaimableAfter),
      uploadedBy: Value(uploadedBy),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ExpenseAttachmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseAttachmentRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      expenseId: serializer.fromJson<String>(json['expenseId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      contentType: serializer.fromJson<String>(json['contentType']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      uploadState: serializer.fromJson<String>(json['uploadState']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      uploadedAt: serializer.fromJson<DateTime?>(json['uploadedAt']),
      reclaimableAfter: serializer.fromJson<DateTime?>(
        json['reclaimableAfter'],
      ),
      uploadedBy: serializer.fromJson<String>(json['uploadedBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'expenseId': serializer.toJson<String>(expenseId),
      'fileName': serializer.toJson<String>(fileName),
      'contentType': serializer.toJson<String>(contentType),
      'byteSize': serializer.toJson<int>(byteSize),
      'contentHash': serializer.toJson<String>(contentHash),
      'localPath': serializer.toJson<String?>(localPath),
      'uploadState': serializer.toJson<String>(uploadState),
      'storagePath': serializer.toJson<String?>(storagePath),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'uploadedAt': serializer.toJson<DateTime?>(uploadedAt),
      'reclaimableAfter': serializer.toJson<DateTime?>(reclaimableAfter),
      'uploadedBy': serializer.toJson<String>(uploadedBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ExpenseAttachmentRow copyWith({
    String? id,
    String? orgId,
    String? expenseId,
    String? fileName,
    String? contentType,
    int? byteSize,
    String? contentHash,
    Value<String?> localPath = const Value.absent(),
    String? uploadState,
    Value<String?> storagePath = const Value.absent(),
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> uploadedAt = const Value.absent(),
    Value<DateTime?> reclaimableAfter = const Value.absent(),
    String? uploadedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ExpenseAttachmentRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    expenseId: expenseId ?? this.expenseId,
    fileName: fileName ?? this.fileName,
    contentType: contentType ?? this.contentType,
    byteSize: byteSize ?? this.byteSize,
    contentHash: contentHash ?? this.contentHash,
    localPath: localPath.present ? localPath.value : this.localPath,
    uploadState: uploadState ?? this.uploadState,
    storagePath: storagePath.present ? storagePath.value : this.storagePath,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
    reclaimableAfter: reclaimableAfter.present
        ? reclaimableAfter.value
        : this.reclaimableAfter,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ExpenseAttachmentRow copyWithCompanion(ExpenseAttachmentsCompanion data) {
    return ExpenseAttachmentRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      expenseId: data.expenseId.present ? data.expenseId.value : this.expenseId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
      reclaimableAfter: data.reclaimableAfter.present
          ? data.reclaimableAfter.value
          : this.reclaimableAfter,
      uploadedBy: data.uploadedBy.present
          ? data.uploadedBy.value
          : this.uploadedBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseAttachmentRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('fileName: $fileName, ')
          ..write('contentType: $contentType, ')
          ..write('byteSize: $byteSize, ')
          ..write('contentHash: $contentHash, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('storagePath: $storagePath, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('reclaimableAfter: $reclaimableAfter, ')
          ..write('uploadedBy: $uploadedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    expenseId,
    fileName,
    contentType,
    byteSize,
    contentHash,
    localPath,
    uploadState,
    storagePath,
    attemptCount,
    nextAttemptAt,
    lastError,
    uploadedAt,
    reclaimableAfter,
    uploadedBy,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseAttachmentRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.expenseId == this.expenseId &&
          other.fileName == this.fileName &&
          other.contentType == this.contentType &&
          other.byteSize == this.byteSize &&
          other.contentHash == this.contentHash &&
          other.localPath == this.localPath &&
          other.uploadState == this.uploadState &&
          other.storagePath == this.storagePath &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.uploadedAt == this.uploadedAt &&
          other.reclaimableAfter == this.reclaimableAfter &&
          other.uploadedBy == this.uploadedBy &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ExpenseAttachmentsCompanion
    extends UpdateCompanion<ExpenseAttachmentRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> expenseId;
  final Value<String> fileName;
  final Value<String> contentType;
  final Value<int> byteSize;
  final Value<String> contentHash;
  final Value<String?> localPath;
  final Value<String> uploadState;
  final Value<String?> storagePath;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime?> uploadedAt;
  final Value<DateTime?> reclaimableAfter;
  final Value<String> uploadedBy;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExpenseAttachmentsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.expenseId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.contentType = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.localPath = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.reclaimableAfter = const Value.absent(),
    this.uploadedBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpenseAttachmentsCompanion.insert({
    required String id,
    required String orgId,
    required String expenseId,
    required String fileName,
    required String contentType,
    required int byteSize,
    required String contentHash,
    this.localPath = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.reclaimableAfter = const Value.absent(),
    required String uploadedBy,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       expenseId = Value(expenseId),
       fileName = Value(fileName),
       contentType = Value(contentType),
       byteSize = Value(byteSize),
       contentHash = Value(contentHash),
       uploadedBy = Value(uploadedBy),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ExpenseAttachmentRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? expenseId,
    Expression<String>? fileName,
    Expression<String>? contentType,
    Expression<int>? byteSize,
    Expression<String>? contentHash,
    Expression<String>? localPath,
    Expression<String>? uploadState,
    Expression<String>? storagePath,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? uploadedAt,
    Expression<DateTime>? reclaimableAfter,
    Expression<String>? uploadedBy,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (expenseId != null) 'expense_id': expenseId,
      if (fileName != null) 'file_name': fileName,
      if (contentType != null) 'content_type': contentType,
      if (byteSize != null) 'byte_size': byteSize,
      if (contentHash != null) 'content_hash': contentHash,
      if (localPath != null) 'local_path': localPath,
      if (uploadState != null) 'upload_state': uploadState,
      if (storagePath != null) 'storage_path': storagePath,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (reclaimableAfter != null) 'reclaimable_after': reclaimableAfter,
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpenseAttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? expenseId,
    Value<String>? fileName,
    Value<String>? contentType,
    Value<int>? byteSize,
    Value<String>? contentHash,
    Value<String?>? localPath,
    Value<String>? uploadState,
    Value<String?>? storagePath,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<DateTime?>? uploadedAt,
    Value<DateTime?>? reclaimableAfter,
    Value<String>? uploadedBy,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExpenseAttachmentsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      expenseId: expenseId ?? this.expenseId,
      fileName: fileName ?? this.fileName,
      contentType: contentType ?? this.contentType,
      byteSize: byteSize ?? this.byteSize,
      contentHash: contentHash ?? this.contentHash,
      localPath: localPath ?? this.localPath,
      uploadState: uploadState ?? this.uploadState,
      storagePath: storagePath ?? this.storagePath,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      reclaimableAfter: reclaimableAfter ?? this.reclaimableAfter,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt ?? this.createdAt,
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
    if (expenseId.present) {
      map['expense_id'] = Variable<String>(expenseId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<String>(uploadState.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<DateTime>(uploadedAt.value);
    }
    if (reclaimableAfter.present) {
      map['reclaimable_after'] = Variable<DateTime>(reclaimableAfter.value);
    }
    if (uploadedBy.present) {
      map['uploaded_by'] = Variable<String>(uploadedBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('ExpenseAttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('expenseId: $expenseId, ')
          ..write('fileName: $fileName, ')
          ..write('contentType: $contentType, ')
          ..write('byteSize: $byteSize, ')
          ..write('contentHash: $contentHash, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('storagePath: $storagePath, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('reclaimableAfter: $reclaimableAfter, ')
          ..write('uploadedBy: $uploadedBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueEntriesTable extends RevenueEntries
    with TableInfo<$RevenueEntriesTable, RevenueEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _txnNumberMeta = const VerificationMeta(
    'txnNumber',
  );
  @override
  late final GeneratedColumn<String> txnNumber = GeneratedColumn<String>(
    'txn_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _financialYearMeta = const VerificationMeta(
    'financialYear',
  );
  @override
  late final GeneratedColumn<String> financialYear = GeneratedColumn<String>(
    'financial_year',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
      );
  static const VerificationMeta _businessDateMeta = const VerificationMeta(
    'businessDate',
  );
  @override
  late final GeneratedColumn<String> businessDate = GeneratedColumn<String>(
    'business_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pnlPeriodKeyMeta = const VerificationMeta(
    'pnlPeriodKey',
  );
  @override
  late final GeneratedColumn<String> pnlPeriodKey = GeneratedColumn<String>(
    'pnl_period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryKindMeta = const VerificationMeta(
    'entryKind',
  );
  @override
  late final GeneratedColumn<String> entryKind = GeneratedColumn<String>(
    'entry_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('daily_summary'),
  );
  static const VerificationMeta _sourceReferenceMeta = const VerificationMeta(
    'sourceReference',
  );
  @override
  late final GeneratedColumn<String> sourceReference = GeneratedColumn<String>(
    'source_reference',
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
  static const VerificationMeta _voidedAtMeta = const VerificationMeta(
    'voidedAt',
  );
  @override
  late final GeneratedColumn<DateTime> voidedAt = GeneratedColumn<DateTime>(
    'voided_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voidedByMeta = const VerificationMeta(
    'voidedBy',
  );
  @override
  late final GeneratedColumn<String> voidedBy = GeneratedColumn<String>(
    'voided_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voidReasonMeta = const VerificationMeta(
    'voidReason',
  );
  @override
  late final GeneratedColumn<String> voidReason = GeneratedColumn<String>(
    'void_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingMutationIdMeta = const VerificationMeta(
    'pendingMutationId',
  );
  @override
  late final GeneratedColumn<String> pendingMutationId =
      GeneratedColumn<String>(
        'pending_mutation_id',
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
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
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
  static const VerificationMeta _scopeRevokedAtMeta = const VerificationMeta(
    'scopeRevokedAt',
  );
  @override
  late final GeneratedColumn<DateTime> scopeRevokedAt =
      GeneratedColumn<DateTime>(
        'scope_revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    txnNumber,
    financialYear,
    businessUnitId,
    revenueCategoryId,
    businessDate,
    pnlPeriodKey,
    capturedAt,
    entryKind,
    sourceReference,
    notes,
    createdBy,
    voidedAt,
    voidedBy,
    voidReason,
    pendingMutationId,
    rowVersion,
    serverUpdatedAt,
    updatedAt,
    scopeRevokedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueEntryRow> instance, {
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
    if (data.containsKey('txn_number')) {
      context.handle(
        _txnNumberMeta,
        txnNumber.isAcceptableOrUnknown(data['txn_number']!, _txnNumberMeta),
      );
    }
    if (data.containsKey('financial_year')) {
      context.handle(
        _financialYearMeta,
        financialYear.isAcceptableOrUnknown(
          data['financial_year']!,
          _financialYearMeta,
        ),
      );
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
    if (data.containsKey('business_date')) {
      context.handle(
        _businessDateMeta,
        businessDate.isAcceptableOrUnknown(
          data['business_date']!,
          _businessDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_businessDateMeta);
    }
    if (data.containsKey('pnl_period_key')) {
      context.handle(
        _pnlPeriodKeyMeta,
        pnlPeriodKey.isAcceptableOrUnknown(
          data['pnl_period_key']!,
          _pnlPeriodKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pnlPeriodKeyMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('entry_kind')) {
      context.handle(
        _entryKindMeta,
        entryKind.isAcceptableOrUnknown(data['entry_kind']!, _entryKindMeta),
      );
    }
    if (data.containsKey('source_reference')) {
      context.handle(
        _sourceReferenceMeta,
        sourceReference.isAcceptableOrUnknown(
          data['source_reference']!,
          _sourceReferenceMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
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
    if (data.containsKey('voided_at')) {
      context.handle(
        _voidedAtMeta,
        voidedAt.isAcceptableOrUnknown(data['voided_at']!, _voidedAtMeta),
      );
    }
    if (data.containsKey('voided_by')) {
      context.handle(
        _voidedByMeta,
        voidedBy.isAcceptableOrUnknown(data['voided_by']!, _voidedByMeta),
      );
    }
    if (data.containsKey('void_reason')) {
      context.handle(
        _voidReasonMeta,
        voidReason.isAcceptableOrUnknown(data['void_reason']!, _voidReasonMeta),
      );
    }
    if (data.containsKey('pending_mutation_id')) {
      context.handle(
        _pendingMutationIdMeta,
        pendingMutationId.isAcceptableOrUnknown(
          data['pending_mutation_id']!,
          _pendingMutationIdMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
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
    if (data.containsKey('scope_revoked_at')) {
      context.handle(
        _scopeRevokedAtMeta,
        scopeRevokedAt.isAcceptableOrUnknown(
          data['scope_revoked_at']!,
          _scopeRevokedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevenueEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      txnNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_number'],
      ),
      financialYear: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}financial_year'],
      ),
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
      revenueCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revenue_category_id'],
      )!,
      businessDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_date'],
      )!,
      pnlPeriodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pnl_period_key'],
      )!,
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      entryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_kind'],
      )!,
      sourceReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_reference'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      voidedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}voided_at'],
      ),
      voidedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voided_by'],
      ),
      voidReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}void_reason'],
      ),
      pendingMutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_mutation_id'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      scopeRevokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scope_revoked_at'],
      ),
    );
  }

  @override
  $RevenueEntriesTable createAlias(String alias) {
    return $RevenueEntriesTable(attachedDatabase, alias);
  }
}

class RevenueEntryRow extends DataClass implements Insertable<RevenueEntryRow> {
  /// Client-generated UUID v7, assigned before the server sees the row (D-008).
  final String id;
  final String orgId;

  /// `KI-REV-26-27-000001`, issued by the server after it accepts the write (spec §8.4).
  ///
  /// **Null until then, and never fabricated locally** — two devices offline for a week
  /// would both invent the same number. Its own sequence, never the expense one.
  final String? txnNumber;
  final String? financialYear;

  /// Soft pointers, for the reason v5 and v8 made their expense counterparts soft: a
  /// per-user cache legitimately outlives the masters it names, and a foreign key with
  /// `ON DELETE RESTRICT` made sign-out throw on a device holding financial rows (D-068).
  final String businessUnitId;
  final String revenueCategoryId;

  /// Derived under the unit's timezone and cut-off, then persisted (D-067). `YYYY-MM-DD`.
  final String businessDate;

  /// `YYYY-MM` of [businessDate], for period lookups and reporting.
  final String pnlPeriodKey;

  /// The device instant. Forensic metadata; never authoritative (spec §9).
  final DateTime capturedAt;

  /// `daily_summary` | `shift` | `import` | `correction` (spec §8.2).
  final String entryKind;
  final String? sourceReference;
  final String? notes;
  final String createdBy;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  /// The queued intent that will deliver this row, if one is outstanding. Sync state is
  /// *derived* through this link rather than copied into a column that could disagree.
  final String? pendingMutationId;
  final int rowVersion;
  final DateTime? serverUpdatedAt;
  final DateTime updatedAt;

  /// When a confirmed revocation removed this user's authority over this entry's business
  /// unit and the row was kept anyway (D-070).
  ///
  /// Null on everything a user may browse. Non-null on exactly one kind of row: an entry
  /// still carrying **its own unsent work** — a queued, failed, rejected or conflicted
  /// intent — at the moment its unit was revoked. Synced rows are purged; an unsent
  /// attempt exists nowhere else, so it is kept, stamped, and excluded from every
  /// canonical revenue read.
  ///
  /// A timestamp rather than a flag, so the retention is dateable.
  final DateTime? scopeRevokedAt;
  const RevenueEntryRow({
    required this.id,
    required this.orgId,
    this.txnNumber,
    this.financialYear,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.pnlPeriodKey,
    required this.capturedAt,
    required this.entryKind,
    this.sourceReference,
    this.notes,
    required this.createdBy,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
    this.pendingMutationId,
    required this.rowVersion,
    this.serverUpdatedAt,
    required this.updatedAt,
    this.scopeRevokedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    if (!nullToAbsent || txnNumber != null) {
      map['txn_number'] = Variable<String>(txnNumber);
    }
    if (!nullToAbsent || financialYear != null) {
      map['financial_year'] = Variable<String>(financialYear);
    }
    map['business_unit_id'] = Variable<String>(businessUnitId);
    map['revenue_category_id'] = Variable<String>(revenueCategoryId);
    map['business_date'] = Variable<String>(businessDate);
    map['pnl_period_key'] = Variable<String>(pnlPeriodKey);
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['entry_kind'] = Variable<String>(entryKind);
    if (!nullToAbsent || sourceReference != null) {
      map['source_reference'] = Variable<String>(sourceReference);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_by'] = Variable<String>(createdBy);
    if (!nullToAbsent || voidedAt != null) {
      map['voided_at'] = Variable<DateTime>(voidedAt);
    }
    if (!nullToAbsent || voidedBy != null) {
      map['voided_by'] = Variable<String>(voidedBy);
    }
    if (!nullToAbsent || voidReason != null) {
      map['void_reason'] = Variable<String>(voidReason);
    }
    if (!nullToAbsent || pendingMutationId != null) {
      map['pending_mutation_id'] = Variable<String>(pendingMutationId);
    }
    map['row_version'] = Variable<int>(rowVersion);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || scopeRevokedAt != null) {
      map['scope_revoked_at'] = Variable<DateTime>(scopeRevokedAt);
    }
    return map;
  }

  RevenueEntriesCompanion toCompanion(bool nullToAbsent) {
    return RevenueEntriesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      txnNumber: txnNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(txnNumber),
      financialYear: financialYear == null && nullToAbsent
          ? const Value.absent()
          : Value(financialYear),
      businessUnitId: Value(businessUnitId),
      revenueCategoryId: Value(revenueCategoryId),
      businessDate: Value(businessDate),
      pnlPeriodKey: Value(pnlPeriodKey),
      capturedAt: Value(capturedAt),
      entryKind: Value(entryKind),
      sourceReference: sourceReference == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceReference),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdBy: Value(createdBy),
      voidedAt: voidedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(voidedAt),
      voidedBy: voidedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(voidedBy),
      voidReason: voidReason == null && nullToAbsent
          ? const Value.absent()
          : Value(voidReason),
      pendingMutationId: pendingMutationId == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingMutationId),
      rowVersion: Value(rowVersion),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      updatedAt: Value(updatedAt),
      scopeRevokedAt: scopeRevokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeRevokedAt),
    );
  }

  factory RevenueEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueEntryRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      txnNumber: serializer.fromJson<String?>(json['txnNumber']),
      financialYear: serializer.fromJson<String?>(json['financialYear']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
      revenueCategoryId: serializer.fromJson<String>(json['revenueCategoryId']),
      businessDate: serializer.fromJson<String>(json['businessDate']),
      pnlPeriodKey: serializer.fromJson<String>(json['pnlPeriodKey']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      entryKind: serializer.fromJson<String>(json['entryKind']),
      sourceReference: serializer.fromJson<String?>(json['sourceReference']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      voidedAt: serializer.fromJson<DateTime?>(json['voidedAt']),
      voidedBy: serializer.fromJson<String?>(json['voidedBy']),
      voidReason: serializer.fromJson<String?>(json['voidReason']),
      pendingMutationId: serializer.fromJson<String?>(
        json['pendingMutationId'],
      ),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      scopeRevokedAt: serializer.fromJson<DateTime?>(json['scopeRevokedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'txnNumber': serializer.toJson<String?>(txnNumber),
      'financialYear': serializer.toJson<String?>(financialYear),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
      'revenueCategoryId': serializer.toJson<String>(revenueCategoryId),
      'businessDate': serializer.toJson<String>(businessDate),
      'pnlPeriodKey': serializer.toJson<String>(pnlPeriodKey),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'entryKind': serializer.toJson<String>(entryKind),
      'sourceReference': serializer.toJson<String?>(sourceReference),
      'notes': serializer.toJson<String?>(notes),
      'createdBy': serializer.toJson<String>(createdBy),
      'voidedAt': serializer.toJson<DateTime?>(voidedAt),
      'voidedBy': serializer.toJson<String?>(voidedBy),
      'voidReason': serializer.toJson<String?>(voidReason),
      'pendingMutationId': serializer.toJson<String?>(pendingMutationId),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'scopeRevokedAt': serializer.toJson<DateTime?>(scopeRevokedAt),
    };
  }

  RevenueEntryRow copyWith({
    String? id,
    String? orgId,
    Value<String?> txnNumber = const Value.absent(),
    Value<String?> financialYear = const Value.absent(),
    String? businessUnitId,
    String? revenueCategoryId,
    String? businessDate,
    String? pnlPeriodKey,
    DateTime? capturedAt,
    String? entryKind,
    Value<String?> sourceReference = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? createdBy,
    Value<DateTime?> voidedAt = const Value.absent(),
    Value<String?> voidedBy = const Value.absent(),
    Value<String?> voidReason = const Value.absent(),
    Value<String?> pendingMutationId = const Value.absent(),
    int? rowVersion,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? updatedAt,
    Value<DateTime?> scopeRevokedAt = const Value.absent(),
  }) => RevenueEntryRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    txnNumber: txnNumber.present ? txnNumber.value : this.txnNumber,
    financialYear: financialYear.present
        ? financialYear.value
        : this.financialYear,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
    businessDate: businessDate ?? this.businessDate,
    pnlPeriodKey: pnlPeriodKey ?? this.pnlPeriodKey,
    capturedAt: capturedAt ?? this.capturedAt,
    entryKind: entryKind ?? this.entryKind,
    sourceReference: sourceReference.present
        ? sourceReference.value
        : this.sourceReference,
    notes: notes.present ? notes.value : this.notes,
    createdBy: createdBy ?? this.createdBy,
    voidedAt: voidedAt.present ? voidedAt.value : this.voidedAt,
    voidedBy: voidedBy.present ? voidedBy.value : this.voidedBy,
    voidReason: voidReason.present ? voidReason.value : this.voidReason,
    pendingMutationId: pendingMutationId.present
        ? pendingMutationId.value
        : this.pendingMutationId,
    rowVersion: rowVersion ?? this.rowVersion,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    scopeRevokedAt: scopeRevokedAt.present
        ? scopeRevokedAt.value
        : this.scopeRevokedAt,
  );
  RevenueEntryRow copyWithCompanion(RevenueEntriesCompanion data) {
    return RevenueEntryRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      txnNumber: data.txnNumber.present ? data.txnNumber.value : this.txnNumber,
      financialYear: data.financialYear.present
          ? data.financialYear.value
          : this.financialYear,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      revenueCategoryId: data.revenueCategoryId.present
          ? data.revenueCategoryId.value
          : this.revenueCategoryId,
      businessDate: data.businessDate.present
          ? data.businessDate.value
          : this.businessDate,
      pnlPeriodKey: data.pnlPeriodKey.present
          ? data.pnlPeriodKey.value
          : this.pnlPeriodKey,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      entryKind: data.entryKind.present ? data.entryKind.value : this.entryKind,
      sourceReference: data.sourceReference.present
          ? data.sourceReference.value
          : this.sourceReference,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      voidedAt: data.voidedAt.present ? data.voidedAt.value : this.voidedAt,
      voidedBy: data.voidedBy.present ? data.voidedBy.value : this.voidedBy,
      voidReason: data.voidReason.present
          ? data.voidReason.value
          : this.voidReason,
      pendingMutationId: data.pendingMutationId.present
          ? data.pendingMutationId.value
          : this.pendingMutationId,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      scopeRevokedAt: data.scopeRevokedAt.present
          ? data.scopeRevokedAt.value
          : this.scopeRevokedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueEntryRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('txnNumber: $txnNumber, ')
          ..write('financialYear: $financialYear, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('businessDate: $businessDate, ')
          ..write('pnlPeriodKey: $pnlPeriodKey, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('entryKind: $entryKind, ')
          ..write('sourceReference: $sourceReference, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('voidedAt: $voidedAt, ')
          ..write('voidedBy: $voidedBy, ')
          ..write('voidReason: $voidReason, ')
          ..write('pendingMutationId: $pendingMutationId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scopeRevokedAt: $scopeRevokedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    orgId,
    txnNumber,
    financialYear,
    businessUnitId,
    revenueCategoryId,
    businessDate,
    pnlPeriodKey,
    capturedAt,
    entryKind,
    sourceReference,
    notes,
    createdBy,
    voidedAt,
    voidedBy,
    voidReason,
    pendingMutationId,
    rowVersion,
    serverUpdatedAt,
    updatedAt,
    scopeRevokedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueEntryRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.txnNumber == this.txnNumber &&
          other.financialYear == this.financialYear &&
          other.businessUnitId == this.businessUnitId &&
          other.revenueCategoryId == this.revenueCategoryId &&
          other.businessDate == this.businessDate &&
          other.pnlPeriodKey == this.pnlPeriodKey &&
          other.capturedAt == this.capturedAt &&
          other.entryKind == this.entryKind &&
          other.sourceReference == this.sourceReference &&
          other.notes == this.notes &&
          other.createdBy == this.createdBy &&
          other.voidedAt == this.voidedAt &&
          other.voidedBy == this.voidedBy &&
          other.voidReason == this.voidReason &&
          other.pendingMutationId == this.pendingMutationId &&
          other.rowVersion == this.rowVersion &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.updatedAt == this.updatedAt &&
          other.scopeRevokedAt == this.scopeRevokedAt);
}

class RevenueEntriesCompanion extends UpdateCompanion<RevenueEntryRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String?> txnNumber;
  final Value<String?> financialYear;
  final Value<String> businessUnitId;
  final Value<String> revenueCategoryId;
  final Value<String> businessDate;
  final Value<String> pnlPeriodKey;
  final Value<DateTime> capturedAt;
  final Value<String> entryKind;
  final Value<String?> sourceReference;
  final Value<String?> notes;
  final Value<String> createdBy;
  final Value<DateTime?> voidedAt;
  final Value<String?> voidedBy;
  final Value<String?> voidReason;
  final Value<String?> pendingMutationId;
  final Value<int> rowVersion;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> scopeRevokedAt;
  final Value<int> rowid;
  const RevenueEntriesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.txnNumber = const Value.absent(),
    this.financialYear = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.revenueCategoryId = const Value.absent(),
    this.businessDate = const Value.absent(),
    this.pnlPeriodKey = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.entryKind = const Value.absent(),
    this.sourceReference = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.voidedAt = const Value.absent(),
    this.voidedBy = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.pendingMutationId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.scopeRevokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueEntriesCompanion.insert({
    required String id,
    required String orgId,
    this.txnNumber = const Value.absent(),
    this.financialYear = const Value.absent(),
    required String businessUnitId,
    required String revenueCategoryId,
    required String businessDate,
    required String pnlPeriodKey,
    required DateTime capturedAt,
    this.entryKind = const Value.absent(),
    this.sourceReference = const Value.absent(),
    this.notes = const Value.absent(),
    required String createdBy,
    this.voidedAt = const Value.absent(),
    this.voidedBy = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.pendingMutationId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    required DateTime updatedAt,
    this.scopeRevokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       businessUnitId = Value(businessUnitId),
       revenueCategoryId = Value(revenueCategoryId),
       businessDate = Value(businessDate),
       pnlPeriodKey = Value(pnlPeriodKey),
       capturedAt = Value(capturedAt),
       createdBy = Value(createdBy),
       updatedAt = Value(updatedAt);
  static Insertable<RevenueEntryRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? txnNumber,
    Expression<String>? financialYear,
    Expression<String>? businessUnitId,
    Expression<String>? revenueCategoryId,
    Expression<String>? businessDate,
    Expression<String>? pnlPeriodKey,
    Expression<DateTime>? capturedAt,
    Expression<String>? entryKind,
    Expression<String>? sourceReference,
    Expression<String>? notes,
    Expression<String>? createdBy,
    Expression<DateTime>? voidedAt,
    Expression<String>? voidedBy,
    Expression<String>? voidReason,
    Expression<String>? pendingMutationId,
    Expression<int>? rowVersion,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? scopeRevokedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (txnNumber != null) 'txn_number': txnNumber,
      if (financialYear != null) 'financial_year': financialYear,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (revenueCategoryId != null) 'revenue_category_id': revenueCategoryId,
      if (businessDate != null) 'business_date': businessDate,
      if (pnlPeriodKey != null) 'pnl_period_key': pnlPeriodKey,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (entryKind != null) 'entry_kind': entryKind,
      if (sourceReference != null) 'source_reference': sourceReference,
      if (notes != null) 'notes': notes,
      if (createdBy != null) 'created_by': createdBy,
      if (voidedAt != null) 'voided_at': voidedAt,
      if (voidedBy != null) 'voided_by': voidedBy,
      if (voidReason != null) 'void_reason': voidReason,
      if (pendingMutationId != null) 'pending_mutation_id': pendingMutationId,
      if (rowVersion != null) 'row_version': rowVersion,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (scopeRevokedAt != null) 'scope_revoked_at': scopeRevokedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String?>? txnNumber,
    Value<String?>? financialYear,
    Value<String>? businessUnitId,
    Value<String>? revenueCategoryId,
    Value<String>? businessDate,
    Value<String>? pnlPeriodKey,
    Value<DateTime>? capturedAt,
    Value<String>? entryKind,
    Value<String?>? sourceReference,
    Value<String?>? notes,
    Value<String>? createdBy,
    Value<DateTime?>? voidedAt,
    Value<String?>? voidedBy,
    Value<String?>? voidReason,
    Value<String?>? pendingMutationId,
    Value<int>? rowVersion,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? scopeRevokedAt,
    Value<int>? rowid,
  }) {
    return RevenueEntriesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      txnNumber: txnNumber ?? this.txnNumber,
      financialYear: financialYear ?? this.financialYear,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
      businessDate: businessDate ?? this.businessDate,
      pnlPeriodKey: pnlPeriodKey ?? this.pnlPeriodKey,
      capturedAt: capturedAt ?? this.capturedAt,
      entryKind: entryKind ?? this.entryKind,
      sourceReference: sourceReference ?? this.sourceReference,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      voidedAt: voidedAt ?? this.voidedAt,
      voidedBy: voidedBy ?? this.voidedBy,
      voidReason: voidReason ?? this.voidReason,
      pendingMutationId: pendingMutationId ?? this.pendingMutationId,
      rowVersion: rowVersion ?? this.rowVersion,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scopeRevokedAt: scopeRevokedAt ?? this.scopeRevokedAt,
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
    if (txnNumber.present) {
      map['txn_number'] = Variable<String>(txnNumber.value);
    }
    if (financialYear.present) {
      map['financial_year'] = Variable<String>(financialYear.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (revenueCategoryId.present) {
      map['revenue_category_id'] = Variable<String>(revenueCategoryId.value);
    }
    if (businessDate.present) {
      map['business_date'] = Variable<String>(businessDate.value);
    }
    if (pnlPeriodKey.present) {
      map['pnl_period_key'] = Variable<String>(pnlPeriodKey.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (entryKind.present) {
      map['entry_kind'] = Variable<String>(entryKind.value);
    }
    if (sourceReference.present) {
      map['source_reference'] = Variable<String>(sourceReference.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (voidedAt.present) {
      map['voided_at'] = Variable<DateTime>(voidedAt.value);
    }
    if (voidedBy.present) {
      map['voided_by'] = Variable<String>(voidedBy.value);
    }
    if (voidReason.present) {
      map['void_reason'] = Variable<String>(voidReason.value);
    }
    if (pendingMutationId.present) {
      map['pending_mutation_id'] = Variable<String>(pendingMutationId.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (scopeRevokedAt.present) {
      map['scope_revoked_at'] = Variable<DateTime>(scopeRevokedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueEntriesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('txnNumber: $txnNumber, ')
          ..write('financialYear: $financialYear, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('businessDate: $businessDate, ')
          ..write('pnlPeriodKey: $pnlPeriodKey, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('entryKind: $entryKind, ')
          ..write('sourceReference: $sourceReference, ')
          ..write('notes: $notes, ')
          ..write('createdBy: $createdBy, ')
          ..write('voidedAt: $voidedAt, ')
          ..write('voidedBy: $voidedBy, ')
          ..write('voidReason: $voidReason, ')
          ..write('pendingMutationId: $pendingMutationId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scopeRevokedAt: $scopeRevokedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueComponentsTable extends RevenueComponents
    with TableInfo<$RevenueComponentsTable, RevenueComponentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueComponentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _revenueEntryIdMeta = const VerificationMeta(
    'revenueEntryId',
  );
  @override
  late final GeneratedColumn<String> revenueEntryId = GeneratedColumn<String>(
    'revenue_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES revenue_entries (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _enteredAmountMinorMeta =
      const VerificationMeta('enteredAmountMinor');
  @override
  late final GeneratedColumn<int> enteredAmountMinor = GeneratedColumn<int>(
    'entered_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enteredBasisMeta = const VerificationMeta(
    'enteredBasis',
  );
  @override
  late final GeneratedColumn<String> enteredBasis = GeneratedColumn<String>(
    'entered_basis',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grossAmountMinorMeta = const VerificationMeta(
    'grossAmountMinor',
  );
  @override
  late final GeneratedColumn<int> grossAmountMinor = GeneratedColumn<int>(
    'gross_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxAmountMinorMeta = const VerificationMeta(
    'taxAmountMinor',
  );
  @override
  late final GeneratedColumn<int> taxAmountMinor = GeneratedColumn<int>(
    'tax_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netAmountMinorMeta = const VerificationMeta(
    'netAmountMinor',
  );
  @override
  late final GeneratedColumn<int> netAmountMinor = GeneratedColumn<int>(
    'net_amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxRuleIdMeta = const VerificationMeta(
    'taxRuleId',
  );
  @override
  late final GeneratedColumn<String> taxRuleId = GeneratedColumn<String>(
    'tax_rule_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxRateBasisPointsMeta =
      const VerificationMeta('taxRateBasisPoints');
  @override
  late final GeneratedColumn<int> taxRateBasisPoints = GeneratedColumn<int>(
    'tax_rate_basis_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxTreatmentMeta = const VerificationMeta(
    'taxTreatment',
  );
  @override
  late final GeneratedColumn<String> taxTreatment = GeneratedColumn<String>(
    'tax_treatment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueBandIdMeta = const VerificationMeta(
    'valueBandId',
  );
  @override
  late final GeneratedColumn<String> valueBandId = GeneratedColumn<String>(
    'value_band_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueBandLabelMeta = const VerificationMeta(
    'valueBandLabel',
  );
  @override
  late final GeneratedColumn<String> valueBandLabel = GeneratedColumn<String>(
    'value_band_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueBandFloorMinorMeta =
      const VerificationMeta('valueBandFloorMinor');
  @override
  late final GeneratedColumn<int> valueBandFloorMinor = GeneratedColumn<int>(
    'value_band_floor_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueBandCeilingMinorMeta =
      const VerificationMeta('valueBandCeilingMinor');
  @override
  late final GeneratedColumn<int> valueBandCeilingMinor = GeneratedColumn<int>(
    'value_band_ceiling_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supplySubtypeIdMeta = const VerificationMeta(
    'supplySubtypeId',
  );
  @override
  late final GeneratedColumn<String> supplySubtypeId = GeneratedColumn<String>(
    'supply_subtype_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supplySubtypeLabelMeta =
      const VerificationMeta('supplySubtypeLabel');
  @override
  late final GeneratedColumn<String> supplySubtypeLabel =
      GeneratedColumn<String>(
        'supply_subtype_label',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _premisesStatusCodeMeta =
      const VerificationMeta('premisesStatusCode');
  @override
  late final GeneratedColumn<String> premisesStatusCode =
      GeneratedColumn<String>(
        'premises_status_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    revenueEntryId,
    enteredAmountMinor,
    enteredBasis,
    grossAmountMinor,
    taxAmountMinor,
    netAmountMinor,
    taxRuleId,
    taxRateBasisPoints,
    taxTreatment,
    valueBandId,
    valueBandLabel,
    valueBandFloorMinor,
    valueBandCeilingMinor,
    supplySubtypeId,
    supplySubtypeLabel,
    premisesStatusCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_components';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueComponentRow> instance, {
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
    if (data.containsKey('revenue_entry_id')) {
      context.handle(
        _revenueEntryIdMeta,
        revenueEntryId.isAcceptableOrUnknown(
          data['revenue_entry_id']!,
          _revenueEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revenueEntryIdMeta);
    }
    if (data.containsKey('entered_amount_minor')) {
      context.handle(
        _enteredAmountMinorMeta,
        enteredAmountMinor.isAcceptableOrUnknown(
          data['entered_amount_minor']!,
          _enteredAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_enteredAmountMinorMeta);
    }
    if (data.containsKey('entered_basis')) {
      context.handle(
        _enteredBasisMeta,
        enteredBasis.isAcceptableOrUnknown(
          data['entered_basis']!,
          _enteredBasisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_enteredBasisMeta);
    }
    if (data.containsKey('gross_amount_minor')) {
      context.handle(
        _grossAmountMinorMeta,
        grossAmountMinor.isAcceptableOrUnknown(
          data['gross_amount_minor']!,
          _grossAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_grossAmountMinorMeta);
    }
    if (data.containsKey('tax_amount_minor')) {
      context.handle(
        _taxAmountMinorMeta,
        taxAmountMinor.isAcceptableOrUnknown(
          data['tax_amount_minor']!,
          _taxAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_taxAmountMinorMeta);
    }
    if (data.containsKey('net_amount_minor')) {
      context.handle(
        _netAmountMinorMeta,
        netAmountMinor.isAcceptableOrUnknown(
          data['net_amount_minor']!,
          _netAmountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_netAmountMinorMeta);
    }
    if (data.containsKey('tax_rule_id')) {
      context.handle(
        _taxRuleIdMeta,
        taxRuleId.isAcceptableOrUnknown(data['tax_rule_id']!, _taxRuleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taxRuleIdMeta);
    }
    if (data.containsKey('tax_rate_basis_points')) {
      context.handle(
        _taxRateBasisPointsMeta,
        taxRateBasisPoints.isAcceptableOrUnknown(
          data['tax_rate_basis_points']!,
          _taxRateBasisPointsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_taxRateBasisPointsMeta);
    }
    if (data.containsKey('tax_treatment')) {
      context.handle(
        _taxTreatmentMeta,
        taxTreatment.isAcceptableOrUnknown(
          data['tax_treatment']!,
          _taxTreatmentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_taxTreatmentMeta);
    }
    if (data.containsKey('value_band_id')) {
      context.handle(
        _valueBandIdMeta,
        valueBandId.isAcceptableOrUnknown(
          data['value_band_id']!,
          _valueBandIdMeta,
        ),
      );
    }
    if (data.containsKey('value_band_label')) {
      context.handle(
        _valueBandLabelMeta,
        valueBandLabel.isAcceptableOrUnknown(
          data['value_band_label']!,
          _valueBandLabelMeta,
        ),
      );
    }
    if (data.containsKey('value_band_floor_minor')) {
      context.handle(
        _valueBandFloorMinorMeta,
        valueBandFloorMinor.isAcceptableOrUnknown(
          data['value_band_floor_minor']!,
          _valueBandFloorMinorMeta,
        ),
      );
    }
    if (data.containsKey('value_band_ceiling_minor')) {
      context.handle(
        _valueBandCeilingMinorMeta,
        valueBandCeilingMinor.isAcceptableOrUnknown(
          data['value_band_ceiling_minor']!,
          _valueBandCeilingMinorMeta,
        ),
      );
    }
    if (data.containsKey('supply_subtype_id')) {
      context.handle(
        _supplySubtypeIdMeta,
        supplySubtypeId.isAcceptableOrUnknown(
          data['supply_subtype_id']!,
          _supplySubtypeIdMeta,
        ),
      );
    }
    if (data.containsKey('supply_subtype_label')) {
      context.handle(
        _supplySubtypeLabelMeta,
        supplySubtypeLabel.isAcceptableOrUnknown(
          data['supply_subtype_label']!,
          _supplySubtypeLabelMeta,
        ),
      );
    }
    if (data.containsKey('premises_status_code')) {
      context.handle(
        _premisesStatusCodeMeta,
        premisesStatusCode.isAcceptableOrUnknown(
          data['premises_status_code']!,
          _premisesStatusCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevenueComponentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueComponentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      revenueEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revenue_entry_id'],
      )!,
      enteredAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entered_amount_minor'],
      )!,
      enteredBasis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entered_basis'],
      )!,
      grossAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gross_amount_minor'],
      )!,
      taxAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_amount_minor'],
      )!,
      netAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}net_amount_minor'],
      )!,
      taxRuleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tax_rule_id'],
      )!,
      taxRateBasisPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_rate_basis_points'],
      )!,
      taxTreatment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tax_treatment'],
      )!,
      valueBandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_band_id'],
      ),
      valueBandLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_band_label'],
      ),
      valueBandFloorMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_band_floor_minor'],
      ),
      valueBandCeilingMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_band_ceiling_minor'],
      ),
      supplySubtypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supply_subtype_id'],
      ),
      supplySubtypeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supply_subtype_label'],
      ),
      premisesStatusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}premises_status_code'],
      ),
    );
  }

  @override
  $RevenueComponentsTable createAlias(String alias) {
    return $RevenueComponentsTable(attachedDatabase, alias);
  }
}

class RevenueComponentRow extends DataClass
    implements Insertable<RevenueComponentRow> {
  final String id;
  final String orgId;

  /// Cascade is scoped to local cache maintenance: the purge and the reconciler delete
  /// **entries**, and their components go with them. Nothing in the product deletes a
  /// revenue document — correction is by void plus audit (D-006) — so this cascade can
  /// never become a business-level destructive delete.
  final String revenueEntryId;

  /// What the operator actually typed, and as what (D-080, D-097).
  final int enteredAmountMinor;

  /// `inclusive_total` | `pre_tax`. There is no third value (D-097).
  final String enteredBasis;

  /// Derived once, half-up, at the record.
  final int grossAmountMinor;
  final int taxAmountMinor;
  final int netAmountMinor;

  /// A **soft pointer**. The rule cache is server-owned reference data and may legitimately
  /// be purged when a scope is revoked, while this component must remain explainable from
  /// its own snapshot columns (D-070 §11). A foreign key here would either block that
  /// purge or destroy the retained work it is meant to spare.
  final String taxRuleId;
  final int taxRateBasisPoints;

  /// `inclusive` | `exclusive` | `none`.
  final String taxTreatment;

  /// The configured band this amount was attributed to, **selected by the operator**.
  ///
  /// Soft pointer, for the same reason as [taxRuleId]. [valueBandFloorMinor] and
  /// [valueBandCeilingMinor] are the band's tariff boundaries, carried for **historical
  /// explanation only**: nothing compares them against [enteredAmountMinor] or any
  /// revenue total, because a day's aggregate attributable to a band is not a
  /// per-room-per-night tariff (D-094).
  final String? valueBandId;
  final String? valueBandLabel;
  final int? valueBandFloorMinor;
  final int? valueBandCeilingMinor;
  final String? supplySubtypeId;
  final String? supplySubtypeLabel;
  final String? premisesStatusCode;
  const RevenueComponentRow({
    required this.id,
    required this.orgId,
    required this.revenueEntryId,
    required this.enteredAmountMinor,
    required this.enteredBasis,
    required this.grossAmountMinor,
    required this.taxAmountMinor,
    required this.netAmountMinor,
    required this.taxRuleId,
    required this.taxRateBasisPoints,
    required this.taxTreatment,
    this.valueBandId,
    this.valueBandLabel,
    this.valueBandFloorMinor,
    this.valueBandCeilingMinor,
    this.supplySubtypeId,
    this.supplySubtypeLabel,
    this.premisesStatusCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['revenue_entry_id'] = Variable<String>(revenueEntryId);
    map['entered_amount_minor'] = Variable<int>(enteredAmountMinor);
    map['entered_basis'] = Variable<String>(enteredBasis);
    map['gross_amount_minor'] = Variable<int>(grossAmountMinor);
    map['tax_amount_minor'] = Variable<int>(taxAmountMinor);
    map['net_amount_minor'] = Variable<int>(netAmountMinor);
    map['tax_rule_id'] = Variable<String>(taxRuleId);
    map['tax_rate_basis_points'] = Variable<int>(taxRateBasisPoints);
    map['tax_treatment'] = Variable<String>(taxTreatment);
    if (!nullToAbsent || valueBandId != null) {
      map['value_band_id'] = Variable<String>(valueBandId);
    }
    if (!nullToAbsent || valueBandLabel != null) {
      map['value_band_label'] = Variable<String>(valueBandLabel);
    }
    if (!nullToAbsent || valueBandFloorMinor != null) {
      map['value_band_floor_minor'] = Variable<int>(valueBandFloorMinor);
    }
    if (!nullToAbsent || valueBandCeilingMinor != null) {
      map['value_band_ceiling_minor'] = Variable<int>(valueBandCeilingMinor);
    }
    if (!nullToAbsent || supplySubtypeId != null) {
      map['supply_subtype_id'] = Variable<String>(supplySubtypeId);
    }
    if (!nullToAbsent || supplySubtypeLabel != null) {
      map['supply_subtype_label'] = Variable<String>(supplySubtypeLabel);
    }
    if (!nullToAbsent || premisesStatusCode != null) {
      map['premises_status_code'] = Variable<String>(premisesStatusCode);
    }
    return map;
  }

  RevenueComponentsCompanion toCompanion(bool nullToAbsent) {
    return RevenueComponentsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      revenueEntryId: Value(revenueEntryId),
      enteredAmountMinor: Value(enteredAmountMinor),
      enteredBasis: Value(enteredBasis),
      grossAmountMinor: Value(grossAmountMinor),
      taxAmountMinor: Value(taxAmountMinor),
      netAmountMinor: Value(netAmountMinor),
      taxRuleId: Value(taxRuleId),
      taxRateBasisPoints: Value(taxRateBasisPoints),
      taxTreatment: Value(taxTreatment),
      valueBandId: valueBandId == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBandId),
      valueBandLabel: valueBandLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBandLabel),
      valueBandFloorMinor: valueBandFloorMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBandFloorMinor),
      valueBandCeilingMinor: valueBandCeilingMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(valueBandCeilingMinor),
      supplySubtypeId: supplySubtypeId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplySubtypeId),
      supplySubtypeLabel: supplySubtypeLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(supplySubtypeLabel),
      premisesStatusCode: premisesStatusCode == null && nullToAbsent
          ? const Value.absent()
          : Value(premisesStatusCode),
    );
  }

  factory RevenueComponentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueComponentRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      revenueEntryId: serializer.fromJson<String>(json['revenueEntryId']),
      enteredAmountMinor: serializer.fromJson<int>(json['enteredAmountMinor']),
      enteredBasis: serializer.fromJson<String>(json['enteredBasis']),
      grossAmountMinor: serializer.fromJson<int>(json['grossAmountMinor']),
      taxAmountMinor: serializer.fromJson<int>(json['taxAmountMinor']),
      netAmountMinor: serializer.fromJson<int>(json['netAmountMinor']),
      taxRuleId: serializer.fromJson<String>(json['taxRuleId']),
      taxRateBasisPoints: serializer.fromJson<int>(json['taxRateBasisPoints']),
      taxTreatment: serializer.fromJson<String>(json['taxTreatment']),
      valueBandId: serializer.fromJson<String?>(json['valueBandId']),
      valueBandLabel: serializer.fromJson<String?>(json['valueBandLabel']),
      valueBandFloorMinor: serializer.fromJson<int?>(
        json['valueBandFloorMinor'],
      ),
      valueBandCeilingMinor: serializer.fromJson<int?>(
        json['valueBandCeilingMinor'],
      ),
      supplySubtypeId: serializer.fromJson<String?>(json['supplySubtypeId']),
      supplySubtypeLabel: serializer.fromJson<String?>(
        json['supplySubtypeLabel'],
      ),
      premisesStatusCode: serializer.fromJson<String?>(
        json['premisesStatusCode'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'revenueEntryId': serializer.toJson<String>(revenueEntryId),
      'enteredAmountMinor': serializer.toJson<int>(enteredAmountMinor),
      'enteredBasis': serializer.toJson<String>(enteredBasis),
      'grossAmountMinor': serializer.toJson<int>(grossAmountMinor),
      'taxAmountMinor': serializer.toJson<int>(taxAmountMinor),
      'netAmountMinor': serializer.toJson<int>(netAmountMinor),
      'taxRuleId': serializer.toJson<String>(taxRuleId),
      'taxRateBasisPoints': serializer.toJson<int>(taxRateBasisPoints),
      'taxTreatment': serializer.toJson<String>(taxTreatment),
      'valueBandId': serializer.toJson<String?>(valueBandId),
      'valueBandLabel': serializer.toJson<String?>(valueBandLabel),
      'valueBandFloorMinor': serializer.toJson<int?>(valueBandFloorMinor),
      'valueBandCeilingMinor': serializer.toJson<int?>(valueBandCeilingMinor),
      'supplySubtypeId': serializer.toJson<String?>(supplySubtypeId),
      'supplySubtypeLabel': serializer.toJson<String?>(supplySubtypeLabel),
      'premisesStatusCode': serializer.toJson<String?>(premisesStatusCode),
    };
  }

  RevenueComponentRow copyWith({
    String? id,
    String? orgId,
    String? revenueEntryId,
    int? enteredAmountMinor,
    String? enteredBasis,
    int? grossAmountMinor,
    int? taxAmountMinor,
    int? netAmountMinor,
    String? taxRuleId,
    int? taxRateBasisPoints,
    String? taxTreatment,
    Value<String?> valueBandId = const Value.absent(),
    Value<String?> valueBandLabel = const Value.absent(),
    Value<int?> valueBandFloorMinor = const Value.absent(),
    Value<int?> valueBandCeilingMinor = const Value.absent(),
    Value<String?> supplySubtypeId = const Value.absent(),
    Value<String?> supplySubtypeLabel = const Value.absent(),
    Value<String?> premisesStatusCode = const Value.absent(),
  }) => RevenueComponentRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    revenueEntryId: revenueEntryId ?? this.revenueEntryId,
    enteredAmountMinor: enteredAmountMinor ?? this.enteredAmountMinor,
    enteredBasis: enteredBasis ?? this.enteredBasis,
    grossAmountMinor: grossAmountMinor ?? this.grossAmountMinor,
    taxAmountMinor: taxAmountMinor ?? this.taxAmountMinor,
    netAmountMinor: netAmountMinor ?? this.netAmountMinor,
    taxRuleId: taxRuleId ?? this.taxRuleId,
    taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
    taxTreatment: taxTreatment ?? this.taxTreatment,
    valueBandId: valueBandId.present ? valueBandId.value : this.valueBandId,
    valueBandLabel: valueBandLabel.present
        ? valueBandLabel.value
        : this.valueBandLabel,
    valueBandFloorMinor: valueBandFloorMinor.present
        ? valueBandFloorMinor.value
        : this.valueBandFloorMinor,
    valueBandCeilingMinor: valueBandCeilingMinor.present
        ? valueBandCeilingMinor.value
        : this.valueBandCeilingMinor,
    supplySubtypeId: supplySubtypeId.present
        ? supplySubtypeId.value
        : this.supplySubtypeId,
    supplySubtypeLabel: supplySubtypeLabel.present
        ? supplySubtypeLabel.value
        : this.supplySubtypeLabel,
    premisesStatusCode: premisesStatusCode.present
        ? premisesStatusCode.value
        : this.premisesStatusCode,
  );
  RevenueComponentRow copyWithCompanion(RevenueComponentsCompanion data) {
    return RevenueComponentRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      revenueEntryId: data.revenueEntryId.present
          ? data.revenueEntryId.value
          : this.revenueEntryId,
      enteredAmountMinor: data.enteredAmountMinor.present
          ? data.enteredAmountMinor.value
          : this.enteredAmountMinor,
      enteredBasis: data.enteredBasis.present
          ? data.enteredBasis.value
          : this.enteredBasis,
      grossAmountMinor: data.grossAmountMinor.present
          ? data.grossAmountMinor.value
          : this.grossAmountMinor,
      taxAmountMinor: data.taxAmountMinor.present
          ? data.taxAmountMinor.value
          : this.taxAmountMinor,
      netAmountMinor: data.netAmountMinor.present
          ? data.netAmountMinor.value
          : this.netAmountMinor,
      taxRuleId: data.taxRuleId.present ? data.taxRuleId.value : this.taxRuleId,
      taxRateBasisPoints: data.taxRateBasisPoints.present
          ? data.taxRateBasisPoints.value
          : this.taxRateBasisPoints,
      taxTreatment: data.taxTreatment.present
          ? data.taxTreatment.value
          : this.taxTreatment,
      valueBandId: data.valueBandId.present
          ? data.valueBandId.value
          : this.valueBandId,
      valueBandLabel: data.valueBandLabel.present
          ? data.valueBandLabel.value
          : this.valueBandLabel,
      valueBandFloorMinor: data.valueBandFloorMinor.present
          ? data.valueBandFloorMinor.value
          : this.valueBandFloorMinor,
      valueBandCeilingMinor: data.valueBandCeilingMinor.present
          ? data.valueBandCeilingMinor.value
          : this.valueBandCeilingMinor,
      supplySubtypeId: data.supplySubtypeId.present
          ? data.supplySubtypeId.value
          : this.supplySubtypeId,
      supplySubtypeLabel: data.supplySubtypeLabel.present
          ? data.supplySubtypeLabel.value
          : this.supplySubtypeLabel,
      premisesStatusCode: data.premisesStatusCode.present
          ? data.premisesStatusCode.value
          : this.premisesStatusCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueComponentRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueEntryId: $revenueEntryId, ')
          ..write('enteredAmountMinor: $enteredAmountMinor, ')
          ..write('enteredBasis: $enteredBasis, ')
          ..write('grossAmountMinor: $grossAmountMinor, ')
          ..write('taxAmountMinor: $taxAmountMinor, ')
          ..write('netAmountMinor: $netAmountMinor, ')
          ..write('taxRuleId: $taxRuleId, ')
          ..write('taxRateBasisPoints: $taxRateBasisPoints, ')
          ..write('taxTreatment: $taxTreatment, ')
          ..write('valueBandId: $valueBandId, ')
          ..write('valueBandLabel: $valueBandLabel, ')
          ..write('valueBandFloorMinor: $valueBandFloorMinor, ')
          ..write('valueBandCeilingMinor: $valueBandCeilingMinor, ')
          ..write('supplySubtypeId: $supplySubtypeId, ')
          ..write('supplySubtypeLabel: $supplySubtypeLabel, ')
          ..write('premisesStatusCode: $premisesStatusCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    revenueEntryId,
    enteredAmountMinor,
    enteredBasis,
    grossAmountMinor,
    taxAmountMinor,
    netAmountMinor,
    taxRuleId,
    taxRateBasisPoints,
    taxTreatment,
    valueBandId,
    valueBandLabel,
    valueBandFloorMinor,
    valueBandCeilingMinor,
    supplySubtypeId,
    supplySubtypeLabel,
    premisesStatusCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueComponentRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.revenueEntryId == this.revenueEntryId &&
          other.enteredAmountMinor == this.enteredAmountMinor &&
          other.enteredBasis == this.enteredBasis &&
          other.grossAmountMinor == this.grossAmountMinor &&
          other.taxAmountMinor == this.taxAmountMinor &&
          other.netAmountMinor == this.netAmountMinor &&
          other.taxRuleId == this.taxRuleId &&
          other.taxRateBasisPoints == this.taxRateBasisPoints &&
          other.taxTreatment == this.taxTreatment &&
          other.valueBandId == this.valueBandId &&
          other.valueBandLabel == this.valueBandLabel &&
          other.valueBandFloorMinor == this.valueBandFloorMinor &&
          other.valueBandCeilingMinor == this.valueBandCeilingMinor &&
          other.supplySubtypeId == this.supplySubtypeId &&
          other.supplySubtypeLabel == this.supplySubtypeLabel &&
          other.premisesStatusCode == this.premisesStatusCode);
}

class RevenueComponentsCompanion extends UpdateCompanion<RevenueComponentRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> revenueEntryId;
  final Value<int> enteredAmountMinor;
  final Value<String> enteredBasis;
  final Value<int> grossAmountMinor;
  final Value<int> taxAmountMinor;
  final Value<int> netAmountMinor;
  final Value<String> taxRuleId;
  final Value<int> taxRateBasisPoints;
  final Value<String> taxTreatment;
  final Value<String?> valueBandId;
  final Value<String?> valueBandLabel;
  final Value<int?> valueBandFloorMinor;
  final Value<int?> valueBandCeilingMinor;
  final Value<String?> supplySubtypeId;
  final Value<String?> supplySubtypeLabel;
  final Value<String?> premisesStatusCode;
  final Value<int> rowid;
  const RevenueComponentsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.revenueEntryId = const Value.absent(),
    this.enteredAmountMinor = const Value.absent(),
    this.enteredBasis = const Value.absent(),
    this.grossAmountMinor = const Value.absent(),
    this.taxAmountMinor = const Value.absent(),
    this.netAmountMinor = const Value.absent(),
    this.taxRuleId = const Value.absent(),
    this.taxRateBasisPoints = const Value.absent(),
    this.taxTreatment = const Value.absent(),
    this.valueBandId = const Value.absent(),
    this.valueBandLabel = const Value.absent(),
    this.valueBandFloorMinor = const Value.absent(),
    this.valueBandCeilingMinor = const Value.absent(),
    this.supplySubtypeId = const Value.absent(),
    this.supplySubtypeLabel = const Value.absent(),
    this.premisesStatusCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueComponentsCompanion.insert({
    required String id,
    required String orgId,
    required String revenueEntryId,
    required int enteredAmountMinor,
    required String enteredBasis,
    required int grossAmountMinor,
    required int taxAmountMinor,
    required int netAmountMinor,
    required String taxRuleId,
    required int taxRateBasisPoints,
    required String taxTreatment,
    this.valueBandId = const Value.absent(),
    this.valueBandLabel = const Value.absent(),
    this.valueBandFloorMinor = const Value.absent(),
    this.valueBandCeilingMinor = const Value.absent(),
    this.supplySubtypeId = const Value.absent(),
    this.supplySubtypeLabel = const Value.absent(),
    this.premisesStatusCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       revenueEntryId = Value(revenueEntryId),
       enteredAmountMinor = Value(enteredAmountMinor),
       enteredBasis = Value(enteredBasis),
       grossAmountMinor = Value(grossAmountMinor),
       taxAmountMinor = Value(taxAmountMinor),
       netAmountMinor = Value(netAmountMinor),
       taxRuleId = Value(taxRuleId),
       taxRateBasisPoints = Value(taxRateBasisPoints),
       taxTreatment = Value(taxTreatment);
  static Insertable<RevenueComponentRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? revenueEntryId,
    Expression<int>? enteredAmountMinor,
    Expression<String>? enteredBasis,
    Expression<int>? grossAmountMinor,
    Expression<int>? taxAmountMinor,
    Expression<int>? netAmountMinor,
    Expression<String>? taxRuleId,
    Expression<int>? taxRateBasisPoints,
    Expression<String>? taxTreatment,
    Expression<String>? valueBandId,
    Expression<String>? valueBandLabel,
    Expression<int>? valueBandFloorMinor,
    Expression<int>? valueBandCeilingMinor,
    Expression<String>? supplySubtypeId,
    Expression<String>? supplySubtypeLabel,
    Expression<String>? premisesStatusCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (revenueEntryId != null) 'revenue_entry_id': revenueEntryId,
      if (enteredAmountMinor != null)
        'entered_amount_minor': enteredAmountMinor,
      if (enteredBasis != null) 'entered_basis': enteredBasis,
      if (grossAmountMinor != null) 'gross_amount_minor': grossAmountMinor,
      if (taxAmountMinor != null) 'tax_amount_minor': taxAmountMinor,
      if (netAmountMinor != null) 'net_amount_minor': netAmountMinor,
      if (taxRuleId != null) 'tax_rule_id': taxRuleId,
      if (taxRateBasisPoints != null)
        'tax_rate_basis_points': taxRateBasisPoints,
      if (taxTreatment != null) 'tax_treatment': taxTreatment,
      if (valueBandId != null) 'value_band_id': valueBandId,
      if (valueBandLabel != null) 'value_band_label': valueBandLabel,
      if (valueBandFloorMinor != null)
        'value_band_floor_minor': valueBandFloorMinor,
      if (valueBandCeilingMinor != null)
        'value_band_ceiling_minor': valueBandCeilingMinor,
      if (supplySubtypeId != null) 'supply_subtype_id': supplySubtypeId,
      if (supplySubtypeLabel != null)
        'supply_subtype_label': supplySubtypeLabel,
      if (premisesStatusCode != null)
        'premises_status_code': premisesStatusCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueComponentsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? revenueEntryId,
    Value<int>? enteredAmountMinor,
    Value<String>? enteredBasis,
    Value<int>? grossAmountMinor,
    Value<int>? taxAmountMinor,
    Value<int>? netAmountMinor,
    Value<String>? taxRuleId,
    Value<int>? taxRateBasisPoints,
    Value<String>? taxTreatment,
    Value<String?>? valueBandId,
    Value<String?>? valueBandLabel,
    Value<int?>? valueBandFloorMinor,
    Value<int?>? valueBandCeilingMinor,
    Value<String?>? supplySubtypeId,
    Value<String?>? supplySubtypeLabel,
    Value<String?>? premisesStatusCode,
    Value<int>? rowid,
  }) {
    return RevenueComponentsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      revenueEntryId: revenueEntryId ?? this.revenueEntryId,
      enteredAmountMinor: enteredAmountMinor ?? this.enteredAmountMinor,
      enteredBasis: enteredBasis ?? this.enteredBasis,
      grossAmountMinor: grossAmountMinor ?? this.grossAmountMinor,
      taxAmountMinor: taxAmountMinor ?? this.taxAmountMinor,
      netAmountMinor: netAmountMinor ?? this.netAmountMinor,
      taxRuleId: taxRuleId ?? this.taxRuleId,
      taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      valueBandId: valueBandId ?? this.valueBandId,
      valueBandLabel: valueBandLabel ?? this.valueBandLabel,
      valueBandFloorMinor: valueBandFloorMinor ?? this.valueBandFloorMinor,
      valueBandCeilingMinor:
          valueBandCeilingMinor ?? this.valueBandCeilingMinor,
      supplySubtypeId: supplySubtypeId ?? this.supplySubtypeId,
      supplySubtypeLabel: supplySubtypeLabel ?? this.supplySubtypeLabel,
      premisesStatusCode: premisesStatusCode ?? this.premisesStatusCode,
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
    if (revenueEntryId.present) {
      map['revenue_entry_id'] = Variable<String>(revenueEntryId.value);
    }
    if (enteredAmountMinor.present) {
      map['entered_amount_minor'] = Variable<int>(enteredAmountMinor.value);
    }
    if (enteredBasis.present) {
      map['entered_basis'] = Variable<String>(enteredBasis.value);
    }
    if (grossAmountMinor.present) {
      map['gross_amount_minor'] = Variable<int>(grossAmountMinor.value);
    }
    if (taxAmountMinor.present) {
      map['tax_amount_minor'] = Variable<int>(taxAmountMinor.value);
    }
    if (netAmountMinor.present) {
      map['net_amount_minor'] = Variable<int>(netAmountMinor.value);
    }
    if (taxRuleId.present) {
      map['tax_rule_id'] = Variable<String>(taxRuleId.value);
    }
    if (taxRateBasisPoints.present) {
      map['tax_rate_basis_points'] = Variable<int>(taxRateBasisPoints.value);
    }
    if (taxTreatment.present) {
      map['tax_treatment'] = Variable<String>(taxTreatment.value);
    }
    if (valueBandId.present) {
      map['value_band_id'] = Variable<String>(valueBandId.value);
    }
    if (valueBandLabel.present) {
      map['value_band_label'] = Variable<String>(valueBandLabel.value);
    }
    if (valueBandFloorMinor.present) {
      map['value_band_floor_minor'] = Variable<int>(valueBandFloorMinor.value);
    }
    if (valueBandCeilingMinor.present) {
      map['value_band_ceiling_minor'] = Variable<int>(
        valueBandCeilingMinor.value,
      );
    }
    if (supplySubtypeId.present) {
      map['supply_subtype_id'] = Variable<String>(supplySubtypeId.value);
    }
    if (supplySubtypeLabel.present) {
      map['supply_subtype_label'] = Variable<String>(supplySubtypeLabel.value);
    }
    if (premisesStatusCode.present) {
      map['premises_status_code'] = Variable<String>(premisesStatusCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueComponentsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueEntryId: $revenueEntryId, ')
          ..write('enteredAmountMinor: $enteredAmountMinor, ')
          ..write('enteredBasis: $enteredBasis, ')
          ..write('grossAmountMinor: $grossAmountMinor, ')
          ..write('taxAmountMinor: $taxAmountMinor, ')
          ..write('netAmountMinor: $netAmountMinor, ')
          ..write('taxRuleId: $taxRuleId, ')
          ..write('taxRateBasisPoints: $taxRateBasisPoints, ')
          ..write('taxTreatment: $taxTreatment, ')
          ..write('valueBandId: $valueBandId, ')
          ..write('valueBandLabel: $valueBandLabel, ')
          ..write('valueBandFloorMinor: $valueBandFloorMinor, ')
          ..write('valueBandCeilingMinor: $valueBandCeilingMinor, ')
          ..write('supplySubtypeId: $supplySubtypeId, ')
          ..write('supplySubtypeLabel: $supplySubtypeLabel, ')
          ..write('premisesStatusCode: $premisesStatusCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueValueBandsTable extends RevenueValueBands
    with TableInfo<$RevenueValueBandsTable, RevenueValueBandRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueValueBandsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _floorMinorMeta = const VerificationMeta(
    'floorMinor',
  );
  @override
  late final GeneratedColumn<int> floorMinor = GeneratedColumn<int>(
    'floor_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ceilingMinorMeta = const VerificationMeta(
    'ceilingMinor',
  );
  @override
  late final GeneratedColumn<int> ceilingMinor = GeneratedColumn<int>(
    'ceiling_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supersededByBandIdMeta =
      const VerificationMeta('supersededByBandId');
  @override
  late final GeneratedColumn<String> supersededByBandId =
      GeneratedColumn<String>(
        'superseded_by_band_id',
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
    code,
    label,
    floorMinor,
    ceilingMinor,
    supersededByBandId,
    archivedAt,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_value_bands';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueValueBandRow> instance, {
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
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('floor_minor')) {
      context.handle(
        _floorMinorMeta,
        floorMinor.isAcceptableOrUnknown(data['floor_minor']!, _floorMinorMeta),
      );
    }
    if (data.containsKey('ceiling_minor')) {
      context.handle(
        _ceilingMinorMeta,
        ceilingMinor.isAcceptableOrUnknown(
          data['ceiling_minor']!,
          _ceilingMinorMeta,
        ),
      );
    }
    if (data.containsKey('superseded_by_band_id')) {
      context.handle(
        _supersededByBandIdMeta,
        supersededByBandId.isAcceptableOrUnknown(
          data['superseded_by_band_id']!,
          _supersededByBandIdMeta,
        ),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevenueValueBandRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueValueBandRow(
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
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      floorMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor_minor'],
      ),
      ceilingMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ceiling_minor'],
      ),
      supersededByBandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}superseded_by_band_id'],
      ),
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
    );
  }

  @override
  $RevenueValueBandsTable createAlias(String alias) {
    return $RevenueValueBandsTable(attachedDatabase, alias);
  }
}

class RevenueValueBandRow extends DataClass
    implements Insertable<RevenueValueBandRow> {
  final String id;
  final String orgId;
  final String revenueCategoryId;

  /// Immutable, like every master code (D-035).
  final String code;

  /// Editable, for a rename that preserves meaning — the D-038 distinction, unchanged.
  final String label;

  /// The tariff boundaries this band describes, per unit per day.
  ///
  /// **Write-once** (D-100). Editing a boundary in place would retroactively redefine
  /// what every effective-dated rule referencing this band applied to — including for
  /// dates already recorded — with nothing saying it had changed. A boundary change is a
  /// *different band*: create a new one and point [supersededByBandId] at it.
  ///
  /// Displayed and snapshotted; **never compared against a revenue amount** (D-094).
  final int? floorMinor;
  final int? ceilingMinor;

  /// The band that replaced this one, when its boundaries changed.
  ///
  /// Makes the lineage explicit, so a later reader can tell "this band replaced that one"
  /// from "an unrelated band appeared". Soft pointer, like every other cache reference.
  final String? supersededByBandId;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  const RevenueValueBandRow({
    required this.id,
    required this.orgId,
    required this.revenueCategoryId,
    required this.code,
    required this.label,
    this.floorMinor,
    this.ceilingMinor,
    this.supersededByBandId,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['revenue_category_id'] = Variable<String>(revenueCategoryId);
    map['code'] = Variable<String>(code);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || floorMinor != null) {
      map['floor_minor'] = Variable<int>(floorMinor);
    }
    if (!nullToAbsent || ceilingMinor != null) {
      map['ceiling_minor'] = Variable<int>(ceilingMinor);
    }
    if (!nullToAbsent || supersededByBandId != null) {
      map['superseded_by_band_id'] = Variable<String>(supersededByBandId);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RevenueValueBandsCompanion toCompanion(bool nullToAbsent) {
    return RevenueValueBandsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      revenueCategoryId: Value(revenueCategoryId),
      code: Value(code),
      label: Value(label),
      floorMinor: floorMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(floorMinor),
      ceilingMinor: ceilingMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(ceilingMinor),
      supersededByBandId: supersededByBandId == null && nullToAbsent
          ? const Value.absent()
          : Value(supersededByBandId),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory RevenueValueBandRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueValueBandRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      revenueCategoryId: serializer.fromJson<String>(json['revenueCategoryId']),
      code: serializer.fromJson<String>(json['code']),
      label: serializer.fromJson<String>(json['label']),
      floorMinor: serializer.fromJson<int?>(json['floorMinor']),
      ceilingMinor: serializer.fromJson<int?>(json['ceilingMinor']),
      supersededByBandId: serializer.fromJson<String?>(
        json['supersededByBandId'],
      ),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
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
      'code': serializer.toJson<String>(code),
      'label': serializer.toJson<String>(label),
      'floorMinor': serializer.toJson<int?>(floorMinor),
      'ceilingMinor': serializer.toJson<int?>(ceilingMinor),
      'supersededByBandId': serializer.toJson<String?>(supersededByBandId),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RevenueValueBandRow copyWith({
    String? id,
    String? orgId,
    String? revenueCategoryId,
    String? code,
    String? label,
    Value<int?> floorMinor = const Value.absent(),
    Value<int?> ceilingMinor = const Value.absent(),
    Value<String?> supersededByBandId = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
  }) => RevenueValueBandRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
    code: code ?? this.code,
    label: label ?? this.label,
    floorMinor: floorMinor.present ? floorMinor.value : this.floorMinor,
    ceilingMinor: ceilingMinor.present ? ceilingMinor.value : this.ceilingMinor,
    supersededByBandId: supersededByBandId.present
        ? supersededByBandId.value
        : this.supersededByBandId,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RevenueValueBandRow copyWithCompanion(RevenueValueBandsCompanion data) {
    return RevenueValueBandRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      revenueCategoryId: data.revenueCategoryId.present
          ? data.revenueCategoryId.value
          : this.revenueCategoryId,
      code: data.code.present ? data.code.value : this.code,
      label: data.label.present ? data.label.value : this.label,
      floorMinor: data.floorMinor.present
          ? data.floorMinor.value
          : this.floorMinor,
      ceilingMinor: data.ceilingMinor.present
          ? data.ceilingMinor.value
          : this.ceilingMinor,
      supersededByBandId: data.supersededByBandId.present
          ? data.supersededByBandId.value
          : this.supersededByBandId,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueValueBandRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('floorMinor: $floorMinor, ')
          ..write('ceilingMinor: $ceilingMinor, ')
          ..write('supersededByBandId: $supersededByBandId, ')
          ..write('archivedAt: $archivedAt, ')
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
    code,
    label,
    floorMinor,
    ceilingMinor,
    supersededByBandId,
    archivedAt,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueValueBandRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.revenueCategoryId == this.revenueCategoryId &&
          other.code == this.code &&
          other.label == this.label &&
          other.floorMinor == this.floorMinor &&
          other.ceilingMinor == this.ceilingMinor &&
          other.supersededByBandId == this.supersededByBandId &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class RevenueValueBandsCompanion extends UpdateCompanion<RevenueValueBandRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> revenueCategoryId;
  final Value<String> code;
  final Value<String> label;
  final Value<int?> floorMinor;
  final Value<int?> ceilingMinor;
  final Value<String?> supersededByBandId;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RevenueValueBandsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.revenueCategoryId = const Value.absent(),
    this.code = const Value.absent(),
    this.label = const Value.absent(),
    this.floorMinor = const Value.absent(),
    this.ceilingMinor = const Value.absent(),
    this.supersededByBandId = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueValueBandsCompanion.insert({
    required String id,
    required String orgId,
    required String revenueCategoryId,
    required String code,
    required String label,
    this.floorMinor = const Value.absent(),
    this.ceilingMinor = const Value.absent(),
    this.supersededByBandId = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       revenueCategoryId = Value(revenueCategoryId),
       code = Value(code),
       label = Value(label),
       updatedAt = Value(updatedAt);
  static Insertable<RevenueValueBandRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? revenueCategoryId,
    Expression<String>? code,
    Expression<String>? label,
    Expression<int>? floorMinor,
    Expression<int>? ceilingMinor,
    Expression<String>? supersededByBandId,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (revenueCategoryId != null) 'revenue_category_id': revenueCategoryId,
      if (code != null) 'code': code,
      if (label != null) 'label': label,
      if (floorMinor != null) 'floor_minor': floorMinor,
      if (ceilingMinor != null) 'ceiling_minor': ceilingMinor,
      if (supersededByBandId != null)
        'superseded_by_band_id': supersededByBandId,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueValueBandsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? revenueCategoryId,
    Value<String>? code,
    Value<String>? label,
    Value<int?>? floorMinor,
    Value<int?>? ceilingMinor,
    Value<String?>? supersededByBandId,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RevenueValueBandsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
      code: code ?? this.code,
      label: label ?? this.label,
      floorMinor: floorMinor ?? this.floorMinor,
      ceilingMinor: ceilingMinor ?? this.ceilingMinor,
      supersededByBandId: supersededByBandId ?? this.supersededByBandId,
      archivedAt: archivedAt ?? this.archivedAt,
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
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (floorMinor.present) {
      map['floor_minor'] = Variable<int>(floorMinor.value);
    }
    if (ceilingMinor.present) {
      map['ceiling_minor'] = Variable<int>(ceilingMinor.value);
    }
    if (supersededByBandId.present) {
      map['superseded_by_band_id'] = Variable<String>(supersededByBandId.value);
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueValueBandsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('floorMinor: $floorMinor, ')
          ..write('ceilingMinor: $ceilingMinor, ')
          ..write('supersededByBandId: $supersededByBandId, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueSupplySubtypesTable extends RevenueSupplySubtypes
    with TableInfo<$RevenueSupplySubtypesTable, RevenueSupplySubtypeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueSupplySubtypesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    revenueCategoryId,
    code,
    label,
    archivedAt,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_supply_subtypes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueSupplySubtypeRow> instance, {
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
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RevenueSupplySubtypeRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueSupplySubtypeRow(
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
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
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
    );
  }

  @override
  $RevenueSupplySubtypesTable createAlias(String alias) {
    return $RevenueSupplySubtypesTable(attachedDatabase, alias);
  }
}

class RevenueSupplySubtypeRow extends DataClass
    implements Insertable<RevenueSupplySubtypeRow> {
  final String id;
  final String orgId;
  final String revenueCategoryId;
  final String code;
  final String label;
  final DateTime? archivedAt;
  final int rowVersion;
  final DateTime updatedAt;
  const RevenueSupplySubtypeRow({
    required this.id,
    required this.orgId,
    required this.revenueCategoryId,
    required this.code,
    required this.label,
    this.archivedAt,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['revenue_category_id'] = Variable<String>(revenueCategoryId);
    map['code'] = Variable<String>(code);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RevenueSupplySubtypesCompanion toCompanion(bool nullToAbsent) {
    return RevenueSupplySubtypesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      revenueCategoryId: Value(revenueCategoryId),
      code: Value(code),
      label: Value(label),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory RevenueSupplySubtypeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueSupplySubtypeRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      revenueCategoryId: serializer.fromJson<String>(json['revenueCategoryId']),
      code: serializer.fromJson<String>(json['code']),
      label: serializer.fromJson<String>(json['label']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
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
      'code': serializer.toJson<String>(code),
      'label': serializer.toJson<String>(label),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RevenueSupplySubtypeRow copyWith({
    String? id,
    String? orgId,
    String? revenueCategoryId,
    String? code,
    String? label,
    Value<DateTime?> archivedAt = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
  }) => RevenueSupplySubtypeRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
    code: code ?? this.code,
    label: label ?? this.label,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RevenueSupplySubtypeRow copyWithCompanion(
    RevenueSupplySubtypesCompanion data,
  ) {
    return RevenueSupplySubtypeRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      revenueCategoryId: data.revenueCategoryId.present
          ? data.revenueCategoryId.value
          : this.revenueCategoryId,
      code: data.code.present ? data.code.value : this.code,
      label: data.label.present ? data.label.value : this.label,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueSupplySubtypeRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('archivedAt: $archivedAt, ')
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
    code,
    label,
    archivedAt,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueSupplySubtypeRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.revenueCategoryId == this.revenueCategoryId &&
          other.code == this.code &&
          other.label == this.label &&
          other.archivedAt == this.archivedAt &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class RevenueSupplySubtypesCompanion
    extends UpdateCompanion<RevenueSupplySubtypeRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> revenueCategoryId;
  final Value<String> code;
  final Value<String> label;
  final Value<DateTime?> archivedAt;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RevenueSupplySubtypesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.revenueCategoryId = const Value.absent(),
    this.code = const Value.absent(),
    this.label = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueSupplySubtypesCompanion.insert({
    required String id,
    required String orgId,
    required String revenueCategoryId,
    required String code,
    required String label,
    this.archivedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       revenueCategoryId = Value(revenueCategoryId),
       code = Value(code),
       label = Value(label),
       updatedAt = Value(updatedAt);
  static Insertable<RevenueSupplySubtypeRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? revenueCategoryId,
    Expression<String>? code,
    Expression<String>? label,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (revenueCategoryId != null) 'revenue_category_id': revenueCategoryId,
      if (code != null) 'code': code,
      if (label != null) 'label': label,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueSupplySubtypesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? revenueCategoryId,
    Value<String>? code,
    Value<String>? label,
    Value<DateTime?>? archivedAt,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RevenueSupplySubtypesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
      code: code ?? this.code,
      label: label ?? this.label,
      archivedAt: archivedAt ?? this.archivedAt,
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
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevenueSupplySubtypesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('revenueCategoryId: $revenueCategoryId, ')
          ..write('code: $code, ')
          ..write('label: $label, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BusinessUnitTaxStatusesTable extends BusinessUnitTaxStatuses
    with TableInfo<$BusinessUnitTaxStatusesTable, BusinessUnitTaxStatusRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BusinessUnitTaxStatusesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _statusCodeMeta = const VerificationMeta(
    'statusCode',
  );
  @override
  late final GeneratedColumn<String> statusCode = GeneratedColumn<String>(
    'status_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    businessUnitId,
    effectiveFrom,
    effectiveTo,
    archivedAt,
    statusCode,
    note,
    rowVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'business_unit_tax_statuses';
  @override
  VerificationContext validateIntegrity(
    Insertable<BusinessUnitTaxStatusRow> instance, {
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
    } else if (isInserting) {
      context.missing(_businessUnitIdMeta);
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
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('status_code')) {
      context.handle(
        _statusCodeMeta,
        statusCode.isAcceptableOrUnknown(data['status_code']!, _statusCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_statusCodeMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BusinessUnitTaxStatusRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BusinessUnitTaxStatusRow(
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
      )!,
      effectiveFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_from'],
      )!,
      effectiveTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_to'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      statusCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_code'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
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
  $BusinessUnitTaxStatusesTable createAlias(String alias) {
    return $BusinessUnitTaxStatusesTable(attachedDatabase, alias);
  }
}

class BusinessUnitTaxStatusRow extends DataClass
    implements Insertable<BusinessUnitTaxStatusRow> {
  final String id;
  final String orgId;

  /// Soft pointer: this row outlives a purged unit exactly as expense history does.
  final String businessUnitId;

  /// `YYYY-MM-DD`, inclusive lower bound.
  final String effectiveFrom;

  /// `YYYY-MM-DD`, **exclusive** upper bound. Null means still in force.
  ///
  /// Added by the A2 audit. Without it the cache could hold two open-ended statuses for
  /// one unit and the offline resolver would have to pick "the latest start" — a ranking,
  /// which is exactly what D-094 forbids for a tax fact. The server enforces
  /// non-overlap with an exclusion constraint; this column is what lets the cache
  /// represent that timeline faithfully rather than approximate it.
  final String? effectiveTo;
  final DateTime? archivedAt;
  final String statusCode;
  final String? note;
  final int rowVersion;
  final DateTime updatedAt;
  const BusinessUnitTaxStatusRow({
    required this.id,
    required this.orgId,
    required this.businessUnitId,
    required this.effectiveFrom,
    this.effectiveTo,
    this.archivedAt,
    required this.statusCode,
    this.note,
    required this.rowVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    map['effective_from'] = Variable<String>(effectiveFrom);
    if (!nullToAbsent || effectiveTo != null) {
      map['effective_to'] = Variable<String>(effectiveTo);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['status_code'] = Variable<String>(statusCode);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BusinessUnitTaxStatusesCompanion toCompanion(bool nullToAbsent) {
    return BusinessUnitTaxStatusesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      businessUnitId: Value(businessUnitId),
      effectiveFrom: Value(effectiveFrom),
      effectiveTo: effectiveTo == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveTo),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      statusCode: Value(statusCode),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      rowVersion: Value(rowVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory BusinessUnitTaxStatusRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BusinessUnitTaxStatusRow(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
      effectiveFrom: serializer.fromJson<String>(json['effectiveFrom']),
      effectiveTo: serializer.fromJson<String?>(json['effectiveTo']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      statusCode: serializer.fromJson<String>(json['statusCode']),
      note: serializer.fromJson<String?>(json['note']),
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
      'businessUnitId': serializer.toJson<String>(businessUnitId),
      'effectiveFrom': serializer.toJson<String>(effectiveFrom),
      'effectiveTo': serializer.toJson<String?>(effectiveTo),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'statusCode': serializer.toJson<String>(statusCode),
      'note': serializer.toJson<String?>(note),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BusinessUnitTaxStatusRow copyWith({
    String? id,
    String? orgId,
    String? businessUnitId,
    String? effectiveFrom,
    Value<String?> effectiveTo = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
    String? statusCode,
    Value<String?> note = const Value.absent(),
    int? rowVersion,
    DateTime? updatedAt,
  }) => BusinessUnitTaxStatusRow(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    effectiveTo: effectiveTo.present ? effectiveTo.value : this.effectiveTo,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    statusCode: statusCode ?? this.statusCode,
    note: note.present ? note.value : this.note,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BusinessUnitTaxStatusRow copyWithCompanion(
    BusinessUnitTaxStatusesCompanion data,
  ) {
    return BusinessUnitTaxStatusRow(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      effectiveTo: data.effectiveTo.present
          ? data.effectiveTo.value
          : this.effectiveTo,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      statusCode: data.statusCode.present
          ? data.statusCode.value
          : this.statusCode,
      note: data.note.present ? data.note.value : this.note,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BusinessUnitTaxStatusRow(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('statusCode: $statusCode, ')
          ..write('note: $note, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    businessUnitId,
    effectiveFrom,
    effectiveTo,
    archivedAt,
    statusCode,
    note,
    rowVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BusinessUnitTaxStatusRow &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.businessUnitId == this.businessUnitId &&
          other.effectiveFrom == this.effectiveFrom &&
          other.effectiveTo == this.effectiveTo &&
          other.archivedAt == this.archivedAt &&
          other.statusCode == this.statusCode &&
          other.note == this.note &&
          other.rowVersion == this.rowVersion &&
          other.updatedAt == this.updatedAt);
}

class BusinessUnitTaxStatusesCompanion
    extends UpdateCompanion<BusinessUnitTaxStatusRow> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> businessUnitId;
  final Value<String> effectiveFrom;
  final Value<String?> effectiveTo;
  final Value<DateTime?> archivedAt;
  final Value<String> statusCode;
  final Value<String?> note;
  final Value<int> rowVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BusinessUnitTaxStatusesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.statusCode = const Value.absent(),
    this.note = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BusinessUnitTaxStatusesCompanion.insert({
    required String id,
    required String orgId,
    required String businessUnitId,
    required String effectiveFrom,
    this.effectiveTo = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required String statusCode,
    this.note = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       businessUnitId = Value(businessUnitId),
       effectiveFrom = Value(effectiveFrom),
       statusCode = Value(statusCode),
       updatedAt = Value(updatedAt);
  static Insertable<BusinessUnitTaxStatusRow> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? businessUnitId,
    Expression<String>? effectiveFrom,
    Expression<String>? effectiveTo,
    Expression<DateTime>? archivedAt,
    Expression<String>? statusCode,
    Expression<String>? note,
    Expression<int>? rowVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (effectiveTo != null) 'effective_to': effectiveTo,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (statusCode != null) 'status_code': statusCode,
      if (note != null) 'note': note,
      if (rowVersion != null) 'row_version': rowVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BusinessUnitTaxStatusesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? businessUnitId,
    Value<String>? effectiveFrom,
    Value<String?>? effectiveTo,
    Value<DateTime?>? archivedAt,
    Value<String>? statusCode,
    Value<String?>? note,
    Value<int>? rowVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BusinessUnitTaxStatusesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: effectiveTo ?? this.effectiveTo,
      archivedAt: archivedAt ?? this.archivedAt,
      statusCode: statusCode ?? this.statusCode,
      note: note ?? this.note,
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
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<String>(effectiveFrom.value);
    }
    if (effectiveTo.present) {
      map['effective_to'] = Variable<String>(effectiveTo.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (statusCode.present) {
      map['status_code'] = Variable<String>(statusCode.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
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
    return (StringBuffer('BusinessUnitTaxStatusesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('statusCode: $statusCode, ')
          ..write('note: $note, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevenueConfigSnapshotsTable extends RevenueConfigSnapshots
    with TableInfo<$RevenueConfigSnapshotsTable, RevenueConfigSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevenueConfigSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
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
    false,
    type: DriftSqlType.string,
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
  static const VerificationMeta _datasetsMeta = const VerificationMeta(
    'datasets',
  );
  @override
  late final GeneratedColumn<String> datasets = GeneratedColumn<String>(
    'datasets',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<String> generation = GeneratedColumn<String>(
    'generation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<DateTime> confirmedAt = GeneratedColumn<DateTime>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
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
    userId,
    orgId,
    businessUnitId,
    status,
    datasets,
    generation,
    confirmedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revenue_config_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevenueConfigSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
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
    } else if (isInserting) {
      context.missing(_businessUnitIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('datasets')) {
      context.handle(
        _datasetsMeta,
        datasets.isAcceptableOrUnknown(data['datasets']!, _datasetsMeta),
      );
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
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
  Set<GeneratedColumn> get $primaryKey => {userId, businessUnitId};
  @override
  RevenueConfigSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevenueConfigSnapshot(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      businessUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_unit_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      datasets: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}datasets'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation'],
      ),
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}confirmed_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RevenueConfigSnapshotsTable createAlias(String alias) {
    return $RevenueConfigSnapshotsTable(attachedDatabase, alias);
  }
}

class RevenueConfigSnapshot extends DataClass
    implements Insertable<RevenueConfigSnapshot> {
  /// Whose sync this was. A snapshot vouches for nobody else (D-051 §9).
  final String userId;
  final String orgId;

  /// Soft pointer, like every other scoped cache row: the unit may be purged from
  /// underneath it, and this row is precisely what has to survive that to say so.
  final String businessUnitId;

  /// `complete` or `revoked`.
  ///
  /// A revocation **downgrades** rather than deletes, so the device can still tell the
  /// two silences apart: no row at all means this scope was never synchronised here,
  /// while `revoked` means it was and the authority was withdrawn. Both refuse new
  /// offline revenue; only one of them is a statement about this user's access (D-106).
  final String status;

  /// The dataset codes proven present, comma-separated and sorted.
  ///
  /// Stored as data rather than implied by row counts, because zero subtypes is a
  /// legitimate synchronised answer and is not the same fact as never having asked.
  final String datasets;

  /// The server generation this snapshot came from — the greatest `change_seq` observed
  /// across the datasets, so two runs cannot be silently interleaved into one claim.
  final String? generation;

  /// **Server** time, taken from the confirmed authority. Never the device clock, which
  /// is forensic metadata only (spec §9).
  final DateTime? confirmedAt;

  /// Device clock, kept for diagnostics and never used to decide anything.
  final DateTime updatedAt;
  const RevenueConfigSnapshot({
    required this.userId,
    required this.orgId,
    required this.businessUnitId,
    required this.status,
    required this.datasets,
    this.generation,
    this.confirmedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['org_id'] = Variable<String>(orgId);
    map['business_unit_id'] = Variable<String>(businessUnitId);
    map['status'] = Variable<String>(status);
    map['datasets'] = Variable<String>(datasets);
    if (!nullToAbsent || generation != null) {
      map['generation'] = Variable<String>(generation);
    }
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RevenueConfigSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return RevenueConfigSnapshotsCompanion(
      userId: Value(userId),
      orgId: Value(orgId),
      businessUnitId: Value(businessUnitId),
      status: Value(status),
      datasets: Value(datasets),
      generation: generation == null && nullToAbsent
          ? const Value.absent()
          : Value(generation),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RevenueConfigSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevenueConfigSnapshot(
      userId: serializer.fromJson<String>(json['userId']),
      orgId: serializer.fromJson<String>(json['orgId']),
      businessUnitId: serializer.fromJson<String>(json['businessUnitId']),
      status: serializer.fromJson<String>(json['status']),
      datasets: serializer.fromJson<String>(json['datasets']),
      generation: serializer.fromJson<String?>(json['generation']),
      confirmedAt: serializer.fromJson<DateTime?>(json['confirmedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'orgId': serializer.toJson<String>(orgId),
      'businessUnitId': serializer.toJson<String>(businessUnitId),
      'status': serializer.toJson<String>(status),
      'datasets': serializer.toJson<String>(datasets),
      'generation': serializer.toJson<String?>(generation),
      'confirmedAt': serializer.toJson<DateTime?>(confirmedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RevenueConfigSnapshot copyWith({
    String? userId,
    String? orgId,
    String? businessUnitId,
    String? status,
    String? datasets,
    Value<String?> generation = const Value.absent(),
    Value<DateTime?> confirmedAt = const Value.absent(),
    DateTime? updatedAt,
  }) => RevenueConfigSnapshot(
    userId: userId ?? this.userId,
    orgId: orgId ?? this.orgId,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    status: status ?? this.status,
    datasets: datasets ?? this.datasets,
    generation: generation.present ? generation.value : this.generation,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RevenueConfigSnapshot copyWithCompanion(
    RevenueConfigSnapshotsCompanion data,
  ) {
    return RevenueConfigSnapshot(
      userId: data.userId.present ? data.userId.value : this.userId,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      businessUnitId: data.businessUnitId.present
          ? data.businessUnitId.value
          : this.businessUnitId,
      status: data.status.present ? data.status.value : this.status,
      datasets: data.datasets.present ? data.datasets.value : this.datasets,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevenueConfigSnapshot(')
          ..write('userId: $userId, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('status: $status, ')
          ..write('datasets: $datasets, ')
          ..write('generation: $generation, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    orgId,
    businessUnitId,
    status,
    datasets,
    generation,
    confirmedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevenueConfigSnapshot &&
          other.userId == this.userId &&
          other.orgId == this.orgId &&
          other.businessUnitId == this.businessUnitId &&
          other.status == this.status &&
          other.datasets == this.datasets &&
          other.generation == this.generation &&
          other.confirmedAt == this.confirmedAt &&
          other.updatedAt == this.updatedAt);
}

class RevenueConfigSnapshotsCompanion
    extends UpdateCompanion<RevenueConfigSnapshot> {
  final Value<String> userId;
  final Value<String> orgId;
  final Value<String> businessUnitId;
  final Value<String> status;
  final Value<String> datasets;
  final Value<String?> generation;
  final Value<DateTime?> confirmedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RevenueConfigSnapshotsCompanion({
    this.userId = const Value.absent(),
    this.orgId = const Value.absent(),
    this.businessUnitId = const Value.absent(),
    this.status = const Value.absent(),
    this.datasets = const Value.absent(),
    this.generation = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevenueConfigSnapshotsCompanion.insert({
    required String userId,
    required String orgId,
    required String businessUnitId,
    required String status,
    this.datasets = const Value.absent(),
    this.generation = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       orgId = Value(orgId),
       businessUnitId = Value(businessUnitId),
       status = Value(status),
       updatedAt = Value(updatedAt);
  static Insertable<RevenueConfigSnapshot> custom({
    Expression<String>? userId,
    Expression<String>? orgId,
    Expression<String>? businessUnitId,
    Expression<String>? status,
    Expression<String>? datasets,
    Expression<String>? generation,
    Expression<DateTime>? confirmedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (orgId != null) 'org_id': orgId,
      if (businessUnitId != null) 'business_unit_id': businessUnitId,
      if (status != null) 'status': status,
      if (datasets != null) 'datasets': datasets,
      if (generation != null) 'generation': generation,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevenueConfigSnapshotsCompanion copyWith({
    Value<String>? userId,
    Value<String>? orgId,
    Value<String>? businessUnitId,
    Value<String>? status,
    Value<String>? datasets,
    Value<String?>? generation,
    Value<DateTime?>? confirmedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RevenueConfigSnapshotsCompanion(
      userId: userId ?? this.userId,
      orgId: orgId ?? this.orgId,
      businessUnitId: businessUnitId ?? this.businessUnitId,
      status: status ?? this.status,
      datasets: datasets ?? this.datasets,
      generation: generation ?? this.generation,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (businessUnitId.present) {
      map['business_unit_id'] = Variable<String>(businessUnitId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (datasets.present) {
      map['datasets'] = Variable<String>(datasets.value);
    }
    if (generation.present) {
      map['generation'] = Variable<String>(generation.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt.value);
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
    return (StringBuffer('RevenueConfigSnapshotsCompanion(')
          ..write('userId: $userId, ')
          ..write('orgId: $orgId, ')
          ..write('businessUnitId: $businessUnitId, ')
          ..write('status: $status, ')
          ..write('datasets: $datasets, ')
          ..write('generation: $generation, ')
          ..write('confirmedAt: $confirmedAt, ')
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
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $ExpenseAllocationsTable expenseAllocations =
      $ExpenseAllocationsTable(this);
  late final $ExpensePeriodAllocationsTable expensePeriodAllocations =
      $ExpensePeriodAllocationsTable(this);
  late final $ExpenseAttachmentsTable expenseAttachments =
      $ExpenseAttachmentsTable(this);
  late final $RevenueEntriesTable revenueEntries = $RevenueEntriesTable(this);
  late final $RevenueComponentsTable revenueComponents =
      $RevenueComponentsTable(this);
  late final $RevenueValueBandsTable revenueValueBands =
      $RevenueValueBandsTable(this);
  late final $RevenueSupplySubtypesTable revenueSupplySubtypes =
      $RevenueSupplySubtypesTable(this);
  late final $BusinessUnitTaxStatusesTable businessUnitTaxStatuses =
      $BusinessUnitTaxStatusesTable(this);
  late final $RevenueConfigSnapshotsTable revenueConfigSnapshots =
      $RevenueConfigSnapshotsTable(this);
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
    expenses,
    expenseAllocations,
    expensePeriodAllocations,
    expenseAttachments,
    revenueEntries,
    revenueComponents,
    revenueValueBands,
    revenueSupplySubtypes,
    businessUnitTaxStatuses,
    revenueConfigSnapshots,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'expenses',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('expense_allocations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'expenses',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('expense_period_allocations', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'expense_allocations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('expense_period_allocations', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'expenses',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('expense_attachments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'revenue_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('revenue_components', kind: UpdateKind.delete)],
    ),
  ]);
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

  static MultiTypedResultKey<$RevenueValueBandsTable, List<RevenueValueBandRow>>
  _revenueValueBandsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.revenueValueBands,
        aliasName:
            'revenue_categories__id__revenue_value_bands__revenue_category_id',
      );

  $$RevenueValueBandsTableProcessedTableManager get revenueValueBandsRefs {
    final manager =
        $$RevenueValueBandsTableTableManager(
          $_db,
          $_db.revenueValueBands,
        ).filter(
          (f) => f.revenueCategoryId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _revenueValueBandsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $RevenueSupplySubtypesTable,
    List<RevenueSupplySubtypeRow>
  >
  _revenueSupplySubtypesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.revenueSupplySubtypes,
    aliasName:
        'revenue_categories__id__revenue_supply_subtypes__revenue_category_id',
  );

  $$RevenueSupplySubtypesTableProcessedTableManager
  get revenueSupplySubtypesRefs {
    final manager =
        $$RevenueSupplySubtypesTableTableManager(
          $_db,
          $_db.revenueSupplySubtypes,
        ).filter(
          (f) => f.revenueCategoryId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _revenueSupplySubtypesRefsTable($_db),
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

  Expression<bool> revenueValueBandsRefs(
    Expression<bool> Function($$RevenueValueBandsTableFilterComposer f) f,
  ) {
    final $$RevenueValueBandsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revenueValueBands,
      getReferencedColumn: (t) => t.revenueCategoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueValueBandsTableFilterComposer(
            $db: $db,
            $table: $db.revenueValueBands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> revenueSupplySubtypesRefs(
    Expression<bool> Function($$RevenueSupplySubtypesTableFilterComposer f) f,
  ) {
    final $$RevenueSupplySubtypesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revenueSupplySubtypes,
          getReferencedColumn: (t) => t.revenueCategoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueSupplySubtypesTableFilterComposer(
                $db: $db,
                $table: $db.revenueSupplySubtypes,
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

  Expression<T> revenueValueBandsRefs<T extends Object>(
    Expression<T> Function($$RevenueValueBandsTableAnnotationComposer a) f,
  ) {
    final $$RevenueValueBandsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revenueValueBands,
          getReferencedColumn: (t) => t.revenueCategoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueValueBandsTableAnnotationComposer(
                $db: $db,
                $table: $db.revenueValueBands,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> revenueSupplySubtypesRefs<T extends Object>(
    Expression<T> Function($$RevenueSupplySubtypesTableAnnotationComposer a) f,
  ) {
    final $$RevenueSupplySubtypesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revenueSupplySubtypes,
          getReferencedColumn: (t) => t.revenueCategoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueSupplySubtypesTableAnnotationComposer(
                $db: $db,
                $table: $db.revenueSupplySubtypes,
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
            bool revenueValueBandsRefs,
            bool revenueSupplySubtypesRefs,
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
              ({
                businessUnitId = false,
                revenueTaxRatesRefs = false,
                revenueValueBandsRefs = false,
                revenueSupplySubtypesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (revenueTaxRatesRefs) db.revenueTaxRates,
                    if (revenueValueBandsRefs) db.revenueValueBands,
                    if (revenueSupplySubtypesRefs) db.revenueSupplySubtypes,
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
                      if (revenueValueBandsRefs)
                        await $_getPrefetchedData<
                          RevenueCategoryRow,
                          $RevenueCategoriesTable,
                          RevenueValueBandRow
                        >(
                          currentTable: table,
                          referencedTable: $$RevenueCategoriesTableReferences
                              ._revenueValueBandsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RevenueCategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).revenueValueBandsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.revenueCategoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (revenueSupplySubtypesRefs)
                        await $_getPrefetchedData<
                          RevenueCategoryRow,
                          $RevenueCategoriesTable,
                          RevenueSupplySubtypeRow
                        >(
                          currentTable: table,
                          referencedTable: $$RevenueCategoriesTableReferences
                              ._revenueSupplySubtypesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RevenueCategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).revenueSupplySubtypesRefs,
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
      PrefetchHooks Function({
        bool businessUnitId,
        bool revenueTaxRatesRefs,
        bool revenueValueBandsRefs,
        bool revenueSupplySubtypesRefs,
      })
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
      Value<String?> inputBasis,
      Value<String?> valueBandId,
      Value<String?> supplySubtypeId,
      Value<String?> premisesStatusCode,
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
      Value<String?> inputBasis,
      Value<String?> valueBandId,
      Value<String?> supplySubtypeId,
      Value<String?> premisesStatusCode,
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

  ColumnFilters<String> get inputBasis => $composableBuilder(
    column: $table.inputBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
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

  ColumnOrderings<String> get inputBasis => $composableBuilder(
    column: $table.inputBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
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

  GeneratedColumn<String> get inputBasis => $composableBuilder(
    column: $table.inputBasis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
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
                Value<String?> inputBasis = const Value.absent(),
                Value<String?> valueBandId = const Value.absent(),
                Value<String?> supplySubtypeId = const Value.absent(),
                Value<String?> premisesStatusCode = const Value.absent(),
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
                inputBasis: inputBasis,
                valueBandId: valueBandId,
                supplySubtypeId: supplySubtypeId,
                premisesStatusCode: premisesStatusCode,
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
                Value<String?> inputBasis = const Value.absent(),
                Value<String?> valueBandId = const Value.absent(),
                Value<String?> supplySubtypeId = const Value.absent(),
                Value<String?> premisesStatusCode = const Value.absent(),
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
                inputBasis: inputBasis,
                valueBandId: valueBandId,
                supplySubtypeId: supplySubtypeId,
                premisesStatusCode: premisesStatusCode,
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
typedef $$ExpensesTableCreateCompanionBuilder =
    ExpensesCompanion Function({
      required String id,
      required String orgId,
      Value<String?> txnNumber,
      Value<int?> financialYear,
      required String businessDate,
      Value<String> businessDateSource,
      Value<String?> accountingPeriodStart,
      Value<String?> accountingPeriodEnd,
      Value<String> visibility,
      Value<int?> documentTotalMinor,
      required int visibleAmountMinor,
      Value<bool> isShared,
      Value<String?> vendorId,
      Value<String> paymentStatus,
      Value<String?> paymentDate,
      Value<String?> paymentMethodId,
      Value<String?> referenceNumber,
      Value<String?> notes,
      Value<int?> taxAmountMinor,
      required String createdBy,
      required DateTime capturedAt,
      Value<DateTime?> voidedAt,
      Value<String?> voidedBy,
      Value<String?> voidReason,
      Value<String?> pendingMutationId,
      Value<int> rowVersion,
      Value<DateTime?> serverUpdatedAt,
      required DateTime updatedAt,
      Value<DateTime?> scopeRevokedAt,
      Value<int> rowid,
    });
typedef $$ExpensesTableUpdateCompanionBuilder =
    ExpensesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String?> txnNumber,
      Value<int?> financialYear,
      Value<String> businessDate,
      Value<String> businessDateSource,
      Value<String?> accountingPeriodStart,
      Value<String?> accountingPeriodEnd,
      Value<String> visibility,
      Value<int?> documentTotalMinor,
      Value<int> visibleAmountMinor,
      Value<bool> isShared,
      Value<String?> vendorId,
      Value<String> paymentStatus,
      Value<String?> paymentDate,
      Value<String?> paymentMethodId,
      Value<String?> referenceNumber,
      Value<String?> notes,
      Value<int?> taxAmountMinor,
      Value<String> createdBy,
      Value<DateTime> capturedAt,
      Value<DateTime?> voidedAt,
      Value<String?> voidedBy,
      Value<String?> voidReason,
      Value<String?> pendingMutationId,
      Value<int> rowVersion,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> scopeRevokedAt,
      Value<int> rowid,
    });

final class $$ExpensesTableReferences
    extends BaseReferences<_$AppDatabase, $ExpensesTable, ExpenseRow> {
  $$ExpensesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $ExpenseAllocationsTable,
    List<ExpenseAllocationRow>
  >
  _expenseAllocationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.expenseAllocations,
        aliasName: 'expenses__id__expense_allocations__expense_id',
      );

  $$ExpenseAllocationsTableProcessedTableManager get expenseAllocationsRefs {
    final manager = $$ExpenseAllocationsTableTableManager(
      $_db,
      $_db.expenseAllocations,
    ).filter((f) => f.expenseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _expenseAllocationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ExpensePeriodAllocationsTable,
    List<ExpensePeriodAllocationRow>
  >
  _expensePeriodAllocationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.expensePeriodAllocations,
        aliasName: 'expenses__id__expense_period_allocations__expense_id',
      );

  $$ExpensePeriodAllocationsTableProcessedTableManager
  get expensePeriodAllocationsRefs {
    final manager = $$ExpensePeriodAllocationsTableTableManager(
      $_db,
      $_db.expensePeriodAllocations,
    ).filter((f) => f.expenseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _expensePeriodAllocationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ExpenseAttachmentsTable,
    List<ExpenseAttachmentRow>
  >
  _expenseAttachmentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.expenseAttachments,
        aliasName: 'expenses__id__expense_attachments__expense_id',
      );

  $$ExpenseAttachmentsTableProcessedTableManager get expenseAttachmentsRefs {
    final manager = $$ExpenseAttachmentsTableTableManager(
      $_db,
      $_db.expenseAttachments,
    ).filter((f) => f.expenseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _expenseAttachmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
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

  ColumnFilters<String> get txnNumber => $composableBuilder(
    column: $table.txnNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessDateSource => $composableBuilder(
    column: $table.businessDateSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get documentTotalMinor => $composableBuilder(
    column: $table.documentTotalMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get visibleAmountMinor => $composableBuilder(
    column: $table.visibleAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isShared => $composableBuilder(
    column: $table.isShared,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vendorId => $composableBuilder(
    column: $table.vendorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethodId => $composableBuilder(
    column: $table.paymentMethodId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voidedBy => $composableBuilder(
    column: $table.voidedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> expenseAllocationsRefs(
    Expression<bool> Function($$ExpenseAllocationsTableFilterComposer f) f,
  ) {
    final $$ExpenseAllocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenseAllocations,
      getReferencedColumn: (t) => t.expenseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpenseAllocationsTableFilterComposer(
            $db: $db,
            $table: $db.expenseAllocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensePeriodAllocationsRefs(
    Expression<bool> Function($$ExpensePeriodAllocationsTableFilterComposer f)
    f,
  ) {
    final $$ExpensePeriodAllocationsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expensePeriodAllocations,
          getReferencedColumn: (t) => t.expenseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpensePeriodAllocationsTableFilterComposer(
                $db: $db,
                $table: $db.expensePeriodAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> expenseAttachmentsRefs(
    Expression<bool> Function($$ExpenseAttachmentsTableFilterComposer f) f,
  ) {
    final $$ExpenseAttachmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenseAttachments,
      getReferencedColumn: (t) => t.expenseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpenseAttachmentsTableFilterComposer(
            $db: $db,
            $table: $db.expenseAttachments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
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

  ColumnOrderings<String> get txnNumber => $composableBuilder(
    column: $table.txnNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessDateSource => $composableBuilder(
    column: $table.businessDateSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get documentTotalMinor => $composableBuilder(
    column: $table.documentTotalMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get visibleAmountMinor => $composableBuilder(
    column: $table.visibleAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isShared => $composableBuilder(
    column: $table.isShared,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vendorId => $composableBuilder(
    column: $table.vendorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethodId => $composableBuilder(
    column: $table.paymentMethodId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voidedBy => $composableBuilder(
    column: $table.voidedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
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

  GeneratedColumn<String> get txnNumber =>
      $composableBuilder(column: $table.txnNumber, builder: (column) => column);

  GeneratedColumn<int> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessDateSource => $composableBuilder(
    column: $table.businessDateSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => column,
  );

  GeneratedColumn<String> get visibility => $composableBuilder(
    column: $table.visibility,
    builder: (column) => column,
  );

  GeneratedColumn<int> get documentTotalMinor => $composableBuilder(
    column: $table.documentTotalMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get visibleAmountMinor => $composableBuilder(
    column: $table.visibleAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isShared =>
      $composableBuilder(column: $table.isShared, builder: (column) => column);

  GeneratedColumn<String> get vendorId =>
      $composableBuilder(column: $table.vendorId, builder: (column) => column);

  GeneratedColumn<String> get paymentStatus => $composableBuilder(
    column: $table.paymentStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethodId => $composableBuilder(
    column: $table.paymentMethodId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get voidedAt =>
      $composableBuilder(column: $table.voidedAt, builder: (column) => column);

  GeneratedColumn<String> get voidedBy =>
      $composableBuilder(column: $table.voidedBy, builder: (column) => column);

  GeneratedColumn<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => column,
  );

  Expression<T> expenseAllocationsRefs<T extends Object>(
    Expression<T> Function($$ExpenseAllocationsTableAnnotationComposer a) f,
  ) {
    final $$ExpenseAllocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expenseAllocations,
          getReferencedColumn: (t) => t.expenseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpenseAllocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.expenseAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> expensePeriodAllocationsRefs<T extends Object>(
    Expression<T> Function($$ExpensePeriodAllocationsTableAnnotationComposer a)
    f,
  ) {
    final $$ExpensePeriodAllocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expensePeriodAllocations,
          getReferencedColumn: (t) => t.expenseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpensePeriodAllocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.expensePeriodAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> expenseAttachmentsRefs<T extends Object>(
    Expression<T> Function($$ExpenseAttachmentsTableAnnotationComposer a) f,
  ) {
    final $$ExpenseAttachmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expenseAttachments,
          getReferencedColumn: (t) => t.expenseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpenseAttachmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.expenseAttachments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ExpensesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpensesTable,
          ExpenseRow,
          $$ExpensesTableFilterComposer,
          $$ExpensesTableOrderingComposer,
          $$ExpensesTableAnnotationComposer,
          $$ExpensesTableCreateCompanionBuilder,
          $$ExpensesTableUpdateCompanionBuilder,
          (ExpenseRow, $$ExpensesTableReferences),
          ExpenseRow,
          PrefetchHooks Function({
            bool expenseAllocationsRefs,
            bool expensePeriodAllocationsRefs,
            bool expenseAttachmentsRefs,
          })
        > {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String?> txnNumber = const Value.absent(),
                Value<int?> financialYear = const Value.absent(),
                Value<String> businessDate = const Value.absent(),
                Value<String> businessDateSource = const Value.absent(),
                Value<String?> accountingPeriodStart = const Value.absent(),
                Value<String?> accountingPeriodEnd = const Value.absent(),
                Value<String> visibility = const Value.absent(),
                Value<int?> documentTotalMinor = const Value.absent(),
                Value<int> visibleAmountMinor = const Value.absent(),
                Value<bool> isShared = const Value.absent(),
                Value<String?> vendorId = const Value.absent(),
                Value<String> paymentStatus = const Value.absent(),
                Value<String?> paymentDate = const Value.absent(),
                Value<String?> paymentMethodId = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int?> taxAmountMinor = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<String?> voidedBy = const Value.absent(),
                Value<String?> voidReason = const Value.absent(),
                Value<String?> pendingMutationId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> scopeRevokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion(
                id: id,
                orgId: orgId,
                txnNumber: txnNumber,
                financialYear: financialYear,
                businessDate: businessDate,
                businessDateSource: businessDateSource,
                accountingPeriodStart: accountingPeriodStart,
                accountingPeriodEnd: accountingPeriodEnd,
                visibility: visibility,
                documentTotalMinor: documentTotalMinor,
                visibleAmountMinor: visibleAmountMinor,
                isShared: isShared,
                vendorId: vendorId,
                paymentStatus: paymentStatus,
                paymentDate: paymentDate,
                paymentMethodId: paymentMethodId,
                referenceNumber: referenceNumber,
                notes: notes,
                taxAmountMinor: taxAmountMinor,
                createdBy: createdBy,
                capturedAt: capturedAt,
                voidedAt: voidedAt,
                voidedBy: voidedBy,
                voidReason: voidReason,
                pendingMutationId: pendingMutationId,
                rowVersion: rowVersion,
                serverUpdatedAt: serverUpdatedAt,
                updatedAt: updatedAt,
                scopeRevokedAt: scopeRevokedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                Value<String?> txnNumber = const Value.absent(),
                Value<int?> financialYear = const Value.absent(),
                required String businessDate,
                Value<String> businessDateSource = const Value.absent(),
                Value<String?> accountingPeriodStart = const Value.absent(),
                Value<String?> accountingPeriodEnd = const Value.absent(),
                Value<String> visibility = const Value.absent(),
                Value<int?> documentTotalMinor = const Value.absent(),
                required int visibleAmountMinor,
                Value<bool> isShared = const Value.absent(),
                Value<String?> vendorId = const Value.absent(),
                Value<String> paymentStatus = const Value.absent(),
                Value<String?> paymentDate = const Value.absent(),
                Value<String?> paymentMethodId = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int?> taxAmountMinor = const Value.absent(),
                required String createdBy,
                required DateTime capturedAt,
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<String?> voidedBy = const Value.absent(),
                Value<String?> voidReason = const Value.absent(),
                Value<String?> pendingMutationId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> scopeRevokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion.insert(
                id: id,
                orgId: orgId,
                txnNumber: txnNumber,
                financialYear: financialYear,
                businessDate: businessDate,
                businessDateSource: businessDateSource,
                accountingPeriodStart: accountingPeriodStart,
                accountingPeriodEnd: accountingPeriodEnd,
                visibility: visibility,
                documentTotalMinor: documentTotalMinor,
                visibleAmountMinor: visibleAmountMinor,
                isShared: isShared,
                vendorId: vendorId,
                paymentStatus: paymentStatus,
                paymentDate: paymentDate,
                paymentMethodId: paymentMethodId,
                referenceNumber: referenceNumber,
                notes: notes,
                taxAmountMinor: taxAmountMinor,
                createdBy: createdBy,
                capturedAt: capturedAt,
                voidedAt: voidedAt,
                voidedBy: voidedBy,
                voidReason: voidReason,
                pendingMutationId: pendingMutationId,
                rowVersion: rowVersion,
                serverUpdatedAt: serverUpdatedAt,
                updatedAt: updatedAt,
                scopeRevokedAt: scopeRevokedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpensesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                expenseAllocationsRefs = false,
                expensePeriodAllocationsRefs = false,
                expenseAttachmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (expenseAllocationsRefs) db.expenseAllocations,
                    if (expensePeriodAllocationsRefs)
                      db.expensePeriodAllocations,
                    if (expenseAttachmentsRefs) db.expenseAttachments,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (expenseAllocationsRefs)
                        await $_getPrefetchedData<
                          ExpenseRow,
                          $ExpensesTable,
                          ExpenseAllocationRow
                        >(
                          currentTable: table,
                          referencedTable: $$ExpensesTableReferences
                              ._expenseAllocationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExpensesTableReferences(
                                db,
                                table,
                                p0,
                              ).expenseAllocationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.expenseId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensePeriodAllocationsRefs)
                        await $_getPrefetchedData<
                          ExpenseRow,
                          $ExpensesTable,
                          ExpensePeriodAllocationRow
                        >(
                          currentTable: table,
                          referencedTable: $$ExpensesTableReferences
                              ._expensePeriodAllocationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExpensesTableReferences(
                                db,
                                table,
                                p0,
                              ).expensePeriodAllocationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.expenseId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expenseAttachmentsRefs)
                        await $_getPrefetchedData<
                          ExpenseRow,
                          $ExpensesTable,
                          ExpenseAttachmentRow
                        >(
                          currentTable: table,
                          referencedTable: $$ExpensesTableReferences
                              ._expenseAttachmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExpensesTableReferences(
                                db,
                                table,
                                p0,
                              ).expenseAttachmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.expenseId == item.id,
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

typedef $$ExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpensesTable,
      ExpenseRow,
      $$ExpensesTableFilterComposer,
      $$ExpensesTableOrderingComposer,
      $$ExpensesTableAnnotationComposer,
      $$ExpensesTableCreateCompanionBuilder,
      $$ExpensesTableUpdateCompanionBuilder,
      (ExpenseRow, $$ExpensesTableReferences),
      ExpenseRow,
      PrefetchHooks Function({
        bool expenseAllocationsRefs,
        bool expensePeriodAllocationsRefs,
        bool expenseAttachmentsRefs,
      })
    >;
typedef $$ExpenseAllocationsTableCreateCompanionBuilder =
    ExpenseAllocationsCompanion Function({
      required String id,
      required String orgId,
      required String expenseId,
      required String businessUnitId,
      required String departmentId,
      required String sectionId,
      required String categoryId,
      required int amountMinor,
      required String categoryLabel,
      Value<int> sortOrder,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ExpenseAllocationsTableUpdateCompanionBuilder =
    ExpenseAllocationsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> expenseId,
      Value<String> businessUnitId,
      Value<String> departmentId,
      Value<String> sectionId,
      Value<String> categoryId,
      Value<int> amountMinor,
      Value<String> categoryLabel,
      Value<int> sortOrder,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExpenseAllocationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ExpenseAllocationsTable,
          ExpenseAllocationRow
        > {
  $$ExpenseAllocationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExpensesTable _expenseIdTable(_$AppDatabase db) =>
      db.expenses.createAlias('expense_allocations__expense_id__expenses__id');

  $$ExpensesTableProcessedTableManager get expenseId {
    final $_column = $_itemColumn<String>('expense_id')!;

    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_expenseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ExpensePeriodAllocationsTable,
    List<ExpensePeriodAllocationRow>
  >
  _expensePeriodAllocationsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expensePeriodAllocations,
    aliasName:
        'expense_allocations__id__expense_period_allocations__allocation_id',
  );

  $$ExpensePeriodAllocationsTableProcessedTableManager
  get expensePeriodAllocationsRefs {
    final manager = $$ExpensePeriodAllocationsTableTableManager(
      $_db,
      $_db.expensePeriodAllocations,
    ).filter((f) => f.allocationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _expensePeriodAllocationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExpenseAllocationsTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseAllocationsTable> {
  $$ExpenseAllocationsTableFilterComposer({
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

  ColumnFilters<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get departmentId => $composableBuilder(
    column: $table.departmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryLabel => $composableBuilder(
    column: $table.categoryLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
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

  $$ExpensesTableFilterComposer get expenseId {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> expensePeriodAllocationsRefs(
    Expression<bool> Function($$ExpensePeriodAllocationsTableFilterComposer f)
    f,
  ) {
    final $$ExpensePeriodAllocationsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expensePeriodAllocations,
          getReferencedColumn: (t) => t.allocationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpensePeriodAllocationsTableFilterComposer(
                $db: $db,
                $table: $db.expensePeriodAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ExpenseAllocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseAllocationsTable> {
  $$ExpenseAllocationsTableOrderingComposer({
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

  ColumnOrderings<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get departmentId => $composableBuilder(
    column: $table.departmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionId => $composableBuilder(
    column: $table.sectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryLabel => $composableBuilder(
    column: $table.categoryLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
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

  $$ExpensesTableOrderingComposer get expenseId {
    final $$ExpensesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableOrderingComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseAllocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseAllocationsTable> {
  $$ExpenseAllocationsTableAnnotationComposer({
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

  GeneratedColumn<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get departmentId => $composableBuilder(
    column: $table.departmentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sectionId =>
      $composableBuilder(column: $table.sectionId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryLabel => $composableBuilder(
    column: $table.categoryLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ExpensesTableAnnotationComposer get expenseId {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> expensePeriodAllocationsRefs<T extends Object>(
    Expression<T> Function($$ExpensePeriodAllocationsTableAnnotationComposer a)
    f,
  ) {
    final $$ExpensePeriodAllocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.expensePeriodAllocations,
          getReferencedColumn: (t) => t.allocationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpensePeriodAllocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.expensePeriodAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ExpenseAllocationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpenseAllocationsTable,
          ExpenseAllocationRow,
          $$ExpenseAllocationsTableFilterComposer,
          $$ExpenseAllocationsTableOrderingComposer,
          $$ExpenseAllocationsTableAnnotationComposer,
          $$ExpenseAllocationsTableCreateCompanionBuilder,
          $$ExpenseAllocationsTableUpdateCompanionBuilder,
          (ExpenseAllocationRow, $$ExpenseAllocationsTableReferences),
          ExpenseAllocationRow,
          PrefetchHooks Function({
            bool expenseId,
            bool expensePeriodAllocationsRefs,
          })
        > {
  $$ExpenseAllocationsTableTableManager(
    _$AppDatabase db,
    $ExpenseAllocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseAllocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseAllocationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseAllocationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> expenseId = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<String> departmentId = const Value.absent(),
                Value<String> sectionId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> categoryLabel = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseAllocationsCompanion(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                businessUnitId: businessUnitId,
                departmentId: departmentId,
                sectionId: sectionId,
                categoryId: categoryId,
                amountMinor: amountMinor,
                categoryLabel: categoryLabel,
                sortOrder: sortOrder,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String expenseId,
                required String businessUnitId,
                required String departmentId,
                required String sectionId,
                required String categoryId,
                required int amountMinor,
                required String categoryLabel,
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ExpenseAllocationsCompanion.insert(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                businessUnitId: businessUnitId,
                departmentId: departmentId,
                sectionId: sectionId,
                categoryId: categoryId,
                amountMinor: amountMinor,
                categoryLabel: categoryLabel,
                sortOrder: sortOrder,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpenseAllocationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({expenseId = false, expensePeriodAllocationsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (expensePeriodAllocationsRefs)
                      db.expensePeriodAllocations,
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
                        if (expenseId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.expenseId,
                                    referencedTable:
                                        $$ExpenseAllocationsTableReferences
                                            ._expenseIdTable(db),
                                    referencedColumn:
                                        $$ExpenseAllocationsTableReferences
                                            ._expenseIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (expensePeriodAllocationsRefs)
                        await $_getPrefetchedData<
                          ExpenseAllocationRow,
                          $ExpenseAllocationsTable,
                          ExpensePeriodAllocationRow
                        >(
                          currentTable: table,
                          referencedTable: $$ExpenseAllocationsTableReferences
                              ._expensePeriodAllocationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExpenseAllocationsTableReferences(
                                db,
                                table,
                                p0,
                              ).expensePeriodAllocationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.allocationId == item.id,
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

typedef $$ExpenseAllocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpenseAllocationsTable,
      ExpenseAllocationRow,
      $$ExpenseAllocationsTableFilterComposer,
      $$ExpenseAllocationsTableOrderingComposer,
      $$ExpenseAllocationsTableAnnotationComposer,
      $$ExpenseAllocationsTableCreateCompanionBuilder,
      $$ExpenseAllocationsTableUpdateCompanionBuilder,
      (ExpenseAllocationRow, $$ExpenseAllocationsTableReferences),
      ExpenseAllocationRow,
      PrefetchHooks Function({
        bool expenseId,
        bool expensePeriodAllocationsRefs,
      })
    >;
typedef $$ExpensePeriodAllocationsTableCreateCompanionBuilder =
    ExpensePeriodAllocationsCompanion Function({
      required String id,
      required String orgId,
      required String expenseId,
      required String allocationId,
      required String businessUnitId,
      required String accountingPeriodStart,
      required String accountingPeriodEnd,
      required int amountMinor,
      required String pnlDate,
      required String pnlPeriodKey,
      Value<bool> isDerived,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ExpensePeriodAllocationsTableUpdateCompanionBuilder =
    ExpensePeriodAllocationsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> expenseId,
      Value<String> allocationId,
      Value<String> businessUnitId,
      Value<String> accountingPeriodStart,
      Value<String> accountingPeriodEnd,
      Value<int> amountMinor,
      Value<String> pnlDate,
      Value<String> pnlPeriodKey,
      Value<bool> isDerived,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExpensePeriodAllocationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ExpensePeriodAllocationsTable,
          ExpensePeriodAllocationRow
        > {
  $$ExpensePeriodAllocationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExpensesTable _expenseIdTable(_$AppDatabase db) => db.expenses
      .createAlias('expense_period_allocations__expense_id__expenses__id');

  $$ExpensesTableProcessedTableManager get expenseId {
    final $_column = $_itemColumn<String>('expense_id')!;

    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_expenseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ExpenseAllocationsTable _allocationIdTable(_$AppDatabase db) =>
      db.expenseAllocations.createAlias(
        'expense_period_allocations__allocation_id__expense_allocations__id',
      );

  $$ExpenseAllocationsTableProcessedTableManager get allocationId {
    final $_column = $_itemColumn<String>('allocation_id')!;

    final manager = $$ExpenseAllocationsTableTableManager(
      $_db,
      $_db.expenseAllocations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_allocationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExpensePeriodAllocationsTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensePeriodAllocationsTable> {
  $$ExpensePeriodAllocationsTableFilterComposer({
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

  ColumnFilters<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pnlDate => $composableBuilder(
    column: $table.pnlDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDerived => $composableBuilder(
    column: $table.isDerived,
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

  $$ExpensesTableFilterComposer get expenseId {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpenseAllocationsTableFilterComposer get allocationId {
    final $$ExpenseAllocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.allocationId,
      referencedTable: $db.expenseAllocations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpenseAllocationsTableFilterComposer(
            $db: $db,
            $table: $db.expenseAllocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensePeriodAllocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensePeriodAllocationsTable> {
  $$ExpensePeriodAllocationsTableOrderingComposer({
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

  ColumnOrderings<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pnlDate => $composableBuilder(
    column: $table.pnlDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDerived => $composableBuilder(
    column: $table.isDerived,
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

  $$ExpensesTableOrderingComposer get expenseId {
    final $$ExpensesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableOrderingComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpenseAllocationsTableOrderingComposer get allocationId {
    final $$ExpenseAllocationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.allocationId,
      referencedTable: $db.expenseAllocations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpenseAllocationsTableOrderingComposer(
            $db: $db,
            $table: $db.expenseAllocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensePeriodAllocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensePeriodAllocationsTable> {
  $$ExpensePeriodAllocationsTableAnnotationComposer({
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

  GeneratedColumn<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountingPeriodStart => $composableBuilder(
    column: $table.accountingPeriodStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountingPeriodEnd => $composableBuilder(
    column: $table.accountingPeriodEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pnlDate =>
      $composableBuilder(column: $table.pnlDate, builder: (column) => column);

  GeneratedColumn<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDerived =>
      $composableBuilder(column: $table.isDerived, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ExpensesTableAnnotationComposer get expenseId {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpenseAllocationsTableAnnotationComposer get allocationId {
    final $$ExpenseAllocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.allocationId,
          referencedTable: $db.expenseAllocations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExpenseAllocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.expenseAllocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ExpensePeriodAllocationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpensePeriodAllocationsTable,
          ExpensePeriodAllocationRow,
          $$ExpensePeriodAllocationsTableFilterComposer,
          $$ExpensePeriodAllocationsTableOrderingComposer,
          $$ExpensePeriodAllocationsTableAnnotationComposer,
          $$ExpensePeriodAllocationsTableCreateCompanionBuilder,
          $$ExpensePeriodAllocationsTableUpdateCompanionBuilder,
          (
            ExpensePeriodAllocationRow,
            $$ExpensePeriodAllocationsTableReferences,
          ),
          ExpensePeriodAllocationRow,
          PrefetchHooks Function({bool expenseId, bool allocationId})
        > {
  $$ExpensePeriodAllocationsTableTableManager(
    _$AppDatabase db,
    $ExpensePeriodAllocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensePeriodAllocationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ExpensePeriodAllocationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ExpensePeriodAllocationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> expenseId = const Value.absent(),
                Value<String> allocationId = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<String> accountingPeriodStart = const Value.absent(),
                Value<String> accountingPeriodEnd = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> pnlDate = const Value.absent(),
                Value<String> pnlPeriodKey = const Value.absent(),
                Value<bool> isDerived = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensePeriodAllocationsCompanion(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                allocationId: allocationId,
                businessUnitId: businessUnitId,
                accountingPeriodStart: accountingPeriodStart,
                accountingPeriodEnd: accountingPeriodEnd,
                amountMinor: amountMinor,
                pnlDate: pnlDate,
                pnlPeriodKey: pnlPeriodKey,
                isDerived: isDerived,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String expenseId,
                required String allocationId,
                required String businessUnitId,
                required String accountingPeriodStart,
                required String accountingPeriodEnd,
                required int amountMinor,
                required String pnlDate,
                required String pnlPeriodKey,
                Value<bool> isDerived = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ExpensePeriodAllocationsCompanion.insert(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                allocationId: allocationId,
                businessUnitId: businessUnitId,
                accountingPeriodStart: accountingPeriodStart,
                accountingPeriodEnd: accountingPeriodEnd,
                amountMinor: amountMinor,
                pnlDate: pnlDate,
                pnlPeriodKey: pnlPeriodKey,
                isDerived: isDerived,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpensePeriodAllocationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({expenseId = false, allocationId = false}) {
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
                    if (expenseId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.expenseId,
                                referencedTable:
                                    $$ExpensePeriodAllocationsTableReferences
                                        ._expenseIdTable(db),
                                referencedColumn:
                                    $$ExpensePeriodAllocationsTableReferences
                                        ._expenseIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (allocationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.allocationId,
                                referencedTable:
                                    $$ExpensePeriodAllocationsTableReferences
                                        ._allocationIdTable(db),
                                referencedColumn:
                                    $$ExpensePeriodAllocationsTableReferences
                                        ._allocationIdTable(db)
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

typedef $$ExpensePeriodAllocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpensePeriodAllocationsTable,
      ExpensePeriodAllocationRow,
      $$ExpensePeriodAllocationsTableFilterComposer,
      $$ExpensePeriodAllocationsTableOrderingComposer,
      $$ExpensePeriodAllocationsTableAnnotationComposer,
      $$ExpensePeriodAllocationsTableCreateCompanionBuilder,
      $$ExpensePeriodAllocationsTableUpdateCompanionBuilder,
      (ExpensePeriodAllocationRow, $$ExpensePeriodAllocationsTableReferences),
      ExpensePeriodAllocationRow,
      PrefetchHooks Function({bool expenseId, bool allocationId})
    >;
typedef $$ExpenseAttachmentsTableCreateCompanionBuilder =
    ExpenseAttachmentsCompanion Function({
      required String id,
      required String orgId,
      required String expenseId,
      required String fileName,
      required String contentType,
      required int byteSize,
      required String contentHash,
      Value<String?> localPath,
      Value<String> uploadState,
      Value<String?> storagePath,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime?> uploadedAt,
      Value<DateTime?> reclaimableAfter,
      required String uploadedBy,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ExpenseAttachmentsTableUpdateCompanionBuilder =
    ExpenseAttachmentsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> expenseId,
      Value<String> fileName,
      Value<String> contentType,
      Value<int> byteSize,
      Value<String> contentHash,
      Value<String?> localPath,
      Value<String> uploadState,
      Value<String?> storagePath,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime?> uploadedAt,
      Value<DateTime?> reclaimableAfter,
      Value<String> uploadedBy,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExpenseAttachmentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ExpenseAttachmentsTable,
          ExpenseAttachmentRow
        > {
  $$ExpenseAttachmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExpensesTable _expenseIdTable(_$AppDatabase db) =>
      db.expenses.createAlias('expense_attachments__expense_id__expenses__id');

  $$ExpensesTableProcessedTableManager get expenseId {
    final $_column = $_itemColumn<String>('expense_id')!;

    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_expenseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExpenseAttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseAttachmentsTable> {
  $$ExpenseAttachmentsTableFilterComposer({
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

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
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

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reclaimableAfter => $composableBuilder(
    column: $table.reclaimableAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ExpensesTableFilterComposer get expenseId {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseAttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseAttachmentsTable> {
  $$ExpenseAttachmentsTableOrderingComposer({
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

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
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

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reclaimableAfter => $composableBuilder(
    column: $table.reclaimableAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExpensesTableOrderingComposer get expenseId {
    final $$ExpensesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableOrderingComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseAttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseAttachmentsTable> {
  $$ExpenseAttachmentsTableAnnotationComposer({
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

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
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

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reclaimableAfter => $composableBuilder(
    column: $table.reclaimableAfter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uploadedBy => $composableBuilder(
    column: $table.uploadedBy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ExpensesTableAnnotationComposer get expenseId {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpenseAttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpenseAttachmentsTable,
          ExpenseAttachmentRow,
          $$ExpenseAttachmentsTableFilterComposer,
          $$ExpenseAttachmentsTableOrderingComposer,
          $$ExpenseAttachmentsTableAnnotationComposer,
          $$ExpenseAttachmentsTableCreateCompanionBuilder,
          $$ExpenseAttachmentsTableUpdateCompanionBuilder,
          (ExpenseAttachmentRow, $$ExpenseAttachmentsTableReferences),
          ExpenseAttachmentRow,
          PrefetchHooks Function({bool expenseId})
        > {
  $$ExpenseAttachmentsTableTableManager(
    _$AppDatabase db,
    $ExpenseAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseAttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseAttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseAttachmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> expenseId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> uploadedAt = const Value.absent(),
                Value<DateTime?> reclaimableAfter = const Value.absent(),
                Value<String> uploadedBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpenseAttachmentsCompanion(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                fileName: fileName,
                contentType: contentType,
                byteSize: byteSize,
                contentHash: contentHash,
                localPath: localPath,
                uploadState: uploadState,
                storagePath: storagePath,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                uploadedAt: uploadedAt,
                reclaimableAfter: reclaimableAfter,
                uploadedBy: uploadedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String expenseId,
                required String fileName,
                required String contentType,
                required int byteSize,
                required String contentHash,
                Value<String?> localPath = const Value.absent(),
                Value<String> uploadState = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> uploadedAt = const Value.absent(),
                Value<DateTime?> reclaimableAfter = const Value.absent(),
                required String uploadedBy,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ExpenseAttachmentsCompanion.insert(
                id: id,
                orgId: orgId,
                expenseId: expenseId,
                fileName: fileName,
                contentType: contentType,
                byteSize: byteSize,
                contentHash: contentHash,
                localPath: localPath,
                uploadState: uploadState,
                storagePath: storagePath,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                uploadedAt: uploadedAt,
                reclaimableAfter: reclaimableAfter,
                uploadedBy: uploadedBy,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExpenseAttachmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({expenseId = false}) {
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
                    if (expenseId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.expenseId,
                                referencedTable:
                                    $$ExpenseAttachmentsTableReferences
                                        ._expenseIdTable(db),
                                referencedColumn:
                                    $$ExpenseAttachmentsTableReferences
                                        ._expenseIdTable(db)
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

typedef $$ExpenseAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpenseAttachmentsTable,
      ExpenseAttachmentRow,
      $$ExpenseAttachmentsTableFilterComposer,
      $$ExpenseAttachmentsTableOrderingComposer,
      $$ExpenseAttachmentsTableAnnotationComposer,
      $$ExpenseAttachmentsTableCreateCompanionBuilder,
      $$ExpenseAttachmentsTableUpdateCompanionBuilder,
      (ExpenseAttachmentRow, $$ExpenseAttachmentsTableReferences),
      ExpenseAttachmentRow,
      PrefetchHooks Function({bool expenseId})
    >;
typedef $$RevenueEntriesTableCreateCompanionBuilder =
    RevenueEntriesCompanion Function({
      required String id,
      required String orgId,
      Value<String?> txnNumber,
      Value<String?> financialYear,
      required String businessUnitId,
      required String revenueCategoryId,
      required String businessDate,
      required String pnlPeriodKey,
      required DateTime capturedAt,
      Value<String> entryKind,
      Value<String?> sourceReference,
      Value<String?> notes,
      required String createdBy,
      Value<DateTime?> voidedAt,
      Value<String?> voidedBy,
      Value<String?> voidReason,
      Value<String?> pendingMutationId,
      Value<int> rowVersion,
      Value<DateTime?> serverUpdatedAt,
      required DateTime updatedAt,
      Value<DateTime?> scopeRevokedAt,
      Value<int> rowid,
    });
typedef $$RevenueEntriesTableUpdateCompanionBuilder =
    RevenueEntriesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String?> txnNumber,
      Value<String?> financialYear,
      Value<String> businessUnitId,
      Value<String> revenueCategoryId,
      Value<String> businessDate,
      Value<String> pnlPeriodKey,
      Value<DateTime> capturedAt,
      Value<String> entryKind,
      Value<String?> sourceReference,
      Value<String?> notes,
      Value<String> createdBy,
      Value<DateTime?> voidedAt,
      Value<String?> voidedBy,
      Value<String?> voidReason,
      Value<String?> pendingMutationId,
      Value<int> rowVersion,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> scopeRevokedAt,
      Value<int> rowid,
    });

final class $$RevenueEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $RevenueEntriesTable, RevenueEntryRow> {
  $$RevenueEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$RevenueComponentsTable, List<RevenueComponentRow>>
  _revenueComponentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.revenueComponents,
        aliasName: 'revenue_entries__id__revenue_components__revenue_entry_id',
      );

  $$RevenueComponentsTableProcessedTableManager get revenueComponentsRefs {
    final manager = $$RevenueComponentsTableTableManager(
      $_db,
      $_db.revenueComponents,
    ).filter((f) => f.revenueEntryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _revenueComponentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RevenueEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueEntriesTable> {
  $$RevenueEntriesTableFilterComposer({
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

  ColumnFilters<String> get txnNumber => $composableBuilder(
    column: $table.txnNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revenueCategoryId => $composableBuilder(
    column: $table.revenueCategoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryKind => $composableBuilder(
    column: $table.entryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceReference => $composableBuilder(
    column: $table.sourceReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voidedBy => $composableBuilder(
    column: $table.voidedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> revenueComponentsRefs(
    Expression<bool> Function($$RevenueComponentsTableFilterComposer f) f,
  ) {
    final $$RevenueComponentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revenueComponents,
      getReferencedColumn: (t) => t.revenueEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueComponentsTableFilterComposer(
            $db: $db,
            $table: $db.revenueComponents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RevenueEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueEntriesTable> {
  $$RevenueEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get txnNumber => $composableBuilder(
    column: $table.txnNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revenueCategoryId => $composableBuilder(
    column: $table.revenueCategoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryKind => $composableBuilder(
    column: $table.entryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceReference => $composableBuilder(
    column: $table.sourceReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get voidedAt => $composableBuilder(
    column: $table.voidedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voidedBy => $composableBuilder(
    column: $table.voidedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RevenueEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueEntriesTable> {
  $$RevenueEntriesTableAnnotationComposer({
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

  GeneratedColumn<String> get txnNumber =>
      $composableBuilder(column: $table.txnNumber, builder: (column) => column);

  GeneratedColumn<String> get financialYear => $composableBuilder(
    column: $table.financialYear,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get revenueCategoryId => $composableBuilder(
    column: $table.revenueCategoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessDate => $composableBuilder(
    column: $table.businessDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pnlPeriodKey => $composableBuilder(
    column: $table.pnlPeriodKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entryKind =>
      $composableBuilder(column: $table.entryKind, builder: (column) => column);

  GeneratedColumn<String> get sourceReference => $composableBuilder(
    column: $table.sourceReference,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get voidedAt =>
      $composableBuilder(column: $table.voidedAt, builder: (column) => column);

  GeneratedColumn<String> get voidedBy =>
      $composableBuilder(column: $table.voidedBy, builder: (column) => column);

  GeneratedColumn<String> get voidReason => $composableBuilder(
    column: $table.voidReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingMutationId => $composableBuilder(
    column: $table.pendingMutationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get scopeRevokedAt => $composableBuilder(
    column: $table.scopeRevokedAt,
    builder: (column) => column,
  );

  Expression<T> revenueComponentsRefs<T extends Object>(
    Expression<T> Function($$RevenueComponentsTableAnnotationComposer a) f,
  ) {
    final $$RevenueComponentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.revenueComponents,
          getReferencedColumn: (t) => t.revenueEntryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RevenueComponentsTableAnnotationComposer(
                $db: $db,
                $table: $db.revenueComponents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$RevenueEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueEntriesTable,
          RevenueEntryRow,
          $$RevenueEntriesTableFilterComposer,
          $$RevenueEntriesTableOrderingComposer,
          $$RevenueEntriesTableAnnotationComposer,
          $$RevenueEntriesTableCreateCompanionBuilder,
          $$RevenueEntriesTableUpdateCompanionBuilder,
          (RevenueEntryRow, $$RevenueEntriesTableReferences),
          RevenueEntryRow,
          PrefetchHooks Function({bool revenueComponentsRefs})
        > {
  $$RevenueEntriesTableTableManager(
    _$AppDatabase db,
    $RevenueEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevenueEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevenueEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String?> txnNumber = const Value.absent(),
                Value<String?> financialYear = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<String> revenueCategoryId = const Value.absent(),
                Value<String> businessDate = const Value.absent(),
                Value<String> pnlPeriodKey = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<String> entryKind = const Value.absent(),
                Value<String?> sourceReference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<String?> voidedBy = const Value.absent(),
                Value<String?> voidReason = const Value.absent(),
                Value<String?> pendingMutationId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> scopeRevokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueEntriesCompanion(
                id: id,
                orgId: orgId,
                txnNumber: txnNumber,
                financialYear: financialYear,
                businessUnitId: businessUnitId,
                revenueCategoryId: revenueCategoryId,
                businessDate: businessDate,
                pnlPeriodKey: pnlPeriodKey,
                capturedAt: capturedAt,
                entryKind: entryKind,
                sourceReference: sourceReference,
                notes: notes,
                createdBy: createdBy,
                voidedAt: voidedAt,
                voidedBy: voidedBy,
                voidReason: voidReason,
                pendingMutationId: pendingMutationId,
                rowVersion: rowVersion,
                serverUpdatedAt: serverUpdatedAt,
                updatedAt: updatedAt,
                scopeRevokedAt: scopeRevokedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                Value<String?> txnNumber = const Value.absent(),
                Value<String?> financialYear = const Value.absent(),
                required String businessUnitId,
                required String revenueCategoryId,
                required String businessDate,
                required String pnlPeriodKey,
                required DateTime capturedAt,
                Value<String> entryKind = const Value.absent(),
                Value<String?> sourceReference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required String createdBy,
                Value<DateTime?> voidedAt = const Value.absent(),
                Value<String?> voidedBy = const Value.absent(),
                Value<String?> voidReason = const Value.absent(),
                Value<String?> pendingMutationId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> scopeRevokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueEntriesCompanion.insert(
                id: id,
                orgId: orgId,
                txnNumber: txnNumber,
                financialYear: financialYear,
                businessUnitId: businessUnitId,
                revenueCategoryId: revenueCategoryId,
                businessDate: businessDate,
                pnlPeriodKey: pnlPeriodKey,
                capturedAt: capturedAt,
                entryKind: entryKind,
                sourceReference: sourceReference,
                notes: notes,
                createdBy: createdBy,
                voidedAt: voidedAt,
                voidedBy: voidedBy,
                voidReason: voidReason,
                pendingMutationId: pendingMutationId,
                rowVersion: rowVersion,
                serverUpdatedAt: serverUpdatedAt,
                updatedAt: updatedAt,
                scopeRevokedAt: scopeRevokedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({revenueComponentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (revenueComponentsRefs) db.revenueComponents,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (revenueComponentsRefs)
                    await $_getPrefetchedData<
                      RevenueEntryRow,
                      $RevenueEntriesTable,
                      RevenueComponentRow
                    >(
                      currentTable: table,
                      referencedTable: $$RevenueEntriesTableReferences
                          ._revenueComponentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RevenueEntriesTableReferences(
                            db,
                            table,
                            p0,
                          ).revenueComponentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.revenueEntryId == item.id,
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

typedef $$RevenueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueEntriesTable,
      RevenueEntryRow,
      $$RevenueEntriesTableFilterComposer,
      $$RevenueEntriesTableOrderingComposer,
      $$RevenueEntriesTableAnnotationComposer,
      $$RevenueEntriesTableCreateCompanionBuilder,
      $$RevenueEntriesTableUpdateCompanionBuilder,
      (RevenueEntryRow, $$RevenueEntriesTableReferences),
      RevenueEntryRow,
      PrefetchHooks Function({bool revenueComponentsRefs})
    >;
typedef $$RevenueComponentsTableCreateCompanionBuilder =
    RevenueComponentsCompanion Function({
      required String id,
      required String orgId,
      required String revenueEntryId,
      required int enteredAmountMinor,
      required String enteredBasis,
      required int grossAmountMinor,
      required int taxAmountMinor,
      required int netAmountMinor,
      required String taxRuleId,
      required int taxRateBasisPoints,
      required String taxTreatment,
      Value<String?> valueBandId,
      Value<String?> valueBandLabel,
      Value<int?> valueBandFloorMinor,
      Value<int?> valueBandCeilingMinor,
      Value<String?> supplySubtypeId,
      Value<String?> supplySubtypeLabel,
      Value<String?> premisesStatusCode,
      Value<int> rowid,
    });
typedef $$RevenueComponentsTableUpdateCompanionBuilder =
    RevenueComponentsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> revenueEntryId,
      Value<int> enteredAmountMinor,
      Value<String> enteredBasis,
      Value<int> grossAmountMinor,
      Value<int> taxAmountMinor,
      Value<int> netAmountMinor,
      Value<String> taxRuleId,
      Value<int> taxRateBasisPoints,
      Value<String> taxTreatment,
      Value<String?> valueBandId,
      Value<String?> valueBandLabel,
      Value<int?> valueBandFloorMinor,
      Value<int?> valueBandCeilingMinor,
      Value<String?> supplySubtypeId,
      Value<String?> supplySubtypeLabel,
      Value<String?> premisesStatusCode,
      Value<int> rowid,
    });

final class $$RevenueComponentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevenueComponentsTable,
          RevenueComponentRow
        > {
  $$RevenueComponentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RevenueEntriesTable _revenueEntryIdTable(_$AppDatabase db) => db
      .revenueEntries
      .createAlias('revenue_components__revenue_entry_id__revenue_entries__id');

  $$RevenueEntriesTableProcessedTableManager get revenueEntryId {
    final $_column = $_itemColumn<String>('revenue_entry_id')!;

    final manager = $$RevenueEntriesTableTableManager(
      $_db,
      $_db.revenueEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_revenueEntryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RevenueComponentsTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueComponentsTable> {
  $$RevenueComponentsTableFilterComposer({
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

  ColumnFilters<int> get enteredAmountMinor => $composableBuilder(
    column: $table.enteredAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get enteredBasis => $composableBuilder(
    column: $table.enteredBasis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get grossAmountMinor => $composableBuilder(
    column: $table.grossAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get netAmountMinor => $composableBuilder(
    column: $table.netAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taxRuleId => $composableBuilder(
    column: $table.taxRuleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxRateBasisPoints => $composableBuilder(
    column: $table.taxRateBasisPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taxTreatment => $composableBuilder(
    column: $table.taxTreatment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueBandLabel => $composableBuilder(
    column: $table.valueBandLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueBandFloorMinor => $composableBuilder(
    column: $table.valueBandFloorMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueBandCeilingMinor => $composableBuilder(
    column: $table.valueBandCeilingMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supplySubtypeLabel => $composableBuilder(
    column: $table.supplySubtypeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
    builder: (column) => ColumnFilters(column),
  );

  $$RevenueEntriesTableFilterComposer get revenueEntryId {
    final $$RevenueEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revenueEntryId,
      referencedTable: $db.revenueEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueEntriesTableFilterComposer(
            $db: $db,
            $table: $db.revenueEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueComponentsTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueComponentsTable> {
  $$RevenueComponentsTableOrderingComposer({
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

  ColumnOrderings<int> get enteredAmountMinor => $composableBuilder(
    column: $table.enteredAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get enteredBasis => $composableBuilder(
    column: $table.enteredBasis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get grossAmountMinor => $composableBuilder(
    column: $table.grossAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get netAmountMinor => $composableBuilder(
    column: $table.netAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taxRuleId => $composableBuilder(
    column: $table.taxRuleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxRateBasisPoints => $composableBuilder(
    column: $table.taxRateBasisPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taxTreatment => $composableBuilder(
    column: $table.taxTreatment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueBandLabel => $composableBuilder(
    column: $table.valueBandLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueBandFloorMinor => $composableBuilder(
    column: $table.valueBandFloorMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueBandCeilingMinor => $composableBuilder(
    column: $table.valueBandCeilingMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supplySubtypeLabel => $composableBuilder(
    column: $table.supplySubtypeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
    builder: (column) => ColumnOrderings(column),
  );

  $$RevenueEntriesTableOrderingComposer get revenueEntryId {
    final $$RevenueEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revenueEntryId,
      referencedTable: $db.revenueEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.revenueEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueComponentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueComponentsTable> {
  $$RevenueComponentsTableAnnotationComposer({
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

  GeneratedColumn<int> get enteredAmountMinor => $composableBuilder(
    column: $table.enteredAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get enteredBasis => $composableBuilder(
    column: $table.enteredBasis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get grossAmountMinor => $composableBuilder(
    column: $table.grossAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taxAmountMinor => $composableBuilder(
    column: $table.taxAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get netAmountMinor => $composableBuilder(
    column: $table.netAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taxRuleId =>
      $composableBuilder(column: $table.taxRuleId, builder: (column) => column);

  GeneratedColumn<int> get taxRateBasisPoints => $composableBuilder(
    column: $table.taxRateBasisPoints,
    builder: (column) => column,
  );

  GeneratedColumn<String> get taxTreatment => $composableBuilder(
    column: $table.taxTreatment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueBandId => $composableBuilder(
    column: $table.valueBandId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueBandLabel => $composableBuilder(
    column: $table.valueBandLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get valueBandFloorMinor => $composableBuilder(
    column: $table.valueBandFloorMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get valueBandCeilingMinor => $composableBuilder(
    column: $table.valueBandCeilingMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supplySubtypeId => $composableBuilder(
    column: $table.supplySubtypeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supplySubtypeLabel => $composableBuilder(
    column: $table.supplySubtypeLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get premisesStatusCode => $composableBuilder(
    column: $table.premisesStatusCode,
    builder: (column) => column,
  );

  $$RevenueEntriesTableAnnotationComposer get revenueEntryId {
    final $$RevenueEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revenueEntryId,
      referencedTable: $db.revenueEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevenueEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.revenueEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevenueComponentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueComponentsTable,
          RevenueComponentRow,
          $$RevenueComponentsTableFilterComposer,
          $$RevenueComponentsTableOrderingComposer,
          $$RevenueComponentsTableAnnotationComposer,
          $$RevenueComponentsTableCreateCompanionBuilder,
          $$RevenueComponentsTableUpdateCompanionBuilder,
          (RevenueComponentRow, $$RevenueComponentsTableReferences),
          RevenueComponentRow,
          PrefetchHooks Function({bool revenueEntryId})
        > {
  $$RevenueComponentsTableTableManager(
    _$AppDatabase db,
    $RevenueComponentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueComponentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevenueComponentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevenueComponentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> revenueEntryId = const Value.absent(),
                Value<int> enteredAmountMinor = const Value.absent(),
                Value<String> enteredBasis = const Value.absent(),
                Value<int> grossAmountMinor = const Value.absent(),
                Value<int> taxAmountMinor = const Value.absent(),
                Value<int> netAmountMinor = const Value.absent(),
                Value<String> taxRuleId = const Value.absent(),
                Value<int> taxRateBasisPoints = const Value.absent(),
                Value<String> taxTreatment = const Value.absent(),
                Value<String?> valueBandId = const Value.absent(),
                Value<String?> valueBandLabel = const Value.absent(),
                Value<int?> valueBandFloorMinor = const Value.absent(),
                Value<int?> valueBandCeilingMinor = const Value.absent(),
                Value<String?> supplySubtypeId = const Value.absent(),
                Value<String?> supplySubtypeLabel = const Value.absent(),
                Value<String?> premisesStatusCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueComponentsCompanion(
                id: id,
                orgId: orgId,
                revenueEntryId: revenueEntryId,
                enteredAmountMinor: enteredAmountMinor,
                enteredBasis: enteredBasis,
                grossAmountMinor: grossAmountMinor,
                taxAmountMinor: taxAmountMinor,
                netAmountMinor: netAmountMinor,
                taxRuleId: taxRuleId,
                taxRateBasisPoints: taxRateBasisPoints,
                taxTreatment: taxTreatment,
                valueBandId: valueBandId,
                valueBandLabel: valueBandLabel,
                valueBandFloorMinor: valueBandFloorMinor,
                valueBandCeilingMinor: valueBandCeilingMinor,
                supplySubtypeId: supplySubtypeId,
                supplySubtypeLabel: supplySubtypeLabel,
                premisesStatusCode: premisesStatusCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String revenueEntryId,
                required int enteredAmountMinor,
                required String enteredBasis,
                required int grossAmountMinor,
                required int taxAmountMinor,
                required int netAmountMinor,
                required String taxRuleId,
                required int taxRateBasisPoints,
                required String taxTreatment,
                Value<String?> valueBandId = const Value.absent(),
                Value<String?> valueBandLabel = const Value.absent(),
                Value<int?> valueBandFloorMinor = const Value.absent(),
                Value<int?> valueBandCeilingMinor = const Value.absent(),
                Value<String?> supplySubtypeId = const Value.absent(),
                Value<String?> supplySubtypeLabel = const Value.absent(),
                Value<String?> premisesStatusCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueComponentsCompanion.insert(
                id: id,
                orgId: orgId,
                revenueEntryId: revenueEntryId,
                enteredAmountMinor: enteredAmountMinor,
                enteredBasis: enteredBasis,
                grossAmountMinor: grossAmountMinor,
                taxAmountMinor: taxAmountMinor,
                netAmountMinor: netAmountMinor,
                taxRuleId: taxRuleId,
                taxRateBasisPoints: taxRateBasisPoints,
                taxTreatment: taxTreatment,
                valueBandId: valueBandId,
                valueBandLabel: valueBandLabel,
                valueBandFloorMinor: valueBandFloorMinor,
                valueBandCeilingMinor: valueBandCeilingMinor,
                supplySubtypeId: supplySubtypeId,
                supplySubtypeLabel: supplySubtypeLabel,
                premisesStatusCode: premisesStatusCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueComponentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({revenueEntryId = false}) {
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
                    if (revenueEntryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.revenueEntryId,
                                referencedTable:
                                    $$RevenueComponentsTableReferences
                                        ._revenueEntryIdTable(db),
                                referencedColumn:
                                    $$RevenueComponentsTableReferences
                                        ._revenueEntryIdTable(db)
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

typedef $$RevenueComponentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueComponentsTable,
      RevenueComponentRow,
      $$RevenueComponentsTableFilterComposer,
      $$RevenueComponentsTableOrderingComposer,
      $$RevenueComponentsTableAnnotationComposer,
      $$RevenueComponentsTableCreateCompanionBuilder,
      $$RevenueComponentsTableUpdateCompanionBuilder,
      (RevenueComponentRow, $$RevenueComponentsTableReferences),
      RevenueComponentRow,
      PrefetchHooks Function({bool revenueEntryId})
    >;
typedef $$RevenueValueBandsTableCreateCompanionBuilder =
    RevenueValueBandsCompanion Function({
      required String id,
      required String orgId,
      required String revenueCategoryId,
      required String code,
      required String label,
      Value<int?> floorMinor,
      Value<int?> ceilingMinor,
      Value<String?> supersededByBandId,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RevenueValueBandsTableUpdateCompanionBuilder =
    RevenueValueBandsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> revenueCategoryId,
      Value<String> code,
      Value<String> label,
      Value<int?> floorMinor,
      Value<int?> ceilingMinor,
      Value<String?> supersededByBandId,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$RevenueValueBandsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevenueValueBandsTable,
          RevenueValueBandRow
        > {
  $$RevenueValueBandsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RevenueCategoriesTable _revenueCategoryIdTable(_$AppDatabase db) =>
      db.revenueCategories.createAlias(
        'revenue_value_bands__revenue_category_id__revenue_categories__id',
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

class $$RevenueValueBandsTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueValueBandsTable> {
  $$RevenueValueBandsTableFilterComposer({
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

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get floorMinor => $composableBuilder(
    column: $table.floorMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ceilingMinor => $composableBuilder(
    column: $table.ceilingMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supersededByBandId => $composableBuilder(
    column: $table.supersededByBandId,
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

class $$RevenueValueBandsTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueValueBandsTable> {
  $$RevenueValueBandsTableOrderingComposer({
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

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get floorMinor => $composableBuilder(
    column: $table.floorMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ceilingMinor => $composableBuilder(
    column: $table.ceilingMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supersededByBandId => $composableBuilder(
    column: $table.supersededByBandId,
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

class $$RevenueValueBandsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueValueBandsTable> {
  $$RevenueValueBandsTableAnnotationComposer({
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

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get floorMinor => $composableBuilder(
    column: $table.floorMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ceilingMinor => $composableBuilder(
    column: $table.ceilingMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supersededByBandId => $composableBuilder(
    column: $table.supersededByBandId,
    builder: (column) => column,
  );

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

class $$RevenueValueBandsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueValueBandsTable,
          RevenueValueBandRow,
          $$RevenueValueBandsTableFilterComposer,
          $$RevenueValueBandsTableOrderingComposer,
          $$RevenueValueBandsTableAnnotationComposer,
          $$RevenueValueBandsTableCreateCompanionBuilder,
          $$RevenueValueBandsTableUpdateCompanionBuilder,
          (RevenueValueBandRow, $$RevenueValueBandsTableReferences),
          RevenueValueBandRow,
          PrefetchHooks Function({bool revenueCategoryId})
        > {
  $$RevenueValueBandsTableTableManager(
    _$AppDatabase db,
    $RevenueValueBandsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueValueBandsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevenueValueBandsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevenueValueBandsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> revenueCategoryId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int?> floorMinor = const Value.absent(),
                Value<int?> ceilingMinor = const Value.absent(),
                Value<String?> supersededByBandId = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueValueBandsCompanion(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                code: code,
                label: label,
                floorMinor: floorMinor,
                ceilingMinor: ceilingMinor,
                supersededByBandId: supersededByBandId,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String revenueCategoryId,
                required String code,
                required String label,
                Value<int?> floorMinor = const Value.absent(),
                Value<int?> ceilingMinor = const Value.absent(),
                Value<String?> supersededByBandId = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RevenueValueBandsCompanion.insert(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                code: code,
                label: label,
                floorMinor: floorMinor,
                ceilingMinor: ceilingMinor,
                supersededByBandId: supersededByBandId,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueValueBandsTableReferences(db, table, e),
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
                                    $$RevenueValueBandsTableReferences
                                        ._revenueCategoryIdTable(db),
                                referencedColumn:
                                    $$RevenueValueBandsTableReferences
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

typedef $$RevenueValueBandsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueValueBandsTable,
      RevenueValueBandRow,
      $$RevenueValueBandsTableFilterComposer,
      $$RevenueValueBandsTableOrderingComposer,
      $$RevenueValueBandsTableAnnotationComposer,
      $$RevenueValueBandsTableCreateCompanionBuilder,
      $$RevenueValueBandsTableUpdateCompanionBuilder,
      (RevenueValueBandRow, $$RevenueValueBandsTableReferences),
      RevenueValueBandRow,
      PrefetchHooks Function({bool revenueCategoryId})
    >;
typedef $$RevenueSupplySubtypesTableCreateCompanionBuilder =
    RevenueSupplySubtypesCompanion Function({
      required String id,
      required String orgId,
      required String revenueCategoryId,
      required String code,
      required String label,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RevenueSupplySubtypesTableUpdateCompanionBuilder =
    RevenueSupplySubtypesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> revenueCategoryId,
      Value<String> code,
      Value<String> label,
      Value<DateTime?> archivedAt,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$RevenueSupplySubtypesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RevenueSupplySubtypesTable,
          RevenueSupplySubtypeRow
        > {
  $$RevenueSupplySubtypesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RevenueCategoriesTable _revenueCategoryIdTable(_$AppDatabase db) =>
      db.revenueCategories.createAlias(
        'revenue_supply_subtypes__revenue_category_id__revenue_categories__id',
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

class $$RevenueSupplySubtypesTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueSupplySubtypesTable> {
  $$RevenueSupplySubtypesTableFilterComposer({
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

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
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

class $$RevenueSupplySubtypesTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueSupplySubtypesTable> {
  $$RevenueSupplySubtypesTableOrderingComposer({
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

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
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

class $$RevenueSupplySubtypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueSupplySubtypesTable> {
  $$RevenueSupplySubtypesTableAnnotationComposer({
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

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

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

class $$RevenueSupplySubtypesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueSupplySubtypesTable,
          RevenueSupplySubtypeRow,
          $$RevenueSupplySubtypesTableFilterComposer,
          $$RevenueSupplySubtypesTableOrderingComposer,
          $$RevenueSupplySubtypesTableAnnotationComposer,
          $$RevenueSupplySubtypesTableCreateCompanionBuilder,
          $$RevenueSupplySubtypesTableUpdateCompanionBuilder,
          (RevenueSupplySubtypeRow, $$RevenueSupplySubtypesTableReferences),
          RevenueSupplySubtypeRow,
          PrefetchHooks Function({bool revenueCategoryId})
        > {
  $$RevenueSupplySubtypesTableTableManager(
    _$AppDatabase db,
    $RevenueSupplySubtypesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueSupplySubtypesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RevenueSupplySubtypesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RevenueSupplySubtypesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> revenueCategoryId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueSupplySubtypesCompanion(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                code: code,
                label: label,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String revenueCategoryId,
                required String code,
                required String label,
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RevenueSupplySubtypesCompanion.insert(
                id: id,
                orgId: orgId,
                revenueCategoryId: revenueCategoryId,
                code: code,
                label: label,
                archivedAt: archivedAt,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevenueSupplySubtypesTableReferences(db, table, e),
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
                                    $$RevenueSupplySubtypesTableReferences
                                        ._revenueCategoryIdTable(db),
                                referencedColumn:
                                    $$RevenueSupplySubtypesTableReferences
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

typedef $$RevenueSupplySubtypesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueSupplySubtypesTable,
      RevenueSupplySubtypeRow,
      $$RevenueSupplySubtypesTableFilterComposer,
      $$RevenueSupplySubtypesTableOrderingComposer,
      $$RevenueSupplySubtypesTableAnnotationComposer,
      $$RevenueSupplySubtypesTableCreateCompanionBuilder,
      $$RevenueSupplySubtypesTableUpdateCompanionBuilder,
      (RevenueSupplySubtypeRow, $$RevenueSupplySubtypesTableReferences),
      RevenueSupplySubtypeRow,
      PrefetchHooks Function({bool revenueCategoryId})
    >;
typedef $$BusinessUnitTaxStatusesTableCreateCompanionBuilder =
    BusinessUnitTaxStatusesCompanion Function({
      required String id,
      required String orgId,
      required String businessUnitId,
      required String effectiveFrom,
      Value<String?> effectiveTo,
      Value<DateTime?> archivedAt,
      required String statusCode,
      Value<String?> note,
      Value<int> rowVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BusinessUnitTaxStatusesTableUpdateCompanionBuilder =
    BusinessUnitTaxStatusesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> businessUnitId,
      Value<String> effectiveFrom,
      Value<String?> effectiveTo,
      Value<DateTime?> archivedAt,
      Value<String> statusCode,
      Value<String?> note,
      Value<int> rowVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$BusinessUnitTaxStatusesTableFilterComposer
    extends Composer<_$AppDatabase, $BusinessUnitTaxStatusesTable> {
  $$BusinessUnitTaxStatusesTableFilterComposer({
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

  ColumnFilters<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
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

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
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
}

class $$BusinessUnitTaxStatusesTableOrderingComposer
    extends Composer<_$AppDatabase, $BusinessUnitTaxStatusesTable> {
  $$BusinessUnitTaxStatusesTableOrderingComposer({
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

  ColumnOrderings<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
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

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
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
}

class $$BusinessUnitTaxStatusesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BusinessUnitTaxStatusesTable> {
  $$BusinessUnitTaxStatusesTableAnnotationComposer({
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

  GeneratedColumn<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusCode => $composableBuilder(
    column: $table.statusCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BusinessUnitTaxStatusesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BusinessUnitTaxStatusesTable,
          BusinessUnitTaxStatusRow,
          $$BusinessUnitTaxStatusesTableFilterComposer,
          $$BusinessUnitTaxStatusesTableOrderingComposer,
          $$BusinessUnitTaxStatusesTableAnnotationComposer,
          $$BusinessUnitTaxStatusesTableCreateCompanionBuilder,
          $$BusinessUnitTaxStatusesTableUpdateCompanionBuilder,
          (
            BusinessUnitTaxStatusRow,
            BaseReferences<
              _$AppDatabase,
              $BusinessUnitTaxStatusesTable,
              BusinessUnitTaxStatusRow
            >,
          ),
          BusinessUnitTaxStatusRow,
          PrefetchHooks Function()
        > {
  $$BusinessUnitTaxStatusesTableTableManager(
    _$AppDatabase db,
    $BusinessUnitTaxStatusesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BusinessUnitTaxStatusesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BusinessUnitTaxStatusesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BusinessUnitTaxStatusesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<String> effectiveFrom = const Value.absent(),
                Value<String?> effectiveTo = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<String> statusCode = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BusinessUnitTaxStatusesCompanion(
                id: id,
                orgId: orgId,
                businessUnitId: businessUnitId,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                archivedAt: archivedAt,
                statusCode: statusCode,
                note: note,
                rowVersion: rowVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String businessUnitId,
                required String effectiveFrom,
                Value<String?> effectiveTo = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                required String statusCode,
                Value<String?> note = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BusinessUnitTaxStatusesCompanion.insert(
                id: id,
                orgId: orgId,
                businessUnitId: businessUnitId,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                archivedAt: archivedAt,
                statusCode: statusCode,
                note: note,
                rowVersion: rowVersion,
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

typedef $$BusinessUnitTaxStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BusinessUnitTaxStatusesTable,
      BusinessUnitTaxStatusRow,
      $$BusinessUnitTaxStatusesTableFilterComposer,
      $$BusinessUnitTaxStatusesTableOrderingComposer,
      $$BusinessUnitTaxStatusesTableAnnotationComposer,
      $$BusinessUnitTaxStatusesTableCreateCompanionBuilder,
      $$BusinessUnitTaxStatusesTableUpdateCompanionBuilder,
      (
        BusinessUnitTaxStatusRow,
        BaseReferences<
          _$AppDatabase,
          $BusinessUnitTaxStatusesTable,
          BusinessUnitTaxStatusRow
        >,
      ),
      BusinessUnitTaxStatusRow,
      PrefetchHooks Function()
    >;
typedef $$RevenueConfigSnapshotsTableCreateCompanionBuilder =
    RevenueConfigSnapshotsCompanion Function({
      required String userId,
      required String orgId,
      required String businessUnitId,
      required String status,
      Value<String> datasets,
      Value<String?> generation,
      Value<DateTime?> confirmedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RevenueConfigSnapshotsTableUpdateCompanionBuilder =
    RevenueConfigSnapshotsCompanion Function({
      Value<String> userId,
      Value<String> orgId,
      Value<String> businessUnitId,
      Value<String> status,
      Value<String> datasets,
      Value<String?> generation,
      Value<DateTime?> confirmedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RevenueConfigSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $RevenueConfigSnapshotsTable> {
  $$RevenueConfigSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datasets => $composableBuilder(
    column: $table.datasets,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RevenueConfigSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $RevenueConfigSnapshotsTable> {
  $$RevenueConfigSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datasets => $composableBuilder(
    column: $table.datasets,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RevenueConfigSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RevenueConfigSnapshotsTable> {
  $$RevenueConfigSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get businessUnitId => $composableBuilder(
    column: $table.businessUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get datasets =>
      $composableBuilder(column: $table.datasets, builder: (column) => column);

  GeneratedColumn<String> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RevenueConfigSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RevenueConfigSnapshotsTable,
          RevenueConfigSnapshot,
          $$RevenueConfigSnapshotsTableFilterComposer,
          $$RevenueConfigSnapshotsTableOrderingComposer,
          $$RevenueConfigSnapshotsTableAnnotationComposer,
          $$RevenueConfigSnapshotsTableCreateCompanionBuilder,
          $$RevenueConfigSnapshotsTableUpdateCompanionBuilder,
          (
            RevenueConfigSnapshot,
            BaseReferences<
              _$AppDatabase,
              $RevenueConfigSnapshotsTable,
              RevenueConfigSnapshot
            >,
          ),
          RevenueConfigSnapshot,
          PrefetchHooks Function()
        > {
  $$RevenueConfigSnapshotsTableTableManager(
    _$AppDatabase db,
    $RevenueConfigSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevenueConfigSnapshotsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RevenueConfigSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RevenueConfigSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> businessUnitId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> datasets = const Value.absent(),
                Value<String?> generation = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevenueConfigSnapshotsCompanion(
                userId: userId,
                orgId: orgId,
                businessUnitId: businessUnitId,
                status: status,
                datasets: datasets,
                generation: generation,
                confirmedAt: confirmedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String orgId,
                required String businessUnitId,
                required String status,
                Value<String> datasets = const Value.absent(),
                Value<String?> generation = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RevenueConfigSnapshotsCompanion.insert(
                userId: userId,
                orgId: orgId,
                businessUnitId: businessUnitId,
                status: status,
                datasets: datasets,
                generation: generation,
                confirmedAt: confirmedAt,
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

typedef $$RevenueConfigSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RevenueConfigSnapshotsTable,
      RevenueConfigSnapshot,
      $$RevenueConfigSnapshotsTableFilterComposer,
      $$RevenueConfigSnapshotsTableOrderingComposer,
      $$RevenueConfigSnapshotsTableAnnotationComposer,
      $$RevenueConfigSnapshotsTableCreateCompanionBuilder,
      $$RevenueConfigSnapshotsTableUpdateCompanionBuilder,
      (
        RevenueConfigSnapshot,
        BaseReferences<
          _$AppDatabase,
          $RevenueConfigSnapshotsTable,
          RevenueConfigSnapshot
        >,
      ),
      RevenueConfigSnapshot,
      PrefetchHooks Function()
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
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$ExpenseAllocationsTableTableManager get expenseAllocations =>
      $$ExpenseAllocationsTableTableManager(_db, _db.expenseAllocations);
  $$ExpensePeriodAllocationsTableTableManager get expensePeriodAllocations =>
      $$ExpensePeriodAllocationsTableTableManager(
        _db,
        _db.expensePeriodAllocations,
      );
  $$ExpenseAttachmentsTableTableManager get expenseAttachments =>
      $$ExpenseAttachmentsTableTableManager(_db, _db.expenseAttachments);
  $$RevenueEntriesTableTableManager get revenueEntries =>
      $$RevenueEntriesTableTableManager(_db, _db.revenueEntries);
  $$RevenueComponentsTableTableManager get revenueComponents =>
      $$RevenueComponentsTableTableManager(_db, _db.revenueComponents);
  $$RevenueValueBandsTableTableManager get revenueValueBands =>
      $$RevenueValueBandsTableTableManager(_db, _db.revenueValueBands);
  $$RevenueSupplySubtypesTableTableManager get revenueSupplySubtypes =>
      $$RevenueSupplySubtypesTableTableManager(_db, _db.revenueSupplySubtypes);
  $$BusinessUnitTaxStatusesTableTableManager get businessUnitTaxStatuses =>
      $$BusinessUnitTaxStatusesTableTableManager(
        _db,
        _db.businessUnitTaxStatuses,
      );
  $$RevenueConfigSnapshotsTableTableManager get revenueConfigSnapshots =>
      $$RevenueConfigSnapshotsTableTableManager(
        _db,
        _db.revenueConfigSnapshots,
      );
}
