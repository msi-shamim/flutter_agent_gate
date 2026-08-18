/// AI-agnostic behavioural routing middleware for Flutter.
///
/// From page **A**, declare candidates **B0…Bn**; AgentGate collects
/// consent-gated behaviour signals, asks *your* backend / AI to choose, and
/// routes there — with timeouts, fallbacks, allow-lists and audit trails.
///
/// See the README for the full guide.
library;

export 'src/adapters/navigation_adapter.dart';
export 'src/audit/audit.dart';
export 'src/context/behavior_event.dart';
export 'src/context/behavior_tracker.dart';
export 'src/context/consent_controller.dart';
export 'src/context/gate_context.dart';
export 'src/context/page_session.dart';
export 'src/context/redactor.dart';
export 'src/core/gate_candidate.dart';
export 'src/core/gate_config.dart';
export 'src/core/gate_decision.dart';
export 'src/core/gate_profile.dart';
export 'src/core/gate_request.dart';
export 'src/decider/agent_decider.dart';
export 'src/decider/callback_decider.dart';
export 'src/decider/http_decider.dart';
export 'src/decider/prompt_builder.dart';
export 'src/decider/rule_decider.dart';
export 'src/middleware/agent_gate.dart';
export 'src/middleware/gate.dart';
export 'src/middleware/widgets.dart';
export 'src/ui/agent_loading.dart';
