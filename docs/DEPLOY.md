# Mettre la démo en ligne gratuitement

| Partie | Hébergeur | Adresse |
|---|---|---|
| Application web | GitHub Pages | `https://renezongo.github.io/laafi-ma/` |
| Console admin | GitHub Pages | `https://renezongo.github.io/laafi-ma/admin/` |
| Statistiques publiques | GitHub Pages | `https://renezongo.github.io/laafi-ma/admin/#/public` |
| API | Render (gratuit) | `https://laafi-ma-api.onrender.com` |
| Base de données | Neon (gratuit) | privée |
| APK de démonstration | GitHub Releases | release `demo` du dépôt |

## Limites de cette démo

- **Démo uniquement, aucune donnée réelle.** Les serveurs sont hors du Burkina
  Faso : pas de vraie bénéficiaire, pas de vraie donnée de santé. Le pilote
  demande un hébergement au Burkina Faso et une déclaration à la CIL.
- **Pas de voix côté serveur, pas de mooré ni de dioula.** Les modèles d'IA
  demandent environ 6 Go de RAM, Render gratuit en offre 0,5. Micro de
  l'assistant, traduction et synthèse répondent `503`. L'assistant texte en
  français, le carnet, l'aide, l'espace agent et les capsules fonctionnent.
- **L'API s'endort** après 15 minutes sans visite. La requête suivante prend
  environ une minute. Prévoyez d'ouvrir l'application avant une présentation.
- **Fichiers audio envoyés dans la console :** perdus à chaque redémarrage de
  Render, car son disque n'est pas conservé. Le texte, lui, reste dans Neon.
- **Assistant vide au départ :** il faut saisir et valider des réponses dans la
  console.

## 1. Neon (base de données)

1. Créez un compte sur [neon.com](https://neon.com), sans carte bancaire.
2. Créez un projet nommé `laafi-ma`, région Europe.
3. Copiez la chaîne de connexion. Elle commence par `postgresql://`.

## 2. Render (API)

1. Créez un compte sur [render.com](https://render.com) avec GitHub.
2. Choisissez **New > Blueprint**, puis le dépôt `laafi-ma`.
3. Render lit `render.yaml` et demande trois valeurs :
   - `DATABASE_URL` : la chaîne copiée sur Neon ;
   - `ADMIN_EMAILS` : votre e-mail au format `["vous@exemple.org"]` ;
   - `ADMIN_BOOTSTRAP_PASSWORD` : un mot de passe d'au moins 10 caractères.
4. Validez, puis attendez la fin du build.
5. Ouvrez `https://laafi-ma-api.onrender.com/health`. Vous devez voir
   `"status":"ok"`.

Si Render a donné une autre adresse, créez sur GitHub la variable
`API_BASE_URL` avec cette adresse (**Settings > Secrets and variables >
Actions > Variables**), puis relancez les deux workflows.

## 3. GitHub Pages

Dans le dépôt : **Settings > Pages > Source : GitHub Actions**. Relancez ensuite
le workflow **Déploiement web** dans l'onglet **Actions**.

## 4. Vérifier

1. Ouvrez la console admin et connectez-vous.
2. Changez votre mot de passe si la console le propose.
3. Ouvrez l'application web et posez une question écrite en français.
4. Téléchargez l'APK depuis la release `demo` et testez-le sur un téléphone.
