# FFCE — Abrégé du schéma en vigueur

> Généré par `schema.py` à partir des 52 migrations. **Ne pas modifier à la main.** Régénérer après chaque migration.

> Ce fichier remplace le recueil des migrations pour écrire du code. N'ouvrir le recueil que pour comprendre le *pourquoi* d'une règle.

**117 tables · 407 fonctions · 49 droits · 17 applications**

---

## Tables et colonnes

**`acces_applications`** — `id`, `profil_id`, `application`, `statut`, `motif`, `accorde_par`, `cree_le`, `revoque_le`, `revoque_par`, `motif_revocation`, `expire_le`

**`acces_rib`** — `id`, `lecteur`, `profil_id`, `note_id`, `cree_le`

**`actes_internes`** — `id`, `reference`, `territoire_id`, `auteur_id`, `type`, `objet`, `visas`, `considerants`, `articles`, `destinataire_id`, `poste_confie`, `prend_effet_le`, `statut`, `signe_par`, `signe_le`, `notifie_le`, `abroge_par`, `motif_abrogation`, `cree_le`, `portee`

**`actes_sensibles`** — `id`, `auteur_id`, `cible_id`, `nature`, `libelle`, `avant`, `apres`, `reversible`, `statut`, `controle_par`, `controle_le`, `observation`, `cree_le`

**`alertes_parcours`** — `id`, `profil_concerne`, `destinataire_id`, `auteur_id`, `message`, `nature`, `traite_le`, `reponse`, `cree_le`

**`alertes_suivi`** — `id`, `profil_id`, `mesure_id`, `application`, `detail`, `vue_par`, `vue_le`, `cree_le`

**`application_visibilite`** — `application`, `fonction`, `etat`, `note`, `maj_par`, `maj_le`

**`applications`** — `code`, `nom`, `description`, `icone`, `niveau_min`, `sur_demande`, `externe_url`, `ordre`, `actif`, `droit_requis`, `nom_court`, `logo`, `couleur`, `accroche`, `direction`, `direction_locale`, `delegable_local`

**`articles`** — `id`, `slug`, `titre`, `chapo`, `contenu`, `image`, `categorie`, `territoire_id`, `publie`, `publie_le`, `auteur_id`, `maj_le`, `cree_le`

**`articles_catalogue`** — `id`, `reference`, `nom`, `description`, `categorie`, `cout_points`, `valeur_euros`, `unite`, `image`, `stock_national`, `seuil_alerte`, `plafond_annuel`, `actif`, `ordre`, `conditionnement`, `quantite_lot`, `variantes`, `variante_libelle`

**`aspirations`** — `profil_id`, `domaines`, `publics`, `competences`, `envies`, `reticences`, `disponibilite`, `mobilite`, `objectif`, `recueilli_par`, `recueilli_le`, `maj_le`

**`assemblees`** — `id`, `reference`, `territoire_id`, `type`, `titre`, `ordre_du_jour`, `lieu`, `date_tenue`, `ouverture_candidatures`, `cloture_candidatures`, `ouverture_scrutin`, `cloture_scrutin`, `quorum_requis`, `statut`, `postes_a_pourvoir`, `duree_mandat_ans`, `proces_verbal`, `pv_fichier`, `organise_par`, `proclame_par`, `proclame_le`, `public_token`, `cree_le`

**`bareme_points`** — `cle`, `libelle`, `points`, `unite`, `actif`, `ordre`, `maj_par`, `maj_le`

**`bilans_mission`** — `id`, `mission_id`, `profil_id`, `heures`, `realise`, `competences`, `appreciation`, `merite`, `redige_par`, `cree_le`

**`blocs_definis`** — `bloc`, `libelle`, `description`, `cree_le`

**`blocs_visibilite`** — `bloc`, `fonction`, `visible`, `note`, `maj_par`, `maj_le`

**`blocs_vitrine`** — `id`, `page`, `type`, `titre`, `contenu`, `image`, `lien`, `lien_texte`, `ordre`, `publie`, `maj_par`, `maj_le`, `cree_le`

**`budget_lignes`** — `id`, `exercice_id`, `poste`, `libelle`, `prevu`, `realise_saisi`, `commentaire`, `maj_par`, `maj_le`

**`bulletins`** — `id`, `assemblee_id`, `poste`, `candidature_id`, `blanc`, `cree_le`

**`campagnes`** — `id`, `titre`, `objectif`, `debut`, `fin`, `statut`, `responsable`, `cree_par`, `cree_le`

**`candidatures`** — `id`, `assemblee_id`, `poste`, `profil_id`, `profession_foi`, `fichier`, `statut`, `motif`, `examinee_par`, `cree_le`

**`candidatures_formation`** — `id`, `formation_id`, `profil_id`, `motivation`, `statut`, `avis_local`, `arbitre_par`, `arbitre_le`, `decision_nationale`, `decide_par`, `cree_le`

**`categories_ressource`** — `code`, `nom`, `ordre`

**`certifications`** — `code`, `nom`, `description`, `formation_id`, `validite_mois`, `actif`

**`certifications_obtenues`** — `id`, `profil_id`, `code`, `numero`, `obtenue_le`, `expire_le`, `delivree_par`

**`cles_depouillement`** — `id`, `assemblee_id`, `profil_id`, `signe_le`, `role`

**`commande_lignes`** — `id`, `commande_id`, `article_id`, `quantite`, `points`, `variante`

**`commandes`** — `id`, `reference`, `territoire_id`, `demandeur_id`, `motif`, `points_debites`, `statut`, `traite_par`, `traite_le`, `motif_refus`, `expediee_le`, `transporteur`, `suivi`, `recue_le`, `cree_le`, `direction`, `adresse_livraison`, `destinataire`, `finance_par`, `engage_par`, `engage_le`, `motif_engagement`

**`consultations`** — `id`, `observateur`, `observe`, `contexte`, `alerte`, `vue_par`, `vue_le`, `cree_le`

**`contact_echanges`** — `id`, `contact_id`, `date_echange`, `nature`, `objet`, `compte_rendu`, `suite`, `echeance`, `par_id`, `cree_le`

**`contact_partages`** — `id`, `contact_id`, `territoire_id`, `groupe_id`, `portee`, `motif`, `expire_le`, `accorde_par`, `retire_le`, `cree_le`

**`contact_personnes`** — `id`, `contact_id`, `prenom`, `nom`, `fonction`, `email`, `telephone`, `notes`, `actif`, `cree_le`

**`contacts`** — `id`, `nom`, `sigle`, `type`, `echelle`, `territoire_id`, `site`, `adresse`, `objet`, `interet`, `statut`, `reserve`, `motif_reserve`, `cree_par`, `maj_le`, `cree_le`

**`contenus`** — `cle`, `valeur`, `libelle`, `format`, `section`, `ordre`

**`controles_pieces`** — `profil_id`, `vu_jusqu_a`

**`conv_participants`** — `id`, `conversation_id`, `profil_id`, `rejoint_le`, `lu_jusqu_a`

**`conversations`** — `id`, `type`, `groupe_id`, `titre`, `cree_par`, `cree_le`, `derniere_activite`, `organe`

**`coordonnees_bancaires`** — `profil_id`, `titulaire`, `iban`, `bic`, `maj_le`, `cree_le`

**`creneaux`** — `id`, `hote_id`, `debut`, `duree_min`, `lieu`, `visio`, `territoire_id`, `reserve_par`, `reserve_le`, `annule_le`, `motif_annulation`, `cree_le`

**`demandes`** — `id`, `profil_id`, `type`, `objet`, `message`, `cible`, `statut`, `traite_par`, `traite_le`, `motif_reponse`, `cree_le`

**`directions`** — `code`, `nom`, `nom_court`, `description`, `couleur`, `ordre`, `actif`, `bloc_permanent`

**`distinctions`** — `id`, `numero`, `profil_id`, `type`, `motif`, `texte`, `publique`, `decernee_par`, `decernee_le`, `retiree_le`, `motif_retrait`

**`dossier_adhesion`** — `profil_id`, `date_naissance`, `adresse`, `code_postal`, `ville`, `situation`, `profession`, `competences`, `disponibilites`, `motivation`, `origine`, `deja_benevole`, `accepte_statuts`, `accepte_rgpd`, `accepte_image`, `maj_le`, `cree_le`

**`dossier_pieces`** — `id`, `dossier_id`, `type`, `titre`, `contenu`, `fichier`, `auteur_id`, `communicable`, `cree_le`

**`dossiers`** — `id`, `reference`, `profil_id`, `origine`, `signalement_id`, `objet`, `qualification`, `gravite`, `statut`, `instructeur_id`, `ouvert_par`, `ouvert_le`, `clos_le`, `clos_par`, `conclusion`, `scelle_le`

**`dotations`** — `id`, `territoire_id`, `annee`, `points_alloues`, `points_reportes`, `points_bonus`, `motif_bonus`, `attribuee_le`, `attribuee_par`

**`dotations_exceptionnelles`** — `id`, `territoire_id`, `annee`, `points`, `motif`, `campagne`, `accorde_par`, `cree_le`, `direction`, `profil_id`, `projet_id`, `transfert_id`, `commande_id`

**`droits`** — `code`, `nom`, `categorie`, `sensible`, `ordre`

**`echelons`** — `niveau`, `nom`, `points`, `ouvre`, `description`, `couleur`

**`engagements`** — `id`, `profil_id`, `mois`, `heures_visees`, `heures_realisees`, `commentaire`, `maj_le`

**`entrees_evenement`** — `id`, `inscription_id`, `categorie`, `scanne_le`, `scanne_par`

**`evenement_categories`** — `id`, `evenement_id`, `code`, `nom`, `description`, `capacite`, `horaire`, `externe_admis`, `ordre`

**`evenements`** — `id`, `reference`, `titre`, `objet`, `nature`, `ouverture`, `territoire_id`, `groupe_id`, `partenaire_id`, `organisateur_id`, `lieu`, `adresse`, `debut`, `fin`, `capacite`, `validation_requise`, `cloture_inscriptions`, `statut`, `motif_annulation`, `jeton_public`, `conservation_jours`, `cree_le`

**`exercices`** — `id`, `annee`, `territoire_id`, `debut`, `fin`, `statut`, `vote_le`, `arrete_le`, `arrete_par`, `observations`, `taux_benevolat`, `cree_le`

**`fonctions`** — `code`, `nom`, `famille`, `niveau`, `echelle_requise`

**`formations`** — `id`, `code`, `titre`, `resume`, `description`, `niveau_min`, `duree_min`, `seuil_quiz`, `publiee`, `ordre`, `cree_par`, `cree_le`, `image`, `prerequis`, `sur_candidature`, `places`, `lieu`, `session_debut`, `session_fin`

**`groupes_travail`** — `id`, `nom`, `objet`, `territoire_id`, `certification_requise`, `niveau_min`, `ouvert`, `statut`, `cree_par`, `cree_le`, `propose_par`, `valide_par`, `valide_le`, `motif_refus`, `sur_candidature`

**`gt_applications`** — `groupe_id`, `application`

**`gt_candidatures`** — `id`, `groupe_id`, `profil_id`, `motivation`, `statut`, `reponse`, `traite_par`, `traite_le`, `cree_le`

**`gt_documents`** — `id`, `groupe_id`, `titre`, `description`, `type`, `url`, `contenu`, `depose_par`, `cree_le`

**`gt_membres`** — `id`, `groupe_id`, `profil_id`, `role`, `statut`, `invite_par`, `cree_le`

**`gt_taches`** — `id`, `groupe_id`, `titre`, `description`, `assigne_a`, `echeance`, `priorite`, `statut`, `cree_par`, `cree_le`, `faite_le`

**`inscriptions_evenement`** — `id`, `evenement_id`, `profil_id`, `nom`, `prenom`, `email`, `telephone`, `organisme`, `besoin`, `categories`, `statut`, `motif`, `valide_par`, `valide_le`, `jeton`, `efface_le`, `cree_le`

**`interims`** — `id`, `titulaire_id`, `interimaire_id`, `poste`, `debut`, `fin`, `motif`, `accepte_le`, `refuse_le`, `clos_le`, `decide_par`, `cree_le`

**`inventaire`** — `id`, `territoire_id`, `article_id`, `libelle_libre`, `quantite`, `etat`, `emplacement`, `origine`, `commande_id`, `valeur_euros`, `acquis_le`, `observation`, `maj_par`, `maj_le`

**`investissements`** — `id`, `reference`, `territoire_id`, `demandeur_id`, `intitule`, `justification`, `usage_prevu`, `beneficiaires`, `fournisseur`, `devis`, `montant`, `exercice_id`, `poste_budget`, `mission_id`, `projet_id`, `statut`, `avis_logistique`, `instruit_par`, `instruit_le`, `ordonnance_par`, `ordonnance_le`, `motif_refus`, `engage_le`, `recu_le`, `facture`, `cree_le`

**`journal`** — `id`, `acteur`, `action`, `cible`, `details`, `cree_le`

**`journal_acces`** — `id`, `profil_id`, `application`, `cree_le`

**`lecons`** — `id`, `module_id`, `titre`, `type`, `contenu`, `url`, `duree_min`, `ordre`

**`mandats`** — `id`, `assemblee_id`, `nomination_id`, `profil_id`, `poste`, `territoire_id`, `debut`, `fin`, `voix`, `suffrages`, `fin_anticipee`, `motif_fin`, `cree_le`

**`messages`** — `id`, `conversation_id`, `auteur_id`, `contenu`, `cree_le`, `retire`, `retire_par`, `piece`, `piece_nom`, `piece_taille`, `piece_type`, `organe`

**`mesures`** — `id`, `dossier_id`, `type`, `motif`, `texte_decision`, `date_effet`, `date_fin`, `statut`, `prise_par`, `prise_le`, `notifiee_le`, `accusee_le`, `delai_recours`, `cree_le`, `max_recours`, `renonce_le`, `renonce_texte`, `fichier`

**`mission_candidatures`** — `id`, `mission_id`, `profil_id`, `message`, `statut`, `motif`, `decide_par`, `decide_le`, `cree_le`

**`missions`** — `id`, `titre`, `description`, `territoire_id`, `groupe_id`, `certification_requise`, `lieu`, `debut`, `fin`, `heures_estimees`, `places`, `statut`, `cree_par`, `cree_le`, `budget_prevu`

**`modeles_com`** — `id`, `titre`, `canal`, `contenu`, `conseils`, `cree_par`, `cree_le`

**`modules`** — `id`, `formation_id`, `titre`, `resume`, `ordre`

**`nf_lignes`** — `id`, `note_id`, `date_depense`, `categorie`, `description`, `montant`, `kilometres`, `justificatif`, `cree_le`, `etat`, `observation`

**`nominations`** — `id`, `profil_id`, `poste`, `territoire_id`, `debut`, `fin`, `motif`, `nomme_par`, `revoque_le`, `revoque_par`, `motif_revocation`, `cree_le`

**`notes_frais`** — `id`, `reference`, `profil_id`, `objet`, `groupe_id`, `statut`, `deposee_le`, `instruit_par`, `instruit_le`, `avis`, `valide_par`, `valide_le`, `payee_le`, `reference_paiement`, `motif_refus`, `cree_le`, `mode_remboursement`, `ordonnance_par`, `ordonnance_le`, `imputation`, `recu_fiscal`, `avis_par`, `avis_le`, `accuse_le`, `conteste_le`, `motif_contestation`, `attestation`, `relance_le`, `demande_precisions`, `precisions_le`

**`organes`** — `code`, `nom`, `description`, `droit`, `logo`, `couleur`, `signature`, `actif`, `ordre`

**`outils_com`** — `id`, `nom`, `url`, `description`, `categorie`, `ordre`, `actif`

**`parametres_frais`** — `cle`, `valeur`, `libelle`, `unite`

**`parcours`** — `profil_id`, `referent_id`, `inscrit_le`, `dossier_complet_le`, `valide_le`, `contacte_le`, `rdv_le`, `forme_le`, `premiere_mission_le`, `abandonne_le`, `motif_abandon`, `notes`, `maj_le`

**`pistes_ap`** — `id`, `intitule`, `cible`, `contact_id`, `objectif`, `enjeu`, `echeance`, `etat`, `conclusion`, `responsable_id`, `maj_le`, `cree_le`

**`poste_applications`** — `poste`, `application`

**`poste_droits`** — `poste`, `droit`

**`poste_formations`** — `poste`, `certification`, `obligatoire`, `delai_jours`

**`postes`** — `code`, `nom`, `description`, `couleur`, `systeme`, `actif`, `cree_par`, `cree_le`, `direction`, `mission`, `delai_prise_fonction`, `suppleant_de`, `ordre_suppleance`, `rang`

**`postes_comptables`** — `code`, `libelle`, `sens`, `categorie`, `automatique`, `source`, `ordre`, `actif`

**`pouvoirs_ag`** — `id`, `assemblee_id`, `mandant_id`, `mandataire_id`, `statut`, `motif`, `cree_le`, `valide_par`

**`presences_assemblee`** — `assemblee_id`, `profil_id`, `constate_le`, `constate_par`

**`profils`** — `id`, `matricule`, `prenom`, `nom`, `email`, `telephone`, `fonction`, `territoire_id`, `echelon`, `statut`, `date_adhesion`, `photo_url`, `bio`, `visible_public`, `webmail`, `cree_le`, `maj_le`, `protege`, `motif_protection`, `sous_suivi`, `pronoms`, `langues`, `reseaux`, `devise`, `jeton_carte`

**`progression`** — `id`, `profil_id`, `lecon_id`, `score`, `tentatives`, `termine_le`

**`projet_participants`** — `projet_id`, `profil_id`, `role`, `cree_le`

**`projets`** — `id`, `reference`, `territoire_id`, `titre`, `objet`, `public_vise`, `partenaires`, `lieu`, `debut`, `fin`, `budget_estime`, `statut`, `avancement`, `responsable_id`, `groupe_id`, `origine_proposition`, `bilan`, `beneficiaires`, `cree_par`, `cree_le`, `maj_le`

**`promotions`** — `id`, `profil_id`, `ancien`, `nouveau`, `points`, `motif`, `decidee_par`, `cree_le`

**`proposition_soutiens`** — `proposition_id`, `profil_id`, `cree_le`

**`propositions`** — `id`, `reference`, `auteur_id`, `territoire_id`, `titre`, `description`, `besoin`, `public_vise`, `statut`, `reponse`, `decide_par`, `decide_le`, `projet_id`, `remontee_le`, `remontee_par`, `motif_remontee`, `soutiens`, `cree_le`

**`publications`** — `id`, `campagne_id`, `canal`, `titre`, `texte`, `image`, `lien`, `date_prevue`, `statut`, `auteur_id`, `valide_par`, `valide_le`, `observation`, `publie_le`, `cree_le`

**`questions`** — `id`, `lecon_id`, `enonce`, `aide`, `ordre`

**`rapports`** — `id`, `annee`, `territoire_id`, `titre`, `edito`, `faits_marquants`, `perspectives`, `remerciements`, `statut`, `adopte_le`, `redige_par`, `maj_le`, `cree_le`

**`recours`** — `id`, `mesure_id`, `auteur_id`, `contenu`, `fichier`, `statut`, `decision`, `decide_par`, `decide_le`, `suspensif`, `cree_le`, `fichier_decision`

**`regles_dotation`** — `cle`, `valeur`, `libelle`, `unite`, `ordre`, `maj_par`, `maj_le`

**`remontees_cabinet`** — `id`, `auteur_id`, `territoire_id`, `nature`, `objet`, `corps`, `lien`, `statut`, `traite_par`, `traite_le`, `reponse`, `acte_id`, `cree_le`

**`reponses`** — `id`, `question_id`, `texte`, `correcte`, `ordre`

**`sauvegardes`** — `id`, `periode`, `portee`, `fait_par`, `emplacement`, `observation`, `cree_le`

**`signalements`** — `id`, `conversation_id`, `message_id`, `auteur_id`, `motif`, `details`, `statut`, `assigne_a`, `decision`, `traite_par`, `traite_le`, `cree_le`

**`sollicitations_ap`** — `id`, `demandeur_id`, `territoire_id`, `groupe_id`, `objet`, `besoin`, `echeance`, `statut`, `reponse`, `traite_par`, `traite_le`, `cree_le`

**`structure_journal`** — `id`, `territoire_id`, `etat`, `motif`, `acteur`, `cree_le`

**`suggestions_com`** — `id`, `reference`, `titre`, `contexte`, `texte`, `canaux`, `visuel`, `lien_canva`, `hashtags`, `a_publier_le`, `expire_le`, `territoire_id`, `campagne_id`, `consignes`, `priorite`, `statut`, `cree_par`, `cree_le`

**`suggestions_reprises`** — `id`, `suggestion_id`, `profil_id`, `territoire_id`, `canal`, `publie_le`, `lien`, `observation`

**`taches_assignees`** — `id`, `titre`, `description`, `assigne_a`, `assigne_par`, `echeance`, `statut`, `delegue_de`, `annule_par`, `annule_le`, `motif_annulation`, `faite_le`, `cree_le`, `maj_le`

**`territoires`** — `id`, `parent_id`, `echelle`, `code`, `nom`, `actif`, `cree_le`, `etat`, `cree_le_reel`, `agree_le`, `sommeil_le`, `motif_etat`, `rattache_a`, `academie`, `siege`, `courriel`, `telephone`, `population`, `note`, `cree_le_reel`

**`ticket_messages`** — `id`, `ticket_id`, `auteur_id`, `contenu`, `cree_le`

**`tickets`** — `id`, `reference`, `auteur_id`, `nature`, `titre`, `description`, `page`, `importance`, `statut`, `assigne_a`, `echeance`, `reponse`, `traite_par`, `traite_le`, `cree_le`, `maj_le`, `urgent`, `contexte`, `vu_par_auteur_le`

**`types_distinction`** — `code`, `nom`, `description`, `couleur`, `points`, `ordre`, `actif`

**`votes`** — `id`, `assemblee_id`, `electeur_id`, `cree_le`, `recepisse`, `pouvoirs_exerces`

---

## Domaines énumérés en vigueur

Avant d'insérer une valeur nouvelle, élargir la contrainte (`drop constraint` puis `add constraint`). Corriger la règle, jamais rabattre la donnée.

- `couleur` : neutre, or, bleu, vert, rouge
- `echelle` : national, region, departement, local
- `famille` : adhesion, encadrement, direction
- `format` : texte, long, nombre, url
- `portee` : fiche, echanges
- `role` : responsable, membre
- `sens` : produit, charge
- `statut` : invite, actif, parti
- `type` : privee, groupe

---

## Fonctions SQL

Une fonction redéfinie plusieurs fois n'apparaît qu'une : la version en vigueur, avec le fichier où elle se trouve.

**`a_acces(app text)`** → `boolean` · sql · 19_coherence_distinctions.sql

**`a_certification(p_code text)`** → `boolean` · sql · 02_formations.sql

**`a_droit(p_droit text)`** → `boolean` · sql · 21_interim_suppleance.sql

**`a_droit_sur(p_droit text, p_territoire uuid)`** → `boolean` · sql · 07_habilitations.sql

**`abroger_acte(p_id uuid, p_motif text)`** → `jsonb` · plpgsql · 48_garde_abrogation.sql

**`accede_conversation(p_conv uuid)`** → `boolean` · sql · 41_organes.sql

**`accede_note(p_note uuid)`** → `boolean` · sql · 06_notes_frais.sql

**`acces_complets(p_profil uuid)`** → `table (application text, nom text, couleur text, ouvert bool` · sql · 16_garde_chancellerie.sql
  
  colonnes : `application`, `nom`, `couleur`, `ouvert`, `origine`, `detail`, `statut`, `expire_le`, `motif`, `derniere_utilisation`, `nb_ouvertures`, `retirable`

**`acces_du_perimetre(p_territoire uuid default null)`** → `table (profil_id uuid, membre text, matricule text, fonction` · sql · 39_gestion_locale.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `fonction`, `niveau`, `territoire`, `statut`, `applications`, `postes`, `echelon`

**`accompagnant_naturel(p_profil uuid)`** → `jsonb` · sql · 27_passeport_parcours.sql

**`accorder_acces(p_profil uuid, p_app text, p_motif text default null, p_expire date default null)`** → `jsonb` · plpgsql · 31_nominations.sql

**`accuser_reception(p_mesure uuid)`** → `jsonb` · plpgsql · 08_discipline.sql

**`accuser_virement(p_note uuid, p_recu boolean, p_motif text default null)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`actes_a_controler()`** → `table (id uuid, auteur text, auteur_fonction text, cible tex` · sql · 16_garde_chancellerie.sql
  
  colonnes : `id`, `auteur`, `auteur_fonction`, `cible`, `cible_matricule`, `nature`, `libelle`, `reversible`, `cree_le`

**`actualites(p_limite integer default 6)`** → `table (slug text, titre text, chapo text, image text, catego` · sql · 14_migration.sql
  
  colonnes : `slug`, `titre`, `chapo`, `image`, `categorie`, `publie_le`, `auteur`

**`affecter_accompagnant(p_profil uuid, p_accompagnant uuid, p_motif text default null)`** → `jsonb` · plpgsql · 27_passeport_parcours.sql

**`affecter_points_projet(p_nature text, p_ref text, p_projet uuid, p_points integer, p_motif text)`** → `jsonb` · plpgsql · 40_enveloppes.sql

**`agir_parcours(p_profil uuid, p_action text, p_texte text default null)`** → `jsonb` · plpgsql · 20_directions_parcours.sql

**`agir_parcours_groupe(p_profils uuid[], p_action text, p_texte text default null)`** → `jsonb` · plpgsql · 20_directions_parcours.sql

**`ajouter_au_panier(p_article uuid, p_quantite integer, p_variante text default null, p_commande uuid default null)`** → `jsonb` · plpgsql · 38_ressources_budget.sql

**`ajuster_acces_groupes(p_profil uuid)`** → `void` · plpgsql · 35_equipes.sql

**`alertes_consultation()`** → `table ( id bigint, observateur_nom text, observateur_fonctio` · sql · 07_habilitations.sql
  
  colonnes : `id`, `observateur_nom`, `observateur_fonction`, `observe_nom`, `observe_matricule`, `contexte`, `cree_le`

**`alertes_nouveaux()`** → `table (code text, libelle text, nombre integer, lien text, u` · sql · 27_passeport_parcours.sql
  
  colonnes : `code`, `libelle`, `nombre`, `lien`, `urgence`

**`ancetre_echelle(cible uuid, p_echelle text)`** → `uuid` · sql · 05_messagerie_correctifs.sql

**`annuler_creneau(p_creneau uuid, p_motif text)`** → `jsonb` · plpgsql · 18_parcours_pilotage.sql

**`annuler_pouvoir(p_assemblee uuid)`** → `jsonb` · plpgsql · 45_correctifs_ag.sql

**`annuler_tache(p_tache uuid, p_motif text)`** → `jsonb` · plpgsql · 51_taches_et_remontees.sql

**`ap_service()`** → `boolean` · sql · 37_affaires_publiques.sql

**`appel_public(p_token text)`** → `jsonb` · sql · 17_vie_statutaire.sql

**`applications_delegables()`** → `table (code text, nom text, nom_court text, description text` · sql · 39_gestion_locale.sql
  
  colonnes : `code`, `nom`, `nom_court`, `description`, `ouvrable`, `motif`

**`appliquer_mesure()`** → `trigger` · plpgsql · 08_discipline.sql

**`arbitrer_candidature_formation(p_id uuid, p_statut text, p_avis text)`** → `jsonb` · plpgsql · 27_passeport_parcours.sql

**`archives_electorales(p_territoire uuid default null)`** → `table (assemblee_id uuid, reference text, titre text, type t` · sql · 19_coherence_distinctions.sql
  
  colonnes : `assemblee_id`, `reference`, `titre`, `type`, `territoire`, `date_tenue`, `proclame_le`, `inscrits`, `votants`, `participation`, `proces_verbal`, `pv_fichier`, `elus`, `jai_participe`

**`article(p_slug text)`** → `jsonb` · sql · 14_migration.sql

**`assigner_tache(p_assigne_a uuid, p_titre text, p_description text default null, p_echeance date default null)`** → `jsonb` · plpgsql · 51_taches_et_remontees.sql

**`attribuer_dotations(p_annee integer)`** → `jsonb` · plpgsql · 28_ressources.sql

**`avancement(p_formation uuid, p_profil uuid default null)`** → `table (total integer, faites integer, pourcent integer)` · sql · 02_formations.sql
  
  colonnes : `total`, `faites`, `pourcent`

**`bareme_echelons()`** → `table (niveau integer, nom text, points integer, ouvre text,` · sql · 39_gestion_locale.sql
  
  colonnes : `niveau`, `nom`, `points`, `ouvre`, `description`, `membres`

**`bilans_a_rediger()`** → `table (mission_id uuid, mission text, fin date, lieu text, p` · sql · 27_passeport_parcours.sql
  
  colonnes : `mission_id`, `mission`, `fin`, `lieu`, `profil_id`, `membre`, `matricule`, `jours_depuis`

**`bord_local()`** → `jsonb` · sql · 18_parcours_pilotage.sql

**`bord_national()`** → `jsonb` · sql · 18_parcours_pilotage.sql

**`budget_exercice(p_exercice uuid)`** → `jsonb` · sql · 23_budget_rapport.sql

**`budget_mission(p_mission uuid)`** → `jsonb` · sql · 28_ressources.sql

**`bureau_territoire(p_territoire uuid)`** → `table (poste text, poste_nom text, titulaire text, matricule` · sql · 15_pilotage_unifie.sql
  
  colonnes : `poste`, `poste_nom`, `titulaire`, `matricule`, `profil_id`, `depuis`, `fin`

**`calculer_dotation(p_territoire uuid, p_annee integer)`** → `jsonb` · sql · 28_ressources.sql

**`calendrier_com(p_depuis date default null, p_jusqu date default null)`** → `table ( id uuid, titre text, canal text, statut text, date_p` · sql · 14_migration.sql
  
  colonnes : `id`, `titre`, `canal`, `statut`, `date_prevue`, `campagne`, `auteur`, `valideur`, `observation`, `image`

**`candidatures_formation_a_arbitrer()`** → `table (id uuid, formation text, formation_id uuid, session_d` · sql · 27_passeport_parcours.sql
  
  colonnes : `id`, `formation`, `formation_id`, `session_debut`, `lieu`, `places`, `candidat`, `matricule`, `profil_id`, `territoire`, `motivation`, `statut`, `avis_local`, `cree_le`, `mon_ressort`

**`candidatures_groupe(p_groupe uuid default null)`** → `table (id uuid, groupe_id uuid, groupe text, candidat text, ` · sql · 35_equipes.sql
  
  colonnes : `id`, `groupe_id`, `groupe`, `candidat`, `candidat_id`, `fonction`, `territoire`, `motivation`, `statut`, `cree_le`

**`ce_qui_attend()`** → `table (code text, libelle text, nombre integer, lien text, u` · sql · 33_messagerie.sql
  
  colonnes : `code`, `libelle`, `nombre`, `lien`, `urgence`

**`chancellerie_synthese()`** → `jsonb` · sql · 16_garde_chancellerie.sql

**`changer_etat_structure(p_territoire uuid, p_etat text, p_motif text, p_rattache uuid default null)`** → `jsonb` · plpgsql · 17_vie_statutaire.sql

**`changer_phase_assemblee(p_assemblee uuid, p_statut text)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`changer_statut_evenement(p_id uuid, p_statut text, p_motif text default null)`** → `jsonb` · plpgsql · 47_evenements.sql

**`changer_statut_exercice(p_id uuid, p_statut text, p_observations text default null)`** → `jsonb` · plpgsql · 23_budget_rapport.sql

**`checklist_ouverture(p_profil uuid default null)`** → `table (code text, libelle text, etat text, detail text, lien` · sql · 31_nominations.sql
  
  colonnes : `code`, `libelle`, `etat`, `detail`, `lien`, `ordre`

**`chemin_territoire(cible uuid)`** → `text` · sql · 01_socle.sql

**`chiffres_annee(p_annee integer, p_territoire uuid default null)`** → `jsonb` · sql · 23_budget_rapport.sql

**`classement_merites(p_territoire uuid default null, p_limite integer default 50)`** → `table (profil_id uuid, membre text, matricule text, fonction` · sql · 16_garde_chancellerie.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `fonction`, `territoire`, `echelon`, `points`, `palier_suivant`, `atteint`, `heures_annee`, `missions`, `certifications`, `derniere_activite`

**`cles_du_depouillement(p_assemblee uuid)`** → `table (profil_id uuid, membre text, role text, signe_le time` · sql · 45_correctifs_ag.sql
  
  colonnes : `profil_id`, `membre`, `role`, `signe_le`

**`clore_dossier(p_dossier uuid, p_conclusion text)`** → `jsonb` · plpgsql · 10_discipline_consolidation.sql

**`clore_interim(p_id uuid)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`clore_signalement(p_sig uuid, p_fonde boolean, p_decision text)`** → `jsonb` · plpgsql · 05_messagerie_correctifs.sql

**`code_postal_valide(t text)`** → `boolean` · sql · 19_coherence_distinctions.sql

**`completer_note(p_note uuid)`** → `jsonb` · plpgsql · 36_notes_engagement.sql

**`completude_bloquante()`** → `jsonb` · sql · 16_garde_chancellerie.sql

**`completude_dossier(p_profil uuid default null)`** → `jsonb` · sql · 19_coherence_distinctions.sql

**`confier_interim(p_interimaire uuid, p_poste text, p_debut date, p_fin date, p_motif text)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`confier_signalement(p_sig uuid, p_a uuid)`** → `jsonb` · plpgsql · 05_messagerie_correctifs.sql

**`conformite_a_traiter()`** → `table (candidature_id uuid, assemblee_id uuid, reference tex` · sql · 19_coherence_distinctions.sql
  
  colonnes : `candidature_id`, `assemblee_id`, `reference`, `assemblee`, `territoire`, `date_tenue`, `cloture_candidatures`, `poste_nom`, `candidat`, `matricule`, `profession_foi`, `depose_le`, `jours_avant_cloture`

**`conformite_poste(p_profil uuid, p_poste text)`** → `jsonb` · sql · 21_interim_suppleance.sql

**`consigner_echange(d jsonb)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`consulter_profil(p_profil uuid, p_contexte text default null)`** → `table ( id uuid, matricule text, prenom text, nom text, emai` · plpgsql · 07_habilitations.sql
  
  colonnes : `id`, `matricule`, `prenom`, `nom`, `email`, `telephone`, `fonction_nom`, `echelon`, `territoire_nom`, `statut`, `date_adhesion`, `bio`, `protege`

**`contact_visible(p_contact uuid)`** → `boolean` · sql · 37_affaires_publiques.sql

**`controler_acte(p_acte uuid, p_confirmer boolean, p_observation text default null)`** → `jsonb` · plpgsql · 34_gardes.sql

**`controler_entree(p_jeton text, p_categorie text default 'general')`** → `jsonb` · plpgsql · 47_evenements.sql

**`conversation_groupe(p_groupe uuid)`** → `jsonb` · plpgsql · 04_messagerie.sql

**`conversation_organe(p_organe text, p_avec uuid)`** → `jsonb` · plpgsql · 41_organes.sql

**`conversation_privee(p_autre uuid)`** → `jsonb` · plpgsql · 05_messagerie_correctifs.sql

**`corps_electoral(p_assemblee uuid)`** → `table (profil_id uuid, membre text, matricule text, a_vote b` · sql · 17_vie_statutaire.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `a_vote`

**`creer_assemblee(p_territoire uuid, p_titre text, p_type text, p_date timestamptz, p_lieu text, p_ordre_du_jour text, p_cloture_cand date, p_ouverture_scrutin timestamptz, p_cloture_scrutin timestamptz, p_quorum integer, p_duree integer)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`creer_groupe(p_nom text, p_objet text, p_territoire uuid default null, p_certification text default null, p_niveau_min integer default 10, p_ouvert boolean default true)`** → `jsonb` · plpgsql · 03_groupes.sql

**`creer_mission(p_titre text, p_description text, p_territoire uuid default null, p_groupe uuid default null, p_certification text default null, p_lieu text default null, p_debut date default null, p_fin date default null, p_heures numeric default null, p_places integer default 1)`** → `jsonb` · plpgsql · 12_engagement.sql

**`creer_profil()`** → `trigger` · plpgsql · 01_socle.sql

**`creer_structure(p_parent uuid, p_nom text, p_code text, p_echelle text default 'local')`** → `jsonb` · plpgsql · 17_vie_statutaire.sql

**`creer_suggestion(p_titre text, p_contexte text, p_texte text, p_canaux text[], p_visuel text default null, p_canva text default null, p_hashtags text default null, p_publier_le date default null, p_expire_le date default null, p_consignes text default null, p_priorite text default 'normale', p_territoire uuid default null)`** → `jsonb` · plpgsql · 24_suggestions_assistance.sql

**`creneaux_disponibles()`** → `table (id uuid, debut timestamptz, duree_min integer, lieu t` · sql · 18_parcours_pilotage.sql
  
  colonnes : `id`, `debut`, `duree_min`, `lieu`, `visio`, `hote`, `hote_fonction`

**`dans_mon_perimetre(cible uuid)`** → `boolean` · sql · 01_socle.sql

**`decerner_distinction(p_profil uuid, p_type text, p_motif text, p_texte text default null, p_publique boolean default true)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`declarer_reprise(p_suggestion uuid, p_canal text, p_lien text default null, p_observation text default null)`** → `jsonb` · plpgsql · 24_suggestions_assistance.sql

**`declarer_sauvegarde(p_portee text, p_emplacement text, p_observation text default null)`** → `jsonb` · plpgsql · 23_budget_rapport.sql

**`deleguer_tache(p_tache uuid, p_a uuid)`** → `jsonb` · plpgsql · 51_taches_et_remontees.sql

**`delivrer_certifications()`** → `void` · plpgsql · 02_formations.sql

**`demander_investissement(p_intitule text, p_justification text, p_usage text, p_montant numeric, p_fournisseur text default null, p_devis text default null, p_beneficiaires integer default null, p_mission uuid default null, p_projet uuid default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`demander_precisions(p_note uuid, p_message text)`** → `jsonb` · plpgsql · 36_notes_engagement.sql

**`deplacer(p_table text, p_id uuid, p_sens integer)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`deposer_attestation(p_note uuid, p_fichier text)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`deposer_candidature(p_assemblee uuid, p_poste text, p_profession_foi text, p_fichier text default null)`** → `jsonb` · plpgsql · 17_vie_statutaire.sql

**`deposer_commande(p_id uuid, p_motif text default null, p_adresse text default null, p_destinataire text default null, p_source text default 'territoire')`** → `jsonb` · plpgsql · 42_engagement.sql

**`deposer_note(p_note uuid)`** → `jsonb` · plpgsql · 09_finances.sql

**`deposer_recours(p_mesure uuid, p_contenu text, p_fichier text default null)`** → `jsonb` · plpgsql · 08_discipline.sql

**`depouillement(p_assemblee uuid)`** → `jsonb` · sql · 17_vie_statutaire.sql

**`destinataires_possibles()`** → `table (id uuid, prenom text, nom text, matricule text, fonct` · sql · 05_messagerie_correctifs.sql
  
  colonnes : `id`, `prenom`, `nom`, `matricule`, `fonction_nom`, `niveau`, `territoire_nom`

**`detail_suivi(p_profil uuid)`** → `table (application text, app_nom text, cree_le timestamptz, ` · sql · 13_correctifs_progression.sql
  
  colonnes : `application`, `app_nom`, `cree_le`, `vue_le`

**`donner_avis(p_note uuid, p_favorable boolean, p_avis text)`** → `jsonb` · plpgsql · 09_finances.sql

**`donner_pouvoir(p_assemblee uuid, p_mandataire uuid)`** → `jsonb` · plpgsql · 45_correctifs_ag.sql

**`dossier_est_clos(p_dossier uuid)`** → `boolean` · sql · 21_interim_suppleance.sql

**`dossiers_discipline(p_filtre text default 'ouverts')`** → `table ( id uuid, reference text, objet text, qualification t` · sql · 08_discipline.sql
  
  colonnes : `id`, `reference`, `objet`, `qualification`, `gravite`, `statut`, `origine`, `ouvert_le`, `clos_le`, `conclusion`, `profil_id`, `concerne`, `matricule`, `territoire_nom`, `instructeur`, `nb_pieces`, `nb_mesures`, `recours_en_attente`

**`dotations_exceptionnelles_recentes(p_annee integer default null)`** → `table (id uuid, territoire text, points integer, motif text,` · sql · 38_ressources_budget.sql
  
  colonnes : `id`, `territoire`, `points`, `motif`, `campagne`, `accorde_par`, `cree_le`

**`doter_exceptionnellement(p_points integer, p_motif text, p_portee text default 'territoires', p_territoires uuid[] default '{}', p_echelle text default null, p_campagne text default null, p_annee integer default null, p_directions text[] default '{}', p_profils uuid[] default '{}')`** → `jsonb` · plpgsql · 40_enveloppes.sql

**`echoir_mesures()`** → `integer` · sql · 08_discipline.sql

**`emarger_par_carte(p_jeton text, p_assemblee uuid)`** → `jsonb` · plpgsql · 43_adherent.sql

**`empreinte_emargement(p_assemblee uuid, p_electeur uuid, p_quand timestamptz)`** → `text` · sql · 46_scrutin.sql

**`engagements_a_valider()`** → `table (id uuid, reference text, demandeur text, territoire t` · sql · 42_engagement.sql
  
  colonnes : `id`, `reference`, `demandeur`, `territoire`, `points`, `finance_par`, `motif`, `cree_le`

**`engager_enveloppes(p_commande uuid, p_plan jsonb)`** → `void` · plpgsql · 42_engagement.sql

**`enregistrer_adhesion(d jsonb)`** → `jsonb` · plpgsql · 12_engagement.sql

**`enregistrer_article(p_id uuid, p_titre text, p_chapo text, p_contenu text, p_image text, p_categorie text, p_publie boolean)`** → `jsonb` · plpgsql · 14_migration.sql

**`enregistrer_aspirations(p_profil uuid, d jsonb)`** → `jsonb` · plpgsql · 27_passeport_parcours.sql

**`enregistrer_certification(p_code text, p_nom text, p_description text, p_formation uuid, p_validite integer default null)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_contact(d jsonb)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`enregistrer_evenement(d jsonb)`** → `jsonb` · plpgsql · 47_evenements.sql

**`enregistrer_formation(p_id uuid, p_code text, p_titre text, p_resume text, p_description text, p_niveau_min integer, p_duree integer, p_seuil integer, p_publiee boolean, p_ordre integer default 100, p_image text default null, p_prerequis text default null)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_interlocuteur(d jsonb)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`enregistrer_inventaire(p_id uuid, p_article uuid, p_libelle text, p_quantite integer, p_etat text, p_emplacement text, p_origine text default 'achat_local', p_valeur numeric default null, p_observation text default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`enregistrer_lecon(p_id uuid, p_module uuid, p_titre text, p_type text, p_contenu text default null, p_url text default null, p_duree integer default null)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_module(p_id uuid, p_formation uuid, p_titre text, p_resume text default null)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_piste(d jsonb)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`enregistrer_projet(p_id uuid, p_titre text, p_objet text, p_lieu text, p_debut date, p_fin date, p_statut text, p_avancement integer, p_public text default null, p_partenaires text default null, p_budget numeric default null, p_territoire uuid default null)`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`enregistrer_question(p_id uuid, p_lecon uuid, p_enonce text, p_aide text default null)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_rapport(p_annee integer, p_territoire uuid, p_titre text, p_edito text, p_faits text, p_perspectives text, p_remerciements text, p_statut text)`** → `jsonb` · plpgsql · 23_budget_rapport.sql

**`enregistrer_reponse(p_id uuid, p_question uuid, p_texte text, p_correcte boolean)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`enregistrer_rib(p_titulaire text, p_iban text, p_bic text default null)`** → `jsonb` · plpgsql · 09_finances.sql

**`envoyer_message(p_conv uuid, p_contenu text default null, p_piece text default null, p_piece_nom text default null, p_taille integer default null, p_type text default null, p_au_nom_de text default null)`** → `jsonb` · plpgsql · 41_organes.sql

**`equipes_a_valider()`** → `table (id uuid, nom text, objet text, territoire text, propo` · sql · 35_equipes.sql
  
  colonnes : `id`, `nom`, `objet`, `territoire`, `propose_par`, `membres`, `applications`, `cree_le`

**`est_admin()`** → `boolean` · sql · 01_socle.sql

**`est_encadrant()`** → `boolean` · sql · 01_socle.sql

**`est_membre_gt(p_groupe uuid)`** → `boolean` · sql · 03_groupes.sql

**`est_ordonnateur()`** → `boolean` · sql · 09_finances.sql

**`est_participant(p_conv uuid)`** → `boolean` · sql · 41_organes.sql

**`est_responsable_gt(p_groupe uuid)`** → `boolean` · sql · 03_groupes.sql

**`est_tresorier()`** → `boolean` · sql · 06_notes_frais.sql

**`etat_application(p_app text, p_fonction text default null)`** → `text` · sql · 11_lisibilite_droits.sql

**`etat_reseau(p_echelle text default 'departement')`** → `table ( territoire_id uuid, territoire text, echelle text, p` · sql · 15_pilotage_unifie.sql
  
  colonnes : `territoire_id`, `territoire`, `echelle`, `parent`, `membres`, `actifs`, `encadrants`, `president`, `tresorier`, `secretaire`, `mandats_pourvus`, `groupes`, `engagement_mois`

**`etat_ressources(p_territoire uuid default null)`** → `table (territoire_id uuid, territoire text, echelle text, ar` · sql · 28_ressources.sql
  
  colonnes : `territoire_id`, `territoire`, `echelle`, `article`, `reference`, `categorie`, `quantite`, `etat`, `emplacement`, `origine`, `valeur`, `maj_le`

**`etat_sauvegardes()`** → `jsonb` · sql · 23_budget_rapport.sql

**`evenement_public(p_jeton text)`** → `jsonb` · sql · 47_evenements.sql

**`examiner_candidature(p_id uuid, p_recevable boolean, p_motif text default null)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`exceptions_reseau()`** → `table (territoire_id uuid, territoire text, echelle text, pa` · sql · 18_parcours_pilotage.sql
  
  colonnes : `territoire_id`, `territoire`, `echelle`, `parent`, `membres`, `alerte`, `gravite`

**`export_budget(p_exercice uuid)`** → `table (sens text, categorie text, code text, libelle text, i` · sql · 23_budget_rapport.sql
  
  colonnes : `sens`, `categorie`, `code`, `libelle`, `intitule`, `prevu`, `realise`, `ecart`, `execution`, `source`, `commentaire`

**`export_depenses(p_exercice uuid)`** → `table (reference text, date_paiement date, beneficiaire text` · sql · 23_budget_rapport.sql
  
  colonnes : `reference`, `date_paiement`, `beneficiaire`, `matricule`, `territoire`, `objet`, `montant`, `mode`, `reference_paiement`, `instruit_par`, `ordonnance_par`, `paye_par`, `accuse_le`

**`faire_remonter(p_id uuid, p_motif text)`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`fermer_paquet_poste()`** → `trigger` · plpgsql · 21_interim_suppleance.sql

**`feuille_presence(p_assemblee uuid)`** → `table (profil_id uuid, membre text, matricule text, fonction` · sql · 46_scrutin.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `fonction`, `territoire`, `etat`, `mandataire`, `emarge_le`, `constate_le`

**`fiche_admin(p_profil uuid)`** → `jsonb` · sql · 15_pilotage_unifie.sql

**`fiche_membre(p_profil uuid, p_reveler boolean default false)`** → `jsonb` · plpgsql · 11_lisibilite_droits.sql

**`fiche_territoire(p_territoire uuid)`** → `jsonb` · sql · 39_gestion_locale.sql

**`fil_actualite(p_limite integer default 25)`** → `table (nature text, titre text, corps text, quand timestampt` · sql · 43_adherent.sql
  
  colonnes : `nature`, `titre`, `corps`, `quand`, `lien`, `action`, `portee`, `urgent`

**`fil_ticket(p_id uuid)`** → `jsonb` · sql · 24_suggestions_assistance.sql

**`flecher_vers_cabinet(p_nature text, p_objet text, p_corps text, p_lien text default null)`** → `jsonb` · plpgsql · 32_cabinet.sql

**`formation_complete(p_formation uuid)`** → `jsonb` · sql · 26_editeur_formations.sql

**`fusionner_territoires(p_source uuid, p_cible uuid, p_motif text)`** → `jsonb` · plpgsql · 39_gestion_locale.sql

**`groupes_ouverts()`** → `table (id uuid, nom text, objet text, territoire text, porte` · sql · 35_equipes.sql
  
  colonnes : `id`, `nom`, `objet`, `territoire`, `portee`, `membres`, `ma_candidature`

**`habilites_engagement(p_nature text, p_ref text)`** → `table (profil_id uuid, membre text, poste text)` · sql · 42_engagement.sql
  
  colonnes : `profil_id`, `membre`, `poste`

**`iban_plausible(p text)`** → `boolean` · sql · 09_finances.sql

**`inscription_publique(p_jeton text, d jsonb)`** → `jsonb` · plpgsql · 47_evenements.sql

**`inscrire_a_evenement(p_evenement uuid, p_categories text[] default '{}', p_besoin text default null)`** → `jsonb` · plpgsql · 47_evenements.sql

**`inscrire_acte(p_cible uuid, p_nature text, p_libelle text, p_avant jsonb default null, p_apres jsonb default null, p_reversible boolean default true)`** → `uuid` · sql · 16_garde_chancellerie.sql

**`insigne_membre(p_profil uuid)`** → `jsonb` · sql · 21_interim_suppleance.sql

**`insignes(p_profils uuid[])`** → `table (profil_id uuid, echelon integer, echelon_nom text, di` · sql · 21_interim_suppleance.sql
  
  colonnes : `profil_id`, `echelon`, `echelon_nom`, `distinction`, `couleur`, `poste`

**`instruire_investissement(p_id uuid, p_favorable boolean, p_avis text, p_poste text default null, p_exercice uuid default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`instruire_note(p_note uuid, p_favorable boolean, p_avis text)`** → `jsonb` · plpgsql · 36_notes_engagement.sql

**`interim_actif(i interims)`** → `boolean` · sql · 21_interim_suppleance.sql

**`investissements_a_traiter(p_filtre text default 'a_instruire')`** → `table (id uuid, reference text, intitule text, justification` · sql · 28_ressources.sql
  
  colonnes : `id`, `reference`, `intitule`, `justification`, `usage_prevu`, `montant`, `fournisseur`, `devis`, `demandeur`, `territoire`, `beneficiaires`, `mission`, `projet`, `statut`, `avis_logistique`, `poste_budget`, `cree_le`

**`inviter_au_groupe(p_groupe uuid, p_profil uuid)`** → `jsonb` · plpgsql · 03_groupes.sql

**`jalonner_parcours(p_profil uuid)`** → `void` · plpgsql · 18_parcours_pilotage.sql

**`je_supplee(p_poste text, p_territoire uuid)`** → `boolean` · sql · 21_interim_suppleance.sql

**`journal_pieces(p_jours integer default 30)`** → `table (envoye_le timestamptz, auteur text, auteur_fonction t` · sql · 33_messagerie.sql
  
  colonnes : `envoye_le`, `auteur`, `auteur_fonction`, `territoire`, `destinataires`, `type_conversation`, `nom`, `taille`, `format`

**`lecon_ouverte(p_lecon uuid)`** → `boolean` · plpgsql · 02_formations.sql

**`limite_recours(m mesures)`** → `date` · sql · 08_discipline.sql

**`lire_carte(p_jeton text)`** → `jsonb` · sql · 43_adherent.sql

**`lire_rib(p_note uuid)`** → `jsonb` · plpgsql · 09_finances.sql

**`liste_directions()`** → `table (code text, nom text, nom_court text, ordre integer)` · sql · 30_menu.sql
  
  colonnes : `code`, `nom`, `nom_court`, `ordre`

**`liste_inscrits(p_evenement uuid, p_filtre text default 'tous')`** → `table (id uuid, nom text, matricule text, courriel text, tel` · sql · 47_evenements.sql
  
  colonnes : `id`, `nom`, `matricule`, `courriel`, `telephone`, `organisme`, `externe`, `categories`, `besoin`, `statut`, `entrees`, `cree_le`

**`liste_tickets(p_filtre text default 'ouverts')`** → `table (id uuid, reference text, nature text, titre text, des` · sql · 19_coherence_distinctions.sql
  
  colonnes : `id`, `reference`, `nature`, `titre`, `description`, `page`, `importance`, `statut`, `echeance`, `auteur`, `auteur_matricule`, `assigne`, `assigne_id`, `reponse`, `cree_le`, `maj_le`, `messages`, `retard`

**`ma_carte()`** → `jsonb` · sql · 43_adherent.sql

**`ma_chaine()`** → `jsonb` · sql · 27_passeport_parcours.sql

**`ma_suppleance()`** → `table (poste text, poste_nom text, territoire text, territoi` · sql · 21_interim_suppleance.sql
  
  colonnes : `poste`, `poste_nom`, `territoire`, `territoire_id`, `depuis_quand`

**`maj_soutiens()`** → `trigger` · plpgsql · 22_mon_comite.sql

**`mandats_a_renouveler()`** → `table (mandat_id uuid, membre text, poste_nom text, territoi` · sql · 17_vie_statutaire.sql
  
  colonnes : `mandat_id`, `membre`, `poste_nom`, `territoire`, `territoire_id`, `debut`, `fin`, `jours_restants`

**`marquer_alerte_vue(p_id bigint)`** → `void` · sql · 07_habilitations.sql

**`marquer_lu(p_conv uuid)`** → `void` · sql · 04_messagerie.sql

**`marquer_pieces_vues()`** → `jsonb` · plpgsql · 33_messagerie.sql

**`marquer_suivi_vu(p_profil uuid)`** → `jsonb` · plpgsql · 13_correctifs_progression.sql

**`matrice_acces()`** → `table (application text, app_nom text, ordre integer, droit_` · sql · 19_coherence_distinctions.sql
  
  colonnes : `application`, `app_nom`, `ordre`, `droit_requis`, `droit_nom`, `fonction`, `fonction_nom`, `niveau`, `etat`, `contournements`

**`membres_pour_discipline(p_recherche text default null)`** → `table (id uuid, prenom text, nom text, matricule text, email` · sql · 13_correctifs_progression.sql
  
  colonnes : `id`, `prenom`, `nom`, `matricule`, `email`, `fonction_nom`, `territoire_nom`, `statut`, `dossiers_ouverts`

**`mes_alertes_parcours()`** → `table (id uuid, profil_concerne uuid, membre text, message t` · sql · 28_ressources.sql
  
  colonnes : `id`, `profil_concerne`, `membre`, `message`, `nature`, `auteur`, `auteur_fonction`, `cree_le`, `traite_le`, `reponse`

**`mes_applications()`** → `table ( code text, nom text, nom_court text, description tex` · sql · 35_equipes.sql
  
  colonnes : `code`, `nom`, `nom_court`, `description`, `accroche`, `logo`, `couleur`, `externe_url`, `ordre`, `direction`, `direction_nom`, `direction_ordre`, `etat`, `source`, `ouvert`, `demande_en_cours`, `explication`, `personnelle`

**`mes_assemblees()`** → `table (id uuid, reference text, titre text, type text, statu` · sql · 17_vie_statutaire.sql
  
  colonnes : `id`, `reference`, `titre`, `type`, `statut`, `territoire`, `territoire_id`, `date_tenue`, `lieu`, `cloture_candidatures`, `cloture_scrutin`, `public_token`, `electeur`, `a_vote`, `ma_candidature`, `candidats`, `votants`, `inscrits`

**`mes_conversations()`** → `table ( id uuid, type text, groupe_id uuid, titre text, dern` · sql · 41_organes.sql
  
  colonnes : `id`, `type`, `groupe_id`, `titre`, `derniere_activite`, `dernier_message`, `dernier_auteur`, `non_lus`, `superviseur`, `signale`, `organe`, `organe_nom`, `organe_logo`, `organe_couleur`

**`mes_delegations()`** → `jsonb` · sql · 21_interim_suppleance.sql

**`mes_directions()`** → `table (code text, nom text, nom_court text, couleur text, or` · sql · 45_correctifs_ag.sql
  
  colonnes : `code`, `nom`, `nom_court`, `couleur`, `ordre`, `par_poste`, `postes`, `bloc_permanent`

**`mes_distinctions(p_profil uuid default null)`** → `table (numero text, type text, type_nom text, couleur text, ` · sql · 19_coherence_distinctions.sql
  
  colonnes : `numero`, `type`, `type_nom`, `couleur`, `motif`, `texte`, `decernee_le`, `par`

**`mes_droits()`** → `table (code text, nom text, categorie text, sensible boolean` · sql · 29_correctifs.sql
  
  colonnes : `code`, `nom`, `categorie`, `sensible`, `source`

**`mes_enveloppes(p_annee integer default null)`** → `table (nature text, ref text, libelle text, recu integer, re` · sql · 40_enveloppes.sql
  
  colonnes : `nature`, `ref`, `libelle`, `recu`, `redistribue`, `disponible`

**`mes_evenements(p_filtre text default 'a_venir')`** → `table (id uuid, reference text, titre text, objet text, natu` · sql · 47_evenements.sql
  
  colonnes : `id`, `reference`, `titre`, `objet`, `nature`, `ouverture`, `lieu`, `debut`, `fin`, `statut`, `territoire`, `partenaire`, `organisateur`, `jeton_public`, `capacite`, `inscrits`, `presents`, `mon_inscription`, `je_tiens`

**`mes_exercices()`** → `table (id uuid, annee integer, territoire text, territoire_i` · sql · 23_budget_rapport.sql
  
  colonnes : `id`, `annee`, `territoire`, `territoire_id`, `statut`, `debut`, `fin`, `arrete_le`, `produits`, `charges`, `resultat`

**`mes_interims()`** → `table (id uuid, poste text, poste_nom text, titulaire text, ` · sql · 21_interim_suppleance.sql
  
  colonnes : `id`, `poste`, `poste_nom`, `titulaire`, `interimaire`, `debut`, `fin`, `motif`, `statut`, `je_suis_interimaire`, `jours_restants`

**`mes_invitations_groupe()`** → `table (groupe_id uuid, titre text, objet text, responsable t` · sql · 29_correctifs.sql
  
  colonnes : `groupe_id`, `titre`, `objet`, `responsable`, `invite_par`, `territoire`

**`mes_organes()`** → `table (code text, nom text, description text, logo text, cou` · sql · 41_organes.sql
  
  colonnes : `code`, `nom`, `description`, `logo`, `couleur`, `signature`, `en_attente`

**`mes_postes()`** → `table (poste text, nom text, couleur text, territoire_nom te` · sql · 07_habilitations.sql
  
  colonnes : `poste`, `nom`, `couleur`, `territoire_nom`, `fin`

**`mes_rendez_vous()`** → `table (id uuid, debut timestamptz, duree_min integer, lieu t` · sql · 18_parcours_pilotage.sql
  
  colonnes : `id`, `debut`, `duree_min`, `lieu`, `visio`, `avec`, `avec_fonction`, `je_suis_hote`, `passe`

**`mes_taches()`** → `table( id uuid, titre text, description text, echeance date,` · sql · 51_taches_et_remontees.sql
  
  colonnes : `id`, `titre`, `description`, `echeance`, `statut`, `assigne_par_nom`, `delegue_de_nom`, `cree_le`

**`mes_virements_a_confirmer()`** → `table (note_id uuid, reference text, objet text, total numer` · sql · 21_interim_suppleance.sql
  
  colonnes : `note_id`, `reference`, `objet`, `total`, `payee_le`, `jours`, `mode`, `reference_paiement`, `attestation`, `recu_fiscal`

**`mes_voix(p_assemblee uuid)`** → `jsonb` · sql · 46_scrutin.sql

**`missions_ouvertes()`** → `table ( id uuid, titre text, description text, lieu text, de` · sql · 12_engagement.sql
  
  colonnes : `id`, `titre`, `description`, `lieu`, `debut`, `fin`, `heures_estimees`, `places`, `retenus`, `statut`, `territoire_nom`, `groupe_nom`, `certification_nom`, `porteur`, `obstacle`, `ma_candidature`

**`modifier_membre(p_profil uuid, p_champ text, p_valeur text)`** → `jsonb` · plpgsql · 34_gardes.sql

**`mon_adhesion()`** → `jsonb` · sql · 12_engagement.sql

**`mon_comite(p_territoire uuid default null)`** → `jsonb` · sql · 25_decouvrabilite.sql

**`mon_dossier()`** → `jsonb` · sql · 13_correctifs_progression.sql

**`mon_echelon()`** → `integer` · sql · 01_socle.sql

**`mon_engagement()`** → `jsonb` · sql · 36_notes_engagement.sql

**`mon_niveau()`** → `integer` · sql · 01_socle.sql

**`mon_perimetre()`** → `table( id uuid, nom text, prenom text, matricule text, fonct` · sql · 50_masquage_perimetre.sql
  
  colonnes : `id`, `nom`, `prenom`, `matricule`, `fonction_nom`, `territoire_nom`, `echelon`, `statut`, `niveau`

**`mon_plafond_nomination()`** → `integer` · sql · 31_nominations.sql

**`mon_poids()`** → `integer` · sql · 16_garde_chancellerie.sql

**`mon_recepisse(p_assemblee uuid)`** → `jsonb` · sql · 46_scrutin.sql

**`mon_rib()`** → `jsonb` · sql · 09_finances.sql

**`mon_role_parcours(p_profil uuid)`** → `text` · sql · 28_ressources.sql

**`mon_territoire()`** → `uuid` · sql · 01_socle.sql

**`montant_ligne(l nf_lignes)`** → `numeric` · sql · 06_notes_frais.sql

**`motif_fermeture_recours(m mesures)`** → `text` · sql · 10_discipline_consolidation.sql

**`motif_refus_action(p_profil uuid)`** → `text` · sql · 19_coherence_distinctions.sql

**`nomination_active(n nominations)`** → `boolean` · sql · 07_habilitations.sql

**`nommer(p_profil uuid, p_poste text, p_territoire uuid default null, p_fin date default null, p_motif text default null)`** → `jsonb` · plpgsql · 31_nominations.sql

**`normaliser_profil()`** → `trigger` · plpgsql · 19_coherence_distinctions.sql

**`normaliser_telephone(t text)`** → `text` · sql · 19_coherence_distinctions.sql

**`noter_parcours(p_profil uuid, p_champ text, p_notes text default null)`** → `jsonb` · plpgsql · 29_correctifs.sql

**`notifier_mesure(p_mesure uuid, p_courrier text default null)`** → `jsonb` · plpgsql · 13_correctifs_progression.sql

**`nouveaux_a_accueillir(p_territoire uuid default null)`** → `table (profil_id uuid, membre text, matricule text, email te` · sql · 18_parcours_pilotage.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `email`, `territoire`, `inscrit_le`, `jours`, `etape`, `prochaine_action`, `referent`, `rdv_le`, `notes`

**`nouveaux_a_accueillir_maj(p_territoire uuid default null)`** → `table (profil_id uuid, membre text, matricule text, email te` · plpgsql · 20_directions_parcours.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `email`, `telephone`, `territoire`, `inscrit_le`, `jours`, `etape`, `etape_rang`, `prochaine_action`, `referent`, `referent_id`, `rdv_le`, `notes`, `completude`, `manques`, `sans_nouvelles`

**`nouveaux_a_repartir()`** → `table (profil_id uuid, membre text, matricule text, email te` · sql · 28_ressources.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `email`, `telephone`, `territoire`, `territoire_id`, `inscrit_le`, `jours`, `etape`, `etape_rang`, `accompagnant`, `accompagnant_id`, `bureau_local`, `mon_role`, `priorite`, `alerte_ouverte`, `derniere_note`

**`observer_ligne(p_ligne uuid, p_etat text, p_observation text default null)`** → `jsonb` · plpgsql · 36_notes_engagement.sql

**`obstacle_groupe(p_groupe uuid)`** → `text` · plpgsql · 03_groupes.sql

**`obstacle_mission(p_mission uuid)`** → `text` · plpgsql · 12_engagement.sql

**`ordonnancer_investissement(p_id uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`ordonnancer_note(p_note uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 09_finances.sql

**`organigramme()`** → `table (direction text, direction_nom text, direction_ordre i` · sql · 42_engagement.sql
  
  colonnes : `direction`, `direction_nom`, `direction_ordre`, `poste`, `poste_nom`, `rang`, `titulaire`, `titulaire_id`, `territoire`, `depuis`, `engage_points`

**`ouvrir_dossier(p_profil uuid, p_objet text, p_qualification text default null, p_gravite text default 'moyenne', p_signalement uuid default null)`** → `jsonb` · plpgsql · 08_discipline.sql

**`ouvrir_exercice(p_annee integer, p_territoire uuid default null)`** → `jsonb` · plpgsql · 23_budget_rapport.sql

**`ouvrir_panier(p_territoire uuid default null, p_direction text default null)`** → `jsonb` · plpgsql · 38_ressources_budget.sql

**`ouvrir_paquet_poste()`** → `trigger` · plpgsql · 21_interim_suppleance.sql

**`ouvrir_parcours()`** → `trigger` · plpgsql · 18_parcours_pilotage.sql

**`ouvrir_ticket(p_nature text, p_titre text, p_description text, p_page text default null, p_importance text default 'normale', p_urgent boolean default false, p_contexte jsonb default null)`** → `jsonb` · plpgsql · 24_suggestions_assistance.sql

**`partager_contacts(p_contacts uuid[], p_territoire uuid default null, p_groupe uuid default null, p_portee text default 'fiche', p_motif text default null, p_expire date default null)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`participants_conversation(p_conv uuid)`** → `table (profil_id uuid, prenom text, nom text, matricule text` · sql · 04_messagerie.sql
  
  colonnes : `profil_id`, `prenom`, `nom`, `matricule`, `fonction_nom`, `territoire_nom`

**`participation(p_assemblee uuid)`** → `jsonb` · sql · 46_scrutin.sql

**`passeport(p_profil uuid default null)`** → `jsonb` · sql · 27_passeport_parcours.sql

**`payer_note(p_note uuid, p_reference text)`** → `jsonb` · plpgsql · 09_finances.sql

**`peut_superviser(p_conv uuid)`** → `boolean` · sql · 05_messagerie_correctifs.sql

**`pieces_depuis_mon_controle()`** → `integer` · sql · 33_messagerie.sql

**`pilotage_acces()`** → `table ( profil_id uuid, membre text, matricule text, fonctio` · sql · 07_habilitations.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `fonction_nom`, `territoire_nom`, `application`, `app_nom`, `origine`, `accorde_le`, `expire_le`, `derniere_utilisation`, `nb_ouvertures`, `statut`

**`places_restantes(p_evenement uuid, p_categorie text default null)`** → `integer` · sql · 47_evenements.sql

**`plan_engagement(p_points integer)`** → `jsonb` · plpgsql · 42_engagement.sql

**`plan_territoires()`** → `table (id uuid, parent_id uuid, echelle text, code text, nom` · sql · 40_enveloppes.sql
  
  colonnes : `id`, `parent_id`, `echelle`, `code`, `nom`, `etat`, `academie`, `profondeur`, `chemin`, `effectif`, `encadrants`, `president`, `tresorier`, `enfants`, `dotation`, `derniere_activite`

**`poids_membre(p_profil uuid)`** → `integer` · sql · 16_garde_chancellerie.sql

**`points_membre(p_profil uuid default null)`** → `jsonb` · sql · 19_coherence_distinctions.sql

**`poser_creneaux(p_creneaux jsonb, p_duree integer, p_lieu text, p_visio text, p_territoire uuid default null)`** → `jsonb` · plpgsql · 18_parcours_pilotage.sql

**`poste_sensible(p_poste text)`** → `boolean` · sql · 31_nominations.sql

**`poste_vacant(p_poste text, p_territoire uuid)`** → `boolean` · sql · 21_interim_suppleance.sql

**`postes_conferables(p_territoire uuid default null)`** → `table (code text, nom text, description text, rang integer, ` · sql · 31_nominations.sql
  
  colonnes : `code`, `nom`, `description`, `rang`, `couleur`, `sensible`

**`postes_non_conformes()`** → `table (profil_id uuid, membre text, poste text, poste_nom te` · sql · 21_interim_suppleance.sql
  
  colonnes : `profil_id`, `membre`, `poste`, `poste_nom`, `territoire`, `depuis`, `jours`, `manquantes`, `delai_depasse`

**`postuler_formation(p_formation uuid, p_motivation text)`** → `jsonb` · plpgsql · 27_passeport_parcours.sql

**`postuler_groupe(p_groupe uuid, p_motivation text)`** → `jsonb` · plpgsql · 35_equipes.sql

**`postuler_mission(p_mission uuid, p_message text default null)`** → `jsonb` · plpgsql · 12_engagement.sql

**`pouvoirs_assemblee(p_assemblee uuid)`** → `table (id uuid, mandant text, mandant_matricule text, mandan` · sql · 45_correctifs_ag.sql
  
  colonnes : `id`, `mandant`, `mandant_matricule`, `mandant_id`, `mandataire`, `mandataire_matricule`, `mandataire_id`, `statut`, `mandant_a_vote`, `cree_le`

**`prendre_acte(p_type text, p_objet text, p_visas text default null, p_considerants text default null, p_articles jsonb default '[]'::jsonb, p_destinataire uuid default null, p_poste text default null, p_effet date default null, p_territoire uuid default null)`** → `jsonb` · plpgsql · 39_gestion_locale.sql

**`proclamer(p_assemblee uuid, p_pv text, p_pv_fichier text default null)`** → `jsonb` · plpgsql · 46_scrutin.sql

**`profil_interne(p_profil uuid)`** → `jsonb` · sql · 33_messagerie.sql

**`projet_pv(p_assemblee uuid)`** → `jsonb` · sql · 46_scrutin.sql

**`projets_a_soutenir(p_filtre text default 'tous')`** → `table (id uuid, reference text, titre text, objet text, terr` · sql · 40_enveloppes.sql
  
  colonnes : `id`, `reference`, `titre`, `objet`, `territoire`, `statut`, `debut`, `budget_estime`, `responsable`, `points_recus`

**`promouvoir(p_profil uuid, p_echelon integer, p_motif text)`** → `jsonb` · plpgsql · 16_garde_chancellerie.sql

**`prononcer_mesure(p_dossier uuid, p_type text, p_motif text, p_texte text default null, p_effet date default null, p_fin date default null, p_fichier text default null)`** → `jsonb` · plpgsql · 13_correctifs_progression.sql

**`proposer(p_titre text, p_description text, p_besoin text default null, p_public text default null)`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`proposer_equipe(p_nom text, p_objet text, p_territoire uuid, p_membres uuid[] default '{}', p_applications text[] default '{}')`** → `jsonb` · plpgsql · 35_equipes.sql

**`propositions_remontees()`** → `table (id uuid, reference text, titre text, description text` · sql · 22_mon_comite.sql
  
  colonnes : `id`, `reference`, `titre`, `description`, `besoin`, `auteur`, `territoire`, `soutiens`, `remontee_le`, `remontee_par`, `motif_remontee`, `statut`

**`publications_a_relayer()`** → `integer` · sql · 25_decouvrabilite.sql

**`puis_je_agir_sur(p_profil uuid)`** → `boolean` · sql · 19_coherence_distinctions.sql

**`puis_je_ecrire_a(p_cible uuid)`** → `boolean` · plpgsql · 05_messagerie_correctifs.sql

**`puis_je_engager(p_nature text, p_ref text)`** → `boolean` · sql · 42_engagement.sql

**`puis_je_instruire(p_note uuid)`** → `boolean` · sql · 06_notes_frais.sql

**`puis_je_lire_journal_pieces()`** → `boolean` · sql · 33_messagerie.sql

**`puis_je_ouvrir_acces(p_app text, p_profil uuid)`** → `boolean` · sql · 39_gestion_locale.sql

**`puis_je_prendre_acte(p_territoire uuid default null)`** → `boolean` · sql · 39_gestion_locale.sql

**`puis_je_signer_acte()`** → `boolean` · sql · 39_gestion_locale.sql

**`puis_je_tenir_evenement(p_evenement uuid)`** → `boolean` · sql · 47_evenements.sql

**`purger_inscriptions_echues()`** → `jsonb` · plpgsql · 47_evenements.sql

**`qui_ma_consulte()`** → `table (observateur text, fonction text, contexte text, cree_` · sql · 11_lisibilite_droits.sql
  
  colonnes : `observateur`, `fonction`, `contexte`, `cree_le`

**`quitter_groupe(p_groupe uuid)`** → `jsonb` · plpgsql · 35_equipes.sql

**`rafraichir_jalons()`** → `integer` · plpgsql · 29_correctifs.sql

**`rattacher_territoire(p_territoire uuid, p_parent uuid)`** → `jsonb` · plpgsql · 39_gestion_locale.sql

**`realise_automatique(p_exercice uuid, p_poste text)`** → `numeric` · sql · 38_ressources_budget.sql

**`receptionner_investissement(p_id uuid, p_facture text default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`recours_deja_formes(p_mesure uuid)`** → `integer` · sql · 10_discipline_consolidation.sql

**`recours_ouvert(m mesures)`** → `boolean` · sql · 10_discipline_consolidation.sql

**`recueil_actes(p_filtre text default 'tous')`** → `table (id uuid, reference text, type text, objet text, statu` · sql · 39_gestion_locale.sql
  
  colonnes : `id`, `reference`, `type`, `objet`, `statut`, `portee`, `auteur`, `auteur_fonction`, `ressort`, `destinataire`, `poste_nom`, `prend_effet_le`, `signe_le`, `abroge`, `cree_le`

**`rediger_bilan(p_mission uuid, p_profil uuid, p_heures numeric, p_realise text, p_competences text[] default null, p_appreciation text default null, p_merite text default null)`** → `jsonb` · plpgsql · 27_passeport_parcours.sql

**`referentiel()`** → `jsonb` · sql · 11_lisibilite_droits.sql

**`refuser_si_scelle()`** → `trigger` · plpgsql · 10_discipline_consolidation.sql

**`regenerer_jeton_carte()`** → `jsonb` · plpgsql · 43_adherent.sql

**`registre_adhesions()`** → `table ( matricule text, prenom text, nom text, email text, t` · sql · 12_engagement.sql
  
  colonnes : `matricule`, `prenom`, `nom`, `email`, `telephone`, `fonction`, `echelon`, `territoire`, `statut`, `date_adhesion`, `date_naissance`, `adresse`, `code_postal`, `ville`, `situation`, `profession`, `competences`, `disponibilites`, `motivation`, `origine`, `accepte_image`, `inscrit_le`

**`registre_discipline()`** → `table ( reference text, ouvert_le timestamptz, clos_le times` · sql · 10_discipline_consolidation.sql
  
  colonnes : `reference`, `ouvert_le`, `clos_le`, `statut`, `gravite`, `origine`, `objet`, `qualification`, `conclusion`, `concerne`, `matricule`, `territoire`, `fonction`, `ouvert_par`, `mesure_type`, `mesure_motif`, `mesure_statut`, `mesure_effet`, `mesure_fin`, `notifiee_le`, `accusee_le`, `renonce_le`, `recours_statut`, `recours_le`, `recours_decision`, `nb_pieces`, `nb_pieces_non_communicables`

**`regler_application(p_code text, p_nom text, p_nom_court text, p_description text, p_accroche text, p_couleur text, p_logo text, p_direction text default null, p_direction_locale text default null, p_ordre integer default null)`** → `jsonb` · plpgsql · 30_menu.sql

**`regler_bareme(p_cle text, p_points integer)`** → `jsonb` · plpgsql · 16_garde_chancellerie.sql

**`regler_categorie(d jsonb)`** → `jsonb` · plpgsql · 47_evenements.sql

**`regler_dotation(p_cle text, p_valeur numeric)`** → `jsonb` · plpgsql · 28_ressources.sql

**`regler_echelon(p_niveau integer, p_nom text, p_points integer, p_ouvre text default null, p_description text default null)`** → `jsonb` · plpgsql · 39_gestion_locale.sql

**`regler_engagement(p_mois date, p_visees numeric, p_realisees numeric default null, p_commentaire text default null)`** → `jsonb` · plpgsql · 12_engagement.sql

**`regler_ligne(p_id uuid, p_champ text, p_valeur text)`** → `jsonb` · plpgsql · 23_budget_rapport.sql

**`regler_ligne_panier(p_ligne uuid, p_quantite integer)`** → `jsonb` · plpgsql · 29_correctifs.sql

**`regler_matrice(p_app text, p_fonction text, p_etat text)`** → `jsonb` · plpgsql · 11_lisibilite_droits.sql

**`regler_territoire(p_territoire uuid, d jsonb)`** → `jsonb` · plpgsql · 39_gestion_locale.sql

**`rejoindre_groupe(p_groupe uuid)`** → `jsonb` · plpgsql · 35_equipes.sql

**`rejoindre_projet(p_projet uuid, p_role text default 'participant')`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`relancer_virements()`** → `integer` · sql · 21_interim_suppleance.sql

**`remontees_du_cabinet(p_filtre text default 'ouvertes')`** → `table (id uuid, nature text, objet text, corps text, lien te` · sql · 32_cabinet.sql
  
  colonnes : `id`, `nature`, `objet`, `corps`, `lien`, `statut`, `auteur`, `auteur_fonction`, `territoire`, `reponse`, `traite_par`, `cree_le`

**`renoncer_gracieux(p_dossier uuid, p_texte text)`** → `jsonb` · plpgsql · 10_discipline_consolidation.sql

**`repondre_alerte_parcours(p_id uuid, p_reponse text)`** → `jsonb` · plpgsql · 28_ressources.sql

**`repondre_interim(p_id uuid, p_accepte boolean)`** → `jsonb` · plpgsql · 21_interim_suppleance.sql

**`repondre_invitation(p_groupe uuid, p_accepte boolean)`** → `jsonb` · plpgsql · 35_equipes.sql

**`repondre_ticket(p_id uuid, p_contenu text)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`reserver_creneau(p_creneau uuid)`** → `jsonb` · plpgsql · 18_parcours_pilotage.sql

**`retenir_candidature(p_id uuid, p_retenue boolean, p_reponse text default null)`** → `jsonb` · plpgsql · 35_equipes.sql

**`retirer_commande(p_id uuid, p_motif text default null)`** → `jsonb` · plpgsql · 42_engagement.sql

**`retirer_distinction(p_id uuid, p_motif text)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`retirer_message(p_id uuid)`** → `jsonb` · plpgsql · 34_gardes.sql

**`retirer_partage(p_id uuid, p_motif text)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`revoquer(p_nomination uuid, p_motif text)`** → `jsonb` · plpgsql · 31_nominations.sql

**`revoquer_acces(p_profil uuid, p_app text, p_motif text)`** → `jsonb` · plpgsql · 31_nominations.sql

**`router_ticket_destinataire()`** → `trigger` · plpgsql · 49_routage_assistance.sql

**`scelle_sur_dossier()`** → `trigger` · plpgsql · 21_interim_suppleance.sql

**`scelle_sur_recours()`** → `trigger` · plpgsql · 21_interim_suppleance.sql

**`scrutins_a_arreter()`** → `table (assemblee_id uuid, reference text, titre text, territ` · sql · 19_coherence_distinctions.sql
  
  colonnes : `assemblee_id`, `reference`, `titre`, `territoire`, `statut`, `date_tenue`, `cloture_scrutin`, `candidatures_a_examiner`, `recevables`, `votants`, `inscrits`, `action`

**`sert_organe(p_organe text)`** → `boolean` · sql · 41_organes.sql

**`signalements_a_traiter()`** → `table ( id uuid, conversation_id uuid, motif text, details t` · sql · 05_messagerie_correctifs.sql
  
  colonnes : `id`, `conversation_id`, `motif`, `details`, `statut`, `cree_le`, `auteur_nom`, `auteur_matricule`, `assigne_a`, `assigne_nom`, `participants`, `nb_messages`

**`signaler_a_accompagnant(p_profil uuid, p_message text, p_nature text default 'observation')`** → `jsonb` · plpgsql · 28_ressources.sql

**`signaler_conversation(p_conv uuid, p_motif text, p_details text, p_message uuid default null)`** → `jsonb` · plpgsql · 05_messagerie_correctifs.sql

**`signer_acte(p_id uuid)`** → `jsonb` · plpgsql · 41_organes.sql

**`signer_depouillement(p_assemblee uuid, p_role text default null)`** → `jsonb` · plpgsql · 45_correctifs_ag.sql

**`slugifier(t text)`** → `text` · sql · 14_migration.sql

**`solde_enveloppe(p_nature text, p_ref text, p_annee integer default null)`** → `jsonb` · sql · 40_enveloppes.sql

**`solde_points(p_territoire uuid default null)`** → `jsonb` · sql · 42_engagement.sql

**`sollicitations_ap_a_traiter(p_filtre text default 'ouvertes')`** → `table (id uuid, objet text, besoin text, echeance date, stat` · sql · 37_affaires_publiques.sql
  
  colonnes : `id`, `objet`, `besoin`, `echeance`, `statut`, `demandeur`, `fonction`, `territoire`, `groupe`, `reponse`, `cree_le`

**`solliciter_ap(p_objet text, p_besoin text, p_groupe uuid default null, p_echeance date default null)`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`soumettre_publication(p_id uuid)`** → `jsonb` · plpgsql · 14_migration.sql

**`source_acces(p_app text, p_profil uuid default null)`** → `text` · sql · 19_coherence_distinctions.sql

**`soutenir(p_proposition uuid)`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`soutiens_projet(p_projet uuid)`** → `table (points integer, motif text, origine text, accorde_par` · sql · 40_enveloppes.sql
  
  colonnes : `points`, `motif`, `origine`, `accorde_par`, `cree_le`

**`statuer_candidature(p_cand uuid, p_statut text, p_motif text default null)`** → `jsonb` · plpgsql · 12_engagement.sql

**`statuer_proposition(p_id uuid, p_statut text, p_reponse text, p_creer_projet boolean default false)`** → `jsonb` · plpgsql · 22_mon_comite.sql

**`statuer_publication(p_id uuid, p_issue text, p_observation text default null)`** → `jsonb` · plpgsql · 14_migration.sql

**`statuer_recours(p_recours uuid, p_issue text, p_decision text, p_suspensif boolean default false, p_fichier text default null)`** → `jsonb` · plpgsql · 13_correctifs_progression.sql

**`structures_en_alerte()`** → `table (territoire_id uuid, territoire text, echelle text, pa` · sql · 17_vie_statutaire.sql
  
  colonnes : `territoire_id`, `territoire`, `echelle`, `parent`, `etat`, `membres`, `alerte`, `depuis`

**`suggestions_disponibles()`** → `table (id uuid, reference text, titre text, contexte text, t` · sql · 24_suggestions_assistance.sql
  
  colonnes : `id`, `reference`, `titre`, `contexte`, `texte`, `canaux`, `visuel`, `lien_canva`, `hashtags`, `a_publier_le`, `expire_le`, `consignes`, `priorite`, `campagne`, `territoire`, `auteur`, `reprises`, `je_lai_reprise`, `cree_le`

**`suis_je_electeur(p_assemblee uuid)`** → `boolean` · sql · 17_vie_statutaire.sql

**`suivi_en_cours()`** → `table ( profil_id uuid, membre text, matricule text, territo` · sql · 13_correctifs_progression.sql
  
  colonnes : `profil_id`, `membre`, `matricule`, `territoire_nom`, `mesure_id`, `motif`, `date_effet`, `date_fin`, `dossier_reference`, `instructeur`, `alertes_non_vues`, `alertes_total`, `derniere_activite`, `applications`

**`suivi_formation(p_formation uuid)`** → `table (profil_id uuid, membre text, territoire text, lecons_` · sql · 26_editeur_formations.sql
  
  colonnes : `profil_id`, `membre`, `territoire`, `lecons_faites`, `total`, `pourcent`, `derniere_activite`, `certifie`

**`suivi_note(p_note uuid)`** → `table (rang integer, etape text, etat text, quand timestampt` · sql · 36_notes_engagement.sql
  
  colonnes : `rang`, `etape`, `etat`, `quand`, `par`, `detail`

**`suivi_suggestions()`** → `table (id uuid, reference text, titre text, priorite text, s` · sql · 24_suggestions_assistance.sql
  
  colonnes : `id`, `reference`, `titre`, `priorite`, `statut`, `a_publier_le`, `reprises`, `territoires`, `canaux_utilises`, `cree_le`

**`supprimer_element(p_table text, p_id uuid)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`supprimer_formation(p_id uuid)`** → `jsonb` · plpgsql · 26_editeur_formations.sql

**`tableau_ap()`** → `jsonb` · sql · 37_affaires_publiques.sql

**`tableau_cabinet()`** → `jsonb` · sql · 32_cabinet.sql

**`tableau_evenement(p_evenement uuid)`** → `jsonb` · sql · 47_evenements.sql

**`tableau_ordonnancement()`** → `jsonb` · sql · 38_ressources_budget.sql

**`taches_que_jai_confiees()`** → `table( id uuid, titre text, description text, echeance date,` · sql · 51_taches_et_remontees.sql
  
  colonnes : `id`, `titre`, `description`, `echeance`, `statut`, `assigne_a_nom`, `cree_le`

**`telephone_valide(t text)`** → `boolean` · sql · 19_coherence_distinctions.sql

**`terminer_lecon(p_lecon uuid)`** → `jsonb` · plpgsql · 02_formations.sql

**`terminer_tache(p_tache uuid)`** → `jsonb` · plpgsql · 51_taches_et_remontees.sql

**`territoires_sous(racine uuid)`** → `table (id uuid)` · sql · 01_socle.sql
  
  colonnes : `id`

**`texte_acte(p_id uuid)`** → `jsonb` · sql · 32_cabinet.sql

**`tickets_urgents()`** → `integer` · sql · 24_suggestions_assistance.sql

**`total_ecarte(p_note uuid)`** → `numeric` · sql · 36_notes_engagement.sql

**`total_note(p_note uuid)`** → `numeric` · sql · 36_notes_engagement.sql

**`tracer_acces(p_app text)`** → `void` · sql · 07_habilitations.sql

**`tracer_export(p_objet text, p_lignes integer)`** → `void` · sql · 10_discipline_consolidation.sql

**`tracer_suivi()`** → `trigger` · plpgsql · 08_discipline.sql

**`traiter_commande(p_id uuid, p_statut text, p_motif text default null, p_transporteur text default null, p_suivi text default null)`** → `jsonb` · plpgsql · 28_ressources.sql

**`traiter_remontee(p_id uuid, p_statut text, p_reponse text default null)`** → `jsonb` · plpgsql · 32_cabinet.sql

**`traiter_sollicitation(p_id uuid, p_statut text, p_reponse text, p_contacts uuid[] default '{}')`** → `jsonb` · plpgsql · 37_affaires_publiques.sql

**`traiter_ticket(p_id uuid, p_statut text, p_assigne uuid default null, p_echeance date default null, p_importance text default null, p_reponse text default null)`** → `jsonb` · plpgsql · 19_coherence_distinctions.sql

**`tunnel_benevole(p_territoire uuid default null, p_mois integer default 6)`** → `jsonb` · sql · 18_parcours_pilotage.sql

**`unaccent_simple(t text)`** → `text` · sql · 14_migration.sql

**`url_piece(p_piece uuid)`** → `text` · sql · 10_discipline_consolidation.sql

**`uuid_valide(p_texte text)`** → `uuid` · sql · 34_gardes.sql

**`v_contacts(p_filtre text default 'tous')`** → `table (id uuid, nom text, sigle text, type text, statut text` · sql · 37_affaires_publiques.sql
  
  colonnes : `id`, `nom`, `sigle`, `type`, `statut`, `echelle`, `territoire`, `objet`, `interet`, `site`, `reserve`, `interlocuteurs`, `dernier_echange`, `partages`, `maj_le`

**`v_notes(p_filtre text default 'miennes')`** → `table ( id uuid, reference text, objet text, statut text, to` · sql · 36_notes_engagement.sql
  
  colonnes : `id`, `reference`, `objet`, `statut`, `total`, `ecarte`, `nb_lignes`, `cree_le`, `deposee_le`, `profil_id`, `deposant`, `matricule`, `territoire_nom`, `groupe_nom`, `avis`, `motif_refus`, `reference_paiement`, `instruit_nom`, `valide_nom`, `demande_precisions`

**`valider_engagement(p_id uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 42_engagement.sql

**`valider_equipe(p_groupe uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 35_equipes.sql

**`valider_inscription(p_id uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 47_evenements.sql

**`valider_note(p_note uuid, p_ok boolean, p_motif text default null)`** → `jsonb` · plpgsql · 06_notes_frais.sql

**`valider_quiz(p_lecon uuid, p_choix uuid[])`** → `jsonb` · plpgsql · 02_formations.sql

**`verifier_changement_profil()`** → `trigger` · plpgsql · 01_socle.sql

**`verifier_formation(p_formation uuid)`** → `jsonb` · sql · 26_editeur_formations.sql

**`verifier_recepisse(p_assemblee uuid, p_empreinte text)`** → `jsonb` · sql · 46_scrutin.sql

**`verser_piece(p_dossier uuid, p_type text, p_titre text, p_contenu text default null, p_fichier text default null, p_communicable boolean default true)`** → `jsonb` · plpgsql · 08_discipline.sql

**`virements_a_suivre()`** → `table (note_id uuid, reference text, objet text, deposant te` · sql · 21_interim_suppleance.sql
  
  colonnes : `note_id`, `reference`, `objet`, `deposant`, `deposant_id`, `total`, `payee_le`, `jours`, `etat`, `motif_contestation`, `mode`, `attestation`

**`vitrine_blocs(p_page text)`** → `table (id uuid, type text, titre text, contenu text, image t` · sql · 14_migration.sql
  
  colonnes : `id`, `type`, `titre`, `contenu`, `image`, `lien`, `lien_texte`, `ordre`

**`voter(p_assemblee uuid, p_choix jsonb)`** → `jsonb` · plpgsql · 46_scrutin.sql

---

## Droits atomiques

- `acces.piloter` — Ouvrir et révoquer les accès applicatifs *(Pilotage, sensible)*
- `actes.local` — Prendre des actes au nom de sa structure *(Présidence)*
- `actes.prendre` — Signer les actes de la présidence *(Présidence, sensible)*
- `actes.recueil` — Administrer le recueil des actes *(Présidence)*
- `ap.partager` — Partager des contacts avec le réseau *(Affaires publiques)*
- `ap.personnes` — Accéder aux interlocuteurs nommément *(Affaires publiques, sensible)*
- `ap.tenir` — Tenir le fichier des relations extérieures *(Affaires publiques)*
- `budget.tenir` — Tenir le budget et les comptes *(Finances)*
- `cabinet.arbitrer` — Instruire les remontées au cabinet *(Présidence)*
- `chancellerie.bareme` — Fixer le barème des points *(Valorisation)*
- `chancellerie.promouvoir` — Proposer et arrêter les promotions *(Valorisation, sensible)*
- `com.publier` — Publier sur le site et les réseaux *(Communication, sensible)*
- `com.rediger` — Rédiger des publications *(Communication)*
- `com.valider` — Valider une publication *(Communication)*
- `discipline.decider` — Prononcer une mesure *(Discipline, sensible)*
- `discipline.exporter` — Extraire le registre disciplinaire *(Discipline, sensible)*
- `discipline.instruire` — Instruire un dossier disciplinaire *(Discipline, sensible)*
- `discipline.recours` — Statuer sur un recours gracieux *(Discipline, sensible)*
- `discipline.saisir` — Ouvrir un dossier disciplinaire *(Discipline)*
- `donnees.protegees` — Consulter un dossier protégé *(Données, sensible)*
- `election.archives` — Consulter toutes les archives électorales *(Structures)*
- `election.conformite` — Statuer sur la recevabilité des candidatures *(Structures, sensible)*
- `evenements.controler` — Contrôler les entrées à un événement *(Événements)*
- `evenements.inscrits` — Accéder à la liste nominative des inscrits *(Événements, sensible)*
- `evenements.tenir` — Créer et tenir des événements *(Événements)*
- `finance.bareme` — Fixer le barème et les plafonds *(Finances)*
- `finance.instruire` — Instruire une note de frais *(Finances)*
- `finance.ordonnancer` — Ordonnancer une dépense *(Finances, sensible)*
- `finance.payer` — Mettre en paiement *(Finances, sensible)*
- `formations.editer` — Créer et modifier les formations *(Contenus)*
- `habilitations.gerer` — Créer des postes et nommer *(Pilotage, sensible)*
- `habilitations.local` — Nommer et ouvrir des accès dans sa structure *(Pilotage)*
- `invest.demander` — Demander un investissement *(Ressources)*
- `membres.exporter` — Extraire le registre des adhésions *(Membres, sensible)*
- `membres.nommer` — Nommer, muter, faire progresser *(Membres, sensible)*
- `membres.suspendre` — Suspendre ou réintégrer un compte *(Membres, sensible)*
- `membres.valider` — Valider une inscription *(Membres)*
- `messagerie.superviser` — Superviser les échanges de son périmètre *(Échanges, sensible)*
- `parcours.accueillir` — Accueillir et accompagner les nouveaux adhérents *(Membres)*
- `rgpd.alertes` — Recevoir les alertes de consultation *(Données)*
- `rgpd.registre` — Tenir le registre des traitements *(Données)*
- `scrutin.organiser` — Organiser une assemblée et un scrutin *(Structures)*
- `scrutin.proclamer` — Proclamer les résultats *(Structures, sensible)*
- `stock.dotation` — Fixer les dotations en points *(Ressources, sensible)*
- `stock.national` — Piloter les stocks et le catalogue *(Ressources)*
- `structure.animer` — Animer une structure territoriale *(Structures)*
- `structure.arreter` — Mettre en sommeil ou dissoudre *(Structures, sensible)*
- `structure.creer` — Créer une structure *(Structures)*
- `vitrine.editer` — Modifier le site public *(Contenus)*

---

## Applications

- `affaires_publiques` — Affaires publiques
- `assemblees` — Vie statutaire
- `budget` — Budget et comptes
- `cabinet` — Cabinet de la présidence
- `chancellerie` — Chancellerie et valorisation
- `comite` — Mon comité
- `communication` — Communication
- `discipline` — Discipline et recours
- `engagement` — Mon engagement
- `evenements` — Événements
- `gestion_locale` — Gestion de la structure
- `ordonnancement` — Ordonnancement
- `parcours` — Parcours adhérent
- `pilotage` — Pilotage du réseau
- `publier` — Publier localement
- `recueil` — Recueil des actes
- `ressources` — Ressources et matériel
