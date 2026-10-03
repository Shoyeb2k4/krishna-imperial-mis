/// Phase 2 acceptance, executed inside the **real installed application** on a real
/// device, against the real `krishna-mis-dev` project, with the real development
/// identities.
///
/// Nothing here is a widget test: the app is assembled exactly as `main()` assembles it —
/// the encrypted local database, the platform key store, the Supabase client, the session
/// state machine, the router and both shells. The only thing supplied from outside is the
/// identity to sign in as, which arrives through `--dart-define-from-file` so no password
/// is ever typed on a command line, rendered on screen, or captured in a screenshot.
///
/// The run is split into phases because several of the rules under test only exist
/// *across* application restarts (session restoration, user switching, offline authority)
/// or need an administrative act in the middle that the signed-in user is by definition
/// not allowed to perform on themselves (revocation, deactivation). Each phase is one
/// `flutter test` invocation, which is one real process launch against the same installed
/// app and the same encrypted database.
///
///     flutter test integration_test/device_acceptance_test.dart -d <device> \
///       --flavor dev --dart-define-from-file=config/dev.json \
///       --dart-define-from-file=<scratch>/identities.defines.json \
///       --dart-define=PHASE=owner
///
/// Phases, in the order they are meant to run:
///
///   owner            sign in as the Owner; both properties, masters, vendors, tax, rename
///   restart          no sign-in at all — the session must come back on its own
///   signout          the account control ends the session
///   ccr-manager      a scoped Manager on the *same* installation as the Owner
///   data-entry       capability-gated UI, and the server refusing regardless
///   offline-cached   cached authority, marked stale, with the cache intact
///   offline-queued   a privileged mutation queued offline stays pending, never final
///   unverified       authenticated, never verified, no network — no access at all
///   revoked          D-048 through the app after the Owner takes a property away
///   conflict         a stale-version mutation is a Conflict, not a Rejection
///   propagate-a      client A: rename and archive, while client B is watching
///   propagate-b      client B: the change arrives; a stale intent conflicts
///   propagate-restore  put the development fixtures back
///   login-ux         keyboard, focus, obscured password, refusal wording
///   expense-simple   record a routine expense, queue it, receive its number
///   expense-offline  record with no network, restart, reconcile exactly once
///   expense-shared   a scoped manager receives their share and not the total
///   expense-refusals closed period, stale edit, and who may void
///   offline-transport  the Phase 2 addendum: the real transport made to fail, offline
///                    working, reconnect, authority-first, and reconciliation
///   d068-switch      signing out and switching users leaves no financial figure behind
///   d068-revoke      losing one property of two: partial purge, downgrade, retention
///   cross-period     the ₹60,000 May/June split, entered through the real UI
///   payment-accrual  a June salary paid in July is June's cost and July's cash
///   expense-edit     the D-072 edit surface: correct, D+7, D+8, and the version rule
///   expense-edit-shared  a scoped share of a shared bill is read-only, UI and server
///   expense-edit-offline  edit with no network, queue it, reconnect, reconcile
///   expense-edit-refused  a closed period and a withdrawn permission are Rejected
///   windows-ledger   filters, paging, selection, and the scoped detail caption
///   attachment-staging  a picked bill is staged, hashed, and never blocks the expense
///   attachment-upload   the bill reaches Storage, is registered, and is retried
///   attachment-scope    a scoped manager cannot retrieve a complete document's bill
///
/// Two-device propagation, Android ⇄ Windows, run in order against one server:
///   propagate-expense-a  Android records it and attaches a bill
///   propagate-expense-b  Windows sees the same document and corrects it
///   propagate-expense-c  Android sees the correction, and a stale edit conflicts
///   propagate-expense-d  Windows voids it
///   propagate-expense-e  Android sees VOIDED, with its evidence intact
///
/// Three phases need something to happen on the *host* while the phase is running — the
/// device's network taken away, a grant revoked, an account deactivated — because the
/// signed-in user is by definition not allowed to do any of those to themselves. The host
/// waits for the application process to appear on the device and then acts, and the phase
/// polls for the consequence rather than assuming a fixed delay:
///
///     after_app_starts.sh 30 net_off_later.sh 0     # offline
///     after_app_starts.sh 45 revoke_only.sh         # revoked
///     after_app_starts.sh 45 deactivate_only.sh     # deactivated
library;

import 'dart:convert';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/mobile_home_page.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/attachment_upload_worker.dart';
import 'package:krishna_mis/data/remote/supabase_attachment_store.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';
import 'package:krishna_mis/data/sync/expense_pull.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_pnl_drilldown_pages.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../test/support/money_layout.dart';
import '../test/support/owner_settlement_reference.dart';
import 'support/controllable_transport.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/features/export/export_centre_page.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_print.dart';
import 'package:krishna_mis/features/export/export_providers.dart';
import 'package:krishna_mis/features/export/export_share.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import '../test/support/pdf_text.dart';
import '../test/support/in_memory_secret_storage.dart';
import '../test/support/expense_ledger_workload.dart' as wl;
import 'package:krishna_mis/app/startup/startup_failure_app.dart';
import 'package:krishna_mis/app/startup/startup_runner.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/local/local_store_recovery.dart';
import 'package:sqlite3/sqlite3.dart' as sq;
import '../test/support/xlsx_reader.dart';
import 'support/pdf_inflate.dart';

const _phase = String.fromEnvironment('PHASE');

/// Identities, supplied by `--dart-define-from-file`. Empty in an ordinary run, which is
/// why every phase is skipped unless one is named.
const _identities = <String, String>{
  'giridhar@hki.com': String.fromEnvironment('PW_OWNER'),
  'ccr.manager@example.com': String.fromEnvironment('PW_CCR_MANAGER'),
  'hki.manager@example.com': String.fromEnvironment('PW_HKI_MANAGER'),
  'data.entry@example.com': String.fromEnvironment('PW_DATA_ENTRY'),
  'accountant@example.com': String.fromEnvironment('PW_ACCOUNTANT'),
  'unassigned@example.com': String.fromEnvironment('PW_UNASSIGNED'),
};

/// The host, acting as the Owner, over the ordinary public API.
///
/// A phase cannot revoke its own signed-in user's grant — that is the point of the rule
/// being tested — so something else has to. Phase 2 did it with shell scripts driven from
/// the build machine; this does the same work in-process, which removes a moving part
/// without changing what is being proven.
///
/// It is **not** a privileged back door. It holds no service-role key, signs in with a
/// development password from the same git-ignored file every other identity comes from,
/// and calls the same `SECURITY DEFINER` RPCs a client calls. It gets exactly the answers
/// the server would give anyone: the Owner may revoke a grant, and a manager may not.
/// Nothing here bypasses RLS, a capability check, a period lock or an audit row.
final class _AdminClient {
  const _AdminClient();

  static const _owner = 'giridhar@hki.com';

  Future<String> _token() async {
    final response = await http.post(
      Uri.parse('$_supabaseUrl/auth/v1/token?grant_type=password'),
      headers: {'apikey': _supabaseAnonKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': _owner, 'password': _identities[_owner]}),
    );
    if (response.statusCode != 200) {
      throw StateError('the acceptance Owner could not sign in to administer');
    }
    return jsonDecode(response.body)['access_token'] as String;
  }

  Future<Map<String, dynamic>> _rpc(
    String function,
    Map<String, dynamic> args,
  ) async {
    final response = await http.post(
      Uri.parse('$_supabaseUrl/rest/v1/rpc/$function'),
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer ${await _token()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(args),
    );
    if (response.statusCode >= 300) {
      throw StateError('$function refused: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {'result': decoded};
  }

  Future<List<dynamic>> _select(String table, String query) async {
    final response = await http.get(
      Uri.parse('$_supabaseUrl/rest/v1/$table?$query'),
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer ${await _token()}',
      },
    );
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<String> _userIdOf(String email) async {
    final rows = await _select('profiles', 'select=id&email=eq.$email');
    if (rows.isEmpty) throw StateError('no profile for $email');
    return (rows.first as Map<String, dynamic>)['id'] as String;
  }

  /// The live grant id for one person on one property, or null if there is none.
  ///
  /// `user_role_revoke` takes a **grant** id, not a (user, unit) pair — grants are the
  /// records, and revoking one is a statement about that record.
  Future<String?> _liveGrantId(String email, String unitId) async {
    final rows = await _select(
      'user_roles',
      'select=id&user_id=eq.${await _userIdOf(email)}'
          '&business_unit_id=eq.$unitId&revoked_at=is.null',
    );
    return rows.isEmpty
        ? null
        : (rows.first as Map<String, dynamic>)['id'] as String;
  }

  Future<void> grantScope(String email, String role, String unitCode) async {
    final unit = unitCode == 'CCR' ? _ccr : _hki;
    if (await _liveGrantId(email, unit) != null) return;
    await _rpc('user_role_grant', {
      'p_user_id': await _userIdOf(email),
      'p_role_code': role,
      'p_business_unit_id': unit,
      'p_mutation_id': const Uuid().v4(),
    });
  }

  Future<void> revokeScope(String email, String unitCode) async {
    final unit = unitCode == 'CCR' ? _ccr : _hki;
    final grantId = await _liveGrantId(email, unit);
    // The tear-down runs whether or not the phase reached the revocation itself, so
    // "there is nothing to revoke" is a normal outcome and not a failure.
    if (grantId == null) return;
    await _rpc('user_role_revoke', {
      'p_grant_id': grantId,
      'p_mutation_id': const Uuid().v4(),
    });
  }

  /// The spec's shared electricity bill, recorded by the Owner: ₹58,000 across both
  /// properties as ₹25,000 + ₹33,000.
  /// The canonical revenue document, as the server holds it.
  Future<Map<String, dynamic>> revenueDocument(String id) async {
    final rows = await _select('revenue_document', 'select=*&id=eq.$id');
    if (rows.isEmpty) throw StateError('no canonical revenue $id');
    return rows.first as Map<String, dynamic>;
  }

  /// The audit rows for one document, which is where "how many times was this applied"
  /// is durably answered. A queue snapshot is not: the worker pushes immediately after a
  /// save, so by the time a test looks the entry may legitimately be gone.
  Future<List<dynamic>> auditFor(String id) => _select(
    'audit_logs',
    'select=action,mutation_id&entity_id=eq.$id&order=occurred_at',
  );

  /// An intervening correction, made by somebody else while the device holds the old
  /// version. This is how a conflict is produced without a second physical device: the
  /// server is genuinely moved on, by an ordinary authorised caller over the public API.
  Future<void> correctRevenue(String id, int paise) async {
    final doc = await revenueDocument(id);
    final components = await _select(
      'revenue_component_detail',
      'select=id&revenue_entry_id=eq.$id',
    );
    await _rpc('revenue_update', {
      'p_id': id,
      'p_base_row_version': doc['row_version'],
      'p_business_date': doc['business_date'],
      'p_notes': doc['notes'],
      'p_components': [
        {
          'id': (components.first as Map<String, dynamic>)['id'],
          'entered_amount_minor': paise,
        },
      ],
      'p_mutation_id': const Uuid().v4(),
    });
  }

  Future<String> createSharedExpense({
    required String notes,
    String businessDate = '2026-06-15',
  }) async {
    final id = const Uuid().v4();
    await _rpc('expense_create', {
      'p_id': id,
      'p_business_date': businessDate,
      'p_total_minor': 5800000,
      'p_notes': notes,
      'p_allocations': [
        {
          'business_unit_id': _ccr,
          'department_id': _seedId('dept:CCR/FB'),
          'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
          'category_id': _kirana,
          'amount_minor': 2500000,
        },
        {
          'business_unit_id': _hki,
          'department_id': _seedId('dept:HKI/HKI_UTIL'),
          'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
          'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
          'amount_minor': 3300000,
        },
      ],
      'p_mutation_id': const Uuid().v4(),
    });
    return id;
  }

  /// ₹4,000 charged entirely to Crystal Canopy.
  Future<String> createCcrExpense({
    required String notes,
    String businessDate = '2026-06-15',
  }) async {
    final id = const Uuid().v4();
    await _rpc('expense_create', {
      'p_id': id,
      'p_business_date': businessDate,
      'p_total_minor': 400000,
      'p_notes': notes,
      'p_allocations': [
        {
          'business_unit_id': _ccr,
          'department_id': _seedId('dept:CCR/FB'),
          'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
          'category_id': _kirana,
          'amount_minor': 400000,
        },
      ],
      'p_mutation_id': const Uuid().v4(),
    });
    return id;
  }
}

const _admin = _AdminClient();

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// The Crystal Canopy grocery classification, as an allocation payload.
///
/// One literal rather than one per phase: it is the same four ids every time, and a
/// phase that mistypes one gets a foreign-key refusal that reads like a rule failing.
Map<String, Object?> get _ccrKirana => {
  'business_unit_id': _ccr,
  'department_id': _seedId('dept:CCR/FB'),
  'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
  'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
};

/// The seeded master ids, derived the same way the migration derives them.
String _seedId(String path) =>
    const Uuid().v5('d9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70', path);

final _ccr = _seedId('bu:CCR');
final _hki = _seedId('bu:HKI');
final _kirana = _seedId('cat:CCR/FB/FOOD_PROD/KIRANA');

/// Two safe leaf categories used by the two-client propagation phases, and put back by
/// `propagate-restore` afterwards.
final _paneer = _seedId('cat:CCR/FB/FOOD_PROD/PANEER');
final _milk = _seedId('cat:CCR/FB/FOOD_PROD/MILK_DAHI');
const _paneerOriginalName = 'Paneer / Dairy';
const _paneerRenamed = 'Paneer / Dairy (cosmetic)';

/// A fixed id, so the queued intent survives from one phase's process into the next.
const _queuedMutationId = '8c41b7d2-63ae-4f0b-9d55-2e7a1c4f8b60';

/// The acceptance transport. Constructed unconditionally and handed to `bootstrap`, but
/// only ever *taken* offline by the phase that is about being offline; every other phase
/// runs with it fully online, so it changes nothing for them.
final _transport = ControllableTransport();

/// The prefix every document an acceptance run creates carries in its notes.
///
/// The list below cannot do the job on its own, and that is not a detail: **each phase
/// is its own process launch**, so a list populated while `expense-shared` runs is empty
/// by the time `expense-cleanup` starts. The marker is what survives the process
/// boundary, and it is what the cleanup actually matches on.
///
/// It sits in the notes rather than in a column, because adding an `is_test` flag to
/// financial rows is precisely what D-066 refuses: a mutable "ignore me" marker on
/// financial data is a liability, and the honest identifiers are the ones already
/// recorded — the `@example.com` actors, the development project, and the reason text.
const _acceptanceMarker = 'Device acceptance';

/// Documents created by the phase currently running, for its own assertions.
///
/// Deliberately **not** the cleanup mechanism: see [_acceptanceMarker].
final List<String> _createdExpenses = [];

/// The one document the two-device phases pass between them.
///
/// Fixed, because **each phase is its own process launch on its own machine** — there is
/// no variable that survives from the Android run to the Windows one. The server is the
/// only thing both can see, so the id is agreed in advance and the document is looked up
/// rather than handed over. That is also what makes the assertions meaningful: "the same
/// expense" means the same client-generated UUID (D-008), not a document that merely
/// looks alike.
/// The two-device chain runs as five separate processes on two machines, so its legs
/// need a shared handle on one document.
///
/// It used to be a **fixed primary key**, which made the chain pass exactly once. Voiding
/// the leftover — which leg *a* dutifully did — does not free a primary key, and no client
/// role holds DELETE on a financial table, correctly (D-006). So the second run of the
/// chain died on `duplicate key value violates unique constraint "expenses_pkey"`, and a
/// phase that can only ever pass once is not a regression test.
///
/// The handle is now the marker in the document's notes, which is already how
/// `expense-cleanup` finds what a run created (D-071). Leg *a* creates a fresh UUID; the
/// later legs look up the newest open document carrying this marker.
const _twoDeviceMarker = '$_acceptanceMarker: two-device propagation';

/// The version Android last saw, parked on the server in the document's own reference
/// field so the conflict phase can submit a genuinely stale intent.
String _staleVersionMarker(int version) => 'seen-v$version';

/// A second fixed id, for work the *Owner* queues before a user switch.
const _ownerQueuedMutationId = 'b5d0e91a-7c34-4a68-8e2f-19b7d3c05a44';

/// On Windows the acceptance run keeps its database and session in its own folder, so it
/// never opens or replaces an installation somebody uses by hand (D-246). The folder is
/// stable across launches, because the restart and accumulated-database phases depend on
/// what an earlier launch left. Android reinstalls per run and uses the normal location.
Directory? _acceptanceDataDirectory() => Platform.isWindows
    ? Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}krishna_mis_acceptance',
      )
    : null;

void main() {
  // A tap that lands on nothing is a *warning* by default, and the test then fails much
  // later on whatever the tap was supposed to cause — which at a financial synchronisation
  // boundary reads exactly like a sync defect. It is not one: the usual cause is a route
  // still animating, whose `AbsorbPointer` swallows the pointer while the button is
  // findable and enabled. Make the miss fatal, so it is reported where it happens.
  WidgetController.hitTestWarningShouldBeFatal = true;

  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late BootstrapResult boot;

  setUpAll(() async {
    boot = await bootstrap(
      transport: _transport,
      appDataDirectory: _acceptanceDataDirectory(),
    );
  });

  // ── Driving the real application ──────────────────────────────────────────

  /// Builds the app exactly as `main()` does, and waits for start-up to settle.
  Future<void> launch(
    WidgetTester tester, {
    AttachmentSource? attachmentSource,
    List<Override> recorders = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Phase 7: recorders that wrap — never replace — the real Save As and print
          // paths, so a phase can read what the native dialog returned.
          ...recorders,
          if (attachmentSource != null)
            attachmentSourceProvider.overrideWithValue(attachmentSource),
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          mutationEndpointProvider.overrideWithValue(boot.mutationEndpoint),
          // `main()` supplies this too. Without it a pushed expense is marked done and
          // never learns its transaction number, which looks exactly like the server
          // failing to issue one.
          mutationReconcilerProvider.overrideWithValue(boot.mutationReconciler),
          // `main()` supplies these too. The acceptance must assemble the application
          // the same way `main()` does, or it is exercising a different application —
          // the attachment worker being absent here made a bill stay `staged` for ever
          // while the real build moved it on.
          expensePullProvider.overrideWithValue(boot.expensePull),
          // And this one: without it Review latest cannot re-read the sale, so a
          // conflict is unresolvable in the acceptance while being resolvable in the
          // shipped application. Exactly the drift the paragraph above describes,
          // arriving again — which is why the wiring test now compares this list
          // against `main()`'s rather than trusting either.
          revenueGatewayProvider.overrideWithValue(boot.revenueGateway),
          // Slice 10: opening a document from a report reads through this gateway.
          expenseGatewayProvider.overrideWithValue(boot.expenseGateway),
          reportingGatewayProvider.overrideWithValue(boot.reportingGateway),
          // OA-3: the settlement surface's owner pull. Without it the acceptance would
          // show "owner history not downloaded" for ever while the shipped build pulls it.
          ownerLedgerGatewayProvider.overrideWithValue(boot.ownerLedgerGateway),
          attachmentUploadWorkerProvider.overrideWithValue(
            boot.attachmentUploads,
          ),
          // D-346: staged bills live in the installation's own folder — here the
          // acceptance folder, as in `main()` it is the build's resolved one.
          localStorageLocationProvider.overrideWithValue(boot.storage),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
        child: KrishnaMisApp(shellKind: boot.shellKind),
      ),
    );
    await tester.pump();
  }

  /// Pumps until [condition] holds, or fails with a legible message.
  ///
  /// `pumpAndSettle` is unusable here: every screen that waits on the network shows a
  /// progress indicator, which never settles, and a real server takes real time.
  Future<void> pumpUntil(
    WidgetTester tester,
    String what,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 150));
    }
    fail('timed out waiting for: $what');
  }

  /// Taps [key] once it can genuinely receive a pointer.
  ///
  /// `enabled` and `present` are not the same thing as `hittable`: during a route
  /// transition the widget is in the tree, the button reports itself enabled, and the
  /// route's `AbsorbPointer` takes the pointer instead. `hitTestable()` matches only when
  /// a hit test at the widget's centre actually reaches it, which is the real condition.
  Future<void> tapWhenHittable(WidgetTester tester, Finder finder) async {
    await pumpUntil(
      tester,
      'the control to become hittable',
      () => finder.hitTestable().evaluate().isNotEmpty,
    );
    await tester.tap(finder.hitTestable());
  }

  bool visible(String text) => find.text(text).evaluate().isNotEmpty;

  /// A money figure as a person reads it. `MoneyText` places invisible break marks after
  /// digit-group commas (D-286), so a literal `textContaining('58,000')` can no longer
  /// match the paragraph that shows ₹58,000.00.
  Finder moneyShown(String figure) => find.byWidgetPredicate((widget) {
    final text = switch (widget) {
      Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
      RichText(:final text) => text.toPlainText(),
      _ => null,
    };
    return text != null &&
        text.replaceAll('​', '').replaceAll('⁠', '').contains(figure);
  });

  /// Named so it cannot be confused with the `contains` *matcher*: shadowing that was
  /// how an assertion about an outbox payload silently became an assertion about the
  /// screen.
  bool showsText(String text) =>
      find.textContaining(text).evaluate().isNotEmpty;

  /// Opens the account/masters area, which is "More" on a phone and "Masters" on Windows.
  Future<void> openSetUp(WidgetTester tester) async {
    final label = boot.shellKind.name == 'mobile' ? 'More' : 'Masters';
    await pumpUntil(tester, 'the $label destination', () => visible(label));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openHierarchy(WidgetTester tester) async {
    await openSetUp(tester);
    // Confirm we actually arrived. The Windows *Overview* placeholder names both
    // properties in its copy, so asserting "the other property is not on
    // screen" from the wrong page passes or fails for reasons that have nothing to do
    // with scope.
    await pumpUntil(
      tester,
      'the Masters surface',
      () => visible('Hierarchy'),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(find.text('Hierarchy').last);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> openSection(WidgetTester tester, String label) async {
    await openSetUp(tester);
    await pumpUntil(tester, 'the $label section', () => visible(label));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Signs out the way a user does: through the account control, confirming the dialog.
  Future<void> signOutThroughTheUi(WidgetTester tester) async {
    await openSetUp(tester);
    await pumpUntil(tester, 'the account control', () => visible('Sign out'));
    await tester.tap(find.text('Sign out').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await pumpUntil(
      tester,
      'the sign-in screen',
      () => find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
    );
  }

  /// Signs [email] in, ending any session already open on this installation first.
  ///
  /// Each test in a phase shares one process and one installation, exactly as a shared
  /// workstation does, so "already signed in as somebody else" is the normal case rather
  /// than an error.
  Future<void> signIn(WidgetTester tester, String email) async {
    // Wait for start-up to settle first. A restored session takes a round trip, and
    // deciding before it lands is how this helper used to sign in on top of somebody
    // else's open session.
    await pumpUntil(
      tester,
      'start-up to settle on either the sign-in screen or a shell',
      () =>
          find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty ||
          visible('SIGNED IN') ||
          visible('Home') ||
          visible('Overview'),
      timeout: const Duration(seconds: 60),
    );

    if (visible('SIGNED IN') || visible('Home') || visible('Overview')) {
      // The dedicated `signout` phase proves the control itself. Here the point is only
      // to reach a clean sign-in screen, so the session is ended through the same
      // notifier the control calls.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).signOut();
      await pumpUntil(
        tester,
        'the sign-in screen after signing the previous user out',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
      );
    }

    final password = _identities[email];
    expect(
      password,
      isNotNull,
      reason: 'no development identity compiled in for $email',
    );
    expect(password, isNotEmpty, reason: 'empty password define for $email');

    await pumpUntil(tester, 'the sign-in screen', () => visible('Sign in'));

    // The labels sit above the fields as their own Text widgets rather than as
    // `labelText`, so the fields are addressed by position: email, then password.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), email);
    await tester.pump();
    await tester.enterText(fields.at(1), password!);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    // A failed sign-in must fail the test here, with the message the user would see,
    // rather than 40 seconds later as "the shell never appeared".
    await tester.pump(const Duration(seconds: 3));
    final notice = find.textContaining('do not match');
    if (notice.evaluate().isNotEmpty) {
      fail(
        'sign-in refused for $email: ${(notice.evaluate().first.widget as Text).data}',
      );
    }
  }

  /// Finds widgets whose key is a `Key('<prefix>…')`.
  ///
  /// The split editor keys its fields by the *draft line's* generated id, so a test
  /// cannot name them in advance. Matching the stable prefix addresses them by role
  /// rather than by position, which is what keeps this from silently editing the wrong
  /// field the day another row is inserted above.
  Finder byKeyPrefix(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  /// The shell is only ever reached through a session the server vouched for.
  ///
  /// The budget is generous on purpose, and it is the *only* wait in this file that is.
  /// Reaching the shell means a real sign-in, `my_authority`, a full reference pull and
  /// the scope purge, against a live project, on a machine that is often compiling the
  /// next phase at the same time; measured in isolation it takes 24–34 seconds. Two
  /// phases in one long sequential batch exceeded 60 and passed on their own immediately
  /// afterwards. Widening a *start-up* budget removes a failure mode that says nothing
  /// about the product. No assertion about a financial outcome is given the same
  /// latitude — those wait for a durable consequence and fail if it does not arrive.
  Future<void> expectSignedIn(WidgetTester tester, String email) async {
    await pumpUntil(
      tester,
      'the application shell for $email',
      () => visible('SIGNED IN') || visible('Home') || visible('Overview'),
      timeout: const Duration(minutes: 3),
    );
  }

  // ── Phases ──────────────────────────────────────────────────

  group('owner', skip: _phase != 'owner', () {
    testWidgets('signs in, and the server states the whole company', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final store = AuthorityStore(boot.database);
      final owner = await store.ownerUserId();
      expect(owner, isNotNull, reason: 'authority must be cached per user');

      final snapshot = await store.loadFor(owner!);
      expect(snapshot, isNotNull);
      expect(
        snapshot!.holdsOrgWideGrant,
        isTrue,
        reason: 'only the Owner may hold an unscoped grant (D-025)',
      );
    });

    testWidgets('both properties arrive from the server', (tester) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(units.map((u) => u.id).toSet(), {_ccr, _hki});

      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'both business units on screen',
        () =>
            showsText('Crystal Canopy Rooftop') &&
            showsText('Hotel Krishna Imperial'),
      );
    });

    testWidgets('vendors and payment methods load', (tester) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final methods = await boot.database
          .select(boot.database.paymentMethods)
          .get();
      expect(methods, isNotEmpty, reason: 'organisation-global company data');

      await openSection(tester, 'Vendors');
      await pumpUntil(
        tester,
        'the vendors surface',
        () => showsText('Vendor') || showsText('vendor'),
      );
    });

    testWidgets('tax says no rule is configured, and invents none', (
      tester,
    ) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final rules = await boot.database
          .select(boot.database.revenueTaxRates)
          .get();
      expect(rules, isEmpty, reason: 'the development project has no tax rule');

      await openSection(tester, 'Tax rules');
      // The approved equivalent of "No rule configured": the screen says a rule is
      // absent, and says what that means for revenue, in two places.
      await pumpUntil(
        tester,
        'the no-rule state',
        () => showsText('No rule in force today'),
        timeout: const Duration(seconds: 60),
      );
      expect(showsText('No tax rule configured'), isTrue);
      expect(showsText('no tax extracted until one is set'), isTrue);

      // "No configured rule" and "a configured zero rate" are different facts.
      expect(showsText('5%'), isFalse);
      expect(showsText('18%'), isFalse);
      expect(showsText('0%'), isFalse);
      expect(showsText('exempt'), isFalse);
    });
  });

  group('session', skip: _phase != 'session', () {
    testWidgets('a fresh session controller restores without credentials', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // A second controller over the same dependencies is what a relaunch produces:
      // it reads the persisted session out of the platform-secure store and asks the
      // server again. Nothing is typed.
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);

      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();
      final restored = container.read(sessionProvider);
      expect(
        restored,
        isA<SessionReady>(),
        reason: 'the token in secure storage must survive a relaunch',
      );
      expect((restored as SessionReady).email, 'giridhar@hki.com');
    });
  });

  group('signout', skip: _phase != 'signout', () {
    testWidgets('the account control ends the session and keeps the queue', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued Before Sign Out'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );

      await openSetUp(tester);
      await pumpUntil(tester, 'the account control', () => visible('Sign out'));
      await tester.tap(find.text('Sign out').last);
      await tester.pump(const Duration(milliseconds: 600));
      expect(showsText('still waiting to reach the server'), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));

      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
      );

      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNull,
        reason: 'cached authority must not outlive the session that earned it',
      );
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.mutationId == _queuedMutationId),
        hasLength(1),
        reason: 'signing out never destroys unsent work',
      );
    });
  });

  // Steps 3, 10 and 14: the whole point of the user-switch rules, in one process on one
  // installation — Owner first, so the Hotel Krishna cache genuinely exists before the
  // Crystal Canopy Manager arrives.
  group('user-switch', skip: _phase != 'user-switch', () {
    testWidgets('Owner → CCR Manager: no cache and no authority is inherited', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final ownerUnits = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        ownerUnits.map((u) => u.id).toSet(),
        {_ccr, _hki},
        reason: 'the Owner really did cache both properties',
      );
      final ownerId = await AuthorityStore(boot.database).ownerUserId();
      expect(ownerId, isNotNull);

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _ownerQueuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': "Owner's Queued Work"},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
          actorUserId: ownerId,
        ),
        now: DateTime.now().toUtc(),
      );

      await signOutThroughTheUi(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      // 1. The previous user's protected hierarchy is gone.
      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        units.map((u) => u.id).toSet(),
        {_ccr},
        reason: "the Owner's Hotel Krishna data must not be browsable",
      );
      final departments = await boot.database
          .select(boot.database.departments)
          .get();
      expect(departments.every((d) => d.businessUnitId == _ccr), isTrue);

      // 2. The authority snapshot belongs to the new user, not the old one.
      final store = AuthorityStore(boot.database);
      final nowOwner = await store.ownerUserId();
      expect(nowOwner, isNot(ownerId));
      expect(
        await store.loadFor(ownerId!),
        isNull,
        reason: "one user's snapshot can never satisfy another's load",
      );
      final mine = await store.loadFor(nowOwner!);
      expect(mine!.holdsOrgWideGrant, isFalse);
      expect(mine.scopedUnits, {_ccr});

      // 3. The queue is preserved and still belongs to whoever queued it.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      final ownersEntry = queued.firstWhere(
        (q) => q.mutationId == _ownerQueuedMutationId,
      );
      expect(
        ownersEntry.actorUserId,
        ownerId,
        reason: 'D-050 — an outbox entry keeps its original actor',
      );
      expect(ownersEntry.actorUserId, isNot(nowOwner));

      // 4. The UI agrees with the data.
      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'Crystal Canopy alone',
        () => showsText('Crystal Canopy Rooftop'),
      );
      expect(showsText('Hotel Krishna Imperial'), isFalse);
      expect(
        visible('Administration'),
        isFalse,
        reason: 'no users.manage capability — and no role name was consulted',
      );
    });

    testWidgets('CCR Manager → HKI Manager: the swap is symmetric', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      expect(
        (await boot.database.select(boot.database.businessUnits).get())
            .map((u) => u.id)
            .toSet(),
        {_ccr},
      );

      await signOutThroughTheUi(tester);
      await signIn(tester, 'hki.manager@example.com');
      await expectSignedIn(tester, 'hki.manager@example.com');

      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        units.map((u) => u.id).toSet(),
        {_hki},
        reason: 'Crystal Canopy must not remain browsable to a Hotel manager',
      );

      final methods = await boot.database
          .select(boot.database.paymentMethods)
          .get();
      expect(
        methods,
        isNotEmpty,
        reason: 'company-wide reference data is not scoped (D-049)',
      );
    });
  });

  group('data-entry', skip: _phase != 'data-entry', () {
    testWidgets('sees permitted reference data and no master actions', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'data.entry@example.com');
      await expectSignedIn(tester, 'data.entry@example.com');

      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'their permitted hierarchy',
        () => showsText('Crystal Canopy Rooftop'),
      );

      expect(visible('Rename'), isFalse);
      expect(visible('Archive'), isFalse);
      expect(visible('Administration'), isFalse);
    });

    testWidgets('the server refuses the mutation anyway, in plain language', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'data.entry@example.com');
      await expectSignedIn(tester, 'data.entry@example.com');

      // Straight past the interface, exactly as a modified client would.
      final gateway = MasterGateway(Supabase.instance.client);
      final outcome = await gateway.rename(
        entityType: 'expense_category',
        entityId: _kirana,
        newName: 'Attempted By Data Entry',
        baseRowVersion: 1,
      );

      expect(
        outcome.isRefused,
        isTrue,
        reason: 'hiding a button has never been security',
      );
      final refusal = outcome.refusalOrNull!;
      expect(refusal.kind, RefusalKind.missingCapability);
      expect(refusal.message, 'You do not have permission to do this.');
      expect(refusal.message, isNot(contains('SQLSTATE')));
      expect(refusal.message, isNot(contains('permission denied')));
      expect(refusal.message, isNot(contains('42501')));
    });
  });

  // Steps 5, 6 and 14. The host takes the device's network away part-way through; the
  // test waits for that to happen rather than assuming it already has.
  group('offline', skip: _phase != 'offline', () {
    testWidgets('cached authority survives, marked stale, cache intact', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      final before = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(before.map((u) => u.id).toSet(), {_ccr});

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // Wait for the host to pull the network, then confirm the session degrades to
      // stale rather than either failing or pretending to be current.
      var state = container.read(sessionProvider);
      final deadline = DateTime.now().add(const Duration(seconds: 240));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        state = container.read(sessionProvider);
        if (state is SessionReady && state.isStale) break;
        await tester.pump(const Duration(seconds: 2));
      }

      expect(
        state,
        isA<SessionReady>(),
        reason: 'a verified user keeps their permitted workflows offline',
      );
      final ready = state as SessionReady;
      expect(
        ready.isStale,
        isTrue,
        reason: 'and is told the access is not fresh',
      );
      expect(ready.authority.userId, isNotNull);
      expect(
        ready.email,
        'ccr.manager@example.com',
        reason: 'the cached authority belongs to this user',
      );

      final after = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        after.map((u) => u.id).toSet(),
        {_ccr},
        reason: 'a network failure is not a statement of scope (D-048)',
      );

      // A privileged mutation queued offline is pending, never final.
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued While Offline'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );
      final status = await boot.outbox.statusOf(_queuedMutationId);
      expect(status, OutboxStatus.pending);
      expect(status!.userVisibleState, SyncState.pendingSync);
      expect(status.userVisibleState.isOnServer, isFalse);
    });

    testWidgets('a user who has never verified here gets nothing at all', (
      tester,
    ) async {
      // The exact precondition: a real authenticated session, an authority store with
      // nothing in it for this user, and no way to ask.
      await AuthorityStore(boot.database).clear();

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      final state = container.read(sessionProvider);
      expect(
        state,
        isA<AuthorityUnverified>(),
        reason: 'fails closed: authenticated is not authorised',
      );
      final blocked = state as AuthorityUnverified;
      expect(
        blocked.message,
        'Unable to verify your access. Connect to the internet and try again.',
      );
      expect(state.grantsAccess, isFalse);
      expect(
        state.principal.grants,
        isEmpty,
        reason: 'no fallback Owner, no fallback Manager, no guessed capability',
      );
    });
  });

  // Step 7: the full D-048 scenario, driven through the app. The host revokes the scope
  // while the device is offline and restores the network afterwards.
  group('revoked', skip: _phase != 'revoked', () {
    testWidgets('authority first, then purge, then a terminal refusal', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      expect(
        (await boot.database.select(boot.database.businessUnits).get())
            .map((u) => u.id)
            .toSet(),
        {_ccr},
        reason: 'Crystal Canopy is cached while the scope is held',
      );

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued While Authorised'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );
      expect(
        await boot.outbox.statusOf(_queuedMutationId),
        OutboxStatus.pending,
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // The host is meanwhile revoking the Crystal Canopy grant as the Owner. Refresh
      // authority — which is what happens on reconnect — until the server says the
      // scope is gone. Authority is asked *before* anything privileged is pushed.
      var purged = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        final state = container.read(sessionProvider);
        if (state is SessionReady &&
            !state.isStale &&
            state.authority.scopedUnits.isEmpty) {
          purged = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(
        purged,
        isTrue,
        reason: 'the server must positively confirm the scope was removed',
      );

      // The server-owned Crystal Canopy cache goes…
      expect(
        await boot.database.select(boot.database.businessUnits).get(),
        isEmpty,
      );
      expect(
        await boot.database.select(boot.database.departments).get(),
        isEmpty,
      );
      // …organisation-global rows stay…
      expect(
        await boot.database.select(boot.database.paymentMethods).get(),
        isNotEmpty,
        reason: 'a payment method is company data, not property data (D-049)',
      );
      // …and the queue is untouched.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.mutationId == _queuedMutationId),
        hasLength(1),
      );

      // The queued mutation now reaches the server on current authority.
      final gateway = MasterGateway(Supabase.instance.client);
      final outcome = await gateway.rename(
        entityType: 'expense_category',
        entityId: _kirana,
        newName: 'Queued While Authorised',
        baseRowVersion: 1,
        mutationId: _queuedMutationId,
      );
      expect(
        outcome.isRefused,
        isTrue,
        reason: 'authority at delivery time wins',
      );
      final refusal = outcome.refusalOrNull!;
      expect(refusal.kind.isAuthorityRefusal, isTrue);
      expect(refusal.kind.isAutomaticallyRetryable, isFalse);
      expect(refusal.message, isNot(contains('SQLSTATE')));

      await boot.outbox.updateStatus(
        _queuedMutationId,
        status: OutboxStatus.rejected,
        lastError: refusal.message,
      );
      final status = await boot.outbox.statusOf(_queuedMutationId);
      expect(status, OutboxStatus.rejected);
      expect(status!.userVisibleState, SyncState.rejected);
      expect(status.isAutomaticallyRetryable, isFalse);

      final rows = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        rows.singleWhere((r) => r.mutationId == _queuedMutationId).payload,
        contains('Queued While Authorised'),
        reason: 'the refused attempt stays inspectable',
      );

      // And the property is gone from the interface.
      await openHierarchy(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(showsText('Crystal Canopy Rooftop'), isFalse);
    });
  });

  // Step 13: a deactivated account loses access at the next refresh, and never falls
  // back to the authority it had cached.
  group('deactivated', skip: _phase != 'deactivated', () {
    testWidgets('a revoked account expires rather than continuing on cache', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');
      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNotNull,
        reason: 'authority was cached while the account was live',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // The host deactivates the account through the Owner's own administration path.
      var expired = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        if (container.read(sessionProvider) is SessionExpired) {
          expired = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }

      expect(
        expired,
        isTrue,
        reason:
            'the server declining to treat somebody as an actor is a statement',
      );
      final state = container.read(sessionProvider);
      expect(state.grantsAccess, isFalse);
      expect(state.principal.grants, isEmpty);
      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNull,
        reason: 'stale authority must not be left behind to fall back on',
      );
    });
  });

  group('conflict', skip: _phase != 'conflict', () {
    testWidgets('a stale base version is a Conflict, never a Rejection', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);
      final department = _seedId('dept:CCR/FB');
      final startVersion = await _currentVersion(department);

      // Move the server on by one version, the way a second authenticated client would.
      final first = await gateway.rename(
        entityType: 'department',
        entityId: department,
        newName: 'F&B / Kitchen',
        baseRowVersion: startVersion,
        acknowledged: true,
      );
      expect(
        first.isOk,
        isTrue,
        reason: 'the Owner may rename: ${first.refusalOrNull?.message}',
      );
      final moved = first.valueOrNull!['row_version'] as int;
      expect(moved, greaterThan(startVersion));

      // Now submit a *new* intent based on the version this client still held.
      final stale = await gateway.rename(
        entityType: 'department',
        entityId: department,
        newName: 'Stale Intent',
        baseRowVersion: startVersion,
        acknowledged: true,
      );

      expect(stale.isRefused, isTrue);
      final refusal = stale.refusalOrNull!;
      expect(
        refusal.kind,
        RefusalKind.versionConflict,
        reason: 'KM003 — resolvable by a person, not a terminal rejection',
      );
      expect(
        refusal.kind.isAuthorityRefusal,
        isFalse,
        reason: 'a conflict is about the record, not about permission',
      );
      expect(refusal.message, isNot(contains('SQLSTATE')));

      // The canonical server state is the one that was applied, not the stale one.
      final row = await Supabase.instance.client
          .from('departments')
          .select('name,row_version')
          .eq('id', department)
          .single();
      expect(row['name'], isNot('Stale Intent'));
      expect(row['row_version'], moved);

      // And the two states are distinguishable to a user: a conflict is not a rejection.
      expect(OutboxStatus.conflict.userVisibleState, SyncState.conflict);
      expect(OutboxStatus.rejected.userVisibleState, SyncState.rejected);
      expect(
        SyncState.conflict.label,
        isNot(SyncState.rejected.label),
        reason: 'Rejected and Conflict must read as different states',
      );
    });
  });
  // Step 11. Two real clients, one on each platform, against one server. `propagate-b`
  // signs in and holds the current label, then waits; `propagate-a` runs on the other
  // platform part-way through that wait and makes the change; `propagate-b` refreshes and
  // watches it arrive.
  // Step 9's login checks. Keyboard-first, because the Windows build is a finance
  // workstation and a form that can only be driven by mouse is a defect there.
  group('login-ux', skip: _phase != 'login-ux', () {
    testWidgets('the password is obscured until the user asks to see it', (
      tester,
    ) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      TextField passwordField() =>
          tester.widgetList<TextField>(find.byType(TextField)).last;

      expect(passwordField().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(passwordField().obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(passwordField().obscureText, isTrue);
    });

    testWidgets('Tab and Shift-Tab move between the fields, visibly', (
      tester,
    ) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      final fields = find.byType(TextFormField);
      await tester.tap(fields.at(0));
      await tester.pump();
      final email = Focus.of(tester.element(fields.at(0)));
      expect(email.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(fields.at(1))).hasFocus,
        isTrue,
        reason: 'Tab must reach the password field',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        Focus.of(tester.element(fields.at(0))).hasFocus,
        isTrue,
        reason: 'Shift-Tab must come back',
      );
    });

    testWidgets('a wrong password is refused in plain language, and Enter '
        'submits the form', (tester) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'giridhar@hki.com');
      await tester.pump();
      await tester.enterText(fields.at(1), 'not-the-password');
      await tester.pump();

      // Enter in the password field submits, rather than doing nothing.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(
        tester,
        'the refusal notice',
        () => showsText('do not match'),
        timeout: const Duration(seconds: 45),
      );

      expect(
        showsText('That email address and password do not match an account.'),
        isTrue,
      );
      expect(showsText('SQLSTATE'), isFalse);
      expect(showsText('invalid_grant'), isFalse);
      expect(showsText('400'), isFalse);
      expect(
        find.widgetWithText(FilledButton, 'Sign in'),
        findsOneWidget,
        reason: 'a refusal leaves the user on the form, able to try again',
      );
    });
  });

  // ── Phase 2 acceptance addendum: the offline transport path ────────────────
  //
  // The one gap the Phase 2 report recorded as NOT TESTED. It runs on either platform,
  // and its point is Windows: the real executable, with its network genuinely failing at
  // the transport, driven end to end through going offline, working offline, coming back,
  // and reconciling under whatever authority the server states at that moment.
  //
  // Nothing here fakes an answer. `ControllableTransport` throws the same SocketException
  // the platform throws for an unreachable host, from inside the Supabase client's own
  // send, so every decision downstream is made by the real code for the real reason.
  group('offline-transport', skip: _phase != 'offline-transport', () {
    testWidgets('offline, then back, with authority first and no false success', (
      tester,
    ) async {
      // 1 · A previously verified user signs in online.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final db = boot.database;
      final store = AuthorityStore(db);
      final userId = await store.ownerUserId();
      expect(userId, isNotNull);

      // Fresh ids each run. A fixed one would be *replayed* by the server on the second
      // run rather than applied — the idempotency guarantee working exactly as designed,
      // and a guarantee this phase is not about.
      final acceptedId = const Uuid().v4();
      final refusedId = const Uuid().v4();

      // 2 · Authority and permitted reference data are cached.
      final cachedAuthority = await store.loadFor(userId!);
      expect(cachedAuthority, isNotNull);
      expect(cachedAuthority!.holdsOrgWideGrant, isTrue);
      final unitsBefore = await db.select(db.businessUnits).get();
      final departmentsBefore = await db.select(db.departments).get();
      final categoriesBefore = await db.select(db.expenseCategories).get();
      expect(unitsBefore, isNotEmpty);
      expect(departmentsBefore, isNotEmpty);
      expect(categoriesBefore, isNotEmpty);

      // The running application's own container, not a parallel one. Everything below
      // is therefore asserted about the interface the user is looking at.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      expect(container.read(sessionProvider), isA<SessionReady>());

      // Two intents queued while authorised and online: one the Owner may do, and one
      // the server will refuse for a reason that is not a version conflict.
      //
      // The fixture is normalised first, so the phase can be re-run: renaming a record to
      // the name it already has is not a change, and the server correctly declines to
      // move its version for it — which would make the assertion below fail for a reason
      // that has nothing to do with the transport.
      final gateway = MasterGateway(Supabase.instance.client);
      var current = await _row('expense_categories', _paneer);
      if (current['name'] != _paneerOriginalName) {
        final reset = await gateway.rename(
          entityType: 'expense_category',
          entityId: _paneer,
          newName: _paneerOriginalName,
          baseRowVersion: current['row_version'] as int,
          acknowledged: true,
        );
        expect(reset.isOk, isTrue, reason: '${reset.refusalOrNull?.message}');
        current = await _row('expense_categories', _paneer);
      }
      final paneer = current;
      final section = _seedId('sec:CCR/FB/FOOD_PROD');
      final sectionRow = await _row('sections', section);

      // 3 · The network goes away. From here nothing reaches the server.
      _transport.online = false;

      // 4 · Permitted cached data remains usable — reads never touch the network.
      expect(
        (await db.select(db.businessUnits).get()).length,
        unitsBefore.length,
      );
      expect(
        (await db.select(db.expenseCategories).get()).length,
        categoriesBefore.length,
      );

      // 6 · Authority refresh becomes *unavailable*, never Confirmed with no grants.
      final refresh = await boot.session!.authority.refresh();
      expect(
        refresh,
        isA<AuthorityUnavailable>(),
        reason: 'a failed request is not a statement that the user has nothing',
      );
      expect(
        (refresh as AuthorityUnavailable).reason,
        AuthorityUnavailableReason.offline,
      );
      expect(
        _transport.refusedWhileOffline,
        isNotEmpty,
        reason: 'the application really did try to reach the server',
      );

      await container.read(sessionProvider.notifier).refreshAuthority();
      final offlineState = container.read(sessionProvider);
      expect(offlineState, isA<SessionReady>());
      expect(
        (offlineState as SessionReady).isStale,
        isTrue,
        reason: 'access is shown as last verified, not as current',
      );
      expect(offlineState.authority.userId, userId);

      // 5 · And the interface says so, in the words a user reads.
      await tester.pump(const Duration(milliseconds: 400));
      await openSetUp(tester);
      await pumpUntil(
        tester,
        'the offline marker',
        () => showsText('Using last verified access'),
      );

      // 7 · Nothing was purged. A network failure is not a statement of scope.
      expect(
        (await db.select(db.businessUnits).get()).length,
        unitsBefore.length,
      );
      expect(
        (await db.select(db.departments).get()).length,
        departmentsBefore.length,
      );
      expect(await store.loadFor(userId), isNotNull);

      // 8 · Privileged mutations created offline are queued, and only queued.
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: acceptedId,
          entityType: 'expense_category',
          entityId: _paneer,
          op: MutationOp.update,
          payload: {'name': _paneerRenamed, 'acknowledged': true},
          baseRowVersion: paneer['row_version'] as int,
          createdAt: DateTime.now().toUtc(),
          actorUserId: userId,
        ),
        now: DateTime.now().toUtc(),
      );
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: refusedId,
          entityType: 'section',
          entityId: section,
          op: MutationOp.archive,
          payload: const {},
          baseRowVersion: sectionRow['row_version'] as int,
          createdAt: DateTime.now().toUtc(),
          actorUserId: userId,
        ),
        now: DateTime.now().toUtc(),
      );

      for (final id in [acceptedId, refusedId]) {
        final status = await boot.outbox.statusOf(id);
        expect(status, OutboxStatus.pending);
        // 9 · Never shown as server-approved.
        expect(status!.userVisibleState, SyncState.pendingSync);
        expect(status.userVisibleState.isOnServer, isFalse);
        expect(status, isNot(OutboxStatus.done));
      }

      // A push attempted while offline must change nothing and claim nothing.
      final engineOffline = container.read(syncEngineProvider);
      expect(engineOffline, isNotNull, reason: 'the push worker exists');
      expect(
        await boot.outbox.dueEntries(now: DateTime.now(), actorUserId: userId),
        hasLength(2),
        reason: 'both intents are due, and both belong to this user',
      );
      expect(
        engineOffline!.actorUserId,
        userId,
        reason: 'the worker sends only the signed-in user work',
      );
      final offlineReport = await engineOffline.pushOnce();
      expect(offlineReport.applied, 0);
      expect(offlineReport.rejected, 0);
      expect(
        offlineReport.transientFailures,
        2,
        reason: 'unreachable is transient — never a refusal, never a success',
      );
      for (final id in [acceptedId, refusedId]) {
        final status = await boot.outbox.statusOf(id);
        expect(status!.isAutomaticallyRetryable, isTrue);
        expect(status.userVisibleState.isOnServer, isFalse);
      }

      // 10 · Connectivity returns.
      _transport.online = true;

      // 11 · Authority is refreshed *before* anything privileged is pushed.
      await container.read(sessionProvider.notifier).refreshAuthority();
      final backOnline = container.read(sessionProvider);
      expect(backOnline, isA<SessionReady>());
      expect(
        (backOnline as SessionReady).isStale,
        isFalse,
        reason: 'reconnecting re-establishes current authority first',
      );

      // 12 · Only then does the queue go, under that current authority.
      //
      // The failed attempts are in backoff, which is the real product behaviour and not
      // something to step over: the engine's clock is genuine, so the test waits for it
      // rather than pretending time has passed.
      final engine = container.read(syncEngineProvider);
      final ready = DateTime.now().add(const Duration(seconds: 90));
      var due = <PendingMutation>[];
      while (DateTime.now().isBefore(ready)) {
        due = await boot.outbox.dueEntries(
          now: DateTime.now(),
          actorUserId: userId,
        );
        if (due.length == 2) break;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        due,
        hasLength(2),
        reason: 'both entries become due again once their backoff elapses',
      );

      final report = await engine!.pushOnce();
      expect(report.attempted, 2);

      // 13 · The permitted mutation reconciles: applied, versioned, marked synced.
      final accepted = await boot.outbox.statusOf(acceptedId);
      expect(accepted, OutboxStatus.done);
      expect(accepted!.userVisibleState, SyncState.synced);
      expect(accepted.userVisibleState.isOnServer, isTrue);
      final server = await _row('expense_categories', _paneer);
      expect(server['name'], _paneerRenamed);
      expect(
        server['row_version'],
        greaterThan(paneer['row_version'] as int),
        reason: 'the server moved the version, and exactly once',
      );

      // 14 · The refused one is Rejected — terminal — and never Conflict.
      final refused = await boot.outbox.statusOf(refusedId);
      expect(refused, OutboxStatus.rejected);
      expect(refused!.userVisibleState, SyncState.rejected);
      expect(
        refused,
        isNot(OutboxStatus.conflict),
        reason:
            'the record did not move — the server declined the act itself, and '
            'telling the user somebody edited it would be a lie',
      );
      expect(refused.isAutomaticallyRetryable, isFalse);
      expect(
        SyncState.rejected.label,
        isNot(SyncState.conflict.label),
        reason: 'the two states must read differently to a user',
      );

      // The attempt stays inspectable, with the server's own reason on it.
      final rows = await db.select(db.syncOutbox).get();
      final row = rows.singleWhere((r) => r.mutationId == refusedId);
      expect(row.lastError, isNotNull);
      expect(row.lastError, isNot(contains('SQLSTATE')));

      // A second push must not resurrect either of them.
      final again = await engine.pushOnce();
      expect(again.attempted, 0, reason: 'neither is due any more');

      // Leave the development fixture as it was found.
      final applied = await _row('expense_categories', _paneer);
      final restored = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: _paneerOriginalName,
        baseRowVersion: applied['row_version'] as int,
        acknowledged: true,
      );
      expect(
        restored.isOk,
        isTrue,
        reason: '${restored.refusalOrNull?.message}',
      );
      expect(
        (await _row('expense_categories', _paneer))['name'],
        _paneerOriginalName,
      );
      expect((await _row('sections', section))['archived_at'], isNull);
    });
  });

  // ── Phase 3: the expense engine, on the real device ────────────────────────
  //
  // These drive the shipped screens against `krishna-mis-dev`. What is asserted is what a
  // manager would see and what the server actually holds — never an internal call that
  // the interface does not make.

  /// Records an expense through the real entry screen, and returns its local id.
  /// Opens the expense entry screen the way a user does, on either shell.
  ///
  /// Extracted from [recordExpense] so a phase that needs to *stop part way* — to open
  /// the period split, or to fill in payment details — drives the same navigation the
  /// routine path drives, rather than a second copy of it that could drift.
  Future<void> openExpenseEntry(WidgetTester tester) async {
    if (boot.shellKind.name == 'mobile') {
      await pumpUntil(
        tester,
        'the add button',
        () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('quick-add-expense')));
    } else {
      await pumpUntil(
        tester,
        'the Transactions destination',
        () => visible('Transactions'),
      );
      await tester.tap(find.text('Transactions').last);
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the add-expense action',
        () => find.byKey(const Key('add-expense')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('add-expense')));
    }
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the expense entry screen',
      () => find.byKey(const Key('expense-amount')).evaluate().isNotEmpty,
    );
  }

  /// Walks the classification picker down the hierarchy, one rung at a time.
  Future<void> classify(WidgetTester tester, List<String> rungs) async {
    // The entry form is a lazy list. On a phone, typing the notes inside More details
    // scrolls the form down far enough that the "Charged to" row above is no longer built,
    // so it cannot be found until the form is scrolled back up (Galaxy A06, Slice 8).
    const summary = Key('classification-summary');
    if (find.byKey(summary).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(summary),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.ensureVisible(find.byKey(summary));
    await tester.pump(const Duration(milliseconds: 300));
    await tapWhenHittable(tester, find.byKey(summary));
    await tester.pump(const Duration(milliseconds: 600));
    for (final rung in rungs) {
      await pumpUntil(tester, 'the option "$rung"', () => visible(rung));
      await tester.tap(find.text(rung).last);
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  /// Presses Save and waits for exactly one new local row, or says what the screen said.
  Future<String> tapSaveAndAwaitRow(WidgetTester tester) async {
    // The id the local row will carry, read before saving so the assertions afterwards
    // can find it without guessing.
    final before = (await boot.database.select(boot.database.expenses).get())
        .map((e) => e.id)
        .toSet();

    await tapWhenHittable(tester, find.byKey(const Key('save-expense')));

    // The save is a transaction against an encrypted database on a phone; it takes as
    // long as it takes. Poll rather than guess at a duration.
    var created = <ExpenseRow>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));

      // If the screen is saying why it could not save, that is the useful failure —
      // "no row appeared" is not.
      final notice = find.textContaining('was not saved');
      if (notice.evaluate().isNotEmpty) {
        fail(
          'the save was refused on screen: '
          '${(notice.evaluate().first.widget as Text).data}',
        );
      }

      created = (await boot.database.select(boot.database.expenses).get())
          .where((e) => !before.contains(e.id))
          .toList();
      if (created.isNotEmpty) break;
    }

    if (created.isEmpty) {
      // Say what the screen is actually showing, so this reports the real problem
      // rather than "no row appeared".
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .where((t) => t.trim().isNotEmpty)
          .take(25)
          .join(' | ');
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      fail(
        'no expense was recorded. Outbox holds ${queued.length} entries. '
        'On screen: $texts',
      );
    }
    return created.single.id;
  }

  /// Pushes whatever is queued and waits for the row to learn its number.

  /// Whether the Save control is currently pressable.
  ///
  /// The distinction matters to more than one phase: a document that does not reconcile
  /// is not saveable, and the screen expresses that by *disabling* the control rather
  /// than by accepting the tap and complaining afterwards.
  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('save-expense')))
          .onPressed !=
      null;

  /// Every formatted money string currently on screen.
  ///
  /// Reads what a manager reads, including the Indian digit grouping, rather than the
  /// integer behind it (`₹12,36,420`, never `₹1,236,420` — spec §20).
  List<String> moneyTextsOnScreen(WidgetTester tester) => find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((t) => t.contains('₹'))
      .toList();

  /// Opens the detail surface for [expenseId] and waits for it.
  ///
  /// Both shells reach it the same way in the end — a ledger row — but the ledger is a
  /// destination on Windows and a tab on Android, so the navigation differs and the
  /// assertions afterwards do not.
  Future<void> openExpenseDetail(WidgetTester tester, String expenseId) async {
    if (boot.shellKind.name == 'mobile') {
      await pumpUntil(
        tester,
        'the Transactions tab',
        () => visible('Transactions'),
      );
      await tester.tap(find.text('Transactions').last);
    } else {
      await pumpUntil(
        tester,
        'the Transactions destination',
        () => visible('Transactions'),
      );
      await tester.tap(find.text('Transactions').last);
    }
    await tester.pump(const Duration(milliseconds: 900));

    final expense = await ExpenseRepository(boot.database).load(expenseId);
    final reference = expense!.row.txnNumber ?? expenseId.substring(0, 8);
    // The ledger is a cached read model, invalidated by this application whenever it
    // saves, edits or voids. A transaction number issued later by the background sync
    // worker arrives in the data layer, where no provider can be reached, so the list can
    // legitimately be a moment behind — hence a wait rather than a single look.
    Future<void> waitFor(Duration window) async {
      final until = DateTime.now().add(window);
      while (DateTime.now().isBefore(until) && !showsText(reference)) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    await waitFor(const Duration(seconds: 10));

    if (!showsText(reference)) {
      // The ledger is a cached read model. The application invalidates it when *it*
      // saves, edits or voids; rows that arrive another way — a pull issued by this
      // phase, or a transaction number written by this phase's own sync engine rather
      // than the app's — leave the cache correct-but-stale, and a `FutureProvider` is
      // not re-run merely by navigating back to it.
      //
      // So the cache is refreshed explicitly. This is the test telling the app to
      // re-read data the *test* wrote behind it; it does not relax any assertion, and
      // every security claim below is still made against what the application renders.
      // The underlying limitation — a pull does not refresh the ledger — is recorded in
      // PROJECT_STATUS rather than papered over here.
      final container =
          ProviderScope.containerOf(tester.element(find.byType(KrishnaMisApp)))
            ..invalidate(filteredExpensesProvider)
            ..invalidate(recentExpensesProvider);
      container.invalidate(expenseDetailProvider(expenseId));
      await tester.pump(const Duration(seconds: 1));
      await waitFor(const Duration(seconds: 25));
    }
    if (!showsText(reference)) {
      final rows = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .where((t) => t.contains('KI-EXP') || t.contains('₹'))
          .take(20)
          .join(' | ');
      fail('the ledger never listed $reference. It shows: $rows');
    }
    await tester.tap(find.textContaining(reference).first);
    await tester.pump(const Duration(milliseconds: 900));

    // Confirm it actually arrived. Almost every assertion made against a detail surface
    // is about something being *absent*, and an absent control is indistinguishable
    // from a screen that never opened — so a navigation that quietly failed would make
    // those assertions pass while proving nothing.
    final arrived = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(arrived)) {
      if (find.byKey(const Key('amount-label')).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 300));
    }

    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .take(30)
        .join(' | ');
    fail(
      'tapping $reference did not open the expense detail. On screen: $texts',
    );
  }

  /// Pushes the outbox until [expenseId] reaches [expected], or gives up saying what it
  /// actually reached.
  Future<SyncState> pushUntilSettled(
    WidgetTester tester,
    String expenseId, {
    required Set<SyncState> expected,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final repository = ExpenseRepository(boot.database);
    final engine = SyncEngine(
      outbox: boot.outbox,
      endpoint: boot.mutationEndpoint!,
      reconciler: boot.mutationReconciler,
      actorUserId: (await AuthorityStore(boot.database).ownerUserId())!,
    );

    var state = SyncState.pendingSync;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await engine.pushOnce();
      state = (await repository.load(expenseId))!.syncState;
      if (expected.contains(state)) return state;
      await tester.pump(const Duration(seconds: 2));
    }
    // Say what the queue actually holds. "It did not sync" is not a diagnosis, and the
    // outbox has the server's own reason written on it.
    final entries = (await boot.outbox.allEntries())
        .where((e) => e.entityId == expenseId)
        .map(
          (e) =>
              '${e.op}/${e.status} attempts=${e.attemptCount} '
              'base=${e.baseRowVersion} err=${e.lastError}',
        )
        .join(' · ');
    fail(
      'expense $expenseId settled at ${state.name}, expected one of '
      '${expected.map((s) => s.name).join(", ")}. Outbox: $entries',
    );
  }

  /// Scrolls [key] into view if it is not already built, then taps it.
  ///
  /// The entry screen grows as a document does — opening a split adds rows above the
  /// optional-details section — so a control that is on screen for a routine expense is
  /// below the fold for a split one. A plain `tap` there fails with "found 0 widgets",
  /// which reads like the control is missing rather than merely out of view.
  /// Opens the optional-details section, and does nothing if it is already open.
  ///
  /// Tapping the `ExpansionTile` itself is wrong twice over. Its render box spans the
  /// whole tile, so once the section is expanded the centre of that box is somewhere in
  /// the body rather than on the header — the tap misses, and used to do so silently.
  /// And on an **edit** draft the section often opens by itself, because the document
  /// already carries a vendor or notes; a tap then *collapses* it, hiding the very fields
  /// the test is about.
  ///
  /// So: check whether it is already open, scroll it into view if the phone's form has it
  /// below the fold, and tap the header's own title rather than the tile.
  Future<void> openMoreDetails(WidgetTester tester) async {
    if (find.byKey(const Key('expense-notes')).evaluate().isNotEmpty) return;

    const tile = Key('more-details');
    if (find.byKey(tile).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(tile),
        200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.ensureVisible(find.byKey(tile));
    await tester.pump(const Duration(milliseconds: 300));

    final header = find.descendant(
      of: find.byKey(tile),
      matching: find.text('More details'),
    );
    await tapWhenHittable(tester, header);
    await pumpUntil(
      tester,
      'the optional details to open',
      () => find.byKey(const Key('expense-notes')).evaluate().isNotEmpty,
    );
  }

  Future<void> revealAndTap(WidgetTester tester, Key key) async {
    if (find.byKey(key).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(key),
        200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.ensureVisible(find.byKey(key));
    await tester.pump(const Duration(milliseconds: 300));
    await tapWhenHittable(tester, find.byKey(key));
  }

  /// The raw text currently in each accounting-period amount field, in screen order.
  ///
  /// These are inputs, not labels, so the figure lives in the field's controller rather
  /// than in a `Text` — reading the rendered money strings finds the totals and misses
  /// the very numbers the split is about.
  List<String> periodAmountsOnScreen(WidgetTester tester) => find
      .descendant(
        of: byKeyPrefix('period-amount-'),
        matching: find.byType(TextField),
      )
      .evaluate()
      .map((e) => (e.widget as TextField).controller?.text ?? '')
      .toList();

  /// The money string rendered inside the widget carrying [key].
  String amountShownFor(WidgetTester tester, Key key) {
    final texts = find
        .descendant(of: find.byKey(key), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((t) => t.contains('₹'));
    if (texts.isEmpty) {
      final self = find.byKey(key).evaluate();
      if (self.isNotEmpty && self.first.widget is Text) {
        return (self.first.widget as Text).data ?? '';
      }
      fail('no money text under $key');
    }
    return texts.first;
  }

  /// Sets a Material date field to [isoDate].
  ///
  /// The control opens `showDatePicker`, so this drives the real dialog rather than
  /// writing to the draft behind it — the point of a device acceptance is that the path
  /// a user takes works. It prefers the picker's **input mode**, because typing a date
  /// is stable regardless of which month the calendar happens to open on; if that
  /// toggle is not offered it falls back to stepping the calendar and tapping the day.
  Future<void> setDateField(
    WidgetTester tester,
    Key field,
    String isoDate,
  ) async {
    final target = DateTime.parse(isoDate);

    await tester.tap(find.byKey(field));
    await tester.pump(const Duration(milliseconds: 900));
    await pumpUntil(
      tester,
      'the date picker dialog',
      () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
    );

    // Scoped to the dialog. The entry screen behind it has its own edit affordance on
    // the business-date row, and an unscoped `byIcon` finds that one first — which taps
    // the row underneath the barrier instead of switching the picker to input mode.
    Finder inDialog(Finder matching) =>
        find.descendant(of: find.byType(DatePickerDialog), matching: matching);

    var entryToggle = inDialog(find.byIcon(Icons.edit_outlined));
    if (entryToggle.evaluate().isEmpty) {
      entryToggle = inDialog(find.byIcon(Icons.edit));
    }

    if (entryToggle.evaluate().isNotEmpty) {
      await tester.tap(entryToggle.first);
      await tester.pump(const Duration(milliseconds: 700));

      await pumpUntil(
        tester,
        'the picker s text field after switching to input mode',
        () => inDialog(find.byType(TextField)).evaluate().isNotEmpty,
      );
      final input = inDialog(find.byType(TextField));
      expect(
        input,
        findsWidgets,
        reason: 'the picker offered input mode but no field appeared',
      );
      // The dialog's own hint states the order it expects, so it is read rather than
      // assumed — a locale change must not silently enter the wrong date.
      final decoration = tester.widget<TextField>(input.first).decoration;
      final hint = (decoration?.hintText ?? 'mm/dd/yyyy').toLowerCase();
      final typed = hint.startsWith('dd')
          ? '${_two(target.day)}/${_two(target.month)}/${target.year}'
          : '${_two(target.month)}/${_two(target.day)}/${target.year}';

      await tester.enterText(input.first, typed);
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      // Calendar mode: step to the right month, then tap the day.
      final now = DateTime.now();
      var months = (target.year - now.year) * 12 + (target.month - now.month);
      final forward = months > 0;
      final arrow = inDialog(
        find.byIcon(forward ? Icons.chevron_right : Icons.chevron_left),
      );
      for (var i = 0; i < months.abs(); i++) {
        await tester.tap(arrow.first);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.tap(inDialog(find.text('${target.day}')).first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    await pumpUntil(
      tester,
      'the picker s OK action',
      () => inDialog(find.text('OK')).evaluate().isNotEmpty,
    );
    await tester.tap(inDialog(find.text('OK')).first);
    await tester.pump(const Duration(milliseconds: 800));
  }

  /// Marks the draft paid, on [isoDate], with the first payment method offered.
  ///
  /// `paid` requires both a date and a method (spec §5.4), and the form enforces that
  /// pairing — so this sets both or the document would not be saveable.
  Future<void> markPaidOn(WidgetTester tester, String isoDate) async {
    await pumpUntil(
      tester,
      'the payment status control',
      () => visible('Paid'),
    );
    await tester.ensureVisible(find.text('Paid').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Paid').last);
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the payment method control',
      () => find.byKey(const Key('payment-method')).evaluate().isNotEmpty,
    );
    await revealAndTap(tester, const Key('payment-method'));
    await tester.pump(const Duration(milliseconds: 700));
    await pumpUntil(
      tester,
      'a payment method to choose',
      () => visible('Cash'),
    );
    await tester.tap(find.text('Cash').last);
    await tester.pump(const Duration(milliseconds: 600));

    await pumpUntil(
      tester,
      'the payment date control',
      () => find.byKey(const Key('payment-date')).evaluate().isNotEmpty,
    );
    await setDateField(tester, const Key('payment-date'), isoDate);
  }

  /// Taps Save and waits for the local row, returning its id.
  Future<String> saveExpense(WidgetTester tester) async {
    await pumpUntil(
      tester,
      'Save to become available',
      () => saveEnabled(tester),
    );
    return tapSaveAndAwaitRow(tester);
  }

  /// Records an expense through the real UI with one synthetic bill attached.
  Future<String> recordExpenseWithBill(
    WidgetTester tester,
    _SyntheticAttachmentSource source, {
    required String amount,
  }) async {
    await openExpenseEntry(tester);
    await tester.enterText(find.byKey(const Key('expense-amount')), amount);
    await tester.pump(const Duration(milliseconds: 300));
    await classify(tester, const [
      'Crystal Canopy Rooftop',
      'F&B / Kitchen',
      'Food Production',
      'Kirana & Pulses',
    ]);

    await openMoreDetails(tester);
    await tester.pump(const Duration(milliseconds: 800));

    final intake = boot.shellKind.name == 'mobile'
        ? AttachmentIntake.gallery
        : AttachmentIntake.file;
    await pumpUntil(
      tester,
      'the ${intake.name} attachment control',
      () => find.byKey(Key('attach-${intake.name}')).evaluate().isNotEmpty,
    );
    await revealAndTap(tester, Key('attach-${intake.name}'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('attachment-refusal')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('expense-notes')),
      '$_acceptanceMarker: attachment upload',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await openMoreDetails(tester);
    await tester.pump(const Duration(milliseconds: 500));

    return saveExpense(tester);
  }

  /// Presses Save on an **edit** and waits for the intent to be queued.
  ///
  /// An edit produces no new row — that is the whole point of it — so the create
  /// helper's success condition ("one row appeared") can never be met and fails with a
  /// message about a record that was never supposed to exist. The durable consequence of
  /// an edit is an `update` intent in the outbox, written in the same transaction as the
  /// local change, so that is what this waits for.
  Future<void> saveEditedExpense(WidgetTester tester, String expenseId) async {
    await pumpUntil(
      tester,
      'Save to become available',
      () => saveEnabled(tester),
    );
    await tapWhenHittable(tester, find.byKey(const Key('save-expense')));

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));

      final refusal = find.textContaining('was not saved');
      if (refusal.evaluate().isNotEmpty) {
        fail(
          'the edit was refused on screen: '
          '${(refusal.evaluate().first.widget as Text).data}',
        );
      }

      final queued = await boot.outbox.allEntries();
      if (queued.any((q) => q.entityId == expenseId && q.op == 'update')) {
        return;
      }
    }

    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .take(25)
        .join(' | ');
    fail('no update intent was queued for $expenseId. On screen: $texts');
  }

  Future<String> recordExpense(
    WidgetTester tester, {
    required String amount,
    required List<String> classification,
    String notes = 'routine entry',
  }) async {
    await openExpenseEntry(tester);

    await tester.enterText(find.byKey(const Key('expense-amount')), amount);
    await tester.pump(const Duration(milliseconds: 300));

    // Every document a run creates says so, in its notes.
    //
    // Without this the cleanup phase cannot find what the UI phases made: phases are
    // separate process launches, so an in-memory list of created ids is empty by the
    // time cleanup starts. Typing it through the real field also exercises the
    // progressive-disclosure section on the way past, which is where notes live
    // (spec §18 — accrual and metadata fields stay out of the fast path).
    await openMoreDetails(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntil(
      tester,
      'the notes field inside More details',
      () => find.byKey(const Key('expense-notes')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('expense-notes')),
      '$_acceptanceMarker: $notes',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await openMoreDetails(tester);
    await tester.pump(const Duration(milliseconds: 500));

    await classify(tester, classification);

    await pumpUntil(
      tester,
      'Save to become available',
      () => saveEnabled(tester),
    );
    return tapSaveAndAwaitRow(tester);
  }

  Future<void> syncAndAwaitNumber(
    WidgetTester tester,
    String expenseId, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await container.read(syncEngineProvider)?.pushOnce();
      final row = await ExpenseRepository(boot.database).load(expenseId);
      if (row?.row.txnNumber != null) return;
      await tester.pump(const Duration(seconds: 2));
    }
    fail('the expense never received a transaction number');
  }

  group('expense-simple', skip: _phase != 'expense-simple', () {
    testWidgets('a routine expense is recorded, queued and numbered', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpense(
        tester,
        amount: '500',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Vegetables & Fruits',
        ],
      );

      final repository = ExpenseRepository(boot.database);
      var saved = await repository.load(id);

      // One expense, one allocation, one derived contribution — the routine shape.
      expect(saved!.allocations, hasLength(1));
      expect(saved.periodContributions, hasLength(1));
      expect(saved.periodContributions.single.isDerived, isTrue);
      expect(saved.visibleAmount, Money.fromRupees(500));
      expect(saved.row.visibility, 'complete');

      // Queued in the same transaction as the document. Whether it has *already* been
      // delivered by the time this line runs is a race the product wins on a fast
      // connection, so the assertion is about the queue entry existing rather than
      // about the number still being absent. The deterministic "never fabricated
      // locally" proof lives in `expense-offline`, where no number can arrive at all.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.entityId == id),
        hasLength(1),
        reason: 'saved and unqueued must be impossible',
      );
      expect(queued.firstWhere((q) => q.entityId == id).op, 'create');

      await syncAndAwaitNumber(tester, id);
      saved = await repository.load(id);

      // The number came from the server, and the identity never moved.
      expect(saved!.row.txnNumber, startsWith('KI-EXP-'));
      expect(ExpenseNumber.tryParse(saved.row.txnNumber!), isNotNull);
      expect(saved.row.financialYear, isNotNull);
      expect(saved.syncState, SyncState.synced);
      expect(saved.row.rowVersion, greaterThan(1));
      expect(
        saved.row.id,
        id,
        reason: 'the client-generated id is the identity, start to finish',
      );

      _createdExpenses.add(id);
    });
  });

  group('expense-offline', skip: _phase != 'expense-offline', () {
    testWidgets('recorded with no network, survives a restart, then reconciles once', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // The network goes away. Everything below is the shipped code deciding for the
      // shipped reason — only the cable is simulated (D-058).
      _transport.online = false;

      final id = await recordExpense(
        tester,
        amount: '750',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Kirana & Pulses',
        ],
      );

      final repository = ExpenseRepository(boot.database);
      var saved = await repository.load(id);
      expect(
        saved,
        isNotNull,
        reason: 'the save must succeed with no network at all',
      );
      expect(saved!.syncState.isOnServer, isFalse);
      expect(saved.row.txnNumber, isNull);

      // A push while offline changes nothing and claims nothing.
      //
      // What is asserted is the **durable consequence**, not the return value of this
      // particular call. The shipped application runs its own sync worker and the save
      // wakes it; whichever of the two reaches the queue first, the product's promise
      // is identical — nothing applied, the intent still queued, no number invented on
      // the device. An earlier version asserted `transientFailures == 1`, which is a
      // claim that *this* call did the work: `pushOnce` returns an empty report both
      // when nothing is due and when a cycle is already running, so the real worker
      // won the race and the assertion failed against correct behaviour. Found by the
      // first device run of this phase.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      final offlinePush = await container.read(syncEngineProvider)!.pushOnce();
      expect(
        offlinePush.applied,
        0,
        reason: 'nothing can be applied with no network',
      );
      expect(
        offlinePush.rejected,
        0,
        reason: 'an unreachable server is never a refusal (D-059)',
      );

      // Something attempted delivery and failed transiently. Polled, because the
      // worker may be mid-cycle: the assertion is that the queue *reaches* this
      // state, not which caller drove it there.
      late SyncOutboxRow entry;
      final deadlineOffline = DateTime.now().add(const Duration(seconds: 30));
      while (true) {
        entry = (await boot.database.select(boot.database.syncOutbox).get())
            .firstWhere((q) => q.entityId == id);
        if (entry.attemptCount > 0) break;
        if (!DateTime.now().isBefore(deadlineOffline)) break;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        entry.attemptCount,
        greaterThan(0),
        reason: 'the offline attempt is recorded, not silently skipped',
      );
      expect(
        entry.status,
        isNot(OutboxStatus.done.name),
        reason: 'an unreachable server must never mark an intent delivered',
      );
      expect(
        entry.status,
        isNot(OutboxStatus.rejected.name),
        reason: 'unknown is not refused — D-048 §1, D-059',
      );
      expect(
        (await repository.load(id))!.row.txnNumber,
        isNull,
        reason: 'a transaction number is only ever issued by the server',
      );

      // "Restart": the database is closed and reopened, which is what an app kill
      // looks like from the data's point of view.
      await boot.database.close();
      final reopened = await bootstrap(
        transport: _transport,
        appDataDirectory: _acceptanceDataDirectory(),
      );
      final afterRestart = ExpenseRepository(reopened.database);
      saved = await afterRestart.load(id);
      expect(saved, isNotNull, reason: 'the expense survives being killed');
      expect(saved!.syncState, isNot(SyncState.synced));
      final queued = await reopened.database
          .select(reopened.database.syncOutbox)
          .get();
      expect(
        queued.where((q) => q.entityId == id),
        hasLength(1),
        reason: 'and so does its queued intent',
      );

      // And it is still attributed to the person who queued it. An anonymous queue is
      // how one user's financial intent gets pushed under another's session (D-050).
      expect(
        queued.firstWhere((q) => q.entityId == id).actorUserId,
        saved.row.createdBy,
        reason: 'the queued intent belongs to the actor who recorded it',
      );

      // Back online: one push, one server record, one reconciled local row.
      _transport.online = true;
      final engine = SyncEngine(
        outbox: reopened.outbox,
        endpoint: reopened.mutationEndpoint!,
        reconciler: reopened.mutationReconciler,
        actorUserId: saved.row.createdBy,
      );

      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await engine.pushOnce();
        final row = await afterRestart.load(id);
        if (row?.row.txnNumber != null) break;
        await tester.pump(const Duration(seconds: 2));
      }

      saved = await afterRestart.load(id);
      expect(saved!.row.txnNumber, startsWith('KI-EXP-'));
      expect(saved.syncState, SyncState.synced);
      expect(
        (await reopened.database.select(reopened.database.expenses).get())
            .where((e) => e.id == id),
        hasLength(1),
        reason: 'exactly one local record',
      );

      _createdExpenses.add(id);
      await reopened.database.close();
    });
  });

  group('expense-shared', skip: _phase != 'expense-shared', () {
    testWidgets('a scoped manager receives their share and not the total', (
      tester,
    ) async {
      // The Owner records the shared bill through the server, then a scoped manager
      // syncs it and the local database is inspected.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = const Uuid().v4();
      final gateway = ExpenseGateway(Supabase.instance.client);
      final created = await gateway.create(
        arguments: {
          'p_id': id,
          'p_business_date': '2026-06-15',
          'p_total_minor': 5800000,
          'p_notes': '$_acceptanceMarker: shared electricity',
          'p_allocations': [
            {
              'business_unit_id': _ccr,
              'department_id': _seedId('dept:CCR/FB'),
              'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
              'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
              'amount_minor': 2500000,
            },
            {
              'business_unit_id': _hki,
              'department_id': _seedId('dept:HKI/HKI_UTIL'),
              'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
              'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
              'amount_minor': 3300000,
            },
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(created.isOk, isTrue, reason: '${created.refusalOrNull?.message}');
      _createdExpenses.add(id);

      // The Owner's own device holds the whole document.
      final pull = ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(id);
      var local = await ExpenseRepository(boot.database).load(id);
      expect(local!.row.visibility, 'complete');
      expect(local.row.documentTotalMinor, 5800000);
      expect(local.allocations, hasLength(2));

      // Now the Crystal Canopy manager, on the same installation.
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(id);

      local = await ExpenseRepository(boot.database).load(id);
      expect(local!.row.visibility, 'scoped');
      expect(local.visibleAmount, Money.fromRupees(25000));
      expect(
        local.row.documentTotalMinor,
        isNull,
        reason: '₹58,000 − ₹25,000 is Hotel Krishna s ₹33,000',
      );
      expect(local.allocations, hasLength(1));
      expect(local.allocations.single.businessUnitId, _ccr);

      // And the raw amounts on this device contain neither forbidden figure.
      final amounts = [
        ...(await boot.database.select(boot.database.expenses).get()).expand(
          (r) => [r.documentTotalMinor, r.visibleAmountMinor],
        ),
        ...(await boot.database.select(boot.database.expenseAllocations).get())
            .map((r) => r.amountMinor),
        ...(await boot.database
                .select(boot.database.expensePeriodAllocations)
                .get())
            .map((r) => r.amountMinor),
      ];
      expect(amounts, isNot(contains(3300000)));
      expect(amounts, isNot(contains(5800000)));

      // The interface says so too, in words.
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('expense-refusals', skip: _phase != 'expense-refusals', () {
    testWidgets('closed period, revoked permission, conflict and void', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final client = Supabase.instance.client;
      final gateway = ExpenseGateway(client);
      final ccrKirana = {
        'business_unit_id': _ccr,
        'department_id': _seedId('dept:CCR/FB'),
        'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
        'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
      };

      // ── A closed period refuses, and says the true reason ──────────────
      await client.rpc<dynamic>(
        'period_close',
        params: {'p_period_key': '2026-03', 'p_business_unit_id': _ccr},
      );
      final closed = await gateway.create(
        arguments: {
          'p_id': const Uuid().v4(),
          'p_business_date': '2026-03-10',
          'p_total_minor': 1000,
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 1000},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(closed.isRefused, isTrue);
      expect(closed.refusalOrNull!.kind, RefusalKind.periodClosed);
      expect(
        closed.refusalOrNull!.kind,
        isNot(RefusalKind.versionConflict),
        reason: 'a closed period is never dressed up as a conflict',
      );
      expect(closed.refusalOrNull!.message, isNot(contains('SQLSTATE')));
      await client.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_period_key': '2026-03',
          'p_business_unit_id': _ccr,
          'p_reason': 'Device acceptance: restoring the fixture',
        },
      );

      // ── A stale edit is a Conflict, not a refusal ──────────────────────
      final conflictId = const Uuid().v4();
      final made = await gateway.create(
        arguments: {
          'p_id': conflictId,
          'p_business_date': '2026-06-15',
          'p_total_minor': 4200,
          'p_notes': '$_acceptanceMarker: stale-edit conflict',
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 4200},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(made.isOk, isTrue, reason: '${made.refusalOrNull?.message}');
      _createdExpenses.add(conflictId);

      final stale = await gateway.update(
        arguments: {
          'p_id': conflictId,
          'p_business_date': '2026-06-15',
          'p_total_minor': 4300,
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 4300},
          ],
        },
        baseRowVersion: 1, // the server holds 2
        mutationId: const Uuid().v4(),
      );
      expect(stale.isRefused, isTrue);
      expect(stale.refusalOrNull!.kind, RefusalKind.versionConflict);

      // ── Void: refused for a manager, permitted for an accountant ───────
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      final managerVoid = await ExpenseGateway(Supabase.instance.client)
          .voidExpense(
            expenseId: conflictId,
            baseRowVersion: 2,
            reason: 'Device acceptance: should be refused',
            mutationId: const Uuid().v4(),
          );
      expect(managerVoid.isRefused, isTrue);
      expect(
        managerVoid.refusalOrNull!.kind,
        RefusalKind.missingCapability,
        reason: 'a Manager cannot void — it is not in the bundle',
      );

      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');
      final accountantVoid = await ExpenseGateway(Supabase.instance.client)
          .voidExpense(
            expenseId: conflictId,
            baseRowVersion: 2,
            reason: 'Device acceptance: correcting a duplicate',
            mutationId: const Uuid().v4(),
          );
      expect(
        accountantVoid.isOk,
        isTrue,
        reason: '${accountantVoid.refusalOrNull?.message}',
      );
    });
  });

  // ── D-072 · the expense edit surface ───────────────────────────────────────
  //
  // Until this slice the client had no way to issue an edit at all: the server RPC and
  // its seven-day window were implemented and proven, and nothing in `lib/` could reach
  // them. These phases exercise the path that was missing, on the real applications.

  group('expense-edit', skip: _phase != 'expense-edit', () {
    testWidgets('a correction keeps the identity and moves the version', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // A routine expense, accepted by the server, is where every edit starts.
      final id = await recordExpense(
        tester,
        amount: '500',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Vegetables & Fruits',
        ],
        notes: 'edit acceptance',
      );
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final repository = ExpenseRepository(boot.database);
      final before = await repository.load(id);
      final numberBefore = before!.row.txnNumber;
      final versionBefore = before.row.rowVersion;
      expect(numberBefore, startsWith('KI-EXP-'));

      // Through the real detail surface, not through the repository.
      await openExpenseDetail(tester, id);
      await pumpUntil(
        tester,
        'the Edit control',
        () => find.byKey(const Key('edit-expense')).evaluate().isNotEmpty,
      );
      await revealAndTap(tester, const Key('edit-expense'));
      await tester.pump(const Duration(milliseconds: 900));

      await pumpUntil(
        tester,
        'the edit form, populated',
        () => find.byKey(const Key('expense-amount')).evaluate().isNotEmpty,
      );
      expect(
        visible('Edit expense'),
        isTrue,
        reason: 'the same screen, saying which mode it is in',
      );
      expect(
        moneyTextsOnScreen(tester).any((t) => t.contains('500')),
        isTrue,
        reason: 'the form opens on the document s current values',
      );

      await tester.enterText(find.byKey(const Key('expense-amount')), '875');
      await tester.pump(const Duration(milliseconds: 400));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 700));
      await pumpUntil(
        tester,
        'the reference field',
        () => find.byKey(const Key('expense-reference')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('expense-reference')),
        'INV-EDITED-1',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await saveEditedExpense(tester, id);

      // Locally: one document, the new figure, an update queued.
      final localAfterSave = await repository.load(id);
      expect(localAfterSave!.documentTotal, Money.fromRupees(875));
      expect(localAfterSave.row.referenceNumber, 'INV-EDITED-1');
      // Deliberately not "still pending". The application pushes as soon as it saves,
      // and on a fast connection the edit can be delivered before this line runs — a
      // race the product wins. What must be true either way is that the intent was
      // written durably in the same transaction as the change, which is asserted next.
      final queued = await boot.outbox.allEntries();
      expect(
        queued.where((q) => q.entityId == id && q.op == 'update'),
        hasLength(1),
        reason: 'the local edit and its intent are one transaction',
      );
      expect(
        queued
            .singleWhere((q) => q.entityId == id && q.op == 'update')
            .baseRowVersion,
        versionBefore,
        reason: 'the version the user was looking at, carried to submission',
      );

      // On the server: accepted, same identity, same number, a higher version.
      final settled = await pushUntilSettled(
        tester,
        id,
        expected: {SyncState.synced},
      );
      expect(settled, SyncState.synced);

      final after = await repository.load(id);
      expect(after!.row.id, id, reason: 'the same expense, corrected');
      expect(
        after.row.txnNumber,
        numberBefore,
        reason: 'a correction does not renumber the document',
      );
      expect(
        after.row.rowVersion,
        greaterThan(versionBefore),
        reason:
            'the server advanced the version it will judge the next edit against',
      );
      expect(after.documentTotal, Money.fromRupees(875));
      expect(
        (await boot.database.select(boot.database.expenses).get()).where(
          (e) => e.id == id,
        ),
        hasLength(1),
        reason: 'exactly one local record, never a duplicate',
      );
    });

    testWidgets('D+7 is accepted and D+8 is refused, at the server', (
      tester,
    ) async {
      // The window is the server's rule and it is measured under the property's own
      // business date (D-067). These two go through the real gateway rather than the
      // form, because the *form* cannot offer an eight-day-old document to a user who
      // has no beyond-window capability — which is itself asserted below.
      // The documents are created **by the identity that will edit them**.
      // `expense.edit.own` means own transactions, so a manager editing the Owner's
      // document is refused for a reason that has nothing to do with the edit window —
      // which is what the first version of this phase actually measured.
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      final gateway = ExpenseGateway(Supabase.instance.client);

      // The **property's** business date, not the IST wall-clock date. D-067's whole
      // point is that the two differ, and this phase proved it on itself: run after
      // midnight IST but before the 05:00 cut-off, a document dated eight wall-clock
      // days ago is only seven trading days old, and the server correctly accepted the
      // edit this phase expected it to refuse. The date is now derived the way the
      // server derives it, from the same instant.
      final propertyToday = BusinessDate.fromInstant(
        DateTime.now().toUtc(),
        timeZoneId: 'Asia/Kolkata',
        cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
      );

      Future<String> createDatedDaysAgo(int days) async {
        final date = propertyToday.addDays(-days);
        final id = const Uuid().v4();
        final created = await gateway.create(
          arguments: {
            'p_id': id,
            'p_business_date': date.iso,
            'p_total_minor': 120000,
            'p_notes': '$_acceptanceMarker: edit window D+$days',
            'p_allocations': [
              {..._ccrKirana, 'amount_minor': 120000},
            ],
          },
          mutationId: const Uuid().v4(),
        );
        expect(
          created.isOk,
          isTrue,
          reason: 'setup failed: ${created.refusalOrNull?.message}',
        );
        _createdExpenses.add(id);
        return id;
      }

      final sevenDaysOld = await createDatedDaysAgo(7);
      final eightDaysOld = await createDatedDaysAgo(8);

      // The same manager edits them. They hold `expense.edit.own` and **not**
      // `transaction.correct.beyond_window`, which is what makes the window the thing
      // being measured rather than a capability difference.
      final scoped = gateway;

      // The version is read, never assumed: the server advances it while writing the
      // allocations, so a hard-coded 1 is a conflict rather than a window test.
      final sevenRow = await _expenseRow(sevenDaysOld);
      final atSeven = await scoped.update(
        arguments: {
          'p_id': sevenDaysOld,
          'p_business_date': sevenRow['business_date'],
          'p_total_minor': 130000,
          'p_notes': '$_acceptanceMarker: D+7 edited',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 130000},
          ],
        },
        baseRowVersion: sevenRow['row_version'] as int,
        mutationId: const Uuid().v4(),
      );
      expect(
        atSeven.isOk,
        isTrue,
        reason:
            'D+7 is inside the window (D-065): ${atSeven.refusalOrNull?.message}',
      );

      final eightRow = await _expenseRow(eightDaysOld);
      final atEight = await scoped.update(
        arguments: {
          'p_id': eightDaysOld,
          'p_business_date': eightRow['business_date'],
          'p_total_minor': 130000,
          'p_notes': '$_acceptanceMarker: D+8 edited',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 130000},
          ],
        },
        baseRowVersion: eightRow['row_version'] as int,
        mutationId: const Uuid().v4(),
      );
      expect(atEight.isRefused, isTrue, reason: 'D+8 is outside the window');
      expect(
        atEight.refusalOrNull!.kind,
        RefusalKind.editWindowExpired,
        reason: 'the KM021 case, branched on by kind rather than by string',
      );
      expect(
        atEight.refusalOrNull!.message,
        isNot(contains('SQLSTATE')),
        reason: 'no database text ever reaches a user',
      );

      // And an Accountant, who holds the beyond-window capability, may still correct it
      // while the period is open.
      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');
      final beyondRow = await _expenseRow(eightDaysOld);
      final beyond = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': eightDaysOld,
          'p_business_date': beyondRow['business_date'],
          'p_total_minor': 140000,
          'p_notes': '$_acceptanceMarker: D+8 corrected beyond window',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 140000},
          ],
        },
        baseRowVersion: beyondRow['row_version'] as int,
        mutationId: const Uuid().v4(),
      );
      expect(
        beyond.isOk,
        isTrue,
        reason:
            'transaction.correct.beyond_window lifts the age rule and nothing else: '
            '${beyond.refusalOrNull?.message}',
      );
    });

    testWidgets('a stale edit is a Conflict, and nothing is overwritten', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpense(
        tester,
        amount: '640',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Vegetables & Fruits',
        ],
        notes: 'stale edit acceptance',
      );
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final repository = ExpenseRepository(boot.database);
      final loaded = await repository.load(id);
      final staleVersion = loaded!.row.rowVersion;

      // Somebody else corrects it first — the server is now ahead of this device.
      final elsewhere = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': id,
          'p_business_date': loaded.row.businessDate,
          'p_total_minor': 99900,
          'p_notes': '$_acceptanceMarker: corrected by someone else',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 99900},
          ],
        },
        baseRowVersion: staleVersion,
        mutationId: const Uuid().v4(),
      );
      expect(elsewhere.isOk, isTrue);

      // This device still holds the old version and submits against it.
      final held = (await repository.load(id))!;
      await repository.updateLocally(
        ExpenseDocument(
          id: id,
          orgId: held.row.orgId,
          businessDate: BusinessDate.tryParse(held.row.businessDate)!,
          businessDateSource: BusinessDateSource.derived,
          total: Money.fromRupees(777),
          allocations: [
            ExpenseAllocation.wholePeriod(
              id: held.allocations.single.id,
              businessUnitId: _ccr,
              departmentId: _seedId('dept:CCR/FB'),
              sectionId: _seedId('sec:CCR/FB/FOOD_PROD'),
              categoryId: _seedId('cat:CCR/FB/FOOD_PROD/VEG_FRUITS'),
              amount: Money.fromRupees(777),
              businessDate: BusinessDate.tryParse(held.row.businessDate)!,
              categoryLabel: 'Vegetables & Fruits',
            ),
          ],
          paymentStatus: PaymentStatus.unpaid,
          createdByUserId: held.row.createdBy,
          capturedAt: held.row.capturedAt,
        ),
        actorUserId: (await AuthorityStore(boot.database).ownerUserId())!,
        mutationId: const Uuid().v4(),
        baseRowVersion: staleVersion,
        now: DateTime.now().toUtc(),
      );

      final settled = await pushUntilSettled(
        tester,
        id,
        expected: {SyncState.conflict, SyncState.rejected},
      );
      expect(
        settled,
        SyncState.conflict,
        reason:
            'a stale version is a conflict about the record, never a rejection about '
            'the person (D-021)',
      );

      // The server's value stands. Nothing was merged and nothing was overwritten.
      final server = await _expenseRow(id);
      expect(server['total_amount_minor'], 99900);
    });
  });

  // ── Attachments, up to the boundary the harness can honestly reach ─────────
  //
  // **What this does not claim.** The Android photo picker and the Windows file dialog
  // are separate activities and OS dialogs; the Flutter test harness drives the
  // application's own view and cannot drive either. So this injects a synthetic picked
  // file at exactly the point the OS would have returned one — `AttachmentSource.pick`,
  // the same shape of injection D-058 uses for the transport — and proves everything
  // after it with the real staging, the real database and the real expense save.
  //
  // Driving the picker itself is a manual smoke test, recorded separately. Calling this
  // proof that the OS picker works would be false, and the project lead asked
  // specifically that it not be called that.

  group('attachment-staging', skip: _phase != 'attachment-staging', () {
    testWidgets('a picked bill is copied, hashed, and does not hold up the expense', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      await openExpenseEntry(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '640');
      await tester.pump(const Duration(milliseconds: 300));
      await classify(tester, const [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Kirana & Pulses',
      ]);

      // Attach through the real control, which calls the real staging service.
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 800));

      final intake = boot.shellKind.name == 'mobile'
          ? AttachmentIntake.gallery
          : AttachmentIntake.file;
      await pumpUntil(
        tester,
        'the ${intake.name} attachment control',
        () => find.byKey(Key('attach-${intake.name}')).evaluate().isNotEmpty,
      );
      await revealAndTap(tester, Key('attach-${intake.name}'));
      await tester.pump(const Duration(seconds: 3));

      expect(
        find.byKey(const Key('attachment-refusal')),
        findsNothing,
        reason: 'a synthetic JPEG within the policy is accepted',
      );

      await tester.enterText(
        find.byKey(const Key('expense-notes')),
        '$_acceptanceMarker: attachment staging',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));

      final id = await saveExpense(tester);
      _createdExpenses.add(id);

      // 1 · The record of the bill is in the same transaction as the expense.
      final repository = ExpenseRepository(boot.database);
      final saved = await repository.load(id);
      expect(saved!.attachments, hasLength(1));
      final attachment = saved.attachments.single;

      // 2 · The bytes were **copied** into app-private storage, not referenced where
      //     the picker left them. A gallery or camera path can be revoked, moved or
      //     cleaned between capture and upload.
      expect(attachment.localPath, isNotNull);
      expect(
        attachment.localPath,
        isNot(source.pickedPath),
        reason: 'the staged copy is not the file the picker returned',
      );
      expect(File(attachment.localPath!).existsSync(), isTrue);
      expect(
        attachment.localPath!.contains(id),
        isTrue,
        reason: 'staging is per expense, so an abandoned draft is reclaimable',
      );

      // 3 · The hash is of what was staged, and it is what "uploaded" will later be a
      //     claim about — an HTTP status is not the same claim.
      expect(attachment.contentHash, hasLength(64));
      expect(
        attachment.contentHash,
        sha256Of(File(attachment.localPath!).readAsBytesSync()),
        reason:
            'the hash describes the bytes on disk, not the bytes that were picked',
      );
      expect(attachment.byteSize, greaterThan(0));
      // One of the lifecycle states, and not a refusal. Which one depends on how fast
      // the expense was accepted — this build pushes as soon as it saves — so pinning a
      // single value here would assert a race rather than a rule. The rule that a bill
      // is never uploaded before its expense is accepted is proven deterministically in
      // `test/data/attachment_test.dart`, where the clock is not the network's.
      expect(
        attachment.uploadState,
        isIn(const [
          'staged',
          'waitingForExpense',
          'pendingUpload',
          'uploading',
          'uploaded',
        ]),
      );

      // 4 · The expense did not wait for any of it, and syncs on its own.
      await syncAndAwaitNumber(tester, id);
      final synced = await repository.load(id);
      expect(synced!.syncState, SyncState.synced);
      expect(
        synced.attachments.single.uploadState,
        isNot('rejected'),
        reason:
            'the expense was accepted on its own, and whatever became of the bill it '
            'was not a refusal — the two are deliberately independent (spec §15)',
      );

      // 5 · And it survives a restart of the application, because staging is a file
      //     and a row, not a field on a widget.
      final reopened = await bootstrap(
        transport: _transport,
        appDataDirectory: _acceptanceDataDirectory(),
      );
      addTearDown(() => reopened.database.close());
      final afterRestart = await ExpenseRepository(reopened.database).load(id);
      expect(afterRestart!.attachments, hasLength(1));
      expect(
        afterRestart.attachments.single.contentHash,
        attachment.contentHash,
      );
      expect(
        File(afterRestart.attachments.single.localPath!).existsSync(),
        isTrue,
      );
    });
  });

  // ── Two devices, one server ────────────────────────────────────────────────
  //
  // Run in order: a and c and e on Android, b and d on Windows. Each is a separate
  // process on a separate machine, which is the point — nothing is shared but the
  // backend, so every assertion is about what actually propagated.

  group('propagate-expense-a', skip: _phase != 'propagate-expense-a', () {
    testWidgets('Android records the document and attaches a bill', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // Any leftover from an earlier run is voided so it cannot be mistaken for this
      // one; the new document gets its own id, because a void does not free a key.
      await _voidTwoDeviceLeftovers();
      final twoDeviceId = const Uuid().v7();

      final gateway = ExpenseGateway(Supabase.instance.client);
      final created = await gateway.create(
        arguments: {
          'p_id': twoDeviceId,
          'p_business_date': _today(),
          'p_total_minor': 145000,
          'p_notes': _twoDeviceMarker,
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 145000},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(created.isOk, isTrue, reason: '${created.refusalOrNull?.message}');
      _createdExpenses.add(twoDeviceId);

      // A bill, uploaded through the real stack so the other device can look for it.
      // Its id is per-run for the same reason the document's is (D-076).
      final twoDeviceAttachmentId = const Uuid().v7();
      final picked = await source.pick(AttachmentIntake.gallery);
      final bytes = picked!.file.readAsBytesSync();
      final orgId = await _orgIdOf(twoDeviceId);
      final stored = await SupabaseAttachmentStore(Supabase.instance.client)
          .upload(
            orgId: orgId,
            owner: AttachmentOwnerKind.expense,
            ownerId: twoDeviceId,
            attachmentId: twoDeviceAttachmentId,
            fileName: 'two-device-receipt.jpg',
            contentType: 'image/jpeg',
            bytes: bytes,
          );
      expect(stored, isA<UploadStored>());

      final row = await _expenseRow(twoDeviceId);
      expect(row['txn_number'], startsWith('KI-EXP-'));
      debugPrint(
        'propagate-a: ${row['txn_number']} at version ${row['row_version']}',
      );
    });
  });

  group('propagate-expense-b', skip: _phase != 'propagate-expense-b', () {
    testWidgets('Windows sees the same document, and corrects it', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final twoDeviceId = await _twoDeviceDocumentId();

      final pull = ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(twoDeviceId);

      final repository = ExpenseRepository(boot.database);
      final local = await repository.load(twoDeviceId);

      // 1 · The same identity, the same number, the same money.
      expect(local, isNotNull, reason: 'the document reached this device');
      expect(local!.row.id, twoDeviceId);
      expect(local.row.txnNumber, startsWith('KI-EXP-'));
      expect(local.documentTotal, Money.fromRupees(1450));

      // 2 · And the same bill, readable because this user sees the whole document.
      final metadata = await Supabase.instance.client
          .from('expense_attachments')
          .select('id,content_hash,storage_path')
          .eq('expense_id', twoDeviceId)
          .single();
      final downloaded = await Supabase.instance.client.storage
          .from(financialAttachmentBucket)
          .download(metadata['storage_path'] as String);
      expect(
        sha256Of(downloaded),
        metadata['content_hash'],
        reason: 'the bytes the other device uploaded, byte for byte',
      );

      // 3 · Windows corrects it. The version Android last saw is parked in the
      //     reference field, because nothing else survives between two machines.
      final seenVersion = local.row.rowVersion;
      final edited = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': twoDeviceId,
          'p_business_date': local.row.businessDate,
          'p_total_minor': 167500,
          'p_reference_number': _staleVersionMarker(seenVersion),
          'p_notes': '$_twoDeviceMarker — corrected on Windows',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 167500},
          ],
        },
        baseRowVersion: seenVersion,
        mutationId: const Uuid().v4(),
      );
      expect(edited.isOk, isTrue, reason: '${edited.refusalOrNull?.message}');

      final after = await _expenseRow(twoDeviceId);
      expect(after['total_amount_minor'], 167500);
      expect(after['row_version'], greaterThan(seenVersion));
    });
  });

  group('propagate-expense-c', skip: _phase != 'propagate-expense-c', () {
    testWidgets('Android sees the correction, and a stale edit conflicts', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final twoDeviceId = await _twoDeviceDocumentId();

      final repository = ExpenseRepository(boot.database);
      final before = await repository.load(twoDeviceId);

      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(twoDeviceId);

      // 1 · The other device's correction arrived, on the same document.
      final refreshed = await repository.load(twoDeviceId);
      expect(refreshed!.row.id, twoDeviceId);
      expect(
        refreshed.documentTotal,
        Money.fromRupees(1675),
        reason: 'the figure Windows wrote',
      );
      if (before != null) {
        expect(
          refreshed.row.rowVersion,
          greaterThan(before.row.rowVersion),
          reason: 'and it arrived as a newer version, not a second record',
        );
      }
      expect(
        (await boot.database.select(boot.database.expenses).get()).where(
          (e) => e.id == twoDeviceId,
        ),
        hasLength(1),
      );

      // 2 · A stale intent — the version Android held before the pull, which Windows
      //     parked in the reference field so this phase can name it exactly.
      final stale =
          int.tryParse(
            (refreshed.row.referenceNumber ?? '').replaceAll('seen-v', ''),
          ) ??
          1;
      final conflicted = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': twoDeviceId,
          'p_business_date': refreshed.row.businessDate,
          'p_total_minor': 190000,
          'p_notes': '$_acceptanceMarker: stale edit from Android',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 190000},
          ],
        },
        baseRowVersion: stale,
        mutationId: const Uuid().v4(),
      );

      expect(conflicted.isRefused, isTrue);
      expect(
        conflicted.refusalOrNull!.kind,
        RefusalKind.versionConflict,
        reason:
            'a stale version is a conflict about the record, and the other device s '
            'correction is not overwritten (D-021)',
      );

      final unchanged = await _expenseRow(twoDeviceId);
      expect(
        unchanged['total_amount_minor'],
        167500,
        reason: 'the Windows figure still stands',
      );
    });
  });

  group('propagate-expense-d', skip: _phase != 'propagate-expense-d', () {
    testWidgets('Windows voids it', (tester) async {
      await launch(tester);
      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');

      final twoDeviceId = await _twoDeviceDocumentId();

      final row = await _expenseRow(twoDeviceId);
      final voided = await ExpenseGateway(Supabase.instance.client).voidExpense(
        expenseId: twoDeviceId,
        baseRowVersion: row['row_version'] as int,
        reason: '$_acceptanceMarker: voided from the other device',
        mutationId: const Uuid().v4(),
      );
      expect(voided.isOk, isTrue, reason: '${voided.refusalOrNull?.message}');
      expect((await _expenseRow(twoDeviceId))['voided_at'], isNotNull);
    });
  });

  group('propagate-expense-e', skip: _phase != 'propagate-expense-e', () {
    testWidgets('Android sees VOIDED, and the evidence is still there', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // Leg (d) voided it, which is the thing this leg is here to see, so the lookup
      // has to include voided documents.
      final twoDeviceId = await _twoDeviceDocumentId(includeVoided: true);

      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(twoDeviceId);

      final repository = ExpenseRepository(boot.database);
      final local = await repository.load(twoDeviceId);

      expect(local, isNotNull, reason: 'a void does not delete the record');
      expect(local!.row.voidedAt, isNotNull);
      expect(local.row.voidReason, contains(_acceptanceMarker));

      // The attachment survives a void: the document remains, and so does its evidence
      // (D-006, and the project lead's V1 rule).
      final attachments = await Supabase.instance.client
          .from('expense_attachments')
          .select('id')
          .eq('expense_id', twoDeviceId);
      expect(
        attachments,
        hasLength(1),
        reason: 'voiding an expense keeps its bills',
      );

      // And it is immutable now, with the reason a user is actually given.
      final refused = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': twoDeviceId,
          'p_business_date': local.row.businessDate,
          'p_total_minor': 200000,
          'p_notes': '$_acceptanceMarker: edit after void',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 200000},
          ],
        },
        baseRowVersion: local.row.rowVersion,
        mutationId: const Uuid().v4(),
      );
      expect(refused.isRefused, isTrue);
      expect(refused.refusalOrNull!.kind, RefusalKind.recordVoided);
    });
  });

  group('attachment-upload', skip: _phase != 'attachment-upload', () {
    testWidgets('the bill uploads after its expense, is registered, and retries', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpenseWithBill(tester, source, amount: '820');
      _createdExpenses.add(id);

      final repository = ExpenseRepository(boot.database);
      final worker = boot.attachmentUploads!;

      // ── 1 · Order: the bill waits for its document ────────────────────────
      //
      // Not an optimisation. The Storage write policy calls
      // `may_read_expense_attachments`, which requires the expense to exist canonically,
      // so uploading first is refused for a reason that reads like a permission problem.
      //
      // Which pre-upload state it is in depends on how fast the expense was accepted:
      // this build pushes as soon as it saves. So the ordering *rule* is proven
      // deterministically in `test/data/attachment_test.dart`, where the clock is not
      // the network's, and what is asserted here is that the bill left the draft state
      // and was not refused.
      var attachment = (await repository.load(id))!.attachments.single;
      expect(
        attachment.uploadState,
        isNot('staged'),
        reason: 'saving the expense moves its bill on from the draft state',
      );
      expect(attachment.uploadState, isNot('rejected'));

      // ── 2 · The expense syncs on its own, then the bill becomes eligible ──
      await syncAndAwaitNumber(tester, id);
      expect((await repository.load(id))!.syncState, SyncState.synced);

      // ── 3 · The upload itself, against real Supabase Storage ─────────────
      //
      // Driven to a settled state rather than asserted step by step: the application
      // promotes and uploads as soon as the push that accepted the expense returns, so
      // on a fast connection it has already happened by the time this line runs. The
      // durable outcome is the claim; which worker got there first is not.
      final settled = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(settled)) {
        attachment = (await repository.load(id))!.attachments.single;
        if (attachment.uploadState == 'uploaded') break;
        await worker.uploadDue();
        await tester.pump(const Duration(seconds: 2));
      }

      attachment = (await repository.load(id))!.attachments.single;
      expect(
        attachment.uploadState,
        'uploaded',
        reason: 'last error: ${attachment.lastError}',
      );
      expect(attachment.storagePath, isNotNull);
      expect(
        attachment.storagePath,
        endsWith('${attachment.id}.jpg'),
        reason: 'the deterministic path (spec §15.2)',
      );
      expect(attachment.uploadedAt, isNotNull);
      expect(
        attachment.lastError,
        isNull,
        reason: 'a confirmed upload carries no complaint',
      );

      // ── 4 · Canonical metadata in Postgres, not an object listing ─────────
      final metadata = await Supabase.instance.client
          .from('expense_attachments')
          .select(
            'id,expense_id,content_hash,storage_path,byte_size,uploaded_by',
          )
          .eq('id', attachment.id)
          .single();
      expect(metadata['expense_id'], id);
      expect(
        metadata['content_hash'],
        attachment.contentHash,
        reason:
            'the hash the server recorded is the hash of what was staged — which is '
            'what makes "uploaded" a claim about bytes rather than about a status code',
      );
      expect(metadata['storage_path'], attachment.storagePath);
      expect(metadata['byte_size'], attachment.byteSize);

      // ── 5 · Idempotency: a retry after a lost response ───────────────────
      //
      // The same bytes, the same attachment id, the same deterministic path. One object
      // and one metadata row, however many times it is delivered (D-073 §8).
      final again = await SupabaseAttachmentStore(Supabase.instance.client)
          .upload(
            orgId: metadata['uploaded_by'] == null ? '' : attachment.orgId,
            owner: AttachmentOwnerKind.expense,
            ownerId: id,
            attachmentId: attachment.id,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            bytes: File(attachment.localPath!).readAsBytesSync(),
          );
      expect(
        again,
        isA<UploadStored>(),
        reason: 'a redelivery is stored again, not refused and not duplicated',
      );
      final rows = await Supabase.instance.client
          .from('expense_attachments')
          .select('id')
          .eq('expense_id', id);
      expect(
        rows,
        hasLength(1),
        reason: 'one canonical metadata record, however many deliveries',
      );

      // ── 6 · The expense is untouched by any of it ────────────────────────
      final afterUpload = await repository.load(id);
      expect(afterUpload!.syncState, SyncState.synced);
      expect(afterUpload.row.txnNumber, isNotNull);
      expect(
        (await boot.outbox.allEntries()).where(
          (q) => q.entityId == id && q.status != OutboxStatus.done.name,
        ),
        isEmpty,
        reason: 'retrying an attachment never generates an expense mutation',
      );
    });

    testWidgets('a transient failure leaves the expense Synced and retries', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpenseWithBill(tester, source, amount: '333');
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final repository = ExpenseRepository(boot.database);
      expect((await repository.load(id))!.syncState, SyncState.synced);

      // The application uploads as soon as the push that accepted the expense returns,
      // so on a fast connection the bill is already on the server by now. To exercise a
      // *transient* failure the row is put back to `pendingUpload` and the network taken
      // away — the worker, the store, the failure and every state transition after it
      // are the real ones; only the starting position is arranged.
      final failing = AttachmentUploadWorker(
        db: boot.database,
        store: SupabaseAttachmentStore(Supabase.instance.client),
      );
      await boot.database.customStatement(
        "UPDATE expense_attachments SET upload_state = 'pendingUpload', "
        'next_attempt_at = NULL, attempt_count = 0 WHERE expense_id = ?',
        [id],
      );

      _transport.online = false;
      expect(
        await failing.uploadDue(),
        0,
        reason: 'nothing can be confirmed with no network',
      );

      var attachment = (await repository.load(id))!.attachments.single;
      expect(
        attachment.uploadState,
        'retryNeeded',
        reason:
            'a transport failure says nothing about permission, so it retries',
      );
      expect(
        attachment.nextAttemptAt,
        isNotNull,
        reason: 'on the durable clock, not in a loop',
      );
      expect(attachment.attemptCount, greaterThan(0));

      // **The point of the phase.** The financial record is untouched.
      final duringFailure = await repository.load(id);
      expect(
        duringFailure!.syncState,
        SyncState.synced,
        reason:
            'an accepted expense does not become Pending, Rejected or Conflict because '
            'a photo failed to upload (spec §15)',
      );
      expect(duringFailure.row.txnNumber, isNotNull);

      // Reconnect, and only the attachment is retried.
      _transport.online = true;
      final outboxBefore = (await boot.outbox.allEntries()).length;

      final deadline = DateTime.now().add(const Duration(seconds: 120));
      var confirmed = 0;
      while (DateTime.now().isBefore(deadline) && confirmed == 0) {
        // The backoff is real, so the row is made due rather than waited out.
        await boot.database.customStatement(
          "UPDATE expense_attachments SET next_attempt_at = ? WHERE expense_id = ?",
          [DateTime.now().toUtc().toIso8601String(), id],
        );
        confirmed = await failing.uploadDue();
        if (confirmed == 0) await tester.pump(const Duration(seconds: 2));
      }
      expect(
        confirmed,
        1,
        reason: 'the retry succeeded once the network returned',
      );

      attachment = (await repository.load(id))!.attachments.single;
      expect(attachment.uploadState, 'uploaded');
      expect(
        (await boot.outbox.allEntries()).length,
        outboxBefore,
        reason: 'retrying an attachment queued no expense mutation',
      );
      expect((await repository.load(id))!.syncState, SyncState.synced);
    });
  });

  group('attachment-scope', skip: _phase != 'attachment-scope', () {
    testWidgets('a scoped manager cannot retrieve a complete document s bill', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // A shared bill the Owner can see whole, with a receipt attached to it.
      final sharedId = await _admin.createSharedExpense(
        notes: '$_acceptanceMarker: attachment scope security',
      );
      _createdExpenses.add(sharedId);

      final attachmentId = const Uuid().v4();
      final bytes = _SyntheticAttachmentSource.syntheticJpeg();
      final store = SupabaseAttachmentStore(Supabase.instance.client);
      final orgId = (await _expenseRow(sharedId))['id'] == null
          ? ''
          : (await Supabase.instance.client
                    .from('expense_document')
                    .select('org_id')
                    .eq('id', sharedId)
                    .single())['org_id']
                as String;

      final stored = await store.upload(
        orgId: orgId,
        owner: AttachmentOwnerKind.expense,
        ownerId: sharedId,
        attachmentId: attachmentId,
        fileName: 'shared-invoice.jpg',
        contentType: 'image/jpeg',
        bytes: bytes,
      );
      expect(
        stored,
        isA<UploadStored>(),
        reason:
            'the Owner sees every line, so may attach: ${stored.runtimeType}',
      );

      final path = 'org/$orgId/expenses/$sharedId/$attachmentId.jpg';

      // The Owner can read it back.
      final ownerCopy = await Supabase.instance.client.storage
          .from(financialAttachmentBucket)
          .download(path);
      expect(ownerCopy, isNotEmpty);

      // The Crystal Canopy manager holds ₹25,000 of it and may not.
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      await expectLater(
        Supabase.instance.client.storage
            .from(financialAttachmentBucket)
            .download(path),
        throwsA(anything),
        reason:
            'an invoice states the whole total on its face, so a scoped holder is not '
            'given it — and this is Storage refusing, not a hidden button (D-063)',
      );

      // Nor may they register one against it, which is the other half of the same rule.
      final forged = await SupabaseAttachmentStore(Supabase.instance.client)
          .upload(
            orgId: orgId,
            owner: AttachmentOwnerKind.expense,
            ownerId: sharedId,
            attachmentId: const Uuid().v4(),
            fileName: 'forged.jpg',
            contentType: 'image/jpeg',
            bytes: bytes,
          );
      expect(
        forged,
        isA<UploadRefused>(),
        reason:
            'attaching implies reading it back, so the same predicate governs both',
      );

      // And the metadata row itself is not readable to them.
      final rows = await Supabase.instance.client
          .from('expense_attachments')
          .select('id')
          .eq('expense_id', sharedId);
      expect(
        rows,
        isEmpty,
        reason: 'the table policy holds the same complete-document predicate',
      );
    });
  });

  // ── The Windows ledger ─────────────────────────────────────────────────────

  group('windows-ledger', skip: _phase != 'windows-ledger', () {
    testWidgets('filters, paging and a detail panel that never lies about a share', (
      tester,
    ) async {
      expect(
        boot.shellKind.name,
        isNot('mobile'),
        reason:
            'this phase is about the desktop ledger; run it with -d windows',
      );

      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // Three documents with deliberately different shapes: one Crystal Canopy, one
      // Hotel Krishna, one shared between them and paid.
      // Dated today, deliberately. The ledger is ordered by business date, and a June
      // fixture sits below every document the other phases have created since — which is
      // the ledger working correctly and makes it a poor subject for a selection test.
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final ccrId = await _admin.createCcrExpense(
        notes: '$_acceptanceMarker: ledger CCR only',
        businessDate: today,
      );
      final sharedId = await _admin.createSharedExpense(
        notes: '$_acceptanceMarker: ledger shared bill',
        businessDate: today,
      );
      _createdExpenses
        ..add(ccrId)
        ..add(sharedId);

      final pull = ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(ccrId);
      await pull.pullOne(sharedId);

      final repository = ExpenseRepository(boot.database);

      // ── Paging is done in SQL, not by loading the ledger into memory ────────
      //
      // Asserted against the repository rather than by counting rows on screen: the
      // claim is about *where* the narrowing happens, and a screen showing 50 rows looks
      // identical whether the database returned 50 or the application fetched ten
      // thousand and threw most away (spec §27).
      final firstPage = await repository.query(
        const ExpenseFilter(),
        limit: 2,
        offset: 0,
      );
      final secondPage = await repository.query(
        const ExpenseFilter(),
        limit: 2,
        offset: 2,
      );
      expect(firstPage, hasLength(lessThanOrEqualTo(2)));
      expect(
        firstPage
            .map((e) => e.row.id)
            .toSet()
            .intersection(secondPage.map((e) => e.row.id).toSet()),
        isEmpty,
        reason:
            'consecutive windows do not overlap, so the offset reached the query',
      );

      // ── The filter bar ──────────────────────────────────────────────────────
      await pumpUntil(
        tester,
        'the Transactions destination',
        () => visible('Transactions'),
      );
      await tester.tap(find.text('Transactions').last);
      await tester.pump(const Duration(milliseconds: 900));
      await pumpUntil(
        tester,
        'the ledger filter bar',
        () => find.byKey(const Key('ledger-search')).evaluate().isNotEmpty,
      );

      final ccrNumber = (await _expenseRow(ccrId))['txn_number'] as String;
      final sharedNumber =
          (await _expenseRow(sharedId))['txn_number'] as String;

      // The application's own container, so the filter asserted below is the one the
      // controls actually wrote — not a copy this phase maintains alongside it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );

      // Search by expense number narrows to one document.
      await tester.enterText(find.byKey(const Key('ledger-search')), ccrNumber);
      await tester.pump(const Duration(seconds: 2));
      expect(showsText(ccrNumber), isTrue);
      expect(
        showsText(sharedNumber),
        isFalse,
        reason: 'the search reached the query, not just the eye',
      );

      await tester.enterText(find.byKey(const Key('ledger-search')), '');
      await tester.pump(const Duration(seconds: 2));

      // The business-unit filter.
      await pumpUntil(
        tester,
        'the business unit filter',
        () => find.byKey(const Key('ledger-unit-filter')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('ledger-unit-filter')));
      await tester.pump(const Duration(milliseconds: 800));
      await pumpUntil(
        tester,
        'Hotel Krishna Imperial in the filter',
        () => visible('Hotel Krishna Imperial'),
      );
      await tester.tap(find.text('Hotel Krishna Imperial').last);
      await tester.pump(const Duration(seconds: 2));

      expect(
        showsText(sharedNumber),
        isTrue,
        reason:
            'a shared bill charges Hotel Krishna, so it belongs in this view',
      );
      expect(
        showsText(ccrNumber),
        isFalse,
        reason: 'and a Crystal-Canopy-only document does not',
      );

      // Filters clear.
      await pumpUntil(
        tester,
        'Clear filters',
        () =>
            find.byKey(const Key('ledger-clear-filters')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('ledger-clear-filters')));
      await tester.pump(const Duration(seconds: 2));
      expect(showsText(ccrNumber), isTrue);
      expect(showsText(sharedNumber), isTrue);

      // ── The rest of the surface, behind Filters ─────────────────────────────
      //
      // Progressive on purpose (D-073 §19): the bar carries the date range, the search
      // and the property; the other six live behind a button that says how many are
      // active, so a narrowed ledger is never mysterious.
      expect(
        find.byKey(const Key('ledger-filter-panel')),
        findsNothing,
        reason: 'closed until asked for',
      );
      await tester.tap(find.byKey(const Key('ledger-more-filters')));
      await tester.pump(const Duration(seconds: 1));
      await pumpUntil(
        tester,
        'the expanded filter panel',
        () =>
            find.byKey(const Key('ledger-filter-panel')).evaluate().isNotEmpty,
      );

      for (final control in const [
        'ledger-department-filter',
        'ledger-section-filter',
        'ledger-category-filter',
        'ledger-payment-filter',
        'ledger-status-filter',
      ]) {
        expect(
          find.byKey(Key(control)),
          findsOneWidget,
          reason: '$control is part of the V1 surface',
        );
      }
      expect(visible('Include voided'), isTrue);
      expect(find.byKey(const Key('ledger-date-range')), findsOneWidget);

      // Department narrows, through the query.
      await tester.tap(find.byKey(const Key('ledger-department-filter')));
      await tester.pump(const Duration(milliseconds: 900));
      await pumpUntil(
        tester,
        'a Hotel Krishna department in the filter',
        () => visible('Utilities'),
      );
      await tester.tap(find.text('Utilities').last);
      await tester.pump(const Duration(seconds: 2));
      expect(
        showsText(sharedNumber),
        isTrue,
        reason: 'the shared bill has a Hotel Krishna utilities line',
      );
      expect(showsText(ccrNumber), isFalse);

      // ── The dependency rule (D-073 §20) ─────────────────────────────────────
      //
      // Moving the property must not leave a department from the other one active behind
      // a collapsed panel: two predicates that intersect to nothing look exactly like an
      // empty ledger, and nothing on screen would say why.
      await tester.tap(find.byKey(const Key('ledger-unit-filter')));
      await tester.pump(const Duration(milliseconds: 900));
      await pumpUntil(
        tester,
        'Crystal Canopy in the unit filter',
        () => visible('Crystal Canopy Rooftop'),
      );
      await tester.tap(find.text('Crystal Canopy Rooftop').last);
      await tester.pump(const Duration(seconds: 2));

      final corrected = container.read(expenseFilterProvider);
      expect(corrected.businessUnitId, isNotNull);
      expect(
        corrected.departmentId,
        isNull,
        reason:
            'a Hotel Krishna department cannot survive a move to Crystal Canopy',
      );
      // And the corrected filter is one that actually returns the Crystal Canopy
      // document — the point being that clearing the orphan restored a *useful* query,
      // not merely a tidy one. Asserted through the query the UI feeds, because what is
      // on screen at this instant also depends on scrolling and column width, and the
      // claim here is about the filter.
      final afterCorrection = await repository.query(corrected);
      expect(
        afterCorrection.map((e) => e.row.id),
        contains(ccrId),
        reason: 'the stale department would have narrowed this to nothing',
      );

      // Payment status, as a predicate rather than a label.
      final unpaidOnly = await repository.query(
        const ExpenseFilter(paymentStatus: 'unpaid'),
      );
      expect(unpaidOnly.every((e) => e.row.paymentStatus == 'unpaid'), isTrue);

      // Clearing restores everything.
      await pumpUntil(
        tester,
        'Clear filters',
        () =>
            find.byKey(const Key('ledger-clear-filters')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('ledger-clear-filters')));
      await tester.pump(const Duration(seconds: 2));
      final afterClear = container.read(expenseFilterProvider);
      expect(
        afterClear.activeCount,
        0,
        reason:
            'no narrowing choice survives Clear filters. Left: '
            'unit=${afterClear.businessUnitId} dept=${afterClear.departmentId} '
            'section=${afterClear.sectionId} category=${afterClear.categoryId} '
            'vendor=${afterClear.vendorId} payment=${afterClear.paymentStatus} '
            'status=${afterClear.syncState} voided=${afterClear.includeVoided} '
            'from=${afterClear.from} to=${afterClear.to}',
      );
      expect(
        (await repository.query(afterClear)).map((e) => e.row.id),
        containsAll(<String>[ccrId, sharedId]),
        reason: 'clearing restores the unfiltered ledger',
      );

      // ── Selection opens the detail, and the caption tells the truth ──────────
      //
      // Searched for first, which is what a finance user does: the ledger is ordered by
      // business date and holds documents from every earlier phase, so a June bill is a
      // long way down a list headed by today's. That is the ledger working, not failing.
      await tester.enterText(
        find.byKey(const Key('ledger-search')),
        sharedNumber,
      );
      await tester.pump(const Duration(seconds: 2));
      await pumpUntil(
        tester,
        'the shared bill, found by its number',
        () => showsText(sharedNumber),
        timeout: const Duration(seconds: 20),
      );
      await tester.tap(find.textContaining(sharedNumber).first);
      await tester.pump(const Duration(seconds: 2));
      await pumpUntil(
        tester,
        'the detail panel',
        () => find.byKey(const Key('amount-label')).evaluate().isNotEmpty,
      );

      // The Owner sees the whole document, so the caption reads TOTAL and the figure is
      // the invoice.
      expect(
        (tester.widget<Text>(find.byKey(const Key('amount-label')))).data,
        'TOTAL',
      );
      expect(
        find
            .descendant(
              of: find.byType(ExpenseDetailPanel),
              matching: moneyShown('58,000'),
            )
            .evaluate(),
        isNotEmpty,
      );

      // A scoped manager, on the same installation, must never see that caption on a
      // share. This is the assertion the ledger phase exists for.
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(sharedId);

      await openExpenseDetail(tester, sharedId);
      await pumpUntil(
        tester,
        'the scoped detail panel',
        () => find.byKey(const Key('scoped-explanation')).evaluate().isNotEmpty,
      );
      expect(
        (tester.widget<Text>(find.byKey(const Key('amount-label')))).data,
        'YOUR ALLOCATION',
        reason:
            'a share is never captioned TOTAL — the caption is the difference between '
            'a true statement and a false one about the same number',
      );
      expect(
        find
            .descendant(
              of: find.byType(ExpenseDetailPanel),
              matching: moneyShown('58,000'),
            )
            .evaluate(),
        isEmpty,
      );
      expect(
        find
            .descendant(
              of: find.byType(ExpenseDetailPanel),
              matching: moneyShown('25,000'),
            )
            .evaluate(),
        isNotEmpty,
      );
    });
  });

  group('expense-edit-offline', skip: _phase != 'expense-edit-offline', () {
    testWidgets('an edit made offline queues, survives, and reconciles once', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpense(
        tester,
        amount: '450',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Vegetables & Fruits',
        ],
        notes: 'offline edit acceptance',
      );
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final repository = ExpenseRepository(boot.database);
      final before = await repository.load(id);
      final versionBefore = before!.row.rowVersion;
      final numberBefore = before.row.txnNumber;

      // The network goes away. Nothing is faked above the cable: the real transport
      // throws the platform's own SocketException from inside `send` (D-058).
      _transport.online = false;
      addTearDown(() => _transport.online = true);

      await openExpenseDetail(tester, id);
      await pumpUntil(
        tester,
        'the Edit control',
        () => find.byKey(const Key('edit-expense')).evaluate().isNotEmpty,
      );
      await revealAndTap(tester, const Key('edit-expense'));
      await tester.pump(const Duration(milliseconds: 900));
      await pumpUntil(
        tester,
        'the edit form',
        () => find.byKey(const Key('expense-amount')).evaluate().isNotEmpty,
      );

      await tester.enterText(find.byKey(const Key('expense-amount')), '612');
      await tester.pump(const Duration(milliseconds: 400));
      await saveEditedExpense(tester, id);

      // 1 · Saved locally, with no network, and honest about it.
      final offline = await repository.load(id);
      expect(offline!.documentTotal, Money.fromRupees(612));
      expect(
        offline.syncState,
        isNot(SyncState.synced),
        reason: 'an edit that has not been delivered is never shown as synced',
      );
      final intent = (await boot.outbox.allEntries()).singleWhere(
        (q) => q.entityId == id && q.op == 'update',
      );
      expect(intent.baseRowVersion, versionBefore);
      expect(intent.status, isNot(OutboxStatus.done.name));

      // 2 · It survives a restart of the application — the queue is durable, not a
      //     field on a widget.
      final reopened = await bootstrap(
        transport: _transport,
        appDataDirectory: _acceptanceDataDirectory(),
      );
      addTearDown(() => reopened.database.close());
      final afterRestart = ExpenseRepository(reopened.database);
      expect(
        (await afterRestart.load(id))!.documentTotal,
        Money.fromRupees(612),
      );
      expect(
        (await reopened.outbox.allEntries()).where(
          (q) => q.entityId == id && q.op == 'update',
        ),
        hasLength(1),
      );

      // 3 · The network returns and the edit is applied exactly once.
      _transport.online = true;
      final settled = await pushUntilSettled(
        tester,
        id,
        expected: {SyncState.synced},
      );
      expect(settled, SyncState.synced);

      final after = await repository.load(id);
      expect(after!.documentTotal, Money.fromRupees(612));
      expect(
        after.row.txnNumber,
        numberBefore,
        reason: 'the number does not move, offline or on',
      );
      expect(after.row.rowVersion, greaterThan(versionBefore));
      expect(
        (await boot.database.select(boot.database.expenses).get()).where(
          (e) => e.id == id,
        ),
        hasLength(1),
        reason: 'one document, one edit, however many times it was retried',
      );

      final server = await _expenseRow(id);
      expect(server['total_amount_minor'], 61200);
    });
  });

  group('expense-edit-refused', skip: _phase != 'expense-edit-refused', () {
    testWidgets('a closed period refuses the edit, and says so plainly', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final client = Supabase.instance.client;
      final gateway = ExpenseGateway(client);

      // A February document, recorded while the period is open.
      final id = const Uuid().v4();
      final created = await gateway.create(
        arguments: {
          'p_id': id,
          'p_business_date': '2026-02-10',
          'p_total_minor': 250000,
          'p_notes': '$_acceptanceMarker: closed-period edit',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 250000},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(
        created.isOk,
        isTrue,
        reason: 'setup: ${created.refusalOrNull?.message}',
      );
      _createdExpenses.add(id);

      // The period is closed behind it. `period_close` takes no reason; only a *reopen*
      // does, because closing is the ordinary end of a month while reopening a closed
      // period is the deliberate act that has to be explained and audited (D-026).
      await client.rpc<dynamic>(
        'period_close',
        params: {
          'p_period_key': '2026-02',
          'p_business_unit_id': _ccr,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      addTearDown(() async {
        await client.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_period_key': '2026-02',
            'p_business_unit_id': _ccr,
            'p_reason': '$_acceptanceMarker: restoring the fixture',
          },
        );
      });

      final row = await _expenseRow(id);
      final refused = await gateway.update(
        arguments: {
          'p_id': id,
          'p_business_date': '2026-02-10',
          'p_total_minor': 260000,
          'p_notes': '$_acceptanceMarker: closed-period edit attempt',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 260000},
          ],
        },
        baseRowVersion: row['row_version'] as int,
        mutationId: const Uuid().v4(),
      );

      expect(refused.isRefused, isTrue);
      expect(
        refused.refusalOrNull!.kind,
        RefusalKind.periodClosed,
        reason:
            'a closed period is its own answer — never dressed up as a conflict, '
            'because the user can do nothing about a version they do not have',
      );
      expect(
        refused.refusalOrNull!.message.toLowerCase(),
        contains('closed'),
        reason: 'and it says so in words a manager can act on',
      );
      expect(refused.refusalOrNull!.message, isNot(contains('SQLSTATE')));

      // The beyond-window capability lifts the age rule and nothing else: the Owner
      // holds it and is refused just the same.
      expect(
        (await _expenseRow(id))['total_amount_minor'],
        250000,
        reason: 'and the document is untouched',
      );
    });

    testWidgets('an edit queued before a revocation is Rejected, not Conflict', (
      tester,
    ) async {
      // The sequence the project lead named: edit offline, lose the permission, come
      // back. Authority is refreshed first, the server declines the act itself, and
      // the attempt is kept exactly as it was made.
      await _admin.grantScope('hki.manager@example.com', 'manager', 'CCR');
      addTearDown(() => _admin.revokeScope('hki.manager@example.com', 'CCR'));

      await launch(tester);
      await signIn(tester, 'hki.manager@example.com');
      await expectSignedIn(tester, 'hki.manager@example.com');

      final repository = ExpenseRepository(boot.database);
      final id = await recordExpense(
        tester,
        amount: '390',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Kirana & Pulses',
        ],
        notes: 'revoked-before-delivery acceptance',
      );
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      // Offline, they correct it.
      _transport.online = false;
      addTearDown(() => _transport.online = true);

      final held = (await repository.load(id))!;
      await repository.updateLocally(
        ExpenseDocument(
          id: id,
          orgId: held.row.orgId,
          businessDate: BusinessDate.tryParse(held.row.businessDate)!,
          businessDateSource: BusinessDateSource.derived,
          total: Money.fromRupees(410),
          allocations: [
            ExpenseAllocation.wholePeriod(
              id: held.allocations.single.id,
              businessUnitId: _ccr,
              departmentId: _seedId('dept:CCR/FB'),
              sectionId: _seedId('sec:CCR/FB/FOOD_PROD'),
              categoryId: _kirana,
              amount: Money.fromRupees(410),
              businessDate: BusinessDate.tryParse(held.row.businessDate)!,
              categoryLabel: 'Kirana & Pulses',
            ),
          ],
          paymentStatus: PaymentStatus.unpaid,
          createdByUserId: held.row.createdBy,
          capturedAt: held.row.capturedAt,
        ),
        actorUserId: (await AuthorityStore(boot.database).ownerUserId())!,
        mutationId: const Uuid().v4(),
        baseRowVersion: held.row.rowVersion,
        now: DateTime.now().toUtc(),
      );
      expect((await repository.load(id))!.syncState, isNot(SyncState.synced));

      // Their Crystal Canopy grant is withdrawn while they are away.
      await _admin.revokeScope('hki.manager@example.com', 'CCR');
      _transport.online = true;

      final settled = await pushUntilSettled(
        tester,
        id,
        expected: {SyncState.rejected, SyncState.conflict},
        timeout: const Duration(seconds: 180),
      );
      expect(
        settled,
        SyncState.rejected,
        reason:
            'a withdrawn permission is about the person and no retry will change '
            'it — terminal Rejected, never Conflict (D-048, D-059)',
      );

      // And the attempt is still there to be looked at.
      final intent = (await boot.outbox.allEntries()).singleWhere(
        (q) => q.entityId == id && q.op == 'update',
      );
      expect(intent.status, OutboxStatus.rejected.name);
      expect(
        intent.lastError,
        isNotNull,
        reason: 'the server s own reason is kept with the attempt',
      );
    });
  });

  group('expense-edit-shared', skip: _phase != 'expense-edit-shared', () {
    testWidgets('a scoped share is read-only, in the UI and at the server', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final sharedId = await _admin.createSharedExpense(
        notes: '$_acceptanceMarker: edit security, shared bill',
      );
      _createdExpenses.add(sharedId);

      final pull = ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(sharedId);

      // The Owner holds the whole document and may edit it.
      final repository = ExpenseRepository(boot.database);
      final complete = await repository.load(sharedId);
      expect(complete!.row.visibility, 'complete');
      await openExpenseDetail(tester, sharedId);
      await pumpUntil(
        tester,
        'the Edit control for a complete document',
        () => find.byKey(const Key('edit-expense')).evaluate().isNotEmpty,
      );

      // The Crystal Canopy manager holds a share of it, and may not.
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(sharedId);

      final scoped = await repository.load(sharedId);
      expect(scoped!.row.visibility, 'scoped');
      expect(scoped.row.documentTotalMinor, isNull);
      expect(scoped.visibleAmount, Money.fromRupees(25000));

      await openExpenseDetail(tester, sharedId);

      // Anchor first. Every assertion below is about something being *absent*, and an
      // absent control is indistinguishable from a screen that never opened — so the
      // scoped rendering is positively identified before anything is denied.
      await pumpUntil(
        tester,
        'the scoped detail panel',
        () => find.byKey(const Key('scoped-explanation')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      // Scoped to the detail panel. On Windows the ledger sits beside it and
      // legitimately lists other documents, so asserting over the whole screen would be
      // asserting something this test is not about.
      bool inDetail(String text) => find
          .descendant(
            of: find.byType(ExpenseDetailPanel),
            matching: find.textContaining(text),
          )
          .evaluate()
          .isNotEmpty;

      expect(
        inDetail('25,000'),
        isTrue,
        reason: 'the share this manager may see is on the document',
      );
      expect(
        inDetail('58,000'),
        isFalse,
        reason: 'and the invoice total is not',
      );
      expect(inDetail('33,000'), isFalse, reason: 'nor the other share');

      expect(
        find.byKey(const Key('edit-expense'), skipOffstage: false),
        findsNothing,
        reason:
            'a partial projection cannot be reconciled, so it is read-only in V1 '
            'however many edit capabilities the holder has',
      );
      expect(
        find.byKey(const Key('scoped-readonly-note'), skipOffstage: false),
        findsOneWidget,
        reason: 'and the rule is stated rather than left as an absent button',
      );

      // The server enforces it regardless of what a modified client attempts.
      final forged = await ExpenseGateway(Supabase.instance.client).update(
        arguments: {
          'p_id': sharedId,
          'p_business_date': '2026-06-15',
          'p_total_minor': 2500000,
          'p_notes': '$_acceptanceMarker: forged scoped edit',
          'p_allocations': [
            {..._ccrKirana, 'amount_minor': 2500000},
          ],
        },
        baseRowVersion: scoped.row.rowVersion,
        mutationId: const Uuid().v4(),
      );
      expect(
        forged.isRefused,
        isTrue,
        reason:
            'hiding the control is not the security boundary; the server is (D-037)',
      );
      expect(forged.refusalOrNull!.message, isNot(contains('SQLSTATE')));

      // And the document still says what it said.
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');
      final unchanged = await _expenseRow(sharedId);
      expect(unchanged['total_amount_minor'], 5800000);
    });
  });

  // ── D-034 / D-060 · cross-period allocation, through the real entry screen ──

  group('cross-period', skip: _phase != 'cross-period', () {
    testWidgets('₹60,000 split May ₹30,000 / June ₹30,000, and nothing else', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      await openExpenseEntry(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '60000');
      await tester.pump(const Duration(milliseconds: 300));
      await classify(tester, const [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Kirana & Pulses',
      ]);

      // The bill covers 15 May – 14 June, so it is recorded on a June business date.
      // The proposal anchors on that date, which is the point: the split it offers is
      // derived from the document, not from when the clerk happened to type it.
      await setDateField(tester, const Key('business-date'), '2026-06-15');
      await pumpUntil(
        tester,
        'the business date to become June',
        () => visible('2026-06-15'),
      );

      // 1 · Reachable only deliberately. An ordinary expense never meets this: the
      //     routine screen offers no period field at all, and the default rule applies
      //     silently (D-034 — the fast path does not change).
      expect(
        byKeyPrefix('period-amount-'),
        findsNothing,
        reason: 'no period editor before anyone asks for one',
      );
      expect(find.byKey(const Key('split-expense')), findsOneWidget);

      await tester.tap(find.byKey(const Key('split-expense')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        byKeyPrefix('period-amount-'),
        findsNothing,
        reason: 'even in the split view it is closed until opened',
      );

      await pumpUntil(
        tester,
        'the accounting-period control',
        () => visible('Split across accounting periods'),
      );
      await tester.tap(find.text('Split across accounting periods'));
      await tester.pump(const Duration(milliseconds: 800));

      // 2 · Two periods, proposed evenly, and the money reconciles exactly.
      expect(byKeyPrefix('period-amount-'), findsNWidgets(2));
      await pumpUntil(
        tester,
        'the split to balance',
        () => visible('BALANCED'),
      );
      // The labels carry the year, because "May" alone is not a period.
      expect(
        visible('May 2026'),
        isTrue,
        reason: 'the previous accounting month',
      );
      expect(
        visible('June 2026'),
        isTrue,
        reason: 'the month of the business date',
      );
      expect(
        showsText('2026-05-01'),
        isTrue,
        reason: 'the service period is stated, not merely the month name',
      );
      expect(showsText('2026-06-15'), isTrue);
      expect(
        moneyTextsOnScreen(tester),
        contains('₹60,000.00'),
        reason:
            'allocated ₹60,000, in Indian digit grouping, as the user reads it',
      );
      expect(
        periodAmountsOnScreen(tester),
        ['30,000.00', '30,000.00'],
        reason:
            'proposed evenly: ₹30,000 to May and ₹30,000 to June, grouped the Indian '
            'way in the field itself',
      );
      expect(
        amountShownFor(tester, const Key('remaining-amount')),
        '₹0.00',
        reason: 'remaining ₹0',
      );
      expect(saveEnabled(tester), isTrue);

      // 3 · Save is available only at exact reconciliation. Not "warned about" —
      //     unavailable, because a split that does not add up is not a document.
      final fields = byKeyPrefix('period-amount-').evaluate().toList();
      await tester.enterText(find.byWidget(fields.first.widget), '25000');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        saveEnabled(tester),
        isFalse,
        reason: '₹25,000 + ₹30,000 is not ₹60,000, so there is nothing to save',
      );
      expect(visible('REMAINING'), isTrue);
      expect(find.byKey(const Key('save-blocked-reason')), findsOneWidget);

      await tester.enterText(find.byWidget(fields.first.widget), '30000');
      await tester.pump(const Duration(milliseconds: 500));
      await pumpUntil(tester, 'balance to return', () => visible('BALANCED'));
      expect(saveEnabled(tester), isTrue);

      // 4 · Saved, accepted by the server, and numbered.
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 700));
      await pumpUntil(
        tester,
        'the notes field',
        () => find.byKey(const Key('expense-notes')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('expense-notes')),
        '$_acceptanceMarker: cross-period May/June',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));

      final id = await saveExpense(tester);
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      // 5 · The reporting shape. One line, two contributions, and — the point of
      //     D-060 — no third row carrying the whole ₹60,000 against the document date.
      final repository = ExpenseRepository(boot.database);
      final saved = await repository.load(id);
      expect(saved!.allocations, hasLength(1));
      expect(saved.periodContributions, hasLength(2));
      expect(
        saved.periodContributions.every((c) => !c.isDerived),
        isTrue,
        reason: 'a deliberate split is not a derived one',
      );

      final byPeriod = {
        for (final c in saved.periodContributions)
          c.pnlPeriodKey: c.amountMinor,
      };
      expect(byPeriod, {'2026-05': 3000000, '2026-06': 3000000});
      expect(
        saved.periodContributions.map((c) => c.amountMinor),
        isNot(contains(6000000)),
        reason:
            'there is no second contribution for the whole amount — reporting reads '
            'these rows and only these rows, so one would be counted twice (D-060)',
      );
      expect(
        saved.periodContributions.fold<int>(0, (t, c) => t + c.amountMinor),
        6000000,
        reason: 'and they still add up to the line, to the paisa',
      );

      expect(
        (await repository.contributionTotals(
          ExpenseContributionQuery(periodKey: '2026-05'),
        )).amount,
        Money.fromRupees(30000),
      );
      expect(
        (await repository.contributionTotals(
          ExpenseContributionQuery(periodKey: '2026-06'),
        )).amount,
        Money.fromRupees(30000),
      );
    });

    testWidgets('an amount that will not divide evenly still reconciles', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // ₹1,000.01 is 100,001 paise. Two periods cannot take half of that, so the
      // proposal has to give one of them a paisa more — largest remainder, applied once
      // (ARCHITECTURE §6.5). What must never happen is a total of 100,000 or 100,002.
      await openExpenseEntry(tester);
      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '1000.01',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await classify(tester, const [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Kirana & Pulses',
      ]);
      await setDateField(tester, const Key('business-date'), '2026-06-15');
      await pumpUntil(
        tester,
        'the business date to become June',
        () => visible('2026-06-15'),
      );
      await tester.tap(find.byKey(const Key('split-expense')));
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the accounting-period control',
        () => visible('Split across accounting periods'),
      );
      await tester.tap(find.text('Split across accounting periods'));
      await tester.pump(const Duration(milliseconds: 800));

      await pumpUntil(
        tester,
        'the odd split to balance itself',
        () => visible('BALANCED'),
      );
      expect(
        amountShownFor(tester, const Key('remaining-amount')),
        '₹0.00',
        reason: 'the proposal reconciles to the paisa before anyone edits it',
      );

      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 700));
      await pumpUntil(
        tester,
        'the notes field',
        () => find.byKey(const Key('expense-notes')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('expense-notes')),
        '$_acceptanceMarker: odd-paise split',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));

      final id = await saveExpense(tester);
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final saved = await ExpenseRepository(boot.database).load(id);
      final amounts = saved!.periodContributions
          .map((c) => c.amountMinor)
          .toList();
      expect(amounts, hasLength(2));
      expect(
        amounts.reduce((a, b) => a + b),
        100001,
        reason: 'no paisa is invented and none disappears',
      );
      expect(
        (amounts.first - amounts.last).abs(),
        1,
        reason:
            'the remainder lands on exactly one period, not spread as a fraction',
      );
      expect(
        saved.allocations.single.amountMinor,
        100001,
        reason: 'and the line the contributions belong to is unchanged',
      );
    });
  });

  // ── D-016 · payment date moves cash, never profitability ───────────────────

  group('payment-accrual', skip: _phase != 'payment-accrual', () {
    testWidgets('a June salary paid on 5 July is June s cost and July s cash', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      await openExpenseEntry(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '80000');
      await tester.pump(const Duration(milliseconds: 300));
      await classify(tester, const [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Kirana & Pulses',
      ]);

      // The salary is June's, so the document's business date is the end of June.
      await setDateField(tester, const Key('business-date'), '2026-06-30');
      await pumpUntil(
        tester,
        'the business date to become June',
        () => visible('2026-06-30'),
      );

      // Paid, on 5 July, for work that belongs to June. Payment lives behind the
      // progressive disclosure precisely because it is not part of the fast path.
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 900));
      // The payment *section* exists as soon as the details open; the method and date
      // controls do not exist until the document is marked paid, because unpaid carries
      // neither and the database refuses a half-stated payment (spec §5.4).
      await pumpUntil(tester, 'the payment section', () => visible('PAYMENT'));
      expect(
        find.byKey(const Key('payment-method')),
        findsNothing,
        reason: 'unpaid states no method, and the form does not offer one',
      );
      await markPaidOn(tester, '2026-07-05');
      await tester.enterText(
        find.byKey(const Key('expense-notes')),
        '$_acceptanceMarker: June salary paid 5 July',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));

      final id = await saveExpense(tester);
      _createdExpenses.add(id);
      await syncAndAwaitNumber(tester, id);

      final repository = ExpenseRepository(boot.database);
      final saved = await repository.load(id);

      // The cost is June's. The payment is July's. They are different columns and they
      // are read by different reports, which is the whole of D-016.
      expect(saved!.row.paymentStatus, 'paid');
      expect(saved.row.paymentDate, '2026-07-05');
      expect(saved.row.paymentMethodId, isNotNull);
      expect(
        saved.periodContributions.single.pnlPeriodKey,
        '2026-06',
        reason: 'the contribution follows the business date, not the payment',
      );
      expect(saved.periodContributions.single.amountMinor, 8000000);

      expect(
        (await repository.contributionTotals(
          ExpenseContributionQuery(periodKey: '2026-06'),
        )).amount,
        Money.fromRupees(80000),
        reason: '₹80,000 of June cost',
      );
      expect(
        (await repository.contributionTotals(
          ExpenseContributionQuery(periodKey: '2026-07'),
        )).amount,
        Money.zero,
        reason:
            'and nothing at all in July — a payment date must never move an expense '
            'into another month s profitability',
      );
    });
  });

  // ── D-068 · financial cache retention ─────────────────────────────────────
  //
  // These re-run the Phase 2 scope and user-switch security paths, because D-068 and
  // local schema v8 changed what happens on exactly that boundary. Phase 2 proved that
  // *reference* data does not survive a user switch. Since D-068 the same must be true
  // of synced financial documents, and the one thing that must survive — the actor's own
  // unsent intent — must stop being browsable rather than stop existing.

  group('d068-switch', skip: _phase != 'd068-switch', () {
    testWidgets('a shared invoice does not survive into the next session', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // The Owner records and caches a complete shared bill: ₹58,000 across both
      // properties. This is the document a scoped manager must never inherit.
      final id = const Uuid().v4();
      final gateway = ExpenseGateway(Supabase.instance.client);
      final created = await gateway.create(
        arguments: {
          'p_id': id,
          'p_business_date': '2026-06-15',
          'p_total_minor': 5800000,
          'p_notes': '$_acceptanceMarker: D-068 shared electricity',
          'p_allocations': [
            {
              'business_unit_id': _ccr,
              'department_id': _seedId('dept:CCR/FB'),
              'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
              'category_id': _kirana,
              'amount_minor': 2500000,
            },
            {
              'business_unit_id': _hki,
              'department_id': _seedId('dept:HKI/HKI_UTIL'),
              'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
              'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
              'amount_minor': 3300000,
            },
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(created.isOk, isTrue, reason: '${created.refusalOrNull?.message}');
      _createdExpenses.add(id);

      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(id);

      final owned = await ExpenseRepository(boot.database).load(id);
      expect(owned!.row.visibility, 'complete');
      expect(
        owned.row.documentTotalMinor,
        5800000,
        reason: 'the Owner really did hold the whole document',
      );

      // The Owner also queues something that will not be delivered, so the retention
      // half of the policy is exercised by the same switch.
      final ownerId = await AuthorityStore(boot.database).ownerUserId();
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _ownerQueuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': "Owner's Queued Work"},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
          actorUserId: ownerId,
        ),
        now: DateTime.now().toUtc(),
      );
      final queuedBefore =
          (await boot.database.select(boot.database.syncOutbox).get()).length;

      await signOutThroughTheUi(tester);

      // Immediately after sign-out, before anybody else has signed in or pulled
      // anything. This is the moment D-053 is about: the previous user's scoped cache is
      // gone while the device still knows whose it was.
      final afterSignOut = await ExpenseRepository(
        boot.database,
      ).list(limit: 200);
      final unitsAfterSignOut = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        afterSignOut,
        isEmpty,
        reason:
            'sign-out purges the scoped financial cache (D-053, D-070). Left '
            '${afterSignOut.length} document(s); cached units after: '
            '${unitsAfterSignOut.length}',
      );

      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      // 1 · Nothing financial is inherited. Not the total, not the other property's
      //     share, not the line, not the contribution, not the attachment record.
      final db = boot.database;
      final repository = ExpenseRepository(db);

      // **Browsable**, which is the claim D-070 actually makes — not "no row exists".
      // A document still carrying the actor's own unsent, rejected or conflicted intent
      // is retained on purpose, stamped, and taken out of every canonical read; an
      // earlier version of this assertion demanded an empty table and failed the moment
      // a previous phase left a conflicted edit behind, which is the retention rule
      // working exactly as designed.
      final browsable = await repository.list();
      expect(
        browsable,
        isEmpty,
        reason:
            "the Owner's document must not be browsable by the next user. Still "
            'browsable: ${browsable.length} document(s), '
            '${browsable.where((e) => e.row.scopeRevokedAt == null).length} of them '
            'unstamped',
      );
      expect(
        await repository.query(const ExpenseFilter(includeVoided: true)),
        isEmpty,
        reason: 'and no filter combination reaches it either',
      );

      for (final retained in await db.select(db.expenses).get()) {
        expect(
          retained.scopeRevokedAt,
          isNotNull,
          reason:
              'the only rows that may survive are those kept for unsent work, and '
              'every one of them is stamped (D-070)',
        );
      }
      expect(
        (await repository.contributionTotals(
          ExpenseContributionQuery(periodKey: '2026-08'),
        )).amount,
        Money.zero,
        reason: 'nothing retained contributes to a figure',
      );

      // 2 · And the reference-data rule from Phase 2 still holds alongside it.
      expect(
        (await db.select(db.businessUnits).get()).map((u) => u.id).toSet(),
        {_ccr},
      );
      expect(
        await db.select(db.paymentMethods).get(),
        isNotEmpty,
        reason: 'company-wide reference data is not scoped (D-049)',
      );

      // 3 · The sign-out that does all this must not throw. Before local schema v8 it
      //     did, on any device that had synced an expense (D-068).
      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(
        violations,
        isEmpty,
        reason: 'no foreign key failure during purge',
      );

      // 4 · Somebody else's queued work survives, attributed to them.
      final queued = await db.select(db.syncOutbox).get();
      expect(queued, hasLength(queuedBefore));
      final owners = queued.firstWhere(
        (q) => q.mutationId == _ownerQueuedMutationId,
      );
      expect(owners.actorUserId, ownerId);
      final nowSignedIn = (await AuthorityStore(db).ownerUserId())!;
      expect(nowSignedIn, isNot(ownerId));
      final mine = await boot.outbox.dueEntries(
        now: DateTime.now().toUtc(),
        actorUserId: nowSignedIn,
      );
      expect(
        mine.map((e) => e.mutationId),
        isNot(contains(_ownerQueuedMutationId)),
        reason: "the new user may not push the previous user's intent (D-050)",
      );
    });

    testWidgets('CCR Manager → HKI Manager inherits no expense either', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      await signIn(tester, 'hki.manager@example.com');
      await expectSignedIn(tester, 'hki.manager@example.com');

      final db = boot.database;
      // Browsable, not "no row exists": a document carrying the actor's own unsent work
      // is retained on purpose and stamped (D-070).
      expect(await ExpenseRepository(db).list(), isEmpty);
      expect(
        (await db.select(db.businessUnits).get()).map((u) => u.id).toSet(),
        {_hki},
      );
      // Payment methods, not vendors, are the organisation-global probe here: the
      // development project seeds no vendor rows at all, so asserting vendors were
      // retained would assert a fixture that does not exist and would pass for the
      // wrong reason. That vendors are organisation-global and unaffected by scope is
      // a classification fact, proven where it lives, in the host suite (D-049).
      expect(
        await db.select(db.paymentMethods).get(),
        isNotEmpty,
        reason: 'company-wide reference data is not scoped (D-049)',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('d068-revoke', skip: _phase != 'd068-revoke', () {
    testWidgets('losing one property of two purges only that property', (
      tester,
    ) async {
      // The project lead's exact case: a manager holding Crystal Canopy and Hotel
      // Krishna loses Crystal Canopy. Grant, act, revoke, and put the grant back — all
      // through the ordinary API as the Owner, holding no privileged credential.
      await _admin.grantScope('hki.manager@example.com', 'manager', 'CCR');
      addTearDown(() => _admin.revokeScope('hki.manager@example.com', 'CCR'));

      await launch(tester);
      await signIn(tester, 'hki.manager@example.com');
      await expectSignedIn(tester, 'hki.manager@example.com');

      final db = boot.database;
      final repository = ExpenseRepository(db);

      // A shared bill, created by the Owner, and visible complete to this manager
      // because they currently hold both properties.
      final sharedId = await _admin.createSharedExpense(
        notes: '$_acceptanceMarker: D-068 partial revocation',
      );
      _createdExpenses.add(sharedId);

      // A Crystal-Canopy-only bill, which must disappear entirely.
      final ccrOnlyId = await _admin.createCcrExpense(
        notes: '$_acceptanceMarker: D-068 CCR only',
      );
      _createdExpenses.add(ccrOnlyId);

      final pull = ExpensePull(
        db: db,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(sharedId);
      await pull.pullOne(ccrOnlyId);

      final shared = await repository.load(sharedId);
      expect(
        shared!.row.visibility,
        'complete',
        reason: 'holding both properties, this manager sees the whole document',
      );
      expect(shared.row.documentTotalMinor, 5800000);

      // Work of their own, over Crystal Canopy, that has not been delivered. This is
      // the one thing a revocation must not destroy.
      final unsent = ExpenseDocument(
        id: const Uuid().v4(),
        orgId: shared.row.orgId,
        businessDate: BusinessDate.of(2026, 6, 15),
        businessDateSource: BusinessDateSource.derived,
        total: Money.fromRupees(1234),
        allocations: [
          ExpenseAllocation.wholePeriod(
            id: const Uuid().v4(),
            businessUnitId: _ccr,
            departmentId: _seedId('dept:CCR/FB'),
            sectionId: _seedId('sec:CCR/FB/FOOD_PROD'),
            categoryId: _kirana,
            amount: Money.fromRupees(1234),
            businessDate: BusinessDate.of(2026, 6, 15),
            categoryLabel: 'Kirana & Pulses',
          ),
        ],
        paymentStatus: PaymentStatus.unpaid,
        createdByUserId: 'acceptance',
        capturedAt: DateTime.now().toUtc(),
      );
      final unsentMutation = await repository.createLocally(
        unsent,
        actorUserId: (await AuthorityStore(db).ownerUserId())!,
        mutationId: const Uuid().v4(),
        now: DateTime.now().toUtc(),
      );
      final outboxBefore = (await db.select(db.syncOutbox).get()).length;

      // Now the Owner takes Crystal Canopy away, and the device refreshes authority —
      // which is what reconnecting does. Nothing is purged until the server says so.
      await _admin.revokeScope('hki.manager@example.com', 'CCR');

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      var confirmed = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        final state = container.read(sessionProvider);
        if (state is SessionReady &&
            !state.isStale &&
            !state.authority.scopedUnits.contains(_ccr)) {
          confirmed = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(
        confirmed,
        isTrue,
        reason: 'the server must positively confirm Crystal Canopy is gone',
      );

      // 1 · The Crystal-Canopy-only document is gone outright.
      expect(
        await repository.load(ccrOnlyId),
        isNull,
        reason: "a document wholly inside the revoked property does not remain",
      );

      // 2 · The shared bill keeps the Hotel Krishna share and loses the rest —
      //     including, and especially, the document total.
      final after = await repository.load(sharedId);
      expect(after, isNotNull, reason: 'Hotel Krishna is still held');
      expect(after!.row.visibility, 'scoped');
      expect(
        after.row.documentTotalMinor,
        isNull,
        reason: '₹58,000 beside ₹33,000 publishes Crystal Canopy s ₹25,000',
      );
      expect(after.visibleAmount, Money.fromRupees(33000));
      expect(after.allocations, hasLength(1));
      expect(after.allocations.single.businessUnitId, _hki);
      expect(after.attachments, isEmpty, reason: 'D-063 — complete only');

      // 3 · Neither forbidden figure survives anywhere on the device.
      final amounts = [
        ...(await db.select(db.expenses).get()).expand(
          (r) => [r.documentTotalMinor, r.visibleAmountMinor],
        ),
        ...(await db.select(db.expenseAllocations).get()).map(
          (r) => r.amountMinor,
        ),
        ...(await db.select(db.expensePeriodAllocations).get()).map(
          (r) => r.amountMinor,
        ),
      ];
      expect(amounts, isNot(contains(2500000)));
      expect(amounts, isNot(contains(5800000)));

      // 4 · The unsent intent survives, stops being browsable, and stays the actor's.
      final ledger = await repository.list();
      expect(
        ledger.map((e) => e.row.id),
        isNot(contains(unsent.id)),
        reason: 'retained is not the same as browsable',
      );
      final retained = await repository.listRetainedAfterRevocation();
      expect(retained.map((e) => e.row.id), contains(unsent.id));
      // Named rather than `.single`: an installation that has been used before
      // legitimately holds other retained work, and since D-074 it keeps holding it
      // rather than being handed to whoever signs in next.
      expect(
        retained.firstWhere((e) => e.row.id == unsent.id).allocations,
        hasLength(1),
      );
      expect(
        (await db.select(db.syncOutbox).get()).length,
        outboxBefore,
        reason: 'no queued work is ever destroyed by an authority change',
      );
      expect(
        await boot.outbox.statusOf(unsentMutation),
        isNot(OutboxStatus.done),
      );

      // 5 · Organisation-global data is untouched, and nothing broke on the way.
      //     Payment methods rather than vendors: the development project seeds no
      //     vendor rows, so asserting vendors survived would pass for the wrong reason.
      expect(await db.select(db.paymentMethods).get(), isNotEmpty);
      expect(
        (await db.select(db.businessUnits).get()).map((u) => u.id).toSet(),
        {_hki},
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  // ── Revenue, on the real Android client (Slice 8) ────────────────────────────
  //
  // Driven through the shipped screen and the shipped controller, against
  // `krishna-mis-dev`. Nothing here reaches into the repository to make a save happen:
  // if these pass, the path a person will actually use works — which is the assertion
  // D-077 exists to insist on, and the one that was missing when the attachment picker
  // reached two real devices without existing.

  /// Opens the sales entry screen from the central add action.
  Future<void> openRevenueEntry(WidgetTester tester) async {
    await pumpUntil(
      tester,
      'the add button',
      () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('quick-add-revenue')));
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the sales entry screen',
      () => visible('Sales category') || visible('Property'),
    );
  }

  Future<void> openRecentRevenue(WidgetTester tester) async {
    // Back to the shell first when a pushed route is on top. A phase that looks at a
    // sale twice would otherwise hunt for a home-screen button from inside the detail
    // page it is already standing on.
    for (var i = 0; i < 4; i++) {
      if (find.byType(FloatingActionButton).evaluate().isNotEmpty) break;
      final state = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (!state.canPop()) break;
      state.pop();
      await tester.pump(const Duration(milliseconds: 700));
    }
    await pumpUntil(
      tester,
      'the add button',
      () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('quick-open-recent-revenue')));
    await tester.pump(const Duration(milliseconds: 800));
    await pumpUntil(
      tester,
      'the recent sales screen',
      () =>
          find.byKey(const Key('revenue-recent-list')).evaluate().isNotEmpty ||
          find.byKey(const Key('revenue-recent-empty')).evaluate().isNotEmpty,
    );
  }

  Future<void> openRevenueMoreDetails(WidgetTester tester) async {
    await revealAndTap(tester, const Key('revenue-more-details'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntil(
      tester,
      'the notes field',
      () => find.byKey(const Key('revenue-notes')).evaluate().isNotEmpty,
    );
  }

  /// Records one sale through the screen, and returns its local id.
  ///
  /// The marker in the notes is how the cleanup phase finds it across a process
  /// boundary, and it survives everything this phase does to the document (D-071,
  /// D-076).
  Future<String> recordSale(
    WidgetTester tester, {
    required String unit,
    required String category,
    required String amount,
  }) async {
    await openRevenueEntry(tester);

    // The property picker appears only for a multi-property user, which the development
    // Owner is. A single-property manager would find it already chosen.
    final unitChip = find.byKey(Key('revenue-unit-$unit'));
    if (unitChip.evaluate().isNotEmpty) {
      await tester.tap(unitChip);
      await tester.pump(const Duration(milliseconds: 600));
    }

    await pumpUntil(
      tester,
      'the $category category',
      () => find.byKey(Key('revenue-category-$category')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(Key('revenue-category-$category')));
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the amount field',
      () => find.byType(TextField).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField).first, amount);
    await tester.pump(const Duration(milliseconds: 400));

    await openRevenueMoreDetails(tester);
    await tester.enterText(
      find.byKey(const Key('revenue-notes')),
      '$_acceptanceMarker $category',
    );
    await tester.pump(const Duration(milliseconds: 400));

    final before = await RevenueRepository(boot.database).list();
    await revealAndTap(tester, const Key('revenue-save'));
    await tester.pump(const Duration(seconds: 2));

    final after = await RevenueRepository(boot.database).list();
    expect(
      after.length,
      before.length + 1,
      reason: 'the save wrote exactly one sale',
    );
    return after.firstWhere((row) => !before.any((b) => b.id == row.id)).id;
  }

  Future<void> syncRevenueUntilNumbered(
    WidgetTester tester,
    String entryId, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await container.read(syncEngineProvider)?.pushOnce();
      final entry = await RevenueRepository(boot.database).load(entryId);
      if (entry?.txnNumber != null) return;
      await tester.pump(const Duration(seconds: 2));
    }
    fail('the sale never received a transaction number');
  }

  group('revenue-entry', skip: _phase != 'revenue-entry', () {
    testWidgets('the four verified categories record, sync and are numbered', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // Configuration first: the screen refuses to resolve tax without an
      // authoritative, fresh snapshot, which is the whole of D-113.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      // Entered amount → (gross, tax, net). The parity figures, through the UI.
      const expected = <String, (String, int, int, int)>{
        'RESTAURANT': ('CCR', 10000000, 476190, 9523810),
        'NANDBHOG': ('CCR', 1250000, 59524, 1190476),
        'ROOM': ('HKI', 6500000, 309524, 6190476),
        'BANQUET': ('HKI', 4034300, 0, 4034300),
      };
      const typed = <String, String>{
        'RESTAURANT': '100000',
        'NANDBHOG': '12500',
        'ROOM': '65000',
        'BANQUET': '40343',
      };

      final numbers = <String>{};
      for (final entry in expected.entries) {
        final id = await recordSale(
          tester,
          unit: entry.value.$1,
          category: entry.key,
          amount: typed[entry.key]!,
        );

        var saved = await RevenueRepository(boot.database).load(id);
        expect(saved, isNotNull, reason: entry.key);

        // Queued in the same transaction as the document. Whether the worker has
        // *already* delivered it by the time this line runs is a race the product wins
        // on a fast connection, so the assertion is about the queue entry existing
        // rather than about the number still being absent. The deterministic "never
        // fabricated locally" proof lives in `revenue-offline`, where no number can
        // arrive at all.
        final queued = await boot.database
            .select(boot.database.syncOutbox)
            .get();
        expect(
          queued.where((q) => q.entityId == id),
          hasLength(1),
          reason: 'saved and unqueued must be impossible',
        );
        expect(
          queued.firstWhere((q) => q.entityId == id).actorUserId,
          isNotNull,
          reason: 'no unattributed revenue intent may exist (D-050, D-074)',
        );

        // The figures the screen showed are the figures that were stored.
        final component = saved!.components.single;
        expect(component.gross.paise, entry.value.$2, reason: entry.key);
        expect(component.tax.paise, entry.value.$3, reason: entry.key);
        expect(component.net.paise, entry.value.$4, reason: entry.key);
        expect(
          component.net.paise + component.tax.paise,
          component.gross.paise,
        );

        await syncRevenueUntilNumbered(tester, id);
        saved = await RevenueRepository(boot.database).load(id);

        expect(saved!.txnNumber, startsWith('KI-REV-'), reason: entry.key);
        numbers.add(saved.txnNumber!);
        expect(
          saved.components.single.tax.paise,
          entry.value.$3,
          reason: '${entry.key}: acceptance did not reprice anything',
        );
      }

      expect(
        numbers,
        hasLength(4),
        reason: 'four sales, four distinct numbers from one FY sequence',
      );
    });
  });

  group('revenue-banquet-label', skip: _phase != 'revenue-banquet-label', () {
    testWidgets('an untaxed category is never labelled as GST-inclusive', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      await openRevenueEntry(tester);
      final unitChip = find.byKey(const Key('revenue-unit-HKI'));
      if (unitChip.evaluate().isNotEmpty) {
        await tester.tap(unitChip);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await pumpUntil(
        tester,
        'the Banquet category',
        () => find
            .byKey(const Key('revenue-category-BANQUET'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('revenue-category-BANQUET')));
      await tester.pump(const Duration(seconds: 1));

      // D-097, on the real device: the label follows the treatment as well as the
      // basis, so a figure carrying no GST is never described as containing some.
      expect(visible('AMOUNT BILLED TO THE CUSTOMER'), isTrue);
      expect(visible('CUSTOMER TOTAL (INCL. GST)'), isFalse);

      await tester.enterText(find.byType(TextField).first, '40343');
      await tester.pump(const Duration(milliseconds: 600));

      expect(visible('No GST'), isTrue);
      expect(
        visible('GST included'),
        isFalse,
        reason: 'there is none to include',
      );
    });
  });

  // ── Correcting and voiding a sale, on the phone (Slice 10 §45) ──────────────
  //
  // Everything below goes through the shipped detail route and the shipped entry form
  // in editing mode. Nothing constructs a controller, overrides a provider or reaches
  // past the interface to make a correction happen: if these pass, the path an operator
  // will actually use works (D-077).

  /// Opens the detail page for one sale from the recent list.
  Future<void> openRevenueDetail(WidgetTester tester, String id) async {
    await openRecentRevenue(tester);
    await pumpUntil(
      tester,
      'the row for the sale',
      () => find.byKey(Key('revenue-row-$id')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(Key('revenue-row-$id')));
    await tester.pump(const Duration(milliseconds: 900));
    await pumpUntil(
      tester,
      'the sale detail',
      () => find.byKey(const Key('revenue-detail-panel')).evaluate().isNotEmpty,
    );
  }

  /// Corrects the open sale through the shipped form, and returns when it is saved.
  Future<void> correctThroughTheForm(
    WidgetTester tester,
    String newAmount,
  ) async {
    await revealAndTap(tester, const Key('revenue-edit'));
    await tester.pump(const Duration(seconds: 1));
    await pumpUntil(
      tester,
      'the correction form',
      () => visible('Correct this sale'),
    );
    expect(
      visible('Save changes'),
      isTrue,
      reason: 'the form says it is correcting, not recording',
    );

    await tester.enterText(find.byType(TextField).first, newAmount);
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('revenue-edit', skip: _phase != 'revenue-edit', () {
    testWidgets('a Restaurant sale is corrected through the shipped surfaces', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      final id = await recordSale(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '100000',
      );
      await syncRevenueUntilNumbered(tester, id);

      final before = await RevenueRepository(boot.database).load(id);
      final number = before!.txnNumber!;
      expect(number, startsWith('KI-REV-'));
      expect(before.components.single.tax.paise, 476190);

      await openRevenueDetail(tester, id);
      await correctThroughTheForm(tester, '210000');

      // The live preview is the record: both come from TaxRule.compute, so a figure the
      // operator approves cannot differ from the one that is stored (D-118).
      expect(
        moneyShown('₹10,000.00').evaluate().isNotEmpty,
        isTrue,
        reason: '5% of 2,10,000 extracted, not added',
      );

      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));

      var saved = await RevenueRepository(boot.database).load(id);
      expect(saved!.components.single.gross.paise, 21000000);
      expect(saved.components.single.tax.paise, 1000000);
      expect(saved.components.single.net.paise, 20000000);
      expect(
        saved.txnNumber,
        number,
        reason: 'the number belongs to the document (D-072a)',
      );

      // Delivered once, and the server agrees to the paise.
      //
      // "Exactly one queued intent, on the version the form opened on" is asserted in
      // the host suite, where it can be. Here it cannot: the controller pushes as soon
      // as the save commits, so the queue may legitimately be empty by the next line —
      // the same race the Slice 8 report records for "no number yet". What is asserted
      // instead is the durable consequence, which is stronger: the server applied the
      // correction exactly once.
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(syncEngineProvider)?.pushOnce();
        final rows = await boot.database.select(boot.database.syncOutbox).get();
        if (rows.where((o) => o.entityId == id && o.status != 'done').isEmpty) {
          break;
        }
        await tester.pump(const Duration(seconds: 2));
      }

      final canonical = await _admin.revenueDocument(id);
      expect(canonical['gross_amount_minor'], 21000000);
      expect(canonical['tax_amount_minor'], 1000000);
      expect(canonical['net_amount_minor'], 20000000);
      expect(canonical['txn_number'], number);
      expect(canonical['component_count'], 1);

      final audit = await _admin.auditFor(id);
      expect(
        audit.where((r) => (r as Map<String, dynamic>)['action'] == 'edited'),
        hasLength(1),
        reason: 'one accepted update, however many times the worker ran',
      );
      expect(
        audit.where((r) => (r as Map<String, dynamic>)['action'] == 'created'),
        hasLength(1),
      );

      // And the detail surface explains the corrected sale from its own snapshot.
      saved = await RevenueRepository(boot.database).load(id);
      expect(saved!.components.single.taxRateBasisPoints, 500);
      await openRevenueDetail(tester, id);
      expect(visible('GST at 5%'), isTrue);
    });
  });

  group('revenue-edit-banquet', skip: _phase != 'revenue-edit-banquet', () {
    testWidgets('an untaxed sale stays untaxed through a correction', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      final id = await recordSale(
        tester,
        unit: 'HKI',
        category: 'BANQUET',
        amount: '40343',
      );
      await syncRevenueUntilNumbered(tester, id);
      final number = (await RevenueRepository(
        boot.database,
      ).load(id))!.txnNumber!;

      await openRevenueDetail(tester, id);
      await correctThroughTheForm(tester, '52500');

      // Still never told it contains GST (D-097).
      expect(visible('AMOUNT BILLED TO THE CUSTOMER'), isTrue);
      expect(visible('CUSTOMER TOTAL (INCL. GST)'), isFalse);
      expect(visible('No GST'), isTrue);

      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));

      final saved = await RevenueRepository(boot.database).load(id);
      final component = saved!.components.single;
      expect(component.tax.paise, 0);
      expect(component.net.paise, 5250000);
      expect(
        component.net.paise,
        component.enteredAmount.paise,
        reason: 'net equals what was entered, because no tax applies',
      );
      expect(saved.txnNumber, number);

      await openRevenueDetail(tester, id);
      expect(
        visible('No GST'),
        isTrue,
        reason: 'a treatment somebody chose, not a rate that came out at zero',
      );
      expect(visible('GST at 0%'), isFalse);
    });
  });

  group('revenue-conflict', skip: _phase != 'revenue-conflict', () {
    testWidgets(
      'an intervening correction surfaces as a conflict, and never merges',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));

        final id = await recordSale(
          tester,
          unit: 'CCR',
          category: 'RESTAURANT',
          amount: '100000',
        );
        await syncRevenueUntilNumbered(tester, id);
        final number = (await RevenueRepository(
          boot.database,
        ).load(id))!.txnNumber!;

        // Somebody else moves the record on while this device still holds the old
        // version. A real correction by a real authorised caller over the public API.
        await _admin.correctRevenue(id, 12000000);

        await openRevenueDetail(tester, id);
        await correctThroughTheForm(tester, '150000');
        await revealAndTap(tester, const Key('revenue-save'));
        await tester.pump(const Duration(seconds: 2));

        // Deliver it, and let the server refuse.
        final deadline = DateTime.now().add(const Duration(seconds: 120));
        while (DateTime.now().isBefore(deadline)) {
          await container.read(syncEngineProvider)?.pushOnce();
          final rows = await boot.database
              .select(boot.database.syncOutbox)
              .get();
          final entry = rows.where(
            (o) => o.entityId == id && o.status != 'done',
          );
          if (entry.isNotEmpty && entry.first.status == 'conflict') break;
          await tester.pump(const Duration(seconds: 2));
        }

        final intent =
            (await boot.database.select(boot.database.syncOutbox).get())
                .firstWhere((o) => o.entityId == id && o.status != 'done');
        expect(intent.status, 'conflict');

        // The phone says so, and offers exactly one thing.
        await openRevenueDetail(tester, id);
        await pumpUntil(
          tester,
          'the conflict banner',
          () => find
              .byKey(const Key('revenue-conflict-banner'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.byKey(const Key('revenue-conflict-review-latest')).evaluate(),
          isNotEmpty,
        );
        expect(
          visible('Overwrite anyway'),
          isFalse,
          reason: 'nothing auto-merges and nothing overwrites',
        );

        // The attempt is retained exactly as it was typed.
        final retained = await RevenueRepository(boot.database).load(id);
        expect(retained!.components.single.gross.paise, 15000000);

        // Canonical is still the other correction, untouched.
        final canonical = await _admin.revenueDocument(id);
        expect(canonical['gross_amount_minor'], 12000000);
        expect(canonical['txn_number'], number);

        // Review latest replaces the local copy with the server's, and does not merge.
        await revealAndTap(tester, const Key('revenue-conflict-review-latest'));
        await tester.pump(const Duration(seconds: 3));
        await pumpUntil(
          tester,
          'the comparison sheet',
          () => find
              .byKey(const Key('revenue-conflict-title'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.byKey(const Key('revenue-conflict-attempted')).evaluate(),
          isNotEmpty,
        );
        expect(
          find.byKey(const Key('revenue-conflict-current')).evaluate(),
          isNotEmpty,
        );

        await tester.tap(find.byKey(const Key('revenue-conflict-dismiss')));
        await tester.pump(const Duration(seconds: 1));

        final afterReview = await RevenueRepository(boot.database).load(id);
        expect(
          afterReview!.components.single.gross.paise,
          12000000,
          reason: 'the local copy is now the server\'s, not a merge of the two',
        );
      },
    );
  });

  group('revenue-void', skip: _phase != 'revenue-void', () {
    testWidgets(
      'voiding needs a reason, keeps the sale, and is not offered to a manager',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));

        final id = await recordSale(
          tester,
          unit: 'CCR',
          category: 'RESTAURANT',
          amount: '100000',
        );
        await syncRevenueUntilNumbered(tester, id);
        final number = (await RevenueRepository(
          boot.database,
        ).load(id))!.txnNumber!;

        await openRevenueDetail(tester, id);
        await revealAndTap(tester, const Key('revenue-void'));
        await tester.pump(const Duration(seconds: 1));
        await pumpUntil(
          tester,
          'the void dialog',
          () => find
              .byKey(const Key('revenue-void-dialog'))
              .evaluate()
              .isNotEmpty,
        );

        // Mandatory, and disabled until there is one.
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('revenue-void-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const Key('revenue-void-reason')),
          'acceptance: entered twice',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byKey(const Key('revenue-void-confirm')));
        await tester.pump(const Duration(seconds: 2));

        final deadline = DateTime.now().add(const Duration(seconds: 120));
        while (DateTime.now().isBefore(deadline)) {
          await container.read(syncEngineProvider)?.pushOnce();
          final rows = await boot.database
              .select(boot.database.syncOutbox)
              .get();
          if (rows
              .where((o) => o.entityId == id && o.status != 'done')
              .isEmpty) {
            break;
          }
          await tester.pump(const Duration(seconds: 2));
        }

        final canonical = await _admin.revenueDocument(id);
        expect(canonical['voided_at'], isNotNull);
        expect(canonical['void_reason'], contains('entered twice'));
        expect(
          canonical['txn_number'],
          number,
          reason: 'void, never delete: the document keeps its number (D-006)',
        );

        // Ordinary list behaviour: a voided sale leaves the phone's recent list, which
        // has no include-voided toggle and is not a ledger by design (Slice 8).
        //
        // The voided *detail* — reason, time, and neither control offered — is asserted
        // on Windows, where the ledger can show voided sales and there is therefore a
        // way to reach one through the interface. Reaching it here by pushing a route
        // directly would be asserting on a screen no operator can open, which proves
        // nothing about the product.
        await openRecentRevenue(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(
          find.byKey(Key('revenue-row-$id')).evaluate(),
          isEmpty,
          reason: 'a voided sale is out of the ordinary recent list',
        );
      },
    );

    testWidgets('recording a sale does not entitle a manager to void it', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      final id = await recordSale(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '100000',
      );
      await syncRevenueUntilNumbered(tester, id);

      await openRevenueDetail(tester, id);
      // Their own sale, inside the window: correctable.
      expect(find.byKey(const Key('revenue-edit')).evaluate(), isNotEmpty);
      // And still not voidable. `revenue.void` is the accountant's and the Owner's.
      expect(
        find.byKey(const Key('revenue-void')).evaluate(),
        isEmpty,
        reason: 'recording a sale is not the right to erase it',
      );
    });
  });

  group('revenue-user-switch', skip: _phase != 'revenue-user-switch', () {
    testWidgets(
      'an unsaved correction does not survive into the next person\'s session',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));

        final id = await recordSale(
          tester,
          unit: 'CCR',
          category: 'RESTAURANT',
          amount: '100000',
        );
        await syncRevenueUntilNumbered(tester, id);

        // A correction is opened and typed, and deliberately never saved.
        await openRevenueDetail(tester, id);
        await correctThroughTheForm(tester, '150000');

        await container.read(sessionProvider.notifier).signOut();
        await tester.pump(const Duration(seconds: 3));

        await signIn(tester, 'ccr.manager@example.com');
        await expectSignedIn(tester, 'ccr.manager@example.com');
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 3));

        // The draft is gone with the screen; nothing persisted it.
        expect(visible('Correct this sale'), isFalse);
        expect(
          moneyShown('₹1,50,000.00').evaluate().isNotEmpty,
          isFalse,
          reason: 'the next person inherits no unsaved figure',
        );

        // And the stored sale is unchanged: an abandoned correction writes nothing.
        final stored = await RevenueRepository(boot.database).load(id);
        if (stored != null) {
          expect(
            stored.components.single.gross.paise,
            10000000,
            reason: 'nothing was written by opening a form',
          );
        }

        // No queued intent for it, from anybody.
        final queued =
            (await boot.database.select(boot.database.syncOutbox).get()).where(
              (o) => o.entityId == id && o.status != 'done',
            );
        expect(queued, isEmpty);
      },
    );
  });

  group('revenue-offline', skip: _phase != 'revenue-offline', () {
    testWidgets('a sale is recorded with no network and syncs once on reconnect', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      // Configuration arrives while the network still works. D-112 then permits offline
      // creation for 24 hours, which is what this phase exercises.
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      _transport.online = false;

      final id = await recordSale(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '80000',
      );

      var saved = await RevenueRepository(boot.database).load(id);
      expect(
        saved!.txnNumber,
        isNull,
        reason: 'nothing may claim a server-issued number offline',
      );
      expect(saved.components.single.tax.paise, 380952);

      // The queue holds it, attributed, and the screen says so rather than failing.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(queued.where((q) => q.entityId == id), hasLength(1));
      expect(
        queued.firstWhere((q) => q.entityId == id).actorUserId,
        isNotNull,
        reason: 'no unattributed revenue intent may exist (D-050, D-074)',
      );

      // The list says it has not reached the server. *Which* not-synced state depends on
      // whether the controller's push attempt had already failed by now — a race, and
      // not the claim worth asserting. What matters is that nothing says "Synced" for
      // something the server has never seen.
      await openRecentRevenue(tester);
      expect(
        visible('Pending Sync') || visible('Sync Failed'),
        isTrue,
        reason: 'the sale is visibly not yet on the server',
      );
      expect(visible('Synced'), isFalse);

      // A push while offline changes nothing durable and invents nothing.
      await container.read(syncEngineProvider)?.pushOnce();
      await tester.pump(const Duration(seconds: 1));
      saved = await RevenueRepository(boot.database).load(id);
      expect(saved!.txnNumber, isNull);

      _transport.online = true;
      await syncRevenueUntilNumbered(tester, id);

      saved = await RevenueRepository(boot.database).load(id);
      expect(saved!.txnNumber, startsWith('KI-REV-'));
      expect(
        saved.components.single.tax.paise,
        380952,
        reason: 'the figures the operator approved survived the round trip',
      );

      // One record, not two: the same mutation id was re-sent, never a fresh one.
      final all = await RevenueRepository(boot.database).list();
      expect(all.where((row) => row.id == id), hasLength(1));
    });
  });

  // ── The Windows revenue ledger, in the real executable (Slice 9) ─────────────
  //
  // Driven through the shipped desktop surfaces against `krishna-mis-dev`. Nothing here
  // reaches into the repository to make a save happen: if these pass, the path a finance
  // user will actually use works, which is the assertion D-077 exists to insist on.

  /// Opens Transactions and switches to the Sales tab.
  Future<void> openRevenueLedger(WidgetTester tester) async {
    await pumpUntil(
      tester,
      'the Transactions destination',
      () => visible('Transactions'),
    );
    await tester.tap(find.text('Transactions').last);
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the Expenses / Sales tabs',
      () => find.byKey(const Key('transactions-tabs')).evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Sales').last);
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the Add Sale action',
      () => find.byKey(const Key('add-revenue')).evaluate().isNotEmpty,
    );
  }

  /// Records one sale through the desktop screen, and returns its local id.
  Future<String> recordSaleOnWindows(
    WidgetTester tester, {
    required String unit,
    required String category,
    required String amount,
  }) async {
    await revealAndTap(tester, const Key('add-revenue'));
    await tester.pump(const Duration(milliseconds: 900));

    await pumpUntil(
      tester,
      'the sales entry screen',
      () => visible('Sales category') || visible('Property'),
    );

    final unitChip = find.byKey(Key('revenue-unit-$unit'));
    if (unitChip.evaluate().isNotEmpty) {
      await tester.tap(unitChip);
      await tester.pump(const Duration(milliseconds: 600));
    }

    await pumpUntil(
      tester,
      'the $category category',
      () => find.byKey(Key('revenue-category-$category')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(Key('revenue-category-$category')));
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the amount field',
      () => find.byType(TextField).evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField).first, amount);
    await tester.pump(const Duration(milliseconds: 500));

    await revealAndTap(tester, const Key('revenue-more-details'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntil(
      tester,
      'the notes field',
      () => find.byKey(const Key('revenue-notes')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('revenue-notes')),
      '$_acceptanceMarker $category',
    );
    await tester.pump(const Duration(milliseconds: 400));

    final before = await RevenueRepository(boot.database).list();
    await revealAndTap(tester, const Key('revenue-save'));
    await tester.pump(const Duration(seconds: 2));

    final after = await RevenueRepository(boot.database).list();
    expect(
      after.length,
      before.length + 1,
      reason: 'the save wrote exactly one sale',
    );
    return after.firstWhere((row) => !before.any((b) => b.id == row.id)).id;
  }

  Future<void> syncRevenueOnWindows(
    WidgetTester tester,
    String entryId, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await container.read(syncEngineProvider)?.pushOnce();
      final entry = await RevenueRepository(boot.database).load(entryId);
      if (entry?.txnNumber != null) return;
      await tester.pump(const Duration(seconds: 2));
    }
    fail('the sale never received a transaction number');
  }

  group('windows-revenue', skip: _phase != 'windows-revenue', () {
    testWidgets('the four categories record, sync, filter and explain themselves', (
      tester,
    ) async {
      expect(
        boot.shellKind.name,
        isNot('mobile'),
        reason:
            'this phase is about the desktop ledger; run it with -d windows',
      );

      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      await openRevenueLedger(tester);

      // Entered amount → (gross, tax, net). The parity figures, through the desktop UI.
      const expected = <String, (String, int, int, int)>{
        'RESTAURANT': ('CCR', 10000000, 476190, 9523810),
        'NANDBHOG': ('CCR', 1250000, 59524, 1190476),
        'ROOM': ('HKI', 6500000, 309524, 6190476),
        'BANQUET': ('HKI', 4034300, 0, 4034300),
      };
      const typed = <String, String>{
        'RESTAURANT': '100000',
        'NANDBHOG': '12500',
        'ROOM': '65000',
        'BANQUET': '40343',
      };

      final ids = <String, String>{};
      for (final entry in expected.entries) {
        ids[entry.key] = await recordSaleOnWindows(
          tester,
          unit: entry.value.$1,
          category: entry.key,
          amount: typed[entry.key]!,
        );

        final saved = await RevenueRepository(
          boot.database,
        ).load(ids[entry.key]!);
        final component = saved!.components.single;
        expect(component.gross.paise, entry.value.$2, reason: entry.key);
        expect(component.tax.paise, entry.value.$3, reason: entry.key);
        expect(component.net.paise, entry.value.$4, reason: entry.key);
      }

      // ── The ledger lists them, and the numbers arrive ───────────────────────
      final numbers = <String>{};
      for (final id in ids.values) {
        await syncRevenueOnWindows(tester, id);
        final saved = await RevenueRepository(boot.database).load(id);
        expect(saved!.txnNumber, startsWith('KI-REV-'));
        numbers.add(saved.txnNumber!);
      }
      expect(
        numbers,
        hasLength(4),
        reason: 'four sales, four distinct numbers from one FY sequence',
      );

      // Reconciliation updates the same rows rather than creating new ones.
      final repository = RevenueRepository(boot.database);
      for (final id in ids.values) {
        final matching = (await repository.list()).where((r) => r.id == id);
        expect(matching, hasLength(1), reason: 'one act, one row');
      }

      // ── The ledger surface itself ──────────────────────────────────────────
      container
        ..invalidate(filteredRevenueProvider)
        ..invalidate(revenueHasMoreProvider);
      await tester.pump(const Duration(seconds: 2));
      await pumpUntil(
        tester,
        'the sales ledger table',
        () =>
            find.byKey(const Key('revenue-ledger-table')).evaluate().isNotEmpty,
      );

      // Filtering happens in SQL and narrows the result, asserted against the
      // repository — the same shape the Windows expense ledger phase uses, because a
      // count of rows on screen is a count of what a viewport happened to build.
      final restaurantOnly = await repository.query(
        RevenueFilter(
          revenueCategoryId: (await (boot.database.select(
            boot.database.revenueCategories,
          )..where((c) => c.code.equals('RESTAURANT'))).getSingle()).id,
        ),
      );
      expect(restaurantOnly, isNotEmpty);
      expect(
        restaurantOnly.every(
          (r) => r.revenueCategoryId == restaurantOnly.first.revenueCategoryId,
        ),
        isTrue,
      );

      final firstPage = await repository.query(const RevenueFilter(), limit: 2);
      final secondPage = await repository.query(
        const RevenueFilter(),
        limit: 2,
        offset: 2,
      );
      expect(firstPage, hasLength(2));
      expect(
        firstPage
            .map((r) => r.id)
            .toSet()
            .intersection(secondPage.map((r) => r.id).toSet()),
        isEmpty,
        reason: 'paging in SQL, with no row on two pages',
      );

      // ── The detail panel explains a sale from its own snapshot ──────────────
      final banquetId = ids['BANQUET']!;
      await pumpUntil(
        tester,
        'the Banquet row',
        () => find
            .byKey(Key('revenue-ledger-row-$banquetId'))
            .evaluate()
            .isNotEmpty,
      );
      await revealAndTap(tester, Key('revenue-ledger-row-$banquetId'));
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.byKey(const Key('revenue-detail-panel')).evaluate().isNotEmpty,
        isTrue,
      );
      // The distinction the panel exists to keep: `none` is a treatment somebody chose,
      // not a rate somebody set (D-091).
      expect(visible('No GST'), isTrue);
      expect(visible('GST at 0%'), isFalse);

      // And no correction control is offered — that is Slice 10.
      expect(find.widgetWithText(FilledButton, 'Void'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Edit'), findsNothing);

      final restaurantId = ids['RESTAURANT']!;
      await revealAndTap(tester, Key('revenue-ledger-row-$restaurantId'));
      await tester.pump(const Duration(seconds: 1));
      expect(visible('GST at 5%'), isTrue);
    });
  });

  // ── Correcting and voiding a sale on the finance workstation (§46) ──────────

  /// Opens the ledger's detail panel for one sale.
  Future<void> openWindowsRevenueDetail(WidgetTester tester, String id) async {
    await openRevenueLedger(tester);
    await pumpUntil(
      tester,
      'the ledger row for the sale',
      () => find.byKey(Key('revenue-ledger-row-$id')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
    await tester.pump(const Duration(milliseconds: 900));
    await pumpUntil(
      tester,
      'the detail panel',
      () => find.byKey(const Key('revenue-detail-panel')).evaluate().isNotEmpty,
    );
  }

  group('windows-revenue-edit', skip: _phase != 'windows-revenue-edit', () {
    testWidgets('a sale is corrected from the ledger, at realistic window sizes', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      await openRevenueLedger(tester);
      final id = await recordSaleOnWindows(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '100000',
      );
      await syncRevenueOnWindows(tester, id);
      final before = await RevenueRepository(boot.database).load(id);
      final number = before!.txnNumber!;

      await openWindowsRevenueDetail(tester, id);
      expect(find.byKey(const Key('revenue-edit')).evaluate(), isNotEmpty);

      await revealAndTap(tester, const Key('revenue-edit'));
      await tester.pump(const Duration(seconds: 1));
      await pumpUntil(
        tester,
        'the correction form',
        () => visible('Correct this sale'),
      );
      expect(visible('Save changes'), isTrue);

      // The edit form at an ordinary laptop width, which is where D-123's drift showed.
      expect(
        tester.takeException(),
        isNull,
        reason: 'the correction form must not overflow a 1366pt laptop',
      );

      await tester.enterText(find.byType(TextField).first, '210000');
      await tester.pump(const Duration(milliseconds: 700));
      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));

      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(syncEngineProvider)?.pushOnce();
        final rows = await boot.database.select(boot.database.syncOutbox).get();
        if (rows.where((o) => o.entityId == id && o.status != 'done').isEmpty) {
          break;
        }
        await tester.pump(const Duration(seconds: 2));
      }

      // One document, one number, the corrected figures, delivered once.
      final canonical = await _admin.revenueDocument(id);
      expect(canonical['txn_number'], number);
      expect(canonical['gross_amount_minor'], 21000000);
      expect(canonical['tax_amount_minor'], 1000000);
      expect(canonical['net_amount_minor'], 20000000);
      expect(canonical['component_count'], 1);

      // The same ledger row, updated in place.
      await openRevenueLedger(tester);
      await pumpUntil(
        tester,
        'the updated ledger row',
        () => find.byKey(Key('revenue-ledger-row-$id')).evaluate().isNotEmpty,
      );
      // **Read the chip, not a string.** The Windows ledger renders its sync
      // state `compact`, which is an icon and a colour and deliberately no text
      // — it is a dense financial table, and a word per row would be noise. So
      // `find.text('Synced')` can never match here, and the assertion that used
      // to stand on this line was passing on text belonging to a surface that
      // happened still to be mounted. It proved nothing about the ledger.
      //
      // Asserting the widget's own state is both satisfiable and stronger: it is
      // what the operator actually sees rendered (D-160).
      // And it CONVERGES on Synced rather than being caught mid-cycle. The chip is
      // fed by a Drift stream over the outbox, so the frame in which the last
      // intent is marked done is not necessarily the frame in which the row
      // repaints. Waiting for the condition rather than for a number of frames is
      // the rule D-152 records; asserting immediately here reported `syncing` and
      // would have been read as a stuck queue.
      SyncState chipState() => tester
          .widget<SyncStateChip>(
            find.descendant(
              of: find.byKey(Key('revenue-ledger-row-$id')),
              matching: find.byType(SyncStateChip),
            ),
          )
          .state;
      await pumpUntil(
        tester,
        'the ledger row to settle on Synced',
        () => chipState() == SyncState.synced,
      );
      expect(
        chipState(),
        SyncState.synced,
        reason: 'the corrected sale is on the server and the row says so',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('windows-revenue-void', skip: _phase != 'windows-revenue-void', () {
    testWidgets(
      'voiding hides the sale from the ledger unless voided are included',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');

        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));

        await openRevenueLedger(tester);
        final id = await recordSaleOnWindows(
          tester,
          unit: 'CCR',
          category: 'RESTAURANT',
          amount: '100000',
        );
        await syncRevenueOnWindows(tester, id);
        final number = (await RevenueRepository(
          boot.database,
        ).load(id))!.txnNumber!;

        await openWindowsRevenueDetail(tester, id);
        await revealAndTap(tester, const Key('revenue-void'));
        await tester.pump(const Duration(seconds: 1));
        await pumpUntil(
          tester,
          'the void dialog',
          () => find
              .byKey(const Key('revenue-void-dialog'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'the void dialog must not overflow',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('revenue-void-confirm')),
              )
              .onPressed,
          isNull,
          reason: 'a reason is mandatory',
        );

        await tester.enterText(
          find.byKey(const Key('revenue-void-reason')),
          'acceptance: duplicated evening summary',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byKey(const Key('revenue-void-confirm')));
        await tester.pump(const Duration(seconds: 2));

        final deadline = DateTime.now().add(const Duration(seconds: 120));
        while (DateTime.now().isBefore(deadline)) {
          await container.read(syncEngineProvider)?.pushOnce();
          final rows = await boot.database
              .select(boot.database.syncOutbox)
              .get();
          if (rows
              .where((o) => o.entityId == id && o.status != 'done')
              .isEmpty) {
            break;
          }
          await tester.pump(const Duration(seconds: 2));
        }

        final canonical = await _admin.revenueDocument(id);
        expect(canonical['voided_at'], isNotNull);
        expect(
          canonical['void_reason'],
          contains('duplicated evening summary'),
        );
        expect(canonical['txn_number'], number);

        // Absent from the ordinary ledger, present when voided are included.
        await openRevenueLedger(tester);
        await pumpUntil(tester, 'the ledger', () => visible('Sales'));
        expect(
          find.byKey(Key('revenue-ledger-row-$id')).evaluate(),
          isEmpty,
          reason: 'a voided sale is out of the ordinary ledger',
        );

        await revealAndTap(tester, const Key('revenue-filter-voided'));
        await tester.pump(const Duration(seconds: 2));
        await pumpUntil(
          tester,
          'the voided sale',
          () => find.byKey(Key('revenue-ledger-row-$id')).evaluate().isNotEmpty,
        );

        await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
        await tester.pump(const Duration(seconds: 1));
        expect(visible('acceptance: duplicated evening summary'), isTrue);
        expect(
          find.byKey(const Key('revenue-voided-note')).evaluate(),
          isNotEmpty,
        );
        expect(find.byKey(const Key('revenue-edit')).evaluate(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('windows-revenue-conflict', skip: _phase != 'windows-revenue-conflict', () {
    testWidgets('a stale correction conflicts, and Review latest resolves it', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      await openRevenueLedger(tester);
      final id = await recordSaleOnWindows(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '100000',
      );
      await syncRevenueOnWindows(tester, id);

      // Somebody else corrects it while this workstation holds the old version.
      await _admin.correctRevenue(id, 12000000);

      await openWindowsRevenueDetail(tester, id);
      await revealAndTap(tester, const Key('revenue-edit'));
      await tester.pump(const Duration(seconds: 1));
      await pumpUntil(
        tester,
        'the correction form',
        () => visible('Correct this sale'),
      );
      await tester.enterText(find.byType(TextField).first, '150000');
      await tester.pump(const Duration(milliseconds: 700));
      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));

      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(syncEngineProvider)?.pushOnce();
        final rows = await boot.database.select(boot.database.syncOutbox).get();
        // The **live** intent, not the completed create beside it: a synced document
        // keeps its create entry, and reading `.first` would report `done` for ever.
        final entry = rows.where((o) => o.entityId == id && o.status != 'done');
        if (entry.isNotEmpty && entry.first.status == 'conflict') break;
        await tester.pump(const Duration(seconds: 2));
      }

      // The conflict state at a real window size, which is the one D-123 says is
      // dangerous: the states differ in width and this is the one an operator most
      // needs to read.
      await openWindowsRevenueDetail(tester, id);
      // The sync state is read from the outbox asynchronously, so the banner arrives a
      // frame after the panel does. Waited for rather than assumed - and it must still
      // arrive, which is what makes this a wait and not a weakening.
      await pumpUntil(
        tester,
        'the conflict banner',
        () => find
            .byKey(const Key('revenue-conflict-banner'))
            .evaluate()
            .isNotEmpty,
      );
      expect(tester.takeException(), isNull);

      await revealAndTap(tester, const Key('revenue-conflict-review-latest'));
      await tester.pump(const Duration(seconds: 3));
      await pumpUntil(
        tester,
        'the comparison sheet',
        () => find
            .byKey(const Key('revenue-conflict-title'))
            .evaluate()
            .isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('revenue-conflict-dismiss')));
      await tester.pump(const Duration(seconds: 1));

      // Replaced by the server's, never merged.
      final local = await RevenueRepository(boot.database).load(id);
      expect(local!.components.single.gross.paise, 12000000);
      final canonical = await _admin.revenueDocument(id);
      expect(canonical['gross_amount_minor'], 12000000);
    });
  });

  group('windows-revenue-offline', skip: _phase != 'windows-revenue-offline', () {
    testWidgets('a sale recorded with no network syncs once on reconnect', (
      tester,
    ) async {
      expect(boot.shellKind.name, isNot('mobile'));

      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      // Configuration arrives while the network works. D-112 then permits offline
      // creation for 24 hours, which is what this phase exercises.
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      await openRevenueLedger(tester);
      _transport.online = false;

      final id = await recordSaleOnWindows(
        tester,
        unit: 'CCR',
        category: 'RESTAURANT',
        amount: '80000',
      );

      final repository = RevenueRepository(boot.database);
      var saved = await repository.load(id);
      expect(
        saved!.txnNumber,
        isNull,
        reason: 'nothing may claim a server-issued number offline',
      );
      expect(saved.components.single.tax.paise, 380952);

      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(queued.where((q) => q.entityId == id), hasLength(1));
      expect(
        queued.firstWhere((q) => q.entityId == id).actorUserId,
        isNotNull,
        reason: 'no unattributed revenue intent may exist (D-050, D-074)',
      );

      // The row is in the ledger immediately, and visibly not yet on the server.
      container.invalidate(filteredRevenueProvider);
      await tester.pump(const Duration(seconds: 1));
      final rows = await repository.list();
      expect(rows.where((r) => r.id == id), hasLength(1));
      expect(
        rows.firstWhere((r) => r.id == id).syncState,
        isNot(SyncState.synced),
      );

      // A push while offline changes nothing durable and invents nothing.
      await container.read(syncEngineProvider)?.pushOnce();
      await tester.pump(const Duration(seconds: 1));
      expect((await repository.load(id))!.txnNumber, isNull);

      _transport.online = true;
      await syncRevenueOnWindows(tester, id);

      saved = await repository.load(id);
      expect(saved!.txnNumber, startsWith('KI-REV-'));
      expect(
        saved.components.single.tax.paise,
        380952,
        reason: 'the figures the operator approved survived the round trip',
      );
      expect(
        (await repository.list()).where((r) => r.id == id),
        hasLength(1),
        reason: 'the same intent was re-sent, never a fresh one',
      );
    });
  });

  // ── Phase 4 Slice 11 · evidence, on the real client ────────────────────────
  //
  // Two phases, on both platforms. What they prove that nothing below them can: that the
  // production composition root reaches the real picker (asserted by
  // `attachment_source_wiring_test.dart` from the host, and exercised here through the
  // shipped screen), and that a sale and its evidence sync in the right order against a
  // real server with a real worker.
  //
  // The picker itself is still injected at the point the OS returns a file — the harness
  // cannot drive a separate activity — and the manual smoke test D-077 pays for stays in
  // the release checklist.

  /// Opens the sales entry form the way this shell offers it.
  ///
  /// The phone reaches it through the central add action; the workstation through
  /// Transactions → Sales → Add Sale (D-120). Branching here rather than writing the
  /// phase twice is what keeps the two runs about the same thing.
  Future<void> openRevenueEntryForm(WidgetTester tester) async {
    if (boot.shellKind.name == 'mobile') {
      await openRevenueEntry(tester);
      return;
    }
    await openRevenueLedger(tester);
    await revealAndTap(tester, const Key('add-revenue'));
    await tester.pump(const Duration(milliseconds: 900));
    await pumpUntil(
      tester,
      'the sales entry screen',
      () => visible('Sales category') || visible('Property'),
    );
  }

  /// Opens one sale's detail surface, the way this shell offers it.
  Future<void> openRevenueDetailForShell(WidgetTester tester, String id) async {
    if (boot.shellKind.name == 'mobile') {
      await openRevenueDetail(tester, id);
    } else {
      await openWindowsRevenueDetail(tester, id);
    }
  }

  /// Attaches a file through the shipped strip, wherever it is on this shell.
  Future<void> attachThroughTheSurface(WidgetTester tester) async {
    final intake = boot.shellKind.name == 'mobile'
        ? AttachmentIntake.gallery
        : AttachmentIntake.file;
    await pumpUntil(
      tester,
      'the ${intake.name} attachment control',
      () => find.byKey(Key('attach-${intake.name}')).evaluate().isNotEmpty,
    );
    await revealAndTap(tester, Key('attach-${intake.name}'));
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.byKey(const Key('attachment-refusal')),
      findsNothing,
      reason: 'staging refused the file',
    );
  }

  /// Drives the shared worker until the sale's evidence is confirmed on the server.
  Future<void> uploadEvidenceUntilConfirmed(
    WidgetTester tester,
    String entryId, {
    Duration timeout = const Duration(seconds: 150),
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await container.read(attachmentUploadWorkerProvider)?.uploadDue();
      final files = await RevenueRepository(
        boot.database,
      ).attachmentsOf(entryId);
      if (files.isNotEmpty && files.every((a) => a.uploadState.isOnServer)) {
        return;
      }
      final failed = files.where((a) => a.uploadState.needsAttention).toList();
      if (failed.isNotEmpty) {
        final rows = await boot.database
            .customSelect(
              "SELECT last_error FROM revenue_attachments "
              "WHERE upload_state IN ('retryNeeded','rejected')",
            )
            .get();
        fail(
          'the evidence would not upload: '
          '${rows.map((r) => r.data['last_error']).join('; ')}',
        );
      }
      await tester.pump(const Duration(seconds: 2));
    }
    fail('the evidence was never confirmed on the server');
  }

  group('revenue-attachment', skip: _phase != 'revenue-attachment', () {
    testWidgets('a Restaurant sale carries evidence from the form to the bucket', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      // The whole workflow through the shipped screen: property, category, amount,
      // More details, attach, Save.
      await openRevenueEntryForm(tester);
      final unitChip = find.byKey(const Key('revenue-unit-CCR'));
      if (unitChip.evaluate().isNotEmpty) {
        await tester.tap(unitChip);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await pumpUntil(
        tester,
        'the Restaurant category',
        () => find
            .byKey(const Key('revenue-category-RESTAURANT'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('revenue-category-RESTAURANT')));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.enterText(find.byType(TextField).first, '100000');
      await tester.pump(const Duration(milliseconds: 400));

      await revealAndTap(tester, const Key('revenue-more-details'));
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the notes field',
        () => find.byKey(const Key('revenue-notes')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('revenue-notes')),
        '$_acceptanceMarker slice11 evidence',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await attachThroughTheSurface(tester);
      expect(
        visible('synthetic-receipt.jpg'),
        isTrue,
        reason: 'the operator can see what they attached',
      );

      final before = await RevenueRepository(boot.database).list();
      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));
      final after = await RevenueRepository(boot.database).list();
      final id = after
          .firstWhere((row) => !before.any((b) => b.id == row.id))
          .id;

      // Exactly one file was recorded against the sale.
      //
      // What is deliberately *not* asserted here is "it has not uploaded yet". The
      // controller pushes as soon as the save commits and nudges the worker straight
      // after, so against a real server on a fast connection the whole chain can finish
      // inside this pump — and a test that required it to be unfinished would be
      // asserting that the product is slow. The ordering rule it was reaching for
      // (D-073 §2) is proven where it can actually be observed: the offline phase, where
      // no number can arrive and the upload provably cannot start. The same lesson the
      // Slice 8 report records for "no number yet" (D-119).
      final staged = await RevenueRepository(boot.database).attachmentsOf(id);
      expect(staged, hasLength(1));

      await syncRevenueUntilNumbered(tester, id);
      final numbered = await RevenueRepository(boot.database).load(id);
      expect(numbered!.txnNumber, startsWith('KI-REV-'));
      expect(
        numbered.components.single.tax.paise,
        476190,
        reason: '5% extracted from the customer total, exactly as ever',
      );

      await uploadEvidenceUntilConfirmed(tester, id);

      // One object, one metadata row, and both belong to this sale.
      final client = Supabase.instance.client;
      final rows = await client
          .from('revenue_attachments')
          .select()
          .eq('revenue_entry_id', id);
      expect(rows, hasLength(1));
      final path = rows.first['storage_path'] as String;
      expect(path, contains('/revenue/$id/'));
      final bytes = await client.storage
          .from(financialAttachmentBucket)
          .download(path);
      expect(bytes, isNotEmpty);
      expect(
        rows.first['content_hash'],
        (await RevenueRepository(
          boot.database,
        ).attachmentsOf(id)).single.contentHash,
        reason: 'confirmation is about bytes, not about an HTTP status',
      );

      // And the sale is untouched by all of it.
      final finalEntry = await RevenueRepository(boot.database).load(id);
      expect(finalEntry!.gross.paise, numbered.gross.paise);
      expect(finalEntry.tax.paise, numbered.tax.paise);
      expect(finalEntry.net.paise, numbered.net.paise);
      expect(finalEntry.txnNumber, numbered.txnNumber);
      expect(finalEntry.rowVersion, numbered.rowVersion);

      // The detail surface shows it, by name and state, with no storage key.
      await openRevenueDetailForShell(tester, id);
      expect(visible('EVIDENCE'), isTrue);
      expect(visible('synthetic-receipt.jpg'), isTrue);
      expect(
        visible('org/'),
        isFalse,
        reason: 'a path is implementation, not information',
      );
    });
  });

  group('revenue-attachment-offline', skip: _phase != 'revenue-attachment-offline', () {
    testWidgets('a sale and its evidence recorded offline survive a reconnect', (
      tester,
    ) async {
      final source = _SyntheticAttachmentSource();
      addTearDown(source.dispose);
      addTearDown(() => _transport.online = true);

      await launch(tester, attachmentSource: source);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));

      // Off the air. Everything from here is local, and the configuration snapshot
      // this device already holds is what makes the sale resolvable at all (D-112).
      _transport.online = false;

      await openRevenueEntryForm(tester);
      final unitChip = find.byKey(const Key('revenue-unit-CCR'));
      if (unitChip.evaluate().isNotEmpty) {
        await tester.tap(unitChip);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await pumpUntil(
        tester,
        'the Restaurant category',
        () => find
            .byKey(const Key('revenue-category-RESTAURANT'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('revenue-category-RESTAURANT')));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.enterText(find.byType(TextField).first, '64000');
      await tester.pump(const Duration(milliseconds: 400));

      await revealAndTap(tester, const Key('revenue-more-details'));
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the notes field',
        () => find.byKey(const Key('revenue-notes')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('revenue-notes')),
        '$_acceptanceMarker slice11 offline evidence',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await attachThroughTheSurface(tester);

      final before = await RevenueRepository(boot.database).list();
      await revealAndTap(tester, const Key('revenue-save'));
      await tester.pump(const Duration(seconds: 2));
      final after = await RevenueRepository(boot.database).list();
      final id = after
          .firstWhere((row) => !before.any((b) => b.id == row.id))
          .id;

      final offline = await RevenueRepository(boot.database).load(id);
      expect(
        offline!.txnNumber,
        isNull,
        reason: 'a number is never invented locally (spec §8.4)',
      );
      final staged = await RevenueRepository(boot.database).attachmentsOf(id);
      expect(staged, hasLength(1));
      final localPath = staged.single.localStagingPath!;
      expect(
        File(localPath).existsSync(),
        isTrue,
        reason: 'the bytes are in app-private storage, not a content URI',
      );

      // A push that cannot reach anybody changes nothing durable, and the worker is
      // driven anyway so its refusal is exercised rather than assumed.
      await container.read(syncEngineProvider)?.pushOnce();
      await container.read(attachmentUploadWorkerProvider)?.uploadDue();
      expect(
        (await RevenueRepository(boot.database).load(id))!.txnNumber,
        isNull,
      );

      // "Restart": the database is closed and reopened, which is what an app kill
      // looks like from the data's point of view — the same technique the expense
      // offline phase uses, and for the same reason it does not relaunch the widget
      // tree afterwards: the running scope still holds providers bound to the database
      // that has just been closed. Everything from here is driven through the reopened
      // bootstrap's own components, which is the shipped code either way.
      await boot.database.close();
      final reopened = await bootstrap(
        transport: _transport,
        appDataDirectory: _acceptanceDataDirectory(),
      );
      final afterRestart = RevenueRepository(reopened.database);

      expect(
        File(localPath).existsSync(),
        isTrue,
        reason: 'the staged bytes outlive the process (§11)',
      );
      final survived = await afterRestart.attachmentsOf(id);
      expect(survived, hasLength(1), reason: 'and so does the record of them');
      expect(
        survived.single.id,
        staged.single.id,
        reason: 'the attachment identity is stable across a restart (§9)',
      );
      expect(
        (await afterRestart.load(id))!.txnNumber,
        isNull,
        reason: 'still unnumbered, because nothing has reached the server',
      );
      expect(
        (await reopened.database.select(reopened.database.syncOutbox).get())
            .where((o) => o.entityId == id && o.status != 'done'),
        hasLength(1),
        reason: 'the queued intent survives too',
      );

      // Back on the air. The financial record first, then its evidence — the order the
      // Storage policy requires and the worker enforces.
      _transport.online = true;
      final engine = SyncEngine(
        outbox: reopened.outbox,
        endpoint: reopened.mutationEndpoint!,
        reconciler: reopened.mutationReconciler,
        actorUserId: (await afterRestart.load(id))!.createdBy!,
      );
      final uploads = AttachmentUploadWorker(
        db: reopened.database,
        store: SupabaseAttachmentStore(Supabase.instance.client),
      );

      final deadline = DateTime.now().add(const Duration(seconds: 180));
      while (DateTime.now().isBefore(deadline)) {
        await engine.pushOnce();
        await uploads.uploadDue();
        final entry = await afterRestart.load(id);
        final files = await afterRestart.attachmentsOf(id);
        if (entry?.txnNumber != null &&
            files.isNotEmpty &&
            files.every((a) => a.uploadState.isOnServer)) {
          break;
        }
        await tester.pump(const Duration(seconds: 2));
      }

      final settled = await afterRestart.load(id);
      expect(
        settled!.txnNumber,
        startsWith('KI-REV-'),
        reason: 'one number, issued by the server and never invented locally',
      );
      expect(settled.gross.paise, 6400000);
      expect(settled.tax.paise, 304762);
      final confirmed = await afterRestart.attachmentsOf(id);
      expect(confirmed, hasLength(1));
      expect(confirmed.single.uploadState.isOnServer, isTrue);

      // One of each, on the server.
      final client = Supabase.instance.client;
      expect(
        await client.from('revenue_document').select('id').eq('id', id),
        hasLength(1),
        reason: 'one canonical sale',
      );
      final files = await client
          .from('revenue_attachments')
          .select('id, storage_path')
          .eq('revenue_entry_id', id);
      expect(files, hasLength(1), reason: 'one canonical attachment');
      final path = files.first['storage_path'] as String;
      final listing = await client.storage
          .from(financialAttachmentBucket)
          .list(path: path.substring(0, path.lastIndexOf('/')));
      expect(listing, hasLength(1), reason: 'one object');

      await reopened.database.close();
    });
  });

  group('revenue-cleanup', skip: _phase != 'revenue-cleanup', () {
    testWidgets('every sale this suite created is reversed', (tester) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final client = Supabase.instance.client;

      // Found by the marker, which is the one identifier that survives a process
      // boundary. Voided rather than deleted: financial history is corrected by void
      // plus audit, never by removing rows (D-006), and no client role holds DELETE on
      // a financial table.
      final open = await client
          .from('revenue_document')
          .select('id, row_version, notes')
          .like('notes', '%$_acceptanceMarker%')
          .isFilter('voided_at', null);

      var reversed = 0;
      for (final row in open.cast<Map<String, dynamic>>()) {
        final outcome = await RevenueGateway(client).voidEntry(
          entryId: row['id'] as String,
          baseRowVersion: row['row_version'] as int? ?? 1,
          reason: 'Slice 8 Android acceptance fixture reversal',
          mutationId: const Uuid().v4(),
        );
        expect(outcome, isA<RemoteOk<Map<String, dynamic>>>());
        reversed++;
      }

      final remaining = await client
          .from('revenue_document')
          .select('id')
          .like('notes', '%$_acceptanceMarker%')
          .isFilter('voided_at', null);
      expect(
        remaining,
        isEmpty,
        reason: 'reversed $reversed of ${open.length}; none may remain open',
      );

      // And the verified configuration is exactly as the migration installed it.
      expect(
        await client
            .from('revenue_tax_rates')
            .select('id')
            .isFilter('archived_at', null),
        hasLength(4),
      );
      expect(await client.from('revenue_value_bands').select('id'), isEmpty);
      expect(
        await client.from('revenue_supply_subtypes').select('id'),
        isEmpty,
      );
      expect(
        await client.from('business_unit_tax_statuses').select('id'),
        isEmpty,
      );
    });
  });

  // ── Phase 5 Slice 8: the Windows P&L, in the real executable ───────────────
  //
  // Every figure on the screen is compared, to the paisa, with `reporting_primitives` over
  // the same scope and inclusive range — the authoritative server aggregation (D-020).
  // Fixtures go through the ordinary RPCs, carry a marker, and are voided with a reason
  // naming the run in a `finally` and again before the next run (D-066, D-071, D-076).

  const pnlMarker = '$_acceptanceMarker: slice8 pnl';
  const pnlFrom = '2027-03-01';
  const pnlTo = '2027-03-31';
  const pnlDate = '2027-03-10';

  Future<void> sweepPnlFixtures(
    SupabaseClient client, {
    String marker = pnlMarker,
  }) async {
    for (final (relation, rpc) in const [
      ('revenue_document', 'revenue_void'),
      ('expense_document', 'expense_void'),
    ]) {
      final open = await client
          .from(relation)
          .select('id,row_version')
          .like('notes', '$marker%')
          .isFilter('voided_at', null);
      for (final row in open) {
        await client.rpc<dynamic>(
          rpc,
          params: {
            'p_id': row['id'],
            'p_base_row_version': row['row_version'],
            'p_reason': 'Reversing $marker fixture (D-066)',
            'p_mutation_id': const Uuid().v4(),
          },
        );
      }
      final remaining = await client
          .from(relation)
          .select('id')
          .like('notes', '$marker%')
          .isFilter('voided_at', null);
      expect(remaining, isEmpty, reason: 'every $relation fixture reversed');
    }
  }

  /// The server's own primitive sums for a scope and range, with breakdowns.
  Future<
    ({
      int gross,
      int tax,
      int net,
      int expenses,
      int revenueRows,
      int expenseRows,
      Map<String, List<int>> revenueLines,
      Map<String, int> expenseLines,
    })
  >
  serverPnl(
    SupabaseClient client,
    List<String> units,
    String from,
    String to,
  ) async {
    final answer = Map<String, dynamic>.from(
      await client.rpc<dynamic>(
            'reporting_primitives',
            params: {
              'p_business_unit_ids': units,
              'p_from': from,
              'p_to': to,
              'p_breakdown': true,
            },
          )
          as Map,
    );
    var gross = 0, tax = 0, net = 0, expenses = 0, rRows = 0, eRows = 0;
    final revenueLines = <String, List<int>>{};
    final expenseLines = <String, int>{};
    int n(Object? v) => (v as num).toInt();
    for (final raw in answer['units'] as List) {
      final unit = Map<String, dynamic>.from(raw as Map);
      final id = unit['business_unit_id'] as String;
      final revenue = unit['revenue'] as Map?;
      final expense = unit['expense'] as Map?;
      expect(revenue, isNotNull, reason: 'server revenue authorised for $id');
      expect(expense, isNotNull, reason: 'server expenses authorised for $id');
      gross += n(revenue!['gross_minor']);
      tax += n(revenue['tax_minor']);
      net += n(revenue['net_minor']);
      rRows += n(revenue['contributions']);
      expenses += n(expense!['amount_minor']);
      eRows += n(expense['contributions']);
      for (final line in (unit['revenue_by_category'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(line as Map);
        revenueLines['$id-${m['revenue_category_id']}'] = [
          n(m['gross_minor']),
          n(m['tax_minor']),
          n(m['net_minor']),
        ];
      }
      for (final line in (unit['expense_by_hierarchy'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(line as Map);
        final key = '$id-${m['category_id']}';
        expenseLines[key] = (expenseLines[key] ?? 0) + n(m['amount_minor']);
      }
    }
    return (
      gross: gross,
      tax: tax,
      net: net,
      expenses: expenses,
      revenueRows: rRows,
      expenseRows: eRows,
      revenueLines: revenueLines,
      expenseLines: expenseLines,
    );
  }

  int uiPaise(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount.paise;

  Future<void> settlePnl(WidgetTester tester, ProviderContainer container) =>
      pumpUntil(tester, 'the P&L to be read', () {
        final view = container.read(pnlViewProvider);
        return view.hasValue &&
            !view.isLoading &&
            !container.read(pnlSyncProvider).isRunning;
      }, timeout: const Duration(seconds: 90));

  Future<void> refreshPnl(
    WidgetTester tester,
    ProviderContainer container, {
    PnlSyncPhase expected = PnlSyncPhase.succeeded,
    Key control = const Key('pnl-refresh'),
  }) async {
    await settlePnl(tester, container);
    final before = container.read(pnlSyncProvider);
    await tapWhenHittable(tester, find.byKey(control));
    await pumpUntil(
      tester,
      'the P&L synchronisation to finish',
      () {
        final now = container.read(pnlSyncProvider);
        return !identical(now, before) && !now.isRunning;
      },
      timeout: const Duration(seconds: 90),
    );
    expect(container.read(pnlSyncProvider).phase, expected);
    await settlePnl(tester, container);
  }

  PnlResult computedPnl(ProviderContainer container) {
    final view = container.read(pnlViewProvider).value;
    expect(view, isA<PnlReportView>());
    final outcome = (view! as PnlReportView).envelope.outcome;
    expect(outcome, isA<PnlComputed>(), reason: '$outcome');
    return (outcome as PnlComputed).result;
  }

  void expectPnlMatchesServer(
    WidgetTester tester,
    ProviderContainer container,
    ({
      int gross,
      int tax,
      int net,
      int expenses,
      int revenueRows,
      int expenseRows,
      Map<String, List<int>> revenueLines,
      Map<String, int> expenseLines,
    })
    server,
  ) {
    // On the screen, exactly.
    expect(uiPaise(tester, 'pnl-gross'), server.gross);
    expect(uiPaise(tester, 'pnl-gst'), server.tax);
    expect(uiPaise(tester, 'pnl-net'), server.net);
    expect(uiPaise(tester, 'pnl-expenses'), server.expenses);
    expect(
      uiPaise(tester, 'pnl-operating-result'),
      server.net - server.expenses,
    );

    // And behind it: counts and every category line, exactly.
    final result = computedPnl(container);
    expect(result.grossSales.paise, server.gross);
    expect(result.gst.paise, server.tax);
    expect(result.netSales.paise, server.net);
    expect(result.expenses.paise, server.expenses);
    expect(result.revenueContributions, server.revenueRows);
    expect(result.expenseContributions, server.expenseRows);
    expect(result.breakdownReconciles, isTrue);
    expect({
      for (final l in result.revenueByCategory)
        '${l.businessUnitId}-${l.revenueCategoryId}': [
          l.totals.gross.paise,
          l.totals.tax.paise,
          l.totals.net.paise,
        ],
    }, equals(server.revenueLines));
    final expenseLines = <String, int>{};
    for (final l in result.expenseByHierarchy) {
      final key = '${l.businessUnitId}-${l.categoryId}';
      expenseLines[key] = (expenseLines[key] ?? 0) + l.totals.amount.paise;
    }
    expect(expenseLines, equals(server.expenseLines));
  }

  Future<void> openPnl(WidgetTester tester, ProviderContainer container) async {
    await pumpUntil(
      tester,
      'the Analytics destination',
      () => visible('Analytics'),
    );
    await tester.tap(find.text('Analytics').first);
    await pumpUntil(
      tester,
      'the P&L page',
      () => find.byKey(const Key('pnl-page')).evaluate().isNotEmpty,
    );
    await settlePnl(tester, container);
  }

  Future<void> chooseCustom(
    WidgetTester tester,
    ProviderContainer container,
    String from,
    String to,
  ) async {
    await tapWhenHittable(tester, find.byKey(const Key('pnl-preset-custom')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('pnl-custom-from')), from);
    await tester.enterText(find.byKey(const Key('pnl-custom-to')), to);
    await tapWhenHittable(tester, find.byKey(const Key('pnl-custom-apply')));
    await tester.pump(const Duration(milliseconds: 400));
    await settlePnl(tester, container);
  }

  group('windows-pnl', skip: _phase != 'windows-pnl', () {
    testWidgets('the P&L equals the server to the paisa through sync, void and offline', (
      tester,
    ) async {
      expect(
        boot.shellKind.name,
        isNot('mobile'),
        reason: 'this phase is about the desktop P&L; run it with -d windows',
      );
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));
      final client = Supabase.instance.client;

      await sweepPnlFixtures(client);
      try {
        await openPnl(tester, container);
        final options = container.read(pnlScopeOptionsProvider).value!;
        expect(options.consolidatedAllowed, isTrue);
        final units = [for (final u in options.units) u.id];
        expect(units, containsAll([_ccr, _hki]));

        final baseline = await serverPnl(client, units, pnlFrom, pnlTo);

        // ── A sale and two expenses, through the ordinary RPCs ───────────────
        final restaurant =
            (await client
                    .from('revenue_categories')
                    .select('id')
                    .eq('code', 'RESTAURANT')
                    .eq('business_unit_id', _ccr)
                    .single())['id']
                as String;
        final sale = const Uuid().v7();
        await client.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': sale,
            'p_business_unit_id': _ccr,
            'p_revenue_category_id': restaurant,
            'p_business_date': pnlDate,
            'p_notes': '$pnlMarker sale',
            'p_components': [
              {'entered_amount_minor': 12364200},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        for (final (unit, dept, section, category, amount) in [
          (
            _ccr,
            _seedId('dept:CCR/FB'),
            _seedId('sec:CCR/FB/FOOD_PROD'),
            _kirana,
            4500000,
          ),
          (
            _hki,
            _seedId('dept:HKI/HKI_UTIL'),
            _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
            _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
            3000000,
          ),
        ]) {
          await client.rpc<dynamic>(
            'expense_create',
            params: {
              'p_id': const Uuid().v7(),
              'p_business_date': pnlDate,
              'p_total_minor': amount,
              'p_notes': '$pnlMarker expense',
              'p_allocations': [
                {
                  'business_unit_id': unit,
                  'department_id': dept,
                  'section_id': section,
                  'category_id': category,
                  'amount_minor': amount,
                },
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          );
        }

        // ── Consolidated custom range, synchronised, equal to the server ─────
        await chooseCustom(tester, container, pnlFrom, pnlTo);
        await refreshPnl(tester, container);
        var server = await serverPnl(client, units, pnlFrom, pnlTo);
        expect(server.gross - baseline.gross, 12364200);
        expect(server.tax - baseline.tax, 588771);
        expect(server.net - baseline.net, 11775429);
        expect(server.expenses - baseline.expenses, 7500000);
        expectPnlMatchesServer(tester, container, server);
        expect(
          find.byKey(const Key('pnl-freshness-synchronised')),
          findsOneWidget,
        );
        expect(
          find.text(computedPnl(container).margin.displayTwoDecimals),
          findsWidgets,
        );

        // The category lines on screen, once scrolled to.
        final page = find.descendant(
          of: find.byKey(const Key('pnl-page')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('pnl-exp-total-amount')),
          300,
          scrollable: page.first,
        );
        expect(
          uiPaise(tester, 'pnl-exp-$_ccr-$_kirana-amount'),
          server.expenseLines['$_ccr-$_kirana'],
        );
        expect(uiPaise(tester, 'pnl-exp-total-amount'), server.expenses);
        await tester.drag(page.first, const Offset(0, 4000));
        await tester.pump(const Duration(milliseconds: 400));

        // ── A void reaches the P&L exactly once ──────────────────────────────
        final saleDoc = await client
            .from('revenue_document')
            .select('row_version')
            .eq('id', sale)
            .single();
        await client.rpc<dynamic>(
          'revenue_void',
          params: {
            'p_id': sale,
            'p_base_row_version': saleDoc['row_version'],
            'p_reason': 'Reversing $pnlMarker sale (D-066)',
            'p_mutation_id': const Uuid().v4(),
          },
        );
        await refreshPnl(tester, container);
        server = await serverPnl(client, units, pnlFrom, pnlTo);
        expect(server.gross, baseline.gross);
        expect(server.expenses - baseline.expenses, 7500000);
        expectPnlMatchesServer(tester, container, server);

        // ── One property, equal to the server for that property ──────────────
        await tapWhenHittable(tester, find.byKey(Key('pnl-scope-$_ccr')));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(client, [_ccr], pnlFrom, pnlTo),
        );
        await tapWhenHittable(
          tester,
          find.byKey(const Key('pnl-scope-consolidated')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);

        // ── Offline: the complete report stays readable, never ₹0 ───────────
        final expensesBefore = uiPaise(tester, 'pnl-expenses');
        final grossBefore = uiPaise(tester, 'pnl-gross');
        _transport.online = false;
        try {
          await refreshPnl(tester, container, expected: PnlSyncPhase.failed);
          expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
          expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
          expect(
            find.byKey(const Key('pnl-freshness-synchronised')),
            findsOneWidget,
          );
          // Re-read from the cache with no server at all.
          container.invalidate(pnlViewProvider);
          await settlePnl(tester, container);
          expect(uiPaise(tester, 'pnl-expenses'), expensesBefore);
          expect(uiPaise(tester, 'pnl-gross'), grossBefore);
        } finally {
          _transport.online = true;
        }

        // ── Older history is downloaded on demand, then equals the server ────
        await chooseCustom(tester, container, '2023-06-01', '2023-06-30');
        if (find.byKey(const Key('pnl-download')).evaluate().isNotEmpty) {
          expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
          await refreshPnl(
            tester,
            container,
            control: const Key('pnl-download'),
          );
        }
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(client, units, '2023-06-01', '2023-06-30'),
        );
      } finally {
        _transport.online = true;
        await sweepPnlFixtures(client);
      }
    });
  });

  group('windows-pnl-scope', skip: _phase != 'windows-pnl-scope', () {
    testWidgets(
      'complete P&L authority for one property reports it and nothing else',
      (tester) async {
        expect(boot.shellKind.name, isNot('mobile'));
        await launch(tester);
        await signIn(tester, 'ccr.manager@example.com');
        await expectSignedIn(tester, 'ccr.manager@example.com');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final client = Supabase.instance.client;

        // The subject is the capability state, not the role name, so it is asserted
        // before anything depends on it.
        final principal = container.read(principalProvider);
        expect(
          PnlAuthority.mayReadUnit(principal, _ccr),
          isTrue,
          reason: 'fixture must hold complete P&L authority for Crystal Canopy',
        );
        expect(
          PnlAuthority.mayReadUnit(principal, _hki),
          isFalse,
          reason: 'fixture must hold no qualifying authority for Hotel Krishna',
        );
        expect(
          PnlAuthority.mayReadConsolidated(principal),
          isFalse,
          reason: 'fixture must hold no unscoped consolidated authority',
        );

        await openPnl(tester, container);
        expect(find.byKey(Key('pnl-scope-$_ccr')), findsOneWidget);
        expect(find.byKey(Key('pnl-scope-$_hki')), findsNothing);
        expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);

        // Crystal Canopy opens, equal to the server.
        await refreshPnl(tester, container);
        final view = container.read(pnlViewProvider).value! as PnlReportView;
        expect(view.scope, PnlUnitScope(_ccr));
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(
            client,
            [_ccr],
            view.range.from.iso,
            view.range.to.iso,
          ),
        );

        Future<void> expectServerWithholds(List<String> units) async {
          final answer = Map<String, dynamic>.from(
            await client.rpc<dynamic>(
                  'reporting_primitives',
                  params: {
                    'p_business_unit_ids': units,
                    'p_from': view.range.from.iso,
                    'p_to': view.range.to.iso,
                    'p_breakdown': true,
                  },
                )
                as Map,
          );
          for (final raw in answer['units'] as List) {
            final unit = Map<String, dynamic>.from(raw as Map);
            expect(unit['revenue'], isNull, reason: '$units revenue withheld');
            expect(unit['expense'], isNull, reason: '$units expenses withheld');
          }
        }

        // Hotel Krishna, requested directly, is refused on the device and the server.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(PnlUnitScope(_hki));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(container.read(pnlViewProvider).value, isA<PnlNotAuthorised>());
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
        expect(find.byKey(const Key('pnl-statement')), findsNothing);
        await expectServerWithholds([_hki]);

        // Consolidated, requested directly, likewise.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(const PnlConsolidatedScope());
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(container.read(pnlViewProvider).value, isA<PnlNotAuthorised>());
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
        await expectServerWithholds([_ccr, _hki]);

        // And the permitted property still reports afterwards.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(PnlUnitScope(_ccr));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      },
    );
  });

  // ── Phase 5 Slice 9: the Android P&L, in the real APK on the emulator ──────
  //
  // The same comparison as the Windows phases — every figure on the phone, to the paisa,
  // against `reporting_primitives` over the same scope and inclusive range — reached the way a
  // phone reaches it: the Reports tab, the scope bottom sheet, the calendar picker and
  // pull-to-refresh. Fixtures carry their own marker and are voided in a `finally` and again
  // before the next run (D-066, D-071, D-076).
  //
  // Emulator acceptance only. It is not physical-device acceptance, and is never reported as
  // one.

  const phonePnlMarker = '$_acceptanceMarker: slice9 android pnl';
  const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Moves [scrollable] as a drag of [step] would, without a pointer: a positive dy
  /// shows content further up, exactly like dragging the page down.
  void p8ScrollBy(WidgetTester tester, Finder scrollable, Offset step) {
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(
      (position.pixels - step.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Finder phonePnlScrollable() => find
      .descendant(
        of: find.byKey(const Key('pnl-page')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Centres [finder] in every scrollable around it, so a tap cannot land on the docked
  /// [ + ] action or past the end of the preset strip.
  Future<void> centrePnlControl(WidgetTester tester, Finder finder) async {
    // The page is a lazy list: a control scrolled far out of view is not built at all, and
    // no amount of waiting will make it exist. Walk the page towards the top, then the
    // bottom, until it is built - the refresh control lives in the header.
    final page = find.byKey(const Key('pnl-page'));
    for (final step in const [Offset(0, 300), Offset(0, -300)]) {
      for (
        var i = 0;
        i < 60 && finder.evaluate().isEmpty && page.evaluate().isNotEmpty;
        i++
      ) {
        // Moves the list rather than dragging it: the point is only to make the lazy
        // list build, and a drag from the list's centre can land on an overlay such as
        // the docked [ + ] action. No gesture is under test here, so none is made
        // (Phase 8 Slice 8 removed the tolerated miss this used to carry).
        p8ScrollBy(tester, phonePnlScrollable(), step);
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    await pumpUntil(
      tester,
      'the control to exist',
      () => finder.evaluate().isNotEmpty,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openPhonePnl(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    expect(
      boot.shellKind.name,
      'mobile',
      reason:
          'this phase is about the phone P&L; run it on the Android emulator',
    );
    await pumpUntil(tester, 'the Reports tab', () => visible('Reports'));
    await tapWhenHittable(tester, find.text('Reports').last);
    await pumpUntil(
      tester,
      'the phone P&L page',
      () => find.byType(MobileProfitAndLossPage).evaluate().isNotEmpty,
    );
    await settlePnl(tester, container);
  }

  Future<void> refreshPhonePnl(
    WidgetTester tester,
    ProviderContainer container, {
    PnlSyncPhase expected = PnlSyncPhase.succeeded,
    Key control = const Key('pnl-refresh'),
  }) async {
    await settlePnl(tester, container);
    await centrePnlControl(tester, find.byKey(control));
    await refreshPnl(tester, container, expected: expected, control: control);
  }

  Future<void> pullToRefreshPnl(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await settlePnl(tester, container);
    // Back to the top first; dragging there may itself refresh, so let that settle.
    await tester.drag(phonePnlScrollable(), const Offset(0, 4000));
    await tester.pump(const Duration(milliseconds: 600));
    await settlePnl(tester, container);
    // D-248: a RefreshIndicator ignores a new pull until the previous refresh's indicator
    // has finished dismissing. The run settling is not enough - the indicator animates out
    // afterwards, and on a slow phone the fling can land inside that animation and do
    // nothing. Wait until no indicator is on screen, and record whether one was.
    final indicatorWasShowing = find
        .byType(RefreshProgressIndicator)
        .evaluate()
        .isNotEmpty;
    await pumpUntil(
      tester,
      'the previous refresh indicator to dismiss',
      () => find.byType(RefreshProgressIndicator).evaluate().isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    final before = container.read(pnlSyncProvider);
    await tester.fling(phonePnlScrollable(), const Offset(0, 500), 1500);
    try {
      await pumpUntil(
        tester,
        'pull-to-refresh to run the synchronisation',
        () {
          final now = container.read(pnlSyncProvider);
          return !identical(now, before) && !now.isRunning;
        },
        timeout: const Duration(seconds: 90),
      );
    } catch (_) {
      // A refresh that resolves nothing leaves the status untouched, so "the gesture never
      // fired" and "the run returned early" look identical from out here. Say which, the way
      // the offline drill-down step reports what was on screen (D-239, D-075).
      final status = container.read(pnlSyncProvider);
      final scopes = container.read(pnlScopeOptionsProvider);
      final rules = container.read(businessDayRulesProvider);
      final view = container.read(pnlViewProvider);
      debugPrint(
        'DIAG pull-to-refresh: indicatorBeforeWait=$indicatorWasShowing '
        'phase=${status.phase} running=${status.isRunning} '
        'identical=${identical(status, before)} '
        'period=${container.read(pnlSelectionProvider).period} '
        'scopeOptions=${scopes.hasValue
            ? 'value'
            : scopes.hasError
            ? 'error:${scopes.error}'
            : 'loading'} '
        'rules=${rules.hasValue
            ? 'value'
            : rules.hasError
            ? 'error:${rules.error}'
            : 'loading'} '
        'view=${view.hasValue
            ? view.value.runtimeType
            : view.hasError
            ? 'error:${view.error}'
            : 'loading'}',
      );
      // Does the header control refresh at all? If it does, the gesture is what did not
      // arrive; if it does not, the run itself cannot resolve anything to fetch.
      try {
        await refreshPhonePnl(tester, container);
        debugPrint('DIAG the header refresh control ran the synchronisation');
      } catch (e) {
        debugPrint('DIAG the header refresh control did not run it either: $e');
      }
      rethrow;
    }
    expect(container.read(pnlSyncProvider).phase, PnlSyncPhase.succeeded);
    await settlePnl(tester, container);
  }

  Future<void> choosePhoneScope(
    WidgetTester tester,
    ProviderContainer container,
    Key choice,
  ) async {
    await settlePnl(tester, container);
    await centrePnlControl(tester, find.byKey(const Key('pnl-scope-selector')));
    await tapWhenHittable(tester, find.byKey(const Key('pnl-scope-selector')));
    await pumpUntil(
      tester,
      'the scope sheet',
      () => find.byKey(const Key('pnl-scope-sheet')).evaluate().isNotEmpty,
    );
    await tapWhenHittable(tester, find.byKey(choice));
    await pumpUntil(
      tester,
      'the scope sheet to close',
      () => find.byKey(const Key('pnl-scope-sheet')).evaluate().isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await settlePnl(tester, container);
  }

  /// Chooses [from]–[to] on the calendar picker, tapping the two days as a person would.
  Future<void> choosePhoneCustom(
    WidgetTester tester,
    ProviderContainer container,
    BusinessDate from,
    BusinessDate to,
  ) async {
    await settlePnl(tester, container);
    final opensOn = switch ((
      container.read(pnlSelectionProvider).period,
      container.read(pnlViewProvider).value,
    )) {
      (PnlCustomPeriod(:final from), _) => from,
      (_, PnlReportView(:final range)) => range.from,
      _ => fail('the picker has no period to open on'),
    };
    final semantics = tester.ensureSemantics();
    try {
      await centrePnlControl(
        tester,
        find.byKey(const Key('pnl-preset-custom')),
      );
      await tapWhenHittable(tester, find.byKey(const Key('pnl-preset-custom')));
      await pumpUntil(
        tester,
        'the date-range picker',
        () => visible('Profit & loss period'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'calendar only: Android takes no typed dates',
      );
      // The month list is the scrollable nearest a day the picker opened on. The first
      // vertical scrollable inside the dialog is not it — dragging that one moved nothing
      // for 400 drags on the emulator. Bound to the element once, so it survives that day
      // scrolling out of view.
      final monthsElement = tester.element(
        find
            .ancestor(
              of: find.bySemanticsLabel(
                RegExp(
                  RegExp.escape(
                    '${monthNames[opensOn.month - 1]} ${opensOn.day}, ${opensOn.year}',
                  ),
                ),
              ),
              // Each month is its own non-scrolling grid; the list of months is the
              // nearest ancestor that can actually scroll.
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Scrollable &&
                    w.physics is! NeverScrollableScrollPhysics,
              ),
            )
            .first,
      );
      final months = find.byElementPredicate((e) => e == monthsElement);
      for (final day in [from, to]) {
        final cell = find.bySemanticsLabel(
          RegExp(
            RegExp.escape(
              '${monthNames[day.month - 1]} ${day.day}, ${day.year}',
            ),
          ),
        );
        await tester.scrollUntilVisible(
          cell,
          day >= opensOn ? 250 : -250,
          scrollable: months,
          maxScrolls: 400,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tapWhenHittable(tester, cell);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tapWhenHittable(tester, find.text('Apply'));
      await pumpUntil(
        tester,
        'the picker to close',
        () => !visible('Profit & loss period'),
      );
    } finally {
      semantics.dispose();
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(pnlSelectionProvider).period,
      PnlCustomPeriod(from, to),
      reason: 'the tapped calendar days are the P&L dates, unconverted',
    );
    await settlePnl(tester, container);
  }

  Future<void> expectServerWithholdsPnl(
    SupabaseClient client,
    List<String> units,
    String from,
    String to,
  ) async {
    final answer = Map<String, dynamic>.from(
      await client.rpc<dynamic>(
            'reporting_primitives',
            params: {
              'p_business_unit_ids': units,
              'p_from': from,
              'p_to': to,
              'p_breakdown': true,
            },
          )
          as Map,
    );
    for (final raw in answer['units'] as List) {
      final unit = Map<String, dynamic>.from(raw as Map);
      expect(unit['revenue'], isNull, reason: '$units revenue withheld');
      expect(unit['expense'], isNull, reason: '$units expenses withheld');
    }
  }

  /// Rows the canonical reporting cache holds for [ownerUserId], optionally for one property.
  Future<int> reportingCacheRows(
    String ownerUserId, {
    String? businessUnitId,
  }) async {
    final db = boot.database;
    final revenue = await db.select(db.reportingRevenueContributions).get();
    final expense = await db.select(db.reportingExpenseContributions).get();
    bool matches(String owner, String unit) =>
        owner == ownerUserId &&
        (businessUnitId == null || unit == businessUnitId);
    return revenue
            .where((r) => matches(r.ownerUserId, r.businessUnitId))
            .length +
        expense.where((r) => matches(r.ownerUserId, r.businessUnitId)).length;
  }

  group('android-pnl', skip: _phase != 'android-pnl', () {
    testWidgets(
      'the phone P&L equals the server to the paisa through the tab, sheet, picker, '
      'pull-to-refresh, void and offline',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final client = Supabase.instance.client;

        await sweepPnlFixtures(client, marker: phonePnlMarker);
        try {
          await openPhonePnl(tester, container);
          final options = container.read(pnlScopeOptionsProvider).value!;
          expect(options.consolidatedAllowed, isTrue);
          final units = [for (final u in options.units) u.id];
          expect(units, containsAll([_ccr, _hki]));
          expect(
            tester.widget<Text>(find.byKey(const Key('pnl-scope-name'))).data,
            'Both properties (consolidated)',
          );

          final baseline = await serverPnl(client, units, pnlFrom, pnlTo);

          // ── A sale and two expenses, through the ordinary RPCs ─────────────
          final restaurant =
              (await client
                      .from('revenue_categories')
                      .select('id')
                      .eq('code', 'RESTAURANT')
                      .eq('business_unit_id', _ccr)
                      .single())['id']
                  as String;
          final sale = const Uuid().v7();
          await client.rpc<dynamic>(
            'revenue_create',
            params: {
              'p_id': sale,
              'p_business_unit_id': _ccr,
              'p_revenue_category_id': restaurant,
              'p_business_date': pnlDate,
              'p_notes': '$phonePnlMarker sale',
              'p_components': [
                {'entered_amount_minor': 12364200},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          );
          for (final (unit, dept, section, category, amount) in [
            (
              _ccr,
              _seedId('dept:CCR/FB'),
              _seedId('sec:CCR/FB/FOOD_PROD'),
              _kirana,
              4500000,
            ),
            (
              _hki,
              _seedId('dept:HKI/HKI_UTIL'),
              _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
              _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
              3000000,
            ),
          ]) {
            await client.rpc<dynamic>(
              'expense_create',
              params: {
                'p_id': const Uuid().v7(),
                'p_business_date': pnlDate,
                'p_total_minor': amount,
                'p_notes': '$phonePnlMarker expense',
                'p_allocations': [
                  {
                    'business_unit_id': unit,
                    'department_id': dept,
                    'section_id': section,
                    'category_id': category,
                    'amount_minor': amount,
                  },
                ],
                'p_mutation_id': const Uuid().v4(),
              },
            );
          }

          // ── Custom range on the calendar, pull-to-refresh, equal to the server ──
          await choosePhoneCustom(
            tester,
            container,
            BusinessDate.of(2027, 3, 1),
            BusinessDate.of(2027, 3, 31),
          );
          await pullToRefreshPnl(tester, container);
          var server = await serverPnl(client, units, pnlFrom, pnlTo);
          expect(server.gross - baseline.gross, 12364200);
          expect(server.tax - baseline.tax, 588771);
          expect(server.net - baseline.net, 11775429);
          expect(server.expenses - baseline.expenses, 7500000);
          expectPnlMatchesServer(tester, container, server);
          expect(
            find.byKey(const Key('pnl-freshness-synchronised')),
            findsOneWidget,
          );
          expect(
            find.text(computedPnl(container).margin.displayTwoDecimals),
            findsWidgets,
          );

          // The category lines on screen, once scrolled to.
          await centrePnlControl(
            tester,
            find.byKey(const Key('pnl-exp-total-amount')),
          );
          expect(
            uiPaise(tester, 'pnl-exp-$_ccr-$_kirana-amount'),
            server.expenseLines['$_ccr-$_kirana'],
          );
          expect(uiPaise(tester, 'pnl-exp-total-amount'), server.expenses);

          // Scrolled to the end, the last line stays clear of the docked [ + ] action.
          await tester.drag(phonePnlScrollable(), const Offset(0, -8000));
          await tester.pump(const Duration(milliseconds: 800));
          final fab = tester.getRect(find.byType(FloatingActionButton));
          expect(
            tester
                .getRect(find.byKey(const Key('pnl-exp-total-amount')))
                .bottom,
            lessThanOrEqualTo(fab.top),
          );
          expect(
            tester.getRect(find.byKey(const Key('pnl-basis'))).bottom,
            lessThanOrEqualTo(fab.top),
          );

          // ── A void reaches the P&L exactly once ────────────────────────────
          final saleDoc = await client
              .from('revenue_document')
              .select('row_version')
              .eq('id', sale)
              .single();
          await client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': sale,
              'p_base_row_version': saleDoc['row_version'],
              'p_reason': 'Reversing $phonePnlMarker sale (D-066)',
              'p_mutation_id': const Uuid().v4(),
            },
          );
          await refreshPhonePnl(tester, container);
          server = await serverPnl(client, units, pnlFrom, pnlTo);
          expect(server.gross, baseline.gross);
          expect(server.expenses - baseline.expenses, 7500000);
          expectPnlMatchesServer(tester, container, server);

          // ── One property through the bottom sheet, equal to the server ─────
          await choosePhoneScope(tester, container, Key('pnl-scope-$_ccr'));
          expect(
            (container.read(pnlViewProvider).value! as PnlReportView).scope,
            PnlUnitScope(_ccr),
          );
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, [_ccr], pnlFrom, pnlTo),
          );

          // Android back closes the sheet and changes nothing.
          await centrePnlControl(
            tester,
            find.byKey(const Key('pnl-scope-selector')),
          );
          await tapWhenHittable(
            tester,
            find.byKey(const Key('pnl-scope-selector')),
          );
          await pumpUntil(
            tester,
            'the scope sheet',
            () =>
                find.byKey(const Key('pnl-scope-sheet')).evaluate().isNotEmpty,
          );
          await tester.binding.handlePopRoute();
          await pumpUntil(
            tester,
            'back to close the sheet',
            () => find.byKey(const Key('pnl-scope-sheet')).evaluate().isEmpty,
          );
          expect(
            container.read(pnlSelectionProvider).scope,
            PnlUnitScope(_ccr),
          );
          expect(find.byType(MobileProfitAndLossPage), findsOneWidget);

          await choosePhoneScope(
            tester,
            container,
            const Key('pnl-scope-consolidated'),
          );

          // ── Offline: the complete report stays readable, never ₹0 ─────────
          final expensesBefore = uiPaise(tester, 'pnl-expenses');
          final grossBefore = uiPaise(tester, 'pnl-gross');
          _transport.online = false;
          try {
            await refreshPhonePnl(
              tester,
              container,
              expected: PnlSyncPhase.failed,
            );
            expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
            expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
            expect(
              find.byKey(const Key('pnl-freshness-synchronised')),
              findsOneWidget,
            );
            // Re-read from the cache with no server at all.
            container.invalidate(pnlViewProvider);
            await settlePnl(tester, container);
            expect(uiPaise(tester, 'pnl-expenses'), expensesBefore);
            expect(uiPaise(tester, 'pnl-gross'), grossBefore);
          } finally {
            _transport.online = true;
          }

          // ── Older history, chosen on the calendar and downloaded on demand ─
          await choosePhoneCustom(
            tester,
            container,
            BusinessDate.of(2025, 3, 1),
            BusinessDate.of(2025, 3, 31),
          );
          if (find.byKey(const Key('pnl-download')).evaluate().isNotEmpty) {
            expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
            expect(find.byKey(const Key('pnl-statement')), findsNothing);
            await refreshPhonePnl(
              tester,
              container,
              control: const Key('pnl-download'),
            );
          }
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, units, '2025-03-01', '2025-03-31'),
          );
        } finally {
          _transport.online = true;
          await sweepPnlFixtures(client, marker: phonePnlMarker);
        }
      },
    );
  });

  group('android-pnl-scope', skip: _phase != 'android-pnl-scope', () {
    testWidgets(
      'complete P&L authority for one property reports it and nothing else, on the phone',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'ccr.manager@example.com');
        await expectSignedIn(tester, 'ccr.manager@example.com');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final client = Supabase.instance.client;

        // The subject is the capability state, not the role name, so it is asserted before
        // anything depends on it.
        final principal = container.read(principalProvider);
        expect(
          PnlAuthority.mayReadUnit(principal, _ccr),
          isTrue,
          reason: 'fixture must hold complete P&L authority for Crystal Canopy',
        );
        expect(
          PnlAuthority.mayReadUnit(principal, _hki),
          isFalse,
          reason: 'fixture must hold no qualifying authority for Hotel Krishna',
        );
        expect(
          PnlAuthority.mayReadConsolidated(principal),
          isFalse,
          reason: 'fixture must hold no unscoped consolidated authority',
        );

        await openPhonePnl(tester, container);
        final options = container.read(pnlScopeOptionsProvider).value!;
        expect([for (final u in options.units) u.id], [_ccr]);
        expect(options.consolidatedAllowed, isFalse);
        expect(find.text('Both properties (consolidated)'), findsNothing);

        // The sheet offers Crystal Canopy alone; back closes it.
        await centrePnlControl(
          tester,
          find.byKey(const Key('pnl-scope-selector')),
        );
        await tapWhenHittable(
          tester,
          find.byKey(const Key('pnl-scope-selector')),
        );
        await pumpUntil(
          tester,
          'the scope sheet',
          () => find.byKey(const Key('pnl-scope-sheet')).evaluate().isNotEmpty,
        );
        expect(find.byKey(Key('pnl-scope-$_ccr')), findsOneWidget);
        expect(find.byKey(Key('pnl-scope-$_hki')), findsNothing);
        expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
        await tester.binding.handlePopRoute();
        await pumpUntil(
          tester,
          'back to close the sheet',
          () => find.byKey(const Key('pnl-scope-sheet')).evaluate().isEmpty,
        );

        // Crystal Canopy opens, equal to the server.
        await refreshPhonePnl(tester, container);
        final view = container.read(pnlViewProvider).value! as PnlReportView;
        expect(view.scope, PnlUnitScope(_ccr));
        expect(view.viewerUserId, principal.userId);
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(
            client,
            [_ccr],
            view.range.from.iso,
            view.range.to.iso,
          ),
        );

        // Hotel Krishna, requested directly, is refused on the phone and the server.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(PnlUnitScope(_hki));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(container.read(pnlViewProvider).value, isA<PnlNotAuthorised>());
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
        expect(find.byKey(const Key('pnl-statement')), findsNothing);
        await expectServerWithholdsPnl(
          client,
          [_hki],
          view.range.from.iso,
          view.range.to.iso,
        );

        // Consolidated, requested directly, likewise.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(const PnlConsolidatedScope());
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(container.read(pnlViewProvider).value, isA<PnlNotAuthorised>());
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
        await expectServerWithholdsPnl(
          client,
          [_ccr, _hki],
          view.range.from.iso,
          view.range.to.iso,
        );

        // And the permitted property still reports afterwards.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(PnlUnitScope(_ccr));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      },
    );
  });

  group('android-pnl-switch', skip: _phase != 'android-pnl-switch', () {
    testWidgets(
      'the next person on the same phone inherits no scope, figure or cache from the last',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final client = Supabase.instance.client;
        final cache = ReportingCache(boot.database);

        // ── The Owner reads the consolidated P&L on this phone ─────────────
        final ownerId = container.read(principalProvider).userId;
        await openPhonePnl(tester, container);
        await refreshPhonePnl(tester, container);
        final ownerView =
            container.read(pnlViewProvider).value! as PnlReportView;
        expect(ownerView.scope, const PnlConsolidatedScope());
        expect(ownerView.viewerUserId, ownerId);
        expect(find.text('Both properties (consolidated)'), findsOneWidget);
        expect(
          await cache.markersFor(ownerId),
          isNotEmpty,
          reason: 'the Owner synchronised a report on this installation',
        );

        // ── The Owner signs out; the next person signs in on the same phone ─
        await container.read(sessionProvider.notifier).signOut();
        await tester.pump(const Duration(seconds: 3));
        expect(
          await cache.markersFor(ownerId),
          isEmpty,
          reason: 'sign-out removes the reporting coverage it held (D-220)',
        );
        expect(
          await reportingCacheRows(ownerId),
          0,
          reason: 'sign-out removes the reporting figures it held (D-220)',
        );

        await signIn(tester, 'ccr.manager@example.com');
        await expectSignedIn(tester, 'ccr.manager@example.com');
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final manager = container.read(principalProvider);
        expect(manager.userId, isNot(ownerId));
        expect(PnlAuthority.mayReadUnit(manager, _ccr), isTrue);
        expect(PnlAuthority.mayReadUnit(manager, _hki), isFalse);
        expect(PnlAuthority.mayReadConsolidated(manager), isFalse);

        // No previous selection survives.
        expect(container.read(pnlSelectionProvider).scope, isNull);
        expect(
          container.read(pnlSelectionProvider).period,
          const PnlPresetPeriod(RelativePreset.thisMonth),
        );

        // At every frame until it settles, the phone shows nothing computed for the Owner.
        await pumpUntil(tester, 'the Reports tab', () => visible('Reports'));
        await tapWhenHittable(tester, find.text('Reports').last);
        var framesChecked = 0;
        await pumpUntil(
          tester,
          'the phone P&L to settle, showing nothing of the previous person',
          () {
            framesChecked++;
            if (visible('Both properties (consolidated)')) {
              fail(
                'the previous person\'s consolidated scope reached the next',
              );
            }
            if (find.byKey(const Key('pnl-statement')).evaluate().isNotEmpty) {
              final shown = pnlViewShownTo(
                container.read(pnlViewProvider),
                container.read(principalProvider),
              );
              if (shown is! PnlReportView ||
                  shown.viewerUserId != manager.userId ||
                  shown.scope != PnlUnitScope(_ccr)) {
                fail('a figure not computed for this person is on screen');
              }
            }
            final view = container.read(pnlViewProvider);
            return find.byType(MobileProfitAndLossPage).evaluate().isNotEmpty &&
                view.hasValue &&
                !view.isLoading &&
                !container.read(pnlSyncProvider).isRunning;
          },
          timeout: const Duration(seconds: 90),
        );
        expect(framesChecked, greaterThan(0));

        // The next person's own report, equal to the server for their property.
        await refreshPhonePnl(tester, container);
        final view = container.read(pnlViewProvider).value! as PnlReportView;
        expect(view.viewerUserId, manager.userId);
        expect(view.scope, PnlUnitScope(_ccr));
        expect(find.text('Both properties (consolidated)'), findsNothing);
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(
            client,
            [_ccr],
            view.range.from.iso,
            view.range.to.iso,
          ),
        );

        // The cache holds this person's Crystal Canopy facts, and nothing of the Owner's.
        final markers = await cache.markersFor(manager.userId);
        expect(markers, isNotEmpty);
        expect({for (final m in markers) m.businessUnitId}, {_ccr});
        expect(await cache.markersFor(ownerId), isEmpty);
        expect(await reportingCacheRows(ownerId), 0);
        expect(
          await reportingCacheRows(manager.userId, businessUnitId: _hki),
          0,
        );

        // A direct read of the other property is still refused.
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(PnlUnitScope(_hki));
        await tester.pump(const Duration(milliseconds: 400));
        await settlePnl(tester, container);
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
        expect(find.byKey(const Key('pnl-statement')), findsNothing);
      },
    );
  });

  // ── Phase 5 Slice 10: the read-only drill-down, in the real applications ────
  //
  // Through the shipped P&L pages: a category row to its documents, the expense hierarchy
  // down to a bucket, and a document opened read-only for a principal who could edit, void
  // and attach from the ledger. Opening a document is asserted to write nothing to this
  // device's ordinary transaction tables, outbox or reporting cache, and a lost connection to
  // leave the rows readable while the detail says it is not downloaded. Fixtures go through
  // the ordinary RPCs and are reversed with a reason naming the run (D-066, D-071, D-076).

  const drillMarker = '$_acceptanceMarker: slice10 drill';

  Future<Map<String, int>> ordinaryAndCacheCounts() async => {
    for (final table in const [
      'expenses',
      'expense_allocations',
      'expense_period_allocations',
      'revenue_entries',
      'revenue_components',
      'sync_outbox',
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
      'reporting_coverage_markers',
    ])
      table:
          (await boot.database
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c'),
  };

  void expectReportDetailReadOnly() {
    for (final key in const [
      'revenue-edit',
      'revenue-void',
      'edit-expense',
      'void-expense',
      'revenue-conflict-review-latest',
      'conflict-review-latest',
      'revenue-evidence',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    for (final text in const [
      'Edit',
      'Edit expense',
      'Void',
      'Review latest',
    ]) {
      expect(find.text(text), findsNothing, reason: text);
    }
  }

  /// Records the drill-down fixtures and returns their ids.
  Future<({String sale, String shared, String restaurant})> recordDrillFixtures(
    SupabaseClient client,
  ) async {
    final restaurant =
        (await client
                .from('revenue_categories')
                .select('id')
                .eq('code', 'RESTAURANT')
                .eq('business_unit_id', _ccr)
                .single())['id']
            as String;
    final sale = const Uuid().v7();
    await client.rpc<dynamic>(
      'revenue_create',
      params: {
        'p_id': sale,
        'p_business_unit_id': _ccr,
        'p_revenue_category_id': restaurant,
        'p_business_date': pnlDate,
        'p_notes': '$drillMarker sale',
        'p_components': [
          {'entered_amount_minor': 12364200},
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    final shared = const Uuid().v7();
    await client.rpc<dynamic>(
      'expense_create',
      params: {
        'p_id': shared,
        'p_business_date': pnlDate,
        'p_total_minor': 5800000,
        'p_notes': '$drillMarker shared expense',
        'p_allocations': [
          {
            'business_unit_id': _ccr,
            'department_id': _seedId('dept:CCR/FB'),
            'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
            'category_id': _kirana,
            'amount_minor': 2500000,
          },
          {
            'business_unit_id': _hki,
            'department_id': _seedId('dept:HKI/HKI_UTIL'),
            'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
            'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
            'amount_minor': 3300000,
          },
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return (sale: sale, shared: shared, restaurant: restaurant);
  }

  group('windows-pnl-drill', skip: _phase != 'windows-pnl-drill', () {
    testWidgets('the Windows drill-down reaches a document read-only, writes nothing, and says '
        'when detail needs a connection', (tester) async {
      expect(
        boot.shellKind.name,
        isNot('mobile'),
        reason:
            'this phase is about the desktop drill-down; run it with -d windows',
      );
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));
      final client = Supabase.instance.client;

      await sweepPnlFixtures(client, marker: drillMarker);
      try {
        final ids = await recordDrillFixtures(client);
        await openPnl(tester, container);
        await chooseCustom(tester, container, pnlFrom, pnlTo);
        await refreshPnl(tester, container);
        final units = [
          for (final u in container.read(pnlScopeOptionsProvider).value!.units)
            u.id,
        ];
        final server = await serverPnl(client, units, pnlFrom, pnlTo);
        expectPnlMatchesServer(tester, container, server);

        Finder pageScroll() => find
            .descendant(
              of: find.byKey(const Key('pnl-page')),
              matching: find.byType(Scrollable),
            )
            .first;

        // ── Revenue → Restaurant → the sale ──────────────────────────────────
        final open = find.byKey(Key('pnl-rev-open-$_ccr-${ids.restaurant}'));
        await tester.scrollUntilVisible(open, 300, scrollable: pageScroll());
        await tapWhenHittable(tester, open);
        await pumpUntil(
          tester,
          'the sale in the drill-down',
          () => find
              .byKey(Key('pnl-drill-doc-${ids.sale}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(uiPaise(tester, 'pnl-drill-doc-${ids.sale}-gross'), 12364200);
        expect(
          uiPaise(tester, 'pnl-drill-total-gross'),
          server.revenueLines['$_ccr-${ids.restaurant}']![0],
        );

        final before = await ordinaryAndCacheCounts();
        await tapWhenHittable(
          tester,
          find.byKey(Key('pnl-drill-doc-${ids.sale}')),
        );
        await pumpUntil(
          tester,
          'the sale opened from the report',
          () => find
              .byKey(const Key('pnl-document-revenue'))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        expect(find.textContaining('KI-REV-'), findsWidgets);
        expect(uiPaise(tester, 'pnl-document-contribution-gross'), 12364200);
        expectReportDetailReadOnly();
        expect(await ordinaryAndCacheCounts(), before);

        // ── Expenses → F&B → Food Production → Kirana → the shared bill ──────
        await tapWhenHittable(
          tester,
          find.byKey(const Key('pnl-crumb-report')),
        );
        await pumpUntil(
          tester,
          'the P&L again',
          () => find.byKey(const Key('pnl-statement')).evaluate().isNotEmpty,
        );
        final byDept = find.byKey(const Key('pnl-exp-by-department'));
        await tester.scrollUntilVisible(byDept, 300, scrollable: pageScroll());
        await tapWhenHittable(tester, byDept);
        for (final key in [
          'pnl-drill-dept-$_ccr-${_seedId('dept:CCR/FB')}',
          'pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}',
          'pnl-drill-category-$_ccr-$_kirana',
        ]) {
          await pumpUntil(
            tester,
            key,
            () => find.byKey(Key(key)).evaluate().isNotEmpty,
          );
          await tapWhenHittable(tester, find.byKey(Key(key)));
        }
        final sharedRow = find.byKey(Key('pnl-drill-doc-${ids.shared}'));
        await pumpUntil(
          tester,
          'the shared bill in its bucket',
          () => sharedRow.evaluate().isNotEmpty,
        );
        expect(uiPaise(tester, 'pnl-drill-doc-${ids.shared}-amount'), 2500000);
        await tapWhenHittable(tester, sharedRow);
        await pumpUntil(
          tester,
          'the shared bill opened from the report',
          () => find
              .byKey(const Key('pnl-document-expense'))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        expect(uiPaise(tester, 'pnl-document-contribution-amount'), 2500000);
        expectReportDetailReadOnly();
        expect(await ordinaryAndCacheCounts(), before);

        // ── Offline: the rows stay, the detail says it is not downloaded ─────
        await tapWhenHittable(
          tester,
          find.byKey(const Key('pnl-document-close')),
        );
        _transport.online = false;
        try {
          await tapWhenHittable(tester, sharedRow);
          try {
            await pumpUntil(
              tester,
              'detail not downloaded while offline',
              () =>
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
            );
          } on TestFailure {
            // Say what is on screen instead, so a timeout is evidence rather than a guess.
            final keys = <String>{
              for (final element
                  in find
                      .byWidgetPredicate(
                        (w) =>
                            w.key is ValueKey<String> &&
                            (w.key! as ValueKey<String>).value.startsWith(
                              'pnl-',
                            ),
                      )
                      .evaluate())
                (element.widget.key! as ValueKey<String>).value,
            }.toList()..sort();
            debugPrint('DRILL keys on screen: $keys');
            debugPrint(
              'DRILL session: ${container.read(sessionProvider).runtimeType}',
            );
            debugPrint(
              'DRILL spinners: '
              '${find.byType(CircularProgressIndicator).evaluate().length}',
            );
            debugPrint(
              'DRILL requests while offline: ${_transport.refusedWhileOffline}',
            );
            rethrow;
          }
          expect(
            uiPaise(tester, 'pnl-drill-doc-${ids.shared}-amount'),
            2500000,
          );
        } finally {
          _transport.online = true;
        }
        expect(await ordinaryAndCacheCounts(), before);
      } finally {
        _transport.online = true;
        await sweepPnlFixtures(client, marker: drillMarker);
      }
    });
  });

  group('android-pnl-drill', skip: _phase != 'android-pnl-drill', () {
    testWidgets(
      'the phone drill-down pushes each level, opens a document read-only, writes '
      'nothing, and backs out',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        await container.read(sessionProvider.notifier).refreshAuthority();
        await tester.pump(const Duration(seconds: 2));
        final client = Supabase.instance.client;

        await sweepPnlFixtures(client, marker: drillMarker);
        try {
          final ids = await recordDrillFixtures(client);
          await openPhonePnl(tester, container);
          await choosePhoneCustom(
            tester,
            container,
            BusinessDate.of(2027, 3, 1),
            BusinessDate.of(2027, 3, 31),
          );
          await refreshPhonePnl(tester, container);

          // ── Reports → Restaurant → the sale ──────────────────────────────────
          final open = find.byKey(Key('pnl-rev-open-$_ccr-${ids.restaurant}'));
          await centrePnlControl(tester, open);
          await tapWhenHittable(tester, open);
          await pumpUntil(
            tester,
            'the drill-down page',
            () => find
                .byKey(Key('pnl-drill-doc-${ids.sale}'))
                .evaluate()
                .isNotEmpty,
          );
          expect(find.byType(MobilePnlDrillPage), findsOneWidget);
          expect(uiPaise(tester, 'pnl-drill-doc-${ids.sale}-gross'), 12364200);

          final before = await ordinaryAndCacheCounts();
          await tapWhenHittable(
            tester,
            find.byKey(Key('pnl-drill-doc-${ids.sale}')),
          );
          await pumpUntil(
            tester,
            'the sale page',
            () => find
                .byKey(const Key('pnl-document-revenue'))
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 60),
          );
          expect(find.byType(MobilePnlDocumentPage), findsOneWidget);
          expect(find.textContaining('KI-REV-'), findsWidgets);
          expectReportDetailReadOnly();
          expect(await ordinaryAndCacheCounts(), before);

          // Android back walks up one level at a time.
          await tester.binding.handlePopRoute();
          await pumpUntil(
            tester,
            'back to the documents',
            () => find.byType(MobilePnlDocumentPage).evaluate().isEmpty,
          );
          expect(find.byType(MobilePnlDrillPage), findsOneWidget);
          await tester.binding.handlePopRoute();
          await pumpUntil(
            tester,
            'back to the P&L',
            () => find.byType(MobilePnlDrillPage).evaluate().isEmpty,
          );
          expect(find.byType(MobileProfitAndLossPage), findsOneWidget);

          // ── Expenses by department down to the shared bill ───────────────────
          final byDept = find.byKey(const Key('pnl-exp-by-department'));
          await centrePnlControl(tester, byDept);
          await tapWhenHittable(tester, byDept);
          for (final key in [
            'pnl-drill-dept-$_ccr-${_seedId('dept:CCR/FB')}',
            'pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}',
            'pnl-drill-category-$_ccr-$_kirana',
          ]) {
            await pumpUntil(
              tester,
              key,
              () => find.byKey(Key(key)).evaluate().isNotEmpty,
            );
            await Scrollable.ensureVisible(
              tester.element(find.byKey(Key(key))),
              alignment: 0.3,
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tapWhenHittable(tester, find.byKey(Key(key)));
          }
          final sharedRow = find.byKey(Key('pnl-drill-doc-${ids.shared}'));
          await pumpUntil(
            tester,
            'the shared bill in its bucket',
            () => sharedRow.evaluate().isNotEmpty,
          );
          expect(
            uiPaise(tester, 'pnl-drill-doc-${ids.shared}-amount'),
            2500000,
          );
          await Scrollable.ensureVisible(
            tester.element(sharedRow),
            alignment: 0.3,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tapWhenHittable(tester, sharedRow);
          await pumpUntil(
            tester,
            'the shared bill page',
            () => find
                .byKey(const Key('pnl-document-expense'))
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 60),
          );
          expect(uiPaise(tester, 'pnl-document-contribution-amount'), 2500000);
          expectReportDetailReadOnly();
          expect(await ordinaryAndCacheCounts(), before);

          // ── Offline: detail not downloaded ───────────────────────────────────
          await tester.binding.handlePopRoute();
          await pumpUntil(
            tester,
            'back to the bucket',
            () => find.byType(MobilePnlDocumentPage).evaluate().isEmpty,
          );
          _transport.online = false;
          try {
            await tapWhenHittable(tester, sharedRow);
            await pumpUntil(
              tester,
              'detail not downloaded while offline',
              () =>
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
            );
          } finally {
            _transport.online = true;
          }
          expect(await ordinaryAndCacheCounts(), before);
          for (var i = 0; i < 5; i++) {
            if (find.byType(MobileProfitAndLossPage).evaluate().isNotEmpty &&
                find.byType(MobilePnlDrillPage).evaluate().isEmpty) {
              break;
            }
            await tester.binding.handlePopRoute();
            await tester.pump(const Duration(milliseconds: 500));
          }
        } finally {
          _transport.online = true;
          await sweepPnlFixtures(client, marker: drillMarker);
        }
      },
    );
  });

  group('expense-cleanup', skip: _phase != 'expense-cleanup', () {
    testWidgets('the development fixtures are reversed', (tester) async {
      // Deliberately its own phase: acceptance creates real documents, and the dev
      // project should end a run in the state it started in.
      //
      // This phase used to be `expect(true, isTrue)` — it signed in and asserted
      // nothing, while `PROJECT_STATUS.md` and D-066 both said the fixtures a run
      // creates are removed afterwards. They were not. The list it was meant to consume
      // is per-process, so it was always empty here; the documentation described an
      // intention and the code never carried it out.
      //
      // What it does now is **void**, not delete, and that is not a compromise: the
      // hard constraint is that financial history is corrected by void plus audit and
      // never by deleting rows (spec §14, D-006). A voided document is excluded from
      // every aggregate, stays visible in audit, and carries a reason naming the run —
      // which is exactly the identification D-066 specifies. The append-only audit rows
      // remain either way, and that asymmetry is the point of the guard.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // Read through `expense_document`, never `expenses`. No client role holds SELECT
      // on the base table — the header total on a shared bill is withheld by the
      // projection, and the first version of this phase asked the base table and was
      // refused `42501`, which is the D-062 boundary working exactly as designed.
      final client = Supabase.instance.client;
      final open = await client
          .from('expense_document')
          .select('id,row_version,notes')
          .like('notes', '$_acceptanceMarker%')
          .filter('voided_at', 'is', null);

      final gateway = ExpenseGateway(client);
      var reversed = 0;
      for (final row in open) {
        final outcome = await gateway.voidExpense(
          expenseId: row['id'] as String,
          baseRowVersion: row['row_version'] as int,
          reason: 'Reversing $_acceptanceMarker fixture (D-066)',
          mutationId: const Uuid().v4(),
        );
        // A closed period legitimately refuses a void, and that refusal is the period
        // lock working. It is reported rather than swallowed, and rather than failed on.
        if (outcome.isOk) {
          reversed++;
        } else {
          debugPrint(
            'cleanup: ${row['id']} left in place — '
            '${outcome.refusalOrNull?.code}: ${outcome.refusalOrNull?.message}',
          );
        }
      }
      debugPrint('cleanup: reversed $reversed of ${open.length} fixture(s)');

      // The state that matters is the end state, and it is asserted rather than assumed.
      final remaining = await client
          .from('expense_document')
          .select('id,notes')
          .like('notes', '$_acceptanceMarker%')
          .filter('voided_at', 'is', null);
      expect(
        remaining,
        isEmpty,
        reason:
            'every acceptance document is reversed, or the run says which is not and '
            'why — silence here is what let this phase pass while doing nothing',
      );
    });
  });

  group('propagate-a', skip: _phase != 'propagate-a', () {
    testWidgets('client A renames cosmetically and archives a leaf', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);

      final paneer = await _row('expense_categories', _paneer);
      final rename = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: _paneerRenamed,
        baseRowVersion: paneer['row_version'] as int,
        acknowledged: true,
      );
      expect(
        rename.isOk,
        isTrue,
        reason: 'rename refused: ${rename.refusalOrNull?.message}',
      );
      expect(
        rename.valueOrNull!['row_version'],
        greaterThan(paneer['row_version'] as int),
      );

      final milk = await _row('expense_categories', _milk);
      final archive = await gateway.archive(
        entityType: 'expense_category',
        entityId: _milk,
        baseRowVersion: milk['row_version'] as int,
      );
      expect(
        archive.isOk,
        isTrue,
        reason: 'archive refused: ${archive.refusalOrNull?.message}',
      );

      // The immutable code never moves, whatever the label says (D-035).
      final after = await _row('expense_categories', _paneer);
      expect(after['code'], paneer['code']);
      expect(after['name'], _paneerRenamed);
    });
  });

  group('propagate-b', skip: _phase != 'propagate-b', () {
    testWidgets("the other client's change arrives, once, with the same id", (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final db = boot.database;
      final held = (await db.select(db.expenseCategories).get()).singleWhere(
        (c) => c.id == _paneer,
      );
      final heldVersion = held.rowVersion;
      final heldCode = held.code;
      expect(
        held.name,
        _paneerOriginalName,
        reason: 'client B starts out holding the old label',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // Client A is renaming it right now, on the other platform.
      var arrived = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        final rows = await db.select(db.expenseCategories).get();
        final match = rows.where((c) => c.id == _paneer).toList();
        if (match.length == 1 && match.single.name == _paneerRenamed) {
          arrived = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(arrived, isTrue, reason: 'the rename never reached this client');

      final rows = await db.select(db.expenseCategories).get();
      final now = rows.where((c) => c.id == _paneer).toList();
      expect(
        now,
        hasLength(1),
        reason: 'a rename must not create a second master',
      );
      expect(
        now.single.code,
        heldCode,
        reason: 'the immutable code never moves',
      );
      expect(
        now.single.rowVersion,
        greaterThan(heldVersion),
        reason: 'the version the server assigned came with it',
      );

      // The archived leaf arrived as archived, and is out of the picker for new use.
      final milk = rows.singleWhere((c) => c.id == _milk);
      expect(milk.archivedAt, isNotNull);
      expect(
        milk.name,
        isNotEmpty,
        reason: 'archiving keeps the record; history stays readable',
      );

      // A stale intent from this client is a conflict, not a rejection.
      final gateway = MasterGateway(Supabase.instance.client);
      final stale = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: 'Stale From Client B',
        baseRowVersion: heldVersion,
        acknowledged: true,
      );
      expect(stale.isRefused, isTrue);
      expect(stale.refusalOrNull!.kind, RefusalKind.versionConflict);

      final server = await _row('expense_categories', _paneer);
      expect(server['name'], _paneerRenamed);
    });
  });

  group('propagate-restore', skip: _phase != 'propagate-restore', () {
    testWidgets('the development fixtures are put back', (tester) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);

      final paneer = await _row('expense_categories', _paneer);
      if (paneer['name'] != _paneerOriginalName) {
        final back = await gateway.rename(
          entityType: 'expense_category',
          entityId: _paneer,
          newName: _paneerOriginalName,
          baseRowVersion: paneer['row_version'] as int,
          acknowledged: true,
        );
        expect(back.isOk, isTrue, reason: '${back.refusalOrNull?.message}');
      }

      final milk = await _row('expense_categories', _milk);
      if (milk['archived_at'] != null) {
        final restored = await gateway.restore(
          entityType: 'expense_category',
          entityId: _milk,
          baseRowVersion: milk['row_version'] as int,
        );
        expect(
          restored.isOk,
          isTrue,
          reason: '${restored.refusalOrNull?.message}',
        );
      }

      expect(
        (await _row('expense_categories', _paneer))['name'],
        _paneerOriginalName,
      );
      expect((await _row('expense_categories', _milk))['archived_at'], isNull);
    });
  });

  // ── Phase 5 Slice 11: full reporting and Owner Accounts acceptance ─────────
  //
  // The completed surfaces together, in the real applications against krishna-mis-dev:
  // the shared device, the whole correction/void/period lifecycle, a closed period, offline
  // and reconnect, an older financial year, the Owner Settlement preview, and a confirmed
  // capability loss while a report is open. Every figure is compared, in paise, against the
  // server's own primitives or the independent settlement oracle — never against production
  // arithmetic. Financial fixtures carry a marker and are voided in a `finally` and before
  // the next run (D-066, D-071, D-076). The disposable settlement start date is removed by
  // the host through the administrator path after the phase; the client has no such path.

  const s11Marker = '$_acceptanceMarker: slice11';
  const s11FixtureStart = '2026-05-01';
  const s11OwnerA = '993e6fa6-1513-4a99-9d45-ebf6440a1d88';
  const s11OwnerB = '62f72e3e-20b3-4085-8363-13c62d868dfe';
  const s11Handshake = String.fromEnvironment('S11_HANDSHAKE');

  bool s11Phone() => boot.shellKind.name == 'mobile';

  Future<ProviderContainer> s11SignIn(WidgetTester tester, String email) async {
    await signIn(tester, email);
    await expectSignedIn(tester, email);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    await container.read(sessionProvider.notifier).refreshAuthority();
    await tester.pump(const Duration(seconds: 2));
    return container;
  }

  Future<void> s11OpenPnl(WidgetTester tester, ProviderContainer container) =>
      s11Phone() ? openPhonePnl(tester, container) : openPnl(tester, container);

  Future<void> s11Range(
    WidgetTester tester,
    ProviderContainer container,
    String from,
    String to,
  ) => s11Phone()
      ? choosePhoneCustom(
          tester,
          container,
          BusinessDate.tryParse(from)!,
          BusinessDate.tryParse(to)!,
        )
      : chooseCustom(tester, container, from, to);

  Future<void> s11Refresh(
    WidgetTester tester,
    ProviderContainer container, {
    PnlSyncPhase expected = PnlSyncPhase.succeeded,
    Key control = const Key('pnl-refresh'),
  }) => s11Phone()
      ? refreshPhonePnl(tester, container, expected: expected, control: control)
      : refreshPnl(tester, container, expected: expected, control: control);

  /// Runs a synchronisation from a control that carries no key of its own — the "Try again"
  /// inside a failed download — and waits for it to finish, as `refreshPnl` does for a keyed
  /// control.
  Future<void> s11RefreshFrom(
    WidgetTester tester,
    ProviderContainer container,
    Finder control, {
    PnlSyncPhase expected = PnlSyncPhase.succeeded,
  }) async {
    await settlePnl(tester, container);
    if (s11Phone()) await centrePnlControl(tester, control);
    final before = container.read(pnlSyncProvider);
    await tapWhenHittable(tester, control);
    await pumpUntil(
      tester,
      'the P&L synchronisation to finish',
      () {
        final now = container.read(pnlSyncProvider);
        return !identical(now, before) && !now.isRunning;
      },
      timeout: const Duration(seconds: 90),
    );
    expect(container.read(pnlSyncProvider).phase, expected);
    await settlePnl(tester, container);
  }

  Future<String> s11Restaurant(SupabaseClient client) async =>
      (await client
              .from('revenue_categories')
              .select('id')
              .eq('code', 'RESTAURANT')
              .eq('business_unit_id', _ccr)
              .single())['id']
          as String;

  Future<int> s11Version(
    SupabaseClient client,
    String relation,
    String id,
  ) async =>
      (await client
              .from(relation)
              .select('row_version')
              .eq('id', id)
              .single())['row_version']
          as int;

  Future<String> s11Sale(
    SupabaseClient client,
    String marker,
    String date,
    int amount,
  ) async {
    final id = const Uuid().v7();
    await client.rpc<dynamic>(
      'revenue_create',
      params: {
        'p_id': id,
        'p_business_unit_id': _ccr,
        'p_revenue_category_id': await s11Restaurant(client),
        'p_business_date': date,
        'p_notes': '$marker sale',
        'p_components': [
          {'entered_amount_minor': amount},
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return id;
  }

  Future<String> s11Cost(
    SupabaseClient client,
    String marker,
    String date,
    int amount,
  ) async {
    final id = const Uuid().v7();
    await client.rpc<dynamic>(
      'expense_create',
      params: {
        'p_id': id,
        'p_business_date': date,
        'p_total_minor': amount,
        'p_notes': '$marker expense',
        'p_allocations': [
          {
            'business_unit_id': _ccr,
            'department_id': _seedId('dept:CCR/FB'),
            'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
            'category_id': _kirana,
            'amount_minor': amount,
          },
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return id;
  }

  Finder s11DesktopPage() => find
      .descendant(
        of: find.byKey(const Key('pnl-page')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> s11Reach(WidgetTester tester, Finder finder) async {
    if (s11Phone()) {
      await centrePnlControl(tester, finder);
    } else {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: s11DesktopPage(),
      );
    }
  }

  /// Revenue → Restaurant → the sale, opened read-only.
  Future<void> s11OpenSale(
    WidgetTester tester,
    String restaurant,
    String sale, {
    bool expectDetail = true,
  }) async {
    final open = find.byKey(Key('pnl-rev-open-$_ccr-$restaurant'));
    await s11Reach(tester, open);
    await tapWhenHittable(tester, open);
    final row = find.byKey(Key('pnl-drill-doc-$sale'));
    await pumpUntil(
      tester,
      'the sale in the drill-down',
      () => row.evaluate().isNotEmpty,
    );
    await Scrollable.ensureVisible(tester.element(row), alignment: 0.3);
    await tester.pump(const Duration(milliseconds: 300));
    await tapWhenHittable(tester, row);
    if (expectDetail) {
      await pumpUntil(
        tester,
        'the sale opened read-only',
        () =>
            find.byKey(const Key('pnl-document-revenue')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );
    }
  }

  Future<void> s11BackToReport(WidgetTester tester) async {
    if (s11Phone()) {
      for (var i = 0; i < 6; i++) {
        if (find.byType(MobilePnlDrillPage).evaluate().isEmpty &&
            find.byType(MobilePnlDocumentPage).evaluate().isEmpty) {
          break;
        }
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 500));
      }
    } else {
      final crumb = find.byKey(const Key('pnl-crumb-report'));
      if (crumb.evaluate().isNotEmpty) await tapWhenHittable(tester, crumb);
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<int> s11OwnerCacheRows(String ownerUserId) async {
    var total = 0;
    for (final table in const [
      'canonical_owner_movements',
      'canonical_owners',
      'canonical_ownership_shares',
      'owner_settlement_coverage',
    ]) {
      total +=
          (await boot.database
                  .customSelect(
                    'SELECT COUNT(*) AS c FROM $table WHERE owner_user_id = ?',
                    variables: [Variable<String>(ownerUserId)],
                  )
                  .getSingle())
              .read<int>('c');
    }
    return total;
  }

  bool s11SettlementEntryVisible() => s11Phone()
      ? find.byKey(const Key('more-owner-settlement')).evaluate().isNotEmpty
      : visible('Owner Settlement');

  Future<void> s11ShowNavigation(WidgetTester tester) async {
    if (s11Phone()) {
      await pumpUntil(tester, 'the More tab', () => visible('More'));
      await tapWhenHittable(tester, find.text('More').last);
      await tester.pump(const Duration(seconds: 1));
    } else {
      await pumpUntil(tester, 'the sidebar', () => visible('Analytics'));
    }
  }

  Future<void> s11OpenSettlement(WidgetTester tester) async {
    await s11ShowNavigation(tester);
    if (s11Phone()) {
      final entry = find.byKey(const Key('more-owner-settlement'));
      await pumpUntil(
        tester,
        'the Owner Settlement entry',
        () => entry.evaluate().isNotEmpty,
      );
      await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
      await tester.pump(const Duration(milliseconds: 300));
      await tapWhenHittable(tester, entry);
    } else {
      await pumpUntil(
        tester,
        'the Owner Settlement destination',
        () => visible('Owner Settlement'),
      );
      await tapWhenHittable(tester, find.text('Owner Settlement').first);
    }
    await pumpUntil(
      tester,
      'the settlement page',
      () =>
          find.byKey(const Key('owner-settlement-page')).evaluate().isNotEmpty,
    );
  }

  Future<void> s11SettleSettlement(
    WidgetTester tester,
    ProviderContainer container,
  ) => pumpUntil(
    tester,
    'the settlement preview to be read',
    () {
      final preview = container.read(ownerSettlementPreviewProvider);
      return preview.hasValue &&
          !preview.isLoading &&
          container.read(ownerSettlementSyncProvider).phase !=
              OwnerSettlementSyncPhase.synchronising;
    },
    timeout: const Duration(seconds: 180),
  );

  Future<void> s11RefreshSettlement(
    WidgetTester tester,
    ProviderContainer container, {
    OwnerSettlementSyncPhase expected = OwnerSettlementSyncPhase.succeeded,
  }) async {
    await s11SettleSettlement(tester, container);
    final before = container.read(ownerSettlementSyncProvider);
    final refresh = find.byKey(const Key('owner-settlement-refresh'));
    await Scrollable.ensureVisible(tester.element(refresh), alignment: 0.2);
    await tester.pump(const Duration(milliseconds: 300));
    await tapWhenHittable(tester, refresh);
    await pumpUntil(
      tester,
      'the settlement refresh to finish',
      () {
        final now = container.read(ownerSettlementSyncProvider);
        return !identical(now, before) &&
            now.phase != OwnerSettlementSyncPhase.synchronising;
      },
      timeout: const Duration(seconds: 180),
    );
    expect(container.read(ownerSettlementSyncProvider).phase, expected);
    await s11SettleSettlement(tester, container);
  }

  Future<void> s11SettlementMonth(
    WidgetTester tester,
    ProviderContainer container,
    int year,
    int month,
  ) async {
    for (var i = 0; i < 24; i++) {
      final current = container.read(settlementMonthProvider);
      if (current.year == year && current.month == month) break;
      await tapWhenHittable(
        tester,
        find.byKey(const Key('owner-settlement-previous-month')),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    final current = container.read(settlementMonthProvider);
    expect((current.year, current.month), (year, month));
    await s11SettleSettlement(tester, container);
  }

  /// The disposable start date, through the audited administrative boundary. Never a
  /// production date: the host removes it through the administrator path afterwards.
  Future<void> s11EnsureFixtureStart(SupabaseClient client) async {
    final rows = await client
        .from('owner_settlement_settings')
        .select('ownership_start_date,row_version');
    if (rows.isNotEmpty) {
      expect(
        rows.single['ownership_start_date'],
        s11FixtureStart,
        reason: 'only the disposable fixture date may ever be present on dev',
      );
      return;
    }
    await client.rpc<dynamic>(
      'owner_settlement_start_set',
      params: {
        'p_ownership_start_date': s11FixtureStart,
        'p_base_row_version': null,
        'p_mutation_id': const Uuid().v4(),
      },
    );
  }

  Future<void> s11SweepOwnerMovements(
    SupabaseClient client,
    String marker,
  ) async {
    final open = await client
        .from('owner_ledger_entries')
        .select('id,row_version')
        .like('remarks', '$marker%')
        .isFilter('voided_at', null);
    for (final row in open) {
      await client.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': row['id'],
          'p_reason': 'Reversing $marker fixture (D-066)',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
    final remaining = await client
        .from('owner_ledger_entries')
        .select('id')
        .like('remarks', '$marker%')
        .isFilter('voided_at', null);
    expect(remaining, isEmpty, reason: 'every owner movement fixture reversed');
  }

  /// June 2026, by the independent oracle, from the server's own P&L primitives and the
  /// server's own owner snapshot.
  Future<ReferenceStatement> s11ExpectedJune(
    SupabaseClient client,
    List<String> units,
  ) async {
    final atEnd = await serverPnl(client, units, s11FixtureStart, '2026-06-30');
    final before = await serverPnl(
      client,
      units,
      s11FixtureStart,
      '2026-05-31',
    );
    final snapshot = Map<String, dynamic>.from(
      await client.rpc<dynamic>('owner_ledger_snapshot') as Map,
    );
    expect(snapshot['settlement_authorised'], isTrue);
    return referenceSettlement(
      ownerIds: [s11OwnerA, s11OwnerB]..sort(),
      cumulativeBeforePaise: before.net - before.expenses,
      cumulativeAtEndPaise: atEnd.net - atEnd.expenses,
      periodStart: '2026-06-01',
      periodEnd: '2026-06-30',
      movements: [
        for (final raw in snapshot['movements'] as List)
          if ((raw as Map)['business_date'].toString().compareTo(
                s11FixtureStart,
              ) >=
              0)
            (
              ownerId: raw['owner_id'] as String,
              type: raw['movement_type'] as String,
              direction: raw['direction'] as String,
              amountPaise: (raw['amount_minor'] as num).toInt(),
              businessDate: raw['business_date'] as String,
              canonical: raw['voided_at'] == null && raw['txn_number'] != null,
            ),
      ],
    );
  }

  void s11ExpectSettlementMatches(
    WidgetTester tester,
    ProviderContainer container,
    ReferenceStatement expected,
  ) {
    final preview = container.read(ownerSettlementPreviewProvider).value;
    expect(preview, isA<OwnerSettlementPreviewReady>(), reason: '$preview');
    final statement = (preview! as OwnerSettlementPreviewReady).statement;
    expect(statement.operatingProfit.paise, expected.operatingProfitPaise);
    expect(statement.undistributedRemainder.paise, expected.remainderPaise);
    expect(
      uiPaise(tester, 'owner-settlement-op-consolidated'),
      expected.operatingProfitPaise,
    );
    final lines = {for (final l in statement.lines) l.ownerId: l};
    for (final line in expected.lines) {
      final actual = lines[line.ownerId]!;
      expect(actual.openingPosition.paise, line.openingPaise);
      expect(actual.profitEntitlement.paise, line.entitlementPaise);
      expect(actual.withdrawals.paise, line.withdrawalsPaise);
      expect(actual.ncConsumption.paise, line.ncPaise);
      expect(actual.settlementPaid.paise, line.settlementPaidPaise);
      expect(actual.closingPosition.paise, line.closingPaise);
      expect(
        uiPaise(tester, 'owner-settlement-closing-${line.ownerId}'),
        line.closingPaise,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(Key('owner-settlement-closing-label-${line.ownerId}')),
            )
            .data,
        line.closingPaise < 0
            ? 'Recoverable from owner'
            : line.closingPaise == 0
            ? 'Nil — nothing due either way'
            : 'Due to owner',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  for (final (phase, phone) in const [
    ('windows-owner-settlement', false),
    ('android-owner-settlement', true),
  ]) {
    group(phase, skip: _phase != phase, () {
      testWidgets(
        'Owner Settlement: not configured, then a disposable start date, the oracle to '
        'the paisa, offline, and a reader who may not see it',
        (tester) async {
          expect(
            s11Phone(),
            phone,
            reason: 'run $phase on ${phone ? 'the Android device' : 'Windows'}',
          );
          const marker = '$s11Marker settlement';
          await launch(tester);
          var container = await s11SignIn(tester, 'giridhar@hki.com');
          final client = Supabase.instance.client;
          final ownerId = container.read(principalProvider).userId;

          expect(
            await client.from('owner_settlement_settings').select('org_id'),
            isEmpty,
            reason:
                'the development baseline is "Settlement start date not configured"',
          );
          await s11SweepOwnerMovements(client, marker);

          try {
            // ── The clean baseline: not configured, and no figure ─────────────
            await s11OpenSettlement(tester);
            await s11RefreshSettlement(tester, container);
            expect(
              find.byKey(
                const Key(
                  'owner-settlement-unavailable-startDateNotConfigured',
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('owner-settlement-statement')),
              findsNothing,
            );

            // ── A disposable start date and one owner movement ────────────────
            await s11EnsureFixtureStart(client);
            await client.rpc<dynamic>(
              'owner_movement_create',
              params: {
                'p_id': const Uuid().v4(),
                'p_business_unit_id': _hki,
                'p_business_date': '2026-06-12',
                'p_movement_type': 'withdrawal',
                'p_amount_minor': 1234567,
                'p_direction': null,
                'p_family_member_id': null,
                'p_declared_owner_id': null,
                'p_owner_id': s11OwnerA,
                'p_remarks': '$marker withdrawal',
                'p_reason': null,
                'p_mutation_id': const Uuid().v4(),
              },
            );

            await s11RefreshSettlement(tester, container);
            await s11SettlementMonth(tester, container, 2026, 6);
            expect(
              find.byKey(const Key('owner-settlement-preview-banner')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('owner-settlement-statement')),
              findsOneWidget,
            );
            final units = [
              for (final unit
                  in container
                      .read(masterGraphProvider)
                      .value!
                      .businessUnits(includeArchived: true))
                unit.id,
            ];
            final expected = await s11ExpectedJune(client, units);
            s11ExpectSettlementMatches(tester, container, expected);
            expect(
              expected.lines
                  .firstWhere((l) => l.ownerId == s11OwnerA)
                  .withdrawalsPaise,
              1234567,
            );

            // ── Offline: the complete preview stays readable, never ₹0 ────────
            final closingA = uiPaise(
              tester,
              'owner-settlement-closing-$s11OwnerA',
            );
            _transport.online = false;
            try {
              await s11RefreshSettlement(
                tester,
                container,
                expected: OwnerSettlementSyncPhase.failed,
              );
              expect(
                find.byKey(const Key('owner-settlement-offline')),
                findsOneWidget,
              );
              expect(
                uiPaise(tester, 'owner-settlement-closing-$s11OwnerA'),
                closingA,
              );
              s11ExpectSettlementMatches(tester, container, expected);
            } finally {
              _transport.online = true;
            }

            await s11SweepOwnerMovements(client, marker);
            expect(await s11OwnerCacheRows(ownerId), greaterThan(0));

            // ── A reader who may not see a settlement ─────────────────────────
            container = await s11SignIn(tester, 'accountant@example.com');
            expect(
              await s11OwnerCacheRows(ownerId),
              0,
              reason: 'sign-out took the owner-sensitive cache with it',
            );
            await s11ShowNavigation(tester);
            expect(s11SettlementEntryVisible(), isFalse);
            final direct = await container.read(
              ownerSettlementPreviewProvider.future,
            );
            expect(direct, isA<OwnerSettlementPreviewUnavailable>());
            expect(
              (direct as OwnerSettlementPreviewUnavailable).reason,
              OwnerSettlementUnavailableReason.notAuthorised,
            );
          } finally {
            _transport.online = true;
            if (container.read(principalProvider).userId != ownerId) {
              container = await s11SignIn(tester, 'giridhar@hki.com');
            }
            await s11SweepOwnerMovements(client, marker);
          }
        },
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('slice11-shared-device', skip: _phase != 'slice11-shared-device', () {
    testWidgets(
      'the next person on the same installation inherits no figure, scope, drill-down, '
      'document, freshness, coverage or settlement from the last',
      (tester) async {
        const marker = '$s11Marker shared';
        await launch(tester);
        var container = await s11SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        final cache = ReportingCache(boot.database);
        final ownerId = container.read(principalProvider).userId;
        await sweepPnlFixtures(client, marker: marker);

        try {
          // ── The Owner: consolidated P&L, a drill-down, a document, the settlement ─
          final restaurant = await s11Restaurant(client);
          final sale = await s11Sale(client, marker, pnlDate, 12364200);
          await s11OpenPnl(tester, container);
          await s11Range(tester, container, pnlFrom, pnlTo);
          await s11Refresh(tester, container);
          final units = [
            for (final u
                in container.read(pnlScopeOptionsProvider).value!.units)
              u.id,
          ];
          expect(
            container.read(pnlScopeOptionsProvider).value!.consolidatedAllowed,
            isTrue,
          );
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, units, pnlFrom, pnlTo),
          );
          await s11OpenSale(tester, restaurant, sale);
          expect(find.textContaining('KI-REV-'), findsWidgets);
          await s11BackToReport(tester);

          await s11EnsureFixtureStart(client);
          await s11OpenSettlement(tester);
          await s11RefreshSettlement(tester, container);
          await s11SettlementMonth(tester, container, 2026, 6);
          expect(
            find.byKey(const Key('owner-settlement-statement')),
            findsOneWidget,
          );
          expect(await cache.markersFor(ownerId), isNotEmpty);
          expect(await s11OwnerCacheRows(ownerId), greaterThan(0));

          // ── The Owner signs out ─────────────────────────────────────────────────
          await container.read(sessionProvider.notifier).signOut();
          await tester.pump(const Duration(seconds: 3));
          expect(await cache.markersFor(ownerId), isEmpty);
          expect(await reportingCacheRows(ownerId), 0);
          expect(await s11OwnerCacheRows(ownerId), 0);

          // ── The next person, before any synchronisation of their own ────────────
          await signIn(tester, 'ccr.manager@example.com');
          await expectSignedIn(tester, 'ccr.manager@example.com');
          container = ProviderScope.containerOf(
            tester.element(find.byType(KrishnaMisApp)),
          );
          final manager = container.read(principalProvider);
          expect(manager.userId, isNot(ownerId));
          expect(PnlAuthority.mayReadConsolidated(manager), isFalse);
          expect(PnlAuthority.mayReadUnit(manager, _hki), isFalse);
          expect(container.read(pnlSelectionProvider).scope, isNull);
          expect(container.read(pnlDrillProvider), isNull);
          expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
          expect(find.textContaining('KI-REV-'), findsNothing);
          expect(await cache.markersFor(manager.userId), isEmpty);
          expect(await cache.markersFor(ownerId), isEmpty);
          expect(await reportingCacheRows(ownerId), 0);
          expect(await s11OwnerCacheRows(ownerId), 0);
          final shown = pnlViewShownTo(
            container.read(pnlViewProvider),
            manager,
          );
          expect(
            shown is! PnlReportView || shown.viewerUserId == manager.userId,
            isTrue,
            reason: 'no report computed for the Owner may be shown',
          );
          await s11ShowNavigation(tester);
          expect(s11SettlementEntryVisible(), isFalse);
          final settlement = await container.read(
            ownerSettlementPreviewProvider.future,
          );
          expect(
            (settlement as OwnerSettlementPreviewUnavailable).reason,
            OwnerSettlementUnavailableReason.notAuthorised,
          );

          // ── After their own synchronisation: their property, exactly ─────────────
          await s11OpenPnl(tester, container);
          expect(find.text('Both properties (consolidated)'), findsNothing);
          await s11Range(tester, container, pnlFrom, pnlTo);
          await s11Refresh(tester, container);
          final view = container.read(pnlViewProvider).value! as PnlReportView;
          expect(view.viewerUserId, manager.userId);
          expect(view.scope, PnlUnitScope(_ccr));
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, [_ccr], pnlFrom, pnlTo),
          );
          final markers = await cache.markersFor(manager.userId);
          expect({for (final m in markers) m.businessUnitId}, {_ccr});
          expect(await cache.markersFor(ownerId), isEmpty);
          expect(
            await reportingCacheRows(manager.userId, businessUnitId: _hki),
            0,
          );
        } finally {
          _transport.online = true;
          if (container.read(principalProvider).userId != ownerId) {
            container = await s11SignIn(tester, 'giridhar@hki.com');
          }
          await sweepPnlFixtures(client, marker: marker);
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('slice11-lifecycle', skip: _phase != 'slice11-lifecycle', () {
    testWidgets(
      'create, correct across periods, close a period, void, go offline and back, and '
      'download an older financial year — every figure equal to the server',
      (tester) async {
        const marker = '$s11Marker lifecycle';
        const febFrom = '2027-02-01';
        const febTo = '2027-02-28';
        const olderFrom = '2025-03-01';
        const olderTo = '2025-03-31';
        await launch(tester);
        final container = await s11SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        final cache = ReportingCache(boot.database);
        await sweepPnlFixtures(client, marker: marker);
        var closed = false;

        Future<void> reopenMarch() async {
          final lock = await client
              .from('period_locks')
              .select('row_version,state')
              .eq('period_key', '2027-03')
              .eq('business_unit_id', _ccr)
              .maybeSingle();
          if (lock == null || lock['state'] != 'closed') return;
          await client.rpc<dynamic>(
            'period_reopen',
            params: {
              'p_period_key': '2027-03',
              'p_business_unit_id': _ccr,
              'p_reason': '$marker: restoring the closed-period fixture',
              'p_base_row_version': lock['row_version'],
              'p_mutation_id': const Uuid().v4(),
            },
          );
        }

        try {
          await s11OpenPnl(tester, container);
          final units = [
            for (final u
                in container.read(pnlScopeOptionsProvider).value!.units)
              u.id,
          ];
          final feb0 = await serverPnl(client, units, febFrom, febTo);
          final mar0 = await serverPnl(client, units, pnlFrom, pnlTo);
          final restaurant = await s11Restaurant(client);

          // ── Create in February ────────────────────────────────────────────────
          final sale = await s11Sale(client, marker, '2027-02-10', 5000000);
          final cost = await s11Cost(client, marker, '2027-02-11', 1200000);
          await s11Range(tester, container, febFrom, febTo);
          await s11Refresh(tester, container);
          var feb = await serverPnl(client, units, febFrom, febTo);
          expect(feb.gross - feb0.gross, 5000000);
          expect(feb.expenses - feb0.expenses, 1200000);
          expectPnlMatchesServer(tester, container, feb);

          // ── Correct both into March: a business date and an accounting period ──
          await client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': sale,
              'p_business_date': '2027-03-10',
              'p_notes': '$marker sale',
              'p_components': [
                {'entered_amount_minor': 5000000},
              ],
              'p_base_row_version': await s11Version(
                client,
                'revenue_document',
                sale,
              ),
              'p_correction_reason':
                  'Recorded against the wrong trading day ($marker)',
              'p_mutation_id': const Uuid().v4(),
            },
          );
          await client.rpc<dynamic>(
            'expense_update',
            params: {
              'p_id': cost,
              'p_base_row_version': await s11Version(
                client,
                'expense_document',
                cost,
              ),
              'p_business_date': '2027-02-11',
              'p_total_minor': 1200000,
              'p_allocations': [
                {
                  'business_unit_id': _ccr,
                  'department_id': _seedId('dept:CCR/FB'),
                  'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
                  'category_id': _kirana,
                  'amount_minor': 1200000,
                },
              ],
              'p_period_start': '2027-03-01',
              'p_period_end': '2027-03-31',
              'p_notes': '$marker expense',
              'p_mutation_id': const Uuid().v4(),
            },
          );
          await s11Refresh(tester, container);
          feb = await serverPnl(client, units, febFrom, febTo);
          expect(feb.gross, feb0.gross, reason: 'nothing left in February');
          expect(feb.expenses, feb0.expenses);
          expectPnlMatchesServer(tester, container, feb);

          await s11Range(tester, container, pnlFrom, pnlTo);
          await s11Refresh(tester, container);
          var mar = await serverPnl(client, units, pnlFrom, pnlTo);
          expect(mar.gross - mar0.gross, 5000000, reason: 'moved exactly once');
          expect(mar.expenses - mar0.expenses, 1200000);
          expectPnlMatchesServer(tester, container, mar);

          // ── Offline, then reconnect ───────────────────────────────────────────
          final before =
              (container.read(pnlViewProvider).value! as PnlReportView)
                  .envelope
                  .freshness
                  ?.synchronisedAt;
          expect(before, isNotNull);
          final grossBefore = uiPaise(tester, 'pnl-gross');
          _transport.online = false;
          try {
            await s11Refresh(tester, container, expected: PnlSyncPhase.failed);
            expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
            expect(uiPaise(tester, 'pnl-gross'), grossBefore);
            expect(find.byKey(const Key('pnl-not-authorised')), findsNothing);
            await s11OpenSale(tester, restaurant, sale, expectDetail: false);
            await pumpUntil(
              tester,
              'detail not downloaded while offline',
              () =>
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
            );
            await s11BackToReport(tester);
          } finally {
            _transport.online = true;
          }
          await tester.pump(const Duration(seconds: 2));
          await s11Refresh(tester, container);
          final after =
              (container.read(pnlViewProvider).value! as PnlReportView)
                  .envelope
                  .freshness
                  ?.synchronisedAt;
          expect(
            after!.isAfter(before!),
            isTrue,
            reason: 'freshness moved forward',
          );
          expectPnlMatchesServer(tester, container, mar);

          // ── A closed period stays readable and refuses a correction ────────────
          await client.rpc<dynamic>(
            'period_close',
            params: {
              'p_period_key': '2027-03',
              'p_business_unit_id': _ccr,
              'p_mutation_id': const Uuid().v4(),
            },
          );
          closed = true;
          await s11Refresh(tester, container);
          expectPnlMatchesServer(tester, container, mar);
          await s11OpenSale(tester, restaurant, sale);
          expect(find.textContaining('KI-REV-'), findsWidgets);
          await s11BackToReport(tester);
          try {
            await client.rpc<dynamic>(
              'revenue_update',
              params: {
                'p_id': sale,
                'p_business_date': '2027-03-10',
                'p_notes': '$marker sale',
                'p_components': [
                  {'entered_amount_minor': 5100000},
                ],
                'p_base_row_version': await s11Version(
                  client,
                  'revenue_document',
                  sale,
                ),
                'p_mutation_id': const Uuid().v4(),
              },
            );
            fail('a correction inside a closed period was accepted');
          } on PostgrestException catch (e) {
            expect(e.code, 'KM004');
          }
          expect(
            (await client
                .from('period_locks')
                .select('state')
                .eq('period_key', '2027-03')
                .eq('business_unit_id', _ccr)
                .single())['state'],
            'closed',
            reason: 'reporting neither reopened nor altered the period',
          );
          expect(
            (await serverPnl(client, units, pnlFrom, pnlTo)).gross,
            mar.gross,
          );
          await reopenMarch();
          closed = false;

          // ── Void both: the effect leaves ──────────────────────────────────────
          await sweepPnlFixtures(client, marker: marker);
          await s11Refresh(tester, container);
          mar = await serverPnl(client, units, pnlFrom, pnlTo);
          expect(mar.gross, mar0.gross);
          expect(mar.expenses, mar0.expenses);
          expectPnlMatchesServer(tester, container, mar);

          // ── An older financial year ────────────────────────────────────────────
          final older = await s11Cost(client, marker, '2025-03-12', 777700);
          await s11Range(tester, container, olderFrom, olderTo);
          expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
          _transport.online = false;
          try {
            await s11Refresh(
              tester,
              container,
              expected: PnlSyncPhase.failed,
              control: const Key('pnl-download'),
            );
            expect(
              find.byKey(const Key('pnl-statement')),
              findsNothing,
              reason: 'an interrupted download never masquerades as complete',
            );
            expect(
              (await cache.markersFor(
                container.read(principalProvider).userId,
              )).where((m) => m.financialYear == 2024),
              isEmpty,
            );
          } finally {
            _transport.online = true;
          }
          // The failed download says so and offers to try again. It has no key: it is the
          // one action inside the failed-download message.
          final failed = find.byKey(const Key('pnl-download-failed'));
          expect(failed, findsOneWidget);
          await s11RefreshFrom(
            tester,
            container,
            find.descendant(of: failed, matching: find.byType(OutlinedButton)),
          );
          final olderServer = await serverPnl(
            client,
            units,
            olderFrom,
            olderTo,
          );
          expectPnlMatchesServer(tester, container, olderServer);

          // Offline afterwards: the rows beneath it are readable, the detail is not.
          _transport.online = false;
          try {
            final byDept = find.byKey(const Key('pnl-exp-by-department'));
            await s11Reach(tester, byDept);
            await tapWhenHittable(tester, byDept);
            for (final key in [
              'pnl-drill-dept-$_ccr-${_seedId('dept:CCR/FB')}',
              'pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}',
              'pnl-drill-category-$_ccr-$_kirana',
            ]) {
              await pumpUntil(
                tester,
                key,
                () => find.byKey(Key(key)).evaluate().isNotEmpty,
              );
              await Scrollable.ensureVisible(
                tester.element(find.byKey(Key(key))),
                alignment: 0.3,
              );
              await tester.pump(const Duration(milliseconds: 300));
              await tapWhenHittable(tester, find.byKey(Key(key)));
            }
            final row = find.byKey(Key('pnl-drill-doc-$older'));
            await pumpUntil(
              tester,
              'the older expense row, offline',
              () => row.evaluate().isNotEmpty,
            );
            expect(uiPaise(tester, 'pnl-drill-doc-$older-amount'), 777700);
            await Scrollable.ensureVisible(tester.element(row), alignment: 0.3);
            await tester.pump(const Duration(milliseconds: 300));
            await tapWhenHittable(tester, row);
            await pumpUntil(
              tester,
              'older detail not downloaded while offline',
              () =>
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
            );
            await s11BackToReport(tester);
          } finally {
            _transport.online = true;
          }
        } finally {
          _transport.online = true;
          if (closed) await reopenMarch();
          await reopenMarch();
          await sweepPnlFixtures(client, marker: marker);
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //
  // A confirmed capability loss while a report is open, in the real Windows executable. The
  // signed-in person cannot withdraw their own capability, so the host does it through the
  // administrator path while this phase waits, exactly as the Phase 2 `revoked` phase has
  // the host revoke a grant. The two talk through a handshake file named by S11_HANDSHAKE:
  // the phase writes `ready`, the host changes the development role and writes `applied`, the
  // phase observes the loss through a real authority refresh and writes `verified`, the host
  // restores the role exactly and writes `restored`.

  Future<void> s11Signal(String step, String state) async => File(
    s11Handshake,
  ).writeAsStringSync(jsonEncode({'step': step, 'state': state}));

  Future<void> s11AwaitHost(WidgetTester tester, String step, String state) =>
      pumpUntil(tester, 'the host to report $step $state', () {
        try {
          final m = jsonDecode(File(s11Handshake).readAsStringSync()) as Map;
          return m['step'] == step && m['state'] == state;
        } on Object {
          return false;
        }
      }, timeout: const Duration(minutes: 20));

  Future<void> s11AuthorityUntil(
    WidgetTester tester,
    ProviderContainer container,
    String what,
    bool Function(Principal principal) done,
  ) async {
    for (var i = 0; i < 60; i++) {
      await container.read(sessionProvider.notifier).refreshAuthority();
      await tester.pump(const Duration(seconds: 2));
      if (done(container.read(principalProvider))) return;
    }
    fail('the confirmed authority never showed $what');
  }

  // A session must come back on its own when the application is started again. Two process
  // launches on one Windows installation: the first signs in and synchronises a report and
  // exits **without signing out**; the second signs nobody in. The Android emulator reinstalls
  // the application on every launch, so there this is a manual physical-device check (§Q.2).
  group('slice11-restart-a', skip: _phase != 'slice11-restart-a', () {
    testWidgets(
      'a person signs in, synchronises a report, and the process ends',
      (tester) async {
        expect(s11Phone(), isFalse, reason: 'run on Windows');
        await launch(tester);
        final container = await s11SignIn(tester, 'ccr.manager@example.com');
        await s11OpenPnl(tester, container);
        await s11Range(tester, container, pnlFrom, pnlTo);
        await s11Refresh(tester, container);
        final view = container.read(pnlViewProvider).value! as PnlReportView;
        expect(view.scope, PnlUnitScope(_ccr));
        expect(
          await ReportingCache(
            boot.database,
          ).markersFor(container.read(principalProvider).userId),
          isNotEmpty,
        );
        // Deliberately no sign-out: the next launch must restore this session on its own.
      },
    );
  });

  group('slice11-restart-b', skip: _phase != 'slice11-restart-b', () {
    testWidgets(
      'the next launch restores the same session with no sign-in, reads the cached report '
      'offline, and refreshes once the connection returns',
      (tester) async {
        expect(
          s11Phone(),
          isFalse,
          reason: 'run on Windows after slice11-restart-a',
        );
        _transport.online = false;
        try {
          await launch(tester);
          await pumpUntil(
            tester,
            'the session to come back on its own, with no sign-in',
            () => visible('Overview') || visible('SIGNED IN'),
            timeout: const Duration(seconds: 60),
          );
          expect(
            find.widgetWithText(FilledButton, 'Sign in'),
            findsNothing,
            reason:
                'restarting the application must not ask the person to sign in again',
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(KrishnaMisApp)),
          );
          final session = container.read(sessionProvider);
          expect(session, isA<SessionReady>());
          expect(
            (session as SessionReady).freshness,
            AuthorityFreshness.stale,
            reason: 'offline, the restored session works from cached authority',
          );
          final principal = container.read(principalProvider);
          expect(PnlAuthority.mayReadUnit(principal, _ccr), isTrue);

          // The cached report is readable with no network at all.
          await s11OpenPnl(tester, container);
          await s11Range(tester, container, pnlFrom, pnlTo);
          final offlineView =
              container.read(pnlViewProvider).value! as PnlReportView;
          expect(offlineView.viewerUserId, principal.userId);
          expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
          expect(find.byKey(const Key('pnl-not-authorised')), findsNothing);
          final before = offlineView.envelope.freshness?.synchronisedAt;
          expect(before, isNotNull);
          final grossOffline = uiPaise(tester, 'pnl-gross');
          await s11Refresh(tester, container, expected: PnlSyncPhase.failed);
          expect(uiPaise(tester, 'pnl-gross'), grossOffline);

          // Back online: refresh, equal to the server, freshness forward.
          _transport.online = true;
          await container.read(sessionProvider.notifier).refreshAuthority();
          await tester.pump(const Duration(seconds: 2));
          await s11Refresh(tester, container);
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(Supabase.instance.client, [_ccr], pnlFrom, pnlTo),
          );
          final after =
              (container.read(pnlViewProvider).value! as PnlReportView)
                  .envelope
                  .freshness
                  ?.synchronisedAt;
          expect(after!.isAfter(before!), isTrue);
        } finally {
          _transport.online = true;
          final container = ProviderScope.containerOf(
            tester.element(find.byType(KrishnaMisApp)),
          );
          await container.read(sessionProvider.notifier).signOut();
          await tester.pump(const Duration(seconds: 2));
        }
      },
    );
  });

  group('slice11-revocation', skip: _phase != 'slice11-revocation', () {
    testWidgets(
      'a confirmed loss of each P&L capability, of unscoped authority and of '
      'owner_settlement.view closes what is open and purges what it read',
      (tester) async {
        expect(s11Phone(), isFalse, reason: 'run on Windows, with the host');
        expect(
          s11Handshake,
          isNotEmpty,
          reason: 'S11_HANDSHAKE names the file',
        );
        const marker = '$s11Marker revocation';
        await launch(tester);
        var container = await s11SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        final ownerId = container.read(principalProvider).userId;
        await sweepPnlFixtures(client, marker: marker);
        final restaurant = await s11Restaurant(client);
        final sale = await s11Sale(client, marker, pnlDate, 4200000);
        final temporaryGrants = <String>[];

        try {
          // ── A scoped manager loses each P&L capability, property access intact ──
          container = await s11SignIn(tester, 'ccr.manager@example.com');
          final managerId = container.read(principalProvider).userId;
          for (final code in const [
            'reports.view',
            'revenue.view',
            'expense.view.all',
          ]) {
            final capability = Capability.fromCode(code);
            await s11OpenPnl(tester, container);
            await s11Range(tester, container, pnlFrom, pnlTo);
            await s11Refresh(tester, container);
            await s11OpenSale(tester, restaurant, sale);
            expect(await reportingCacheRows(managerId), greaterThan(0));

            if (code == 'reports.view') {
              // A refresh that cannot reach the server is not a revocation.
              _transport.online = false;
              try {
                await container
                    .read(sessionProvider.notifier)
                    .refreshAuthority();
                await tester.pump(const Duration(seconds: 2));
              } finally {
                _transport.online = true;
              }
              // Nothing was confirmed, so nothing that is open closes and nothing is purged.
              // The detail itself is never cached (D-239): it may still show the document, or
              // say it needs a connection — never a refusal, and never nothing.
              final detailShown =
                  find
                      .byKey(const Key('pnl-document-revenue'))
                      .evaluate()
                      .isNotEmpty ||
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty;
              if (!detailShown || container.read(pnlDrillProvider) == null) {
                final keys = <String>{
                  for (final element
                      in find
                          .byWidgetPredicate(
                            (w) =>
                                w.key is ValueKey<String> &&
                                (w.key! as ValueKey<String>).value.startsWith(
                                  'pnl-',
                                ),
                          )
                          .evaluate())
                    (element.widget.key! as ValueKey<String>).value,
                }.toList()..sort();
                debugPrint('S11 offline-refresh keys on screen: $keys');
                debugPrint(
                  'S11 session: ${container.read(sessionProvider).runtimeType}',
                );
              }
              expect(
                container.read(pnlDrillProvider),
                isNotNull,
                reason: 'a refresh that proved nothing closed the drill-down',
              );
              expect(detailShown, isTrue);
              expect(find.byKey(const Key('pnl-not-authorised')), findsNothing);
              expect(await reportingCacheRows(managerId), greaterThan(0));

              // Back online, the document opens again before the capability is taken away.
              await s11BackToReport(tester);
              await s11OpenSale(tester, restaurant, sale);
            }

            await s11Signal('manager:$code', 'ready');
            await s11AwaitHost(tester, 'manager:$code', 'applied');
            await s11AuthorityUntil(
              tester,
              container,
              'manager without $code',
              (p) => !p.can(capability, businessUnitId: _ccr),
            );
            expect(
              container
                  .read(principalProvider)
                  .can(Capability.mastersView, businessUnitId: _ccr),
              isTrue,
              reason: 'property access remains',
            );
            await tester.pump(const Duration(seconds: 2));
            expect(container.read(pnlDrillProvider), isNull);
            expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
            expect(find.byKey(const Key('pnl-statement')), findsNothing);
            expect(
              await reportingCacheRows(managerId, businessUnitId: _ccr),
              0,
              reason: 'the confirmed loss of $code purged the reporting cache',
            );

            await s11Signal('manager:$code', 'verified');
            await s11AwaitHost(tester, 'manager:$code', 'restored');
            await s11AuthorityUntil(
              tester,
              container,
              'manager with $code again',
              (p) => p.can(capability, businessUnitId: _ccr),
            );
            // Regaining authority is a change of P&L read grants, so the reader starts again
            // from the default report rather than inheriting a choice made under other
            // authority (D-242, D-245). The fixture range is chosen again before comparing.
            expect(
              container.read(pnlSelectionProvider).period,
              isA<PnlPresetPeriod>(),
              reason: 'a change of P&L authority resets the chosen period',
            );
            await s11OpenPnl(tester, container);
            await s11Range(tester, container, pnlFrom, pnlTo);
            await s11Refresh(tester, container);
            expectPnlMatchesServer(
              tester,
              container,
              await serverPnl(client, [_ccr], pnlFrom, pnlTo),
            );
          }

          // ── The Owner loses owner_settlement.view ─────────────────────────────
          container = await s11SignIn(tester, 'giridhar@hki.com');
          await s11EnsureFixtureStart(client);
          await s11OpenSettlement(tester);
          await s11RefreshSettlement(tester, container);
          await s11SettlementMonth(tester, container, 2026, 6);
          expect(
            find.byKey(const Key('owner-settlement-statement')),
            findsOneWidget,
          );
          expect(await s11OwnerCacheRows(ownerId), greaterThan(0));

          await s11Signal('owner:owner_settlement.view', 'ready');
          await s11AwaitHost(tester, 'owner:owner_settlement.view', 'applied');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner without owner_settlement.view',
            (p) => !p.canAnywhere(Capability.ownerSettlementView),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(
            find.byKey(const Key('owner-settlement-statement')),
            findsNothing,
          );
          expect(s11SettlementEntryVisible(), isFalse);
          expect(await s11OwnerCacheRows(ownerId), 0);
          final refused = await container.read(
            ownerSettlementPreviewProvider.future,
          );
          expect(
            (refused as OwnerSettlementPreviewUnavailable).reason,
            OwnerSettlementUnavailableReason.notAuthorised,
          );
          await s11Signal('owner:owner_settlement.view', 'verified');
          await s11AwaitHost(tester, 'owner:owner_settlement.view', 'restored');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner with owner_settlement.view again',
            (p) => p.canAnywhere(Capability.ownerSettlementView),
          );
          expect(s11SettlementEntryVisible(), isTrue);

          // ── Unscoped authority lost while scoped authority remains ─────────────
          for (final unit in [_ccr, _hki]) {
            final granted = Map<String, dynamic>.from(
              await client.rpc<dynamic>(
                    'user_role_grant',
                    params: {
                      'p_user_id': ownerId,
                      'p_role_code': 'manager',
                      'p_business_unit_id': unit,
                      'p_mutation_id': const Uuid().v4(),
                    },
                  )
                  as Map,
            );
            temporaryGrants.add(granted['entity_id'] as String);
          }
          await s11AuthorityUntil(
            tester,
            container,
            'the temporary scoped grants',
            (p) =>
                PnlAuthority.mayReadUnit(p, _ccr) &&
                PnlAuthority.mayReadUnit(p, _hki),
          );
          await s11OpenPnl(tester, container);
          if (find
              .byKey(const Key('pnl-scope-consolidated'))
              .evaluate()
              .isNotEmpty) {
            await tapWhenHittable(
              tester,
              find.byKey(const Key('pnl-scope-consolidated')),
            );
          }
          await s11Range(tester, container, pnlFrom, pnlTo);
          await s11Refresh(tester, container);
          expect(
            (container.read(pnlViewProvider).value! as PnlReportView).scope,
            const PnlConsolidatedScope(),
          );
          await s11OpenSale(tester, restaurant, sale);

          await s11Signal('owner:reports.view', 'ready');
          await s11AwaitHost(tester, 'owner:reports.view', 'applied');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner without unscoped reports.view',
            (p) =>
                !PnlAuthority.mayReadConsolidated(p) &&
                PnlAuthority.mayReadUnit(p, _ccr),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(container.read(pnlDrillProvider), isNull);
          expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
          expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
          await tapWhenHittable(tester, find.byKey(Key('pnl-scope-$_ccr')));
          await tester.pump(const Duration(milliseconds: 400));
          await s11Range(tester, container, pnlFrom, pnlTo);
          await s11Refresh(tester, container);
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, [_ccr], pnlFrom, pnlTo),
          );
          await s11Signal('owner:reports.view', 'verified');
          await s11AwaitHost(tester, 'owner:reports.view', 'restored');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner with unscoped reports.view again',
            PnlAuthority.mayReadConsolidated,
          );
        } finally {
          _transport.online = true;
          if (container.read(principalProvider).userId != ownerId) {
            container = await s11SignIn(tester, 'giridhar@hki.com');
          }
          for (final grant in temporaryGrants) {
            await client.rpc<dynamic>(
              'user_role_revoke',
              params: {'p_grant_id': grant, 'p_mutation_id': const Uuid().v4()},
            );
          }
          await sweepPnlFixtures(client, marker: marker);
          await s11Signal('done', 'finished');
        }
      },
    );
  });

  // ── Phase 6 Slice 10: the dashboard and analytics, end to end ─────────────
  //
  // The Overview, the Analytics workspace and the Android Home in the real applications
  // against krishna-mis-dev. Every figure is compared, in paise, with `reporting_primitives`
  // over the exact range the planner resolved — the authoritative server aggregation, never
  // the production arithmetic (D-020). Fixtures go through the ordinary RPCs, carry a marker,
  // and are voided with a reason naming the run in a `finally` and again before the next run
  // (D-066, D-071, D-076). The March 2027 fixture month lies inside the retained financial
  // year, so an ordinary refresh brings it down.

  const p6Marker = '$_acceptanceMarker: phase6';
  final p6From = BusinessDate.of(2027, 3, 1);
  final p6To = BusinessDate.of(2027, 3, 31);

  bool p6Phone() => boot.shellKind.name == 'mobile';

  /// The sweep in a `finally`. A failure here — a dropped connection, say — must not
  /// replace the failure that brought the test to its `finally` (D-075). It is reported,
  /// and the next run's opening sweep reverses whatever it left (D-076).
  Future<void> p6SweepAfter(SupabaseClient client) async {
    try {
      await sweepPnlFixtures(client, marker: p6Marker);
    } on Object catch (error) {
      debugPrint('P6 SWEEP AFTER FAILED (reversed by the next run): $error');
    }
  }

  Future<String> p6Category(
    SupabaseClient client,
    String unit,
    String code,
  ) async =>
      (await client
              .from('revenue_categories')
              .select('id')
              .eq('code', code)
              .eq('business_unit_id', unit)
              .single())['id']
          as String;

  Future<String> p6Sale(
    SupabaseClient client, {
    required String unit,
    required String category,
    required String date,
    required int paise,
    required String label,
  }) async {
    final id = const Uuid().v7();
    await client.rpc<dynamic>(
      'revenue_create',
      params: {
        'p_id': id,
        'p_business_unit_id': unit,
        'p_revenue_category_id': category,
        'p_business_date': date,
        'p_notes': '$p6Marker $label',
        'p_components': [
          {'entered_amount_minor': paise},
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return id;
  }

  Future<String> p6Cost(
    SupabaseClient client, {
    required String date,
    required List<(String, String, String, String, int)> lines,
    required String label,
  }) async {
    final id = const Uuid().v7();
    await client.rpc<dynamic>(
      'expense_create',
      params: {
        'p_id': id,
        'p_business_date': date,
        'p_total_minor': lines.fold<int>(0, (s, l) => s + l.$5),
        'p_notes': '$p6Marker $label',
        'p_allocations': [
          for (final (u, d, s, c, p) in lines)
            {
              'business_unit_id': _seedId('bu:$u'),
              'department_id': _seedId('dept:$u/$d'),
              'section_id': _seedId('sec:$u/$d/$s'),
              'category_id': _seedId('cat:$u/$d/$s/$c'),
              'amount_minor': p,
            },
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return id;
  }

  /// Two properties' March 2027, a February sale for the comparator, and eight expense
  /// categories so the Top 5 genuinely has an Others remainder.
  Future<({String sale, String room, String shared, String restaurant})>
  p6Fixtures(SupabaseClient client) async {
    final restaurant = await p6Category(client, _ccr, 'RESTAURANT');
    final roomCategory = await p6Category(client, _hki, 'ROOM');
    final sale = await p6Sale(
      client,
      unit: _ccr,
      category: restaurant,
      date: '2027-03-10',
      paise: 12364200,
      label: 'sale',
    );
    final room = await p6Sale(
      client,
      unit: _hki,
      category: roomCategory,
      date: '2027-03-12',
      paise: 4200000,
      label: 'room',
    );
    await p6Sale(
      client,
      unit: _ccr,
      category: restaurant,
      date: '2027-02-15',
      paise: 5000000,
      label: 'previous',
    );
    final shared = await p6Cost(
      client,
      date: '2027-03-10',
      lines: const [
        ('CCR', 'FB', 'FOOD_PROD', 'KIRANA', 2500000),
        ('HKI', 'HKI_UTIL', 'HKI_POWER', 'ELECTRICITY', 3300000),
      ],
      label: 'shared',
    );
    final others = const [
      ('CCR', 'FB', 'FOOD_PROD', 'PANEER', 1200000),
      ('CCR', 'FB', 'KITCHEN_FUEL', 'CYL_COAL', 900000),
      ('CCR', 'CCR_UTIL', 'CCR_UTIL_SVC', 'WATER', 700000),
      ('HKI', 'HKI_UTIL', 'HKI_WATER', 'TANKER', 600000),
      ('HKI', 'HKI_MAINT', 'HKI_BUILDING', 'MAINTENANCE', 400000),
      ('CCR', 'FB', 'FOOD_PROD', 'MILK_DAHI', 200000),
    ];
    for (final (i, line) in others.indexed) {
      await p6Cost(
        client,
        date: '2027-03-${_two(11 + i)}',
        lines: [line],
        label: 'cost ${line.$4}',
      );
    }
    return (sale: sale, room: room, shared: shared, restaurant: restaurant);
  }

  Future<void> p6Settle(WidgetTester tester, ProviderContainer container) =>
      pumpUntil(tester, 'the dashboard to be read', () {
        final state = container.read(dashboardViewProvider);
        return state.hasValue &&
            !state.isLoading &&
            !container.read(dashboardSyncProvider).isRunning;
      }, timeout: const Duration(seconds: 90));

  DashboardReady p6Ready(ProviderContainer container) {
    final state = container.read(dashboardViewProvider).value;
    expect(state, isA<DashboardReady>(), reason: '$state');
    return state! as DashboardReady;
  }

  Finder p6HomeScrollable() => find
      .descendant(
        of: find.byKey(const Key('dashboard-home-page')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// The page whose list holds the dashboard controls on screen now.
  Finder p6PageFinder() {
    if (p6Phone()) return find.byKey(const Key('dashboard-home-page'));
    for (final key in const [
      Key('dashboard-drill'),
      Key('analytics-workspace'),
      Key('dashboard-page'),
    ]) {
      final page = find.byKey(key).hitTestable();
      if (page.evaluate().isNotEmpty) return find.byKey(key);
    }
    return find.byKey(const Key('dashboard-page'));
  }

  /// Brings a control on the phone Home into the middle of the screen, building it first
  /// if the lazy list has not.
  Future<void> p6Centre(WidgetTester tester, Finder finder) async {
    final page = p6PageFinder();
    final scrollable = find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first;
    for (final step in const [Offset(0, 300), Offset(0, -300)]) {
      for (
        var i = 0;
        i < 60 && finder.evaluate().isEmpty && page.evaluate().isNotEmpty;
        i++
      ) {
        // Moved, not dragged: see [p8ScrollBy].
        p8ScrollBy(tester, scrollable, step);
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    await pumpUntil(
      tester,
      'the control to exist',
      () => finder.evaluate().isNotEmpty,
    );
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.5,
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Makes [finder] visible on whichever surface holds it.
  Future<void> p6Reveal(WidgetTester tester, Finder finder) =>
      p6Centre(tester, finder);

  Future<void> p6Tap(WidgetTester tester, Finder finder) async {
    await p6Reveal(tester, finder);
    await tapWhenHittable(tester, finder);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> p6Refresh(
    WidgetTester tester,
    ProviderContainer container, {
    DashboardSyncPhase expected = DashboardSyncPhase.succeeded,
  }) async {
    await p6Settle(tester, container);
    final control = find.byKey(const Key('dashboard-refresh'));
    await p6Reveal(tester, control);
    final before = container.read(dashboardSyncProvider);
    await tapWhenHittable(tester, control);
    await pumpUntil(
      tester,
      'the dashboard synchronisation to finish',
      () {
        final now = container.read(dashboardSyncProvider);
        return !identical(now, before) && !now.isRunning;
      },
      timeout: const Duration(seconds: 90),
    );
    expect(container.read(dashboardSyncProvider).phase, expected);
    await p6Settle(tester, container);
  }

  Future<void> p6OpenOverview(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    if (p6Phone()) {
      await pumpUntil(tester, 'the Home tab', () => visible('Home'));
      await tapWhenHittable(tester, find.text('Home').last);
      await pumpUntil(
        tester,
        'the phone Home dashboard',
        () => find.byType(MobileHomePage).evaluate().isNotEmpty,
      );
    } else {
      await pumpUntil(
        tester,
        'the Overview destination',
        () => visible('Overview'),
      );
      await tester.tap(find.text('Overview').first);
      await pumpUntil(
        tester,
        'the Overview page',
        () => find.byKey(const Key('dashboard-page')).evaluate().isNotEmpty,
      );
    }
    await tester.pump(const Duration(seconds: 1));
    await p6Settle(tester, container);
  }

  Future<void> p6OpenAnalytics(
    WidgetTester tester,
    ProviderContainer container,
    AnalyticsSection section,
  ) async {
    if (find.byKey(const Key('analytics-page')).evaluate().isEmpty) {
      await pumpUntil(
        tester,
        'the Analytics destination',
        () => visible('Analytics'),
      );
      await tester.tap(find.text('Analytics').first);
      await pumpUntil(
        tester,
        'the Analytics page',
        () => find.byKey(const Key('analytics-page')).evaluate().isNotEmpty,
      );
    }
    await tapWhenHittable(
      tester,
      find.byKey(Key('analytics-section-${section.name}')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    if (section == AnalyticsSection.profitAndLoss) {
      await settlePnl(tester, container);
    } else {
      await p6Settle(tester, container);
    }
  }

  Future<void> p6Period(
    WidgetTester tester,
    ProviderContainer container,
    DashboardPeriodKind kind,
  ) async {
    await p6Tap(tester, find.byKey(Key('dashboard-period-${kind.name}')));
    expect(
      container.read(dashboardSelectionProvider).period,
      DashboardRelativePeriod(kind),
    );
    await p6Settle(tester, container);
  }

  /// A custom range: typed on Windows, tapped on the Material calendar on the phone
  /// (D-229, D-250).
  Future<void> p6Custom(
    WidgetTester tester,
    ProviderContainer container,
    BusinessDate from,
    BusinessDate to,
  ) async {
    await p6Settle(tester, container);
    if (!p6Phone()) {
      await p6Tap(tester, find.byKey(const Key('dashboard-period-custom')));
      await tester.enterText(
        find.byKey(const Key('dashboard-custom-from')).hitTestable(),
        from.iso,
      );
      await tester.enterText(
        find.byKey(const Key('dashboard-custom-to')).hitTestable(),
        to.iso,
      );
      await tapWhenHittable(
        tester,
        find.byKey(const Key('dashboard-custom-apply')),
      );
    } else {
      final opensOn = switch ((
        container.read(dashboardSelectionProvider).period,
        container.read(dashboardViewProvider).value,
      )) {
        (DashboardCustomPeriod(:final from), _) => from,
        (_, DashboardReady(:final pair)) => pair.current.from,
        _ => fail('the picker has no period to open on'),
      };
      final semantics = tester.ensureSemantics();
      try {
        await p6Tap(tester, find.byKey(const Key('dashboard-period-custom')));
        await pumpUntil(
          tester,
          'the date-range picker',
          () => visible('Dashboard period'),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.byType(TextField),
          findsNothing,
          reason: 'calendar only: Android takes no typed dates',
        );
        final monthsElement = tester.element(
          find
              .ancestor(
                of: find.bySemanticsLabel(
                  RegExp(
                    RegExp.escape(
                      '${monthNames[opensOn.month - 1]} ${opensOn.day}, ${opensOn.year}',
                    ),
                  ),
                ),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Scrollable &&
                      w.physics is! NeverScrollableScrollPhysics,
                ),
              )
              .first,
        );
        final months = find.byElementPredicate((e) => e == monthsElement);
        for (final day in [from, to]) {
          final cell = find.bySemanticsLabel(
            RegExp(
              RegExp.escape(
                '${monthNames[day.month - 1]} ${day.day}, ${day.year}',
              ),
            ),
          );
          await tester.scrollUntilVisible(
            cell,
            day >= opensOn ? 250 : -250,
            scrollable: months,
            maxScrolls: 400,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tapWhenHittable(tester, cell);
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tapWhenHittable(tester, find.text('Apply'));
        await pumpUntil(
          tester,
          'the picker to close',
          () => !visible('Dashboard period'),
        );
      } finally {
        semantics.dispose();
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(dashboardSelectionProvider).period,
      DashboardCustomPeriod(from, to),
      reason: 'the chosen days are the P&L dates, unconverted',
    );
    await p6Settle(tester, container);
  }

  Future<void> p6Scope(
    WidgetTester tester,
    ProviderContainer container,
    Key choice,
  ) async {
    if (p6Phone()) {
      await p6Tap(tester, find.byKey(const Key('dashboard-scope-selector')));
      await pumpUntil(
        tester,
        'the scope sheet',
        () => find
            .byKey(const Key('dashboard-scope-sheet'))
            .evaluate()
            .isNotEmpty,
      );
      await tapWhenHittable(tester, find.byKey(choice));
      await pumpUntil(
        tester,
        'the scope sheet to close',
        () => find.byKey(const Key('dashboard-scope-sheet')).evaluate().isEmpty,
      );
    } else {
      await p6Tap(tester, find.byKey(choice));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await p6Settle(tester, container);
  }

  /// The exact margin, worked out here from the server's two integers: hundredths of a
  /// percent, half away from zero — never through the production calculator.
  String p6Margin(int profit, int net) {
    if (net == 0) return 'N/A';
    final scaled = profit * 10000;
    var q = scaled ~/ net;
    final r = scaled.remainder(net).abs() * 2;
    if (r >= net.abs()) q += (scaled < 0) != (net < 0) ? -1 : 1;
    final sign = q < 0 ? '-' : '';
    final a = q.abs();
    return '$sign${a ~/ 100}.${_two(a % 100)}%';
  }

  /// Money is never ellipsised, wrapped or clipped: every amount on screen is laid out at
  /// least as wide as its own text.
  /// Every amount on screen is whole and at the reader's own text size: never shrunk,
  /// clipped or ellipsised, and broken only between digit groups when wider than a
  /// line of its own (D-286). The same check the host layout suites run.
  void p6ExpectMoneyWhole(WidgetTester tester, String where) =>
      expectMoneyWholeAndUnshrunk(tester, where);

  /// Before a refresh, a comparator the device has not downloaded is withheld — never a
  /// zero movement (D-253). Records which periods were withheld, for the report.
  final p6Withheld = <String>[];
  Future<void> p6ExpectComparedOrWithheld(
    WidgetTester tester,
    ProviderContainer container,
    DashboardPeriodKind kind,
  ) async {
    final comparison = p6Ready(container).view.comparison.netSales;
    if (comparison is MoneyComparisonUnavailable) {
      p6Withheld.add(
        '${kind.name}: ${comparison.side} ${comparison.previousRefusal}',
      );
      debugPrint('P6 comparator withheld before refresh: ${p6Withheld.last}');
      await p6Reveal(
        tester,
        find.byKey(const Key('dashboard-net-sales-movement')),
      );
      final text =
          tester
              .widget<Text>(
                find.byKey(const Key('dashboard-net-sales-movement')),
              )
              .data ??
          '';
      expect(text, isNot(contains('₹0.00')), reason: 'withheld is not zero');
    }
  }

  /// The dashboard's headline against the server, to the paisa, on screen and behind it,
  /// and the comparison against the server's own previous stretch.
  Future<void> p6ExpectHeadline(
    WidgetTester tester,
    ProviderContainer container,
    SupabaseClient client, {
    bool onScreen = true,
  }) async {
    final ready = p6Ready(container);
    final units = ready.view.scope.ordered;
    final current = await serverPnl(
      client,
      units,
      ready.pair.current.from.iso,
      ready.pair.current.to.iso,
    );
    final previous = await serverPnl(
      client,
      units,
      ready.pair.comparison.from.iso,
      ready.pair.comparison.to.iso,
    );
    final result = ready.view.resultOrNull!;
    expect(result.grossSales.paise, current.gross);
    expect(result.gst.paise, current.tax);
    expect(result.netSales.paise, current.net);
    expect(result.expenses.paise, current.expenses);
    expect(result.revenueContributions, current.revenueRows);
    expect(result.expenseContributions, current.expenseRows);
    expect(
      current.gross,
      current.tax + current.net,
      reason: 'Gross = GST + Net',
    );

    final comparison = ready.view.comparison;
    for (final (name, got, now, before) in [
      ('gross', comparison.grossSales, current.gross, previous.gross),
      ('gst', comparison.gst, current.tax, previous.tax),
      ('net', comparison.netSales, current.net, previous.net),
      ('expenses', comparison.expenses, current.expenses, previous.expenses),
      (
        'operating',
        comparison.operatingProfit,
        current.net - current.expenses,
        previous.net - previous.expenses,
      ),
    ]) {
      expect(got, isA<MoneyComparisonAvailable>(), reason: name);
      final available = got as MoneyComparisonAvailable;
      expect(available.current.paise, now, reason: '$name current');
      expect(available.previous.paise, before, reason: '$name previous');
    }

    if (!onScreen) return;
    await p6Reveal(tester, find.byKey(const Key('dashboard-net-sales-value')));
    expect(uiPaise(tester, 'dashboard-net-sales-value'), current.net);
    expect(uiPaise(tester, 'dashboard-expenses-value'), current.expenses);
    expect(
      uiPaise(tester, 'dashboard-operating-value'),
      current.net - current.expenses,
    );
    expect(uiPaise(tester, 'dashboard-gross-sales'), current.gross);
    expect(uiPaise(tester, 'dashboard-gst'), current.tax);
    expect(
      tester.widget<Text>(find.byKey(const Key('dashboard-margin-value'))).data,
      p6Margin(current.net - current.expenses, current.net),
    );
    final movement = find.byKey(const Key('dashboard-net-sales-movement'));
    expect(movement, findsOneWidget);
    final movementText = tester.widget<Text>(movement).data ?? '';
    expect(
      movementText,
      contains(
        MoneyFormatter.movement.format(
          Money.fromPaise(current.net - previous.net),
        ),
      ),
    );
  }

  /// Every word a dashboard or analytics surface may not use about two properties.
  void p6ExpectNoRanking() {
    for (final word in const [
      'winner',
      'Winner',
      'better',
      'Better',
      'best',
      'Best',
      'wins',
      'outperform',
    ]) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  }

  Future<String> p6Readout(WidgetTester tester, Finder panel) async {
    final readout = find.descendant(
      of: panel,
      matching: find.byKey(const Key('chart-readout')),
    );
    expect(readout, findsOneWidget);
    return tester
        .widgetList<Text>(
          find.descendant(of: readout, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .join('|');
  }

  /// Opens position [index] of the chart inside [panel] from the keyboard — the path a
  /// reader without a mouse takes, and the same selection a tap or hover moves.
  Future<void> p6OpenChartPoint(
    WidgetTester tester,
    Finder panel,
    int index,
  ) async {
    await p6Reveal(tester, panel);
    final node = tester
        .widgetList<Focus>(
          find.descendant(of: panel, matching: find.byType(Focus)),
        )
        .map((f) => f.focusNode)
        .firstWhere((n) => n?.debugLabel == 'chart')!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    for (var i = 0; i < index; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
  }

  TrendSeries p6Series(DashboardReady ready, TrendMeasure measure) =>
      ready.view.trends.firstWhere((s) => s.measure == measure);

  int p6RankedIndex<L>(TopNOutcome<L> outcome, bool Function(L line) match) {
    final grouped = outcome as TopNGrouped<L>;
    final index = grouped.top.indexWhere((r) => match(r.line));
    expect(index, isNonNegative, reason: 'the line is among the top rows');
    return index;
  }

  Finder p6Row(Key panel, int index) => find.descendant(
    of: find.byKey(panel),
    matching: find.byKey(Key('chart-ranked-row-$index')),
  );

  PnlDrillLocation p6OpenLocation(ProviderContainer container) =>
      container.read(dashboardDrillProvider)!.location;

  Future<void> p6AwaitDrillLevel(WidgetTester tester, Key key) => pumpUntil(
    tester,
    '$key in the drill-down',
    () => find.byKey(key).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 60),
  );

  /// Back from a Windows drill-down pane, or up one pushed page on the phone.
  Future<void> p6Back(WidgetTester tester) async {
    if (p6Phone()) {
      await tester.binding.handlePopRoute();
    } else {
      await tapWhenHittable(
        tester,
        find.byKey(const Key('dashboard-drill-back')),
      );
    }
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> p6BackToHome(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      if (find.byType(MobilePnlDrillPage).evaluate().isEmpty &&
          find.byType(MobilePnlDocumentPage).evaluate().isEmpty) {
        break;
      }
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<ProviderContainer> p6SignIn(WidgetTester tester, String email) async {
    await signIn(tester, email);
    await expectSignedIn(tester, email);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    await container.read(sessionProvider.notifier).refreshAuthority();
    await tester.pump(const Duration(seconds: 2));
    return container;
  }

  /// The approved neutral surface: the sentence, no property, no figure, no chart.
  void p6ExpectNeutral(WidgetTester tester) {
    expect(visible(dashboardNotAuthorisedMessage.title), isTrue);
    expect(find.byKey(const Key('dashboard-body')), findsNothing);
    expect(find.byKey(const Key('dashboard-scope-bar')), findsNothing);
    expect(find.byKey(const Key('dashboard-scope-selector')), findsNothing);
    expect(find.byKey(const Key('dashboard-scope-consolidated')), findsNothing);
    expect(find.byKey(const Key('dashboard-period-bar')), findsNothing);
    expect(find.byType(MoneyText), findsNothing);
    expect(find.byKey(const Key('chart-semantics')), findsNothing);
    for (final name in const ['Crystal Canopy', 'Hotel Krishna']) {
      final page = p6Phone()
          ? find.byKey(const Key('dashboard-home-page'))
          : find.byKey(const Key('dashboard-page'));
      expect(
        find.descendant(of: page, matching: find.textContaining(name)),
        findsNothing,
        reason: 'no property name for a reader without authority',
      );
    }
  }

  group('p6-windows-dashboard', skip: _phase != 'p6-windows-dashboard', () {
    testWidgets('the Overview and the Analytics workspace equal the server to the paisa, share one '
        'period, drill down read-only, hand off to the P&L, survive offline and fit every '
        'Windows size', (tester) async {
      expect(p6Phone(), isFalse, reason: 'run with -d windows');
      await launch(tester);
      final container = await p6SignIn(tester, 'giridhar@hki.com');
      final client = Supabase.instance.client;
      await sweepPnlFixtures(client, marker: p6Marker);
      try {
        final ids = await p6Fixtures(client);

        // ── 1 · the Overview opens on the authorised scope ─────────────────────
        await p6OpenOverview(tester, container);
        await p6Refresh(tester, container);
        expect(
          find.byKey(const Key('dashboard-scope-consolidated')),
          findsOneWidget,
        );
        expect(p6Ready(container).scope, const PnlConsolidatedScope());
        expect(p6Ready(container).view.scope.ordered.toSet(), {_ccr, _hki});

        // ── 2 · each relative period, against the server over what it resolved ─
        for (final kind in const [
          DashboardPeriodKind.today,
          DashboardPeriodKind.weekToDate,
          DashboardPeriodKind.monthToDate,
          DashboardPeriodKind.financialYearToDate,
        ]) {
          await p6Period(tester, container, kind);
          await p6ExpectComparedOrWithheld(tester, container, kind);
          await p6Refresh(tester, container);
          await p6ExpectHeadline(tester, container, client);
        }
        // ── 9 · Financial year to date trends profit monthly ───────────────────
        final fytd = p6Ready(container);
        final fytdProfit = p6Series(fytd, TrendMeasure.operatingProfit);
        expect(fytdProfit.grain, TrendGrain.monthly);
        expect(
          find.byKey(const Key('dashboard-trend-operating-profit')),
          findsOneWidget,
        );

        // ── Custom: March 2027, the fixture month ──────────────────────────────
        await p6Custom(tester, container, p6From, p6To);
        await p6ExpectHeadline(tester, container, client);
        final march = p6Ready(container);
        expect(march.pair.current.from, p6From);
        expect(march.pair.current.to, p6To);

        // ── 8 · the Net Sales trend is daily, each day the server's own figure ──
        final netTrend = p6Series(march, TrendMeasure.netSales);
        expect(netTrend.grain, TrendGrain.daily);
        expect(netTrend.points, hasLength(31));
        expect(netTrend.hasGap, isFalse, reason: 'March is downloaded');
        for (final day in const [9, 11]) {
          final point = netTrend.points[day] as TrendValue;
          final server = await serverPnl(
            client,
            [_ccr, _hki],
            point.bucket.range.from.iso,
            point.bucket.range.to.iso,
          );
          expect(point.amount.paise, server.net, reason: 'day ${day + 1}');
        }
        // ── 9 · a one-month custom range has no monthly profit trend ───────────
        expect(
          march.view.trends.where(
            (s) => s.measure == TrendMeasure.operatingProfit,
          ),
          isEmpty,
        );
        expect(
          find.byKey(const Key('dashboard-trend-operating-profit')),
          findsNothing,
        );

        // ── 18 · the readout states the exact prepared figure ──────────────────
        final trendPanel = find.byKey(const Key('dashboard-trend-net-sales'));
        await p6Reveal(tester, trendPanel);
        final plot = find.descendant(
          of: trendPanel,
          matching: find.byKey(const Key('chart-semantics')),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(plot));
        await mouse.moveTo(tester.getCenter(plot) + const Offset(1, 0));
        await tester.pump(const Duration(milliseconds: 400));
        final readout = (await p6Readout(tester, trendPanel)).split('|');
        await mouse.removePointer();
        final hovered = netTrend.points.indexWhere(
          (p) => dashboardBucketLabel(p.bucket, netTrend.grain) == readout[0],
        );
        expect(hovered, isNonNegative, reason: 'readout names a day: $readout');
        final hoveredServer = await serverPnl(
          client,
          [_ccr, _hki],
          netTrend.points[hovered].bucket.range.from.iso,
          netTrend.points[hovered].bucket.range.to.iso,
        );
        expect(
          readout[1],
          MoneyFormatter.standard.format(Money.fromPaise(hoveredServer.net)),
        );

        // ── 10 · 11 · 12 · ranked rows are the prepared ones, exactly ──────────
        final server = await serverPnl(
          client,
          [_ccr, _hki],
          p6From.iso,
          p6To.iso,
        );
        final mix =
            march.view.topRevenueCategories!
                as TopNGrouped<RevenueCategoryLine>;
        for (final (i, row) in mix.top.indexed) {
          expect(
            row.amount.paise,
            server
                .revenueLines['${row.line.businessUnitId}-${row.line.revenueCategoryId}']![2],
          );
          await p6Reveal(tester, p6Row(const Key('dashboard-revenue-mix'), i));
          expect(
            tester
                .widget<Text>(
                  find.descendant(
                    of: find.byKey(const Key('dashboard-revenue-mix')),
                    matching: find.byKey(Key('chart-ranked-value-$i')),
                  ),
                )
                .data,
            MoneyFormatter.standard.format(row.amount),
          );
        }
        final top =
            march.view.topExpenseCategories!
                as TopNGrouped<ExpenseHierarchyLine>;
        expect(top.top, hasLength(5));
        expect(top.others, isNotNull, reason: 'eight categories, five shown');
        expect(
          top.top.fold<int>(0, (s, r) => s + r.amount.paise) +
              top.others!.paise,
          server.expenses,
          reason: 'Top 5 + Others is the whole of Expenses, exactly',
        );
        for (final row in top.top) {
          expect(
            row.amount.paise,
            server
                .expenseLines['${row.line.businessUnitId}-${row.line.categoryId}'],
          );
        }
        final departments =
            march.view.departmentSpending! as TopNGrouped<ExpenseHierarchyLine>;
        expect(
          departments.top.fold<int>(0, (s, r) => s + r.amount.paise) +
              (departments.others?.paise ?? 0),
          server.expenses,
        );
        await p6Reveal(tester, find.byKey(const Key('dashboard-departments')));
        expect(find.byKey(const Key('dashboard-departments')), findsOneWidget);

        // ── 3 · 4 · one period across the Overview and the three sections ──────
        final pnlPeriodBefore = container.read(pnlSelectionProvider).period;
        await p6OpenAnalytics(tester, container, AnalyticsSection.revenue);
        expect(
          container.read(dashboardSelectionProvider).period,
          DashboardCustomPeriod(p6From, p6To),
        );
        expect(
          uiPaise(tester, 'analytics-revenue-net-sales-value'),
          server.net,
        );
        await p6OpenAnalytics(tester, container, AnalyticsSection.expenses);
        expect(
          uiPaise(tester, 'analytics-expense-total-value'),
          server.expenses,
        );
        expect(
          find.byKey(const Key('analytics-expense-no-trend')),
          findsOneWidget,
        );
        // A period chosen here is the Overview's too.
        await p6Period(tester, container, DashboardPeriodKind.monthToDate);
        await p6OpenOverview(tester, container);
        expect(
          find
              .byKey(const Key('dashboard-period-monthToDate'))
              .evaluate()
              .map((e) => (e.widget as ChoiceChip).selected),
          everyElement(isTrue),
        );
        await p6Custom(tester, container, p6From, p6To);
        // The P&L keeps its own Phase 5 period, untouched by the dashboard's.
        expect(container.read(pnlSelectionProvider).period, pnlPeriodBefore);

        // ── 13 · 14 · 15 · Business Comparison, consolidated only ──────────────
        await p6OpenAnalytics(
          tester,
          container,
          AnalyticsSection.businessComparison,
        );
        expect(
          find.byKey(const Key('analytics-comparison-table')),
          findsOneWidget,
        );
        for (final unit in [_ccr, _hki]) {
          final one = await serverPnl(client, [unit], p6From.iso, p6To.iso);
          expect(
            uiPaise(tester, 'analytics-comparison-$unit-net-sales'),
            one.net,
          );
          expect(
            uiPaise(tester, 'analytics-comparison-$unit-expenses'),
            one.expenses,
          );
          expect(
            uiPaise(tester, 'analytics-comparison-$unit-operating'),
            one.net - one.expenses,
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(Key('analytics-comparison-$unit-margin')),
                )
                .data,
            p6Margin(one.net - one.expenses, one.net),
          );
        }
        expect(
          uiPaise(tester, 'analytics-comparison-total-net-sales'),
          server.net,
        );
        expect(
          uiPaise(tester, 'analytics-comparison-total-expenses'),
          server.expenses,
        );
        p6ExpectNoRanking();
        await p6OpenOverview(tester, container);
        p6ExpectNoRanking();
        await p6Scope(tester, container, Key('dashboard-scope-$_ccr'));
        await p6OpenAnalytics(
          tester,
          container,
          AnalyticsSection.businessComparison,
        );
        expect(
          find.byKey(const Key('analytics-comparison-table')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('analytics-comparison-needs-both')),
          findsOneWidget,
        );
        await p6OpenOverview(tester, container);
        await p6Scope(
          tester,
          container,
          const Key('dashboard-scope-consolidated'),
        );
        await p6ExpectHeadline(tester, container, client);

        // ── 21 · 23 · Net Sales → a category → its documents → read-only ───────
        final before = await ordinaryAndCacheCounts();
        await p6Tap(tester, find.byKey(const Key('dashboard-net-sales-open')));
        await p6AwaitDrillLevel(
          tester,
          Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
        );
        expect(find.byKey(const Key('dashboard-drill')), findsOneWidget);
        expect(p6OpenLocation(container).anchor.range.from, p6From);
        expect(p6OpenLocation(container).anchor.range.to, p6To);
        await p6Tap(
          tester,
          find.byKey(Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}')),
        );
        await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
        expect(uiPaise(tester, 'pnl-drill-doc-${ids.sale}-gross'), 12364200);
        await p6Tap(tester, find.byKey(Key('pnl-drill-doc-${ids.sale}')));
        await p6AwaitDrillLevel(tester, const Key('pnl-document-revenue'));
        expect(find.textContaining('KI-REV-'), findsWidgets);
        // ── 28 · no mutation action on report detail ───────────────────────────
        expectReportDetailReadOnly();
        expect(await ordinaryAndCacheCounts(), before);
        // ── 27 · Back returns to the Overview, exactly as it was ───────────────
        await p6Back(tester);
        expect(find.byKey(const Key('dashboard-drill')), findsNothing);
        expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
        expect(
          container.read(dashboardSelectionProvider).period,
          DashboardCustomPeriod(p6From, p6To),
        );

        // ── 22 · 24 · Expenses → department → section → category → documents ───
        await p6Tap(tester, find.byKey(const Key('dashboard-expenses-open')));
        for (final key in [
          'pnl-drill-dept-$_ccr-${_seedId('dept:CCR/FB')}',
          'pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}',
          'pnl-drill-category-$_ccr-$_kirana',
        ]) {
          await p6AwaitDrillLevel(tester, Key(key));
          await p6Tap(tester, find.byKey(Key(key)));
        }
        await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.shared}'));
        expect(uiPaise(tester, 'pnl-drill-doc-${ids.shared}-amount'), 2500000);
        await p6Back(tester);

        // ── 25 · a trend point opens exactly its own day ───────────────────────
        await p6OpenChartPoint(tester, trendPanel, 9);
        await p6AwaitDrillLevel(
          tester,
          Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
        );
        expect(
          p6OpenLocation(container).anchor.range.from,
          BusinessDate.of(2027, 3, 10),
        );
        expect(
          p6OpenLocation(container).anchor.range.to,
          BusinessDate.of(2027, 3, 10),
        );
        expect(
          uiPaise(tester, 'pnl-drill-total-net'),
          (await serverPnl(
            client,
            [_ccr, _hki],
            '2027-03-10',
            '2027-03-10',
          )).net,
        );
        await p6Back(tester);

        // ── 11 · a top expense category opens its own bucket ───────────────────
        final kiranaRow = p6RankedIndex<ExpenseHierarchyLine>(
          top,
          (l) => l.businessUnitId == _ccr && l.categoryId == _kirana,
        );
        await p6Tap(
          tester,
          p6Row(const Key('dashboard-top-expenses'), kiranaRow),
        );
        await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.shared}'));
        expect(p6OpenLocation(container), isA<PnlExpenseDocumentsAt>());
        await p6Back(tester);

        // ── 12 · a department opens its sections ───────────────────────────────
        final fbRow = p6RankedIndex<ExpenseHierarchyLine>(
          departments,
          (l) =>
              l.businessUnitId == _ccr &&
              l.departmentId == _seedId('dept:CCR/FB'),
        );
        await p6Tap(tester, p6Row(const Key('dashboard-departments'), fbRow));
        await p6AwaitDrillLevel(
          tester,
          Key('pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}'),
        );
        await p6Back(tester);

        // ── 10 · a revenue mix row opens that category's documents ─────────────
        final restaurantRow = p6RankedIndex<RevenueCategoryLine>(
          mix,
          (l) => l.revenueCategoryId == ids.restaurant,
        );
        await p6Tap(
          tester,
          p6Row(const Key('dashboard-revenue-mix'), restaurantRow),
        );
        await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
        await p6Back(tester);

        // ── 30 · a document changed on the server since this device synchronised ─
        await _admin.correctRevenue(ids.sale, 12464200);
        await p6Tap(tester, find.byKey(const Key('dashboard-net-sales-open')));
        await p6Tap(
          tester,
          find.byKey(Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}')),
        );
        await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
        await p6Tap(tester, find.byKey(Key('pnl-drill-doc-${ids.sale}')));
        await pumpUntil(
          tester,
          'the changed-since-synchronised refusal',
          () => find.text(pnlDocumentChangedText).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
        await p6Back(tester);
        await p6Refresh(tester, container);
        await p6ExpectHeadline(tester, container, client);

        // ── 26 · 27 · Operating Profit → the existing P&L, as a Custom period ──
        await p6Tap(tester, find.byKey(const Key('dashboard-operating-open')));
        await pumpUntil(
          tester,
          'the P&L, handed the dashboard period',
          () => find.byKey(const Key('pnl-page')).evaluate().isNotEmpty,
        );
        expect(
          container.read(pnlSelectionProvider).period,
          PnlCustomPeriod(p6From, p6To),
        );
        expect(
          container.read(pnlSelectionProvider).scope,
          const PnlConsolidatedScope(),
        );
        await settlePnl(tester, container);
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(client, [_ccr, _hki], p6From.iso, p6To.iso),
        );
        // Back is the Overview destination, where the dashboard is as it was.
        await p6OpenOverview(tester, container);
        expect(
          container.read(dashboardSelectionProvider).period,
          DashboardCustomPeriod(p6From, p6To),
        );
        expect(container.read(dashboardDrillProvider), isNull);
        // From a section, back is that section.
        await p6OpenAnalytics(tester, container, AnalyticsSection.revenue);
        await p6Tap(
          tester,
          find.byKey(const Key('analytics-revenue-gross-sales-open')),
        );
        await settlePnl(tester, container);
        expect(
          container.read(analyticsSectionProvider),
          AnalyticsSection.profitAndLoss,
        );
        await p6OpenAnalytics(tester, container, AnalyticsSection.revenue);
        expect(
          find.byKey(const Key('analytics-revenue-summary')),
          findsOneWidget,
        );
        await p6OpenOverview(tester, container);

        // ── 16 · 17 · every Windows size, no overflow, no amount cut short ─────
        for (final size in const [
          Size(1366, 768),
          Size(1024, 700),
          Size(1920, 1080),
        ]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pump(const Duration(milliseconds: 600));
          for (final section in [null, ...AnalyticsSection.values]) {
            if (section == null) {
              await p6OpenOverview(tester, container);
            } else {
              await p6OpenAnalytics(tester, container, section);
            }
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull, reason: '$size $section');
            p6ExpectMoneyWhole(tester, '$size ${section ?? 'overview'}');
          }
        }
        await tester.binding.setSurfaceSize(null);
        await p6OpenOverview(tester, container);

        // ── 19 · 20 · 29 · offline: kept, reported, detail refused ─────────────
        final freshBefore = p6Ready(container).view.freshness!.synchronisedAt;
        await p6Reveal(
          tester,
          find.byKey(const Key('dashboard-net-sales-value')),
        );
        final netBefore = uiPaise(tester, 'dashboard-net-sales-value');
        final expensesBefore = uiPaise(tester, 'dashboard-expenses-value');
        _transport.online = false;
        try {
          await p6Refresh(
            tester,
            container,
            expected: DashboardSyncPhase.failed,
          );
          expect(find.byKey(const Key('dashboard-offline')), findsOneWidget);
          expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
          expect(uiPaise(tester, 'dashboard-net-sales-value'), netBefore);
          expect(uiPaise(tester, 'dashboard-expenses-value'), expensesBefore);
          expect(
            find.byKey(const Key('dashboard-freshness-synchronised')),
            findsOneWidget,
          );
          await p6Tap(
            tester,
            find.byKey(const Key('dashboard-net-sales-open')),
          );
          await p6Tap(
            tester,
            find.byKey(
              Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
            ),
          );
          await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
          await p6Tap(tester, find.byKey(Key('pnl-drill-doc-${ids.sale}')));
          await pumpUntil(
            tester,
            'detail not downloaded while offline',
            () => find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 60),
          );
          await p6Back(tester);
        } finally {
          _transport.online = true;
        }
        await p6Refresh(tester, container);
        expect(
          p6Ready(
            container,
          ).view.freshness!.synchronisedAt.isAfter(freshBefore),
          isTrue,
          reason: 'a successful refresh advances the freshness claim',
        );
        await p6ExpectHeadline(tester, container, client);
      } finally {
        _transport.online = true;
        await tester.binding.setSurfaceSize(null);
        await p6SweepAfter(client);
      }
    });
  });

  /// Pumps [frames] frames and fails the moment anything the next person may not see is on
  /// screen — the check that a previous person's dashboard never flashes (D-231, D-267).
  Future<void> p6WatchNoLeak(
    WidgetTester tester,
    ProviderContainer container, {
    required Set<String> forbiddenUnits,
    bool consolidatedForbidden = true,
    int frames = 40,
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (consolidatedForbidden) {
        expect(
          find.byKey(const Key('dashboard-scope-consolidated')),
          findsNothing,
          reason: 'frame $i: a consolidated choice was offered',
        );
        expect(
          find.byKey(const Key('dashboard-property-comparison')),
          findsNothing,
          reason: 'frame $i: a property comparison was shown',
        );
      }
      for (final unit in forbiddenUnits) {
        expect(
          find.byKey(Key('dashboard-scope-$unit')),
          findsNothing,
          reason: 'frame $i: a withdrawn property was offered',
        );
      }
      final shown = dashboardShownTo(
        container.read(dashboardViewProvider),
        container.read(principalProvider),
      );
      if (shown is DashboardReady) {
        expect(
          shown.view.scope.ordered.toSet().intersection(forbiddenUnits),
          isEmpty,
          reason: 'frame $i: a dashboard over a withdrawn property is shown',
        );
      }
    }
  }

  /// The dashboard, the analytics sections and the drill-down after a confirmed loss.
  Future<void> p6ExpectClosedAfterLoss(
    WidgetTester tester,
    ProviderContainer container,
    Set<String> lostUnits,
  ) async {
    expect(container.read(dashboardDrillProvider), isNull);
    expect(find.byKey(const Key('dashboard-drill')), findsNothing);
    expect(find.byType(MobilePnlDrillPage), findsNothing);
    expect(find.byType(MobilePnlDocumentPage), findsNothing);
    await p6WatchNoLeak(
      tester,
      container,
      forbiddenUnits: lostUnits,
      frames: 20,
    );
  }

  Future<void> p6OpenNetSalesDrill(
    WidgetTester tester,
    String restaurant,
  ) async {
    await p6Tap(tester, find.byKey(const Key('dashboard-net-sales-open')));
    await p6AwaitDrillLevel(
      tester,
      Key('pnl-drill-revenue-category-$_ccr-$restaurant'),
    );
  }

  group('p6-windows-authority', skip: _phase != 'p6-windows-authority', () {
    testWidgets(
      'a user switch, a withdrawn property, a withdrawn capability and a withdrawn '
      'consolidated authority each close the dashboard, the sections and the drill-down',
      (tester) async {
        expect(p6Phone(), isFalse, reason: 'run on Windows, with the host');
        expect(
          s11Handshake,
          isNotEmpty,
          reason: 'S11_HANDSHAKE names the file',
        );
        await launch(tester);
        var container = await p6SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        final ownerId = container.read(principalProvider).userId;
        await sweepPnlFixtures(client, marker: p6Marker);
        final temporaryGrants = <String>[];
        try {
          final ids = await p6Fixtures(client);

          // ── The Owner's consolidated dashboard, a drill-down open ─────────────
          await p6OpenOverview(tester, container);
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          await p6ExpectHeadline(tester, container, client);
          await p6OpenNetSalesDrill(tester, ids.restaurant);
          expect(await reportingCacheRows(ownerId), greaterThan(0));

          // ── A → B, with a synchronisation still in flight ──────────────────────
          // The run started for the Owner must not publish for whoever comes next.
          unawaited(container.read(dashboardSyncProvider.notifier).refresh());
          await tester.pump(const Duration(milliseconds: 50));
          await signOutThroughTheUi(tester);
          expect(
            await reportingCacheRows(ownerId),
            0,
            reason: 'sign-out takes the Owner\'s reporting cache with it',
          );
          container = await p6SignIn(tester, 'ccr.manager@example.com');
          final managerId = container.read(principalProvider).userId;
          await p6OpenOverview(tester, container);
          await p6WatchNoLeak(tester, container, forbiddenUnits: {_hki});
          expect(container.read(dashboardDrillProvider), isNull);
          expect(
            container.read(dashboardSelectionProvider).period,
            const DashboardRelativePeriod(DashboardPeriodKind.monthToDate),
            reason: 'nothing the Owner chose is inherited',
          );
          expect(await reportingCacheRows(ownerId), 0);
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_ccr]);
          expect(
            p6Ready(container).authorityKey,
            PnlAuthority.readKey(container.read(principalProvider)),
          );
          await p6ExpectHeadline(tester, container, client);
          await p6OpenAnalytics(
            tester,
            container,
            AnalyticsSection.businessComparison,
          );
          expect(
            find.byKey(const Key('analytics-comparison-table')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('analytics-comparison-not-authorised')),
            findsOneWidget,
          );
          await p6OpenOverview(tester, container);

          // ── Property-scope loss, the same person ───────────────────────────────
          await _admin.grantScope('ccr.manager@example.com', 'manager', 'HKI');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager with Hotel Krishna',
            (p) => PnlAuthority.mayReadUnit(p, _hki),
          );
          expect(
            find.byKey(const Key('dashboard-scope-consolidated')),
            findsNothing,
            reason: 'two scoped grants are not consolidated authority (D-164)',
          );
          await p6Scope(tester, container, Key('dashboard-scope-$_hki'));
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_hki]);
          await p6ExpectHeadline(tester, container, client);
          await p6Tap(tester, find.byKey(const Key('dashboard-expenses-open')));
          await p6AwaitDrillLevel(
            tester,
            Key('pnl-drill-dept-$_hki-${_seedId('dept:HKI/HKI_UTIL')}'),
          );
          expect(
            await reportingCacheRows(managerId, businessUnitId: _hki),
            greaterThan(0),
          );
          await _admin.revokeScope('ccr.manager@example.com', 'HKI');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager without Hotel Krishna',
            (p) =>
                !PnlAuthority.mayReadUnit(p, _hki) &&
                PnlAuthority.mayReadUnit(p, _ccr),
          );
          await p6ExpectClosedAfterLoss(tester, container, {_hki});
          await p6Settle(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_ccr]);
          expect(
            await reportingCacheRows(managerId, businessUnitId: _hki),
            0,
            reason: 'the confirmed loss purged that property\'s figures',
          );

          // ── A capability withdrawn from the same person, property kept (host) ──
          await p6Custom(tester, container, p6From, p6To);
          await p6OpenNetSalesDrill(tester, ids.restaurant);
          await s11Signal('manager:reports.view', 'ready');
          await s11AwaitHost(tester, 'manager:reports.view', 'applied');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager without reports.view',
            (p) =>
                !p.can(Capability.reportsView, businessUnitId: _ccr) &&
                p.can(Capability.mastersView, businessUnitId: _ccr),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(container.read(dashboardDrillProvider), isNull);
          await p6Settle(tester, container);
          p6ExpectNeutral(tester);
          expect(await reportingCacheRows(managerId, businessUnitId: _ccr), 0);
          expect(
            visible('Analytics'),
            isFalse,
            reason:
                'the analytics workspace is not offered without reports.view',
          );
          await s11Signal('manager:reports.view', 'verified');
          await s11AwaitHost(tester, 'manager:reports.view', 'restored');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager with reports.view again',
            (p) => p.can(Capability.reportsView, businessUnitId: _ccr),
          );
          await p6Settle(tester, container);
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          await p6ExpectHeadline(tester, container, client);

          // ── No qualifying authority at all ─────────────────────────────────────
          container = await p6SignIn(tester, 'data.entry@example.com');
          await p6OpenOverview(tester, container);
          await p6WatchNoLeak(tester, container, forbiddenUnits: {_ccr, _hki});
          p6ExpectNeutral(tester);

          // ── Consolidated authority withdrawn, scoped authority kept (host) ────
          container = await p6SignIn(tester, 'giridhar@hki.com');
          for (final unit in [_ccr, _hki]) {
            final granted = Map<String, dynamic>.from(
              await client.rpc<dynamic>(
                    'user_role_grant',
                    params: {
                      'p_user_id': ownerId,
                      'p_role_code': 'manager',
                      'p_business_unit_id': unit,
                      'p_mutation_id': const Uuid().v4(),
                    },
                  )
                  as Map,
            );
            temporaryGrants.add(granted['entity_id'] as String);
          }
          await s11AuthorityUntil(
            tester,
            container,
            'the temporary scoped grants',
            (p) =>
                PnlAuthority.mayReadUnit(p, _ccr) &&
                PnlAuthority.mayReadUnit(p, _hki) &&
                PnlAuthority.mayReadConsolidated(p),
          );
          await p6OpenOverview(tester, container);
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          expect(p6Ready(container).scope, const PnlConsolidatedScope());
          await p6OpenNetSalesDrill(tester, ids.restaurant);
          await s11Signal('owner:reports.view', 'ready');
          await s11AwaitHost(tester, 'owner:reports.view', 'applied');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner without unscoped reports.view',
            (p) =>
                !PnlAuthority.mayReadConsolidated(p) &&
                PnlAuthority.mayReadUnit(p, _ccr),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(container.read(dashboardDrillProvider), isNull);
          await p6Settle(tester, container);
          await p6WatchNoLeak(tester, container, forbiddenUnits: const {});
          expect(p6Ready(container).view.scope.ordered, hasLength(1));
          await p6OpenAnalytics(
            tester,
            container,
            AnalyticsSection.businessComparison,
          );
          expect(
            find.byKey(const Key('analytics-comparison-table')),
            findsNothing,
          );
          await p6OpenOverview(tester, container);
          await s11Signal('owner:reports.view', 'verified');
          await s11AwaitHost(tester, 'owner:reports.view', 'restored');
          await s11AuthorityUntil(
            tester,
            container,
            'the Owner with unscoped reports.view again',
            PnlAuthority.mayReadConsolidated,
          );
        } finally {
          _transport.online = true;
          if (container.read(principalProvider).userId != ownerId) {
            container = await p6SignIn(tester, 'giridhar@hki.com');
          }
          for (final grant in temporaryGrants) {
            await client.rpc<dynamic>(
              'user_role_revoke',
              params: {'p_grant_id': grant, 'p_mutation_id': const Uuid().v4()},
            );
          }
          await _admin.revokeScope('ccr.manager@example.com', 'HKI');
          await p6SweepAfter(client);
          await s11Signal('done', 'finished');
        }
      },
    );
  });

  group('p6-android-dashboard', skip: _phase != 'p6-android-dashboard', () {
    testWidgets(
      'the Home dashboard equals the server, drills down one level at a time, hands off '
      'to the P&L, survives offline and fits every phone width and font scale',
      (tester) async {
        expect(p6Phone(), isTrue, reason: 'run on an Android device');
        await launch(tester);
        final container = await p6SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        await sweepPnlFixtures(client, marker: p6Marker);
        try {
          final ids = await p6Fixtures(client);

          // ── 1 · 3 · Home, consolidated ─────────────────────────────────────────
          await p6OpenOverview(tester, container);
          await p6Refresh(tester, container);
          expect(p6Ready(container).scope, const PnlConsolidatedScope());

          // ── 5 · each relative period ───────────────────────────────────────────
          for (final kind in const [
            DashboardPeriodKind.today,
            DashboardPeriodKind.weekToDate,
            DashboardPeriodKind.monthToDate,
            DashboardPeriodKind.financialYearToDate,
          ]) {
            await p6Period(tester, container, kind);
            await p6ExpectComparedOrWithheld(tester, container, kind);
            await p6Refresh(tester, container);
            await p6ExpectHeadline(tester, container, client);
          }

          // ── 6 · Custom on the Material calendar ────────────────────────────────
          await p6Custom(tester, container, p6From, p6To);
          await p6ExpectHeadline(tester, container, client);
          final march = p6Ready(container);

          // ── 9 · Property comparison, from the server's own per-unit figures ────
          final split =
              march.view.propertyComparison! as PropertyComparisonReady;
          for (final property in split.properties) {
            final one = await serverPnl(
              client,
              [property.businessUnitId],
              p6From.iso,
              p6To.iso,
            );
            expect(property.netSales.paise, one.net);
            expect(property.expenses.paise, one.expenses);
          }
          await p6Reveal(
            tester,
            find.byKey(const Key('dashboard-property-comparison')),
          );

          // ── 8 · Top expense categories; the workspace content stays on Windows ─
          await p6Reveal(
            tester,
            find.byKey(const Key('dashboard-top-expenses')),
          );
          final top =
              march.view.topExpenseCategories!
                  as TopNGrouped<ExpenseHierarchyLine>;
          final server = await serverPnl(
            client,
            [_ccr, _hki],
            p6From.iso,
            p6To.iso,
          );
          expect(
            top.top.fold<int>(0, (s, r) => s + r.amount.paise) +
                (top.others?.paise ?? 0),
            server.expenses,
          );
          for (final key in const [
            'dashboard-revenue-mix',
            'dashboard-departments',
            'dashboard-trend-operating-profit',
          ]) {
            expect(find.byKey(Key(key)), findsNothing, reason: key);
          }
          // ── 19 · no Owner Accounts anywhere on Home ────────────────────────────
          for (final word in const [
            'Settlement',
            'Owner position',
            'Withdrawal',
          ]) {
            expect(
              find.descendant(
                of: find.byKey(const Key('dashboard-home-page')),
                matching: find.textContaining(word),
              ),
              findsNothing,
              reason: word,
            );
          }

          // ── 11 · 14 · Net Sales → category → documents → document, back one level
          final before = await ordinaryAndCacheCounts();
          await p6OpenNetSalesDrill(tester, ids.restaurant);
          expect(find.byType(MobilePnlDrillPage), findsOneWidget);
          await p6Tap(
            tester,
            find.byKey(
              Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
            ),
          );
          await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
          await p6Tap(tester, find.byKey(Key('pnl-drill-doc-${ids.sale}')));
          await p6AwaitDrillLevel(tester, const Key('pnl-document-revenue'));
          expect(find.byType(MobilePnlDocumentPage), findsOneWidget);
          expectReportDetailReadOnly();
          expect(await ordinaryAndCacheCounts(), before);
          await p6Back(tester);
          expect(find.byType(MobilePnlDocumentPage), findsNothing);
          expect(find.byKey(Key('pnl-drill-doc-${ids.sale}')), findsOneWidget);
          await p6Back(tester);
          expect(
            find.byKey(
              Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
            ),
            findsOneWidget,
          );
          await p6Back(tester);
          expect(find.byType(MobilePnlDrillPage), findsNothing);
          expect(find.byType(MobileHomePage), findsOneWidget);

          // ── 12 · Expenses → department → section → category → documents ────────
          await p6Tap(tester, find.byKey(const Key('dashboard-expenses-open')));
          for (final key in [
            'pnl-drill-dept-$_ccr-${_seedId('dept:CCR/FB')}',
            'pnl-drill-section-$_ccr-${_seedId('sec:CCR/FB/FOOD_PROD')}',
            'pnl-drill-category-$_ccr-$_kirana',
          ]) {
            await p6AwaitDrillLevel(tester, Key(key));
            await Scrollable.ensureVisible(
              tester.element(find.byKey(Key(key))),
              alignment: 0.3,
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tapWhenHittable(tester, find.byKey(Key(key)));
          }
          await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.shared}'));
          expect(
            uiPaise(tester, 'pnl-drill-doc-${ids.shared}-amount'),
            2500000,
          );
          await p6BackToHome(tester);

          // ── 7 · 13 · a trend point opens exactly its own day ───────────────────
          final trendPanel = find.byKey(const Key('dashboard-trend-net-sales'));
          await p6OpenChartPoint(tester, trendPanel, 9);
          await p6AwaitDrillLevel(
            tester,
            Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
          );
          final dayServer = await serverPnl(
            client,
            [_ccr, _hki],
            '2027-03-10',
            '2027-03-10',
          );
          expect(uiPaise(tester, 'pnl-drill-total-net'), dayServer.net);
          await p6BackToHome(tester);

          // ── 10 · See full P&L, and Operating Profit handed over as Custom ──────
          await p6Tap(tester, find.byKey(const Key('dashboard-see-full-pnl')));
          await pumpUntil(
            tester,
            'the Reports tab',
            () => find.byType(MobileProfitAndLossPage).evaluate().isNotEmpty,
          );
          await p6OpenOverview(tester, container);
          await p6Tap(
            tester,
            find.byKey(const Key('dashboard-operating-open')),
          );
          await pumpUntil(
            tester,
            'the P&L, handed the dashboard period',
            () => find.byType(MobileProfitAndLossPage).evaluate().isNotEmpty,
          );
          expect(
            container.read(pnlSelectionProvider).period,
            PnlCustomPeriod(p6From, p6To),
          );
          await settlePnl(tester, container);
          expectPnlMatchesServer(tester, container, server);
          await p6OpenOverview(tester, container);
          expect(
            container.read(dashboardSelectionProvider).period,
            DashboardCustomPeriod(p6From, p6To),
            reason: 'Home is as it was left',
          );

          // ── 2 · one property ───────────────────────────────────────────────────
          await p6Scope(tester, container, Key('dashboard-scope-$_ccr'));
          expect(p6Ready(container).view.scope.ordered, [_ccr]);
          await p6ExpectHeadline(tester, container, client);
          expect(
            find.byKey(const Key('dashboard-property-comparison')),
            findsNothing,
          );
          await p6Scope(
            tester,
            container,
            const Key('dashboard-scope-consolidated'),
          );

          // ── 17 · 18 · 20 · offline, then reconnect ─────────────────────────────
          final freshBefore = p6Ready(container).view.freshness!.synchronisedAt;
          await p6Reveal(
            tester,
            find.byKey(const Key('dashboard-net-sales-value')),
          );
          final netBefore = uiPaise(tester, 'dashboard-net-sales-value');
          _transport.online = false;
          try {
            await p6Refresh(
              tester,
              container,
              expected: DashboardSyncPhase.failed,
            );
            await p6Reveal(
              tester,
              find.byKey(const Key('dashboard-net-sales-value')),
            );
            expect(uiPaise(tester, 'dashboard-net-sales-value'), netBefore);
            expect(find.byKey(const Key('dashboard-offline')), findsOneWidget);
            await p6OpenNetSalesDrill(tester, ids.restaurant);
            await p6Tap(
              tester,
              find.byKey(
                Key('pnl-drill-revenue-category-$_ccr-${ids.restaurant}'),
              ),
            );
            await p6AwaitDrillLevel(tester, Key('pnl-drill-doc-${ids.sale}'));
            await p6Tap(tester, find.byKey(Key('pnl-drill-doc-${ids.sale}')));
            await pumpUntil(
              tester,
              'detail not downloaded while offline',
              () =>
                  find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 60),
            );
            await p6BackToHome(tester);
          } finally {
            _transport.online = true;
          }
          await p6Refresh(tester, container);
          expect(
            p6Ready(
              container,
            ).view.freshness!.synchronisedAt.isAfter(freshBefore),
            isTrue,
          );

          // ── Layout: widths and font scales ─────────────────────────────────────
          for (final size in const [
            Size(320, 640),
            Size(360, 740),
            Size(411, 891),
          ]) {
            for (final scale in const [1.0, 1.6]) {
              await tester.binding.setSurfaceSize(size);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              await tester.pump(const Duration(milliseconds: 800));
              await tester.drag(p6HomeScrollable(), const Offset(0, 4000));
              await tester.pump(const Duration(milliseconds: 400));
              for (var i = 0; i < 12; i++) {
                expect(tester.takeException(), isNull, reason: '$size ×$scale');
                p6ExpectMoneyWhole(tester, '$size ×$scale');
                await tester.drag(p6HomeScrollable(), const Offset(0, -400));
                await tester.pump(const Duration(milliseconds: 250));
              }
              final last = find.byKey(const Key('dashboard-see-full-pnl'));
              await p6Centre(tester, last);
              await tester.drag(p6HomeScrollable(), const Offset(0, -4000));
              await tester.pump(const Duration(milliseconds: 400));
              expect(
                tester.getRect(last).bottom,
                lessThanOrEqualTo(
                  tester.getRect(find.byType(FloatingActionButton)).top,
                ),
                reason:
                    'the last control clears the docked [ + ] at $size ×$scale',
              );
            }
          }
        } finally {
          _transport.online = true;
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
          await p6SweepAfter(client);
        }
      },
    );
  });

  group('p6-android-authority', skip: _phase != 'p6-android-authority', () {
    testWidgets(
      'on one phone the next person inherits nothing, a withdrawn property closes what '
      'is open, and a reader without authority sees the neutral sentence',
      (tester) async {
        expect(p6Phone(), isTrue, reason: 'run on an Android device');
        await launch(tester);
        var container = await p6SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        final ownerId = container.read(principalProvider).userId;
        await sweepPnlFixtures(client, marker: p6Marker);
        try {
          final ids = await p6Fixtures(client);
          debugPrint('P6 STEP 1: p6OpenOverview(tester, container);');
          await p6OpenOverview(tester, container);
          debugPrint('P6 STEP 2: p6Custom(tester, container, p6From, p6To);');
          await p6Custom(tester, container, p6From, p6To);
          debugPrint('P6 STEP 3: p6Refresh(tester, container);');
          await p6Refresh(tester, container);
          expect(p6Ready(container).scope, const PnlConsolidatedScope());
          debugPrint('P6 STEP 4: p6OpenNetSalesDrill(tester, ids.restaurant);');
          await p6OpenNetSalesDrill(tester, ids.restaurant);

          // ── 15 · the Owner → a Crystal Canopy manager, a refresh in flight ──────
          unawaited(container.read(dashboardSyncProvider.notifier).refresh());
          debugPrint(
            'P6 STEP 5: tester.pump(const Duration(milliseconds: 50));',
          );
          await tester.pump(const Duration(milliseconds: 50));
          debugPrint('P6 STEP 6: p6BackToHome(tester);');
          await p6BackToHome(tester);
          debugPrint('P6 STEP 7: signOutThroughTheUi(tester);');
          await signOutThroughTheUi(tester);
          expect(await reportingCacheRows(ownerId), 0);
          container = await p6SignIn(tester, 'ccr.manager@example.com');
          final managerId = container.read(principalProvider).userId;
          debugPrint('P6 STEP 8: p6OpenOverview(tester, container);');
          await p6OpenOverview(tester, container);
          debugPrint(
            'P6 STEP 9: p6WatchNoLeak(tester, container, forbiddenUnits: {_hki',
          );
          await p6WatchNoLeak(tester, container, forbiddenUnits: {_hki});
          expect(
            container.read(dashboardSelectionProvider).period,
            const DashboardRelativePeriod(DashboardPeriodKind.monthToDate),
          );
          debugPrint('P6 STEP 10: p6Custom(tester, container, p6From, p6To);');
          await p6Custom(tester, container, p6From, p6To);
          debugPrint('P6 STEP 11: p6Refresh(tester, container);');
          await p6Refresh(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_ccr]);
          debugPrint(
            'P6 STEP 12: p6ExpectHeadline(tester, container, client);',
          );
          await p6ExpectHeadline(tester, container, client);

          // ── 16 · the same person loses a property while a drill-down is open ──
          debugPrint(
            'P6 STEP 13: _admin.grantScope(ccr.manager@example.com, manager',
          );
          await _admin.grantScope('ccr.manager@example.com', 'manager', 'HKI');
          debugPrint('P6 STEP 14: s11AuthorityUntil(');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager with Hotel Krishna',
            (p) => PnlAuthority.mayReadUnit(p, _hki),
          );
          debugPrint(
            'P6 STEP 15: p6Scope(tester, container, Key(dashboard-scope-_hki',
          );
          await p6Scope(tester, container, Key('dashboard-scope-$_hki'));
          debugPrint('P6 STEP 16: p6Custom(tester, container, p6From, p6To);');
          await p6Custom(tester, container, p6From, p6To);
          debugPrint('P6 STEP 17: p6Refresh(tester, container);');
          await p6Refresh(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_hki]);
          debugPrint(
            'P6 STEP 18: p6Tap(tester, find.byKey(const Key(dashboard-expenses',
          );
          await p6Tap(tester, find.byKey(const Key('dashboard-expenses-open')));
          debugPrint('P6 STEP 19: p6AwaitDrillLevel(');
          await p6AwaitDrillLevel(
            tester,
            Key('pnl-drill-dept-$_hki-${_seedId('dept:HKI/HKI_UTIL')}'),
          );
          expect(find.byType(MobilePnlDrillPage), findsOneWidget);
          debugPrint(
            'P6 STEP 20: _admin.revokeScope(ccr.manager@example.com, HKI);',
          );
          await _admin.revokeScope('ccr.manager@example.com', 'HKI');
          debugPrint('P6 STEP 21: s11AuthorityUntil(');
          await s11AuthorityUntil(
            tester,
            container,
            'the manager without Hotel Krishna',
            (p) =>
                !PnlAuthority.mayReadUnit(p, _hki) &&
                PnlAuthority.mayReadUnit(p, _ccr),
          );
          debugPrint('P6 STEP 22: pumpUntil(');
          await pumpUntil(
            tester,
            'the drill-down to close',
            () => find.byType(MobilePnlDrillPage).evaluate().isEmpty,
          );
          debugPrint(
            'P6 STEP 23: p6ExpectClosedAfterLoss(tester, container, {_hki});',
          );
          await p6ExpectClosedAfterLoss(tester, container, {_hki});
          debugPrint('P6 STEP 24: p6Settle(tester, container);');
          await p6Settle(tester, container);
          expect(p6Ready(container).view.scope.ordered, [_ccr]);
          expect(await reportingCacheRows(managerId, businessUnitId: _hki), 0);

          // ── 4 · no qualifying authority ────────────────────────────────────────
          container = await p6SignIn(tester, 'data.entry@example.com');
          debugPrint('P6 STEP 25: p6OpenOverview(tester, container);');
          await p6OpenOverview(tester, container);
          debugPrint(
            'P6 STEP 26: p6WatchNoLeak(tester, container, forbiddenUnits: {_ccr',
          );
          await p6WatchNoLeak(tester, container, forbiddenUnits: {_ccr, _hki});
          p6ExpectNeutral(tester);
        } finally {
          _transport.online = true;
          if (container.read(principalProvider).userId != ownerId) {
            container = await p6SignIn(tester, 'giridhar@hki.com');
          }
          debugPrint(
            'P6 STEP 27: _admin.revokeScope(ccr.manager@example.com, HKI);',
          );
          await _admin.revokeScope('ccr.manager@example.com', 'HKI');
          debugPrint('P6 STEP 28: sweepPnlFixtures(client, marker: p6Marker);');
          await p6SweepAfter(client);
        }
      },
    );
  });

  // ── Phase 7 Slice 10 — export, Save As and printing in the real Windows application ──
  //
  // One process launch on Windows. The phase drives the application; a PERSON (or the
  // acceptance operator) answers every native dialog, which no harness can reach — the
  // Save As dialog, the overwrite question, the print dialog and "Save Print Output As".
  // Nothing replaces those dialogs: the saver and printer are the production ones,
  // wrapped only to record what the dialog returned and which bytes went to print.
  //
  //     flutter test integration_test/device_acceptance_test.dart -d windows \
  //       --dart-define-from-file=config/dev.json \
  //       --dart-define-from-file=<scratch>/identities.defines.json \
  //       --dart-define=PHASE=p7-windows-export \
  //       --dart-define=P7_OUT=<an empty folder> \
  //       --dart-define=P7_STATUS=<a file the operator watches> \
  //       --dart-define=P7_HOST=<a file the operator writes>
  //
  // Each dialog step writes {step, do} to P7_STATUS and waits, up to fifteen minutes,
  // for the person to finish it. Steps that need the operator to act outside the app
  // (open a file in Excel, change a development role) wait for P7_HOST to say so.
  const p7Out = String.fromEnvironment('P7_OUT');
  const p7StatusFile = String.fromEnvironment('P7_STATUS');
  const p7HostFile = String.fromEnvironment('P7_HOST');
  final p7Dialogs = <({String suggested, String? chosen})>[];
  final p7Printed = <Uint8List>[];

  List<Override> p7Recorders() => [
    exportFileSaverProvider.overrideWithValue(
      ExportFileSaver(
        pickLocation: ({required suggestedName, required format}) async {
          final chosen = await fileSelectorSaveLocation(
            suggestedName: suggestedName,
            format: format,
          );
          p7Dialogs.add((suggested: suggestedName, chosen: chosen));
          return chosen;
        },
      ),
    ),
    // Records what the dialog was actually given, when Print was pressed.
    exportPrinterProvider.overrideWithValue(({
      required bytes,
      required jobName,
      required layout,
    }) {
      return printingLayoutPdf(
        bytes: bytes,
        jobName: jobName,
        layout: () {
          final document = layout();
          if (document.isNotEmpty) p7Printed.add(document);
          return document;
        },
      );
    }),
  ];

  void p7Say(String step, String instruction) {
    File(p7StatusFile).writeAsStringSync(
      jsonEncode({
        'step': step,
        'do': instruction,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    debugPrint('P7 $step: $instruction');
  }

  Future<void> p7AwaitHost(WidgetTester tester, String state) =>
      pumpUntil(tester, 'the operator to report $state', () {
        try {
          return (jsonDecode(File(p7HostFile).readAsStringSync())
                  as Map)['state'] ==
              state;
        } on Object {
          return false;
        }
      }, timeout: const Duration(minutes: 20));

  String p7Path(String name) => '$p7Out${Platform.pathSeparator}$name';

  // Excel's own `~$name` owner file, present while a workbook is open, is Excel's.
  List<String> p7Listing() => [
    for (final e in Directory(p7Out).listSync())
      if (!e.uri.pathSegments.last.startsWith(r'~$')) e.uri.pathSegments.last,
  ]..sort();

  Future<void> p7OpenExportCentre(WidgetTester tester) async {
    await pumpUntil(
      tester,
      'the Reports destination',
      () => visible('Reports'),
    );
    await tester.tap(find.text('Reports').first);
    await pumpUntil(
      tester,
      'the Export Centre',
      () => find.byKey(const Key('export-centre')).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> p7Reveal(WidgetTester tester, Finder finder) async {
    final list = find
        .descendant(
          of: find.byKey(const Key('export-centre')),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.scrollUntilVisible(finder, 160, scrollable: list);
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.5,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool p7Has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  /// Taps an export or print control, tells the operator what to do in the native
  /// dialog, and waits for the application's own outcome.
  Future<ExportActionResult> p7Act(
    WidgetTester tester,
    ProviderContainer container,
    String key,
    String step,
    String instruction,
  ) async {
    final before = container.read(exportActionProvider).last;
    await p7Reveal(tester, find.byKey(Key(key)));
    p7Say(step, instruction);
    await tapWhenHittable(tester, find.byKey(Key(key)));
    await pumpUntil(tester, 'the operator to finish $step', () {
      final s = container.read(exportActionProvider);
      return !s.isRunning && s.last != null && !identical(s.last, before);
    }, timeout: const Duration(minutes: 15));
    final result = container.read(exportActionProvider).last!.result;
    final shown = find.byKey(Key('export-${key.split('-')[1]}-outcome'));
    await p7Reveal(tester, shown);
    expect(
      tester.widget<Text>(shown).data,
      exportActionMessage(result),
      reason: 'the outcome is stated on screen as it happened',
    );
    p7Say('$step:done', exportActionMessage(result));
    return result;
  }

  /// A saved file whose name the dialog returned, read back.
  Uint8List p7Saved(ExportActionResult result) {
    expect(result, isA<ExportActionSaved>(), reason: '$result');
    final name = (result as ExportActionSaved).fileName;
    // Read back from where the dialog actually put it, not from where it was asked to.
    final chosen = p7Dialogs.last.chosen!;
    final path = chosen.toLowerCase().endsWith(name.toLowerCase())
        ? chosen
        : '$chosen${name.substring(name.lastIndexOf('.'))}';
    expect(File(path).parent.path, p7Out, reason: 'saved where asked: $path');
    final bytes = File(path).readAsBytesSync();
    expect(bytes, isNotEmpty);
    return bytes;
  }

  String p7PdfText(Uint8List bytes) =>
      PdfText.read(inflatePdfStreams(bytes)).lines.join('\n');

  Set<String> p7Numbers(Uint8List xlsx) {
    final book = StoredWorkbook(xlsx);
    return {
      for (final s in book.sheetNames)
        for (final c in book.cells(s).values)
          if (c.isNumber) c.value!,
    };
  }

  /// Every figure is in the PDF exactly as the screen prints it, and in the workbook
  /// as the exact numeric cell; the workbook holds no formula and no internal id.
  void p7ExpectFigures(
    String what,
    Uint8List pdf,
    Uint8List xlsx,
    List<Money> figures, {
    List<String> forbidden = const [],
  }) {
    final text = p7PdfText(pdf);
    final numbers = p7Numbers(xlsx);
    for (final m in figures) {
      expect(
        text,
        contains(MoneyFormatter.standard.format(m)),
        reason: '$what PDF ${m.paise}',
      );
      expect(
        numbers,
        contains(MoneyFormatter.decimalLiteral(m)),
        reason: '$what XLSX ${m.paise}',
      );
    }
    final book = StoredWorkbook(xlsx).allText;
    expect(book, isNot(contains('<f>')), reason: '$what: no formula');
    expect(book, isNot(contains('<f ')), reason: '$what: no formula');
    for (final f in forbidden) {
      expect(book, isNot(contains(f)), reason: '$what XLSX leaks $f');
      expect(text, isNot(contains(f)), reason: '$what PDF leaks $f');
      expect(
        latin1.decode(inflatePdfStreams(pdf)),
        isNot(contains(f)),
        reason: '$what PDF bytes leak $f',
      );
    }
  }

  Money p7Top<L>(TopNOutcome<L>? outcome) {
    expect(outcome, isA<TopNGrouped<L>>(), reason: '$outcome');
    return (outcome! as TopNGrouped<L>).top.first.amount;
  }

  String p7Hash(String path) {
    final bytes = File(path).readAsBytesSync();
    var h = 0;
    for (final b in bytes) {
      h = (h * 31 + b) & 0x3fffffff;
    }
    return '${bytes.length}:$h';
  }

  /// The text of two renders of one document, less the one line that names when the
  /// file was generated.
  List<String> p7WithoutGenerated(Uint8List pdf) => [
    for (final l in PdfText.read(inflatePdfStreams(pdf)).lines)
      if (!l.contains('Generated on this device')) l,
  ];

  group('p7-windows-export', skip: _phase != 'p7-windows-export', () {
    testWidgets('the Export Centre saves, prints and refuses through the real native dialogs, '
        'offline too, and every file equals the screen to the paisa', (tester) async {
      expect(p6Phone(), isFalse, reason: 'run on Windows');
      for (final (name, value) in [
        ('P7_OUT', p7Out),
        ('P7_STATUS', p7StatusFile),
        ('P7_HOST', p7HostFile),
      ]) {
        expect(value, isNotEmpty, reason: '$name names a path');
      }
      final out = Directory(p7Out)..createSync(recursive: true);
      expect(out.listSync(), isEmpty, reason: 'P7_OUT starts empty');

      await launch(tester, recorders: p7Recorders());
      final container = await p6SignIn(tester, 'giridhar@hki.com');
      final client = Supabase.instance.client;
      final ownerId = container.read(principalProvider).userId;
      await sweepPnlFixtures(client, marker: p6Marker);
      try {
        final ids = await p6Fixtures(client);

        // ── The two reports the Export Centre exports from ────────────────────
        await openPnl(tester, container);
        await chooseCustom(tester, container, p6From.iso, p6To.iso);
        await refreshPnl(tester, container);
        expect(
          (container.read(pnlViewProvider).value! as PnlReportView).scope,
          isA<PnlConsolidatedScope>(),
          reason: 'the Owner reads the consolidated P&L',
        );
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(client, [_ccr, _hki], p6From.iso, p6To.iso),
        );
        final pnl = computedPnl(container);

        await p6OpenOverview(tester, container);
        await p6Custom(tester, container, p6From, p6To);
        await p6Refresh(tester, container);
        await p6ExpectHeadline(tester, container, client);
        final ready = p6Ready(container);
        final dash = ready.view.resultOrNull!;

        // ── The Export Centre: four reports, what each covers, its actions ────
        await p7OpenExportCentre(tester);
        for (final r in ExportReport.values) {
          await p7Reveal(tester, find.byKey(Key('export-${r.name}')));
          final covers = tester
              .widget<Text>(find.byKey(Key('export-${r.name}-covers')))
              .data!;
          expect(covers, contains(dashboardConsolidatedScopeLabel));
          expect(covers, contains('2027'), reason: '${r.name}: $covers');
          expect(p7Has('export-${r.name}-freshness'), isTrue);
          expect(p7Has('export-${r.name}-pdf'), isTrue, reason: r.name);
          expect(p7Has('export-${r.name}-xlsx'), isTrue, reason: r.name);
          expect(p7Has('export-${r.name}-print'), isTrue, reason: r.name);
          debugPrint(
            'P7 CARD ${r.name}: $covers | ${tester.widget<Text>(find.byKey(Key('export-${r.name}-freshness'))).data}',
          );
        }
        final sync = (
          container.read(pnlSyncProvider),
          container.read(dashboardSyncProvider),
        );

        // ── Save As, one of each report and format ─────────────────────────────
        final saved = <String, Uint8List>{};
        for (final (report, format, file) in [
          (ExportReport.profitAndLoss, 'pdf', 'p7-pnl.pdf'),
          (ExportReport.profitAndLoss, 'xlsx', 'p7-pnl.xlsx'),
          (ExportReport.revenueAnalysis, 'pdf', 'p7-revenue.pdf'),
          (ExportReport.revenueAnalysis, 'xlsx', 'p7-revenue.xlsx'),
          (ExportReport.expenseAnalysis, 'pdf', 'p7-expense.pdf'),
          (ExportReport.expenseAnalysis, 'xlsx', 'p7-expense.xlsx'),
          (ExportReport.businessComparison, 'pdf', 'p7-comparison.pdf'),
          (ExportReport.businessComparison, 'xlsx', 'p7-comparison.xlsx'),
        ]) {
          final result = await p7Act(
            tester,
            container,
            'export-${report.name}-$format',
            'save ${report.name} $format',
            'Save As: note the suggested name, then save as ${p7Path(file)}',
          );
          saved[file] = p7Saved(result);
          final dialog = p7Dialogs.last;
          debugPrint(
            'P7 DIALOG suggested=${dialog.suggested} chose=${dialog.chosen}',
          );
          expect(dialog.suggested, startsWith('KrishnaImperialMIS_'));
          expect(dialog.suggested, endsWith('.$format'));
          expect(dialog.suggested, contains('2027-03-01_2027-03-31'));
        }
        expect(
          p7Listing().where((n) => n.contains('.part')),
          isEmpty,
          reason: 'no temporary file is left beside a save',
        );
        expect(p7Listing(), hasLength(8));

        // ── Parity: screen = PDF = XLSX, to the paisa ─────────────────────────
        final forbidden = [
          _ccr,
          _hki,
          ownerId,
          ids.sale,
          ids.room,
          ids.shared,
          ids.restaurant,
          'reports.export',
          'reports.view',
          'row_version',
          'snapshot',
          p6Marker,
          'C:\\',
        ];
        final split = PropertyComparison.of(pnl) as PropertyComparisonReady;
        p7ExpectFigures('P&L', saved['p7-pnl.pdf']!, saved['p7-pnl.xlsx']!, [
          pnl.grossSales,
          pnl.gst,
          pnl.netSales,
          pnl.expenses,
          pnl.operatingProfit,
          for (final p in split.properties) ...[
            p.result.netSales,
            p.result.expenses,
            p.result.operatingProfit,
          ],
          Money.fromPaise(2500000), // Kirana & Pulses, Crystal Canopy
        ], forbidden: forbidden);
        expect(
          p7PdfText(saved['p7-pnl.pdf']!),
          contains(pnl.margin.displayTwoDecimals),
        );
        expect(
          p7Numbers(saved['p7-pnl.xlsx']!),
          contains((pnl.margin as MarginRatio).displayedFractionLiteral),
        );
        final previous = ready.view.previous.resultOrNull!;
        p7ExpectFigures(
          'Revenue Analysis',
          saved['p7-revenue.pdf']!,
          saved['p7-revenue.xlsx']!,
          [
            dash.grossSales,
            dash.gst,
            dash.netSales,
            previous.netSales,
            p7Top(ready.view.topRevenueCategories),
          ],
          forbidden: forbidden,
        );
        p7ExpectFigures(
          'Expense & Department Analysis',
          saved['p7-expense.pdf']!,
          saved['p7-expense.xlsx']!,
          [
            dash.expenses,
            p7Top(ready.view.topExpenseCategories),
            p7Top(ready.view.departmentSpending),
          ],
          forbidden: forbidden,
        );
        final comparison =
            ready.view.propertyComparison! as PropertyComparisonReady;
        p7ExpectFigures(
          'Business Comparison',
          saved['p7-comparison.pdf']!,
          saved['p7-comparison.xlsx']!,
          [
            for (final p in comparison.properties) ...[
              p.result.netSales,
              p.result.expenses,
              p.result.operatingProfit,
            ],
            comparison.total.netSales,
            comparison.total.operatingProfit,
          ],
          forbidden: forbidden,
        );
        for (final entry in saved.entries.where(
          (e) => e.key.endsWith('.pdf'),
        )) {
          final text = p7PdfText(entry.value);
          expect(text, contains('Page 1 of'), reason: entry.key);
          expect(text, contains('₹'), reason: entry.key);
          expect(text, contains('Generated on this device'), reason: entry.key);
        }

        // ── Cancel ─────────────────────────────────────────────────────────────
        final listing = p7Listing();
        final cancelled = await p7Act(
          tester,
          container,
          'export-profitAndLoss-pdf',
          'cancel',
          'Save As: press Cancel',
        );
        expect(cancelled, isA<ExportActionCancelled>());
        expect(p7Listing(), listing, reason: 'a cancel writes nothing');

        // ── Overwrite, confirmed in the dialog ─────────────────────────────────
        final beforeOverwrite = File(p7Path('p7-pnl.pdf')).lastModifiedSync();
        await tester.pump(const Duration(seconds: 2));
        final replaced = await p7Act(
          tester,
          container,
          'export-profitAndLoss-pdf',
          'overwrite',
          'Save As: choose ${p7Path('p7-pnl.pdf')} again and answer Yes to replace',
        );
        p7Saved(replaced);
        expect(
          File(
            p7Path('p7-pnl.pdf'),
          ).lastModifiedSync().isAfter(beforeOverwrite),
          isTrue,
        );
        expect(p7Listing(), listing);

        // ── A name typed without its extension ─────────────────────────────────
        final xlsxBefore = p7Hash(p7Path('p7-pnl.xlsx'));
        final noExtension = await p7Act(
          tester,
          container,
          'export-profitAndLoss-xlsx',
          'no-extension',
          'Save As: type ${p7Path('p7-pnl')} (no extension). If Windows asks to '
              'replace p7-pnl.xlsx, answer No, then Cancel',
        );
        debugPrint(
          'P7 NO-EXTENSION dialog returned ${p7Dialogs.last.chosen}: $noExtension',
        );
        expect(
          noExtension,
          anyOf(
            isA<ExportActionCancelled>(),
            isA<ExportActionSaveFailed>().having(
              (f) => f.failure,
              'failure',
              ExportSaveFailure.nameTaken,
            ),
          ),
        );
        expect(p7Hash(p7Path('p7-pnl.xlsx')), xlsxBefore);
        expect(p7Listing(), listing);

        // ── A write the file system refuses: the file is open in Excel ─────────
        p7Say(
          'excel-lock',
          'Open ${p7Path('p7-pnl.xlsx')} in Microsoft Excel and leave it open, '
              'then write {"state":"excel-open"} to P7_HOST',
        );
        await p7AwaitHost(tester, 'excel-open');
        final locked = await p7Act(
          tester,
          container,
          'export-profitAndLoss-xlsx',
          'locked',
          'Save As: choose ${p7Path('p7-pnl.xlsx')} and answer Yes to replace',
        );
        debugPrint('P7 LOCKED: $locked');
        expect(
          locked,
          isA<ExportActionSaveFailed>().having(
            (f) => f.failure,
            'failure',
            ExportSaveFailure.fileInUse,
          ),
          reason: 'the person is told the file is open, not to change folder',
        );
        expect(p7Hash(p7Path('p7-pnl.xlsx')), xlsxBefore);
        expect(p7Listing(), listing, reason: 'no partial file is left');
        p7Say(
          'excel-close',
          'Close Excel, then write {"state":"excel-closed"}',
        );
        await p7AwaitHost(tester, 'excel-closed');

        // ── Print: the native dialog, the same PDF ─────────────────────────────
        final printed = await p7Act(
          tester,
          container,
          'export-profitAndLoss-print',
          'print pnl',
          'Print: choose Microsoft Print to PDF, Print, and save the output as '
              '${p7Path('printed-pnl.pdf')}',
        );
        expect(printed, isA<ExportActionHandedOver>());
        expect(
          p7WithoutGenerated(p7Printed.last),
          p7WithoutGenerated(File(p7Path('p7-pnl.pdf')).readAsBytesSync()),
          reason: 'print receives the Save PDF document, not a second render',
        );
        final printCancel = await p7Act(
          tester,
          container,
          'export-profitAndLoss-print',
          'print cancel',
          'Print: press Cancel',
        );
        expect(printCancel, isA<ExportActionCancelled>());
        for (final (report, file) in [
          (ExportReport.revenueAnalysis, 'printed-revenue.pdf'),
          (ExportReport.expenseAnalysis, 'printed-expense.pdf'),
          (ExportReport.businessComparison, 'printed-comparison.pdf'),
        ]) {
          final r = await p7Act(
            tester,
            container,
            'export-${report.name}-print',
            'print ${report.name}',
            'Print: Microsoft Print to PDF, Print, save as ${p7Path(file)}',
          );
          expect(r, isA<ExportActionHandedOver>());
          expect(
            p7WithoutGenerated(p7Printed.last),
            p7WithoutGenerated(
              saved['p7-${switch (report) {
                ExportReport.revenueAnalysis => 'revenue',
                ExportReport.expenseAnalysis => 'expense',
                _ => 'comparison',
              }}.pdf']!,
            ),
          );
        }
        expect(
          (
            container.read(pnlSyncProvider),
            container.read(dashboardSyncProvider),
          ),
          sync,
          reason: 'no export or print started a synchronisation',
        );

        // ── Offline: exports from what is on the device ────────────────────────
        _transport.online = false;
        _transport.refusedWhileOffline.clear();
        final freshness = {
          for (final r in ExportReport.values)
            r: tester
                .widget<Text>(find.byKey(Key('export-${r.name}-freshness')))
                .data,
        };
        final offline = <String, Uint8List>{};
        for (final (key, file) in [
          ('export-profitAndLoss-pdf', 'offline-pnl.pdf'),
          ('export-profitAndLoss-xlsx', 'offline-pnl.xlsx'),
          ('export-expenseAnalysis-xlsx', 'offline-expense.xlsx'),
          ('export-businessComparison-pdf', 'offline-comparison.pdf'),
        ]) {
          offline[file] = p7Saved(
            await p7Act(
              tester,
              container,
              key,
              'offline $file',
              'OFFLINE. Save As: ${p7Path(file)}',
            ),
          );
        }
        final offlinePrint = await p7Act(
          tester,
          container,
          'export-profitAndLoss-print',
          'offline print',
          'OFFLINE. Print: Microsoft Print to PDF, save as '
              '${p7Path('offline-printed-pnl.pdf')}',
        );
        expect(offlinePrint, isA<ExportActionHandedOver>());
        debugPrint('P7 OFFLINE refused: ${_transport.refusedWhileOffline}');
        expect(
          _transport.refusedWhileOffline.where(
            (r) =>
                r.contains('reporting') ||
                r.contains('contribution') ||
                r.contains('revenue') ||
                r.contains('expense'),
          ),
          isEmpty,
          reason: 'no export reached for a report',
        );
        expect((
          container.read(pnlSyncProvider),
          container.read(dashboardSyncProvider),
        ), sync);
        for (final r in ExportReport.values) {
          await p7Reveal(tester, find.byKey(Key('export-${r.name}')));
          expect(
            tester
                .widget<Text>(find.byKey(Key('export-${r.name}-freshness')))
                .data,
            freshness[r],
            reason: 'freshness is what it was — offline changes no claim',
          );
        }
        expect(
          p7WithoutGenerated(offline['offline-pnl.pdf']!),
          p7WithoutGenerated(saved['p7-pnl.pdf']!),
        );
        expect(
          p7Numbers(offline['offline-pnl.xlsx']!),
          p7Numbers(saved['p7-pnl.xlsx']!),
        );

        // ── Reconnect: reporting refreshes as normal ───────────────────────────
        _transport.online = true;
        await openPnl(tester, container);
        await refreshPnl(tester, container);
        expectPnlMatchesServer(
          tester,
          container,
          await serverPnl(client, [_ccr, _hki], p6From.iso, p6To.iso),
        );
        await p6OpenOverview(tester, container);
        await p6Refresh(tester, container);

        // ── Open in Analytics goes to the report the card describes ────────────
        await p7OpenExportCentre(tester);
        await p7Reveal(
          tester,
          find.byKey(const Key('export-revenueAnalysis-open')),
        );
        await tapWhenHittable(
          tester,
          find.byKey(const Key('export-revenueAnalysis-open')),
        );
        await pumpUntil(
          tester,
          'Revenue Analysis',
          () =>
              container.read(analyticsSectionProvider) ==
                  AnalyticsSection.revenue &&
              find.byKey(const Key('analytics-page')).evaluate().isNotEmpty,
        );
        await p7OpenExportCentre(tester);
        await p7Reveal(
          tester,
          find.byKey(const Key('export-profitAndLoss-open')),
        );
        await tapWhenHittable(
          tester,
          find.byKey(const Key('export-profitAndLoss-open')),
        );
        await pumpUntil(
          tester,
          'the P&L',
          () =>
              container.read(analyticsSectionProvider) ==
                  AnalyticsSection.profitAndLoss &&
              find.byKey(const Key('pnl-page')).evaluate().isNotEmpty,
        );
        p7Say('done', 'phase finished; ${p7Listing().length} files');
        debugPrint('P7 FILES ${p7Listing()}');
      } finally {
        _transport.online = true;
        await p6SweepAfter(client);
      }
    });
  });

  // ── Phase 7 Slice 10 — who is offered Export and Print, in the real application ───
  //
  // Run on Windows with the operator, like p7-windows-export. Some steps change a
  // development role for a moment; the phase writes {step:"host:…"} and waits for
  // P7_HOST to report "applied" and later "restored" (D-243). Nothing branches on a role
  // name: every assertion is about which controls the capabilities produce.
  Future<void> p7Host(WidgetTester tester, String step, String state) async {
    p7Say('host:$step', 'HOST: $step, then write {"state":"$state"}');
    await p7AwaitHost(tester, state);
  }

  /// Which of the three actions a report card offers now.
  ({bool pdf, bool xlsx, bool print, bool refused}) p7Offered(ExportReport r) =>
      (
        pdf: p7Has('export-${r.name}-pdf'),
        xlsx: p7Has('export-${r.name}-xlsx'),
        print: p7Has('export-${r.name}-print'),
        refused:
            p7Has('export-${r.name}-not-offered') ||
            p7Has('export-${r.name}-unavailable'),
      );

  Future<({bool pdf, bool xlsx, bool print, bool refused})> p7Card(
    WidgetTester tester,
    ExportReport r,
  ) async {
    await p7Reveal(tester, find.byKey(Key('export-${r.name}')));
    await tester.pump(const Duration(milliseconds: 300));
    final o = p7Offered(r);
    debugPrint('P7 AUTH ${r.name}: $o');
    return o;
  }

  Future<void> p7Reports(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await openPnl(tester, container);
    await chooseCustom(tester, container, p6From.iso, p6To.iso);
    await refreshPnl(tester, container);
    await p6OpenOverview(tester, container);
    await p6Custom(tester, container, p6From, p6To);
    await p6Refresh(tester, container);
    await p7OpenExportCentre(tester);
  }

  group('p7-windows-authority', skip: _phase != 'p7-windows-authority', () {
    testWidgets('Export needs view authority and reports.export, Print needs reports.print, for '
        'the exact scope; a user switch, a role change and a loss while a dialog is open '
        'each take the action away', (tester) async {
      expect(p6Phone(), isFalse, reason: 'run on Windows');
      for (final v in [p7Out, p7StatusFile, p7HostFile]) {
        expect(v, isNotEmpty);
      }
      Directory(p7Out).createSync(recursive: true);
      expect(Directory(p7Out).listSync(), isEmpty);

      await launch(tester, recorders: p7Recorders());
      var container = await p6SignIn(tester, 'giridhar@hki.com');
      final ownerId = container.read(principalProvider).userId;
      final client = Supabase.instance.client;
      await sweepPnlFixtures(client, marker: p6Marker);
      try {
        await p6Fixtures(client);

        // ── The Owner: everything, consolidated ────────────────────────────────
        await p7Reports(tester, container);
        for (final r in ExportReport.values) {
          final o = await p7Card(tester, r);
          expect((o.pdf, o.xlsx, o.print), (true, true, true), reason: r.name);
        }

        // ── A user switch: the Manager bundle holds reports.view only (D-292) ──
        await signOutThroughTheUi(tester);
        container = await p6SignIn(tester, 'ccr.manager@example.com');
        expect(
          container.read(exportActionProvider).last,
          isNull,
          reason: 'the previous person\'s outcome is not the next person\'s',
        );
        await p7Reports(tester, container);
        for (final r in ExportReport.values) {
          final o = await p7Card(tester, r);
          expect(
            (o.pdf, o.xlsx, o.print),
            (false, false, false),
            reason: '${r.name}: reading a report is not exporting it',
          );
        }
        expect(
          p7Has('export-profitAndLoss-not-offered'),
          isTrue,
          reason: 'the P&L says why nothing is offered',
        );

        // ── The Accountant: export and print, Crystal Canopy only ──────────────
        await signOutThroughTheUi(tester);
        container = await p6SignIn(tester, 'accountant@example.com');
        await p7Reports(tester, container);
        expect(
          (container.read(pnlViewProvider).value! as PnlReportView).scope,
          isA<PnlUnitScope>(),
        );
        for (final r in [
          ExportReport.profitAndLoss,
          ExportReport.revenueAnalysis,
          ExportReport.expenseAnalysis,
        ]) {
          final o = await p7Card(tester, r);
          expect((o.pdf, o.xlsx, o.print), (true, true, true), reason: r.name);
        }
        final comparison = await p7Card(
          tester,
          ExportReport.businessComparison,
        );
        expect(
          (comparison.pdf, comparison.xlsx, comparison.print),
          (false, false, false),
          reason: 'Business Comparison needs consolidated authority',
        );

        // ── Two scoped grants are not consolidated authority (D-164) ───────────
        await _admin.grantScope('accountant@example.com', 'accountant', 'HKI');
        await s11AuthorityUntil(
          tester,
          container,
          'the accountant with Hotel Krishna too',
          (p) => PnlAuthority.mayReadUnit(p, _hki),
        );
        await p7OpenExportCentre(tester);
        final both = await p7Card(tester, ExportReport.businessComparison);
        expect((both.pdf, both.xlsx, both.print), (false, false, false));
        await _admin.revokeScope('accountant@example.com', 'HKI');
        await s11AuthorityUntil(
          tester,
          container,
          'the accountant without Hotel Krishna',
          (p) => !PnlAuthority.mayReadUnit(p, _hki),
        );

        // ── Export-only: reports.print taken from the role ─────────────────────
        await p7Host(tester, 'remove reports.print from accountant', 'applied');
        await s11AuthorityUntil(
          tester,
          container,
          'the accountant without reports.print',
          (p) => !p.canAnywhere(Capability.reportsPrint),
        );
        await p7OpenExportCentre(tester);
        var pnl = await p7Card(tester, ExportReport.profitAndLoss);
        expect((pnl.pdf, pnl.xlsx, pnl.print), (true, true, false));
        await p7Host(tester, 'restore reports.print to accountant', 'restored');
        await s11AuthorityUntil(
          tester,
          container,
          'reports.print back',
          (p) => p.canAnywhere(Capability.reportsPrint),
        );

        // ── Print-only: reports.export taken from the role ─────────────────────
        await p7Host(
          tester,
          'remove reports.export from accountant',
          'applied',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'the accountant without reports.export',
          (p) => !p.canAnywhere(Capability.reportsExport),
        );
        await p7OpenExportCentre(tester);
        pnl = await p7Card(tester, ExportReport.profitAndLoss);
        expect((pnl.pdf, pnl.xlsx, pnl.print), (false, false, true));
        await p7Host(
          tester,
          'restore reports.export to accountant',
          'restored',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'reports.export back',
          (p) => p.canAnywhere(Capability.reportsExport),
        );

        // ── reports.export lost while the Save As dialog is open ───────────────
        await p7OpenExportCentre(tester);
        await p7Reveal(
          tester,
          find.byKey(const Key('export-profitAndLoss-pdf')),
        );
        final beforeSave = container.read(exportActionProvider).last;
        await tapWhenHittable(
          tester,
          find.byKey(const Key('export-profitAndLoss-pdf')),
        );
        await tester.pump(const Duration(seconds: 2));
        await p7Host(
          tester,
          'save-dialog-open: remove reports.export from accountant '
              '(leave the dialog open)',
          'applied',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'the loss, while the dialog is open',
          (p) => !p.canAnywhere(Capability.reportsExport),
        );
        p7Say(
          'lost-during-save',
          'Save As: save as ${p7Path('lost-during-save.pdf')}',
        );
        await pumpUntil(tester, 'the dialog to close', () {
          final s = container.read(exportActionProvider);
          return !s.isRunning && !identical(s.last, beforeSave);
        }, timeout: const Duration(minutes: 15));
        final lostSave = container.read(exportActionProvider).last!.result;
        debugPrint('P7 LOST DURING SAVE: $lostSave');
        expect(lostSave, isA<ExportActionAbandoned>());
        expect(
          File(p7Path('lost-during-save.pdf')).existsSync(),
          isFalse,
          reason: 'no file is written for a person who lost reports.export',
        );
        await p7Host(
          tester,
          'restore reports.export to accountant',
          'restored',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'reports.export back',
          (p) => p.canAnywhere(Capability.reportsExport),
        );

        // ── reports.print lost while the print dialog is open ──────────────────
        await p7OpenExportCentre(tester);
        await p7Reveal(
          tester,
          find.byKey(const Key('export-profitAndLoss-print')),
        );
        final beforePrint = container.read(exportActionProvider).last;
        await tapWhenHittable(
          tester,
          find.byKey(const Key('export-profitAndLoss-print')),
        );
        await tester.pump(const Duration(seconds: 2));
        await p7Host(
          tester,
          'print-dialog-open: remove reports.print from accountant '
              '(leave the dialog open)',
          'applied',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'the loss, while the print dialog is open',
          (p) => !p.canAnywhere(Capability.reportsPrint),
        );
        p7Say(
          'lost-during-print',
          'Print: Microsoft Print to PDF, Print; if Windows asks where to save, '
              'save as ${p7Path('lost-during-print.pdf')}',
        );
        await pumpUntil(tester, 'the print dialog to close', () {
          final s = container.read(exportActionProvider);
          return !s.isRunning && !identical(s.last, beforePrint);
        }, timeout: const Duration(minutes: 15));
        await tester.pump(const Duration(seconds: 5));
        final lostPrint = container.read(exportActionProvider).last!.result;
        debugPrint(
          'P7 LOST DURING PRINT: $lostPrint; printed file exists: '
          '${File(p7Path('lost-during-print.pdf')).existsSync()}',
        );
        await p7Host(tester, 'restore reports.print to accountant', 'restored');
        // Microsoft Print to PDF creates its output file when the job starts, before the
        // document is asked for, and leaves it empty when the job is aborted. No report
        // content may reach it (accepted by the project lead, D-309).
        final printedFile = File(p7Path('lost-during-print.pdf'));
        expect(
          !printedFile.existsSync() || printedFile.lengthSync() == 0,
          isTrue,
          reason: 'nothing is printed for a person who lost reports.print',
        );
        expect(lostPrint, isA<ExportActionAbandoned>());
        p7Say('done', 'authority phase finished');
      } finally {
        await _admin.revokeScope('accountant@example.com', 'HKI');
        if (container.read(principalProvider).userId != ownerId) {
          container = await p6SignIn(tester, 'giridhar@hki.com');
        }
        await p6SweepAfter(client);
      }
    });
  });

  // A save that follows a print, or that is made offline: reduced to one variable at a
  // time, after the full export phase stopped responding at that point (Slice 10).
  const p7Repro = String.fromEnvironment('P7_REPRO');
  group('p7-windows-repro', skip: _phase != 'p7-windows-repro', () {
    testWidgets('repro: $p7Repro', (tester) async {
      Directory(p7Out).createSync(recursive: true);
      await launch(tester, recorders: p7Recorders());
      final container = await p6SignIn(tester, 'giridhar@hki.com');
      final client = Supabase.instance.client;
      await sweepPnlFixtures(client, marker: p6Marker);
      try {
        await p6Fixtures(client);
        await openPnl(tester, container);
        await chooseCustom(tester, container, p6From.iso, p6To.iso);
        await refreshPnl(tester, container);
        await p7OpenExportCentre(tester);
        // `x3` in the variant repeats the print, to show whether the save survives
        // several print dialogs rather than one.
        final prints = int.parse(
          RegExp(r'x(\d+)').firstMatch(p7Repro)?.group(1) ?? '1',
        );
        for (var n = 0; p7Repro.contains('print') && n < prints; n++) {
          final r = await p7Act(
            tester,
            container,
            'export-profitAndLoss-print',
            p7Repro.contains('printcancel')
                ? 'repro print cancel'
                : 'repro print',
            'Print Setup OK; save as ${p7Path('repro-printed.pdf')}',
          );
          debugPrint('P7 REPRO print: $r');
        }
        if (p7Repro.contains('offline')) _transport.online = false;
        final r = await p7Act(
          tester,
          container,
          'export-profitAndLoss-pdf',
          'repro save',
          'Save As: ${p7Path('repro-saved.pdf')}',
        );
        debugPrint('P7 REPRO save: $r');
        expect(r, isA<ExportActionSaved>());
      } finally {
        _transport.online = true;
        await p6SweepAfter(client);
      }
    });
  });

  // ── Phase 7 Slice 10 — the P&L PDF share on a real phone ──────────────────────
  //
  // Run on the Galaxy A06 over USB only (D-288). The system share sheet is outside the
  // application, so the operator answers it over adb. The phase prints `P7PHONE STEP …`
  // and waits for the operator to write the same step name, plus `:done`, into
  // `<app files>/p7host.json` (`adb shell run-as <package> …`).
  Future<void> p7PhoneStep(
    WidgetTester tester,
    String hostFile,
    String step,
    String instruction,
  ) async {
    debugPrint('P7PHONE STEP $step :: $instruction');
    await pumpUntil(tester, 'the operator to finish $step', () {
      try {
        return File(hostFile).readAsStringSync().contains('$step:done');
      } on Object {
        return false;
      }
    }, timeout: const Duration(minutes: 20));
  }

  List<File> p7Shared(Directory cache) {
    final folder = Directory('${cache.path}/share');
    if (!folder.existsSync()) return const [];
    return [
      for (final e in folder.listSync())
        if (e is File) e,
    ];
  }

  Future<void> p7PhoneShare(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final before = container.read(exportActionProvider).last;
    await centrePnlControl(tester, find.byKey(const Key('pnl-share-pdf')));
    await tapWhenHittable(tester, find.byKey(const Key('pnl-share-pdf')));
    await pumpUntil(tester, 'the share to hand over', () {
      final s = container.read(exportActionProvider);
      return !s.isRunning && !identical(s.last, before);
    }, timeout: const Duration(minutes: 2));
  }

  group('p7-android-share', skip: _phase != 'p7-android-share', () {
    testWidgets('the phone shares the P&L PDF from its private cache, offline too, only with '
        'reports.export, and offers no Excel, print or Export Centre', (tester) async {
      expect(s11Phone(), isTrue, reason: 'run on the Galaxy A06');
      final hostFile =
          '${(Platform.isWindows ? Directory.systemTemp : await getApplicationSupportDirectory()).path}/p7host.json';
      final cache = await exportShareCacheRoot();
      debugPrint('P7PHONE PATHS host=$hostFile cache=${cache.path}');
      await launch(tester);
      var container = await s11SignIn(tester, 'giridhar@hki.com');
      final ownerId = container.read(principalProvider).userId;
      final client = Supabase.instance.client;
      await sweepPnlFixtures(client, marker: p6Marker);
      try {
        await p6Fixtures(client);
        await openPhonePnl(tester, container);
        await choosePhoneCustom(tester, container, p6From, p6To);
        await refreshPhonePnl(tester, container);
        final pnl = computedPnl(container);

        // Only the P&L share: no Excel, no print, no Export Centre on a phone.
        expect(find.byKey(const Key('pnl-share-pdf')), findsOneWidget);
        expect(find.byKey(const Key('export-centre')), findsNothing);
        expect(find.textContaining('Save Excel'), findsNothing);
        expect(find.byIcon(Icons.print_outlined), findsNothing);
        expect(find.byIcon(Icons.table_chart_outlined), findsNothing);

        // ── Share one: the sheet opens; the file is in the private cache ──────
        await p7PhoneShare(tester, container);
        expect(
          container.read(exportActionProvider).last!.result,
          isA<ExportActionHandedOver>(),
        );
        var shared = p7Shared(cache);
        debugPrint('P7PHONE SHARED ${[for (final f in shared) f.path]}');
        expect(shared, hasLength(1));
        final first = shared.single;
        expect(first.path, startsWith(cache.path), reason: 'private cache');
        expect(
          first.uri.pathSegments.last,
          'KrishnaImperialMIS_ProfitAndLoss_Consolidated_2027-03-01_2027-03-31.pdf',
        );
        final text = PdfText.read(
          inflatePdfStreams(first.readAsBytesSync()),
        ).lines.join('\n');
        for (final m in [
          pnl.grossSales,
          pnl.gst,
          pnl.netSales,
          pnl.expenses,
          pnl.operatingProfit,
        ]) {
          expect(text, contains(MoneyFormatter.standard.format(m)));
        }
        expect(text, contains('Both properties (consolidated)'));
        expect(text, contains('1 Mar 2027 – 31 Mar 2027'));
        expect(text, contains('Synchronised as of'));
        expect(text, contains('₹'));
        final firstModified = first.lastModifiedSync();
        await p7PhoneStep(
          tester,
          hostFile,
          'share1',
          'the share sheet is open: inspect it, then press Back (cancel)',
        );
        await tester.pump(const Duration(seconds: 2));

        // ── Share two, offline: the earlier file goes before the new one ──────
        _transport.online = false;
        await tester.pump(const Duration(seconds: 2));
        await p7PhoneShare(tester, container);
        expect(
          container.read(exportActionProvider).last!.result,
          isA<ExportActionHandedOver>(),
          reason: 'a complete cached report shares offline',
        );
        shared = p7Shared(cache);
        expect(shared, hasLength(1), reason: 'the earlier export was removed');
        expect(
          shared.single.lastModifiedSync().isAfter(firstModified) ||
              shared.single.lastModifiedSync() == firstModified,
          isTrue,
        );
        await p7PhoneStep(
          tester,
          hostFile,
          'share2',
          'offline share sheet open: press Back',
        );
        _transport.online = true;

        // ── Leaving the P&L and opening it again ───────────────────────────────
        await p6OpenOverview(tester, container);
        await openPhonePnl(tester, container);
        await tester.pump(const Duration(seconds: 2));
        debugPrint(
          'P7PHONE AFTER RE-ENTRY ${[for (final f in p7Shared(cache)) f.path]}',
        );

        // ── Sign-out takes the shared PDF with it (D-310) ──────────────────────
        expect(p7Shared(cache), isNotEmpty, reason: 'shared, then signed out');
        await signOutThroughTheUi(tester);
        await pumpUntil(
          tester,
          'sign-out to remove the shared PDF',
          () => p7Shared(cache).isEmpty,
          timeout: const Duration(seconds: 20),
        );
        debugPrint('P7PHONE AFTER SIGN-OUT ${p7Shared(cache)}');

        // ── The Manager bundle: reads the P&L, is offered no share (D-292) ────
        container = await s11SignIn(tester, 'ccr.manager@example.com');
        await openPhonePnl(tester, container);
        await choosePhoneCustom(tester, container, p6From, p6To);
        await refreshPhonePnl(tester, container);
        expect(container.read(pnlViewProvider).value, isA<PnlReportView>());
        expect(find.byKey(const Key('pnl-share-pdf')), findsNothing);

        // ── The Accountant, then reports.export taken away ─────────────────────
        await signOutThroughTheUi(tester);
        container = await s11SignIn(tester, 'accountant@example.com');
        await openPhonePnl(tester, container);
        await choosePhoneCustom(tester, container, p6From, p6To);
        await refreshPhonePnl(tester, container);
        expect(find.byKey(const Key('pnl-share-pdf')), findsOneWidget);
        await p7PhoneStep(
          tester,
          hostFile,
          'remove-export',
          'HOST: remove reports.export from the accountant role',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'the accountant without reports.export',
          (p) => !p.canAnywhere(Capability.reportsExport),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(
          find.byKey(const Key('pnl-share-pdf')),
          findsNothing,
          reason: 'a lost capability takes the share away',
        );
        await p7PhoneStep(
          tester,
          hostFile,
          'restore-export',
          'HOST: restore reports.export to the accountant role',
        );
        await s11AuthorityUntil(
          tester,
          container,
          'reports.export back',
          (p) => p.canAnywhere(Capability.reportsExport),
        );
        expect(find.byKey(const Key('pnl-share-pdf')), findsOneWidget);

        // ── The Accountant shares, then the session changes hands (D-310) ─────
        await p7PhoneShare(tester, container);
        expect(
          container.read(exportActionProvider).last!.result,
          isA<ExportActionHandedOver>(),
        );
        expect(p7Shared(cache), hasLength(1));
        await p7PhoneStep(
          tester,
          hostFile,
          'share3',
          "the accountant's share sheet is open: press Back",
        );
        await signOutThroughTheUi(tester);
        await pumpUntil(
          tester,
          "sign-out to remove the accountant's shared PDF",
          () => p7Shared(cache).isEmpty,
          timeout: const Duration(seconds: 20),
        );
        // A file left from the previous person, as if the app had stopped before
        // sign-out finished, and an unrelated file beside it.
        final share = Directory('${cache.path}/share')
          ..createSync(recursive: true);
        final leftover = File(
          '${share.path}/KrishnaImperialMIS_ProfitAndLoss_Leftover.pdf',
        )..writeAsBytesSync([1, 2, 3]);
        final unrelated = File('${share.path}/unrelated.txt')
          ..writeAsStringSync('not ours');
        container = await s11SignIn(tester, 'giridhar@hki.com');
        await pumpUntil(
          tester,
          'the next person to remove the previous file',
          () => !leftover.existsSync(),
          timeout: const Duration(seconds: 20),
        );
        expect(unrelated.existsSync(), isTrue, reason: 'only our PDFs go');
        unrelated.deleteSync();
        debugPrint('P7PHONE SWITCH CLEANED ${p7Shared(cache)}');
        debugPrint('P7PHONE DONE');
      } finally {
        _transport.online = true;
        if (container.read(principalProvider).userId != ownerId) {
          container = await s11SignIn(tester, 'giridhar@hki.com');
        }
        await p6SweepAfter(client);
      }
    });
  });

  // ── Phase 8 Slice 8: integrated acceptance ─────────────────────────────────────
  //
  // Five phases for what no earlier phase covers. None touches the machine's ordinary
  // application data folder (D-247): the recovery and migration phases work in their own
  // disposable folders with an in-memory key store, and every other phase uses the
  // harness's isolated installation.

  /// Every piece of text on screen, for the "no technical text" assertions.
  List<String> p8Texts(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
    for (final t in tester.widgetList<EditableText>(find.byType(EditableText)))
      t.controller.text,
  ];

  /// Raw technical detail a person must never be shown (D-329).
  void p8ExpectPlainWords(WidgetTester tester, List<String> forbidden) {
    final shown = p8Texts(tester).join('\n');
    for (final f in [
      'Sqlite',
      'SQLITE',
      'sqlite',
      'drift',
      'Drift',
      'Exception',
      'database is locked',
      'not a database',
      'StackTrace',
      ...forbidden,
    ]) {
      expect(shown, isNot(contains(f)), reason: 'raw text on screen: $f');
    }
  }

  Directory p8Disposable(String name) => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'krishna_mis_p8_${name}_${DateTime.now().millisecondsSinceEpoch}',
  )..createSync(recursive: true);

  String p8Digest(File file) {
    final bytes = file.readAsBytesSync();
    var h = 0;
    for (final b in bytes) {
      h = (h * 31 + b) & 0x3fffffff;
    }
    return '${bytes.length}:$h';
  }

  // ── p8-revenue-ledger: D-331 in the running application ───────────────────────

  group('p8-revenue-ledger', skip: _phase != 'p8-revenue-ledger', () {
    testWidgets('a sync-state filter reaches every matching sale, page by page, in the '
        'real application', (tester) async {
      await launch(tester);
      final container = await p6SignIn(tester, 'giridhar@hki.com');
      final ownerId = container.read(principalProvider).userId;
      final db = boot.database;

      // A local fixture: 60 synced sales in front of 75 conflicts, so the conflicts
      // start beyond the first page and run past the second. Local only, keyed
      // `p8fix-`, and removed in `finally`; nothing here reaches the server.
      final org =
          (await db
                      .customSelect(
                        'SELECT org_id FROM business_units WHERE id = ?',
                        variables: [Variable<String>(_ccr)],
                      )
                      .getSingle())
                  .data['org_id']!
              as String;
      Future<String> category(String unit) async =>
          (await db
                      .customSelect(
                        'SELECT id FROM revenue_categories WHERE business_unit_id = ? '
                        'AND archived_at IS NULL ORDER BY code LIMIT 1',
                        variables: [Variable<String>(unit)],
                      )
                      .getSingle())
                  .data['id']!
              as String;
      final ccrCategory = await category(_ccr);
      final hkiCategory = await category(_hki);

      Future<void> clean() async {
        await db.customStatement(
          "DELETE FROM sync_outbox WHERE mutation_id LIKE 'p8fix-%'",
        );
        await db.customStatement(
          "DELETE FROM revenue_components WHERE revenue_entry_id LIKE 'p8fix-%'",
        );
        await db.customStatement(
          "DELETE FROM revenue_entries WHERE id LIKE 'p8fix-%'",
        );
      }

      await clean();
      final fixtureConflicts = <String>{};
      try {
        await db.transaction(() async {
          for (var i = 0; i < 135; i++) {
            final conflict = i < 75;
            final id = 'p8fix-${i.toString().padLeft(4, '0')}';
            final date = conflict
                ? '2027-02-${(1 + i % 28).toString().padLeft(2, '0')}'
                : '2027-03-${(1 + i % 28).toString().padLeft(2, '0')}';
            final hki = i % 3 == 0;
            await db.customStatement(
              'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
              'revenue_category_id, business_date, pnl_period_key, captured_at, '
              'entry_kind, created_by, txn_number, financial_year, '
              'pending_mutation_id, row_version, updated_at) '
              "VALUES (?, ?, ?, ?, ?, ?, ?, 'daily_summary', ?, ?, '2026-27', ?, 1, ?)",
              [
                id,
                org,
                hki ? _hki : _ccr,
                hki ? hkiCategory : ccrCategory,
                date,
                date.substring(0, 7),
                '${date}T10:00:00.000Z',
                ownerId,
                'KI-REV-P8-${i.toString().padLeft(6, '0')}',
                conflict ? id : null,
                '2026-10-02T00:00:00.000Z',
              ],
            );
            await db.customStatement(
              'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
              'entered_amount_minor, entered_basis, gross_amount_minor, '
              'tax_amount_minor, net_amount_minor, tax_rule_id, '
              'tax_rate_basis_points, tax_treatment) '
              "VALUES (?, ?, ?, 105000, 'inclusive_total', 105000, 5000, 100000, "
              "'p8-rule', 500, 'inclusive')",
              ['$id-c0', org, id],
            );
            if (conflict) {
              fixtureConflicts.add(id);
              await db.customStatement(
                'INSERT INTO sync_outbox (mutation_id, actor_user_id, entity_type, '
                'entity_id, op, payload, next_attempt_at, status, created_at, '
                'attempt_count) '
                "VALUES (?, ?, ?, ?, 'update', '{}', ?, 'conflict', ?, 0)",
                [
                  id,
                  ownerId,
                  revenueEntityType,
                  id,
                  '2026-10-02T00:00:00.000Z',
                  '2026-10-02T00:00:00.000Z',
                ],
              );
            }
          }
        });

        final repository = RevenueRepository(db);
        final scope = container.read(revenueFilterProvider).businessUnitIds;
        final conflictFilter = RevenueFilter(
          businessUnitIds: scope,
          syncState: SyncState.conflict,
        );
        final expectedAll = <String>[];
        for (var page = 0; ; page++) {
          final rows = await repository.query(
            conflictFilter,
            limit: revenuePageSize,
            offset: page * revenuePageSize,
          );
          expectedAll.addAll(rows.map((r) => r.id));
          if (rows.length < revenuePageSize) break;
        }
        debugPrint(
          'P8 LEDGER conflicts in scope: ${expectedAll.length} '
          '(fixture ${fixtureConflicts.length})',
        );
        expect(expectedAll.toSet().containsAll(fixtureConflicts), isTrue);

        List<String> shown() => [
          for (final r in container.read(filteredRevenueProvider).value ?? [])
            r.id,
        ];

        final seen = <String>[];
        if (p6Phone()) {
          // The phone has no Sales ledger page; the same providers run in this process.
          container
              .read(revenueFilterProvider.notifier)
              .update(
                container
                    .read(revenueFilterProvider)
                    .copyWith(syncState: SyncState.conflict),
              );
          final keepAlive = [
            container.listen(filteredRevenueProvider, (_, _) {}),
            container.listen(revenueHasMoreProvider, (_, _) {}),
          ];
          for (var page = 0; ; page++) {
            await pumpUntil(
              tester,
              'conflict page ${page + 1}',
              () =>
                  container.read(revenuePageProvider) == page &&
                  container.read(filteredRevenueProvider).hasValue &&
                  !container.read(filteredRevenueProvider).isLoading &&
                  container.read(revenueHasMoreProvider).hasValue &&
                  !container.read(revenueHasMoreProvider).isLoading,
            );
            expect(
              shown(),
              expectedAll.skip(page * revenuePageSize).take(revenuePageSize),
            );
            seen.addAll(shown());
            if (!container.read(revenueHasMoreProvider).value!) break;
            container.read(revenuePageProvider.notifier).next();
          }
          for (final s in keepAlive) {
            s.close();
          }
        } else {
          await openRevenueLedger(tester);
          final status = find.byKey(const Key('revenue-filter-status'));
          await tester.ensureVisible(status);
          await tapWhenHittable(tester, status);
          await tester.pump(const Duration(milliseconds: 600));
          await tapWhenHittable(
            tester,
            find.text(SyncState.conflict.label).last,
          );
          for (var page = 0; ; page++) {
            await pumpUntil(
              tester,
              'conflict page ${page + 1} on screen',
              () =>
                  container.read(revenueFilterProvider).syncState ==
                      SyncState.conflict &&
                  showsText('Page ${page + 1}') &&
                  container.read(filteredRevenueProvider).hasValue &&
                  !container.read(filteredRevenueProvider).isLoading &&
                  container.read(revenueHasMoreProvider).hasValue &&
                  !container.read(revenueHasMoreProvider).isLoading,
            );
            final ids = shown();
            expect(
              ids,
              expectedAll.skip(page * revenuePageSize).take(revenuePageSize),
              reason: 'page ${page + 1} is the canonical continuation',
            );
            expect(
              find.byKey(Key('revenue-ledger-row-${ids.first}')),
              findsOneWidget,
              reason: 'the page is on screen',
            );
            seen.addAll(ids);
            final next = tester.widget<IconButton>(
              find.byKey(const Key('revenue-page-next')),
            );
            if (next.onPressed == null) break;
            await tapWhenHittable(
              tester,
              find.byKey(const Key('revenue-page-next')),
            );
          }
          // Clearing the filters returns to the whole ledger, from page one.
          await tapWhenHittable(
            tester,
            find.byKey(const Key('revenue-filter-reset')),
          );
          await pumpUntil(
            tester,
            'the whole ledger again',
            () =>
                container.read(revenueFilterProvider).syncState == null &&
                showsText('Page 1') &&
                container.read(filteredRevenueProvider).hasValue &&
                !container.read(filteredRevenueProvider).isLoading,
          );
          final whole = await repository.query(
            RevenueFilter(businessUnitIds: scope),
            limit: revenuePageSize,
          );
          expect(shown(), whole.map((r) => r.id).toList());
        }

        expect(seen, expectedAll, reason: 'every conflict, in order');
        expect(seen.toSet(), hasLength(seen.length), reason: 'no duplicate');
        expect(seen.length, greaterThan(revenuePageSize));
        debugPrint('P8 LEDGER walked ${seen.length} conflicts across pages');
      } finally {
        await clean();
      }
    });
  });

  // ── p8-double-submit: D-326 in the running application ────────────────────────

  group('p8-double-submit', skip: _phase != 'p8-double-submit', () {
    testWidgets('a second Save press before the next frame records nothing more, for a '
        'sale and for an expense', (tester) async {
      await launch(tester);
      await p6SignIn(tester, 'giridhar@hki.com');
      final client = Supabase.instance.client;
      final stamp = DateTime.now().millisecondsSinceEpoch;

      // ── A sale ─────────────────────────────────────────────────────────────
      final saleMarker = '$_acceptanceMarker p8 double sale $stamp';
      if (p6Phone()) {
        await openRevenueEntry(tester);
      } else {
        await openRevenueLedger(tester);
        await revealAndTap(tester, const Key('add-revenue'));
        await tester.pump(const Duration(milliseconds: 900));
        await pumpUntil(
          tester,
          'the sales entry screen',
          () => visible('Sales category') || visible('Property'),
        );
      }
      final unitChip = find.byKey(const Key('revenue-unit-CCR'));
      if (unitChip.evaluate().isNotEmpty) {
        await tester.tap(unitChip);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await pumpUntil(
        tester,
        'the Restaurant category',
        () => find
            .byKey(const Key('revenue-category-RESTAURANT'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('revenue-category-RESTAURANT')));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pump(const Duration(milliseconds: 400));
      await openRevenueMoreDetails(tester);
      await tester.enterText(
        find.byKey(const Key('revenue-notes')),
        saleMarker,
      );
      await tester.pump(const Duration(milliseconds: 400));

      final salesBefore = await RevenueRepository(boot.database).list();
      final saveSale = find.byKey(const Key('revenue-save'));
      if (saveSale.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          saveSale,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
      }
      await tester.ensureVisible(saveSale);
      await pumpUntil(
        tester,
        'Save to be hittable',
        () => saveSale.hitTestable().evaluate().isNotEmpty,
      );
      // Two presses with no frame between them: what a janking device delivers.
      await tester.tap(saveSale.hitTestable());
      await tester.tap(saveSale.hitTestable());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: 'nothing escaped');
      final salesAfter = await RevenueRepository(boot.database).list();
      final newSales = salesAfter
          .where((r) => !salesBefore.any((b) => b.id == r.id))
          .toList();
      expect(newSales, hasLength(1), reason: 'two presses, one sale');
      if (p6Phone()) {
        await syncRevenueUntilNumbered(tester, newSales.single.id);
      } else {
        await syncRevenueOnWindows(tester, newSales.single.id);
      }
      final serverSales = await client
          .from('revenue_document')
          .select('id')
          .like('notes', saleMarker);
      expect(serverSales, hasLength(1), reason: 'one sale on the server');
      debugPrint('P8 DOUBLE SALE: 1 local, 1 server');

      // ── An expense ─────────────────────────────────────────────────────────
      for (var i = 0; i < 4; i++) {
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        if (!nav.canPop()) break;
        nav.pop();
        await tester.pump(const Duration(milliseconds: 700));
      }
      final expenseNote = 'p8 double expense $stamp';
      if (!p6Phone()) {
        // The sale left Transactions on its Sales tab; the expense action is on the
        // Expenses tab.
        await tester.tap(find.text('Transactions').last);
        await tester.pump(const Duration(milliseconds: 600));
        await pumpUntil(
          tester,
          'the Expenses / Sales tabs',
          () =>
              find.byKey(const Key('transactions-tabs')).evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Expenses').last);
        await tester.pump(const Duration(milliseconds: 800));
      }
      await openExpenseEntry(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '777');
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the notes field',
        () => find.byKey(const Key('expense-notes')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('expense-notes')),
        '$_acceptanceMarker: $expenseNote',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await openMoreDetails(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await classify(tester, const [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Vegetables & Fruits',
      ]);
      await pumpUntil(tester, 'Save to be enabled', () => saveEnabled(tester));

      final expensesBefore =
          (await boot.database.select(boot.database.expenses).get())
              .map((e) => e.id)
              .toSet();
      Future<List<String>> createdExpenses() async =>
          (await boot.database.select(boot.database.expenses).get())
              .map((e) => e.id)
              .where((id) => !expensesBefore.contains(id))
              .toList();
      final saveExpense = find.byKey(const Key('save-expense'));
      await pumpUntil(
        tester,
        'Save to be hittable',
        () => saveExpense.hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(saveExpense.hitTestable());
      await tester.tap(saveExpense.hitTestable());
      var created = <String>[];
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline) && created.isEmpty) {
        await tester.pump(const Duration(milliseconds: 250));
        created = await createdExpenses();
      }
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: 'nothing escaped');
      created = await createdExpenses();
      expect(created, hasLength(1), reason: 'two presses, one expense');
      await syncAndAwaitNumber(tester, created.single);
      final serverExpenses = await client
          .from('expense_document')
          .select('id')
          .like('notes', '%$expenseNote%');
      expect(serverExpenses, hasLength(1), reason: 'one expense on the server');
      debugPrint('P8 DOUBLE EXPENSE: 1 local, 1 server');
    });
  });

  // ── p8-recovery: the start-up failure and reset screens, for real ─────────────

  group('p8-recovery', skip: _phase != 'p8-recovery', () {
    testWidgets(
      'a lock offers Try again only; damaged data offers a reset behind typed '
      'RESET; cancel changes nothing; the data is set aside, not erased; a failed '
      'restart stays recoverable',
      (tester) async {
        final dir = p8Disposable('recovery');
        final dbFile = File(
          '${dir.path}${Platform.pathSeparator}krishna_mis.db',
        );
        final storage = InMemorySecretStorage();
        const keyName = 'krishna_mis.p8-recovery.db_key.v1';
        DatabaseKeyManager keys() =>
            DatabaseKeyManager(storage: storage, keyName: keyName);

        final current = ValueNotifier<Widget>(const SizedBox());
        sq.Database? lockHolder;
        Object? failNextBoot;
        AppDatabase? started;
        final runner = StartupRunner(
          boot: () async {
            final failure = failNextBoot;
            failNextBoot = null;
            if (failure != null) throw failure;
            started = await openLocalStore(keyManager: keys(), directory: dir);
            return boot;
          },
          run: (widget) => current.value = widget,
          appFor: (_) => const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('P8 started', key: Key('p8-started'))),
            ),
          ),
          recoveryFor: (failure) async => LocalStoreRecoveryActions(
            LocalStoreRecovery(directory: dir, keyManager: keys()),
            reason: failure.kind,
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder<Widget>(
            valueListenable: current,
            builder: (_, widget, _) => widget,
          ),
        );
        bool has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;
        Future<void> settleOn(String key) =>
            pumpUntil(tester, 'the $key screen', () => has(key));
        Future<void> closeStarted() async {
          await started?.close();
          started = null;
        }

        String title() => tester
            .widget<Text>(find.byKey(const Key('startup-failure-title')))
            .data!;
        String reference() => tester
            .widget<Text>(find.byKey(const Key('startup-failure-reference')))
            .data!;

        try {
          // ── A healthy start, to have a real encrypted file ─────────────────────
          await runner.start();
          await settleOn('p8-started');
          await closeStarted();

          // ── Another holder of the file: in use, retry only ─────────────────────
          final holder = sq.sqlite3.open(dbFile.path);
          applyEncryptionKey(holder, (await storage.read(key: keyName))!);
          holder.execute('BEGIN EXCLUSIVE');
          lockHolder = holder;
          await runner.start();
          await tester.pump(const Duration(milliseconds: 500));
          debugPrint(
            'P8 RECOVERY under lock: opened=${started != null} '
            'screen=${p8Texts(tester).take(6).join(' | ')}',
          );
          await settleOn('startup-failure-title');
          expect(has('startup-try-again'), isTrue);
          expect(
            has('startup-open-reset'),
            isFalse,
            reason: 'a lock is not damage',
          );
          p8ExpectPlainWords(tester, [dir.path]);
          debugPrint('P8 RECOVERY in use: ${title()} | ${reference()}');
          holder.execute('ROLLBACK');
          holder.close();
          lockHolder = null;
          await tapWhenHittable(
            tester,
            find.byKey(const Key('startup-try-again')),
          );
          await settleOn('p8-started');
          await closeStarted();

          // ── Damaged bytes: reset offered, behind typed RESET ──────────────────
          for (final suffix in ['-wal', '-shm']) {
            final side = File('${dbFile.path}$suffix');
            if (side.existsSync()) side.deleteSync();
          }
          dbFile.writeAsBytesSync(
            List<int>.generate(65536, (i) => (i * 7919 + 13) & 0xff),
          );
          final damaged = p8Digest(dbFile);
          await runner.start();
          await settleOn('startup-open-reset');
          expect(has('startup-try-again'), isTrue);
          p8ExpectPlainWords(tester, [dir.path]);
          debugPrint('P8 RECOVERY damaged: ${title()} | ${reference()}');

          await tapWhenHittable(
            tester,
            find.byKey(const Key('startup-open-reset')),
          );
          await settleOn('reset-confirmation-field');
          String statement() => tester
              .widget<Text>(find.byKey(const Key('reset-unsynced-statement')))
              .data!;
          await pumpUntil(
            tester,
            'the unsent-work statement',
            () => !statement().startsWith('Checking'),
          );
          expect(
            statement(),
            contains('may be lost'),
            reason: 'unreadable data is never "nothing to lose"',
          );
          FilledButton confirm() => tester.widget<FilledButton>(
            find.byKey(const Key('reset-confirm')),
          );
          expect(confirm().onPressed, isNull, reason: 'nothing typed');
          await tester.enterText(
            find.byKey(const Key('reset-confirmation-field')),
            'reset',
          );
          await tester.pump();
          expect(confirm().onPressed, isNull, reason: 'lower case is refused');
          await tester.enterText(
            find.byKey(const Key('reset-confirmation-field')),
            'RESET ',
          );
          await tester.pump();
          expect(
            confirm().onPressed,
            isNotNull,
            reason: 'RESET, spaces ignored',
          );

          // Cancel: nothing moves.
          await tapWhenHittable(tester, find.byKey(const Key('reset-cancel')));
          await settleOn('startup-open-reset');
          await tester.pump(const Duration(milliseconds: 500));
          expect(p8Digest(dbFile), damaged, reason: 'cancel changed nothing');
          final recoveryDir = Directory(
            '${dir.path}${Platform.pathSeparator}recovery',
          );
          expect(
            recoveryDir.existsSync() && recoveryDir.listSync().isNotEmpty,
            isFalse,
            reason: 'nothing set aside on cancel',
          );

          // Confirm, and make the restart after it fail too.
          await tapWhenHittable(
            tester,
            find.byKey(const Key('startup-open-reset')),
          );
          await settleOn('reset-confirmation-field');
          await tester.enterText(
            find.byKey(const Key('reset-confirmation-field')),
            'RESET',
          );
          await tester.pump();
          failNextBoot = FileSystemException('p8 simulated failure', dir.path);
          await tapWhenHittable(tester, find.byKey(const Key('reset-confirm')));
          await pumpUntil(
            tester,
            'the failed restart to be shown',
            () =>
                has('startup-failure-title') &&
                !has('reset-confirmation-field'),
          );
          expect(has('startup-try-again'), isTrue);
          expect(
            has('startup-open-reset'),
            isFalse,
            reason: 'a storage failure is not damage',
          );
          p8ExpectPlainWords(tester, [dir.path, 'p8 simulated']);
          debugPrint('P8 RECOVERY failed restart: ${title()} | ${reference()}');

          final quarantine = recoveryDir
              .listSync()
              .whereType<Directory>()
              .single;
          final setAside = File(
            '${quarantine.path}${Platform.pathSeparator}krishna_mis.db',
          );
          expect(setAside.existsSync(), isTrue, reason: 'set aside');
          expect(p8Digest(setAside), damaged, reason: 'the same bytes, moved');
          expect(
            dbFile.existsSync(),
            isFalse,
            reason: 'no active database yet',
          );
          final record = File(
            '${quarantine.path}${Platform.pathSeparator}recovery.json',
          ).readAsStringSync();
          // The key is kept aside under its own entry, named for the folder (D-330).
          final id = quarantine.path
              .split(Platform.pathSeparator)
              .last
              .substring('quarantine-'.length);
          final keptKey = await storage.read(key: '$keyName.quarantine.$id');
          expect(keptKey, isNotNull, reason: 'the key is set aside too');
          expect(record, isNot(contains(keptKey!)), reason: 'no key in it');
          expect(
            await storage.read(key: keyName),
            isNull,
            reason: 'key set aside',
          );

          // Try again: a fresh, empty database at the current schema.
          await tapWhenHittable(
            tester,
            find.byKey(const Key('startup-try-again')),
          );
          await settleOn('p8-started');
          final version = await started!
              .customSelect('PRAGMA user_version')
              .getSingle();
          expect(version.data.values.single, started!.schemaVersion);
          final outbox = await started!
              .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
              .getSingle();
          expect(outbox.data['n'], 0, reason: 'nothing of the old data');
          debugPrint(
            'P8 RECOVERY reset: set aside to ${quarantine.path.split(Platform.pathSeparator).last} '
            '(its key kept aside); fresh v${version.data.values.single}',
          );
          await closeStarted();
        } finally {
          try {
            lockHolder?.execute('ROLLBACK');
          } on Object {
            // nothing open
          }
          lockHolder?.close();
          await closeStarted();
          try {
            dir.deleteSync(recursive: true);
          } on Object {
            debugPrint('P8 RECOVERY could not remove ${dir.path}');
          }
        }
      },
    );
  });

  // ── p8-migration: v21 → v22 on a production-shaped copy ───────────────────────

  group('p8-migration', skip: _phase != 'p8-migration', () {
    testWidgets(
      "a copy of this installation's synced database, taken back to v21, "
      'upgrades to v22 in the running application and keeps every row',
      (tester) async {
        await launch(tester);
        final container = await p6SignIn(tester, 'giridhar@hki.com');
        // The reporting cache too, so the copy is what a working device holds. A phone
        // reaches the P&L through Reports, the desktop through Analytics.
        if (s11Phone()) {
          await openPhonePnl(tester, container);
          await refreshPhonePnl(tester, container);
        } else {
          await openPnl(tester, container);
          await refreshPnl(tester, container);
        }

        final dir = p8Disposable('migration');
        final storage = InMemorySecretStorage();
        DatabaseKeyManager keys() => DatabaseKeyManager(
          storage: storage,
          keyName: 'krishna_mis.p8-mig.v1',
        );
        const v22Indexes = [
          'ix_expense_allocations_expense',
          'ix_expense_period_allocations_expense',
          'ix_expense_attachments_expense',
          'ix_expenses_ledger',
        ];
        try {
          final target = await openLocalStore(
            keyManager: keys(),
            directory: dir,
          );
          final tables = [
            for (final r
                in await target
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table' "
                      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
                    )
                    .get())
              r.data['name']! as String,
          ];
          final counts = <String, int>{};
          await target.customStatement('PRAGMA foreign_keys = OFF');
          await target.transaction(() async {
            for (final t in tables) {
              await target.customStatement('DELETE FROM "$t"');
              final rows = await boot.database
                  .customSelect('SELECT * FROM "$t"')
                  .get();
              for (final r in rows) {
                final cols = r.data.keys.toList();
                await target.customStatement(
                  'INSERT INTO "$t" (${cols.map((c) => '"$c"').join(', ')}) '
                  'VALUES (${List.filled(cols.length, '?').join(', ')})',
                  [for (final c in cols) r.data[c]],
                );
              }
              counts[t] = rows.length;
            }
          });
          await target.customStatement('PRAGMA foreign_keys = ON');
          // Sign-out purges financial documents from this installation, so add the
          // CURRENT-shaped expense ledger (2,276 documents with lines, period rows,
          // attachments and queued work) the v22 indexes exist to serve (D-323).
          final orgId =
              (await target
                          .customSelect(
                            'SELECT org_id FROM business_units LIMIT 1',
                          )
                          .getSingle())
                      .data['org_id']!
                  as String;
          final seeded = await wl.seedExpenseLedgerFixture(
            target,
            documents: wl.LedgerDatasetClass.current.documents,
            years: 1,
            orgId: orgId,
          );
          debugPrint('P8 MIGRATION added the CURRENT expense ledger: $seeded');
          for (final t in const [
            'expenses',
            'expense_allocations',
            'expense_period_allocations',
            'expense_attachments',
            'sync_outbox',
          ]) {
            counts[t] =
                (await target
                            .customSelect('SELECT COUNT(*) AS n FROM "$t"')
                            .getSingle())
                        .data['n']!
                    as int;
          }
          final firstPageBeforeUpgrade = await ExpenseRepository(
            target,
          ).query(const ExpenseFilter(), limit: 50);
          expect(firstPageBeforeUpgrade, hasLength(50));
          final total = counts.values.fold<int>(0, (a, b) => a + b);
          debugPrint(
            'P8 MIGRATION copied $total rows over ${tables.length} tables: '
            'expenses ${counts['expenses']}, revenue ${counts['revenue_entries']}, '
            'reporting ${(counts['reporting_revenue_contributions'] ?? 0) + (counts['reporting_expense_contributions'] ?? 0)}',
          );
          expect(total, greaterThan(0));

          // Back to v21: v22 added exactly these four indexes (D-323).
          for (final index in v22Indexes) {
            await target.customStatement('DROP INDEX IF EXISTS $index');
          }
          await target.customStatement('PRAGMA user_version = 21');
          await target.close();

          final watch = Stopwatch()..start();
          final upgraded = await openLocalStore(
            keyManager: keys(),
            directory: dir,
          );
          watch.stop();
          try {
            final version = await upgraded
                .customSelect('PRAGMA user_version')
                .getSingle();
            expect(version.data.values.single, 22);
            final indexes = {
              for (final r
                  in await upgraded
                      .customSelect(
                        "SELECT name FROM sqlite_master WHERE type = 'index'",
                      )
                      .get())
                r.data['name']! as String,
            };
            expect(indexes.containsAll(v22Indexes), isTrue);
            for (final t in tables) {
              final n = await upgraded
                  .customSelect('SELECT COUNT(*) AS n FROM "$t"')
                  .getSingle();
              expect(n.data['n'], counts[t], reason: '$t keeps every row');
            }
            final integrity = await upgraded
                .customSelect('PRAGMA integrity_check')
                .get();
            expect(integrity.single.data.values.single, 'ok');
            expect(
              await upgraded.customSelect('PRAGMA foreign_key_check').get(),
              isEmpty,
            );
            final before = firstPageBeforeUpgrade;
            final after = await ExpenseRepository(
              upgraded,
            ).query(const ExpenseFilter(), limit: 50);
            expect(
              after.map((e) => e.row.id).toList(),
              before.map((e) => e.row.id).toList(),
              reason: 'the upgraded ledger reads the same first page',
            );
            debugPrint(
              'P8 MIGRATION v21->v22 in ${watch.elapsedMilliseconds} ms; '
              '$total rows kept; integrity ok; first ledger page equal',
            );
          } finally {
            await upgraded.close();
          }
        } finally {
          try {
            dir.deleteSync(recursive: true);
          } on Object {
            debugPrint('P8 MIGRATION could not remove ${dir.path}');
          }
        }
      },
    );
  });

  // ── p8-windows-export: the native dialogs, driven by a host script ────────────

  group('p8-windows-export', skip: _phase != 'p8-windows-export', () {
    testWidgets(
      'Save As and Print through the real native dialogs, online and offline, '
      'and the files equal the screen to the paisa',
      (tester) async {
        expect(p6Phone(), isFalse, reason: 'run on Windows');
        expect(p7Out, isNotEmpty, reason: 'P7_OUT names a folder');
        expect(p7StatusFile, isNotEmpty, reason: 'P7_STATUS names a file');
        final out = Directory(p7Out)..createSync(recursive: true);
        expect(out.listSync(), isEmpty, reason: 'P7_OUT starts empty');

        await launch(tester, recorders: p7Recorders());
        final container = await p6SignIn(tester, 'giridhar@hki.com');
        final client = Supabase.instance.client;
        await sweepPnlFixtures(client, marker: p6Marker);
        try {
          final ids = await p6Fixtures(client);
          await openPnl(tester, container);
          await chooseCustom(tester, container, p6From.iso, p6To.iso);
          await refreshPnl(tester, container);
          expectPnlMatchesServer(
            tester,
            container,
            await serverPnl(client, [_ccr, _hki], p6From.iso, p6To.iso),
          );
          final pnl = computedPnl(container);
          await p6OpenOverview(tester, container);
          await p6Custom(tester, container, p6From, p6To);
          await p6Refresh(tester, container);
          final dash = p6Ready(container).view.resultOrNull!;

          await p7OpenExportCentre(tester);
          Future<Uint8List> save(String key, String file) async => p7Saved(
            await p7Act(
              tester,
              container,
              key,
              'save $file',
              'SAVE|${p7Path(file)}',
            ),
          );

          final pdf = await save('export-profitAndLoss-pdf', 'p8-pnl.pdf');
          final xlsx = await save('export-profitAndLoss-xlsx', 'p8-pnl.xlsx');
          final forbidden = [_ccr, _hki, ids.sale, p6Marker, 'reports.export'];
          p7ExpectFigures('P&L', pdf, xlsx, [
            pnl.grossSales,
            pnl.gst,
            pnl.netSales,
            pnl.expenses,
            pnl.operatingProfit,
          ], forbidden: forbidden);
          final revPdf = await save(
            'export-revenueAnalysis-pdf',
            'p8-revenue.pdf',
          );
          final revXlsx = await save(
            'export-revenueAnalysis-xlsx',
            'p8-revenue.xlsx',
          );
          p7ExpectFigures('Revenue Analysis', revPdf, revXlsx, [
            dash.grossSales,
            dash.gst,
            dash.netSales,
          ], forbidden: forbidden);

          final listing = p7Listing();
          final cancelled = await p7Act(
            tester,
            container,
            'export-profitAndLoss-pdf',
            'cancel',
            'CANCEL',
          );
          expect(cancelled, isA<ExportActionCancelled>());
          expect(p7Listing(), listing, reason: 'a cancel writes nothing');

          final printed = await p7Act(
            tester,
            container,
            'export-profitAndLoss-print',
            'print pnl',
            'PRINT|${p7Path('p8-printed-pnl.pdf')}',
          );
          expect(printed, isA<ExportActionHandedOver>());
          expect(
            p7WithoutGenerated(p7Printed.last),
            p7WithoutGenerated(pdf),
            reason: 'print receives the Save PDF document',
          );
          await pumpUntil(tester, 'the printed file', () {
            final f = File(p7Path('p8-printed-pnl.pdf'));
            return f.existsSync() && f.lengthSync() > 0;
          }, timeout: const Duration(seconds: 60));

          // After a print, Save As still opens (D-308); and offline too (D-299).
          _transport.online = false;
          final offline = await save(
            'export-profitAndLoss-xlsx',
            'p8-offline-pnl.xlsx',
          );
          p7ExpectFigures('offline P&L', pdf, offline, [
            pnl.netSales,
            pnl.operatingProfit,
          ]);
          _transport.online = true;
          expect(
            p7Listing().where((n) => n.contains('.part')),
            isEmpty,
            reason: 'no temporary file left',
          );
          p7Say('done', 'phase finished; ${p7Listing().length} files');
        } finally {
          _transport.online = true;
          await p6SweepAfter(client);
        }
      },
    );
  });
}

/// One row, read the way any client would.
Future<Map<String, dynamic>> _row(String table, String id) async =>
    await Supabase.instance.client
        .from(table)
        .select('id,code,name,row_version,archived_at')
        .eq('id', id)
        .single();

/// One expense, read through the projection a client is allowed to read.
///
/// Never `expenses`: no client role holds SELECT on the base table, and the header total
/// on a shared bill is withheld by the view for the caller who may not see it (D-062).
/// A separate helper from [_row] because the master tables and the expense projection
/// have nothing in common but an id — asking for `code` here returns `42703`.
/// Today, as the property's books would date it.
String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

/// The organisation an expense belongs to, read through the permitted projection.
Future<String> _orgIdOf(String expenseId) async =>
    (await Supabase.instance.client
            .from('expense_document')
            .select('org_id')
            .eq('id', expenseId)
            .single())['org_id']
        as String;

/// Voids a leftover document at a fixed id, so the two-device phases can be re-run.
///
/// Void rather than delete, as everywhere: financial history is corrected by void plus
/// audit (spec §14, D-006), and a re-runnable acceptance is not a reason to make an
/// exception.
/// The id of the document the two-device chain is currently about.
///
/// Found by its marker rather than hard-coded, so the chain can run more than once
/// against a database that never deletes a financial row. The newest **open** one is the
/// current run's; older voided ones are left where they are, because voiding is how this
/// project retires a document and the audit trail keeps them (D-006, D-066).
Future<String> _twoDeviceDocumentId({bool includeVoided = false}) async {
  // A *prefix* match, not equality: leg (b) corrects the document and rewrites its notes,
  // so the marker has to survive being edited. Every leg that writes notes keeps this
  // prefix and appends to it.
  var query = Supabase.instance.client
      .from('expense_document')
      .select('id,created_at,voided_at')
      .like('notes', '$_twoDeviceMarker%');
  if (!includeVoided) query = query.isFilter('voided_at', null);
  final rows = await query.order('created_at', ascending: false).limit(1);
  if (rows.isEmpty) {
    fail(
      'no open two-device document exists. Leg (a) creates it and must run first, on '
      'Android, before this leg.',
    );
  }
  return rows.first['id'] as String;
}

/// Voids every open document left by an earlier two-device run.
Future<void> _voidTwoDeviceLeftovers() async {
  final rows = await Supabase.instance.client
      .from('expense_document')
      .select('id,row_version')
      .like('notes', '$_twoDeviceMarker%')
      .isFilter('voided_at', null);
  for (final row in rows) {
    await ExpenseGateway(Supabase.instance.client).voidExpense(
      expenseId: row['id'] as String,
      baseRowVersion: row['row_version'] as int,
      reason: '$_acceptanceMarker: clearing the previous two-device fixture',
      mutationId: const Uuid().v4(),
    );
  }
}

Future<Map<String, dynamic>> _expenseRow(String id) async => await Supabase
    .instance
    .client
    .from('expense_document')
    .select(
      'id,txn_number,business_date,total_amount_minor,visible_amount_minor,'
      'is_complete,row_version,voided_at,notes',
    )
    .eq('id', id)
    .single();

/// The department's current `row_version`, read the way any client would.
Future<int> _currentVersion(String departmentId) async {
  final row = await Supabase.instance.client
      .from('departments')
      .select('row_version')
      .eq('id', departmentId)
      .single();
  return row['row_version'] as int;
}

String _two(int value) => value.toString().padLeft(2, '0');

/// A file, at the exact point the OS picker would have returned one.
///
/// Not a fake of the staging service, the database or the upload: everything downstream
/// of this is the real code path. What it replaces is the one step the Flutter test
/// harness genuinely cannot drive — an Android photo-picker activity or a Windows file
/// dialog, both of which are outside the application's own view.
class _SyntheticAttachmentSource implements AttachmentSource {
  _SyntheticAttachmentSource();

  Directory? _scratch;
  String? pickedPath;

  @override
  Set<AttachmentIntake> get available => AttachmentIntake.values.toSet();

  @override
  Future<PickedFile?> pick(AttachmentIntake intake) async {
    final scratch = _scratch ??= Directory.systemTemp.createTempSync(
      'krishna_acceptance_bill',
    );
    final file = File('${scratch.path}/synthetic-receipt.jpg')
      ..writeAsBytesSync(syntheticJpeg());
    pickedPath = file.path;
    return PickedFile(
      file: file,
      fileName: 'synthetic-receipt.jpg',
      contentType: 'image/jpeg',
    );
  }

  void dispose() {
    if (_scratch?.existsSync() ?? false) _scratch!.deleteSync(recursive: true);
  }

  /// A real, decodable JPEG — small enough that the optimiser leaves it alone, so the
  /// phases are about staging and upload rather than about re-encoding.
  static List<int> syntheticJpeg() {
    final image = img.Image(width: 64, height: 64);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, 128);
      }
    }
    return img.encodeJpg(image, quality: 80);
  }
}
