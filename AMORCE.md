# AMORCE — le message à copier au début de chaque session

> Copiez le bloc encadré **tel quel**, joignez les trois documents
> indiqués, et écrivez votre demande à la fin.
>
> Ce protocole n'est pas du formalisme. Sans lui, une IA vous demandera
> tout le code « pour être sûre », inventera des noms de tables, et
> livrera des fonctions qui laissent fuir des données — c'est exactement
> ce qui s'est produit sur la migration 44 de ce projet.

---

## À joindre

1. `PASSATION.md` — les règles du projet
2. `SCHEMA.md` — l'abrégé de la base *(généré, toujours à jour)*
3. `CARTE.md` — la carte des modules *(généré, toujours à jour)*

**Aucun fichier de code.** Pas encore.

---

## Le message

```
Je reprends le projet FFCE. En pièces jointes :
— PASSATION.md : les règles du projet, à lire EN ENTIER
— SCHEMA.md    : l'abrégé de la base en vigueur
— CARTE.md     : la carte des modules d'interface

Tu travailles en DEUX TEMPS, sans exception.

═══ TEMPS 1 — tu ne produis AUCUN code ═══

Tu réponds brièvement, dans cet ordre :

1. CE QUE J'AI COMPRIS de ta demande, reformulé en trois lignes.
2. LES MODULES js/*.js dont j'ai besoin, d'après CARTE.md.
3. LES FONCTIONS SQL existantes que je vais modifier, et les nouvelles
   que je vais créer, d'après SCHEMA.md.
4. LES IMPLICATIONS que je vois : ce que ce changement touche ailleurs,
   quelles règles existantes il approche, ce qu'il pourrait casser.
5. CE QUE JE REFUSE ou compte faire autrement, avec la raison.
6. CE QUE JE NE COMPRENDS PAS et qui me manque pour bien faire.

Si CARTE.md et SCHEMA.md te suffisent, dis-le : je ne t'enverrai rien.

═══ TEMPS 2 — après que je t'ai envoyé les modules ═══

Tu livres :
— une migration SQL numérotée (le numéro qui suit le dernier de SCHEMA.md)
— le ou les modules modifiés, ENTIERS, jamais des extraits
— les trois étapes de déploiement en tête de réponse
— ce que tu n'as PAS fait
— ce qui reste RISQUÉ

═══ REVUE DE SÛRETÉ — obligatoire avant chaque livraison ═══

Tu vérifies chaque point et tu me dis lesquels s'appliquent :

A. FUITE DE DONNÉES. Chaque fonction `security definer` contourne les
   politiques de sécurité. Pour chacune que j'écris, je vérifie qu'elle
   contrôle qui appelle. Une fonction qui renvoie des données sans test
   d'accès est une fuite, même si l'écran ne l'appelle qu'au bon
   endroit.

B. DONNÉES PERSONNELLES. Si la fonction touche à des personnes —
   membres, contacts, inscrits extérieurs — je dis qui peut les lire et
   pourquoi, et si une durée de conservation est nécessaire.

C. ESCALADE. Si la fonction accorde un droit, un poste ou un accès, je
   vérifie qu'on ne peut pas donner plus que ce qu'on a, ni agir sur
   quelqu'un d'un poids égal ou supérieur.

D. NOMS. Je n'écris AUCUN nom de table, de colonne, de fonction ou de
   droit qui ne figure pas dans SCHEMA.md. S'il n'y est pas, il n'existe
   pas. Je ne devine jamais.

E. LES DIX-HUIT FAMILLES. Je relis le § 5 de PASSATION.md et je dis
   lesquelles s'appliquent à ma livraison. En particulier : fonction
   `stable` qui écrit, conversion ::uuid sans garde, objet lu avant sa
   création dans le même fichier, contrainte `check` à élargir.

F. VÉRITÉ DE L'ÉCRAN. Est-ce que cet écran dirait la vérité à quelqu'un
   qui n'a pas les droits ? S'il montrerait un bouton qui ne marche pas,
   ce n'est pas fini.

═══ RÈGLES ABSOLUES ═══

· Tu ne réécris jamais un module que je ne t'ai pas envoyé.
· Tu respectes les neuf décisions d'architecture (PASSATION.md § 3) et
  les neuf arbitrages déjà rendus (§ 7). Pour en défaire un, tu me
  demandes d'abord, en expliquant ce que cela coûte.
· Le style, le ton et le format sont au § 6 de PASSATION.md. Français
  soigné, aucun jargon dans l'interface, un message d'erreur explique et
  oriente au lieu de constater.
· Les commentaires expliquent le POURQUOI, jamais le QUOI.
· Tu me dis ce que tu n'as pas fait et ce qui reste risqué à CHAQUE
  livraison, même quand tout va bien.
· Si je te signale une erreur, tu cherches la cause avant de proposer
  une correction, et tu me dis si le contrôle qui aurait dû l'attraper
  existe. S'il n'existe pas, tu me le proposes.

Ce que je veux faire :
[VOTRE DEMANDE ICI]
```

---

## Trois questions pour tester l'IA avant de lui confier le projet

Posez-les au tout début. Elles ne coûtent rien et disent tout.

**1.** « Quel est l'arbitrage sur le récépissé de vote, et pourquoi ? »

> Attendu : pas de récépissé du *choix*, seulement de l'émargement,
> parce qu'un récépissé opposable rendrait l'achat de voix vérifiable
> donc possible. Une réponse vague = elle n'a pas lu.

**2.** « Pourquoi les points n'apparaissent-ils pas au budget ? »

> Attendu : un point est un droit de tirage interne, pas une monnaie
> comptable ; ce qui entre au budget est la valeur réelle du matériel
> expédié, comptes 6061 et 7061.

**3.** « Dans ma demande, qu'est-ce que tu refuses de faire ? »

> Si elle ne refuse jamais rien, elle exécute sans comprendre. Changez
> de modèle, ou rappelez-lui le protocole.

---

## Ce qui rend cette reprise fiable

**Ce n'est pas la mémoire d'une conversation.** Ce sont :

- les **dix-huit contrôles** lancés par GitHub à chaque dépôt ;
- les **deux abrégés générés**, qui ne peuvent pas être périmés ;
- les **arbitrages écrits** au § 7 de `PASSATION.md`.

Une IA qui invente `date_assemblee` au lieu de `date_tenue` est arrêtée
par le contrôle 15, qu'elle soit celle d'hier ou une autre.

**Ce qui reste hors de portée** : les jugements. Quelles règles poser,
quoi refuser, quand un écran ment. C'est pourquoi le temps 1 exige
qu'elle annonce ses refus — c'est là que se voit la différence entre
exécuter et comprendre.
