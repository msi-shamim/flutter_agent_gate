import 'dart:async';

import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Gate _gate({GateConfig? config, AgentDecider? decider}) => Gate(
      id: 'a_to_b',
      from: 'A',
      fallback: 'b0',
      config: config,
      decider: decider,
      candidates: <GateCandidate>[
        GateCandidate(
          id: 'b0',
          label: 'B0',
          description: 'default',
          builder: (_) => const Text('B0'),
        ),
        GateCandidate(
          id: 'b1',
          label: 'B1',
          description: 'premium',
          builder: (_) => const Text('B1'),
        ),
        GateCandidate(
          id: 'b2',
          label: 'B2',
          description: 'step-up',
          builder: (_) => const Text('B2'),
        ),
      ],
    );

class _FixedDecider implements AgentDecider {
  _FixedDecider(this.id, {this.confidence = 0.9, this.delay});
  final String id;
  final double confidence;
  final Duration? delay;
  int calls = 0;

  @override
  String get name => 'fixed';

  @override
  Stream<String>? reasoning(GateRequest request) => null;

  @override
  Future<GateDecision> decide(GateRequest request) async {
    calls++;
    if (delay != null) await Future<void>.delayed(delay!);
    return GateDecision(
      candidateId: id,
      source: DecisionSource.agent,
      confidence: confidence,
      reason: 'test',
    );
  }
}

class _FlakyDecider implements AgentDecider {
  _FlakyDecider({required this.failuresBeforeSuccess});
  int failuresBeforeSuccess;
  int calls = 0;

  @override
  String get name => 'flaky';

  @override
  Stream<String>? reasoning(GateRequest request) => null;

  @override
  Future<GateDecision> decide(GateRequest request) async {
    calls++;
    if (failuresBeforeSuccess-- > 0) {
      throw const DeciderTransientException('boom');
    }
    return const GateDecision(
        candidateId: 'b1', source: DecisionSource.agent);
  }
}

void main() {
  setUp(AgentGate.reset);

  group('Gate validation', () {
    test('rejects empty, duplicate, unknown fallback, >1000', () {
      expect(
        () => Gate(id: 'x', from: 'A', fallback: 'a', candidates: const []),
        throwsArgumentError,
      );
      expect(
        () => Gate(id: 'x', from: 'A', fallback: 'a', candidates: const [
          GateCandidate(id: 'a', label: 'a', description: ''),
          GateCandidate(id: 'a', label: 'a', description: ''),
        ]),
        throwsArgumentError,
      );
      expect(
        () => Gate(id: 'x', from: 'A', fallback: 'zzz', candidates: const [
          GateCandidate(id: 'a', label: 'a', description: ''),
        ]),
        throwsArgumentError,
      );
      final many = List.generate(
        1001,
        (i) => GateCandidate(id: 'c$i', label: 'c$i', description: ''),
      );
      expect(
        () => Gate(id: 'x', from: 'A', fallback: 'c0', candidates: many),
        throwsArgumentError,
      );
      // exactly 1000 is fine
      expect(
        Gate(id: 'x', from: 'A', fallback: 'c0', candidates: many.sublist(0, 1000))
            .candidates
            .length,
        1000,
      );
    });
  });

  group('AgentGate.decide pipeline', () {
    test('uses agent decision', () async {
      AgentGate.configure(decider: _FixedDecider('b1'));
      final d = await AgentGate.instance.decide(_gate());
      expect(d.candidateId, 'b1');
      expect(d.source, DecisionSource.agent);
    });

    test('falls back when no decider', () async {
      final d = await AgentGate.instance.decide(_gate());
      expect(d.candidateId, 'b0');
      expect(d.source, DecisionSource.fallback);
    });

    test('falls back on unknown id', () async {
      AgentGate.configure(decider: _FixedDecider('nope'));
      final d = await AgentGate.instance.decide(_gate());
      expect(d.candidateId, 'b0');
      expect(d.source, DecisionSource.fallback);
      expect(d.reason, contains('unknown candidate'));
    });

    test('falls back on timeout', () async {
      AgentGate.configure(
        decider: _FixedDecider('b1', delay: const Duration(seconds: 5)),
      );
      final d = await AgentGate.instance.decide(
        _gate(config: const GateConfig(timeout: Duration(milliseconds: 50))),
      );
      expect(d.candidateId, 'b0');
      expect(d.reason, contains('timeout'));
    });

    test('enforces allow-list', () async {
      AgentGate.configure(decider: _FixedDecider('b1'));
      final d = await AgentGate.instance.decide(
        _gate(config: const GateConfig(allowedCandidateIds: {'b0', 'b2'})),
      );
      expect(d.candidateId, 'b0');
      expect(d.reason, contains('allow-list'));
    });

    test('enforces min confidence', () async {
      AgentGate.configure(decider: _FixedDecider('b1', confidence: 0.3));
      final d = await AgentGate.instance
          .decide(_gate(config: const GateConfig.risk()));
      expect(d.candidateId, 'b0');
      expect(d.reason, contains('confidence'));
    });

    test('retries transient errors', () async {
      final flaky = _FlakyDecider(failuresBeforeSuccess: 1);
      AgentGate.configure(decider: flaky);
      final d = await AgentGate.instance.decide(
        _gate(config: const GateConfig(maxRetries: 2, retryDelay: Duration.zero)),
      );
      expect(d.candidateId, 'b1');
      expect(flaky.calls, 2);
    });

    test('does not retry beyond maxRetries', () async {
      final flaky = _FlakyDecider(failuresBeforeSuccess: 5);
      AgentGate.configure(decider: flaky);
      final d = await AgentGate.instance.decide(
        _gate(config: const GateConfig(maxRetries: 1, retryDelay: Duration.zero)),
      );
      expect(d.source, DecisionSource.fallback);
      expect(flaky.calls, 2);
    });

    test('caches when cacheTtl set', () async {
      final fixed = _FixedDecider('b1');
      AgentGate.configure(decider: fixed);
      final g = _gate(config: const GateConfig.recommendation());
      final d1 = await AgentGate.instance.decide(g);
      final d2 = await AgentGate.instance.decide(g);
      expect(d1.source, DecisionSource.agent);
      expect(d2.source, DecisionSource.cache);
      expect(fixed.calls, 1);
    });

    test('rules run before agent in a composite', () async {
      final fixed = _FixedDecider('b1');
      AgentGate.configure(
        decider: CompositeDecider([
          RuleDecider([
            GateRule(
              id: 'high_risk',
              when: (r) => (r.context.app['risk_score'] as num? ?? 0) > 80,
              candidateId: 'b2',
            ),
          ]),
          fixed,
        ]),
      );
      final risky = await AgentGate.instance
          .decide(_gate(), extra: {'risk_score': 95});
      expect(risky.candidateId, 'b2');
      expect(risky.source, DecisionSource.rule);
      expect(fixed.calls, 0);

      final normal = await AgentGate.instance
          .decide(_gate(), extra: {'risk_score': 10});
      expect(normal.candidateId, 'b1');
      expect(fixed.calls, 1);
    });

    test('writes audit entries and notifies observers', () async {
      final sink = MemoryAuditSink();
      final events = <String>[];
      AgentGate.configure(
        decider: _FixedDecider('nope'),
        auditSink: sink,
        observers: [
          _Obs((e) => events.add(e)),
        ],
      );
      await AgentGate.instance.decide(_gate());
      expect(sink.entries, hasLength(1));
      expect(sink.entries.single.error, isNotNull);
      expect(sink.entries.single.decision.source, DecisionSource.fallback);
      expect(events, ['start', 'fallback', 'decision']);
    });

    test('redacts sensitive keys and respects consent', () async {
      GateRequest? seen;
      AgentGate.configure(
        decider: CallbackDecider((r) {
          seen = r;
          return const GateDecision(
              candidateId: 'b0', source: DecisionSource.agent);
        }),
        contextBuilder: () => {'email': 'a@b.c', 'tier': 'gold'},
      );
      // No consent → no behaviour, but app context present.
      AgentGate.instance.tracker.enterPage('A');
      AgentGate.instance.tracker.tap('x');
      await AgentGate.instance.decide(_gate(), extra: {'card_number': '4111'});
      expect(seen!.context.consentGranted, isFalse);
      expect(seen!.context.currentPage, isNull);
      expect(seen!.context.app['email'], '[REDACTED]');
      expect(seen!.context.app['card_number'], '[REDACTED]');
      expect(seen!.context.app['tier'], 'gold');

      // Consent → behaviour attached.
      AgentGate.instance.tracker.consent.grant();
      AgentGate.instance.tracker.enterPage('A');
      AgentGate.instance.tracker.tap('pay');
      AgentGate.instance.tracker.tap('pay');
      AgentGate.instance.tracker.attempt('pay');
      AgentGate.instance.tracker.failure('pay', code: 'declined');
      await AgentGate.instance.decide(_gate());
      expect(seen!.context.consentGranted, isTrue);
      expect(seen!.context.currentPage!.tapCount, 2);
      expect(seen!.context.currentPage!.attemptCount, 1);
      expect(seen!.context.currentPage!.failureCount, 1);
      expect(seen!.context.currentPage!.tapsByTarget['pay'], 2);
    });
  });

  group('PromptBuilder', () {
    test('produces enum-constrained schema for all three providers', () async {
      AgentGate.configure(decider: _FixedDecider('b0'));
      GateRequest? req;
      AgentGate.configure(decider: CallbackDecider((r) {
        req = r;
        return const GateDecision(candidateId: 'b0', source: DecisionSource.agent);
      }));
      await AgentGate.instance.decide(_gate());
      const pb = PromptBuilder();
      final schema = pb.decisionSchema(req!);
      final props = schema['properties']! as Map<String, Object?>;
      final idProp = props['candidate_id']! as Map<String, Object?>;
      expect(idProp['enum'], ['b0', 'b1', 'b2']);

      final oa = pb.openAiRequest(req!);
      expect(oa['tools'], isA<List<Object?>>());
      final an = pb.anthropicRequest(req!);
      expect((an['tools']! as List<Object?>).single, contains('input_schema'));
      final ge = pb.geminiRequest(req!);
      final decl = ((ge['tools']! as List<Object?>).single
              as Map<String, Object?>)['function_declarations']! as List<Object?>;
      final params = (decl.single as Map<String, Object?>)['parameters']!
          as Map<String, Object?>;
      expect(params.containsKey('additionalProperties'), isFalse);
      expect(pb.systemPrompt(req!), contains('choose_next_page'));
    });
  });

  group('GateDecision.fromJson', () {
    test('accepts canonical and alt keys, clamps confidence', () {
      final d = GateDecision.fromJson({'candidate_id': 'x', 'confidence': 1.7});
      expect(d.confidence, 1.0);
      expect(GateDecision.fromJson({'candidateId': 'y'}).candidateId, 'y');
      expect(GateDecision.fromJson({'id': 'z'}).candidateId, 'z');
      expect(() => GateDecision.fromJson({'foo': 1}), throwsFormatException);
    });
  });

  group('Redactor', () {
    test('redacts nested, case-insensitive', () {
      const r = Redactor({'Email', 'pan'});
      final out = r.applyToMap({
        'user': {'EMAIL': 'x', 'name': 'ok'},
        'cards': [
          {'PAN': '1', 'exp': '12/29'},
        ],
      });
      expect((out['user']! as Map)['EMAIL'], '[REDACTED]');
      expect((out['user']! as Map)['name'], 'ok');
      expect(((out['cards']! as List).first as Map)['PAN'], '[REDACTED]');
    });
  });

  group('Widgets', () {
    testWidgets('navigate() shows loading then pushes chosen page',
        (tester) async {
      AgentGate.configure(
        decider: _FixedDecider('b1', delay: const Duration(milliseconds: 100)),
      );
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const Text('A');
        }),
      ));
      final f = AgentGate.instance.navigate(_gate(), context: ctx);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byType(AgentLoadingView), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final r = await f;
      expect(r.candidate.id, 'b1');
      expect(find.text('B1'), findsOneWidget);
      expect(find.byType(AgentLoadingView), findsNothing);
    });

    testWidgets('GatePage renders chosen candidate inline', (tester) async {
      AgentGate.configure(decider: _FixedDecider('b2'));
      await tester.pumpWidget(MaterialApp(home: GatePage(gate: _gate())));
      expect(find.byType(AgentLoadingView), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('B2'), findsOneWidget);
    });

    testWidgets('TrackedPage records enter/exit', (tester) async {
      AgentGate.instance.tracker.consent.grant();
      await tester.pumpWidget(const MaterialApp(
        home: TrackedPage(id: 'A', child: Text('A')),
      ));
      expect(AgentGate.instance.tracker.currentPage, 'A');
      await tester.pumpWidget(const MaterialApp(home: Text('other')));
      expect(AgentGate.instance.tracker.currentPage, isNull);
      expect(
        AgentGate.instance.tracker
            .eventsFor('A')
            .map((e) => e.type)
            .toList(),
        [BehaviorEventType.pageEnter, BehaviorEventType.pageExit],
      );
    });
  });
}

class _Obs extends GateObserver {
  const _Obs(this.log);
  final void Function(String) log;
  @override
  void onStart(GateRequest request) => log('start');
  @override
  void onDecision(GateRequest request, GateDecision decision) =>
      log('decision');
  @override
  void onFallback(GateRequest request, Object error, GateDecision fallback) =>
      log('fallback');
}
