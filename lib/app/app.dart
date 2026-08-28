/// The application widget.
///
/// Chooses the platform's shell and density. Everything below this point is shared.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/features/auth/presentation/session_gate.dart';

class KrishnaMisApp extends StatefulWidget {
  const KrishnaMisApp({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  State<KrishnaMisApp> createState() => _KrishnaMisAppState();
}

class _KrishnaMisAppState extends State<KrishnaMisApp> {
  late final _router = AppRouter.create(shellKind: widget.shellKind);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Krishna Imperial MIS',
      debugShowCheckedModeBanner: false,
      theme: widget.shellKind == AppShellKind.desktop
          ? AppTheme.desktop
          : AppTheme.mobile,
      routerConfig: _router,
      // One gate decides what the application is allowed to show. Wrapping the router's
      // output rather than guarding each route keeps the decision in a single place, and
      // means a route added later cannot forget to make it.
      builder: (context, child) => SessionGate(
        shellKind: widget.shellKind,
        child: child ?? const SizedBox(),
      ),
    );
  }
}
