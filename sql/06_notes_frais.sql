-- =====================================================================
--  FFCE — Migration 06 — NOTES DE FRAIS ET DIRECTION FINANCIÈRE
--
--  Circuit à trois temps, comme dans toute association qui tient ses
--  comptes proprement :
--
--    1. Le membre saisit ses dépenses, joint ses justificatifs, dépose.
--    2. Son encadrement instruit — il sait si la dépense était engagée
--       pour une mission réelle. Il donne un avis, il ne paie pas.
--    3. Le trésorier valide, puis paie. Il tient les comptes, il n'a
--       pas à juger de l'opportunité d'un déplacement.
--
--  Séparer l'instruction du paiement n'est pas une lourdeur : c'est ce
--  qui protège le trésorier autant que le bénévole.
--
--  Prérequis : 01 à 05.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PARAMÈTRES
--    Barème kilométrique et plafonds. Modifiables sans toucher au code.
-- ---------------------------------------------------------------------

create table if not exists parametres_frais (
  cle     text primary key,
  valeur  numeric(10,4) not null,
  libelle text not null,
  unite   text not null default 'euros'
);

insert into parametres_frais (cle, valeur, libelle, unite) values
  ('taux_km',            0.529, 'Indemnité kilométrique', 'euros/km'),
  ('plafond_repas',      20.00, 'Plafond par repas',       'euros'),
  ('plafond_nuitee',     90.00, 'Plafond par nuitée',      'euros'),
  ('plafond_note',      800.00, 'Plafond par note de frais','euros')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 2. NOTES DE FRAIS
-- ---------------------------------------------------------------------

create sequence if not exists seq_note_frais start 1;

create table if not exists notes_frais (
  id           uuid primary key default gen_random_uuid(),
  reference    text unique not null default 'NF-' || to_char(now(),'YYYY') || '-' ||
                            lpad(nextval('seq_note_frais')::text, 4, '0'),
  profil_id    uuid not null references profils(id) on delete cascade,
  objet        text not null,
  groupe_id    uuid references groupes_travail(id) on delete set null,
  statut       text not null default 'brouillon' check (statut in
                 ('brouillon','deposee','instruite','validee','payee','refusee')),
  deposee_le   timestamptz,
  instruit_par uuid references profils(id),
  instruit_le  timestamptz,
  avis         text,                      -- avis de l'encadrement
  valide_par   uuid references profils(id),
  valide_le    timestamptz,
  payee_le     timestamptz,
  reference_paiement text,
  motif_refus  text,
  cree_le      timestamptz not null default now()
);
create index if not exists idx_nf_profil on notes_frais(profil_id);
create index if not exists idx_nf_statut on notes_frais(statut);

create table if not exists nf_lignes (
  id            uuid primary key default gen_random_uuid(),
  note_id       uuid not null references notes_frais(id) on delete cascade,
  date_depense  date not null,
  categorie     text not null check (categorie in
                  ('transport','kilometres','repas','hebergement','materiel','autre')),
  description   text not null,
  montant       numeric(10,2),            -- pour les dépenses réelles
  kilometres    numeric(10,1),            -- pour l'indemnité kilométrique
  justificatif  text,                     -- chemin dans le stockage
  cree_le       timestamptz not null default now()
);
create index if not exists idx_nfl_note on nf_lignes(note_id);

-- Le montant d'une ligne : soit la dépense, soit le barème kilométrique.
create or replace function montant_ligne(l nf_lignes)
returns numeric language sql stable as $$
  select case
    when l.categorie = 'kilometres'
      then round(coalesce(l.kilometres,0) *
                 (select valeur from parametres_frais where cle = 'taux_km'), 2)
    else coalesce(l.montant, 0)
  end;
$$;

create or replace function total_note(p_note uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(montant_ligne(l)), 0) from nf_lignes l where l.note_id = p_note;
$$;

-- ---------------------------------------------------------------------
-- 3. QUI FAIT QUOI
-- ---------------------------------------------------------------------

-- Le trésorier : celui à qui la Direction générale a ouvert
-- l'application « Direction financière ».
create or replace function est_tresorier()
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from acces_applications
    where profil_id = auth.uid() and application = 'tresorerie' and statut = 'accorde');
$$;

-- L'instructeur : l'encadrement du territoire du déposant, à partir du
-- niveau référent départemental.
create or replace function puis_je_instruire(p_note uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() then true
    when mon_niveau() < 60 then false
    else exists (
      select 1 from notes_frais n join profils p on p.id = n.profil_id
      where n.id = p_note and n.profil_id <> auth.uid()
        and dans_mon_perimetre(p.territoire_id))
  end;
$$;

create or replace function accede_note(p_note uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from notes_frais n
                 where n.id = p_note and n.profil_id = auth.uid())
      or est_tresorier() or puis_je_instruire(p_note);
$$;

-- ---------------------------------------------------------------------
-- 4. LE CIRCUIT
-- ---------------------------------------------------------------------

create or replace function deposer_note(p_note uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_total numeric; v_lignes int; v_sans int; v_plafond numeric;
begin
  if not exists (select 1 from notes_frais
                 where id = p_note and profil_id = auth.uid() and statut = 'brouillon') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est plus modifiable.');
  end if;

  select count(*) into v_lignes from nf_lignes where note_id = p_note;
  if v_lignes = 0 then
    return jsonb_build_object('ok', false, 'message', 'Ajoutez au moins une dépense.');
  end if;

  -- Un justificatif est exigé, sauf pour l'indemnité kilométrique.
  select count(*) into v_sans from nf_lignes
   where note_id = p_note and categorie <> 'kilometres'
     and coalesce(justificatif,'') = '';
  if v_sans > 0 then
    return jsonb_build_object('ok', false,
      'message', v_sans || ' dépense(s) sans justificatif. Joignez-les avant de déposer.');
  end if;

  v_total := total_note(p_note);
  select valeur into v_plafond from parametres_frais where cle = 'plafond_note';
  if v_total > v_plafond then
    return jsonb_build_object('ok', false,
      'message', 'Cette note dépasse le plafond de ' || v_plafond ||
                 ' €. Scindez-la ou demandez un accord préalable.');
  end if;

  update notes_frais set statut = 'deposee', deposee_le = now() where id = p_note;
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_deposee', p_note::text, jsonb_build_object('total', v_total));

  return jsonb_build_object('ok', true, 'total', v_total);
end $$;

create or replace function instruire_note(p_note uuid, p_favorable boolean, p_avis text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not puis_je_instruire(p_note) then
    return jsonb_build_object('ok', false, 'message', 'Cette note ne relève pas de votre périmètre.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'deposee') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est pas en attente d''instruction.');
  end if;
  if not p_favorable and coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un avis défavorable doit être motivé.');
  end if;

  update notes_frais
     set statut = case when p_favorable then 'instruite' else 'refusee' end,
         instruit_par = auth.uid(), instruit_le = now(),
         avis = nullif(trim(p_avis),''),
         motif_refus = case when p_favorable then null else trim(p_avis) end
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_instruite', p_note::text,
          jsonb_build_object('favorable', p_favorable));
  return jsonb_build_object('ok', true);
end $$;

create or replace function valider_note(p_note uuid, p_ok boolean, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_tresorier() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'instruite') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''a pas été instruite.');
  end if;
  if not p_ok and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus doit être motivé.');
  end if;

  update notes_frais
     set statut = case when p_ok then 'validee' else 'refusee' end,
         valide_par = auth.uid(), valide_le = now(),
         motif_refus = case when p_ok then null else trim(p_motif) end
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_validee', p_note::text, jsonb_build_object('accord', p_ok));
  return jsonb_build_object('ok', true);
end $$;

create or replace function payer_note(p_note uuid, p_reference text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_tresorier() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'validee') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est pas validée.');
  end if;

  update notes_frais
     set statut = 'payee', payee_le = now(),
         reference_paiement = nullif(trim(p_reference),'')
   where id = p_note;

  insert into journal (acteur, action, cible)
  values (auth.uid(), 'note_payee', p_note::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. VUES
-- ---------------------------------------------------------------------

create or replace function v_notes(p_filtre text default 'miennes')
returns table (
  id uuid, reference text, objet text, statut text, total numeric,
  nb_lignes integer, cree_le timestamptz, deposee_le timestamptz,
  profil_id uuid, deposant text, matricule text, territoire_nom text,
  groupe_nom text, avis text, motif_refus text, reference_paiement text,
  instruit_nom text, valide_nom text
) language sql stable security definer set search_path = public as $$
  select n.id, n.reference, n.objet, n.statut, total_note(n.id),
         (select count(*)::int from nf_lignes l where l.note_id = n.id),
         n.cree_le, n.deposee_le,
         n.profil_id, trim(p.prenom || ' ' || p.nom), p.matricule, t.nom,
         g.nom, n.avis, n.motif_refus, n.reference_paiement,
         trim(i.prenom || ' ' || i.nom), trim(v.prenom || ' ' || v.nom)
  from notes_frais n
  join profils p on p.id = n.profil_id
  left join territoires t     on t.id = p.territoire_id
  left join groupes_travail g on g.id = n.groupe_id
  left join profils i on i.id = n.instruit_par
  left join profils v on v.id = n.valide_par
  where case p_filtre
    when 'miennes'   then n.profil_id = auth.uid()
    when 'instruire' then n.statut = 'deposee' and puis_je_instruire(n.id)
    when 'tresorerie'then est_tresorier() and n.statut in ('instruite','validee')
    when 'toutes'    then est_tresorier() or est_admin()
    else false end
  order by n.cree_le desc;
$$;

-- =====================================================================
--  6. SÉCURITÉ
-- =====================================================================

alter table notes_frais      enable row level security;
alter table nf_lignes        enable row level security;
alter table parametres_frais enable row level security;

drop policy if exists lire_notes on notes_frais;
create policy lire_notes on notes_frais for select using (accede_note(id));

drop policy if exists creer_note on notes_frais;
create policy creer_note on notes_frais for insert
  with check (profil_id = auth.uid() and a_acces('notes_frais'));

-- Le déposant ne modifie sa note qu'à l'état de brouillon. Le reste du
-- circuit passe par les fonctions, qui vérifient chaque transition.
drop policy if exists maj_note on notes_frais;
create policy maj_note on notes_frais for update
  using (profil_id = auth.uid() and statut = 'brouillon')
  with check (profil_id = auth.uid() and statut = 'brouillon');

drop policy if exists suppr_note on notes_frais;
create policy suppr_note on notes_frais for delete
  using (profil_id = auth.uid() and statut = 'brouillon');

drop policy if exists lire_lignes on nf_lignes;
create policy lire_lignes on nf_lignes for select using (accede_note(note_id));

drop policy if exists ecrire_lignes on nf_lignes;
create policy ecrire_lignes on nf_lignes for all using (
  exists (select 1 from notes_frais n where n.id = note_id
          and n.profil_id = auth.uid() and n.statut = 'brouillon')
) with check (
  exists (select 1 from notes_frais n where n.id = note_id
          and n.profil_id = auth.uid() and n.statut = 'brouillon')
);

drop policy if exists lire_parametres on parametres_frais;
create policy lire_parametres on parametres_frais for select using (mon_niveau() >= 10);
drop policy if exists ecrire_parametres on parametres_frais;
create policy ecrire_parametres on parametres_frais for all
  using (est_tresorier()) with check (est_tresorier());

-- ---------------------------------------------------------------------
-- 7. STOCKAGE DES JUSTIFICATIFS
--    Dépôt privé. Chacun écrit dans son propre dossier, nommé par son
--    identifiant : un membre ne peut pas déposer chez un autre.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('justificatifs', 'justificatifs', false, 5242880)
on conflict (id) do update set public = false, file_size_limit = 5242880;

drop policy if exists depot_justificatifs on storage.objects;
create policy depot_justificatifs on storage.objects for insert to authenticated
  with check (bucket_id = 'justificatifs'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists lecture_justificatifs on storage.objects;
create policy lecture_justificatifs on storage.objects for select to authenticated
  using (bucket_id = 'justificatifs'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or est_tresorier() or mon_niveau() >= 60));

drop policy if exists suppr_justificatifs on storage.objects;
create policy suppr_justificatifs on storage.objects for delete to authenticated
  using (bucket_id = 'justificatifs'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 8. DROITS DE BASE
-- ---------------------------------------------------------------------

grant select on notes_frais, nf_lignes, parametres_frais to authenticated;
grant insert, update, delete on notes_frais, nf_lignes to authenticated;
grant update on parametres_frais to authenticated;
grant usage, select on all sequences in schema public to authenticated;

grant execute on function montant_ligne(nf_lignes), total_note(uuid),
                          est_tresorier(), puis_je_instruire(uuid), accede_note(uuid),
                          deposer_note(uuid), instruire_note(uuid, boolean, text),
                          valider_note(uuid, boolean, text), payer_note(uuid, text),
                          v_notes(text)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 06
--
--  Pour ouvrir l'application à quelqu'un, deux voies :
--    — le membre la demande depuis son guichet, vous l'accordez ;
--    — ou vous l'ouvrez directement :
--
--    insert into acces_applications (profil_id, application, statut, accorde_par)
--    select id, 'tresorerie', 'accorde',
--           (select id from profils where fonction = 'admin' limit 1)
--    from profils where email = 'tresorier@ffce-asso.fr'
--    on conflict (profil_id, application) do update set statut = 'accorde';
--
--  Le barème kilométrique et les plafonds se règlent dans l'onglet
--  Direction financière, ou ici :
--    update parametres_frais set valeur = 0.603 where cle = 'taux_km';
-- =====================================================================
