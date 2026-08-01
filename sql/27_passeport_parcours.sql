-- =====================================================================
--  FFCE — Migration 27 — PARCOURS LOCAL ET PASSEPORT D'ENGAGEMENT
--
--  Cinq apports, tous branchés sur ce qui existe déjà — aucun doublon.
--
--  1. L'ALERTE À LA BONNE PERSONNE. Un nouvel adhérent notifie son
--     bureau local. S'il n'y en a pas, il remonte en priorité au
--     responsable national du parcours : c'est précisément là qu'on
--     perd les gens.
--
--  2. L'ACCOMPAGNANT. Le bureau nomme un responsable du parcours
--     local — un poste, comme les autres — et peut aussi confier
--     quelqu'un à n'importe quel membre de son périmètre.
--
--  3. LE PASSEPORT D'ENGAGEMENT. Après chaque mission, le responsable
--     remplit un bilan : heures, ce qui a été fait, appréciation. Le
--     bénévole obtient un relevé de son parcours, utile pour un CV ou
--     une VAE. Les heures alimentent l'engagement mensuel, sans double
--     saisie.
--
--  4. LES CANDIDATURES AUX FORMATIONS NATIONALES. Le bénévole postule,
--     son bureau local arbitre qui partir.
--
--  5. L'ARBRE HIÉRARCHIQUE. Qui dépend de qui, calculé depuis le
--     maillage territorial existant.
--
--  Prérequis : 01 à 26.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE POSTE D'ACCOMPAGNEMENT LOCAL
-- ---------------------------------------------------------------------

insert into postes (code, nom, description, couleur, systeme, direction) values
  ('parcours_local', 'Responsable du parcours adhérent — local',
   'Accueille les nouveaux membres de sa structure, tient les entretiens et fait remonter ce qui bloque.',
   'vert', true, 'dvie')
on conflict (code) do update
  set description = excluded.description, direction = excluded.direction;

insert into poste_droits (poste, droit) values
  ('parcours_local','parcours.accueillir'),
  ('parcours_local','membres.consulter')
on conflict do nothing;

insert into poste_applications (poste, application) values
  ('parcours_local','parcours'), ('parcours_local','annuaire')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2. À QUI REVIENT UN NOUVEL ADHÉRENT
--    On cherche d'abord au plus près, puis on remonte. Un adhérent d'un
--    département sans bureau ne doit pas rester sans personne.
-- ---------------------------------------------------------------------

create or replace function accompagnant_naturel(p_profil uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  -- « recursive » vaut pour tout le bloc WITH, même si une seule CTE
  -- se référence elle-même.
  with recursive terr as (select territoire_id as t from profils where id = p_profil),
  chaine as (
    -- Le territoire du membre, puis ses parents, du plus proche au plus loin.
    select id, parent_id, 1 as rang from territoires, terr where id = terr.t
    union all
    select t.id, t.parent_id, c.rang + 1
    from territoires t join chaine c on t.id = c.parent_id),
  candidats as (
    select n.profil_id, po.code as poste, po.nom as poste_nom, c.rang,
           case po.code
             when 'parcours_local' then 1
             when 'president_structure' then 2
             when 'parcours_adherent' then 3
             else 4 end as priorite
    from chaine c
    join nominations n on n.territoire_id = c.id and nomination_active(n)
    join postes po on po.code = n.poste
    where po.code in ('parcours_local','president_structure','parcours_adherent'))
  select coalesce(
    (select jsonb_build_object(
       'profil_id', p.id, 'nom', trim(p.prenom || ' ' || p.nom),
       'poste', x.poste_nom, 'echelon', x.rang,
       'source', case when x.rang = 1 then 'local' else 'remonte' end)
     from candidats x join profils p on p.id = x.profil_id
     order by x.rang, x.priorite limit 1),
    -- Personne dans la chaîne : le national prend la main.
    (select jsonb_build_object(
       'profil_id', p.id, 'nom', trim(p.prenom || ' ' || p.nom),
       'poste', 'Responsable national du parcours', 'echelon', 99,
       'source', 'national')
     from nominations n join profils p on p.id = n.profil_id
     where n.poste = 'parcours_adherent' and n.territoire_id is null
       and nomination_active(n) limit 1),
    jsonb_build_object('source', 'aucun'));
$$;

-- L'affectation se fait à l'inscription, et se corrige à tout moment.
create or replace function affecter_accompagnant(p_profil uuid, p_accompagnant uuid,
                                                 p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('parcours.accueillir') or est_admin()
          or (mon_niveau() >= 50 and dans_mon_perimetre(
                (select territoire_id from profils where id = p_profil)))) then
    return jsonb_build_object('ok', false, 'message', 'Hors de votre périmètre.');
  end if;
  -- N'importe quel membre actif du périmètre peut accompagner : ce n'est
  -- pas un pouvoir, c'est une attention.
  if not exists (select 1 from profils where id = p_accompagnant and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Cette personne n''est pas active.');
  end if;

  update parcours set referent_id = p_accompagnant,
         notes = coalesce(notes || E'\n', '') || to_char(now(),'DD/MM') ||
                 ' — confié à ' ||
                 (select trim(prenom || ' ' || nom) from profils where id = p_accompagnant) ||
                 coalesce(' : ' || nullif(trim(p_motif),''), ''),
         maj_le = now()
   where profil_id = p_profil;
  return jsonb_build_object('ok', true);
end $$;

-- Les nouveaux, avec l'urgence là où il n'y a pas de bureau.
create or replace function nouveaux_a_repartir()
returns table (profil_id uuid, membre text, matricule text, email text,
               territoire text, territoire_id uuid, inscrit_le timestamptz,
               jours integer, accompagnant text, accompagnant_id uuid,
               bureau_local boolean, source text, priorite integer)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, p.email,
         t.nom, p.territoire_id, pa.inscrit_le,
         extract(day from now() - pa.inscrit_le)::int,
         trim(r.prenom || ' ' || r.nom), pa.referent_id,
         exists (select 1 from nominations n
                 where n.territoire_id = p.territoire_id and nomination_active(n)
                   and n.poste in ('president_structure','parcours_local')),
         accompagnant_naturel(p.id)->>'source',
         -- Sans bureau et sans accompagnant : c'est le cas prioritaire.
         case
           when pa.referent_id is null
                and not exists (select 1 from nominations n
                                where n.territoire_id = p.territoire_id
                                  and nomination_active(n)
                                  and n.poste in ('president_structure','parcours_local'))
             then 1
           when pa.referent_id is null then 2
           when pa.contacte_le is null and pa.inscrit_le < now() - interval '7 days' then 3
           else 4 end
  from parcours pa
  join profils p on p.id = pa.profil_id
  left join territoires t on t.id = p.territoire_id
  left join profils r on r.id = pa.referent_id
  where pa.premiere_mission_le is null and pa.abandonne_le is null
    and p.statut <> 'archive'
    and (est_admin() or a_droit('parcours.accueillir')
         or (mon_niveau() >= 50 and dans_mon_perimetre(p.territoire_id)))
  order by 13, pa.inscrit_le;
$$;

-- Ce qui remonte au bureau local et au national : une seule fonction,
-- appelée par la file de travail.
create or replace function alertes_nouveaux()
returns table (code text, libelle text, nombre integer, lien text, urgence text)
language sql stable security definer set search_path = public as $$
  select * from (values
    ('sans_bureau', 'nouvel(le)(s) adhérent(s) sans bureau local',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 1),
      '#/espace/parcours', 'haute'),
    ('sans_accompagnant', 'nouvel(le)(s) adhérent(s) sans accompagnant',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 2),
      '#/espace/parcours', 'haute')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

-- ---------------------------------------------------------------------
-- 3. LE RECUEIL DES ENVIES
--    Ce qu'on demande à l'entretien d'accueil, et qui sert ensuite à
--    proposer les bonnes missions.
-- ---------------------------------------------------------------------

create table if not exists aspirations (
  profil_id     uuid primary key references profils(id) on delete cascade,
  domaines      text[],          -- éducation, mémoire, médias, égalité…
  publics       text[],          -- collégiens, lycéens, quartiers, ruralité…
  competences   text[],
  envies        text,            -- ce que la personne veut faire
  reticences    text,            -- ce qu'elle préfère éviter
  disponibilite text,
  mobilite      text,
  objectif      text,            -- où elle se voit dans un an
  recueilli_par uuid references profils(id),
  recueilli_le  timestamptz,
  maj_le        timestamptz not null default now()
);

create or replace function enregistrer_aspirations(p_profil uuid, d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (p_profil = auth.uid() or a_droit('parcours.accueillir') or est_admin()
          or exists (select 1 from parcours where profil_id = p_profil
                     and referent_id = auth.uid())) then
    return jsonb_build_object('ok', false, 'message', 'Ce dossier n''est pas le vôtre.');
  end if;

  insert into aspirations (profil_id, domaines, publics, competences, envies,
                           reticences, disponibilite, mobilite, objectif,
                           recueilli_par, recueilli_le)
  values (p_profil,
    (select array_agg(x) from jsonb_array_elements_text(coalesce(d->'domaines','[]')) x),
    (select array_agg(x) from jsonb_array_elements_text(coalesce(d->'publics','[]')) x),
    (select array_agg(x) from jsonb_array_elements_text(coalesce(d->'competences','[]')) x),
    nullif(d->>'envies',''), nullif(d->>'reticences',''),
    nullif(d->>'disponibilite',''), nullif(d->>'mobilite',''),
    nullif(d->>'objectif',''),
    case when p_profil <> auth.uid() then auth.uid() end,
    case when p_profil <> auth.uid() then now() end)
  on conflict (profil_id) do update set
    domaines = excluded.domaines, publics = excluded.publics,
    competences = excluded.competences, envies = excluded.envies,
    reticences = excluded.reticences, disponibilite = excluded.disponibilite,
    mobilite = excluded.mobilite, objectif = excluded.objectif,
    recueilli_par = coalesce(excluded.recueilli_par, aspirations.recueilli_par),
    recueilli_le = coalesce(excluded.recueilli_le, aspirations.recueilli_le),
    maj_le = now();
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LE PASSEPORT D'ENGAGEMENT
--    Après chaque mission, un bilan. Les heures alimentent l'engagement
--    mensuel : on ne saisit pas deux fois la même chose.
-- ---------------------------------------------------------------------

create table if not exists bilans_mission (
  id            uuid primary key default gen_random_uuid(),
  mission_id    uuid not null references missions(id) on delete cascade,
  profil_id     uuid not null references profils(id) on delete cascade,
  heures        numeric(5,1) not null check (heures > 0),
  realise       text not null,          -- ce qui a été fait, concrètement
  competences   text[],                 -- ce que la personne y a exercé
  appreciation  text,
  merite        text check (merite is null or merite in
                  ('a_progresser','satisfaisant','remarquable','exemplaire')),
  redige_par    uuid not null references profils(id),
  cree_le       timestamptz not null default now(),
  unique (mission_id, profil_id)
);
create index if not exists idx_bilans_profil on bilans_mission(profil_id);

create or replace function rediger_bilan(
  p_mission uuid, p_profil uuid, p_heures numeric, p_realise text,
  p_competences text[] default null, p_appreciation text default null,
  p_merite text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m missions; v_mois date;
begin
  select * into m from missions where id = p_mission;
  if m is null then return jsonb_build_object('ok', false, 'message', 'Mission introuvable.'); end if;

  if not (m.cree_par = auth.uid() or est_admin() or mon_niveau() >= 50
          or a_droit('parcours.accueillir')) then
    return jsonb_build_object('ok', false,
      'message', 'Le bilan revient au porteur de la mission ou à l''encadrement.');
  end if;
  if not exists (select 1 from mission_candidatures c
                 where c.mission_id = p_mission and c.profil_id = p_profil
                   and c.statut = 'retenu') then
    return jsonb_build_object('ok', false,
      'message', 'Cette personne n''a pas été retenue sur cette mission.');
  end if;
  if coalesce(p_heures, 0) <= 0 then
    return jsonb_build_object('ok', false,
      'message', 'Les heures effectuées sont obligatoires : c''est ce qui vaut au bénévole sa reconnaissance.');
  end if;
  if coalesce(trim(p_realise),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Décrivez ce qui a été fait : le bénévole en aura besoin pour son passeport.');
  end if;

  insert into bilans_mission (mission_id, profil_id, heures, realise, competences,
                              appreciation, merite, redige_par)
  values (p_mission, p_profil, p_heures, trim(p_realise), p_competences,
          nullif(trim(p_appreciation),''), p_merite, auth.uid())
  on conflict (mission_id, profil_id) do update
    set heures = excluded.heures, realise = excluded.realise,
        competences = excluded.competences, appreciation = excluded.appreciation,
        merite = excluded.merite, redige_par = auth.uid();

  -- Les heures rejoignent l'engagement du mois de la mission : une
  -- seule source de vérité, pas deux compteurs qui divergent.
  v_mois := date_trunc('month', coalesce(m.fin, m.debut, current_date))::date;
  insert into engagements (profil_id, mois, heures_visees, heures_realisees)
  values (p_profil, v_mois, 0, p_heures)
  on conflict (profil_id, mois) do update
    set heures_realisees = coalesce(engagements.heures_realisees, 0) + p_heures,
        maj_le = now();

  perform jalonner_parcours(p_profil);
  return jsonb_build_object('ok', true);
end $$;

-- Les missions achevées dont le bilan manque : ce qu'un porteur doit voir.
create or replace function bilans_a_rediger()
returns table (mission_id uuid, mission text, fin date, lieu text,
               profil_id uuid, membre text, matricule text,
               jours_depuis integer)
language sql stable security definer set search_path = public as $$
  select m.id, m.titre, m.fin, m.lieu, p.id,
         trim(p.prenom || ' ' || p.nom), p.matricule,
         (current_date - coalesce(m.fin, m.debut))::int
  from missions m
  join mission_candidatures c on c.mission_id = m.id and c.statut = 'retenu'
  join profils p on p.id = c.profil_id
  where coalesce(m.fin, m.debut) < current_date
    and not exists (select 1 from bilans_mission b
                    where b.mission_id = m.id and b.profil_id = p.id)
    and (m.cree_par = auth.uid() or est_admin() or mon_niveau() >= 50)
  order by coalesce(m.fin, m.debut);
$$;

-- Le passeport : le relevé qu'un bénévole peut présenter ailleurs.
create or replace function passeport(p_profil uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with cible as (select coalesce(p_profil, auth.uid()) as id)
  select case when not (
      (select id from cible) = auth.uid() or est_admin()
      or a_droit('parcours.accueillir') or a_droit('chancellerie.suivre')
      or exists (select 1 from profils p, cible where p.id = cible.id
                 and est_encadrant() and dans_mon_perimetre(p.territoire_id)))
    then jsonb_build_object('erreur', 'Ce passeport n''est pas le vôtre.')
    else jsonb_build_object(
      'identite', (select jsonb_build_object(
          'matricule', p.matricule, 'nom', trim(p.prenom || ' ' || p.nom),
          'fonction', f.nom, 'echelon', p.echelon, 'echelon_nom', e.nom,
          'territoire', t.nom, 'depuis', p.date_adhesion, 'inscrit_le', p.cree_le)
        from profils p
        join cible on cible.id = p.id
        join fonctions f on f.code = p.fonction
        join echelons e on e.niveau = p.echelon
        left join territoires t on t.id = p.territoire_id),
      'totaux', (select jsonb_build_object(
          'heures', coalesce(sum(b.heures), 0),
          'missions', count(*),
          'annees', (select round(extract(epoch from now() - p.cree_le)
                                  / 31557600, 1) from profils p, cible where p.id = cible.id))
        from bilans_mission b join cible on cible.id = b.profil_id),
      'missions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'titre', m.titre, 'lieu', m.lieu, 'debut', m.debut, 'fin', m.fin,
          'heures', b.heures, 'realise', b.realise,
          'competences', b.competences, 'appreciation', b.appreciation,
          'merite', b.merite,
          'atteste_par', trim(r.prenom || ' ' || r.nom))
          order by coalesce(m.fin, m.debut) desc)
        from bilans_mission b
        join missions m on m.id = b.mission_id
        join profils r on r.id = b.redige_par
        join cible on cible.id = b.profil_id), '[]'::jsonb),
      'certifications', coalesce((
        select jsonb_agg(jsonb_build_object(
          'nom', c.nom, 'numero', co.numero,
          'obtenue_le', co.obtenue_le, 'expire_le', co.expire_le)
          order by co.obtenue_le desc)
        from certifications_obtenues co
        join certifications c on c.code = co.code
        join cible on cible.id = co.profil_id), '[]'::jsonb),
      'distinctions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'nom', td.nom, 'motif', d.motif, 'numero', d.numero,
          'le', d.decernee_le) order by d.decernee_le desc)
        from distinctions d
        join types_distinction td on td.code = d.type
        join cible on cible.id = d.profil_id
        where d.retiree_le is null), '[]'::jsonb),
      'mandats', coalesce((
        select jsonb_agg(jsonb_build_object(
          'poste', po.nom, 'territoire', t.nom, 'debut', mn.debut, 'fin', mn.fin)
          order by mn.debut desc)
        from mandats mn join postes po on po.code = mn.poste
        left join territoires t on t.id = mn.territoire_id
        join cible on cible.id = mn.profil_id), '[]'::jsonb),
      'competences_exercees', coalesce((
        select jsonb_agg(distinct x) from bilans_mission b
        join cible on cible.id = b.profil_id
        cross join lateral unnest(coalesce(b.competences, '{}')) x), '[]'::jsonb))
    end;
$$;

-- ---------------------------------------------------------------------
-- 5. CANDIDATURES AUX FORMATIONS NATIONALES
--    Le bénévole postule, son bureau arbitre.
-- ---------------------------------------------------------------------

alter table formations add column if not exists sur_candidature boolean not null default false;
alter table formations add column if not exists places integer;
alter table formations add column if not exists lieu text;
alter table formations add column if not exists session_debut date;
alter table formations add column if not exists session_fin date;

create table if not exists candidatures_formation (
  id           uuid primary key default gen_random_uuid(),
  formation_id uuid not null references formations(id) on delete cascade,
  profil_id    uuid not null references profils(id) on delete cascade,
  motivation   text not null,
  statut       text not null default 'deposee' check (statut in
                 ('deposee','soutenue','ecartee','retenue','non_retenue','desistee')),
  avis_local   text,
  arbitre_par  uuid references profils(id),
  arbitre_le   timestamptz,
  decision_nationale text,
  decide_par   uuid references profils(id),
  cree_le      timestamptz not null default now(),
  unique (formation_id, profil_id)
);

create or replace function postuler_formation(p_formation uuid, p_motivation text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f formations;
begin
  select * into f from formations where id = p_formation;
  if f is null or not f.sur_candidature then
    return jsonb_build_object('ok', false, 'message', 'Cette formation ne se fait pas sur candidature.');
  end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if mon_niveau() < f.niveau_min then
    return jsonb_build_object('ok', false,
      'message', 'Cette formation s''adresse à une autre fonction.');
  end if;
  if coalesce(trim(p_motivation),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi cette formation vous intéresse : votre bureau doit arbitrer.');
  end if;

  insert into candidatures_formation (formation_id, profil_id, motivation)
  values (p_formation, auth.uid(), trim(p_motivation))
  on conflict (formation_id, profil_id) do update
    set motivation = trim(p_motivation), statut = 'deposee';
  return jsonb_build_object('ok', true);
end $$;

create or replace function arbitrer_candidature_formation(
  p_id uuid, p_statut text, p_avis text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c candidatures_formation; v_terr uuid;
begin
  select * into c from candidatures_formation where id = p_id;
  select territoire_id into v_terr from profils where id = c.profil_id;

  -- Le soutien local relève du bureau ; la décision finale du national.
  if p_statut in ('soutenue','ecartee') then
    if not (est_admin() or mon_niveau() >= 50 or a_droit('structure.animer')
            or dans_mon_perimetre(v_terr)) then
      return jsonb_build_object('ok', false, 'message', 'Hors de votre périmètre.');
    end if;
  elsif not (est_admin() or a_droit('formations.editer') or mon_niveau() >= 80) then
    return jsonb_build_object('ok', false,
      'message', 'La décision finale relève du national.');
  end if;
  if coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Motivez votre décision.');
  end if;

  if p_statut in ('soutenue','ecartee') then
    update candidatures_formation
       set statut = p_statut, avis_local = trim(p_avis),
           arbitre_par = auth.uid(), arbitre_le = now()
     where id = p_id;
  else
    update candidatures_formation
       set statut = p_statut, decision_nationale = trim(p_avis),
           decide_par = auth.uid()
     where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function candidatures_formation_a_arbitrer()
returns table (id uuid, formation text, formation_id uuid, session_debut date,
               lieu text, places integer, candidat text, matricule text,
               profil_id uuid, territoire text, motivation text, statut text,
               avis_local text, cree_le timestamptz, mon_ressort boolean)
language sql stable security definer set search_path = public as $$
  select cf.id, f.titre, f.id, f.session_debut, f.lieu, f.places,
         trim(p.prenom || ' ' || p.nom), p.matricule, p.id, t.nom,
         cf.motivation, cf.statut, cf.avis_local, cf.cree_le,
         cf.statut = 'deposee' and (est_admin() or mon_niveau() >= 50
                                    or dans_mon_perimetre(p.territoire_id))
  from candidatures_formation cf
  join formations f on f.id = cf.formation_id
  join profils p on p.id = cf.profil_id
  left join territoires t on t.id = p.territoire_id
  where cf.statut in ('deposee','soutenue')
    and (est_admin() or mon_niveau() >= 50 or a_droit('formations.editer')
         or dans_mon_perimetre(p.territoire_id))
  order by f.session_debut nulls last, cf.cree_le;
$$;

-- ---------------------------------------------------------------------
-- 6. L'ARBRE HIÉRARCHIQUE
--    Qui dépend de qui, depuis le maillage existant.
-- ---------------------------------------------------------------------

create or replace function ma_chaine()
returns jsonb language sql stable security definer set search_path = public as $$
  with recursive moi as (select territoire_id as t from profils where id = auth.uid()),
  remonte as (
    select id, parent_id, nom, echelle, 0 as rang from territoires, moi where id = moi.t
    union all
    select t.id, t.parent_id, t.nom, t.echelle, r.rang + 1
    from territoires t join remonte r on t.id = r.parent_id)
  select jsonb_build_object(
    'moi', (select jsonb_build_object('nom', trim(p.prenom || ' ' || p.nom),
              'fonction', f.nom, 'matricule', p.matricule)
            from profils p join fonctions f on f.code = p.fonction
            where p.id = auth.uid()),
    'chaine', coalesce((
      select jsonb_agg(jsonb_build_object(
        'territoire', r.nom, 'echelle', r.echelle, 'rang', r.rang,
        'responsables', coalesce((
          select jsonb_agg(jsonb_build_object(
            'nom', trim(pp.prenom || ' ' || pp.nom),
            'poste', po.nom, 'profil_id', pp.id, 'photo', pp.photo_url))
          from nominations n join postes po on po.code = n.poste
          join profils pp on pp.id = n.profil_id
          where n.territoire_id = r.id and nomination_active(n)
            and po.code like '%_structure'), '[]'::jsonb),
        'encadrants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'nom', trim(pp.prenom || ' ' || pp.nom),
            'fonction', ff.nom, 'profil_id', pp.id, 'photo', pp.photo_url))
          from profils pp join fonctions ff on ff.code = pp.fonction
          where pp.territoire_id = r.id and pp.statut = 'actif' and ff.niveau >= 50),
          '[]'::jsonb))
        order by r.rang)
      from remonte r), '[]'::jsonb),
    'mon_accompagnant', (select jsonb_build_object(
        'nom', trim(rp.prenom || ' ' || rp.nom), 'profil_id', rp.id)
      from parcours pa join profils rp on rp.id = pa.referent_id
      where pa.profil_id = auth.uid()),
    'dont_je_reponds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nom', trim(pp.prenom || ' ' || pp.nom), 'fonction', ff.nom,
        'territoire', tt.nom, 'profil_id', pp.id))
      from profils pp join fonctions ff on ff.code = pp.fonction
      left join territoires tt on tt.id = pp.territoire_id
      where pp.statut = 'actif' and pp.id <> auth.uid()
        and est_encadrant() and dans_mon_perimetre(pp.territoire_id)
        and ff.niveau < mon_niveau()), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- 7. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table aspirations            enable row level security;
alter table bilans_mission         enable row level security;
alter table candidatures_formation enable row level security;

drop policy if exists lire_aspirations on aspirations;
create policy lire_aspirations on aspirations for select using (
  profil_id = auth.uid() or est_admin() or a_droit('parcours.accueillir')
  or exists (select 1 from parcours pa where pa.profil_id = aspirations.profil_id
             and pa.referent_id = auth.uid())
  or exists (select 1 from profils p where p.id = aspirations.profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);

drop policy if exists lire_bilans on bilans_mission;
create policy lire_bilans on bilans_mission for select using (
  profil_id = auth.uid() or redige_par = auth.uid() or est_admin()
  or a_droit('chancellerie.suivre') or a_droit('parcours.accueillir')
  or exists (select 1 from profils p where p.id = bilans_mission.profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);

drop policy if exists lire_cand_formation on candidatures_formation;
create policy lire_cand_formation on candidatures_formation for select using (
  profil_id = auth.uid() or est_admin() or a_droit('formations.editer')
  or exists (select 1 from profils p where p.id = candidatures_formation.profil_id
             and (mon_niveau() >= 50 and dans_mon_perimetre(p.territoire_id)))
);

grant select on aspirations, bilans_mission, candidatures_formation to authenticated;
grant insert, update on aspirations to authenticated;

grant execute on function accompagnant_naturel(uuid),
                          affecter_accompagnant(uuid, uuid, text),
                          nouveaux_a_repartir(), alertes_nouveaux(),
                          enregistrer_aspirations(uuid, jsonb),
                          rediger_bilan(uuid, uuid, numeric, text, text[], text, text),
                          bilans_a_rediger(), passeport(uuid),
                          postuler_formation(uuid, text),
                          arbitrer_candidature_formation(uuid, text, text),
                          candidatures_formation_a_arbitrer(), ma_chaine()
  to authenticated;

-- ---------------------------------------------------------------------
-- 8. LA FILE DE TRAVAIL INTÈGRE LE NOUVEAU
-- ---------------------------------------------------------------------

drop function if exists ce_qui_attend();
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
    ('taches', 'tâche(s) qui vous sont assignées',
      (select count(*)::int from gt_taches
        where assigne_a = auth.uid() and statut in ('a_faire','en_cours')),
      '#/espace/groupes', 'normale'),
    ('invitations', 'invitation(s) à un groupe de travail',
      (select count(*)::int from gt_membres
        where profil_id = auth.uid() and statut = 'invite'),
      '#/espace/groupes', 'normale'),
    ('scrutins', 'scrutin(s) où vous n''avez pas voté',
      (select count(*)::int from mes_assemblees()
        where statut = 'scrutin' and electeur and not a_vote),
      '#/espace/assemblees', 'haute'),
    ('interims', 'intérim(s) qui vous sont proposés',
      (select count(*)::int from mes_interims()
        where statut = 'propose' and je_suis_interimaire),
      '#/espace/habilitations', 'normale'),
    ('messages', 'conversation(s) non lue(s)',
      (select count(*)::int from mes_conversations() c where c.non_lus > 0),
      '#/espace/messagerie', 'normale')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

grant execute on function ce_qui_attend() to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 27
--
--  Vérifications :
--    select accompagnant_naturel('<un-profil>');
--    select * from nouveaux_a_repartir();
--    select * from bilans_a_rediger();
--    select passeport();
--
--  Sur les heures : le bilan de mission alimente l'engagement mensuel
--  du mois concerné. Une seule source, pas deux compteurs qui
--  divergent — et le bénévole n'a rien à ressaisir.
-- =====================================================================
