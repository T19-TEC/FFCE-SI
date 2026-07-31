-- =====================================================================
--  FFCE — Migration 09 — FINANCES : ORDONNATEUR ET PAYEUR
--
--  Le principe comptable de base : celui qui décide d'engager la
--  dépense n'est jamais celui qui la paie. Cette séparation ne protège
--  pas l'association contre ses bénévoles — elle protège le trésorier,
--  qui ne peut plus se voir reprocher une dépense qu'il n'a pas
--  décidée, et l'ordonnateur, qui ne touche pas aux fonds.
--
--  Le circuit devient :
--
--    1. DÉPÔT           le membre saisit, joint ses justificatifs,
--                       choisit son mode de remboursement
--    2. AVIS            son encadrement territorial dit si la dépense
--                       correspondait à une mission réelle (facultatif)
--    3. INSTRUCTION     la direction financière contrôle la forme :
--                       justificatifs, barème, imputation
--    4. ORDONNANCEMENT  l'ordonnateur décide d'engager la dépense
--    5. PAIEMENT        la direction financière exécute
--
--  Une même personne ne peut pas ordonnancer et payer la même note.
--  Ce n'est pas un réglage : c'est vérifié en base.
--
--  Prérequis : 01 à 08.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. COORDONNÉES BANCAIRES
--    Table à part, RLS stricte, consultation tracée. Un IBAN n'a rien
--    à faire dans la table des profils, que trop de monde peut lire.
-- ---------------------------------------------------------------------

create table if not exists coordonnees_bancaires (
  profil_id uuid primary key references profils(id) on delete cascade,
  titulaire text not null,
  iban      text not null,
  bic       text,
  maj_le    timestamptz not null default now(),
  cree_le   timestamptz not null default now()
);

create table if not exists acces_rib (
  id        bigserial primary key,
  lecteur   uuid not null references profils(id) on delete cascade,
  profil_id uuid not null references profils(id) on delete cascade,
  note_id   uuid,
  cree_le   timestamptz not null default now()
);

-- Contrôle sommaire de forme, sans prétendre valider la clé.
create or replace function iban_plausible(p text)
returns boolean language sql immutable as $$
  select upper(regexp_replace(coalesce(p,''), '\s', '', 'g')) ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$';
$$;

create or replace function enregistrer_rib(p_titulaire text, p_iban text, p_bic text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_iban text;
begin
  v_iban := upper(regexp_replace(coalesce(p_iban,''), '\s', '', 'g'));
  if not iban_plausible(v_iban) then
    return jsonb_build_object('ok', false, 'message', 'Cet IBAN ne paraît pas valide.');
  end if;
  if coalesce(trim(p_titulaire),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Indiquez le titulaire du compte.');
  end if;

  insert into coordonnees_bancaires (profil_id, titulaire, iban, bic)
  values (auth.uid(), trim(p_titulaire), v_iban, nullif(upper(trim(p_bic)),''))
  on conflict (profil_id) do update
    set titulaire = excluded.titulaire, iban = excluded.iban,
        bic = excluded.bic, maj_le = now();

  return jsonb_build_object('ok', true);
end $$;

-- Le trésorier lit l'IBAN au moment de payer, et la lecture est tracée.
create or replace function lire_rib(p_note uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_profil uuid; r coordonnees_bancaires;
begin
  if not a_droit('finance.payer') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au paiement.');
  end if;
  select profil_id into v_profil from notes_frais where id = p_note;
  select * into r from coordonnees_bancaires where profil_id = v_profil;
  if r is null then
    return jsonb_build_object('ok', false, 'message', 'Aucune coordonnée bancaire enregistrée.');
  end if;

  insert into acces_rib (lecteur, profil_id, note_id) values (auth.uid(), v_profil, p_note);
  insert into journal (acteur, action, cible) values (auth.uid(), 'rib_consulte', v_profil::text);

  return jsonb_build_object('ok', true, 'titulaire', r.titulaire,
                            'iban', r.iban, 'bic', r.bic);
end $$;

-- Chacun sait si ses coordonnées sont enregistrées, sans les réafficher.
create or replace function mon_rib()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
      'enregistre', true, 'titulaire', titulaire,
      'iban_masque', left(iban,4) || ' •••• ' || right(iban,4),
      'maj_le', maj_le,
      'consultations', (select count(*) from acces_rib a where a.profil_id = auth.uid()))
    from coordonnees_bancaires where profil_id = auth.uid()),
    jsonb_build_object('enregistre', false));
$$;

-- ---------------------------------------------------------------------
-- 2. LE CIRCUIT, REVU
-- ---------------------------------------------------------------------

alter table notes_frais drop constraint if exists notes_frais_statut_check;
alter table notes_frais add constraint notes_frais_statut_check
  check (statut in ('brouillon','deposee','instruite','ordonnancee','payee','refusee'));

alter table notes_frais add column if not exists mode_remboursement text
  not null default 'virement'
  check (mode_remboursement in ('virement','abandon_creance'));
alter table notes_frais add column if not exists ordonnance_par uuid references profils(id);
alter table notes_frais add column if not exists ordonnance_le timestamptz;
alter table notes_frais add column if not exists imputation text;   -- ligne budgétaire
alter table notes_frais add column if not exists recu_fiscal text;  -- abandon de créance
alter table notes_frais add column if not exists avis_par uuid references profils(id);
alter table notes_frais add column if not exists avis_le timestamptz;

-- On déplace l'ancien avis hiérarchique dans ses propres colonnes.
update notes_frais set avis_par = instruit_par, avis_le = instruit_le
 where avis is not null and avis_par is null;

create or replace function est_ordonnateur()
returns boolean language sql stable security definer set search_path = public as $$
  select a_droit('finance.ordonnancer');
$$;

-- L'avis hiérarchique : facultatif, jamais bloquant, toujours conservé.
create or replace function donner_avis(p_note uuid, p_favorable boolean, p_avis text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not puis_je_instruire(p_note) then
    return jsonb_build_object('ok', false, 'message', 'Cette note ne relève pas de votre périmètre.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'deposee') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''attend pas d''avis.');
  end if;
  if not p_favorable and coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un avis défavorable doit être motivé.');
  end if;

  update notes_frais
     set avis = case when p_favorable then coalesce(nullif(trim(p_avis),''), 'Avis favorable')
                     else 'Avis défavorable — ' || trim(p_avis) end,
         avis_par = auth.uid(), avis_le = now()
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_avis', p_note::text, jsonb_build_object('favorable', p_favorable));
  return jsonb_build_object('ok', true);
end $$;

-- INSTRUCTION : contrôle de forme, par la direction financière.
create or replace function instruire_note(p_note uuid, p_favorable boolean, p_avis text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('finance.instruire') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'deposee') then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est pas en attente d''instruction.');
  end if;
  if not p_favorable and coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un rejet doit être motivé.');
  end if;

  update notes_frais
     set statut = case when p_favorable then 'instruite' else 'refusee' end,
         instruit_par = auth.uid(), instruit_le = now(),
         imputation = nullif(trim(p_avis),''),
         motif_refus = case when p_favorable then null else trim(p_avis) end
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_instruite', p_note::text,
          jsonb_build_object('favorable', p_favorable));
  return jsonb_build_object('ok', true);
end $$;

-- ORDONNANCEMENT : la décision d'engager la dépense.
create or replace function ordonnancer_note(p_note uuid, p_ok boolean, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n notes_frais;
begin
  if not est_ordonnateur() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''ordonnateur.');
  end if;
  select * into n from notes_frais where id = p_note;
  if n is null or n.statut <> 'instruite' then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''a pas été instruite.');
  end if;
  if n.profil_id = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez pas ordonnancer votre propre note de frais.');
  end if;
  if n.instruit_par = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Vous avez instruit cette note : un autre ordonnateur doit l''engager.');
  end if;
  if not p_ok and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus doit être motivé.');
  end if;

  update notes_frais
     set statut = case when p_ok then 'ordonnancee' else 'refusee' end,
         ordonnance_par = auth.uid(), ordonnance_le = now(),
         motif_refus = case when p_ok then null else trim(p_motif) end
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_ordonnancee', p_note::text, jsonb_build_object('accord', p_ok));
  return jsonb_build_object('ok', true);
end $$;

-- PAIEMENT : l'exécution, par la direction financière.
create or replace function payer_note(p_note uuid, p_reference text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n notes_frais;
begin
  if not a_droit('finance.payer') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au paiement.');
  end if;
  select * into n from notes_frais where id = p_note;
  if n is null or n.statut <> 'ordonnancee' then
    return jsonb_build_object('ok', false,
      'message', 'Cette note n''a pas été ordonnancée. Aucun paiement possible.');
  end if;
  if n.ordonnance_par = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Vous avez ordonnancé cette dépense : le paiement revient à un autre.');
  end if;
  if n.profil_id = auth.uid() then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez pas payer votre propre note de frais.');
  end if;

  update notes_frais
     set statut = 'payee', payee_le = now(),
         valide_par = auth.uid(), valide_le = now(),
         reference_paiement = nullif(trim(p_reference),''),
         recu_fiscal = case when n.mode_remboursement = 'abandon_creance'
                            then 'RF-' || to_char(now(),'YYYY') || '-' || right(n.reference, 4)
                            else null end
   where id = p_note;

  insert into journal (acteur, action, cible) values (auth.uid(), 'note_payee', p_note::text);
  return jsonb_build_object('ok', true);
end $$;

-- La fonction valider_note n'a plus de raison d'être : le circuit passe
-- désormais par l'ordonnancement.
drop function if exists valider_note(uuid, boolean, text);

-- DÉPÔT : on exige un IBAN si le remboursement est demandé.
create or replace function deposer_note(p_note uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_total numeric; v_lignes int; v_sans int; v_plafond numeric; n notes_frais;
begin
  select * into n from notes_frais where id = p_note and profil_id = auth.uid();
  if n is null or n.statut <> 'brouillon' then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est plus modifiable.');
  end if;

  select count(*) into v_lignes from nf_lignes where note_id = p_note;
  if v_lignes = 0 then
    return jsonb_build_object('ok', false, 'message', 'Ajoutez au moins une dépense.');
  end if;

  select count(*) into v_sans from nf_lignes
   where note_id = p_note and categorie <> 'kilometres'
     and coalesce(justificatif,'') = '';
  if v_sans > 0 then
    return jsonb_build_object('ok', false,
      'message', v_sans || ' dépense(s) sans justificatif. Joignez-les avant de déposer.');
  end if;

  if n.mode_remboursement = 'virement'
     and not exists (select 1 from coordonnees_bancaires where profil_id = auth.uid()) then
    return jsonb_build_object('ok', false,
      'message', 'Enregistrez vos coordonnées bancaires, ou choisissez l''abandon de créance.');
  end if;

  v_total := total_note(p_note);
  select valeur into v_plafond from parametres_frais where cle = 'plafond_note';
  if v_total > v_plafond then
    return jsonb_build_object('ok', false,
      'message', 'Cette note dépasse le plafond de ' || v_plafond || ' €.');
  end if;

  update notes_frais set statut = 'deposee', deposee_le = now() where id = p_note;
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_deposee', p_note::text,
          jsonb_build_object('total', v_total, 'mode', n.mode_remboursement));

  return jsonb_build_object('ok', true, 'total', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 3. LA VUE, REVUE
-- ---------------------------------------------------------------------

drop function if exists v_notes(text);
create or replace function v_notes(p_filtre text default 'miennes')
returns table (
  id uuid, reference text, objet text, statut text, total numeric,
  nb_lignes integer, cree_le timestamptz, deposee_le timestamptz,
  profil_id uuid, deposant text, matricule text, territoire_nom text,
  groupe_nom text, avis text, imputation text, motif_refus text,
  reference_paiement text, recu_fiscal text, mode_remboursement text,
  avis_nom text, instruit_nom text, ordonnance_nom text, paye_nom text,
  a_un_rib boolean
) language sql stable security definer set search_path = public as $$
  select n.id, n.reference, n.objet, n.statut, total_note(n.id),
         (select count(*)::int from nf_lignes l where l.note_id = n.id),
         n.cree_le, n.deposee_le,
         n.profil_id, trim(p.prenom || ' ' || p.nom), p.matricule, t.nom,
         g.nom, n.avis, n.imputation, n.motif_refus,
         n.reference_paiement, n.recu_fiscal, n.mode_remboursement,
         trim(av.prenom || ' ' || av.nom), trim(i.prenom || ' ' || i.nom),
         trim(o.prenom || ' ' || o.nom), trim(v.prenom || ' ' || v.nom),
         exists (select 1 from coordonnees_bancaires cb where cb.profil_id = n.profil_id)
  from notes_frais n
  join profils p on p.id = n.profil_id
  left join territoires t     on t.id = p.territoire_id
  left join groupes_travail g on g.id = n.groupe_id
  left join profils av on av.id = n.avis_par
  left join profils i  on i.id  = n.instruit_par
  left join profils o  on o.id  = n.ordonnance_par
  left join profils v  on v.id  = n.valide_par
  where case p_filtre
    when 'miennes'     then n.profil_id = auth.uid()
    when 'avis'        then n.statut = 'deposee' and puis_je_instruire(n.id)
    when 'instruire'   then n.statut = 'deposee' and a_droit('finance.instruire')
    when 'ordonnancer' then n.statut = 'instruite' and est_ordonnateur()
    when 'payer'       then n.statut = 'ordonnancee' and a_droit('finance.payer')
    when 'toutes'      then a_droit('finance.instruire') or a_droit('finance.payer')
                            or est_ordonnateur() or est_admin()
    else false end
  order by n.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 4. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table coordonnees_bancaires enable row level security;
alter table acces_rib             enable row level security;

-- Personne ne lit l'IBAN d'un autre par requête directe. Le trésorier
-- passe par lire_rib(), qui trace.
drop policy if exists lire_rib_soi on coordonnees_bancaires;
create policy lire_rib_soi on coordonnees_bancaires for select
  using (profil_id = auth.uid());
drop policy if exists ecrire_rib_soi on coordonnees_bancaires;
create policy ecrire_rib_soi on coordonnees_bancaires for all
  using (profil_id = auth.uid()) with check (profil_id = auth.uid());

-- Chacun voit qui a consulté ses coordonnées. Droit RGPD.
drop policy if exists lire_acces_rib on acces_rib;
create policy lire_acces_rib on acces_rib for select
  using (profil_id = auth.uid() or est_admin() or a_droit('rgpd.alertes'));

-- Le déposant choisit son mode de remboursement tant que la note est
-- en brouillon.
drop policy if exists lire_notes on notes_frais;
create policy lire_notes on notes_frais for select using (
  profil_id = auth.uid() or a_droit('finance.instruire') or a_droit('finance.payer')
  or est_ordonnateur() or puis_je_instruire(id)
);

grant select on coordonnees_bancaires, acces_rib to authenticated;
grant insert, update, delete on coordonnees_bancaires to authenticated;

grant execute on function iban_plausible(text), enregistrer_rib(text, text, text),
                          lire_rib(uuid), mon_rib(), est_ordonnateur(),
                          donner_avis(uuid, boolean, text),
                          instruire_note(uuid, boolean, text),
                          ordonnancer_note(uuid, boolean, text),
                          payer_note(uuid, text), deposer_note(uuid), v_notes(text)
  to authenticated;

-- ---------------------------------------------------------------------
-- 5. DEUX APPLICATIONS DISTINCTES
--    Elles ne s'ouvrent pas au même poste. C'est visible à l'écran,
--    et c'est le but : la séparation doit se voir.
-- ---------------------------------------------------------------------

update applications
   set nom = 'Direction financière',
       description = 'Instruire les notes de frais et exécuter les paiements.',
       droit_requis = 'finance.instruire'
 where code = 'tresorerie';

insert into applications (code, nom, description, icone, niveau_min, sur_demande,
                          droit_requis, ordre)
values ('ordonnancement', 'Ordonnancement',
        'Décider d''engager les dépenses instruites par la direction financière.',
        'stamp', 100, true, 'finance.ordonnancer', 62)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      droit_requis = excluded.droit_requis, ordre = excluded.ordre;

-- =====================================================================
--  FIN DE LA MIGRATION 09
--
--  Pour nommer une direction financière et un ordonnateur — deux
--  personnes différentes, sans quoi la séparation ne sert à rien :
--
--    select nommer((select id from profils where email='tresorier@…'),
--                  'dg_finance', null, null, 'Élu au bureau');
--    select nommer((select id from profils where email='president@…'),
--                  'ordonnateur', null, null, 'Président, ordonnateur de droit');
--
--  Trois incompatibilités sont vérifiées en base, pas dans l'interface :
--    — nul n'ordonnance sa propre note ;
--    — qui a instruit ne peut pas ordonnancer ;
--    — qui a ordonnancé ne peut pas payer.
-- =====================================================================
