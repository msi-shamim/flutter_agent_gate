import 'package:agent_gate/agent_gate.dart';
import 'package:agent_gate_riverpod/agent_gate_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the outcome so tests assert on Riverpod wiring, not decision logic
/// (covered by the core package).
class _Fixed implements AgentDecider {
  _Fixed(this.id, {this.delay});
  final String id;
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
      confidence: 0.9,
      reason: 'test',
    );
  }
}

Gate _gate() => Gate(
  id: 'a_to_b',
  from: 'A',
  fallback: 'b0',
  config: const GateConfig(showLoadingUi: false),
  candidates: <GateCandidate>[
    GateCandidate(
      id: 'b0',
      label: 'B0',
      description: '',
      builder: (_) => const Text('B0'),
    ),
    GateCandidate(
      id: 'b1',
      label: 'B1',
      description: '',
      builder: (_) => const Text('B1'),
    ),
  ],
);

void main() {
  setUp(AgentGate.reset);

  group('gateDecisionProvider', () {
    test('resolves to the agent decision', () async {
      AgentGate.configure(decider: _Fixed('b1'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final d = await container.read(gateDecisionProvider(_gate()).future);
      expect(d.candidateId, 'b1');
    });

    test('with-extra variant forwards extra and dedups by key', () async {
      Map<String, Object?>? seen;
      final fixed = _Fixed('b0');
      AgentGate.configure(
        decider: CallbackDecider((r) {
          seen = r.context.app;
          return fixed.decide(r);
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final g = _gate();
      final k1 = GateArgs(g, <String, Object?>{'x': 1});
      final k2 = GateArgs(g, <String, Object?>{'x': 1});
      expect(k1, equals(k2)); // same family key → same provider instance
      await container.read(gateDecisionWithExtraProvider(k1).future);
      await container.read(gateDecisionWithExtraProvider(k2).future);
      expect(seen!['x'], 1);
      expect(fixed.calls, 1);
    });
  });

  group('GateNotifier', () {
    test('idle → loading → data, then reset', () async {
      AgentGate.configure(decider: _Fixed('b1'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final states = <AsyncValue<GateOutcome?>>[];
      container.listen(
        gateNotifierProvider,
        (_, s) => states.add(s),
        fireImmediately: true,
      );
      await container.read(gateNotifierProvider.future); // initial null
      final n = container.read(gateNotifierProvider.notifier);
      final o = await n.decide(_gate());
      expect(o.candidate.id, 'b1');
      expect(o.isFallback, isFalse);
      expect(states.any((s) => s.isLoading), isTrue);
      expect(container.read(gateNotifierProvider).value, o);
      n.reset();
      expect(container.read(gateNotifierProvider).value, isNull);
    });

    test('fallback is data, not error', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gateNotifierProvider.future);
      final o = await container
          .read(gateNotifierProvider.notifier)
          .decide(_gate());
      expect(o.isFallback, isTrue);
      expect(container.read(gateNotifierProvider).hasError, isFalse);
    });

    test('latest call wins', () async {
      var calls = 0;
      AgentGate.configure(
        decider: CallbackDecider((r) async {
          calls++;
          if (calls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return const GateDecision(
              candidateId: 'b0',
              source: DecisionSource.agent,
            );
          }
          return const GateDecision(
            candidateId: 'b1',
            source: DecisionSource.agent,
          );
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(gateNotifierProvider.future);
      final n = container.read(gateNotifierProvider.notifier);
      await Future.wait(<Future<GateOutcome>>[
        n.decide(_gate()),
        n.decide(_gate()),
      ]);
      expect(container.read(gateNotifierProvider).value!.candidate.id, 'b1');
    });
  });

  group('GateListener', () {
    testWidgets('shows loading, then navigates via adapter', (tester) async {
      AgentGate.configure(
        decider: _Fixed('b1', delay: const Duration(milliseconds: 100)),
        adapter: const NavigatorAdapter(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GateListener(child: Text('A'))),
        ),
      );
      await tester.pump();
      final f = container.read(gateNotifierProvider.notifier).decide(_gate());
      await tester.pump();
      expect(find.byType(AgentLoadingView), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await f;
      await tester.pumpAndSettle();
      expect(find.text('B1'), findsOneWidget);
      expect(find.byType(AgentLoadingView), findsNothing);
    });

    testWidgets('re-fires when the same outcome lands again after loading', (
      tester,
    ) async {
      var navs = 0;
      AgentGate.configure(decider: _Fixed('b1'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: GateListener(
              onDecided: (_, _, _) => navs++,
              child: const Text('A'),
            ),
          ),
        ),
      );
      await tester.pump();
      final n = container.read(gateNotifierProvider.notifier);
      await n.decide(_gate());
      await tester.pump();
      await n.decide(_gate()); // same answer again
      await tester.pump();
      expect(navs, 2);
    });

    testWidgets('navigateOnFallback=false suppresses fallback navigation', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GateListener(navigateOnFallback: false, child: Text('A')),
          ),
        ),
      );
      await tester.pump();
      await container.read(gateNotifierProvider.notifier).decide(_gate());
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B0'), findsNothing);
    });
  });
}
