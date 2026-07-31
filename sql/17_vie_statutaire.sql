-- =====================================================================
--  FFCE — Migration 17 — VIE STATUTAIRE DES STRUCTURES
--
--  La distinction qui commande tout : un MANDAT ÉLECTIF n'est pas une
--  FONCTION OPÉRATIONNELLE.
--
--    Le mandat vient du vote des adhérents. Il a une durée fixée par
--    les statuts, il ne se révoque pas d'un clic, et il fonde la
--    légitimité — président, trésorier, secrétaire.
--
--    La fonction vient de la nomination. Elle s'attribue et se retire
--    par décision, elle organise le travail — responsable local,
--    référent départemental.
--
--  Une même personne cumule souvent les deux. Les confondre, c'est
--  permettre à la direction de défaire un élu : exactement ce qu'il
--  faut empêcher.
--
--  Contenu : cycle de vie des structures, assemblées, appels à
--  candidature partageables hors connexion, scrutin, proclamation.
--
--  Prérequis : 01 à 16.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CYCLE DE VIE DES STRUCTURES
-- ---------------------------------------------------------------------

alter table territoires add column if not exists etat text not null default 'active'
  check (etat in ('projet','constitution','active','sommeil','dissoute'));
alter table territoires add column if not exists cree_le_reel date;
alter table territoires add column if not exists agree_le date;
alter table territoires add column if not exists sommeil_le date;
alter table territoires add column if not exists motif_etat text;
alter table territoires add column if not exists rattache_a uuid references territoires(id);

create table if not exists structure_journal (
  id        bigserial primary key,
  territoire_id uuid not null references territoires(id) on delete cascade,
  etat      text not null,
  motif     text,
  acteur    uuid references profils(id),
  cree_le   timestamptz not null default now()
);

insert into droits (code, nom, categorie, sensible, ordre) values
  ('structure.creer',   'Créer une structure',              'Structures', false, 32),
  ('structure.arreter', 'Mettre en sommeil ou dissoudre',   'Structures', true,  33),
  ('scrutin.organiser', 'Organiser une assemblée et un scrutin','Structures', false, 34),
  ('scrutin.proclamer', 'Proclamer les résultats',          'Structures', true,  36)
on conflict (code) do nothing;

insert into poste_droits (poste, droit) values
  ('delegue_admin','structure.creer'), ('delegue_admin','structure.arreter'),
  ('delegue_admin','scrutin.proclamer'),
  ('president_structure','scrutin.organiser'),
  ('secretaire_structure','scrutin.organiser')
on conflict do nothing;

create or replace function creer_structure(
  p_parent uuid, p_nom text, p_code text, p_echelle text default 'local')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('structure.creer') or mon_niveau() >= 60) then
    return jsonb_build_object('ok', false,
      'message', 'La création d''une structure relève du référent départemental ou de la direction.');
  end if;
  if coalesce(trim(p_nom),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le nom est obligatoire.');
  end if;

  insert into territoires (parent_id, echelle, code, nom, etat, cree_le_reel)
  values (p_parent, p_echelle,
          coalesce(nullif(trim(p_code),''),
                   'L' || upper(substr(md5(random()::text), 1, 6))),
          trim(p_nom), 'constitution', current_date)
  returning id into v_id;

  insert into structure_journal (territoire_id, etat, motif, acteur)
  values (v_id, 'constitution', 'Création', auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function changer_etat_structure(p_territoire uuid, p_etat text,
                                                  p_motif text, p_rattache uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_membres int;
begin
  if not a_droit('structure.arreter') and p_etat in ('sommeil','dissoute') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le changement doit être motivé.');
  end if;

  if p_etat = 'dissoute' then
    select count(*) into v_membres from profils
     where territoire_id = p_territoire and statut = 'actif';
    if v_membres > 0 and p_rattache is null then
      return jsonb_build_object('ok', false,
        'message', v_membres || ' membre(s) actif(s). Indiquez la structure de rattachement.');
    end if;
    if p_rattache is not null then
      update profils set territoire_id = p_rattache where territoire_id = p_territoire;
    end if;
  end if;

  update territoires
     set etat = p_etat, motif_etat = trim(p_motif),
         agree_le = case when p_etat = 'active' then coalesce(agree_le, current_date) else agree_le end,
         sommeil_le = case when p_etat = 'sommeil' then current_date else null end,
         rattache_a = p_rattache,
         actif = (p_etat not in ('dissoute'))
   where id = p_territoire;

  insert into structure_journal (territoire_id, etat, motif, acteur)
  values (p_territoire, p_etat, trim(p_motif), auth.uid());
  return jsonb_build_object('ok', true);
end $$;

-- Le sommeil se détecte, il ne se devine pas.
create or replace function structures_en_alerte()
returns table (territoire_id uuid, territoire text, echelle text, parent text,
               etat text, membres integer, alerte text, depuis integer)
language sql stable security definer set search_path = public as $$
  with base as (
    select t.id, t.nom, t.echelle, pt.nom as parent, t.etat,
      (select count(*)::int from profils p
        where p.territoire_id in (select s.id from territoires_sous(t.id) s)
          and p.statut = 'actif') as membres,
      (select max(n.debut) from nominations n
        where n.territoire_id = t.id and n.poste = 'president_structure'
          and nomination_active(n)) as president_depuis,
      (select max(g.cree_le) from groupes_travail g where g.territoire_id = t.id) as derniere_action,
      (select max(p.cree_le) from profils p where p.territoire_id = t.id) as dernier_adherent
    from territoires t
    left join territoires pt on pt.id = t.parent_id
    where t.echelle in ('local','departement') and t.etat <> 'dissoute')
  select b.id, b.nom, b.echelle, b.parent, b.etat, b.membres,
    case
      when b.membres = 0 then 'Aucun membre actif'
      when b.president_depuis is null then 'Aucun président élu'
      when b.derniere_action is null or b.derniere_action < now() - interval '6 months'
        then 'Aucune action depuis six mois'
      when b.dernier_adherent is null or b.dernier_adherent < now() - interval '12 months'
        then 'Aucun nouvel adhérent depuis un an'
      else null end,
    case
      when b.dernier_adherent is not null
        then extract(day from now() - b.dernier_adherent)::int
      else null end
  from base b
  where (est_admin() or mon_niveau() >= 60 or a_droit('membres.consulter'))
    and (b.membres = 0 or b.president_depuis is null
         or b.derniere_action is null or b.derniere_action < now() - interval '6 months')
  order by b.membres, b.nom;
$$;

-- ---------------------------------------------------------------------
-- 2. ASSEMBLÉES
-- ---------------------------------------------------------------------

create sequence if not exists seq_assemblee start 1;

create table if not exists assemblees (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'AG-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_assemblee')::text, 3, '0'),
  territoire_id uuid not null references territoires(id) on delete cascade,
  type          text not null default 'ordinaire'
                  check (type in ('constitutive','ordinaire','extraordinaire')),
  titre         text not null,
  ordre_du_jour text,
  lieu          text,
  date_tenue    timestamptz not null,
  -- Le calendrier statutaire : on ne vote pas sans avoir convoqué.
  ouverture_candidatures date,
  cloture_candidatures   date,
  ouverture_scrutin      timestamptz,
  cloture_scrutin        timestamptz,
  quorum_requis integer not null default 0,   -- en pourcentage
  statut        text not null default 'annoncee' check (statut in
                  ('annoncee','candidatures','scrutin','depouillement','proclamee','annulee')),
  postes_a_pourvoir text[] not null default array['president_structure',
                                                  'tresorier_structure',
                                                  'secretaire_structure'],
  duree_mandat_ans integer not null default 3,
  proces_verbal text,
  pv_fichier    text,
  organise_par  uuid references profils(id),
  proclame_par  uuid references profils(id),
  proclame_le   timestamptz,
  public_token  text unique not null default encode(gen_random_bytes(12), 'hex'),
  cree_le       timestamptz not null default now()
);
create index if not exists idx_ag_territoire on assemblees(territoire_id, date_tenue desc);

-- ---------------------------------------------------------------------
-- 3. CANDIDATURES
-- ---------------------------------------------------------------------

create table if not exists candidatures (
  id           uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  poste        text not null references postes(code),
  profil_id    uuid not null references profils(id) on delete cascade,
  profession_foi text,
  fichier      text,
  statut       text not null default 'deposee'
                 check (statut in ('deposee','recevable','irrecevable','retiree','elue','non_elue')),
  motif        text,
  examinee_par uuid references profils(id),
  cree_le      timestamptz not null default now(),
  unique (assemblee_id, poste, profil_id)
);

-- LE SCRUTIN, DEUX TABLES SANS LIEN.
--   L'ÉMARGEMENT dit qui a voté, le BULLETIN dit ce qui a été voté.
--   Aucune référence de l'un à l'autre : c'est ce qui rend le vote
--   secret tout en permettant de vérifier le quorum.
--   Elles sont déclarées ici, avant les fonctions qui les lisent.

create table if not exists votes (            -- l'émargement
  id           uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  electeur_id  uuid not null references profils(id) on delete cascade,
  cree_le      timestamptz not null default now(),
  unique (assemblee_id, electeur_id)
);

create table if not exists bulletins (        -- le contenu, anonyme
  id           uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  poste        text not null,
  candidature_id uuid references candidatures(id) on delete cascade,
  blanc        boolean not null default false,
  cree_le      timestamptz not null default now()
);
create index if not exists idx_bulletins on bulletins(assemblee_id, poste);

-- Qui peut se présenter, et qui peut voter : le corps électoral est le
-- même — les membres actifs rattachés au territoire.
create or replace function corps_electoral(p_assemblee uuid)
returns table (profil_id uuid, membre text, matricule text, a_vote boolean)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule,
         exists (select 1 from votes v where v.assemblee_id = p_assemblee
                 and v.electeur_id = p.id)
  from assemblees a
  join profils p on p.territoire_id in (select s.id from territoires_sous(a.territoire_id) s)
  where a.id = p_assemblee and p.statut = 'actif'
  order by p.nom, p.prenom;
$$;

create or replace function suis_je_electeur(p_assemblee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from corps_electoral(p_assemblee) c where c.profil_id = auth.uid());
$$;

create or replace function deposer_candidature(
  p_assemblee uuid, p_poste text, p_profession_foi text, p_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees;
begin
  select * into a from assemblees where id = p_assemblee;
  if a is null then return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.'); end if;
  if a.statut <> 'candidatures' then
    return jsonb_build_object('ok', false, 'message', 'Les candidatures ne sont pas ouvertes.');
  end if;
  if a.cloture_candidatures is not null and a.cloture_candidatures < current_date then
    return jsonb_build_object('ok', false,
      'message', 'Le dépôt était clos le ' || to_char(a.cloture_candidatures,'DD/MM/YYYY') || '.');
  end if;
  if not suis_je_electeur(p_assemblee) then
    return jsonb_build_object('ok', false,
      'message', 'Seuls les membres actifs du territoire peuvent se présenter.');
  end if;
  if coalesce(trim(p_profession_foi),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une profession de foi est demandée : les électeurs doivent savoir pour quoi ils votent.');
  end if;

  insert into candidatures (assemblee_id, poste, profil_id, profession_foi, fichier)
  values (p_assemblee, p_poste, auth.uid(), trim(p_profession_foi), nullif(p_fichier,''))
  on conflict (assemblee_id, poste, profil_id) do update
    set profession_foi = trim(p_profession_foi), fichier = nullif(p_fichier,''),
        statut = 'deposee';

  return jsonb_build_object('ok', true);
end $$;

create or replace function examiner_candidature(p_id uuid, p_recevable boolean, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('scrutin.organiser') or a_droit('scrutin.proclamer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''organisez pas ce scrutin.');
  end if;
  if not p_recevable and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une irrecevabilité doit être motivée.');
  end if;
  update candidatures
     set statut = case when p_recevable then 'recevable' else 'irrecevable' end,
         motif = nullif(trim(p_motif),''), examinee_par = auth.uid()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LE SCRUTIN
-- ---------------------------------------------------------------------

create or replace function voter(p_assemblee uuid, p_choix jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; v_poste text; v_cand text;
begin
  select * into a from assemblees where id = p_assemblee;
  if a is null then return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.'); end if;
  if a.statut <> 'scrutin' then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin n''est pas ouvert.');
  end if;
  if a.cloture_scrutin is not null and a.cloture_scrutin < now() then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin est clos.');
  end if;
  if not suis_je_electeur(p_assemblee) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''appartenez pas au corps électoral.');
  end if;
  if exists (select 1 from votes where assemblee_id = p_assemblee and electeur_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Vous avez déjà voté.');
  end if;

  -- L'émargement d'abord : il engage l'électeur.
  insert into votes (assemblee_id, electeur_id) values (p_assemblee, auth.uid());

  -- Puis les bulletins, sans aucun lien avec lui.
  for v_poste, v_cand in select key, value #>> '{}' from jsonb_each(p_choix) loop
    insert into bulletins (assemblee_id, poste, candidature_id, blanc)
    values (p_assemblee, v_poste,
            case when v_cand = 'blanc' then null else v_cand::uuid end,
            v_cand = 'blanc');
  end loop;

  return jsonb_build_object('ok', true);
end $$;

create or replace function depouillement(p_assemblee uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'inscrits', (select count(*) from corps_electoral(p_assemblee)),
    'votants',  (select count(*) from votes where assemblee_id = p_assemblee),
    'participation', case
      when (select count(*) from corps_electoral(p_assemblee)) = 0 then 0
      else round((select count(*) from votes where assemblee_id = p_assemblee)::numeric
                 / (select count(*) from corps_electoral(p_assemblee)) * 100) end,
    'quorum_requis', (select quorum_requis from assemblees where id = p_assemblee),
    'quorum_atteint', (
      select case when a.quorum_requis = 0 then true
        when (select count(*) from corps_electoral(p_assemblee)) = 0 then false
        else (select count(*) from votes where assemblee_id = p_assemblee)::numeric
             / (select count(*) from corps_electoral(p_assemblee)) * 100 >= a.quorum_requis end
      from assemblees a where a.id = p_assemblee),
    'resultats', coalesce((
      select jsonb_object_agg(po.nom, r.lignes) from (
        select b.poste, jsonb_agg(jsonb_build_object(
            'candidature_id', b.candidature_id,
            'nom', case when b.candidature_id is null then 'Bulletins blancs'
                        else trim(pr.prenom || ' ' || pr.nom) end,
            'voix', b.voix) order by b.voix desc) as lignes
        from (
          select poste, candidature_id, count(*)::int as voix
          from bulletins where assemblee_id = p_assemblee
          group by poste, candidature_id) b
        left join candidatures c on c.id = b.candidature_id
        left join profils pr on pr.id = c.profil_id
        group by b.poste) r
      join postes po on po.code = r.poste), '{}'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------
-- 5. PROCLAMATION
--    C'est ici que le mandat naît. Il crée une nomination datée, avec
--    une échéance conforme aux statuts.
-- ---------------------------------------------------------------------

create table if not exists mandats (
  id            uuid primary key default gen_random_uuid(),
  assemblee_id  uuid references assemblees(id) on delete set null,
  nomination_id uuid references nominations(id) on delete set null,
  profil_id     uuid not null references profils(id) on delete cascade,
  poste         text not null references postes(code),
  territoire_id uuid references territoires(id),
  debut         date not null,
  fin           date not null,
  voix          integer,
  suffrages     integer,
  fin_anticipee date,
  motif_fin     text,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_mandats_profil on mandats(profil_id);

create or replace function proclamer(p_assemblee uuid, p_pv text, p_pv_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; d jsonb; r record; v_nom uuid; v_fin date; v_elus int := 0;
begin
  if not (a_droit('scrutin.proclamer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'La proclamation relève de la direction.');
  end if;
  select * into a from assemblees where id = p_assemblee;
  if a.statut not in ('scrutin','depouillement') then
    return jsonb_build_object('ok', false, 'message', 'Ce scrutin n''est pas en état d''être proclamé.');
  end if;
  if coalesce(trim(p_pv),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le procès-verbal est obligatoire.');
  end if;

  d := depouillement(p_assemblee);
  if not (d->>'quorum_atteint')::boolean then
    return jsonb_build_object('ok', false,
      'message', 'Quorum non atteint : ' || (d->>'participation') || ' % pour ' ||
                 (d->>'quorum_requis') || ' % requis. Convoquez une nouvelle assemblée.');
  end if;

  v_fin := (a.date_tenue + (a.duree_mandat_ans || ' years')::interval)::date;

  -- Pour chaque poste, le candidat le mieux placé.
  for r in
    select distinct on (b.poste) b.poste, b.candidature_id, count(*)::int as voix
    from bulletins b
    where b.assemblee_id = p_assemblee and b.candidature_id is not null
    group by b.poste, b.candidature_id
    order by b.poste, count(*) desc
  loop
    -- Les mandats en cours sur ce poste et ce territoire prennent fin.
    update mandats set fin_anticipee = a.date_tenue::date,
           motif_fin = 'Fin de mandat — renouvellement'
     where poste = r.poste and territoire_id = a.territoire_id
       and fin_anticipee is null and fin >= current_date;
    update nominations set revoque_le = now(),
           motif_revocation = 'Renouvellement par élection'
     where poste = r.poste and territoire_id = a.territoire_id and revoque_le is null;

    insert into nominations (profil_id, poste, territoire_id, debut, fin, motif, nomme_par)
    select c.profil_id, r.poste, a.territoire_id, a.date_tenue::date, v_fin,
           'Élu en assemblée ' || a.reference, auth.uid()
    from candidatures c where c.id = r.candidature_id
    returning id into v_nom;

    insert into mandats (assemblee_id, nomination_id, profil_id, poste, territoire_id,
                         debut, fin, voix, suffrages)
    select p_assemblee, v_nom, c.profil_id, r.poste, a.territoire_id,
           a.date_tenue::date, v_fin, r.voix, (d->>'votants')::int
    from candidatures c where c.id = r.candidature_id;

    update candidatures set statut = 'elue' where id = r.candidature_id;
    update candidatures set statut = 'non_elue'
     where assemblee_id = p_assemblee and poste = r.poste
       and id <> r.candidature_id and statut = 'recevable';
    v_elus := v_elus + 1;
  end loop;

  update assemblees
     set statut = 'proclamee', proces_verbal = trim(p_pv),
         pv_fichier = nullif(p_pv_fichier,''),
         proclame_par = auth.uid(), proclame_le = now()
   where id = p_assemblee;

  -- Une assemblée constitutive fait naître la structure.
  if a.type = 'constitutive' then
    update territoires set etat = 'active', agree_le = current_date
     where id = a.territoire_id and etat = 'constitution';
    insert into structure_journal (territoire_id, etat, motif, acteur)
    values (a.territoire_id, 'active', 'Constituée par l''assemblée ' || a.reference, auth.uid());
  end if;

  return jsonb_build_object('ok', true, 'elus', v_elus, 'fin_mandat', v_fin);
end $$;

-- Les mandats qui arrivent à terme : on prévient six mois avant.
create or replace function mandats_a_renouveler()
returns table (mandat_id uuid, membre text, poste_nom text, territoire text,
               territoire_id uuid, debut date, fin date, jours_restants integer)
language sql stable security definer set search_path = public as $$
  select m.id, trim(p.prenom || ' ' || p.nom), po.nom, t.nom, t.id,
         m.debut, m.fin, (m.fin - current_date)::int
  from mandats m
  join profils p on p.id = m.profil_id
  join postes po on po.code = m.poste
  left join territoires t on t.id = m.territoire_id
  where m.fin_anticipee is null
    and m.fin between current_date - 30 and current_date + 180
    and (est_admin() or mon_niveau() >= 60 or a_droit('scrutin.organiser'))
  order by m.fin;
$$;

-- ---------------------------------------------------------------------
-- 6. LECTURE PUBLIQUE D'UN APPEL À CANDIDATURE
--    Partageable sans compte : c'est ainsi qu'on touche des gens qui
--    ne sont pas encore sur la plateforme.
-- ---------------------------------------------------------------------

create or replace function appel_public(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'reference', a.reference, 'titre', a.titre, 'type', a.type,
    'territoire', t.nom, 'chemin', chemin_territoire(t.id),
    'lieu', a.lieu, 'date_tenue', a.date_tenue,
    'ordre_du_jour', a.ordre_du_jour,
    'ouverture', a.ouverture_candidatures, 'cloture', a.cloture_candidatures,
    'statut', a.statut, 'duree_mandat', a.duree_mandat_ans,
    'postes', (select jsonb_agg(jsonb_build_object('code', po.code, 'nom', po.nom,
                      'description', po.description))
               from postes po where po.code = any(a.postes_a_pourvoir)),
    'candidats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'poste', po.nom,
        'nom', trim(pr.prenom || ' ' || substr(pr.nom, 1, 1) || '.'),
        'profession_foi', c.profession_foi))
      from candidatures c
      join postes po on po.code = c.poste
      join profils pr on pr.id = c.profil_id
      where c.assemblee_id = a.id and c.statut in ('recevable','elue')), '[]'::jsonb),
    'resultats', case when a.statut = 'proclamee' then (
      select jsonb_agg(jsonb_build_object('poste', po.nom,
             'elu', trim(pr.prenom || ' ' || pr.nom), 'fin', m.fin))
      from mandats m join postes po on po.code = m.poste
      join profils pr on pr.id = m.profil_id
      where m.assemblee_id = a.id) end
  )
  from assemblees a
  join territoires t on t.id = a.territoire_id
  where a.public_token = p_token
    and a.statut in ('annoncee','candidatures','scrutin','depouillement','proclamee');
$$;

-- ---------------------------------------------------------------------
-- 7. VUE D'ENSEMBLE
-- ---------------------------------------------------------------------

create or replace function mes_assemblees()
returns table (id uuid, reference text, titre text, type text, statut text,
               territoire text, territoire_id uuid, date_tenue timestamptz,
               lieu text, cloture_candidatures date, cloture_scrutin timestamptz,
               public_token text, electeur boolean, a_vote boolean,
               ma_candidature text, candidats integer, votants integer, inscrits integer)
language sql stable security definer set search_path = public as $$
  select a.id, a.reference, a.titre, a.type, a.statut, t.nom, t.id,
         a.date_tenue, a.lieu, a.cloture_candidatures, a.cloture_scrutin,
         a.public_token,
         suis_je_electeur(a.id),
         exists (select 1 from votes v where v.assemblee_id = a.id and v.electeur_id = auth.uid()),
         (select c.statut from candidatures c
           where c.assemblee_id = a.id and c.profil_id = auth.uid() limit 1),
         (select count(*)::int from candidatures c
           where c.assemblee_id = a.id and c.statut in ('deposee','recevable','elue')),
         (select count(*)::int from votes v where v.assemblee_id = a.id),
         (select count(*)::int from corps_electoral(a.id))
  from assemblees a
  join territoires t on t.id = a.territoire_id
  where suis_je_electeur(a.id) or est_admin() or a_droit('scrutin.organiser')
     or a_droit('scrutin.proclamer') or mon_niveau() >= 60
  order by a.date_tenue desc;
$$;

create or replace function creer_assemblee(
  p_territoire uuid, p_titre text, p_type text, p_date timestamptz,
  p_lieu text, p_ordre_du_jour text, p_cloture_cand date,
  p_ouverture_scrutin timestamptz, p_cloture_scrutin timestamptz,
  p_quorum integer, p_duree integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('scrutin.organiser') or a_droit('scrutin.proclamer')
          or est_admin() or mon_niveau() >= 60) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''organisez pas d''assemblée.');
  end if;
  insert into assemblees (territoire_id, titre, type, date_tenue, lieu, ordre_du_jour,
                          ouverture_candidatures, cloture_candidatures,
                          ouverture_scrutin, cloture_scrutin, quorum_requis,
                          duree_mandat_ans, organise_par, statut)
  values (p_territoire, trim(p_titre), p_type, p_date, nullif(trim(p_lieu),''),
          nullif(trim(p_ordre_du_jour),''), current_date, p_cloture_cand,
          p_ouverture_scrutin, p_cloture_scrutin, coalesce(p_quorum,0),
          coalesce(p_duree,3), auth.uid(), 'candidatures')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function changer_phase_assemblee(p_assemblee uuid, p_statut text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('scrutin.organiser') or a_droit('scrutin.proclamer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''organisez pas ce scrutin.');
  end if;
  if p_statut = 'scrutin' and not exists (
      select 1 from candidatures where assemblee_id = p_assemblee and statut = 'recevable') then
    return jsonb_build_object('ok', false,
      'message', 'Aucune candidature recevable : le scrutin serait sans objet.');
  end if;
  update assemblees set statut = p_statut,
         ouverture_scrutin = case when p_statut = 'scrutin'
           then coalesce(ouverture_scrutin, now()) else ouverture_scrutin end
   where id = p_assemblee;
  return jsonb_build_object('ok', true);
end $$;

-- =====================================================================
--  8. SÉCURITÉ
-- =====================================================================

alter table assemblees        enable row level security;
alter table candidatures      enable row level security;
alter table votes             enable row level security;
alter table bulletins         enable row level security;
alter table mandats           enable row level security;
alter table structure_journal enable row level security;

drop policy if exists lire_assemblees on assemblees;
create policy lire_assemblees on assemblees for select using (mon_niveau() >= 10);
drop policy if exists gerer_assemblees on assemblees;
create policy gerer_assemblees on assemblees for all
  using (a_droit('scrutin.organiser') or a_droit('scrutin.proclamer') or est_admin())
  with check (a_droit('scrutin.organiser') or a_droit('scrutin.proclamer') or est_admin());

drop policy if exists lire_candidatures_ag on candidatures;
create policy lire_candidatures_ag on candidatures for select using (
  profil_id = auth.uid() or suis_je_electeur(assemblee_id)
  or a_droit('scrutin.organiser') or est_admin()
);
drop policy if exists gerer_candidatures_ag on candidatures;
create policy gerer_candidatures_ag on candidatures for update
  using (a_droit('scrutin.organiser') or est_admin()
         or (profil_id = auth.uid() and statut = 'deposee'));

-- L'émargement est public au sein du corps électoral : chacun doit
-- pouvoir vérifier le quorum. Le bulletin, lui, ne l'est jamais.
drop policy if exists lire_votes on votes;
create policy lire_votes on votes for select using (suis_je_electeur(assemblee_id));

-- Aucune politique de lecture sur bulletins : le dépouillement passe
-- exclusivement par depouillement(), qui n'agrège que des totaux.

drop policy if exists lire_mandats on mandats;
create policy lire_mandats on mandats for select using (mon_niveau() >= 10);

drop policy if exists lire_struct_journal on structure_journal;
create policy lire_struct_journal on structure_journal for select using (mon_niveau() >= 10);

grant select on assemblees, candidatures, votes, mandats, structure_journal
  to authenticated;
grant insert, update on assemblees, candidatures to authenticated;

grant execute on function creer_structure(uuid, text, text, text),
                          changer_etat_structure(uuid, text, text, uuid),
                          structures_en_alerte(), corps_electoral(uuid),
                          suis_je_electeur(uuid),
                          deposer_candidature(uuid, text, text, text),
                          examiner_candidature(uuid, boolean, text),
                          voter(uuid, jsonb), depouillement(uuid),
                          proclamer(uuid, text, text), mandats_a_renouveler(),
                          mes_assemblees(),
                          creer_assemblee(uuid, text, text, timestamptz, text, text,
                                          date, timestamptz, timestamptz, integer, integer),
                          changer_phase_assemblee(uuid, text)
  to authenticated;

grant execute on function appel_public(text) to anon, authenticated;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, ordre)
values ('assemblees', 'Vie statutaire', 'Assemblées',
        'Assemblées, candidatures, scrutins et mandats.',
        'Élire, proclamer, renouveler.',
        10, false, 'bleu', 45)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche;

insert into application_visibilite (application, fonction, etat)
select 'assemblees', f.code, 'ouverte' from fonctions f
on conflict (application, fonction) do update set etat = 'ouverte';

-- =====================================================================
--  FIN DE LA MIGRATION 17
--
--  Le principe à ne jamais assouplir : l'émargement et le bulletin sont
--  deux tables sans lien. On sait qui a voté — c'est nécessaire au
--  quorum — et on sait ce qui a été voté, mais jamais qui a voté quoi.
--  La table bulletins n'a aucune politique de lecture : le
--  dépouillement passe par une fonction qui n'agrège que des totaux.
--
--  Et : la proclamation crée un MANDAT, avec une échéance. Un mandat
--  n'est pas une nomination ordinaire — il ne se révoque pas d'un clic,
--  il s'éteint à son terme ou par une nouvelle assemblée.
-- =====================================================================
