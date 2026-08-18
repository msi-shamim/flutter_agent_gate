import 'dart:async';

import 'package:meta/meta.dart';

import '../core/gate_candidate.dart';
import '../core/gate_config.dart';
import '../decider/agent_decider.dart';

/// Signature for per-gate app-context contribution.
typedef GateContextBuilder = FutureOr<Map<String, Object?>> Function();

/// A declared decision point: from page A, to one of [candidates].
///
/// Declare gates once (top-level constants are fine) and reuse them.
///
/// ```dart
/// final checkoutGate = Gate(
///   id: 'cart_to_checkout',
///   from: 'cart',
///   fallback: 'checkout_standard',
///   config: const GateConfig.recommendation(),
///   candidates: [
///     GateCandidate(id: 'checkout_express', label: 'Express', description: '…', route: '/checkout/express'),
///     GateCandidate(id: 'checkout_standard', label: 'Standard', description: '…', route: '/checkout'),
///     GateCandidate(id: 'checkout_bnpl', label: 'Pay later', description: '…', route: '/checkout/bnpl'),
///   ],
/// );
/// ```
@immutable
class Gate {
  /// Creates a gate. Throws if [candidates] is empty, exceeds
  /// [kMaxGateCandidates], contains duplicate ids, or [fallback] is unknown.
  Gate({
    required this.id,
    required this.from,
    required this.candidates,
    required this.fallback,
    this.config,
    this.instructions,
    this.decider,
    this.contextBuilder,
  }) {
    if (candidates.isEmpty) {
      throw ArgumentError.value(candidates, 'candidates', 'must not be empty');
    }
    if (candidates.length > kMaxGateCandidates) {
      throw ArgumentError.value(
        candidates.length,
        'candidates',
        'at most $kMaxGateCandidates candidates per gate',
      );
    }
    final ids = <String>{};
    for (final c in candidates) {
      if (!ids.add(c.id)) {
        throw ArgumentError('duplicate candidate id "${c.id}" in gate "$id"');
      }
    }
    if (!ids.contains(fallback)) {
      throw ArgumentError('fallback "$fallback" is not a candidate of "$id"');
    }
  }

  /// Unique gate id.
  final String id;

  /// Origin page id (used for tracker summaries and prompts).
  final String from;

  /// B0…Bn.
  final List<GateCandidate> candidates;

  /// Candidate id used when the AI can't / shouldn't decide.
  final String fallback;

  /// Per-gate config override (falls back to `AgentGate.config`).
  final GateConfig? config;

  /// Extra guidance for the AI.
  final String? instructions;

  /// Per-gate decider override.
  final AgentDecider? decider;

  /// Per-gate app-context contribution (merged after the global one).
  final GateContextBuilder? contextBuilder;

  /// Look up a candidate by id.
  GateCandidate? candidate(String id) {
    for (final c in candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The fallback candidate object.
  GateCandidate get fallbackCandidate => candidate(fallback)!;
}
