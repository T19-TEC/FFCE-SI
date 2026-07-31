-- =====================================================================
--  FFCE — Migration 05 — MESSAGERIE : CORRECTIFS ET SIGNALEMENTS
--
--  Trois corrections et un ajout.
--
--  1. QUI PEUT ÉCRIRE À QUI. Un adhérent voit peu de monde dans
--     l'annuaire, il ne pouvait donc écrire à personne. On sépare le
--     droit de voir l'annuaire du droit d'écrire : chacun peut joindre
--     son département, sa hiérarchie et la direction nationale, et le
--     cercle s'élargit avec l'échelon.
--
--  2. LA SUPERVISION EST STRICTEMENT DESCENDANTE. Un superviseur ne
--     voit une conversation que si TOUS les autres participants ont une
--     fonction inférieure à la sienne. Un référent départemental ne lit
--     donc pas un échange entre la Direction générale et un adhérent :
--     il n'a pas à savoir ce que la direction écrit, et ces propos le
--     concernent peut-être.
--
--  3. LA SUPERVISION SE FAIT DISCRÈTE. Annoncée, toujours — c'est une
--     obligation — mais en une ligne sobre plutôt qu'en avertissement.
--
--  4. SIGNALEMENTS. Un membre peut signaler une conversation. Le
--     signalement remonte dans Vérifications, et la Direction générale
--     peut le confier à un encadrant, qui obtient alors — et seulement
--     alors — l'accès à la conversation concernée.
--
--  Prérequis : 01 à 04.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. OUTILS TERRITORIAUX
-- ---------------------------------------------------------------------

-- L'ancêtre d'une échelle donnée : la région d'un département, etc.
create or replace function ancetre_echelle(cible uuid, p_echelle text)
returns uuid language sql stable security definer set search_path = public as $$
  with recursive remonte as (
    select t.id, t.parent_id, t.echelle from territoires t where t.id = cible
    union all
    select t.id, t.parent_id, t.echelle
      from territoires t join remonte r on t.id = r.parent_id
  )
  select id from remonte where echelle = p_echelle limit 1;
$$;

-- ---------------------------------------------------------------------
-- 2. QUI PEUT ÉCRIRE À QUI
--
--    Le principe : on écrit à son territoire, à sa hiérarchie, et à la
--    direction nationale. Voir l'annuaire et pouvoir écrire sont deux
--    droits distincts — un adhérent ne consulte pas la liste de son
--    département, mais il peut y adresser un message.
-- ---------------------------------------------------------------------

create or replace function puis_je_ecrire_a(p_cible uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_mon_terr uuid; v_sa_terr uuid; v_son_niveau int; v_mon_ech int;
begin
  if p_cible = auth.uid() then return false; end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then return false; end if;
  if not exists (select 1 from profils where id = p_cible and statut = 'actif') then
    return false;
  end if;
  if est_admin() then return true; end if;

  select territoire_id into v_mon_terr from profils where id = auth.uid();
  select p.territoire_id, f.niveau into v_sa_terr, v_son_niveau
    from profils p join fonctions f on f.code = p.fonction where p.id = p_cible;
  v_mon_ech := mon_echelon();

  -- La direction nationale est toujours joignable.
  if v_son_niveau >= 80 then return true; end if;

  if v_mon_terr is null then return false; end if;

  -- Vers le bas : tout ce qui dépend de mon territoire.
  if v_sa_terr is not null
     and exists (select 1 from territoires_sous(v_mon_terr) s where s.id = v_sa_terr)
  then return true; end if;

  -- Vers le haut : ma hiérarchie, jusqu'au national.
  if v_sa_terr is not null
     and exists (select 1 from territoires_sous(v_sa_terr) s where s.id = v_mon_terr)
  then return true; end if;

  -- À partir de l'échelon 4, toute sa région.
  if v_mon_ech >= 4 and v_sa_terr is not null
     and ancetre_echelle(v_mon_terr,'region') is not null
     and ancetre_echelle(v_mon_terr,'region') = ancetre_echelle(v_sa_terr,'region')
  then return true; end if;

  -- À partir de l'échelon 6, ou d'une fonction de délégué régional,
  -- toute la fédération.
  if v_mon_ech >= 6 or mon_niveau() >= 70 then return true; end if;

  return false;
end $$;

-- La liste, pour l'écran « Nouvelle conversation ».
create or replace function destinataires_possibles()
returns table (id uuid, prenom text, nom text, matricule text,
               fonction_nom text, niveau int, territoire_nom text)
language sql stable security definer set search_path = public as $$
  select p.id, p.prenom, p.nom, p.matricule, f.nom, f.niveau, t.nom
  from profils p
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where p.statut = 'actif'
    and p.id <> auth.uid()
    and puis_je_ecrire_a(p.id)
  order by f.niveau desc, p.nom, p.prenom;
$$;

-- On applique la règle à l'ouverture d'une conversation privée.
create or replace function conversation_privee(p_autre uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_conv uuid;
begin
  if not puis_je_ecrire_a(p_autre) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez pas écrire à ce membre. Passez par votre responsable ou par la direction.');
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

-- ---------------------------------------------------------------------
-- 3. SIGNALEMENTS
-- ---------------------------------------------------------------------

create table if not exists signalements (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid references conversations(id) on delete cascade,
  message_id      uuid references messages(id) on delete set null,
  auteur_id       uuid not null references profils(id) on delete cascade,
  motif           text not null check (motif in
                    ('propos_deplaces','harcelement','hors_sujet','securite','autre')),
  details         text,
  statut          text not null default 'ouvert'
                    check (statut in ('ouvert','en_cours','clos_fonde','clos_infonde')),
  assigne_a       uuid references profils(id) on delete set null,
  decision        text,
  traite_par      uuid references profils(id),
  traite_le       timestamptz,
  cree_le         timestamptz not null default now()
);
create index if not exists idx_sig_statut on signalements(statut);
create index if not exists idx_sig_conv   on signalements(conversation_id);

create or replace function signaler_conversation(
  p_conv uuid, p_motif text, p_details text, p_message uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_participant(p_conv) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne participez pas à cette conversation.');
  end if;
  if exists (select 1 from signalements
             where conversation_id = p_conv and auteur_id = auth.uid()
               and statut in ('ouvert','en_cours')) then
    return jsonb_build_object('ok', false,
      'message', 'Vous avez déjà signalé cette conversation. Elle est en cours d''examen.');
  end if;

  insert into signalements (conversation_id, message_id, auteur_id, motif, details)
  values (p_conv, p_message, auth.uid(), p_motif, nullif(trim(p_details),''));

  insert into journal (acteur, action, cible)
  values (auth.uid(), 'signalement_depose', p_conv::text);

  return jsonb_build_object('ok', true);
end $$;

-- Confier un signalement à un encadrant. Cela lui ouvre l'accès à la
-- conversation, et à elle seule, le temps de l'examen.
create or replace function confier_signalement(p_sig uuid, p_a uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Seule la Direction générale confie un signalement.');
  end if;
  if p_a is not null and (select f.niveau from profils p join fonctions f on f.code = p.fonction
                          where p.id = p_a) < 50 then
    return jsonb_build_object('ok', false,
      'message', 'Un signalement se confie à un membre de l''encadrement.');
  end if;

  update signalements
     set assigne_a = p_a,
         statut = case when p_a is null then 'ouvert' else 'en_cours' end
   where id = p_sig;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'signalement_confie', p_sig::text,
          jsonb_build_object('a', p_a));

  return jsonb_build_object('ok', true);
end $$;

create or replace function clore_signalement(p_sig uuid, p_fonde boolean, p_decision text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_assigne uuid;
begin
  select assigne_a into v_assigne from signalements where id = p_sig;
  if not (est_admin() or v_assigne = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Ce signalement ne vous est pas confié.');
  end if;
  if coalesce(trim(p_decision),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'La décision doit être motivée.');
  end if;

  update signalements
     set statut = case when p_fonde then 'clos_fonde' else 'clos_infonde' end,
         decision = trim(p_decision), traite_par = auth.uid(), traite_le = now()
   where id = p_sig;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'signalement_clos', p_sig::text,
          jsonb_build_object('fonde', p_fonde));

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LA SUPERVISION, RÉÉCRITE
--
--    Trois portes, et trois seulement :
--      — la Direction générale, qui voit tout ;
--      — un encadrant de niveau 60 ou plus, à condition que TOUS les
--        autres participants aient une fonction strictement inférieure
--        à la sienne, et qu'au moins un relève de son territoire ;
--      — un encadrant à qui un signalement a été confié, pour la seule
--        conversation concernée et le temps de l'examen.
-- ---------------------------------------------------------------------

create or replace function peut_superviser(p_conv uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() then true
    when est_participant(p_conv) then false
    -- Signalement confié : accès limité à cette conversation.
    when exists (select 1 from signalements s
                 where s.conversation_id = p_conv and s.assigne_a = auth.uid()
                   and s.statut in ('ouvert','en_cours')) then true
    when mon_niveau() < 60 then false
    -- Aucun participant ne doit être de niveau égal ou supérieur au mien.
    when exists (select 1 from conv_participants cp
                 join profils p on p.id = cp.profil_id
                 join fonctions f on f.code = p.fonction
                 where cp.conversation_id = p_conv and f.niveau >= mon_niveau())
      then false
    -- Et au moins un participant doit relever de mon territoire.
    else exists (select 1 from conv_participants cp
                 join profils p on p.id = cp.profil_id
                 where cp.conversation_id = p_conv
                   and dans_mon_perimetre(p.territoire_id))
  end;
$$;

-- La liste des conversations signale désormais celles qui font l'objet
-- d'un examen.
drop function if exists mes_conversations();
create or replace function mes_conversations()
returns table (
  id uuid, type text, groupe_id uuid, titre text,
  derniere_activite timestamptz, dernier_message text,
  dernier_auteur uuid, non_lus integer, superviseur boolean,
  signale boolean
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
         cp.id is null,
         exists (select 1 from signalements s
                 where s.conversation_id = c.id and s.statut in ('ouvert','en_cours'))
  from conversations c
  left join conv_participants cp
         on cp.conversation_id = c.id and cp.profil_id = auth.uid()
  where cp.id is not null or peut_superviser(c.id)
  order by c.derniere_activite desc;
$$;

-- Les signalements à traiter, avec le nécessaire pour décider.
create or replace function signalements_a_traiter()
returns table (
  id uuid, conversation_id uuid, motif text, details text, statut text,
  cree_le timestamptz, auteur_nom text, auteur_matricule text,
  assigne_a uuid, assigne_nom text, participants text, nb_messages integer
) language sql stable security definer set search_path = public as $$
  select s.id, s.conversation_id, s.motif, s.details, s.statut, s.cree_le,
         trim(a.prenom || ' ' || a.nom), a.matricule,
         s.assigne_a, trim(b.prenom || ' ' || b.nom),
         (select string_agg(trim(p.prenom || ' ' || p.nom), ', ')
            from conv_participants cp join profils p on p.id = cp.profil_id
           where cp.conversation_id = s.conversation_id),
         (select count(*)::int from messages m where m.conversation_id = s.conversation_id)
  from signalements s
  join profils a on a.id = s.auteur_id
  left join profils b on b.id = s.assigne_a
  where s.statut in ('ouvert','en_cours')
    and (est_admin() or s.assigne_a = auth.uid())
  order by s.cree_le;
$$;

-- =====================================================================
--  5. SÉCURITÉ
-- =====================================================================

alter table signalements enable row level security;

drop policy if exists lire_signalements on signalements;
create policy lire_signalements on signalements for select using (
  auteur_id = auth.uid() or assigne_a = auth.uid() or est_admin()
);
drop policy if exists gerer_signalements on signalements;
create policy gerer_signalements on signalements for all
  using (est_admin()) with check (est_admin());

grant select on signalements to authenticated;
grant execute on function ancetre_echelle(uuid, text),
                          puis_je_ecrire_a(uuid), destinataires_possibles(),
                          conversation_privee(uuid),
                          signaler_conversation(uuid, text, text, uuid),
                          confier_signalement(uuid, uuid),
                          clore_signalement(uuid, boolean, text),
                          peut_superviser(uuid), mes_conversations(),
                          signalements_a_traiter()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 05
--
--  Vérifications utiles :
--
--    -- À qui puis-je écrire ?
--    select prenom, nom, fonction_nom, territoire_nom from destinataires_possibles();
--
--    -- Quelles conversations puis-je superviser ?
--    select titre, superviseur, signale from mes_conversations();
--
--  Le principe à ne jamais assouplir : la supervision descend, elle ne
--  remonte jamais. Un encadrant ne lit pas ce que sa hiérarchie écrit.
-- =====================================================================
