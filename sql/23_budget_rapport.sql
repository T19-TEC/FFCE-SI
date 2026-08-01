-- =====================================================================
--  FFCE — Migration 23 — BUDGET ET RAPPORT D'ACTIVITÉ
--
--  Deux documents que toute association doit produire, et que presque
--  toutes reconstituent à la main chaque année dans la douleur.
--
--  Or les données sont déjà là : notes de frais payées, heures données,
--  missions accomplies, formations délivrées, projets menés. Le budget
--  et le rapport se remplissent donc d'eux-mêmes autant que possible,
--  et la direction ne saisit que ce que le système ignore — les
--  subventions, les cotisations, les dons.
--
--  Contenu : plan comptable simplifié, exercices, budget prévisionnel,
--  réalisé automatique, compte de résultat, rapport d'activité,
--  exports, et rappel mensuel de sauvegarde.
--
--  Prérequis : 01 à 22.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DROITS ET APPLICATION
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('budget.tenir',    'Tenir le budget et les comptes',      'Finances', false, 112),
  ('budget.arreter',  'Arrêter les comptes d''un exercice',  'Finances', true,  114),
  ('rapport.rediger', 'Rédiger le rapport d''activité',      'Contenus', false, 175)
on conflict (code) do nothing;

insert into poste_droits (poste, droit) values
  ('dg_finance','budget.tenir'), ('dg_finance','budget.arreter'),
  ('tresorier_structure','budget.tenir'),
  ('delegue_admin','rapport.rediger')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2. PLAN COMPTABLE SIMPLIFIÉ
--    Assez fidèle au plan associatif pour qu'un expert-comptable s'y
--    retrouve, assez court pour qu'un trésorier bénévole s'en serve.
-- ---------------------------------------------------------------------

create table if not exists postes_comptables (
  code      text primary key,
  libelle   text not null,
  sens      text not null check (sens in ('produit','charge')),
  categorie text not null,
  automatique boolean not null default false,  -- alimenté par la plateforme
  source    text,                              -- d'où viennent les montants
  ordre     integer not null default 100,
  actif     boolean not null default true
);

insert into postes_comptables (code, libelle, sens, categorie, automatique, source, ordre) values
  -- Produits
  ('706', 'Cotisations des adhérents',        'produit', 'Ressources propres', false, null, 10),
  ('754', 'Dons et mécénat',                  'produit', 'Ressources propres', false, null, 20),
  ('7541','Abandons de frais par les bénévoles','produit','Ressources propres', true,
          'Notes de frais réglées en abandon de créance', 25),
  ('740', 'Subventions publiques',            'produit', 'Concours publics', false, null, 30),
  ('7401','Subventions de l''État',           'produit', 'Concours publics', false, null, 31),
  ('7402','Subventions des collectivités',    'produit', 'Concours publics', false, null, 32),
  ('756', 'Partenariats privés',              'produit', 'Partenariats',      false, null, 40),
  ('758', 'Autres produits',                  'produit', 'Autres',            false, null, 50),
  ('870', 'Bénévolat valorisé',               'produit', 'Contributions volontaires', true,
          'Heures déclarées au barème horaire', 60),
  -- Charges
  ('606', 'Fournitures et petit matériel',    'charge', 'Fonctionnement', false, null, 110),
  ('613', 'Locations',                        'charge', 'Fonctionnement', false, null, 120),
  ('616', 'Assurances',                       'charge', 'Fonctionnement', false, null, 130),
  ('618', 'Documentation et formation',       'charge', 'Fonctionnement', false, null, 140),
  ('623', 'Communication et publications',    'charge', 'Actions',        false, null, 150),
  ('625', 'Déplacements et missions',         'charge', 'Actions',        true,
          'Notes de frais payées par virement', 160),
  ('626', 'Frais postaux et télécommunications','charge','Fonctionnement', false, null, 170),
  ('627', 'Services bancaires',               'charge', 'Fonctionnement', false, null, 180),
  ('628', 'Prestations et honoraires',        'charge', 'Fonctionnement', false, null, 190),
  ('641', 'Rémunérations',                    'charge', 'Personnel',      false, null, 200),
  ('645', 'Charges sociales',                 'charge', 'Personnel',      false, null, 210),
  ('658', 'Autres charges',                   'charge', 'Autres',         false, null, 220),
  ('860', 'Contributions volontaires en nature','charge','Contributions volontaires', true,
          'Contrepartie du bénévolat valorisé', 230)
on conflict (code) do update
  set libelle = excluded.libelle, categorie = excluded.categorie,
      automatique = excluded.automatique, source = excluded.source;

-- ---------------------------------------------------------------------
-- 3. EXERCICES
-- ---------------------------------------------------------------------

create table if not exists exercices (
  id            uuid primary key default gen_random_uuid(),
  annee         integer not null,
  territoire_id uuid references territoires(id) on delete cascade,
  debut         date not null,
  fin           date not null,
  statut        text not null default 'prevision' check (statut in
                  ('prevision','vote','en_cours','arrete','clos')),
  vote_le       date,
  arrete_le     date,
  arrete_par    uuid references profils(id),
  observations  text,
  taux_benevolat numeric(6,2) not null default 12.50,  -- € par heure
  cree_le       timestamptz not null default now(),
  unique (annee, territoire_id)
);

create table if not exists budget_lignes (
  id          uuid primary key default gen_random_uuid(),
  exercice_id uuid not null references exercices(id) on delete cascade,
  poste       text not null references postes_comptables(code),
  libelle     text,
  prevu       numeric(12,2) not null default 0,
  realise_saisi numeric(12,2) not null default 0,   -- ce que la plateforme ignore
  commentaire text,
  maj_par     uuid references profils(id),
  maj_le      timestamptz not null default now(),
  unique (exercice_id, poste)
);

create or replace function ouvrir_exercice(p_annee integer, p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not a_droit('budget.tenir') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if exists (select 1 from exercices where annee = p_annee
             and territoire_id is not distinct from p_territoire) then
    return jsonb_build_object('ok', false, 'message', 'Cet exercice existe déjà.');
  end if;

  insert into exercices (annee, territoire_id, debut, fin)
  values (p_annee, p_territoire,
          make_date(p_annee,1,1), make_date(p_annee,12,31))
  returning id into v_id;

  -- Toutes les lignes du plan, à zéro : on ne demande pas au trésorier
  -- de deviner quels postes existent.
  insert into budget_lignes (exercice_id, poste)
  select v_id, pc.code from postes_comptables pc where pc.actif;

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 4. LE RÉALISÉ, CALCULÉ DEPUIS LA PLATEFORME
-- ---------------------------------------------------------------------

create or replace function realise_automatique(p_exercice uuid, p_poste text)
returns numeric language sql stable security definer set search_path = public as $$
  with e as (select * from exercices where id = p_exercice),
  perimetre as (
    select case when (select territoire_id from e) is null then null
                else (select territoire_id from e) end as terr)
  select coalesce(case p_poste
    -- Déplacements : notes de frais payées par virement
    when '625' then (
      select sum(total_note(n.id)) from notes_frais n
      join profils p on p.id = n.profil_id
      cross join e
      where n.statut = 'payee' and n.mode_remboursement = 'virement'
        and n.payee_le::date between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    -- Abandons de frais : produit
    when '7541' then (
      select sum(total_note(n.id)) from notes_frais n
      join profils p on p.id = n.profil_id
      cross join e
      where n.statut = 'payee' and n.mode_remboursement = 'abandon_creance'
        and n.payee_le::date between e.debut and e.fin
        and ((select terr from perimetre) is null
             or p.territoire_id in (select s.id from territoires_sous(
                  (select terr from perimetre)) s)))
    -- Bénévolat valorisé, en produit comme en charge
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
    else 0 end, 0);
$$;

create or replace function budget_exercice(p_exercice uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with lignes as (
    select bl.id, bl.poste, pc.libelle, pc.sens, pc.categorie, pc.ordre,
           pc.automatique, pc.source, bl.libelle as intitule,
           bl.prevu, bl.realise_saisi, bl.commentaire,
           case when pc.automatique
                then realise_automatique(p_exercice, pc.code)
                else bl.realise_saisi end as realise
    from budget_lignes bl
    join postes_comptables pc on pc.code = bl.poste
    where bl.exercice_id = p_exercice and pc.actif),
  totaux as (
    select
      sum(prevu)   filter (where sens = 'produit' and categorie <> 'Contributions volontaires') as prod_prevu,
      sum(realise) filter (where sens = 'produit' and categorie <> 'Contributions volontaires') as prod_realise,
      sum(prevu)   filter (where sens = 'charge'  and categorie <> 'Contributions volontaires') as charg_prevu,
      sum(realise) filter (where sens = 'charge'  and categorie <> 'Contributions volontaires') as charg_realise,
      sum(realise) filter (where categorie = 'Contributions volontaires' and sens = 'produit') as benevolat
    from lignes)
  select jsonb_build_object(
    'exercice', (select to_jsonb(e) from exercices e where e.id = p_exercice),
    'lignes', coalesce((select jsonb_agg(to_jsonb(l) order by l.sens desc, l.ordre)
                        from lignes l), '[]'::jsonb),
    'produits', coalesce((select prod_prevu from totaux), 0),
    'produits_realises', coalesce((select prod_realise from totaux), 0),
    'charges', coalesce((select charg_prevu from totaux), 0),
    'charges_realisees', coalesce((select charg_realise from totaux), 0),
    'resultat_prevu', coalesce((select prod_prevu - charg_prevu from totaux), 0),
    'resultat_realise', coalesce((select prod_realise - charg_realise from totaux), 0),
    'benevolat', coalesce((select benevolat from totaux), 0),
    'execution', case when coalesce((select charg_prevu from totaux),0) = 0 then null
                 else round(coalesce((select charg_realise from totaux),0)
                            / (select charg_prevu from totaux) * 100) end);
$$;

create or replace function regler_ligne(p_id uuid, p_champ text, p_valeur text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('budget.tenir') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if exists (select 1 from budget_lignes bl join exercices e on e.id = bl.exercice_id
             where bl.id = p_id and e.statut in ('arrete','clos')) then
    return jsonb_build_object('ok', false, 'message', 'Cet exercice est arrêté.');
  end if;

  if p_champ = 'prevu' then
    update budget_lignes set prevu = coalesce(p_valeur,'0')::numeric,
           maj_par = auth.uid(), maj_le = now() where id = p_id;
  elsif p_champ = 'realise' then
    update budget_lignes set realise_saisi = coalesce(p_valeur,'0')::numeric,
           maj_par = auth.uid(), maj_le = now() where id = p_id;
  elsif p_champ = 'libelle' then
    update budget_lignes set libelle = nullif(trim(p_valeur),''),
           maj_par = auth.uid(), maj_le = now() where id = p_id;
  elsif p_champ = 'commentaire' then
    update budget_lignes set commentaire = nullif(trim(p_valeur),''),
           maj_par = auth.uid(), maj_le = now() where id = p_id;
  else
    return jsonb_build_object('ok', false, 'message', 'Champ inconnu.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function changer_statut_exercice(p_id uuid, p_statut text,
                                                   p_observations text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_statut in ('arrete','clos') and not a_droit('budget.arreter') then
    return jsonb_build_object('ok', false,
      'message', 'L''arrêté des comptes relève de la direction financière.');
  end if;
  if not a_droit('budget.tenir') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;

  update exercices
     set statut = p_statut,
         vote_le = case when p_statut = 'vote' then current_date else vote_le end,
         arrete_le = case when p_statut = 'arrete' then current_date else arrete_le end,
         arrete_par = case when p_statut = 'arrete' then auth.uid() else arrete_par end,
         observations = coalesce(nullif(trim(p_observations),''), observations)
   where id = p_id;

  if p_statut = 'arrete' then
    perform inscrire_acte(null, 'finance',
      'Comptes arrêtés — exercice ' ||
      (select annee::text from exercices where id = p_id), null, null, false);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function mes_exercices()
returns table (id uuid, annee integer, territoire text, territoire_id uuid,
               statut text, debut date, fin date, arrete_le date,
               produits numeric, charges numeric, resultat numeric)
language sql stable security definer set search_path = public as $$
  select e.id, e.annee, t.nom, e.territoire_id, e.statut, e.debut, e.fin, e.arrete_le,
         (budget_exercice(e.id)->>'produits_realises')::numeric,
         (budget_exercice(e.id)->>'charges_realisees')::numeric,
         (budget_exercice(e.id)->>'resultat_realise')::numeric
  from exercices e
  left join territoires t on t.id = e.territoire_id
  where a_droit('budget.tenir') or est_admin() or mon_niveau() >= 80
  order by e.annee desc, t.nom nulls first;
$$;

-- ---------------------------------------------------------------------
-- 5. RAPPORT D'ACTIVITÉ
--    Les chiffres se calculent, le récit se rédige.
-- ---------------------------------------------------------------------

create table if not exists rapports (
  id            uuid primary key default gen_random_uuid(),
  annee         integer not null,
  territoire_id uuid references territoires(id) on delete cascade,
  titre         text,
  edito         text,
  faits_marquants text,
  perspectives  text,
  remerciements text,
  statut        text not null default 'brouillon'
                  check (statut in ('brouillon','relecture','adopte','publie')),
  adopte_le     date,
  redige_par    uuid references profils(id),
  maj_le        timestamptz not null default now(),
  cree_le       timestamptz not null default now(),
  unique (annee, territoire_id)
);

create or replace function chiffres_annee(p_annee integer, p_territoire uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with bornes as (select make_date(p_annee,1,1) as d, make_date(p_annee,12,31) as f),
  perimetre as (
    select case when p_territoire is null then null else p_territoire end as terr),
  membres as (
    select p.* from profils p, perimetre
    where perimetre.terr is null
       or p.territoire_id in (select s.id from territoires_sous(perimetre.terr) s))
  select jsonb_build_object(
    'annee', p_annee,
    'adherents', jsonb_build_object(
      'total_fin_annee', (select count(*) from membres where statut = 'actif'),
      'nouveaux', (select count(*) from membres, bornes
                   where cree_le::date between bornes.d and bornes.f),
      'par_fonction', (select jsonb_object_agg(f.nom, n) from (
          select fonction, count(*) as n from membres where statut = 'actif'
          group by fonction) x join fonctions f on f.code = x.fonction),
      'par_echelon', (select jsonb_object_agg(e.nom, n) from (
          select echelon, count(*) as n from membres where statut = 'actif'
          group by echelon) x join echelons e on e.niveau = x.echelon)),
    'benevolat', jsonb_build_object(
      'heures', (select coalesce(sum(en.heures_realisees),0)
                 from engagements en
                 join membres m on m.id = en.profil_id
                 cross join bornes
                 where en.mois between bornes.d and bornes.f),
      'benevoles_actifs', (select count(distinct en.profil_id)
                 from engagements en
                 join membres m on m.id = en.profil_id
                 cross join bornes
                 where en.mois between bornes.d and bornes.f
                   and en.heures_realisees > 0)),
    'actions', jsonb_build_object(
      'missions', (select count(*) from missions mi, bornes
                   where mi.debut between bornes.d and bornes.f),
      'participations', (select count(*) from mission_candidatures mc
                   join missions mi on mi.id = mc.mission_id
                   join membres m on m.id = mc.profil_id
                   cross join bornes
                   where mc.statut = 'retenu' and mi.debut between bornes.d and bornes.f),
      'projets', (select count(*) from projets pj, bornes, perimetre
                   where (pj.debut between bornes.d and bornes.f
                          or pj.fin between bornes.d and bornes.f)
                     and (perimetre.terr is null
                          or pj.territoire_id in (select s.id from territoires_sous(perimetre.terr) s))),
      'beneficiaires', (select coalesce(sum(pj.beneficiaires),0) from projets pj, bornes, perimetre
                   where pj.statut = 'termine'
                     and pj.fin between bornes.d and bornes.f
                     and (perimetre.terr is null
                          or pj.territoire_id in (select s.id from territoires_sous(perimetre.terr) s)))),
    'formation', jsonb_build_object(
      'certifications', (select count(*) from certifications_obtenues co
                   join membres m on m.id = co.profil_id
                   cross join bornes
                   where co.obtenue_le::date between bornes.d and bornes.f),
      'formations_publiees', (select count(*) from formations where publiee)),
    'reseau', jsonb_build_object(
      'departements', (select count(distinct t.id) from territoires t
                   where t.echelle = 'departement'
                     and exists (select 1 from membres m
                                 where m.territoire_id in (select s.id from territoires_sous(t.id) s)
                                   and m.statut = 'actif')),
      'structures_actives', (select count(*) from territoires t
                   where t.echelle in ('local','departement') and t.etat = 'active'),
      'assemblees', (select count(*) from assemblees a, bornes, perimetre
                   where a.date_tenue::date between bornes.d and bornes.f
                     and a.statut = 'proclamee'
                     and (perimetre.terr is null or a.territoire_id = perimetre.terr)),
      'groupes_travail', (select count(*) from groupes_travail where statut = 'actif')),
    'vie_democratique', jsonb_build_object(
      'propositions', (select count(*) from propositions pr, bornes
                   where pr.cree_le::date between bornes.d and bornes.f),
      'propositions_retenues', (select count(*) from propositions pr, bornes
                   where pr.cree_le::date between bornes.d and bornes.f
                     and pr.statut in ('retenue','remontee','nationale'))));
$$;

create or replace function enregistrer_rapport(
  p_annee integer, p_territoire uuid, p_titre text, p_edito text,
  p_faits text, p_perspectives text, p_remerciements text, p_statut text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('rapport.rediger') or est_admin() or mon_niveau() >= 60) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne rédigez pas le rapport.');
  end if;

  insert into rapports (annee, territoire_id, titre, edito, faits_marquants,
                        perspectives, remerciements, statut, redige_par,
                        adopte_le)
  values (p_annee, p_territoire, nullif(trim(p_titre),''), p_edito, p_faits,
          p_perspectives, p_remerciements, coalesce(p_statut,'brouillon'), auth.uid(),
          case when p_statut = 'adopte' then current_date end)
  on conflict (annee, territoire_id) do update
    set titre = nullif(trim(p_titre),''), edito = p_edito,
        faits_marquants = p_faits, perspectives = p_perspectives,
        remerciements = p_remerciements, statut = coalesce(p_statut, rapports.statut),
        adopte_le = case when p_statut = 'adopte' then current_date else rapports.adopte_le end,
        maj_le = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 6. SAUVEGARDES
--    Le plan gratuit n'en fournit aucune. On ne peut pas les faire à la
--    place de la direction, mais on peut refuser de la laisser oublier.
-- ---------------------------------------------------------------------

create table if not exists sauvegardes (
  id         uuid primary key default gen_random_uuid(),
  periode    text not null,          -- 2026-07
  portee     text not null default 'complete'
               check (portee in ('complete','comptes','membres','discipline')),
  fait_par   uuid not null references profils(id),
  emplacement text,                  -- où le fichier a été déposé
  observation text,
  cree_le    timestamptz not null default now()
);

create or replace function etat_sauvegardes()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'periode', to_char(current_date, 'YYYY-MM'),
    'faite_ce_mois', exists (select 1 from sauvegardes
                             where periode = to_char(current_date,'YYYY-MM')),
    'derniere', (select jsonb_build_object(
        'periode', s.periode, 'le', s.cree_le,
        'par', trim(p.prenom || ' ' || p.nom), 'emplacement', s.emplacement)
      from sauvegardes s join profils p on p.id = s.fait_par
      order by s.cree_le desc limit 1),
    'jours_depuis', (select extract(day from now() - max(cree_le))::int from sauvegardes),
    'historique', coalesce((select jsonb_agg(jsonb_build_object(
        'periode', s.periode, 'portee', s.portee, 'le', s.cree_le,
        'par', trim(p.prenom || ' ' || p.nom), 'emplacement', s.emplacement)
        order by s.cree_le desc)
      from sauvegardes s join profils p on p.id = s.fait_par
      limit 12), '[]'::jsonb));
$$;

create or replace function declarer_sauvegarde(p_portee text, p_emplacement text,
                                               p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('budget.tenir') or est_admin() or a_droit('discipline.exporter')) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux directions concernées.');
  end if;
  insert into sauvegardes (periode, portee, fait_par, emplacement, observation)
  values (to_char(current_date,'YYYY-MM'), coalesce(p_portee,'complete'), auth.uid(),
          nullif(trim(p_emplacement),''), nullif(trim(p_observation),''));

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'sauvegarde_declaree', to_char(current_date,'YYYY-MM'),
          jsonb_build_object('portee', p_portee));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. EXPORTS COMPTABLES
-- ---------------------------------------------------------------------

create or replace function export_budget(p_exercice uuid)
returns table (sens text, categorie text, code text, libelle text,
               intitule text, prevu numeric, realise numeric,
               ecart numeric, execution integer, source text, commentaire text)
language sql stable security definer set search_path = public as $$
  select pc.sens, pc.categorie, pc.code, pc.libelle, bl.libelle,
         bl.prevu,
         case when pc.automatique then realise_automatique(p_exercice, pc.code)
              else bl.realise_saisi end,
         case when pc.automatique then realise_automatique(p_exercice, pc.code)
              else bl.realise_saisi end - bl.prevu,
         case when bl.prevu = 0 then null
              else round((case when pc.automatique
                               then realise_automatique(p_exercice, pc.code)
                               else bl.realise_saisi end) / bl.prevu * 100)::int end,
         pc.source, bl.commentaire
  from budget_lignes bl
  join postes_comptables pc on pc.code = bl.poste
  where bl.exercice_id = p_exercice
    and (a_droit('budget.tenir') or est_admin() or mon_niveau() >= 80)
  order by pc.sens desc, pc.ordre;
$$;

-- Le détail des notes de frais d'un exercice : ce qu'un
-- commissaire aux comptes demandera.
create or replace function export_depenses(p_exercice uuid)
returns table (reference text, date_paiement date, beneficiaire text,
               matricule text, territoire text, objet text, montant numeric,
               mode text, reference_paiement text, instruit_par text,
               ordonnance_par text, paye_par text, accuse_le timestamptz)
language sql stable security definer set search_path = public as $$
  select n.reference, n.payee_le::date, trim(p.prenom || ' ' || p.nom),
         p.matricule, t.nom, n.objet, total_note(n.id),
         n.mode_remboursement, n.reference_paiement,
         trim(i.prenom || ' ' || i.nom), trim(o.prenom || ' ' || o.nom),
         trim(v.prenom || ' ' || v.nom), n.accuse_le
  from notes_frais n
  join profils p on p.id = n.profil_id
  left join territoires t on t.id = p.territoire_id
  left join profils i on i.id = n.instruit_par
  left join profils o on o.id = n.ordonnance_par
  left join profils v on v.id = n.valide_par
  join exercices e on e.id = p_exercice
  where n.statut = 'payee' and n.payee_le::date between e.debut and e.fin
    and (a_droit('budget.tenir') or est_admin())
  order by n.payee_le;
$$;

-- ---------------------------------------------------------------------
-- 8. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table postes_comptables enable row level security;
alter table exercices         enable row level security;
alter table budget_lignes     enable row level security;
alter table rapports          enable row level security;
alter table sauvegardes       enable row level security;

drop policy if exists lire_plan on postes_comptables;
create policy lire_plan on postes_comptables for select using (mon_niveau() >= 10);
drop policy if exists gerer_plan on postes_comptables;
create policy gerer_plan on postes_comptables for all
  using (a_droit('budget.arreter')) with check (a_droit('budget.arreter'));

drop policy if exists lire_exercices on exercices;
create policy lire_exercices on exercices for select using (
  a_droit('budget.tenir') or est_admin() or mon_niveau() >= 80
);
drop policy if exists gerer_exercices on exercices;
create policy gerer_exercices on exercices for all
  using (a_droit('budget.tenir')) with check (a_droit('budget.tenir'));

drop policy if exists lire_budget on budget_lignes;
create policy lire_budget on budget_lignes for select using (
  a_droit('budget.tenir') or est_admin() or mon_niveau() >= 80
);
drop policy if exists gerer_budget on budget_lignes;
create policy gerer_budget on budget_lignes for all
  using (a_droit('budget.tenir')) with check (a_droit('budget.tenir'));

-- Un rapport adopté est lisible de tous les membres : c'est le sens
-- même d'un rapport d'activité.
drop policy if exists lire_rapports on rapports;
create policy lire_rapports on rapports for select using (
  statut in ('adopte','publie') or a_droit('rapport.rediger')
  or est_admin() or mon_niveau() >= 60
);
drop policy if exists gerer_rapports on rapports;
create policy gerer_rapports on rapports for all
  using (a_droit('rapport.rediger') or est_admin() or mon_niveau() >= 60)
  with check (a_droit('rapport.rediger') or est_admin() or mon_niveau() >= 60);

drop policy if exists lire_sauvegardes on sauvegardes;
create policy lire_sauvegardes on sauvegardes for select using (mon_niveau() >= 60);

grant select on postes_comptables, exercices, budget_lignes, rapports, sauvegardes
  to authenticated;
grant insert, update, delete on exercices, budget_lignes, rapports to authenticated;

grant execute on function ouvrir_exercice(integer, uuid),
                          realise_automatique(uuid, text), budget_exercice(uuid),
                          regler_ligne(uuid, text, text),
                          changer_statut_exercice(uuid, text, text),
                          mes_exercices(), chiffres_annee(integer, uuid),
                          enregistrer_rapport(integer, uuid, text, text, text,
                                              text, text, text),
                          etat_sauvegardes(), declarer_sauvegarde(text, text, text),
                          export_budget(uuid), export_depenses(uuid)
  to authenticated;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, droit_requis, couleur,
                          direction, ordre)
values ('budget', 'Budget et comptes', 'Budget',
        'Budget prévisionnel, compte de résultat, exports comptables et sauvegardes.',
        'Ce que la plateforme sait déjà, elle le compte.',
        100, true, 'budget.tenir', 'brun', 'dfin', 64)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      droit_requis = excluded.droit_requis, direction = excluded.direction;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre)
values ('rapport', 'Rapport d''activité', 'Rapport',
        'Chiffres de l''année, récit et adoption.',
        'Ce que nous avons fait, en chiffres et en mots.',
        10, false, 'bleu', 'dg', 68)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction;

insert into application_visibilite (application, fonction, etat)
select 'budget', f.code, 'invisible' from fonctions f
on conflict (application, fonction) do nothing;

insert into application_visibilite (application, fonction, etat)
select 'rapport', f.code, 'ouverte' from fonctions f
on conflict (application, fonction) do update set etat = 'ouverte';

-- =====================================================================
--  FIN DE LA MIGRATION 23
--
--  Vérifications :
--    select ouvrir_exercice(2026, null);
--    select budget_exercice((select id from exercices where annee = 2026));
--    select chiffres_annee(2026);
--    select etat_sauvegardes();
--
--  Sur le bénévolat valorisé : il figure en produit ET en charge pour
--  le même montant, conformément au plan comptable associatif. Il ne
--  change donc pas le résultat, mais il montre le poids réel de
--  l'engagement bénévole — ce que tout financeur regarde.
-- =====================================================================
