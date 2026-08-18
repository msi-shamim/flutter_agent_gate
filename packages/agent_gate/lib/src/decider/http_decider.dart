import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../core/gate_decision.dart';
import '../core/gate_request.dart';
import 'agent_decider.dart';

/// Signature for adding auth headers per request (bearer tokens, session
/// cookies, app-attest tokens…). Called right before each POST.
typedef HeaderProvider = FutureOr<Map<String, String>> Function(
  GateRequest request,
);

/// The **recommended** decider: POST the request to *your* backend, which
/// holds the AI keys, the population baseline, the fraud signals, and the
/// business rules. Your backend answers with
/// `{ "candidate_id": "...", "confidence": 0.87, "reason": "..." }`.
///
/// Optional payload signing: if [signingSecret] is supplied, an
/// `X-AgentGate-Signature: sha256=<hex hmac>` header is added over the raw
/// body, plus `X-AgentGate-Timestamp`. Combine with a short replay window on
/// the server. (For serious fraud use, prefer platform attestation —
/// App Attest / Play Integrity — and pass the token via [headers].)
class HttpDecider implements AgentDecider {
  /// Creates an HTTP decider.
  HttpDecider({
    required this.endpoint,
    this.headers,
    this.signingSecret,
    http.Client? client,
    this.method = 'POST',
    this.decodeResponse,
  }) : _client = client ?? http.Client();

  /// Where to POST.
  final Uri endpoint;

  /// Dynamic headers (auth).
  final HeaderProvider? headers;

  /// Optional HMAC secret (only for integrity, not secrecy — it ships in
  /// the app binary).
  final String? signingSecret;

  /// HTTP method (POST default).
  final String method;

  /// Override if your backend wraps the decision, e.g. `{"data": {...}}`.
  final Map<String, Object?> Function(Map<String, Object?> body)?
  decodeResponse;

  final http.Client _client;

  @override
  String get name => 'HttpDecider(${endpoint.host})';

  @override
  Stream<String>? reasoning(GateRequest request) => null;

  @override
  Future<GateDecision> decide(GateRequest request) async {
    final body = jsonEncode(request.toJson());
    final hdrs = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
      'x-agentgate-request-id': request.requestId,
      ...?await headers?.call(request),
    };
    if (signingSecret != null) {
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      final mac = Hmac(
        sha256,
        utf8.encode(signingSecret!),
      ).convert(utf8.encode('$ts.$body'));
      hdrs['x-agentgate-timestamp'] = ts;
      hdrs['x-agentgate-signature'] = 'sha256=$mac';
    }

    final sw = Stopwatch()..start();
    http.Response res;
    try {
      final req = http.Request(method, endpoint)
        ..headers.addAll(hdrs)
        ..body = body;
      res = await http.Response.fromStream(await _client.send(req));
    } on Exception catch (e) {
      throw DeciderTransientException('network error', e);
    }
    sw.stop();

    if (res.statusCode >= 500 || res.statusCode == 429) {
      throw DeciderTransientException('HTTP ${res.statusCode}');
    }
    if (res.statusCode >= 400) {
      throw DeciderFormatException('HTTP ${res.statusCode}: ${res.body}');
    }

    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) throw const FormatException('not an object');
      json = Map<String, Object?>.from(decoded);
      if (decodeResponse != null) json = decodeResponse!(json);
    } on FormatException catch (e) {
      throw DeciderFormatException('bad JSON', e);
    }

    try {
      return GateDecision.fromJson(json, latency: sw.elapsed);
    } on FormatException catch (e) {
      throw DeciderFormatException(e.message, e);
    }
  }

  /// Closes the underlying client.
  void close() => _client.close();
}
