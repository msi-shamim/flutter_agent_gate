/// Removes sensitive keys from a JSON-like structure before it leaves the
/// device.
///
/// Matching is case-insensitive and applies at any depth. Matched values are
/// replaced with [placeholder] rather than dropped, so a backend can still
/// see that a field existed.
class Redactor {
  /// Creates a redactor.
  const Redactor(this.keys, {this.placeholder = '[REDACTED]'});

  /// Common PII/PCI keys — a sane starting point, extend for your domain.
  static const Set<String> defaultKeys = <String>{
    'email',
    'phone',
    'password',
    'pin',
    'otp',
    'ssn',
    'iban',
    'card',
    'card_number',
    'cardnumber',
    'pan',
    'cvv',
    'cvc',
    'token',
    'access_token',
    'refresh_token',
    'authorization',
    'address',
    'dob',
    'date_of_birth',
    'national_id',
    'passport',
  };

  /// Keys to redact (case-insensitive).
  final Set<String> keys;

  /// Replacement value.
  final String placeholder;

  /// Returns a deep copy of [input] with matching keys replaced.
  Object? apply(Object? input) {
    if (keys.isEmpty) return input;
    final lower = keys.map((k) => k.toLowerCase()).toSet();
    return _walk(input, lower);
  }

  /// Convenience for maps.
  Map<String, Object?> applyToMap(Map<String, Object?> input) =>
      apply(input)! as Map<String, Object?>;

  Object? _walk(Object? v, Set<String> lower) {
    if (v is Map) {
      final out = <String, Object?>{};
      v.forEach((Object? k, Object? val) {
        final key = k.toString();
        out[key] =
            lower.contains(key.toLowerCase()) ? placeholder : _walk(val, lower);
      });
      return out;
    }
    if (v is List) return v.map((e) => _walk(e, lower)).toList();
    return v;
  }
}
