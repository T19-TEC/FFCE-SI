# AMORCE — le message à copier au début de chaque session

> Copiez le bloc ci-dessous **tel quel**, joignez les trois fichiers
> indiqués, et écrivez votre demande à la fin. Rien d'autre.
>
> Ce protocole existe pour une raison : sans lui, l'IA vous demandera
> le code entier « pour être sûre », et vous paierez 19 000 lignes à
> chaque fois. Avec lui, elle vous dit d'abord quels fichiers envoyer.

---

## À joindre

1. `PASSATION.md` — les règles du projet
2. `SCHEMA.md` — l'abrégé de la base (généré)
3. `CARTE.md` — la carte des modules (générée)

**Aucun fichier de code.** Pas encore.

---

## Le message

```
Je reprends le projet FFCE. Tu trouveras en pièces jointes :
— PASSATION.md : les règles du projet, à lire en entier
— SCHEMA.md    : l'abrégé de la base en vigueur
— CARTE.md     : la carte des modules d'interface

PROTOCOLE — deux temps, sans exception.

TEMPS 1. Tu ne produis AUCUN code dans ta première réponse. Tu réponds
uniquement, et brièvement :
  a) les modules `js/*.js` dont tu as besoin, d'après CARTE.md
  b) les fonctions SQL que tu comptes créer ou modifier, d'après SCHEMA.md
  c) ce que tu ne comprends pas encore dans ma demande
  d) ce que tu comptes refuser ou faire autrement, avec la raison

Si CARTE.md et SCHEMA.md te suffisent, dis-le : je ne t'enverrai rien.

TEMPS 2. Je t'envoie les modules demandés. Tu livres alors :
  — une migration SQL numérotée (le numéro suivant le dernier de SCHEMA.md)
  — le ou les modules modifiés, ENTIERS
  — les trois étapes de déploiement en tête de réponse
  — ce que tu n'as pas fait, et ce qui reste risqué

RÈGLES ABSOLUES
· Tu ne réécris jamais un module que je ne t'ai pas envoyé.
· Tu n'inventes jamais un nom de table, de colonne, de fonction ou de
  droit : tout est dans SCHEMA.md. Si ce n'y est pas, ça n'existe pas.
· Tu respectes les neuf décisions d'architecture et les arbitrages déjà
  rendus (PASSATION.md § 3 et § 7). Pour en défaire un, tu me demandes.
· Le style, le ton et le format de réponse sont décrits au § 6 de
  PASSATION.md. Français soigné, aucun jargon dans l'interface, un
  message d'erreur explique et oriente.
· Tu me dis ce que tu n'as pas fait et ce qui reste risqué, à chaque
  livraison, même quand tout va bien.

Ce que je veux faire :
[VOTRE DEMANDE ICI]
```

---

## Après la livraison

Une seule commande, à la racine du dépôt :

```bash
python3 livrer.py 48_ma_migration.sql
```

Elle régénère `SCHEMA.md` et `CARTE.md`, passe les dix-huit contrôles,
charge réellement les modules, et conclut par :

```
PRÊT À DÉPLOYER.
```

ou par la liste des anomalies. **Si ce n'est pas « PRÊT À DÉPLOYER », on
ne déploie pas** : on renvoie la sortie du script à l'IA, qui corrige.

Puis :

1. Supabase → SQL Editor → **une seule migration à la fois** → Run
2. GitHub → remplacer les modules reçus, plus `SCHEMA.md` et `CARTE.md`
3. Vider le cache au premier chargement : `Ctrl + Maj + R`

---

## Pourquoi ce protocole marche

**Vous n'avez pas à savoir quel module envoyer.** `CARTE.md` liste, pour
chaque module, ses composants et ce que chacun fait. L'IA y lit la
réponse sans avoir vu une ligne de code.

**Le temps 1 coûte presque rien** — trois documents générés, quelques
centaines de lignes — et il évite le gaspillage : sans lui, l'IA demande
tout par précaution.

**Le temps 1 vous protège aussi.** Il oblige l'IA à annoncer ce qu'elle
va faire *avant* de le faire, y compris ce qu'elle compte refuser. C'est
le moment où une mauvaise compréhension coûte une phrase, et non une
livraison entière.

**Ce qui rend la reprise fiable** n'est pas la mémoire d'une
conversation : ce sont les dix-huit contrôles et les deux abrégés
générés. Une IA qui se trompe sur un nom de colonne sera arrêtée par le
contrôle 13, qu'elle soit la même qu'hier ou une autre.

---

## Ce qui reste hors de portée d'un protocole

Une session neuve ne reproduira pas les jugements de celle-ci — quelles
règles poser, quoi refuser, quand un écran ment. `PASSATION.md § 7`
consigne les arbitrages déjà rendus pour qu'ils ne se défassent pas par
inadvertance, mais les prochains resteront des décisions.

C'est pourquoi le temps 1 demande explicitement à l'IA **ce qu'elle
compte refuser ou faire autrement**. C'est là que se voit la différence
entre exécuter et comprendre.
