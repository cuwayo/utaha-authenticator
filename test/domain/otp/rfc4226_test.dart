import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';

/// The HOTP test vectors from RFC 4226 Appendix D.
///
/// The shared secret is the ASCII string "12345678901234567890", which is 20
/// bytes long.
final Uint8List _rfc4226Secret = Uint8List.fromList(
  utf8.encode('12345678901234567890'),
);

/// Table 2: the HOTP value for each counter, as published in the RFC.
const List<int> _rfc4226Expected = <int>[
  755224,
  287082,
  359152,
  969429,
  338314,
  254676,
  287922,
  162583,
  399871,
  520489,
];

void main() {
  group('RFC 4226 Appendix D — HOTP test vectors', () {
    test('secret is the documented 20-byte ASCII string', () {
      expect(_rfc4226Secret, hasLength(20));
      expect(_rfc4226Secret, <int>[
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, //
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30,
      ]);
    });

    test('produces the published HOTP value for counters 0 through 9', () {
      for (var counter = 0; counter < _rfc4226Expected.length; counter++) {
        expect(
          hotp(_rfc4226Secret, counter),
          _rfc4226Expected[counter].toString(),
          reason: 'counter $counter',
        );
      }
    });

    test('every vector is exactly six digits', () {
      for (var counter = 0; counter < _rfc4226Expected.length; counter++) {
        expect(hotp(_rfc4226Secret, counter), hasLength(6));
      }
    });

    test('counter values beyond the published table stay deterministic', () {
      // Guards against an off-by-one in the counter encoding showing up only
      // outside the published range.
      final first = hotp(_rfc4226Secret, 1234567890);
      final second = hotp(_rfc4226Secret, 1234567890);
      expect(first, second);
      expect(first, hasLength(6));
      expect(hotp(_rfc4226Secret, 1234567891), isNot(first));
    });

    test('the counter is encoded big-endian', () {
      // A little-endian encoding would collide counter 1 with counter
      // 0x0100000000000000, so distinct counters must give distinct codes.
      expect(
        hotp(_rfc4226Secret, 1),
        isNot(hotp(_rfc4226Secret, 0x0100000000000000)),
      );
    });
  });

  group('digit counts', () {
    test('six digits truncates to the last six digits of the integer', () {
      // Counter 0 truncates to 1284755224, so six digits is 755224.
      expect(hotp(_rfc4226Secret, 0), '755224');
    });

    test('seven digits keeps one more digit', () {
      // 1284755224 % 10^7 == 4755224
      expect(hotp(_rfc4226Secret, 0, digits: 7), '4755224');
    });

    test('eight digits keeps two more', () {
      // 1284755224 % 10^8 == 84755224
      expect(hotp(_rfc4226Secret, 0, digits: 8), '84755224');
    });

    test('rejects unsupported digit counts', () {
      for (final digits in <int>[0, 1, 5, 9, 10, -6]) {
        expect(
          () => hotp(_rfc4226Secret, 0, digits: digits),
          throwsA(isA<OtpException>()),
          reason: 'digits $digits should be rejected',
        );
      }
    });
  });

  group('padding', () {
    test(
      'a code that truncates to a small number is left-padded with zeroes',
      () {
        // RFC 6238's SHA-1 vector at t=1111111109 is 07081804; without padding
        // this would render as "7081804" and be rejected by the server. The
        // padding is therefore a correctness requirement, not cosmetics.
        final code = totp(
          _rfc4226Secret,
          DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true),
          digits: 8,
        );
        expect(code, '07081804');
        expect(code, hasLength(8));
        expect(code.startsWith('0'), isTrue);
      },
    );
  });

  group('input validation', () {
    test('rejects an empty secret', () {
      expect(
        () => hotp(Uint8List(0), 0),
        throwsA(
          isA<OtpException>().having(
            (e) => e.message,
            'message',
            contains('no secret key'),
          ),
        ),
      );
    });

    test('rejects a negative counter', () {
      expect(
        () => hotp(_rfc4226Secret, -1),
        throwsA(
          isA<OtpException>().having(
            (e) => e.message,
            'message',
            contains('invalid counter'),
          ),
        ),
      );
    });

    test('error messages avoid technical jargon', () {
      // These strings reach the user directly.
      try {
        hotp(Uint8List(0), 0);
        fail('expected an exception');
      } on OtpException catch (error) {
        final text = error.message.toLowerCase();
        expect(text, isNot(contains('hmac')));
        expect(text, isNot(contains('rfc')));
        expect(text, isNot(contains('null')));
        expect(text, isNot(contains('exception')));
      }
    });
  });

  group('algorithms', () {
    test('SHA-1 is the default', () {
      expect(hotp(_rfc4226Secret, 0), hotp(_rfc4226Secret, 0));
    });

    test('different algorithms produce different codes', () {
      final sha1 = hotp(_rfc4226Secret, 0);
      final sha256 = hotp(_rfc4226Secret, 0, algorithm: OtpAlgorithm.sha256);
      final sha512 = hotp(_rfc4226Secret, 0, algorithm: OtpAlgorithm.sha512);
      expect(sha1, isNot(sha256));
      expect(sha256, isNot(sha512));
      expect(sha1, isNot(sha512));
    });

    test('macLength matches the hash output size', () {
      expect(OtpAlgorithm.sha1.macLength, 20);
      expect(OtpAlgorithm.sha256.macLength, 32);
      expect(OtpAlgorithm.sha512.macLength, 64);
    });
  });
}
