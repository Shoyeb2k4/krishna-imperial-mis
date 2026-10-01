/// What an expense surface says when this device could not read what it needed.
///
/// Plain words and a way forward, never the exception (D-322, D-323). A raw SQLite or
/// Drift message, a provider name or a stack trace tells a manager nothing they can act
/// on, and can carry a local file path. The detail still matters to whoever diagnoses the
/// device, so it goes to the developer log — never to the screen.
library;

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

/// Records a read failure for diagnosis, off screen.
void logExpenseReadFailure(String where, Object error, StackTrace? stack) =>
    developer.log(
      '$where could not be read',
      name: 'krishna_mis.expenses',
      error: error,
      stackTrace: stack,
    );

class ExpenseReadFailure extends StatelessWidget {
  const ExpenseReadFailure({
    required this.title,
    required this.body,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String body;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.subheading,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const Key('expense-read-retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
