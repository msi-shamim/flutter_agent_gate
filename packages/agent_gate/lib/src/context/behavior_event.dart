import 'package:meta/meta.dart';

/// Kinds of behavioural events the tracker understands.
///
/// Use [BehaviorEventType.custom] with a `name` for anything else.
enum BehaviorEventType {
  /// Page became visible.
  pageEnter,

  /// Page was left.
  pageExit,

  /// A tap / click on something identifiable.
  tap,

  /// Long-press.
  longPress,

  /// Scroll position update (throttled by the tracker).
  scroll,

  /// A text field got focus.
  fieldFocus,

  /// A text field lost focus.
  fieldBlur,

  /// The user changed a field value (value itself is NOT recorded).
  fieldEdit,

  /// A validation error was shown.
  validationError,

  /// An action was attempted (submit, pay, login…).
  attempt,

  /// An attempt succeeded.
  success,

  /// An attempt failed.
  failure,

  /// The user navigated back.
  back,

  /// App went to background / foreground.
  lifecycle,

  /// Developer-defined event.
  custom,
}

/// A single behavioural event.
@immutable
class BehaviorEvent {
  /// Creates an event.
  BehaviorEvent({
    required this.type,
    required this.page,
    this.target,
    this.name,
    this.value,
    this.attributes = const <String, Object?>{},
    DateTime? at,
  }) : at = at ?? DateTime.now().toUtc();

  /// Kind of event.
  final BehaviorEventType type;

  /// Page the event happened on.
  final String page;

  /// Widget / control identifier (`btn_pay`, `field_amount`).
  final String? target;

  /// Name for [BehaviorEventType.custom] events or attempt names.
  final String? name;

  /// Numeric value (scroll fraction, duration ms, …). Never raw user input.
  final num? value;

  /// Extra attributes. Redaction applies here too.
  final Map<String, Object?> attributes;

  /// UTC timestamp.
  final DateTime at;

  /// JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    't': type.name,
    'page': page,
    if (target != null) 'target': target,
    if (name != null) 'name': name,
    if (value != null) 'value': value,
    if (attributes.isNotEmpty) 'attrs': attributes,
    'at': at.toIso8601String(),
  };
}
