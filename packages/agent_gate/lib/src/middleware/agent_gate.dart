import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../adapters/navigation_adapter.dart';
import '../audit/audit.dart';
import '../context/behavior_tracker.dart';
import '../context/gate_context.dart';
import '../context/redactor.dart';
import '../core/gate_candidate.dart';
import '../core/gate_config.dart';
import '../core/gate_decision.dart';
import '../core/gate_request.dart';
import '../decider/agent_decider.dart';
import '../ui/agent_loading.dart';
import 'gate.dart';

/// Result of [AgentGate.navigate].
@immutable
class GateResult {
  /// Creates a result.
  GateResult({
    required this.request,
    required this.decision,
    required this.candidate,
    Future<Object?>? navigationResult,
  }) : navigationResult = navigationResult ?? Future<Object?>.value(null);

  /// The request that was sent.
  final GateRequest request;

  /// The final decision.
  final GateDecision decision;

  /// The candidate that was routed to.
  final GateCandidate candidate;

  /// The future returned by the adapter (for `Navigator.push` / `Get.toNamed`
  /// it completes with the pop result when the destination page closes).
  /// Await it only if you want that.
  final Future<Object?> navigationResult;
}

/// The middleware. Configure once, then call [navigate] or [decide].
///
/// ```dart
/// AgentGate.configure(
///   decider: HttpDecider(endpoint: Uri.parse('https://api.example.com/gate')),
///   adapter: RouteNameAdapter((ctx, route, _) async => ctx!.go(route)),
/// );
/// ```
class AgentGate {
  AgentGate._();

  /// Global instance.
  static final AgentGate instance = AgentGate._();

  /// Configure the global instance. Call once at startup (may be called
  /// again to swap pieces, e.g. after login).
  static void configure({
    AgentDecider? decider,
    NavigationAdapter? adapter,
    BehaviorTracker? tracker,
    GateConfig? config,
    GateAuditSink? auditSink,
    List<GateObserver>? observers,
    AgentLoadingBuilder? loadingBuilder,
    GateContextBuilder? contextBuilder,
    Set<String>? redactKeys,
    bool? includeRawEvents,
    int? historyDepth,
  }) {
    final i = instance;
    if (decider != null) i.decider = decider;
    if (adapter != null) i.adapter = adapter;
    if (tracker != null) i.tracker = tracker;
    if (config != null) i.config = config;
    if (auditSink != null) i.auditSink = auditSink;
    if (observers != null) i.observers = List.of(observers);
    if (loadingBuilder != null) i.loadingBuilder = loadingBuilder;
    if (contextBuilder != null) i.contextBuilder = contextBuilder;
    if (redactKeys != null) i.redactKeys = redactKeys;
    if (includeRawEvents != null) i.includeRawEvents = includeRawEvents;
    if (historyDepth != null) i.historyDepth = historyDepth;
  }

  /// Resets to defaults (tests).
  @visibleForTesting
  static void reset() {
    final i = instance;
    i.decider = null;
    i.adapter = const NavigatorAdapter();
    i.tracker = BehaviorTracker(observeLifecycle: false);
    i.config = const GateConfig();
    i.auditSink = MemoryAuditSink();
    i.observers = <GateObserver>[];
    i.loadingBuilder = null;
    i.contextBuilder = null;
    i.redactKeys = Redactor.defaultKeys;
    i.includeRawEvents = false;
    i.historyDepth = 5;
    i._cache.clear();
  }

  /// The intelligence. Required before the first [decide].
  AgentDecider? decider;

  /// How to actually navigate. Default: plain `Navigator`.
  NavigationAdapter adapter = const NavigatorAdapter();

  /// Behaviour tracker (consent-gated).
  BehaviorTracker tracker = BehaviorTracker(observeLifecycle: false);

  /// Global default config.
  GateConfig config = const GateConfig();

  /// Where audit entries go. Default: in-memory (swap for production).
  GateAuditSink auditSink = MemoryAuditSink();

  /// Observers.
  List<GateObserver> observers = <GateObserver>[];

  /// Custom loading UI.
  AgentLoadingBuilder? loadingBuilder;

  /// Global app-context contribution (auth tier, cart, locale…).
  GateContextBuilder? contextBuilder;

  /// Keys redacted from context before it leaves the device.
  Set<String> redactKeys = Redactor.defaultKeys;

  /// Include raw events in context (default false — summaries only).
  bool includeRawEvents = false;

  /// How many previous page summaries to include.
  int historyDepth = 5;

  final Map<String, _CachedDecision> _cache = <String, _CachedDecision>{};
  int _seq = 0;
  final Random _rng = Random.secure();

  // ── Public API ────────────────────────────────────────────────────────

  /// Decide (no navigation). Useful for prefetching or for driving your own
  /// state management. Never throws: on any failure returns the fallback.
  Future<GateDecision> decide(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
    GateContext? contextOverride,
  }) async {
    final r = await _run(gate, extra: extra, contextOverride: contextOverride);
    return r.decision;
  }

  /// Warm the cache for [gate] so a later [navigate] is instant. Only
  /// meaningful when the effective config has a `cacheTtl`.
  Future<void> prefetch(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => decide(gate, extra: extra);

  /// Decide and navigate. Shows the loading UI (unless disabled) as an
  /// overlay while the decision is in flight.
  ///
  /// [context] may be null when your adapter does not need one (GetX,
  /// GoRouter with a global router). The loading overlay needs a context;
  /// without one it is skipped.
  Future<GateResult> navigate(
    Gate gate, {
    BuildContext? context,
    Map<String, Object?> extra = const <String, Object?>{},
    GateContext? contextOverride,
  }) async {
    final cfg = gate.config ?? config;
    OverlayEntry? overlay;

    Stream<String>? reasoningStream;
    if (cfg.showLoadingUi && context != null && context.mounted) {
      final overlayState = Overlay.maybeOf(context, rootOverlay: true);
      if (overlayState != null) {
        overlay = OverlayEntry(
          builder: (ctx) => _LoadingHost(
            builder: loadingBuilder,
            reasoning: () => reasoningStream,
          ),
        );
        overlayState.insert(overlay);
      }
    }

    try {
      final r = await _run(
        gate,
        extra: extra,
        contextOverride: contextOverride,
        onRequest: (req) {
          reasoningStream = (gate.decider ?? decider)?.reasoning(req);
        },
      );
      overlay?.remove();
      overlay = null;
      // NOTE: deliberately not awaited. Navigator.push / Get.toNamed return
      // a future that completes when the pushed route is *popped*; awaiting
      // it here would block the caller for the lifetime of the next page.
      final Future<Object?> navFuture = adapter.navigate(
        context != null && context.mounted ? context : null,
        r.candidate,
        r.decision,
      );
      for (final o in observers) {
        o.onNavigated(r.request, r.decision);
      }
      return GateResult(
        request: r.request,
        decision: r.decision,
        candidate: r.candidate,
        navigationResult: navFuture,
      );
    } finally {
      overlay?.remove();
    }
  }

  /// Clears cached decisions (e.g. on logout).
  void clearCache() => _cache.clear();

  // ── Pipeline ──────────────────────────────────────────────────────────

  Future<GateResult> _run(
    Gate gate, {
    required Map<String, Object?> extra,
    GateContext? contextOverride,
    void Function(GateRequest)? onRequest,
  }) async {
    final cfg = gate.config ?? config;
    final d = gate.decider ?? decider;
    final ctx = contextOverride ?? await _buildContext(gate, cfg, extra);
    final request = GateRequest(
      gateId: gate.id,
      fromPage: gate.from,
      candidates: gate.candidates,
      context: ctx,
      profile: cfg.profile,
      requestId: _newRequestId(),
      timestamp: DateTime.now().toUtc(),
      instructions: gate.instructions,
    );
    onRequest?.call(request);
    for (final o in observers) {
      o.onStart(request);
    }

    GateDecision decision;
    String? error;

    // 1. Cache
    final cached = cfg.cacheTtl == null ? null : _cache[request.cacheKey];
    if (cached != null && !cached.isExpired) {
      decision = cached.decision.copyWith(source: DecisionSource.cache);
    } else if (d == null) {
      error = 'no decider configured';
      decision = GateDecision.fallback(gate.fallback, reason: error);
    } else {
      // 2. Agent with retries + hard timeout
      final sw = Stopwatch()..start();
      try {
        decision = await _withRetries(d, request, cfg).timeout(cfg.timeout);
        decision = decision.copyWith(latency: decision.latency ?? sw.elapsed);
        if (cfg.cacheTtl != null &&
            decision.source != DecisionSource.fallback) {
          _cache[request.cacheKey] = _CachedDecision(decision, cfg.cacheTtl!);
        }
      } on TimeoutException {
        error = 'timeout after ${cfg.timeout.inMilliseconds}ms';
        decision = GateDecision.fallback(gate.fallback, reason: error);
      } catch (e) {
        error = e.toString();
        decision = GateDecision.fallback(gate.fallback, reason: error);
      }
    }

    // 3. Validate: known id, allow-list, confidence
    final chosen = gate.candidate(decision.candidateId);
    if (chosen == null) {
      error = 'decider returned unknown candidate "${decision.candidateId}"';
      decision = GateDecision.fallback(gate.fallback, reason: error);
    } else if (cfg.allowedCandidateIds != null &&
        !cfg.allowedCandidateIds!.contains(decision.candidateId) &&
        decision.source != DecisionSource.fallback) {
      error = 'candidate "${decision.candidateId}" not in allow-list';
      decision = GateDecision.fallback(gate.fallback, reason: error);
    } else if (decision.source == DecisionSource.agent &&
        decision.confidence < cfg.minConfidence) {
      error =
          'confidence ${decision.confidence.toStringAsFixed(2)} '
          '< ${cfg.minConfidence}';
      decision = GateDecision.fallback(
        gate.fallback,
        reason: '$error (agent suggested ${decision.candidateId})',
      );
    }
    final candidate = gate.candidate(decision.candidateId)!;

    // 4. Observe + audit
    for (final o in observers) {
      if (error != null && decision.source == DecisionSource.fallback) {
        o.onFallback(request, error, decision);
      }
      o.onDecision(request, decision);
    }
    try {
      await auditSink.record(
        GateAuditEntry(
          requestId: request.requestId,
          gateId: gate.id,
          fromPage: gate.from,
          profile: cfg.profile.name,
          decision: decision,
          decider: d?.name ?? 'none',
          at: DateTime.now().toUtc(),
          candidateIds: gate.candidates.map((c) => c.id).toList(),
          error: error,
          contextHash: request.cacheKey,
        ),
      );
    } catch (_) {
      // never let audit break navigation
    }

    return GateResult(
      request: request,
      decision: decision,
      candidate: candidate,
    );
  }

  Future<GateDecision> _withRetries(
    AgentDecider d,
    GateRequest req,
    GateConfig cfg,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        return await d.decide(req);
      } on DeciderTransientException {
        if (attempt++ >= cfg.maxRetries) rethrow;
        await Future<void>.delayed(cfg.retryDelay);
      }
    }
  }

  Future<GateContext> _buildContext(
    Gate gate,
    GateConfig cfg,
    Map<String, Object?> extra,
  ) async {
    final consent = !cfg.requireConsent || tracker.consent.granted;
    final app = <String, Object?>{
      ...?await contextBuilder?.call(),
      ...?await gate.contextBuilder?.call(),
      ...extra,
    };
    final redactor = Redactor(<String>{...redactKeys, ...cfg.redactKeys});
    final redactedApp = redactor.applyToMap(app);

    if (!consent) {
      return GateContext(app: redactedApp, device: _device());
    }
    final current = tracker.summaryFor(gate.from);
    final history = tracker
        .recentSummaries(count: historyDepth + 1)
        .where((s) => s.page != gate.from)
        .take(historyDepth)
        .toList();
    return GateContext(
      currentPage: current,
      history: history,
      rawEvents: includeRawEvents ? tracker.eventsFor(gate.from) : const [],
      app: redactedApp,
      device: _device(),
      consentGranted: true,
    );
  }

  Map<String, Object?> _device() => <String, Object?>{
    'platform': defaultTargetPlatform.name,
    'locale': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    'debug': kDebugMode,
  };

  String _newRequestId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = _rng.nextInt(1 << 32).toRadixString(36);
    return '$t-${(_seq++).toRadixString(36)}-$r';
  }
}

class _CachedDecision {
  _CachedDecision(this.decision, Duration ttl)
    : expiresAt = DateTime.now().add(ttl);
  final GateDecision decision;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _LoadingHost extends StatelessWidget {
  const _LoadingHost({required this.builder, required this.reasoning});
  final AgentLoadingBuilder? builder;
  final Stream<String>? Function() reasoning;

  @override
  Widget build(BuildContext context) {
    final r = reasoning();
    return AbsorbPointer(
      child: builder?.call(context, r) ?? AgentLoadingView(reasoning: r),
    );
  }
}
