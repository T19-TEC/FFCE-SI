# FFCE — Dossier de passation

> À joindre **en entier** à toute IA qui reprend le projet, avec
> `SCHEMA.md` et `CARTE.md`. À lire avant d'écrire une ligne.

---

## 0. En chiffres

| | |
|---|---|
| Migrations SQL | **48**, toutes exécutées en production |
| Tables et vues | 118 |
| Fonctions SQL | **402** |
| Modules d'interface | 12 fichiers `js/*.js`, **19 000 lignes** |
| Composants | ~180 |
| Droits atomiques | 56 |
| Applications | 18 |
| Contrôles de livraison automatisés | **18** |

**État** : tout fonctionne, testé **depuis un compte administrateur
uniquement**. C'est la limite majeure : `est_admin()` court-circuite
chaque garde posée depuis la migration 31, donc la moitié des règles
n'a jamais été éprouvée par quelqu'un qui les subit.

---

## 1. Le projet

Plateforme de la **Fédération française pour la citoyenneté et l'égalité
des chances**, association d'éducation populaire. Site vitrine public +
intranet fédéral multi-rôles territorial.

**Pile** — volontairement minimale :

- **Supabase** (PostgreSQL + Auth + Storage, Paris), plan gratuit
- **GitHub** → **Vercel**, déploiement automatique
- **Modules ES natifs** : `index.html` (447 lignes : styles et point de
  montage) + `js/*.js`. **Aucune compilation, aucun `npm install`.**

```
Dépôt : github.com/T19-TEC/FFCE-SI
URL   : https://ibxydmtqdyynteiopjiv.supabase.co
Clé   : sb_publishable_A-2UHxGyxQ1--eEnsULBlQ_eyebc9dh
```

**Arborescence** :

```
ffce/
├── index.html                  styles + <script src="./js/app.js">
├── logo.png
├── js/                         12 modules — voir CARTE.md
├── sql/                        les 48 migrations, une par fichier
├── .github/workflows/controles.yml
├── schema.py  carte.py  controles.py  verifier_modules.py
├── SCHEMA.md  CARTE.md         générés — ne jamais modifier à la main
└── PASSATION.md  AMORCE.md  PAS_A_PAS.md  MODE_EMPLOI.md
```

---

## 2. La méthode — à ne pas modifier

**Protocole en deux temps** (voir `AMORCE.md`) :

- **Temps 1** — l'IA reçoit `PASSATION.md`, `SCHEMA.md`, `CARTE.md` et la
  demande. Elle ne produit **aucun code**. Elle répond : les modules dont
  elle a besoin, les fonctions SQL qu'elle touchera, ce qu'elle ne
  comprend pas, **et ce qu'elle compte refuser ou faire autrement**.
- **Temps 2** — elle reçoit les modules et livre : une migration SQL
  numérotée + les modules modifiés **entiers** + les trois étapes de
  déploiement en tête + ce qu'elle n'a pas fait + ce qui reste risqué.

**Toutes les migrations sont ré-exécutables** : `if not exists`,
`create or replace`, `on conflict`.

**Les contrôles tournent tout seuls** à chaque dépôt sur la branche
`travail`, via GitHub Actions. L'IA n'a pas à les lancer ; elle doit
savoir qu'ils existent et ce qu'ils vérifient.

---

## 3. Les neuf décisions d'architecture à ne pas défaire

1. **Pas de compilation.** Modules ES natifs. C'est ce qui rend le
   projet maintenable par une personne seule.
2. **La logique en base, pas dans l'interface.** Toute règle de droit
   passe par une fonction SQL `security definer`. L'interface *affiche*
   la règle, elle ne la *décide* jamais.
3. **Rien de stocké qui puisse être calculé.** Points d'échelon, totaux
   budgétaires, soldes d'enveloppes, complétude : tout se recalcule à la
   lecture. Un solde stocké est un solde qui finira faux.
4. **Une seule source par donnée.** Les heures d'un bilan de mission
   alimentent l'engagement mensuel, pas un second compteur.
5. **La même règle à un seul endroit.** Si l'écran et la base doivent
   toutes deux la connaître, l'écran appelle la fonction de la base
   (`plan_engagement`, `postes_conferables`).
6. **On ne donne que ce qu'on a.** Un responsable n'ouvre qu'un accès
   dont il dispose lui-même. C'est ce qui empêche l'escalade sans
   maintenir de liste blanche.
7. **Toute décision se motive.** Refus, révocation, abrogation, fusion,
   dotation exceptionnelle : la base **exige** un motif.
8. **L'étiquette et la réalité ne peuvent pas diverger.**
   `source_acces()` dit *pourquoi* une application est ouverte, et
   l'interface reprend ce mot.
9. **Rien ne disparaît de ce qui a produit effet.** Un acte signé
   s'abroge par un autre acte, qui reste au recueil.

---

## 4. Le modèle de droits

**Trois axes indépendants** :

| Axe | Table | Nature |
|---|---|---|
| **Fonction** | `profils.fonction` → `fonctions.niveau` (10–100) | Position + périmètre territorial |
| **Échelon** | `profils.echelon` (1–7) | Progression, points calculés |
| **Postes** | `nominations` → `postes` → `poste_droits` | Mandats révocables, droits atomiques |

**Niveaux** : 10 adhérent · 40 encadrement · 50 responsable local ·
60 référent départemental · 70 délégué régional · 80 directeur de pôle ·
100 admin.

**Seuil « national » = 80.** Au-dessus on voit l'organigramme fédéral et
tout le réseau ; en dessous, le sien. Ce chiffre apparaît dans
`mes_applications`, `mes_directions`, `plan_territoires` — **le changer
suppose de le changer aux trois endroits**.

**Rang des postes** (`postes.rang`) : on ne confère qu'un poste de rang
**strictement inférieur** à son plafond (`mon_plafond_nomination()`).

### Sept séparations garanties en base

1. Voir ≠ écrire → `puis_je_ecrire_a()`
2. Supervision strictement descendante → `peut_superviser()`
3. Ordonnancer ≠ payer
4. **Garde hiérarchique** → `puis_je_agir_sur()` : nul n'agit sur un
   poids égal ou supérieur, ni sur soi-même. L'admin excepté.
5. **Émargement ≠ bulletin** → `votes` et `bulletins` sans lien.
   `bulletins` n'a **aucune politique de lecture**. `presences_assemblee`
   est encore distincte : on peut être présent sans voter.
6. **Préparer ≠ engager** → `points.engager`. Tout le monde monte un
   panier, seul l'habilité le débite.
7. **Le cabinet prépare, la présidence signe** → `puis_je_prendre_acte()`
   vs `puis_je_signer_acte()`.

**Voie locale** (migration 31) : quatre conditions cumulatives —
territoire dans mon périmètre, garde hiérarchique, poste strictement
moins lourd, jamais un droit sensible. Le journal distingue les deux
voies.

---

## 5. Les dix-huit familles d'erreurs

Chacune a été commise **au moins une fois** ici. `controles.py` les
vérifie toutes, et l'automate le lance à chaque dépôt.

| # | Famille | Conséquence si ignorée |
|---|---|---|
| 1 | Composant appelé mais non défini | Écran blanc |
| 2 | Fonction SQL invoquée mais absente | Erreur à l'usage |
| 3 | Définition en double | La seconde écrase la première, en silence |
| 4 | `returns table` redéfinie avec d'autres colonnes, sans `drop` | La migration échoue |
| 5 | Objet lu avant sa création **dans le même fichier** | La migration échoue |
| 6 | Jointure mêlée `from x a, y join z on …` | Le JOIN ne voit pas `a` |
| 7 | CTE récursive sans `with recursive` | La migration échoue |
| 8 | Contrainte `check` violée par une valeur nouvelle | La migration échoue |
| 9 | Fonction `stable` qui écrit, même indirectement | **Erreur silencieuse** : écran vide |
| 10 | Objet cité inexistant (nom deviné) | La migration échoue |
| 11 | Conversion `::uuid` sans garde | Dans une politique RLS, un refus devient une **panne** |
| 12 | Fonction « redéfinie » sous un nom inexistant | Crée une **seconde** fonction, jamais appelée |
| 13 | Colonne absente de la table visée | La migration échoue |
| 14 | Droit invoqué mais jamais déclaré | Renvoie **faux** : refuse tout le monde en silence |
| 15 | Colonne absente du résultat d'une fonction | La migration échoue |
| 16 | Composant défini mais jamais monté | Livraison à moitié appliquée, sans signal |
| 17 | Import de module manquant ou pointant dans le vide | Page blanche |
| 18 | Modules qui ne se chargent pas | Le site ne démarre pas |

**Ce que le script ne voit pas** : la famille 8 (il ne connaît pas les
domaines énumérés — lire la contrainte en vigueur avant d'insérer une
valeur nouvelle), les corps PL/pgSQL non résolus au `CREATE`, et le sens.

### Domaines énumérés élargis — à connaître

- `postes.couleur` : neutre, or, bleu, vert, rouge, bordeaux, nuit,
  brun, action, framboise
- `applications.couleur` : bleu, bordeaux, nuit, brun, action, framboise
- `commandes.statut` : brouillon, a_valider, deposee, validee, expediee,
  recue, refusee, annulee
- `notes_frais.statut` : brouillon, deposee, a_completer, instruite,
  validee, payee, refusee
- `nf_lignes.etat` : proposee, retenue, ecartee, a_preciser
- `groupes_travail.statut` : propose, actif, refuse, archive
- `conversations.type` : privee, groupe, organique
- `actes_internes.portee` : federale, locale
- `directions.couleur` : **aucune contrainte**

### Les noms qu'on écrit spontanément faux

| Ce qu'on tape | Le vrai nom |
|---|---|
| `groupes` | `groupes_travail` |
| `dossiers_discipline` | `dossiers` |
| `progressions` | `progression` (singulier) |
| `gt_taches.maj_le` | `faite_le` |
| `distinctions.attribue_le` | `decernee_le` |
| `investissements.ordonnancee_le` | `ordonnance_le` |
| `mes_assemblees().date_assemblee` | `date_tenue` |
| `groupes_travail.titre` | `nom` |
| `structures.piloter` | `structure.creer` |
| `chancellerie.tenir` | `chancellerie.bareme` |
| `regler_membre` | `modifier_membre` |
| `annuler_acte` | `controler_acte` |
| `publications_du_moment()` | `suggestions_disponibles()` |
| `jetons_carte` | `profils.jeton_carte` |

**Ne jamais écrire de SQL de mémoire. Tout est dans `SCHEMA.md`.**

### Fonctions redéfinies plusieurs fois — piège n° 1

`SCHEMA.md` ne montre que la **version en vigueur**. Si vous ouvrez les
migrations, sachez que `ce_qui_attend` est redéfinie en 25, 27, 29 et 33 ;
`mes_applications` en 11, 15, 19, 20, 30 et 35 ; `signer_acte` en 32, 39
et 41 ; `solde_points` en 28, 38 et 42.

### Trois fonctions à volatilité corrigée (migration 29)

`consulter_profil`, `fiche_membre`, `nouveaux_a_accueillir_maj` étaient
`stable` alors qu'elles écrivent. **Ne jamais les redéfinir sans remettre
la volatilité**, sinon la panne revient.

---

## 6. Le style

### Le ton

- **Français soigné, aucun jargon technique** dans l'interface.
- Un message d'erreur **explique et oriente** :
  - ✗ « Accès refusé. »
  - ✓ « Ce poste pèse autant ou plus que le vôtre. Vous ne pouvez nommer
    qu'en dessous de vous. »
- Un écran vide **dit pourquoi il est vide**.
- Les règles importantes s'écrivent **à l'écran**, pas seulement dans le
  code : « Une équipe n'hérite de rien », « Préparer n'est pas engager ».

### Les commentaires

**En français, ils expliquent le *pourquoi*, jamais le *quoi*.** Chaque
migration s'ouvre sur un cartouche disant quel problème réel elle
résout, et se ferme sur les vérifications et les pièges qu'elle laisse.

### Typographie et CSS

Apostrophes `\u2019` dans les littéraux JS. Guillemets « ».

Classes existantes uniquement : `panneau, tete, corps, ligne, spread,
row, field, stack, btn, btn sm, btn light, btn danger, tag, tag vert,
tag rouge, tag or, tag bleu, alerte, alerte ok, alerte err, chiffres,
jauge, vide, muted, small, mono, eyebrow, carte, tuiles, grid, hr`.

Variables : `--bleu --bordeaux --nuit --action --framboise --ciel --brun
--gris --papier --creme --filet --encre --vert --rouge --laiton --taupe`
et leurs `-clair`.

**Aucun effet décoratif** : pas d'ombre, pas de dégradé, pas de contour.

### Le code

- Composants `function NomEnPascalCase({ props })`, `export` si employés
  ailleurs.
- `useState`, `useEffect`, `useCallback` importés **depuis `socle.js`**,
  jamais depuis esm.sh.
- Un helper `appel(fn, args, messageSucces)` par écran, traitant `error`
  **et** `data.ok === false`.
- **Interdit** : `localStorage`, `sessionStorage`, toute bibliothèque non
  déjà importée. Le QR code, la carte et la projection sont écrits à la
  main pour cette raison.

---

## 7. Les arbitrages rendus — ne pas les défaire sans en parler

1. **Les équipes n'héritent d'aucun droit.** Elles reçoivent une fiche,
   bornée à ce que le validateur détient.
2. **Pas d'alerte par fichier envoyé.** Un journal des envois — qui,
   quand, vers qui, nom, taille — **jamais le contenu**. « Une trace,
   pas une clé. »
3. **Pas de récépissé de vote.** Un récépissé prouvant *ce qu'on a voté*
   rend l'achat de voix vérifiable. Ce qui existe : un **récépissé
   d'émargement**, horodaté, sans le choix.
4. **Pas de coffre-fort de mots de passe.** Sans compilation, tout
   secret stocké dans Supabase est déchiffrable par qui accède à la
   base. Proposé à la place : un registre des accès. **Décision
   attendue.**
5. **Pas de lecture automatisée de LinkedIn** — conditions
   d'utilisation, API, base légale. Proposé : un référentiel déclaratif.
   **Décision attendue.**
6. **Les points ne figurent pas au budget.** Un point est un droit de
   tirage, pas une monnaie comptable. Ce qui y entre : la valeur réelle
   du matériel expédié (6061 en charge, 7061 en produit).
7. **La supervision ne s'applique pas aux conversations organiques.**
8. **La présidence de structure ne se confère pas localement.**
9. **Le fond de carte est une dépendance externe assumée** ; si le
   chargement échoue, le tableau reste et l'écran le dit.

---

## 8. Ce qui reste à faire

### Bloquant, hors développement

1. **Brevo non configuré** — aucune notification, aucune
   réinitialisation de mot de passe. Or les mesures disciplinaires
   ouvrent des délais de recours **qui courent**. Le point le plus grave.
2. **Test multi-comptes** — jamais fait. Créer au minimum : un adhérent,
   un responsable local, un président de structure, un trésorier, un
   membre de la DAJ.
3. **Un seul administrateur.**
4. **Mentions légales et politique de confidentialité vides** — il y a
   beaucoup à y écrire : journal des pièces jointes, fichier de contacts
   tiers, jeton de carte, inscriptions externes aux événements.
5. **Connexion Google** — une demi-heure via Supabase.

### À vérifier sur ce qui est livré

- Le **QR code** de la carte d'adhérent n'a **jamais été scanné**.
- La **carte du réseau** n'a jamais été rendue dans un navigateur.
- La **fusion de territoires** est irréversible : la tester sur deux
  territoires fictifs.

### Lots restants

**Lot 15 — Projets.** Les projets remontés au national ne sont
traitables nulle part (`faire_remonter` existe depuis la migration 22,
aucun écran ne reçoit). L'onglet Projets de Mon comité ne permet pas de
monter un projet complet : budget, étapes, partenaires, pièces, et le
lien avec les points affectés (`soutiens_projet` existe déjà).

**Lot 16 — Deux écrans.** Mon compte allégé quand le dossier est
complet. Parcours par étapes — cotiser, déposer une note de frais, poser
sa candidature — avec sauvegarde automatique des brouillons.

**Lot 17 — Sur décision de l'utilisateur.** Registre des accès (§ 7.4),
OCR en pré-remplissage suggéré, référentiel de talents déclaratif
(§ 7.5).

### Aspérités connues

- Le rattachement et la fusion de territoires demandent un identifiant
  collé dans une invite (`prompt`). Un sélecteur d'arbre serait mieux.
- Les commandes déposées avant la migration 38 n'ont pas d'adresse de
  livraison.
- L'effacement d'une pièce jointe se fait côté navigateur ; si l'appel
  Storage échoue, le fichier reste (le message est retiré, l'échec est
  affiché).
- Le PV et la feuille de présence sortent en texte et CSV, pas en PDF —
  un vrai PDF demanderait `jsPDF`, la première dépendance du projet.

---

## 9. Où trouver quoi

Voir `CARTE.md` pour le détail. En résumé :

| Domaine | Module | Migrations |
|---|---|---|
| Site public, connexion, inscription | `vitrine.js` | 01, 14 |
| Menu, tableau de bord, fil, routes | `espace.js` | 15, 20, 30, 43 |
| Compte, carte, dossier, engagement, passeport | `membre.js` | 01, 12, 27, 43 |
| Groupes, équipes, messagerie | `collectif.js` | 03, 04, 33, 35, 41 |
| Formations, chancellerie, distinctions | `formation.js` | 02, 16, 26, 39 |
| Notes de frais, budget, ressources, enveloppes | `finances.js` | 06, 23, 28, 36, 38, 40, 42 |
| Comité, gestion locale, carte, pilotage | `structure.js` | 18, 22, 39, 40 |
| Habilitations, cabinet, affaires publiques, com | `direction.js` | 07, 31, 32, 37, 41 |
| Assemblées, scrutin, discipline | `statutaire.js` | 08, 17, 44, 45, 46 |
| Événements | `evenements.js` | 47 |

**Postes à pourvoir** (aucun titulaire) :

```sql
select nommer((select id from profils where email='…'),
              'president_federation', null, null, 'Élu par l''AG du …');
select nommer((select id from profils where email='…'),
              'affaires_publiques', null, null, 'Désigné le …');
select nommer((select id from profils where email='…'),
              'evenementiel', null, null, 'Désigné le …');
```

---

## 10. À celui qui reprend

Ce projet tient parce que trois choses ont été tenues : **la règle vit
dans la base**, **rien n'est stocké qui puisse être calculé**, et
**chaque erreur commise a été transformée en contrôle automatique**
plutôt qu'en résolution de faire attention.

Les dix-huit contrôles ont attrapé, dans l'ordre : une table inventée,
une colonne inventée, deux droits inventés, deux fonctions inventées, une
fonction lue avant sa création, une conversion `::uuid` qui aurait
transformé un refus en panne dans une politique de sécurité, deux
composants livrés mais jamais montés, un commentaire coupé en deux par
un découpage — et trois fonctions `stable` qui écrivaient, lesquelles
expliquaient à elles seules trois pannes que personne n'arrivait à
diagnostiquer.

**Quand une erreur passe au travers, la bonne réponse n'est pas de faire
plus attention : c'est d'élargir le contrôle.** C'est ainsi que les
dix-huit se sont construits.

Et la question à se poser avant chaque livraison : *est-ce que cet écran
dirait la vérité à quelqu'un qui n'a pas les droits ?* Si la réponse est
« il verrait un bouton qui ne marche pas », ce n'est pas fini.
