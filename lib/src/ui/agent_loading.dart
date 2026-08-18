import 'package:flutter/material.dart';

/// Signature for a custom loading builder. [reasoning] streams partial
/// model output when the decider supports it (may be null).
typedef AgentLoadingBuilder = Widget Function(
  BuildContext context,
  Stream<String>? reasoning,
);

/// Default "agentic loading" screen: a subtle progress indicator with an
/// optional live reasoning ticker. Replace it via `AgentGate.loadingBuilder`.
class AgentLoadingView extends StatelessWidget {
  /// Creates the view.
  const AgentLoadingView({
    super.key,
    this.reasoning,
    this.title = 'Preparing the best next step…',
    this.showReasoning = true,
  });

  /// Optional streamed reasoning text.
  final Stream<String>? reasoning;

  /// Title text.
  final String title;

  /// Whether to show reasoning.
  final bool showReasoning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (showReasoning && reasoning != null) ...<Widget>[
                  const SizedBox(height: 16),
                  StreamBuilder<String>(
                    stream: reasoning,
                    builder: (context, snap) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        snap.data ?? '',
                        key: ValueKey<String>(snap.data ?? ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
