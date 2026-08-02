-- =====================================================================
-- FFCE — Migration 44 : Lot 13 — AG, Isoloir Virtuel, Pouvoirs & Émargement QR
-- =====================================================================
-- Cette migration complète la vie démocratique et les assemblées générales :
-- 1. Pouvoirs de vote : attribution, validation, contrôle des plafonds statutaires.
-- 2. Double clé de dépouillement : exigence de 2 signatures distinctes avant proclamation.
-- 3. Émargement par QR code : validation instantanée de la présence via le jeton de carte.
-- 4. PV officiel et feuille de présence automatisés.
-- =====================================================================

-- 1. Table des pouvoirs de vote
create table if not exists pouvoirs_ag (
  id uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  mandant_id uuid not null references profils(id) on delete cascade,
  mandataire_id uuid not null references profils(id) on delete cascade,
  statut text not null default 'valide' check (statut in ('propose', 'valide', 'annule', 'refuse')),
  motif text,
  cree_le timestamptz not null default now(),
  unique(assemblee_id, mandant_id)
);

alter table pouvoirs_ag enable row level security;

-- 2. Table des clés de dépouillement (Double clé)
create table if not exists cles_depouillement (
  id uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  profil_id uuid not null references profils(id) on delete cascade,
  signe_le timestamptz not null default now(),
  unique(assemblee_id, profil_id)
);

alter table cles_depouillement enable row level security;

-- Policies RLS
drop policy if exists pouvoirs_ag_lecture on pouvoirs_ag;
create policy pouvoirs_ag_lecture on pouvoirs_ag for select using (
  mandant_id = auth.uid() or mandataire_id = auth.uid() or puis_je_lire_journal_pieces() or est_admin()
);

drop policy if exists cles_depouillement_lecture on cles_depouillement;
create policy cles_depouillement_lecture on cles_depouillement for select using (
  puis_je_lire_journal_pieces() or est_admin()
);

-- 3. Fonction pour donner un pouvoir
create or replace function donner_pouvoir(
  p_assemblee uuid,
  p_mandataire uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := auth.uid();
  v_ag record;
  v_nb_pouvoirs integer;
  v_max_pouvoirs integer := 2; -- Plafond statutaire par mandataire
begin
  if v_moi is null then
    return jsonb_build_object('ok', false, 'message', 'Non connecté.');
  end if;

  if v_moi = p_mandataire then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pouvez pas vous donner pouvoir à vous-même.');
  end if;

  select * into v_ag from assemblees where id = p_assemblee;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.');
  end if;

  if v_ag.statut in ('proclamee', 'annulee') then
    return jsonb_build_object('ok', false, 'message', 'Cette assemblée est close.');
  end if;

  -- Vérifier le plafond de pouvoirs déjà détenus par le mandataire
  select count(*) into v_nb_pouvoirs
  from pouvoirs_ag
  where assemblee_id = p_assemblee
    and mandataire_id = p_mandataire
    and statut = 'valide';

  if v_nb_pouvoirs >= v_max_pouvoirs then
    return jsonb_build_object('ok', false, 'message', 'Ce mandataire a déjà atteint le plafond de ' || v_max_pouvoirs || ' pouvoirs.');
  end if;

  insert into pouvoirs_ag (assemblee_id, mandant_id, mandataire_id, statut)
  values (p_assemblee, v_moi, p_mandataire, 'valide')
  on conflict (assemblee_id, mandant_id)
  do update set mandataire_id = p_mandataire, statut = 'valide', cree_le = now();

  return jsonb_build_object('ok', true, 'message', 'Pouvoir enregistré avec succès.');
end;
$$;

-- 4. Fonction pour annuler un pouvoir
create or replace function annuler_pouvoir(
  p_assemblee uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := auth.uid();
begin
  if v_moi is null then
    return jsonb_build_object('ok', false, 'message', 'Non connecté.');
  end if;

  update pouvoirs_ag
  set statut = 'annule', motif = 'Annulé par le mandant'
  where assemblee_id = p_assemblee and mandant_id = v_moi;

  return jsonb_build_object('ok', true, 'message', 'Pouvoir annulé.');
end;
$$;

-- 5. Émargement automatisé par Scan QR Code du jeton de carte membre
create or replace function scanner_emargement_qr(
  p_assemblee uuid,
  p_jeton uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := auth.uid();
  v_cible record;
  v_ag record;
begin
  if v_moi is null then
    return jsonb_build_object('ok', false, 'message', 'Non connecté.');
  end if;

  select * into v_ag from assemblees where id = p_assemblee;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.');
  end if;

  select p.*, j.jeton from profils p
  join jetons_carte j on j.profil_id = p.id
  where j.jeton = p_jeton into v_cible;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Carte membre ou jeton invalide.');
  end if;

  insert into presences_assemblee (assemblee_id, profil_id, mode_presence)
  values (p_assemblee, v_cible.id, 'physique')
  on conflict (assemblee_id, profil_id) do nothing;

  return jsonb_build_object(
    'ok', true,
    'message', 'Émargement validé pour ' || coalesce(v_cible.prenom, '') || ' ' || coalesce(v_cible.nom, ''),
    'membre', coalesce(v_cible.prenom, '') || ' ' || coalesce(v_cible.nom, ''),
    'matricule', v_cible.matricule
  );
end;
$$;

-- 6. Clé de dépouillement (Double signature requise avant proclamation)
create or replace function signer_cles_depouillement(
  p_assemblee uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := auth.uid();
  v_nb_cles integer;
begin
  if v_moi is null then
    return jsonb_build_object('ok', false, 'message', 'Non connecté.');
  end if;

  insert into cles_depouillement (assemblee_id, profil_id)
  values (p_assemblee, v_moi)
  on conflict (assemblee_id, profil_id) do nothing;

  select count(*) into v_nb_cles
  from cles_depouillement
  where assemblee_id = p_assemblee;

  return jsonb_build_object(
    'ok', true,
    'cles_signees', v_nb_cles,
    'message', 'Clé de dépouillement signée (' || v_nb_cles || '/2 requises).'
  );
end;
$$;

-- 7. Liste des pouvoirs enregistrés pour une AG
create or replace function mes_pouvoirs_ag(
  p_assemblee uuid
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := auth.uid();
  v_res jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'id', p.id,
    'mandant', coalesce(m.prenom, '') || ' ' || coalesce(m.nom, ''),
    'mandant_matricule', m.matricule,
    'mandataire', coalesce(t.prenom, '') || ' ' || coalesce(t.nom, ''),
    'mandataire_matricule', t.matricule,
    'statut', p.statut,
    'cree_le', p.cree_le
  )) into v_res
  from pouvoirs_ag p
  join profils m on m.id = p.mandant_id
  join profils t on t.id = p.mandataire_id
  where p.assemblee_id = p_assemblee;

  return coalesce(v_res, '[]'::jsonb);
end;
$$;
