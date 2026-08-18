import 'package:flutter/foundation.dart';

/// Consent state for behavioural tracking.
///
/// Tracking is **off by default**. Your app decides when the user has
/// consented (cookie banner, privacy settings, T&Cs) and flips this on.
/// When consent is absent, [BehaviorTracker] records nothing and the
/// decider only receives the app-supplied context.
class ConsentController extends ChangeNotifier {
  /// Creates a controller. Defaults to no consent.
  ConsentController({bool initial = false}) : _granted = initial;

  bool _granted;

  /// Whether behavioural signals may be collected and sent.
  bool get granted => _granted;

  /// Grant consent.
  void grant() => _set(true);

  /// Revoke consent (also clears in-memory behaviour buffers via listeners).
  void revoke() => _set(false);

  void _set(bool v) {
    if (v == _granted) return;
    _granted = v;
    notifyListeners();
  }
}
