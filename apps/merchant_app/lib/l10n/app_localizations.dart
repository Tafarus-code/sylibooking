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
  /// **'Sylibooking Merchant'**
  String get appTitle;

  /// No description provided for @merchant.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get merchant;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @keepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get keepIt;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

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

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @enterYourUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter your username'**
  String get enterYourUsername;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterYourPassword;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hidePassword;

  /// No description provided for @wrongUsernameOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong username or password.'**
  String get wrongUsernameOrPassword;

  /// No description provided for @navReservations.
  ///
  /// In en, this message translates to:
  /// **'Reservations'**
  String get navReservations;

  /// No description provided for @navPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get navPayments;

  /// No description provided for @navManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get navManage;

  /// Left half of the desk switcher. Stays French in both languages: it is the word merchants already use on the floor.
  ///
  /// In en, this message translates to:
  /// **'Réservations'**
  String get tabReservations;

  /// Right half of the desk switcher. See tabReservations.
  ///
  /// In en, this message translates to:
  /// **'Commandes'**
  String get tabOrders;

  /// No description provided for @switchVenue.
  ///
  /// In en, this message translates to:
  /// **'Switch venue'**
  String get switchVenue;

  /// No description provided for @noVenue.
  ///
  /// In en, this message translates to:
  /// **'No venue'**
  String get noVenue;

  /// No description provided for @chooseAVenue.
  ///
  /// In en, this message translates to:
  /// **'Choose a venue'**
  String get chooseAVenue;

  /// No description provided for @keepCurrentVenue.
  ///
  /// In en, this message translates to:
  /// **'Keep current venue'**
  String get keepCurrentVenue;

  /// No description provided for @everythingAppliesToVenue.
  ///
  /// In en, this message translates to:
  /// **'Everything you do next applies to the venue you pick.'**
  String get everythingAppliesToVenue;

  /// No description provided for @noVenueYet.
  ///
  /// In en, this message translates to:
  /// **'No venue yet'**
  String get noVenueYet;

  /// No description provided for @noVenueYetDetail.
  ///
  /// In en, this message translates to:
  /// **'This account is not a member of any establishment. An owner can add you to theirs, or an admin can set one up.'**
  String get noVenueYetDetail;

  /// No description provided for @rangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get rangeToday;

  /// No description provided for @rangeNextSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Next 7 days'**
  String get rangeNextSevenDays;

  /// No description provided for @dayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dayToday;

  /// No description provided for @dayTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dayTomorrow;

  /// No description provided for @couldNotLoadReservations.
  ///
  /// In en, this message translates to:
  /// **'Could not load reservations'**
  String get couldNotLoadReservations;

  /// No description provided for @noVenueAssigned.
  ///
  /// In en, this message translates to:
  /// **'No venue assigned'**
  String get noVenueAssigned;

  /// No description provided for @noVenueAssignedDetail.
  ///
  /// In en, this message translates to:
  /// **'This account is not staff at any establishment yet, so there is nothing to show. An admin can assign one in the Django admin.'**
  String get noVenueAssignedDetail;

  /// No description provided for @nothingBookedToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing booked today'**
  String get nothingBookedToday;

  /// No description provided for @nothingBookedThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Nothing booked this week'**
  String get nothingBookedThisWeek;

  /// No description provided for @newReservationsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'New reservations appear here as customers make them.'**
  String get newReservationsAppearHere;

  /// No description provided for @cancelThisReservation.
  ///
  /// In en, this message translates to:
  /// **'Cancel this reservation?'**
  String get cancelThisReservation;

  /// No description provided for @cancelReservationDetail.
  ///
  /// In en, this message translates to:
  /// **'{name} · {space} at {time}.\n\nThe slot becomes bookable again.'**
  String cancelReservationDetail(String name, String space, String time);

  /// No description provided for @cancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get cancelBooking;

  /// No description provided for @reservationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Reservation cancelled.'**
  String get reservationCancelled;

  /// No description provided for @reservationConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Reservation confirmed.'**
  String get reservationConfirmed;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @guestCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 guest} other{{count} guests}}'**
  String guestCount(int count);

  /// No description provided for @cannotConfirmUntilPaymentClears.
  ///
  /// In en, this message translates to:
  /// **'Cannot confirm until the payment clears.'**
  String get cannotConfirmUntilPaymentClears;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get statusUnknown;

  /// No description provided for @paidWith.
  ///
  /// In en, this message translates to:
  /// **'Paid ({provider})'**
  String paidWith(String provider);

  /// No description provided for @mobileMoney.
  ///
  /// In en, this message translates to:
  /// **'mobile money'**
  String get mobileMoney;

  /// No description provided for @paymentFailedWith.
  ///
  /// In en, this message translates to:
  /// **'Payment failed ({provider})'**
  String paymentFailedWith(String provider);

  /// No description provided for @awaitingPaymentWith.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment ({provider})'**
  String awaitingPaymentWith(String provider);

  /// No description provided for @paymentFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentFailedShort;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @cashOnArrival.
  ///
  /// In en, this message translates to:
  /// **'Cash on arrival'**
  String get cashOnArrival;

  /// No description provided for @cashShort.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cashShort;

  /// No description provided for @stageReadyToCollect.
  ///
  /// In en, this message translates to:
  /// **'Ready to collect'**
  String get stageReadyToCollect;

  /// No description provided for @stageBeingPrepared.
  ///
  /// In en, this message translates to:
  /// **'Being prepared'**
  String get stageBeingPrepared;

  /// No description provided for @stageNewOrders.
  ///
  /// In en, this message translates to:
  /// **'New orders'**
  String get stageNewOrders;

  /// No description provided for @stageHeading.
  ///
  /// In en, this message translates to:
  /// **'{label} · {count}'**
  String stageHeading(String label, int count);

  /// No description provided for @couldNotLoadTheQueue.
  ///
  /// In en, this message translates to:
  /// **'Could not load the queue'**
  String get couldNotLoadTheQueue;

  /// No description provided for @noVenueSelected.
  ///
  /// In en, this message translates to:
  /// **'No venue selected'**
  String get noVenueSelected;

  /// No description provided for @pickAVenueForQueue.
  ///
  /// In en, this message translates to:
  /// **'Pick a venue to see its kitchen queue.'**
  String get pickAVenueForQueue;

  /// No description provided for @nothingInTheQueue.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the queue'**
  String get nothingInTheQueue;

  /// No description provided for @ordersLandHere.
  ///
  /// In en, this message translates to:
  /// **'Orders placed for today land here as they come in.'**
  String get ordersLandHere;

  /// No description provided for @cancelThisOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get cancelThisOrder;

  /// No description provided for @cancelOrderDetail.
  ///
  /// In en, this message translates to:
  /// **'{name} will not be able to collect it, and nothing will be owed.'**
  String cancelOrderDetail(String name);

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @startPreparing.
  ///
  /// In en, this message translates to:
  /// **'Start preparing'**
  String get startPreparing;

  /// No description provided for @markReady.
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get markReady;

  /// No description provided for @markCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get markCollected;

  /// No description provided for @moveOn.
  ///
  /// In en, this message translates to:
  /// **'Move on'**
  String get moveOn;

  /// No description provided for @atTheirTable.
  ///
  /// In en, this message translates to:
  /// **'At their table'**
  String get atTheirTable;

  /// No description provided for @orderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get orderPlaced;

  /// No description provided for @orderPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get orderPreparing;

  /// No description provided for @orderReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
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

  /// No description provided for @orderUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get orderUnknown;

  /// No description provided for @waitingOnPayment.
  ///
  /// In en, this message translates to:
  /// **'Waiting on the {provider} payment. The kitchen cannot start until it clears.'**
  String waitingOnPayment(String provider);

  /// No description provided for @cashOnPickup.
  ///
  /// In en, this message translates to:
  /// **'Cash on pickup'**
  String get cashOnPickup;

  /// No description provided for @amountGnf.
  ///
  /// In en, this message translates to:
  /// **'{amount} GNF'**
  String amountGnf(String amount);

  /// No description provided for @reservationTitle.
  ///
  /// In en, this message translates to:
  /// **'Reservation'**
  String get reservationTitle;

  /// No description provided for @sectionBooking.
  ///
  /// In en, this message translates to:
  /// **'Booking'**
  String get sectionBooking;

  /// No description provided for @rowWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get rowWhen;

  /// No description provided for @rowSpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get rowSpace;

  /// No description provided for @rowParty.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get rowParty;

  /// No description provided for @rowPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get rowPhone;

  /// No description provided for @rowReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get rowReference;

  /// No description provided for @sectionPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get sectionPayment;

  /// No description provided for @rowMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get rowMethod;

  /// No description provided for @rowTaken.
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get rowTaken;

  /// No description provided for @nothingYetSettledAtVenue.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet — settled at the venue'**
  String get nothingYetSettledAtVenue;

  /// No description provided for @rowAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get rowAmount;

  /// No description provided for @rowStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get rowStatus;

  /// No description provided for @rowProviderReference.
  ///
  /// In en, this message translates to:
  /// **'Provider reference'**
  String get rowProviderReference;

  /// No description provided for @copyField.
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String copyField(String label);

  /// No description provided for @fieldCopied.
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String fieldCopied(String label);

  /// No description provided for @cannotConfirmUntilPaymentClearsLong.
  ///
  /// In en, this message translates to:
  /// **'This booking cannot be confirmed until the payment clears. Cancel it if the customer does not pay.'**
  String get cannotConfirmUntilPaymentClearsLong;

  /// No description provided for @youAreRoleHere.
  ///
  /// In en, this message translates to:
  /// **'{city} · you are {role} here'**
  String youAreRoleHere(String city, String role);

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @menuSubtitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Items, prices, and what is sold out'**
  String get menuSubtitleEdit;

  /// No description provided for @menuSubtitleStaff.
  ///
  /// In en, this message translates to:
  /// **'Mark items sold out'**
  String get menuSubtitleStaff;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @photosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What customers see of the room'**
  String get photosSubtitle;

  /// No description provided for @photosSubtitleViewOnly.
  ///
  /// In en, this message translates to:
  /// **'What customers see of the room (view only)'**
  String get photosSubtitleViewOnly;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening hours'**
  String get openingHours;

  /// No description provided for @openingHoursSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When the doors are open, including past midnight'**
  String get openingHoursSubtitle;

  /// No description provided for @venueDetails.
  ///
  /// In en, this message translates to:
  /// **'Venue details'**
  String get venueDetails;

  /// No description provided for @venueDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name, tagline, description, address'**
  String get venueDetailsSubtitle;

  /// No description provided for @branding.
  ///
  /// In en, this message translates to:
  /// **'Branding'**
  String get branding;

  /// No description provided for @brandingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How your venue looks to customers'**
  String get brandingSubtitle;

  /// No description provided for @whoHasAccess.
  ///
  /// In en, this message translates to:
  /// **'Who has access'**
  String get whoHasAccess;

  /// No description provided for @whoHasAccessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add people, change roles, remove access'**
  String get whoHasAccessSubtitle;

  /// No description provided for @managedByOwnerOrManager.
  ///
  /// In en, this message translates to:
  /// **'Opening hours, venue details and access are managed by an owner or manager.'**
  String get managedByOwnerOrManager;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get tuesday;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get wednesday;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get thursday;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get friday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get saturday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @onlyOwnerOrManagerCanChangeHours.
  ///
  /// In en, this message translates to:
  /// **'Only an owner or manager can change opening hours.'**
  String get onlyOwnerOrManagerCanChangeHours;

  /// No description provided for @saveWeek.
  ///
  /// In en, this message translates to:
  /// **'Save week'**
  String get saveWeek;

  /// No description provided for @hoursSaved.
  ///
  /// In en, this message translates to:
  /// **'Hours saved.'**
  String get hoursSaved;

  /// No description provided for @dayOpenButNoTimes.
  ///
  /// In en, this message translates to:
  /// **'{day} is open but has no times set.'**
  String dayOpenButNoTimes(String day);

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @opens.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get opens;

  /// No description provided for @opensAt.
  ///
  /// In en, this message translates to:
  /// **'Opens {time}'**
  String opensAt(String time);

  /// No description provided for @closes.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get closes;

  /// No description provided for @closesAt.
  ///
  /// In en, this message translates to:
  /// **'Closes {time}'**
  String closesAt(String time);

  /// No description provided for @runsPastMidnight.
  ///
  /// In en, this message translates to:
  /// **'Runs past midnight into the next morning.'**
  String get runsPastMidnight;

  /// No description provided for @takeAPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takeAPhoto;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @addACaption.
  ///
  /// In en, this message translates to:
  /// **'Add a caption'**
  String get addACaption;

  /// No description provided for @captionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional, e.g. \"The terrace at night\"'**
  String get captionHint;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @photoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo added.'**
  String get photoAdded;

  /// No description provided for @noPhotosYet.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get noPhotosYet;

  /// No description provided for @noPhotosDetailCanUpload.
  ///
  /// In en, this message translates to:
  /// **'Customers browse with their eyes. A few good photos of the room go a long way.'**
  String get noPhotosDetailCanUpload;

  /// No description provided for @noPhotosDetailViewOnly.
  ///
  /// In en, this message translates to:
  /// **'An owner or manager adds photos here.'**
  String get noPhotosDetailViewOnly;

  /// No description provided for @yourVenue.
  ///
  /// In en, this message translates to:
  /// **'Your venue'**
  String get yourVenue;

  /// No description provided for @brandingIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose how {venue} looks to customers. Each set has been checked for readability.'**
  String brandingIntro(String venue);

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @saveBranding.
  ///
  /// In en, this message translates to:
  /// **'Save branding'**
  String get saveBranding;

  /// No description provided for @savedLabel.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedLabel;

  /// No description provided for @brandingSaved.
  ///
  /// In en, this message translates to:
  /// **'Branding saved.'**
  String get brandingSaved;

  /// No description provided for @previewOpenUntil.
  ///
  /// In en, this message translates to:
  /// **'Open until 02:00'**
  String get previewOpenUntil;

  /// No description provided for @previewVenueLine.
  ///
  /// In en, this message translates to:
  /// **'Lounge · Conakry · 1.2 km away'**
  String get previewVenueLine;

  /// No description provided for @previewReserve.
  ///
  /// In en, this message translates to:
  /// **'Reserve'**
  String get previewReserve;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @noMenuYet.
  ///
  /// In en, this message translates to:
  /// **'No menu yet'**
  String get noMenuYet;

  /// No description provided for @noMenuDetailCanEdit.
  ///
  /// In en, this message translates to:
  /// **'Add your first item and customers will see it straight away.'**
  String get noMenuDetailCanEdit;

  /// No description provided for @noMenuDetailStaff.
  ///
  /// In en, this message translates to:
  /// **'A manager or owner adds items here.'**
  String get noMenuDetailStaff;

  /// No description provided for @staffCanMarkSoldOut.
  ///
  /// In en, this message translates to:
  /// **'You can mark items sold out. Adding and editing is done by a manager or owner.'**
  String get staffCanMarkSoldOut;

  /// No description provided for @soldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out'**
  String get soldOut;

  /// No description provided for @itemBackOn.
  ///
  /// In en, this message translates to:
  /// **'{name} is back on.'**
  String itemBackOn(String name);

  /// No description provided for @itemMarkedSoldOut.
  ///
  /// In en, this message translates to:
  /// **'{name} marked sold out.'**
  String itemMarkedSoldOut(String name);

  /// No description provided for @pictureAddedTo.
  ///
  /// In en, this message translates to:
  /// **'Picture added to {name}.'**
  String pictureAddedTo(String name);

  /// No description provided for @removeItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removeItemTitle(String name);

  /// No description provided for @removeItemDetail.
  ///
  /// In en, this message translates to:
  /// **'It disappears from the customer menu. To hide it temporarily, mark it sold out instead.'**
  String get removeItemDetail;

  /// No description provided for @itemRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed.'**
  String itemRemoved(String name);

  /// No description provided for @addAPicture.
  ///
  /// In en, this message translates to:
  /// **'Add a picture'**
  String get addAPicture;

  /// No description provided for @replacePicture.
  ///
  /// In en, this message translates to:
  /// **'Replace picture'**
  String get replacePicture;

  /// No description provided for @addAnItem.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get addAnItem;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get editItem;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @giveItAName.
  ///
  /// In en, this message translates to:
  /// **'Give it a name'**
  String get giveItAName;

  /// No description provided for @fieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get fieldCategory;

  /// No description provided for @categoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get categoryFood;

  /// No description provided for @categoryDrink.
  ///
  /// In en, this message translates to:
  /// **'Drink'**
  String get categoryDrink;

  /// No description provided for @categoryChicha.
  ///
  /// In en, this message translates to:
  /// **'Chicha flavour'**
  String get categoryChicha;

  /// No description provided for @fieldPriceGnf.
  ///
  /// In en, this message translates to:
  /// **'Price (GNF)'**
  String get fieldPriceGnf;

  /// No description provided for @giveItAPrice.
  ///
  /// In en, this message translates to:
  /// **'Give it a price'**
  String get giveItAPrice;

  /// No description provided for @numbersOnly.
  ///
  /// In en, this message translates to:
  /// **'Numbers only'**
  String get numbersOnly;

  /// No description provided for @fieldOneLineDescription.
  ///
  /// In en, this message translates to:
  /// **'One-line description (optional)'**
  String get fieldOneLineDescription;

  /// No description provided for @addSomeone.
  ///
  /// In en, this message translates to:
  /// **'Add someone'**
  String get addSomeone;

  /// No description provided for @fieldRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get fieldRole;

  /// No description provided for @roleStaffOption.
  ///
  /// In en, this message translates to:
  /// **'Staff — floor work'**
  String get roleStaffOption;

  /// No description provided for @roleManagerOption.
  ///
  /// In en, this message translates to:
  /// **'Manager — venue and profile'**
  String get roleManagerOption;

  /// No description provided for @roleOwnerOption.
  ///
  /// In en, this message translates to:
  /// **'Owner — everything'**
  String get roleOwnerOption;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'owner'**
  String get roleOwner;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'manager'**
  String get roleManager;

  /// No description provided for @roleStaff.
  ///
  /// In en, this message translates to:
  /// **'staff'**
  String get roleStaff;

  /// No description provided for @personAdded.
  ///
  /// In en, this message translates to:
  /// **'{name} added.'**
  String personAdded(String name);

  /// No description provided for @personIsNowRole.
  ///
  /// In en, this message translates to:
  /// **'{name} is now {role}.'**
  String personIsNowRole(String name, String role);

  /// No description provided for @removePersonTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removePersonTitle(String name);

  /// No description provided for @removePersonDetail.
  ///
  /// In en, this message translates to:
  /// **'They lose access to this venue immediately.'**
  String get removePersonDetail;

  /// No description provided for @personRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed.'**
  String personRemoved(String name);

  /// No description provided for @makeOwner.
  ///
  /// In en, this message translates to:
  /// **'Make owner'**
  String get makeOwner;

  /// No description provided for @makeManager.
  ///
  /// In en, this message translates to:
  /// **'Make manager'**
  String get makeManager;

  /// No description provided for @makeStaff.
  ///
  /// In en, this message translates to:
  /// **'Make staff'**
  String get makeStaff;

  /// No description provided for @removeAccess.
  ///
  /// In en, this message translates to:
  /// **'Remove access'**
  String get removeAccess;

  /// No description provided for @window7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get window7Days;

  /// No description provided for @window30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get window30Days;

  /// No description provided for @window90Days.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get window90Days;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to}'**
  String dateRange(String from, String to);

  /// No description provided for @collected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get collected;

  /// No description provided for @paymentCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payment} other{{count} payments}}'**
  String paymentCount(int count);

  /// No description provided for @awaiting.
  ///
  /// In en, this message translates to:
  /// **'Awaiting'**
  String get awaiting;

  /// No description provided for @pendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String pendingCount(int count);

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @failedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String failedCount(int count);

  /// No description provided for @sectionBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get sectionBookings;

  /// No description provided for @countTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get countTotal;

  /// No description provided for @sectionByPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'By payment method'**
  String get sectionByPaymentMethod;

  /// No description provided for @bookingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 booking} other{{count} bookings}}'**
  String bookingCount(int count);

  /// No description provided for @atTheTill.
  ///
  /// In en, this message translates to:
  /// **'at the till'**
  String get atTheTill;

  /// No description provided for @sectionNeedsChasing.
  ///
  /// In en, this message translates to:
  /// **'Needs chasing'**
  String get sectionNeedsChasing;

  /// No description provided for @nothingOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Nothing outstanding. Every booking is settled.'**
  String get nothingOutstanding;

  /// No description provided for @providerPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'{provider} payment failed'**
  String providerPaymentFailed(String provider);

  /// No description provided for @providerNotReceived.
  ///
  /// In en, this message translates to:
  /// **'{provider} not received'**
  String providerNotReceived(String provider);

  /// No description provided for @fieldTagline.
  ///
  /// In en, this message translates to:
  /// **'Tagline (one line)'**
  String get fieldTagline;

  /// No description provided for @fieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fieldDescription;

  /// No description provided for @fieldCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get fieldCity;

  /// No description provided for @fieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get fieldAddress;

  /// No description provided for @detailsSaved.
  ///
  /// In en, this message translates to:
  /// **'Details saved.'**
  String get detailsSaved;
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
