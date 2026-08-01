// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sylibooking Merchant';

  @override
  String get merchant => 'Merchant';

  @override
  String get signIn => 'Sign in';

  @override
  String get signOut => 'Sign out';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get keepIt => 'Keep it';

  @override
  String get keep => 'Keep';

  @override
  String get remove => 'Remove';

  @override
  String get add => 'Add';

  @override
  String get edit => 'Edit';

  @override
  String get tryAgain => 'Try again';

  @override
  String get refresh => 'Refresh';

  @override
  String get required => 'Required';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get enterYourUsername => 'Enter your username';

  @override
  String get enterYourPassword => 'Enter your password';

  @override
  String get showPassword => 'Show';

  @override
  String get hidePassword => 'Hide';

  @override
  String get wrongUsernameOrPassword => 'Wrong username or password.';

  @override
  String get navReservations => 'Reservations';

  @override
  String get navPayments => 'Payments';

  @override
  String get navManage => 'Manage';

  @override
  String get tabReservations => 'Réservations';

  @override
  String get tabOrders => 'Commandes';

  @override
  String get switchVenue => 'Switch venue';

  @override
  String get noVenue => 'No venue';

  @override
  String get chooseAVenue => 'Choose a venue';

  @override
  String get keepCurrentVenue => 'Keep current venue';

  @override
  String get everythingAppliesToVenue =>
      'Everything you do next applies to the venue you pick.';

  @override
  String get noVenueYet => 'No venue yet';

  @override
  String get noVenueYetDetail =>
      'This account is not a member of any establishment. An owner can add you to theirs, or an admin can set one up.';

  @override
  String get rangeToday => 'Today';

  @override
  String get rangeNextSevenDays => 'Next 7 days';

  @override
  String get dayToday => 'Today';

  @override
  String get dayTomorrow => 'Tomorrow';

  @override
  String get couldNotLoadReservations => 'Could not load reservations';

  @override
  String get noVenueAssigned => 'No venue assigned';

  @override
  String get noVenueAssignedDetail =>
      'This account is not staff at any establishment yet, so there is nothing to show. An admin can assign one in the Django admin.';

  @override
  String get nothingBookedToday => 'Nothing booked today';

  @override
  String get nothingBookedThisWeek => 'Nothing booked this week';

  @override
  String get newReservationsAppearHere =>
      'New reservations appear here as customers make them.';

  @override
  String get cancelThisReservation => 'Cancel this reservation?';

  @override
  String cancelReservationDetail(String name, String space, String time) {
    return '$name · $space at $time.\n\nThe slot becomes bookable again.';
  }

  @override
  String get cancelBooking => 'Cancel booking';

  @override
  String get reservationCancelled => 'Reservation cancelled.';

  @override
  String get reservationConfirmed => 'Reservation confirmed.';

  @override
  String get confirm => 'Confirm';

  @override
  String guestCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count guests',
      one: '1 guest',
    );
    return '$_temp0';
  }

  @override
  String get cannotConfirmUntilPaymentClears =>
      'Cannot confirm until the payment clears.';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusUnknown => 'Unknown';

  @override
  String paidWith(String provider) {
    return 'Paid ($provider)';
  }

  @override
  String get mobileMoney => 'mobile money';

  @override
  String paymentFailedWith(String provider) {
    return 'Payment failed ($provider)';
  }

  @override
  String awaitingPaymentWith(String provider) {
    return 'Awaiting payment ($provider)';
  }

  @override
  String get paymentFailedShort => 'Payment failed';

  @override
  String get unpaid => 'Unpaid';

  @override
  String get cashOnArrival => 'Cash on arrival';

  @override
  String get cashShort => 'Cash';

  @override
  String get stageReadyToCollect => 'Ready to collect';

  @override
  String get stageBeingPrepared => 'Being prepared';

  @override
  String get stageNewOrders => 'New orders';

  @override
  String stageHeading(String label, int count) {
    return '$label · $count';
  }

  @override
  String get couldNotLoadTheQueue => 'Could not load the queue';

  @override
  String get noVenueSelected => 'No venue selected';

  @override
  String get pickAVenueForQueue => 'Pick a venue to see its kitchen queue.';

  @override
  String get nothingInTheQueue => 'Nothing in the queue';

  @override
  String get ordersLandHere =>
      'Orders placed for today land here as they come in.';

  @override
  String get cancelThisOrder => 'Cancel this order?';

  @override
  String cancelOrderDetail(String name) {
    return '$name will not be able to collect it, and nothing will be owed.';
  }

  @override
  String get cancelOrder => 'Cancel order';

  @override
  String get startPreparing => 'Start preparing';

  @override
  String get markReady => 'Mark ready';

  @override
  String get markCollected => 'Collected';

  @override
  String get moveOn => 'Move on';

  @override
  String get atTheirTable => 'At their table';

  @override
  String get orderPlaced => 'Placed';

  @override
  String get orderPreparing => 'Preparing';

  @override
  String get orderReady => 'Ready';

  @override
  String get orderCollected => 'Collected';

  @override
  String get orderCancelled => 'Cancelled';

  @override
  String get orderUnknown => 'Unknown';

  @override
  String waitingOnPayment(String provider) {
    return 'Waiting on the $provider payment. The kitchen cannot start until it clears.';
  }

  @override
  String get cashOnPickup => 'Cash on pickup';

  @override
  String amountGnf(String amount) {
    return '$amount GNF';
  }

  @override
  String get reservationTitle => 'Reservation';

  @override
  String get sectionBooking => 'Booking';

  @override
  String get rowWhen => 'When';

  @override
  String get rowSpace => 'Space';

  @override
  String get rowParty => 'Party';

  @override
  String get rowPhone => 'Phone';

  @override
  String get rowReference => 'Reference';

  @override
  String get sectionPayment => 'Payment';

  @override
  String get rowMethod => 'Method';

  @override
  String get rowTaken => 'Taken';

  @override
  String get nothingYetSettledAtVenue => 'Nothing yet — settled at the venue';

  @override
  String get rowAmount => 'Amount';

  @override
  String get rowStatus => 'Status';

  @override
  String get rowProviderReference => 'Provider reference';

  @override
  String copyField(String label) {
    return 'Copy $label';
  }

  @override
  String fieldCopied(String label) {
    return '$label copied';
  }

  @override
  String get cannotConfirmUntilPaymentClearsLong =>
      'This booking cannot be confirmed until the payment clears. Cancel it if the customer does not pay.';

  @override
  String youAreRoleHere(String city, String role) {
    return '$city · you are $role here';
  }

  @override
  String get menu => 'Menu';

  @override
  String get menuSubtitleEdit => 'Items, prices, and what is sold out';

  @override
  String get menuSubtitleStaff => 'Mark items sold out';

  @override
  String get photos => 'Photos';

  @override
  String get photosSubtitle => 'What customers see of the room';

  @override
  String get photosSubtitleViewOnly =>
      'What customers see of the room (view only)';

  @override
  String get openingHours => 'Opening hours';

  @override
  String get openingHoursSubtitle =>
      'When the doors are open, including past midnight';

  @override
  String get venueDetails => 'Venue details';

  @override
  String get venueDetailsSubtitle => 'Name, tagline, description, address';

  @override
  String get branding => 'Branding';

  @override
  String get brandingSubtitle => 'How your venue looks to customers';

  @override
  String get whoHasAccess => 'Who has access';

  @override
  String get whoHasAccessSubtitle => 'Add people, change roles, remove access';

  @override
  String get managedByOwnerOrManager =>
      'Opening hours, venue details and access are managed by an owner or manager.';

  @override
  String get monday => 'Monday';

  @override
  String get tuesday => 'Tuesday';

  @override
  String get wednesday => 'Wednesday';

  @override
  String get thursday => 'Thursday';

  @override
  String get friday => 'Friday';

  @override
  String get saturday => 'Saturday';

  @override
  String get sunday => 'Sunday';

  @override
  String get onlyOwnerOrManagerCanChangeHours =>
      'Only an owner or manager can change opening hours.';

  @override
  String get saveWeek => 'Save week';

  @override
  String get hoursSaved => 'Hours saved.';

  @override
  String dayOpenButNoTimes(String day) {
    return '$day is open but has no times set.';
  }

  @override
  String get closed => 'Closed';

  @override
  String get open => 'Open';

  @override
  String get opens => 'Opens';

  @override
  String opensAt(String time) {
    return 'Opens $time';
  }

  @override
  String get closes => 'Closes';

  @override
  String closesAt(String time) {
    return 'Closes $time';
  }

  @override
  String get runsPastMidnight => 'Runs past midnight into the next morning.';

  @override
  String get takeAPhoto => 'Take a photo';

  @override
  String get addPhoto => 'Add photo';

  @override
  String get addACaption => 'Add a caption';

  @override
  String get captionHint => 'Optional, e.g. \"The terrace at night\"';

  @override
  String get upload => 'Upload';

  @override
  String get photoAdded => 'Photo added.';

  @override
  String get noPhotosYet => 'No photos yet';

  @override
  String get noPhotosDetailCanUpload =>
      'Customers browse with their eyes. A few good photos of the room go a long way.';

  @override
  String get noPhotosDetailViewOnly => 'An owner or manager adds photos here.';

  @override
  String get yourVenue => 'Your venue';

  @override
  String brandingIntro(String venue) {
    return 'Choose how $venue looks to customers. Each set has been checked for readability.';
  }

  @override
  String get preview => 'Preview';

  @override
  String get saveBranding => 'Save branding';

  @override
  String get savedLabel => 'Saved';

  @override
  String get brandingSaved => 'Branding saved.';

  @override
  String get previewOpenUntil => 'Open until 02:00';

  @override
  String get previewVenueLine => 'Lounge · Conakry · 1.2 km away';

  @override
  String get previewReserve => 'Reserve';

  @override
  String get addItem => 'Add item';

  @override
  String get noMenuYet => 'No menu yet';

  @override
  String get noMenuDetailCanEdit =>
      'Add your first item and customers will see it straight away.';

  @override
  String get noMenuDetailStaff => 'A manager or owner adds items here.';

  @override
  String get staffCanMarkSoldOut =>
      'You can mark items sold out. Adding and editing is done by a manager or owner.';

  @override
  String get soldOut => 'Sold out';

  @override
  String itemBackOn(String name) {
    return '$name is back on.';
  }

  @override
  String itemMarkedSoldOut(String name) {
    return '$name marked sold out.';
  }

  @override
  String pictureAddedTo(String name) {
    return 'Picture added to $name.';
  }

  @override
  String removeItemTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get removeItemDetail =>
      'It disappears from the customer menu. To hide it temporarily, mark it sold out instead.';

  @override
  String itemRemoved(String name) {
    return '$name removed.';
  }

  @override
  String get addAPicture => 'Add a picture';

  @override
  String get replacePicture => 'Replace picture';

  @override
  String get addAnItem => 'Add an item';

  @override
  String get editItem => 'Edit item';

  @override
  String get fieldName => 'Name';

  @override
  String get giveItAName => 'Give it a name';

  @override
  String get fieldCategory => 'Category';

  @override
  String get categoryFood => 'Food';

  @override
  String get categoryDrink => 'Drink';

  @override
  String get categoryChicha => 'Chicha flavour';

  @override
  String get fieldPriceGnf => 'Price (GNF)';

  @override
  String get giveItAPrice => 'Give it a price';

  @override
  String get numbersOnly => 'Numbers only';

  @override
  String get fieldOneLineDescription => 'One-line description (optional)';

  @override
  String get addSomeone => 'Add someone';

  @override
  String get fieldRole => 'Role';

  @override
  String get roleStaffOption => 'Staff — floor work';

  @override
  String get roleManagerOption => 'Manager — venue and profile';

  @override
  String get roleOwnerOption => 'Owner — everything';

  @override
  String get roleOwner => 'owner';

  @override
  String get roleManager => 'manager';

  @override
  String get roleStaff => 'staff';

  @override
  String get roleOwnerName => 'Owner';

  @override
  String get roleManagerName => 'Manager';

  @override
  String get roleStaffName => 'Staff';

  @override
  String personAdded(String name) {
    return '$name added.';
  }

  @override
  String personIsNowRole(String name, String role) {
    return '$name is now $role.';
  }

  @override
  String removePersonTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get removePersonDetail =>
      'They lose access to this venue immediately.';

  @override
  String personRemoved(String name) {
    return '$name removed.';
  }

  @override
  String get makeOwner => 'Make owner';

  @override
  String get makeManager => 'Make manager';

  @override
  String get makeStaff => 'Make staff';

  @override
  String get removeAccess => 'Remove access';

  @override
  String get window7Days => '7 days';

  @override
  String get window30Days => '30 days';

  @override
  String get window90Days => '90 days';

  @override
  String dateRange(String from, String to) {
    return '$from – $to';
  }

  @override
  String get collected => 'Collected';

  @override
  String paymentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '1 payment',
    );
    return '$_temp0';
  }

  @override
  String get awaiting => 'Awaiting';

  @override
  String pendingCount(int count) {
    return '$count pending';
  }

  @override
  String get failed => 'Failed';

  @override
  String failedCount(int count) {
    return '$count failed';
  }

  @override
  String get sectionBookings => 'Bookings';

  @override
  String get countTotal => 'Total';

  @override
  String get sectionByPaymentMethod => 'By payment method';

  @override
  String bookingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookings',
      one: '1 booking',
    );
    return '$_temp0';
  }

  @override
  String get atTheTill => 'at the till';

  @override
  String get sectionNeedsChasing => 'Needs chasing';

  @override
  String get nothingOutstanding =>
      'Nothing outstanding. Every booking is settled.';

  @override
  String providerPaymentFailed(String provider) {
    return '$provider payment failed';
  }

  @override
  String providerNotReceived(String provider) {
    return '$provider not received';
  }

  @override
  String get fieldTagline => 'Tagline (one line)';

  @override
  String get fieldDescription => 'Description';

  @override
  String get fieldCity => 'City';

  @override
  String get fieldAddress => 'Address';

  @override
  String get detailsSaved => 'Details saved.';
}
