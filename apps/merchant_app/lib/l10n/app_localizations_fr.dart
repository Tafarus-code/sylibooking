// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class LFr extends L {
  LFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Sylibooking Commerçant';

  @override
  String get merchant => 'Commerçant';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get keepIt => 'Garder';

  @override
  String get keep => 'Garder';

  @override
  String get remove => 'Supprimer';

  @override
  String get add => 'Ajouter';

  @override
  String get edit => 'Modifier';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get refresh => 'Actualiser';

  @override
  String get required => 'Obligatoire';

  @override
  String get language => 'Langue';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get enterYourUsername => 'Entrez votre nom d\'utilisateur';

  @override
  String get enterYourPassword => 'Entrez votre mot de passe';

  @override
  String get showPassword => 'Afficher';

  @override
  String get hidePassword => 'Masquer';

  @override
  String get wrongUsernameOrPassword =>
      'Nom d\'utilisateur ou mot de passe incorrect.';

  @override
  String get navReservations => 'Réservations';

  @override
  String get navPayments => 'Paiements';

  @override
  String get navManage => 'Gérer';

  @override
  String get tabReservations => 'Réservations';

  @override
  String get tabOrders => 'Commandes';

  @override
  String get switchVenue => 'Changer d\'établissement';

  @override
  String get noVenue => 'Aucun établissement';

  @override
  String get chooseAVenue => 'Choisir un établissement';

  @override
  String get keepCurrentVenue => 'Garder l\'établissement actuel';

  @override
  String get everythingAppliesToVenue =>
      'Tout ce que vous ferez ensuite s\'applique à l\'établissement choisi.';

  @override
  String get noVenueYet => 'Aucun établissement';

  @override
  String get noVenueYetDetail =>
      'Créez votre propre établissement pour commencer à prendre des réservations, ou demandez à un propriétaire de vous ajouter au sien.';

  @override
  String get rangeToday => 'Aujourd\'hui';

  @override
  String get rangeNextSevenDays => '7 prochains jours';

  @override
  String get dayToday => 'Aujourd\'hui';

  @override
  String get dayTomorrow => 'Demain';

  @override
  String get couldNotLoadReservations =>
      'Impossible de charger les réservations';

  @override
  String get noVenueAssigned => 'Aucun établissement attribué';

  @override
  String get noVenueAssignedDetail =>
      'Ce compte ne fait encore partie du personnel d\'aucun établissement, il n\'y a donc rien à afficher. Un administrateur peut en attribuer un.';

  @override
  String get nothingBookedToday => 'Aucune réservation aujourd\'hui';

  @override
  String get nothingBookedThisWeek => 'Aucune réservation cette semaine';

  @override
  String get newReservationsAppearHere =>
      'Les nouvelles réservations apparaissent ici au fur et à mesure.';

  @override
  String get cancelThisReservation => 'Annuler cette réservation ?';

  @override
  String cancelReservationDetail(String name, String space, String time) {
    return '$name · $space à $time.\n\nLe créneau redevient réservable.';
  }

  @override
  String get cancelBooking => 'Annuler la réservation';

  @override
  String get reservationCancelled => 'Réservation annulée.';

  @override
  String get reservationConfirmed => 'Réservation confirmée.';

  @override
  String get confirm => 'Confirmer';

  @override
  String guestCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes',
      one: '1 personne',
    );
    return '$_temp0';
  }

  @override
  String get cannotConfirmUntilPaymentClears =>
      'Impossible de confirmer tant que le paiement n\'est pas abouti.';

  @override
  String get statusPending => 'En attente';

  @override
  String get statusConfirmed => 'Confirmée';

  @override
  String get statusCancelled => 'Annulée';

  @override
  String get statusCompleted => 'Terminée';

  @override
  String get statusUnknown => 'Inconnu';

  @override
  String paidWith(String provider) {
    return 'Payé ($provider)';
  }

  @override
  String get mobileMoney => 'mobile money';

  @override
  String paymentFailedWith(String provider) {
    return 'Paiement échoué ($provider)';
  }

  @override
  String awaitingPaymentWith(String provider) {
    return 'Paiement en attente ($provider)';
  }

  @override
  String get paymentFailedShort => 'Paiement échoué';

  @override
  String get unpaid => 'Impayé';

  @override
  String get cashOnArrival => 'Espèces sur place';

  @override
  String get cashShort => 'Espèces';

  @override
  String get stageReadyToCollect => 'Prêtes à emporter';

  @override
  String get stageBeingPrepared => 'En préparation';

  @override
  String get stageNewOrders => 'Nouvelles commandes';

  @override
  String stageHeading(String label, int count) {
    return '$label · $count';
  }

  @override
  String get couldNotLoadTheQueue => 'Impossible de charger la file';

  @override
  String get noVenueSelected => 'Aucun établissement sélectionné';

  @override
  String get pickAVenueForQueue =>
      'Choisissez un établissement pour voir sa file de cuisine.';

  @override
  String get nothingInTheQueue => 'Rien dans la file';

  @override
  String get ordersLandHere =>
      'Les commandes du jour arrivent ici au fur et à mesure.';

  @override
  String get cancelThisOrder => 'Annuler cette commande ?';

  @override
  String cancelOrderDetail(String name) {
    return '$name ne pourra pas la récupérer, et rien ne sera dû.';
  }

  @override
  String get cancelOrder => 'Annuler la commande';

  @override
  String get startPreparing => 'Commencer la préparation';

  @override
  String get markReady => 'Marquer prête';

  @override
  String get markCollected => 'Récupérée';

  @override
  String get moveOn => 'Étape suivante';

  @override
  String get atTheirTable => 'À leur table';

  @override
  String get orderPlaced => 'Reçue';

  @override
  String get orderPreparing => 'En préparation';

  @override
  String get orderReady => 'Prête';

  @override
  String get orderCollected => 'Récupérée';

  @override
  String get orderCancelled => 'Annulée';

  @override
  String get orderUnknown => 'Inconnu';

  @override
  String waitingOnPayment(String provider) {
    return 'En attente du paiement $provider. La cuisine ne peut pas commencer avant qu\'il aboutisse.';
  }

  @override
  String get cashOnPickup => 'Espèces au retrait';

  @override
  String amountGnf(String amount) {
    return '$amount GNF';
  }

  @override
  String get reservationTitle => 'Réservation';

  @override
  String get sectionBooking => 'La réservation';

  @override
  String get rowWhen => 'Quand';

  @override
  String get rowSpace => 'Espace';

  @override
  String get rowParty => 'Personnes';

  @override
  String get rowPhone => 'Téléphone';

  @override
  String get rowReference => 'Référence';

  @override
  String get sectionPayment => 'Paiement';

  @override
  String get rowMethod => 'Moyen';

  @override
  String get rowTaken => 'Encaissé';

  @override
  String get nothingYetSettledAtVenue =>
      'Rien pour l\'instant — réglé sur place';

  @override
  String get rowAmount => 'Montant';

  @override
  String get rowStatus => 'Statut';

  @override
  String get rowProviderReference => 'Référence opérateur';

  @override
  String copyField(String label) {
    return 'Copier : $label';
  }

  @override
  String fieldCopied(String label) {
    return '$label copié';
  }

  @override
  String get cannotConfirmUntilPaymentClearsLong =>
      'Cette réservation ne peut pas être confirmée tant que le paiement n\'a pas abouti. Annulez-la si le client ne paie pas.';

  @override
  String youAreRoleHere(String city, String role) {
    return '$city · vous y êtes $role';
  }

  @override
  String get menu => 'Menu';

  @override
  String get menuSubtitleEdit => 'Articles, prix et ruptures';

  @override
  String get menuSubtitleStaff => 'Signaler les ruptures';

  @override
  String get photos => 'Photos';

  @override
  String get photosSubtitle => 'Ce que les clients voient de la salle';

  @override
  String get photosSubtitleViewOnly =>
      'Ce que les clients voient de la salle (lecture seule)';

  @override
  String get openingHours => 'Heures d\'ouverture';

  @override
  String get openingHoursSubtitle =>
      'Quand vous ouvrez, y compris après minuit';

  @override
  String get venueDetails => 'Détails de l\'établissement';

  @override
  String get venueDetailsSubtitle => 'Nom, slogan, description, adresse';

  @override
  String get branding => 'Identité visuelle';

  @override
  String get brandingSubtitle =>
      'L\'allure de votre établissement pour les clients';

  @override
  String get whoHasAccess => 'Qui a accès';

  @override
  String get whoHasAccessSubtitle =>
      'Ajouter des personnes, changer les rôles, retirer l\'accès';

  @override
  String get managedByOwnerOrManager =>
      'Les heures d\'ouverture, les détails de l\'établissement et les accès sont gérés par un propriétaire ou un gérant.';

  @override
  String get monday => 'Lundi';

  @override
  String get tuesday => 'Mardi';

  @override
  String get wednesday => 'Mercredi';

  @override
  String get thursday => 'Jeudi';

  @override
  String get friday => 'Vendredi';

  @override
  String get saturday => 'Samedi';

  @override
  String get sunday => 'Dimanche';

  @override
  String get onlyOwnerOrManagerCanChangeHours =>
      'Seul un propriétaire ou un gérant peut modifier les heures d\'ouverture.';

  @override
  String get saveWeek => 'Enregistrer la semaine';

  @override
  String get hoursSaved => 'Heures enregistrées.';

  @override
  String dayOpenButNoTimes(String day) {
    return '$day est ouvert mais aucune heure n\'est renseignée.';
  }

  @override
  String get closed => 'Fermé';

  @override
  String get open => 'Ouvert';

  @override
  String get opens => 'Ouvre';

  @override
  String opensAt(String time) {
    return 'Ouvre à $time';
  }

  @override
  String get closes => 'Ferme';

  @override
  String closesAt(String time) {
    return 'Ferme à $time';
  }

  @override
  String get runsPastMidnight => 'Se poursuit après minuit, jusqu\'au matin.';

  @override
  String get takeAPhoto => 'Prendre une photo';

  @override
  String get addPhoto => 'Ajouter une photo';

  @override
  String get addACaption => 'Ajouter une légende';

  @override
  String get captionHint => 'Facultatif, ex. « La terrasse le soir »';

  @override
  String get upload => 'Envoyer';

  @override
  String get photoAdded => 'Photo ajoutée.';

  @override
  String get noPhotosYet => 'Aucune photo';

  @override
  String get noPhotosDetailCanUpload =>
      'Les clients choisissent avec les yeux. Quelques bonnes photos de la salle changent tout.';

  @override
  String get noPhotosDetailViewOnly =>
      'Un propriétaire ou un gérant ajoute les photos ici.';

  @override
  String get yourVenue => 'Votre établissement';

  @override
  String brandingIntro(String venue) {
    return 'Choisissez l\'allure de $venue pour les clients. Chaque ensemble a été vérifié pour la lisibilité.';
  }

  @override
  String get preview => 'Aperçu';

  @override
  String get saveBranding => 'Enregistrer l\'identité';

  @override
  String get savedLabel => 'Enregistré';

  @override
  String get brandingSaved => 'Identité visuelle enregistrée.';

  @override
  String get previewOpenUntil => 'Ouvert jusqu\'à 02:00';

  @override
  String get previewVenueLine => 'Salon · Conakry · à 1,2 km';

  @override
  String get previewReserve => 'Réserver';

  @override
  String get addItem => 'Ajouter un article';

  @override
  String get noMenuYet => 'Aucun menu';

  @override
  String get noMenuDetailCanEdit =>
      'Ajoutez votre premier article et les clients le verront aussitôt.';

  @override
  String get noMenuDetailStaff =>
      'Un gérant ou un propriétaire ajoute les articles ici.';

  @override
  String get staffCanMarkSoldOut =>
      'Vous pouvez signaler les ruptures. L\'ajout et la modification reviennent à un gérant ou à un propriétaire.';

  @override
  String get soldOut => 'En rupture';

  @override
  String itemBackOn(String name) {
    return '$name est de nouveau disponible.';
  }

  @override
  String itemMarkedSoldOut(String name) {
    return '$name signalé en rupture.';
  }

  @override
  String pictureAddedTo(String name) {
    return 'Photo ajoutée à $name.';
  }

  @override
  String removeItemTitle(String name) {
    return 'Supprimer $name ?';
  }

  @override
  String get removeItemDetail =>
      'L\'article disparaît du menu des clients. Pour le masquer temporairement, signalez-le plutôt en rupture.';

  @override
  String itemRemoved(String name) {
    return '$name supprimé.';
  }

  @override
  String get addAPicture => 'Ajouter une photo';

  @override
  String get replacePicture => 'Remplacer la photo';

  @override
  String get addAnItem => 'Ajouter un article';

  @override
  String get editItem => 'Modifier l\'article';

  @override
  String get fieldName => 'Nom';

  @override
  String get giveItAName => 'Donnez-lui un nom';

  @override
  String get fieldCategory => 'Catégorie';

  @override
  String get categoryFood => 'Plats';

  @override
  String get categoryDrink => 'Boissons';

  @override
  String get categoryChicha => 'Parfums chicha';

  @override
  String get fieldPriceGnf => 'Prix (GNF)';

  @override
  String get giveItAPrice => 'Donnez-lui un prix';

  @override
  String get numbersOnly => 'Chiffres uniquement';

  @override
  String get fieldOneLineDescription => 'Description en une ligne (facultatif)';

  @override
  String get addSomeone => 'Ajouter quelqu\'un';

  @override
  String get fieldRole => 'Rôle';

  @override
  String get roleStaffOption => 'Personnel — service en salle';

  @override
  String get roleManagerOption => 'Gérant — établissement et profil';

  @override
  String get roleOwnerOption => 'Propriétaire — tout';

  @override
  String get roleOwner => 'propriétaire';

  @override
  String get roleManager => 'gérant';

  @override
  String get roleStaff => 'personnel';

  @override
  String get roleOwnerName => 'Propriétaire';

  @override
  String get roleManagerName => 'Gérant';

  @override
  String get roleStaffName => 'Personnel';

  @override
  String personAdded(String name) {
    return '$name ajouté.';
  }

  @override
  String personIsNowRole(String name, String role) {
    return '$name est maintenant $role.';
  }

  @override
  String removePersonTitle(String name) {
    return 'Retirer $name ?';
  }

  @override
  String get removePersonDetail =>
      'Cette personne perd l\'accès à cet établissement immédiatement.';

  @override
  String personRemoved(String name) {
    return '$name retiré.';
  }

  @override
  String get makeOwner => 'Nommer propriétaire';

  @override
  String get makeManager => 'Nommer gérant';

  @override
  String get makeStaff => 'Nommer personnel';

  @override
  String get removeAccess => 'Retirer l\'accès';

  @override
  String get window7Days => '7 jours';

  @override
  String get window30Days => '30 jours';

  @override
  String get window90Days => '90 jours';

  @override
  String dateRange(String from, String to) {
    return '$from – $to';
  }

  @override
  String get collected => 'Encaissé';

  @override
  String paymentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paiements',
      one: '1 paiement',
    );
    return '$_temp0';
  }

  @override
  String get awaiting => 'En attente';

  @override
  String pendingCount(int count) {
    return '$count en attente';
  }

  @override
  String get failed => 'Échoués';

  @override
  String failedCount(int count) {
    return '$count échoués';
  }

  @override
  String get sectionBookings => 'Réservations';

  @override
  String get countTotal => 'Total';

  @override
  String get sectionByPaymentMethod => 'Par moyen de paiement';

  @override
  String bookingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count réservations',
      one: '1 réservation',
    );
    return '$_temp0';
  }

  @override
  String get atTheTill => 'à la caisse';

  @override
  String get sectionNeedsChasing => 'À relancer';

  @override
  String get nothingOutstanding =>
      'Rien en souffrance. Toutes les réservations sont réglées.';

  @override
  String providerPaymentFailed(String provider) {
    return 'Paiement $provider échoué';
  }

  @override
  String providerNotReceived(String provider) {
    return 'Paiement $provider non reçu';
  }

  @override
  String get fieldTagline => 'Slogan (une ligne)';

  @override
  String get fieldDescription => 'Description';

  @override
  String get fieldCity => 'Ville';

  @override
  String get fieldAddress => 'Adresse';

  @override
  String get detailsSaved => 'Détails enregistrés.';

  @override
  String get tablesAndRooms => 'Tables et salons';

  @override
  String get tablesAndRoomsSubtitle => 'Où vos clients s’assoient vraiment';

  @override
  String get noSpacesYet => 'Aucune table';

  @override
  String get noSpacesDetail =>
      'Un établissement a besoin de places assises avant de pouvoir prendre une réservation. Ajoutez votre première table pour commencer.';

  @override
  String get addSpace => 'Ajouter une table';

  @override
  String get editSpace => 'Modifier';

  @override
  String get spaceName => 'Nom';

  @override
  String get spaceNameHint => 'Le nom utilisé en salle, ex. « Table 4 »';

  @override
  String get spaceType => 'Type';

  @override
  String get spaceTypeTable => 'Table';

  @override
  String get spaceTypeVipRoom => 'Salon VIP';

  @override
  String get spaceTypeTerrace => 'Terrasse';

  @override
  String get spaceCapacity => 'Places';

  @override
  String get spaceCapacityHint => 'Nombre maximum de clients';

  @override
  String spaceSeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
    );
    return '$_temp0';
  }

  @override
  String get spaceRetired => 'Hors service';

  @override
  String spaceSaved(String name) {
    return '$name enregistrée.';
  }

  @override
  String removeSpaceTitle(String name) {
    return 'Supprimer $name ?';
  }

  @override
  String get removeSpaceDetail => 'Elle cesse immédiatement d’être réservable.';

  @override
  String get removeSpaceKeepsHistory =>
      'Les réservations déjà prises dessus sont conservées et restent consultables — la table est mise hors service, pas effacée.';

  @override
  String spaceDeleted(String name) {
    return '$name supprimée.';
  }

  @override
  String spaceRetiredNotice(String name) {
    return '$name est hors service. Ses réservations passées sont conservées.';
  }

  @override
  String get bringSpaceBack => 'Remettre en service';

  @override
  String spaceBroughtBack(String name) {
    return '$name est de nouveau réservable.';
  }

  @override
  String get seatsAtLeastOne => 'Une table accueille au moins un client.';

  @override
  String get createVenue => 'Créer votre établissement';

  @override
  String get newVenue => 'Nouvel établissement';

  @override
  String get createVenueIntro =>
      'L’essentiel seulement. Les heures, le menu, les photos et l’identité visuelle ont chacun leur écran une fois qu’il existe.';

  @override
  String get venueKind => 'Type';

  @override
  String get venueKindLounge => 'Salon';

  @override
  String get venueKindRestaurant => 'Restaurant';

  @override
  String get createVenueCta => 'Créer l’établissement';

  @override
  String venueCreated(String name) {
    return '$name est à vous. Ajoutez vos tables ensuite.';
  }

  @override
  String get markArrived => 'Marquer arrivé';

  @override
  String guestsArrived(String name) {
    return '$name marqué comme arrivé.';
  }

  @override
  String get statusMissed => 'Absent';

  @override
  String get rowDepositOutcome => 'Acompte';

  @override
  String get depositNotSettled => 'Pas encore réglé';

  @override
  String get depositOffset => 'Déduit de l’addition';

  @override
  String get depositForfeited => 'Conservé — personne ne s’est présenté';

  @override
  String get depositRefunded => 'Remboursé';

  @override
  String get keptFromNoShows => 'Conservé sur absences';

  @override
  String get offsetAgainstBills => 'Déduit des additions';

  @override
  String depositCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count acomptes',
      one: '1 acompte',
    );
    return '$_temp0';
  }

  @override
  String get refundDeposit => 'Rendre l’acompte';

  @override
  String refundDepositTitle(String amount) {
    return 'Rendre $amount GNF ?';
  }

  @override
  String get refundDepositDetail =>
      'La réservation reste marquée absente — la table a été gardée puis perdue, et le registre doit le dire. Seul l’argent est rendu.';

  @override
  String get depositRefundedNotice => 'Acompte rendu.';

  @override
  String get returnedToCustomers => 'Rendu';
}
