import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Payload delivered via `Get.arguments` by [GetxAdapter].
///
/// Same reasoning as the GoRouter companion's `GateExtra`: `Get.arguments`
/// is `dynamic`, so a dedicated type lets a destination page tell "reached
/// through a gate" apart from any other arguments, and carries the candidate
/// alongside the decision. If your app already passes arguments to that
/// page, use `GetxAdapter.argumentsBuilder` to merge.
@immutable
class GateArguments {
  /// Creates the payload.
  const GateArguments({required this.decision, required this.candidate});

  /// The validated decision.
  final GateDecision decision;

  /// The chosen candidate.
  final GateCandidate candidate;

  /// Reads the current route's arguments; null if not a [GateArguments].
  ///
  /// ```dart
  /// final why = GateArguments.current?.decision.reason;
  /// ```
  static GateArguments? get current {
    final Object? args = Get.arguments;
    return args is GateArguments ? args : null;
  }

  @override
  String toString() =>
      'GateArguments(${candidate.id}, ${decision.source.name})';
}
