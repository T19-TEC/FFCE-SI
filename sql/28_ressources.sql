-- =====================================================================
--  FFCE — Migration 28 — SUIVI GRADUÉ ET RESSOURCES
--
--  PREMIÈRE PARTIE — LE PARCOURS, CORRIGÉ
--  La liste était visible des échelons supérieurs, mais rien ne
--  distinguait « c'est à moi d'agir » de « je regarde ». Trois rôles
--  désormais : responsable, suivi, information — et la possibilité de
--  réaffecter ou d'interpeller l'accompagnant.
--
--  SECONDE PARTIE — LES RESSOURCES
--  Un inventaire par structure, une dotation annuelle en points, un
--  catalogue, et des demandes d'investissement qui passent par
--  l'ordonnateur comme toute dépense — mais visiblement identifiées
--  comme investissement, avec leur demandeur et leur justification.
--
--  Prérequis : 01 à 27.
-- =====================================================================

-- =====================================================================
--  PREMIÈRE PARTIE — PARCOURS
-- =====================================================================

-- Les interpellations adressées à l'accompagnant. Déclarée ici, avant
-- les fonctions qui la lisent.
create table if not exists alertes_parcours (
  id               uuid primary key default gen_random_uuid(),
  profil_concerne  uuid not null references profils(id) on delete cascade,
  destinataire_id  uuid references profils(id) on delete set null,
  auteur_id        uuid not null references profils(id) on delete cascade,
  message          text not null,
  nature           text not null default 'observation'
                     check (nature in ('observation','relance','proposition','reaffectation')),
  traite_le        timestamptz,
  reponse          text,
  cree_le          timestamptz not null default now()
);
create index if not exists idx_alertes_parcours on alertes_parcours(destinataire_id, traite_le);

-- Quel est mon rôle vis-à-vis de ce nouvel adhérent ?
create or replace function mon_role_parcours(p_profil uuid)
returns text language sql stable security definer set search_path = public as $$
  with c as (
    select pa.referent_id, p.territoire_id
    from parcours pa join profils p on p.id = pa.profil_id
    where pa.profil_id = p_profil)
  select case
    -- Je l'accompagne : c'est à moi d'agir.
    when (select referent_id from c) = auth.uid() then 'responsable'
    -- Personne ne l'accompagne et il est chez moi : à moi de désigner.
    when (select referent_id from c) is null
         and (est_admin() or a_droit('parcours.accueillir')
              or (mon_niveau() >= 50 and dans_mon_perimetre((select territoire_id from c))))
      then 'a_affecter'
    -- Je préside ou j'encadre son territoire : je suis le suivi.
    when exists (select 1 from nominations n, c
                 where n.profil_id = auth.uid() and nomination_active(n)
                   and n.territoire_id = c.territoire_id
                   and n.poste in ('president_structure','parcours_local'))
      then 'suivi'
    when mon_niveau() >= 50 and dans_mon_perimetre((select territoire_id from c))
      then 'suivi'
    -- Le national regarde tout, pour information.
    when est_admin() or a_droit('parcours.accueillir') or mon_niveau() >= 80
      then 'information'
    else null end;
$$;

-- La liste, avec le rôle de chacun sur chaque ligne.
drop function if exists nouveaux_a_repartir();
create or replace function nouveaux_a_repartir()
returns table (profil_id uuid, membre text, matricule text, email text,
               telephone text, territoire text, territoire_id uuid,
               inscrit_le timestamptz, jours integer, etape text, etape_rang integer,
               accompagnant text, accompagnant_id uuid, bureau_local boolean,
               mon_role text, priorite integer, alerte_ouverte boolean,
               derniere_note text)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, p.email, p.telephone,
         t.nom, p.territoire_id, pa.inscrit_le,
         extract(day from now() - pa.inscrit_le)::int,
         case
           when pa.premiere_mission_le is not null then 'Engagé'
           when pa.forme_le is not null then 'Formé'
           when pa.rdv_le is not null then 'Rendez-vous pris'
           when pa.contacte_le is not null then 'Contacté'
           when pa.valide_le is not null then 'Adhésion validée'
           when pa.dossier_complet_le is not null then 'Dossier complet'
           else 'Inscrit' end,
         case
           when pa.premiere_mission_le is not null then 6
           when pa.forme_le is not null then 5
           when pa.rdv_le is not null or pa.contacte_le is not null then 4
           when pa.valide_le is not null then 3
           when pa.dossier_complet_le is not null then 2
           else 1 end,
         trim(r.prenom || ' ' || r.nom), pa.referent_id,
         exists (select 1 from nominations n
                 where n.territoire_id = p.territoire_id and nomination_active(n)
                   and n.poste in ('president_structure','parcours_local')),
         mon_role_parcours(p.id),
         case
           when pa.referent_id is null
                and not exists (select 1 from nominations n
                                where n.territoire_id = p.territoire_id
                                  and nomination_active(n)
                                  and n.poste in ('president_structure','parcours_local'))
             then 1
           when pa.referent_id is null then 2
           when pa.contacte_le is null and pa.inscrit_le < now() - interval '7 days' then 3
           else 4 end,
         exists (select 1 from alertes_parcours ap
                 where ap.profil_concerne = p.id and ap.traite_le is null),
         (select split_part(pa.notes, E'\n', -1))
  from parcours pa
  join profils p on p.id = pa.profil_id
  left join territoires t on t.id = p.territoire_id
  left join profils r on r.id = pa.referent_id
  where pa.premiere_mission_le is null and pa.abandonne_le is null
    and p.statut <> 'archive'
    and mon_role_parcours(p.id) is not null
  order by 16, pa.inscrit_le;
$$;

-- Interpeller l'accompagnant : le suivi n'est pas la surveillance, mais
-- il doit pouvoir dire quelque chose.
create or replace function signaler_a_accompagnant(
  p_profil uuid, p_message text, p_nature text default 'observation')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_dest uuid; v_role text;
begin
  v_role := mon_role_parcours(p_profil);
  if v_role is null then
    return jsonb_build_object('ok', false, 'message', 'Ce dossier n''est pas dans votre périmètre.');
  end if;
  if coalesce(trim(p_message),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Écrivez ce que vous voulez signaler.');
  end if;

  select referent_id into v_dest from parcours where profil_id = p_profil;
  insert into alertes_parcours (profil_concerne, destinataire_id, auteur_id,
                                message, nature)
  values (p_profil, v_dest, auth.uid(), trim(p_message), coalesce(p_nature,'observation'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function repondre_alerte_parcours(p_id uuid, p_reponse text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update alertes_parcours
     set traite_le = now(), reponse = nullif(trim(p_reponse),'')
   where id = p_id and (destinataire_id = auth.uid() or est_admin());
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Cette alerte ne vous est pas adressée.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function mes_alertes_parcours()
returns table (id uuid, profil_concerne uuid, membre text, message text,
               nature text, auteur text, auteur_fonction text,
               cree_le timestamptz, traite_le timestamptz, reponse text)
language sql stable security definer set search_path = public as $$
  select ap.id, ap.profil_concerne, trim(c.prenom || ' ' || c.nom),
         ap.message, ap.nature, trim(a.prenom || ' ' || a.nom), f.nom,
         ap.cree_le, ap.traite_le, ap.reponse
  from alertes_parcours ap
  join profils c on c.id = ap.profil_concerne
  join profils a on a.id = ap.auteur_id
  join fonctions f on f.code = a.fonction
  where ap.destinataire_id = auth.uid() or ap.auteur_id = auth.uid()
     or (ap.destinataire_id is null and a_droit('parcours.accueillir'))
  order by ap.traite_le nulls first, ap.cree_le desc;
$$;

-- =====================================================================
--  SECONDE PARTIE — RESSOURCES
-- =====================================================================

insert into droits (code, nom, categorie, sensible, ordre) values
  ('stock.tenir',        'Tenir l''inventaire de sa structure',   'Ressources', false, 300),
  ('stock.national',     'Piloter les stocks et le catalogue',    'Ressources', false, 310),
  ('stock.dotation',     'Fixer les dotations en points',         'Ressources', true,  320),
  ('invest.demander',    'Demander un investissement',            'Ressources', false, 330),
  ('invest.instruire',   'Instruire les demandes d''investissement','Ressources', false, 340)
on conflict (code) do nothing;

-- La contrainte de couleur des postes datait de la migration 07, avant
-- que la charte complète ne soit intégrée. On l'aligne sur la palette
-- réelle plutôt que de rabattre les postes sur une teinte approximative.
alter table postes drop constraint if exists postes_couleur_check;
alter table postes add constraint postes_couleur_check
  check (couleur in ('neutre','or','bleu','vert','rouge',
                     'bordeaux','nuit','brun','action','framboise'));

insert into postes (code, nom, description, couleur, systeme, direction) values
  ('logistique', 'Direction de la logistique',
   'Tient le catalogue, les stocks nationaux et instruit les demandes d''investissement.',
   'brun', true, 'dfin')
on conflict (code) do update set description = excluded.description;

insert into poste_droits (poste, droit) values
  ('logistique','stock.national'), ('logistique','invest.instruire'),
  ('logistique','stock.tenir'),
  ('dg_finance','stock.dotation'), ('dg_finance','invest.instruire'),
  ('president_structure','stock.tenir'), ('president_structure','invest.demander'),
  ('tresorier_structure','stock.tenir'), ('tresorier_structure','invest.demander')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 1. LE CATALOGUE
-- ---------------------------------------------------------------------

create table if not exists categories_ressource (
  code    text primary key,
  nom     text not null,
  ordre   integer not null default 100
);

insert into categories_ressource (code, nom, ordre) values
  ('communication', 'Supports de communication', 10),
  ('vetements',     'Vêtements et identification', 20),
  ('materiel',      'Matériel d''animation', 30),
  ('bureautique',   'Fournitures de bureau', 40),
  ('technique',     'Matériel technique', 50),
  ('autre',         'Autre', 90)
on conflict (code) do nothing;

create table if not exists articles_catalogue (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null,
  nom           text not null,
  description   text,
  categorie     text not null references categories_ressource(code),
  cout_points   integer not null default 0,
  valeur_euros  numeric(10,2),          -- pour la comptabilité
  unite         text not null default 'unité',
  image         text,
  stock_national integer,               -- null = illimité (impression à la demande)
  seuil_alerte  integer default 10,
  plafond_annuel integer,               -- par structure, null = pas de plafond
  actif         boolean not null default true,
  ordre         integer not null default 100
);

insert into articles_catalogue (reference, nom, description, categorie,
                                cout_points, valeur_euros, unite, stock_national, ordre)
select v.r, v.n, v.d, v.c, v.p, v.e, v.u, v.s, v.o from (values
  ('COM-001','Cartes de visite (100)','Aux nom et fonction du membre, charte FFCE.',
   'communication', 15, 22.00, 'boîte de 100', null, 10),
  ('COM-002','Kakémono FFCE','Roll-up 85 × 200 cm, à déployer en événement.',
   'communication', 120, 95.00, 'unité', 25, 20),
  ('COM-003','Flyers de présentation (500)','Présentation de la fédération.',
   'communication', 25, 40.00, 'lot de 500', null, 30),
  ('COM-004','Affiches A3 (50)','Modèle personnalisable par territoire.',
   'communication', 18, 28.00, 'lot de 50', null, 40),
  ('VET-001','Chasuble FFCE','Identification en intervention. Tailles S à XXL.',
   'vetements', 20, 16.00, 'unité', 200, 50),
  ('VET-002','Badge nominatif','Avec matricule et fonction.',
   'vetements', 5, 4.50, 'unité', null, 60),
  ('MAT-001','Malle d''animation citoyenneté','Jeux et supports pour un atelier complet.',
   'materiel', 180, 150.00, 'malle', 15, 70),
  ('MAT-002','Jeu du parcours citoyen','Support d''animation, 8 à 30 joueurs.',
   'materiel', 45, 38.00, 'unité', 40, 80),
  ('BUR-001','Ramette de papier A4','80 g, blanc.',
   'bureautique', 3, 4.00, 'ramette', null, 90),
  ('TEC-001','Vidéoprojecteur portable','Prêt de longue durée, sur demande motivée.',
   'technique', 400, 320.00, 'unité', 8, 100)
) as v(r,n,d,c,p,e,u,s,o)
where not exists (select 1 from articles_catalogue);

-- ---------------------------------------------------------------------
-- 2. COMMANDES ET INVENTAIRE — LES TABLES
--    Déclarées avant les fonctions de calcul des points, qui les lisent.
-- ---------------------------------------------------------------------

create sequence if not exists seq_commande start 1;

create table if not exists commandes (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'CMD-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_commande')::text, 4, '0'),
  territoire_id uuid not null references territoires(id) on delete cascade,
  demandeur_id  uuid not null references profils(id) on delete cascade,
  motif         text,
  points_debites integer not null default 0,
  statut        text not null default 'brouillon' check (statut in
                  ('brouillon','deposee','validee','expediee','recue','refusee','annulee')),
  traite_par    uuid references profils(id),
  traite_le     timestamptz,
  motif_refus   text,
  expediee_le   date,
  transporteur  text,
  suivi         text,
  recue_le      date,
  cree_le       timestamptz not null default now()
);

create table if not exists commande_lignes (
  id          uuid primary key default gen_random_uuid(),
  commande_id uuid not null references commandes(id) on delete cascade,
  article_id  uuid not null references articles_catalogue(id) on delete restrict,
  quantite    integer not null default 1 check (quantite > 0),
  points      integer not null default 0,
  unique (commande_id, article_id)
);

create table if not exists inventaire (
  id            uuid primary key default gen_random_uuid(),
  territoire_id uuid not null references territoires(id) on delete cascade,
  article_id    uuid references articles_catalogue(id) on delete set null,
  libelle_libre text,                    -- pour ce qui n'est pas au catalogue
  quantite      integer not null default 0,
  etat          text not null default 'bon'
                  check (etat in ('neuf','bon','usage','a_remplacer','hors_service')),
  emplacement   text,
  origine       text not null default 'catalogue'
                  check (origine in ('catalogue','achat_local','don','investissement')),
  commande_id   uuid references commandes(id) on delete set null,
  valeur_euros  numeric(10,2),
  acquis_le     date,
  observation   text,
  maj_par       uuid references profils(id),
  maj_le        timestamptz not null default now(),
  unique (territoire_id, article_id)
);

-- ---------------------------------------------------------------------
-- 3. LA DOTATION EN POINTS
--    Une monnaie annuelle. Les règles de report se règlent par la
--    direction financière, pas dans le code.
-- ---------------------------------------------------------------------

create table if not exists regles_dotation (
  cle     text primary key,
  valeur  numeric(10,2) not null,
  libelle text not null,
  unite   text not null default 'points',
  ordre   integer not null default 100,
  maj_par uuid references profils(id),
  maj_le  timestamptz not null default now()
);

insert into regles_dotation (cle, valeur, libelle, unite, ordre) values
  ('base_structure',   200, 'Dotation de base par structure',        'points', 10),
  ('par_adherent',       5, 'Points supplémentaires par adhérent actif', 'points', 20),
  ('par_mission',       10, 'Points par mission accomplie l''an passé',  'points', 30),
  ('report_max_pct',    30, 'Part reportable d''une année sur l''autre', '%',     40),
  ('plafond_report',   150, 'Plafond du report, en points',          'points', 50),
  ('valeur_point',    1.00, 'Valeur comptable d''un point',           'euros',  60)
on conflict (cle) do nothing;

create table if not exists dotations (
  id            uuid primary key default gen_random_uuid(),
  territoire_id uuid not null references territoires(id) on delete cascade,
  annee         integer not null,
  points_alloues integer not null default 0,
  points_reportes integer not null default 0,
  points_bonus  integer not null default 0,
  motif_bonus   text,
  attribuee_le  timestamptz not null default now(),
  attribuee_par uuid references profils(id),
  unique (territoire_id, annee)
);

-- Le calcul de la dotation, selon les règles en vigueur.
create or replace function calculer_dotation(p_territoire uuid, p_annee integer)
returns jsonb language sql stable security definer set search_path = public as $$
  with r as (select cle, valeur from regles_dotation),
  effectif as (
    select count(*)::int as n from profils p
    where p.statut = 'actif'
      and p.territoire_id in (select s.id from territoires_sous(p_territoire) s)),
  missions_passees as (
    select count(*)::int as n from missions m
    where m.territoire_id = p_territoire
      and extract(year from coalesce(m.fin, m.debut)) = p_annee - 1
      and m.statut in ('complete','close')),
  precedente as (
    select d.points_alloues + d.points_reportes + d.points_bonus as total,
           coalesce((select sum(c.points_debites) from commandes c
                     where c.territoire_id = p_territoire
                       and extract(year from c.cree_le) = p_annee - 1
                       and c.statut <> 'annulee'), 0) as depense
    from dotations d where d.territoire_id = p_territoire and d.annee = p_annee - 1)
  select jsonb_build_object(
    'base', (select valeur from r where cle = 'base_structure')::int,
    'effectif', (select n from effectif),
    'points_effectif', ((select n from effectif)
                        * (select valeur from r where cle = 'par_adherent'))::int,
    'missions', coalesce((select n from missions_passees), 0),
    'points_missions', (coalesce((select n from missions_passees), 0)
                        * (select valeur from r where cle = 'par_mission'))::int,
    'reliquat', greatest(coalesce((select total - depense from precedente), 0), 0)::int,
    'report', least(
        greatest(coalesce((select total - depense from precedente), 0), 0)
          * (select valeur from r where cle = 'report_max_pct') / 100,
        (select valeur from r where cle = 'plafond_report'))::int,
    'total', ((select valeur from r where cle = 'base_structure')
              + (select n from effectif) * (select valeur from r where cle = 'par_adherent')
              + coalesce((select n from missions_passees), 0)
                * (select valeur from r where cle = 'par_mission')
              + least(
                  greatest(coalesce((select total - depense from precedente), 0), 0)
                    * (select valeur from r where cle = 'report_max_pct') / 100,
                  (select valeur from r where cle = 'plafond_report')))::int);
$$;

create or replace function attribuer_dotations(p_annee integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t record; d jsonb; v_n int := 0;
begin
  if not a_droit('stock.dotation') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  for t in select id from territoires
           where echelle in ('local','departement') and etat = 'active' loop
    d := calculer_dotation(t.id, p_annee);
    insert into dotations (territoire_id, annee, points_alloues, points_reportes,
                           attribuee_par)
    values (t.id, p_annee,
            (d->>'base')::int + (d->>'points_effectif')::int + (d->>'points_missions')::int,
            (d->>'report')::int, auth.uid())
    on conflict (territoire_id, annee) do update
      set points_alloues = excluded.points_alloues,
          points_reportes = excluded.points_reportes,
          attribuee_par = auth.uid(), attribuee_le = now();
    v_n := v_n + 1;
  end loop;
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'dotations_attribuees', p_annee::text,
          jsonb_build_object('structures', v_n));
  return jsonb_build_object('ok', true, 'structures', v_n);
end $$;

create or replace function regler_dotation(p_cle text, p_valeur numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('stock.dotation') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  update regles_dotation set valeur = p_valeur, maj_par = auth.uid(), maj_le = now()
   where cle = p_cle;
  return jsonb_build_object('ok', true);
end $$;

-- Mon solde de points, tel qu'il se calcule.
create or replace function solde_points(p_territoire uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with t as (select coalesce(p_territoire,
      (select territoire_id from profils where id = auth.uid())) as id),
  d as (select * from dotations, t
        where dotations.territoire_id = t.id
          and dotations.annee = extract(year from current_date)),
  depense as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id
      and extract(year from c.cree_le) = extract(year from current_date)
      and c.statut <> 'annulee'),
  engage as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id and c.statut in ('deposee','validee'))
  select jsonb_build_object(
    'annee', extract(year from current_date)::int,
    'territoire', (select nom from territoires, t where territoires.id = t.id),
    'alloues', coalesce((select points_alloues from d), 0),
    'reportes', coalesce((select points_reportes from d), 0),
    'bonus', coalesce((select points_bonus from d), 0),
    'total', coalesce((select points_alloues + points_reportes + points_bonus from d), 0),
    'depenses', (select n from depense),
    'engages', (select n from engage),
    'disponible', coalesce((select points_alloues + points_reportes + points_bonus from d), 0)
                  - (select n from depense),
    'dotee', exists (select 1 from d));
$$;

-- ---------------------------------------------------------------------
-- 4. LES COMMANDES — LES FONCTIONS
-- ---------------------------------------------------------------------

create or replace function ajouter_au_panier(p_article uuid, p_quantite integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cmd uuid; v_terr uuid; a articles_catalogue; v_deja int;
begin
  if not (a_droit('stock.tenir') or a_droit('invest.demander')
          or mon_niveau() >= 50 or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'La commande relève du bureau de votre structure.');
  end if;
  select * into a from articles_catalogue where id = p_article and actif;
  if a is null then return jsonb_build_object('ok', false, 'message', 'Article introuvable.'); end if;

  v_terr := (select territoire_id from profils where id = auth.uid());

  -- Le plafond annuel par structure, s'il existe.
  if a.plafond_annuel is not null then
    select coalesce(sum(cl.quantite), 0) into v_deja
      from commande_lignes cl join commandes c on c.id = cl.commande_id
     where cl.article_id = p_article and c.territoire_id = v_terr
       and c.statut not in ('annulee','refusee')
       and extract(year from c.cree_le) = extract(year from current_date);
    if v_deja + p_quantite > a.plafond_annuel then
      return jsonb_build_object('ok', false,
        'message', 'Plafond annuel atteint pour cet article : ' || a.plafond_annuel ||
                   ' par an et par structure.');
    end if;
  end if;

  select id into v_cmd from commandes
   where territoire_id = v_terr and demandeur_id = auth.uid() and statut = 'brouillon'
   limit 1;
  if v_cmd is null then
    insert into commandes (territoire_id, demandeur_id) values (v_terr, auth.uid())
    returning id into v_cmd;
  end if;

  insert into commande_lignes (commande_id, article_id, quantite, points)
  values (v_cmd, p_article, p_quantite, a.cout_points * p_quantite)
  on conflict (commande_id, article_id) do update
    set quantite = commande_lignes.quantite + p_quantite,
        points = (commande_lignes.quantite + p_quantite) * a.cout_points;

  update commandes set points_debites = (
    select coalesce(sum(points), 0) from commande_lignes where commande_id = v_cmd)
   where id = v_cmd;

  return jsonb_build_object('ok', true, 'commande', v_cmd);
end $$;

create or replace function deposer_commande(p_id uuid, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes; s jsonb;
begin
  select * into c from commandes where id = p_id and statut = 'brouillon';
  if c is null then return jsonb_build_object('ok', false, 'message', 'Commande introuvable.'); end if;
  if c.points_debites = 0 then
    return jsonb_build_object('ok', false, 'message', 'Votre panier est vide.');
  end if;

  s := solde_points(c.territoire_id);
  if not (s->>'dotee')::boolean then
    return jsonb_build_object('ok', false,
      'message', 'Votre structure n''a pas encore reçu sa dotation annuelle.');
  end if;
  if (s->>'disponible')::int < c.points_debites then
    return jsonb_build_object('ok', false,
      'message', 'Solde insuffisant : ' || (s->>'disponible') || ' points disponibles pour '
                 || c.points_debites || ' demandés.');
  end if;

  update commandes set statut = 'deposee', motif = nullif(trim(p_motif),'')
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function traiter_commande(p_id uuid, p_statut text,
                                            p_motif text default null,
                                            p_transporteur text default null,
                                            p_suivi text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes;
begin
  select * into c from commandes where id = p_id;
  if c is null then return jsonb_build_object('ok', false, 'message', 'Introuvable.'); end if;

  -- La réception se constate par la structure ; le reste par la logistique.
  if p_statut = 'recue' then
    if not (c.demandeur_id = auth.uid() or dans_mon_perimetre(c.territoire_id)) then
      return jsonb_build_object('ok', false, 'message', 'Ce n''est pas votre commande.');
    end if;
    update commandes set statut = 'recue', recue_le = current_date where id = p_id;
    -- Ce qui arrive entre dans l'inventaire de la structure.
    insert into inventaire (territoire_id, article_id, quantite, origine, commande_id)
    select c.territoire_id, cl.article_id, cl.quantite, 'catalogue', c.id
    from commande_lignes cl where cl.commande_id = c.id
    on conflict (territoire_id, article_id) do update
      set quantite = inventaire.quantite + excluded.quantite, maj_le = now();
    return jsonb_build_object('ok', true);
  end if;

  if not a_droit('stock.national') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la logistique.');
  end if;
  if p_statut = 'refusee' and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus doit être motivé.');
  end if;

  update commandes
     set statut = p_statut, traite_par = auth.uid(), traite_le = now(),
         motif_refus = case when p_statut = 'refusee' then trim(p_motif) end,
         expediee_le = case when p_statut = 'expediee' then current_date else expediee_le end,
         transporteur = coalesce(nullif(trim(p_transporteur),''), transporteur),
         suivi = coalesce(nullif(trim(p_suivi),''), suivi)
   where id = p_id;

  -- Le stock national se décrémente à l'expédition, pas avant.
  if p_statut = 'expediee' then
    update articles_catalogue a
       set stock_national = a.stock_national - cl.quantite
      from commande_lignes cl
     where cl.commande_id = p_id and cl.article_id = a.id
       and a.stock_national is not null;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. L'INVENTAIRE — LES FONCTIONS
-- ---------------------------------------------------------------------

create or replace function enregistrer_inventaire(
  p_id uuid, p_article uuid, p_libelle text, p_quantite integer,
  p_etat text, p_emplacement text, p_origine text default 'achat_local',
  p_valeur numeric default null, p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_terr uuid;
begin
  if not (a_droit('stock.tenir') or mon_niveau() >= 50 or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'L''inventaire est tenu par le bureau de la structure.');
  end if;
  v_terr := (select territoire_id from profils where id = auth.uid());

  if p_id is null then
    insert into inventaire (territoire_id, article_id, libelle_libre, quantite,
                            etat, emplacement, origine, valeur_euros, observation,
                            acquis_le, maj_par)
    values (v_terr, p_article, nullif(trim(p_libelle),''), coalesce(p_quantite,0),
            coalesce(p_etat,'bon'), nullif(trim(p_emplacement),''),
            coalesce(p_origine,'achat_local'), p_valeur,
            nullif(trim(p_observation),''), current_date, auth.uid())
    on conflict (territoire_id, article_id) do update
      set quantite = excluded.quantite, etat = excluded.etat,
          emplacement = excluded.emplacement, maj_par = auth.uid(), maj_le = now();
  else
    update inventaire set quantite = coalesce(p_quantite, quantite),
           etat = coalesce(p_etat, etat),
           emplacement = nullif(trim(p_emplacement),''),
           observation = nullif(trim(p_observation),''),
           valeur_euros = coalesce(p_valeur, valeur_euros),
           maj_par = auth.uid(), maj_le = now()
     where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Qui a quoi : la vue nationale.
create or replace function etat_ressources(p_territoire uuid default null)
returns table (territoire_id uuid, territoire text, echelle text,
               article text, reference text, categorie text,
               quantite integer, etat text, emplacement text,
               origine text, valeur numeric, maj_le timestamptz)
language sql stable security definer set search_path = public as $$
  select i.territoire_id, t.nom, t.echelle,
         coalesce(a.nom, i.libelle_libre), a.reference, cr.nom,
         i.quantite, i.etat, i.emplacement, i.origine,
         coalesce(i.valeur_euros, a.valeur_euros * i.quantite), i.maj_le
  from inventaire i
  join territoires t on t.id = i.territoire_id
  left join articles_catalogue a on a.id = i.article_id
  left join categories_ressource cr on cr.code = a.categorie
  where (a_droit('stock.national') or est_admin()
         or dans_mon_perimetre(i.territoire_id))
    and (p_territoire is null or i.territoire_id = p_territoire)
  order by t.nom, cr.ordre, coalesce(a.nom, i.libelle_libre);
$$;

-- ---------------------------------------------------------------------
-- 6. LES INVESTISSEMENTS
--    Une dépense d'équipement, demandée par une structure, instruite par
--    la logistique, ordonnancée comme toute dépense — mais visiblement
--    identifiée, avec son demandeur et sa justification.
-- ---------------------------------------------------------------------

create sequence if not exists seq_investissement start 1;

create table if not exists investissements (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'INV-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_investissement')::text, 4, '0'),
  territoire_id uuid references territoires(id) on delete set null,
  demandeur_id  uuid not null references profils(id) on delete cascade,
  intitule      text not null,
  justification text not null,          -- pourquoi c'est nécessaire
  usage_prevu   text,                   -- ce que cela permettra de faire
  beneficiaires integer,
  fournisseur   text,
  devis         text,                   -- fichier, dépôt privé
  montant       numeric(10,2) not null check (montant > 0),
  exercice_id   uuid references exercices(id) on delete set null,
  poste_budget  text references postes_comptables(code),
  mission_id    uuid references missions(id) on delete set null,
  projet_id     uuid references projets(id) on delete set null,
  statut        text not null default 'deposee' check (statut in
                  ('deposee','instruite','ordonnancee','engagee','recue','refusee','ajournee')),
  avis_logistique text,
  instruit_par  uuid references profils(id),
  instruit_le   timestamptz,
  ordonnance_par uuid references profils(id),
  ordonnance_le timestamptz,
  motif_refus   text,
  engage_le     date,
  recu_le       date,
  facture       text,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_invest_statut on investissements(statut, cree_le);

create or replace function demander_investissement(
  p_intitule text, p_justification text, p_usage text, p_montant numeric,
  p_fournisseur text default null, p_devis text default null,
  p_beneficiaires integer default null, p_mission uuid default null,
  p_projet uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('invest.demander') or mon_niveau() >= 50 or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'La demande d''investissement relève du bureau de votre structure.');
  end if;
  if coalesce(trim(p_justification),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi cet achat est nécessaire : c''est ce qui sera examiné.');
  end if;
  if coalesce(p_montant, 0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Indiquez le montant estimé.');
  end if;

  insert into investissements (territoire_id, demandeur_id, intitule, justification,
                               usage_prevu, montant, fournisseur, devis,
                               beneficiaires, mission_id, projet_id)
  values ((select territoire_id from profils where id = auth.uid()), auth.uid(),
          trim(p_intitule), trim(p_justification), nullif(trim(p_usage),''),
          p_montant, nullif(trim(p_fournisseur),''), nullif(p_devis,''),
          p_beneficiaires, p_mission, p_projet)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function instruire_investissement(
  p_id uuid, p_favorable boolean, p_avis text,
  p_poste text default null, p_exercice uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('invest.instruire') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la logistique ou aux finances.');
  end if;
  if coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Motivez votre avis.');
  end if;

  update investissements
     set statut = case when p_favorable then 'instruite' else 'refusee' end,
         avis_logistique = trim(p_avis), instruit_par = auth.uid(), instruit_le = now(),
         motif_refus = case when not p_favorable then trim(p_avis) end,
         poste_budget = coalesce(p_poste, poste_budget),
         exercice_id = coalesce(p_exercice, exercice_id)
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function ordonnancer_investissement(p_id uuid, p_ok boolean,
                                                      p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare i investissements;
begin
  if not est_ordonnateur() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''ordonnateur.');
  end if;
  select * into i from investissements where id = p_id;
  if i.statut <> 'instruite' then
    return jsonb_build_object('ok', false, 'message', 'Cette demande n''a pas été instruite.');
  end if;
  if i.demandeur_id = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez pas ordonnancer votre propre demande.');
  end if;
  if not p_ok and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus doit être motivé.');
  end if;

  update investissements
     set statut = case when p_ok then 'ordonnancee' else 'refusee' end,
         ordonnance_par = auth.uid(), ordonnance_le = now(),
         motif_refus = case when not p_ok then trim(p_motif) end
   where id = p_id;

  perform inscrire_acte(null, 'finance',
    'Investissement ' || i.reference || ' — ' ||
    (case when p_ok then 'ordonnancé' else 'refusé' end) || ' : ' || i.intitule,
    null, jsonb_build_object('montant', i.montant), false);
  return jsonb_build_object('ok', true);
end $$;

create or replace function receptionner_investissement(p_id uuid, p_facture text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare i investissements;
begin
  select * into i from investissements where id = p_id;
  if not (i.demandeur_id = auth.uid() or dans_mon_perimetre(i.territoire_id)
          or a_droit('invest.instruire')) then
    return jsonb_build_object('ok', false, 'message', 'Ce n''est pas votre demande.');
  end if;
  update investissements set statut = 'recue', recu_le = current_date,
         facture = coalesce(nullif(p_facture,''), facture)
   where id = p_id;

  -- Le bien entre à l'inventaire de la structure.
  insert into inventaire (territoire_id, libelle_libre, quantite, etat, origine,
                          valeur_euros, acquis_le, maj_par)
  values (i.territoire_id, i.intitule, 1, 'neuf', 'investissement',
          i.montant, current_date, auth.uid());
  return jsonb_build_object('ok', true);
end $$;

create or replace function investissements_a_traiter(p_filtre text default 'a_instruire')
returns table (id uuid, reference text, intitule text, justification text,
               usage_prevu text, montant numeric, fournisseur text, devis text,
               demandeur text, territoire text, beneficiaires integer,
               mission text, projet text, statut text, avis_logistique text,
               poste_budget text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id, i.reference, i.intitule, i.justification, i.usage_prevu,
         i.montant, i.fournisseur, i.devis,
         trim(p.prenom || ' ' || p.nom), t.nom, i.beneficiaires,
         m.titre, pj.titre, i.statut, i.avis_logistique,
         (select pc.libelle from postes_comptables pc where pc.code = i.poste_budget),
         i.cree_le
  from investissements i
  join profils p on p.id = i.demandeur_id
  left join territoires t on t.id = i.territoire_id
  left join missions m on m.id = i.mission_id
  left join projets pj on pj.id = i.projet_id
  where case p_filtre
    when 'a_instruire'   then i.statut = 'deposee' and a_droit('invest.instruire')
    when 'a_ordonnancer' then i.statut = 'instruite' and est_ordonnateur()
    when 'miennes'       then i.demandeur_id = auth.uid()
                              or dans_mon_perimetre(i.territoire_id)
    when 'toutes'        then a_droit('invest.instruire') or est_ordonnateur()
                              or est_admin()
    else false end
  order by i.cree_le;
$$;

-- ---------------------------------------------------------------------
-- 7. LE BUDGET D'UNE MISSION
--    Ce que coûte réellement une action : notes de frais, points
--    dépensés, investissements rattachés.
-- ---------------------------------------------------------------------

alter table missions add column if not exists budget_prevu numeric(10,2);

create or replace function budget_mission(p_mission uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mission', (select jsonb_build_object('titre', m.titre, 'debut', m.debut,
        'fin', m.fin, 'budget_prevu', m.budget_prevu,
        'participants', (select count(*) from mission_candidatures c
                         where c.mission_id = m.id and c.statut = 'retenu'))
      from missions m where m.id = p_mission),
    'heures', (select coalesce(sum(b.heures), 0) from bilans_mission b
               where b.mission_id = p_mission),
    'investissements', coalesce((
      select jsonb_agg(jsonb_build_object('intitule', i.intitule,
             'montant', i.montant, 'statut', i.statut))
      from investissements i where i.mission_id = p_mission), '[]'::jsonb),
    'total_investissements', (select coalesce(sum(i.montant), 0)
      from investissements i where i.mission_id = p_mission
        and i.statut in ('ordonnancee','engagee','recue')),
    'valorisation_benevolat', (
      select coalesce(sum(b.heures), 0) *
             coalesce((select taux_benevolat from exercices
                       where annee = extract(year from current_date)
                       and territoire_id is null limit 1), 12.5)
      from bilans_mission b where b.mission_id = p_mission));
$$;

-- ---------------------------------------------------------------------
-- 8. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table alertes_parcours     enable row level security;
alter table categories_ressource enable row level security;
alter table articles_catalogue   enable row level security;
alter table regles_dotation      enable row level security;
alter table dotations            enable row level security;
alter table commandes            enable row level security;
alter table commande_lignes      enable row level security;
alter table inventaire           enable row level security;
alter table investissements      enable row level security;

drop policy if exists lire_alertes_parcours on alertes_parcours;
create policy lire_alertes_parcours on alertes_parcours for select using (
  destinataire_id = auth.uid() or auteur_id = auth.uid()
  or est_admin() or a_droit('parcours.accueillir')
);

drop policy if exists lire_categories on categories_ressource;
create policy lire_categories on categories_ressource for select using (mon_niveau() >= 10);
drop policy if exists lire_catalogue on articles_catalogue;
create policy lire_catalogue on articles_catalogue for select using (mon_niveau() >= 10);
drop policy if exists gerer_catalogue on articles_catalogue;
create policy gerer_catalogue on articles_catalogue for all
  using (a_droit('stock.national')) with check (a_droit('stock.national'));

drop policy if exists lire_regles_dotation on regles_dotation;
create policy lire_regles_dotation on regles_dotation for select using (mon_niveau() >= 40);
drop policy if exists gerer_regles_dotation on regles_dotation;
create policy gerer_regles_dotation on regles_dotation for all
  using (a_droit('stock.dotation')) with check (a_droit('stock.dotation'));

drop policy if exists lire_dotations on dotations;
create policy lire_dotations on dotations for select using (
  dans_mon_perimetre(territoire_id) or a_droit('stock.national')
  or a_droit('stock.dotation') or est_admin()
);

drop policy if exists lire_commandes on commandes;
create policy lire_commandes on commandes for select using (
  demandeur_id = auth.uid() or dans_mon_perimetre(territoire_id)
  or a_droit('stock.national') or est_admin()
);
drop policy if exists lire_lignes_cmd on commande_lignes;
create policy lire_lignes_cmd on commande_lignes for select using (
  exists (select 1 from commandes c where c.id = commande_id
          and (c.demandeur_id = auth.uid() or dans_mon_perimetre(c.territoire_id)
               or a_droit('stock.national') or est_admin()))
);
drop policy if exists gerer_lignes_cmd on commande_lignes;
create policy gerer_lignes_cmd on commande_lignes for delete using (
  exists (select 1 from commandes c where c.id = commande_id
          and c.demandeur_id = auth.uid() and c.statut = 'brouillon')
);

drop policy if exists lire_inventaire on inventaire;
create policy lire_inventaire on inventaire for select using (
  dans_mon_perimetre(territoire_id) or a_droit('stock.national') or est_admin()
);
drop policy if exists gerer_inventaire on inventaire;
create policy gerer_inventaire on inventaire for all
  using (a_droit('stock.tenir') and dans_mon_perimetre(territoire_id))
  with check (a_droit('stock.tenir') and dans_mon_perimetre(territoire_id));

drop policy if exists lire_investissements on investissements;
create policy lire_investissements on investissements for select using (
  demandeur_id = auth.uid() or dans_mon_perimetre(territoire_id)
  or a_droit('invest.instruire') or est_ordonnateur() or est_admin()
);

grant select on alertes_parcours, categories_ressource, articles_catalogue,
                regles_dotation, dotations, commandes, commande_lignes,
                inventaire, investissements to authenticated;
grant insert, update, delete on articles_catalogue, commande_lignes,
                inventaire to authenticated;
grant update on regles_dotation to authenticated;

grant execute on function mon_role_parcours(uuid), nouveaux_a_repartir(),
                          signaler_a_accompagnant(uuid, text, text),
                          repondre_alerte_parcours(uuid, text), mes_alertes_parcours(),
                          calculer_dotation(uuid, integer),
                          attribuer_dotations(integer), regler_dotation(text, numeric),
                          solde_points(uuid), ajouter_au_panier(uuid, integer),
                          deposer_commande(uuid, text),
                          traiter_commande(uuid, text, text, text, text),
                          enregistrer_inventaire(uuid, uuid, text, integer, text,
                                                 text, text, numeric, text),
                          etat_ressources(uuid),
                          demander_investissement(text, text, text, numeric, text,
                                                  text, integer, uuid, uuid),
                          instruire_investissement(uuid, boolean, text, text, uuid),
                          ordonnancer_investissement(uuid, boolean, text),
                          receptionner_investissement(uuid, text),
                          investissements_a_traiter(text), budget_mission(uuid)
  to authenticated;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre)
values ('ressources', 'Ressources et matériel', 'Ressources',
        'Inventaire, catalogue, dotation en points et demandes d''investissement.',
        'Ce que nous avons, ce qu''il nous faut.',
        40, false, 'brun', 'dfin', 66)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction;

insert into application_visibilite (application, fonction, etat)
select 'ressources', f.code, case when f.niveau >= 40 then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do update
  set etat = case when (select niveau from fonctions
                        where code = application_visibilite.fonction) >= 40
                  then 'ouverte' else 'invisible' end;

-- =====================================================================
--  FIN DE LA MIGRATION 28
--
--  Vérifications :
--    select calculer_dotation('<territoire>', 2026);
--    select attribuer_dotations(2026);
--    select solde_points();
--    select * from etat_ressources();
--
--  Sur les points : c'est une monnaie annuelle. Le report se calcule
--  selon deux règles — un pourcentage du reliquat et un plafond
--  absolu — toutes deux réglables par la direction financière. Rien
--  n'est écrit en dur.
--
--  Sur les investissements : ils passent par l'ordonnateur comme toute
--  dépense, mais leur écran montre le demandeur, la justification,
--  l'usage prévu et le nombre de bénéficiaires. Ce n'est pas une note
--  de frais : c'est une décision d'équipement, et elle se motive.
-- =====================================================================
