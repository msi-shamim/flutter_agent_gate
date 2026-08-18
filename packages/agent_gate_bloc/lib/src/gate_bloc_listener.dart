import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'gate_state.dart';

/// Called when a decision lands. Return normally after navigating.
typedef GateDecidedCallback = void Function(
  BuildContext context,
  GateDecided state,
);

/// Widget-layer side-effect handler for [GateCubit] / [GateBloc].
///
/// On every *new* [GateDecided] it navigates — by default through
/// `AgentGate.instance.adapter` (so the same `NavigatorAdapter` /
/// `GoRouterAdapter` / `GetxAdapter` you configured globally is used), or via
/// [onDecided] if you want to dispatch your own navigation.
///
/// While the state is [GateDeciding] and [showLoading] is true, the loading
/// UI is layered over [child] (uses `AgentGate.loadingBuilder` or the default
/// `AgentLoadingView`) — no overlay tricks, plain widget composition, so it
/// works inside nested navigators and tests.
///
/// ```dart
/// GateBlocListener<GateCubit>(
///   child: CartView(),
///   onNavigated: (ctx, s) => ctx.read<GateCubit>().reset(),
/// )
/// ```
///
/// [B] is the bloc type to listen to — `GateCubit` or `GateBloc` (or your
/// own `BlocBase<GateState>`); it is looked up with `context.read<B>()` unless
/// [bloc] is passed explicitly.
class GateBlocListener<B extends BlocBase<GateState>> extends StatelessWidget {
  /// Creates the listener.
  const GateBlocListener({
    super.key,
    required this.child,
    this.bloc,
    this.onDecided,
    this.onNavigated,
    this.showLoading = true,
    this.navigateOnFallback = true,
  });

  /// The subtree (usually the page A UI).
  final Widget child;

  /// Explicit bloc; defaults to `context.read<B>()`.
  final B? bloc;

  /// Custom navigation. If null, `AgentGate.instance.adapter.navigate` is
  /// used with the listener's `BuildContext`.
  final GateDecidedCallback? onDecided;

  /// Called after navigation was triggered — typical place to `reset()`.
  final GateDecidedCallback? onNavigated;

  /// Overlay the loading UI while deciding.
  final bool showLoading;

  /// If false, fallback decisions are *not* navigated automatically (you
  /// might want to show an error/retry instead). They still reach
  /// [onDecided] when it is provided.
  final bool navigateOnFallback;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<B, GateState>(
      bloc: bloc,
      listenWhen: (prev, curr) => curr is GateDecided && prev != curr,
      listener: (context, state) {
        final s = state as GateDecided;
        if (onDecided != null) {
          onDecided!(context, s);
        } else if (navigateOnFallback || !s.isFallback) {
          // Not awaited on purpose — push futures complete on pop.
          AgentGate.instance.adapter.navigate(context, s.candidate, s.decision);
        }
        onNavigated?.call(context, s);
      },
      buildWhen: (prev, curr) =>
          (prev is GateDeciding) != (curr is GateDeciding),
      builder: (context, state) {
        if (!showLoading || state is! GateDeciding) return child;
        final reasoning = AgentGate.instance.decider?.reasoning(
          _requestStubFor(state),
        );
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            child,
            Positioned.fill(
              child: AbsorbPointer(
                child:
                    AgentGate.instance.loadingBuilder?.call(
                      context,
                      reasoning,
                    ) ??
                    AgentLoadingView(reasoning: reasoning),
              ),
            ),
          ],
        );
      },
    );
  }

  // The reasoning stream API is keyed on a GateRequest. In the listener we do
  // not have the request the cubit built (it is internal to AgentGate), so we
  // hand deciders a minimal stand-in. Deciders that ignore the request (the
  // common case: they stream generic progress) work; ones that need the real
  // request return null and the loader simply shows no reasoning text.
  GateRequest _requestStubFor(GateDeciding s) => GateRequest(
    gateId: s.gate.id,
    fromPage: s.gate.from,
    candidates: s.gate.candidates,
    context: GateContext.empty,
    profile: (s.gate.config ?? AgentGate.instance.config).profile,
    requestId: 'listener-preview',
    timestamp: DateTime.now().toUtc(),
  );
}
