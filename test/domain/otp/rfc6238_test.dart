import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';

/// The secrets used by RFC 6238 Appendix B.
///
/// The RFC's published SHA-256 and SHA-512 vectors do not actually use the
/// 20-byte ASCII secret named in the surrounding prose — they use the ASCII
/// string repeated to the hash's block size. This is RFC 6238 errata ID 2866,
/// confirmed against the published values rather than assumed. The 20-byte
/// secret is used only for the SHA-1 column.
Uint8List _secretOfLength(int length) {
  const base = '12345678901234567890';
  final repeated = (base * ((length ~/ base.length) + 1)).substring(0, length);
  return Uint8List.fromList(utf8.encode(repeated));
}

final Uint8List _sha1Secret = _secretOfLength(20);
final Uint8List _sha256Secret = _secretOfLength(32);
final Uint8List _sha512Secret = _secretOfLength(64);

/// One row of RFC 6238 Appendix B Table 1.
typedef _Vector = ({int seconds, String sha1, String sha256, String sha512});

/// Appendix B Table 1, verbatim. All values are eight digits, because that is
/// what the RFC specifies for these vectors.
const List<_Vector> _vectors = <_Vector>[
  (seconds: 59, sha1: '94287082', sha256: '46119246', sha512: '90693936'),
  (
    seconds: 1111111109,
    sha1: '07081804',
    sha256: '68084774',
    sha512: '25091201',
  ),
  (
    seconds: 1111111111,
    sha1: '14050471',
    sha256: '67062674',
    sha512: '99943326',
  ),
  (
    seconds: 1234567890,
    sha1: '89005924',
    sha256: '91819424',
    sha512: '93441116',
  ),
  (
    seconds: 2000000000,
    sha1: '69279037',
    sha256: '90698825',
    sha512: '38618901',
  ),
  (
    seconds: 20000000000,
    sha1: '65353130',
    sha256: '77737706',
    sha512: '47863826',
  ),
];

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('RFC 6238 Appendix B — TOTP test vectors', () {
    test('SHA-1 vectors match the published table', () {
      for (final vector in _vectors) {
        expect(
          totp(_sha1Secret, _at(vector.seconds), digits: 8),
          vector.sha1,
          reason: 'SHA-1 at t=${vector.seconds}',
        );
      }
    });

    test('SHA-256 vectors match the published table', () {
      for (final vector in _vectors) {
        expect(
          totp(
            _sha256Secret,
            _at(vector.seconds),
            algorithm: OtpAlgorithm.sha256,
            digits: 8,
          ),
          vector.sha256,
          reason: 'SHA-256 at t=${vector.seconds}',
        );
      }
    });

    test('SHA-512 vectors match the published table', () {
      for (final vector in _vectors) {
        expect(
          totp(
            _sha512Secret,
            _at(vector.seconds),
            algorithm: OtpAlgorithm.sha512,
            digits: 8,
          ),
          vector.sha512,
          reason: 'SHA-512 at t=${vector.seconds}',
        );
      }
    });

    test('every vector is eight digits and correctly padded', () {
      for (final vector in _vectors) {
        for (final (algorithm, secret, expected)
            in <(OtpAlgorithm, Uint8List, String)>[
              (OtpAlgorithm.sha1, _sha1Secret, vector.sha1),
              (OtpAlgorithm.sha256, _sha256Secret, vector.sha256),
              (OtpAlgorithm.sha512, _sha512Secret, vector.sha512),
            ]) {
          final code = totp(
            secret,
            _at(vector.seconds),
            algorithm: algorithm,
            digits: 8,
          );
          expect(
            code,
            hasLength(8),
            reason: '${algorithm.name} at t=${vector.seconds}',
          );
          expect(code, expected);
        }
      }
    });
  });

  group('RFC 6238 errata 2866 — extended secrets', () {
    test('the 20-byte secret does NOT reproduce the SHA-256 vectors', () {
      // If this ever passes, the RFC's prose (rather than its vectors) has been
      // implemented, and the SHA-256/SHA-512 columns above are being satisfied
      // by coincidence. Documented as a test so the choice is deliberate.
      expect(
        totp(_sha1Secret, _at(59), algorithm: OtpAlgorithm.sha256, digits: 8),
        isNot('46119246'),
      );
    });

    test('the 20-byte secret DOES reproduce the SHA-1 vectors', () {
      expect(totp(_sha1Secret, _at(59), digits: 8), '94287082');
    });
  });

  group('time step', () {
    test('default period is 30 seconds', () {
      expect(kDefaultPeriod, 30);
    });

    test('all timestamps inside a step share one code', () {
      // t=59 falls in step 1 (seconds 30..59).
      final atThirty = totp(_sha1Secret, _at(30), digits: 8);
      final atFiftyNine = totp(_sha1Secret, _at(59), digits: 8);
      expect(atThirty, atFiftyNine);
    });

    test('the code changes at the next step boundary', () {
      final before = totp(_sha1Secret, _at(59), digits: 8);
      final after = totp(_sha1Secret, _at(60), digits: 8);
      expect(before, isNot(after));
    });

    test('a custom period shifts the boundaries', () {
      // With a 60-second period, t=59 and t=60 fall in *different* steps
      // (0 and 1), so their codes differ...
      expect(
        totp(_sha1Secret, _at(59), period: 60, digits: 8),
        isNot(totp(_sha1Secret, _at(60), period: 60, digits: 8)),
      );
      // ...whereas t=60 and t=119 share step 1.
      expect(
        totp(_sha1Secret, _at(60), period: 60, digits: 8),
        totp(_sha1Secret, _at(119), period: 60, digits: 8),
      );
      // Under the default 30-second period, t=60 and t=119 are in steps 2 and 3.
      expect(
        totp(_sha1Secret, _at(60), digits: 8),
        isNot(totp(_sha1Secret, _at(119), digits: 8)),
      );
    });

    test('rejects a non-positive period', () {
      for (final period in <int>[0, -1, -30]) {
        expect(
          () => totp(_sha1Secret, _at(59), period: period),
          throwsA(isA<OtpException>()),
          reason: 'period $period',
        );
      }
    });
  });

  group('totpCounter', () {
    test('is the floor of unix seconds divided by the period', () {
      expect(totpCounter(_at(0)), 0);
      expect(totpCounter(_at(29)), 0);
      expect(totpCounter(_at(30)), 1);
      expect(totpCounter(_at(59)), 1);
      expect(totpCounter(_at(60)), 2);
    });

    test('matches the T column published in RFC 6238 Table 1', () {
      // The RFC lists the time-step number in hex; 0x23523EC == 37051900.
      expect(totpCounter(_at(1111111109)), 0x23523EC);
      expect(totpCounter(_at(1111111111)), 0x23523ED);
      expect(totpCounter(_at(1234567890)), 0x273EF07);
      expect(totpCounter(_at(2000000000)), 0x3F940AA);
    });

    test('uses UTC, not local time', () {
      final utc = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      final sameMomentLocal = utc.toLocal();
      expect(totpCounter(utc), totpCounter(sameMomentLocal));
    });
  });

  group('totpSecondsRemaining', () {
    test('counts down through a step', () {
      expect(totpSecondsRemaining(_at(0)), 30);
      expect(totpSecondsRemaining(_at(1)), 29);
      expect(totpSecondsRemaining(_at(29)), 1);
      expect(totpSecondsRemaining(_at(30)), 30);
    });

    test('never returns zero or more than the period', () {
      // The UI shows this number; a 0 or 31 would look like a bug.
      for (var second = 0; second < 300; second++) {
        final remaining = totpSecondsRemaining(_at(second));
        expect(remaining, greaterThanOrEqualTo(1), reason: 't=$second');
        expect(remaining, lessThanOrEqualTo(30), reason: 't=$second');
      }
    });

    test('respects a custom period', () {
      expect(totpSecondsRemaining(_at(0), 60), 60);
      expect(totpSecondsRemaining(_at(59), 60), 1);
      expect(totpSecondsRemaining(_at(60), 60), 60);
    });
  });

  group('totpProgress', () {
    test('runs from zero to just under one across a step', () {
      expect(totpProgress(_at(0)), 0);
      expect(totpProgress(_at(15)), closeTo(0.5, 1e-9));
      expect(totpProgress(_at(29)), closeTo(29 / 30, 1e-9));
    });

    test('stays within 0.0..1.0', () {
      for (var second = 0; second < 120; second++) {
        final progress = totpProgress(_at(second));
        expect(progress, greaterThanOrEqualTo(0.0), reason: 't=$second');
        expect(progress, lessThanOrEqualTo(1.0), reason: 't=$second');
      }
    });

    test('is consistent with seconds remaining', () {
      // The two are rendered side by side, so they must not disagree.
      // secondsRemaining = period - floor(progress * period), clamped to >= 1.
      const period = 30;
      for (final second in <int>[0, 5, 17, 29, 45, 59]) {
        final progress = totpProgress(_at(second));
        final remaining = totpSecondsRemaining(_at(second));
        final elapsed = (progress * period).floor();
        expect(remaining, period - elapsed, reason: 't=$second');
      }
    });
  });

  group('sub-second precision', () {
    test('a timestamp mid-second uses the correct step', () {
      final onTheBoundary = DateTime.fromMillisecondsSinceEpoch(
        60 * 1000,
        isUtc: true,
      );
      final justAfter = DateTime.fromMillisecondsSinceEpoch(
        60 * 1000 + 500,
        isUtc: true,
      );
      final justBefore = DateTime.fromMillisecondsSinceEpoch(
        60 * 1000 - 1,
        isUtc: true,
      );

      expect(totpCounter(justAfter), totpCounter(onTheBoundary));
      expect(totpCounter(justBefore), totpCounter(onTheBoundary) - 1);
    });
  });
}
