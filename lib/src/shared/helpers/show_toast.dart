import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../routing/global_navigator.dart';

/// Feedback for shared operations that do not have a local widget context.
void showGlobalToast({required String message, String status = 'success'}) {
  final context = rootContext;
  if (context == null || !context.mounted) return;

  final description = Text(message);
  ShadToaster.of(context).show(
    status == 'error'
        ? ShadToast.destructive(description: description)
        : ShadToast(description: description),
  );
}
