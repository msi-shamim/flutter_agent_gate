import 'package:flutter/widgets.dart';

import '../context/behavior_tracker.dart';
import '../core/gate_candidate.dart';
import '../core/gate_decision.dart';
import '../ui/agent_loading.dart';
import 'agent_gate.dart';
import 'gate.dart';

/// A widget that decides *inline* and renders the chosen candidate's
/// `builder`. Ideal for declarative routers (GoRouter, auto_route, Beamer):
/// point a route at `GatePage(gate: myGate)` and the AI-chosen page renders
/// in place — no imperative navigation needed.
///
/// ```dart
/// GoRoute(path: '/checkout', builder: (_, __) => GatePage(gate: checkoutGate));
/// ```
class GatePage extends StatefulWidget {
  /// Creates a gate page.
  const GatePage({
    super.key,
    required this.gate,
    this.extra = const <String, Object?>{},
    this.loading,
    this.onDecided,
  });

  /// The gate.
  final Gate gate;

  /// Extra app context for this decision.
  final Map<String, Object?> extra;

  /// Custom loading widget (defaults to `AgentGate.loadingBuilder` /
  /// [AgentLoadingView]).
  final Widget? loading;

  /// Callback with the decision.
  final void Function(GateDecision decision, GateCandidate candidate)?
  onDecided;

  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  late Future<GateDecision> _future;

  @override
  void initState() {
    super.initState();
    _future = AgentGate.instance.decide(widget.gate, extra: widget.extra);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GateDecision>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return widget.loading ??
              AgentGate.instance.loadingBuilder?.call(context, null) ??
              const AgentLoadingView();
        }
        final decision = snap.data!;
        final candidate =
            widget.gate.candidate(decision.candidateId) ??
            widget.gate.fallbackCandidate;
        widget.onDecided?.call(decision, candidate);
        final b = candidate.builder;
        if (b == null) {
          return ErrorWidget.withDetails(
            message:
                'GatePage: candidate "${candidate.id}" has no builder. '
                'Provide a builder or use AgentGate.navigate with a router adapter.',
          );
        }
        return b(context);
      },
    );
  }
}

/// Wrap a page to automatically record `enterPage` / `exitPage` on the
/// tracker. Zero cost when consent is not granted.
///
/// ```dart
/// TrackedPage(id: 'cart', child: CartScreen())
/// ```
class TrackedPage extends StatefulWidget {
  /// Creates a tracked page.
  const TrackedPage({
    super.key,
    required this.id,
    required this.child,
    this.tracker,
  });

  /// Page id (must match `Gate.from`).
  final String id;

  /// The page.
  final Widget child;

  /// Tracker (defaults to `AgentGate.instance.tracker`).
  final BehaviorTracker? tracker;

  @override
  State<TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<TrackedPage> {
  BehaviorTracker get _t => widget.tracker ?? AgentGate.instance.tracker;

  @override
  void initState() {
    super.initState();
    _t.enterPage(widget.id);
  }

  @override
  void dispose() {
    _t.exitPage(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Convenience: a [GestureDetector]-free way to record taps on any child.
/// Records `tracker.tap(id)` then calls [onTap].
class TrackedTap extends StatelessWidget {
  /// Creates the wrapper.
  const TrackedTap({
    super.key,
    required this.id,
    required this.child,
    this.onTap,
    this.tracker,
  });

  /// Target id.
  final String id;

  /// Child.
  final Widget child;

  /// Handler.
  final VoidCallback? onTap;

  /// Tracker.
  final BehaviorTracker? tracker;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => (tracker ?? AgentGate.instance.tracker).tap(id),
      child: onTap == null
          ? child
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap,
              child: child,
            ),
    );
  }
}

/// A [NavigatorObserver] that feeds `enterPage`/`exitPage`/`back` from route
/// names. Add to `MaterialApp.navigatorObservers` (or GoRouter `observers`)
/// and name your routes; then you don't need [TrackedPage].
class GateNavigatorObserver extends NavigatorObserver {
  /// Creates the observer.
  GateNavigatorObserver({BehaviorTracker? tracker})
    : _tracker = tracker; // ignore: prefer_initializing_formals

  final BehaviorTracker? _tracker;
  BehaviorTracker get _t => _tracker ?? AgentGate.instance.tracker;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) _t.enterPage(name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _t.back();
    final name = route.settings.name;
    if (name != null) _t.exitPage(name);
    final prev = previousRoute?.settings.name;
    if (prev != null) _t.enterPage(prev);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final old = oldRoute?.settings.name;
    if (old != null) _t.exitPage(old);
    final n = newRoute?.settings.name;
    if (n != null) _t.enterPage(n);
  }
}
