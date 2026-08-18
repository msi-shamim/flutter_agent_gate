import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../context/gate_context.dart';
import 'gate_candidate.dart';
import 'gate_profile.dart';

/// Everything a decider needs to pick a candidate.
///
/// This is the payload that goes to your backend / AI. It is deliberately
/// plain JSON so any language or model can consume it.
@immutable
class GateRequest {
  /// Creates a request.
  const GateRequest({
    required this.gateId,
    required this.fromPage,
    required this.candidates,
    required this.context,
    required this.profile,
    required this.requestId,
    required this.timestamp,
    this.instructions,
  });

  /// Identifier of the gate (`home_to_checkout`).
  final String gateId;

  /// Where the user is coming from.
  final String fromPage;

  /// The B0…Bn candidates.
  final List<GateCandidate> candidates;

  /// Behavioural + app context (already redacted / consent-filtered).
  final GateContext context;

  /// Risk / recommendation / general.
  final GateProfile profile;

  /// Unique id for this decision (also usable as an idempotency key).
  final String requestId;

  /// Client timestamp (UTC).
  final DateTime timestamp;

  /// Optional developer instructions for the AI ("prefer cheaper options for
  /// students", "never route to premium if balance < 100").
  final String? instructions;

  /// Serializes to the canonical `agent_gate/v1` payload.
  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 'agent_gate/v1',
        'request_id': requestId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'gate_id': gateId,
        'from_page': fromPage,
        'profile': profile.name,
        if (instructions != null) 'instructions': instructions,
        'candidates': candidates.map((c) => c.toJson()).toList(),
        'context': context.toJson(),
      };

  /// Stable hash for cache keys — excludes request id and timestamp.
  String get cacheKey {
    final body = jsonEncode(<String, Object?>{
      'gate_id': gateId,
      'from_page': fromPage,
      'candidates': candidates.map((c) => c.id).toList(),
      'context': context.toJson(),
      if (instructions != null) 'instructions': instructions,
    });
    return sha256.convert(utf8.encode(body)).toString();
  }
}
