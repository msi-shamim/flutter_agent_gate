import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'behavior_event.dart';
import 'consent_controller.dart';
import 'page_session.dart';

/// Collects behavioural events, in memory, on device.
///
/// * **Consent-gated** — records nothing until [ConsentController.granted].
/// * **Bounded** — keeps at most [maxEvents] and at most [maxPages] page
///   histories; oldest are dropped.
/// * **No raw input** — the API only accepts identifiers and numbers. Field
///   *values* are never captured.
///
/// One tracker per app is typical. Use [AgentGate.tracker] or create your own
/// and pass it in.
class BehaviorTracker extends ChangeNotifier with WidgetsBindingObserver {
  /// Creates a tracker.
  BehaviorTracker({
    ConsentController? consent,
    this.maxEvents = 2000,
    this.maxPages = 30,
    this.scrollThrottle = const Duration(milliseconds: 250),
    this.observeLifecycle = true,
  }) : consent = consent ?? ConsentController() {
    this.consent.addListener(_onConsentChanged);
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// Consent controller.
  final ConsentController consent;

  /// Ring-buffer size for raw events.
  final int maxEvents;

  /// How many distinct page visits to remember.
  final int maxPages;

  /// Minimum gap between recorded scroll events.
  final Duration scrollThrottle;

  /// Whether to record app lifecycle events.
  final bool observeLifecycle;

  final ListQueue<BehaviorEvent> _events = ListQueue<BehaviorEvent>();
  final LinkedHashMap<String, DateTime> _pageOrder =
      LinkedHashMap<String, DateTime>();
  String? _currentPage;
  DateTime? _lastScroll;

  /// Page the user is currently on (last [enterPage]).
  String? get currentPage => _currentPage;

  /// Snapshot of raw events (unmodifiable).
  List<BehaviorEvent> get events => List.unmodifiable(_events);

  /// Whether recording is active.
  bool get isRecording => consent.granted;

  // ── Recording API ─────────────────────────────────────────────────────

  /// Mark that [page] became visible.
  void enterPage(String page) {
    _currentPage = page;
    _record(BehaviorEvent(type: BehaviorEventType.pageEnter, page: page));
    _pageOrder.remove(page);
    _pageOrder[page] = DateTime.now().toUtc();
    while (_pageOrder.length > maxPages) {
      final oldest = _pageOrder.keys.first;
      _pageOrder.remove(oldest);
      _events.removeWhere((e) => e.page == oldest);
    }
  }

  /// Mark that [page] (default: current) was left.
  void exitPage([String? page]) {
    final p = page ?? _currentPage;
    if (p == null) return;
    _record(BehaviorEvent(type: BehaviorEventType.pageExit, page: p));
    if (p == _currentPage) _currentPage = null;
  }

  /// A tap on [target].
  void tap(String target, {Map<String, Object?> attributes = const {}}) =>
      _quick(BehaviorEventType.tap, target: target, attributes: attributes);

  /// A long-press on [target].
  void longPress(String target) =>
      _quick(BehaviorEventType.longPress, target: target);

  /// Scroll position as a 0..1 fraction (throttled).
  void scroll(double fraction, {String? target}) {
    final now = DateTime.now();
    if (_lastScroll != null && now.difference(_lastScroll!) < scrollThrottle) {
      return;
    }
    _lastScroll = now;
    _quick(BehaviorEventType.scroll, target: target, value: fraction);
  }

  /// A field gained focus.
  void fieldFocus(String field) =>
      _quick(BehaviorEventType.fieldFocus, target: field);

  /// A field lost focus.
  void fieldBlur(String field) =>
      _quick(BehaviorEventType.fieldBlur, target: field);

  /// A field was edited. Only the *fact* is recorded, never the value.
  void fieldEdit(String field, {int? length}) =>
      _quick(BehaviorEventType.fieldEdit, target: field, value: length);

  /// A validation error appeared on [field].
  void validationError(String field, {String? code}) =>
      _quick(BehaviorEventType.validationError, target: field, name: code);

  /// The user attempted an action (`pay`, `login`, `submit`).
  void attempt(String name, {Map<String, Object?> attributes = const {}}) =>
      _quick(BehaviorEventType.attempt, name: name, attributes: attributes);

  /// The attempt [name] succeeded.
  void success(String name) => _quick(BehaviorEventType.success, name: name);

  /// The attempt [name] failed with an optional [code].
  void failure(String name, {String? code}) => _quick(
    BehaviorEventType.failure,
    name: name,
    attributes: code == null ? const {} : {'code': code},
  );

  /// User navigated back.
  void back() => _quick(BehaviorEventType.back);

  /// Developer-defined event.
  void custom(
    String name, {
    String? target,
    num? value,
    Map<String, Object?> attributes = const {},
  }) => _quick(
    BehaviorEventType.custom,
    name: name,
    target: target,
    value: value,
    attributes: attributes,
  );

  /// Records an already-built event.
  void add(BehaviorEvent event) => _record(event);

  // ── Query API ─────────────────────────────────────────────────────────

  /// Summary for [page] (default: current page).
  PageSessionSummary summaryFor([String? page]) {
    final p = page ?? _currentPage ?? '';
    return PageSessionSummary.fromEvents(p, _events.toList());
  }

  /// Summaries for the last [count] visited pages, most recent first.
  List<PageSessionSummary> recentSummaries({int count = 5}) {
    final pages = _pageOrder.keys.toList().reversed.take(count);
    return pages.map(summaryFor).toList();
  }

  /// Ordered list of recently visited page ids (most recent last).
  List<String> get pageTrail => List.unmodifiable(_pageOrder.keys);

  /// Raw events for one page.
  List<BehaviorEvent> eventsFor(String page) =>
      _events.where((e) => e.page == page).toList(growable: false);

  /// Wipes everything.
  void clear() {
    _events.clear();
    _pageOrder.clear();
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  void _quick(
    BehaviorEventType type, {
    String? target,
    String? name,
    num? value,
    Map<String, Object?> attributes = const {},
  }) {
    final page = _currentPage;
    if (page == null) return;
    _record(
      BehaviorEvent(
        type: type,
        page: page,
        target: target,
        name: name,
        value: value,
        attributes: attributes,
      ),
    );
  }

  void _record(BehaviorEvent e) {
    if (!consent.granted) return;
    _events.addLast(e);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    notifyListeners();
  }

  void _onConsentChanged() {
    if (!consent.granted) clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _quick(BehaviorEventType.lifecycle, name: state.name);
  }

  @override
  void dispose() {
    consent.removeListener(_onConsentChanged);
    if (observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
