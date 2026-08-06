import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Sylibooking'**
  String get appTitle;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @navBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get navBookings;

  /// No description provided for @navFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get navFavourites;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @greetingWithName.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}'**
  String greetingWithName(String greeting, String name);

  /// No description provided for @findATable.
  ///
  /// In en, this message translates to:
  /// **'Find a table'**
  String get findATable;

  /// No description provided for @searchByName.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchByName;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get filterRestaurants;

  /// No description provided for @filterLounges.
  ///
  /// In en, this message translates to:
  /// **'Lounges'**
  String get filterLounges;

  /// No description provided for @filterOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get filterOpenNow;

  /// No description provided for @filterNearest.
  ///
  /// In en, this message translates to:
  /// **'Nearest'**
  String get filterNearest;

  /// No description provided for @filterShowDistances.
  ///
  /// In en, this message translates to:
  /// **'Show distances'**
  String get filterShowDistances;

  /// No description provided for @statusOpenUntil.
  ///
  /// In en, this message translates to:
  /// **'Open until {time}'**
  String statusOpenUntil(String time);

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @statusHoursNotListed.
  ///
  /// In en, this message translates to:
  /// **'Hours not listed'**
  String get statusHoursNotListed;

  /// No description provided for @resStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get resStatusPending;

  /// No description provided for @resStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get resStatusConfirmed;

  /// No description provided for @resStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get resStatusCancelled;

  /// No description provided for @resStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get resStatusCompleted;

  /// No description provided for @resStatusMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get resStatusMissed;

  /// No description provided for @typeAndCity.
  ///
  /// In en, this message translates to:
  /// **'{type} · {city}'**
  String typeAndCity(String type, String city);

  /// No description provided for @couldNotLoadPlaces.
  ///
  /// In en, this message translates to:
  /// **'Could not load places'**
  String get couldNotLoadPlaces;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get nothingFound;

  /// No description provided for @nothingFoundDetail.
  ///
  /// In en, this message translates to:
  /// **'Try a different name, or clear the filters.'**
  String get nothingFoundDetail;

  /// No description provided for @nothingOpenRightNow.
  ///
  /// In en, this message translates to:
  /// **'Nothing is open right now. Turn off \"Open now\" to see places you can book for later.'**
  String get nothingOpenRightNow;

  /// No description provided for @showDistancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Show distances?'**
  String get showDistancesTitle;

  /// No description provided for @showDistancesBody.
  ///
  /// In en, this message translates to:
  /// **'Sylibooking can show how far each place is and sort by what is nearest. Your location stays on your phone — it is never sent to us or to the venues.'**
  String get showDistancesBody;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'No problem — browsing works without it. You can allow location later in your phone settings.'**
  String get locationDenied;

  /// No description provided for @locationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Location is switched off on this phone. Turn it on to see distances.'**
  String get locationServicesOff;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not get a location just now. Distances are unavailable.'**
  String get locationUnavailable;

  /// No description provided for @getDirections.
  ///
  /// In en, this message translates to:
  /// **'Get directions'**
  String get getDirections;

  /// No description provided for @noMapsApp.
  ///
  /// In en, this message translates to:
  /// **'No maps app found on this phone.'**
  String get noMapsApp;

  /// No description provided for @saveToFavourites.
  ///
  /// In en, this message translates to:
  /// **'Save to favourites'**
  String get saveToFavourites;

  /// No description provided for @removeFromFavourites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFromFavourites;

  /// No description provided for @allWeek.
  ///
  /// In en, this message translates to:
  /// **'All week'**
  String get allWeek;

  /// No description provided for @hideWeek.
  ///
  /// In en, this message translates to:
  /// **'Hide week'**
  String get hideWeek;

  /// No description provided for @closedToday.
  ///
  /// In en, this message translates to:
  /// **'Closed today'**
  String get closedToday;

  /// No description provided for @seeAllReviews.
  ///
  /// In en, this message translates to:
  /// **'See all {count}'**
  String seeAllReviews(int count);

  /// No description provided for @noReviewsAfterVisit.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet — be the first after your visit.'**
  String get noReviewsAfterVisit;

  /// No description provided for @lastSpaceFree.
  ///
  /// In en, this message translates to:
  /// **'Last space free at this time'**
  String get lastSpaceFree;

  /// No description provided for @slotTaken.
  ///
  /// In en, this message translates to:
  /// **'Already taken'**
  String get slotTaken;

  /// No description provided for @spacesFree.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 space free} other{{count} spaces free}}'**
  String spacesFree(int count);

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @orderAhead.
  ///
  /// In en, this message translates to:
  /// **'Order ahead'**
  String get orderAhead;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @reviewCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No reviews yet} =1{1 review} other{{count} reviews}}'**
  String reviewCount(int count);

  /// No description provided for @beTheFirstToReview.
  ///
  /// In en, this message translates to:
  /// **'Be the first to leave a review.'**
  String get beTheFirstToReview;

  /// No description provided for @writeAReview.
  ///
  /// In en, this message translates to:
  /// **'Write a review'**
  String get writeAReview;

  /// No description provided for @partySize.
  ///
  /// In en, this message translates to:
  /// **'Party size'**
  String get partySize;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// No description provided for @availableTimes.
  ///
  /// In en, this message translates to:
  /// **'Available times'**
  String get availableTimes;

  /// No description provided for @nothingFreeForParty.
  ///
  /// In en, this message translates to:
  /// **'Nothing free for {count} on this day'**
  String nothingFreeForParty(int count);

  /// No description provided for @tryAnotherDay.
  ///
  /// In en, this message translates to:
  /// **'Try another day, or a smaller party.'**
  String get tryAnotherDay;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @bookATable.
  ///
  /// In en, this message translates to:
  /// **'Book a table'**
  String get bookATable;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'The venue needs a name for the booking.'**
  String get nameRequired;

  /// No description provided for @phoneRequired.
  ///
  /// In en, this message translates to:
  /// **'A number to reach you on.'**
  String get phoneRequired;

  /// No description provided for @phoneTooShort.
  ///
  /// In en, this message translates to:
  /// **'That number looks too short.'**
  String get phoneTooShort;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @cashOnArrival.
  ///
  /// In en, this message translates to:
  /// **'Cash on arrival'**
  String get cashOnArrival;

  /// No description provided for @cashOnArrivalDetail.
  ///
  /// In en, this message translates to:
  /// **'Pay at the venue'**
  String get cashOnArrivalDetail;

  /// No description provided for @orangeMoney.
  ///
  /// In en, this message translates to:
  /// **'Orange Money'**
  String get orangeMoney;

  /// No description provided for @mtnMoney.
  ///
  /// In en, this message translates to:
  /// **'MTN Mobile Money'**
  String get mtnMoney;

  /// No description provided for @payNowDetail.
  ///
  /// In en, this message translates to:
  /// **'The table is held once the payment clears'**
  String get payNowDetail;

  /// No description provided for @confirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get confirmBooking;

  /// No description provided for @payAndBook.
  ///
  /// In en, this message translates to:
  /// **'Pay and book'**
  String get payAndBook;

  /// No description provided for @booking.
  ///
  /// In en, this message translates to:
  /// **'Booking…'**
  String get booking;

  /// No description provided for @bookingConfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Table confirmed'**
  String get bookingConfirmedTitle;

  /// No description provided for @bookingRequestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking requested'**
  String get bookingRequestedTitle;

  /// No description provided for @paymentFailedNothingCharged.
  ///
  /// In en, this message translates to:
  /// **'The payment did not go through, so nothing was charged. Your booking is still requested — you can pay at the venue.'**
  String get paymentFailedNothingCharged;

  /// No description provided for @waitingForPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your payment to clear.'**
  String get waitingForPayment;

  /// No description provided for @backToBrowsing.
  ///
  /// In en, this message translates to:
  /// **'Back to browsing'**
  String get backToBrowsing;

  /// No description provided for @myBookings.
  ///
  /// In en, this message translates to:
  /// **'My bookings'**
  String get myBookings;

  /// No description provided for @tabBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get tabBookings;

  /// No description provided for @tabOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get tabOrders;

  /// No description provided for @noBookingsYet.
  ///
  /// In en, this message translates to:
  /// **'No bookings yet'**
  String get noBookingsYet;

  /// No description provided for @noBookingsDetail.
  ///
  /// In en, this message translates to:
  /// **'Book a table and it will show up here.'**
  String get noBookingsDetail;

  /// No description provided for @cancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get cancelBooking;

  /// No description provided for @cancelBookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this booking?'**
  String get cancelBookingTitle;

  /// No description provided for @cancelBookingBody.
  ///
  /// In en, this message translates to:
  /// **'The venue will free the table for someone else.'**
  String get cancelBookingBody;

  /// No description provided for @keepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get keepIt;

  /// No description provided for @sharePhoto.
  ///
  /// In en, this message translates to:
  /// **'Share a photo'**
  String get sharePhoto;

  /// No description provided for @reviewYourVisit.
  ///
  /// In en, this message translates to:
  /// **'Review your visit'**
  String get reviewYourVisit;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get noOrdersYet;

  /// No description provided for @noOrdersDetail.
  ///
  /// In en, this message translates to:
  /// **'Order ahead from a restaurant and it will show up here, with its progress while the kitchen works on it.'**
  String get noOrdersDetail;

  /// No description provided for @couldNotLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Could not load your orders'**
  String get couldNotLoadOrders;

  /// No description provided for @sectionActive.
  ///
  /// In en, this message translates to:
  /// **'Active · {count}'**
  String sectionActive(int count);

  /// No description provided for @sectionPast.
  ///
  /// In en, this message translates to:
  /// **'Past · {count}'**
  String sectionPast(int count);

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// No description provided for @orderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get orderPlaced;

  /// No description provided for @orderPreparing.
  ///
  /// In en, this message translates to:
  /// **'Being prepared'**
  String get orderPreparing;

  /// No description provided for @orderReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to collect'**
  String get orderReady;

  /// No description provided for @orderCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get orderCollected;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderCancelled;

  /// No description provided for @orderWaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting on payment'**
  String get orderWaitingPayment;

  /// No description provided for @couldNotLoadMenu.
  ///
  /// In en, this message translates to:
  /// **'Could not load the menu'**
  String get couldNotLoadMenu;

  /// No description provided for @nothingToOrderYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to order yet'**
  String get nothingToOrderYet;

  /// No description provided for @nothingToOrderDetail.
  ///
  /// In en, this message translates to:
  /// **'This restaurant has not put its menu online. You can still book a table and order at it.'**
  String get nothingToOrderDetail;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addNamed.
  ///
  /// In en, this message translates to:
  /// **'Add {name}'**
  String addNamed(String name);

  /// No description provided for @oneFewer.
  ///
  /// In en, this message translates to:
  /// **'One fewer {name}'**
  String oneFewer(String name);

  /// No description provided for @oneMore.
  ///
  /// In en, this message translates to:
  /// **'One more {name}'**
  String oneMore(String name);

  /// No description provided for @tapToReview.
  ///
  /// In en, this message translates to:
  /// **'{count} · tap to review'**
  String tapToReview(String count);

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @yourBasket.
  ///
  /// In en, this message translates to:
  /// **'Your basket'**
  String get yourBasket;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @priceWithCurrency.
  ///
  /// In en, this message translates to:
  /// **'{amount} GNF'**
  String priceWithCurrency(String amount);

  /// No description provided for @dishCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 dish} other{{count} dishes}} · collect at the counter'**
  String dishCount(int count);

  /// No description provided for @timedToYourBooking.
  ///
  /// In en, this message translates to:
  /// **'Timed to your table booking'**
  String get timedToYourBooking;

  /// No description provided for @counterNeedsName.
  ///
  /// In en, this message translates to:
  /// **'The counter needs a name to call out.'**
  String get counterNeedsName;

  /// No description provided for @collectionTime.
  ///
  /// In en, this message translates to:
  /// **'Collection time'**
  String get collectionTime;

  /// No description provided for @cashOnPickup.
  ///
  /// In en, this message translates to:
  /// **'Cash on pickup'**
  String get cashOnPickup;

  /// No description provided for @cashOnPickupDetail.
  ///
  /// In en, this message translates to:
  /// **'Pay at the counter when you collect'**
  String get cashOnPickupDetail;

  /// No description provided for @kitchenStartsWhenPaid.
  ///
  /// In en, this message translates to:
  /// **'The kitchen starts once the payment clears'**
  String get kitchenStartsWhenPaid;

  /// No description provided for @placeOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get placeOrder;

  /// No description provided for @payAndOrder.
  ///
  /// In en, this message translates to:
  /// **'Pay and order'**
  String get payAndOrder;

  /// No description provided for @placing.
  ///
  /// In en, this message translates to:
  /// **'Placing…'**
  String get placing;

  /// No description provided for @yourOrder.
  ///
  /// In en, this message translates to:
  /// **'Your order'**
  String get yourOrder;

  /// No description provided for @collectAt.
  ///
  /// In en, this message translates to:
  /// **'Collect at {when}'**
  String collectAt(String when);

  /// No description provided for @progressPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get progressPlaced;

  /// No description provided for @progressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get progressPreparing;

  /// No description provided for @progressReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get progressReady;

  /// No description provided for @progressPlacedDetail.
  ///
  /// In en, this message translates to:
  /// **'The restaurant has your order'**
  String get progressPlacedDetail;

  /// No description provided for @progressPreparingDetail.
  ///
  /// In en, this message translates to:
  /// **'It is being cooked'**
  String get progressPreparingDetail;

  /// No description provided for @progressReadyDetail.
  ///
  /// In en, this message translates to:
  /// **'Collect it at the counter'**
  String get progressReadyDetail;

  /// No description provided for @progressCollectedDetail.
  ///
  /// In en, this message translates to:
  /// **'Collected. Enjoy it.'**
  String get progressCollectedDetail;

  /// No description provided for @progressCancelledDetail.
  ///
  /// In en, this message translates to:
  /// **'This order was cancelled'**
  String get progressCancelledDetail;

  /// No description provided for @whatYouOrdered.
  ///
  /// In en, this message translates to:
  /// **'What you ordered'**
  String get whatYouOrdered;

  /// No description provided for @waitingOnPaymentDetail.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your {provider} payment. The kitchen starts once it clears.'**
  String waitingOnPaymentDetail(String provider);

  /// No description provided for @orderCancelledNothingOwed.
  ///
  /// In en, this message translates to:
  /// **'This order was cancelled. Nothing is owed.'**
  String get orderCancelledNothingOwed;

  /// No description provided for @favourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favourites;

  /// No description provided for @nothingSavedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet'**
  String get nothingSavedYet;

  /// No description provided for @nothingSavedDetail.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on a place you like and it will wait for you here.'**
  String get nothingSavedDetail;

  /// No description provided for @savedOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. Make an account from Profile and they follow you to the next one.'**
  String get savedOnThisPhone;

  /// No description provided for @couldNotLoadFavourites.
  ///
  /// In en, this message translates to:
  /// **'Could not load your favourites'**
  String get couldNotLoadFavourites;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @makeAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Make an account'**
  String get makeAnAccount;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @accountIsOptional.
  ///
  /// In en, this message translates to:
  /// **'You do not need one. Everything works without it — an account just keeps your bookings and favourites if you change phone.'**
  String get accountIsOptional;

  /// No description provided for @whatShouldWeCallYou.
  ///
  /// In en, this message translates to:
  /// **'What should we call you?'**
  String get whatShouldWeCallYou;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @pickAUsername.
  ///
  /// In en, this message translates to:
  /// **'Pick a username.'**
  String get pickAUsername;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @enterAPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a password.'**
  String get enterAPassword;

  /// No description provided for @atLeast8Characters.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters.'**
  String get atLeast8Characters;

  /// No description provided for @phoneHelper.
  ///
  /// In en, this message translates to:
  /// **'So you can get back in if you forget the password'**
  String get phoneHelper;

  /// No description provided for @emailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get emailOptional;

  /// No description provided for @emailLooksWrong.
  ///
  /// In en, this message translates to:
  /// **'That email looks wrong.'**
  String get emailLooksWrong;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @justAMoment.
  ///
  /// In en, this message translates to:
  /// **'Just a moment…'**
  String get justAMoment;

  /// No description provided for @iAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get iAlreadyHaveAnAccount;

  /// No description provided for @iNeedAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I need an account'**
  String get iNeedAnAccount;

  /// No description provided for @iForgotMyPassword.
  ///
  /// In en, this message translates to:
  /// **'I have forgotten my password'**
  String get iForgotMyPassword;

  /// No description provided for @signedInEverythingSaved.
  ///
  /// In en, this message translates to:
  /// **'Signed in. Everything on this phone is saved.'**
  String get signedInEverythingSaved;

  /// No description provided for @accountKeepsEverything.
  ///
  /// In en, this message translates to:
  /// **'Your bookings, orders and favourites are saved to this account. Sign in on another phone and they follow you.'**
  String get accountKeepsEverything;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutKeepsPhone.
  ///
  /// In en, this message translates to:
  /// **'Signing out leaves this phone with what it had before — nothing is deleted.'**
  String get signOutKeepsPhone;

  /// No description provided for @noWayBackIn.
  ///
  /// In en, this message translates to:
  /// **'This account has no phone number or email, so a forgotten password cannot be reset.'**
  String get noWayBackIn;

  /// No description provided for @forgottenPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgotten password'**
  String get forgottenPassword;

  /// No description provided for @getACode.
  ///
  /// In en, this message translates to:
  /// **'Get a code'**
  String get getACode;

  /// No description provided for @enterTheCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get enterTheCode;

  /// No description provided for @getACodeDetail.
  ///
  /// In en, this message translates to:
  /// **'Tell us your username, phone number or email and we will send a code to whichever we have on file.'**
  String get getACodeDetail;

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a six digit code to {destination}. It is good for 15 minutes.'**
  String codeSentTo(String destination);

  /// No description provided for @identifierLabel.
  ///
  /// In en, this message translates to:
  /// **'Username, phone or email'**
  String get identifierLabel;

  /// No description provided for @identifierRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your username, phone or email.'**
  String get identifierRequired;

  /// No description provided for @sixDigitCode.
  ///
  /// In en, this message translates to:
  /// **'Six digit code'**
  String get sixDigitCode;

  /// No description provided for @codeIsSixDigits.
  ///
  /// In en, this message translates to:
  /// **'The code is six digits.'**
  String get codeIsSixDigits;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @sendMeACode.
  ///
  /// In en, this message translates to:
  /// **'Send me a code'**
  String get sendMeACode;

  /// No description provided for @changeMyPassword.
  ///
  /// In en, this message translates to:
  /// **'Change my password'**
  String get changeMyPassword;

  /// No description provided for @sendAnotherCode.
  ///
  /// In en, this message translates to:
  /// **'Send another code'**
  String get sendAnotherCode;

  /// No description provided for @newCodeCancelsLast.
  ///
  /// In en, this message translates to:
  /// **'Asking for a new code cancels the last one.'**
  String get newCodeCancelsLast;

  /// No description provided for @cancelBookingWhen.
  ///
  /// In en, this message translates to:
  /// **'{when}.\n\nThe table goes back to other customers, so you may not get it again.'**
  String cancelBookingWhen(String when);

  /// No description provided for @bookingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Booking cancelled.'**
  String get bookingCancelled;

  /// No description provided for @reviewIsLive.
  ///
  /// In en, this message translates to:
  /// **'Thanks — your review is live.'**
  String get reviewIsLive;

  /// No description provided for @addACaption.
  ///
  /// In en, this message translates to:
  /// **'Add a caption'**
  String get addACaption;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @photoShared.
  ///
  /// In en, this message translates to:
  /// **'Thanks — your photo is shared.'**
  String get photoShared;

  /// No description provided for @noBookingsOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Reservations you make on this phone show up here.'**
  String get noBookingsOnThisPhone;

  /// No description provided for @paymentFailedShort.
  ///
  /// In en, this message translates to:
  /// **'{provider} · payment failed'**
  String paymentFailedShort(String provider);

  /// No description provided for @paymentPendingShort.
  ///
  /// In en, this message translates to:
  /// **'{provider} · payment pending'**
  String paymentPendingShort(String provider);

  /// No description provided for @addAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get addAPhoto;

  /// No description provided for @nameRequiredBooking.
  ///
  /// In en, this message translates to:
  /// **'The venue needs a name for the booking'**
  String get nameRequiredBooking;

  /// No description provided for @phoneRequiredBooking.
  ///
  /// In en, this message translates to:
  /// **'The venue will call to confirm'**
  String get phoneRequiredBooking;

  /// No description provided for @phoneTooShortBooking.
  ///
  /// In en, this message translates to:
  /// **'That number looks too short'**
  String get phoneTooShortBooking;

  /// No description provided for @howWouldYouLikeToPay.
  ///
  /// In en, this message translates to:
  /// **'How would you like to pay?'**
  String get howWouldYouLikeToPay;

  /// No description provided for @payOnArrival.
  ///
  /// In en, this message translates to:
  /// **'Pay on arrival'**
  String get payOnArrival;

  /// No description provided for @payOnArrivalDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing is charged now. The venue confirms your table.'**
  String get payOnArrivalDetail;

  /// No description provided for @payDepositDetail.
  ///
  /// In en, this message translates to:
  /// **'Pay a deposit now — your table is confirmed straight away.'**
  String get payDepositDetail;

  /// No description provided for @payAndReserve.
  ///
  /// In en, this message translates to:
  /// **'Pay and reserve'**
  String get payAndReserve;

  /// No description provided for @reserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get reserve;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get requestSent;

  /// No description provided for @willConfirmShortly.
  ///
  /// In en, this message translates to:
  /// **'{venue} will confirm shortly. They may call {phone}.'**
  String willConfirmShortly(String venue, String phone);

  /// No description provided for @tableConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Table confirmed'**
  String get tableConfirmed;

  /// No description provided for @paidAndConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Paid and confirmed at {venue}. Show this reference when you arrive.'**
  String paidAndConfirmed(String venue);

  /// No description provided for @paymentDidNotGoThrough.
  ///
  /// In en, this message translates to:
  /// **'Payment did not go through'**
  String get paymentDidNotGoThrough;

  /// No description provided for @stillHeldAsRequest.
  ///
  /// In en, this message translates to:
  /// **'Your table is still held as a request. {venue} will confirm it, or you can pay on arrival.'**
  String stillHeldAsRequest(String venue);

  /// No description provided for @stillWaitingOnPayment.
  ///
  /// In en, this message translates to:
  /// **'Still waiting on payment'**
  String get stillWaitingOnPayment;

  /// No description provided for @waitingForPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for payment'**
  String get waitingForPaymentTitle;

  /// No description provided for @notComeThroughYet.
  ///
  /// In en, this message translates to:
  /// **'It has not come through yet. Check My bookings in a moment — the table is held either way.'**
  String get notComeThroughYet;

  /// No description provided for @approveOnYourPhone.
  ///
  /// In en, this message translates to:
  /// **'Approve the payment on your phone. This updates by itself.'**
  String get approveOnYourPhone;

  /// No description provided for @booked.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get booked;

  /// No description provided for @bookingLabel.
  ///
  /// In en, this message translates to:
  /// **'Booking'**
  String get bookingLabel;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @paidWith.
  ///
  /// In en, this message translates to:
  /// **'Paid with'**
  String get paidWith;

  /// No description provided for @chooseARating.
  ///
  /// In en, this message translates to:
  /// **'Choose a rating from 1 to 5.'**
  String get chooseARating;

  /// No description provided for @howWasIt.
  ///
  /// In en, this message translates to:
  /// **'How was it?'**
  String get howWasIt;

  /// No description provided for @anythingToAdd.
  ///
  /// In en, this message translates to:
  /// **'Anything to add? (optional)'**
  String get anythingToAdd;

  /// No description provided for @postReview.
  ///
  /// In en, this message translates to:
  /// **'Post review'**
  String get postReview;

  /// No description provided for @onlyFirstNameShown.
  ///
  /// In en, this message translates to:
  /// **'Only your first name is shown.'**
  String get onlyFirstNameShown;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @backToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Back to photos'**
  String get backToPhotos;

  /// No description provided for @photoOf.
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}'**
  String photoOf(int index, int total);

  /// No description provided for @previousPhoto.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get previousPhoto;

  /// No description provided for @nextPhoto.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get nextPhoto;

  /// No description provided for @photoCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'This photo could not be loaded'**
  String get photoCouldNotLoad;

  /// No description provided for @tableHeldFor.
  ///
  /// In en, this message translates to:
  /// **'We will hold your table for {minutes} minutes after your booking time.'**
  String tableHeldFor(int minutes);

  /// No description provided for @bookingMissedDetail.
  ///
  /// In en, this message translates to:
  /// **'Nobody arrived before the venue stopped holding the table.'**
  String get bookingMissedDetail;

  /// No description provided for @depositTerms.
  ///
  /// In en, this message translates to:
  /// **'Your {amount} GNF deposit comes off the bill when you arrive. If nobody arrives in that time, the venue keeps it.'**
  String depositTerms(String amount);

  /// No description provided for @depositHeadline.
  ///
  /// In en, this message translates to:
  /// **'Deposit {amount} GNF.'**
  String depositHeadline(String amount);

  /// No description provided for @depositDetail.
  ///
  /// In en, this message translates to:
  /// **'It comes off your bill when you arrive. If the table isn\'t taken {minutes} minutes after the booked time, the venue keeps it.'**
  String depositDetail(int minutes);

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a moment and try again.'**
  String get tooManyAttempts;

  /// Shown when the public catalogue refuses a request for coming too fast.
  ///
  /// In en, this message translates to:
  /// **'You\'re going a bit fast. Wait a moment and try again.'**
  String get browsingTooFast;

  /// No description provided for @yourDetails.
  ///
  /// In en, this message translates to:
  /// **'Your details'**
  String get yourDetails;

  /// No description provided for @detailsIntro.
  ///
  /// In en, this message translates to:
  /// **'Used to fill in your next booking, and to reach you if you forget your password.'**
  String get detailsIntro;

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileName;

  /// No description provided for @profilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get profilePhone;

  /// No description provided for @profileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get profileEmail;

  /// No description provided for @saveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save details'**
  String get saveDetails;

  /// No description provided for @detailsSaved.
  ///
  /// In en, this message translates to:
  /// **'Details saved.'**
  String get detailsSaved;

  /// No description provided for @closeAccount.
  ///
  /// In en, this message translates to:
  /// **'Close my account'**
  String get closeAccount;

  /// No description provided for @closeAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Close your account?'**
  String get closeAccountTitle;

  /// No description provided for @closeAccountDetail.
  ///
  /// In en, this message translates to:
  /// **'Your saved venues and your sign-in go for good. Bookings you have already made stay with the venue as part of their records, with your name and number removed.'**
  String get closeAccountDetail;

  /// No description provided for @closeAccountCannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get closeAccountCannotUndo;

  /// No description provided for @closeAccountPassword.
  ///
  /// In en, this message translates to:
  /// **'Your password'**
  String get closeAccountPassword;

  /// No description provided for @closeAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Close it'**
  String get closeAccountConfirm;

  /// No description provided for @accountClosed.
  ///
  /// In en, this message translates to:
  /// **'Your account is closed.'**
  String get accountClosed;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'fr':
      return LFr();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
