/// The application widget.
///
/// Chooses the platform's shell and density. Everything below this point is shared.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';

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
    );
  }
}
