-- =====================================================================
--  FFCE — Migration 29 — CE QUI BLOQUAIT
--
--  Toutes ces corrections viennent de l'usage réel. La première n'était
--  visible nulle part et expliquait plusieurs pannes à la fois.
--
--  PostgreSQL exécute toute fonction déclarée `stable` ou `immutable`
--  dans un contexte en lecture seule, et cette contrainte se propage à
--  tout ce que la fonction appelle. Trois fonctions du projet écrivent
--  alors qu'elles sont déclarées `stable` : elles lèvent une erreur à
--  chaque appel. L'utilisateur ne voit qu'un écran vide.
--
--    consulter_profil          journalise la consultation → alerte RGPD
--    fiche_membre              idem
--    nouveaux_a_accueillir_maj jalonne le parcours avant de le lire
--
--  D'où : la constatation des dossiers qui ne se fait pas, et les
--  alertes de consultation qui ne partent jamais.
--
--  Prérequis : 01 à 28.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. VOLATILITÉ
--    Les corps sont justes ; seule la déclaration était fausse. On ne
--    réécrit rien, on corrige l'étiquette.
-- ---------------------------------------------------------------------

alter function consulter_profil(uuid, text) volatile;
alter function fiche_membre(uuid, boolean) volatile;
alter function nouveaux_a_accueillir_maj(uuid) volatile;

-- ---------------------------------------------------------------------
-- 2. LE JALONNAGE, SÉPARÉ DE LA LECTURE
--    `nouveaux_a_repartir()` doit rester en lecture seule : la file de
--    travail du tableau de bord l'interroge, et elle-même est `stable`.
--    Le rafraîchissement devient donc une opération distincte, que
--    l'écran du parcours déclenche avant de lire.
-- ---------------------------------------------------------------------

create or replace function rafraichir_jalons()
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer := 0; r record;
begin
  for r in
    select pa.profil_id from parcours pa
    join profils p on p.id = pa.profil_id
    where pa.premiere_mission_le is null and pa.abandonne_le is null
      and p.statut <> 'archive'
      and mon_role_parcours(pa.profil_id) is not null
  loop
    perform jalonner_parcours(r.profil_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- 3. QUI ACCOMPAGNE PEUT AGIR
--    La migration 28 a créé trois rôles sur le parcours — responsable,
--    à affecter, suivi — mais `noter_parcours` est restée fermée au
--    seul droit national. Un président de structure voyait la liste
--    sans pouvoir la renseigner. La règle devient la même des deux
--    côtés : qui a un rôle sur le dossier peut le tenir à jour.
-- ---------------------------------------------------------------------

create or replace function noter_parcours(p_profil uuid, p_champ text,
                                          p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('parcours.accueillir') or est_admin()
          or mon_role_parcours(p_profil) in ('responsable','a_affecter','suivi')) then
    return jsonb_build_object('ok', false,
      'message', 'Vous n''accompagnez pas ce nouvel adhérent.');
  end if;

  if p_champ = 'contacte' then
    update parcours set contacte_le = now(), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'referent' then
    update parcours set referent_id = auth.uid(), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'notes' then
    update parcours set notes = nullif(trim(p_notes),''), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'abandon' then
    if coalesce(trim(p_notes),'') = '' then
      return jsonb_build_object('ok', false, 'message', 'Indiquez pourquoi le parcours s''arrête.');
    end if;
    update parcours set abandonne_le = now(), motif_abandon = trim(p_notes), maj_le = now()
     where profil_id = p_profil;
  elsif p_champ = 'reprise' then
    update parcours set abandonne_le = null, motif_abandon = null, maj_le = now()
     where profil_id = p_profil;
  else
    return jsonb_build_object('ok', false, 'message', 'Champ inconnu.');
  end if;

  perform jalonner_parcours(p_profil);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. MES DROITS, ÉNONCÉS
--    L'interface devinait quels volets afficher à partir de la fonction
--    et des postes. Or `v_annuaire` ne porte pas les droits : la
--    devinette était toujours fausse, et l'écran des habilitations
--    n'était ouvert qu'à l'administrateur, alors que le droit existe.
--    La base énonce désormais la liste. L'affichage cesse de diverger.
-- ---------------------------------------------------------------------

drop function if exists mes_droits();
create or replace function mes_droits()
returns table (code text, nom text, categorie text, sensible boolean, source text)
language sql stable security definer set search_path = public as $$
  select d.code, d.nom, d.categorie, d.sensible,
         case when est_admin() then 'administration'
              when exists (select 1 from nominations n
                           join poste_droits pd on pd.poste = n.poste
                           join postes po on po.code = n.poste
                           where n.profil_id = auth.uid() and pd.droit = d.code
                             and po.actif and nomination_active(n)) then 'poste'
              else 'interim' end
  from droits d
  where a_droit(d.code)
  order by d.categorie, d.ordre;
$$;

-- ---------------------------------------------------------------------
-- 5. LE PANIER SE CORRIGE
--    La migration 28 sait ajouter au panier, jamais en retirer. Et
--    `commandes.points_debites` n'est pas accordé en écriture aux
--    membres — c'est la bonne décision : un total débité ne se retouche
--    pas depuis un navigateur. Il manquait la fonction symétrique.
--    Zéro vaut suppression. Le total se recalcule ici, jamais ailleurs.
-- ---------------------------------------------------------------------

create or replace function regler_ligne_panier(p_ligne uuid, p_quantite integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cmd uuid; v_art uuid; v_cout integer;
begin
  select cl.commande_id, cl.article_id into v_cmd, v_art
    from commande_lignes cl
    join commandes c on c.id = cl.commande_id
   where cl.id = p_ligne
     and c.demandeur_id = auth.uid()
     and c.statut = 'brouillon';

  if v_cmd is null then
    return jsonb_build_object('ok', false,
      'message', 'Cette ligne ne fait pas partie de votre panier.');
  end if;

  if coalesce(p_quantite, 0) <= 0 then
    delete from commande_lignes where id = p_ligne;
  else
    select cout_points into v_cout from articles_catalogue where id = v_art;
    update commande_lignes
       set quantite = p_quantite, points = p_quantite * coalesce(v_cout, 0)
     where id = p_ligne;
  end if;

  update commandes set points_debites = (
    select coalesce(sum(points), 0) from commande_lignes where commande_id = v_cmd)
   where id = v_cmd;

  return jsonb_build_object('ok', true);
end $$;

-- L'application Ressources n'exigeait aucun droit : les postes de la
-- logistique ne l'ouvraient donc pas, seule la fonction y donnait accès.
update applications set droit_requis = 'stock.tenir' where code = 'ressources';

-- ---------------------------------------------------------------------
-- 6. RÉPONDRE SANS AVOIR L'ACCÈS
--    Un intérim proposé à quelqu'un qui n'a pas Habilitations ne
--    pouvait pas être accepté : la file de travail renvoyait vers une
--    application fermée. Même chose pour les invitations en groupe de
--    travail. Ce qu'on me demande à moi se répond depuis un écran
--    personnel, jamais depuis l'application concernée.
-- ---------------------------------------------------------------------

drop function if exists mes_invitations_groupe();
create or replace function mes_invitations_groupe()
returns table (groupe_id uuid, titre text, objet text, responsable text,
               invite_par text, territoire text)
language sql stable security definer set search_path = public as $$
  select g.id, g.nom, g.objet,
         -- Le groupe n'a pas de colonne « responsable » : c'est un rôle
         -- tenu par l'un de ses membres.
         (select trim(r.prenom || ' ' || r.nom)
            from gt_membres rm join profils r on r.id = rm.profil_id
           where rm.groupe_id = g.id and rm.role = 'responsable'
             and rm.statut = 'actif' limit 1),
         trim(i.prenom || ' ' || i.nom), t.nom
  from gt_membres m
  join groupes_travail g on g.id = m.groupe_id
  left join profils i on i.id = m.invite_par
  left join territoires t on t.id = g.territoire_id
  where m.profil_id = auth.uid() and m.statut = 'invite'
    and g.statut = 'actif'
  order by g.nom;
$$;

-- ---------------------------------------------------------------------
-- 7. LA FILE DE TRAVAIL
--    Reprise de la version en vigueur (migration 27), avec trois
--    changements : les sollicitations personnelles renvoient vers
--    l'écran personnel, et les ressources y font enfin apparaître leur
--    travail en attente. Aucune ligne ne doit appeler une fonction
--    volatile : cette fonction est `stable`.
-- ---------------------------------------------------------------------

create or replace function ce_qui_attend()
returns table (code text, libelle text, nombre integer, lien text, urgence text)
language sql stable security definer set search_path = public as $$
  select * from (
    values
    ('inscriptions', 'inscription(s) à vérifier',
      (select count(*)::int from profils where statut = 'en_attente'
        and (est_admin() or a_droit('membres.valider'))),
      '#/espace/validation', 'normale'),
    ('sans_bureau', 'adhérent(s) sans bureau local ni accompagnant',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 1),
      '#/espace/parcours', 'haute'),
    ('sans_accompagnant', 'adhérent(s) sans accompagnant',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 2),
      '#/espace/parcours', 'haute'),
    ('alertes_parcours', 'observation(s) sur un accompagnement',
      (select count(*)::int from mes_alertes_parcours() where traite_le is null),
      '#/espace/parcours', 'normale'),
    ('bilans', 'bilan(s) de mission à rédiger',
      (select count(*)::int from bilans_a_rediger()),
      '#/espace/parcours', 'haute'),
    ('cand_formation', 'candidature(s) à une formation à arbitrer',
      (select count(*)::int from candidatures_formation_a_arbitrer() where mon_ressort),
      '#/espace/formations', 'normale'),
    ('demandes', 'demande(s) d''accès en attente',
      (select count(*)::int from demandes where statut in ('ouverte','en_cours')
        and est_admin()),
      '#/espace/validation', 'normale'),
    ('signalements', 'signalement(s) à examiner',
      (select count(*)::int from signalements s where s.statut in ('ouvert','en_cours')
        and (est_admin() or s.assigne_a = auth.uid())),
      '#/espace/validation', 'haute'),
    ('alertes_rgpd', 'consultation(s) de dossier protégé',
      (select count(*)::int from consultations
        where alerte and vue_le is null and (est_admin() or a_droit('rgpd.alertes'))),
      '#/espace/validation', 'haute'),
    ('alertes_suivi', 'alerte(s) de suivi des usages',
      (select count(*)::int from alertes_suivi
        where vue_le is null and (est_admin() or a_droit('discipline.instruire'))),
      '#/espace/discipline', 'haute'),
    ('recours', 'recours à trancher',
      (select count(*)::int from recours r where r.statut in ('depose','recevable')
        and a_droit('discipline.recours')),
      '#/espace/discipline', 'haute'),
    ('candidatures', 'candidature(s) électorale(s) à examiner',
      (select count(*)::int from conformite_a_traiter()),
      '#/espace/conformite', 'haute'),
    ('actes', 'acte(s) sensible(s) à contrôler',
      (select count(*)::int from actes_sensibles where statut = 'a_controler'
        and est_admin()),
      '#/espace/validation', 'haute'),
    ('publications', 'publication(s) à relayer sur vos réseaux',
      publications_a_relayer(), '#/espace/publier', 'normale'),
    ('notes_avis', 'note(s) de frais en attente de votre avis',
      (select count(*)::int from notes_frais n where n.statut = 'deposee'
        and puis_je_instruire(n.id)),
      '#/espace/tresorerie', 'normale'),
    ('notes_instruire', 'note(s) de frais à instruire',
      (select count(*)::int from notes_frais where statut = 'deposee'
        and a_droit('finance.instruire')),
      '#/espace/tresorerie', 'normale'),
    ('notes_ordonnancer', 'dépense(s) à ordonnancer',
      (select count(*)::int from notes_frais where statut = 'instruite'
        and est_ordonnateur()),
      '#/espace/ordonnancement', 'normale'),
    ('notes_payer', 'paiement(s) à exécuter',
      (select count(*)::int from notes_frais where statut = 'ordonnancee'
        and a_droit('finance.payer')),
      '#/espace/tresorerie', 'normale'),
    ('virements', 'paiement(s) sans accusé depuis 15 jours',
      (select count(*)::int from virements_a_suivre()
        where etat in ('conteste','sans_reponse')),
      '#/espace/tresorerie', 'haute'),
    ('propositions', 'proposition(s) d''adhérent sans réponse',
      (select count(*)::int from propositions pr
        where pr.statut = 'deposee' and (est_admin() or mon_niveau() >= 50)
          and dans_mon_perimetre(pr.territoire_id)),
      '#/espace/comite', 'normale'),
    ('commandes_stock', 'commande(s) de matériel à traiter',
      (select count(*)::int from commandes
        where statut in ('deposee','validee') and a_droit('stock.national')),
      '#/espace/ressources', 'normale'),
    ('invest_instruire', 'demande(s) d''investissement à instruire',
      (select count(*)::int from investissements_a_traiter('a_instruire')),
      '#/espace/ressources', 'normale'),
    ('invest_ordonnancer', 'investissement(s) à ordonnancer',
      (select count(*)::int from investissements_a_traiter('a_ordonnancer')),
      '#/espace/ressources', 'normale'),
    ('taches', 'tâche(s) qui vous sont assignées',
      (select count(*)::int from gt_taches
        where assigne_a = auth.uid() and statut in ('a_faire','en_cours')),
      '#/espace/groupes', 'normale'),
    ('invitations', 'invitation(s) à un groupe de travail',
      (select count(*)::int from mes_invitations_groupe()),
      '#/espace/mandats', 'normale'),
    ('scrutins', 'scrutin(s) où vous n''avez pas voté',
      (select count(*)::int from mes_assemblees()
        where statut = 'scrutin' and electeur and not a_vote),
      '#/espace/assemblees', 'haute'),
    ('interims', 'intérim(s) qui vous sont proposés',
      (select count(*)::int from mes_interims()
        where statut = 'propose' and je_suis_interimaire),
      '#/espace/mandats', 'haute'),
    ('messages', 'conversation(s) non lue(s)',
      (select count(*)::int from mes_conversations() c where c.non_lus > 0),
      '#/espace/messagerie', 'normale')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

-- ---------------------------------------------------------------------
-- 8. DROITS D'EXÉCUTION
-- ---------------------------------------------------------------------

grant execute on function mes_droits(), mes_invitations_groupe(),
                          regler_ligne_panier(uuid, integer),
                          rafraichir_jalons(), ce_qui_attend(),
                          noter_parcours(uuid, text, text)
  to authenticated;

-- La vitrine publique lit les profils qui ont coché la case. La
-- politique de lecture existe depuis le socle ; les tables jointes par
-- `v_annuaire` n'étaient pas explicitement ouvertes à l'anonyme.
grant select on territoires, fonctions, echelons to anon, authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 29
--
--  Vérifications :
--    select provolatile from pg_proc where proname = 'consulter_profil';  -- 'v'
--    select * from mes_droits();
--    select rafraichir_jalons();
--    select code, nombre, lien from ce_qui_attend();
--
--  Neuvième famille d'erreur, à ajouter aux contrôles de livraison :
--  une fonction qui écrit ne peut pas être déclarée `stable`, et une
--  fonction `stable` ne peut appeler aucune fonction qui écrit. Le
--  contrôle doit être transitif : c'est la chaîne d'appel entière qui
--  hérite du contexte en lecture seule.
-- =====================================================================
