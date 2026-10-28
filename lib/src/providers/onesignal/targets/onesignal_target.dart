import '../../../core/notification/notification_target.dart';
import '../enums/one_signal_target_kind.dart';

/// Mutually exclusive constructors rule out invalid combinations of targeting
/// modes at compile time. Raw filters are limited to OneSignal's 200 entries.
final class OneSignalTarget implements NotificationTarget {
  OneSignalTarget._(
    this._kind,
    this._payload,
  );

  factory OneSignalTarget.externalIds(
    Iterable<String> ids,
  ) =>
      OneSignalTarget.aliases('external_id', ids);

  factory OneSignalTarget.onesignalIds(
    Iterable<String> ids,
  ) =>
      OneSignalTarget.aliases('onesignal_id', ids);

  factory OneSignalTarget.aliases(
    String aliasKey,
    Iterable<String> ids,
  ) {
    if (aliasKey.trim().isEmpty) throw ArgumentError('aliasKey required');
    return OneSignalTarget._(
      OneSignalTargetKind.aliases,
      {aliasKey: _validateIds(ids)},
    );
  }

  factory OneSignalTarget.subscriptionIds(
    Iterable<String> ids,
  ) =>
      OneSignalTarget._(
        OneSignalTargetKind.subscriptions,
        _validateIds(ids),
      );

  factory OneSignalTarget.segments(
    Iterable<String> included, {
    Iterable<String> excluded = const [],
  }) =>
      OneSignalTarget._(
        OneSignalTargetKind.segments,
        {
          'included_segments': _validateIds(included),
          if (excluded.isNotEmpty) 'excluded_segments': _validateIds(excluded),
        },
      );

  factory OneSignalTarget.filters(
    Iterable<Map<String, Object?>> filters,
  ) {
    final values =
        filters.map((entry) => Map<String, Object?>.of(entry)).toList();
    if (values.isEmpty || values.length > 200) {
      throw ArgumentError('OneSignal filters require 1-200 entries');
    }
    return OneSignalTarget._(
      OneSignalTargetKind.filters,
      List<Map<String, Object?>>.unmodifiable(values),
    );
  }

  final OneSignalTargetKind _kind;
  final Object _payload;

  Map<String, Object?> toJson() => switch (_kind) {
        OneSignalTargetKind.aliases => {
            'include_aliases': _payload,
            'target_channel': 'push',
          },
        OneSignalTargetKind.subscriptions => {
            'include_subscription_ids': _payload
          },
        OneSignalTargetKind.segments => Map<String, Object?>.from(
            _payload as Map<String, Object?>,
          ),
        OneSignalTargetKind.filters => {'filters': _payload},
      };

  static List<String> _validateIds(Iterable<String> input) {
    final ids = input.toSet().toList(growable: false);
    if (ids.isEmpty ||
        ids.length > 20000 ||
        ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Target IDs must contain 1-20,000 nonblank IDs');
    }
    return List.unmodifiable(ids);
  }
}
