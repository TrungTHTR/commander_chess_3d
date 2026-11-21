/// Deterministic UTC clock abstraction for match timestamps and tests.
abstract interface class Clock {
  DateTime nowUtc();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class FixedClock implements Clock {
  FixedClock(DateTime initialUtc) : _currentUtc = initialUtc.toUtc();

  DateTime _currentUtc;

  @override
  DateTime nowUtc() => _currentUtc;

  void setNowUtc(DateTime utc) {
    _currentUtc = utc.toUtc();
  }

  void advance(Duration delta) {
    _currentUtc = _currentUtc.add(delta);
  }
}
