/// JSON conversion helpers shared by the freezed models.
///
/// The backend stores naive UTC datetimes, so serialized values usually have
/// no timezone offset. These helpers parse such values as UTC by appending
/// 'Z' — but ONLY when no explicit offset is present.
library;

final RegExp _offsetPattern = RegExp(r'(Z|z|[+-]\d{2}:?\d{2})$');

/// Parses [value] as a [DateTime], treating offset-less values as UTC.
DateTime dateTimeFromJson(String value) {
  final s = value.trim();
  final hasOffset = _offsetPattern.hasMatch(s);
  final hasTime = s.contains('T') || s.contains(':');
  if (!hasOffset && hasTime) {
    return DateTime.parse('${s}Z');
  }
  return DateTime.parse(s);
}

/// Nullable variant of [dateTimeFromJson].
DateTime? nullableDateTimeFromJson(String? value) =>
    value == null ? null : dateTimeFromJson(value);
