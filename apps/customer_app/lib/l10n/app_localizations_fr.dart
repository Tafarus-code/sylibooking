// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class LFr extends L {
  LFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Sylibooking';

  @override
  String get navBrowse => 'Explorer';

  @override
  String get navBookings => 'Réservations';

  @override
  String get navFavourites => 'Favoris';

  @override
  String get navProfile => 'Profil';

  @override
  String get greetingMorning => 'Bonjour';

  @override
  String get greetingAfternoon => 'Bon après-midi';

  @override
  String get greetingEvening => 'Bonsoir';

  @override
  String greetingWithName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get findATable => 'Trouver une table';

  @override
  String get searchByName => 'Rechercher par nom';

  @override
  String get filterAll => 'Tout';

  @override
  String get filterRestaurants => 'Restaurants';

  @override
  String get filterLounges => 'Salons';

  @override
  String get filterOpenNow => 'Ouvert';

  @override
  String get filterNearest => 'Au plus près';

  @override
  String get filterShowDistances => 'Voir les distances';

  @override
  String statusOpenUntil(String time) {
    return 'Ouvert jusqu\'à $time';
  }

  @override
  String get statusClosed => 'Fermé';

  @override
  String get statusHoursNotListed => 'Horaires non indiqués';

  @override
  String typeAndCity(String type, String city) {
    return '$type · $city';
  }

  @override
  String get couldNotLoadPlaces => 'Impossible de charger les établissements';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get nothingFound => 'Aucun résultat';

  @override
  String get nothingFoundDetail =>
      'Essayez un autre nom, ou retirez les filtres.';

  @override
  String get nothingOpenRightNow =>
      'Rien n\'est ouvert en ce moment. Retirez « Ouvert » pour voir les établissements où réserver plus tard.';

  @override
  String get showDistancesTitle => 'Afficher les distances ?';

  @override
  String get showDistancesBody =>
      'Sylibooking peut indiquer la distance de chaque établissement et trier par proximité. Votre position reste sur votre téléphone — elle n\'est envoyée ni à nous ni aux établissements.';

  @override
  String get notNow => 'Pas maintenant';

  @override
  String get allow => 'Autoriser';

  @override
  String get locationDenied =>
      'Aucun souci — la recherche fonctionne sans. Vous pourrez autoriser la position plus tard dans les réglages du téléphone.';

  @override
  String get locationServicesOff =>
      'La localisation est désactivée sur ce téléphone. Activez-la pour voir les distances.';

  @override
  String get locationUnavailable =>
      'Impossible d\'obtenir votre position pour l\'instant. Les distances ne sont pas disponibles.';

  @override
  String get getDirections => 'Itinéraire';

  @override
  String get noMapsApp => 'Aucune application de cartes sur ce téléphone.';

  @override
  String get saveToFavourites => 'Ajouter aux favoris';

  @override
  String get removeFromFavourites => 'Retirer des favoris';

  @override
  String get allWeek => 'Toute la semaine';

  @override
  String get hideWeek => 'Masquer la semaine';

  @override
  String get closedToday => 'Fermé aujourd\'hui';

  @override
  String seeAllReviews(int count) {
    return 'Voir les $count';
  }

  @override
  String get noReviewsAfterVisit =>
      'Aucun avis pour l\'instant — soyez le premier après votre visite.';

  @override
  String get lastSpaceFree => 'Dernière place à cette heure';

  @override
  String spacesFree(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places libres',
      one: '1 place libre',
    );
    return '$_temp0';
  }

  @override
  String get menu => 'Menu';

  @override
  String get orderAhead => 'Commander à l\'avance';

  @override
  String get reviews => 'Avis';

  @override
  String reviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count avis',
      one: '1 avis',
      zero: 'Aucun avis pour l\'instant',
    );
    return '$_temp0';
  }

  @override
  String get beTheFirstToReview => 'Soyez le premier à laisser un avis.';

  @override
  String get writeAReview => 'Écrire un avis';

  @override
  String get partySize => 'Nombre de personnes';

  @override
  String get day => 'Jour';

  @override
  String get availableTimes => 'Horaires disponibles';

  @override
  String nothingFreeForParty(int count) {
    return 'Rien de libre pour $count ce jour-là';
  }

  @override
  String get tryAnotherDay => 'Essayez un autre jour, ou un groupe plus petit.';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get tomorrow => 'Demain';

  @override
  String get bookATable => 'Réserver une table';

  @override
  String get yourName => 'Votre nom';

  @override
  String get phoneNumber => 'Numéro de téléphone';

  @override
  String get nameRequired =>
      'L\'établissement a besoin d\'un nom pour la réservation.';

  @override
  String get phoneRequired => 'Un numéro pour vous joindre.';

  @override
  String get phoneTooShort => 'Ce numéro semble trop court.';

  @override
  String get payment => 'Paiement';

  @override
  String get cashOnArrival => 'Espèces sur place';

  @override
  String get cashOnArrivalDetail => 'Payez à l\'établissement';

  @override
  String get orangeMoney => 'Orange Money';

  @override
  String get mtnMoney => 'MTN Mobile Money';

  @override
  String get payNowDetail => 'La table est retenue dès que le paiement aboutit';

  @override
  String get confirmBooking => 'Confirmer la réservation';

  @override
  String get payAndBook => 'Payer et réserver';

  @override
  String get booking => 'Réservation…';

  @override
  String get bookingConfirmedTitle => 'Table confirmée';

  @override
  String get bookingRequestedTitle => 'Réservation demandée';

  @override
  String get paymentFailedNothingCharged =>
      'Le paiement n\'a pas abouti, rien n\'a été débité. Votre réservation reste demandée — vous pouvez payer sur place.';

  @override
  String get waitingForPayment => 'En attente de votre paiement.';

  @override
  String get backToBrowsing => 'Retour à la recherche';

  @override
  String get myBookings => 'Mes réservations';

  @override
  String get tabBookings => 'Réservations';

  @override
  String get tabOrders => 'Commandes';

  @override
  String get noBookingsYet => 'Aucune réservation';

  @override
  String get noBookingsDetail => 'Réservez une table et elle apparaîtra ici.';

  @override
  String get cancelBooking => 'Annuler la réservation';

  @override
  String get cancelBookingTitle => 'Annuler cette réservation ?';

  @override
  String get cancelBookingBody =>
      'L\'établissement libérera la table pour quelqu\'un d\'autre.';

  @override
  String get keepIt => 'La garder';

  @override
  String get sharePhoto => 'Partager une photo';

  @override
  String get reviewYourVisit => 'Donner votre avis';

  @override
  String get noOrdersYet => 'Aucune commande';

  @override
  String get noOrdersDetail =>
      'Commandez à l\'avance dans un restaurant et la commande apparaîtra ici, avec son avancement pendant que la cuisine travaille.';

  @override
  String get couldNotLoadOrders => 'Impossible de charger vos commandes';

  @override
  String sectionActive(int count) {
    return 'En cours · $count';
  }

  @override
  String sectionPast(int count) {
    return 'Passées · $count';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return '$_temp0';
  }

  @override
  String get orderPlaced => 'Reçue';

  @override
  String get orderPreparing => 'En préparation';

  @override
  String get orderReady => 'Prête à récupérer';

  @override
  String get orderCollected => 'Récupérée';

  @override
  String get orderCancelled => 'Annulée';

  @override
  String get orderWaitingPayment => 'En attente de paiement';

  @override
  String get couldNotLoadMenu => 'Impossible de charger le menu';

  @override
  String get nothingToOrderYet => 'Rien à commander pour l\'instant';

  @override
  String get nothingToOrderDetail =>
      'Ce restaurant n\'a pas encore mis son menu en ligne. Vous pouvez toujours réserver une table et commander sur place.';

  @override
  String get add => 'Ajouter';

  @override
  String addNamed(String name) {
    return 'Ajouter $name';
  }

  @override
  String oneFewer(String name) {
    return 'Un $name de moins';
  }

  @override
  String oneMore(String name) {
    return 'Un $name de plus';
  }

  @override
  String tapToReview(String count) {
    return '$count · appuyez pour vérifier';
  }

  @override
  String get checkout => 'Commander';

  @override
  String get yourBasket => 'Votre panier';

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
      other: '$count plats',
      one: '1 plat',
    );
    return '$_temp0 · à récupérer au comptoir';
  }

  @override
  String get timedToYourBooking => 'Calé sur votre réservation de table';

  @override
  String get counterNeedsName => 'Le comptoir a besoin d\'un nom à appeler.';

  @override
  String get collectionTime => 'Heure de retrait';

  @override
  String get cashOnPickup => 'Espèces au retrait';

  @override
  String get cashOnPickupDetail => 'Payez au comptoir en récupérant';

  @override
  String get kitchenStartsWhenPaid =>
      'La cuisine commence dès que le paiement aboutit';

  @override
  String get placeOrder => 'Passer la commande';

  @override
  String get payAndOrder => 'Payer et commander';

  @override
  String get placing => 'Envoi…';

  @override
  String get yourOrder => 'Votre commande';

  @override
  String collectAt(String when) {
    return 'À récupérer $when';
  }

  @override
  String get progressPlaced => 'Reçue';

  @override
  String get progressPreparing => 'En préparation';

  @override
  String get progressReady => 'Prête';

  @override
  String get progressPlacedDetail => 'Le restaurant a votre commande';

  @override
  String get progressPreparingDetail => 'C\'est en cuisine';

  @override
  String get progressReadyDetail => 'À récupérer au comptoir';

  @override
  String get progressCollectedDetail => 'Récupérée. Bon appétit.';

  @override
  String get progressCancelledDetail => 'Cette commande a été annulée';

  @override
  String get whatYouOrdered => 'Votre commande';

  @override
  String waitingOnPaymentDetail(String provider) {
    return 'En attente de votre paiement $provider. La cuisine commence dès qu\'il aboutit.';
  }

  @override
  String get orderCancelledNothingOwed =>
      'Cette commande a été annulée. Rien n\'est dû.';

  @override
  String get favourites => 'Favoris';

  @override
  String get nothingSavedYet => 'Aucun favori';

  @override
  String get nothingSavedDetail =>
      'Appuyez sur le cœur d\'un établissement qui vous plaît et il vous attendra ici.';

  @override
  String get savedOnThisPhone =>
      'Enregistrés sur ce téléphone. Créez un compte depuis Profil et ils vous suivront sur le prochain.';

  @override
  String get couldNotLoadFavourites => 'Impossible de charger vos favoris';

  @override
  String get profile => 'Profil';

  @override
  String get makeAnAccount => 'Créer un compte';

  @override
  String get welcomeBack => 'Content de vous revoir';

  @override
  String get accountIsOptional =>
      'Ce n\'est pas obligatoire. Tout fonctionne sans — un compte garde simplement vos réservations et vos favoris si vous changez de téléphone.';

  @override
  String get whatShouldWeCallYou => 'Comment doit-on vous appeler ?';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get pickAUsername => 'Choisissez un nom d\'utilisateur.';

  @override
  String get password => 'Mot de passe';

  @override
  String get enterAPassword => 'Saisissez un mot de passe.';

  @override
  String get atLeast8Characters => 'Au moins 8 caractères.';

  @override
  String get phoneHelper =>
      'Pour retrouver votre compte si vous oubliez le mot de passe';

  @override
  String get emailOptional => 'E-mail (facultatif)';

  @override
  String get emailLooksWrong => 'Cet e-mail semble incorrect.';

  @override
  String get createAccount => 'Créer le compte';

  @override
  String get signIn => 'Se connecter';

  @override
  String get justAMoment => 'Un instant…';

  @override
  String get iAlreadyHaveAnAccount => 'J\'ai déjà un compte';

  @override
  String get iNeedAnAccount => 'Je veux créer un compte';

  @override
  String get iForgotMyPassword => 'J\'ai oublié mon mot de passe';

  @override
  String get signedInEverythingSaved =>
      'Connecté. Tout ce qui est sur ce téléphone est enregistré.';

  @override
  String get accountKeepsEverything =>
      'Vos réservations, commandes et favoris sont enregistrés sur ce compte. Connectez-vous sur un autre téléphone et ils vous suivent.';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutKeepsPhone =>
      'La déconnexion laisse ce téléphone comme avant — rien n\'est supprimé.';

  @override
  String get noWayBackIn =>
      'Ce compte n\'a ni numéro ni e-mail : un mot de passe oublié ne pourra pas être réinitialisé.';

  @override
  String get forgottenPassword => 'Mot de passe oublié';

  @override
  String get getACode => 'Recevoir un code';

  @override
  String get enterTheCode => 'Saisir le code';

  @override
  String get getACodeDetail =>
      'Indiquez votre nom d\'utilisateur, votre numéro ou votre e-mail et nous enverrons un code à ce que nous avons au dossier.';

  @override
  String codeSentTo(String destination) {
    return 'Nous avons envoyé un code à six chiffres à $destination. Il est valable 15 minutes.';
  }

  @override
  String get identifierLabel => 'Nom d\'utilisateur, numéro ou e-mail';

  @override
  String get identifierRequired =>
      'Saisissez votre nom d\'utilisateur, numéro ou e-mail.';

  @override
  String get sixDigitCode => 'Code à six chiffres';

  @override
  String get codeIsSixDigits => 'Le code fait six chiffres.';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get sendMeACode => 'Envoyez-moi un code';

  @override
  String get changeMyPassword => 'Changer mon mot de passe';

  @override
  String get sendAnotherCode => 'Envoyer un autre code';

  @override
  String get newCodeCancelsLast =>
      'Demander un nouveau code annule le précédent.';

  @override
  String cancelBookingWhen(String when) {
    return '$when.\n\nLa table repart aux autres clients, vous risquez de ne pas la retrouver.';
  }

  @override
  String get bookingCancelled => 'Réservation annulée.';

  @override
  String get reviewIsLive => 'Merci — votre avis est en ligne.';

  @override
  String get addACaption => 'Ajouter une légende';

  @override
  String get optional => 'Facultatif';

  @override
  String get cancel => 'Annuler';

  @override
  String get share => 'Partager';

  @override
  String get photoShared => 'Merci — votre photo est partagée.';

  @override
  String get noBookingsOnThisPhone =>
      'Les réservations faites sur ce téléphone apparaissent ici.';

  @override
  String paymentFailedShort(String provider) {
    return '$provider · paiement échoué';
  }

  @override
  String paymentPendingShort(String provider) {
    return '$provider · paiement en attente';
  }

  @override
  String get addAPhoto => 'Ajouter une photo';

  @override
  String get nameRequiredBooking =>
      'L\'établissement a besoin d\'un nom pour la réservation';

  @override
  String get phoneRequiredBooking =>
      'L\'établissement appellera pour confirmer';

  @override
  String get phoneTooShortBooking => 'Ce numéro semble trop court';

  @override
  String get howWouldYouLikeToPay => 'Comment souhaitez-vous payer ?';

  @override
  String get payOnArrival => 'Payer sur place';

  @override
  String get payOnArrivalDetail =>
      'Rien n\'est débité maintenant. L\'établissement confirme votre table.';

  @override
  String get payDepositDetail =>
      'Payez un acompte maintenant — votre table est confirmée immédiatement.';

  @override
  String get payAndReserve => 'Payer et réserver';

  @override
  String get reserve => 'Réserver';

  @override
  String get requestSent => 'Demande envoyée';

  @override
  String willConfirmShortly(String venue, String phone) {
    return '$venue confirmera sous peu. On pourra vous appeler au $phone.';
  }

  @override
  String get tableConfirmed => 'Table confirmée';

  @override
  String paidAndConfirmed(String venue) {
    return 'Payé et confirmé chez $venue. Présentez cette référence à votre arrivée.';
  }

  @override
  String get paymentDidNotGoThrough => 'Le paiement n\'a pas abouti';

  @override
  String stillHeldAsRequest(String venue) {
    return 'Votre table reste retenue en demande. $venue la confirmera, ou vous pourrez payer sur place.';
  }

  @override
  String get stillWaitingOnPayment => 'Toujours en attente du paiement';

  @override
  String get waitingForPaymentTitle => 'En attente du paiement';

  @override
  String get notComeThroughYet =>
      'Il n\'est pas encore arrivé. Regardez Mes réservations dans un moment — la table est retenue dans tous les cas.';

  @override
  String get approveOnYourPhone =>
      'Validez le paiement sur votre téléphone. La page se met à jour toute seule.';

  @override
  String get booked => 'Réservé';

  @override
  String get bookingLabel => 'Réservation';

  @override
  String get reference => 'Référence';

  @override
  String get paidWith => 'Payé avec';

  @override
  String get chooseARating => 'Choisissez une note de 1 à 5.';

  @override
  String get howWasIt => 'Comment était-ce ?';

  @override
  String get anythingToAdd => 'Un commentaire ? (facultatif)';

  @override
  String get postReview => 'Publier l\'avis';

  @override
  String get onlyFirstNameShown => 'Seul votre prénom est affiché.';

  @override
  String get language => 'Langue';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get backToPhotos => 'Retour aux photos';

  @override
  String photoOf(int index, int total) {
    return '$index sur $total';
  }

  @override
  String get previousPhoto => 'Photo précédente';

  @override
  String get nextPhoto => 'Photo suivante';

  @override
  String get photoCouldNotLoad => 'Cette photo n\'a pas pu être chargée';
}
