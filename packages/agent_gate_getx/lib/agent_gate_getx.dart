/// GetX integration for `agent_gate`.
///
/// * [GetxAdapter] — `NavigationAdapter` over `Get.toNamed` / `offNamed` /
///   `offAllNamed` (or `Get.to(builder)` for builder-only candidates). No
///   `BuildContext` needed anywhere.
/// * [GateArguments] — the typed payload delivered through `Get.arguments`
///   so the destination knows *why* it was chosen.
/// * [GateGetPage] — a `GetPage` whose page is a `GatePage`: the AI-chosen
///   candidate renders inline at that named route.
/// * [GateMiddleware] — `GetMiddleware.redirectDelegate` for apps on GetX's
///   Navigator-2 router (`GetMaterialApp.router`); resolves a gate path to
///   the chosen candidate's route before anything is built.
/// * [GateController] — a `GetxController` that exposes the last decision
///   reactively, for teams that keep navigation decisions in controllers.
library;

export 'src/gate_arguments.dart';
export 'src/gate_controller.dart';
export 'src/gate_get_page.dart';
export 'src/gate_middleware.dart';
export 'src/getx_adapter.dart';
