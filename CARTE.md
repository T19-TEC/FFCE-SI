# FFCE — Carte des modules d'interface

> Généré par `carte.py`. **Ne pas modifier à la main.** Régénérer après chaque livraison.

> À joindre en début de session avec `SCHEMA.md` et `PASSATION.md`. Elle permet de désigner le module à modifier **sans lire le code** : c'est ce qui rend une reprise économe.

| Module | Lignes | Composants | Ce qu'il contient |
|---|---|---|---|
| `js/app.js` | 11 | 0 | FFCE — Point d'entrée Le navigateur charge ce module ; les autres suivent par leurs imports. |
| `js/collectif.js` | 1325 | 11 |  |
| `js/direction.js` | 3755 | 35 |  |
| `js/espace.js` | 1155 | 12 | La charpente de l'intranet : le menu latéral, le routeur des applications, le tableau de bord, le fil d'actualité, la file de travail, le guichet des demandes et le référentiel des droits. |
| `js/evenements.js` | 1188 | 11 | Créer, ouvrir les inscriptions, tenir la liste, contrôler les entrées. |
| `js/finances.js` | 2841 | 18 |  |
| `js/formation.js` | 1230 | 9 |  |
| `js/membre.js` | 2688 | 29 |  |
| `js/socle.js` | 518 | 6 |  |
| `js/statutaire.js` | 1802 | 11 |  |
| `js/structure.js` | 2167 | 20 |  |
| `js/vitrine.js` | 647 | 17 | Tout ce qui se voit sans compte : accueil, présentation de la fédération, actions, réseau, actualités, pages de texte, adhésion, connexion et inscription. |

**Total : 19327 lignes d'interface.**

---

## `js/app.js`

FFCE — Point d'entrée Le navigateur charge ce module ; les autres suivent par leurs imports.

*11 lignes · 0 composants*

## `js/collectif.js`

*1325 lignes · 11 composants*

- **`Conversation`** — 297 lignes
- **`Groupes`** — 163 lignes  
  5 ter.
- **`EquipesLocales`** — 139 lignes  
  --- Constituer une équipe locale La fiche ne peut contenir que des applications que le proposant détient.
- **`Messagerie`** — 127 lignes  
  5 quater.
- **`Groupe`** — 113 lignes
- **`GtMembres`** — 111 lignes
- **`GtTaches`** — 109 lignes
- **`GtDocuments`** — 78 lignes
- **`JournalPieces`** — 67 lignes  
  --- Le journal des envois Qui, quand, vers qui, quel nom, quelle taille.
- **`GroupesOuverts`** — 61 lignes  
  Un groupe ne se rejoint plus d'un clic : on postule, on est retenu.
- **`CandidaturesGroupe`** — 50 lignes  
  --- Les candidatures reçues, côté responsable de groupe

Fonctions SQL appelées : `candidatures_groupe`, `conversation_groupe`, `conversation_privee`, `creer_groupe`, `destinataires_possibles`, `envoyer_message`, `equipes_a_valider`, `groupes_ouverts`, `inviter_au_groupe`, `journal_pieces`, `marquer_lu`, `marquer_pieces_vues`, `mes_conversations`, `mes_organes`, `obstacle_groupe`, `participants_conversation`, `postuler_groupe`, `proposer_equipe`, `quitter_groupe`, `rejoindre_groupe`, `repondre_invitation`, `retenir_candidature`, `retirer_message`, `signaler_conversation`, `valider_equipe`

## `js/direction.js`

*3755 lignes · 35 composants*

- **`Validation`** — 342 lignes  
  Paramètres administrateur : quelles catégories de poste voient les noms dans « Mon périmètre ».
- **`FicheAdmin`** — 292 lignes  
  --- La fiche unique : tout se règle ici
- **`CabinetActes`** — 187 lignes  
  --- Préparer, signer, abroger
- **`ApFichier`** — 187 lignes  
  --- Le fichier
- **`IdentiteApplications`** — 171 lignes  
  --- Identité des applications
- **`Communication`** — 165 lignes
- **`SuggestionsAdmin`** — 147 lignes  
  --- Suggestions, côté direction
- **`ApContact`** — 143 lignes  
  --- Le détail d'un contact
- **`Interims`** — 140 lignes
- **`VitrineBlocs`** — 135 lignes
- **`Suggestion`** — 129 lignes
- **`EditionPublication`** — 123 lignes
- **`AdministrateurReseau`** — 116 lignes  
  --- Administrateur réseau : configurer sans passer par le code
- **`ApSollicitations`** — 116 lignes  
  --- Les sollicitations du réseau
- **`VitrineArticles`** — 109 lignes
- **`Postes`** — 108 lignes
- **`ApProspection`** — 108 lignes  
  --- La prospection
- **`CabinetTaches`** — 103 lignes  
  --- Les tâches confiées par la présidence
- **`AffairesPubliques`** — 88 lignes
- **`Publier`** — 83 lignes  
  --- Suivi des virements, côté direction financière
- **`Cabinet`** — 75 lignes
- **`VersLeCabinet`** — 75 lignes  
  --- Porter au cabinet, depuis n'importe où
- **`ListeMembres`** — 67 lignes  
  --- Liste des membres, une seule porte d'entrée
- **`RecueilListe`** — 61 lignes  
  --- Le recueil : la même liste pour le cabinet et pour les adhérents ---
- **`RappelCharte`** — 59 lignes  
  --- La charte, sous la main Une charte qu'il faut rouvrir en PDF n'est pas appliquée.
- **`Campagnes`** — 59 lignes
- **`CabinetEtat`** — 57 lignes  
  --- L'état de la fédération, vu d'en haut
- **`Recueil`** — 51 lignes  
  --- Le recueil, application ouverte à tous
- **`CabinetRemontees`** — 42 lignes  
  --- Les remontées du réseau
- **`Habilitations`** — 40 lignes  
  éorganisé autour de deux objets, pas de cinq tables : la PERSONNE et la STRUCTURE.
- **`VitrineTextes`** — 40 lignes
- **`ConformitePostes`** — 37 lignes  
  --- Conformité des postes
- **`PostesEtDroits`** — 30 lignes  
  --- Les structures : où le réseau tient, où il manque du monde
- **`VitrineAdmin`** — 29 lignes  
  --- Direction générale : le site public Textes, blocs répétables et actualités.
- **`EnAttente`** — 21 lignes  
  --- Coquille de l'espace membre

Fonctions SQL appelées : `acces_complets`, `accorder_acces`, `actes_a_controler`, `alertes_consultation`, `annuler_tache`, `assigner_tache`, `calendrier_com`, `clore_interim`, `clore_signalement`, `confier_interim`, `confier_signalement`, `controler_acte`, `creer_suggestion`, `declarer_reprise`, `enregistrer_article`, `fiche_admin`, `flecher_vers_cabinet`, `liste_directions`, `marquer_alerte_vue`, `mes_interims`, `modifier_membre`, `nommer`, `ouvrir_dossier`, `postes_non_conformes`, `puis_je_lire_journal_pieces`, `puis_je_signer_acte`, `recueil_actes`, `registre_adhesions`, `regler_application`, `remontees_du_cabinet`, `repondre_interim`, `revoquer`, `revoquer_acces`, `signalements_a_traiter`, `sollicitations_ap_a_traiter`, `soumettre_publication`, `statuer_publication`, `suggestions_disponibles`, `suivi_suggestions`, `tableau_ap`, `tableau_cabinet`, `taches_que_jai_confiees`, `texte_acte`, `tracer_export`, `v_contacts`, `valider_inscription`

## `js/espace.js`

La charpente de l'intranet : le menu latéral, le routeur des applications, le tableau de bord, le fil d'actualité, la file de travail, le guichet des demandes et le référentiel des droits.

*1155 lignes · 12 composants*

- **`Espace`** — 195 lignes
- **`Assistance`** — 178 lignes
- **`Referentiel`** — 138 lignes  
  --- L'application Discipline
- **`AssistanceAdmin`** — 111 lignes  
  --- Assistance, côté pilotage
- **`TableauDeBord`** — 101 lignes
- **`Matrice`** — 83 lignes  
  --- La matrice des accès, côté pilotage
- **`Flanc`** — 82 lignes  
  --- Menu latéral Le menu suit l'organigramme, pas la liste des tables.
- **`MesTaches`** — 74 lignes  
  Les tâches que la présidence a confiées, vues par la personne qui les reçoit.
- **`FilActualite`** — 65 lignes  
  --- Intérim
- **`EspaceSuspendu`** — 51 lignes
- **`CeQuiAttend`** — 32 lignes  
  --- Ce qui attend : la file de travail personnelle Les alertes se perdaient au fond des onglets.
- **`Delegations`** — 15 lignes  
  --- Mes délégations en cours Agir au nom d'un autre doit toujours se voir.

Fonctions SQL appelées : `ce_qui_attend`, `chemin_territoire`, `completude_bloquante`, `deleguer_tache`, `fil_actualite`, `fil_ticket`, `liste_tickets`, `matrice_acces`, `mes_applications`, `mes_delegations`, `mes_directions`, `mes_droits`, `mes_postes`, `mes_taches`, `ouvrir_ticket`, `referentiel`, `regler_matrice`, `repondre_ticket`, `terminer_tache`, `tracer_acces`, `traiter_ticket`

## `js/evenements.js`

Créer, ouvrir les inscriptions, tenir la liste, contrôler les entrées.

*1188 lignes · 11 composants*

- **`Evenement`** — 169 lignes  
  --- Un événement ouvert
- **`ReglagesEvenement`** *(interne)* — 153 lignes  
  --- Les réglages
- **`EvenementPublic`** — 135 lignes  
  --- La page publique d'inscription Elle s'ouvre sans compte.
- **`ControleEntrees`** *(interne)* — 132 lignes
- **`ScannerCamera`** *(interne)* — 106 lignes  
  Scan à la caméra : lit le QR du billet sans appareil dédié.
- **`Evenements`** — 101 lignes
- **`FormulaireEvenement`** *(interne)* — 98 lignes  
  --- Le formulaire de création
- **`ListeInscrits`** *(interne)* — 92 lignes  
  --- La liste des inscrits
- **`NiveauxAccreditation`** *(interne)* — 69 lignes  
  --- Niveaux d'accréditation Un raccourci, pas un nouveau pouvoir : assigner un niveau pose en une fois le même tableau de catégories qu'on pourrait cocher une par une.
- **`MonBillet`** *(interne)* — 61 lignes  
  --- Mon billet Le code présenté à l'entrée.
- **`AutourDeVous`** *(interne)* — 39 lignes  
  Ce qui se passe autour de vous : événements et projets à venir, dans un seul fil, pour que la fédération se voie comme un réseau vivant plutôt que comme des écrans séparés.

Fonctions SQL appelées : `controler_entree`, `evenement_public`, `inscription_publique`, `liste_inscrits`, `mes_evenements`, `projets_a_venir`, `tableau_evenement`, `v_contacts`

## `js/finances.js`

*2841 lignes · 18 composants*

- **`Budget`** — 312 lignes  
  --- Confirmer un virement, côté membre
- **`Finances`** — 282 lignes  
  --- Finances : instruction, ordonnancement, paiement Trois écrans distincts pour trois responsabilités distinctes.
- **`NoteFrais`** — 256 lignes
- **`ResDotations`** — 247 lignes  
  --- Les dotations en points
- **`ResCommandes`** — 229 lignes  
  --- Le panier et les commandes
- **`ResLogistique`** — 204 lignes  
  --- La logistique fédérale
- **`ResInventaire`** — 192 lignes  
  --- L'inventaire
- **`Rapport`** — 189 lignes  
  Les chiffres se calculent, le récit se rédige.
- **`ResInvestissements`** — 154 lignes  
  --- Les investissements
- **`MesEnveloppes`** — 134 lignes  
  Une direction ou un responsable qui détient des points ne les consomme pas : il les répartit.
- **`Ressources`** — 130 lignes
- **`NotesFrais`** — 107 lignes
- **`InstruireLignes`** — 87 lignes  
  --- Instruire ligne à ligne L'instructeur avait un doute sur une ligne et refusait la note entière.
- **`SuiviVirements`** — 77 lignes  
  --- Mes coordonnées bancaires
- **`ResCatalogue`** — 77 lignes  
  --- Le catalogue
- **`InvestissementsAOrdonnancer`** — 62 lignes  
  Ils n'apparaissaient que dans Ressources, alors qu'ordonnancer est le métier de l'ordonnateur, qui travaille dans son écran.
- **`SuiviNote`** — 53 lignes  
  Le déposant ne voyait qu'un mot.
- **`ResSolde`** — 44 lignes  
  --- Le solde de points, en tête de tous les volets

Fonctions SQL appelées : `affecter_points_projet`, `budget_exercice`, `calculer_dotation`, `changer_statut_exercice`, `chiffres_annee`, `completer_note`, `declarer_sauvegarde`, `demander_precisions`, `deposer_attestation`, `deposer_note`, `dotations_exceptionnelles_recentes`, `engagements_a_valider`, `enregistrer_rapport`, `etat_ressources`, `etat_sauvegardes`, `investissements_a_traiter`, `lire_rib`, `liste_directions`, `mes_enveloppes`, `mes_exercices`, `observer_ligne`, `ordonnancer_investissement`, `ouvrir_exercice`, `plan_engagement`, `projets_a_soutenir`, `regler_ligne`, `solde_points`, `soutiens_projet`, `suivi_note`, `tracer_export`, `v_notes`, `virements_a_suivre`

## `js/formation.js`

*1230 lignes · 9 composants*

- **`EditeurParcours`** — 263 lignes
- **`Chancellerie`** — 225 lignes  
  --- Chancellerie Reconnaître ce qui est donné.
- **`EditeurLecon`** — 162 lignes
- **`Lecon`** — 131 lignes
- **`Distinctions`** — 106 lignes  
  --- Distinctions Reconnaître un engagement sans attendre un palier.
- **`EditeurFormations`** — 100 lignes  
  --- Mes distinctions, sur la fiche du membre
- **`Formation`** — 92 lignes
- **`BaremeEchelons`** — 73 lignes  
  Nom, seuil et ce que l'échelon ouvre étaient figés dans la migration du socle.
- **`Formations`** — 70 lignes  
  5 bis.

Fonctions SQL appelées : `avancement`, `bareme_echelons`, `chancellerie_synthese`, `classement_merites`, `decerner_distinction`, `enregistrer_formation`, `formation_complete`, `promouvoir`, `regler_bareme`, `regler_echelon`, `suivi_formation`, `terminer_lecon`, `valider_quiz`, `verifier_formation`

## `js/membre.js`

*2688 lignes · 29 composants*

- **`MonDossier`** — 292 lignes  
  --- Ce que voit un membre : bandeau, ou page entière si suspendu
- **`MesMandats`** — 231 lignes  
  Ce qu'on me demande à moi se répond ici, jamais depuis l'application concernée.
- **`DossierAdhesion`** — 223 lignes
- **`Engagement`** — 215 lignes
- **`MonCompte`** — 130 lignes
- **`FicheMembre`** — 124 lignes  
  --- Fiche membre Trois paliers.
- **`Passeport`** — 121 lignes
- **`CurseurEngagement`** — 95 lignes  
  --- Le référentiel, ouvert à tous
- **`MesDemandes`** — 94 lignes
- **`BilansMission`** — 92 lignes  
  --- Bilans de mission à rédiger
- **`BilanAnnee`** — 90 lignes  
  LE BILAN DE L'ANNÉE « Mon engagement » listait sans totaliser.
- **`MesCreneaux`** — 80 lignes
- **`Annuaire`** — 79 lignes
- **`CarteAdherent`** — 69 lignes
- **`MonRib`** — 65 lignes
- **`MesVirements`** — 65 lignes  
  --- Assistance : signaler, proposer
- **`ProfilInterne`** — 64 lignes  
  Ce que la fédération montre d'un membre à un autre.
- **`PrendreRendezVous`** — 60 lignes
- **`MaChaine`** — 57 lignes  
  --- Répartition des nouveaux adhérents
- **`Tunnel`** — 55 lignes  
  --- Le tunnel : chaque marche perdue se voit
- **`MonPortrait`** — 53 lignes  
  --- Mon portrait Deux mégaoctets, dépôt privé, dossier nommé par l'identifiant : nul ne peut déposer chez un autre.
- **`ReglagesAffichage`** *(interne)* — 47 lignes  
  Réglage admin, à même l'écran : quelles catégories de poste voient les noms dans « Mon périmètre ».
- **`FicheOuverture`** — 47 lignes  
  LA FICHE D'OUVERTURE « Comment tout lui débloquer, et rien de plus.
- **`ApercuAdhesion`** — 42 lignes  
  --- Complétude d'un dossier
- **`QuiMaConsulte`** — 33 lignes  
  --- Qui a consulté mon dossier Droit RGPD, exercé en un clic plutôt que par courrier.
- **`MesAlertesParcours`** — 33 lignes
- **`MesDistinctions`** — 31 lignes
- **`DossierIncomplet`** — 27 lignes  
  --- Dossier incomplet : on ne va pas plus loin Ni un mur ni une fenêtre qu'on referme : la page qui suit la connexion, tant qu'il manque l'essentiel.
- **`FilDossier`** — 19 lignes

Fonctions SQL appelées : `accuser_reception`, `accuser_virement`, `annuler_creneau`, `bilans_a_rediger`, `checklist_ouverture`, `completude_dossier`, `creer_mission`, `creneaux_disponibles`, `deposer_recours`, `enregistrer_adhesion`, `enregistrer_rib`, `fiche_membre`, `ma_carte`, `ma_chaine`, `mes_alertes_parcours`, `mes_distinctions`, `mes_droits`, `mes_interims`, `mes_invitations_groupe`, `mes_rendez_vous`, `mes_virements_a_confirmer`, `missions_ouvertes`, `mon_adhesion`, `mon_dossier`, `mon_engagement`, `mon_perimetre`, `mon_rib`, `passeport`, `poser_creneaux`, `postuler_mission`, `profil_interne`, `qui_ma_consulte`, `rediger_bilan`, `regenerer_jeton_carte`, `regler_engagement`, `renoncer_gracieux`, `repondre_alerte_parcours`, `reserver_creneau`, `verser_piece`

## `js/socle.js`

*518 lignes · 6 composants*

- **`Progression`** — 58 lignes
- **`Logo`** — 25 lignes  
  --- Logo La charte interdit toute modification du logo.
- **`Completude`** — 25 lignes
- **`Info`** — 23 lignes  
  Une explication brève, à la demande.
- **`Maillage`** — 21 lignes  
  Le maillage : la fédération est un réseau de territoires.
- **`Portrait`** — 20 lignes  
  --- Portrait Les portraits vivent dans un dépôt privé : on signe une adresse temporaire plutôt que de les rendre publics.

Fonctions SQL appelées : `completude_dossier`, `points_membre`

## `js/statutaire.js`

*1802 lignes · 11 composants*

- **`DossierDetail`** — 319 lignes
- **`Assemblee`** — 267 lignes
- **`BureauDeVote`** — 237 lignes  
  Ce que tiennent les organisateurs : les pouvoirs, l'émargement par scan, la feuille de présence, les deux signatures du dépouillement, et le procès-verbal.
- **`Assemblees`** — 195 lignes
- **`Discipline`** — 175 lignes
- **`Isoloir`** — 151 lignes  
  Un écran, une question à la fois, et rien d'autre à l'écran.
- **`Conformite`** — 136 lignes
- **`SuiviUsages`** — 99 lignes  
  --- Suivi des usages, agrégé par membre Une liste d'événements bruts ne se suit pas.
- **`AppelPublic`** — 96 lignes  
  --- L'appel public, hors connexion
- **`ArchivesElectorales`** — 63 lignes
- **`Recepisse`** — 57 lignes  
  --- Le récépissé, une fois qu'on a voté Ce que l'électeur peut opposer si l'on prétend qu'il n'a pas voté.

Fonctions SQL appelées : `appel_public`, `archives_electorales`, `changer_phase_assemblee`, `cles_du_depouillement`, `clore_dossier`, `conformite_a_traiter`, `corps_electoral`, `creer_assemblee`, `deposer_candidature`, `depouillement`, `detail_suivi`, `dossiers_discipline`, `emarger_par_carte`, `examiner_candidature`, `feuille_presence`, `mandats_a_renouveler`, `marquer_suivi_vu`, `membres_pour_discipline`, `mes_assemblees`, `mes_voix`, `mon_recepisse`, `notifier_mesure`, `ouvrir_dossier`, `participation`, `pouvoirs_assemblee`, `proclamer`, `projet_pv`, `prononcer_mesure`, `registre_discipline`, `scrutins_a_arreter`, `signer_depouillement`, `statuer_recours`, `suivi_en_cours`, `tracer_export`, `verser_piece`, `voter`

## `js/structure.js`

*2167 lignes · 20 composants*

- **`MonComite`** — 182 lignes  
  --- Prendre rendez-vous, côté nouvel adhérent
- **`FileAccueil`** — 180 lignes  
  --- Ce que les échelons supérieurs me signalent
- **`GlActes`** — 172 lignes  
  --- Les actes locaux
- **`NommerLocal`** — 134 lignes  
  --- Nommer dans sa structure La liste des postes vient de `postes_conferables` : l'écran ne peut pas proposer ce que la base refusera.
- **`GlPlan`** — 134 lignes  
  --- Le plan du réseau Ni carte ni dessin : un arbre, avec ce qui sert à décider.
- **`GlFiche`** — 133 lignes  
  --- La fiche d'identité
- **`PropositionsComite`** — 131 lignes
- **`ProjetsComite`** — 120 lignes
- **`CarteReseau`** — 117 lignes
- **`ParcoursAdherent`** — 114 lignes  
  Six marches, de l'inscription à la première mission.
- **`BordNational`** — 105 lignes  
  --- National : on ne regarde que ce qui va mal
- **`GlAcces`** — 102 lignes  
  --- Les accès du périmètre
- **`Structures`** — 99 lignes
- **`BordLocal`** — 72 lignes  
  --- Local : quatre choses, pas une de plus
- **`RepartirNouveaux`** — 71 lignes
- **`GestionLocale`** — 69 lignes  
  Voir avant de décider.
- **`BordTunnel`** — 64 lignes
- **`Organigramme`** — 44 lignes  
  Qui appartient à quoi.
- **`PropositionsNationales`** — 37 lignes  
  --- Ce qui remonte, côté national
- **`Pilotage`** — 30 lignes  
  Trois vues selon l'échelon : local, territorial, national.

Fonctions SQL appelées : `acces_du_perimetre`, `accorder_acces`, `affecter_accompagnant`, `agir_parcours`, `agir_parcours_groupe`, `annuler_creneau`, `applications_delegables`, `bord_local`, `bord_national`, `enregistrer_projet`, `etat_reseau`, `exceptions_reseau`, `faire_remonter`, `fiche_territoire`, `mes_rendez_vous`, `mon_comite`, `nouveaux_a_accueillir`, `nouveaux_a_accueillir_maj`, `nouveaux_a_repartir`, `organigramme`, `plan_territoires`, `postes_conferables`, `prendre_acte`, `proposer`, `propositions_remontees`, `rafraichir_jalons`, `recueil_actes`, `rejoindre_projet`, `signaler_a_accompagnant`, `soutenir`, `statuer_proposition`, `texte_acte`, `tunnel_benevole`

## `js/vitrine.js`

Tout ce qui se voit sans compte : accueil, présentation de la fédération, actions, réseau, actualités, pages de texte, adhésion, connexion et inscription.

*647 lignes · 17 composants*

- **`Inscription`** — 91 lignes
- **`Site`** — 73 lignes  
  6.
- **`Reseau`** — 66 lignes
- **`Accueil`** — 56 lignes
- **`Connexion`** — 42 lignes  
  4.
- **`Rejoindre`** — 40 lignes
- **`Pied`** — 38 lignes
- **`PageArticle`** — 30 lignes
- **`EntetePublique`** — 29 lignes
- **`Actualites`** — 28 lignes  
  Les actualités, sur l'accueil et sur leur page.
- **`CarteFederale`** — 28 lignes  
  5.
- **`Association`** — 24 lignes
- **`Blocs`** — 23 lignes  
  Un jeu de blocs administrables, pour n'importe quelle page.
- **`Contact`** — 20 lignes
- **`PageTexte`** — 16 lignes
- **`Actions`** — 14 lignes
- **`PageActualites`** — 12 lignes

Fonctions SQL appelées : `actualites`, `article`, `vitrine_blocs`

