/// Which kind of decision a gate is making.
///
/// The profile changes defaults, fallback behaviour and how much the AI is
/// trusted. Keep protective (risk) routing and persuasive (recommendation)
/// routing separate — they have different compliance stories.
enum GateProfile {
  /// Fraud / risk / step-up-auth style routing.
  ///
  /// * Rules are the floor, AI is an assist.
  /// * Short timeouts, deterministic fallback.
  /// * Every decision is audited.
  risk,

  /// Personalisation / recommendation / funnel optimisation routing.
  ///
  /// * AI has more latitude.
  /// * Longer timeouts allowed, decisions can be cached.
  recommendation,

  /// Anything else — plain adaptive navigation.
  general,
}
