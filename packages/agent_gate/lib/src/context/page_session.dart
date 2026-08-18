import 'package:meta/meta.dart';

import 'behavior_event.dart';

/// Aggregated statistics for one visit to one page.
///
/// This is what most deciders actually want: not 400 raw events, but
/// "user spent 42 s, tapped Pay 3 times, got 2 validation errors, scrolled
/// 80 %, went back once".
@immutable
class PageSessionSummary {
  /// Creates a summary.
  const PageSessionSummary({
    required this.page,
    required this.enteredAt,
    required this.dwell,
    required this.tapCount,
    required this.attemptCount,
    required this.failureCount,
    required this.successCount,
    required this.validationErrorCount,
    required this.backCount,
    required this.fieldEditCount,
    required this.maxScrollFraction,
    required this.attemptsByName,
    required this.tapsByTarget,
    required this.eventCount,
    this.hesitationMs,
  });

  /// Builds a summary from raw events for a page.
  factory PageSessionSummary.fromEvents(
    String page,
    List<BehaviorEvent> events, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now().toUtc();
    DateTime? entered;
    DateTime? exited;
    var taps = 0, attempts = 0, failures = 0, successes = 0;
    var validation = 0, backs = 0, edits = 0;
    double maxScroll = 0;
    final attemptsByName = <String, int>{};
    final tapsByTarget = <String, int>{};
    DateTime? firstInteraction;

    for (final e in events) {
      if (e.page != page) continue;
      switch (e.type) {
        case BehaviorEventType.pageEnter:
          entered ??= e.at;
        case BehaviorEventType.pageExit:
          exited = e.at;
        case BehaviorEventType.tap:
          taps++;
          if (e.target != null) {
            tapsByTarget[e.target!] = (tapsByTarget[e.target!] ?? 0) + 1;
          }
        case BehaviorEventType.attempt:
          attempts++;
          final k = e.name ?? e.target ?? 'attempt';
          attemptsByName[k] = (attemptsByName[k] ?? 0) + 1;
        case BehaviorEventType.failure:
          failures++;
        case BehaviorEventType.success:
          successes++;
        case BehaviorEventType.validationError:
          validation++;
        case BehaviorEventType.back:
          backs++;
        case BehaviorEventType.fieldEdit:
          edits++;
        case BehaviorEventType.scroll:
          final v = e.value?.toDouble() ?? 0;
          if (v > maxScroll) maxScroll = v;
        case BehaviorEventType.longPress:
        case BehaviorEventType.fieldFocus:
        case BehaviorEventType.fieldBlur:
        case BehaviorEventType.lifecycle:
        case BehaviorEventType.custom:
          break;
      }
      if (e.type != BehaviorEventType.pageEnter &&
          e.type != BehaviorEventType.pageExit &&
          e.type != BehaviorEventType.lifecycle) {
        firstInteraction ??= e.at;
      }
    }

    final start = entered ?? (events.isNotEmpty ? events.first.at : n);
    final end = exited ?? n;
    return PageSessionSummary(
      page: page,
      enteredAt: start,
      dwell: end.difference(start),
      tapCount: taps,
      attemptCount: attempts,
      failureCount: failures,
      successCount: successes,
      validationErrorCount: validation,
      backCount: backs,
      fieldEditCount: edits,
      maxScrollFraction: maxScroll.clamp(0.0, 1.0),
      attemptsByName: Map.unmodifiable(attemptsByName),
      tapsByTarget: Map.unmodifiable(tapsByTarget),
      eventCount: events.where((e) => e.page == page).length,
      hesitationMs: firstInteraction?.difference(start).inMilliseconds,
    );
  }

  /// Page id.
  final String page;

  /// When the page was entered.
  final DateTime enteredAt;

  /// Time spent on the page.
  final Duration dwell;

  /// Total taps.
  final int tapCount;

  /// Total attempts (submit / pay / login …).
  final int attemptCount;

  /// Failed attempts.
  final int failureCount;

  /// Successful attempts.
  final int successCount;

  /// Validation errors shown.
  final int validationErrorCount;

  /// Back navigations.
  final int backCount;

  /// Field edits.
  final int fieldEditCount;

  /// Deepest scroll (0..1).
  final double maxScrollFraction;

  /// Attempts grouped by name.
  final Map<String, int> attemptsByName;

  /// Taps grouped by target.
  final Map<String, int> tapsByTarget;

  /// Total events on this page.
  final int eventCount;

  /// Milliseconds before the first interaction (null = none yet).
  final int? hesitationMs;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
        'page': page,
        'entered_at': enteredAt.toIso8601String(),
        'dwell_ms': dwell.inMilliseconds,
        'taps': tapCount,
        'attempts': attemptCount,
        'failures': failureCount,
        'successes': successCount,
        'validation_errors': validationErrorCount,
        'backs': backCount,
        'field_edits': fieldEditCount,
        'max_scroll': maxScrollFraction,
        if (hesitationMs != null) 'hesitation_ms': hesitationMs,
        if (attemptsByName.isNotEmpty) 'attempts_by_name': attemptsByName,
        if (tapsByTarget.isNotEmpty) 'taps_by_target': tapsByTarget,
        'events': eventCount,
      };
}
