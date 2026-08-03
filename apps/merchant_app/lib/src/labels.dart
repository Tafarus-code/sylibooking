import 'package:shared_client/shared_client.dart';

import '../l10n/app_localizations.dart';

/// Enum values as words, in the language on screen.
///
/// These live here rather than beside each widget because the same statuses
/// are drawn in several places — a badge on the list, a chip on the detail
/// screen — and two switches drifting apart is how one screen ends up saying
/// "Ready" while the next says "Prête".
extension ReservationStatusLabel on ReservationStatus {
  String label(L l) => switch (this) {
        ReservationStatus.pending => l.statusPending,
        ReservationStatus.confirmed => l.statusConfirmed,
        ReservationStatus.cancelled => l.statusCancelled,
        ReservationStatus.completed => l.statusCompleted,
        ReservationStatus.noShow => l.statusMissed,
        ReservationStatus.unknown => l.statusUnknown,
      };
}

extension OrderStatusLabel on OrderStatus {
  String label(L l) => switch (this) {
        OrderStatus.placed => l.orderPlaced,
        OrderStatus.preparing => l.orderPreparing,
        OrderStatus.ready => l.orderReady,
        OrderStatus.completed => l.orderCollected,
        OrderStatus.cancelled => l.orderCancelled,
        OrderStatus.unknown => l.orderUnknown,
      };

  /// The button that moves a ticket to its next stage.
  String advanceLabel(L l) => switch (this) {
        OrderStatus.placed => l.startPreparing,
        OrderStatus.preparing => l.markReady,
        OrderStatus.ready => l.markCollected,
        _ => l.moveOn,
      };
}

/// Roles are labelled here rather than taken from the server's `role_display`.
///
/// The venue list is fetched once at sign-in and held for the session, so a
/// server-supplied role stays in whatever language that one request was made
/// in — switching to French left "vous y êtes owner" on the Manage screen
/// until the next sign-in. The set is closed and known, so there is nothing
/// to gain by asking.
extension MerchantRoleLabel on MerchantRole {
  /// Lowercase, because it is read inside a sentence rather than on its own.
  String label(L l) => switch (this) {
        MerchantRole.owner => l.roleOwner,
        MerchantRole.manager => l.roleManager,
        MerchantRole.staff => l.roleStaff,
        MerchantRole.unknown => l.statusUnknown,
      };

  /// Standing on its own, next to a venue name or a username.
  String name(L l) => switch (this) {
        MerchantRole.owner => l.roleOwnerName,
        MerchantRole.manager => l.roleManagerName,
        MerchantRole.staff => l.roleStaffName,
        MerchantRole.unknown => l.statusUnknown,
      };
}
