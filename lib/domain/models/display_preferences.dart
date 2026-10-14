/// How much vertical space each row in the account list consumes.
///
/// This lives in the domain layer as a plain enum so it can be persisted and
/// reasoned about without depending on Flutter. The mapping to Flutter's
/// `VisualDensity` lives in the theme layer.
enum ListDensity {
  /// Roomy rows with generous padding.
  comfortable,

  /// Tighter rows that fit more accounts on screen.
  compact;

  /// Stable identifier used for persistence.
  String get id => name;

  /// Parses [id], falling back to [ListDensity.comfortable].
  static ListDensity fromId(String? id) => ListDensity.values.firstWhere(
    (value) => value.name == id,
    orElse: () => ListDensity.comfortable,
  );
}

/// How an OTP code is split into groups for display, e.g. `123 456`.
enum CodeGrouping {
  /// `123456` — no separation.
  none,

  /// `12 34 56` — groups of two.
  pairs,

  /// `123 456` — groups of three.
  triples,

  /// `1234 56` — a group of four, then the remainder.
  quads;

  /// Stable identifier used for persistence.
  String get id => name;

  /// Parses [id], falling back to [CodeGrouping.triples].
  static CodeGrouping fromId(String? id) => CodeGrouping.values.firstWhere(
    (value) => value.name == id,
    orElse: () => CodeGrouping.triples,
  );

  /// Formats [code] using this grouping.
  ///
  /// Trailing groups shorter than the group size are kept as-is, so an
  /// eight-digit code with [CodeGrouping.triples] becomes `123 456 78`.
  String format(String code) {
    final size = switch (this) {
      CodeGrouping.none => 0,
      CodeGrouping.pairs => 2,
      CodeGrouping.triples => 3,
      CodeGrouping.quads => 4,
    };
    if (size == 0 || code.length <= size) return code;

    final parts = <String>[];
    for (var i = 0; i < code.length; i += size) {
      parts.add(
        code.substring(i, i + size > code.length ? code.length : i + size),
      );
    }
    return parts.join(' ');
  }
}
