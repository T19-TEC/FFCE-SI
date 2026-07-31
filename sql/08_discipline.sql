-- =====================================================================
--  FFCE — Migration 08 — DISCIPLINE, RECOURS ET ARCHIVES
--
--  Un télérecours interne. Le principe qui gouverne tout le module :
--  aucune mesure ne produit d'effet sans avoir été notifiée, et aucune
--  notification n'est valable sans voie de recours ouverte.
--
--  Le circuit :
--    saisine ou signalement  →  DOSSIER
--    instruction (DAJ, référent)  →  PIÈCES versées, contradictoire
--    décision (conseil de discipline)  →  MESURE motivée
--    notification à l'intéressé  →  délai de recours ouvert
--    RECOURS GRACIEUX  →  décision motivée, versée au dossier
--    clôture  →  ARCHIVE, jamais effacée
--
--  Un compte suspendu n'est pas un compte fermé : son titulaire se
--  connecte toujours, pour voir où en est son dossier et exercer ses
--  droits. Rien d'autre.
--
--  Prérequis : 01 à 07.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DOSSIERS
-- ---------------------------------------------------------------------

create sequence if not exists seq_dossier start 1;

create table if not exists dossiers (
  id             uuid primary key default gen_random_uuid(),
  reference      text unique not null default 'D-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_dossier')::text, 4, '0'),
  profil_id      uuid not null references profils(id) on delete restrict,
  origine        text not null default 'saisine'
                   check (origine in ('signalement','saisine','plainte_externe','controle')),
  signalement_id uuid references signalements(id) on delete set null,
  objet          text not null,
  qualification  text,        -- ce qui est reproché, en termes du règlement
  gravite        text not null default 'moyenne'
                   check (gravite in ('faible','moyenne','elevee')),
  statut         text not null default 'ouvert' check (statut in
                   ('ouvert','instruction','decision','notifie','recours','clos')),
  instructeur_id uuid references profils(id),
  ouvert_par     uuid references profils(id),
  ouvert_le      timestamptz not null default now(),
  clos_le        timestamptz,
  clos_par       uuid references profils(id),
  conclusion     text
);
create index if not exists idx_dos_profil on dossiers(profil_id);
create index if not exists idx_dos_statut on dossiers(statut);

-- ---------------------------------------------------------------------
-- 2. LES PIÈCES
--    Chaque pièce est marquée communicable ou non. Une pièce
--    communicable est visible de l'intéressé : c'est le contradictoire.
--    Une pièce non communicable protège un témoin — elle existe, elle
--    est datée, mais son contenu n'est pas ouvert.
-- ---------------------------------------------------------------------

create table if not exists dossier_pieces (
  id           uuid primary key default gen_random_uuid(),
  dossier_id   uuid not null references dossiers(id) on delete cascade,
  type         text not null check (type in
                 ('signalement','observation','temoignage','piece_jointe',
                  'note_instruction','convocation','decision','notification',
                  'recours','reponse_recours','alerte_suivi')),
  titre        text not null,
  contenu      text,
  fichier      text,                        -- chemin dans le dépôt privé
  auteur_id    uuid references profils(id),
  communicable boolean not null default true,
  cree_le      timestamptz not null default now()
);
create index if not exists idx_pieces_dossier on dossier_pieces(dossier_id, cree_le);

-- ---------------------------------------------------------------------
-- 3. LES MESURES
--    Sept degrés, du classement à la radiation. Le suivi des usages
--    est une mesure comme une autre : elle se prononce, se motive,
--    se notifie, et se conteste.
-- ---------------------------------------------------------------------

create table if not exists mesures (
  id             uuid primary key default gen_random_uuid(),
  dossier_id     uuid not null references dossiers(id) on delete cascade,
  type           text not null check (type in
                   ('classement','rappel_regles','avertissement','suivi_usages',
                    'retrait_habilitation','suspension','radiation')),
  motif          text not null,
  texte_decision text,
  date_effet     date not null default current_date,
  date_fin       date,                       -- null = sans terme
  statut         text not null default 'prononcee' check (statut in
                   ('prononcee','notifiee','executee','suspendue','annulee','echue')),
  prise_par      uuid references profils(id),
  prise_le       timestamptz not null default now(),
  notifiee_le    timestamptz,
  accusee_le     timestamptz,                -- accusé de réception de l'intéressé
  delai_recours  integer not null default 30,-- jours
  cree_le        timestamptz not null default now()
);
create index if not exists idx_mesures_dossier on mesures(dossier_id);

-- La date limite de recours : elle court à compter de l'accusé de
-- réception, ou à défaut quinze jours après la notification.
create or replace function limite_recours(m mesures)
returns date language sql immutable as $$
  select case
    when m.notifiee_le is null then null
    else (coalesce(m.accusee_le, m.notifiee_le + interval '15 days')
          + (m.delai_recours || ' days')::interval)::date
  end;
$$;

create or replace function recours_ouvert(m mesures)
returns boolean language sql stable as $$
  select m.notifiee_le is not null
     and m.type <> 'classement'
     and m.statut not in ('annulee','echue')
     and (limite_recours(m) is null or limite_recours(m) >= current_date);
$$;

-- ---------------------------------------------------------------------
-- 4. LES RECOURS
-- ---------------------------------------------------------------------

create table if not exists recours (
  id          uuid primary key default gen_random_uuid(),
  mesure_id   uuid not null references mesures(id) on delete cascade,
  auteur_id   uuid not null references profils(id) on delete cascade,
  contenu     text not null,
  fichier     text,
  statut      text not null default 'depose' check (statut in
                ('depose','recevable','irrecevable','accepte','rejete','partiel')),
  decision    text,
  decide_par  uuid references profils(id),
  decide_le   timestamptz,
  suspensif   boolean not null default false, -- suspend-il l'exécution ?
  cree_le     timestamptz not null default now()
);
create index if not exists idx_recours_mesure on recours(mesure_id);

-- ---------------------------------------------------------------------
-- 5. SUIVI DES USAGES
--    Une mesure de suivi place le compte sous observation. Chaque
--    ouverture d'application remonte alors en alerte à la direction.
-- ---------------------------------------------------------------------

alter table profils add column if not exists sous_suivi boolean not null default false;

create table if not exists alertes_suivi (
  id          bigserial primary key,
  profil_id   uuid not null references profils(id) on delete cascade,
  mesure_id   uuid references mesures(id) on delete set null,
  application text,
  detail      text,
  vue_par     uuid references profils(id),
  vue_le      timestamptz,
  cree_le     timestamptz not null default now()
);
create index if not exists idx_as_vue on alertes_suivi(vue_le);

create or replace function tracer_suivi()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_mesure uuid;
begin
  if not exists (select 1 from profils where id = new.profil_id and sous_suivi) then
    return new;
  end if;
  select m.id into v_mesure
    from mesures m join dossiers d on d.id = m.dossier_id
   where d.profil_id = new.profil_id and m.type = 'suivi_usages'
     and m.statut = 'executee'
   order by m.prise_le desc limit 1;

  insert into alertes_suivi (profil_id, mesure_id, application, detail)
  values (new.profil_id, v_mesure, new.application, 'Ouverture de l''application');
  return new;
end $$;

drop trigger if exists trg_tracer_suivi on journal_acces;
create trigger trg_tracer_suivi
  after insert on journal_acces
  for each row execute function tracer_suivi();

-- ---------------------------------------------------------------------
-- 6. EFFETS D'UNE MESURE SUR LE COMPTE
--    Une mesure ne produit d'effet qu'une fois EXÉCUTÉE, et elle ne
--    peut l'être qu'après notification. C'est la règle cardinale.
-- ---------------------------------------------------------------------

create or replace function appliquer_mesure()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'executee' and coalesce(old.statut,'') <> 'executee' then
    if new.type = 'suspension' then
      update profils set statut = 'suspendu'
       where id = (select profil_id from dossiers where id = new.dossier_id);
    elsif new.type = 'radiation' then
      update profils set statut = 'archive'
       where id = (select profil_id from dossiers where id = new.dossier_id);
    elsif new.type = 'suivi_usages' then
      update profils set sous_suivi = true
       where id = (select profil_id from dossiers where id = new.dossier_id);
    elsif new.type = 'retrait_habilitation' then
      update nominations set revoque_le = now(), motif_revocation = 'Mesure disciplinaire'
       where profil_id = (select profil_id from dossiers where id = new.dossier_id)
         and revoque_le is null;
      update acces_applications set statut = 'revoque', revoque_le = now(),
             motif_revocation = 'Mesure disciplinaire'
       where profil_id = (select profil_id from dossiers where id = new.dossier_id)
         and statut = 'accorde';
    end if;
  end if;

  -- Levée : la mesure est annulée, échue, ou suspendue par un recours.
  if new.statut in ('annulee','echue','suspendue')
     and coalesce(old.statut,'') = 'executee' then
    if new.type = 'suspension' then
      update profils set statut = 'actif'
       where id = (select profil_id from dossiers where id = new.dossier_id)
         and statut = 'suspendu';
    elsif new.type = 'suivi_usages' then
      update profils set sous_suivi = false
       where id = (select profil_id from dossiers where id = new.dossier_id);
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_appliquer_mesure on mesures;
create trigger trg_appliquer_mesure
  after update on mesures
  for each row execute function appliquer_mesure();

-- Les mesures à terme s'éteignent seules.
create or replace function echoir_mesures()
returns integer language sql security definer set search_path = public as $$
  with maj as (
    update mesures set statut = 'echue'
     where statut = 'executee' and date_fin is not null and date_fin < current_date
    returning 1)
  select count(*)::int from maj;
$$;

-- ---------------------------------------------------------------------
-- 7. LE CIRCUIT
-- ---------------------------------------------------------------------

create or replace function ouvrir_dossier(
  p_profil uuid, p_objet text, p_qualification text default null,
  p_gravite text default 'moyenne', p_signalement uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not a_droit('discipline.saisir') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pouvez pas ouvrir de dossier.');
  end if;
  if coalesce(trim(p_objet),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'L''objet du dossier est obligatoire.');
  end if;

  insert into dossiers (profil_id, objet, qualification, gravite, ouvert_par,
                        origine, signalement_id)
  values (p_profil, trim(p_objet), nullif(trim(p_qualification),''), p_gravite, auth.uid(),
          case when p_signalement is null then 'saisine' else 'signalement' end,
          p_signalement)
  returning id into v_id;

  -- Le dossier ouvert place l'intéressé sous protection renforcée :
  -- toute consultation de son profil sera désormais tracée.
  update profils set protege = true,
         motif_protection = coalesce(motif_protection, 'Dossier disciplinaire en cours')
   where id = p_profil;

  if p_signalement is not null then
    insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
    select v_id, 'signalement', 'Signalement à l''origine du dossier',
           coalesce(s.details, ''), s.auteur_id, false
    from signalements s where s.id = p_signalement;

    update signalements set statut = 'en_cours' where id = p_signalement;
  end if;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'dossier_ouvert', v_id::text,
          jsonb_build_object('concerne', p_profil, 'gravite', p_gravite));

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function verser_piece(
  p_dossier uuid, p_type text, p_titre text, p_contenu text default null,
  p_fichier text default null, p_communicable boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_concerne uuid;
begin
  select profil_id into v_concerne from dossiers where id = p_dossier;

  -- L'intéressé verse ses observations. Elles sont toujours
  -- communicables : ce sont les siennes.
  if v_concerne = auth.uid() then
    if p_type not in ('observation','piece_jointe','recours') then
      return jsonb_build_object('ok', false,
        'message', 'Vous pouvez déposer des observations et des pièces.');
    end if;
    insert into dossier_pieces (dossier_id, type, titre, contenu, fichier, auteur_id, communicable)
    values (p_dossier, p_type, trim(p_titre), p_contenu, p_fichier, auth.uid(), true);
    return jsonb_build_object('ok', true);
  end if;

  if not a_droit('discipline.instruire') then
    return jsonb_build_object('ok', false, 'message', 'Vous n''instruisez pas ce dossier.');
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, fichier, auteur_id, communicable)
  values (p_dossier, p_type, trim(p_titre), p_contenu, p_fichier, auth.uid(),
          coalesce(p_communicable, true));

  update dossiers set statut = 'instruction'
   where id = p_dossier and statut = 'ouvert';

  return jsonb_build_object('ok', true);
end $$;

create or replace function prononcer_mesure(
  p_dossier uuid, p_type text, p_motif text, p_texte text default null,
  p_effet date default null, p_fin date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne prononcez pas de mesure.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Toute mesure doit être motivée.');
  end if;

  insert into mesures (dossier_id, type, motif, texte_decision, date_effet, date_fin, prise_par)
  values (p_dossier, p_type, trim(p_motif), nullif(trim(p_texte),''),
          coalesce(p_effet, current_date), p_fin, auth.uid())
  returning id into v_id;

  insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
  values (p_dossier, 'decision', 'Décision : ' || p_type,
          trim(p_motif) || coalesce(E'\n\n' || p_texte, ''), auth.uid(), true);

  update dossiers set statut = 'decision' where id = p_dossier;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'mesure_prononcee', v_id::text, jsonb_build_object('type', p_type));

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Notifier, c'est ouvrir le délai de recours. Une mesure notifiée
-- devient exécutoire, sauf le classement, qui n'exécute rien.
create or replace function notifier_mesure(p_mesure uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_dossier uuid; v_type text;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au conseil de discipline.');
  end if;
  select dossier_id, type into v_dossier, v_type from mesures where id = p_mesure;

  update mesures
     set notifiee_le = now(),
         statut = case when type = 'classement' then 'echue' else 'executee' end
   where id = p_mesure and notifiee_le is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Mesure déjà notifiée.');
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
  values (v_dossier, 'notification', 'Notification de la décision',
          'La décision vous a été notifiée. Vous disposez d''un délai de recours gracieux.',
          auth.uid(), true);

  update dossiers set statut = 'notifie' where id = v_dossier;
  return jsonb_build_object('ok', true);
end $$;

-- L'intéressé accuse réception : le délai de recours part de là.
create or replace function accuser_reception(p_mesure uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update mesures m set accusee_le = now()
   where m.id = p_mesure and m.accusee_le is null
     and exists (select 1 from dossiers d where d.id = m.dossier_id
                 and d.profil_id = auth.uid());
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Réception déjà accusée.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function deposer_recours(
  p_mesure uuid, p_contenu text, p_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m mesures; v_dossier uuid;
begin
  select * into m from mesures where id = p_mesure;
  if m is null then
    return jsonb_build_object('ok', false, 'message', 'Mesure introuvable.');
  end if;
  if not exists (select 1 from dossiers d where d.id = m.dossier_id and d.profil_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Cette mesure ne vous concerne pas.');
  end if;
  if not recours_ouvert(m) then
    return jsonb_build_object('ok', false,
      'message', 'Le délai de recours est clos ou la mesure n''a pas été notifiée.');
  end if;
  if coalesce(trim(p_contenu),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Exposez les motifs de votre recours.');
  end if;
  if exists (select 1 from recours where mesure_id = p_mesure
             and auteur_id = auth.uid() and statut in ('depose','recevable')) then
    return jsonb_build_object('ok', false, 'message', 'Un recours est déjà en cours d''examen.');
  end if;

  insert into recours (mesure_id, auteur_id, contenu, fichier)
  values (p_mesure, auth.uid(), trim(p_contenu), p_fichier);

  insert into dossier_pieces (dossier_id, type, titre, contenu, fichier, auteur_id, communicable)
  values (m.dossier_id, 'recours', 'Recours gracieux', trim(p_contenu), p_fichier, auth.uid(), true);

  update dossiers set statut = 'recours' where id = m.dossier_id;

  insert into journal (acteur, action, cible)
  values (auth.uid(), 'recours_depose', p_mesure::text);

  return jsonb_build_object('ok', true);
end $$;

create or replace function statuer_recours(
  p_recours uuid, p_issue text, p_decision text, p_suspensif boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r recours; v_dossier uuid;
begin
  if not a_droit('discipline.recours') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne statuez pas sur les recours.');
  end if;
  if coalesce(trim(p_decision),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'La décision doit être motivée.');
  end if;

  select * into r from recours where id = p_recours;
  select dossier_id into v_dossier from mesures where id = r.mesure_id;

  update recours
     set statut = p_issue, decision = trim(p_decision),
         decide_par = auth.uid(), decide_le = now(), suspensif = coalesce(p_suspensif,false)
   where id = p_recours;

  if p_issue = 'accepte' then
    update mesures set statut = 'annulee' where id = r.mesure_id;
  elsif coalesce(p_suspensif,false) then
    update mesures set statut = 'suspendue' where id = r.mesure_id;
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
  values (v_dossier, 'reponse_recours', 'Décision sur recours gracieux',
          trim(p_decision), auth.uid(), true);

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'recours_statue', p_recours::text, jsonb_build_object('issue', p_issue));

  return jsonb_build_object('ok', true);
end $$;

create or replace function clore_dossier(p_dossier uuid, p_conclusion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_concerne uuid;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au conseil de discipline.');
  end if;
  if coalesce(trim(p_conclusion),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'La clôture doit être motivée.');
  end if;

  update dossiers
     set statut = 'clos', clos_le = now(), clos_par = auth.uid(),
         conclusion = trim(p_conclusion)
   where id = p_dossier
  returning profil_id into v_concerne;

  -- Si plus aucun dossier n'est ouvert, la protection renforcée peut
  -- être levée — sauf si elle avait un autre motif.
  if not exists (select 1 from dossiers where profil_id = v_concerne and statut <> 'clos') then
    update profils set protege = false, motif_protection = null
     where id = v_concerne and motif_protection = 'Dossier disciplinaire en cours';
  end if;

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 8. CE QUE VOIT L'INTÉRESSÉ
--    Une seule fonction, appelée par la page qui s'affiche à un compte
--    suspendu comme par le bandeau d'un compte actif.
-- ---------------------------------------------------------------------

create or replace function mon_dossier()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'statut_compte', (select statut from profils where id = auth.uid()),
    'sous_suivi',    (select sous_suivi from profils where id = auth.uid()),
    'dossiers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'reference', d.reference, 'objet', d.objet,
        'qualification', d.qualification, 'gravite', d.gravite,
        'statut', d.statut, 'ouvert_le', d.ouvert_le,
        'clos_le', d.clos_le, 'conclusion', d.conclusion,
        'pieces', coalesce((
          select jsonb_agg(jsonb_build_object(
            'type', pc.type, 'titre', pc.titre, 'contenu', pc.contenu,
            'fichier', pc.fichier, 'cree_le', pc.cree_le)
            order by pc.cree_le)
          from dossier_pieces pc
          where pc.dossier_id = d.id and pc.communicable), '[]'::jsonb),
        'pieces_non_communicables', (
          select count(*) from dossier_pieces pc
          where pc.dossier_id = d.id and not pc.communicable),
        'mesures', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', m.id, 'type', m.type, 'motif', m.motif,
            'texte', m.texte_decision, 'statut', m.statut,
            'date_effet', m.date_effet, 'date_fin', m.date_fin,
            'notifiee_le', m.notifiee_le, 'accusee_le', m.accusee_le,
            'limite_recours', limite_recours(m),
            'recours_ouvert', recours_ouvert(m),
            'recours', coalesce((
              select jsonb_agg(jsonb_build_object(
                'contenu', rc.contenu, 'statut', rc.statut,
                'decision', rc.decision, 'cree_le', rc.cree_le,
                'decide_le', rc.decide_le) order by rc.cree_le)
              from recours rc where rc.mesure_id = m.id), '[]'::jsonb))
            order by m.prise_le desc)
          from mesures m where m.dossier_id = d.id and m.notifiee_le is not null),
          '[]'::jsonb))
        order by d.ouvert_le desc)
      from dossiers d where d.profil_id = auth.uid()), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------
-- 9. CE QUE VOIT L'INSTRUCTION
-- ---------------------------------------------------------------------

create or replace function dossiers_discipline(p_filtre text default 'ouverts')
returns table (
  id uuid, reference text, objet text, qualification text, gravite text,
  statut text, origine text, ouvert_le timestamptz, clos_le timestamptz,
  conclusion text, profil_id uuid, concerne text, matricule text,
  territoire_nom text, instructeur text, nb_pieces integer, nb_mesures integer,
  recours_en_attente integer
) language sql stable security definer set search_path = public as $$
  select d.id, d.reference, d.objet, d.qualification, d.gravite, d.statut,
         d.origine, d.ouvert_le, d.clos_le, d.conclusion,
         d.profil_id, trim(p.prenom || ' ' || p.nom), p.matricule, t.nom,
         trim(i.prenom || ' ' || i.nom),
         (select count(*)::int from dossier_pieces x where x.dossier_id = d.id),
         (select count(*)::int from mesures m where m.dossier_id = d.id),
         (select count(*)::int from recours r join mesures m on m.id = r.mesure_id
           where m.dossier_id = d.id and r.statut in ('depose','recevable'))
  from dossiers d
  join profils p on p.id = d.profil_id
  left join territoires t on t.id = p.territoire_id
  left join profils i on i.id = d.instructeur_id
  where (a_droit('discipline.instruire') or a_droit('discipline.decider')
         or a_droit('discipline.recours') or a_droit('discipline.saisir'))
    and case p_filtre
      when 'ouverts'  then d.statut <> 'clos'
      when 'archives' then d.statut = 'clos'
      else true end
  order by
    case d.gravite when 'elevee' then 1 when 'moyenne' then 2 else 3 end,
    d.ouvert_le desc;
$$;

-- =====================================================================
--  10. SÉCURITÉ
-- =====================================================================

alter table dossiers       enable row level security;
alter table dossier_pieces enable row level security;
alter table mesures        enable row level security;
alter table recours        enable row level security;
alter table alertes_suivi  enable row level security;

drop policy if exists lire_dossiers on dossiers;
create policy lire_dossiers on dossiers for select using (
  profil_id = auth.uid() or instructeur_id = auth.uid()
  or a_droit('discipline.instruire') or a_droit('discipline.decider')
  or a_droit('discipline.recours') or a_droit('discipline.saisir')
);
drop policy if exists gerer_dossiers on dossiers;
create policy gerer_dossiers on dossiers for update
  using (a_droit('discipline.instruire')) with check (a_droit('discipline.instruire'));

-- Les pièces non communicables ne sortent pas pour l'intéressé.
drop policy if exists lire_pieces on dossier_pieces;
create policy lire_pieces on dossier_pieces for select using (
  a_droit('discipline.instruire') or a_droit('discipline.decider')
  or a_droit('discipline.recours')
  or (communicable and exists (select 1 from dossiers d
      where d.id = dossier_id and d.profil_id = auth.uid()))
);

drop policy if exists lire_mesures on mesures;
create policy lire_mesures on mesures for select using (
  a_droit('discipline.instruire') or a_droit('discipline.decider')
  or a_droit('discipline.recours')
  or (notifiee_le is not null and exists (select 1 from dossiers d
      where d.id = dossier_id and d.profil_id = auth.uid()))
);

drop policy if exists lire_recours on recours;
create policy lire_recours on recours for select using (
  auteur_id = auth.uid() or a_droit('discipline.recours')
  or a_droit('discipline.instruire') or a_droit('discipline.decider')
);

drop policy if exists lire_alertes_suivi on alertes_suivi;
create policy lire_alertes_suivi on alertes_suivi for select using (
  est_admin() or a_droit('discipline.instruire')
);
drop policy if exists maj_alertes_suivi on alertes_suivi;
create policy maj_alertes_suivi on alertes_suivi for update
  using (est_admin() or a_droit('discipline.instruire'));

-- ---------------------------------------------------------------------
-- 11. DÉPÔT DES PIÈCES
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('dossiers', 'dossiers', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists depot_dossiers on storage.objects;
create policy depot_dossiers on storage.objects for insert to authenticated
  with check (bucket_id = 'dossiers'
              and ((storage.foldername(name))[1] = auth.uid()::text
                   or a_droit('discipline.instruire')));

drop policy if exists lecture_dossiers on storage.objects;
create policy lecture_dossiers on storage.objects for select to authenticated
  using (bucket_id = 'dossiers'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or a_droit('discipline.instruire') or a_droit('discipline.decider')
              or a_droit('discipline.recours')));

-- ---------------------------------------------------------------------
-- 12. DROITS ET APPLICATION
-- ---------------------------------------------------------------------

grant select on dossiers, dossier_pieces, mesures, recours, alertes_suivi
  to authenticated;
grant update on dossiers, alertes_suivi to authenticated;

grant execute on function limite_recours(mesures), recours_ouvert(mesures),
                          ouvrir_dossier(uuid, text, text, text, uuid),
                          verser_piece(uuid, text, text, text, text, boolean),
                          prononcer_mesure(uuid, text, text, text, date, date),
                          notifier_mesure(uuid), accuser_reception(uuid),
                          deposer_recours(uuid, text, text),
                          statuer_recours(uuid, text, text, boolean),
                          clore_dossier(uuid, text), mon_dossier(),
                          dossiers_discipline(text), echoir_mesures()
  to authenticated;

insert into applications (code, nom, description, icone, niveau_min, sur_demande,
                          droit_requis, ordre)
values ('discipline', 'Discipline et recours',
        'Dossiers, mesures, recours gracieux et archives.',
        'scale', 100, true, 'discipline.saisir', 65)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      droit_requis = excluded.droit_requis, ordre = excluded.ordre;

-- =====================================================================
--  FIN DE LA MIGRATION 08
--
--  Pour ouvrir l'accès, nommez quelqu'un à un poste qui porte le droit :
--    Direction des affaires juridiques, Référent discriminations, ou
--    Conseil de discipline. Cela se fait dans l'onglet Habilitations.
--
--  Les mesures à terme s'éteignent seules ; pour forcer le passage :
--    select echoir_mesures();
--
--  Le principe cardinal : aucune mesure ne produit d'effet sans avoir
--  été notifiée, et aucune notification n'est valable sans voie de
--  recours ouverte. Le déclencheur trg_appliquer_mesure garantit le
--  premier point ; la fonction recours_ouvert() garantit le second.
-- =====================================================================
