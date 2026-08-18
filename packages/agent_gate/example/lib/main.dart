// AgentGate example: an e-commerce cart that routes to one of several
// checkout experiences, and a banking transfer page that routes to a
// risk-appropriate confirmation flow.
//
// No real AI is called here — `DemoDecider` simulates what your backend
// would return so you can run the example offline. Swap it for
// `HttpDecider(endpoint: ...)` to go live.

import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/material.dart';

void main() {
  AgentGate.configure(
    decider: CompositeDecider(<AgentDecider>[
      // 1. Hard rules first — these are your non-negotiables.
      RuleDecider(<GateRule>[
        GateRule(
          id: 'transfer_over_limit',
          when: (r) =>
              r.gateId == 'transfer_to_confirm' &&
              (r.context.app['amount'] as num? ?? 0) > 5000,
          candidateId: 'confirm_stepup',
          reason: 'Amount above the daily limit always requires step-up.',
        ),
      ]),
      // 2. Then the "AI" (simulated here).
      DemoDecider(),
    ]),
    adapter: const NavigatorAdapter(),
    config: const GateConfig(),
    contextBuilder: () => <String, Object?>{
      'tier': 'gold',
      'email': 'jane@example.com', // will be redacted automatically
    },
    observers: <GateObserver>[const _LogObserver()],
  );
  runApp(const DemoApp());
}

/// Simulates a backend/AI decider using the behavioural summary.
class DemoDecider implements AgentDecider {
  @override
  String get name => 'DemoDecider';

  @override
  Stream<String>? reasoning(GateRequest request) async* {
    yield 'Reading behaviour on ${request.fromPage}…';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    yield 'Comparing ${request.candidates.length} options…';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    yield 'Deciding…';
  }

  @override
  Future<GateDecision> decide(GateRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final page = request.context.currentPage;
    final taps = page?.tapCount ?? 0;
    final failures = page?.failureCount ?? 0;
    final dwellSec = (page?.dwell.inMilliseconds ?? 0) / 1000;

    switch (request.gateId) {
      case 'cart_to_checkout':
        if (failures >= 2) {
          return _d(
            'checkout_assisted',
            0.86,
            'User failed to apply a coupon $failures times — assisted flow.',
          );
        }
        if (dwellSec < 4 && taps <= 2) {
          return _d(
            'checkout_express',
            0.78,
            'Fast, decisive session (${dwellSec.toStringAsFixed(1)} s) — express.',
          );
        }
        return _d('checkout_standard', 0.7, 'Typical session — standard flow.');
      case 'transfer_to_confirm':
        final anomalies = failures + (page?.backCount ?? 0);
        if (anomalies >= 2 || (page?.fieldEditCount ?? 0) > 6) {
          return _d(
            'confirm_stepup',
            0.82,
            'Repeated edits/back-navigation on a transfer page look anomalous.',
          );
        }
        return _d(
          'confirm_simple',
          0.74,
          'Behaviour consistent with baseline.',
        );
    }
    return _d(request.candidates.first.id, 0.5, 'default');
  }

  GateDecision _d(String id, double c, String why) => GateDecision(
    candidateId: id,
    source: DecisionSource.agent,
    confidence: c,
    reason: why,
    model: 'demo',
  );
}

class _LogObserver extends GateObserver {
  const _LogObserver();
  @override
  void onDecision(GateRequest request, GateDecision decision) {
    debugPrint(
      '[AgentGate] ${request.gateId} → $decision (${decision.reason})',
    );
  }
}

// ── Gates ─────────────────────────────────────────────────────────────────

final Gate checkoutGate = Gate(
  id: 'cart_to_checkout',
  from: 'cart',
  fallback: 'checkout_standard',
  config: const GateConfig.recommendation().copyWith(cacheTtl: null),
  instructions:
      'Prefer the flow with the fewest steps unless the user '
      'showed signs of confusion.',
  candidates: <GateCandidate>[
    GateCandidate(
      id: 'checkout_express',
      label: 'Express checkout',
      description:
          'One-tap checkout with saved card & address. Best for '
          'confident returning users who move fast.',
      builder: (_) => const ResultPage('Express checkout', Colors.green),
    ),
    GateCandidate(
      id: 'checkout_standard',
      label: 'Standard checkout',
      description: 'Regular 3-step checkout. Safe default.',
      builder: (_) => const ResultPage('Standard checkout', Colors.blue),
    ),
    GateCandidate(
      id: 'checkout_assisted',
      label: 'Assisted checkout',
      description:
          'Guided checkout with inline help and live chat. Best '
          'when the user struggled (coupon failures, many back-navigations).',
      builder: (_) => const ResultPage('Assisted checkout', Colors.orange),
    ),
  ],
);

final Gate transferGate = Gate(
  id: 'transfer_to_confirm',
  from: 'transfer',
  fallback: 'confirm_stepup', // in risk profiles, fall back to the SAFE page
  config: const GateConfig.risk(),
  candidates: <GateCandidate>[
    GateCandidate(
      id: 'confirm_simple',
      label: 'Simple confirmation',
      description:
          'Confirm with biometric only. For behaviour consistent '
          'with the user baseline and low amounts.',
      tags: const <String>['low_friction'],
      builder: (_) => const ResultPage('Confirm (biometric)', Colors.teal),
    ),
    GateCandidate(
      id: 'confirm_stepup',
      label: 'Step-up verification',
      description:
          'OTP + security question. For anomalous behaviour, high '
          'amounts or new payees.',
      tags: const <String>['protective'],
      builder: (_) => const ResultPage('Step-up verification', Colors.red),
    ),
  ],
);

// ── UI ────────────────────────────────────────────────────────────────────

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AgentGate demo',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    navigatorObservers: <NavigatorObserver>[GateNavigatorObserver()],
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool get _consent => AgentGate.instance.tracker.consent.granted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AgentGate demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            title: const Text('Behavioural tracking consent'),
            subtitle: const Text('Off = only app context is sent'),
            value: _consent,
            onChanged: (v) => setState(
              () => v
                  ? AgentGate.instance.tracker.consent.grant()
                  : AgentGate.instance.tracker.consent.revoke(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.shopping_cart),
            label: const Text('E-commerce: cart → checkout'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'cart'),
                builder: (_) => const CartPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.account_balance),
            label: const Text('Banking: transfer → confirmation'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'transfer'),
                builder: (_) => const TransferPage(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Try: on the cart page, tap "Apply coupon" twice (it fails) → '
            'assisted checkout. Go fast → express. On the transfer page, '
            'edit the amount many times or enter > 5000 → step-up.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final BehaviorTracker t = AgentGate.instance.tracker;
  String? couponMsg;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const ListTile(
              title: Text('Noise-cancelling headphones'),
              trailing: Text('\$199'),
            ),
            const ListTile(title: Text('USB-C cable'), trailing: Text('\$12')),
            const Divider(),
            OutlinedButton(
              onPressed: () {
                t.tap('btn_apply_coupon');
                t.attempt('apply_coupon');
                t.failure('apply_coupon', code: 'invalid');
                setState(() => couponMsg = 'Coupon invalid');
              },
              child: const Text('Apply coupon'),
            ),
            if (couponMsg != null)
              Text(couponMsg!, style: const TextStyle(color: Colors.red)),
            const Spacer(),
            FilledButton(
              onPressed: () {
                t.tap('btn_checkout');
                AgentGate.instance.navigate(
                  checkoutGate,
                  context: context,
                  extra: <String, Object?>{'cart_total': 211, 'items': 2},
                );
              },
              child: const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final BehaviorTracker t = AgentGate.instance.tracker;
  final TextEditingController amount = TextEditingController(text: '100');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
              onTap: () => t.fieldFocus('field_amount'),
              onChanged: (v) => t.fieldEdit('field_amount', length: v.length),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(labelText: 'Payee (new)'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                t.tap('btn_continue');
                t.attempt('transfer');
                AgentGate.instance.navigate(
                  transferGate,
                  context: context,
                  extra: <String, Object?>{
                    'amount': num.tryParse(amount.text) ?? 0,
                    'new_payee': true,
                  },
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage(this.title, this.color, {super.key});
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final audit = AgentGate.instance.auditSink;
    final last = audit is MemoryAuditSink && audit.entries.isNotEmpty
        ? audit.entries.last
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: color),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'You were routed here by AgentGate.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (last != null) ...<Widget>[
              Text('Decision: ${last.decision.candidateId}'),
              Text('Source: ${last.decision.source.name}'),
              Text(
                'Confidence: ${last.decision.confidence.toStringAsFixed(2)}',
              ),
              Text('Reason: ${last.decision.reason ?? '-'}'),
              Text(
                'Latency: ${last.decision.latency?.inMilliseconds ?? '-'} ms',
              ),
              const SizedBox(height: 8),
              Text(
                'Request ${last.requestId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Spacer(),
            OutlinedButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Back to start'),
            ),
          ],
        ),
      ),
    );
  }
}
