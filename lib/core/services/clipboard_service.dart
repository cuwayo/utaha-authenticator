import 'dart:async';

/// Writes to and clears the system clipboard.
///
/// Abstracted so the auto-clear behaviour can be tested without touching the
/// real clipboard, and so the "is this still our text?" check is explicit.
abstract interface class ClipboardPort {
  /// Copies [text] to the clipboard.
  Future<void> copy(String text);

  /// Returns the clipboard's current contents, or null when unreadable.
  ///
  /// Used to avoid clearing text the user copied from somewhere else in the
  /// meantime — clearing an unrelated clipboard entry would be a surprise, and
  /// on Android 10+ a background app cannot read the clipboard at all, in which
  /// case this returns null.
  Future<String?> currentText();
}

/// A `ClipboardPort` backed by callbacks, for tests.
class FakeClipboard implements ClipboardPort {
  /// Creates a fake clipboard, optionally pre-filled with [initial].
  new({String? initial}) : _text = initial;

  String? _text;

  /// The clipboard's contents.
  String? get text => _text;

  @override
  Future<void> copy(String text) async => _text = text;

  @override
  Future<String?> currentText() async => _text;
}

/// Copies codes to the clipboard and clears them again after a delay.
///
/// The clear is deliberately guarded: if the clipboard no longer holds the text
/// we put there — because the user copied something else, or another code — the
/// timer does nothing. Wiping a password the user copied in the meantime would
/// be worse than leaving a stale OTP behind.
class ClipboardService {
  /// Creates a service over the given `clipboard`.
  new(this._clipboard);

  final ClipboardPort _clipboard;

  Timer? _clearTimer;
  String? _lastCopied;

  /// Copies [text] and schedules a clear after [clearAfterSeconds].
  ///
  /// A [clearAfterSeconds] of zero or less copies without scheduling a clear,
  /// which is what the "Never" setting means.
  ///
  /// Returns true when a clear was scheduled.
  Future<bool> copyWithAutoClear(
    String text, {
    required int clearAfterSeconds,
  }) async {
    // Recorded before the await so the service's own state is consistent the
    // moment this returns a future, and an immediate clear cannot race it.
    _lastCopied = text;

    // A second copy supersedes the first: cancel the pending clear so the new
    // code is not wiped early by the previous timer.
    _clearTimer?.cancel();
    _clearTimer = null;

    if (clearAfterSeconds > 0) {
      _clearTimer = Timer(
        Duration(seconds: clearAfterSeconds),
        _clearIfUnchanged,
      );
    }

    await _clipboard.copy(text);
    return clearAfterSeconds > 0;
  }

  /// Clears the clipboard immediately if it still holds our text.
  ///
  /// Called when the app is backgrounded, so a copied code does not sit on the
  /// clipboard indefinitely while the app is not even on screen.
  Future<void> clearNowIfChanged() => _clearIfUnchanged();

  Future<void> _clearIfUnchanged() async {
    _clearTimer?.cancel();
    _clearTimer = null;

    final expected = _lastCopied;
    if (expected == null) return;

    final current = await _clipboard.currentText();
    if (current == expected) {
      await _clipboard.copy('');
    }
    _lastCopied = null;
  }

  /// Cancels any pending clear. Call from `dispose`.
  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _lastCopied = null;
  }
}
