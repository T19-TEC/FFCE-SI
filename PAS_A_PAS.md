# FFCE — Pas à pas

> Deux parties, et rien d'autre.
> **A. Ce qui se fait UNE FOIS** — une demi-heure, jamais à refaire.
> **B. Ce qui se fait À CHAQUE MISE À JOUR** — cinq minutes.

---

# A. UNE SEULE FOIS

## A1 — Déposer tous les fichiers sur GitHub

Sur `github.com/…/ffce` → bouton **« Add file » → « Upload files »** →
glissez tout → **« Commit changes »**.

Arborescence à obtenir :

```
ffce/
├── index.html
├── logo.png
├── js/                     12 fichiers
├── sql/SQL/                les migrations, une par fichier
├── .github/workflows/controles.yml
├── schema.py  carte.py  controles.py  verifier_modules.py
├── SCHEMA.md  CARTE.md
├── PASSATION.md  MODE_EMPLOI.md  AMORCE.md  PAS_A_PAS.md
```

**Pour créer un dossier** : « Add file » → « Create new file », puis
tapez le chemin entier, par exemple `.github/workflows/controles.yml`.
Les barres obliques créent les dossiers toutes seules.

## A2 — Autoriser l'automate à écrire

**Settings → Actions → General → Workflow permissions**
→ cocher **« Read and write permissions »** → **Save**.

**Sans cette case, rien ne fonctionnera.** C'est ce qui permet à la
machine de réenregistrer `SCHEMA.md` et `CARTE.md` après les avoir
régénérés.

## A3 — Créer la branche de travail

En haut à gauche de la page du dépôt, le menu qui affiche **`main`** →
tapez **`travail`** → **« Create branch: travail from main »**.

C'est là que vous déposerez tout, désormais. `main` reste ce qui est en
ligne.

## A4 — Protéger `main`

**Settings → Branches → Add branch protection rule**

- Branch name pattern : **`main`**
- Cocher **« Require status checks to pass before merging »**
- Dans la case de recherche qui apparaît, choisir **« verifier »**
  *(le nom de la tâche du fichier `controles.yml`)*
- **Create**

> Si « verifier » n'apparaît pas encore dans la liste, c'est que
> l'automate n'a jamais tourné. Faites d'abord A5, puis revenez ici.

**Ce que cela produit** : GitHub refusera *physiquement* de faire passer
en production quoi que ce soit dont les contrôles ne sont pas verts.
C'est la seule protection qui ne dépend pas de votre vigilance.

## A5 — Vérifier que la machine tourne

Onglet **Actions** → **« Contrôles FFCE »** → bouton **« Run workflow »**
→ choisir la branche `travail` → **Run**.

Une minute plus tard :

- **Pastille verte** — tout est en place.
- **Croix rouge** — cliquez dessus : le rapport complet s'affiche, avec
  la ligne fautive. Copiez-le et envoyez-le-moi.

**Comment savoir que les abrégés ont bien été régénérés** : allez dans
l'historique des dépôts (onglet **Code**, puis « commits »). Vous devez
voir un dépôt intitulé **« Abrégés régénérés automatiquement »**, signé
« Contrôles FFCE ». C'est la preuve que le mécanisme fonctionne.

## A6 — Vérifier que Vercel ne déploie que `main`

Sur Vercel → votre projet → **Settings → Git → Production Branch** →
doit indiquer **`main`**.

C'est ce qui garantit que la branche `travail` ne met rien en ligne.

**A1 à A6 : terminé. Vous ne referez plus jamais cela.**

---

# B. À CHAQUE MISE À JOUR

## B1 — Télécharger les trois documents

Depuis GitHub, branche `main`. Pour chacun : ouvrez le fichier → bouton
**« Raw »** en haut à droite → `Ctrl+S` (ou `Cmd+S`).

1. `PASSATION.md`
2. `SCHEMA.md`
3. `CARTE.md`

> Les deux derniers sont régénérés par la machine à chaque dépôt : ils
> sont donc toujours justes. C'est tout l'intérêt du mécanisme.

## B2 — Ouvrir une conversation neuve

Joindre **ces trois fichiers uniquement**. Aucun code.

Copier le message contenu dans `AMORCE.md`, et écrire votre demande à la
fin.

## B3 — L'IA vous dit quoi lui envoyer

Elle ne produit **aucun code** dans cette première réponse. Elle répond :

- les modules `js/*.js` dont elle a besoin
- les fonctions SQL qu'elle compte toucher
- ce qu'elle ne comprend pas
- **ce qu'elle compte refuser ou faire autrement, et pourquoi**

Vous téléchargez les modules demandés (bouton **Raw**) et vous les
envoyez. **Rien de plus que ce qu'elle a demandé.**

## B4 — Recevoir et déposer

**a) La migration SQL** → Supabase → SQL Editor → coller **une seule
migration** → **Run**.

> Une seule à la fois. Tout ce qui est collé s'exécute en une
> transaction : une erreur annule le bloc entier.

**b) Les modules** → GitHub → **passer sur la branche `travail`** (menu
en haut à gauche) → « Add file » → « Upload files » → déposer les
modules dans `js/` et la migration dans `sql/SQL/` → **« Commit
changes »**.

## B5 — Regarder le feu

Onglet **Actions**, une minute plus tard.

- **Vert** → passez à B6.
- **Rouge** → cliquez, copiez le rapport, renvoyez-le à l'IA. **Vous ne
  passez pas à B6.**

## B6 — Mettre en ligne

Onglet **Pull requests** → **« New pull request »**
→ base : `main`, compare : `travail` → **« Create pull request »** →
**« Merge pull request »**.

Le bouton de fusion est **grisé tant que les contrôles ne sont pas
verts**. C'est voulu.

Vercel déploie dans la minute.

## B7 — Vérifier le site

`Ctrl + Maj + R` pour vider le cache.

Si une page reste blanche : `F12` → onglet Console → l'erreur nomme le
module et la ligne. Copiez-la.

---

# Ce qui tourne tout seul, et ce qui ne tourne pas

| | Automatique ? |
|---|---|
| Régénérer `SCHEMA.md` et `CARTE.md` | **Oui**, à chaque dépôt sur `travail` |
| Passer les dix-huit contrôles | **Oui** |
| Charger les modules pour vérifier qu'ils démarrent | **Oui** |
| Bloquer une mise en ligne fautive | **Oui**, grâce à A4 |
| Exécuter la migration dans Supabase | **Non** — c'est vous, à chaque fois |
| Télécharger les trois documents avant une session | **Non** — c'est vous |
| Décider ce qu'il faut faire | **Non**, et c'est heureux |

---

# Les cinq pièges

1. **Oublier A2** — la case « Read and write permissions ». Sans elle,
   les abrégés ne se réenregistrent jamais, et vous joindrez des
   documents périmés sans le savoir.
2. **Déposer sur `main` au lieu de `travail`.** Vérifiez le menu de
   branche en haut à gauche avant chaque dépôt.
3. **Coller deux migrations ensemble** dans Supabase.
4. **Modifier `SCHEMA.md` ou `CARTE.md` à la main.** Ils sont générés :
   votre modification sera écrasée au dépôt suivant.
5. **Envoyer à l'IA un module qu'elle n'a pas demandé.** Elle le
   réécrira « pour aider », et vous perdrez des modifications.
