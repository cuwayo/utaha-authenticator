import 'package:local_auth/local_auth.dart' as local_auth;

/// The kinds of authentication a device can offer.
///
/// A trimmed-down copy of the plugin's enum so the domain layer does not depend
/// on a platform package, and so the set is explicit rather than open-ended.
enum BiometricKind {
  /// A fingerprint reader.
  fingerprint,

  /// Face recognition.
  face,

  /// Iris recognition.
  iris,

  /// Any other biometric the platform reports.
  other,
}

/// Checks for and performs device authentication.
///
/// Wraps the platform plugin so the lock logic can be tested without a device,
/// and so the app depends on a narrow interface rather than the plugin's full
/// surface.
abstract interface class BiometricAuth {
  /// Whether this device can authenticate at all.
  ///
  /// False on a device with no biometrics and no PIN, pattern or password set —
  /// in which case enabling the app lock would lock the user out permanently,
  /// so the setting must refuse to turn on.
  Future<bool> isAvailable();

  /// The authentication methods enrolled on this device.
  Future<List<BiometricKind>> availableKinds();

  /// Prompts the user to authenticate.
  ///
  /// Returns true on success and false when the user cancels or fails. Throws
  /// nothing: every failure is a false, because the caller's only decision is
  /// whether to unlock.
  Future<bool> authenticate({required String reason});
}

/// A [BiometricAuth] backed by `local_auth`.
class PlatformBiometricAuth implements BiometricAuth {
  /// Creates the platform-backed implementation.
  new({local_auth.LocalAuthentication? auth})
    : _auth = auth ?? local_auth.LocalAuthentication();

  final local_auth.LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return true;
    } on Object {
      // A platform that cannot answer is treated as unable to authenticate,
      // which is the safe direction: it stops the lock being enabled.
      return false;
    }
  }

  @override
  Future<List<BiometricKind>> availableKinds() async {
    try {
      final kinds = await _auth.getAvailableBiometrics();
      return kinds.map(_mapKind).toList(growable: false);
    } on Object {
      return const <BiometricKind>[];
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } on Object {
      // Includes the user cancelling, which is not an error worth surfacing.
      return false;
    }
  }

  static BiometricKind _mapKind(local_auth.BiometricType type) =>
      switch (type) {
        local_auth.BiometricType.face => BiometricKind.face,
        local_auth.BiometricType.fingerprint => BiometricKind.fingerprint,
        local_auth.BiometricType.iris => BiometricKind.iris,
        _ => BiometricKind.other,
      };
}

/// A [BiometricAuth] for tests and for platforms without a prompt.
class FakeBiometricAuth implements BiometricAuth {
  /// Creates a fake.
  new({
    this.available = true,
    this.succeeds = true,
    this.kinds = const <BiometricKind>[BiometricKind.fingerprint],
  });

  /// Whether the device reports any usable authentication.
  bool available;

  /// Whether [authenticate] succeeds.
  bool succeeds;

  /// What [availableKinds] reports.
  List<BiometricKind> kinds;

  /// How many times [authenticate] was called.
  int authenticateCount = 0;

  /// When set, [authenticate] throws this instead of returning.
  Exception? failWith;

  /// The reasons passed to [authenticate], in order.
  final List<String> reasons = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<BiometricKind>> availableKinds() async => kinds;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCount++;
    reasons.add(reason);
    if (failWith != null) throw failWith!;
    return succeeds;
  }
}
