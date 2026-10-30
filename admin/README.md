# Laafi Ma — console web

Console de gestion (validateurs et administrateurs) et page publique de
statistiques anonymes. React 19 + TypeScript + Tailwind 4 + Vite 8.
Le contrat d'API est `../docs/API.md`.

## Lancer en local

```
npm ci
npm run dev
```

L'API `core-service` est attendue sur `http://127.0.0.1:8000`, redéfinissable
via `VITE_API_BASE_URL` (voir `.env.example`).

## Accès

- `/login` : comptes `admin` et `validator` (e-mail + mot de passe). Les
  agents de santé reçoivent un message « accès réservé » : ils utilisent l'app.
- `/public` : statistiques publiques, sans compte, actualisées toutes les 60 s.

| Page | Route | Rôles |
| --- | --- | --- |
| Tableau de bord | `/` | admin |
| Base de réponses | `/kb`, `/kb/new`, `/kb/:id` | validator, admin |
| Signes de danger | `/danger-signs` | validator, admin |
| Questions sans réponse | `/unanswered` | validator, admin |
| Capsules | `/capsules`, `/capsules/new`, `/capsules/:id` | validator, admin |
| Annuaire d'aide | `/help-services` | admin |
| Districts | `/districts` | admin |
| Utilisateurs | `/users` | admin |
| État des services | `/services` | admin |

Les règles sont centralisées dans `src/lib/roles.ts` ; le backend reste
l'autorité (403).

## Vérifications

```
npm run lint    # oxlint
npm test        # node --test (rôles, conversions API, périodes, erreurs)
npm run build   # tsc -b && vite build → dist/
```

Aucune donnée fictive : chaque liste vide affiche un état vide expliquant
d'où doivent venir les données (sources officielles).
