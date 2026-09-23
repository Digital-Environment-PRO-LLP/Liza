import 'package:flutter/material.dart';

import 'package:liza/widgets/matrix.dart';

/// Renders [child] only when the current user has the "developer" role.
///
/// Listens to [UserRoleService.rolesVersion], so the UI updates reactively when
/// the role is (re-)fetched. Default fallback is [SizedBox.shrink], which lets
/// you drop this widget into any layout without breaking neighbouring spacing.
class IfDeveloper extends StatelessWidget {
  final Widget child;
  final Widget? fallback;

  const IfDeveloper({required this.child, this.fallback, super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: matrix.userRoleService.rolesVersion,
      builder: (context, _, _) {
        if (!matrix.isCurrentUserDeveloper) {
          return fallback ?? const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}
