/// Tous les textes de l'interface, en un seul endroit, pour pouvoir les
/// traduire plus tard (mooré, dioula). Pour l'instant l'interface reste en
/// français ; la langue choisie change la VOIX (bouton « Écouter ») et la
/// langue des contenus de santé servis par l'API.
///
/// Règle : des mots simples, des phrases courtes. Aucun contenu de santé ici :
/// tous les conseils viennent de l'API, validés par une sage-femme.
abstract final class S {
  // --- Général ---
  static const appName = 'Laafi Ma';
  static const listen = 'Écouter';
  static const listenUnavailable = "L'écoute a besoin d'internet la première fois. Réessayez plus tard.";
  static const save = 'Enregistrer';
  static const cancel = 'Annuler';
  static const delete = 'Supprimer';
  static const edit = 'Modifier';
  static const add = 'Ajouter';
  static const close = 'Fermer';
  static const yes = 'Oui';
  static const no = 'Non';
  static const ok = 'OK';
  static const next = 'Suivant';
  static const back = 'Retour';
  static const skip = 'Passer';
  static const retry = 'Réessayer';
  static const loading = 'Chargement…';
  static const empty = 'Rien pour le moment.';
  static const required = 'Obligatoire';
  static const estimation = 'Estimation';
  static const offline = 'Hors connexion';
  static const offlineData = 'Données enregistrées sur le téléphone';
  static const download = 'Télécharger';
  static const downloadedOn = 'Téléchargé le';
  static const confirmDelete = 'Supprimer cet élément ?';
  static const synthVoice = 'voix de synthèse';
  static const humanVoice = 'voix enregistrée';
  static const play = 'Écouter';
  static const stop = 'Arrêter';
  static const days = 'jours';
  static const today = "Aujourd'hui";
  static const chooseDate = 'Choisir une date';
  static const chooseTime = 'Choisir une heure';
  static const notSet = 'Non renseigné';
  static const webNoReminders =
      "Sur navigateur, les rappels ne sonnent pas : installez l'application Android pour les recevoir.";

  // --- Sortie rapide / verrou ---
  static const quickExit = 'Sortie rapide';
  static const quickExitHint = "Ferme tout de suite l'application";
  static const lockTitle = 'Code';
  static const lockListen = 'Tapez votre code secret.';
  static const wrongPin = 'Code incorrect';
  static String tooManyAttempts(int seconds) => 'Trop d\'essais. Attendez $seconds secondes.';
  static const pinTooShort = 'Le code doit avoir 4 à 6 chiffres.';
  static const pinMismatch = 'Les deux codes ne sont pas pareils.';
  static const pinMustDiffer = 'Ce code est déjà utilisé pour autre chose. Choisissez-en un autre.';
  static const calculator = 'Calculatrice';

  // --- Accueil ---
  static const homeListen =
      'Bienvenue. Touchez une grande image. Assistant pour poser une question. Mon carnet pour votre santé. '
      'Aide pour être protégée. Apprendre pour écouter des leçons. Espace agent pour les agents de santé.';
  static const tileAssistant = 'Assistant';
  static const tileAssistantListen = 'Assistant : posez une question à voix haute.';
  static const tileCarnet = 'Mon carnet';
  static const tileCarnetListen = 'Mon carnet : votre carnet de santé, gardé sur ce téléphone.';
  static const tileHelp = 'Aide';
  static const tileHelpListen = 'Aide : alerte, numéros utiles, journal privé, bien-être.';
  static const tileLearn = 'Apprendre';
  static const tileLearnListen = 'Apprendre : écoutez des leçons courtes.';
  static const tileAgent = 'Espace agent';
  static const tileAgentListen = 'Espace agent : réservé aux agents de santé.';
  static const settings = 'Réglages';

  // --- Accueil (premier lancement) ---
  static const onbWelcome = 'Bienvenue sur Laafi Ma';
  static const onbChooseLang = 'Choisissez votre langue';
  static const onbChooseLangListen = 'Bienvenue. Choisissez votre langue : français, mooré ou dioula.';
  static const onbLangNote = "La voix et les conseils seront dans cette langue. Les écrans restent en français.";
  static const accept = "J'accepte";
  static const refuse = 'Non merci';
  static const consentRecordTitle = 'Votre carnet reste sur ce téléphone';
  static const consentRecordText =
      'Laafi Ma garde votre carnet de santé seulement sur ce téléphone. Il est fermé à clé (chiffré). '
      'Personne d\'autre ne peut le lire, même pas nous. Vous pouvez tout effacer quand vous voulez.';
  static const consentStatsTitle = 'Aider avec des chiffres anonymes ?';
  static const consentStatsText =
      'Si vous voulez, l\'application envoie des compteurs anonymes : par exemple « une question posée aujourd\'hui ». '
      'Jamais votre nom, jamais votre numéro, jamais ce que vous écrivez. Vous pouvez changer d\'avis dans les réglages.';
  static const consentBackupTitle = 'Sauvegarde (facultatif)';
  static const consentBackupText =
      'Plus tard, vous pourrez faire une copie de votre carnet sur internet, fermée par un mot de passe que vous seule '
      'connaissez. Personne ne peut l\'ouvrir sans ce mot de passe. C\'est facultatif.';
  static const createPinTitle = 'Créez votre code secret';
  static const createPinText = 'Choisissez 4 à 6 chiffres. Ce code ouvre l\'application. Ne le dites à personne.';
  static const confirmPinTitle = 'Tapez encore le même code';
  static const decoyTitle = 'Code de diversion (facultatif)';
  static const decoyText =
      'Si quelqu\'un vous force à ouvrir l\'application, tapez ce code : un carnet vide s\'ouvre. Vos vraies données '
      'restent cachées.';
  static const helpCodeTitle = 'Code pour la page Aide (facultatif)';
  static const helpCodeText = 'Un deuxième code, demandé seulement pour ouvrir la page Aide (alerte, journal privé).';
  static const disguiseTitle = 'Cacher l\'application (facultatif)';
  static const disguiseText =
      'L\'application s\'ouvre comme une calculatrice. Pour entrer, tapez votre code puis la touche « = ».';
  static const disguiseOn = 'Oui, montrer une calculatrice';
  static const disguiseOff = 'Non, montrer l\'écran du code';
  static const setThisCode = 'Choisir ce code';
  static const onbDone = 'C\'est prêt !';
  static const onbDoneText = 'Votre application est prête. Elle se ferme à clé quand vous la quittez.';
  static const start = 'Commencer';

  // --- Assistant ---
  static const assistantTitle = 'Assistant';
  static const assistantListen =
      'Appuyez sur le gros micro et posez votre question. Appuyez encore pour envoyer. Vous pouvez aussi écrire.';
  static const tapToSpeak = 'Appuyez pour parler';
  static const tapToSend = 'Je parle… appuyez pour envoyer';
  static const sending = 'Envoi…';
  static const typeQuestion = 'Écrire ma question';
  static const ask = 'Demander';
  static const youSaid = 'Vous avez dit';
  static const answer = 'Réponse';
  static const dangerTitle = 'Attention : signe de danger';
  static const callHealthCenter = 'Appeler le centre de santé';
  static const callHotline = 'Numéro vert';
  static const noNumberCached = 'Aucun numéro enregistré. Ouvrez l\'annuaire avec internet pour le télécharger.';
  static const faq = 'Questions fréquentes';
  static const faqListen = 'Voici les questions fréquentes. Touchez une question pour lire la réponse.';
  static const downloadForOffline = 'Garder pour hors connexion';
  static const offlineAnswerNote =
      'Pas de connexion : voici ce que le téléphone peut faire seul. Demandez à votre agent de santé si besoin.';
  static const closeQuestions = 'Questions proches';
  static const noFaqOffline = 'Aucune question enregistrée. Utilisez « Garder pour hors connexion » avec internet.';
  static const micDenied = 'Le micro est refusé. Autorisez-le dans les réglages du téléphone.';
  static const voiceUnavailable = 'Assistant vocal indisponible pour le moment. Écrivez votre question.';
  static const dangerDetectedOffline = 'Signe de danger possible dans votre question';
  static String confirmQuestion(String text) => 'Vous avez demandé : « $text » ?';
  static const confirmRepeat = 'Non, je répète';
  static const confirmListen =
      'Voici ce que le téléphone a compris. Est-ce bien votre question ? Oui, ou non je répète.';
  static const notHeard = 'Je n\'ai pas bien entendu. Appuyez sur le micro et parlez encore.';
  static const understoodQuestion = 'Avez-vous compris ?';
  static const understoodThanks = 'Merci pour votre réponse.';
  static const notUnderstoodHint =
      'Vous pouvez réécouter la réponse. Vous pouvez aussi demander à votre agent de santé de vous l\'expliquer.';
  static const replayAnswer = 'Réécouter la réponse';
  static const callEmergency = 'Appeler les urgences';

  // --- Carnet ---
  static const carnetTitle = 'Mon carnet';
  static const carnetListen =
      'Votre carnet de santé. Touchez une image : profil, règles, contraception, grossesse, après l\'accouchement, '
      'enfants, consultations, documents, médicaments, agenda, bien-être, partager, sauvegarde.';
  static const carnetConsentNeeded = 'Pour utiliser le carnet, acceptez qu\'il soit gardé sur ce téléphone.';
  static const healthProfile = 'Mon profil santé';
  static const cycle = 'Mes règles';
  static const contraception = 'Contraception';
  static const pregnancy = 'Grossesse';
  static const postpartum = 'Après l\'accouchement';
  static const children = 'Mes enfants';
  static const consultations = 'Consultations';
  static const documents = 'Documents';
  static const medicines = 'Médicaments';
  static const agenda = 'Agenda';
  static const wellbeing = 'Bien-être';
  static const share = 'Montrer à un soignant';
  static const backup = 'Sauvegarde';
  static const nextPeriodEstimate = 'Prochaines règles (estimation)';
  static const averageCycle = 'Cycle moyen';
  static const needTwoPeriods = 'Notez au moins deux débuts de règles pour avoir une estimation.';
  static String lateBy(int days) => 'Retard estimé : $days jour${days > 1 ? 's' : ''}';
  static const lateNote = 'Ce n\'est qu\'une estimation. Si vous êtes inquiète, parlez-en à votre agent de santé.';
  static const addPeriod = 'Noter le début des règles';
  static const lmp = 'Premier jour des dernières règles';
  static const pregnancyWeek = 'Semaine de grossesse (estimation)';
  static const dueDate = 'Date prévue d\'accouchement (estimation)';
  static const naegeleNote = 'Calcul : règle de Naegele. Seul un soignant peut confirmer.';
  static const prenatalVisits = 'Visites prénatales';
  static const exams = 'Examens';
  static const weight = 'Poids';
  static const bloodPressure = 'Tension';
  static const endPregnancy = 'Effacer la grossesse en cours';
  static const deliveryDate = 'Date de l\'accouchement';
  static String postpartumDay(int day) => 'Jour $day après l\'accouchement';
  static const postpartumDone = 'Le suivi des 42 jours est terminé.';
  static const postpartumLogs = 'Suivi du jour';
  static const vaccines = 'Vaccins';
  static const vaccinesNote =
      'Notez les vaccins reçus avec leur date. Le calendrier national sera ajouté quand il sera validé.';
  static const recommendations = 'Recommandations';
  static const addDocument = 'Ajouter un document';
  static const takePhoto = 'Prendre une photo';
  static const pickImage = 'Choisir une image';
  static const pickFile = 'Choisir un fichier';
  static const pdfFile = 'Fichier PDF';
  static const reminders = 'Rappels';
  static const weekView = 'Semaine';
  static const moodToday = 'Comment vous sentez-vous aujourd\'hui ?';
  static const capsulesWellbeing = 'Écouter les leçons bien-être';
  static const gentleSupportTitle = 'Ces derniers jours semblent difficiles';
  static const gentleSupportText =
      'Vous n\'êtes pas seule. Si vous voulez, vous pouvez parler à quelqu\'un ou prendre un moment pour respirer.';
  static const supportSheetTitle = 'Prenez soin de vous';
  static const supportSheetText = 'Si vous voulez, vous pouvez maintenant parler à quelqu\'un ou respirer calmement.';
  static const weeklyTip = 'Conseil de la semaine';

  // --- Partage QR ---
  static const shareListen =
      'Choisissez ce que vous voulez montrer. Un code carré apparaît. Le soignant le lit avec son téléphone. '
      'Il ne marche que 15 minutes.';
  static const chooseSections = 'Que voulez-vous montrer ?';
  static const showQr = 'Afficher le code';
  static String validUntil(String time) => 'Valable jusqu\'à $time';
  static const qrExpired = 'Ce code a expiré. Créez-en un nouveau.';
  static const generatedAt = 'Créé à';
  static const shareLog = 'Journal des partages';
  static const shareLogNote =
      'L\'application ne peut pas savoir si le code a été lu : le téléphone du soignant le lit sans internet.';
  static const shareLogEmpty = 'Aucun code créé pour le moment.';
  static String shareLogLine(String when, String sections, String until) =>
      '$when · $sections · valable jusqu\'à $until';

  // --- Sauvegarde ---
  static const backupListen =
      'La sauvegarde copie votre carnet sur internet, fermé par votre mot de passe. Sans ce mot de passe, '
      'personne ne peut l\'ouvrir, même pas nous. Si vous l\'oubliez, la copie est perdue.';
  static const createAccount = 'Créer un compte anonyme';
  static const recoveryCodeTitle = 'Votre code de récupération';
  static const recoveryCodeWarning =
      'IMPORTANT : notez ce numéro de compte et ce code sur un papier caché. Ils ne seront plus jamais affichés. '
      'Sans eux, impossible de récupérer votre sauvegarde sur un autre téléphone.';
  static const iWroteItDown = 'Je les ai notés';
  static const passphrase = 'Mot de passe de la sauvegarde';
  static const passphraseConfirm = 'Tapez encore le mot de passe';
  static const passphraseTooShort = 'Au moins 8 caractères.';
  static const backupNow = 'Sauvegarder maintenant';
  static const restore = 'Restaurer ma sauvegarde';
  static const restoreFromOtherPhone = 'Restaurer depuis un autre téléphone';
  static const accountId = 'Numéro de compte';
  static const recoveryCode = 'Code de récupération';
  static const includeMedia = 'Inclure les photos et notes vocales';
  static const backupDone = 'Sauvegarde envoyée.';
  static const restoreDone = 'Carnet restauré.';
  static const wrongPassphrase = 'Mot de passe incorrect ou sauvegarde abîmée.';
  static const noBackup = 'Aucune sauvegarde trouvée.';
  static const backupTooBig = 'Sauvegarde trop grosse. Essayez sans les photos.';
  static const lastBackup = 'Dernière sauvegarde';
  static const deleteBackup = 'Effacer la sauvegarde en ligne';
  static const backupDisabledByConsent =
      'Vous avez refusé la sauvegarde au premier lancement. Vous pouvez l\'accepter ici.';

  // --- Aide ---
  static const helpTitle = 'Aide et protection';
  static const helpListen =
      'Page d\'aide. Gros bouton rouge : appuyez longtemps pour préparer un message d\'alerte. '
      'Vous pouvez aussi appeler un service, écrire dans votre journal privé, ou respirer calmement.';
  static const helpCodePrompt = 'Code de la page Aide';
  static const sos = 'ALERTE';
  static const sosHint = 'Appuyez longtemps';
  static String sosCountdown(int s) => 'Message d\'alerte dans $s…';
  static const sosHonest =
      'Le téléphone va ouvrir vos SMS avec le message prêt. C\'est VOUS qui devez appuyer sur « Envoyer ».';
  static const sosNoContacts = 'Ajoutez d\'abord jusqu\'à 3 personnes de confiance dans les réglages.';
  static const sosDefaultMessage =
      'J\'ai besoin d\'aide. Ce message vient de mon téléphone. Appelle-moi ou viens vite.';
  static const sosLocation = 'Ma position';
  static const sosNoLocationMinor =
      'Vous avez moins de 18 ans : votre position n\'est jamais ajoutée au message, pour vous protéger.';
  static const directory = 'Numéros utiles';
  static const directoryListen = 'Numéros utiles. Touchez le bouton vert pour appeler.';
  static const notConfirmed = 'numéro non confirmé';
  static const freeCall = 'appel gratuit';
  static const call = 'Appeler';
  static const callLogNote =
      'L\'appel passe par le téléphone : il apparaîtra dans l\'historique des appels du téléphone. '
      'Effacez-le si besoin. L\'application, elle, ne garde aucune trace.';
  static const journal = 'Journal privé';
  static const journalListen = 'Votre journal privé. Ce que vous écrivez est fermé à clé sur ce téléphone.';
  static const newEntry = 'Nouvelle page';
  static const writeHere = 'Écrivez ici…';
  static const addPhoto = 'Photo';
  static const recordAudio = 'Note vocale';
  static const rights = 'Mes droits';
  static const breathing = 'Respirer';
  static const breathingListen = 'Suivez le cercle. Inspirez quand il grandit, soufflez quand il diminue.';
  static const breatheIn = 'Inspirez…';
  static const breatheOut = 'Soufflez…';
  static const listeningServices = 'Parler à quelqu\'un';
  static const trustedContacts = 'Personnes de confiance';

  // --- Agent ---
  static const agentTitle = 'Espace agent';
  static const agentLogin = 'Connexion agent';
  static const email = 'Email';
  static const password = 'Mot de passe';
  static const login = 'Se connecter';
  static const logout = 'Se déconnecter';
  static const notAnAgent = 'Ce compte n\'est pas un compte agent.';
  static const beneficiaries = 'Bénéficiaires';
  static const visits = 'Visites';
  static const gbvReferral = 'Orientation VBG (anonyme)';
  static const summary = 'Résumé';
  static const sync = 'Synchroniser';
  static String pendingSync(int n) => '$n élément${n > 1 ? 's' : ''} à envoyer';
  static const syncDone = 'Synchronisation terminée.';
  static const scanQr = 'Lire le QR d\'une femme';
  static const pasteQr = 'Collez le contenu du QR code';
  static const translation = 'Traduction';
  static const consentRequired = 'Le consentement de la personne est obligatoire.';
  static const consentCheckbox = 'La personne a donné son accord pour être suivie';
  static const dangerChecklist = 'Signes de danger observés';
  static const referAdvice = 'Signe de danger : orientez vers le centre de santé.';
  static const noDangerSignsCached = 'Liste des signes de danger non téléchargée. Synchronisez avec internet.';
  static const gbvNoName = 'Aucun nom n\'est enregistré : seulement la date, le type et le service.';

  static const decisionAid = 'Fiche d\'aide à la décision';
  static const decisionAidListen = 'Fiches d\'aide à la décision. Touchez un signe de danger pour voir sa fiche.';
  static const decisionAidNotWritten = 'Fiche pas encore rédigée par la sage-femme.';
  static const openSheet = 'Fiche';
  static const adviceLabel = 'Conseil';
  static const questionsToAsk = 'Questions à poser';
  static const whenToRefer = 'Quand orienter';
  static const servicesToCall = 'Services à appeler';
  static String verifiedOn(String date) => 'vérifié le $date';
  static const remindersToDo = 'Rappels à faire';
  static const remindersToDoListen =
      'Rappels à faire : les rendez-vous en retard et ceux des 7 prochains jours. Envoyez un SMS ou appelez.';
  static const remindersEmpty = 'Aucun rendez-vous en retard ni dans les 7 prochains jours.';
  static const reminderOverdue = 'en retard';
  static String reminderSms(String date) => 'Bonjour. Petit rappel : rendez-vous au centre de santé le $date. Merci.';
  static const sms = 'SMS';
  static const noPhoneNoted = 'Pas de numéro noté';
  static const nextAppointment = 'Prochain rendez-vous';
  static const nextAppointmentReason = 'Motif du rendez-vous';
  static const clearDate = 'Effacer la date';
  static const phoneLocalOnly = 'Téléphone (facultatif)';
  static const phoneLocalOnlyNote = 'Ce numéro reste sur ce téléphone. Il n\'est jamais envoyé au serveur.';
  static const appointmentReasons = {
    'prenatal': 'Consultation prénatale',
    'postnatal': 'Consultation postnatale',
    'vaccine': 'Vaccin',
    'family_planning': 'Planification familiale',
    'follow_up': 'Suivi',
    'other': 'Autre',
  };

  // --- Apprendre ---
  static const learnTitle = 'Apprendre';
  static const learnListen = 'Choisissez un thème, puis une leçon. Appuyez sur Écouter.';
  static const quiz = 'Petit jeu';
  static const goodAnswer = 'Bonne réponse !';
  static String rightAnswerIs(String a) => 'La bonne réponse est : $a';
  static const tracks = {
    'adolescente': 'Adolescente',
    'future_mere': 'Future maman',
    'jeune_mere': 'Jeune maman',
    'hommes_familles': 'Hommes et familles',
    'droits': 'Droits',
    'bien_etre': 'Bien-être',
    'general': 'Général',
  };

  static const suggestedForYou = 'Conseillé pour vous';

  // --- Réglages ---
  static const settingsListen = 'Réglages : langue, codes, personnes de confiance, sauvegarde, effacer.';
  static const language = 'Langue';
  static const security = 'Sécurité';
  static const changePin = 'Changer mon code';
  static const decoyPin = 'Code de diversion';
  static const helpCode = 'Code de la page Aide';
  static const disguise = 'Calculatrice de camouflage';
  static const iconDisguise = 'Changer aussi l\'icône et le nom';
  static const iconDisguiseText =
      'Sur l\'écran du téléphone, l\'application s\'appellera « Calculatrice ». Cela peut prendre quelques secondes.';
  static const iconDisguiseFailed = 'Le changement d\'icône n\'a pas marché sur ce téléphone.';
  static const helpPhrase = 'Phrase secrète d\'aide';
  static const helpPhraseText =
      'Une phrase banale, par exemple sur la cuisine. Si vous la dites ou l\'écrivez dans l\'Assistant, la page Aide '
      's\'ouvre et rien n\'est envoyé.';
  static const helpPhraseHint = 'Votre phrase (au moins 3 mots)';
  static const helpPhraseIsSet = 'Phrase choisie (elle n\'est jamais affichée)';
  static const helpPhraseTooShort = 'Au moins 3 mots.';
  static const helpPhraseSaved = 'Phrase enregistrée.';
  static const profilesTitle = 'Profils (téléphone partagé)';
  static const profilesText =
      'Chaque personne a son propre code et son propre carnet. Le code tapé ouvre le bon profil. '
      'Personne ne voit le carnet des autres.';
  static String profileName(int n) => 'Profil $n';
  static const profileCurrent = 'ouvert maintenant';
  static const profileAdd = 'Ajouter un profil';
  static const profileNewPinText =
      'Choisissez le code de ce nouveau profil. Il doit être différent de tous les autres codes du téléphone.';
  static const profileRemove = 'Retirer ce profil';
  static const profileRemoveConfirm =
      'Le carnet, le journal, les contacts et les codes de ce profil seront effacés de ce téléphone. '
      'On ne pourra rien récupérer. Continuer ?';
  static const profileRemovePin = 'Tapez le code de ce profil';
  static const profileRemoved = 'Profil retiré.';
  static const profileMax = 'Au maximum 3 profils sur un téléphone.';
  static const deviceSettingsProfile1 =
      'Les réglages du téléphone (code de diversion, camouflage, sauvegarde, tout effacer) se changent dans le '
      'profil 1.';
  static const remove = 'Retirer';
  static const district = 'District sanitaire';
  static const noDistrict = 'Aucun';
  static const stats = 'Chiffres anonymes';
  static const wipeAll = 'Supprimer toutes mes données';
  static const wipeConfirm =
      'Tout sera effacé de ce téléphone : carnet, journal, codes. Et votre compte en ligne s\'il existe. '
      'On ne pourra rien récupérer. Continuer ?';
  static const wipeOfflineWarning =
      'Données du téléphone effacées. Le compte en ligne n\'a pas pu être supprimé sans internet.';
  static const contactName = 'Nom';
  static const contactPhone = 'Téléphone';
  static const maxThreeContacts = 'Au maximum 3 personnes.';
  static const sosMessage = 'Message d\'alerte';
  static const consentRecord = 'Carnet gardé sur ce téléphone';
  static const remindersPermission = 'Autoriser les rappels';
}
