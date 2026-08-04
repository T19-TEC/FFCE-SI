-- =====================================================================
-- 52 — Registre des blocs configurables
--
-- POURQUOI : blocs_visibilite (migration 50) sait déjà régler la
-- visibilité d'un bloc par catégorie de poste, mais rien ne liste les
-- blocs qui existent. Pour qu'un écran d'administration centralisé
-- puisse les présenter avec un intitulé lisible, il leur faut un
-- registre. Un seul bloc y figure aujourd'hui ; chaque futur bloc
-- configurable s'y ajoutera au moment de sa création, plutôt que
-- d'être une clé de texte connue seulement du code.
-- =====================================================================

create table if not exists blocs_definis (
  bloc         text primary key,
  libelle      text not null,
  description  text,
  cree_le      timestamptz not null default now()
);

alter table blocs_definis enable row level security;

drop policy if exists blocs_definis_lecture on blocs_definis;
create policy blocs_definis_lecture on blocs_definis for select using (true);

drop policy if exists blocs_definis_ecriture on blocs_definis;
create policy blocs_definis_ecriture on blocs_definis
  for all using (est_admin()) with check (est_admin());

insert into blocs_definis (bloc, libelle, description) values
  ('annuaire.noms', 'Noms dans « Mon périmètre »',
   'Affiche ou masque le nom et le matricule dans l\u2019écran Mon périmètre. Décoché, seul l\u2019effectif reste visible.')
on conflict (bloc) do nothing;

-- Rien d'autre en SQL pour ce lot : la visibilité des applications
-- utilise application_visibilite, qui existe déjà. Je ne connais pas
-- le type exact de sa colonne etat (booléen ou texte à valeurs
-- fixes) — SCHEMA.md n'en dit rien de plus que son nom. L'écran
-- écrit un booléen ; si la colonne attend autre chose, l'écriture
-- échouera proprement avec un message d'erreur visible, plutôt que
-- d'écrire une valeur silencieusement fausse. Dites-moi le message
-- exact si ça se produit, je corrige dans la foulée.
