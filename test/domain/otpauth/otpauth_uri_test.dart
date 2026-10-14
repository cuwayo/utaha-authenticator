import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/otpauth/otpauth_uri.dart';

/// A valid Base32 secret used across these tests.
const String _secret = 'JBSWY3DPEHPK3PXP';

void main() {
  group('OtpAuthUri.parse — valid URIs', () {
    test('parses a minimal TOTP URI', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/ada@example.com?secret=$_secret',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.type, OtpType.totp);
      expect(parsed.accountName, 'ada@example.com');
      expect(parsed.issuer, isNull);
      expect(parsed.algorithm, OtpAlgorithm.sha1);
      expect(parsed.digits, 6);
      expect(parsed.period, 30);
      expect(parsed.counter, isNull);
      expect(parsed.secret, Base32.decode(_secret));
    });

    test('parses a full TOTP URI with every parameter', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/GitHub:ada@example.com'
        '?secret=$_secret&issuer=GitHub&algorithm=SHA512&digits=8&period=60',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'GitHub');
      expect(parsed.accountName, 'ada@example.com');
      expect(parsed.algorithm, OtpAlgorithm.sha512);
      expect(parsed.digits, 8);
      expect(parsed.period, 60);
    });

    test('parses an HOTP URI with a counter', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://hotp/Bank:ada?secret=$_secret&counter=42',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.type, OtpType.hotp);
      expect(parsed.counter, 42);
    });

    test('decodes a percent-encoded label', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/My%20Company%3Aada%40example.com?secret=$_secret',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'My Company');
      expect(parsed.accountName, 'ada@example.com');
    });

    test('accepts a literal colon in the label', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/GitHub:ada?secret=$_secret',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'GitHub');
      expect(parsed.accountName, 'ada');
    });

    test('accepts a lower-case scheme and host', () {
      final parsed = OtpAuthUri.parse('otpauth://TOTP/ada?secret=$_secret');
      addTearDown(() => zero(parsed.secret));

      expect(parsed.type, OtpType.totp);
    });

    test('accepts upper-case parameter names', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/ada?SECRET=$_secret&ISSUER=Acme&DIGITS=7&PERIOD=45'
        '&ALGORITHM=SHA256',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'Acme');
      expect(parsed.digits, 7);
      expect(parsed.period, 45);
      expect(parsed.algorithm, OtpAlgorithm.sha256);
    });

    test('accepts "SHA-1" as well as "SHA1"', () {
      for (final name in <String>['SHA1', 'sha1', 'SHA-1', 'sha-1', 'Sha_1']) {
        final parsed = OtpAuthUri.parse(
          'otpauth://totp/ada?secret=$_secret&algorithm=$name',
        );
        addTearDown(() => zero(parsed.secret));
        expect(parsed.algorithm, OtpAlgorithm.sha1, reason: 'algorithm=$name');
      }
    });

    test(
      'falls back to the label prefix when the issuer parameter is absent',
      () {
        final parsed = OtpAuthUri.parse(
          'otpauth://totp/Acme:ada?secret=$_secret',
        );
        addTearDown(() => zero(parsed.secret));

        expect(parsed.issuer, 'Acme');
        expect(parsed.accountName, 'ada');
      },
    );

    test('prefers the issuer parameter over the label prefix', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/Wrong:ada?secret=$_secret&issuer=Right',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'Right');
      expect(parsed.accountName, 'ada');
    });

    test('tolerates a secret written in groups with separators', () {
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/ada?secret=JBSW%20Y3DP%20EHPK%203PXP',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.secret, Base32.decode(_secret));
    });

    test('uses the issuer as the account name when the label is empty', () {
      // Some issuers emit "otpauth://totp/?secret=..&issuer=Acme".
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/?secret=$_secret&issuer=Acme',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.accountName, 'Acme');
      expect(parsed.issuer, 'Acme');
    });
  });

  group('OtpAuthUri.parse — malformed input', () {
    /// Asserts that [uri] is rejected with a user-facing message.
    void expectRejected(String uri, {String? containing}) {
      expect(
        () => OtpAuthUri.parse(uri),
        throwsA(
          isA<InvalidOtpAuthUriFailure>().having(
            (e) => e.message,
            'message',
            containing == null ? anything : contains(containing),
          ),
        ),
        reason: 'should reject: $uri',
      );
    }

    test('rejects a non-otpauth scheme', () {
      expectRejected(
        'https://example.com/?secret=$_secret',
        containing: 'otpauth',
      );
    });

    test('rejects a missing secret', () {
      expectRejected('otpauth://totp/ada', containing: 'secret key');
    });

    test('rejects an empty secret', () {
      expectRejected('otpauth://totp/ada?secret=', containing: 'secret key');
    });

    test('rejects a secret containing invalid characters', () {
      // '1' is not in the Base32 alphabet; silently dropping it would yield a
      // plausible but wrong secret.
      expectRejected(
        'otpauth://totp/ada?secret=JBSW1YDP',
        containing: 'not valid',
      );
    });

    test('rejects a secret too short to hold a key', () {
      expectRejected('otpauth://totp/ada?secret=A');
    });

    test('rejects an unknown type', () {
      expectRejected(
        'otpauth://steam/ada?secret=$_secret',
        containing: 'does not support',
      );
    });

    test('rejects a missing type', () {
      expectRejected('otpauth:///ada?secret=$_secret');
    });

    test('rejects an unsupported digit count', () {
      expectRejected(
        'otpauth://totp/ada?secret=$_secret&digits=5',
        containing: '6, 7 or 8',
      );
      expectRejected('otpauth://totp/ada?secret=$_secret&digits=9');
    });

    test('rejects a non-numeric digit count', () {
      expectRejected('otpauth://totp/ada?secret=$_secret&digits=lots');
    });

    test('rejects a non-positive period', () {
      expectRejected('otpauth://totp/ada?secret=$_secret&period=0');
      expectRejected('otpauth://totp/ada?secret=$_secret&period=-30');
    });

    test('rejects an unsupported algorithm', () {
      expectRejected(
        'otpauth://totp/ada?secret=$_secret&algorithm=MD5',
        containing: 'unsupported',
      );
    });

    test('rejects an HOTP URI with no counter', () {
      // Defaulting to zero would generate a code the server likely rejects.
      expectRejected(
        'otpauth://hotp/ada?secret=$_secret',
        containing: 'counter',
      );
    });

    test('rejects an HOTP URI with a negative counter', () {
      expectRejected('otpauth://hotp/ada?secret=$_secret&counter=-1');
    });

    test('rejects a URI with no label and no issuer', () {
      expectRejected(
        'otpauth://totp/?secret=$_secret',
        containing: 'account name',
      );
    });

    test('rejects an empty string', () {
      expectRejected('');
    });

    test('rejects a bare word', () {
      expectRejected('hello world');
    });

    test('never leaks the secret in an error message', () {
      // A rejected URI's secret must not appear in the text we show the user or
      // write to a log.
      try {
        OtpAuthUri.parse('otpauth://totp/ada?secret=$_secret&digits=5');
        fail('expected rejection');
      } on InvalidOtpAuthUriFailure catch (error) {
        expect(error.message, isNot(contains(_secret)));
      }
    });
  });

  group('OtpAuthUri.build', () {
    test('round-trips a TOTP account', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      final uri = OtpAuthUri.build(
        secret: secret,
        accountName: 'ada@example.com',
        issuer: 'GitHub',
        algorithm: OtpAlgorithm.sha256,
        digits: 8,
        period: 60,
      );

      final parsed = OtpAuthUri.parse(uri);
      addTearDown(() => zero(parsed.secret));

      expect(parsed.type, OtpType.totp);
      expect(parsed.issuer, 'GitHub');
      expect(parsed.accountName, 'ada@example.com');
      expect(parsed.algorithm, OtpAlgorithm.sha256);
      expect(parsed.digits, 8);
      expect(parsed.period, 60);
      expect(parsed.secret, secret);
    });

    test('round-trips an HOTP account including its counter', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      final uri = OtpAuthUri.build(
        secret: secret,
        accountName: 'ada',
        issuer: 'Bank',
        type: OtpType.hotp,
        counter: 7,
      );

      final parsed = OtpAuthUri.parse(uri);
      addTearDown(() => zero(parsed.secret));

      expect(parsed.type, OtpType.hotp);
      expect(parsed.counter, 7);
    });

    test('omits period for HOTP and counter for TOTP', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      final totpUri = OtpAuthUri.build(secret: secret, accountName: 'a');
      expect(totpUri, contains('period='));
      expect(totpUri, isNot(contains('counter=')));

      final hotpUri = OtpAuthUri.build(
        secret: secret,
        accountName: 'a',
        type: OtpType.hotp,
      );
      expect(hotpUri, contains('counter='));
      expect(hotpUri, isNot(contains('period=')));
    });

    test('works without an issuer', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      final parsed = OtpAuthUri.parse(
        OtpAuthUri.build(secret: secret, accountName: 'ada@example.com'),
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, isNull);
      expect(parsed.accountName, 'ada@example.com');
    });

    test('round-trips an issuer containing a colon', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      final parsed = OtpAuthUri.parse(
        OtpAuthUri.build(
          secret: secret,
          accountName: 'ada',
          issuer: 'Weird:Co',
        ),
      );
      addTearDown(() => zero(parsed.secret));

      // This works because build() emits the issuer as a query parameter as well
      // as a label prefix, and the query parameter is authoritative. The label
      // is still ambiguous on its own (see the test below), so the parameter is
      // what makes an awkward issuer round-trip.
      expect(parsed.issuer, 'Weird:Co');
      expect(parsed.accountName, 'ada');
    });

    test('a colon inside a label part is a documented ambiguity', () {
      // When only the label carries the issuer — no `issuer=` parameter — the
      // label is decoded and then split on its first colon, which is what every
      // mainstream authenticator does. That is what makes the common
      // fully-encoded form "My%20Company%3Aada%40example.com" parse correctly,
      // but it means a colon *inside* the issuer is read as the separator.
      final parsed = OtpAuthUri.parse(
        'otpauth://totp/Weird%3ACo:ada?secret=$_secret',
      );
      addTearDown(() => zero(parsed.secret));

      expect(parsed.issuer, 'Weird');
      expect(parsed.accountName, 'Co:ada');
      // No data is lost; only the boundary between the two fields moves.
      expect('${parsed.issuer}:${parsed.accountName}', 'Weird:Co:ada');
    });

    test(
      'decodes a fully percent-encoded label, as issued by many services',
      () {
        // The important case the decode-then-split rule exists to handle.
        final parsed = OtpAuthUri.parse(
          'otpauth://totp/My%20Company%3Aada%40example.com?secret=$_secret',
        );
        addTearDown(() => zero(parsed.secret));

        expect(parsed.issuer, 'My Company');
        expect(parsed.accountName, 'ada@example.com');
      },
    );

    test('refuses to build a URI without a secret', () {
      expect(
        () => OtpAuthUri.build(secret: Uint8List(0), accountName: 'ada'),
        throwsA(isA<InvalidOtpAuthUriFailure>()),
      );
    });
  });

  group('round-trip stability', () {
    test('parsing a built URI repeatedly is stable', () {
      final secret = Base32.decode(_secret);
      addTearDown(() => zero(secret));

      var uri = OtpAuthUri.build(
        secret: secret,
        accountName: 'ada@example.com',
        issuer: 'GitHub',
      );
      for (var i = 0; i < 5; i++) {
        final parsed = OtpAuthUri.parse(uri);
        final rebuilt = OtpAuthUri.build(
          secret: parsed.secret,
          accountName: parsed.accountName,
          issuer: parsed.issuer,
          type: parsed.type,
          algorithm: parsed.algorithm,
          digits: parsed.digits,
          period: parsed.period,
          counter: parsed.counter,
        );
        zero(parsed.secret);
        expect(rebuilt, uri, reason: 'iteration $i');
        uri = rebuilt;
      }
    });
  });
}
