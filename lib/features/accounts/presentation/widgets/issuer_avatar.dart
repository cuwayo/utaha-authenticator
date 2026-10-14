import 'package:flutter/material.dart';

/// A circular avatar showing the first letter of an account's issuer.
///
/// Used when no bundled icon is available for a service. The colour is chosen
/// deterministically from the issuer name, so the same service always gets the
/// same colour and the list is visually scannable without needing artwork.
class IssuerAvatar extends StatelessWidget {
  /// Creates an avatar for [label], which is the issuer or the account name.
  const new({required this.label, this.size = 40, super.key});

  /// Text to derive the initial and colour from.
  final String label;

  /// Diameter of the avatar.
  final double size;

  /// Hues chosen to stay legible with white text in both light and dark themes.
  ///
  /// Deliberately not derived from the colour scheme: every avatar would then be
  /// the same colour, which defeats the point of a scannable list.
  static const List<Color> _palette = <Color>[
    Color(0xFF5B3FA6), // violet
    Color(0xFF1565C0), // blue
    Color(0xFF00695C), // teal
    Color(0xFF2E7D32), // green
    Color(0xFFB26A00), // amber
    Color(0xFFAD1457), // pink
    Color(0xFF4527A0), // deep purple
    Color(0xFF00838F), // cyan
  ];

  /// The colour this label maps to.
  Color get _colour {
    if (label.isEmpty) return _palette.first;
    // Sum of code units: stable across runs, unlike Object.hashCode which is
    // randomised per process and would make the colours shuffle on restart.
    var sum = 0;
    for (final unit in label.codeUnits) {
      sum = (sum + unit) % _palette.length;
    }
    return _palette[sum];
  }

  /// The initial shown in the avatar.
  String get _initial {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    // Take the first character, which for an emoji or a non-BMP letter is a
    // whole grapheme rather than half a surrogate pair.
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _colour, shape: BoxShape.circle),
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
