// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sylibooking';

  @override
  String get navBrowse => 'Browse';

  @override
  String get navBookings => 'Bookings';

  @override
  String get navFavourites => 'Favourites';

  @override
  String get navProfile => 'Profile';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String greetingWithName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get findATable => 'Find a table';

  @override
  String get searchByName => 'Search by name';

  @override
  String get filterAll => 'All';

  @override
  String get filterRestaurants => 'Restaurants';

  @override
  String get filterLounges => 'Lounges';

  @override
  String get filterOpenNow => 'Open now';

  @override
  String get filterNearest => 'Nearest';

  @override
  String get filterShowDistances => 'Show distances';

  @override
  String statusOpenUntil(String time) {
    return 'Open until $time';
  }

  @override
  String get statusClosed => 'Closed';

  @override
  String get statusHoursNotListed => 'Hours not listed';

  @override
  String typeAndCity(String type, String city) {
    return '$type · $city';
  }

  @override
  String get couldNotLoadPlaces => 'Could not load places';

  @override
  String get tryAgain => 'Try again';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get nothingFoundDetail =>
      'Try a different name, or clear the filters.';

  @override
  String get nothingOpenRightNow =>
      'Nothing is open right now. Turn off \"Open now\" to see places you can book for later.';

  @override
  String get showDistancesTitle => 'Show distances?';

  @override
  String get showDistancesBody =>
      'Sylibooking can show how far each place is and sort by what is nearest. Your location stays on your phone — it is never sent to us or to the venues.';

  @override
  String get notNow => 'Not now';

  @override
  String get allow => 'Allow';

  @override
  String get locationDenied =>
      'No problem — browsing works without it. You can allow location later in your phone settings.';

  @override
  String get locationServicesOff =>
      'Location is switched off on this phone. Turn it on to see distances.';

  @override
  String get locationUnavailable =>
      'Could not get a location just now. Distances are unavailable.';

  @override
  String get getDirections => 'Get directions';

  @override
  String get noMapsApp => 'No maps app found on this phone.';

  @override
  String get saveToFavourites => 'Save to favourites';

  @override
  String get removeFromFavourites => 'Remove from favourites';

  @override
  String get allWeek => 'All week';

  @override
  String get hideWeek => 'Hide week';

  @override
  String get closedToday => 'Closed today';

  @override
  String seeAllReviews(int count) {
    return 'See all $count';
  }

  @override
  String get noReviewsAfterVisit =>
      'No reviews yet — be the first after your visit.';

  @override
  String get lastSpaceFree => 'Last space free at this time';

  @override
  String spacesFree(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spaces free',
      one: '1 space free',
    );
    return '$_temp0';
  }

  @override
  String get menu => 'Menu';

  @override
  String get orderAhead => 'Order ahead';

  @override
  String get reviews => 'Reviews';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews',
      one: '1 review',
      zero: 'No reviews yet',
    );
    return '$_temp0';
  }

  @override
  String get beTheFirstToReview => 'Be the first to leave a review.';

  @override
  String get writeAReview => 'Write a review';

  @override
  String get partySize => 'Party size';

  @override
  String get day => 'Day';

  @override
  String get availableTimes => 'Available times';

  @override
  String nothingFreeForParty(int count) {
    return 'Nothing free for $count on this day';
  }

  @override
  String get tryAnotherDay => 'Try another day, or a smaller party.';

  @override
  String get today => 'Today';

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get bookATable => 'Book a table';

  @override
  String get yourName => 'Your name';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get nameRequired => 'The venue needs a name for the booking.';

  @override
  String get phoneRequired => 'A number to reach you on.';

  @override
  String get phoneTooShort => 'That number looks too short.';

  @override
  String get payment => 'Payment';

  @override
  String get cashOnArrival => 'Cash on arrival';

  @override
  String get cashOnArrivalDetail => 'Pay at the venue';

  @override
  String get orangeMoney => 'Orange Money';

  @override
  String get mtnMoney => 'MTN Mobile Money';

  @override
  String get payNowDetail => 'The table is held once the payment clears';

  @override
  String get confirmBooking => 'Confirm booking';

  @override
  String get payAndBook => 'Pay and book';

  @override
  String get booking => 'Booking…';

  @override
  String get bookingConfirmedTitle => 'Table confirmed';

  @override
  String get bookingRequestedTitle => 'Booking requested';

  @override
  String get paymentFailedNothingCharged =>
      'The payment did not go through, so nothing was charged. Your booking is still requested — you can pay at the venue.';

  @override
  String get waitingForPayment => 'Waiting for your payment to clear.';

  @override
  String get backToBrowsing => 'Back to browsing';

  @override
  String get myBookings => 'My bookings';

  @override
  String get tabBookings => 'Bookings';

  @override
  String get tabOrders => 'Orders';

  @override
  String get noBookingsYet => 'No bookings yet';

  @override
  String get noBookingsDetail => 'Book a table and it will show up here.';

  @override
  String get cancelBooking => 'Cancel booking';

  @override
  String get cancelBookingTitle => 'Cancel this booking?';

  @override
  String get cancelBookingBody =>
      'The venue will free the table for someone else.';

  @override
  String get keepIt => 'Keep it';

  @override
  String get sharePhoto => 'Share a photo';

  @override
  String get reviewYourVisit => 'Review your visit';

  @override
  String get noOrdersYet => 'No orders yet';

  @override
  String get noOrdersDetail =>
      'Order ahead from a restaurant and it will show up here, with its progress while the kitchen works on it.';

  @override
  String get couldNotLoadOrders => 'Could not load your orders';

  @override
  String sectionActive(int count) {
    return 'Active · $count';
  }

  @override
  String sectionPast(int count) {
    return 'Past · $count';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get orderPlaced => 'Placed';

  @override
  String get orderPreparing => 'Being prepared';

  @override
  String get orderReady => 'Ready to collect';

  @override
  String get orderCollected => 'Collected';

  @override
  String get orderCancelled => 'Cancelled';

  @override
  String get orderWaitingPayment => 'Waiting on payment';

  @override
  String get couldNotLoadMenu => 'Could not load the menu';

  @override
  String get nothingToOrderYet => 'Nothing to order yet';

  @override
  String get nothingToOrderDetail =>
      'This restaurant has not put its menu online. You can still book a table and order at it.';

  @override
  String get add => 'Add';

  @override
  String addNamed(String name) {
    return 'Add $name';
  }

  @override
  String oneFewer(String name) {
    return 'One fewer $name';
  }

  @override
  String oneMore(String name) {
    return 'One more $name';
  }

  @override
  String tapToReview(String count) {
    return '$count · tap to review';
  }

  @override
  String get checkout => 'Checkout';

  @override
  String get yourBasket => 'Your basket';

  @override
  String get total => 'Total';

  @override
  String priceWithCurrency(String amount) {
    return '$amount GNF';
  }

  @override
  String dishCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dishes',
      one: '1 dish',
    );
    return '$_temp0 · collect at the counter';
  }

  @override
  String get timedToYourBooking => 'Timed to your table booking';

  @override
  String get counterNeedsName => 'The counter needs a name to call out.';

  @override
  String get collectionTime => 'Collection time';

  @override
  String get cashOnPickup => 'Cash on pickup';

  @override
  String get cashOnPickupDetail => 'Pay at the counter when you collect';

  @override
  String get kitchenStartsWhenPaid =>
      'The kitchen starts once the payment clears';

  @override
  String get placeOrder => 'Place order';

  @override
  String get payAndOrder => 'Pay and order';

  @override
  String get placing => 'Placing…';

  @override
  String get yourOrder => 'Your order';

  @override
  String collectAt(String when) {
    return 'Collect at $when';
  }

  @override
  String get progressPlaced => 'Placed';

  @override
  String get progressPreparing => 'Preparing';

  @override
  String get progressReady => 'Ready';

  @override
  String get progressPlacedDetail => 'The restaurant has your order';

  @override
  String get progressPreparingDetail => 'It is being cooked';

  @override
  String get progressReadyDetail => 'Collect it at the counter';

  @override
  String get progressCollectedDetail => 'Collected. Enjoy it.';

  @override
  String get progressCancelledDetail => 'This order was cancelled';

  @override
  String get whatYouOrdered => 'What you ordered';

  @override
  String waitingOnPaymentDetail(String provider) {
    return 'Waiting for your $provider payment. The kitchen starts once it clears.';
  }

  @override
  String get orderCancelledNothingOwed =>
      'This order was cancelled. Nothing is owed.';

  @override
  String get favourites => 'Favourites';

  @override
  String get nothingSavedYet => 'Nothing saved yet';

  @override
  String get nothingSavedDetail =>
      'Tap the heart on a place you like and it will wait for you here.';

  @override
  String get savedOnThisPhone =>
      'Saved on this phone. Make an account from Profile and they follow you to the next one.';

  @override
  String get couldNotLoadFavourites => 'Could not load your favourites';

  @override
  String get profile => 'Profile';

  @override
  String get makeAnAccount => 'Make an account';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get accountIsOptional =>
      'You do not need one. Everything works without it — an account just keeps your bookings and favourites if you change phone.';

  @override
  String get whatShouldWeCallYou => 'What should we call you?';

  @override
  String get username => 'Username';

  @override
  String get pickAUsername => 'Pick a username.';

  @override
  String get password => 'Password';

  @override
  String get enterAPassword => 'Enter a password.';

  @override
  String get atLeast8Characters => 'At least 8 characters.';

  @override
  String get phoneHelper => 'So you can get back in if you forget the password';

  @override
  String get emailOptional => 'Email (optional)';

  @override
  String get emailLooksWrong => 'That email looks wrong.';

  @override
  String get createAccount => 'Create account';

  @override
  String get signIn => 'Sign in';

  @override
  String get justAMoment => 'Just a moment…';

  @override
  String get iAlreadyHaveAnAccount => 'I already have an account';

  @override
  String get iNeedAnAccount => 'I need an account';

  @override
  String get iForgotMyPassword => 'I have forgotten my password';

  @override
  String get signedInEverythingSaved =>
      'Signed in. Everything on this phone is saved.';

  @override
  String get accountKeepsEverything =>
      'Your bookings, orders and favourites are saved to this account. Sign in on another phone and they follow you.';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutKeepsPhone =>
      'Signing out leaves this phone with what it had before — nothing is deleted.';

  @override
  String get noWayBackIn =>
      'This account has no phone number or email, so a forgotten password cannot be reset.';

  @override
  String get forgottenPassword => 'Forgotten password';

  @override
  String get getACode => 'Get a code';

  @override
  String get enterTheCode => 'Enter the code';

  @override
  String get getACodeDetail =>
      'Tell us your username, phone number or email and we will send a code to whichever we have on file.';

  @override
  String codeSentTo(String destination) {
    return 'We sent a six digit code to $destination. It is good for 15 minutes.';
  }

  @override
  String get identifierLabel => 'Username, phone or email';

  @override
  String get identifierRequired => 'Enter your username, phone or email.';

  @override
  String get sixDigitCode => 'Six digit code';

  @override
  String get codeIsSixDigits => 'The code is six digits.';

  @override
  String get newPassword => 'New password';

  @override
  String get sendMeACode => 'Send me a code';

  @override
  String get changeMyPassword => 'Change my password';

  @override
  String get sendAnotherCode => 'Send another code';

  @override
  String get newCodeCancelsLast =>
      'Asking for a new code cancels the last one.';

  @override
  String cancelBookingWhen(String when) {
    return '$when.\n\nThe table goes back to other customers, so you may not get it again.';
  }

  @override
  String get bookingCancelled => 'Booking cancelled.';

  @override
  String get reviewIsLive => 'Thanks — your review is live.';

  @override
  String get addACaption => 'Add a caption';

  @override
  String get optional => 'Optional';

  @override
  String get cancel => 'Cancel';

  @override
  String get share => 'Share';

  @override
  String get photoShared => 'Thanks — your photo is shared.';

  @override
  String get noBookingsOnThisPhone =>
      'Reservations you make on this phone show up here.';

  @override
  String paymentFailedShort(String provider) {
    return '$provider · payment failed';
  }

  @override
  String paymentPendingShort(String provider) {
    return '$provider · payment pending';
  }

  @override
  String get addAPhoto => 'Add a photo';

  @override
  String get nameRequiredBooking => 'The venue needs a name for the booking';

  @override
  String get phoneRequiredBooking => 'The venue will call to confirm';

  @override
  String get phoneTooShortBooking => 'That number looks too short';

  @override
  String get howWouldYouLikeToPay => 'How would you like to pay?';

  @override
  String get payOnArrival => 'Pay on arrival';

  @override
  String get payOnArrivalDetail =>
      'Nothing is charged now. The venue confirms your table.';

  @override
  String get payDepositDetail =>
      'Pay a deposit now — your table is confirmed straight away.';

  @override
  String get payAndReserve => 'Pay and reserve';

  @override
  String get reserve => 'Reserve';

  @override
  String get requestSent => 'Request sent';

  @override
  String willConfirmShortly(String venue, String phone) {
    return '$venue will confirm shortly. They may call $phone.';
  }

  @override
  String get tableConfirmed => 'Table confirmed';

  @override
  String paidAndConfirmed(String venue) {
    return 'Paid and confirmed at $venue. Show this reference when you arrive.';
  }

  @override
  String get paymentDidNotGoThrough => 'Payment did not go through';

  @override
  String stillHeldAsRequest(String venue) {
    return 'Your table is still held as a request. $venue will confirm it, or you can pay on arrival.';
  }

  @override
  String get stillWaitingOnPayment => 'Still waiting on payment';

  @override
  String get waitingForPaymentTitle => 'Waiting for payment';

  @override
  String get notComeThroughYet =>
      'It has not come through yet. Check My bookings in a moment — the table is held either way.';

  @override
  String get approveOnYourPhone =>
      'Approve the payment on your phone. This updates by itself.';

  @override
  String get booked => 'Booked';

  @override
  String get bookingLabel => 'Booking';

  @override
  String get reference => 'Reference';

  @override
  String get paidWith => 'Paid with';

  @override
  String get chooseARating => 'Choose a rating from 1 to 5.';

  @override
  String get howWasIt => 'How was it?';

  @override
  String get anythingToAdd => 'Anything to add? (optional)';

  @override
  String get postReview => 'Post review';

  @override
  String get onlyFirstNameShown => 'Only your first name is shown.';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get backToPhotos => 'Back to photos';

  @override
  String photoOf(int index, int total) {
    return '$index of $total';
  }

  @override
  String get previousPhoto => 'Previous photo';

  @override
  String get nextPhoto => 'Next photo';

  @override
  String get photoCouldNotLoad => 'This photo could not be loaded';

  @override
  String tableHeldFor(int minutes) {
    return 'We will hold your table for $minutes minutes after your booking time.';
  }

  @override
  String get bookingMissed => 'Missed';

  @override
  String get bookingMissedDetail =>
      'Nobody arrived before the venue stopped holding the table.';
}
