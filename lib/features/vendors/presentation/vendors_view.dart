/// Vendor management.
///
/// The lightest surface in the product, on purpose. These are small local suppliers —
/// a vegetable market, a gas agency, a plumber. **Name is the only requirement**, and the
/// form says so rather than presenting a wall of corporate-registration fields nobody
/// will fill in.
///
/// Search is built for speed because this list is what expense entry will reach for on a
/// phone, at the end of a shift.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/features/masters/presentation/masters_model.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:uuid/uuid.dart';

final vendorSearchProvider = NotifierProvider<VendorSearchTerm, String>(
  VendorSearchTerm.new,
);

class VendorSearchTerm extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final selectedVendorProvider = NotifierProvider<SelectedVendor, Vendor?>(
  SelectedVendor.new,
);

class SelectedVendor extends Notifier<Vendor?> {
  @override
  Vendor? build() => null;
  void select(Vendor? vendor) => state = vendor;
}

class VendorsView extends ConsumerWidget {
  const VendorsView({required this.isDesktop, super.key});

  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(showArchivedMastersProvider);
    final vendorsAsync = ref.watch(vendorListProvider(showArchived));

    return vendorsAsync.when(
      loading: () => const QuietLoading(label: 'Loading vendors…'),
      error: (error, stack) {
        logMasterReadFailure('the supplier list', error, stack);
        return MasterErrorState(
          suppliersUnreadable,
          onRetry: () => ref.invalidate(vendorListProvider(showArchived)),
        );
      },
      data: (vendors) {
        final term = ref.watch(vendorSearchProvider).trim().toLowerCase();
        final filtered =
            term.isEmpty
                  ? vendors
                  : [
                      for (final v in vendors)
                        if (v.name.toLowerCase().contains(term) ||
                            (v.phone ?? '').contains(term))
                          v,
                    ]
              ..sort((a, b) {
                final aPrefix = a.name.toLowerCase().startsWith(term);
                final bPrefix = b.name.toLowerCase().startsWith(term);
                if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
                return a.name.compareTo(b.name);
              });

        if (!isDesktop) return _VendorList(vendors: filtered, isDesktop: false);

        final selected = ref.watch(selectedVendorProvider);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 380,
              child: _VendorList(vendors: filtered, isDesktop: true),
            ),
            const VerticalDivider(width: 1, color: AppColors.hairline),
            Expanded(
              child: selected == null
                  ? const MasterEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'Select a vendor',
                      message:
                          'Or add one. A name is all that is needed — everything else '
                          'is optional.',
                    )
                  : VendorDetail(vendor: selected),
            ),
          ],
        );
      },
    );
  }
}

class _VendorList extends ConsumerWidget {
  const _VendorList({required this.vendors, required this.isDesktop});

  final List<Vendor> vendors;
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(principalProvider)
        .canAnywhere(Capability.mastersManage);
    final selectedId = ref.watch(selectedVendorProvider)?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search vendors',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ref.read(vendorSearchProvider.notifier).set(v),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Add vendor',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addVendor(context, ref),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: vendors.isEmpty
              ? MasterEmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'No vendors yet',
                  message:
                      'Add the suppliers you buy from. A name is enough — "Local '
                      'Vegetable Market" is a complete entry.',
                  action: canManage
                      ? FilledButton.icon(
                          onPressed: () => _addVendor(context, ref),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add vendor'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brass,
                            foregroundColor: AppColors.inkInverse,
                          ),
                        )
                      : null,
                )
              : ListView.separated(
                  itemCount: vendors.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    final vendor = vendors[index];
                    return InkWell(
                      focusColor: AppColors.brassWash,
                      hoverColor: AppColors.surfaceSunken,
                      onTap: () {
                        ref
                            .read(selectedVendorProvider.notifier)
                            .select(vendor);
                        if (!isDesktop) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: Text(vendor.name)),
                                body: VendorDetail(vendor: vendor),
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: isDesktop ? 44 : 60,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        color: vendor.id == selectedId && isDesktop
                            ? AppColors.brassWash
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    vendor.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.body.copyWith(
                                      color: vendor.isArchived
                                          ? AppColors.inkFaint
                                          : AppColors.ink,
                                    ),
                                  ),
                                  if (vendor.phone != null) ...[
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      vendor.phone!,
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (vendor.isArchived)
                              const MasterStatusChip(
                                isArchived: true,
                                compact: true,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addVendor(BuildContext context, WidgetRef ref) async {
    final result = await VendorEditor.show(context);
    if (result == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(vendorRepositoryProvider)
          .create(
            id: const Uuid().v7(),
            orgId: 'seed-org-krishna',
            code: _codeFor(result.name),
            name: result.name,
            phone: result.phone,
            gstin: result.gstin,
            address: result.address,
            notes: result.notes,
            now: DateTime.now().toUtc(),
          );
      ref.invalidate(vendorListProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${result.name} added.')));
    } on VendorWriteRefused catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// A readable permanent code derived from the name, uniquified by a short suffix.
  ///
  /// The user never types this and never edits it afterwards; it exists so history and
  /// exports have something stable to key on when the label is later corrected (D-035).
  static String _codeFor(String name) {
    final slug = name
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final trimmed = slug.length > 20 ? slug.substring(0, 20) : slug;
    final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${trimmed.isEmpty ? 'VENDOR' : trimmed}_${suffix.substring(suffix.length - 4)}';
  }
}

class VendorDetail extends ConsumerWidget {
  const VendorDetail({required this.vendor, super.key});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(principalProvider)
        .canAnywhere(Capability.mastersManage);
    final usage = ref.watch(vendorUsageProvider(vendor.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VENDOR', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(vendor.name, style: AppTypography.heading)),
              const SizedBox(width: AppSpacing.md),
              MasterStatusChip(isArchived: vendor.isArchived),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CodeBadge(vendor.code),
          const SizedBox(height: AppSpacing.xl),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.xl),

          if (!vendor.hasContactDetails && vendor.notes == null)
            DetailField(
              label: 'Details',
              child: Text(
                'Only a name was recorded. That is a complete vendor — nothing else '
                'is required.',
                style: AppTypography.bodyMuted,
              ),
            ),
          DetailField(label: 'Phone', value: vendor.phone),
          DetailField(label: 'GSTIN', value: vendor.gstin),
          DetailField(label: 'Address', value: vendor.address),
          DetailField(label: 'Notes', value: vendor.notes),

          DetailField(
            label: 'Historical usage',
            child: usage.when(
              data: UsageNote.new,
              loading: () =>
                  const Text('Checking…', style: AppTypography.bodyMuted),
              error: (_, _) => const Text(
                'Could not check usage.',
                style: AppTypography.bodyMuted,
              ),
            ),
          ),

          if (vendor.isArchived)
            DetailField(
              label: 'Archived',
              child: Text(
                'Not offered when recording a new expense. Past expenses still show '
                'this vendor.',
                style: AppTypography.bodyMuted,
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          if (!canManage)
            Text(
              'Managing vendors requires the "manage masters" permission.',
              style: AppTypography.bodyMuted,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
                if (vendor.isArchived)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _setArchived(context, ref, archived: false),
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: const Text('Restore'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _setArchived(context, ref, archived: true),
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Archive'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await VendorEditor.show(context, existing: vendor);
    if (result == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(vendorRepositoryProvider)
          .update(
            id: vendor.id,
            name: result.name,
            phone: result.phone,
            gstin: result.gstin,
            address: result.address,
            notes: result.notes,
            now: DateTime.now().toUtc(),
          );
      final updated = await ref.read(vendorRepositoryProvider).byId(vendor.id);
      ref.read(selectedVendorProvider.notifier).select(updated);
      ref.invalidate(vendorListProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Vendor updated.')));
    } on VendorWriteRefused catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _setArchived(
    BuildContext context,
    WidgetRef ref, {
    required bool archived,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(vendorRepositoryProvider);
    try {
      if (archived) {
        await repository.archive(id: vendor.id, now: DateTime.now().toUtc());
      } else {
        await repository.unarchive(id: vendor.id, now: DateTime.now().toUtc());
      }
      ref
          .read(selectedVendorProvider.notifier)
          .select(await repository.byId(vendor.id));
      ref.invalidate(vendorListProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              archived
                  ? '${vendor.name} archived. Past expenses still show this vendor.'
                  : '${vendor.name} restored.',
            ),
          ),
        );
    } on VendorWriteRefused catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// What the editor returns.
class VendorDraft {
  const VendorDraft({
    required this.name,
    this.phone,
    this.gstin,
    this.address,
    this.notes,
  });

  final String name;
  final String? phone;
  final String? gstin;
  final String? address;
  final String? notes;
}

/// Create/edit form.
///
/// One required field at the top, everything else clearly marked optional and collapsed
/// out of the way. A small supplier should take five seconds to record.
class VendorEditor extends StatefulWidget {
  const VendorEditor({super.key, this.existing});

  final Vendor? existing;

  static Future<VendorDraft?> show(BuildContext context, {Vendor? existing}) =>
      showDialog<VendorDraft>(
        context: context,
        builder: (_) => VendorEditor(existing: existing),
      );

  @override
  State<VendorEditor> createState() => _VendorEditorState();
}

class _VendorEditorState extends State<VendorEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _gstin = TextEditingController(text: widget.existing?.gstin ?? '');
  late final _address = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late bool _showOptional = widget.existing?.hasContactDetails ?? false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _gstin, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMedium),
      title: Text(
        editing ? 'Edit vendor' : 'Add vendor',
        style: AppTypography.heading,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'The only thing required',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_showOptional)
                TextButton.icon(
                  onPressed: () => setState(() => _showOptional = true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add phone, GSTIN or address (optional)'),
                )
              else ...[
                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gstin,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brass,
            foregroundColor: AppColors.inkInverse,
          ),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  VendorDraft(
                    name: _name.text.trim(),
                    phone: _phone.text,
                    gstin: _gstin.text,
                    address: _address.text,
                    notes: _notes.text,
                  ),
                ),
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
