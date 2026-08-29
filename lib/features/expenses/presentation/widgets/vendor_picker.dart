/// Choosing a supplier, or not choosing one.
///
/// A vendor is optional. It is also organisation-global (D-049): one Sharma Traders
/// serves both properties, and a manager who loses access to Crystal Canopy still sees
/// the supplier — they simply lose the *pre-selection* that pointed at it.
///
/// Two rules this widget keeps:
///
/// * **Nothing here writes to a vendor.** Selecting one on an expense does not touch the
///   master. Remembering a last-used supplier by editing the vendor record would turn a
///   company-wide master into a per-user preference, and quietly move a row version that
///   other people are basing edits on.
/// * **The effective default is derived, not stored.** A vendor whose configured default
///   property is outside this user's scope offers no default to them, and offers it again
///   the moment scope returns — with nothing written either way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';

class VendorPicker extends ConsumerWidget {
  const VendorPicker({
    required this.selectedVendorId,
    required this.onChanged,
    super.key,
    this.businessUnitIds = const {},
  });

  final String? selectedVendorId;

  /// The properties this expense charges, used only to say something helpful about a
  /// vendor's usual property. Never used to filter the list.
  final Set<String> businessUnitIds;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorListProvider(false));

    return vendors.when(
      loading: () => const SizedBox(height: 56),
      error: (error, _) => Text(
        'Suppliers could not be read.',
        style: AppTypography.caption.copyWith(color: AppColors.caution),
      ),
      data: (list) {
        final selected = list
            .where((v) => v.id == selectedVendorId)
            .firstOrNull;
        return InkWell(
          key: const Key('vendor-picker'),
          onTap: () async {
            final chosen = await showModalBottomSheet<_VendorChoice>(
              context: context,
              backgroundColor: AppColors.surface,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: AppRadius.large),
              ),
              builder: (_) => _VendorSheet(vendors: list),
            );
            if (chosen != null) onChanged(chosen.vendorId);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Vendor (optional)',
              border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.name ?? 'None',
                    key: const Key('vendor-name'),
                    style: AppTypography.body.copyWith(
                      color: selected == null
                          ? AppColors.inkFaint
                          : AppColors.ink,
                    ),
                  ),
                ),
                const Icon(Icons.search, size: 18, color: AppColors.inkFaint),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VendorChoice {
  const _VendorChoice(this.vendorId);
  final String? vendorId;
}

/// A searchable list. Fast, because this is used mid-entry on a phone.
class _VendorSheet extends StatefulWidget {
  const _VendorSheet({required this.vendors});
  final List<Vendor> vendors;

  @override
  State<_VendorSheet> createState() => _VendorSheetState();
}

class _VendorSheetState extends State<_VendorSheet> {
  String _term = '';

  List<Vendor> get _matches {
    if (_term.trim().isEmpty) return widget.vendors;
    final needle = _term.trim().toLowerCase();
    return [
      for (final vendor in widget.vendors)
        if (vendor.name.toLowerCase().contains(needle) ||
            vendor.code.toLowerCase().contains(needle))
          vendor,
    ];
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                key: const Key('vendor-search'),
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search suppliers',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
                ),
                onChanged: (value) => setState(() => _term = value),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    key: const Key('vendor-none'),
                    leading: const Icon(Icons.block, size: 18),
                    title: const Text('No vendor'),
                    onTap: () =>
                        Navigator.of(context).pop(const _VendorChoice(null)),
                  ),
                  const Divider(height: 1),
                  for (final vendor in _matches)
                    ListTile(
                      title: Text(vendor.name),
                      subtitle: Text(vendor.code, style: AppTypography.caption),
                      onTap: () =>
                          Navigator.of(context).pop(_VendorChoice(vendor.id)),
                    ),
                  if (_matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Text(
                        'No supplier matches "$_term".',
                        style: AppTypography.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
