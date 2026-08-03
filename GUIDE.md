# FFCE — Guide

> Ce document remplace `MODE_EMPLOI.md` et `PAS_A_PAS.md`, que vous
> pouvez supprimer du dépôt.
>
> Tout se fait depuis GitHub, Supabase et votre navigateur. **Aucune
> ligne de commande.**

---

# 1. Comment le dispositif fonctionne

## Les quatre programmes

Ils vivent à la racine du dépôt. Ils **lisent** votre code et
**écrivent** deux résumés.

| Programme | Ce qu'il fait |
|---|---|
| `schema.py` | Lit les migrations `sql/*.sql` → écrit **`SCHEMA.md`**. 81 ko au lieu d'un million d'octets. Pour chaque fonction, il ne garde que la **dernière** définition, celle qui est en vigueur. |
| `carte.py` | Lit les modules `js/*.js` → écrit **`CARTE.md`**. Le sommaire de l'interface, sans le code. |
| `verifier_modules.py` | **Charge réellement** les dix modules avec des substituts de Preact et Supabase. La seule vérification qui prouve que le site démarrera. |
| `controles.py` | Lit tout et cherche les incohérences : les **dix-huit familles d'erreurs**. |

## L'automate

`.github/workflows/controles.yml` n'est **pas** un programme de contrôle.
C'est l'ordre donné à GitHub de lancer les quatre ci-dessus, tout seul,
à chaque dépôt.

Sur **`travail`** : il régénère les deux abrégés, passe les contrôles,
charge les modules, et **réenregistre `SCHEMA.md` et `CARTE.md` dans le
dépôt**.

Sur **`main`** : il contrôle, mais n'écrit jamais — il se heurterait à la
protection qu'il doit lui-même satisfaire.

## Les deux branches

| | Rôle |
|---|---|
| **`travail`** | On y dépose. C'est le brouillon. |
| **`main`** | Ce qui est en ligne. Protégée : rien n'y entre sans contrôles verts. Vercel ne déploie que celle-là. |

## Pourquoi les abrégés sont toujours justes

Parce que la machine les régénère à chaque dépôt sur `travail`, et que
`main` les reçoit par fusion. Vous téléchargez donc toujours des
documents à jour — c'est ce qui empêche une IA de travailler sur un
schéma périmé et d'inventer des colonnes.

---

# 2. Le cycle, à chaque mise à jour

## Étape 1 — Télécharger les trois documents

Sur GitHub, **branche `main`**. Pour chacun : ouvrez le fichier → bouton
**« Raw »** en haut à droite → `Ctrl+S` (ou `Cmd+S`).

1. `PASSATION.md`
2. `SCHEMA.md`
3. `CARTE.md`

## Étape 2 — Ouvrir une conversation neuve

Joignez **ces trois fichiers uniquement**. Aucun code.

Copiez le message d'`AMORCE.md`, et écrivez votre demande à la fin.

## Étape 3 — L'IA répond sans coder

Elle doit vous donner six choses : ce qu'elle a compris, les modules dont
elle a besoin, les fonctions SQL qu'elle touchera, les implications
qu'elle voit, **ce qu'elle refuse**, et ce qu'elle ne comprend pas.

**Si elle produit du code à ce stade, rappelez-lui le protocole.**

## Étape 4 — Lui envoyer les modules demandés

Uniquement ceux-là. Téléchargez-les depuis GitHub par le bouton
**« Raw »**.

## Étape 5 — Recevoir et déposer

**a) La migration SQL** → Supabase → SQL Editor → coller **une seule
migration** → **Run**.

> Tout ce qui est collé s'exécute en une seule transaction. Une erreur
> annule le bloc entier, y compris ce qui la précédait. **Une à la fois.**

**b) Les fichiers** → GitHub → **basculer sur la branche `travail`**
(menu en haut à gauche) → puis, pour chaque fichier existant : cliquer
dessus, icône **crayon**, `Ctrl+A`, coller, **« Commit directly to the
`travail` branch »**.

Pour un fichier nouveau : « Add file » → « Create new file », tapez le
chemin complet (`sql/49_ma_migration.sql`), collez, commit.

## Étape 6 — Regarder la pastille

Onglet **Actions**, une minute plus tard.

- **Verte** → passez à l'étape 7.
- **Rouge** → cliquez, copiez **tout le rapport**, renvoyez-le à l'IA.
  **N'allez pas plus loin.**

## Étape 7 — Mettre en ligne

Onglet **Pull requests** → **New pull request** →
base : **`main`**, compare : **`travail`** → un **titre** (obligatoire,
n'importe lequel) → **Create pull request** → **Merge pull request** →
**Confirm merge**.

Vercel déploie dans la minute.

## Étape 8 — Vérifier le site

`Ctrl + Maj + R` pour vider le cache.

Si une page reste blanche : `F12` → onglet **Console** → l'erreur nomme
le module et la ligne. Copiez-la.

---

# 3. Quand quelque chose ne va pas

## L'automate est rouge

Cliquez sur l'exécution. Le rapport complet s'affiche. **Copiez-le en
entier** — pas seulement la dernière ligne — et renvoyez-le.

Lisez la ligne `ANOMALIES BLOQUANTES : N`. Si `N` vaut 0 et que c'est
tout de même rouge, c'est une étape de l'automate qui a échoué, pas
votre code : dites-le.

## Une migration est refusée par Supabase

Copiez le message **avec le numéro de ligne**. **Rien n'a été appliqué**,
il n'y a rien à défaire.

## Une action affiche « Erreur : … » dans le site

C'est un message écrit par la base pour être lu. Copiez-le tel quel : il
dit ce qui manque.

## Une page est blanche

`F12` → Console. L'erreur nomme le module et la ligne.

## Quelque chose a disparu du menu

Ce n'est probablement pas une panne. Vérifiez dans l'ordre :

1. La personne détient-elle le droit requis ?
2. La direction n'ouvre-t-elle qu'une seule application ? Dans ce cas
   elle est repliée sous « Mon activité » — c'est voulu.

## Savoir ce qui est réellement en base

Dans le SQL Editor :

```sql
select code, nom, direction, droit_requis from applications order by ordre;
select code, nom, sensible from droits order by code;
select * from organigramme();
```

## Les deux branches ont divergé

Symptôme : `travail` est rouge avec des anomalies que `main` n'a pas.

**Pull requests → New pull request →** base : **`travail`**, compare :
**`main`** *(dans ce sens)* → titre → Create → Merge. `travail` redevient
identique à `main`.

---

# 4. Ce qui ne doit jamais arriver

| Interdit | Pourquoi |
|---|---|
| Fusionner vers `main` sur une pastille rouge | Les dix-huit contrôles existent parce que chaque famille d'erreur a déjà cassé quelque chose ici |
| Coller deux migrations ensemble dans Supabase | Une erreur dans la seconde annule la première |
| Modifier `SCHEMA.md` ou `CARTE.md` à la main | Ils sont générés : la retouche sera écrasée et faussera la session suivante |
| Renuméroter ou supprimer une migration passée | Le dépôt doit refléter la base. Une migration fautive se corrige par une migration **suivante** |
| Ré-exécuter une vieille migration « pour être sûr » | Elle défera ce que les suivantes ont corrigé. La 32 remettrait le cabinet sous la Direction générale |
| Envoyer à l'IA un module qu'elle n'a pas demandé | Elle le réécrira « pour aider », et vous perdrez des modifications |
| Déposer directement sur `main` | Court-circuite les contrôles et fait diverger les branches |

---

# 5. Quelle IA

**Google AI Studio** plutôt que l'application Gemini, pour trois raisons
concrètes :

- vous pouvez y coller `PASSATION.md` en **instruction système**, une
  fois pour toutes : le protocole tient sur toute la conversation au
  lieu de se diluer ;
- le contexte y est plus large, et la température réglable — moins
  d'invention ;
- la conversation n'est pas encombrée de suggestions.

**Réserve honnête** : je ne peux pas comparer les modèles sérieusement.
Ce que je sais tient à un fait vérifiable : la migration 44 de ce
projet, écrite par une autre IA, contenait **une fuite de données** —
n'importe quel membre pouvait lister qui avait donné pouvoir à qui — et
trois fonctions qui échouaient à chaque appel.

Ce n'était pas un défaut d'intelligence, mais de méthode : écrire sans
le schéma sous les yeux, et ne pas se demander qui a le droit de lire.
**`SCHEMA.md` supprime la première cause. La revue de sûreté de
l'amorce attaque la seconde.**

Quel que soit le modèle : jugez-le sur les trois questions à la fin
d'`AMORCE.md`, et **ne fusionnez jamais sur une pastille rouge**.

---

# 6. Ce qui reste à faire

## Bloquant, hors développement

1. **Brevo non configuré.** Aucune notification, aucune réinitialisation
   de mot de passe. Or les mesures disciplinaires ouvrent des délais de
   recours **qui courent**. C'est le point le plus grave du projet.
2. **Test multi-comptes — jamais fait.** `est_admin()` court-circuite
   toutes les gardes posées depuis la migration 31 : la moitié des
   règles n'a jamais été éprouvée par quelqu'un qui les subit. Créer au
   minimum : un adhérent, un responsable local, un président de
   structure, un trésorier, un membre de la DAJ.
3. **Un seul administrateur** — risque de perte d'accès.
4. **Mentions légales et politique de confidentialité vides.** Il y a
   beaucoup à y écrire : journal des pièces jointes, fichier de contacts
   tiers, jeton de carte d'adhérent, inscriptions externes aux
   événements.
5. **Connexion Google** — une demi-heure via Supabase.

## À vérifier sur ce qui est livré

- Le **QR code** de la carte d'adhérent n'a **jamais été scanné**. Testez
  avec un téléphone. S'il ne se lit pas, il faudra une bibliothèque.
- La **carte du réseau** n'a jamais été rendue dans un navigateur.
- La **fusion de territoires** est irréversible et touche toutes les
  tables : testez-la sur deux territoires fictifs.

## Postes sans titulaire

```sql
select nommer((select id from profils where email='…'),
              'president_federation', null, null, 'Élu par l''AG du …');
select nommer((select id from profils where email='…'),
              'affaires_publiques', null, null, 'Désigné le …');
select nommer((select id from profils where email='…'),
              'evenementiel', null, null, 'Désigné le …');
```

Tant que `president_federation` n'est attribué à personne, seul
l'administrateur peut signer un acte.

## Lots restants

**Lot 15 — Projets.**
Les projets remontés au national ne sont traitables nulle part :
`faire_remonter` existe depuis la migration 22, aucun écran ne reçoit
les remontées. Et l'onglet Projets de Mon comité ne permet pas de monter
un projet complet — il manque le budget, les étapes, les partenaires,
les pièces, et le lien avec les points déjà affectés
(`soutiens_projet` existe déjà, migration 40).
*Modules : `structure.js`. Migrations à lire : 22, 40.*

**Lot 16 — Deux écrans à refondre.**
Mon compte allégé une fois le dossier complet : réduire les sections,
supprimer la barre de progression, ne laisser que « dossier complet » et
un moyen de consulter. Et les parcours par étapes — cotiser, déposer une
note de frais, poser sa candidature — avec indicateur de progression et
sauvegarde automatique des brouillons.
*Modules : `membre.js`, `finances.js`.*

**Lot 17 — Sur vos décisions, pas sur du travail.**
- **Registre des accès** à la place du coffre-fort de mots de passe
  (quel service, qui le détient, où est le secret, quand il a été
  changé — jamais le secret lui-même).
- **OCR des justificatifs** en pré-remplissage suggéré, jamais en
  saisie automatique.
- **Référentiel de talents déclaratif** à la place de la lecture de
  LinkedIn.

## Aspérités connues

- Le rattachement et la fusion de territoires demandent un identifiant
  collé dans une invite. Un sélecteur d'arbre serait mieux.
- Les commandes déposées avant la migration 38 n'ont pas d'adresse de
  livraison : la logistique verra un blanc.
- L'effacement d'une pièce jointe se fait côté navigateur ; si l'appel
  échoue, le fichier reste — le message est retiré, l'échec est affiché.
- Le procès-verbal et la feuille de présence sortent en texte et CSV,
  pas en PDF. Un vrai PDF demanderait `jsPDF`, première dépendance du
  projet.
- Les inscriptions publiques aux événements n'ont pas de captcha. Si un
  événement prend de l'ampleur, activez la validation manuelle.

---

# 7. Les fichiers du dépôt

| Fichier | Rôle | Déployé ? |
|---|---|---|
| `index.html` | Styles et point de montage, 447 lignes | Oui |
| `js/*.js` | Les 12 modules d'interface | Oui |
| `logo.png` | | Oui |
| `sql/*.sql` | Les 48 migrations | Non — exécutées à la main dans Supabase |
| `.github/workflows/controles.yml` | L'ordre donné à GitHub | Non |
| `schema.py` `carte.py` `controles.py` `verifier_modules.py` | Les quatre programmes | Non |
| `decouper.py` `livrer.py` | Outils d'atelier | Non |
| `SCHEMA.md` `CARTE.md` | **Générés** — à joindre à l'IA | Non |
| `PASSATION.md` | Les règles — à joindre à l'IA | Non |
| `AMORCE.md` `GUIDE.md` | Pour vous | Non |
