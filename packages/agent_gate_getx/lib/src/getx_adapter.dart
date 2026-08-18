import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'gate_arguments.dart';

/// How [GetxAdapter] should move to the chosen route.
enum GetxNavigationMode {
  /// `Get.toNamed` — stack on top; back returns to page A.
  to,

  /// `Get.offNamed` — replace page A; back skips the gate origin.
  off,

  /// `Get.offAllNamed` — clear the stack; typical for "onboarding → home".
  offAll,
}

/// Customises the arguments delivered to the destination.
/// Receives the default [GateArguments]; return anything (or null).
typedef GateArgumentsBuilder = Object? Function(GateArguments args);

/// [NavigationAdapter] for GetX. Context-free: works from controllers,
/// services and callbacks alike.
///
/// Routing rules, in order:
/// 1. If the candidate has a `route`, navigate by name using [mode].
/// 2. Else if it has a `builder`, use `Get.to(builder)` (only [mode]
///    `to`/`off` make sense here; `offAll` maps to `Get.offAll`).
/// 3. Else throw a descriptive [StateError] — a candidate must be reachable.
class GetxAdapter implements NavigationAdapter {
  /// Creates the adapter.
  const GetxAdapter({
    this.mode = GetxNavigationMode.to,
    this.argumentsBuilder,
    this.id,
  });

  /// to / off / offAll.
  final GetxNavigationMode mode;

  /// Customises `Get.arguments`. Default: a [GateArguments].
  final GateArgumentsBuilder? argumentsBuilder;

  /// Nested-navigator id (GetX `id:` parameter), if you use nested routing.
  final int? id;

  @override
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  ) {
    final defaultArgs = GateArguments(decision: decision, candidate: candidate);
    final args = argumentsBuilder == null
        ? defaultArgs
        : argumentsBuilder!(defaultArgs);

    final route = candidate.route;
    if (route != null) {
      // GetX returns Future<T?>? — null when navigation is a no-op (e.g.
      // duplicate route prevented). Normalise so callers always get a future.
      final Future<Object?>? f = switch (mode) {
        GetxNavigationMode.to => Get.toNamed<Object?>(
          route,
          arguments: args,
          id: id,
        ),
        GetxNavigationMode.off => Get.offNamed<Object?>(
          route,
          arguments: args,
          id: id,
        ),
        GetxNavigationMode.offAll => Get.offAllNamed<Object?>(
          route,
          arguments: args,
          id: id,
        ),
      };
      return f ?? Future<Object?>.value(null);
    }

    final builder = candidate.builder;
    if (builder != null) {
      // Builder-only candidates: give the page a stable name so GetX's
      // routing observers (and our GateNavigatorObserver) see it.
      final name = '/${candidate.id}';
      final Future<Object?>? f = switch (mode) {
        GetxNavigationMode.to => Get.to<Object?>(
          () => Builder(builder: builder),
          routeName: name,
          arguments: args,
          id: id,
        ),
        GetxNavigationMode.off => Get.off<Object?>(
          () => Builder(builder: builder),
          routeName: name,
          arguments: args,
          id: id,
        ),
        GetxNavigationMode.offAll => Get.offAll<Object?>(
          () => Builder(builder: builder),
          routeName: name,
          arguments: args,
          id: id,
        ),
      };
      return f ?? Future<Object?>.value(null);
    }

    throw StateError(
      'GetxAdapter: candidate "${candidate.id}" has neither `route` nor '
      '`builder`. Give it a GetX route name (e.g. "/checkout/express") or a '
      'widget builder.',
    );
  }
}
