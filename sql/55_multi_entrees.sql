-- =====================================================================
-- 55 — Multi-entrées : couleurs, désactivation, options avancées,
--       niveaux d'accréditation
--
-- CHOIX CENTRAL : un niveau d'accréditation n'est PAS un nouveau
-- mécanisme de sécurité. C'est un raccourci qui pose, en une fois, le
-- même tableau categories text[] qu'un organisateur pourrait cocher
-- entrée par entrée sur inscriptions_evenement. Le contrôle à l'entrée
-- (controler_entree) n'est pas touché — il continue de vérifier ce
-- même tableau, comme aujourd'hui. Un niveau qui donnerait accès à une
-- entrée n'existe que parce que ses catégories existent déjà ; il ne
-- crée aucun nouveau chemin d'accès.
--
-- « Retirer l'entrée billet général » devient une DÉSACTIVATION
-- (actif=false), pas une suppression : des inscriptions existantes
-- peuvent déjà porter 'general' dans leur tableau de catégories.
-- Supprimer la ligne les aurait rendues incohérentes sans prévenir
-- personne. Désactivée, elle disparaît des écrans de choix sans
-- casser ce qui existe déjà.
--
-- REVUE DE SÛRETÉ, point C (escalade) : regler_niveau() n'autorise que
-- l'organisateur de l'événement (evenements.organisateur_id) ou
-- l'admin (est_admin()). Je n'ai pas trouvé, dans SCHEMA.md, de droit
-- nommé pour la co-organisation d'un événement — si plusieurs
-- personnes doivent pouvoir régler les niveaux d'un même événement
-- sans être admin, dites-le-moi, j'élargirai.
-- =====================================================================

alter table evenement_categories add column if not exists couleur text;
alter table evenement_categories add column if not exists actif boolean not null default true;

alter table evenements add column if not exists avance boolean not null default false;

create table if not exists niveaux_accreditation (
  id           uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references evenements(id) on delete cascade,
  nom          text not null,
  couleur      text default 'bleu',
  categories   text[] not null default '{}',
  ordre        integer not null default 100,
  cree_le      timestamptz not null default now()
);

alter table niveaux_accreditation enable row level security;

drop policy if exists niveaux_accreditation_lecture on niveaux_accreditation;
create policy niveaux_accreditation_lecture on niveaux_accreditation
  for select using (true);

-- Aucune politique d'écriture directe : tout passe par regler_niveau()
-- et supprimer_niveau() ci-dessous.

create or replace function peut_regler_evenement(p_evenement uuid)
returns boolean
language sql
stable
as $$
  select est_admin() or exists (
    select 1 from evenements e where e.id = p_evenement and e.organisateur_id = auth.uid()
  )
$$;

create or replace function regler_niveau(
  p_evenement uuid, p_id uuid default null, p_nom text default null,
  p_couleur text default 'bleu', p_categories text[] default '{}', p_ordre integer default 100
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not peut_regler_evenement(p_evenement) then
    return jsonb_build_object('ok', false,
      'message', 'Seul l\u2019organisateur de cet événement peut régler ses niveaux d\u2019accréditation.');
  end if;
  if p_nom is null or length(trim(p_nom)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Le nom du niveau est obligatoire.');
  end if;

  if p_id is null then
    insert into niveaux_accreditation (evenement_id, nom, couleur, categories, ordre)
    values (p_evenement, p_nom, p_couleur, p_categories, p_ordre)
    returning id into v_id;
  else
    update niveaux_accreditation
      set nom = p_nom, couleur = p_couleur, categories = p_categories, ordre = p_ordre
      where id = p_id and evenement_id = p_evenement
      returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'message', 'Niveau introuvable.');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function supprimer_niveau(p_id uuid, p_evenement uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not peut_regler_evenement(p_evenement) then
    return jsonb_build_object('ok', false, 'message', 'Non autorisé.');
  end if;
  delete from niveaux_accreditation where id = p_id and evenement_id = p_evenement;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function assigner_niveau(p_inscription uuid, p_niveau uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evenement uuid;
  v_categories text[];
begin
  select evenement_id into v_evenement from inscriptions_evenement where id = p_inscription;
  if v_evenement is null then
    return jsonb_build_object('ok', false, 'message', 'Inscription introuvable.');
  end if;
  if not peut_regler_evenement(v_evenement) then
    return jsonb_build_object('ok', false, 'message', 'Non autorisé.');
  end if;

  select categories into v_categories
  from niveaux_accreditation where id = p_niveau and evenement_id = v_evenement;
  if v_categories is null then
    return jsonb_build_object('ok', false, 'message', 'Niveau introuvable pour cet événement.');
  end if;

  update inscriptions_evenement set categories = v_categories where id = p_inscription;
  return jsonb_build_object('ok', true);
end;
$$;

-- Je n'ai jamais vu le corps de regler_categorie(d jsonb) : rien ne me
-- dit qu'elle prendrait en compte des clés couleur/actif ajoutées à
-- son jsonb d'entrée. Plutôt que de parier dessus, deux fonctions
-- dédiées, qui n'écrivent que la colonne qu'elles nomment.

create or replace function regler_couleur_categorie(p_categorie uuid, p_couleur text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evenement uuid;
begin
  select evenement_id into v_evenement from evenement_categories where id = p_categorie;
  if v_evenement is null or not peut_regler_evenement(v_evenement) then
    return jsonb_build_object('ok', false, 'message', 'Non autorisé.');
  end if;
  update evenement_categories set couleur = p_couleur where id = p_categorie;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function regler_actif_categorie(p_categorie uuid, p_actif boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evenement uuid;
begin
  select evenement_id into v_evenement from evenement_categories where id = p_categorie;
  if v_evenement is null or not peut_regler_evenement(v_evenement) then
    return jsonb_build_object('ok', false, 'message', 'Non autorisé.');
  end if;
  update evenement_categories set actif = p_actif where id = p_categorie;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function regler_options_avancees(p_evenement uuid, p_avance boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not peut_regler_evenement(p_evenement) then
    return jsonb_build_object('ok', false, 'message', 'Non autorisé.');
  end if;
  update evenements set avance = p_avance where id = p_evenement;
  return jsonb_build_object('ok', true);
end;
$$;

-- VÉRIFICATIONS à faire après dépôt :
-- - peut_regler_evenement() suppose que organisateur_id est la seule
--   source d'autorisation en dehors de l'admin — à confirmer.
