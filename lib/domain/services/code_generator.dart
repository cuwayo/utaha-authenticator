import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';

/// Supplies the current time.
///
/// Injected rather than calling [DateTime.now] directly so the countdown and
/// code generation can be driven deterministically in tests.
abstract interface class Clock {
  /// The current instant, in UTC.
  DateTime now();
}

/// The real clock.
class SystemClock implements Clock {
  /// Creates a clock that reads the system time.
  const new();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock fixed at a chosen instant, for tests.
class FixedClock implements Clock {
  /// Creates a clock pinned to [instant].
  new(this.instant);

  /// The instant this clock reports.
  DateTime instant;

  @override
  DateTime now() => instant;
}

/// The current state of an account's code.
class AccountCode {
  /// Creates a code snapshot.
  const new({required this.code, this.secondsRemaining, this.progress});

  /// The formatted code, padded to the account's digit count.
  final String code;

  /// Whole seconds until the code changes. Null for HOTP, which has no expiry.
  final int? secondsRemaining;

  /// Fraction of the period elapsed, `0.0..1.0`. Null for HOTP.
  final double? progress;

  /// Whether this code is about to expire.
  ///
  /// True in the final five seconds of a period, which the UI renders in the
  /// error colour.
  bool get isExpiringSoon => secondsRemaining != null && secondsRemaining! <= 5;
}

/// Generates codes for accounts, reading secrets from the keystore on demand.
///
/// Secrets are read, used and zeroed inside this class and are never returned to
/// callers, so no secret can reach widget state, a log or a crash report.
class CodeGenerator {
  /// Creates a generator over [_secrets] and [_clock].
  new({required this._secrets, required this._clock});

  final SecretRepository _secrets;
  final Clock _clock;

  /// Generates the code an account is currently showing.
  ///
  /// Returns null when the account's secret is missing — for example after a
  /// keystore reset — so the caller can flag the account instead of failing.
  Future<AccountCode?> generate(Account account) async {
    final secret = await _secrets.read(account.id);
    if (secret == null || secret.isEmpty) {
      zero(secret);
      return null;
    }

    try {
      final now = _clock.now();
      final code = switch (account.type) {
        OtpType.totp => totp(
          secret,
          now,
          algorithm: account.algorithm,
          digits: account.digits,
          period: account.period,
        ),
        OtpType.hotp => hotp(
          secret,
          account.counter,
          algorithm: account.algorithm,
          digits: account.digits,
        ),
      };

      return AccountCode(
        code: code,
        secondsRemaining: account.type == OtpType.totp
            ? totpSecondsRemaining(now, account.period)
            : null,
        progress: account.type == OtpType.totp
            ? totpProgress(now, account.period)
            : null,
      );
    } finally {
      // Zero the secret as soon as the code is derived. Nothing above this line
      // may retain a reference to it.
      zero(secret);
    }
  }

  /// The current instant, exposed so the UI and the generator agree on time.
  DateTime now() => _clock.now();
}
