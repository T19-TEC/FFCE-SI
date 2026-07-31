-- =====================================================================
--  FFCE — Migration 03 — GROUPES DE TRAVAIL
--
--  Groupes, responsables, invitations, documents (dont liens Workspace),
--  assignation de tâches.
--
--  Une certification peut conditionner l'entrée dans un groupe : c'est
--  ce qui relie la formation à l'action.
--
--  Prérequis : 01_socle.sql et 02_formations.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES GROUPES
-- ---------------------------------------------------------------------

create table if not exists groupes_travail (
  id                    uuid primary key default gen_random_uuid(),
  nom                   text not null,
  objet                 text,
  territoire_id         uuid references territoires(id),   -- null = national
  certification_requise text references certifications(code) on delete set null,
  niveau_min            integer not null default 10,
  ouvert                boolean not null default true,  -- true : on rejoint seul
                                                        -- false : sur invitation
  statut                text not null default 'actif'
                          check (statut in ('actif','archive')),
  cree_par              uuid references profils(id),
  cree_le               timestamptz not null default now()
);
create index if not exists idx_gt_territoire on groupes_travail(territoire_id);

create table if not exists gt_membres (
  id         uuid primary key default gen_random_uuid(),
  groupe_id  uuid not null references groupes_travail(id) on delete cascade,
  profil_id  uuid not null references profils(id) on delete cascade,
  role       text not null default 'membre' check (role in ('responsable','membre')),
  statut     text not null default 'actif' check (statut in ('invite','actif','parti')),
  invite_par uuid references profils(id),
  cree_le    timestamptz not null default now(),
  unique (groupe_id, profil_id)
);
create index if not exists idx_gtm_groupe on gt_membres(groupe_id);
create index if not exists idx_gtm_profil on gt_membres(profil_id);

create table if not exists gt_documents (
  id          uuid primary key default gen_random_uuid(),
  groupe_id   uuid not null references groupes_travail(id) on delete cascade,
  titre       text not null,
  description text,
  type        text not null default 'lien'
                check (type in ('lien','drive','docs','sheets','agenda','note')),
  url         text,
  contenu     text,                       -- pour une note écrite ici
  depose_par  uuid references profils(id),
  cree_le     timestamptz not null default now()
);
create index if not exists idx_gtd_groupe on gt_documents(groupe_id);

create table if not exists gt_taches (
  id          uuid primary key default gen_random_uuid(),
  groupe_id   uuid not null references groupes_travail(id) on delete cascade,
  titre       text not null,
  description text,
  assigne_a   uuid references profils(id) on delete set null,
  echeance    date,
  priorite    text not null default 'normale'
                check (priorite in ('basse','normale','haute')),
  statut      text not null default 'a_faire'
                check (statut in ('a_faire','en_cours','faite','abandonnee')),
  cree_par    uuid references profils(id),
  cree_le     timestamptz not null default now(),
  faite_le    timestamptz
);
create index if not exists idx_gtt_groupe  on gt_taches(groupe_id);
create index if not exists idx_gtt_assigne on gt_taches(assigne_a);

-- ---------------------------------------------------------------------
-- 2. APPARTENANCE
--    Fonctions SECURITY DEFINER : les politiques de gt_membres ne
--    peuvent pas interroger gt_membres sans tourner en rond.
-- ---------------------------------------------------------------------

create or replace function est_membre_gt(p_groupe uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from gt_membres
                 where groupe_id = p_groupe and profil_id = auth.uid()
                   and statut = 'actif');
$$;

create or replace function est_responsable_gt(p_groupe uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from gt_membres
    where groupe_id = p_groupe and profil_id = auth.uid()
      and statut = 'actif' and role = 'responsable');
$$;

-- Puis-je entrer dans ce groupe ? Renvoie le motif du refus, ou null.
create or replace function obstacle_groupe(p_groupe uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare g record;
begin
  select * into g from groupes_travail where id = p_groupe;
  if g is null then return 'Groupe introuvable.'; end if;
  if g.statut <> 'actif' then return 'Ce groupe est archivé.'; end if;
  if (select statut from profils where id = auth.uid()) <> 'actif'
    then return 'Compte non validé.'; end if;
  if mon_niveau() < g.niveau_min then
    return 'Ce groupe est réservé à une fonction plus élevée.'; end if;
  if g.certification_requise is not null and not a_certification(g.certification_requise) then
    return 'Ce groupe demande la certification « ' ||
           (select nom from certifications where code = g.certification_requise) || ' ».';
  end if;
  if g.territoire_id is not null
     and not exists (select 1 from territoires_sous(g.territoire_id) s
                     where s.id = (select territoire_id from profils where id = auth.uid()))
     and not est_admin() then
    return 'Ce groupe est réservé à un autre territoire.';
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- 3. ENTRER, INVITER, RÉPONDRE
-- ---------------------------------------------------------------------

create or replace function rejoindre_groupe(p_groupe uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_obstacle text; v_ouvert boolean;
begin
  v_obstacle := obstacle_groupe(p_groupe);
  if v_obstacle is not null then
    return jsonb_build_object('ok', false, 'message', v_obstacle);
  end if;

  select ouvert into v_ouvert from groupes_travail where id = p_groupe;
  if not v_ouvert and not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Ce groupe se rejoint sur invitation de son responsable.');
  end if;

  insert into gt_membres (groupe_id, profil_id, role, statut)
  values (p_groupe, auth.uid(), 'membre', 'actif')
  on conflict (groupe_id, profil_id)
    do update set statut = 'actif';

  return jsonb_build_object('ok', true);
end $$;

create or replace function inviter_au_groupe(p_groupe uuid, p_profil uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_responsable_gt(p_groupe) then
    return jsonb_build_object('ok', false,
      'message', 'Seul le responsable du groupe peut inviter.');
  end if;
  if not exists (select 1 from profils where id = p_profil and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas actif.');
  end if;

  insert into gt_membres (groupe_id, profil_id, role, statut, invite_par)
  values (p_groupe, p_profil, 'membre', 'invite', auth.uid())
  on conflict (groupe_id, profil_id)
    do update set statut = case when gt_membres.statut = 'parti' then 'invite'
                                else gt_membres.statut end;

  return jsonb_build_object('ok', true);
end $$;

create or replace function repondre_invitation(p_groupe uuid, p_accepte boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update gt_membres
     set statut = case when p_accepte then 'actif' else 'parti' end
   where groupe_id = p_groupe and profil_id = auth.uid() and statut = 'invite';
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Aucune invitation en cours.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function quitter_groupe(p_groupe uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_autres int;
begin
  if exists (select 1 from gt_membres where groupe_id = p_groupe
             and profil_id = auth.uid() and role = 'responsable') then
    select count(*) into v_autres from gt_membres
     where groupe_id = p_groupe and role = 'responsable'
       and statut = 'actif' and profil_id <> auth.uid();
    if v_autres = 0 then
      return jsonb_build_object('ok', false,
        'message', 'Désignez d''abord un autre responsable.');
    end if;
  end if;
  update gt_membres set statut = 'parti'
   where groupe_id = p_groupe and profil_id = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- Créer un groupe : à partir de l'échelon 3, ou d'une fonction d'encadrement.
create or replace function creer_groupe(
  p_nom text, p_objet text, p_territoire uuid default null,
  p_certification text default null, p_niveau_min integer default 10,
  p_ouvert boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (mon_echelon() >= 3 or mon_niveau() >= 50) then
    return jsonb_build_object('ok', false,
      'message', 'La création d''un groupe demande l''échelon 3 ou une fonction d''encadrement.');
  end if;

  insert into groupes_travail (nom, objet, territoire_id, certification_requise,
                               niveau_min, ouvert, cree_par)
  values (p_nom, p_objet, p_territoire, nullif(p_certification,''),
          coalesce(p_niveau_min,10), coalesce(p_ouvert,true), auth.uid())
  returning id into v_id;

  insert into gt_membres (groupe_id, profil_id, role, statut)
  values (v_id, auth.uid(), 'responsable', 'actif');

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 4. VUE DE LISTE
-- ---------------------------------------------------------------------

drop view if exists v_groupes;
create view v_groupes with (security_invoker = true) as
select g.*,
       t.nom as territoire_nom,
       c.nom as certification_nom,
       (select count(*) from gt_membres m
         where m.groupe_id = g.id and m.statut = 'actif')   as nb_membres,
       (select count(*) from gt_taches k
         where k.groupe_id = g.id and k.statut in ('a_faire','en_cours')) as nb_taches
from groupes_travail g
left join territoires t    on t.id = g.territoire_id
left join certifications c on c.code = g.certification_requise;

-- =====================================================================
--  5. SÉCURITÉ
-- =====================================================================

alter table groupes_travail enable row level security;
alter table gt_membres      enable row level security;
alter table gt_documents    enable row level security;
alter table gt_taches       enable row level security;

-- Le catalogue des groupes est visible de tous les membres actifs :
-- on doit pouvoir savoir qu'un groupe existe pour demander à le rejoindre.
-- Ce qu'il contient, en revanche, est réservé à ses membres.
drop policy if exists lire_groupes on groupes_travail;
create policy lire_groupes on groupes_travail for select
  using (mon_niveau() >= 10);

drop policy if exists creer_groupes on groupes_travail;
create policy creer_groupes on groupes_travail for insert
  with check (est_admin());

drop policy if exists maj_groupes on groupes_travail;
create policy maj_groupes on groupes_travail for update
  using (est_responsable_gt(id)) with check (est_responsable_gt(id));

drop policy if exists suppr_groupes on groupes_travail;
create policy suppr_groupes on groupes_travail for delete using (est_admin());

-- Membres : visibles des membres du groupe, et de chacun pour lui-même
-- (sans quoi on ne verrait pas ses propres invitations).
drop policy if exists lire_membres on gt_membres;
create policy lire_membres on gt_membres for select using (
  profil_id = auth.uid() or est_membre_gt(groupe_id) or est_admin()
);
drop policy if exists maj_membres on gt_membres;
create policy maj_membres on gt_membres for update
  using (est_responsable_gt(groupe_id)) with check (est_responsable_gt(groupe_id));
drop policy if exists suppr_membres on gt_membres;
create policy suppr_membres on gt_membres for delete
  using (est_responsable_gt(groupe_id));

-- Documents et tâches : membres du groupe, strictement.
drop policy if exists lire_docs on gt_documents;
create policy lire_docs on gt_documents for select
  using (est_membre_gt(groupe_id) or est_admin());
drop policy if exists ecrire_docs on gt_documents;
create policy ecrire_docs on gt_documents for insert
  with check (est_membre_gt(groupe_id) and depose_par = auth.uid());
drop policy if exists maj_docs on gt_documents;
create policy maj_docs on gt_documents for update
  using (depose_par = auth.uid() or est_responsable_gt(groupe_id));
drop policy if exists suppr_docs on gt_documents;
create policy suppr_docs on gt_documents for delete
  using (depose_par = auth.uid() or est_responsable_gt(groupe_id));

drop policy if exists lire_taches on gt_taches;
create policy lire_taches on gt_taches for select
  using (est_membre_gt(groupe_id) or est_admin());
drop policy if exists ecrire_taches on gt_taches;
create policy ecrire_taches on gt_taches for insert
  with check (est_membre_gt(groupe_id) and cree_par = auth.uid());
-- Chacun avance ses propres tâches ; le responsable les gère toutes.
drop policy if exists maj_taches on gt_taches;
create policy maj_taches on gt_taches for update using (
  est_responsable_gt(groupe_id) or cree_par = auth.uid() or assigne_a = auth.uid()
);
drop policy if exists suppr_taches on gt_taches;
create policy suppr_taches on gt_taches for delete
  using (est_responsable_gt(groupe_id) or cree_par = auth.uid());

-- ---------------------------------------------------------------------
-- 6. DROITS DE BASE
-- ---------------------------------------------------------------------

grant select on groupes_travail, gt_membres, gt_documents, gt_taches to authenticated;
grant select on v_groupes to authenticated;
grant insert, update, delete on gt_documents, gt_taches to authenticated;
grant update, delete on gt_membres to authenticated;
grant update on groupes_travail to authenticated;

grant execute on function est_membre_gt(uuid), est_responsable_gt(uuid),
                          obstacle_groupe(uuid), rejoindre_groupe(uuid),
                          inviter_au_groupe(uuid, uuid),
                          repondre_invitation(uuid, boolean),
                          quitter_groupe(uuid),
                          creer_groupe(text, text, uuid, text, integer, boolean)
  to authenticated;

-- ---------------------------------------------------------------------
-- 7. UN GROUPE POUR DÉMARRER
--    Ouvert à tous les membres certifiés « Socle citoyen » — la
--    démonstration que la formation conditionne l'accès au projet.
-- ---------------------------------------------------------------------

insert into groupes_travail (nom, objet, certification_requise, niveau_min, ouvert)
select 'Quartiers d''été',
       'Coordination nationale du projet : calendrier, outils communs, relais départementaux.',
       'socle_citoyen', 10, true
where not exists (select 1 from groupes_travail where nom = 'Quartiers d''été');

insert into groupes_travail (nom, objet, niveau_min, ouvert)
select 'Communication et site public',
       'Textes du site, réseaux sociaux, supports d''intervention.',
       30, false
where not exists (select 1 from groupes_travail where nom = 'Communication et site public');

-- =====================================================================
--  FIN DE LA MIGRATION 03
--
--  Vérification :
--    select nom, nb_membres, certification_nom, ouvert from v_groupes;
--
--  L'onglet Groupes de travail s'ouvre à partir de la fonction Bénévole.
-- =====================================================================
