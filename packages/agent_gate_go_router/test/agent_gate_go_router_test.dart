import 'package:agent_gate/agent_gate.dart';
import 'package:agent_gate_go_router/agent_gate_go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A decider that always answers with [id] — lets each test pin the outcome
/// and assert on routing behaviour rather than on decision logic (which the
/// core package already covers).
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
      candidates: <GateCandidate>[
        GateCandidate(
            id: 'a', label: 'A', description: '', builder: (_) => const Text('PAGE A')),
        GateCandidate(
            id: 'b', label: 'B', description: '', builder: (_) => const Text('PAGE B')),
      ],
    );

GoRouter _router({required List<RouteBase> routes, String initial = '/'}) =>
    GoRouter(initialLocation: initial, routes: routes);

void main() {
  setUp(AgentGate.reset);

  group('GoRouterAdapter', () {
    testWidgets('go() navigates to chosen route and passes GateExtra',
        (tester) async {
      GateExtra? received;
      final router = _router(routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/std', builder: (_, _) => const Text('STD')),
        GoRoute(
          path: '/exp',
          builder: (_, state) {
            received = state.gateExtra;
            return const Text('EXP');
          },
        ),
      ]);
      AgentGate.configure(
        decider: _Fixed('exp'),
        adapter: GoRouterAdapter(router: router),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('HOME'), findsOneWidget);

      // No BuildContext needed because the router was passed explicitly.
      final result = await AgentGate.instance.navigate(_routeGate());
      await tester.pumpAndSettle();

      expect(result.candidate.id, 'exp');
      expect(find.text('EXP'), findsOneWidget);
      expect(received, isNotNull);
      expect(received!.decision.candidateId, 'exp');
      expect(received!.candidate.route, '/exp');
    });

    testWidgets('resolves router from context when not supplied',
        (tester) async {
      late BuildContext ctx;
      final router = _router(routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (c, _) {
            ctx = c;
            return const Text('HOME');
          },
        ),
        GoRoute(path: '/std', builder: (_, _) => const Text('STD')),
        GoRoute(path: '/exp', builder: (_, _) => const Text('EXP')),
      ]);
      AgentGate.configure(
        decider: _Fixed('std'),
        adapter: const GoRouterAdapter(mode: GoRouterNavigationMode.push),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await AgentGate.instance.navigate(_routeGate(), context: ctx);
      await tester.pumpAndSettle();
      expect(find.text('STD'), findsOneWidget);
    });

    testWidgets('extraBuilder can replace the payload', (tester) async {
      Object? received;
      final router = _router(routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/std', builder: (_, _) => const Text('STD')),
        GoRoute(
          path: '/exp',
          builder: (_, s) {
            received = s.extra;
            return const Text('EXP');
          },
        ),
      ]);
      AgentGate.configure(
        decider: _Fixed('exp'),
        adapter: GoRouterAdapter(
          router: router,
          extraBuilder: (e) => <String, Object?>{'why': e.decision.reason},
        ),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await AgentGate.instance.navigate(_routeGate());
      await tester.pumpAndSettle();
      expect(received, <String, Object?>{'why': 'test'});
    });

    test('throws a helpful error when candidate has no route', () {
      const adapter = GoRouterAdapter(router: null);
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

  group('GateRoute.page', () {
    testWidgets('renders the chosen candidate inline', (tester) async {
      AgentGate.configure(decider: _Fixed('b'));
      final router = _router(
        initial: '/inline',
        routes: <RouteBase>[
          GateRoute.page(path: '/inline', gate: _builderGate()),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('PAGE B'), findsOneWidget);
    });

    testWidgets('forwards contextFromState to the decider', (tester) async {
      Map<String, Object?>? seenApp;
      AgentGate.configure(
        decider: CallbackDecider((r) {
          seenApp = r.context.app;
          return const GateDecision(
              candidateId: 'a', source: DecisionSource.agent);
        }),
      );
      final router = _router(
        initial: '/inline?coupon=SAVE10',
        routes: <RouteBase>[
          GateRoute.page(
            path: '/inline',
            gate: _builderGate(),
            contextFromState: (s) =>
                <String, Object?>{'coupon': s.uri.queryParameters['coupon']},
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(seenApp!['coupon'], 'SAVE10');
      expect(find.text('PAGE A'), findsOneWidget);
    });
  });

  group('GateRoute.redirect / gateRedirect', () {
    testWidgets('deep link to gate path resolves to chosen route',
        (tester) async {
      AgentGate.configure(decider: _Fixed('exp'));
      final router = _router(
        initial: '/checkout',
        routes: <RouteBase>[
          GateRoute.redirect(path: '/checkout', gate: _routeGate()),
          GoRoute(path: '/std', builder: (_, _) => const Text('STD')),
          GoRoute(path: '/exp', builder: (_, _) => const Text('EXP')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('EXP'), findsOneWidget);
      expect(router.state.matchedLocation, '/exp');
    });

    testWidgets('falls back to the fallback route when decider is missing',
        (tester) async {
      // No decider configured → AgentGate.decide returns the fallback.
      final router = _router(
        initial: '/checkout',
        routes: <RouteBase>[
          GateRoute.redirect(path: '/checkout', gate: _routeGate()),
          GoRoute(path: '/std', builder: (_, _) => const Text('STD')),
          GoRoute(path: '/exp', builder: (_, _) => const Text('EXP')),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('STD'), findsOneWidget);
    });
  });
}
