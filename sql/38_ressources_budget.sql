-- =====================================================================
--   FFCE — Migration 38 — LES RESSOURCES REMISES D'APLOMB (CORRIGÉE)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CREATION PREALABLE DES TABLES ET COLONNES
-- ---------------------------------------------------------------------

create table if not exists dotations_exceptionnelles (
  id            uuid primary key default gen_random_uuid(),
  territoire_id uuid not null references territoires(id) on delete cascade,
  annee         integer not null,
  points        integer not null check (points <> 0),
  motif         text not null,
  campagne      text,          -- pour retrouver ensemble les dotations d'un même geste
  accorde_par   uuid references profils(id),
  cree_le       timestamptz not null default now()
);
create index if not exists idx_dotexc on dotations_exceptionnelles(territoire_id, annee);

alter table dotations_exceptionnelles enable row level security;
drop policy if exists lire_dotexc on dotations_exceptionnelles;
create policy lire_dotexc on dotations_exceptionnelles for select using (
  est_admin() or a_droit('stock.dotation') or dans_mon_perimetre(territoire_id));
grant select on dotations_exceptionnelles to authenticated;

alter table commandes add column if not exists direction text references directions(code);
alter table commandes add column if not exists adresse_livraison text;
alter table commandes add column if not exists destinataire text;

alter table articles_catalogue add column if not exists conditionnement text;
alter table articles_catalogue add column if not exists quantite_lot integer;
alter table articles_catalogue add column if not exists variantes text[];
alter table articles_catalogue add column if not exists variante_libelle text;

comment on column articles_catalogue.conditionnement is
  'Ce que représente une unité commandée : « lot de 500 », « paquet de 10 ».';
comment on column articles_catalogue.variantes is
  'Choix à faire à la commande : tailles, coloris. Null : aucun choix.';

alter table commande_lignes add column if not exists variante text;

-- ---------------------------------------------------------------------
-- 1. LE SOLDE DIT LA VÉRITÉ
-- ---------------------------------------------------------------------

create or replace function solde_points(p_territoire uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with t as (select coalesce(p_territoire,
      (select territoire_id from profils where id = auth.uid())) as id),
  d as (select * from dotations, t
        where dotations.territoire_id = t.id
          and dotations.annee = extract(year from current_date)),
  -- Dépensé : la commande est partie, les points ne reviendront pas.
  depense as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id
      and extract(year from c.cree_le) = extract(year from current_date)
      and c.statut in ('expediee','recue')),
  -- Engagé : réservé le temps de l'instruction, rendu si l'on refuse.
  engage as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id and c.statut in ('deposee','validee')),
  -- Ce qui a été accordé en cours d'année, hors calcul annuel.
  exceptionnel as (
    select coalesce(sum(x.points), 0)::int as n
    from dotations_exceptionnelles x, t
    where x.territoire_id = t.id
      and x.annee = extract(year from current_date)::int),
  total as (
    select coalesce((select points_alloues + points_reportes + points_bonus from d), 0)
           + (select n from exceptionnel) as n)
  select jsonb_build_object(
    'annee', extract(year from current_date)::int,
    'territoire', (select nom from territoires, t where territoires.id = t.id),
    'alloues', coalesce((select points_alloues from d), 0),
    'reportes', coalesce((select points_reportes from d), 0),
    'bonus', coalesce((select points_bonus from d), 0) + (select n from exceptionnel),
    'exceptionnel', (select n from exceptionnel),
    'total', (select n from total),
    'depenses', (select n from depense),
    'engages', (select n from engage),
    -- Ce qu'on peut encore commander : ni le dépensé, ni l'engagé.
    'disponible', (select n from total) - (select n from depense) - (select n from engage),
    'dotee', exists (select 1 from d) or (select n from exceptionnel) > 0);
$$;

-- ---------------------------------------------------------------------
-- 2. FONCTIONS DE DOTATION EXCEPTIONNELLE
-- ---------------------------------------------------------------------

create or replace function doter_exceptionnellement(
  p_points integer, p_motif text, p_portee text default 'territoires',
  p_territoires uuid[] default '{}', p_echelle text default null,
  p_campagne text default null, p_annee integer default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_annee integer; v_n integer := 0; v_t uuid;
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

  if v_n = 0 then
    return jsonb_build_object('ok', false,
      'message', 'Aucune structure active ne correspond à cette portée.');
  end if;
  return jsonb_build_object('ok', true, 'structures', v_n,
                            'points', v_n * p_points);
end $$;

drop function if exists dotations_exceptionnelles_recentes(integer);
create or replace function dotations_exceptionnelles_recentes(p_annee integer default null)
returns table (id uuid, territoire text, points integer, motif text,
               campagne text, accorde_par text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select x.id, t.nom, x.points, x.motif, x.campagne,
         trim(p.prenom || ' ' || p.nom), x.cree_le
  from dotations_exceptionnelles x
  join territoires t on t.id = x.territoire_id
  left join profils p on p.id = x.accorde_par
  where x.annee = coalesce(p_annee, extract(year from current_date)::int)
    and (est_admin() or a_droit('stock.dotation') or dans_mon_perimetre(x.territoire_id))
  order by x.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 3. COMMANDES ET PANIER
-- ---------------------------------------------------------------------

create or replace function ouvrir_panier(p_territoire uuid default null,
                                         p_direction text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_terr uuid; v_cmd uuid;
begin
  v_terr := coalesce(p_territoire, (select territoire_id from profils where id = auth.uid()));
  if v_terr is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun territoire de rattachement.');
  end if;
  if p_territoire is not null and not (dans_mon_perimetre(p_territoire) or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne commandez que dans votre périmètre.');
  end if;
  if p_direction is not null and not (est_admin() or a_droit('stock.national')
      or exists (select 1 from nominations n join postes po on po.code = n.poste
                 where n.profil_id = auth.uid() and nomination_active(n)
                   and po.direction = p_direction)) then
    return jsonb_build_object('ok', false,
      'message', 'Vous n''appartenez pas à cette direction.');
  end if;

  select id into v_cmd from commandes
   where demandeur_id = auth.uid() and statut = 'brouillon'
     and territoire_id = v_terr
     and coalesce(direction,'') = coalesce(p_direction,'')
   limit 1;
  if v_cmd is null then
    insert into commandes (territoire_id, demandeur_id, direction)
    values (v_terr, auth.uid(), p_direction) returning id into v_cmd;
  end if;
  return jsonb_build_object('ok', true, 'id', v_cmd);
end $$;

create or replace function deposer_commande(p_id uuid, p_motif text default null,
                                            p_adresse text default null,
                                            p_destinataire text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes; v_total integer; v_solde jsonb;
begin
  select * into c from commandes
   where id = p_id and demandeur_id = auth.uid() and statut = 'brouillon';
  if c is null then
    return jsonb_build_object('ok', false, 'message', 'Ce panier n''est plus modifiable.');
  end if;
  if not exists (select 1 from commande_lignes where commande_id = p_id) then
    return jsonb_build_object('ok', false, 'message', 'Votre panier est vide.');
  end if;
  if coalesce(trim(p_adresse),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Indiquez l''adresse de livraison : un colis sans adresse ne part pas.');
  end if;

  select coalesce(sum(points), 0) into v_total
    from commande_lignes where commande_id = p_id;
  v_solde := solde_points(c.territoire_id);
  if v_total > (v_solde->>'disponible')::int then
    return jsonb_build_object('ok', false,
      'message', 'Solde insuffisant : ' || (v_solde->>'disponible') ||
                 ' points disponibles pour ' || v_total || ' demandés.');
  end if;

  update commandes
     set statut = 'deposee', points_debites = v_total,
         motif = nullif(trim(p_motif),''),
         adresse_livraison = trim(p_adresse),
         destinataire = nullif(trim(p_destinataire),'')
   where id = p_id;
  return jsonb_build_object('ok', true, 'points', v_total);
end $$;

create or replace function retirer_commande(p_id uuid, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes;
begin
  select * into c from commandes where id = p_id;
  if c is null then
    return jsonb_build_object('ok', false, 'message', 'Commande introuvable.');
  end if;
  if c.statut in ('expediee','recue','annulee') then
    return jsonb_build_object('ok', false,
      'message', 'Cette commande est déjà partie : elle ne se retire plus.');
  end if;
  if not (c.demandeur_id = auth.uid() or est_admin() or a_droit('stock.national')) then
    return jsonb_build_object('ok', false, 'message', 'Cette commande n''est pas la vôtre.');
  end if;
  if c.demandeur_id <> auth.uid() and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Retirer la commande d''autrui se motive.');
  end if;

  update commandes
     set statut = 'annulee', motif_refus = nullif(trim(p_motif),''),
         traite_par = auth.uid(), traite_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. GESTION DES VARIANTES DANS LES COMMANDES
-- ---------------------------------------------------------------------

alter table commande_lignes drop constraint if exists commande_lignes_commande_id_article_id_key;
drop index if exists idx_cl_unique;
create unique index if not exists idx_cl_unique
  on commande_lignes (commande_id, article_id, coalesce(variante, ''));

create or replace function ajouter_au_panier(p_article uuid, p_quantite integer,
                                             p_variante text default null,
                                             p_commande uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cmd uuid; v_terr uuid; a articles_catalogue; v_deja int; v_res jsonb;
begin
  if not (a_droit('stock.tenir') or a_droit('invest.demander')
          or mon_niveau() >= 50 or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'La commande relève du bureau de votre structure.');
  end if;
  select * into a from articles_catalogue where id = p_article and actif;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Article introuvable.');
  end if;
  if a.variantes is not null and array_length(a.variantes, 1) > 0
     and (p_variante is null or not (p_variante = any (a.variantes))) then
    return jsonb_build_object('ok', false,
      'message', 'Choisissez ' || coalesce(lower(a.variante_libelle), 'une variante') || '.');
  end if;

  if p_commande is not null then
    select id, territoire_id into v_cmd, v_terr from commandes
     where id = p_commande and demandeur_id = auth.uid() and statut = 'brouillon';
    if v_cmd is null then
      return jsonb_build_object('ok', false, 'message', 'Panier introuvable.');
    end if;
  else
    v_res := ouvrir_panier(null, null);
    if not (v_res->>'ok')::boolean then return v_res; end if;
    v_cmd := uuid_valide(v_res->>'id');
    v_terr := (select territoire_id from commandes where id = v_cmd);
  end if;

  if a.plafond_annuel is not null then
    select coalesce(sum(cl.quantite), 0) into v_deja
      from commande_lignes cl join commandes c on c.id = cl.commande_id
     where cl.article_id = p_article and c.territoire_id = v_terr
       and c.statut not in ('annulee','refusee','brouillon')
       and extract(year from c.cree_le) = extract(year from current_date);
    if v_deja + p_quantite > a.plafond_annuel then
      return jsonb_build_object('ok', false,
        'message', 'Plafond annuel atteint pour cet article : ' || a.plafond_annuel ||
                   ' par an et par structure.');
    end if;
  end if;

  if exists (select 1 from commande_lignes
             where commande_id = v_cmd and article_id = p_article
               and coalesce(variante,'') = coalesce(p_variante,'')) then
    update commande_lignes
       set quantite = quantite + p_quantite,
           points = (quantite + p_quantite) * a.cout_points
     where commande_id = v_cmd and article_id = p_article
       and coalesce(variante,'') = coalesce(p_variante,'');
  else
    insert into commande_lignes (commande_id, article_id, quantite, points, variante)
    values (v_cmd, p_article, p_quantite, a.cout_points * p_quantite, p_variante);
  end if;

  return jsonb_build_object('ok', true, 'commande', v_cmd);
end $$;

-- ---------------------------------------------------------------------
-- 5. LES POSTES COMPTABLES ET AUTOMATISATION
-- ---------------------------------------------------------------------

insert into postes_comptables (code, libelle, sens, categorie, automatique, source, ordre) values
  ('215', 'Investissements et équipements', 'charge', 'Investissement', true,
          'Investissements ordonnancés ou reçus sur l''exercice', 105),
  ('6061','Matériel fourni par la fédération', 'charge', 'Fonctionnement', true,
          'Valeur des commandes au catalogue fédéral, expédiées sur l''exercice', 111),
  ('7061','Dotation fédérale en matériel', 'produit', 'Concours fédéraux', true,
          'Contrepartie du matériel fourni par la fédération', 45)
on conflict (code) do update
  set libelle = excluded.libelle, categorie = excluded.categorie,
      automatique = excluded.automatique, source = excluded.source;

create or replace function realise_automatique(p_exercice uuid, p_poste text)
returns numeric language sql stable security definer set search_path = public as $$
  with e as (select * from exercices where id = p_exercice),
  perimetre as (
    select case when (select territoire_id from e) is null then null
                else (select territoire_id from e) end as terr)
  select coalesce(case p_poste
    when '625' then (
      select sum(total_note(n.id)) from notes_frais n
      join profils p on p.id = n.profil_id
      cross join e
      where n.statut = 'payee' and n.mode_remboursement = 'virement'
        and n.payee_le::date between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '7541' then (
      select sum(total_note(n.id)) from notes_frais n
      join profils p on p.id = n.profil_id
      cross join e
      where n.statut = 'payee' and n.mode_remboursement = 'abandon_creance'
        and n.payee_le::date between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '870' then (
      select sum(en.heures_realisees) * (select taux_benevolat from e)
      from engagements en
      join profils p on p.id = en.profil_id
      cross join e
      where en.mois between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '860' then (
      select sum(en.heures_realisees) * (select taux_benevolat from e)
      from engagements en
      join profils p on p.id = en.profil_id
      cross join e
      where en.mois between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '215' then (
      select sum(i.montant) from investissements i
      cross join e
      where i.statut in ('ordonnancee','engagee','recue')
        and i.ordonnance_le::date between e.debut and e.fin
        and ((select terr from perimetre) is null
             or i.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '6061' then (
      select sum(cl.quantite * coalesce(a.valeur_euros, 0))
      from commande_lignes cl
      join commandes cd on cd.id = cl.commande_id
      join articles_catalogue a on a.id = cl.article_id
      cross join e
      where cd.statut in ('expediee','recue')
        and coalesce(cd.expediee_le, cd.cree_le::date) between e.debut and e.fin
        and ((select terr from perimetre) is null
             or cd.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    when '7061' then (
      select sum(cl.quantite * coalesce(a.valeur_euros, 0))
      from commande_lignes cl
      join commandes cd on cd.id = cl.commande_id
      join articles_catalogue a on a.id = cl.article_id
      cross join e
      where cd.statut in ('expediee','recue')
        and coalesce(cd.expediee_le, cd.cree_le::date) between e.debut and e.fin
        and ((select terr from perimetre) is null
             or cd.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    else 0 end, 0);
$$;

-- ---------------------------------------------------------------------
-- 6. ORDONNANCEMENT ET DROITS
-- ---------------------------------------------------------------------

create or replace function tableau_ordonnancement()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'notes', (select count(*)::int from notes_frais
              where statut = 'instruite' and est_ordonnateur()),
    'investissements', (select count(*)::int from investissements_a_traiter('a_ordonnancer')),
    'montant_notes', coalesce((select sum(total_note(n.id)) from notes_frais n
                               where n.statut = 'instruite' and est_ordonnateur()), 0),
    'montant_invest', coalesce((select sum(montant)
                                from investissements_a_traiter('a_ordonnancer')), 0));
$$;

grant execute on function solde_points(uuid), doter_exceptionnellement(integer, text, text, uuid[], text, text, integer),
                          dotations_exceptionnelles_recentes(integer),
                          ouvrir_panier(uuid, text),
                          deposer_commande(uuid, text, text, text),
                          retirer_commande(uuid, text),
                          ajouter_au_panier(uuid, integer, text, uuid),
                          realise_automatique(uuid, text), tableau_ordonnancement()
  to authenticated;
