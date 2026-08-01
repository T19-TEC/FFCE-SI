-- =====================================================================
--  FFCE — Migration 35 — LES ÉQUIPES
--
--  Trois choses, qui n'en font qu'une : on ne travaille pas en équipe
--  parce qu'un menu le propose, mais parce qu'on a été retenu quelque
--  part.
--
--  1. « Groupes de travail » s'affichait pour tout adhérent, et restait
--     vide pour la plupart. L'application ne s'ouvre désormais qu'à qui
--     appartient à un groupe — et se referme quand on le quitte.
--
--  2. On rejoignait un groupe ouvert d'un clic, ou on y était invité.
--     Il manquait la voie normale : postuler, et être retenu. Une
--     candidature s'écrit, se motive, et se répond.
--
--  3. Le travail en équipe n'existait qu'au national. Un responsable
--     local peut désormais proposer une équipe et les personnes qui la
--     composent ; la présidence de la structure valide, ou propose
--     elle-même — auquel cas la proposition vaut décision.
--
--  Sur l'héritage des droits : une équipe n'hérite de rien. Elle reçoit
--  une fiche, comme un poste en reçoit une. Le validateur y met les
--  applications qu'il détient lui-même — jamais davantage. C'est la
--  règle du lot précédent : on ne donne que ce qu'on a. Un héritage
--  automatique ferait circuler des droits dont plus personne ne saurait
--  dire d'où ils viennent.
--
--  Prérequis : 01 à 34.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. UN GROUPE PEUT ÊTRE PROPOSÉ AVANT D'EXISTER
--    Le domaine énuméré d'origine ne connaissait que 'actif' et
--    'archive'. On l'élargit plutôt que de détourner une valeur
--    existante de son sens.
-- ---------------------------------------------------------------------

alter table groupes_travail drop constraint if exists groupes_travail_statut_check;
alter table groupes_travail add constraint groupes_travail_statut_check
  check (statut in ('propose','actif','refuse','archive'));

alter table groupes_travail add column if not exists propose_par uuid references profils(id);
alter table groupes_travail add column if not exists valide_par uuid references profils(id);
alter table groupes_travail add column if not exists valide_le timestamptz;
alter table groupes_travail add column if not exists motif_refus text;
alter table groupes_travail add column if not exists sur_candidature boolean not null default false;

comment on column groupes_travail.sur_candidature is
  'true : on y entre en postulant et en étant retenu, pas en cliquant.';

-- ---------------------------------------------------------------------
-- 2. LA FICHE D'ÉQUIPE
--    Ce qu'appartenir à cette équipe ouvre. Pas un héritage : une liste
--    explicite, remplie par qui valide, dans la limite de ce qu'il a.
-- ---------------------------------------------------------------------

create table if not exists gt_applications (
  groupe_id   uuid not null references groupes_travail(id) on delete cascade,
  application text not null references applications(code) on delete cascade,
  primary key (groupe_id, application)
);

-- ---------------------------------------------------------------------
-- 3. LES CANDIDATURES
-- ---------------------------------------------------------------------

create table if not exists gt_candidatures (
  id          uuid primary key default gen_random_uuid(),
  groupe_id   uuid not null references groupes_travail(id) on delete cascade,
  profil_id   uuid not null references profils(id) on delete cascade,
  motivation  text not null,
  statut      text not null default 'deposee'
                check (statut in ('deposee','retenue','ecartee','retiree')),
  reponse     text,
  traite_par  uuid references profils(id),
  traite_le   timestamptz,
  cree_le     timestamptz not null default now(),
  unique (groupe_id, profil_id)
);
create index if not exists idx_gtc_groupe on gt_candidatures(groupe_id, statut);

alter table gt_applications  enable row level security;
alter table gt_candidatures  enable row level security;

drop policy if exists lire_gt_applications on gt_applications;
create policy lire_gt_applications on gt_applications for select using (
  est_membre_gt(groupe_id) or est_admin() or mon_niveau() >= 50);

drop policy if exists lire_gt_candidatures on gt_candidatures;
create policy lire_gt_candidatures on gt_candidatures for select using (
  profil_id = auth.uid() or est_responsable_gt(groupe_id) or est_admin());

grant select on gt_applications, gt_candidatures to authenticated;

-- ---------------------------------------------------------------------
-- 4. L'ACCÈS SUIT L'APPARTENANCE
--    On ouvre à l'entrée, on referme à la sortie. La fonction est
--    appelée par tout ce qui fait entrer ou sortir quelqu'un : il n'y a
--    donc qu'un seul endroit où la règle est écrite.
-- ---------------------------------------------------------------------

create or replace function ajuster_acces_groupes(p_profil uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_membre boolean; v_apps text[];
begin
  select exists (select 1 from gt_membres m
                 join groupes_travail g on g.id = m.groupe_id
                 where m.profil_id = p_profil and m.statut = 'actif'
                   and g.statut = 'actif')
    into v_membre;

  if v_membre then
    insert into acces_applications (profil_id, application, statut, motif, accorde_par)
    values (p_profil, 'groupes', 'accorde',
            'Membre d''un groupe de travail', auth.uid())
    on conflict (profil_id, application) do update
      set statut = 'accorde', revoque_le = null, revoque_par = null,
          motif = 'Membre d''un groupe de travail';
  else
    -- On ne referme que ce que l'appartenance avait ouvert : un accès
    -- accordé pour une autre raison ne doit pas disparaître ici.
    update acces_applications
       set statut = 'revoque', revoque_le = now(),
           motif_revocation = 'N''appartient plus à aucun groupe'
     where profil_id = p_profil and application = 'groupes'
       and motif = 'Membre d''un groupe de travail';
  end if;

  -- Les applications de la fiche d'équipe suivent la même logique.
  select coalesce(array_agg(distinct ga.application), '{}') into v_apps
    from gt_applications ga
    join gt_membres m on m.groupe_id = ga.groupe_id
    join groupes_travail g on g.id = ga.groupe_id
   where m.profil_id = p_profil and m.statut = 'actif' and g.statut = 'actif';

  insert into acces_applications (profil_id, application, statut, motif, accorde_par)
  select p_profil, a, 'accorde', 'Fiche d''équipe', auth.uid()
  from unnest(v_apps) as a
  on conflict (profil_id, application) do update
    set statut = 'accorde', revoque_le = null, revoque_par = null,
        motif = 'Fiche d''équipe';

  update acces_applications
     set statut = 'revoque', revoque_le = now(),
         motif_revocation = 'Sortie de l''équipe'
   where profil_id = p_profil and motif = 'Fiche d''équipe'
     and application <> all (v_apps);
end $$;

-- L'application « Groupes de travail » n'est plus ouverte par la
-- fonction : elle l'est par l'appartenance, donc nominativement.
update application_visibilite set etat = 'invisible' where application = 'groupes';

-- Ceux qui appartiennent déjà à un groupe gardent leur accès.
do $$
declare r record;
begin
  for r in select distinct profil_id from gt_membres where statut = 'actif' loop
    insert into acces_applications (profil_id, application, statut, motif)
    values (r.profil_id, 'groupes', 'accorde', 'Membre d''un groupe de travail')
    on conflict (profil_id, application) do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. PROPOSER, VALIDER
-- ---------------------------------------------------------------------

create or replace function proposer_equipe(
  p_nom text, p_objet text, p_territoire uuid, p_membres uuid[] default '{}',
  p_applications text[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_direct boolean; v_m uuid; v_a text;
begin
  if coalesce(trim(p_nom),'') = '' or coalesce(trim(p_objet),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une équipe a un nom et un objet : sans quoi personne ne saura pourquoi elle existe.');
  end if;
  if p_territoire is null or not dans_mon_perimetre(p_territoire) then
    return jsonb_build_object('ok', false,
      'message', 'Une équipe se constitue dans votre périmètre.');
  end if;
  if mon_niveau() < 40 and not a_droit('habilitations.local') and not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'La constitution d''une équipe revient à l''encadrement local.');
  end if;

  -- Qui peut nommer dans sa structure n'a pas à demander la permission
  -- de constituer une équipe : sa proposition vaut décision.
  v_direct := est_admin() or a_droit('habilitations.local') or mon_niveau() >= 60;

  insert into groupes_travail (nom, objet, territoire_id, ouvert, sur_candidature,
                               statut, cree_par, propose_par, valide_par, valide_le)
  values (trim(p_nom), trim(p_objet), p_territoire, false, false,
          case when v_direct then 'actif' else 'propose' end,
          auth.uid(), auth.uid(),
          case when v_direct then auth.uid() end,
          case when v_direct then now() end)
  returning id into v_id;

  insert into gt_membres (groupe_id, profil_id, role, statut)
  values (v_id, auth.uid(), 'responsable', case when v_direct then 'actif' else 'invite' end);

  foreach v_m in array coalesce(p_membres, '{}') loop
    if v_m <> auth.uid() then
      insert into gt_membres (groupe_id, profil_id, role, statut, invite_par)
      values (v_id, v_m, 'membre', 'invite', auth.uid())
      on conflict (groupe_id, profil_id) do nothing;
    end if;
  end loop;

  -- La fiche ne peut contenir que ce que le proposant détient lui-même.
  foreach v_a in array coalesce(p_applications, '{}') loop
    if a_acces(v_a) and v_a <> 'groupes' then
      insert into gt_applications (groupe_id, application) values (v_id, v_a)
      on conflict do nothing;
    end if;
  end loop;

  if v_direct then
    perform ajuster_acces_groupes(auth.uid());
  end if;

  return jsonb_build_object('ok', true, 'id', v_id,
    'statut', case when v_direct then 'actif' else 'propose' end);
end $$;

create or replace function valider_equipe(p_groupe uuid, p_ok boolean,
                                          p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g groupes_travail; r record;
begin
  select * into g from groupes_travail where id = p_groupe;
  if g is null or g.statut <> 'propose' then
    return jsonb_build_object('ok', false, 'message', 'Cette équipe n''est pas en attente.');
  end if;
  if not (est_admin() or (dans_mon_perimetre(g.territoire_id)
          and (a_droit('habilitations.local') or mon_niveau() >= 60))) then
    return jsonb_build_object('ok', false,
      'message', 'La validation revient à la présidence de la structure.');
  end if;
  if not p_ok and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus se motive.');
  end if;

  if not p_ok then
    update groupes_travail set statut = 'refuse', motif_refus = trim(p_motif),
           valide_par = auth.uid(), valide_le = now()
     where id = p_groupe;
    return jsonb_build_object('ok', true);
  end if;

  update groupes_travail set statut = 'actif', valide_par = auth.uid(),
         valide_le = now(), motif_refus = null
   where id = p_groupe;

  -- Le responsable proposé devient actif ; les autres restent invités
  -- et doivent accepter. On n'enrôle personne malgré lui.
  update gt_membres set statut = 'actif'
   where groupe_id = p_groupe and role = 'responsable' and statut = 'invite';

  -- La fiche est ramenée à ce que le validateur détient : il engage sa
  -- signature, pas celle du proposant.
  delete from gt_applications ga
   where ga.groupe_id = p_groupe and not a_acces(ga.application);

  for r in select profil_id from gt_membres
           where groupe_id = p_groupe and statut = 'actif' loop
    perform ajuster_acces_groupes(r.profil_id);
  end loop;

  return jsonb_build_object('ok', true);
end $$;

drop function if exists equipes_a_valider();
create or replace function equipes_a_valider()
returns table (id uuid, nom text, objet text, territoire text,
               propose_par text, membres integer, applications text[],
               cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select g.id, g.nom, g.objet, t.nom, trim(p.prenom || ' ' || p.nom),
         (select count(*)::int from gt_membres m where m.groupe_id = g.id),
         coalesce(array(select a.nom from gt_applications ga
                        join applications a on a.code = ga.application
                        where ga.groupe_id = g.id), '{}'),
         g.cree_le
  from groupes_travail g
  left join territoires t on t.id = g.territoire_id
  left join profils p on p.id = g.propose_par
  where g.statut = 'propose'
    and (est_admin() or (dans_mon_perimetre(g.territoire_id)
         and (a_droit('habilitations.local') or mon_niveau() >= 60)))
  order by g.cree_le;
$$;

-- ---------------------------------------------------------------------
-- 6. POSTULER, ÊTRE RETENU
-- ---------------------------------------------------------------------

create or replace function postuler_groupe(p_groupe uuid, p_motivation text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_obstacle text;
begin
  if coalesce(trim(p_motivation),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi vous souhaitez rejoindre ce groupe.');
  end if;
  if not exists (select 1 from groupes_travail
                 where id = p_groupe and statut = 'actif' and sur_candidature) then
    return jsonb_build_object('ok', false,
      'message', 'Ce groupe ne recrute pas sur candidature.');
  end if;
  v_obstacle := obstacle_groupe(p_groupe);
  if v_obstacle is not null then
    return jsonb_build_object('ok', false, 'message', v_obstacle);
  end if;
  if exists (select 1 from gt_membres where groupe_id = p_groupe
             and profil_id = auth.uid() and statut in ('invite','actif')) then
    return jsonb_build_object('ok', false, 'message', 'Vous en faites déjà partie.');
  end if;

  insert into gt_candidatures (groupe_id, profil_id, motivation)
  values (p_groupe, auth.uid(), trim(p_motivation))
  on conflict (groupe_id, profil_id) do update
    set motivation = trim(p_motivation), statut = 'deposee',
        reponse = null, traite_par = null, traite_le = null, cree_le = now();

  return jsonb_build_object('ok', true);
end $$;

create or replace function retenir_candidature(p_id uuid, p_retenue boolean,
                                               p_reponse text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c gt_candidatures;
begin
  select * into c from gt_candidatures where id = p_id and statut = 'deposee';
  if c is null then
    return jsonb_build_object('ok', false, 'message', 'Candidature introuvable ou déjà traitée.');
  end if;
  if not (est_responsable_gt(c.groupe_id) or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'Seul le responsable du groupe examine les candidatures.');
  end if;
  -- Un refus se motive : c'est la règle de la maison, elle vaut ici.
  if not p_retenue and coalesce(trim(p_reponse),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une candidature écartée se motive.');
  end if;

  update gt_candidatures
     set statut = case when p_retenue then 'retenue' else 'ecartee' end,
         reponse = nullif(trim(p_reponse),''), traite_par = auth.uid(), traite_le = now()
   where id = p_id;

  if p_retenue then
    insert into gt_membres (groupe_id, profil_id, role, statut, invite_par)
    values (c.groupe_id, c.profil_id, 'membre', 'actif', auth.uid())
    on conflict (groupe_id, profil_id) do update set statut = 'actif';
    perform ajuster_acces_groupes(c.profil_id);
  end if;

  return jsonb_build_object('ok', true);
end $$;

drop function if exists candidatures_groupe(uuid);
create or replace function candidatures_groupe(p_groupe uuid default null)
returns table (id uuid, groupe_id uuid, groupe text, candidat text,
               candidat_id uuid, fonction text, territoire text,
               motivation text, statut text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.groupe_id, g.nom, trim(p.prenom || ' ' || p.nom), p.id,
         f.nom, t.nom, c.motivation, c.statut, c.cree_le
  from gt_candidatures c
  join groupes_travail g on g.id = c.groupe_id
  join profils p on p.id = c.profil_id
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where c.statut = 'deposee'
    and (p_groupe is null or c.groupe_id = p_groupe)
    and (est_responsable_gt(c.groupe_id) or est_admin())
  order by c.cree_le;
$$;

-- Les groupes ouverts aux candidatures, pour qui n'en est pas membre.
drop function if exists groupes_ouverts();
create or replace function groupes_ouverts()
returns table (id uuid, nom text, objet text, territoire text, portee text,
               membres integer, ma_candidature text)
language sql stable security definer set search_path = public as $$
  select g.id, g.nom, g.objet, coalesce(t.nom, 'National'),
         case when g.territoire_id is null then 'nationale' else 'locale' end,
         (select count(*)::int from gt_membres m
          where m.groupe_id = g.id and m.statut = 'actif'),
         (select c.statut from gt_candidatures c
          where c.groupe_id = g.id and c.profil_id = auth.uid())
  from groupes_travail g
  left join territoires t on t.id = g.territoire_id
  where g.statut = 'actif' and g.sur_candidature
    and obstacle_groupe(g.id) is null
    and not exists (select 1 from gt_membres m
                    where m.groupe_id = g.id and m.profil_id = auth.uid()
                      and m.statut in ('invite','actif'))
  order by g.territoire_id nulls first, g.nom;
$$;

-- ---------------------------------------------------------------------
-- 7. LES CHEMINS EXISTANTS SUIVENT LA MÊME RÈGLE
--    Entrer et sortir d'un groupe ajuste l'accès. Sans cela, la règle
--    ne vaudrait que pour les candidatures — et deux portes pour une
--    même chose finissent toujours par diverger.
-- ---------------------------------------------------------------------

create or replace function repondre_invitation(p_groupe uuid, p_accepte boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from gt_membres where groupe_id = p_groupe
                 and profil_id = auth.uid() and statut = 'invite') then
    return jsonb_build_object('ok', false, 'message', 'Aucune invitation en cours.');
  end if;
  if p_accepte then
    update gt_membres set statut = 'actif'
     where groupe_id = p_groupe and profil_id = auth.uid();
    perform ajuster_acces_groupes(auth.uid());
  else
    delete from gt_membres where groupe_id = p_groupe and profil_id = auth.uid();
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function rejoindre_groupe(p_groupe uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_obstacle text;
begin
  if not exists (select 1 from groupes_travail
                 where id = p_groupe and statut = 'actif' and ouvert) then
    return jsonb_build_object('ok', false,
      'message', 'Ce groupe ne se rejoint pas librement.');
  end if;
  v_obstacle := obstacle_groupe(p_groupe);
  if v_obstacle is not null then
    return jsonb_build_object('ok', false, 'message', v_obstacle);
  end if;

  insert into gt_membres (groupe_id, profil_id, role, statut)
  values (p_groupe, auth.uid(), 'membre', 'actif')
  on conflict (groupe_id, profil_id) do update set statut = 'actif';
  perform ajuster_acces_groupes(auth.uid());
  return jsonb_build_object('ok', true);
end $$;

create or replace function quitter_groupe(p_groupe uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from gt_membres
      where groupe_id = p_groupe and role = 'responsable' and statut = 'actif') = 1
     and exists (select 1 from gt_membres where groupe_id = p_groupe
                 and profil_id = auth.uid() and role = 'responsable') then
    return jsonb_build_object('ok', false,
      'message', 'Vous êtes seul responsable : confiez le groupe avant de le quitter.');
  end if;
  update gt_membres set statut = 'parti'
   where groupe_id = p_groupe and profil_id = auth.uid();
  perform ajuster_acces_groupes(auth.uid());
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 8. DIRE LA VÉRITÉ SUR L'ORIGINE D'UN ACCÈS
--    « Accordée nominativement par la direction » était faux pour un
--    accès ouvert par l'appartenance à une équipe. L'explication reprend
--    désormais le motif inscrit en base.
-- ---------------------------------------------------------------------

create or replace function mes_applications()
returns table (
  code text, nom text, nom_court text, description text, accroche text,
  logo text, couleur text, externe_url text, ordre integer,
  direction text, direction_nom text, direction_ordre integer,
  etat text, source text, ouvert boolean, demande_en_cours boolean,
  explication text, personnelle boolean
) language sql stable security definer set search_path = public as $$
  with vu as (select mon_niveau() >= 80 as federal)
  select a.code, a.nom, a.nom_court, a.description, a.accroche, a.logo,
         coalesce(a.couleur,'bleu'), a.externe_url, a.ordre,
         d.code, d.nom_court, coalesce(d.ordre, 999),
         case source_acces(a.code)
           when 'ferme' then 'invisible'
           when 'sur_demande' then 'sur_demande'
           else 'ouverte' end,
         source_acces(a.code),
         source_acces(a.code) in ('admin','nominatif','poste','fonction'),
         exists (select 1 from demandes dm
                 where dm.profil_id = auth.uid() and dm.cible = a.code
                   and dm.statut in ('ouverte','en_cours')),
         case source_acces(a.code)
           when 'admin' then 'Ouverte au titre de l''administration'
           when 'nominatif' then coalesce(
             (select 'Ouverte : ' || lower(x.motif) from acces_applications x
              where x.profil_id = auth.uid() and x.application = a.code
                and x.statut = 'accorde' and x.motif is not null),
             'Accordée nominativement par la direction')
           when 'poste' then 'Ouverte par un poste que vous occupez'
           when 'fonction' then 'Ouverte à votre fonction'
           when 'sur_demande' then 'À demander au guichet'
           else 'Non ouverte à votre fonction' end,
         d.code is null
  from applications a
  cross join vu
  left join directions d
    on d.code = case when vu.federal then a.direction
                     else coalesce(a.direction_locale, a.direction) end
  where a.actif
    and (source_acces(a.code) <> 'ferme'
         or (select v.etat from application_visibilite v
             where v.application = a.code
               and v.fonction = (select fonction from profils where id = auth.uid()))
            = 'sur_demande')
  order by coalesce(d.ordre, 0), a.ordre;
$$;

grant execute on function ajuster_acces_groupes(uuid),
                          proposer_equipe(text, text, uuid, uuid[], text[]),
                          valider_equipe(uuid, boolean, text), equipes_a_valider(),
                          postuler_groupe(uuid, text),
                          retenir_candidature(uuid, boolean, text),
                          candidatures_groupe(uuid), groupes_ouverts(),
                          repondre_invitation(uuid, boolean), rejoindre_groupe(uuid),
                          quitter_groupe(uuid), mes_applications()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 35
--
--  Vérifications :
--    select * from groupes_ouverts();
--    select * from equipes_a_valider();
--    select code, source, explication from mes_applications()
--     where code = 'groupes';
--
--  Sur la fermeture de l'application : elle se rouvre dès la première
--  appartenance et se referme à la dernière sortie, par une seule
--  fonction appelée depuis les cinq chemins d'entrée et de sortie. Les
--  membres déjà en place conservent leur accès : la migration le leur
--  pose explicitement.
--
--  Sur la fiche d'équipe : au moment de valider, elle est ramenée à ce
--  que le validateur détient lui-même. Il engage sa signature, pas
--  celle du proposant.
-- =====================================================================
