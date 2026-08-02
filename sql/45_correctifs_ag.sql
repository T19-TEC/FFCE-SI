-- =====================================================================
--  FFCE — Migration 45 — REPRISE DE LA MIGRATION 44, ET LE BLOC PRÉSIDENCE
--
--  La migration 44 a été écrite sans le schéma sous les yeux. Elle
--  s'est exécutée sans erreur — PostgreSQL ne résout pas le corps d'une
--  fonction PL/pgSQL au moment du CREATE — mais quatre de ses cinq
--  fonctions échouent ou ouvrent une brèche à l'usage. Aucune table
--  n'est à supprimer : `pouvoirs_ag` et `cles_depouillement` sont de
--  bonnes idées, correctement modélisées. Ce sont les fonctions qu'il
--  faut reprendre.
--
--  Ce qui ne marchait pas :
--
--    · `scanner_emargement_qr` lit une table `jetons_carte` qui n'existe
--      pas — le jeton est une colonne de `profils` (migration 43) — et
--      écrit dans une colonne `mode_presence` qui n'existe pas non plus.
--      Elle échoue à chaque appel. Elle faisait de surcroît doublon avec
--      `emarger_par_carte`, déjà livrée.
--
--    · `mes_pouvoirs_ag` est `security definer` sans aucun contrôle
--      d'accès : n'importe quel membre pouvait lister qui avait donné
--      pouvoir à qui, pour n'importe quelle assemblée. C'est la brèche
--      la plus sérieuse des cinq.
--
--    · `signer_cles_depouillement` n'exige aucune habilitation, et rien
--      ne l'exige en retour : deux clés pouvaient être signées par
--      n'importe qui, et la proclamation avait lieu sans elles. La
--      double clé était décorative.
--
--    · `donner_pouvoir` ne vérifie ni que le mandant est électeur, ni
--      que le mandataire l'est, et fige le plafond de pouvoirs à 2 dans
--      le corps de la fonction. Les règles statutaires se règlent, elles
--      ne se codent pas.
--
--    · Les politiques de lecture s'appuient sur
--      `puis_je_lire_journal_pieces()`, qui gouverne les pièces jointes
--      de la messagerie. L'organisateur du scrutin n'y avait pas accès,
--      un référent RGPD oui. Sans rapport avec le sujet.
--
--  Prérequis : 01 à 44.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE MÉNAGE
--    On retire les fonctions fautives. Les tables restent : elles sont
--    vides, bien faites, et on va s'en servir.
-- ---------------------------------------------------------------------

drop function if exists scanner_emargement_qr(uuid, uuid);
drop function if exists mes_pouvoirs_ag(uuid);
drop function if exists signer_cles_depouillement(uuid);
drop function if exists donner_pouvoir(uuid, uuid);
drop function if exists annuler_pouvoir(uuid);

-- Le plafond de pouvoirs est une règle statutaire : il se règle.
alter table pouvoirs_ag add column if not exists valide_par uuid references profils(id);
alter table cles_depouillement add column if not exists role text;

insert into regles_dotation (cle, libelle, valeur, unite, ordre) values
  ('ag_pouvoirs_max', 'Pouvoirs qu''un même mandataire peut détenir en assemblée',
   2, 'pouvoirs', 90)
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 2. LES POUVOIRS
--    Un pouvoir se donne entre électeurs de la même assemblée, et ne
--    vaut plus dès que le mandant a voté lui-même.
-- ---------------------------------------------------------------------

create or replace function donner_pouvoir(p_assemblee uuid, p_mandataire uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; v_max integer; v_deja integer; v_nom text;
begin
  select * into a from assemblees where id = p_assemblee;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.');
  end if;
  if a.statut not in ('annoncee','candidatures','scrutin') then
    return jsonb_build_object('ok', false,
      'message', 'Cette assemblée n''accepte plus de pouvoirs.');
  end if;
  if p_mandataire = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'On ne se donne pas pouvoir à soi-même.');
  end if;

  -- Les deux doivent appartenir au corps électoral : un pouvoir donné à
  -- quelqu'un qui ne peut pas voter ne vaut rien, et un pouvoir donné
  -- par un non-électeur créerait une voix de plus que d'électeurs.
  if not exists (select 1 from corps_electoral(p_assemblee) c
                 where c.profil_id = auth.uid()) then
    return jsonb_build_object('ok', false,
      'message', 'Vous n''appartenez pas au corps électoral de cette assemblée.');
  end if;
  if not exists (select 1 from corps_electoral(p_assemblee) c
                 where c.profil_id = p_mandataire) then
    return jsonb_build_object('ok', false,
      'message', 'Cette personne n''est pas électrice à cette assemblée : elle ne peut pas porter votre voix.');
  end if;
  if exists (select 1 from votes where assemblee_id = p_assemblee
             and electeur_id = auth.uid()) then
    return jsonb_build_object('ok', false,
      'message', 'Vous avez déjà voté : votre voix est exprimée, elle ne peut plus être déléguée.');
  end if;

  select coalesce(valeur, 2)::int into v_max
    from regles_dotation where cle = 'ag_pouvoirs_max';
  select count(*) into v_deja from pouvoirs_ag
   where assemblee_id = p_assemblee and mandataire_id = p_mandataire
     and statut = 'valide';
  select trim(prenom || ' ' || nom) into v_nom from profils where id = p_mandataire;

  if v_deja >= coalesce(v_max, 2) then
    return jsonb_build_object('ok', false,
      'message', v_nom || ' détient déjà ' || v_deja || ' pouvoir(s), soit le maximum statutaire.');
  end if;

  insert into pouvoirs_ag (assemblee_id, mandant_id, mandataire_id, statut)
  values (p_assemblee, auth.uid(), p_mandataire, 'valide')
  on conflict (assemblee_id, mandant_id) do update
    set mandataire_id = p_mandataire, statut = 'valide',
        motif = null, cree_le = now();

  return jsonb_build_object('ok', true, 'mandataire', v_nom);
end $$;

create or replace function annuler_pouvoir(p_assemblee uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update pouvoirs_ag
     set statut = 'annule', motif = 'Retiré par le mandant'
   where assemblee_id = p_assemblee and mandant_id = auth.uid()
     and statut = 'valide';
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Aucun pouvoir en cours.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Ce que je vois des pouvoirs : les miens toujours, tous ceux de
-- l'assemblée si j'en tiens l'organisation. Jamais au-delà.
drop function if exists pouvoirs_assemblee(uuid);
create or replace function pouvoirs_assemblee(p_assemblee uuid)
returns table (id uuid, mandant text, mandant_matricule text, mandant_id uuid,
               mandataire text, mandataire_matricule text, mandataire_id uuid,
               statut text, mandant_a_vote boolean, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, trim(m.prenom || ' ' || m.nom), m.matricule, m.id,
         trim(t.prenom || ' ' || t.nom), t.matricule, t.id,
         p.statut,
         exists (select 1 from votes v where v.assemblee_id = p.assemblee_id
                 and v.electeur_id = p.mandant_id),
         p.cree_le
  from pouvoirs_ag p
  join profils m on m.id = p.mandant_id
  join profils t on t.id = p.mandataire_id
  where p.assemblee_id = p_assemblee
    and (p.mandant_id = auth.uid() or p.mandataire_id = auth.uid()
         or est_admin() or a_droit('scrutin.organiser'))
  order by m.nom;
$$;

drop policy if exists pouvoirs_ag_lecture on pouvoirs_ag;
create policy pouvoirs_ag_lecture on pouvoirs_ag for select using (
  mandant_id = auth.uid() or mandataire_id = auth.uid()
  or est_admin() or a_droit('scrutin.organiser'));
grant select on pouvoirs_ag to authenticated;

-- ---------------------------------------------------------------------
-- 3. LA DOUBLE CLÉ
--    Elle ne vaut que si elle bloque quelque chose. Deux personnes
--    distinctes, habilitées, doivent la signer — et la proclamation la
--    vérifie.
-- ---------------------------------------------------------------------

create or replace function signer_depouillement(p_assemblee uuid, p_role text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; v_n integer;
begin
  if not (est_admin() or a_droit('scrutin.organiser') or a_droit('scrutin.proclamer')) then
    return jsonb_build_object('ok', false,
      'message', 'Seuls les membres du bureau de vote signent le dépouillement.');
  end if;
  select * into a from assemblees where id = p_assemblee;
  if a is null or a.statut not in ('scrutin','depouillement') then
    return jsonb_build_object('ok', false,
      'message', 'Ce scrutin n''est pas en cours de dépouillement.');
  end if;

  insert into cles_depouillement (assemblee_id, profil_id, role)
  values (p_assemblee, auth.uid(), nullif(trim(p_role),''))
  on conflict (assemblee_id, profil_id) do update
    set role = coalesce(nullif(trim(p_role),''), cles_depouillement.role);

  select count(*) into v_n from cles_depouillement where assemblee_id = p_assemblee;
  return jsonb_build_object('ok', true, 'cles', v_n, 'requises', 2,
    'message', case when v_n >= 2
      then 'Le dépouillement peut être proclamé.'
      else 'Une seconde signature est nécessaire, par une autre personne.' end);
end $$;

drop function if exists cles_du_depouillement(uuid);
create or replace function cles_du_depouillement(p_assemblee uuid)
returns table (profil_id uuid, membre text, role text, signe_le timestamptz)
language sql stable security definer set search_path = public as $$
  select c.profil_id, trim(p.prenom || ' ' || p.nom), c.role, c.signe_le
  from cles_depouillement c
  join profils p on p.id = c.profil_id
  where c.assemblee_id = p_assemblee
    and (est_admin() or a_droit('scrutin.organiser') or a_droit('scrutin.proclamer'))
  order by c.signe_le;
$$;

drop policy if exists cles_depouillement_lecture on cles_depouillement;
create policy cles_depouillement_lecture on cles_depouillement for select using (
  est_admin() or a_droit('scrutin.organiser') or a_droit('scrutin.proclamer'));
grant select on cles_depouillement to authenticated;

-- ---------------------------------------------------------------------
-- 4. LE BLOC « PRÉSIDENCE DE LA FFCE »
--    Il n'apparaissait pas, et ce n'était pas une erreur de données : la
--    règle du bloc solitaire, posée au lot 2, replie dans « Mon
--    activité » toute direction qui n'ouvre qu'une application. Or la
--    Présidence n'en porte qu'une — le Cabinet — depuis que le Recueil
--    est passé aux affaires juridiques.
--
--    La règle reste bonne pour les directions fonctionnelles. On ajoute
--    donc une exception nommée : certaines entités constituent un bloc
--    même seules, parce que leur existence dit quelque chose de
--    l'organisation.
-- ---------------------------------------------------------------------

alter table directions add column if not exists bloc_permanent boolean not null default false;

comment on column directions.bloc_permanent is
  'true : forme un bloc dans le menu même si elle n''ouvre qu''une application. Réservé aux entités dont l''existence même est signifiante.';

update directions set bloc_permanent = true where code = 'presidence';

drop function if exists mes_directions();
create or replace function mes_directions()
returns table (code text, nom text, nom_court text, couleur text, ordre integer,
               par_poste boolean, postes text[], bloc_permanent boolean)
language sql stable security definer set search_path = public as $$
  with vu as (select mon_niveau() >= 80 as federal)
  select d.code, d.nom, d.nom_court, d.couleur, d.ordre,
         exists (select 1 from nominations n
                 join postes po on po.code = n.poste
                 where n.profil_id = auth.uid() and nomination_active(n)
                   and po.direction = d.code),
         coalesce(array(select po.nom from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = auth.uid() and nomination_active(n)
                          and po.direction = d.code), '{}'),
         d.bloc_permanent
  from directions d, vu
  where d.actif
    and (
      exists (select 1 from nominations n join postes po on po.code = n.poste
              where n.profil_id = auth.uid() and nomination_active(n)
                and po.direction = d.code)
      or exists (select 1 from applications a
                 where a.actif
                   and d.code = case when vu.federal then a.direction
                                     else coalesce(a.direction_locale, a.direction) end
                   and source_acces(a.code) in ('admin','nominatif','poste','fonction'))
    )
  order by d.ordre;
$$;

grant execute on function donner_pouvoir(uuid, uuid), annuler_pouvoir(uuid),
                          pouvoirs_assemblee(uuid), signer_depouillement(uuid, text),
                          cles_du_depouillement(uuid), mes_directions()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 45
--
--  Vérifications :
--    select * from pouvoirs_assemblee('<uuid>');
--    select code, nom, bloc_permanent from mes_directions();
--    select proname from pg_proc where proname = 'scanner_emargement_qr';  -- vide
--
--  L'émargement par carte reste `emarger_par_carte(p_jeton, p_assemblee)`,
--  livrée en migration 43 : elle lit `profils.jeton_carte`, vérifie le
--  corps électoral, et n'est ouverte qu'à l'organisateur du scrutin.
--
--  Reste à faire dans le lot 13, non couvert ici : la proclamation ne
--  vérifie pas encore les deux clés. Le tour de vis se fera avec
--  l'écran de l'isoloir, pour ne pas bloquer une assemblée en cours
--  d'une règle qu'aucune interface ne permettrait encore de satisfaire.
-- =====================================================================
