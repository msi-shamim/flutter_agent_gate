import 'package:agent_gate/agent_gate.dart';
import 'package:agent_gate_getx/agent_gate_getx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Pins the outcome so tests assert on GetX wiring, not decision logic
/// (covered by the core package).
class _Fixed implements AgentDecider {
  _Fixed(this.id);
  final String id;
  @override
  String get name => 'fixed';
  @override
  Stream<String>? reasoning(GateRequest request) => null;
  @override
  Future<GateDecision> decide(GateRequest request) async => GateDecision(
        candidateId: id,
        source: DecisionSource.agent,
        confidence: 0.9,
        reason: 'test',
      );
}

Gate _routeGate() => Gate(
      id: 'home_to_x',
      from: 'home',
      fallback: 'std',
      config: const GateConfig(showLoadingUi: false),
      candidates: const <GateCandidate>[
        GateCandidate(id: 'std', label: 'Std', description: '', route: '/std'),
        GateCandidate(id: 'exp', label: 'Exp', description: '', route: '/exp'),
      ],
    );

Gate _builderGate() => Gate(
      id: 'inline',
      from: 'home',
      fallback: 'a',
      config: const GateConfig(showLoadingUi: false),
      candidates: <GateCandidate>[
        GateCandidate(
            id: 'a', label: 'A', description: '', builder: (_) => const Text('PAGE A')),
        GateCandidate(
            id: 'b', label: 'B', description: '', builder: (_) => const Text('PAGE B')),
      ],
    );

/// A destination that displays the reason it was chosen via GateArguments.
class _WhyPage extends StatelessWidget {
  const _WhyPage(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final why = GateArguments.current?.decision.reason ?? 'none';
    return Text('$label:$why');
  }
}

Widget _app({String initial = '/', List<GetPage<dynamic>>? pages}) =>
    GetMaterialApp(
      initialRoute: initial,
      getPages: pages ??
          <GetPage<dynamic>>[
            GetPage(name: '/', page: () => const Text('HOME')),
            GetPage(name: '/std', page: () => const _WhyPage('STD')),
            GetPage(name: '/exp', page: () => const _WhyPage('EXP')),
          ],
    );

void main() {
  setUp(() {
    AgentGate.reset();
    Get.reset();
  });

  group('GetxAdapter', () {
    testWidgets('toNamed with GateArguments (context-free)', (tester) async {
      AgentGate.configure(decider: _Fixed('exp'), adapter: const GetxAdapter());
      await tester.pumpWidget(_app());
      expect(find.text('HOME'), findsOneWidget);

      final r = await AgentGate.instance.navigate(_routeGate());
      await tester.pumpAndSettle();

      expect(r.candidate.id, 'exp');
      expect(find.text('EXP:test'), findsOneWidget);
      expect(Get.currentRoute, '/exp');
    });

    testWidgets('offAll clears the stack', (tester) async {
      AgentGate.configure(
        decider: _Fixed('std'),
        adapter: const GetxAdapter(mode: GetxNavigationMode.offAll),
      );
      await tester.pumpWidget(_app());
      await AgentGate.instance.navigate(_routeGate());
      await tester.pumpAndSettle();
      expect(find.text('STD:test'), findsOneWidget);
      // Back should not be possible: HOME was cleared.
      expect(Get.key.currentState!.canPop(), isFalse);
    });

    testWidgets('builder-only candidate uses Get.to', (tester) async {
      AgentGate.configure(decider: _Fixed('b'), adapter: const GetxAdapter());
      await tester.pumpWidget(_app());
      await AgentGate.instance.navigate(_builderGate());
      await tester.pumpAndSettle();
      expect(find.text('PAGE B'), findsOneWidget);
      expect(Get.currentRoute, '/b');
    });

    testWidgets('argumentsBuilder replaces payload', (tester) async {
      AgentGate.configure(
        decider: _Fixed('exp'),
        adapter: GetxAdapter(
          argumentsBuilder: (a) => <String, Object?>{'id': a.candidate.id},
        ),
      );
      Object? seen;
      await tester.pumpWidget(_app(pages: <GetPage<dynamic>>[
        GetPage(name: '/', page: () => const Text('HOME')),
        GetPage(name: '/std', page: () => const Text('STD')),
        GetPage(
          name: '/exp',
          page: () {
            seen = Get.arguments;
            return const Text('EXP');
          },
        ),
      ]));
      await AgentGate.instance.navigate(_routeGate());
      await tester.pumpAndSettle();
      expect(seen, <String, Object?>{'id': 'exp'});
    });

    test('throws when candidate has neither route nor builder', () {
      const adapter = GetxAdapter();
      expect(
        () => adapter.navigate(
          null,
          const GateCandidate(id: 'x', label: 'x', description: ''),
          const GateDecision(candidateId: 'x', source: DecisionSource.agent),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('GateGetPage', () {
    testWidgets('renders chosen candidate inline at a named route',
        (tester) async {
      AgentGate.configure(decider: _Fixed('b'));
      await tester.pumpWidget(_app(
        initial: '/inline',
        pages: <GetPage<dynamic>>[
          GateGetPage(name: '/inline', gate: _builderGate()),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('PAGE B'), findsOneWidget);
    });

    testWidgets('forwards route parameters to the decider', (tester) async {
      Map<String, Object?>? app;
      AgentGate.configure(
        decider: CallbackDecider((r) {
          app = r.context.app;
          return const GateDecision(
              candidateId: 'a', source: DecisionSource.agent);
        }),
      );
      await tester.pumpWidget(_app(
        initial: '/inline?coupon=SAVE10',
        pages: <GetPage<dynamic>>[
          GateGetPage(
            name: '/inline',
            gate: _builderGate(),
            contextFromRoute: (params, _) =>
                <String, Object?>{'coupon': params['coupon']},
          ),
        ],
      ));
      await tester.pumpAndSettle();
      expect(app!['coupon'], 'SAVE10');
      expect(find.text('PAGE A'), findsOneWidget);
    });
  });

  group('GateController', () {
    testWidgets('mirrors deciding state and last decision', (tester) async {
      AgentGate.configure(decider: _Fixed('exp'), adapter: const GetxAdapter());
      await tester.pumpWidget(_app());
      final c = Get.put(GateController());
      expect(c.isDeciding.value, isFalse);
      final f = c.navigate(_routeGate());
      expect(c.isDeciding.value, isTrue);
      await f;
      await tester.pumpAndSettle();
      expect(c.isDeciding.value, isFalse);
      expect(c.lastDecision.value!.candidateId, 'exp');
      expect(c.lastCandidate.value!.route, '/exp');
    });
  });

  group('GateMiddleware', () {
    testWidgets('redirectDelegate resolves to the chosen route', (tester) async {
      AgentGate.configure(decider: _Fixed('exp'));
      // The route tree must exist for GetNavConfig.fromRoute to match.
      await tester.pumpWidget(_app(pages: <GetPage<dynamic>>[
        GetPage(name: '/', page: () => const Text('HOME')),
        GetPage(name: '/checkout', page: () => const SizedBox.shrink()),
        GetPage(name: '/std', page: () => const Text('STD')),
        GetPage(name: '/exp', page: () => const Text('EXP')),
      ]));
      final mw = GateMiddleware(_routeGate());
      final incoming = GetNavConfig.fromRoute('/checkout')!;
      final out = await mw.redirectDelegate(incoming);
      expect(out!.uri.toString(), '/exp');
    });

    testWidgets('returns the incoming route when already at target',
        (tester) async {
      AgentGate.configure(decider: _Fixed('exp'));
      await tester.pumpWidget(_app());
      final mw = GateMiddleware(_routeGate());
      final incoming = GetNavConfig.fromRoute('/exp')!;
      final out = await mw.redirectDelegate(incoming);
      expect(identical(out, incoming), isTrue);
    });
  });
}
