-- =====================================================================
--  FFCE — Migration 20 — DIRECTIONS ET PARCOURS FLUIDE
--
--  1. LES DIRECTIONS. Ce qui manquait au menu : une strate au-dessus
--     des postes. Dans une fédération organisée, on n'appartient pas à
--     « des responsabilités » en vrac — on appartient à une direction.
--     Le menu suit désormais l'organigramme.
--
--  2. LE PARCOURS SE MET À JOUR SEUL. Les étapes restaient figées :
--     jalonner_parcours() n'était appelé nulle part. Il l'est
--     maintenant à chaque lecture, et les actions se font en un clic.
--
--  Prérequis : 01 à 19.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DIRECTIONS
--    Une direction regroupe des postes et des applications. C'est la
--    strate qui manquait entre l'individu et la fédération.
-- ---------------------------------------------------------------------

create table if not exists directions (
  code        text primary key,
  nom         text not null,
  nom_court   text,
  description text,
  couleur     text not null default 'bleu',
  ordre       integer not null default 100,
  actif       boolean not null default true
);

insert into directions (code, nom, nom_court, description, couleur, ordre) values
  ('dg',      'Direction générale', 'Direction générale',
   'Pilotage du réseau, habilitations, vérifications.', 'bleu', 10),
  ('daj',     'Affaires juridiques', 'Affaires juridiques',
   'Discipline, recours, conformité des élections, protection des données.', 'nuit', 20),
  ('dfin',    'Direction financière', 'Finances',
   'Instruction des dépenses, ordonnancement, paiements.', 'brun', 30),
  ('dircom',  'Communication', 'Communication',
   'Site public, publications, charte graphique.', 'framboise', 40),
  ('dvie',    'Vie associative', 'Vie associative',
   'Parcours des adhérents, assemblées, structures territoriales.', 'action', 50),
  ('dform',   'Formation et valorisation', 'Formation',
   'Parcours de formation, certifications, chancellerie.', 'or', 60)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, couleur = excluded.couleur,
      ordre = excluded.ordre;

alter table postes       add column if not exists direction text references directions(code);
alter table applications add column if not exists direction text references directions(code);

update postes set direction = case code
  when 'delegue_admin'        then 'dg'
  when 'daj'                  then 'daj'
  when 'conformite_election'  then 'daj'
  when 'ref_rgpd'             then 'daj'
  when 'ref_discrimination'   then 'daj'
  when 'conseil_discipline'   then 'daj'
  when 'ordonnateur'          then 'dfin'
  when 'dg_finance'           then 'dfin'
  when 'tresorier_structure'  then 'dfin'
  when 'dircom'               then 'dircom'
  when 'charge_com'           then 'dircom'
  when 'parcours_adherent'    then 'dvie'
  when 'president_structure'  then 'dvie'
  when 'secretaire_structure' then 'dvie'
  when 'chancellerie'         then 'dform'
  else direction end
where direction is null;

update applications set direction = case code
  when 'validation'     then 'dg'
  when 'habilitations'  then 'dg'
  when 'reseau'         then 'dg'
  when 'pilotage'       then 'dg'
  when 'annuaire'       then 'dg'
  when 'discipline'     then 'daj'
  when 'conformite'     then 'daj'
  when 'tresorerie'     then 'dfin'
  when 'ordonnancement' then 'dfin'
  when 'communication'  then 'dircom'
  when 'vitrine'        then 'dircom'
  when 'parcours'       then 'dvie'
  when 'assemblees'     then 'dvie'
  when 'chancellerie'   then 'dform'
  else direction end
where direction is null;

-- Mes directions : celles où j'occupe un poste, ou dont je détiens une
-- application. Le menu s'organise autour de cette liste.
create or replace function mes_directions()
returns table (code text, nom text, nom_court text, couleur text, ordre integer,
               par_poste boolean, postes text[])
language sql stable security definer set search_path = public as $$
  select d.code, d.nom, d.nom_court, d.couleur, d.ordre,
         exists (select 1 from nominations n
                 join postes po on po.code = n.poste
                 where n.profil_id = auth.uid() and nomination_active(n)
                   and po.direction = d.code),
         coalesce(array(select po.nom from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = auth.uid() and nomination_active(n)
                          and po.direction = d.code), '{}')
  from directions d
  where d.actif
    and (
      -- J'y occupe un poste
      exists (select 1 from nominations n join postes po on po.code = n.poste
              where n.profil_id = auth.uid() and nomination_active(n)
                and po.direction = d.code)
      -- ou j'y détiens une application ouverte
      or exists (select 1 from applications a
                 where a.direction = d.code and a.actif
                   and source_acces(a.code) in ('admin','nominatif','poste','fonction'))
    )
  order by d.ordre;
$$;

-- Les applications regroupées par direction, pour le menu.
drop function if exists mes_applications();
create or replace function mes_applications()
returns table (
  code text, nom text, nom_court text, description text, accroche text,
  logo text, couleur text, externe_url text, ordre integer,
  direction text, direction_nom text, direction_ordre integer,
  etat text, source text, ouvert boolean, demande_en_cours boolean,
  explication text, personnelle boolean
) language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.nom_court, a.description, a.accroche, a.logo,
         coalesce(a.couleur,'bleu'), a.externe_url, a.ordre,
         a.direction, d.nom_court, coalesce(d.ordre, 999),
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
           when 'nominatif' then 'Accordée nominativement par la direction'
           when 'poste' then 'Ouverte par un poste que vous occupez'
           when 'fonction' then 'Ouverte à votre fonction'
           when 'sur_demande' then 'À demander au guichet'
           else 'Non ouverte à votre fonction' end,
         -- Une application « personnelle » relève de mon activité de
         -- membre, pas d'une direction.
         a.direction is null
  from applications a
  left join directions d on d.code = a.direction
  where a.actif
    and (source_acces(a.code) <> 'ferme'
         or (select v.etat from application_visibilite v
             where v.application = a.code
               and v.fonction = (select fonction from profils where id = auth.uid()))
            = 'sur_demande')
  order by coalesce(d.ordre, 0), a.ordre;
$$;

-- ---------------------------------------------------------------------
-- 2. LE PARCOURS SE MET À JOUR SEUL
-- ---------------------------------------------------------------------

-- La liste jalonne au passage : plus besoin d'appeler la mise à jour
-- séparément, et les étapes ne peuvent plus être périmées.
create or replace function nouveaux_a_accueillir_maj(p_territoire uuid default null)
returns table (profil_id uuid, membre text, matricule text, email text,
               telephone text, territoire text, inscrit_le timestamptz,
               jours integer, etape text, etape_rang integer,
               prochaine_action text, referent text, referent_id uuid,
               rdv_le timestamptz, notes text, completude integer,
               manques text, sans_nouvelles boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  -- On rafraîchit les jalons de tout le périmètre avant de lire.
  perform jalonner_parcours(pa.profil_id)
  from parcours pa
  join profils p on p.id = pa.profil_id
  where pa.premiere_mission_le is null and pa.abandonne_le is null
    and p.statut <> 'archive'
    and (p_territoire is null
         or p.territoire_id in (select s.id from territoires_sous(p_territoire) s));

  return query
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, p.email, p.telephone,
         t.nom, pa.inscrit_le, extract(day from now() - pa.inscrit_le)::int,
         case
           when pa.premiere_mission_le is not null then 'Engagé'
           when pa.forme_le is not null then 'Formé'
           when pa.rdv_le is not null then 'Rendez-vous pris'
           when pa.contacte_le is not null then 'Contacté'
           when pa.valide_le is not null then 'Adhésion validée'
           when pa.dossier_complet_le is not null then 'Dossier complet'
           else 'Inscrit' end,
         case
           when pa.premiere_mission_le is not null then 6
           when pa.forme_le is not null then 5
           when pa.rdv_le is not null then 4
           when pa.contacte_le is not null then 4
           when pa.valide_le is not null then 3
           when pa.dossier_complet_le is not null then 2
           else 1 end,
         case
           when pa.forme_le is not null then 'Lui proposer une première mission'
           when pa.valide_le is not null and pa.contacte_le is null then 'Prendre contact'
           when pa.valide_le is not null and pa.forme_le is null then 'Relancer sur la formation d''accueil'
           when pa.dossier_complet_le is not null then 'Valider l''adhésion'
           else 'Relancer pour compléter le dossier' end,
         trim(r.prenom || ' ' || r.nom), pa.referent_id, pa.rdv_le, pa.notes,
         (completude_dossier(p.id)->>'pourcent')::int,
         (select string_agg(x, ', ') from jsonb_array_elements_text(
            completude_dossier(p.id)->'manques') x),
         pa.contacte_le is null and pa.inscrit_le < now() - interval '7 days'
  from parcours pa
  join profils p on p.id = pa.profil_id
  left join territoires t on t.id = p.territoire_id
  left join profils r on r.id = pa.referent_id
  where pa.premiere_mission_le is null and pa.abandonne_le is null
    and p.statut <> 'archive'
    and (est_admin() or a_droit('parcours.accueillir')
         or (mon_niveau() >= 50 and dans_mon_perimetre(p.territoire_id)))
    and (p_territoire is null
         or p.territoire_id in (select s.id from territoires_sous(p_territoire) s))
  order by
    case when pa.contacte_le is null and pa.inscrit_le < now() - interval '7 days'
         then 0 else 1 end,
    pa.inscrit_le;
end $$;

-- Une action, un appel. Le suivi ne doit pas coûter plus cher que le
-- geste qu'il enregistre.
create or replace function agir_parcours(p_profil uuid, p_action text,
                                         p_texte text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('parcours.accueillir') or est_admin()
          or (mon_niveau() >= 50 and dans_mon_perimetre(
                (select territoire_id from profils where id = p_profil)))) then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas dans votre périmètre.');
  end if;

  if p_action = 'contact' then
    update parcours set contacte_le = coalesce(contacte_le, now()),
           referent_id = coalesce(referent_id, auth.uid()),
           notes = case when coalesce(trim(p_texte),'') = '' then notes
                        else coalesce(notes || E'\n', '') ||
                             to_char(now(),'DD/MM') || ' — ' || trim(p_texte) end,
           maj_le = now()
     where profil_id = p_profil;

  elsif p_action = 'prendre_en_charge' then
    update parcours set referent_id = auth.uid(), maj_le = now() where profil_id = p_profil;

  elsif p_action = 'relancer' then
    update parcours set notes = coalesce(notes || E'\n', '') ||
             to_char(now(),'DD/MM') || ' — relance' ||
             coalesce(' : ' || nullif(trim(p_texte),''), ''),
           maj_le = now()
     where profil_id = p_profil;

  elsif p_action = 'valider' then
    return valider_inscription(p_profil, true, false);

  elsif p_action = 'note' then
    update parcours set notes = nullif(trim(p_texte),''), maj_le = now()
     where profil_id = p_profil;

  elsif p_action = 'clore' then
    if coalesce(trim(p_texte),'') = '' then
      return jsonb_build_object('ok', false, 'message', 'Indiquez pourquoi le parcours s''arrête.');
    end if;
    update parcours set abandonne_le = now(), motif_abandon = trim(p_texte), maj_le = now()
     where profil_id = p_profil;

  else
    return jsonb_build_object('ok', false, 'message', 'Action inconnue.');
  end if;

  perform jalonner_parcours(p_profil);
  return jsonb_build_object('ok', true);
end $$;

-- Prendre en charge plusieurs personnes d'un coup.
create or replace function agir_parcours_groupe(p_profils uuid[], p_action text,
                                                p_texte text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; v_ok int := 0; v_ko int := 0; r jsonb;
begin
  foreach v in array coalesce(p_profils, '{}') loop
    r := agir_parcours(v, p_action, p_texte);
    if (r->>'ok')::boolean then v_ok := v_ok + 1; else v_ko := v_ko + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'traites', v_ok, 'echecs', v_ko);
end $$;

-- ---------------------------------------------------------------------
-- 3. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table directions enable row level security;

drop policy if exists lire_directions on directions;
create policy lire_directions on directions for select using (mon_niveau() >= 10);
drop policy if exists gerer_directions on directions;
create policy gerer_directions on directions for all
  using (est_admin()) with check (est_admin());

grant select on directions to authenticated;
grant insert, update on directions to authenticated;

grant execute on function mes_directions(), mes_applications(),
                          nouveaux_a_accueillir_maj(uuid),
                          agir_parcours(uuid, text, text),
                          agir_parcours_groupe(uuid[], text, text)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 20
--
--  Vérifications :
--    select * from mes_directions();
--    select direction_nom, nom_court, source from mes_applications();
--    select membre, etape, prochaine_action, sans_nouvelles
--      from nouveaux_a_accueillir_maj();
--
--  Sur les directions : elles se créent et se modifient en base, sans
--  toucher au code. Rattacher un poste ou une application à une
--  direction suffit à la faire apparaître dans le menu de ceux qui en
--  relèvent.
-- =====================================================================
