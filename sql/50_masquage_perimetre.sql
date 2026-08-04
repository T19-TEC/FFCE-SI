-- =====================================================================
-- 50 — Masquage nominatif du périmètre, paramétrable par catégorie de
--       poste (« fonction »)
--
-- POURQUOI : dans « Mon périmètre », un responsable voit aujourd'hui le
-- nom de chaque personne de son territoire. Le réseau veut pouvoir
-- retirer le nom pour certaines catégories de poste (fonction) et ne
-- garder que l'effectif, réglable par l'admin.
--
-- ARCHITECTURE : une table de réglage, generalisable à d'autres blocs
-- que celui-ci plus tard, sur le même principe que application_visibilite
-- (application, fonction, etat) déjà en place — même axe de
-- catégorisation (fonction), pour rester cohérent avec l'existant.
--
-- CHOIX DE SÛRETÉ (revue de sûreté, point A) : mon_perimetre() N'EST
-- PAS security definer. Elle tourne avec les droits de l'appelant, donc
-- avec la même portée RLS que la requête directe sur v_annuaire
-- utilisée jusqu'ici. Je n'ai jamais vu la définition de v_annuaire ni
-- ses politiques de sécurité (elles ne sont pas dans SCHEMA.md, qui est
-- un abrégé) — un security definer aurait pu, sans le vouloir, faire
-- sauter le filtrage territorial et exposer tout l'annuaire national.
-- En restant security invoker, ce risque n'existe pas : la fonction ne
-- peut voir que ce que l'appelant voit déjà.
--
-- Le masquage porte sur nom, prénom ET matricule (point B, données
-- personnelles) : masquer le nom en laissant le matricule visible
-- suffirait à ré-identifier quelqu'un pour peu qu'on le recoupe
-- ailleurs. Territoire, fonction, échelon et statut restent affichés :
-- ce sont des agrégats de gestion, pas des identifiants.
-- =====================================================================

create table if not exists blocs_visibilite (
  bloc      text not null,
  fonction  text not null references fonctions(code),
  visible   boolean not null default true,
  note      text,
  maj_par   uuid references profils(id),
  maj_le    timestamptz not null default now(),
  primary key (bloc, fonction)
);

alter table blocs_visibilite enable row level security;

drop policy if exists blocs_visibilite_lecture on blocs_visibilite;
create policy blocs_visibilite_lecture on blocs_visibilite
  for select using (true);

drop policy if exists blocs_visibilite_creation on blocs_visibilite;
create policy blocs_visibilite_creation on blocs_visibilite
  for insert with check (est_admin());

drop policy if exists blocs_visibilite_maj on blocs_visibilite;
create policy blocs_visibilite_maj on blocs_visibilite
  for update using (est_admin()) with check (est_admin());

drop policy if exists blocs_visibilite_suppression on blocs_visibilite;
create policy blocs_visibilite_suppression on blocs_visibilite
  for delete using (est_admin());

-- Lecture ouverte à tous : chacun doit pouvoir savoir si SA propre
-- catégorie a les noms masqués ou non, pour que mon_perimetre() (qui,
-- elle, tourne avec les droits de l'appelant) puisse lire ce réglage.
-- Seule l'écriture est réservée à l'admin (est_admin(), déjà définie en
-- 01_socle.sql).

create or replace function mon_perimetre()
returns table(
  id uuid, nom text, prenom text, matricule text,
  fonction_nom text, territoire_nom text, echelon text, statut text,
  niveau integer
)
language sql
stable
as $$
  select
    a.id,
    case when coalesce(bv.visible, true) then a.nom      else null end as nom,
    case when coalesce(bv.visible, true) then a.prenom   else null end as prenom,
    case when coalesce(bv.visible, true) then a.matricule else null end as matricule,
    a.fonction_nom, a.territoire_nom, a.echelon, a.statut, a.niveau
  from v_annuaire a
  left join profils moi on moi.id = auth.uid()
  left join blocs_visibilite bv
    on bv.bloc = 'annuaire.noms' and bv.fonction = moi.fonction
$$;

-- VÉRIFICATION à faire après dépôt : ouvrir Mon périmètre avec un
-- compte dont la fonction n'a aucune ligne dans blocs_visibilite —
-- coalesce(bv.visible, true) doit laisser les noms visibles par
-- défaut. Rien ne doit se masquer tant que l'admin n'a rien réglé.
