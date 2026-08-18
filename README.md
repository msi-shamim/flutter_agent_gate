# AgentGate monorepo

[![CI](https://github.com/msi-shamim/flutter_agent_gate/actions/workflows/ci.yml/badge.svg)](https://github.com/msi-shamim/flutter_agent_gate/actions/workflows/ci.yml) [![pub](https://img.shields.io/pub/v/agent_gate.svg)](https://pub.dev/packages/agent_gate)

AI-agnostic behavioural routing middleware for Flutter, plus adapters and
backend samples.

| Path | What | pub.dev |
|---|---|---|
| [`packages/agent_gate`](packages/agent_gate) | **Core** — gates, deciders, tracker, audit, adapters, widgets. Zero AI / state-management deps. | `agent_gate` |
| [`packages/agent_gate_go_router`](packages/agent_gate_go_router) | GoRouter adapter + `GateRoute` helper | `agent_gate_go_router` |
| [`packages/agent_gate_getx`](packages/agent_gate_getx) | GetX adapter + `GetPage` helper | `agent_gate_getx` |
| [`packages/agent_gate_bloc`](packages/agent_gate_bloc) | Bloc/Cubit integration (`GateCubit`, `GateBloc`, `GateBlocListener`) | `agent_gate_bloc` |
| [`packages/agent_gate_riverpod`](packages/agent_gate_riverpod) | Riverpod 3 integration (`gateDecisionProvider`, `GateNotifier`, `GateListener`) | `agent_gate_riverpod` |
| [`backends/node`](backends/node) | Reference `agent_gate/v1` decide endpoint (TypeScript, Express, OpenAI-compatible) | — |
| [`backends/python`](backends/python) | Reference `agent_gate/v1` decide endpoint (FastAPI, provider-agnostic) | — |

Start with the **core README**: [`packages/agent_gate/README.md`](packages/agent_gate/README.md).

## Development

```sh
cd packages/agent_gate && flutter pub get && flutter test
```

Companion packages depend on the core via a path dependency in this repo
(`dependency_overrides`) and on the published version when released. Keep the
core free of provider / state-management dependencies — that is the whole
point of the companion packages.

## License

MIT © MSI Shamim / Increments Inc.
