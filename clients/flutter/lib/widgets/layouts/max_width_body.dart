import 'package:flutter/material.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/themes.dart';

class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool withScrolling;
  final EdgeInsets? innerPadding;

  const MaxWidthBody({
    required this.child,
    this.maxWidth = 600,
    this.withScrolling = true,
    this.innerPadding,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final bottomPadding = MediaQuery.paddingOf(context).bottom;

          const desiredWidth = LizaThemes.columnWidth * 1.5;
          final body = constraints.maxWidth <= desiredWidth
              ? child
              : Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: LizaThemes.columnWidth * 1.5,
                    ),
                    child: Material(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                        side: BorderSide(color: theme.dividerColor),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: child,
                      ),
                    ),
                  ),
                );
          if (!withScrolling) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: body,
            );
          }

          return SingleChildScrollView(
            padding: (innerPadding ?? EdgeInsets.zero).copyWith(
              bottom: (innerPadding?.bottom ?? 0) + bottomPadding,
            ),
            physics: const ScrollPhysics(),
            child: body,
          );
        },
      ),
    );
  }
}
