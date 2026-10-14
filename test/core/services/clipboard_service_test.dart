import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utaha_authenticator/core/services/clipboard_service.dart';

void main() {
  late FakeClipboard clipboard;
  late ClipboardService service;

  setUp(() {
    clipboard = FakeClipboard();
    service = ClipboardService(clipboard);
  });

  tearDown(() => service.dispose());

  group('copyWithAutoClear', () {
    test('copies the text immediately', () async {
      await service.copyWithAutoClear('123456', clearAfterSeconds: 30);
      expect(clipboard.text, '123456');
    });

    test('reports that a clear was scheduled', () async {
      final scheduled = await service.copyWithAutoClear(
        '123456',
        clearAfterSeconds: 30,
      );
      expect(scheduled, isTrue);
    });

    test('does not schedule a clear when the delay is zero', () async {
      // The "Never" setting: the code stays until the user copies something else.
      final scheduled = await service.copyWithAutoClear(
        '123456',
        clearAfterSeconds: 0,
      );
      expect(scheduled, isFalse);
      expect(clipboard.text, '123456');
    });

    test('treats a negative delay as no clear', () async {
      final scheduled = await service.copyWithAutoClear(
        '123456',
        clearAfterSeconds: -5,
      );
      expect(scheduled, isFalse);
    });

    test('clears the clipboard once the delay elapses', () {
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('123456', clearAfterSeconds: 30));
        async.elapse(const Duration(seconds: 29));
        expect(clipboard.text, '123456', reason: 'still within the window');
        async.elapse(const Duration(seconds: 2));
        expect(clipboard.text, '');
      });
    });

    test("a second copy cancels the first copy's pending clear", () {
      // Otherwise the first timer would wipe the newer code early.
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('111111', clearAfterSeconds: 30));
        async.elapse(const Duration(seconds: 20));
        unawaited(service.copyWithAutoClear('222222', clearAfterSeconds: 30));

        // The original timer would have fired at t=30; the new code must survive.
        async.elapse(const Duration(seconds: 11));
        expect(clipboard.text, '222222');

        // The new timer fires 30s after the second copy.
        async.elapse(const Duration(seconds: 20));
        expect(clipboard.text, '');
      });
    });

    test('does NOT clear text the user copied in the meantime', () {
      // Wiping a password the user copied from another app would be worse than
      // leaving a stale one-time code behind.
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('123456', clearAfterSeconds: 30));
        async.elapse(const Duration(seconds: 10));

        // The user copies something else.
        unawaited(clipboard.copy('a-password-from-elsewhere'));
        async.elapse(const Duration(seconds: 30));

        expect(clipboard.text, 'a-password-from-elsewhere');
      });
    });

    test('clears an empty clipboard without error', () {
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('123456', clearAfterSeconds: 5));
        unawaited(clipboard.copy(''));
        async.elapse(const Duration(seconds: 6));
        expect(clipboard.text, '');
      });
    });
  });

  group('clearNowIfChanged', () {
    test('clears our text immediately', () async {
      await service.copyWithAutoClear('123456', clearAfterSeconds: 30);
      await service.clearNowIfChanged();
      expect(clipboard.text, '');
    });

    test('leaves other text alone', () async {
      await service.copyWithAutoClear('123456', clearAfterSeconds: 30);
      await clipboard.copy('something else');
      await service.clearNowIfChanged();
      expect(clipboard.text, 'something else');
    });

    test('is a no-op when nothing was ever copied', () async {
      await clipboard.copy('pre-existing');
      await service.clearNowIfChanged();
      expect(clipboard.text, 'pre-existing');
    });

    test('cancels a pending clear so it cannot fire later', () {
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('123456', clearAfterSeconds: 30));
        unawaited(service.clearNowIfChanged());
        async.flushMicrotasks();
        expect(clipboard.text, '');

        // Copy something new; the old timer must not still be armed.
        unawaited(clipboard.copy('later text'));
        async.elapse(const Duration(seconds: 60));
        expect(clipboard.text, 'later text');
      });
    });
  });

  group('dispose', () {
    test('cancels a pending clear', () {
      fakeAsync((async) {
        unawaited(service.copyWithAutoClear('123456', clearAfterSeconds: 30));
        service.dispose();
        unawaited(clipboard.copy('after dispose'));
        async.elapse(const Duration(seconds: 60));
        expect(clipboard.text, 'after dispose');
      });
    });
  });
}
