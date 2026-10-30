// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Terrain GN';

  @override
  String get tabListings => 'Terrains';

  @override
  String get tabMine => 'Mes terrains';

  @override
  String get tabAccount => 'Compte';

  @override
  String get allRegions => 'Toutes les régions';

  @override
  String get verifiedBadge => 'Vérifié';

  @override
  String verifiedOn(String date) {
    return 'Vérifié sur le terrain par un agent le $date';
  }

  @override
  String get pendingVerification => 'En attente de vérification terrain';

  @override
  String get statusPending => 'En vérification';

  @override
  String get statusVerified => 'Publié';

  @override
  String get statusReserved => 'Réservé';

  @override
  String get statusSold => 'Vendu';

  @override
  String get statusRejected => 'Refusé';

  @override
  String get statusWithdrawn => 'Retiré';

  @override
  String get emptyListings => 'Aucun terrain vérifié ici pour le moment.';

  @override
  String get retry => 'Réessayer';

  @override
  String get networkError =>
      'Pas de connexion. Vérifiez votre réseau et réessayez.';

  @override
  String genericError(String code) {
    return 'Une erreur est survenue ($code).';
  }

  @override
  String get plotCode => 'N° de parcelle';

  @override
  String get location => 'Emplacement';

  @override
  String get area => 'Superficie';

  @override
  String get price => 'Prix';

  @override
  String get deposit => 'Acompte de réservation';

  @override
  String get openInMaps => 'Ouvrir dans Maps';

  @override
  String get contactSeller => 'Contacter le vendeur';

  @override
  String get whatsappSheetTitle => 'Continuer sur WhatsApp';

  @override
  String get whatsappSheetBody =>
      'WhatsApp va s\'ouvrir avec ce résumé prêt à être envoyé au vendeur.';

  @override
  String get connectWhatsapp => 'Contacter via WhatsApp';

  @override
  String get cancel => 'Annuler';

  @override
  String get whatsappSafety =>
      'N\'envoyez jamais d\'argent hors d\'une réservation vérifiée par un agent.';

  @override
  String get whatsappUnavailable => 'Impossible d\'ouvrir WhatsApp.';

  @override
  String get signInTitle => 'Connexion';

  @override
  String get signInToContinue =>
      'Connectez-vous pour contacter les vendeurs et publier vos terrains.';

  @override
  String get phoneLabel => 'Numéro de téléphone';

  @override
  String get phoneInvalid =>
      'Saisissez votre numéro avec l\'indicatif, ex. +224…';

  @override
  String get sendCodeSms => 'Recevoir le code par SMS';

  @override
  String get sendCodeWhatsapp => 'Recevoir le code sur WhatsApp';

  @override
  String get codeLabel => 'Code à 6 chiffres';

  @override
  String codeSentTo(String phone) {
    return 'Code envoyé au $phone';
  }

  @override
  String get verifyCode => 'Confirmer';

  @override
  String get otpInvalid => 'Code incorrect ou expiré.';

  @override
  String get rateLimited =>
      'Trop de tentatives. Patientez une minute et réessayez.';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get language => 'Langue';

  @override
  String get myParcelsEmpty => 'Vous n\'avez encore publié aucun terrain.';

  @override
  String get addParcel => 'Publier un terrain';

  @override
  String get submitTitle => 'Nouveau terrain';

  @override
  String get fieldTitle => 'Titre de l\'annonce';

  @override
  String get fieldRegion => 'Région';

  @override
  String get fieldPrefecture => 'Préfecture';

  @override
  String get fieldLocality => 'Quartier ou village';

  @override
  String get fieldPrice => 'Prix (GNF)';

  @override
  String get fieldTitleRef => 'N° de titre foncier ou permis (facultatif)';

  @override
  String get required => 'Obligatoire';

  @override
  String get boundaryTitle => 'Bornes du terrain';

  @override
  String get boundaryHelp =>
      'Placez-vous sur chaque borne et ajoutez votre position, ou saisissez les coordonnées du plan de bornage, dans l\'ordre autour du terrain.';

  @override
  String get addCornerGps => 'Ajouter ma position';

  @override
  String get addCornerManual => 'Saisir des coordonnées';

  @override
  String cornerN(int n) {
    return 'Borne $n';
  }

  @override
  String gpsAccuracy(int meters) {
    return '±$meters m';
  }

  @override
  String get coordinateSystem => 'Système de coordonnées';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get easting => 'X (est)';

  @override
  String get northing => 'Y (nord)';

  @override
  String get add => 'Ajouter';

  @override
  String get checkBoundary => 'Vérifier les limites';

  @override
  String boundaryOk(String area) {
    return 'Limites valides : $area m², aucune revendication concurrente.';
  }

  @override
  String boundaryBlocked(String code, String m2) {
    return 'Chevauche la parcelle $code sur $m2 m². Ce terrain est déjà revendiqué.';
  }

  @override
  String boundarySoft(String code, String m2) {
    return 'Empiète de $m2 m² sur la parcelle $code. Un agent vérifiera sur place.';
  }

  @override
  String get problemInvalid =>
      'Les bornes se croisent. Ajoutez-les dans l\'ordre autour du terrain.';

  @override
  String get problemOutside => 'Ces limites sont hors de Guinée.';

  @override
  String get problemArea =>
      'La superficie doit être comprise entre 50 m² et 500 ha.';

  @override
  String get problemCorners => 'Ajoutez entre 3 et 200 bornes.';

  @override
  String get duplicateTitleRef =>
      'Ce numéro de titre est déjà utilisé par une autre annonce.';

  @override
  String get submit => 'Envoyer pour vérification';

  @override
  String get submitted =>
      'Envoyé. Un agent terrain visitera le terrain avant sa publication.';

  @override
  String get addPhotos => 'Ajouter des photos';

  @override
  String get addTitleDeed => 'Photo du titre foncier';

  @override
  String get uploading => 'Envoi en cours…';

  @override
  String uploadedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers envoyés',
      one: '1 fichier envoyé',
      zero: 'Aucun fichier envoyé',
    );
    return '$_temp0';
  }

  @override
  String get done => 'Terminer';

  @override
  String get locationDenied =>
      'Autorisez l\'accès à la position pour ajouter votre position.';

  @override
  String get withdraw => 'Retirer l\'annonce';

  @override
  String rejectedReason(String reason) {
    return 'Refusé : $reason';
  }

  @override
  String get parcelLocked => 'Ce terrain ne peut plus être modifié.';

  @override
  String reserve(String amount) {
    return 'Réserver avec un acompte de $amount';
  }

  @override
  String get reserveTitle => 'Réserver ce terrain';

  @override
  String get reserveExplain =>
      'Votre acompte est encaissé par CinetPay et conservé jusqu\'à la validation de la vente par notre équipe. Le vendeur ne le reçoit pas directement.';

  @override
  String get payDeposit => 'Payer l\'acompte par Mobile Money';

  @override
  String get openPayment => 'Ouvrir la page de paiement';

  @override
  String get checkPayment => 'J\'ai payé, vérifier';

  @override
  String get reservationPending => 'En attente de votre paiement…';

  @override
  String get reservationHeld =>
      'Acompte sécurisé. Le terrain vous est réservé.';

  @override
  String get reservationFailed =>
      'Le paiement n\'a pas abouti. Vous pouvez réessayer.';

  @override
  String get reservationExpired =>
      'Le délai de paiement est écoulé. Vous pouvez recommencer.';

  @override
  String get reservationReview =>
      'Paiement reçu. Notre équipe le vérifie et vous contactera.';

  @override
  String get reservationReleased => 'Vente finalisée.';

  @override
  String get reservationRefunded => 'Acompte remboursé.';

  @override
  String get parcelNotAvailable =>
      'Ce terrain n\'est plus disponible à la réservation.';

  @override
  String get paymentsUnavailable =>
      'Le paiement n\'est pas encore disponible. Contactez le vendeur sur WhatsApp.';

  @override
  String get depositTooHigh => 'Cet acompte dépasse la limite Mobile Money.';

  @override
  String get payoutWallet => 'Portefeuille de paiement';

  @override
  String get payoutWalletHelp =>
      'Pour recevoir le paiement d\'une vente ou un remboursement. Un numéro Orange Money ou MTN de Guinée.';

  @override
  String get walletPending => 'En attente de confirmation par un agent';

  @override
  String get walletVerified => 'Confirmé par un agent';

  @override
  String get walletInvalid =>
      'Saisissez un numéro guinéen : +224 suivi de 9 chiffres.';

  @override
  String get save => 'Enregistrer';

  @override
  String get saved => 'Enregistré';
}
