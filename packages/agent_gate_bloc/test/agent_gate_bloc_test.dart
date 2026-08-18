import 'package:agent_gate/agent_gate.dart';
import 'package:agent_gate_bloc/agent_gate_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the outcome (optionally with a delay) so tests assert on Bloc wiring
/// rather than decision logic, which the core package covers.
class _Fixed implements AgentDecider {
  _Fixed(this.id, {this.delay});
  final String id;
  final Duration? delay;
  @override
  String get name => 'fixed';
  @override
  Stream<String>? reasoning(GateRequest request) => null;
  @override
  Future<GateDecision> decide(GateRequest request) async {
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

  group('GateCubit', () {
    blocTest<GateCubit, GateState>(
      'emits Deciding then Decided with the agent choice',
      setUp: () => AgentGate.configure(decider: _Fixed('b1')),
      build: GateCubit.new,
      act: (c) => c.decide(_gate(), extra: <String, Object?>{'k': 1}),
      expect: () => <Matcher>[
        isA<GateDeciding>().having((s) => s.gate.id, 'gate', 'a_to_b').having(
          (s) => s.extra,
          'extra',
          <String, Object?>{'k': 1},
        ),
        isA<GateDecided>()
            .having((s) => s.candidate.id, 'candidate', 'b1')
            .having((s) => s.isFallback, 'isFallback', isFalse),
      ],
    );

    blocTest<GateCubit, GateState>(
      'emits a fallback Decided when no decider is configured',
      build: GateCubit.new,
      act: (c) => c.decide(_gate()),
      expect: () => <Matcher>[
        isA<GateDeciding>(),
        isA<GateDecided>()
            .having((s) => s.candidate.id, 'candidate', 'b0')
            .having((s) => s.isFallback, 'isFallback', isTrue),
      ],
    );

    blocTest<GateCubit, GateState>(
      'reset returns to Idle',
      setUp: () => AgentGate.configure(decider: _Fixed('b1')),
      build: GateCubit.new,
      act: (c) async {
        await c.decide(_gate());
        c.reset();
      },
      expect: () => <Matcher>[
        isA<GateDeciding>(),
        isA<GateDecided>(),
        isA<GateIdle>(),
      ],
    );

    test('a slower earlier decide() does not overwrite a newer one', () async {
      // First call is slow (b0), second is fast (b1); b1 must stay.
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
      final c = GateCubit();
      final f1 = c.decide(_gate());
      final f2 = c.decide(_gate());
      await Future.wait(<Future<GateDecided>>[f1, f2]);
      expect((c.state as GateDecided).candidate.id, 'b1');
      await c.close();
    });
  });

  group('GateBloc', () {
    blocTest<GateBloc, GateState>(
      'handles GateDecideRequested and GateReset',
      setUp: () => AgentGate.configure(decider: _Fixed('b1')),
      build: GateBloc.new,
      act: (b) => b
        ..add(GateDecideRequested(_gate()))
        ..add(const GateReset()),
      expect: () => <Matcher>[
        isA<GateDeciding>(),
        isA<GateDecided>().having((s) => s.candidate.id, 'candidate', 'b1'),
        isA<GateIdle>(),
      ],
    );
  });

  group('GateBlocListener', () {
    testWidgets('shows loading while deciding then navigates via adapter', (
      tester,
    ) async {
      AgentGate.configure(
        decider: _Fixed('b1', delay: const Duration(milliseconds: 100)),
        adapter: const NavigatorAdapter(),
      );
      final cubit = GateCubit();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<GateCubit>.value(
            value: cubit,
            child: const GateBlocListener<GateCubit>(child: Text('A')),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);

      final f = cubit.decide(_gate());
      await tester.pump();
      expect(find.byType(AgentLoadingView), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      await f;
      await tester.pumpAndSettle();
      expect(find.text('B1'), findsOneWidget);
      expect(find.byType(AgentLoadingView), findsNothing);
      await cubit.close();
    });

    testWidgets('onDecided replaces default navigation', (tester) async {
      AgentGate.configure(decider: _Fixed('b1'));
      final cubit = GateCubit();
      GateDecided? got;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<GateCubit>.value(
            value: cubit,
            child: GateBlocListener<GateCubit>(
              onDecided: (_, s) => got = s,
              child: const Text('A'),
            ),
          ),
        ),
      );
      await cubit.decide(_gate());
      await tester.pumpAndSettle();
      expect(got!.candidate.id, 'b1');
      expect(find.text('A'), findsOneWidget); // no navigation happened
      await cubit.close();
    });

    testWidgets('navigateOnFallback=false suppresses fallback navigation', (
      tester,
    ) async {
      // No decider → fallback.
      final cubit = GateCubit();
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<GateCubit>.value(
            value: cubit,
            child: const GateBlocListener<GateCubit>(
              navigateOnFallback: false,
              child: Text('A'),
            ),
          ),
        ),
      );
      await cubit.decide(_gate());
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B0'), findsNothing);
      await cubit.close();
    });
  });
}
