-- =====================================================================
--  FFCE — Migration 04 — MESSAGERIE
--
--  Conversations privées, conversations de groupe de travail.
--
--  SUPERVISION. Aucun échange n'est hors de portée de la hiérarchie :
--  la Direction générale accède à tout, et un encadrant de niveau
--  référent départemental ou plus accède aux conversations dont un
--  participant relève de son territoire. Cette supervision est
--  annoncée à l'écran, sans exception — c'est une obligation de
--  transparence, et le principe de protection des mineurs.
--
--  Un superviseur LIT. Il n'écrit pas. La politique d'insertion ne
--  l'autorise que pour les participants.
--
--  Prérequis : 01, 02 et 03.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

create table if not exists conversations (
  id        uuid primary key default gen_random_uuid(),
  type      text not null default 'privee' check (type in ('privee','groupe')),
  groupe_id uuid references groupes_travail(id) on delete cascade,
  titre     text,
  cree_par  uuid references profils(id),
  cree_le   timestamptz not null default now(),
  derniere_activite timestamptz not null default now()
);
create unique index if not exists idx_conv_groupe
  on conversations(groupe_id) where groupe_id is not null;

create table if not exists conv_participants (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  profil_id       uuid not null references profils(id) on delete cascade,
  rejoint_le      timestamptz not null default now(),
  lu_jusqu_a      timestamptz not null default 'epoch',
  unique (conversation_id, profil_id)
);
create index if not exists idx_cp_profil on conv_participants(profil_id);
create index if not exists idx_cp_conv   on conv_participants(conversation_id);

create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  auteur_id       uuid not null references profils(id) on delete cascade,
  contenu         text not null check (length(trim(contenu)) > 0),
  cree_le         timestamptz not null default now(),
  retire          boolean not null default false,
  retire_par      uuid references profils(id)
);
create index if not exists idx_msg_conv on messages(conversation_id, cree_le);

-- ---------------------------------------------------------------------
-- 2. QUI VOIT QUOI
--    Fonctions SECURITY DEFINER : sans elles, les politiques de
--    conv_participants s'interrogeraient elles-mêmes.
-- ---------------------------------------------------------------------

create or replace function est_participant(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from conv_participants
                 where conversation_id = p_conv and profil_id = auth.uid());
$$;

-- La supervision. Deux portes, et deux seulement.
create or replace function peut_superviser(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() then true
    when mon_niveau() < 60 then false
    else exists (
      select 1 from conv_participants cp
      join profils p on p.id = cp.profil_id
      where cp.conversation_id = p_conv
        and p.id <> auth.uid()
        and dans_mon_perimetre(p.territoire_id))
  end;
$$;

create or replace function accede_conversation(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select est_participant(p_conv) or peut_superviser(p_conv);
$$;

-- ---------------------------------------------------------------------
-- 3. OUVRIR UNE CONVERSATION
-- ---------------------------------------------------------------------

-- Conversation privée à deux. Si elle existe déjà, on la retrouve.
create or replace function conversation_privee(p_autre uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_conv uuid;
begin
  if p_autre = auth.uid() then
    return jsonb_build_object('ok', false, 'message', 'Choisissez un autre destinataire.');
  end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if not exists (select 1 from profils where id = p_autre and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas actif.');
  end if;

  select c.id into v_conv
  from conversations c
  where c.type = 'privee'
    and (select count(*) from conv_participants x where x.conversation_id = c.id) = 2
    and exists (select 1 from conv_participants x
                where x.conversation_id = c.id and x.profil_id = auth.uid())
    and exists (select 1 from conv_participants x
                where x.conversation_id = c.id and x.profil_id = p_autre)
  limit 1;

  if v_conv is null then
    insert into conversations (type, cree_par) values ('privee', auth.uid())
    returning id into v_conv;
    insert into conv_participants (conversation_id, profil_id)
    values (v_conv, auth.uid()), (v_conv, p_autre);
  end if;

  return jsonb_build_object('ok', true, 'id', v_conv);
end $$;

-- Conversation d'un groupe de travail. Les participants suivent
-- toujours la liste des membres actifs du groupe.
create or replace function conversation_groupe(p_groupe uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_conv uuid; v_nom text;
begin
  if not est_membre_gt(p_groupe) and not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Vous ne participez pas à ce groupe.');
  end if;

  select id into v_conv from conversations where groupe_id = p_groupe;
  if v_conv is null then
    select nom into v_nom from groupes_travail where id = p_groupe;
    insert into conversations (type, groupe_id, titre, cree_par)
    values ('groupe', p_groupe, v_nom, auth.uid())
    returning id into v_conv;
  end if;

  -- Synchronisation : on ajoute les membres actifs qui manquent.
  insert into conv_participants (conversation_id, profil_id)
  select v_conv, m.profil_id from gt_membres m
  where m.groupe_id = p_groupe and m.statut = 'actif'
  on conflict (conversation_id, profil_id) do nothing;

  -- Et on retire ceux qui ont quitté le groupe.
  delete from conv_participants cp
  where cp.conversation_id = v_conv
    and not exists (select 1 from gt_membres m
                    where m.groupe_id = p_groupe and m.profil_id = cp.profil_id
                      and m.statut = 'actif');

  return jsonb_build_object('ok', true, 'id', v_conv);
end $$;

-- ---------------------------------------------------------------------
-- 4. ÉCRIRE ET LIRE
-- ---------------------------------------------------------------------

create or replace function envoyer_message(p_conv uuid, p_contenu text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_participant(p_conv) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne participez pas à cette conversation.');
  end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if coalesce(trim(p_contenu),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Message vide.');
  end if;

  insert into messages (conversation_id, auteur_id, contenu)
  values (p_conv, auth.uid(), trim(p_contenu));

  update conversations set derniere_activite = now() where id = p_conv;
  update conv_participants set lu_jusqu_a = now()
   where conversation_id = p_conv and profil_id = auth.uid();

  return jsonb_build_object('ok', true);
end $$;

create or replace function marquer_lu(p_conv uuid)
returns void language sql security definer set search_path = public as $$
  update conv_participants set lu_jusqu_a = now()
   where conversation_id = p_conv and profil_id = auth.uid();
$$;

-- Mes conversations, avec le dernier message et le non-lu.
create or replace function mes_conversations()
returns table (
  id uuid, type text, groupe_id uuid, titre text,
  derniere_activite timestamptz, dernier_message text,
  dernier_auteur uuid, non_lus integer, superviseur boolean
) language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.groupe_id,
         coalesce(c.titre, (
           select string_agg(trim(p.prenom || ' ' || p.nom), ', ')
           from conv_participants x join profils p on p.id = x.profil_id
           where x.conversation_id = c.id and x.profil_id <> auth.uid())),
         c.derniere_activite,
         (select m.contenu from messages m where m.conversation_id = c.id
            and not m.retire order by m.cree_le desc limit 1),
         (select m.auteur_id from messages m where m.conversation_id = c.id
            and not m.retire order by m.cree_le desc limit 1),
         (select count(*)::int from messages m
           where m.conversation_id = c.id and not m.retire
             and m.auteur_id <> auth.uid()
             and m.cree_le > coalesce(cp.lu_jusqu_a, 'epoch')),
         cp.id is null
  from conversations c
  left join conv_participants cp
         on cp.conversation_id = c.id and cp.profil_id = auth.uid()
  where cp.id is not null or peut_superviser(c.id)
  order by c.derniere_activite desc;
$$;

-- Les personnes présentes dans une conversation.
create or replace function participants_conversation(p_conv uuid)
returns table (profil_id uuid, prenom text, nom text, matricule text,
               fonction_nom text, territoire_nom text)
language sql stable security definer set search_path = public as $$
  select p.id, p.prenom, p.nom, p.matricule, f.nom, t.nom
  from conv_participants cp
  join profils p     on p.id = cp.profil_id
  join fonctions f   on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where cp.conversation_id = p_conv
    and accede_conversation(p_conv);
$$;

-- =====================================================================
--  5. SÉCURITÉ
-- =====================================================================

alter table conversations     enable row level security;
alter table conv_participants enable row level security;
alter table messages          enable row level security;

drop policy if exists lire_conversations on conversations;
create policy lire_conversations on conversations for select
  using (accede_conversation(id));

drop policy if exists lire_participants on conv_participants;
create policy lire_participants on conv_participants for select
  using (profil_id = auth.uid() or accede_conversation(conversation_id));

-- LECTURE des messages : participants et superviseurs.
drop policy if exists lire_messages on messages;
create policy lire_messages on messages for select
  using (accede_conversation(conversation_id));

-- ÉCRITURE : les participants, et eux seuls. Un superviseur lit,
-- il n'écrit pas. C'est la différence entre surveiller et se mêler.
drop policy if exists ecrire_messages on messages;
create policy ecrire_messages on messages for insert
  with check (auteur_id = auth.uid() and est_participant(conversation_id));

-- Retrait d'un message : son auteur, ou la modération à partir de
-- l'échelon 6, ou la Direction générale.
drop policy if exists retirer_messages on messages;
create policy retirer_messages on messages for update using (
  auteur_id = auth.uid() or est_admin() or mon_echelon() >= 6
);

drop policy if exists maj_lecture on conv_participants;
create policy maj_lecture on conv_participants for update
  using (profil_id = auth.uid()) with check (profil_id = auth.uid());

-- ---------------------------------------------------------------------
-- 6. DROITS DE BASE
-- ---------------------------------------------------------------------

grant select on conversations, conv_participants, messages to authenticated;
grant update on conv_participants, messages to authenticated;

grant execute on function est_participant(uuid), peut_superviser(uuid),
                          accede_conversation(uuid),
                          conversation_privee(uuid), conversation_groupe(uuid),
                          envoyer_message(uuid, text), marquer_lu(uuid),
                          mes_conversations(), participants_conversation(uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 7. LA MESSAGERIE S'OUVRE À TOUS LES MEMBRES ACTIFS
-- ---------------------------------------------------------------------

update applications
   set description = 'Échanges privés et de groupe. Supervisés par l''encadrement.'
 where code = 'messagerie';

-- =====================================================================
--  FIN DE LA MIGRATION 04
--
--  Vérification, en tant qu'administrateur :
--    select * from mes_conversations();
--
--  Le principe à ne jamais assouplir : aucun canal privé non supervisé
--  entre un adulte et un mineur. Si un jour la fédération ouvre des
--  comptes à des mineurs, cette règle est déjà tenue par la base.
-- =====================================================================
