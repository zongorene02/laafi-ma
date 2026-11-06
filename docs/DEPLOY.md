# Mettre la démo en ligne gratuitement

Pas de Docker : l'API tourne sur le runtime Python natif de Render.

| Partie | Hébergeur | Adresse |
|---|---|---|
| Application web | Cloudflare Workers | `https://laafi-ma.zongorene08.workers.dev/` |
| Console admin | Cloudflare Workers | `https://laafi-ma.zongorene08.workers.dev/admin/` |
| Statistiques publiques | Cloudflare Workers | `https://laafi-ma.zongorene08.workers.dev/admin/#/public` |
| API | Render (gratuit) | `https://laafi-ma-api.onrender.com` |
| Voix et mooré/dioula | Hugging Face Spaces (ZeroGPU, gratuit) | `https://huggingface.co/spaces/renezongo/laafi-ma-voice` |
| Base de données | Neon (gratuit) | privée |
| APK de démonstration | GitHub Releases | release `demo` du dépôt |

## Limites de cette démo

- **Démo uniquement, aucune donnée réelle.** Les serveurs sont hors du Burkina
  Faso : pas de vraie bénéficiaire, pas de vraie donnée de santé. Le pilote
  demande un hébergement au Burkina Faso et une déclaration à la CIL.
- **La voix et le mooré/dioula sont limités.** Les modèles d'IA demandent
  environ 6 Go de RAM, Render gratuit en offre 0,5. Ils tournent donc sur un
  Space Hugging Face gratuit (section 5) : 5 minutes de carte graphique par
  jour, et un Space endormi met plusieurs minutes à se réveiller. Quand le
  Space ne répond pas à temps ou que le quota du jour est épuisé, le micro de
  l'assistant, la traduction et la synthèse répondent `503` : il faut
  réessayer plus tard. Sans la section 5, ils répondent toujours `503`.
  L'assistant texte en français, le carnet, l'aide, l'espace agent et les
  capsules fonctionnent dans tous les cas.
- **Modèles non commerciaux.** NLLB-200, MMS et l'adaptateur mooré sont sous
  licence CC-BY-NC 4.0 : interdit de s'en servir pour gagner de l'argent sans
  autre accord. Une démo ou un projet sans but commercial, oui.
- **L'API s'endort** après 15 minutes sans visite. La requête suivante prend
  environ une minute. Prévoyez d'ouvrir l'application avant une présentation.
- **Fichiers audio envoyés dans la console :** perdus à chaque redémarrage de
  Render, car son disque n'est pas conservé. Le texte, lui, reste dans Neon.
- **Contenu non relu par une sage-femme.** Les réponses, les capsules et les
  signes de danger préchargés viennent de documents publics de l'OMS et de
  l'UNFPA. L'application les affiche comme non relus. Ils existent en français
  seulement. `SERVE_SOURCED_CONTENT=true` dans `render.yaml` les rend visibles :
  ce réglage doit rester à `false` pour un vrai pilote tant que ce contenu n'est
  pas validé dans la console.

## 1. Neon (base de données)

1. Créez un compte sur [neon.com](https://neon.com), sans carte bancaire.
2. Créez un projet nommé `laafi-ma`, région Europe.
3. Copiez la chaîne de connexion. Elle commence par `postgresql://`.

## 2. Render (API)

1. Créez un compte sur [render.com](https://render.com) avec GitHub.
2. Choisissez **New > Blueprint**, puis le dépôt `laafi-ma`.
3. Render lit `render.yaml` et demande quatre valeurs :
   - `DATABASE_URL` : la chaîne copiée sur Neon ;
   - `ADMIN_EMAILS` : votre e-mail au format `["vous@exemple.org"]` ;
   - `ADMIN_BOOTSTRAP_PASSWORD` : un mot de passe d'au moins 10 caractères ;
   - `HF_TOKEN` : le jeton Hugging Face de la section 5 (laissez vide en
     attendant : l'API démarre quand même).
4. Validez, puis attendez la fin du build.
5. Ouvrez `https://laafi-ma-api.onrender.com/health`. Vous devez voir
   `"status":"ok"`.

Si Render a donné une autre adresse, mettez-la dans `API_BASE_URL` à l'étape 3,
et créez aussi sur GitHub la variable `API_BASE_URL` (**Settings > Secrets and
variables > Actions > Variables**) pour l'APK, puis relancez le workflow **APK
de démonstration**.

## 3. Cloudflare (application web et console)

1. Créez un compte sur [cloudflare.com](https://dash.cloudflare.com/sign-up).
2. Ouvrez **Workers & Pages > Create > Worker > Import a repository**, puis
   autorisez GitHub et choisissez le dépôt `laafi-ma`.
3. Nommez le projet `laafi-ma` et validez. `wrangler.jsonc` indique à Cloudflare
   comment construire et publier le site. Le premier build prend plusieurs
   minutes.
4. Notez l'adresse du Worker, de la forme `https://laafi-ma.zongorene08.workers.dev`
   (**Settings > Domains & Routes**).
5. Ajoutez cette adresse à `CORS_ALLOWED_ORIGINS` dans `render.yaml` : sinon
   l'application ne pourra pas joindre l'API.

GitHub Actions reste utilisé pour les tests et pour construire l'APK : Cloudflare
ne fait que publier le site.

## 4. Vérifier

1. Ouvrez la console admin et connectez-vous.
2. Changez votre mot de passe si la console le propose.
3. Ouvrez l'application web et posez une question écrite en français.
4. Téléchargez l'APK depuis la release `demo` et testez-le sur un téléphone.

## 5. Voix et mooré/dioula (Hugging Face ZeroGPU)

Le dossier `hf-space/` du dépôt est une petite application Gradio qui fait
tourner Whisper, MMS et NLLB (avec l'adaptateur mooré) sur une carte graphique
prêtée à la demande par Hugging Face (« ZeroGPU »). L'API sur Render l'appelle
à distance. Aucun texte ni aucun audio n'y est journalisé. Les audios reçus
sont effacés dès leur lecture ; les audios produits par la synthèse restent au
plus une vingtaine de minutes dans le cache du Space.

### Ce qu'il faut savoir avant

- **Compte Hugging Face gratuit** de plus de 30 jours, avec une adresse e-mail
  vérifiée. Sinon, le matériel ZeroGPU n'est pas proposé.
- **Quota : 5 minutes de carte graphique par jour**, pour le compte à qui
  appartient le jeton `HF_TOKEN` (pas pour le compte qui possède le Space).
  Le compteur repart 24 heures après la première utilisation. Une question
  vocale coûte quelques secondes ; chaque texte lu par la synthèse est gardé
  sur le disque de Render et ne coûte qu'une fois (jusqu'au prochain
  redémarrage de Render).
- **Le Space s'endort** après un moment sans visite. Le premier appel peut
  alors prendre plusieurs minutes. L'API attend au plus
  `VOICE_SPACE_TIMEOUT_SECONDS` (180 secondes), puis répond `503` : il suffit
  de réessayer une minute plus tard. Avant une présentation, ouvrez la page du
  Space pour le réveiller.
- **Licence non commerciale** (CC-BY-NC 4.0) pour NLLB, MMS et l'adaptateur
  mooré, voir plus haut.

### Étapes

1. **Créer le Space** (déjà fait pour cette démo : `renezongo/laafi-ma-voice`).
   Sur [huggingface.co/new-space](https://huggingface.co/new-space) : nom
   `laafi-ma-voice`, SDK **Gradio**, matériel **ZeroGPU**, visibilité
   **Public**.
2. **Créer un jeton d'écriture**, seulement pour envoyer le code : **Settings >
   Access Tokens > Create new token**, type **Write**. Ne le collez dans
   aucun fichier.
3. **Envoyer le dossier `hf-space/`** dans le Space. Il faut
   [Git LFS](https://git-lfs.com) pour les gros fichiers de l'adaptateur.
   Dans PowerShell, à la racine du dépôt :

   ```powershell
   git lfs install
   git clone https://huggingface.co/spaces/renezongo/laafi-ma-voice C:\laafi-ma-voice
   robocopy hf-space C:\laafi-ma-voice /E /XD tests __pycache__
   cd C:\laafi-ma-voice
   git add .
   git commit -m "Laafi Ma : voix et traduction"
   git push
   ```

   Git demande un nom d'utilisateur (votre nom Hugging Face) et un mot de
   passe : tapez le jeton d'écriture de l'étape 2. Le dossier
   `hf-space/moore-nllb-lora-adapter/` n'est pas sur GitHub (trop lourd) : sur
   une autre machine, copiez-y d'abord le contenu de
   `backend/services/core-service/models/moore-nllb-lora-adapter/`.
4. **Attendre le démarrage** : onglet **Logs** du Space. Le premier démarrage
   télécharge les modèles (plusieurs minutes). Quand le Space affiche
   « Running », ouvrez l'onglet **État** et cliquez sur **Vérifier**.
5. **Créer le jeton de lecture** pour l'API : **Settings > Access Tokens >
   Create new token**, type **Fine-grained**, sans aucun droit d'écriture
   (un jeton de type **Read** convient aussi). C'est son compte qui paie le
   quota de 5 minutes.
6. **Le donner à Render** : service `laafi-ma-api` > **Environment**.
   `VOICE_SPACE` vaut déjà `renezongo/laafi-ma-voice` (dans `render.yaml`).
   Mettez le jeton de lecture dans `HF_TOKEN`, enregistrez : Render redémarre
   l'API.
7. **Vérifier** : `https://laafi-ma-api.onrender.com/health` doit montrer
   `"voice_backend":"remote"`. Dans l'application, posez une question à la
   voix en mooré. Si la réponse est `503`, attendez que le Space se réveille
   et recommencez.

Pour mettre le Space à jour plus tard, recopiez `hf-space/` dans
`C:\laafi-ma-voice` (même commande `robocopy`), puis `git add .`,
`git commit` et `git push`.
