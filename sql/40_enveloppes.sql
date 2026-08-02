-- =====================================================================
--  FFCE — Migration 40 — LES ENVELOPPES DE POINTS
--
--  Jusqu'ici les points n'appartenaient qu'à des territoires. Or une
--  direction dispose de moyens, et un responsable national — parcours
--  adhérent, affaires juridiques — se voit confier une enveloppe qu'il
--  répartit ensuite sur les projets qu'il retient.
--
--  On généralise donc le porteur de points : un territoire, une
--  direction, ou une personne. Et l'on ajoute le geste qui manquait :
--  affecter une part de son enveloppe à un projet, ce qui la verse à la
--  structure qui le porte.
--
--  Un transfert s'écrit en deux lignes, une négative chez celui qui
--  donne et une positive chez celui qui reçoit, réunies par un même
--  identifiant. Le solde de chacun n'est donc jamais stocké : c'est une
--  somme. Rien ne peut diverger, et le mouvement se lit des deux côtés.
--
--  Prérequis : 01 à 39.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE PORTEUR N'EST PLUS FORCÉMENT UN TERRITOIRE
-- ---------------------------------------------------------------------

alter table dotations_exceptionnelles alter column territoire_id drop not null;
alter table dotations_exceptionnelles add column if not exists direction text
  references directions(code) on delete cascade;
alter table dotations_exceptionnelles add column if not exists profil_id uuid
  references profils(id) on delete cascade;
alter table dotations_exceptionnelles add column if not exists projet_id uuid
  references projets(id) on delete set null;
alter table dotations_exceptionnelles add column if not exists transfert_id uuid;

-- Un porteur et un seul. Sans cette contrainte, une même dotation
-- pourrait être comptée deux fois.
alter table dotations_exceptionnelles drop constraint if exists dotexc_un_porteur;
alter table dotations_exceptionnelles add constraint dotexc_un_porteur check (
  (territoire_id is not null)::int + (direction is not null)::int
  + (profil_id is not null)::int = 1);

create index if not exists idx_dotexc_dir on dotations_exceptionnelles(direction, annee);
create index if not exists idx_dotexc_prof on dotations_exceptionnelles(profil_id, annee);

drop policy if exists lire_dotexc on dotations_exceptionnelles;
create policy lire_dotexc on dotations_exceptionnelles for select using (
  est_admin() or a_droit('stock.dotation')
  or (territoire_id is not null and dans_mon_perimetre(territoire_id))
  or profil_id = auth.uid()
  or (direction is not null and exists (
        select 1 from nominations n join postes po on po.code = n.poste
        where n.profil_id = auth.uid() and nomination_active(n)
          and po.direction = dotations_exceptionnelles.direction)));

-- ---------------------------------------------------------------------
-- 2. LE SOLDE D'UNE ENVELOPPE
--    Trois natures, une seule fonction. Le disponible est la somme
--    algébrique : ce qui a été reçu, moins ce qui a été redistribué.
-- ---------------------------------------------------------------------

create or replace function solde_enveloppe(p_nature text, p_ref text,
                                           p_annee integer default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with a as (select coalesce(p_annee, extract(year from current_date)::int) as n),
  mvt as (
    select x.points, x.transfert_id, x.projet_id
    from dotations_exceptionnelles x, a
    where x.annee = a.n
      and case p_nature
        when 'direction'  then x.direction = p_ref
        when 'profil'     then x.profil_id = uuid_valide(p_ref)
        when 'territoire' then x.territoire_id = uuid_valide(p_ref)
        else false end)
  select jsonb_build_object(
    'nature', p_nature,
    'annee', (select n from a),
    'recu', coalesce((select sum(points) from mvt where points > 0), 0)::int,
    'redistribue', coalesce((select -sum(points) from mvt where points < 0), 0)::int,
    'disponible', coalesce((select sum(points) from mvt), 0)::int,
    'affectations', (select count(*)::int from mvt where projet_id is not null));
$$;

-- Les enveloppes dont je dispose : la mienne, et celles des directions
-- où j'occupe un poste.
drop function if exists mes_enveloppes(integer);
create or replace function mes_enveloppes(p_annee integer default null)
returns table (nature text, ref text, libelle text, recu integer,
               redistribue integer, disponible integer)
language sql stable security definer set search_path = public as $$
  with a as (select coalesce(p_annee, extract(year from current_date)::int) as n),
  sources as (
    select 'profil'::text as nature, auth.uid()::text as ref,
           'Enveloppe personnelle'::text as libelle
    union all
    select 'direction', d.code, d.nom
    from directions d
    where d.actif and (est_admin() or exists (
      select 1 from nominations n join postes po on po.code = n.poste
      where n.profil_id = auth.uid() and nomination_active(n) and po.direction = d.code))
  )
  select s.nature, s.ref, s.libelle,
         (solde_enveloppe(s.nature, s.ref, (select n from a))->>'recu')::int,
         (solde_enveloppe(s.nature, s.ref, (select n from a))->>'redistribue')::int,
         (solde_enveloppe(s.nature, s.ref, (select n from a))->>'disponible')::int
  from sources s
  where (solde_enveloppe(s.nature, s.ref, (select n from a))->>'recu')::int <> 0
  order by 3;
$$;

-- ---------------------------------------------------------------------
-- 3. DOTER — TERRITOIRES, DIRECTIONS OU PERSONNES
-- ---------------------------------------------------------------------

create or replace function doter_exceptionnellement(
  p_points integer, p_motif text, p_portee text default 'territoires',
  p_territoires uuid[] default '{}', p_echelle text default null,
  p_campagne text default null, p_annee integer default null,
  p_directions text[] default '{}', p_profils uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_annee integer; v_n integer := 0; v_t uuid; v_d text;
begin
  if not (est_admin() or a_droit('stock.dotation')) then
    return jsonb_build_object('ok', false,
      'message', 'Les dotations relèvent de la direction financière.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une dotation exceptionnelle se motive : sans motif, c''est un privilège.');
  end if;
  if coalesce(p_points, 0) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Indiquez un nombre de points.');
  end if;
  v_annee := coalesce(p_annee, extract(year from current_date)::int);

  if p_portee = 'directions' then
    foreach v_d in array coalesce(p_directions, '{}') loop
      if exists (select 1 from directions where code = v_d and actif) then
        insert into dotations_exceptionnelles (direction, annee, points, motif,
                                               campagne, accorde_par)
        values (v_d, v_annee, p_points, trim(p_motif),
                nullif(trim(p_campagne),''), auth.uid());
        v_n := v_n + 1;
      end if;
    end loop;

  elsif p_portee = 'responsables' then
    foreach v_t in array coalesce(p_profils, '{}') loop
      -- Une enveloppe personnelle se confie à quelqu'un qui encadre :
      -- elle sert à répartir, pas à consommer.
      if exists (select 1 from profils p join fonctions f on f.code = p.fonction
                 where p.id = v_t and p.statut = 'actif' and f.niveau >= 40) then
        insert into dotations_exceptionnelles (profil_id, annee, points, motif,
                                               campagne, accorde_par)
        values (v_t, v_annee, p_points, trim(p_motif),
                nullif(trim(p_campagne),''), auth.uid());
        v_n := v_n + 1;
      end if;
    end loop;

  else
    for v_t in
      select t.id from territoires t
      where t.etat = 'active'
        and case p_portee
          when 'territoires' then t.id = any (coalesce(p_territoires, '{}'))
          when 'echelle'     then t.echelle = p_echelle
          when 'reseau'      then t.echelle in ('region','departement','local')
          else false end
    loop
      insert into dotations_exceptionnelles (territoire_id, annee, points, motif,
                                             campagne, accorde_par)
      values (v_t, v_annee, p_points, trim(p_motif),
              nullif(trim(p_campagne),''), auth.uid());
      v_n := v_n + 1;
    end loop;
  end if;

  if v_n = 0 then
    return jsonb_build_object('ok', false,
      'message', 'Aucun bénéficiaire ne correspond à cette portée.');
  end if;
  return jsonb_build_object('ok', true, 'beneficiaires', v_n,
                            'points', v_n * p_points);
end $$;

-- ---------------------------------------------------------------------
-- 4. AFFECTER À UN PROJET
--    Le geste que la fédération attendait : un responsable ou une
--    direction met une part de son enveloppe sur un projet retenu, et
--    les points arrivent à la structure qui le porte.
-- ---------------------------------------------------------------------

create or replace function affecter_points_projet(
  p_nature text, p_ref text, p_projet uuid, p_points integer, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v_dispo integer; v_terr uuid; v_titre text;
        v_transfert uuid; v_annee integer;
begin
  v_annee := extract(year from current_date)::int;

  -- Qui dispose de l'enveloppe ? Soi-même, ou sa direction.
  v_ok := case p_nature
    when 'profil'    then uuid_valide(p_ref) = auth.uid() or est_admin()
    when 'direction' then est_admin() or exists (
      select 1 from nominations n join postes po on po.code = n.poste
      where n.profil_id = auth.uid() and nomination_active(n) and po.direction = p_ref)
    else false end;
  if not v_ok then
    return jsonb_build_object('ok', false,
      'message', 'Cette enveloppe n''est pas la vôtre.');
  end if;
  if coalesce(p_points, 0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Indiquez un nombre de points positif.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi ce projet : c''est ce qui justifie l''affectation.');
  end if;

  select territoire_id, titre into v_terr, v_titre from projets where id = p_projet;
  if v_terr is null then
    return jsonb_build_object('ok', false, 'message', 'Projet introuvable.');
  end if;

  v_dispo := (solde_enveloppe(p_nature, p_ref, v_annee)->>'disponible')::int;
  if p_points > v_dispo then
    return jsonb_build_object('ok', false,
      'message', 'Votre enveloppe ne dispose que de ' || v_dispo || ' points.');
  end if;

  v_transfert := gen_random_uuid();

  -- La ligne négative, chez celui qui donne.
  insert into dotations_exceptionnelles (territoire_id, direction, profil_id, annee,
                                         points, motif, projet_id, transfert_id,
                                         accorde_par)
  values (case when p_nature = 'territoire' then uuid_valide(p_ref) end,
          case when p_nature = 'direction' then p_ref end,
          case when p_nature = 'profil' then uuid_valide(p_ref) end,
          v_annee, -p_points,
          'Affecté au projet « ' || v_titre || ' » : ' || trim(p_motif),
          p_projet, v_transfert, auth.uid());

  -- La ligne positive, chez la structure qui porte le projet.
  insert into dotations_exceptionnelles (territoire_id, annee, points, motif,
                                         projet_id, transfert_id, accorde_par)
  values (v_terr, v_annee, p_points,
          'Projet « ' || v_titre || ' » : ' || trim(p_motif),
          p_projet, v_transfert, auth.uid());

  return jsonb_build_object('ok', true, 'points', p_points,
                            'restant', v_dispo - p_points);
end $$;

-- Ce qu'un projet a reçu, et de qui.
drop function if exists soutiens_projet(uuid);
create or replace function soutiens_projet(p_projet uuid)
returns table (points integer, motif text, origine text, accorde_par text,
               cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select x.points, x.motif,
         coalesce(d.nom, trim(pr.prenom || ' ' || pr.nom), t.nom, 'Fédération'),
         trim(a.prenom || ' ' || a.nom), x.cree_le
  from dotations_exceptionnelles x
  left join directions d on d.code = x.direction
  left join profils pr on pr.id = x.profil_id
  left join territoires t on t.id = x.territoire_id
  left join profils a on a.id = x.accorde_par
  where x.projet_id = p_projet and x.points < 0
  order by x.cree_le desc;
$$;

-- Les projets sur lesquels je peux affecter : ceux de mon ressort, ou
-- tous si je porte une enveloppe nationale.
drop function if exists projets_a_soutenir(text);
create or replace function projets_a_soutenir(p_filtre text default 'tous')
returns table (id uuid, reference text, titre text, objet text, territoire text,
               statut text, debut date, budget_estime numeric, responsable text,
               points_recus integer)
language sql stable security definer set search_path = public as $$
  select p.id, p.reference, p.titre, p.objet, t.nom, p.statut, p.debut,
         p.budget_estime, trim(r.prenom || ' ' || r.nom),
         coalesce((select sum(x.points)::int from dotations_exceptionnelles x
                   where x.projet_id = p.id and x.points > 0), 0)
  from projets p
  join territoires t on t.id = p.territoire_id
  left join profils r on r.id = p.responsable_id
  where p.statut in ('preparation','en_cours')
    and (est_admin() or mon_niveau() >= 60 or dans_mon_perimetre(p.territoire_id))
    and case p_filtre
      when 'sans_soutien' then not exists (
        select 1 from dotations_exceptionnelles x
        where x.projet_id = p.id and x.points > 0)
      else true end
  order by p.debut nulls last, p.titre;
$$;

-- ---------------------------------------------------------------------
-- 5. LE SOLDE D'UN TERRITOIRE INTÈGRE LES TRANSFERTS
--    Une affectation de projet est une dotation exceptionnelle comme
--    une autre : elle est déjà comptée. Rien à changer — sinon d'écarter
--    du solde territorial les lignes qui appartiennent à une direction
--    ou à une personne, ce que la contrainte de porteur garantit déjà.
--
--    Le seuil du plan du réseau passe de 60 à 80 : voir tout le réseau
--    relève du national, non d'un échelon régional.
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
                     and d.annee = extract(year from current_date)::int), 0)
         + coalesce((select sum(x.points)::int from dotations_exceptionnelles x
                     where x.territoire_id = a.id
                       and x.annee = extract(year from current_date)::int), 0),
         (select max(p.cree_le) from profils p where p.territoire_id = a.id)
  from arbre a
  -- Voir tout le réseau relève du national. En dessous, on voit le sien.
  where est_admin() or mon_niveau() >= 80 or dans_mon_perimetre(a.id)
  order by a.chemin;
$$;

grant execute on function solde_enveloppe(text, text, integer),
                          mes_enveloppes(integer),
                          doter_exceptionnellement(integer, text, text, uuid[], text, text, integer, text[], uuid[]),
                          affecter_points_projet(text, text, uuid, integer, text),
                          soutiens_projet(uuid), projets_a_soutenir(text),
                          plan_territoires()
  to authenticated;

-- L'ancienne signature à sept paramètres disparaît : deux fonctions de
-- même nom rendraient l'appel ambigu.
drop function if exists doter_exceptionnellement(integer, text, text, uuid[], text, text, integer);

-- =====================================================================
--  FIN DE LA MIGRATION 40
--
--  Vérifications :
--    select * from mes_enveloppes();
--    select solde_enveloppe('direction', 'dg');
--    select * from projets_a_soutenir('sans_soutien');
--
--  Sur le transfert en deux lignes : il évite de stocker un solde, donc
--  d'avoir un solde faux. Il rend aussi le mouvement lisible des deux
--  côtés — celui qui donne voit ce qu'il lui reste, celui qui reçoit
--  voit d'où cela vient et pourquoi. Un compteur unique aurait perdu
--  l'une des deux moitiés.
--
--  Sur l'enveloppe personnelle : elle n'est confiée qu'à partir du
--  niveau 40. Elle sert à répartir, jamais à consommer : un responsable
--  ne commande pas avec, il affecte à des projets.
-- =====================================================================
