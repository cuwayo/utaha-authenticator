import 'package:meta/meta.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';

/// An account that generates one-time passwords.
///
/// **This model deliberately does not carry the secret key.** The secret lives
/// only in the platform keystore, addressed by [id], and is fetched on demand
/// and wiped afterwards. Keeping it out of the model means a whole class of
/// accidents cannot happen: the account cannot be serialised to JSON, written to
/// a log, or captured in a crash report with its secret attached.
///
/// Annotated [immutable] because value equality is defined on it, and the
/// `tags` list is defensively copied into an unmodifiable view.
@immutable
class Account {
  /// Creates an account.
  ///
  /// Not a `const` constructor because [tags] is defensively copied into an
  /// unmodifiable list: an `@immutable` class holding a caller-owned mutable
  /// list would be able to change under its own `hashCode`.
  new({
    required this.id,
    required this.accountName,
    this.issuer,
    this.type = OtpType.totp,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
    List<String> tags = const <String>[],
    this.pinned = false,
    this.sortOrder = 0,
    this.createdAt,
  }) : tags = List<String>.unmodifiable(tags);

  /// Stable local identifier, and the key the secret is stored under.
  final String id;

  /// The user's name for this account, e.g. `ada@example.com`.
  final String accountName;

  /// The service the account belongs to, e.g. `GitHub`. Optional because some
  /// services issue secrets without one.
  final String? issuer;

  /// Whether codes are time-based or counter-based.
  final OtpType type;

  /// HMAC hash function.
  final OtpAlgorithm algorithm;

  /// Number of digits in a generated code (6, 7 or 8).
  final int digits;

  /// TOTP time step in seconds. Ignored for HOTP.
  final int period;

  /// HOTP counter. Ignored for TOTP.
  ///
  /// Only ever advanced by an explicit "generate next code" action, because
  /// advancing it wrongly desynchronises the account from the server.
  final int counter;

  /// Optional user-assigned labels used for grouping and filtering.
  final List<String> tags;

  /// Whether the account is pinned to the top of the list.
  final bool pinned;

  /// Position in the user's manual ordering.
  final int sortOrder;

  /// When the account was added. Null for accounts created before this field
  /// existed.
  final DateTime? createdAt;

  /// The primary line shown in the account list: the issuer when there is one,
  /// otherwise the account name.
  String get displayTitle =>
      (issuer != null && issuer!.isNotEmpty) ? issuer! : accountName;

  /// The secondary line shown under [displayTitle].
  ///
  /// When there is no issuer the title already shows the account name, so this
  /// returns an empty string rather than repeating it.
  String get displaySubtitle =>
      (issuer != null && issuer!.isNotEmpty) ? accountName : '';

  /// A single string combining issuer and account name, for search matching.
  String get searchHaystack => '${issuer ?? ''} $accountName'.toLowerCase();

  /// Returns a copy with the given fields replaced.
  ///
  /// [issuer] cannot be set to null through this method — pass an empty string
  /// to clear it. That avoids the usual `copyWith` trap where an explicit null
  /// is indistinguishable from an omitted argument.
  Account copyWith({
    String? id,
    String? accountName,
    String? issuer,
    OtpType? type,
    OtpAlgorithm? algorithm,
    int? digits,
    int? period,
    int? counter,
    List<String>? tags,
    bool? pinned,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      accountName: accountName ?? this.accountName,
      issuer: issuer ?? this.issuer,
      type: type ?? this.type,
      algorithm: algorithm ?? this.algorithm,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      counter: counter ?? this.counter,
      tags: tags ?? this.tags,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account &&
        other.id == id &&
        other.accountName == accountName &&
        other.issuer == issuer &&
        other.type == type &&
        other.algorithm == algorithm &&
        other.digits == digits &&
        other.period == period &&
        other.counter == counter &&
        other.pinned == pinned &&
        other.sortOrder == sortOrder &&
        other.createdAt == createdAt &&
        _sameTags(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountName,
    issuer,
    type,
    algorithm,
    digits,
    period,
    counter,
    pinned,
    sortOrder,
    createdAt,
    Object.hashAll(tags),
  );

  /// Never includes the secret, which this model does not hold.
  @override
  String toString() =>
      'Account(id: $id, issuer: $issuer, accountName: $accountName, '
      'type: ${type.name}, algorithm: ${algorithm.name}, digits: $digits)';

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
