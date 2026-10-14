import 'dart:typed_data';

/// Utilities for scrubbing secret material from memory.
///
/// Dart `String` values are immutable and may be interned or copied by the
/// garbage collector, so they can never be reliably zeroed. This is a genuine
/// platform limitation, not an oversight:
///
/// * Secrets that originate as text (a Base32 secret pasted from a QR code) must
///   therefore be converted to [Uint8List] as early as possible, used, and then
///   wiped with [zero].
/// * Where a `String` is unavoidable, keep its lifetime as short as possible and
///   never place it in long-lived widget state or logs.
///
/// [zero] overwrites every byte in place. It is best-effort: it defeats casual
/// memory inspection and keeps secrets out of heap dumps, but it cannot defend
/// against an attacker who can already read the process's memory.
void zero(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return;
  bytes.fillRange(0, bytes.length, 0);
}

/// Zeroes several buffers, ignoring nulls.
void zeroAll(Iterable<Uint8List?> buffers) {
  buffers.forEach(zero);
}

/// Runs [body] with [bytes], then zeroes [bytes] even if [body] throws.
///
/// Use this for any operation that consumes a secret:
///
/// ```dart
/// final code = withSecret(secretBytes, (b) => hotp(b, counter));
/// ```
T withSecret<T>(Uint8List bytes, T Function(Uint8List bytes) body) {
  try {
    return body(bytes);
  } finally {
    zero(bytes);
  }
}
