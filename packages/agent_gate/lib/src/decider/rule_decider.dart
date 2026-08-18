import '../core/gate_decision.dart';
import '../core/gate_request.dart';
import 'agent_decider.dart';

/// A deterministic rule: if [when] matches, route to [candidateId].
class GateRule {
  /// Creates a rule.
  const GateRule({
    required this.id,
    required this.when,
    required this.candidateId,
    this.reason,
    this.confidence = 1.0,
  });

  /// Rule id (audit).
  final String id;

  /// Predicate over the request.
  final bool Function(GateRequest r) when;

  /// Target candidate.
  final String candidateId;

  /// Reason to attach.
  final String? reason;

  /// Confidence to attach.
  final double confidence;
}

/// Evaluates [rules] in order; first match wins.
///
/// If no rule matches it throws [NoRuleMatched] so a [CompositeDecider] can
/// move on to the AI. Rules are the *floor* for risk profiles: put your
/// non-negotiables here (velocity limits, blocked geos, KYC state…).
class RuleDecider implements AgentDecider {
  /// Creates the decider.
  const RuleDecider(this.rules);

  /// Ordered rules.
  final List<GateRule> rules;

  @override
  String get name => 'RuleDecider';

  @override
  Stream<String>? reasoning(GateRequest request) => null;

  @override
  Future<GateDecision> decide(GateRequest request) async {
    for (final rule in rules) {
      if (rule.when(request)) {
        return GateDecision(
          candidateId: rule.candidateId,
          source: DecisionSource.rule,
          confidence: rule.confidence,
          reason: rule.reason ?? 'rule:${rule.id}',
          model: 'rule:${rule.id}',
        );
      }
    }
    throw const NoRuleMatched();
  }
}

/// Signals that no rule matched; [CompositeDecider] treats it as "continue".
class NoRuleMatched implements Exception {
  /// Creates the marker exception.
  const NoRuleMatched();
}

/// Tries deciders in order. A [NoRuleMatched] moves to the next; any other
/// error also moves on (and is remembered), and if all fail the last error
/// is rethrown.
///
/// Typical risk setup: `CompositeDecider([RuleDecider(rules), HttpDecider(...)])`.
class CompositeDecider implements AgentDecider {
  /// Creates the composite.
  const CompositeDecider(this.deciders);

  /// Ordered deciders.
  final List<AgentDecider> deciders;

  @override
  String get name => 'Composite(${deciders.map((d) => d.name).join(' > ')})';

  @override
  Stream<String>? reasoning(GateRequest request) {
    for (final d in deciders) {
      final s = d.reasoning(request);
      if (s != null) return s;
    }
    return null;
  }

  @override
  Future<GateDecision> decide(GateRequest request) async {
    Object? lastError;
    StackTrace? lastStack;
    for (final d in deciders) {
      try {
        return await d.decide(request);
      } on NoRuleMatched {
        continue;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack!);
    }
    throw const DeciderFormatException('no decider produced a decision');
  }
}
