/// Masters, routed to the right experience for the platform.
///
/// Windows gets a browsable hierarchy with a persistent detail panel; Android gets a
/// drill-down. They share the domain, the repository and the detail content — only the
/// navigation shape differs (master spec §18, §19).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/features/masters/presentation/android_masters_view.dart';
import 'package:krishna_mis/features/masters/presentation/windows_masters_view.dart';

class MastersPage extends StatelessWidget {
  const MastersPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  Widget build(BuildContext context) => shellKind == AppShellKind.desktop
      ? const WindowsMastersView()
      : const AndroidMastersView();
}
