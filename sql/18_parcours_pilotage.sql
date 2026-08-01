-- =====================================================================
--  FFCE — Migration 18 — PARCOURS ADHÉRENT ET PILOTAGE PAR ÉCHELON
--
--  Deux chantiers qui n'en font qu'un : le parcours produit les données
--  que les tableaux de bord lisent.
--
--  1. LE PARCOURS D'ACCUEIL. Six étapes, du dépôt de la candidature à
--     la première mission. Chacune est datée, ce qui permet de voir
--     exactement où l'on perd les gens.
--
--  2. LES RENDEZ-VOUS. Le responsable du parcours pose ses
--     disponibilités, le nouvel adhérent choisit un créneau.
--
--  3. LE TUNNEL DU BÉNÉVOLE. Combien d'inscrits ce mois, combien
--     validés, combien formés, combien en mission, combien encore là à
--     six mois. Chaque marche perdue se voit.
--
--  4. TROIS TABLEAUX DE BORD. Local : quatre choses, rien de plus.
--     Départemental : le tunnel. National : le pilotage par
--     l'exception — on ne regarde pas les 101 départements, on regarde
--     les douze qui vont mal.
--
--  Prérequis : 01 à 17.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE PARCOURS D'ACCUEIL
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('parcours.accueillir', 'Accueillir et accompagner les nouveaux adhérents',
   'Membres', false, 46)
on conflict (code) do nothing;

insert into postes (code, nom, description, couleur, systeme) values
  ('parcours_adherent', 'Responsable du parcours adhérent',
   'Accueille les nouveaux membres, suit leur intégration jusqu''à la première mission et tient les rendez-vous d''accueil.',
   'vert', true)
on conflict (code) do update set description = excluded.description;

insert into poste_droits (poste, droit) values
  ('parcours_adherent','parcours.accueillir'),
  ('parcours_adherent','membres.consulter'),
  ('parcours_adherent','membres.valider')
on conflict do nothing;

create table if not exists parcours (
  profil_id        uuid primary key references profils(id) on delete cascade,
  referent_id      uuid references profils(id) on delete set null,
  inscrit_le       timestamptz not null default now(),
  dossier_complet_le timestamptz,
  valide_le        timestamptz,
  contacte_le      timestamptz,
  rdv_le           timestamptz,
  forme_le         timestamptz,     -- certification d'accueil obtenue
  premiere_mission_le timestamptz,
  abandonne_le     timestamptz,
  motif_abandon    text,
  notes            text,
  maj_le           timestamptz not null default now()
);

-- Le parcours s'ouvre à l'inscription, sans intervention.
create or replace function ouvrir_parcours()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into parcours (profil_id) values (new.id)
  on conflict (profil_id) do nothing;
  return new;
end $$;

drop trigger if exists trg_ouvrir_parcours on profils;
create trigger trg_ouvrir_parcours
  after insert on profils
  for each row execute function ouvrir_parcours();

-- On rattrape les membres déjà inscrits.
insert into parcours (profil_id, inscrit_le, valide_le)
select p.id, p.cree_le,
       case when p.statut = 'actif' then coalesce(p.date_adhesion::timestamptz, p.cree_le) end
from profils p
on conflict (profil_id) do nothing;

-- Les étapes se datent d'elles-mêmes : on ne demande à personne de
-- cocher une case que le système peut constater.
create or replace function jalonner_parcours(p_profil uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update parcours p set
    dossier_complet_le = coalesce(p.dossier_complet_le,
      case when (completude_dossier(p_profil)->>'complet')::boolean then now() end),
    valide_le = coalesce(p.valide_le,
      case when (select statut from profils where id = p_profil) = 'actif' then now() end),
    forme_le = coalesce(p.forme_le,
      (select min(co.obtenue_le) from certifications_obtenues co
        where co.profil_id = p_profil and co.code in ('socle_citoyen','usage_si'))),
    premiere_mission_le = coalesce(p.premiere_mission_le,
      (select min(mc.decide_le) from mission_candidatures mc
        where mc.profil_id = p_profil and mc.statut = 'retenu')),
    maj_le = now()
  where p.profil_id = p_profil;
end $$;

create or replace function noter_parcours(p_profil uuid, p_champ text,
                                          p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('parcours.accueillir') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''accompagnez pas les nouveaux adhérents.');
  end if;
  if p_champ = 'contacte' then
    update parcours set contacte_le = now(), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'referent' then
    update parcours set referent_id = auth.uid(), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'notes' then
    update parcours set notes = nullif(trim(p_notes),''), maj_le = now() where profil_id = p_profil;
  elsif p_champ = 'abandon' then
    if coalesce(trim(p_notes),'') = '' then
      return jsonb_build_object('ok', false, 'message', 'Indiquez pourquoi le parcours s''arrête.');
    end if;
    update parcours set abandonne_le = now(), motif_abandon = trim(p_notes), maj_le = now()
     where profil_id = p_profil;
  elsif p_champ = 'reprise' then
    update parcours set abandonne_le = null, motif_abandon = null, maj_le = now()
     where profil_id = p_profil;
  else
    return jsonb_build_object('ok', false, 'message', 'Champ inconnu.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 2. RENDEZ-VOUS D'ACCUEIL
-- ---------------------------------------------------------------------

create table if not exists creneaux (
  id         uuid primary key default gen_random_uuid(),
  hote_id    uuid not null references profils(id) on delete cascade,
  debut      timestamptz not null,
  duree_min  integer not null default 30,
  lieu       text,
  visio      text,
  territoire_id uuid references territoires(id),
  reserve_par uuid references profils(id) on delete set null,
  reserve_le timestamptz,
  annule_le  timestamptz,
  motif_annulation text,
  cree_le    timestamptz not null default now()
);
create index if not exists idx_creneaux_debut on creneaux(debut);

create or replace function poser_creneaux(p_creneaux jsonb, p_duree integer,
                                          p_lieu text, p_visio text,
                                          p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_date text; v_n int := 0;
begin
  if not (a_droit('parcours.accueillir') or mon_niveau() >= 50) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne tenez pas de rendez-vous d''accueil.');
  end if;
  for v_date in select jsonb_array_elements_text(p_creneaux) loop
    insert into creneaux (hote_id, debut, duree_min, lieu, visio, territoire_id)
    values (auth.uid(), v_date::timestamptz, coalesce(p_duree,30),
            nullif(trim(p_lieu),''), nullif(trim(p_visio),''), p_territoire);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'poses', v_n);
end $$;

create or replace function reserver_creneau(p_creneau uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c creneaux;
begin
  select * into c from creneaux where id = p_creneau;
  if c is null then return jsonb_build_object('ok', false, 'message', 'Créneau introuvable.'); end if;
  if c.reserve_par is not null then
    return jsonb_build_object('ok', false, 'message', 'Ce créneau vient d''être pris.');
  end if;
  if c.annule_le is not null or c.debut < now() then
    return jsonb_build_object('ok', false, 'message', 'Ce créneau n''est plus disponible.');
  end if;

  update creneaux set reserve_par = auth.uid(), reserve_le = now()
   where id = p_creneau and reserve_par is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Ce créneau vient d''être pris.');
  end if;

  update parcours set rdv_le = c.debut, maj_le = now() where profil_id = auth.uid();
  return jsonb_build_object('ok', true, 'debut', c.debut);
end $$;

create or replace function annuler_creneau(p_creneau uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c creneaux;
begin
  select * into c from creneaux where id = p_creneau;
  if c is null then return jsonb_build_object('ok', false, 'message', 'Créneau introuvable.'); end if;
  if c.hote_id <> auth.uid() and c.reserve_par <> auth.uid() and not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Ce rendez-vous n''est pas le vôtre.');
  end if;

  if c.reserve_par = auth.uid() then
    -- Le membre se désiste : le créneau redevient libre.
    update creneaux set reserve_par = null, reserve_le = null where id = p_creneau;
    update parcours set rdv_le = null where profil_id = auth.uid();
  else
    update creneaux set annule_le = now(), motif_annulation = nullif(trim(p_motif),'')
     where id = p_creneau;
    if c.reserve_par is not null then
      update parcours set rdv_le = null where profil_id = c.reserve_par;
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function creneaux_disponibles()
returns table (id uuid, debut timestamptz, duree_min integer, lieu text,
               visio text, hote text, hote_fonction text)
language sql stable security definer set search_path = public as $$
  select c.id, c.debut, c.duree_min, c.lieu, c.visio,
         trim(p.prenom || ' ' || p.nom), f.nom
  from creneaux c
  join profils p on p.id = c.hote_id
  join fonctions f on f.code = p.fonction
  where c.reserve_par is null and c.annule_le is null and c.debut > now()
    and (c.territoire_id is null
         or c.territoire_id in (
             with recursive remonte as (
               select t.id, t.parent_id from territoires t
               where t.id = (select territoire_id from profils where id = auth.uid())
               union all
               select t.id, t.parent_id from territoires t
               join remonte r on t.id = r.parent_id)
             select id from remonte))
  order by c.debut
  limit 40;
$$;

create or replace function mes_rendez_vous()
returns table (id uuid, debut timestamptz, duree_min integer, lieu text, visio text,
               avec text, avec_fonction text, je_suis_hote boolean, passe boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.debut, c.duree_min, c.lieu, c.visio,
         case when c.hote_id = auth.uid()
              then trim(pr.prenom || ' ' || pr.nom)
              else trim(ho.prenom || ' ' || ho.nom) end,
         case when c.hote_id = auth.uid() then fr.nom else fh.nom end,
         c.hote_id = auth.uid(),
         c.debut < now()
  from creneaux c
  join profils ho on ho.id = c.hote_id
  join fonctions fh on fh.code = ho.fonction
  left join profils pr on pr.id = c.reserve_par
  left join fonctions fr on fr.code = pr.fonction
  where c.annule_le is null
    and (c.hote_id = auth.uid() or c.reserve_par = auth.uid())
    and c.reserve_par is not null
  order by c.debut;
$$;

-- ---------------------------------------------------------------------
-- 3. LE TUNNEL DU BÉNÉVOLE
--    Six marches. À chaque marche, combien restent, combien tombent.
-- ---------------------------------------------------------------------

create or replace function tunnel_benevole(p_territoire uuid default null,
                                           p_mois integer default 6)
returns jsonb language sql stable security definer set search_path = public as $$
  with base as (
    select pa.*, p.territoire_id, p.statut
    from parcours pa
    join profils p on p.id = pa.profil_id
    where pa.inscrit_le >= (date_trunc('month', current_date)
                            - ((coalesce(p_mois,6) - 1) || ' months')::interval)
      and (p_territoire is null
           or p.territoire_id in (select s.id from territoires_sous(p_territoire) s))),
  m as (
    select
      count(*)::int as inscrits,
      count(*) filter (where dossier_complet_le is not null)::int as complets,
      count(*) filter (where valide_le is not null)::int as valides,
      count(*) filter (where contacte_le is not null or rdv_le is not null)::int as accueillis,
      count(*) filter (where forme_le is not null)::int as formes,
      count(*) filter (where premiere_mission_le is not null)::int as engages,
      count(*) filter (where abandonne_le is not null)::int as abandons,
      count(*) filter (where inscrit_le < now() - interval '6 months'
                         and statut = 'actif')::int as fideles_6m,
      count(*) filter (where inscrit_le < now() - interval '6 months')::int as cohorte_6m
    from base)
  select case when not (est_admin() or mon_niveau() >= 50
                        or a_droit('parcours.accueillir') or a_droit('membres.consulter'))
    then jsonb_build_object('erreur', 'Réservé à l''encadrement.')
    else jsonb_build_object(
      'periode_mois', coalesce(p_mois,6),
      'marches', jsonb_build_array(
        jsonb_build_object('rang',1,'nom','Inscrits','n',m.inscrits,'perte',0),
        jsonb_build_object('rang',2,'nom','Dossier complet','n',m.complets,
          'perte', m.inscrits - m.complets),
        jsonb_build_object('rang',3,'nom','Adhésion validée','n',m.valides,
          'perte', m.complets - m.valides),
        jsonb_build_object('rang',4,'nom','Accueillis','n',m.accueillis,
          'perte', m.valides - m.accueillis),
        jsonb_build_object('rang',5,'nom','Formation d''accueil','n',m.formes,
          'perte', m.accueillis - m.formes),
        jsonb_build_object('rang',6,'nom','Première mission','n',m.engages,
          'perte', m.formes - m.engages)),
      'abandons', m.abandons,
      'retention_6m', case when m.cohorte_6m = 0 then null
        else round(m.fideles_6m::numeric / m.cohorte_6m * 100) end,
      'cohorte_6m', m.cohorte_6m,
      'delai_median_validation', (
        select round(percentile_cont(0.5) within group (
          order by extract(epoch from (valide_le - inscrit_le))/86400))::int
        from base where valide_le is not null),
      'delai_median_formation', (
        select round(percentile_cont(0.5) within group (
          order by extract(epoch from (forme_le - valide_le))/86400))::int
        from base where forme_le is not null and valide_le is not null))
    end
  from m;
$$;

-- Qui attend quoi, nominativement.
create or replace function nouveaux_a_accueillir(p_territoire uuid default null)
returns table (profil_id uuid, membre text, matricule text, email text,
               territoire text, inscrit_le timestamptz, jours integer,
               etape text, prochaine_action text, referent text,
               rdv_le timestamptz, notes text)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, p.email, t.nom,
         pa.inscrit_le, extract(day from now() - pa.inscrit_le)::int,
         case
           when pa.abandonne_le is not null then 'Parcours interrompu'
           when pa.premiere_mission_le is not null then 'Engagé'
           when pa.forme_le is not null then 'Formé'
           when pa.rdv_le is not null then 'Rendez-vous pris'
           when pa.contacte_le is not null then 'Contacté'
           when pa.valide_le is not null then 'Adhésion validée'
           when pa.dossier_complet_le is not null then 'Dossier complet'
           else 'Inscrit' end,
         case
           when pa.abandonne_le is not null then null
           when pa.premiere_mission_le is not null then null
           when pa.forme_le is not null then 'Lui proposer une première mission'
           when pa.valide_le is not null and pa.contacte_le is null then 'Prendre contact'
           when pa.valide_le is not null and pa.forme_le is null then 'Relancer sur la formation d''accueil'
           when pa.dossier_complet_le is not null then 'Valider l''adhésion'
           else 'Relancer pour compléter le dossier' end,
         trim(r.prenom || ' ' || r.nom), pa.rdv_le, pa.notes
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
  order by pa.inscrit_le;
$$;

-- ---------------------------------------------------------------------
-- 4. TABLEAU DE BORD LOCAL
--    Quatre choses. Pas une de plus : c'est l'échelon où l'on perd les
--    gens si l'outil est lourd.
-- ---------------------------------------------------------------------

create or replace function bord_local()
returns jsonb language sql stable security definer set search_path = public as $$
  with moi as (select territoire_id from profils where id = auth.uid())
  select jsonb_build_object(
    'territoire', (select t.nom from territoires t, moi where t.id = moi.territoire_id),
    'membres', jsonb_build_object(
      'total', (select count(*) from profils p, moi
                where p.territoire_id in (select s.id from territoires_sous(moi.territoire_id) s)
                  and p.statut = 'actif'),
      'nouveaux', (select count(*) from profils p, moi
                where p.territoire_id in (select s.id from territoires_sous(moi.territoire_id) s)
                  and p.cree_le > now() - interval '30 days'),
      'a_accueillir', (select count(*) from nouveaux_a_accueillir(
                        (select territoire_id from moi)))),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object('titre', m.titre, 'debut', m.debut,
             'lieu', m.lieu, 'places', m.places,
             'retenus', (select count(*) from mission_candidatures c
                         where c.mission_id = m.id and c.statut = 'retenu'))
             order by m.debut)
      from missions m, moi
      where m.statut in ('ouverte','complete')
        and (m.territoire_id is null or m.territoire_id in
             (select s.id from territoires_sous(moi.territoire_id) s))
        and (m.debut is null or m.debut >= current_date)
      limit 8), '[]'::jsonb),
    'taches', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'titre', k.titre,
             'echeance', k.echeance, 'groupe', g.nom, 'groupe_id', g.id,
             'retard', k.echeance is not null and k.echeance < current_date)
             order by k.echeance nulls last)
      from gt_taches k join groupes_travail g on g.id = k.groupe_id
      where k.assigne_a = auth.uid() and k.statut in ('a_faire','en_cours')
      limit 10), '[]'::jsonb),
    'attentes', (select coalesce(jsonb_agg(jsonb_build_object(
        'libelle', x.libelle, 'nombre', x.nombre, 'lien', x.lien)), '[]'::jsonb)
      from ce_qui_attend() x));
$$;

-- ---------------------------------------------------------------------
-- 5. TABLEAU DE BORD NATIONAL
--    Le pilotage par l'exception : on ne regarde pas les 101
--    départements, on regarde ceux qui vont mal.
-- ---------------------------------------------------------------------

create or replace function bord_national()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (est_admin() or mon_niveau() >= 80)
    then jsonb_build_object('erreur', 'Réservé à la direction nationale.')
    else jsonb_build_object(
      'membres_actifs', (select count(*) from profils where statut = 'actif'),
      'nouveaux_30j', (select count(*) from profils where cree_le > now() - interval '30 days'),
      'departements_couverts', (select count(distinct t.id) from territoires t
        where t.echelle = 'departement'
          and exists (select 1 from profils p where p.territoire_id in
                      (select s.id from territoires_sous(t.id) s) and p.statut = 'actif')),
      'heures_mois', (select coalesce(sum(heures_realisees),0) from engagements
        where mois = date_trunc('month', current_date)::date),
      'tunnel', tunnel_benevole(null, 6),
      -- Les exceptions, par ordre d'urgence.
      'alertes', jsonb_build_object(
        'structures_sans_president', (select count(*) from structures_en_alerte()
          where alerte = 'Aucun président élu'),
        'structures_vides', (select count(*) from structures_en_alerte()
          where alerte = 'Aucun membre actif'),
        'structures_inactives', (select count(*) from structures_en_alerte()
          where alerte = 'Aucune action depuis six mois'),
        'mandats_echus', (select count(*) from mandats_a_renouveler()
          where jours_restants < 0),
        'mandats_proches', (select count(*) from mandats_a_renouveler()
          where jours_restants between 0 and 180),
        'acces_dormants', (select count(*) from acces_applications x
          where x.statut = 'accorde' and x.revoque_le is null
            and not exists (select 1 from journal_acces j
                            where j.profil_id = x.profil_id and j.application = x.application)),
        'habilitations_expirantes', (select count(*) from nominations n
          where n.revoque_le is null and n.fin between current_date and current_date + 90),
        'dossiers_disciplinaires', (select count(*) from dossiers where statut <> 'clos'),
        'actes_a_controler', (select count(*) from actes_sensibles where statut = 'a_controler'),
        'formation_accueil_manquante', (select count(*) from profils p
          join fonctions f on f.code = p.fonction
          where p.statut = 'actif' and f.niveau >= 40
            and not exists (select 1 from certifications_obtenues c
                            where c.profil_id = p.id and c.code = 'usage_si'))),
      'top_regions', coalesce((
        select jsonb_agg(jsonb_build_object('nom', r.nom, 'membres', r.n) order by r.n desc)
        from (select t.nom, (select count(*) from profils p
                where p.territoire_id in (select s.id from territoires_sous(t.id) s)
                  and p.statut = 'actif') as n
              from territoires t where t.echelle = 'region') r
        where r.n > 0), '[]'::jsonb))
    end;
$$;

-- La liste des structures à reprendre, pour agir depuis le tableau.
create or replace function exceptions_reseau()
returns table (territoire_id uuid, territoire text, echelle text, parent text,
               membres integer, alerte text, gravite integer)
language sql stable security definer set search_path = public as $$
  select s.territoire_id, s.territoire, s.echelle, s.parent, s.membres, s.alerte,
         case s.alerte
           when 'Aucun membre actif' then 1
           when 'Aucun président élu' then 2
           when 'Aucune action depuis six mois' then 3
           else 4 end
  from structures_en_alerte() s
  where s.alerte is not null
  order by case s.alerte
    when 'Aucun membre actif' then 1
    when 'Aucun président élu' then 2
    when 'Aucune action depuis six mois' then 3
    else 4 end, s.territoire;
$$;

-- ---------------------------------------------------------------------
-- 6. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table parcours enable row level security;
alter table creneaux enable row level security;

drop policy if exists lire_parcours on parcours;
create policy lire_parcours on parcours for select using (
  profil_id = auth.uid() or est_admin() or a_droit('parcours.accueillir')
  or exists (select 1 from profils p where p.id = profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);
drop policy if exists gerer_parcours on parcours;
create policy gerer_parcours on parcours for update
  using (a_droit('parcours.accueillir') or est_admin());

drop policy if exists lire_creneaux on creneaux;
create policy lire_creneaux on creneaux for select using (mon_niveau() >= 10);
drop policy if exists gerer_creneaux on creneaux;
create policy gerer_creneaux on creneaux for all
  using (hote_id = auth.uid() or est_admin())
  with check (hote_id = auth.uid() or est_admin());

grant select on parcours, creneaux to authenticated;
grant insert, update, delete on creneaux to authenticated;
grant update on parcours to authenticated;

grant execute on function jalonner_parcours(uuid),
                          noter_parcours(uuid, text, text),
                          poser_creneaux(jsonb, integer, text, text, uuid),
                          reserver_creneau(uuid), annuler_creneau(uuid, text),
                          creneaux_disponibles(), mes_rendez_vous(),
                          tunnel_benevole(uuid, integer),
                          nouveaux_a_accueillir(uuid),
                          bord_local(), bord_national(), exceptions_reseau()
  to authenticated;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, droit_requis, couleur, ordre)
values ('parcours', 'Parcours adhérent', 'Accueil',
        'Nouveaux membres, rendez-vous d''accueil et suivi de l''intégration.',
        'Personne ne se perd entre l''inscription et la première mission.',
        100, true, 'parcours.accueillir', 'action', 55)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      droit_requis = excluded.droit_requis;

insert into application_visibilite (application, fonction, etat)
select 'parcours', f.code, case when f.niveau >= 60 then 'sur_demande' else 'invisible' end
from fonctions f
on conflict (application, fonction) do nothing;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, ordre)
values ('pilotage', 'Pilotage du réseau', 'Pilotage',
        'Tunnel du bénévole, structures en alerte, indicateurs par territoire.',
        'Voir où le réseau tient, et où il lâche.',
        50, false, 'nuit', 58)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche;

insert into application_visibilite (application, fonction, etat)
select 'pilotage', f.code, case when f.niveau >= 50 then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do update
  set etat = case when (select niveau from fonctions where code = application_visibilite.fonction) >= 50
                  then 'ouverte' else 'invisible' end;

-- =====================================================================
--  FIN DE LA MIGRATION 18
--
--  Pour nommer un responsable du parcours adhérent :
--    select nommer((select id from profils where email='…'),
--                  'parcours_adherent', null, null, 'Désigné par le bureau');
--
--  Vérifications :
--    select tunnel_benevole(null, 6);
--    select * from nouveaux_a_accueillir();
--    select bord_national();
--
--  Le principe du tunnel : chaque marche est datée par le système
--  lui-même quand il peut la constater — dossier complet, adhésion
--  validée, formation achevée, première mission. On ne demande à
--  personne de cocher une case que la base sait déjà remplir.
-- =====================================================================
