/// Renaming a master (D-038).
///
/// A rename may **correct or clarify** a label. It may not **change what the label
/// means** — doing so would silently restate history, making months of grocery spending
/// appear under a different concept.
///
/// No attempt is made to detect this automatically. Whether two labels mean the same
/// thing is a business judgement, and an AI guess at it would be exactly the kind of
/// invented business fact this project forbids. Instead the rule is stated, the real
/// impact is shown, and the person renaming must acknowledge it deliberately.
///
/// The safe default matters: when usage **cannot be confirmed** — no backend yet, or
/// offline — the warning is shown anyway. Silence is not evidence of "unused".
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/masters/master_usage.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';

/// The outcome of the dialog: a new name, or null if the user backed out.
class RenameMasterDialog extends StatefulWidget {
  const RenameMasterDialog({
    required this.currentName,
    required this.code,
    required this.usage,
    super.key,
    this.kindLabel = 'record',
  });

  final String currentName;
  final String code;
  final MasterUsage usage;

  /// "expense category", "department", "vendor" — used in the prose.
  final String kindLabel;

  static Future<String?> show(
    BuildContext context, {
    required String currentName,
    required String code,
    required MasterUsage usage,
    String kindLabel = 'record',
  }) => showDialog<String>(
    context: context,
    builder: (_) => RenameMasterDialog(
      currentName: currentName,
      code: code,
      usage: usage,
      kindLabel: kindLabel,
    ),
  );

  @override
  State<RenameMasterDialog> createState() => _RenameMasterDialogState();
}

class _RenameMasterDialogState extends State<RenameMasterDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentName,
  );
  bool _acknowledged = false;

  /// Whether the rule must be shown and acknowledged.
  ///
  /// Only a **server-confirmed** absence of history lets us skip it. A local count of
  /// zero proves nothing about the other three years on the server.
  bool get _requiresAcknowledgement =>
      !(widget.usage.isAuthoritative && !widget.usage.hasKnownHistory);

  bool get _nameChanged =>
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim() != widget.currentName;

  bool get _canSave =>
      _nameChanged && (!_requiresAcknowledgement || _acknowledged);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMedium),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RENAME ${widget.kindLabel.toUpperCase()}',
            style: AppTypography.overline,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.currentName, style: AppTypography.heading),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CodeBadge(widget.code),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'The code stays the same. Reports and history follow it, not the name.',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_canSave) {
                    Navigator.of(context).pop(_controller.text.trim());
                  }
                },
              ),
              if (_requiresAcknowledgement) ...[
                const SizedBox(height: AppSpacing.lg),
                _RenameRuleNotice(usage: widget.usage),
                const SizedBox(height: AppSpacing.md),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: AppColors.brass,
                  title: Text(
                    'I am correcting or clarifying the label. The business meaning is '
                    'not changing.',
                    style: AppTypography.body,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brass,
            foregroundColor: AppColors.inkInverse,
          ),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

class _RenameRuleNotice extends StatelessWidget {
  const _RenameRuleNotice({required this.usage});

  final MasterUsage usage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.brassWash,
        borderRadius: AppRadius.allMedium,
        border: Border.all(color: AppColors.brassMuted.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_edu_outlined,
                size: 16,
                color: AppColors.brass,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('This record has history', style: AppTypography.subheading),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Renaming should only correct or clarify the label. If the business '
            'meaning is changing, archive this item and create a new one.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.md),
          const _RuleExample(
            allowed: true,
            before: 'VEGITABLE & FRUITS',
            after: 'VEGETABLES & FRUITS',
            note: 'Same thing, spelled correctly.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RuleExample(
            allowed: false,
            before: 'Kirana & Pulses',
            after: 'Building Maintenance',
            note:
                'A different concept. Past grocery spending would appear as building '
                'costs.',
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          UsageNote(usage),
        ],
      ),
    );
  }
}

class _RuleExample extends StatelessWidget {
  const _RuleExample({
    required this.allowed,
    required this.before,
    required this.after,
    required this.note,
  });

  final bool allowed;
  final String before;
  final String after;
  final String note;

  @override
  Widget build(BuildContext context) {
    final color = allowed ? AppColors.positive : AppColors.negative;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(allowed ? Icons.check : Icons.close, size: 14, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: before, style: AppTypography.body),
                    TextSpan(
                      text: '  →  ',
                      style: AppTypography.body.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                    TextSpan(
                      text: after,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Text(note, style: AppTypography.caption),
            ],
          ),
        ),
      ],
    );
  }
}
