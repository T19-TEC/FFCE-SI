-- =====================================================================
--  FFCE — Migration 41 — LA PRÉSIDENCE COMME ORGANE
--
--  Quand la présidence notifie un acte, le message venait de la personne
--  qui l'avait signé. Deux conséquences fâcheuses : l'intéressé
--  répondait à un individu là où il s'adressait à une institution, et
--  le jour où cette personne quitte ses fonctions, la conversation
--  part avec elle.
--
--  On introduit donc les ORGANES : des boîtes qui appartiennent à une
--  fonction, non à quelqu'un. Le Secrétariat de la présidence en est le
--  premier. Un message y est signé de l'organe ; tous ceux qui en
--  détiennent l'habilitation le lisent et peuvent répondre ; et le
--  départ d'un titulaire ne fait rien disparaître.
--
--  Une conversation organique n'est pas une conversation privée
--  déguisée : elle ne relève pas de la supervision hiérarchique, parce
--  qu'elle est déjà collective par construction.
--
--  Prérequis : 01 à 40.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES ORGANES
-- ---------------------------------------------------------------------

create table if not exists organes (
  code        text primary key,
  nom         text not null,
  description text,
  droit       text not null references droits(code),
  logo        text,
  couleur     text not null default 'nuit',
  signature   text,                  -- ce dont l'organe signe ses envois
  actif       boolean not null default true,
  ordre       integer not null default 100
);

alter table organes enable row level security;
drop policy if exists lire_organes on organes;
create policy lire_organes on organes for select using (mon_niveau() >= 10);
grant select on organes to authenticated;

insert into organes (code, nom, description, droit, couleur, signature, ordre) values
  ('secretariat_presidence', 'Secrétariat de la présidence',
   'Notifie les actes, reçoit les réponses, tient la correspondance de la présidence.',
   'cabinet.arbitrer', 'nuit',
   'Le secrétariat de la présidence', 10)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      droit = excluded.droit, signature = excluded.signature;

-- ---------------------------------------------------------------------
-- 2. LA CONVERSATION ORGANIQUE
--    Un troisième type, à côté du privé et du groupe. Le participant
--    inscrit est l'interlocuteur ; l'organe, lui, est accessible par le
--    droit, non par une inscription — sans quoi il faudrait ajouter et
--    retirer chaque titulaire à la main.
-- ---------------------------------------------------------------------

alter table conversations drop constraint if exists conversations_type_check;
alter table conversations add constraint conversations_type_check
  check (type in ('privee','groupe','organique'));

alter table conversations add column if not exists organe text references organes(code);
create index if not exists idx_conv_organe on conversations(organe);

-- Un message peut être signé d'un organe. L'auteur reste enregistré —
-- on doit toujours pouvoir savoir qui a écrit — mais c'est l'organe qui
-- s'affiche, et c'est à lui qu'on répond.
alter table messages add column if not exists organe text references organes(code);

create or replace function sert_organe(p_organe text)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from organes o where o.code = p_organe and o.actif and a_droit(o.droit));
$$;

create or replace function est_participant(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from conv_participants
                 where conversation_id = p_conv and profil_id = auth.uid())
      or exists (select 1 from conversations c
                 where c.id = p_conv and c.organe is not null and sert_organe(c.organe));
$$;

-- Une conversation organique est déjà collective : la supervision
-- hiérarchique n'a rien à y ajouter, et l'y étendre reviendrait à
-- ouvrir la correspondance de la présidence à des tiers.
create or replace function accede_conversation(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select est_participant(p_conv)
      or (peut_superviser(p_conv)
          and not exists (select 1 from conversations c
                          where c.id = p_conv and c.type = 'organique'));
$$;

-- Ouvrir — ou retrouver — la boîte d'un organe avec quelqu'un.
create or replace function conversation_organe(p_organe text, p_avec uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_conv uuid; o organes;
begin
  select * into o from organes where code = p_organe and actif;
  if o is null then
    return jsonb_build_object('ok', false, 'message', 'Organe inconnu.');
  end if;
  if not (sert_organe(p_organe) or p_avec = auth.uid()) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne servez pas cet organe.');
  end if;

  select c.id into v_conv from conversations c
   where c.organe = p_organe and c.type = 'organique'
     and exists (select 1 from conv_participants x
                 where x.conversation_id = c.id and x.profil_id = p_avec)
   limit 1;

  if v_conv is null then
    insert into conversations (type, organe, titre, cree_par)
    values ('organique', p_organe, o.nom, auth.uid())
    returning id into v_conv;
    insert into conv_participants (conversation_id, profil_id) values (v_conv, p_avec);
  end if;
  return jsonb_build_object('ok', true, 'id', v_conv);
end $$;

-- Écrire au nom de l'organe. L'auteur est conservé — la traçabilité
-- n'est pas négociable — mais l'affichage porte la signature de
-- l'institution.
create or replace function envoyer_message(
  p_conv uuid, p_contenu text default null, p_piece text default null,
  p_piece_nom text default null, p_taille integer default null,
  p_type text default null, p_au_nom_de text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_organe text;
begin
  if not est_participant(p_conv) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne participez pas à cette conversation.');
  end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if coalesce(trim(p_contenu),'') = '' and p_piece is null then
    return jsonb_build_object('ok', false, 'message', 'Message vide.');
  end if;
  if p_piece is not null and p_piece not like (p_conv::text || '/%') then
    return jsonb_build_object('ok', false,
      'message', 'Cette pièce n''appartient pas à cette conversation.');
  end if;

  -- On ne signe d'un organe que si on le sert, et que si la
  -- conversation est bien la sienne.
  if p_au_nom_de is not null then
    if not sert_organe(p_au_nom_de) then
      return jsonb_build_object('ok', false,
        'message', 'Vous ne pouvez pas écrire au nom de cet organe.');
    end if;
    if (select organe from conversations where id = p_conv) is distinct from p_au_nom_de then
      return jsonb_build_object('ok', false,
        'message', 'Cette conversation n''appartient pas à cet organe.');
    end if;
    v_organe := p_au_nom_de;
  end if;

  insert into messages (conversation_id, auteur_id, contenu, piece,
                        piece_nom, piece_taille, piece_type, organe)
  values (p_conv, auth.uid(),
          coalesce(nullif(trim(p_contenu),''), '[pièce jointe]'),
          p_piece, p_piece_nom, p_taille, p_type, v_organe);

  update conversations set derniere_activite = now() where id = p_conv;
  update conv_participants set lu_jusqu_a = now()
   where conversation_id = p_conv and profil_id = auth.uid();

  return jsonb_build_object('ok', true);
end $$;

drop function if exists envoyer_message(uuid, text, text, text, integer, text);

-- La liste des conversations distingue l'organe et le nomme.
drop function if exists mes_conversations();
create or replace function mes_conversations()
returns table (
  id uuid, type text, groupe_id uuid, titre text,
  derniere_activite timestamptz, dernier_message text,
  dernier_auteur uuid, non_lus integer, superviseur boolean,
  signale boolean, organe text, organe_nom text, organe_logo text,
  organe_couleur text
) language sql stable security definer set search_path = public as $$
  select c.id, c.type, c.groupe_id,
         coalesce(
           case when c.organe is not null and not sert_organe(c.organe)
                then o.nom end,
           case when c.organe is not null then
             o.nom || ' — ' || coalesce((
               select string_agg(trim(p.prenom || ' ' || p.nom), ', ')
               from conv_participants x join profils p on p.id = x.profil_id
               where x.conversation_id = c.id), '') end,
           c.titre, (
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
         cp.id is null and c.organe is null,
         exists (select 1 from signalements s
                 where s.conversation_id = c.id and s.statut in ('ouvert','en_cours')),
         c.organe, o.nom, o.logo, o.couleur
  from conversations c
  left join organes o on o.code = c.organe
  left join conv_participants cp
         on cp.conversation_id = c.id and cp.profil_id = auth.uid()
  where cp.id is not null
     or (c.organe is not null and sert_organe(c.organe))
     or (c.type <> 'organique' and peut_superviser(c.id))
  order by c.derniere_activite desc;
$$;

-- Les organes que je sers, pour que l'interface sache proposer d'écrire
-- en leur nom.
drop function if exists mes_organes();
create or replace function mes_organes()
returns table (code text, nom text, description text, logo text,
               couleur text, signature text, en_attente integer)
language sql stable security definer set search_path = public as $$
  select o.code, o.nom, o.description, o.logo, o.couleur, o.signature,
         (select count(*)::int from conversations c
          join messages m on m.conversation_id = c.id
          where c.organe = o.code and not m.retire and m.organe is null
            and m.cree_le > coalesce((select max(x.cree_le) from messages x
                                      where x.conversation_id = c.id
                                        and x.organe is not null), 'epoch'))
  from organes o
  where o.actif and sert_organe(o.code)
  order by o.ordre;
$$;

-- ---------------------------------------------------------------------
-- 3. LA NOTIFICATION D'UN ACTE PASSE PAR L'ORGANE
-- ---------------------------------------------------------------------

create or replace function signer_acte(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a actes_internes; v_conv jsonb; v_res jsonb; v_texte text; v_sign text;
begin
  select * into a from actes_internes where id = p_id;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Acte introuvable.');
  end if;
  if a.statut <> 'projet' then
    return jsonb_build_object('ok', false, 'message', 'Cet acte est déjà signé.');
  end if;
  if not puis_je_signer_acte() then
    return jsonb_build_object('ok', false,
      'message', 'Le cabinet prépare les actes ; seule la présidence les signe.');
  end if;
  if a.portee = 'locale' and not (est_admin() or a_droit('actes.prendre')
      or (a_droit('actes.local') and dans_mon_perimetre(a.territoire_id))) then
    return jsonb_build_object('ok', false,
      'message', 'Cet acte relève d''un autre ressort.');
  end if;

  if a.type = 'nomination' then
    v_res := nommer(a.destinataire_id, a.poste_confie, a.territoire_id,
                    null, 'Acte ' || a.reference);
    if not (v_res->>'ok')::boolean then
      return jsonb_build_object('ok', false,
        'message', 'L''acte ne peut pas être signé : ' || (v_res->>'message'));
    end if;
  end if;

  update actes_internes
     set statut = 'signe', signe_le = now(), signe_par = auth.uid(),
         prend_effet_le = coalesce(prend_effet_le, current_date)
   where id = p_id;

  if a.destinataire_id is not null then
    select signature into v_sign from organes where code = 'secretariat_presidence';
    v_conv := conversation_organe('secretariat_presidence', a.destinataire_id);
    if (v_conv->>'ok')::boolean then
      v_texte := 'Notification de l''acte ' || a.reference || E'\n\n'
        || a.objet || E'\n\n'
        || 'Cet acte prend effet le '
        || to_char(coalesce(a.prend_effet_le, current_date), 'DD/MM/YYYY')
        || '. Son texte intégral est consultable et téléchargeable au recueil '
        || 'des actes. Vous pouvez répondre à ce message : il parvient au '
        || 'secrétariat, non à une personne.' || E'\n\n'
        || coalesce(v_sign, 'Le secrétariat de la présidence') || '.';

      insert into messages (conversation_id, auteur_id, contenu, organe)
      values (uuid_valide(v_conv->>'id'), auth.uid(), v_texte,
              'secretariat_presidence');
      update conversations set derniere_activite = now()
       where id = uuid_valide(v_conv->>'id');

      update actes_internes set statut = 'notifie', notifie_le = now() where id = p_id;
    end if;
  end if;

  perform inscrire_acte(a.destinataire_id, 'acte_interne',
    'Acte ' || a.reference || ' — ' || a.objet, null,
    jsonb_build_object('acte_id', p_id, 'type', a.type), false);

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LA SECTION « PRÉSIDENCE DE LA FFCE »
--    Le cabinet et le recueil n'ont rien à faire sous la Direction
--    générale : ils relèvent de la présidence, qui est un organe
--    distinct. La distinction n'est pas cosmétique — elle dit qui
--    décide de quoi.
-- ---------------------------------------------------------------------

insert into directions (code, nom, nom_court, description, couleur, ordre) values
  ('presidence', 'Présidence de la FFCE', 'Présidence',
   'Le cabinet, les actes de la présidence et leur recueil.', 'nuit', 1)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, couleur = excluded.couleur,
      ordre = excluded.ordre;

update applications set direction = 'presidence', direction_locale = null
 where code in ('cabinet', 'recueil');

-- Le rapport d'activité est désormais un onglet du cabinet : il ne
-- mérite plus une entrée propre dans le menu. La route reste ouverte —
-- les liens existants doivent continuer de fonctionner.
update application_visibilite set etat = 'invisible' where application = 'rapport';

-- ---------------------------------------------------------------------
-- 5. DROITS D'EXÉCUTION
-- ---------------------------------------------------------------------

grant execute on function sert_organe(text), est_participant(uuid),
                          accede_conversation(uuid), conversation_organe(text, uuid),
                          envoyer_message(uuid, text, text, text, integer, text, text),
                          mes_conversations(), mes_organes(), signer_acte(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 41
--
--  Vérifications :
--    select * from mes_organes();
--    select id, type, titre, organe_nom from mes_conversations();
--    select conversation_organe('secretariat_presidence', '<uuid>');
--
--  Sur l'auteur d'un message organique : il est conservé en base. Ce
--  n'est pas une contradiction avec la signature de l'organe — c'est
--  ce qui permet, en cas de litige, de savoir qui a écrit. L'organe
--  s'affiche, la personne se retrouve.
--
--  Sur la supervision : elle ne s'applique pas aux conversations
--  organiques. Une boîte déjà collective n'a pas besoin d'un tiers pour
--  la surveiller, et l'y autoriser ouvrirait la correspondance de la
--  présidence à qui n'a rien à y voir.
-- =====================================================================
