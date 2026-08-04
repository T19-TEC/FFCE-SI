-- =====================================================================
-- 51 — Tâches de la présidence, et remontées « rendu de travail »
--
-- PARTIE A — REMONTÉES
-- Aucun changement de structure : remontees_cabinet.nature est un texte
-- libre (pas de contrainte trouvée dans SCHEMA.md), et flecher_vers_cabinet
-- accepte déjà p_corps et p_lien. « Rendu de travail » est traité comme
-- une nature de plus, avec un formulaire plus structuré côté écran — je
-- n'ai pas touché à flecher_vers_cabinet, dont je n'ai jamais vu le
-- corps. Rien à faire ici en SQL pour cette partie.
--
-- PARTIE B — TÂCHES
-- Aucune table existante ne convient : gt_taches est liée à un
-- groupe_id (groupe de travail), pas à une tâche libre assignée par le
-- président à qui il veut. Je crée une table dédiée plutôt que de
-- plier gt_taches à un usage qu'elle n'a pas prévu et dont je ne
-- connais pas les politiques de sécurité.
--
-- Règles fixées : une échéance, un contenu libre, délégation possible
-- (mais pas de refus), annulation réservée à qui a assigné la tâche ou
-- à qui tient aujourd'hui le poste de président fédéral (pour survivre
-- à une alternance).
--
-- REVUE DE SÛRETÉ, point C (escalade) : assigner_tache() et
-- annuler_tache() vérifient toutes deux que l'appelant tient
-- actuellement le poste 'president_federation' — je n'ai pas élargi
-- ce pouvoir à un niveau numérique (ex. niveau >= 90), pour éviter
-- qu'un directeur de haut niveau, non président, ne puisse assigner
-- des tâches en son nom.
-- =====================================================================

create table if not exists taches_assignees (
  id                uuid primary key default gen_random_uuid(),
  titre             text not null,
  description       text,
  assigne_a         uuid not null references profils(id),
  assigne_par       uuid not null references profils(id),
  echeance          date,
  statut            text not null default 'en_cours'
                      check (statut in ('en_cours','faite','annulee')),
  delegue_de        uuid references profils(id),
  annule_par        uuid references profils(id),
  annule_le         timestamptz,
  motif_annulation  text,
  faite_le          timestamptz,
  cree_le           timestamptz not null default now(),
  maj_le            timestamptz not null default now()
);

alter table taches_assignees enable row level security;

drop policy if exists taches_assignees_lecture on taches_assignees;
create policy taches_assignees_lecture on taches_assignees
  for select using (auth.uid() = assigne_a or auth.uid() = assigne_par);

-- Aucune politique d'écriture directe : toute création, délégation ou
-- annulation passe par une fonction ci-dessous. RLS activée sans
-- politique insert/update/delete = écriture directe toujours refusée.

create or replace function assigner_tache(
  p_assigne_a uuid, p_titre text, p_description text default null,
  p_echeance date default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (
    select 1 from nominations n
    where n.poste = 'president_federation'
      and n.profil_id = auth.uid()
      and n.revoque_le is null
      and (n.fin is null or n.fin > now())
  ) then
    return jsonb_build_object('ok', false,
      'message', 'Seule la présidence fédérale peut assigner une tâche.');
  end if;

  if p_titre is null or length(trim(p_titre)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Le titre est obligatoire.');
  end if;

  insert into taches_assignees (titre, description, assigne_a, assigne_par, echeance)
  values (p_titre, p_description, p_assigne_a, auth.uid(), p_echeance)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function deleguer_tache(p_tache uuid, p_a uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actuel uuid;
  v_statut text;
begin
  select assigne_a, statut into v_actuel, v_statut
  from taches_assignees where id = p_tache;

  if v_actuel is null then
    return jsonb_build_object('ok', false, 'message', 'Tâche introuvable.');
  end if;
  if v_actuel <> auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Seule la personne à qui la tâche est confiée peut la déléguer.');
  end if;
  if v_statut <> 'en_cours' then
    return jsonb_build_object('ok', false, 'message', 'Cette tâche n\u2019est plus en cours.');
  end if;
  if p_a = auth.uid() then
    return jsonb_build_object('ok', false, 'message', 'Choisissez quelqu\u2019un d\u2019autre.');
  end if;

  update taches_assignees
    set assigne_a = p_a, delegue_de = auth.uid(), maj_le = now()
    where id = p_tache;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function terminer_tache(p_tache uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update taches_assignees
    set statut = 'faite', faite_le = now(), maj_le = now()
    where id = p_tache and assigne_a = auth.uid() and statut = 'en_cours';

  if not found then
    return jsonb_build_object('ok', false,
      'message', 'Tâche introuvable, déjà close, ou qui ne vous est pas confiée.');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function annuler_tache(p_tache uuid, p_motif text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assigne_par uuid;
begin
  select assigne_par into v_assigne_par from taches_assignees where id = p_tache;
  if v_assigne_par is null then
    return jsonb_build_object('ok', false, 'message', 'Tâche introuvable.');
  end if;

  if auth.uid() <> v_assigne_par and not exists (
    select 1 from nominations n
    where n.poste = 'president_federation'
      and n.profil_id = auth.uid()
      and n.revoque_le is null
      and (n.fin is null or n.fin > now())
  ) then
    return jsonb_build_object('ok', false,
      'message', 'Seule la présidence fédérale peut annuler cette tâche.');
  end if;

  update taches_assignees
    set statut = 'annulee', annule_par = auth.uid(), annule_le = now(),
        motif_annulation = p_motif, maj_le = now()
    where id = p_tache and statut = 'en_cours';

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Cette tâche n\u2019est plus en cours.');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function mes_taches()
returns table(
  id uuid, titre text, description text, echeance date, statut text,
  assigne_par_nom text, delegue_de_nom text, cree_le timestamptz
)
language sql
stable
as $$
  select t.id, t.titre, t.description, t.echeance, t.statut,
    nullif(trim(p1.prenom || ' ' || p1.nom), '') as assigne_par_nom,
    nullif(trim(p2.prenom || ' ' || p2.nom), '') as delegue_de_nom,
    t.cree_le
  from taches_assignees t
  left join profils p1 on p1.id = t.assigne_par
  left join profils p2 on p2.id = t.delegue_de
  where t.assigne_a = auth.uid()
  order by (t.statut = 'en_cours') desc, t.echeance nulls last, t.cree_le desc
$$;

create or replace function taches_que_jai_confiees()
returns table(
  id uuid, titre text, description text, echeance date, statut text,
  assigne_a_nom text, cree_le timestamptz
)
language sql
stable
as $$
  select t.id, t.titre, t.description, t.echeance, t.statut,
    nullif(trim(p.prenom || ' ' || p.nom), '') as assigne_a_nom,
    t.cree_le
  from taches_assignees t
  left join profils p on p.id = t.assigne_a
  where t.assigne_par = auth.uid()
  order by (t.statut = 'en_cours') desc, t.echeance nulls last, t.cree_le desc
$$;

-- VÉRIFICATIONS à faire après dépôt :
-- - confirmer que 'president_federation' est bien le code exact (déjà
--   utilisé sans incident depuis la migration 49) ;
-- - tenter d'assigner une tâche avec un compte non-président : doit
--   échouer proprement, pas planter ;
-- - déléguer, puis vérifier que l'ancien assigné ne voit plus la tâche
--   dans mes_taches() et que le nouveau si.
