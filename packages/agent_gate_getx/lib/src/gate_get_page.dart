import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Derives per-navigation decider context from GetX routing state
/// (`Get.parameters`, `Get.arguments`).
typedef GateGetContext = Map<String, Object?> Function(
  Map<String, String?> parameters,
  Object? arguments,
);

/// A `GetPage` whose page *is* the gate.
///
/// ```dart
/// GetMaterialApp(getPages: [
///   GateGetPage(name: '/checkout', gate: checkoutGate),
///   GetPage(name: '/checkout/express', page: () => const ExpressPage()),
/// ]);
/// ```
///
/// Navigating to `/checkout` (Get.toNamed, deep link, or a redirect) shows the
/// loading view, decides, and renders the chosen candidate's `builder` inline.
/// Candidates therefore need `builder`s. If your destinations are separate
/// `GetPage`s, use [GetxAdapter] or [GateMiddleware] instead.
class GateGetPage extends GetPage<void> {
  /// Creates the page.
  GateGetPage({
    required super.name,
    required Gate gate,
    GateGetContext? contextFromRoute,
    Widget? loading,
    super.transition,
    super.middlewares,
    super.binding,
    super.bindings,
    super.fullscreenDialog,
    super.title,
  }) : super(
         page: () => GatePage(
           gate: gate,
           extra:
               contextFromRoute?.call(Get.parameters, Get.arguments) ??
               const <String, Object?>{},
           loading: loading,
         ),
       );
}
