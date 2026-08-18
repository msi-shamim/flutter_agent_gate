import 'dart:async';

import 'package:meta/meta.dart';

import '../core/gate_decision.dart';
import '../core/gate_request.dart';

/// One audit entry: what was asked, what was decided, and what happened.
@immutable
class GateAuditEntry {
  /// Creates an entry.
  const GateAuditEntry({
    required this.requestId,
    required this.gateId,
    required this.fromPage,
    required this.profile,
    required this.decision,
    required this.decider,
    required this.at,
    required this.candidateIds,
    this.error,
    this.contextHash,
  });

  /// Request id.
  final String requestId;

  /// Gate id.
  final String gateId;

  /// Origin page.
  final String fromPage;

  /// Profile name.
  final String profile;

  /// Final decision (after allow-list / confidence checks).
  final GateDecision decision;

  /// Decider name.
  final String decider;

  /// UTC timestamp.
  final DateTime at;

  /// Candidate ids offered.
  final List<String> candidateIds;

  /// Error text if the agent failed and fallback was used.
  final String? error;

  /// Hash of the context (so you can prove *what* was sent without storing it).
  final String? contextHash;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
        'request_id': requestId,
        'gate_id': gateId,
        'from_page': fromPage,
        'profile': profile,
        'decider': decider,
        'candidates': candidateIds,
        'decision': decision.toJson(),
        'at': at.toIso8601String(),
        if (error != null) 'error': error,
        if (contextHash != null) 'context_hash': contextHash,
      };
}

/// Receives audit entries. Implement to ship to your SIEM / analytics /
/// database. [MemoryAuditSink] is included for tests and debugging.
abstract interface class GateAuditSink {
  /// Called once per completed gate decision. Must not throw.
  FutureOr<void> record(GateAuditEntry entry);
}

/// Keeps entries in memory (bounded).
class MemoryAuditSink implements GateAuditSink {
  /// Creates the sink.
  MemoryAuditSink({this.capacity = 500});

  /// Max entries kept.
  final int capacity;
  final List<GateAuditEntry> _entries = <GateAuditEntry>[];

  /// Recorded entries, oldest first.
  List<GateAuditEntry> get entries => List.unmodifiable(_entries);

  @override
  void record(GateAuditEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  /// Clears entries.
  void clear() => _entries.clear();
}

/// Fan-out to several sinks.
class MultiAuditSink implements GateAuditSink {
  /// Creates the sink.
  const MultiAuditSink(this.sinks);

  /// Targets.
  final List<GateAuditSink> sinks;

  @override
  Future<void> record(GateAuditEntry entry) async {
    for (final s in sinks) {
      try {
        await s.record(entry);
      } catch (_) {
        // Audit must never break navigation.
      }
    }
  }
}

/// Lifecycle hooks — analytics, logging, UI side-effects.
abstract class GateObserver {
  /// Creates an observer.
  const GateObserver();

  /// A gate started deciding.
  void onStart(GateRequest request) {}

  /// A decision was reached (any source).
  void onDecision(GateRequest request, GateDecision decision) {}

  /// The agent failed; fallback was used.
  void onFallback(GateRequest request, Object error, GateDecision fallback) {}

  /// Navigation completed.
  void onNavigated(GateRequest request, GateDecision decision) {}
}
