import 'package:flutter/widgets.dart';

/// Maximum number of candidates a single gate may hold (`B0 … B999`).
const int kMaxGateCandidates = 1000;

/// One possible destination the gate may route to.
///
/// A candidate is described in plain language so that an AI model (or a
/// rule engine) can pick between them. The [id] MUST be unique inside a gate
/// and is what the decider returns.
@immutable
class GateCandidate {
  /// Creates a candidate.
  ///
  /// Provide either a [builder] (for `Navigator`) or a [route] name/path
  /// (for `GoRouter`, `GetX`, or your own adapter). Both may be set.
  const GateCandidate({
    required this.id,
    required this.label,
    required this.description,
    this.builder,
    this.route,
    this.tags = const <String>[],
    this.priority = 0,
    this.metadata = const <String, Object?>{},
  });

  /// Stable identifier, e.g. `checkout_express`, `step_up_auth`.
  final String id;

  /// Human-readable label shown in loading UI / audit logs.
  final String label;

  /// Plain-language description of *when* this page is the right destination.
  /// This is what the AI reads — write it like you would explain it to a
  /// new colleague.
  final String description;

  /// Widget builder for the plain `Navigator` adapter.
  final WidgetBuilder? builder;

  /// Route name/path for router-based adapters (`/checkout/express`).
  final String? route;

  /// Free-form tags (`risk`, `upsell`, `default`, …) usable in rules.
  final List<String> tags;

  /// Tie-breaker used by rule/fallback deciders (higher wins).
  final int priority;

  /// Anything else you want the decider to see (price tier, eligibility…).
  final Map<String, Object?> metadata;

  /// Serializes the candidate for a decider payload. Widget builders are
  /// intentionally omitted.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'description': description,
    if (route != null) 'route': route,
    if (tags.isNotEmpty) 'tags': tags,
    'priority': priority,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  String toString() => 'GateCandidate($id)';

  @override
  bool operator ==(Object other) => other is GateCandidate && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
