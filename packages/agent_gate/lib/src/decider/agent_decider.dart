import '../core/gate_decision.dart';
import '../core/gate_request.dart';

/// Thrown by deciders for transient problems (network, 5xx). The gate will
/// retry these up to `GateConfig.maxRetries` times.
class DeciderTransientException implements Exception {
  /// Creates the exception.
  const DeciderTransientException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// Underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'DeciderTransientException: $message';
}

/// Thrown by deciders when the answer is unusable (bad JSON, unknown id).
/// The gate does **not** retry these; it falls back.
class DeciderFormatException implements Exception {
  /// Creates the exception.
  const DeciderFormatException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// Underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'DeciderFormatException: $message';
}

/// The single abstraction between AgentGate and *your* intelligence.
///
/// Implement this to plug in anything: your backend, an on-device rules
/// engine, an OpenAI/Anthropic/Gemini SDK, a local model. AgentGate ships
/// [HttpDecider], [CallbackDecider], [RuleDecider] and [CompositeDecider].
///
/// Contract:
/// * Return a [GateDecision] whose `candidateId` is one of
///   `request.candidates`.
/// * Throw [DeciderTransientException] for retryable errors.
/// * Throw [DeciderFormatException] for unusable answers.
/// * Respect cancellation — the gate wraps you in a timeout regardless.
abstract interface class AgentDecider {
  /// Decide which candidate to route to.
  Future<GateDecision> decide(GateRequest request);

  /// Optional: stream partial reasoning for the loading UI. Default: none.
  Stream<String>? reasoning(GateRequest request) => null;

  /// Human-readable name for audit logs.
  String get name => runtimeType.toString();
}
