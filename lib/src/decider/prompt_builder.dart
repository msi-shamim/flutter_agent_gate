import 'dart:convert';

import '../core/gate_request.dart';

/// Builds provider-shaped prompts and tool/function schemas from a
/// [GateRequest].
///
/// AgentGate never calls a model itself, but it gives you battle-tested
/// prompt scaffolding so your backend (or on-device SDK) can do so in a few
/// lines and get back the canonical `{candidate_id, confidence, reason}`.
///
/// Three shapes are provided because the three big SDK families differ:
/// * [openAiTool] – OpenAI `tools[].function` (also works for most
///   OpenAI-compatible APIs: Groq, Mistral, Together, Ollama…).
/// * [anthropicTool] – Anthropic `tools[]` with `input_schema`.
/// * [geminiFunctionDeclaration] – Gemini `function_declarations[]`.
class PromptBuilder {
  /// Creates a builder.
  const PromptBuilder({
    this.toolName = 'choose_next_page',
    this.systemPreamble,
  });

  /// Name of the tool/function the model must call.
  final String toolName;

  /// Optional text prepended to the system prompt.
  final String? systemPreamble;

  /// The JSON schema of the decision the model must return.
  Map<String, Object?> decisionSchema(GateRequest r) => <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['candidate_id', 'confidence', 'reason'],
        'properties': <String, Object?>{
          'candidate_id': <String, Object?>{
            'type': 'string',
            'description': 'The id of the single best candidate page.',
            'enum': r.candidates.map((c) => c.id).toList(),
          },
          'confidence': <String, Object?>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
            'description': 'How sure you are, 0..1.',
          },
          'reason': <String, Object?>{
            'type': 'string',
            'description':
                'One or two sentences, in plain language, explaining why. '
                    'This may be shown to the user and stored for audit.',
          },
        },
      };

  /// System prompt: role, rules, and profile-specific guidance.
  String systemPrompt(GateRequest r) {
    final b = StringBuffer();
    if (systemPreamble != null) b.writeln(systemPreamble);
    b.writeln(
      'You are a navigation decision engine inside a mobile application. '
      'The user is leaving page "${r.fromPage}". You must pick exactly one '
      'of the candidate next pages by calling the tool "$toolName".',
    );
    b.writeln();
    b.writeln('Rules:');
    b.writeln('- Choose ONLY from the provided candidate ids.');
    b.writeln('- Base your choice on the behavioural context and app context.');
    b.writeln('- Explain the reason briefly and truthfully.');
    b.writeln('- If the context is insufficient, pick the candidate that is '
        'safest / most neutral for the user and give a low confidence.');
    switch (r.profile.name) {
      case 'risk':
        b.writeln('- This is a RISK decision. Prefer protective outcomes '
            '(verification, review, safe defaults) when signals are anomalous. '
            'Never route to a less-protected page on weak evidence.');
      case 'recommendation':
        b.writeln('- This is a RECOMMENDATION decision. Optimise for the '
            "user's stated and inferred goals; do not pressure or mislead.");
      default:
        break;
    }
    if (r.instructions != null) {
      b.writeln();
      b.writeln('Developer instructions:');
      b.writeln(r.instructions);
    }
    return b.toString();
  }

  /// User prompt: candidates + context as JSON.
  String userPrompt(GateRequest r) {
    final enc = const JsonEncoder.withIndent('  ');
    return 'Candidates:\n${enc.convert(r.candidates.map((c) => c.toJson()).toList())}\n\n'
        'Context:\n${enc.convert(r.context.toJson())}\n\n'
        'Call $toolName now.';
  }

  /// OpenAI-style tool definition.
  Map<String, Object?> openAiTool(GateRequest r) => <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': toolName,
          'description': 'Select the next page for the user.',
          'parameters': decisionSchema(r),
          'strict': true,
        },
      };

  /// Full OpenAI chat-completions request body (minus `model`).
  Map<String, Object?> openAiRequest(GateRequest r) => <String, Object?>{
        'messages': <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': systemPrompt(r)},
          <String, Object?>{'role': 'user', 'content': userPrompt(r)},
        ],
        'tools': <Object?>[openAiTool(r)],
        'tool_choice': <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{'name': toolName},
        },
        'temperature': 0,
      };

  /// Anthropic-style tool definition.
  Map<String, Object?> anthropicTool(GateRequest r) => <String, Object?>{
        'name': toolName,
        'description': 'Select the next page for the user.',
        'input_schema': decisionSchema(r),
      };

  /// Full Anthropic messages request body (minus `model` / `max_tokens`).
  Map<String, Object?> anthropicRequest(GateRequest r) => <String, Object?>{
        'system': systemPrompt(r),
        'messages': <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': userPrompt(r)},
        ],
        'tools': <Object?>[anthropicTool(r)],
        'tool_choice': <String, Object?>{'type': 'tool', 'name': toolName},
        'temperature': 0,
      };

  /// Gemini-style function declaration.
  Map<String, Object?> geminiFunctionDeclaration(GateRequest r) =>
      <String, Object?>{
        'name': toolName,
        'description': 'Select the next page for the user.',
        'parameters': _stripForGemini(decisionSchema(r)),
      };

  /// Full Gemini generateContent request body.
  Map<String, Object?> geminiRequest(GateRequest r) => <String, Object?>{
        'system_instruction': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': systemPrompt(r)},
          ],
        },
        'contents': <Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': userPrompt(r)},
            ],
          },
        ],
        'tools': <Object?>[
          <String, Object?>{
            'function_declarations': <Object?>[geminiFunctionDeclaration(r)],
          },
        ],
        'tool_config': <String, Object?>{
          'function_calling_config': <String, Object?>{
            'mode': 'ANY',
            'allowed_function_names': <String>[toolName],
          },
        },
      };

  // Gemini rejects `additionalProperties`.
  Map<String, Object?> _stripForGemini(Map<String, Object?> s) {
    final out = Map<String, Object?>.from(s)..remove('additionalProperties');
    return out;
  }
}
