import 'dart:async';

import '../core/gate_decision.dart';
import '../core/gate_request.dart';
import 'agent_decider.dart';

/// Signature for a developer-supplied decision function.
typedef DecideCallback = FutureOr<GateDecision> Function(GateRequest request);

/// Signature for optional streamed reasoning.
typedef ReasoningCallback = Stream<String>? Function(GateRequest request);

/// Wraps any Dart function as a decider.
///
/// Use this when you want to call an SDK directly from the app (e.g. with a
/// key loaded from `flutter_dotenv`) or run your own on-device logic.
///
/// ```dart
/// CallbackDecider((req) async {
///   final body = PromptBuilder().openAiRequest(req)..['model'] = 'gpt-4o-mini';
///   final json = await myOpenAiClient.chat(body);
///   return GateDecision.fromJson(parseToolArgs(json));
/// });
/// ```
class CallbackDecider implements AgentDecider {
  /// Creates the decider.
  const CallbackDecider(
    this.onDecide, {
    this.onReasoning,
    this.label = 'CallbackDecider',
  });

  /// The function that decides.
  final DecideCallback onDecide;

  /// Optional streamed reasoning.
  final ReasoningCallback? onReasoning;

  /// Name for audit logs.
  final String label;

  @override
  String get name => label;

  @override
  Future<GateDecision> decide(GateRequest request) async => onDecide(request);

  @override
  Stream<String>? reasoning(GateRequest request) => onReasoning?.call(request);
}
