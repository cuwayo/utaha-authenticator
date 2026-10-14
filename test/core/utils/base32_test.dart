import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';

void main() {
  group('Base32.decode', () {
    test('decodes the RFC 4648 example vectors', () {
      // The canonical vectors from RFC 4648 section 10. Padding is stripped by
      // the codec, so only the significant characters are supplied here.
      const vectors = <String, String>{
        'MY': 'f',
        'MZXQ': 'fo',
        'MZXW6': 'foo',
        'MZXW6YQ': 'foob',
        'MZXW6YTB': 'fooba',
        'MZXW6YTBOI': 'foobar',
      };

      for (final entry in vectors.entries) {
        final decoded = Base32.decode(entry.key);
        expect(
          utf8.decode(decoded),
          entry.value,
          reason: 'decoding ${entry.key}',
        );
      }
    });

    test('ignores case, spaces, hyphens and padding', () {
      final canonical = Base32.decode('MZXW6YTBOI');
      for (final variant in <String>[
        'mzxw6ytboi',
        'MZXW 6YTB OI',
        'MZXW-6YTB-OI',
        'MZXW6YTBOI=====',
        'mzxw 6ytb oi',
      ]) {
        expect(
          Base32.decode(variant),
          canonical,
          reason: 'variant "$variant" should match the canonical decoding',
        );
      }
    });

    test('produces the byte values from the RFC 4648 vector', () {
      // "foobar" is 0x66 0x6F 0x6F 0x62 0x61 0x72.
      expect(Base32.decode('MZXW6YTBOI'), <int>[
        0x66,
        0x6F,
        0x6F,
        0x62,
        0x61,
        0x72,
      ]);
    });

    test('decodes a typical 20-byte authenticator secret', () {
      // The classic "JBSWY3DPEHPK3PXP" secret used throughout TOTP examples.
      final decoded = Base32.decode('JBSWY3DPEHPK3PXP');
      expect(decoded, hasLength(10));
      expect(decoded, <int>[
        0x48,
        0x65,
        0x6C,
        0x6C,
        0x6F,
        0x21,
        0xDE,
        0xAD,
        0xBE,
        0xEF,
      ]);
    });

    test('rejects characters outside the alphabet, naming the position', () {
      // '1' and '0' are the classic confusions with 'I' and 'O'; they are not
      // in the alphabet and must not be silently dropped.
      expect(
        () => Base32.decode('MZXW1YTB'),
        throwsA(
          isA<Base32FormatException>()
              .having((e) => e.index, 'index', 4)
              .having((e) => e.message, 'message', contains('1')),
        ),
      );
    });

    test('rejects an empty secret', () {
      expect(() => Base32.decode('   '), throwsA(isA<Base32FormatException>()));
    });

    test('rejects a secret too short to hold any byte', () {
      expect(
        () => Base32.decode('A'),
        throwsA(
          isA<Base32FormatException>().having(
            (e) => e.message,
            'message',
            contains('too short'),
          ),
        ),
      );
    });

    test('error messages avoid technical jargon', () {
      // The brief requires calm, jargon-free copy; these strings are shown
      // directly to the user.
      for (final input in <String>['!!!!', 'A']) {
        try {
          Base32.decode(input);
          fail('expected $input to be rejected');
        } on Base32FormatException catch (error) {
          expect(error.message, isNot(contains('base32')));
          expect(error.message.toLowerCase(), isNot(contains('rfc')));
          expect(error.message.toLowerCase(), isNot(contains('padding')));
        }
      }
    });
  });

  group('Base32.encode', () {
    test('round-trips the RFC 4648 vectors', () {
      const encoded = <String>[
        'MY',
        'MZXQ',
        'MZXW6',
        'MZXW6YQ',
        'MZXW6YTB',
        'MZXW6YTBOI',
      ];
      for (final value in <String>[
        'f',
        'fo',
        'foo',
        'foob',
        'fooba',
        'foobar',
      ]) {
        // Encoding then decoding must return the original bytes...
        expect(
          utf8.decode(Base32.decode(Base32.encode(utf8.encode(value)))),
          value,
        );
      }
      // ...and each expected encoding must match the RFC exactly.
      for (var i = 0; i < encoded.length; i++) {
        final plain = <String>['f', 'fo', 'foo', 'foob', 'fooba', 'foobar'][i];
        expect(Base32.encode(utf8.encode(plain)), encoded[i]);
      }
    });

    test('encodes the RFC 4648 vector without padding', () {
      expect(Base32.encode(utf8.encode('foobar')), 'MZXW6YTBOI');
    });

    test('returns an empty string for empty input', () {
      expect(Base32.encode(<int>[]), '');
    });

    test('round-trips arbitrary bytes', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 7) % 256),
      );
      expect(Base32.decode(Base32.encode(bytes)), bytes);
    });
  });

  group('Base32.normalize', () {
    test('uppercases and strips separators', () {
      expect(Base32.normalize('jbsw y3dp-ehpk_3pxp'), 'JBSWY3DPEHPK3PXP');
    });
  });

  group('Base32.isValid', () {
    test('is true for a well-formed secret', () {
      expect(Base32.isValid('JBSWY3DPEHPK3PXP'), isTrue);
    });

    test('is false for malformed input', () {
      for (final input in <String>['', '   ', 'JBSW1YDP', 'JBSW0YDP', 'A']) {
        expect(Base32.isValid(input), isFalse, reason: 'input "$input"');
      }
    });
  });
}
