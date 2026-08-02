-- =====================================================================
--  FFCE — Migration 39 — LA GESTION LOCALE
--
--  Quatre chantiers qui n'en font qu'un : rendre au terrain ce qui
--  relève du terrain, sans lâcher ce qui relève du national.
--
--  1. LES ACTES LOCAUX. Une nomination locale se prend désormais par
--     acte, comme au national — mais un acte local ne s'affiche qu'aux
--     adhérents du périmètre concerné. Les présidents de structure en
--     sont exclus : ils sont annoncés par l'échelon supérieur, sans
--     quoi une présidence se conférerait elle-même.
--
--  2. LES HABILITATIONS LOCALES. Le national décide quelles
--     applications peuvent être ouvertes localement ; l'échelon local
--     décide à qui. La liste des applications délégables est une
--     donnée, pas une règle codée.
--
--  3. LA FICHE DE TERRITOIRE. Identité, rattachement, académie, siège,
--     contacts, et les indicateurs de vie qui se recalculent à la
--     lecture. Plus un plan d'ensemble qui permet de rattacher, mettre
--     en sommeil ou fusionner.
--
--  4. LES ÉCHELONS. Leur nom, leur seuil et ce qu'ils ouvrent étaient
--     figés dans la migration 01. Ils se règlent depuis la chancellerie.
--
--  Prérequis : 01 à 38.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. MÉNAGE
--    Les migrations 36 et 38 ont élargi trois fonctions en ajoutant des
--    paramètres. `create or replace` n'a pas remplacé l'ancienne
--    signature : il en a créé une seconde. Deux fonctions de même nom
--    rendent l'appel ambigu et laissent vivre du code mort.
-- ---------------------------------------------------------------------

drop function if exists ajouter_au_panier(uuid, integer);
drop function if exists deposer_commande(uuid, text);
drop function if exists envoyer_message(uuid, text);

-- ---------------------------------------------------------------------
-- 1. LA FICHE D'IDENTITÉ D'UN TERRITOIRE
-- ---------------------------------------------------------------------

alter table territoires add column if not exists academie text;
alter table territoires add column if not exists siege text;
alter table territoires add column if not exists courriel text;
alter table territoires add column if not exists telephone text;
alter table territoires add column if not exists population integer;
alter table territoires add column if not exists note text;
alter table territoires add column if not exists cree_le_reel date;

comment on column territoires.academie is
  'Rattachement académique, utile pour les partenariats scolaires. Sans lien avec le découpage administratif.';

-- ---------------------------------------------------------------------
-- 2. CE QUE LE NATIONAL DÉLÈGUE
--    Une application délégable peut être ouverte par un responsable
--    local à quelqu'un de son périmètre. Les autres restent au
--    national. C'est une donnée réglable, pas une règle écrite dans le
--    code — le jour où la fédération change d'avis, elle coche.
-- ---------------------------------------------------------------------

alter table applications add column if not exists delegable_local boolean not null default false;

update applications set delegable_local = true
 where code in ('formations','groupes','messagerie','engagement','notes_frais',
                'passeport','comite','publier','assemblees','annuaire','parcours');

-- On ne délègue jamais ce qui touche à l'argent au-delà du dépôt, à la
-- discipline, aux droits ou aux actes.
update applications set delegable_local = false
 where code in ('habilitations','discipline','conformite','tresorerie',
                'ordonnancement','budget','cabinet','validation','chancellerie',
                'affaires_publiques','pilotage','rapport','ressources');

create or replace function puis_je_ouvrir_acces(p_app text, p_profil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() or a_droit('acces.piloter') then true
    when not (a_droit('habilitations.local') or mon_niveau() >= 50) then false
    when not puis_je_agir_sur(p_profil) then false
    when not dans_mon_perimetre(
           (select territoire_id from profils where id = p_profil)) then false
    -- Le national décide de ce qui est délégable.
    when not coalesce((select delegable_local from applications where code = p_app), false)
      then false
    when exists (select 1 from applications a join droits d on d.code = a.droit_requis
                 where a.code = p_app and d.sensible) then false
    -- Et l'on ne donne que ce dont on dispose soi-même.
    else source_acces(p_app) in ('admin','nominatif','poste','fonction')
  end;
$$;

-- Ce qu'un responsable local peut ouvrir, et à qui : l'écran s'y limite,
-- la base revérifie.
drop function if exists applications_delegables();
create or replace function applications_delegables()
returns table (code text, nom text, nom_court text, description text,
               ouvrable boolean, motif text)
language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.nom_court, a.description,
         a.delegable_local and source_acces(a.code)
           in ('admin','nominatif','poste','fonction'),
         case
           when not a.delegable_local
             then 'Le national ne délègue pas cette application.'
           when source_acces(a.code) not in ('admin','nominatif','poste','fonction')
             then 'Vous n''y avez pas accès vous-même : on ne donne que ce qu''on a.'
           else 'Vous pouvez l''ouvrir aux membres de votre périmètre.' end
  from applications a
  where a.actif
  order by a.delegable_local desc, a.ordre;
$$;

-- Qui a quoi, dans mon périmètre. Le portail de gestion locale part de
-- là : voir avant de décider.
drop function if exists acces_du_perimetre(uuid);
create or replace function acces_du_perimetre(p_territoire uuid default null)
returns table (profil_id uuid, membre text, matricule text, fonction text,
               niveau integer, territoire text, statut text,
               applications text[], postes text[], echelon text)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, f.nom, f.niveau,
         t.nom, p.statut,
         coalesce(array(select a.nom_court from applications a
                        where a.actif
                          and source_acces(a.code, p.id)
                              in ('admin','nominatif','poste','fonction')
                        order by a.ordre), '{}'),
         coalesce(array(select po.nom from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = p.id and nomination_active(n)), '{}'),
         e.nom
  from profils p
  join fonctions f on f.code = p.fonction
  join echelons e on e.niveau = p.echelon
  left join territoires t on t.id = p.territoire_id
  where p.statut <> 'archive'
    and dans_mon_perimetre(p.territoire_id)
    and (p_territoire is null or p.territoire_id in
         (select s.id from territoires_sous(p_territoire) s))
    and (est_admin() or mon_niveau() >= 40)
  order by f.niveau desc, p.nom;
$$;

-- ---------------------------------------------------------------------
-- 3. LES ACTES LOCAUX
--    Un acte local ne s'affiche qu'aux adhérents du périmètre. Un acte
--    fédéral s'affiche à tous. La portée n'est pas une décoration :
--    c'est ce qui décide de la lecture.
-- ---------------------------------------------------------------------

alter table actes_internes add column if not exists portee text not null default 'federale';
alter table actes_internes drop constraint if exists actes_internes_portee_check;
alter table actes_internes add constraint actes_internes_portee_check
  check (portee in ('federale','locale'));

insert into droits (code, nom, categorie, sensible, ordre) values
  ('actes.local', 'Prendre des actes au nom de sa structure', 'Présidence', false, 405)
on conflict (code) do update set nom = excluded.nom;

insert into poste_droits (poste, droit) values
  ('president_structure', 'actes.local')
on conflict do nothing;

create or replace function puis_je_prendre_acte(p_territoire uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('actes.prendre') or a_droit('cabinet.arbitrer')
      or (a_droit('actes.local')
          and p_territoire is not null and dans_mon_perimetre(p_territoire));
$$;

create or replace function prendre_acte(
  p_type text, p_objet text, p_visas text default null,
  p_considerants text default null, p_articles jsonb default '[]'::jsonb,
  p_destinataire uuid default null, p_poste text default null,
  p_effet date default null, p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_national boolean; v_portee text; v_rang integer;
begin
  v_national := est_admin() or a_droit('actes.prendre') or a_droit('cabinet.arbitrer');
  v_portee := case when v_national then 'federale' else 'locale' end;

  if not (v_national or (a_droit('actes.local')
          and p_territoire is not null and dans_mon_perimetre(p_territoire))) then
    return jsonb_build_object('ok', false,
      'message', 'Les actes se prennent au cabinet, ou par la présidence d''une structure pour son ressort.');
  end if;
  if not v_national and p_territoire is null then
    return jsonb_build_object('ok', false,
      'message', 'Un acte local porte sur un territoire : indiquez lequel.');
  end if;
  if coalesce(trim(p_objet),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un acte a un objet.');
  end if;
  if jsonb_array_length(coalesce(p_articles,'[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false,
      'message', 'Un acte sans article ne décide rien. Écrivez au moins un article.');
  end if;
  if p_type = 'nomination' and (p_destinataire is null or p_poste is null) then
    return jsonb_build_object('ok', false,
      'message', 'Un acte de nomination désigne une personne et un poste.');
  end if;

  -- Une présidence de structure ne se confère pas localement : elle est
  -- annoncée par l'échelon régional ou national. Sans cette règle, une
  -- présidence pourrait se reconduire elle-même par acte.
  if not v_national and p_type = 'nomination' then
    select rang into v_rang from postes where code = p_poste;
    if p_poste = 'president_structure' or coalesce(v_rang, 100) >= mon_plafond_nomination() then
      return jsonb_build_object('ok', false,
        'message', 'Ce poste est annoncé par l''échelon supérieur : il ne se confère pas localement.');
    end if;
    if poste_sensible(p_poste) then
      return jsonb_build_object('ok', false,
        'message', 'Ce poste ouvre des droits sensibles : seule la direction le confère.');
    end if;
  end if;

  insert into actes_internes (territoire_id, auteur_id, type, objet, visas,
                              considerants, articles, destinataire_id,
                              poste_confie, prend_effet_le, portee)
  values (p_territoire, auth.uid(), p_type, trim(p_objet), nullif(trim(p_visas),''),
          nullif(trim(p_considerants),''), coalesce(p_articles,'[]'::jsonb),
          p_destinataire, p_poste, coalesce(p_effet, current_date), v_portee)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'portee', v_portee);
end $$;

-- Qui a pris l'acte le signe : le national par `actes.prendre`, la
-- présidence de structure par `actes.local` sur son propre acte.
create or replace function puis_je_signer_acte()
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('actes.prendre') or a_droit('actes.local');
$$;

drop policy if exists lire_actes_internes on actes_internes;
create policy lire_actes_internes on actes_internes for select using (
  est_admin() or a_droit('actes.recueil') or a_droit('cabinet.arbitrer')
  or auteur_id = auth.uid() or destinataire_id = auth.uid()
  or (statut in ('signe','notifie','abroge')
      and (portee = 'federale'
           or (territoire_id is not null and dans_mon_perimetre(territoire_id))))
);

drop function if exists recueil_actes(text);
create or replace function recueil_actes(p_filtre text default 'tous')
returns table (id uuid, reference text, type text, objet text, statut text,
               portee text, auteur text, auteur_fonction text, ressort text,
               destinataire text, poste_nom text, prend_effet_le date,
               signe_le timestamptz, abroge boolean, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.reference, a.type, a.objet, a.statut, a.portee,
         trim(au.prenom || ' ' || au.nom), f.nom,
         coalesce(t.nom, 'Toute la fédération'),
         trim(de.prenom || ' ' || de.nom),
         (select po.nom from postes po where po.code = a.poste_confie),
         a.prend_effet_le, a.signe_le, a.statut = 'abroge', a.cree_le
  from actes_internes a
  join profils au on au.id = a.auteur_id
  join fonctions f on f.code = au.fonction
  left join territoires t on t.id = a.territoire_id
  left join profils de on de.id = a.destinataire_id
  where (
      est_admin() or a_droit('actes.recueil') or a_droit('cabinet.arbitrer')
      or a.auteur_id = auth.uid() or a.destinataire_id = auth.uid()
      or (a.statut in ('signe','notifie','abroge')
          and (a.portee = 'federale'
               or (a.territoire_id is not null and dans_mon_perimetre(a.territoire_id))))
    )
    and case p_filtre
      when 'projets'    then a.statut = 'projet'
      when 'en_vigueur' then a.statut in ('signe','notifie')
      when 'miens'      then a.destinataire_id = auth.uid()
      when 'locaux'     then a.portee = 'locale'
      else true end
  order by a.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 4. LE PLAN DES TERRITOIRES
--    Ni carte ni dessin : un arbre, avec ce qui compte pour décider —
--    effectif, bureau constitué, activité. Rien n'est stocké.
-- ---------------------------------------------------------------------

drop function if exists plan_territoires();
create or replace function plan_territoires()
returns table (id uuid, parent_id uuid, echelle text, code text, nom text,
               etat text, academie text, profondeur integer, chemin text,
               effectif integer, encadrants integer, president text,
               tresorier text, enfants integer, dotation integer,
               derniere_activite timestamptz)
language sql stable security definer set search_path = public as $$
  with recursive arbre as (
    select t.id, t.parent_id, t.echelle, t.code, t.nom, t.etat, t.academie,
           0 as profondeur, t.nom::text as chemin
    from territoires t where t.parent_id is null
    union all
    select t.id, t.parent_id, t.echelle, t.code, t.nom, t.etat, t.academie,
           a.profondeur + 1, a.chemin || ' › ' || t.nom
    from territoires t join arbre a on a.id = t.parent_id
  )
  select a.id, a.parent_id, a.echelle, a.code, a.nom, a.etat, a.academie,
         a.profondeur, a.chemin,
         (select count(*)::int from profils p
          where p.territoire_id = a.id and p.statut = 'actif'),
         (select count(*)::int from profils p join fonctions f on f.code = p.fonction
          where p.territoire_id = a.id and p.statut = 'actif' and f.niveau >= 40),
         (select trim(pr.prenom || ' ' || pr.nom) from nominations n
          join profils pr on pr.id = n.profil_id
          where n.territoire_id = a.id and n.poste = 'president_structure'
            and nomination_active(n) limit 1),
         (select trim(pr.prenom || ' ' || pr.nom) from nominations n
          join profils pr on pr.id = n.profil_id
          where n.territoire_id = a.id and n.poste = 'tresorier_structure'
            and nomination_active(n) limit 1),
         (select count(*)::int from territoires e where e.parent_id = a.id),
         coalesce((select d.points_alloues + d.points_reportes + d.points_bonus
                   from dotations d where d.territoire_id = a.id
                     and d.annee = extract(year from current_date)::int), 0),
         (select max(p.cree_le) from profils p where p.territoire_id = a.id)
  from arbre a
  where est_admin() or mon_niveau() >= 60 or dans_mon_perimetre(a.id)
  order by a.chemin;
$$;

create or replace function fiche_territoire(p_territoire uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', t.id, 'nom', t.nom, 'code', t.code, 'echelle', t.echelle,
    'etat', t.etat, 'motif_etat', t.motif_etat, 'academie', t.academie,
    'siege', t.siege, 'courriel', t.courriel, 'telephone', t.telephone,
    'population', t.population, 'note', t.note, 'creee_le', t.cree_le_reel,
    'parent', (select p.nom from territoires p where p.id = t.parent_id),
    'parent_id', t.parent_id,
    'effectif', (select count(*)::int from profils x
                 where x.territoire_id = t.id and x.statut = 'actif'),
    'en_attente', (select count(*)::int from profils x
                   where x.territoire_id = t.id and x.statut = 'en_attente'),
    'encadrants', (select count(*)::int from profils x
                   join fonctions f on f.code = x.fonction
                   where x.territoire_id = t.id and x.statut = 'actif' and f.niveau >= 40),
    'bureau', coalesce((select jsonb_agg(jsonb_build_object(
                  'poste', po.nom, 'membre', trim(pr.prenom || ' ' || pr.nom),
                  'depuis', n.cree_le))
                from nominations n
                join postes po on po.code = n.poste
                join profils pr on pr.id = n.profil_id
                where n.territoire_id = t.id and nomination_active(n)), '[]'::jsonb),
    'enfants', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', e.id, 'nom', e.nom, 'echelle', e.echelle, 'etat', e.etat)
                  order by e.nom)
                from territoires e where e.parent_id = t.id), '[]'::jsonb),
    'points', solde_points(t.id),
    'actes_locaux', (select count(*)::int from actes_internes a
                     where a.territoire_id = t.id and a.portee = 'locale'
                       and a.statut in ('signe','notifie')))
  from territoires t
  where t.id = p_territoire
    and (est_admin() or mon_niveau() >= 40 or dans_mon_perimetre(t.id));
$$;

create or replace function regler_territoire(p_territoire uuid, d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('structure.creer')
          or (mon_niveau() >= 50 and dans_mon_perimetre(p_territoire))) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne réglez pas ce territoire.');
  end if;
  update territoires set
    nom       = coalesce(nullif(trim(d->>'nom'),''), nom),
    academie  = nullif(trim(d->>'academie'),''),
    siege     = nullif(trim(d->>'siege'),''),
    courriel  = nullif(trim(d->>'courriel'),''),
    telephone = nullif(trim(d->>'telephone'),''),
    population = case when d ? 'population'
                      then nullif(d->>'population','')::int else population end,
    note      = nullif(trim(d->>'note'),''),
    cree_le_reel = case when d ? 'creee_le'
                        then nullif(d->>'creee_le','')::date else cree_le_reel end
  where id = p_territoire;
  return jsonb_build_object('ok', true);
end $$;

-- Rattacher un territoire à un autre parent. Une boucle rendrait
-- l'arbre infini : on la refuse explicitement.
create or replace function rattacher_territoire(p_territoire uuid, p_parent uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('structure.creer')) then
    return jsonb_build_object('ok', false, 'message', 'Réservé au pilotage du réseau.');
  end if;
  if p_territoire = p_parent then
    return jsonb_build_object('ok', false,
      'message', 'Un territoire ne peut pas être son propre parent.');
  end if;
  if p_parent is not null and p_parent in (select s.id from territoires_sous(p_territoire) s) then
    return jsonb_build_object('ok', false,
      'message', 'Ce rattachement créerait une boucle : le parent visé dépend déjà de ce territoire.');
  end if;
  update territoires set parent_id = p_parent where id = p_territoire;
  return jsonb_build_object('ok', true);
end $$;

-- Fusionner deux territoires. Toutes les colonnes `territoire_id` du
-- schéma sont reportées, y compris celles des migrations futures : on
-- interroge le catalogue plutôt que d'énumérer une liste qui vieillira.
create or replace function fusionner_territoires(p_source uuid, p_cible uuid,
                                                 p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_n integer := 0;
begin
  if not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Une fusion de structures relève de l''administrateur.');
  end if;
  if p_source = p_cible then
    return jsonb_build_object('ok', false, 'message', 'Les deux territoires sont le même.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une fusion se motive.');
  end if;
  if exists (select 1 from territoires where parent_id = p_source) then
    return jsonb_build_object('ok', false,
      'message', 'Ce territoire a des territoires enfants : rattachez-les d''abord.');
  end if;

  for r in
    select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'territoire_id'
      and t.table_type = 'BASE TABLE' and c.table_name <> 'territoires'
  loop
    execute format('update %I set territoire_id = $1 where territoire_id = $2',
                   r.table_name) using p_cible, p_source;
    v_n := v_n + 1;
  end loop;

  update territoires set etat = 'dissoute',
         motif_etat = 'Fusionnée : ' || trim(p_motif)
   where id = p_source;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'fusion_territoire', p_source::text,
          jsonb_build_object('cible', p_cible, 'motif', trim(p_motif),
                             'tables', v_n));
  return jsonb_build_object('ok', true, 'tables', v_n);
end $$;

-- ---------------------------------------------------------------------
-- 5. LES ÉCHELONS SE RÈGLENT
--    Leur nom, leur seuil et ce qu'ils ouvrent étaient figés depuis le
--    socle. La chancellerie doit pouvoir les faire évoluer sans qu'on
--    y touche du code.
-- ---------------------------------------------------------------------

alter table echelons add column if not exists description text;
alter table echelons add column if not exists couleur text;

create or replace function regler_echelon(p_niveau integer, p_nom text,
                                          p_points integer, p_ouvre text default null,
                                          p_description text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_min integer; v_max integer;
begin
  if not (est_admin() or a_droit('chancellerie.bareme')) then
    return jsonb_build_object('ok', false,
      'message', 'Le barème des échelons relève de la chancellerie.');
  end if;
  if coalesce(trim(p_nom),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un échelon porte un nom.');
  end if;

  -- Les seuils doivent rester croissants, sans quoi la progression
  -- devient incompréhensible et certains échelons inatteignables.
  select max(points) into v_min from echelons where niveau < p_niveau;
  select min(points) into v_max from echelons where niveau > p_niveau;
  if v_min is not null and p_points <= v_min then
    return jsonb_build_object('ok', false,
      'message', 'Le seuil doit dépasser celui de l''échelon précédent (' || v_min || ').');
  end if;
  if v_max is not null and p_points >= v_max then
    return jsonb_build_object('ok', false,
      'message', 'Le seuil doit rester sous celui de l''échelon suivant (' || v_max || ').');
  end if;

  update echelons set nom = trim(p_nom), points = p_points,
         ouvre = nullif(trim(p_ouvre),''),
         description = nullif(trim(p_description),'')
   where niveau = p_niveau;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Échelon inconnu.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

drop function if exists bareme_echelons();
create or replace function bareme_echelons()
returns table (niveau integer, nom text, points integer, ouvre text,
               description text, membres integer)
language sql stable security definer set search_path = public as $$
  select e.niveau, e.nom, e.points, e.ouvre, e.description,
         (select count(*)::int from profils p
          where p.echelon = e.niveau and p.statut = 'actif')
  from echelons e order by e.niveau;
$$;

grant execute on function puis_je_ouvrir_acces(text, uuid), applications_delegables(),
                          acces_du_perimetre(uuid), puis_je_prendre_acte(uuid),
                          prendre_acte(text, text, text, text, jsonb, uuid, text, date, uuid),
                          puis_je_signer_acte(), recueil_actes(text),
                          plan_territoires(), fiche_territoire(uuid),
                          regler_territoire(uuid, jsonb),
                          rattacher_territoire(uuid, uuid),
                          fusionner_territoires(uuid, uuid, text),
                          regler_echelon(integer, text, integer, text, text),
                          bareme_echelons()
  to authenticated;

-- ---------------------------------------------------------------------
-- 6. L'APPLICATION DE GESTION LOCALE
-- ---------------------------------------------------------------------

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction,
                          direction_locale, ordre)
values ('gestion_locale', 'Gestion de la structure', 'Ma structure',
        'Fiche du territoire, accès du périmètre, actes locaux.',
        'Voir avant de décider.',
        50, false, 'bordeaux', 'dg', 'dvie', 22)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction, direction_locale = excluded.direction_locale;

insert into application_visibilite (application, fonction, etat)
select 'gestion_locale', f.code,
       case when f.niveau >= 50 then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do nothing;

insert into poste_applications (poste, application) values
  ('president_structure', 'gestion_locale'),
  ('secretaire_structure', 'gestion_locale')
on conflict do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 39
--
--  Vérifications :
--    select * from plan_territoires();
--    select fiche_territoire('<uuid>');
--    select code, ouvrable, motif from applications_delegables();
--    select * from bareme_echelons();
--
--  Sur la fusion : elle parcourt le catalogue des colonnes plutôt qu'une
--  liste écrite à la main. Une table ajoutée demain sera reprise sans
--  qu'on y pense — ce qui est exactement ce qu'on veut d'une opération
--  aussi rare et aussi lourde de conséquences.
--
--  Sur les actes locaux : la présidence de structure ne se confère pas
--  localement. Sans cette règle, une présidence pourrait se reconduire
--  elle-même par acte, et le contrôle de l'échelon supérieur
--  disparaîtrait sans que personne ne l'ait décidé.
-- =====================================================================
