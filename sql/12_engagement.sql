-- =====================================================================
--  FFCE — Migration 12 — ENGAGEMENT, MISSIONS ET ADHÉSION
--
--  Trois ajouts qui répondent à la même question : qu'est-ce qui donne
--  envie de revenir sur la plateforme ?
--
--  1. L'ENGAGEMENT MENSUEL. Chacun déclare ce qu'il peut donner ce
--     mois-ci. Historisé mois par mois, jamais écrasé — ce qui permet
--     de voir qui tient ses engagements, sans jamais le reprocher :
--     un bénévole n'est pas un salarié.
--
--  2. LES MISSIONS. Des actions ouvertes au volontariat, avec places,
--     dates, territoire et certification éventuellement requise. On s'y
--     porte candidat, le porteur retient.
--
--  3. LE DOSSIER D'ADHÉSION. Les informations recueillies à l'entrée,
--     conservées à part, exportables par les seules personnes
--     habilitées.
--
--  Prérequis : 01 à 11.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ENGAGEMENT MENSUEL
-- ---------------------------------------------------------------------

create table if not exists engagements (
  id           uuid primary key default gen_random_uuid(),
  profil_id    uuid not null references profils(id) on delete cascade,
  mois         date not null,                 -- toujours le 1er du mois
  heures_visees   numeric(5,1) not null default 0,
  heures_realisees numeric(5,1),
  commentaire  text,
  maj_le       timestamptz not null default now(),
  unique (profil_id, mois)
);
create index if not exists idx_eng_mois on engagements(mois);

create or replace function regler_engagement(
  p_mois date, p_visees numeric, p_realisees numeric default null,
  p_commentaire text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mois date;
begin
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  v_mois := date_trunc('month', coalesce(p_mois, current_date))::date;
  if p_visees < 0 or p_visees > 200 then
    return jsonb_build_object('ok', false, 'message', 'Indiquez un nombre d''heures réaliste.');
  end if;

  insert into engagements (profil_id, mois, heures_visees, heures_realisees, commentaire)
  values (auth.uid(), v_mois, p_visees, p_realisees, nullif(trim(p_commentaire),''))
  on conflict (profil_id, mois) do update
    set heures_visees = excluded.heures_visees,
        heures_realisees = coalesce(excluded.heures_realisees, engagements.heures_realisees),
        commentaire = coalesce(excluded.commentaire, engagements.commentaire),
        maj_le = now();

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 2. MISSIONS OUVERTES AU VOLONTARIAT
-- ---------------------------------------------------------------------

create table if not exists missions (
  id                    uuid primary key default gen_random_uuid(),
  titre                 text not null,
  description           text,
  territoire_id         uuid references territoires(id),
  groupe_id             uuid references groupes_travail(id) on delete set null,
  certification_requise text references certifications(code) on delete set null,
  lieu                  text,
  debut                 date,
  fin                   date,
  heures_estimees       numeric(5,1),
  places                integer not null default 1,
  statut                text not null default 'ouverte'
                          check (statut in ('ouverte','complete','close','annulee')),
  cree_par              uuid references profils(id),
  cree_le               timestamptz not null default now()
);
create index if not exists idx_missions_statut on missions(statut);

create table if not exists mission_candidatures (
  id         uuid primary key default gen_random_uuid(),
  mission_id uuid not null references missions(id) on delete cascade,
  profil_id  uuid not null references profils(id) on delete cascade,
  message    text,
  statut     text not null default 'candidat'
               check (statut in ('candidat','retenu','non_retenu','desiste')),
  motif      text,
  decide_par uuid references profils(id),
  decide_le  timestamptz,
  cree_le    timestamptz not null default now(),
  unique (mission_id, profil_id)
);

-- Puis-je me porter volontaire ? Renvoie le motif du refus, ou null.
create or replace function obstacle_mission(p_mission uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare m missions; v_retenus int;
begin
  select * into m from missions where id = p_mission;
  if m is null then return 'Mission introuvable.'; end if;
  if m.statut <> 'ouverte' then return 'Cette mission n''est plus ouverte.'; end if;
  if (select statut from profils where id = auth.uid()) <> 'actif'
    then return 'Compte non validé.'; end if;
  if m.certification_requise is not null and not a_certification(m.certification_requise) then
    return 'Cette mission demande la certification « ' ||
           (select nom from certifications where code = m.certification_requise) || ' ».';
  end if;
  if m.territoire_id is not null and not est_admin()
     and not exists (select 1 from territoires_sous(m.territoire_id) s
                     where s.id = (select territoire_id from profils where id = auth.uid()))
    then return 'Cette mission concerne un autre territoire.'; end if;

  select count(*) into v_retenus from mission_candidatures
   where mission_id = p_mission and statut = 'retenu';
  if v_retenus >= m.places then return 'Toutes les places sont pourvues.'; end if;

  return null;
end $$;

create or replace function postuler_mission(p_mission uuid, p_message text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_obstacle text;
begin
  v_obstacle := obstacle_mission(p_mission);
  if v_obstacle is not null then
    return jsonb_build_object('ok', false, 'message', v_obstacle);
  end if;

  insert into mission_candidatures (mission_id, profil_id, message)
  values (p_mission, auth.uid(), nullif(trim(p_message),''))
  on conflict (mission_id, profil_id) do update
    set statut = 'candidat', message = nullif(trim(p_message),''), cree_le = now();

  return jsonb_build_object('ok', true);
end $$;

create or replace function statuer_candidature(p_cand uuid, p_statut text, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mission uuid; v_places int; v_retenus int;
begin
  select mission_id into v_mission from mission_candidatures where id = p_cand;
  if not exists (select 1 from missions where id = v_mission
                 and (cree_par = auth.uid() or est_admin() or mon_niveau() >= 60)) then
    return jsonb_build_object('ok', false, 'message', 'Cette mission n''est pas la vôtre.');
  end if;

  update mission_candidatures
     set statut = p_statut, motif = nullif(trim(p_motif),''),
         decide_par = auth.uid(), decide_le = now()
   where id = p_cand;

  -- La mission se ferme d'elle-même quand les places sont pourvues.
  select places into v_places from missions where id = v_mission;
  select count(*) into v_retenus from mission_candidatures
   where mission_id = v_mission and statut = 'retenu';
  update missions set statut = case when v_retenus >= v_places then 'complete' else 'ouverte' end
   where id = v_mission and statut in ('ouverte','complete');

  return jsonb_build_object('ok', true);
end $$;

create or replace function creer_mission(
  p_titre text, p_description text, p_territoire uuid default null,
  p_groupe uuid default null, p_certification text default null,
  p_lieu text default null, p_debut date default null, p_fin date default null,
  p_heures numeric default null, p_places integer default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (mon_echelon() >= 3 or mon_niveau() >= 50) then
    return jsonb_build_object('ok', false,
      'message', 'Proposer une mission demande l''échelon 3 ou une fonction d''encadrement.');
  end if;
  insert into missions (titre, description, territoire_id, groupe_id,
                        certification_requise, lieu, debut, fin, heures_estimees,
                        places, cree_par)
  values (trim(p_titre), nullif(trim(p_description),''), p_territoire, p_groupe,
          nullif(p_certification,''), nullif(trim(p_lieu),''), p_debut, p_fin,
          p_heures, greatest(coalesce(p_places,1),1), auth.uid())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function missions_ouvertes()
returns table (
  id uuid, titre text, description text, lieu text, debut date, fin date,
  heures_estimees numeric, places integer, retenus integer, statut text,
  territoire_nom text, groupe_nom text, certification_nom text,
  porteur text, obstacle text, ma_candidature text
) language sql stable security definer set search_path = public as $$
  select m.id, m.titre, m.description, m.lieu, m.debut, m.fin,
         m.heures_estimees, m.places,
         (select count(*)::int from mission_candidatures c
           where c.mission_id = m.id and c.statut = 'retenu'),
         m.statut, t.nom, g.nom, ce.nom,
         trim(p.prenom || ' ' || p.nom),
         obstacle_mission(m.id),
         (select c.statut from mission_candidatures c
           where c.mission_id = m.id and c.profil_id = auth.uid())
  from missions m
  left join territoires t     on t.id = m.territoire_id
  left join groupes_travail g on g.id = m.groupe_id
  left join certifications ce on ce.code = m.certification_requise
  left join profils p         on p.id = m.cree_par
  where m.statut in ('ouverte','complete')
    and (m.fin is null or m.fin >= current_date)
  order by coalesce(m.debut, m.cree_le::date);
$$;

-- ---------------------------------------------------------------------
-- 3. MON TABLEAU D'ENGAGEMENT
--    Ce que je vois en premier : ce que j'ai promis, ce qu'on attend de
--    moi, et ce qui arrive.
-- ---------------------------------------------------------------------

create or replace function mon_engagement()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mois', date_trunc('month', current_date)::date,
    'heures_visees', coalesce((select heures_visees from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date), 0),
    'heures_realisees', (select heures_realisees from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date),
    'declare', exists (select 1 from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date),
    'historique', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mois', e.mois, 'visees', e.heures_visees, 'realisees', e.heures_realisees)
        order by e.mois desc)
      from engagements e where e.profil_id = auth.uid()
        and e.mois >= (date_trunc('month', current_date) - interval '11 months')::date),
      '[]'::jsonb),
    'taches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'titre', k.titre, 'echeance', k.echeance,
        'priorite', k.priorite, 'statut', k.statut, 'groupe', g.nom,
        'groupe_id', g.id,
        'retard', k.echeance is not null and k.echeance < current_date)
        order by k.echeance nulls last)
      from gt_taches k join groupes_travail g on g.id = k.groupe_id
      where k.assigne_a = auth.uid() and k.statut in ('a_faire','en_cours')),
      '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'titre', m.titre, 'debut', m.debut, 'fin', m.fin, 'lieu', m.lieu,
        'statut', c.statut) order by m.debut nulls last)
      from mission_candidatures c join missions m on m.id = c.mission_id
      where c.profil_id = auth.uid() and c.statut in ('candidat','retenu')
        and (m.fin is null or m.fin >= current_date)),
      '[]'::jsonb),
    -- avancement() renvoie une table : PostgreSQL refuse un tel appel à
    -- l'intérieur d'un jsonb_agg. On le passe donc en jointure latérale.
    'formations_en_cours', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'titre', f.titre, 'pourcent', av.pourcent))
      from formations f
      cross join lateral avancement(f.id) av
      where f.publiee and av.pourcent between 1 and 99),
      '[]'::jsonb),
    'missions_disponibles', (select count(*)::int from missions_ouvertes()
      where obstacle is null and ma_candidature is null)
  );
$$;

-- ---------------------------------------------------------------------
-- 4. LE DOSSIER D'ADHÉSION
--    Conservé à part de la table des profils : ces informations sont
--    plus sensibles et ne doivent pas circuler avec l'annuaire.
-- ---------------------------------------------------------------------

create table if not exists dossier_adhesion (
  profil_id       uuid primary key references profils(id) on delete cascade,
  date_naissance  date,
  adresse         text,
  code_postal     text,
  ville           text,
  situation       text,          -- lycéen, étudiant, salarié, en recherche…
  profession      text,
  competences     text,
  disponibilites  text,
  motivation      text,
  origine         text,          -- comment le membre a connu la fédération
  deja_benevole   boolean,
  accepte_statuts boolean not null default false,
  accepte_rgpd    boolean not null default false,
  accepte_image   boolean not null default false,
  maj_le          timestamptz not null default now(),
  cree_le         timestamptz not null default now()
);

create or replace function enregistrer_adhesion(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce((d->>'accepte_statuts')::boolean, false) is not true
     or coalesce((d->>'accepte_rgpd')::boolean, false) is not true then
    return jsonb_build_object('ok', false,
      'message', 'L''acceptation des statuts et de la politique de confidentialité est requise.');
  end if;

  insert into dossier_adhesion (
    profil_id, date_naissance, adresse, code_postal, ville, situation,
    profession, competences, disponibilites, motivation, origine,
    deja_benevole, accepte_statuts, accepte_rgpd, accepte_image)
  values (auth.uid(),
    nullif(d->>'date_naissance','')::date, nullif(d->>'adresse',''),
    nullif(d->>'code_postal',''), nullif(d->>'ville',''), nullif(d->>'situation',''),
    nullif(d->>'profession',''), nullif(d->>'competences',''),
    nullif(d->>'disponibilites',''), nullif(d->>'motivation',''),
    nullif(d->>'origine',''), (d->>'deja_benevole')::boolean,
    true, true, coalesce((d->>'accepte_image')::boolean, false))
  on conflict (profil_id) do update set
    date_naissance = excluded.date_naissance, adresse = excluded.adresse,
    code_postal = excluded.code_postal, ville = excluded.ville,
    situation = excluded.situation, profession = excluded.profession,
    competences = excluded.competences, disponibilites = excluded.disponibilites,
    motivation = excluded.motivation, origine = excluded.origine,
    deja_benevole = excluded.deja_benevole, accepte_image = excluded.accepte_image,
    maj_le = now();

  return jsonb_build_object('ok', true);
end $$;

create or replace function mon_adhesion()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(to_jsonb(a) - 'profil_id', '{}'::jsonb)
  from dossier_adhesion a where a.profil_id = auth.uid();
$$;

-- Export : réservé, et tracé comme celui du registre disciplinaire.
insert into droits (code, nom, categorie, sensible, ordre)
values ('membres.exporter', 'Extraire le registre des adhésions', 'Membres', true, 45)
on conflict (code) do nothing;

insert into poste_droits (poste, droit) values ('delegue_admin','membres.exporter')
on conflict do nothing;

create or replace function registre_adhesions()
returns table (
  matricule text, prenom text, nom text, email text, telephone text,
  fonction text, echelon integer, territoire text, statut text,
  date_adhesion date, date_naissance date, adresse text, code_postal text,
  ville text, situation text, profession text, competences text,
  disponibilites text, motivation text, origine text,
  accepte_image boolean, inscrit_le timestamptz
) language sql stable security definer set search_path = public as $$
  select p.matricule, p.prenom, p.nom, p.email, p.telephone,
         f.nom, p.echelon, t.nom, p.statut, p.date_adhesion,
         a.date_naissance, a.adresse, a.code_postal, a.ville, a.situation,
         a.profession, a.competences, a.disponibilites, a.motivation, a.origine,
         a.accepte_image, p.cree_le
  from profils p
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  left join dossier_adhesion a on a.profil_id = p.id
  where a_droit('membres.exporter') and p.statut <> 'archive'
  order by p.nom, p.prenom;
$$;

-- ---------------------------------------------------------------------
-- 5. PROFIL ENRICHI
-- ---------------------------------------------------------------------

alter table profils add column if not exists pronoms text;
alter table profils add column if not exists langues text;
alter table profils add column if not exists reseaux text;
alter table profils add column if not exists devise text;   -- une phrase, sur la fiche

-- =====================================================================
--  6. SÉCURITÉ
-- =====================================================================

alter table engagements          enable row level security;
alter table missions             enable row level security;
alter table mission_candidatures enable row level security;
alter table dossier_adhesion     enable row level security;

drop policy if exists lire_engagements on engagements;
create policy lire_engagements on engagements for select using (
  profil_id = auth.uid() or est_admin()
  or exists (select 1 from profils p where p.id = profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);
drop policy if exists ecrire_engagements on engagements;
create policy ecrire_engagements on engagements for all
  using (profil_id = auth.uid()) with check (profil_id = auth.uid());

drop policy if exists lire_missions on missions;
create policy lire_missions on missions for select using (mon_niveau() >= 10);
drop policy if exists gerer_missions on missions;
create policy gerer_missions on missions for update
  using (cree_par = auth.uid() or est_admin() or mon_niveau() >= 60);
drop policy if exists suppr_missions on missions;
create policy suppr_missions on missions for delete
  using (cree_par = auth.uid() or est_admin());

drop policy if exists lire_candidatures on mission_candidatures;
create policy lire_candidatures on mission_candidatures for select using (
  profil_id = auth.uid() or est_admin()
  or exists (select 1 from missions m where m.id = mission_id
             and (m.cree_par = auth.uid() or mon_niveau() >= 60))
);

-- Le dossier d'adhésion : son titulaire, et les personnes habilitées.
drop policy if exists lire_adhesion on dossier_adhesion;
create policy lire_adhesion on dossier_adhesion for select using (
  profil_id = auth.uid() or est_admin()
  or a_droit('membres.valider') or a_droit('membres.exporter')
);
drop policy if exists ecrire_adhesion on dossier_adhesion;
create policy ecrire_adhesion on dossier_adhesion for all
  using (profil_id = auth.uid()) with check (profil_id = auth.uid());

grant select on engagements, missions, mission_candidatures, dossier_adhesion
  to authenticated;
grant insert, update, delete on engagements, missions, mission_candidatures,
      dossier_adhesion to authenticated;

grant execute on function regler_engagement(date, numeric, numeric, text),
                          obstacle_mission(uuid), postuler_mission(uuid, text),
                          statuer_candidature(uuid, text, text),
                          creer_mission(text, text, uuid, uuid, text, text,
                                        date, date, numeric, integer),
                          missions_ouvertes(), mon_engagement(),
                          enregistrer_adhesion(jsonb), mon_adhesion(),
                          registre_adhesions()
  to authenticated;

-- ---------------------------------------------------------------------
-- 7. L'APPLICATION, OUVERTE À TOUS
-- ---------------------------------------------------------------------

insert into applications (code, nom, description, icone, niveau_min, sur_demande, ordre)
values ('engagement', 'Mon engagement',
        'Ce que je donne ce mois-ci, mes tâches, mes échéances et les missions ouvertes.',
        'heart', 10, false, 5)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description, ordre = excluded.ordre;

insert into application_visibilite (application, fonction, etat)
select 'engagement', f.code, 'ouverte' from fonctions f
on conflict (application, fonction) do update set etat = 'ouverte';

-- =====================================================================
--  FIN DE LA MIGRATION 12
--
--  Vérifications :
--    select mon_engagement();
--    select * from missions_ouvertes();
--    select count(*) from registre_adhesions();
--
--  Un mot sur l'engagement déclaré : il sert à s'organiser, jamais à
--  sanctionner. Un bénévole qui ne tient pas ses heures n'a de compte à
--  rendre à personne — c'est la différence avec un contrat de travail,
--  et l'interface le dit explicitement.
-- =====================================================================
