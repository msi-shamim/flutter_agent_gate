import 'package:meta/meta.dart';

import 'behavior_event.dart';
import 'page_session.dart';

/// The context handed to a decider.
///
/// Three layers, all optional:
/// 1. [currentPage] — summary of behaviour on the page the user is leaving.
/// 2. [history] — summaries of previous pages this session.
/// 3. [app] — whatever your app adds (auth tier, cart total, locale, KYC
///    status, A/B bucket …). Free-form JSON.
///
/// [baseline] is where a backend can inject "how a typical user behaves on
/// this page" so the model can compare. The device never computes it.
@immutable
class GateContext {
  /// Creates a context.
  const GateContext({
    this.currentPage,
    this.history = const <PageSessionSummary>[],
    this.rawEvents = const <BehaviorEvent>[],
    this.app = const <String, Object?>{},
    this.baseline,
    this.device = const <String, Object?>{},
    this.consentGranted = false,
  });

  /// Empty context.
  static const GateContext empty = GateContext();

  /// Behaviour summary of the page being left.
  final PageSessionSummary? currentPage;

  /// Previous pages this session (most recent first).
  final List<PageSessionSummary> history;

  /// Optional raw events (off by default — summaries are usually enough).
  final List<BehaviorEvent> rawEvents;

  /// App-supplied context. Redaction applies.
  final Map<String, Object?> app;

  /// Optional population baseline supplied by your backend.
  final Map<String, Object?>? baseline;

  /// Non-identifying device hints (platform, locale, screen class…).
  final Map<String, Object?> device;

  /// Whether behavioural tracking consent was granted.
  final bool consentGranted;

  /// Copy with overrides.
  GateContext copyWith({
    PageSessionSummary? currentPage,
    List<PageSessionSummary>? history,
    List<BehaviorEvent>? rawEvents,
    Map<String, Object?>? app,
    Map<String, Object?>? baseline,
    Map<String, Object?>? device,
    bool? consentGranted,
  }) =>
      GateContext(
        currentPage: currentPage ?? this.currentPage,
        history: history ?? this.history,
        rawEvents: rawEvents ?? this.rawEvents,
        app: app ?? this.app,
        baseline: baseline ?? this.baseline,
        device: device ?? this.device,
        consentGranted: consentGranted ?? this.consentGranted,
      );

  /// Merges [extra] into [app].
  GateContext withApp(Map<String, Object?> extra) =>
      copyWith(app: <String, Object?>{...app, ...extra});

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
        'consent': consentGranted,
        if (currentPage != null) 'current_page': currentPage!.toJson(),
        if (history.isNotEmpty)
          'history': history.map((h) => h.toJson()).toList(),
        if (rawEvents.isNotEmpty)
          'events': rawEvents.map((e) => e.toJson()).toList(),
        if (app.isNotEmpty) 'app': app,
        if (baseline != null) 'baseline': baseline,
        if (device.isNotEmpty) 'device': device,
      };
}
