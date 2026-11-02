"""
Contenu de santé par défaut, en français, tiré de sources publiques (OMS, UNFPA).

Ce contenu n'a été relu par AUCUNE sage-femme : il entre avec le statut
`sourced`, jamais `validated`. L'application l'affiche avec la mention « pas
encore relu par une sage-femme », et seulement si SERVE_SOURCED_CONTENT=true.
Une validation dans la console le fait passer en `validated`.

Règles de rédaction :
- chaque phrase reprend un fait de la source citée, reformulé en mots simples ;
- aucune dose, aucun médicament à prendre soi-même, aucun diagnostic ;
- aucun calendrier national : il doit venir du ministère de la Santé ;
- aucun numéro de téléphone : ils viennent de l'annuaire ;
- pas de mooré ni de dioula : à écrire et relire par des locuteurs natifs.

Limites connues, à régler à la relecture par la sage-femme :
- les listes de signes de danger viennent de l'édition 2003 du guide OMS ;
  elles restent à comparer à la 3e édition (2015), illisible depuis cet outil ;
- « le plus vite possible » et quelques consignes de sécurité (violences,
  idées de se faire du mal) sont plus prudentes que le texte des sources.
"""

from typing import Any

WHO_PCPNC = (
    "OMS, Pregnancy, Childbirth, Postpartum and Newborn Care: a guide for essential practice (édition 2003) — "
    "https://www.afro.who.int/sites/default/files/2017-06/mps%20pcpnc.pdf"
)
WHO_ANC = (
    "OMS, nouvelles recommandations sur les soins prénatals, 2016 — "
    "https://www.who.int/news/item/07-11-2016-new-guidelines-on-antenatal-care-for-a-positive-pregnancy-experience"
)
WHO_MATERNAL = "OMS, Maternal mortality — https://www.who.int/news-room/fact-sheets/detail/maternal-mortality"
WHO_NEWBORN = "OMS, Newborn mortality — https://www.who.int/news-room/fact-sheets/detail/newborn-mortality"
WHO_FEEDING = "OMS, Infant and young child feeding — https://www.who.int/news-room/fact-sheets/detail/infant-and-young-child-feeding"
WHO_FP = (
    "OMS, Family planning/contraception methods — "
    "https://www.who.int/news-room/fact-sheets/detail/family-planning-contraception"
)
WHO_EC = "OMS, Emergency contraception — https://www.who.int/news-room/fact-sheets/detail/emergency-contraception"
WHO_MALARIA = "OMS, Malaria — https://www.who.int/news-room/fact-sheets/detail/malaria"
WHO_ANAEMIA = "OMS, Anaemia — https://www.who.int/news-room/fact-sheets/detail/anaemia"
WHO_PRE_ECLAMPSIA = "OMS, Pre-eclampsia — https://www.who.int/news-room/fact-sheets/detail/pre-eclampsia"
WHO_CERVICAL = "OMS, Cervical cancer — https://www.who.int/news-room/fact-sheets/detail/cervical-cancer"
WHO_VAW = "OMS, Violence against women — https://www.who.int/news-room/fact-sheets/detail/violence-against-women"
WHO_RAPE = (
    "OMS, UNFPA, HCR, Clinical Management of Rape Survivors — "
    "https://www.unfpa.org/sites/default/files/pub-pdf/clinical-mgtrape-2005rev1.pdf"
)
WHO_VIOLENCE_HANDBOOK = (
    "Manuel clinique de l'OMS sur les violences, adaptation de la Namibie — "
    "https://www.afro.who.int/sites/default/files/2020-06/Clinical%20Handook%20for%20Women%20Web%20final%20signed_0.pdf"
)
WHO_SUICIDE_FAMILY = (
    "OMS, dépliant sur le suicide pour les proches, 2021 — "
    "https://cdn.who.int/media/docs/default-source/campaigns-and-initiatives/world-mental-health-day/2021/"
    "4_suicide_for_friend_family_members_2021.pdf"
)
WHO_MENTAL = (
    "OMS, Maternal mental health — "
    "https://www.who.int/teams/mental-health-and-substance-use/promotion-prevention/maternal-mental-health"
)
WHO_KEEPING_WELL = (
    "OMS, Keeping well during pregnancy and after childbirth — "
    "https://www.who.int/tools/your-life-your-health/life-phase/pregnancy--birth-and-after-childbirth/"
    "keeping-well-during-pregnancy-and-after-childbirth"
)
WHO_ADOLESCENT = "OMS, Adolescent pregnancy — https://www.who.int/news-room/fact-sheets/detail/adolescent-pregnancy"
UNFPA_FISTULA = "UNFPA, Obstetric fistula — https://www.unfpa.org/obstetric-fistula"
UNFPA_MENSTRUATION = "UNFPA, Menstruation and human rights — https://www.unfpa.org/menstruationfaq"


def _entry(
    seed_key: str, topic: str, question: str, variants: list[str], answer: str, source: str, *, danger: bool = False
) -> dict[str, Any]:
    return {
        "seed_key": seed_key,
        "topic": topic,
        "is_danger_topic": danger,
        "source": source,
        "translations": {"fr": {"question": question, "variants": variants, "answer": answer}},
    }


KB_ENTRIES: list[dict[str, Any]] = [
    # --- Grossesse ---
    _entry(
        "kb-signes-danger-grossesse",
        "grossesse",
        "Quels sont les signes de danger pendant la grossesse ?",
        ["signes de danger grossesse", "quand aller vite au centre de santé enceinte", "danger pendant la grossesse"],
        "Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre, si vous avez : un "
        "saignement par le vagin, des convulsions, de très forts maux de tête avec la vue trouble, de la fièvre "
        "et que vous êtes trop faible pour vous lever, une très forte douleur au ventre, ou si vous respirez vite "
        "ou difficilement. Allez au centre de santé le plus vite possible, le jour même si vous pouvez, sans "
        "attendre que ça passe, si vous avez de la fièvre, mal au ventre, si vous vous sentez malade, si vos "
        "doigts, votre visage ou vos jambes gonflent, ou si le bébé ne bouge plus.",
        WHO_PCPNC,
        danger=True,
    ),
    _entry(
        "kb-consultations-prenatales-nombre",
        "grossesse",
        "Combien de consultations prénatales faut-il faire ?",
        ["combien de visites pendant la grossesse", "nombre de consultations prénatales", "quand faire la CPN"],
        "L'OMS recommande au moins 8 contacts avec un soignant pendant la grossesse. Le premier contact a lieu "
        "dans les 12 premières semaines. Les suivants sont conseillés à 20, 26, 30, 34, 36, 38 et 40 semaines. "
        "Votre centre de santé vous donne vos dates.",
        WHO_ANC,
    ),
    _entry(
        "kb-consultations-prenatales-utilite",
        "grossesse",
        "À quoi servent les consultations prénatales ?",
        ["pourquoi aller aux consultations prénatales", "que fait-on à la consultation prénatale", "utilité de la CPN"],
        "Pendant ces visites, le soignant vous conseille sur l'alimentation et l'activité physique. Il fait les "
        "analyses de sang, le vaccin contre le tétanos et mesure la croissance du bébé. Il vous aide aussi à vous "
        "protéger du paludisme et du VIH, et répond à vos questions sur les petits problèmes de la grossesse, "
        "comme les nausées, le mal de dos ou la constipation.",
        WHO_ANC,
    ),
    _entry(
        "kb-preparer-accouchement",
        "grossesse",
        "Comment préparer mon accouchement et les urgences ?",
        ["préparer l'accouchement", "plan pour l'accouchement", "que prévoir avant d'accoucher"],
        "Parlez-en pendant la grossesse avec votre partenaire ou votre famille. Décidez où vous irez, comment "
        "vous vous y rendrez et combien cela peut coûter. Commencez à mettre de l'argent de côté dès maintenant. "
        "Choisissez qui vous accompagnera et qui gardera la maison et les autres enfants. Si vous habitez loin du "
        "centre, allez 2 à 3 semaines avant la date prévue, et restez près du centre, à la maison d'attente ou "
        "chez des proches. Si vous habitez près, partez dès les premiers signes du travail. Emportez toujours "
        "votre carnet de santé au centre, même pour une urgence.",
        WHO_PCPNC,
    ),
    _entry(
        "kb-signes-travail",
        "grossesse",
        "Comment savoir que le travail commence ?",
        ["début du travail", "quand partir à la maternité", "signes de l'accouchement"],
        "Rendez-vous au centre de santé si vous avez une perte de glaires avec un peu de sang, des contractions "
        "douloureuses toutes les 20 minutes ou moins, ou si la poche des eaux s'est rompue. N'attendez pas que "
        "l'eau s'arrête.",
        WHO_PCPNC,
    ),
    _entry(
        "kb-accoucher-avec-soignant",
        "grossesse",
        "Pourquoi accoucher avec un soignant ?",
        ["accoucher à la maison", "accoucher au centre de santé", "pourquoi aller à la maternité pour accoucher"],
        "Selon l'OMS, toutes les naissances devraient se faire avec un soignant qualifié. Les saignements graves "
        "après l'accouchement et les infections font partie des premières causes de décès des mères. Un soignant "
        "peut agir tout de suite après la naissance pour réduire le risque de saignement.",
        WHO_MATERNAL,
    ),
    _entry(
        "kb-paludisme-grossesse",
        "maladies",
        "Le paludisme est-il dangereux pendant la grossesse ?",
        ["paludisme enceinte", "palu pendant la grossesse", "moustiquaire grossesse"],
        "Oui. Une femme enceinte risque plus une forme grave de paludisme. Le paludisme peut aussi faire naître "
        "le bébé trop tôt ou trop petit. Dormez sous une moustiquaire imprégnée d'insecticide et demandez à la "
        "consultation prénatale le traitement préventif donné aux femmes enceintes. Si vous avez de la fièvre, "
        "faites-vous tester vite au centre de santé. Si vous avez de la fièvre et êtes trop faible pour vous "
        "lever, allez-y tout de suite, de jour comme de nuit.",
        f"{WHO_MALARIA} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-anemie",
        "nutrition",
        "Qu'est-ce que l'anémie et comment l'éviter ?",
        ["anémie", "manque de sang", "je suis fatiguée et pâle", "aliments riches en fer"],
        "L'anémie donne souvent de la fatigue, des vertiges, des mains et des pieds froids, des maux de tête et "
        "un essoufflement à l'effort. Si vous avez ces signes, parlez-en tôt à un agent de santé. Si vous êtes "
        "très pâle ou si vous respirez vite, consultez sans tarder. Pendant la grossesse, l'anémie est liée aux "
        "naissances trop tôt et aux bébés trop petits, et elle peut mettre en danger la vie de la mère. Mangez "
        "des aliments riches en fer : viande, poisson, volaille, légumineuses comme le haricot, et légumes à "
        "feuilles vert foncé. Ajoutez des fruits et des légumes, qui aident le corps à absorber le fer. Le thé et "
        "le café freinent cette absorption : évitez-les au moment du repas. Ne prenez des comprimés que si un "
        "soignant vous les a conseillés. Pendant la grossesse, demandez à la consultation prénatale si vous devez "
        "prendre des comprimés de fer.",
        f"{WHO_ANAEMIA} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-tension-grossesse",
        "grossesse",
        "Qu'est-ce que la pré-éclampsie ?",
        ["tension pendant la grossesse", "pré éclampsie", "hypertension grossesse", "éclampsie"],
        "C'est une tension trop élevée pendant la grossesse, le plus souvent après 20 semaines. Elle peut donner "
        "de très forts maux de tête, une vue trouble ou des points devant les yeux, une douleur en haut du "
        "ventre, des vomissements, et un gonflement des mains et du visage. Certaines femmes ne sentent rien : "
        "faites contrôler votre tension à chaque consultation. Elle peut mener à des convulsions et mettre en "
        "danger la mère et le bébé. Allez tout de suite au centre de santé, de jour comme de nuit, si vous avez "
        "de très forts maux de tête avec la vue trouble, une très forte douleur au ventre ou des convulsions, "
        "pendant la grossesse ou après l'accouchement. Si seuls vos mains ou votre visage gonflent, allez au "
        "centre de santé le plus vite possible.",
        f"{WHO_PRE_ECLAMPSIA} ; {WHO_PCPNC}",
        danger=True,
    ),
    _entry(
        "kb-perte-des-eaux",
        "grossesse",
        "J'ai perdu les eaux, que faire ?",
        ["la poche des eaux s'est rompue", "perte des eaux", "les contractions durent longtemps"],
        "Allez au centre de santé dès que les eaux ont coulé, même sans contractions. N'attendez pas que l'eau "
        "s'arrête. C'est une urgence, de jour comme de nuit, si vous êtes enceinte de moins de 8 mois, si vous "
        "avez de la fièvre, ou si le liquide sent mauvais.",
        WHO_PCPNC,
        danger=True,
    ),
    # --- Après l'accouchement ---
    _entry(
        "kb-saignement-apres-accouchement",
        "post_partum",
        "Quels sont les signes de danger après l'accouchement ?",
        ["saignement après l'accouchement", "hémorragie après l'accouchement", "le placenta n'est pas sorti"],
        "Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre, si : vous saignez beaucoup "
        "(un linge trempé en moins de 5 minutes, ou 2 à 3 linges en 20 à 30 minutes) ; le saignement augmente au "
        "lieu de diminuer ; le placenta n'est pas sorti 1 heure après la naissance ; vous avez des convulsions ; "
        "vous respirez vite ou difficilement ; vous avez de la fièvre et êtes trop faible pour vous lever ; vous "
        "avez une très forte douleur au ventre. Allez au centre de santé le plus vite possible, sans attendre que "
        "ça passe, si vous avez de la fièvre, mal au ventre, si vous vous sentez malade, si vos seins sont "
        "gonflés, rouges ou douloureux, si l'urine coule sans que vous puissiez la retenir ou vous brûle, si vous "
        "avez mal entre le vagin et l'anus ou si du pus en sort, ou si vos pertes sentent mauvais.",
        f"{WHO_PCPNC} ; {WHO_MATERNAL}",
        danger=True,
    ),
    _entry(
        "kb-visites-apres-naissance",
        "post_partum",
        "Combien de visites faut-il après la naissance ?",
        ["visite postnatale", "consultation après l'accouchement", "suivi après la naissance"],
        "L'OMS recommande 4 contacts de soins après la naissance, au centre de santé ou à domicile. Elle "
        "recommande aussi que le bébé reste 24 heures au centre de santé après la naissance.",
        WHO_NEWBORN,
    ),
    _entry(
        "kb-allaitement",
        "enfant",
        "Comment bien allaiter mon bébé ?",
        ["allaitement", "jusqu'à quand allaiter", "quand donner à manger au bébé", "lait maternel"],
        "Mettez le bébé au sein dans l'heure qui suit la naissance. Donnez-lui le sein aussi souvent qu'il le "
        "veut, de jour comme de nuit. Pendant les 6 premiers mois, donnez seulement votre lait, même pas d'eau, "
        "sauf si un soignant le demande. Vers 6 mois, commencez aussi de petites quantités d'aliments sûrs et "
        "nourrissants. Continuez d'allaiter jusqu'à 2 ans ou plus. Si vous vivez avec le VIH, parlez-en à un "
        "agent de santé.",
        WHO_FEEDING,
    ),
    _entry(
        "kb-soins-nouveau-ne",
        "enfant",
        "Comment prendre soin de mon nouveau-né ?",
        ["soins du bébé", "soins du cordon", "que faire pour le nouveau-né"],
        "Gardez le bébé au chaud, peau contre peau avec vous. Gardez le cordon et la peau propres. Ne mettez rien "
        "sur le cordon : ni cendre, ni bouse, ni autre produit. Allaitez tôt et seulement au sein. Faites "
        "enregistrer la naissance. Emmenez le bébé à ses vaccins aux dates prévues par le calendrier national. "
        "Apprenez les signes de danger chez le bébé, et consultez vite si quelque chose vous inquiète.",
        f"{WHO_NEWBORN} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-danger-bebe",
        "enfant",
        "Quels sont les signes de danger chez le bébé ?",
        ["mon bébé ne tète pas", "bébé malade", "bébé a de la fièvre", "signes de danger nouveau-né"],
        "Allez tout de suite au centre de santé, de jour comme de nuit, si votre bébé a du mal à téter ou à "
        "s'alimenter, bouge moins que d'habitude, respire difficilement, a de la fièvre, fait des convulsions, a "
        "le corps froid, saigne, a la diarrhée, ou s'il est né très petit. Allez aussi au centre le plus vite "
        "possible s'il a la peau jaune, du pus aux yeux ou sur la peau, si son cordon est rouge ou coule, ou s'il "
        "tète moins de 5 fois en 24 heures. En route, gardez-le au chaud, peau contre peau, et continuez de lui "
        "donner le sein.",
        f"{WHO_NEWBORN} ; {WHO_PCPNC}",
        danger=True,
    ),
    # --- Bien-être mental ---
    _entry(
        "kb-tristesse-apres-accouchement",
        "sante_mentale",
        "Je suis très triste depuis mon accouchement, est-ce normal ?",
        ["dépression après l'accouchement", "je pleure tout le temps", "tristesse pendant la grossesse"],
        "Cela arrive à beaucoup de femmes, pendant la grossesse et après la naissance. Ces troubles se soignent. "
        "Parlez à une personne de confiance et à un agent de santé. Si cela dure plus de 2 semaines, allez voir "
        "un agent de santé sans tarder. Demandez aussi de l'aide si vous êtes très triste, très anxieuse, épuisée "
        "ou si vous n'arrivez plus à faire face. Si vous pensez à vous faire du mal ou à faire du mal à votre "
        "bébé, allez tout de suite au centre de santé.",
        f"{WHO_MENTAL} ; {WHO_KEEPING_WELL} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-pensees-se-faire-mal",
        "sante_mentale",
        "J'ai des idées de me faire du mal ou de faire du mal à mon bébé",
        ["envie de mourir", "je veux me faire du mal", "je pense à faire du mal à mon bébé", "je veux me tuer"],
        "Vous n'êtes pas seule, et on peut vous aider. Allez tout de suite au centre de santé, de jour comme de "
        "nuit, avec une personne de confiance. En attendant, ne restez pas seule. Demandez à cette personne de "
        "rester avec vous, de garder le bébé, et d'éloigner les médicaments, les produits pour les champs et tout "
        "ce qui peut blesser. La page Aide de l'application donne des numéros utiles.",
        f"{WHO_KEEPING_WELL} ; {WHO_SUICIDE_FAMILY}",
        danger=True,
    ),
    # --- Contraception ---
    _entry(
        "kb-methodes-contraception",
        "contraception",
        "Quelles sont les méthodes de contraception ?",
        ["planning familial", "méthodes pour ne pas tomber enceinte", "quelle contraception choisir"],
        "Les méthodes les plus efficaces et de longue durée sont l'implant, le stérilet et la stérilisation. La "
        "stérilisation est définitive. La pilule, l'injection, le patch et l'anneau vaginal sont efficaces s'ils "
        "sont utilisés régulièrement et correctement. Le préservatif est efficace s'il est bien utilisé. Les "
        "méthodes basées sur le calcul des jours et le retrait sont moins sûres. Un agent de santé peut vous "
        "aider à choisir.",
        WHO_FP,
    ),
    _entry(
        "kb-contraception-sterilite",
        "contraception",
        "La contraception rend-elle stérile ?",
        ["la pilule rend stérile", "contraception et infertilité", "l'injection empêche d'avoir des enfants"],
        "Non. Les méthodes modernes de contraception ne rendent pas stérile.",
        WHO_FP,
    ),
    _entry(
        "kb-preservatif-ist",
        "contraception",
        "Quelle méthode protège des infections sexuelles et du VIH ?",
        ["préservatif et VIH", "se protéger du sida", "protection contre les infections sexuelles"],
        "Le préservatif est la seule méthode de contraception qui protège aussi des infections sexuellement "
        "transmissibles, dont le VIH.",
        WHO_FP,
    ),
    _entry(
        "kb-contraception-urgence",
        "contraception",
        "Que faire après un rapport non protégé ?",
        ["pilule du lendemain", "contraception d'urgence", "le préservatif a craqué"],
        "La contraception d'urgence peut éviter une grossesse. Elle s'utilise dans les 5 jours après le rapport, "
        "et elle marche mieux si elle est prise tôt. Elle ne provoque pas d'avortement et ne peut pas arrêter une "
        "grossesse déjà installée. Elle ne protège pas du VIH ni des infections. Allez vite voir un agent de "
        "santé. Si le rapport a été forcé, allez tout de suite au centre de santé.",
        WHO_EC,
    ),
    _entry(
        "kb-espacement-naissances",
        "contraception",
        "Combien de temps attendre entre deux grossesses ?",
        ["espacer les naissances", "attendre avant une nouvelle grossesse"],
        "L'OMS conseille d'attendre au moins 24 mois entre deux grossesses. Cela aide notamment à prévenir l'anémie.",
        WHO_ANAEMIA,
    ),
    # --- Règles ---
    _entry(
        "kb-regles-normales",
        "menstruation",
        "Comment se passent des règles normales ?",
        ["premières règles", "à quel âge viennent les règles", "durée des règles", "mes règles sont irrégulières"],
        "Les règles sont naturelles et saines. Les premières arrivent le plus souvent entre 10 et 16 ans. Le "
        "cycle dure environ 28 jours, parfois un peu moins ou un peu plus. Le saignement dure souvent 2 à 5 "
        "jours. Dans les premières années, les règles peuvent être irrégulières. Si vos règles ne viennent pas, "
        "vous êtes peut-être enceinte. Si elles sont souvent irrégulières après les premières années, parlez-en à "
        "un agent de santé.",
        UNFPA_MENSTRUATION,
    ),
    _entry(
        "kb-regles-hygiene",
        "menstruation",
        "Comment rester propre pendant les règles ?",
        ["hygiène pendant les règles", "serviettes hygiéniques", "peut-on se laver pendant les règles"],
        "Utilisez des protections propres et absorbantes, jetables ou lavables. Changez-les dans un endroit sûr "
        "et privé, et lavez-vous avec de l'eau et du savon. Le sang des règles n'est pas sale : c'est du sang et "
        "des tissus ordinaires.",
        UNFPA_MENSTRUATION,
    ),
    _entry(
        "kb-regles-douleur",
        "menstruation",
        "Mes règles sont très douloureuses ou très abondantes, que faire ?",
        ["mal au ventre pendant les règles", "règles abondantes", "je saigne beaucoup pendant les règles"],
        "Les douleurs de règles sont fréquentes. Consultez un agent de santé si elles vous empêchent d'aller à "
        "l'école ou au travail, ou si le saignement est très fort ou dure longtemps. Des règles très abondantes "
        "peuvent causer une anémie. Si vous pouvez être enceinte, tout saignement demande d'aller tout de suite "
        "au centre de santé. Allez-y aussi tout de suite si le saignement vient avec une forte douleur, de la "
        "fièvre, un évanouissement ou de mauvaises odeurs.",
        f"{UNFPA_MENSTRUATION} ; {WHO_PCPNC}",
    ),
    # --- Maladies ---
    _entry(
        "kb-paludisme-signes",
        "maladies",
        "Quels sont les signes du paludisme ?",
        ["symptômes du paludisme", "j'ai peut-être le palu", "comment éviter le paludisme"],
        "Les premiers signes sont la fièvre, les maux de tête et les frissons. Faites-vous tester vite. Le "
        "paludisme doit toujours être soigné avec des médicaments donnés par un agent de santé. Sans soin, il "
        "peut devenir grave et tuer en 24 heures. Allez en urgence au centre de santé en cas de grande fatigue, "
        "de confusion, de convulsions, de difficulté à respirer, d'urines foncées ou avec du sang, de jaunisse ou "
        "de saignements anormaux. Les bébés, les jeunes enfants et les femmes enceintes risquent plus. Pour vous "
        "protéger, dormez sous une moustiquaire imprégnée d'insecticide.",
        WHO_MALARIA,
        danger=True,
    ),
    _entry(
        "kb-cancer-col",
        "maladies",
        "Comment se protéger du cancer du col de l'utérus ?",
        ["dépistage du col", "vaccin HPV", "cancer du col"],
        "Ce cancer vient d'une infection durable par certains types de papillomavirus (HPV). L'OMS recommande de "
        "vacciner les filles de 9 à 14 ans. Elle recommande un dépistage à partir de 30 ans, ou de 25 ans pour "
        "les femmes vivant avec le VIH. Soigné tôt, ce cancer peut guérir. Consultez en cas de saignement entre "
        "les règles, après un rapport ou après la ménopause, ou de pertes qui sentent mauvais.",
        WHO_CERVICAL,
    ),
    _entry(
        "kb-fistule",
        "maladies",
        "Je perds mes urines ou mes selles depuis l'accouchement, que faire ?",
        ["fistule obstétricale", "je perds mes urines", "perte de selles après accouchement"],
        "Cela peut être une fistule, une blessure causée le plus souvent par un accouchement long et bloqué. Ce "
        "n'est pas votre faute. Allez au centre de santé dès que possible. Une opération peut en général la "
        "réparer. Si vous êtes opérée, gardez le suivi, surtout pour les prochaines grossesses.",
        f"{UNFPA_FISTULA} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-grossesse-adolescente",
        "grossesse",
        "Pourquoi une grossesse est-elle risquée pour une adolescente ?",
        ["grossesse précoce", "enceinte à 15 ans", "tomber enceinte jeune"],
        "Chez les filles de 10 à 19 ans, le risque d'éclampsie et d'infections est plus élevé. Le bébé risque "
        "plus de naître trop tôt ou trop petit. Si vous êtes enceinte, allez vite à la consultation prénatale. "
        "Une adolescente peut aussi demander conseil sur la contraception à un agent de santé.",
        f"{WHO_ADOLESCENT} ; {WHO_ANC} ; {WHO_FP}",
    ),
    # --- Violences ---
    _entry(
        "kb-violences-definition",
        "violences",
        "Qu'est-ce qu'une violence faite aux femmes ?",
        ["mon mari me frappe", "violence conjugale", "violences basées sur le genre"],
        "C'est un acte qui cause ou peut causer une souffrance physique, sexuelle ou psychologique à une femme. "
        "Cela comprend les coups, les relations sexuelles forcées, les insultes et les menaces, et le fait de "
        "contrôler ou d'enfermer une femme. Ce n'est jamais votre faute. Si vous ou vos enfants êtes en danger "
        "maintenant, allez chez une personne de confiance, par exemple vos parents ou des amis. Si vous êtes "
        "blessée, ou si on vous a forcée à un rapport, allez tout de suite au centre de santé. Sinon, contactez "
        "un agent de santé dès que possible. La page Aide de l'application donne des numéros utiles.",
        f"{WHO_VAW} ; {WHO_KEEPING_WELL} ; {WHO_PCPNC}",
    ),
    _entry(
        "kb-apres-agression-sexuelle",
        "violences",
        "J'ai été violée, que dois-je faire ?",
        ["viol", "agression sexuelle", "on m'a forcée à un rapport"],
        "Allez au centre de santé le plus vite possible, si vous pouvez sans vous laver ni changer de vêtements. "
        "Ce n'est pas votre faute. Le traitement pour prévenir le VIH doit commencer le plus tôt possible, au "
        "plus tard dans les 72 heures. La contraception d'urgence marche mieux tôt, et reste possible jusqu'à 5 "
        "jours après. Même si ces délais sont passés, allez quand même au centre : on peut soigner vos blessures, "
        "prévenir et soigner les infections, faire les tests, et vous soutenir. La page Aide de l'application "
        "donne des numéros utiles.",
        f"{WHO_VIOLENCE_HANDBOOK} ; {WHO_RAPE} ; {WHO_EC}",
        danger=True,
    ),
]


def _capsule(seed_key: str, track: str, order: int, title: str, text: str, quiz: dict[str, Any]) -> dict[str, Any]:
    return {
        "seed_key": seed_key,
        "track": track,
        "order": order,
        "translations": {"fr": {"title": title, "text": text}},
        "quiz": [
            {
                "question": {"fr": quiz["question"]},
                "choices": [{"fr": choice} for choice in quiz["choices"]],
                "correct_index": quiz["correct"],
            }
        ],
    }


CAPSULES: list[dict[str, Any]] = [
    _capsule(
        "capsule-signes-danger",
        "future_mere",
        1,
        "Les signes de danger pendant la grossesse",
        "Certains signes demandent d'aller tout de suite au centre de santé, de jour comme de nuit : un "
        "saignement, des convulsions, de très forts maux de tête avec la vue trouble, une très forte douleur au "
        "ventre, ou une respiration rapide ou difficile. La fièvre avec une faiblesse qui vous empêche de vous "
        "lever est aussi une urgence. La fièvre seule, le mal au ventre ou un gonflement des doigts, du visage ou "
        "des jambes demandent d'y aller le plus vite possible. Parlez de ces signes avec votre famille pour "
        "qu'elle sache quoi faire. Source : OMS.",
        {
            "question": "Que faire en cas de saignement pendant la grossesse ?",
            "choices": ["Aller tout de suite au centre de santé", "Attendre le lendemain"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-consultations",
        "future_mere",
        2,
        "Les consultations prénatales",
        "L'OMS recommande au moins 8 contacts avec un soignant pendant la grossesse, et le premier dans les 12 "
        "premières semaines. Ces visites permettent de faire les analyses, le vaccin contre le tétanos, de "
        "surveiller le bébé et de se protéger du paludisme. Source : OMS.",
        {
            "question": "Quand faire le premier contact avec un soignant ?",
            "choices": ["Dans les 12 premières semaines", "Juste avant l'accouchement"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-allaitement",
        "jeune_mere",
        1,
        "L'allaitement",
        "Mettez le bébé au sein dans l'heure qui suit la naissance. Donnez seulement votre lait pendant les 6 "
        "premiers mois, même pas d'eau, sauf si un soignant le demande. Vers 6 mois, ajoutez de petites quantités "
        "d'aliments sûrs et nourrissants, et continuez d'allaiter jusqu'à 2 ans ou plus. Source : OMS.",
        {
            "question": "Jusqu'à quel âge donner seulement le lait maternel ?",
            "choices": ["6 mois", "2 semaines"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-danger-bebe",
        "jeune_mere",
        2,
        "Les signes de danger chez le bébé",
        "Allez tout de suite au centre de santé si votre bébé a du mal à téter, bouge moins, respire "
        "difficilement, a de la fièvre, fait des convulsions, a le corps froid, saigne ou a la diarrhée. En "
        "route, gardez-le au chaud, peau contre peau, et continuez de lui donner le sein. Source : OMS.",
        {
            "question": "Votre bébé a le corps froid et ne tète plus. Que faire ?",
            "choices": ["Aller tout de suite au centre de santé", "Attendre quelques jours"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-premieres-regles",
        "adolescente",
        1,
        "Les premières règles",
        "Les règles sont naturelles et saines. Elles commencent le plus souvent entre 10 et 16 ans. Le saignement "
        "dure souvent 2 à 5 jours et peut être irrégulier les premières années. Les règles ne veulent pas dire "
        "qu'une fille est prête pour le mariage. Utilisez des protections propres, et lavez-vous avec de l'eau et "
        "du savon. Source : UNFPA.",
        {
            "question": "Avoir ses règles veut-il dire qu'une fille est prête pour le mariage ?",
            "choices": ["Non", "Oui"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-grossesse-precoce",
        "adolescente",
        2,
        "La grossesse trop tôt",
        "Avant 20 ans, une grossesse présente plus de risques pour la jeune fille et pour le bébé, qui peut "
        "naître trop tôt ou trop petit. Un agent de santé peut donner des conseils sur la contraception. Source : "
        "OMS.",
        {
            "question": "Une grossesse avant 20 ans présente-t-elle plus de risques ?",
            "choices": ["Oui", "Non"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-soutien-famille",
        "hommes_familles",
        1,
        "Préparer l'accouchement en famille",
        "Le partenaire et la famille aident à préparer l'accouchement. Parlez-en pendant la grossesse. Ensemble, "
        "décidez où aller, comment vous y rendre, combien cela peut coûter, et commencez à mettre de l'argent de "
        "côté. Décidez qui accompagnera la femme et qui gardera la maison et les enfants. Si vous habitez loin du "
        "centre, prévoyez d'y aller 2 à 3 semaines avant la date prévue. Apprenez les signes de danger pour "
        "réagir vite. Source : OMS.",
        {
            "question": "Quand parler du plan pour l'accouchement ?",
            "choices": ["Pendant la grossesse", "Le jour même"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-violences",
        "droits",
        1,
        "Reconnaître les violences",
        "Une violence peut être physique, sexuelle ou psychologique. Les menaces et le contrôle en font partie. "
        "Elle peut venir d'un partenaire ou d'une autre personne. La victime n'est jamais responsable. Un agent "
        "de santé peut aider, et la page Aide donne des numéros utiles. Source : OMS.",
        {
            "question": "Les menaces sont-elles une forme de violence ?",
            "choices": ["Oui", "Non"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-bien-etre-maman",
        "bien_etre",
        1,
        "Prendre soin de son moral",
        "La tristesse ou l'anxiété peuvent toucher toute femme, pendant la grossesse et après la naissance. Ces "
        "troubles se soignent. Parlez à une personne de confiance, à d'autres femmes et à un agent de santé. Si "
        "cela dure plus de 2 semaines, ou si vous n'arrivez plus à faire face, demandez de l'aide. Si vous pensez "
        "à vous faire du mal ou à faire du mal à votre bébé, allez tout de suite au centre de santé. Source : "
        "OMS.",
        {
            "question": "Ces troubles peuvent-ils se soigner ?",
            "choices": ["Oui", "Non"],
            "correct": 0,
        },
    ),
    _capsule(
        "capsule-paludisme",
        "general",
        1,
        "Se protéger du paludisme",
        "Le paludisme commence souvent par de la fièvre, des maux de tête et des frissons. Il peut devenir grave "
        "en 24 heures : faites-vous tester vite. En cas de grande fatigue, de convulsions ou de difficulté à "
        "respirer, allez en urgence au centre de santé. Dormez sous une moustiquaire imprégnée d'insecticide. Les "
        "femmes enceintes et les jeunes enfants risquent plus. Source : OMS.",
        {
            "question": "Que faire en cas de fièvre avec des frissons ?",
            "choices": ["Se faire tester vite", "Attendre une semaine"],
            "correct": 0,
        },
    ),
]
