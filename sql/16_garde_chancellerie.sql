-- =====================================================================
--  FFCE — Migration 16 — GARDE HIÉRARCHIQUE ET CHANCELLERIE
--
--  Deux failles comblées, une contrainte posée, un métier outillé.
--
--  1. NUL NE DÉFAIT PLUS HAUT QUE SOI. Un membre de la DG habilité à
--     nommer pouvait révoquer les mandats d'un administrateur. C'était
--     la faille : le droit de nommer n'est pas le droit de tout défaire.
--
--  2. DOUBLE VALIDATION A POSTERIORI. Les actes sensibles s'exécutent
--     immédiatement — on ne bloque pas le réseau — mais ils remontent à
--     l'administrateur, qui peut les annuler. C'est le modèle du
--     contrôle de légalité : l'acte est exécutoire, le contrôle suit.
--
--  3. LE DOSSIER INCOMPLET BLOQUE. Tant qu'il manque une information
--     essentielle, le membre ne quitte pas son compte.
--
--  4. LA CHANCELLERIE. Le barème des points devient paramétrable, et
--     le responsable dispose des classements, des propositions de
--     promotion et de l'historique des décisions.
--
--  Prérequis : 01 à 15.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE POIDS D'UNE PERSONNE
--    Fonction + postes : on retient le plus élevé. C'est ce chiffre
--    qui décide de qui peut agir sur qui.
-- ---------------------------------------------------------------------

create or replace function poids_membre(p_profil uuid)
returns integer language sql stable security definer set search_path = public as $$
  select greatest(
    coalesce((select f.niveau from profils p join fonctions f on f.code = p.fonction
              where p.id = p_profil), 0),
    -- Un poste sensible pèse : porter « habilitations.gerer » ou
    -- « discipline.decider » place au niveau d'un directeur de pôle.
    coalesce((select max(case when d.sensible then 80 else 40 end)
              from nominations n
              join poste_droits pd on pd.poste = n.poste
              join droits d on d.code = pd.droit
              where n.profil_id = p_profil and nomination_active(n)), 0));
$$;

create or replace function mon_poids()
returns integer language sql stable security definer set search_path = public as $$
  select poids_membre(auth.uid());
$$;

-- La garde : puis-je agir sur cette personne ?
create or replace function puis_je_agir_sur(p_profil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_profil = auth.uid() then false           -- jamais sur soi-même
    when (select fonction from profils where id = auth.uid()) = 'admin'
         and (select fonction from profils where id = p_profil) <> 'admin' then true
    else mon_poids() > poids_membre(p_profil)
  end;
$$;

create or replace function motif_refus_action(p_profil uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when p_profil = auth.uid() then
      'Vous ne pouvez pas modifier vos propres habilitations.'
    when not puis_je_agir_sur(p_profil) then
      'Ce membre dispose d''habilitations égales ou supérieures aux vôtres. Seul un administrateur peut intervenir.'
    else null end;
$$;

-- ---------------------------------------------------------------------
-- 2. LE REGISTRE DES ACTES SENSIBLES
--    L'acte s'exécute, puis remonte. L'administrateur confirme ou
--    annule. Tant qu'il n'a pas tranché, l'acte est « à contrôler ».
-- ---------------------------------------------------------------------

create table if not exists actes_sensibles (
  id          uuid primary key default gen_random_uuid(),
  auteur_id   uuid not null references profils(id) on delete cascade,
  cible_id    uuid references profils(id) on delete set null,
  nature      text not null,
  libelle     text not null,
  avant       jsonb,
  apres       jsonb,
  reversible  boolean not null default true,
  statut      text not null default 'a_controler'
                check (statut in ('a_controler','confirme','annule')),
  controle_par uuid references profils(id),
  controle_le  timestamptz,
  observation  text,
  cree_le     timestamptz not null default now()
);
create index if not exists idx_actes_statut on actes_sensibles(statut, cree_le desc);

create or replace function inscrire_acte(
  p_cible uuid, p_nature text, p_libelle text,
  p_avant jsonb default null, p_apres jsonb default null,
  p_reversible boolean default true)
returns uuid language sql security definer set search_path = public as $$
  insert into actes_sensibles (auteur_id, cible_id, nature, libelle,
                               avant, apres, reversible)
  -- L'administrateur qui agit lui-même n'a pas à se contrôler.
  select auth.uid(), p_cible, p_nature, p_libelle, p_avant, p_apres,
         coalesce(p_reversible, true)
  where (select fonction from profils where id = auth.uid()) <> 'admin'
  returning id;
$$;

create or replace function controler_acte(p_acte uuid, p_confirmer boolean,
                                          p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a actes_sensibles;
begin
  if not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''administrateur.');
  end if;
  select * into a from actes_sensibles where id = p_acte and statut = 'a_controler';
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Acte déjà contrôlé.');
  end if;

  if not p_confirmer then
    if not a.reversible then
      return jsonb_build_object('ok', false,
        'message', 'Cet acte n''est pas réversible automatiquement. Corrigez-le à la main.');
    end if;

    -- Remise en l'état, selon la nature de l'acte.
    if a.nature = 'profil' then
      update profils set
        fonction      = coalesce(a.avant->>'fonction', fonction),
        echelon       = coalesce((a.avant->>'echelon')::int, echelon),
        statut        = coalesce(a.avant->>'statut', statut),
        territoire_id = coalesce((a.avant->>'territoire_id')::uuid, territoire_id),
        protege       = coalesce((a.avant->>'protege')::boolean, protege)
      where id = a.cible_id;
    elsif a.nature = 'nomination' then
      update nominations set revoque_le = now(), revoque_par = auth.uid(),
             motif_revocation = 'Annulée au contrôle'
       where id = (a.apres->>'nomination_id')::uuid and revoque_le is null;
    elsif a.nature = 'revocation' then
      update nominations set revoque_le = null, revoque_par = null, motif_revocation = null
       where id = (a.avant->>'nomination_id')::uuid;
    elsif a.nature = 'acces' then
      update acces_applications set statut = coalesce(a.avant->>'statut','revoque'),
             revoque_le = case when a.avant->>'statut' = 'accorde' then null else now() end
       where profil_id = a.cible_id and application = a.apres->>'application';
    end if;
  end if;

  update actes_sensibles
     set statut = case when p_confirmer then 'confirme' else 'annule' end,
         controle_par = auth.uid(), controle_le = now(),
         observation = nullif(trim(p_observation),'')
   where id = p_acte;

  return jsonb_build_object('ok', true);
end $$;

create or replace function actes_a_controler()
returns table (id uuid, auteur text, auteur_fonction text, cible text,
               cible_matricule text, nature text, libelle text,
               reversible boolean, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, trim(au.prenom || ' ' || au.nom), f.nom,
         trim(ci.prenom || ' ' || ci.nom), ci.matricule,
         a.nature, a.libelle, a.reversible, a.cree_le
  from actes_sensibles a
  join profils au on au.id = a.auteur_id
  join fonctions f on f.code = au.fonction
  left join profils ci on ci.id = a.cible_id
  where a.statut = 'a_controler' and est_admin()
  order by a.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 3. LES ACTIONS SENSIBLES, SOUS GARDE
-- ---------------------------------------------------------------------

create or replace function modifier_membre(p_profil uuid, p_champ text, p_valeur text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text; v_avant jsonb; v_libelle text;
begin
  if not (est_admin() or a_droit('membres.nommer')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas le réseau.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;
  if p_champ not in ('fonction','echelon','statut','territoire_id','protege') then
    return jsonb_build_object('ok', false, 'message', 'Champ non modifiable ici.');
  end if;

  select jsonb_build_object('fonction', fonction, 'echelon', echelon,
                            'statut', statut, 'territoire_id', territoire_id,
                            'protege', protege)
    into v_avant from profils where id = p_profil;

  -- Nul ne hisse quelqu'un à son propre niveau ou au-dessus.
  if p_champ = 'fonction' then
    if (select niveau from fonctions where code = p_valeur) >= mon_poids()
       and not est_admin() then
      return jsonb_build_object('ok', false,
        'message', 'Vous ne pouvez pas conférer une fonction égale ou supérieure à la vôtre.');
    end if;
    update profils set fonction = p_valeur where id = p_profil;
    v_libelle := 'Fonction portée à « ' ||
                 (select nom from fonctions where code = p_valeur) || ' »';
  elsif p_champ = 'echelon' then
    update profils set echelon = p_valeur::int where id = p_profil;
    v_libelle := 'Échelon porté à ' || p_valeur;
  elsif p_champ = 'statut' then
    update profils set statut = p_valeur where id = p_profil;
    v_libelle := 'Statut du compte : ' || replace(p_valeur,'_',' ');
  elsif p_champ = 'territoire_id' then
    update profils set territoire_id = nullif(p_valeur,'')::uuid where id = p_profil;
    v_libelle := 'Mutation vers ' ||
                 coalesce((select nom from territoires where id = nullif(p_valeur,'')::uuid),
                          'aucun territoire');
  elsif p_champ = 'protege' then
    update profils set protege = (p_valeur = 'true') where id = p_profil;
    v_libelle := case when p_valeur = 'true' then 'Protection renforcée activée'
                      else 'Protection renforcée levée' end;
  end if;

  perform inscrire_acte(p_profil, 'profil', v_libelle, v_avant,
                        jsonb_build_object(p_champ, p_valeur));
  return jsonb_build_object('ok', true);
end $$;

create or replace function nommer(
  p_profil uuid, p_poste text, p_territoire uuid default null,
  p_fin date default null, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_refus text; v_sensible boolean;
begin
  if not a_droit('habilitations.gerer') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne nommez pas.');
  end if;
  if not exists (select 1 from profils where id = p_profil and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas actif.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;
  if exists (select 1 from nominations n where n.profil_id = p_profil
             and n.poste = p_poste and nomination_active(n)) then
    return jsonb_build_object('ok', false, 'message', 'Ce membre occupe déjà ce poste.');
  end if;

  -- On ne confère pas un poste qui pèserait plus lourd que soi.
  select bool_or(d.sensible) into v_sensible from poste_droits pd
    join droits d on d.code = pd.droit where pd.poste = p_poste;
  if coalesce(v_sensible,false) and mon_poids() < 90 and not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Ce poste ouvre des droits sensibles : seul un administrateur peut le conférer.');
  end if;

  insert into nominations (profil_id, poste, territoire_id, fin, motif, nomme_par)
  values (p_profil, p_poste, p_territoire, p_fin, nullif(trim(p_motif),''), auth.uid())
  returning id into v_id;

  perform inscrire_acte(p_profil, 'nomination',
    'Nommé « ' || (select nom from postes where code = p_poste) || ' »',
    null, jsonb_build_object('nomination_id', v_id, 'poste', p_poste));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function revoquer(p_nomination uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n nominations; v_refus text;
begin
  if not a_droit('habilitations.gerer') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne révoquez pas.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;
  select * into n from nominations where id = p_nomination and revoque_le is null;
  if n is null then
    return jsonb_build_object('ok', false, 'message', 'Cette nomination est déjà close.');
  end if;
  v_refus := motif_refus_action(n.profil_id);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  update nominations set revoque_le = now(), revoque_par = auth.uid(),
         motif_revocation = trim(p_motif)
   where id = p_nomination;

  perform inscrire_acte(n.profil_id, 'revocation',
    'Retrait du poste « ' || (select nom from postes where code = n.poste) || ' »',
    jsonb_build_object('nomination_id', p_nomination), null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function accorder_acces(
  p_profil uuid, p_app text, p_motif text default null, p_expire date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text; v_avant jsonb;
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les accès.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  select jsonb_build_object('statut', statut) into v_avant
    from acces_applications where profil_id = p_profil and application = p_app;

  insert into acces_applications (profil_id, application, statut, motif, accorde_par, expire_le)
  values (p_profil, p_app, 'accorde', nullif(trim(p_motif),''), auth.uid(), p_expire)
  on conflict (profil_id, application) do update
    set statut = 'accorde', revoque_le = null, revoque_par = null,
        motif_revocation = null, motif = nullif(trim(p_motif),''),
        accorde_par = auth.uid(), expire_le = p_expire;

  perform inscrire_acte(p_profil, 'acces',
    'Accès ouvert : ' || (select nom from applications where code = p_app),
    v_avant, jsonb_build_object('application', p_app));
  return jsonb_build_object('ok', true);
end $$;

create or replace function revoquer_acces(p_profil uuid, p_app text, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text;
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les accès.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  update acces_applications
     set statut = 'revoque', revoque_le = now(), revoque_par = auth.uid(),
         motif_revocation = trim(p_motif)
   where profil_id = p_profil and application = p_app;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Aucun accès à révoquer.');
  end if;

  perform inscrire_acte(p_profil, 'acces',
    'Accès retiré : ' || (select nom from applications where code = p_app),
    jsonb_build_object('statut','accorde'), jsonb_build_object('application', p_app));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. TOUS LES ACCÈS D'UN MEMBRE, ET LEUR ORIGINE
--    Nominatif, par fonction, ou par poste : on doit voir d'où vient
--    chaque droit pour savoir ce qu'on peut retirer.
-- ---------------------------------------------------------------------

create or replace function acces_complets(p_profil uuid)
returns table (application text, nom text, couleur text, ouvert boolean,
               origine text, detail text, statut text, expire_le date,
               motif text, derniere_utilisation timestamptz, nb_ouvertures integer,
               retirable boolean)
language sql stable security definer set search_path = public as $$
  with moi as (select p.fonction, f.niveau from profils p
               join fonctions f on f.code = p.fonction where p.id = p_profil)
  select a.code, a.nom, coalesce(a.couleur,'bleu'),
         -- Ouvert par la matrice, par un poste, ou nominativement ?
         coalesce(v.etat,'invisible') = 'ouverte'
           or (a.droit_requis is not null and exists (
                 select 1 from nominations n
                 join poste_droits pd on pd.poste = n.poste
                 where n.profil_id = p_profil and pd.droit = a.droit_requis
                   and nomination_active(n)))
           or (x.statut = 'accorde' and x.revoque_le is null
               and (x.expire_le is null or x.expire_le >= current_date)),
         case
           when x.id is not null then 'Octroi nominatif'
           when a.droit_requis is not null and exists (
                  select 1 from nominations n join poste_droits pd on pd.poste = n.poste
                  where n.profil_id = p_profil and pd.droit = a.droit_requis
                    and nomination_active(n)) then 'Poste occupé'
           when coalesce(v.etat,'invisible') = 'ouverte' then 'Fonction'
           when coalesce(v.etat,'invisible') = 'sur_demande' then 'Sur demande'
           else 'Non ouverte' end,
         case
           when x.id is not null then coalesce(x.motif, 'Accordé nominativement')
           when a.droit_requis is not null then
             coalesce((select string_agg(po.nom, ', ') from nominations n
                       join postes po on po.code = n.poste
                       join poste_droits pd on pd.poste = n.poste
                       where n.profil_id = p_profil and pd.droit = a.droit_requis
                         and nomination_active(n)),
                      'Exige : ' || (select d.nom from droits d where d.code = a.droit_requis))
           when coalesce(v.etat,'invisible') = 'ouverte' then
             'Ouverte à la fonction « ' || (select f.nom from fonctions f, moi
                                            where f.code = moi.fonction) || ' »'
           else 'Non ouverte à cette fonction' end,
         coalesce(x.statut, '—'), x.expire_le, x.motif,
         (select max(j.cree_le) from journal_acces j
           where j.profil_id = p_profil and j.application = a.code),
         (select count(*)::int from journal_acces j
           where j.profil_id = p_profil and j.application = a.code),
         x.id is not null and x.statut = 'accorde'
  from applications a
  left join application_visibilite v on v.application = a.code
        and v.fonction = (select fonction from moi)
  left join acces_applications x on x.profil_id = p_profil and x.application = a.code
  where a.actif
    and (est_admin() or a_droit('acces.piloter') or a_droit('membres.nommer'))
  order by a.ordre;
$$;

-- ---------------------------------------------------------------------
-- 5. LE DOSSIER INCOMPLET BLOQUE
-- ---------------------------------------------------------------------

create or replace function completude_bloquante()
returns jsonb language sql stable security definer set search_path = public as $$
  select completude_dossier() || jsonb_build_object(
    'bloquant', not (completude_dossier()->>'complet')::boolean
                and (select statut from profils where id = auth.uid()) in ('actif','en_attente'));
$$;

-- ---------------------------------------------------------------------
-- 6. LA CHANCELLERIE
--    Le barème des points devient une table. Le responsable l'ajuste,
--    voit les classements et propose les promotions.
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('chancellerie.bareme',  'Fixer le barème des points',      'Valorisation', false, 240),
  ('chancellerie.suivre',  'Suivre l''activité et les mérites','Valorisation', false, 250),
  ('chancellerie.promouvoir','Proposer et arrêter les promotions','Valorisation', true, 260)
on conflict (code) do nothing;

insert into postes (code, nom, description, couleur, systeme) values
  ('chancellerie', 'Chancellerie et valorisation des compétences',
   'Tient le barème des mérites, suit l''activité du réseau et arrête les promotions d''échelon.',
   'or', true)
on conflict (code) do update set description = excluded.description;

insert into poste_droits (poste, droit) values
  ('chancellerie','chancellerie.bareme'),
  ('chancellerie','chancellerie.suivre'),
  ('chancellerie','chancellerie.promouvoir'),
  ('chancellerie','membres.consulter')
on conflict do nothing;

create table if not exists bareme_points (
  cle      text primary key,
  libelle  text not null,
  points   integer not null,
  unite    text not null,
  actif    boolean not null default true,
  ordre    integer not null default 100,
  maj_par  uuid references profils(id),
  maj_le   timestamptz not null default now()
);

insert into bareme_points (cle, libelle, points, unite, ordre) values
  ('certification', 'Certification obtenue',        25, 'par certification', 10),
  ('mission',       'Mission accomplie',            15, 'par mission',       20),
  ('responsabilite','Responsabilité de groupe',     20, 'par groupe',        30),
  ('tache',         'Tâche menée à terme',           5, 'par tâche',         40),
  ('heure',         'Heure de bénévolat déclarée',   2, 'par heure',         50),
  ('anciennete',    'Ancienneté',                    3, 'par mois',          60)
on conflict (cle) do nothing;

-- Le calcul lit désormais le barème.
create or replace function points_membre(p_profil uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with moi as (select coalesce(p_profil, auth.uid()) as id),
  b as (select cle, points, libelle from bareme_points where actif),
  brut as (
    select
      (select count(*) from certifications_obtenues c, moi where c.profil_id = moi.id)::int as certification,
      (select count(*) from mission_candidatures mc, moi
        where mc.profil_id = moi.id and mc.statut = 'retenu')::int as mission,
      (select count(*) from gt_membres g, moi
        where g.profil_id = moi.id and g.statut = 'actif' and g.role = 'responsable')::int as responsabilite,
      (select count(*) from gt_taches k, moi
        where k.assigne_a = moi.id and k.statut = 'faite')::int as tache,
      (select coalesce(sum(e.heures_realisees),0) from engagements e, moi
        where e.profil_id = moi.id)::int as heure,
      (select greatest(extract(year from age(now(), p.cree_le))::int * 12
              + extract(month from age(now(), p.cree_le))::int, 0)
        from profils p, moi where p.id = moi.id) as anciennete,
      (select p.echelon from profils p, moi where p.id = moi.id) as echelon),
  calc as (
    select b.cle, b.libelle, b.points,
           case b.cle when 'certification' then brut.certification
                      when 'mission' then brut.mission
                      when 'responsabilite' then brut.responsabilite
                      when 'tache' then brut.tache
                      when 'heure' then brut.heure
                      when 'anciennete' then brut.anciennete else 0 end as nb
    from b, brut)
  select jsonb_build_object(
    'total', (select coalesce(sum(nb * points),0)::int from calc),
    'detail', (select jsonb_object_agg(libelle, nb * points) from calc),
    'volumes', (select jsonb_object_agg(libelle, nb) from calc),
    'echelon', (select echelon from brut),
    'echelon_nom', (select nom from echelons where niveau = (select echelon from brut)),
    'palier_actuel', (select points from echelons where niveau = (select echelon from brut)),
    'prochain', (select jsonb_build_object('niveau', e.niveau, 'nom', e.nom,
                        'points', e.points, 'ouvre', e.ouvre)
                 from echelons e where e.niveau = (select echelon from brut) + 1),
    'atteint_le_palier',
      (select coalesce(sum(nb * points),0) from calc)
      >= coalesce((select points from echelons
                   where niveau = (select echelon from brut) + 1), 999999));
$$;

create or replace function regler_bareme(p_cle text, p_points integer)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('chancellerie.bareme') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la chancellerie.');
  end if;
  if p_points < 0 or p_points > 500 then
    return jsonb_build_object('ok', false, 'message', 'Valeur hors limites.');
  end if;
  update bareme_points set points = p_points, maj_par = auth.uid(), maj_le = now()
   where cle = p_cle;
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'bareme_modifie', p_cle, jsonb_build_object('points', p_points));
  return jsonb_build_object('ok', true);
end $$;

-- Le classement, et surtout : qui a atteint son palier.
create or replace function classement_merites(p_territoire uuid default null,
                                              p_limite integer default 50)
returns table (profil_id uuid, membre text, matricule text, fonction text,
               territoire text, echelon integer, points integer,
               palier_suivant integer, atteint boolean,
               heures_annee numeric, missions integer, certifications integer,
               derniere_activite timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, f.nom, t.nom, p.echelon,
         (points_membre(p.id)->>'total')::int,
         (select e.points from echelons e where e.niveau = p.echelon + 1),
         (points_membre(p.id)->>'atteint_le_palier')::boolean,
         (select coalesce(sum(e.heures_realisees),0) from engagements e
           where e.profil_id = p.id and e.mois >= date_trunc('year', current_date)),
         (select count(*)::int from mission_candidatures mc
           where mc.profil_id = p.id and mc.statut = 'retenu'),
         (select count(*)::int from certifications_obtenues c where c.profil_id = p.id),
         greatest(
           (select max(e.maj_le) from engagements e where e.profil_id = p.id),
           (select max(j.cree_le) from journal_acces j where j.profil_id = p.id))
  from profils p
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where p.statut = 'actif'
    and (est_admin() or a_droit('chancellerie.suivre'))
    and (p_territoire is null
         or p.territoire_id in (select s.id from territoires_sous(p_territoire) s))
  order by (points_membre(p.id)->>'total')::int desc
  limit greatest(coalesce(p_limite,50),1);
$$;

create table if not exists promotions (
  id          uuid primary key default gen_random_uuid(),
  profil_id   uuid not null references profils(id) on delete cascade,
  ancien      integer not null,
  nouveau     integer not null,
  points      integer,
  motif       text not null,
  decidee_par uuid references profils(id),
  cree_le     timestamptz not null default now()
);

create or replace function promouvoir(p_profil uuid, p_echelon integer, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ancien integer; v_refus text;
begin
  if not a_droit('chancellerie.promouvoir') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la chancellerie.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Toute promotion doit être motivée.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  select echelon into v_ancien from profils where id = p_profil;
  update profils set echelon = p_echelon where id = p_profil;

  insert into promotions (profil_id, ancien, nouveau, points, motif, decidee_par)
  values (p_profil, v_ancien, p_echelon,
          (points_membre(p_profil)->>'total')::int, trim(p_motif), auth.uid());

  perform inscrire_acte(p_profil, 'profil',
    'Promotion à l''échelon ' || p_echelon || ' — ' || trim(p_motif),
    jsonb_build_object('echelon', v_ancien),
    jsonb_build_object('echelon', p_echelon));
  return jsonb_build_object('ok', true);
end $$;

create or replace function chancellerie_synthese()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (est_admin() or a_droit('chancellerie.suivre'))
    then jsonb_build_object('erreur', 'Réservé à la chancellerie.')
    else jsonb_build_object(
      'membres_actifs', (select count(*) from profils where statut = 'actif'),
      'a_promouvoir', (select count(*) from profils p
        where p.statut = 'actif'
          and (points_membre(p.id)->>'atteint_le_palier')::boolean),
      'heures_mois', (select coalesce(sum(heures_realisees),0) from engagements
        where mois = date_trunc('month', current_date)::date),
      'heures_annee', (select coalesce(sum(heures_realisees),0) from engagements
        where mois >= date_trunc('year', current_date)),
      'certifications_mois', (select count(*) from certifications_obtenues
        where obtenue_le >= date_trunc('month', current_date)),
      'promotions_annee', (select count(*) from promotions
        where cree_le >= date_trunc('year', current_date)),
      'par_echelon', (select jsonb_object_agg(e.nom, (
          select count(*) from profils p where p.echelon = e.niveau and p.statut = 'actif'))
        from echelons e),
      'dormants', (select count(*) from profils p
        where p.statut = 'actif'
          and not exists (select 1 from journal_acces j where j.profil_id = p.id
                          and j.cree_le > now() - interval '90 days')
          and not exists (select 1 from engagements e where e.profil_id = p.id
                          and e.mois >= (date_trunc('month', current_date) - interval '3 months')::date))
    ) end;
$$;

-- ---------------------------------------------------------------------
-- 7. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table actes_sensibles enable row level security;
alter table bareme_points   enable row level security;
alter table promotions      enable row level security;

drop policy if exists lire_actes on actes_sensibles;
create policy lire_actes on actes_sensibles for select
  using (est_admin() or auteur_id = auth.uid());

drop policy if exists lire_bareme on bareme_points;
create policy lire_bareme on bareme_points for select using (mon_niveau() >= 10);
drop policy if exists ecrire_bareme on bareme_points;
create policy ecrire_bareme on bareme_points for all
  using (a_droit('chancellerie.bareme')) with check (a_droit('chancellerie.bareme'));

drop policy if exists lire_promotions on promotions;
create policy lire_promotions on promotions for select using (
  profil_id = auth.uid() or est_admin() or a_droit('chancellerie.suivre')
);

grant select on actes_sensibles, bareme_points, promotions to authenticated;
grant update on bareme_points to authenticated;

grant execute on function poids_membre(uuid), mon_poids(), puis_je_agir_sur(uuid),
                          motif_refus_action(uuid), inscrire_acte(uuid, text, text, jsonb, jsonb, boolean),
                          controler_acte(uuid, boolean, text), actes_a_controler(),
                          modifier_membre(uuid, text, text),
                          nommer(uuid, text, uuid, date, text), revoquer(uuid, text),
                          accorder_acces(uuid, text, text, date),
                          revoquer_acces(uuid, text, text), acces_complets(uuid),
                          completude_bloquante(), points_membre(uuid),
                          regler_bareme(text, integer),
                          classement_merites(uuid, integer),
                          promouvoir(uuid, integer, text), chancellerie_synthese()
  to authenticated;

insert into applications (code, nom, nom_court, description, accroche, niveau_min,
                          sur_demande, droit_requis, couleur, ordre)
values ('chancellerie', 'Chancellerie et valorisation', 'Chancellerie',
        'Barème des mérites, classements, promotions d''échelon.',
        'Reconnaître ce qui est donné.',
        100, true, 'chancellerie.suivre', 'brun', 75)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      droit_requis = excluded.droit_requis, couleur = excluded.couleur;

insert into application_visibilite (application, fonction, etat)
select 'chancellerie', f.code, 'invisible' from fonctions f
on conflict (application, fonction) do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 16
--
--  Pour nommer un responsable de la chancellerie :
--    select nommer((select id from profils where email='…'),
--                  'chancellerie', null, null, 'Désigné par le bureau');
--
--  Sur la garde hiérarchique : le poids d'une personne est le plus
--  élevé entre sa fonction et ses postes. Porter un droit sensible
--  place au niveau d'un directeur de pôle. Nul n'agit sur quelqu'un
--  d'un poids égal ou supérieur au sien — et nul n'agit sur soi-même.
-- =====================================================================
