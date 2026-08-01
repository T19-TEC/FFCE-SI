-- =====================================================================
--  FFCE — Migration 19 — COHÉRENCE, DISTINCTIONS ET CONFORMITÉ
--
--  1. L'ÉTAT AFFICHÉ DIT ENFIN LA VÉRITÉ. Une application était marquée
--     « non ouverte » alors qu'elle fonctionnait : l'étiquette lisait la
--     matrice des fonctions, tandis que l'accès réel vient de trois
--     sources — la fonction, un poste, ou un octroi nominatif. On
--     calcule désormais l'état à partir de la source effective.
--
--  2. L'ADMINISTRATEUR S'HABILITE LUI-MÊME. La garde hiérarchique
--     interdisait toute action sur soi. C'est juste pour tous, sauf
--     pour lui : sinon nul ne peut amorcer un poste vacant.
--
--  3. DISTINCTIONS. Reconnaître un engagement sans attendre un palier.
--     Une lettre de félicitations n'a pas besoin d'un barème.
--
--  4. CONFORMITÉ ÉLECTORALE. La recevabilité des candidatures, la
--     clôture et la proclamation reviennent à la DAJ et aux
--     responsables de la conformité. Les archives sont ouvertes aux
--     électeurs du scrutin.
--
--  5. ASSISTANCE. Chacun signale un problème ou propose une
--     amélioration ; la direction assigne, priorise et suit.
--
--  Prérequis : 01 à 18.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. L'ÉTAT RÉEL D'UNE APPLICATION
-- ---------------------------------------------------------------------

-- La source effective de l'accès, pour un membre donné.
create or replace function source_acces(p_app text, p_profil uuid default null)
returns text language sql stable security definer set search_path = public as $$
  with c as (select coalesce(p_profil, auth.uid()) as id),
  a as (select * from applications where code = p_app and actif)
  select case
    when (select fonction from profils, c where profils.id = c.id) = 'admin' then 'admin'
    when exists (select 1 from acces_applications x, c
                 where x.profil_id = c.id and x.application = p_app
                   and x.statut = 'accorde' and x.revoque_le is null
                   and (x.expire_le is null or x.expire_le >= current_date)) then 'nominatif'
    when exists (select 1 from a
                 join poste_droits pd on pd.droit = a.droit_requis
                 join nominations n on n.poste = pd.poste
                 where n.profil_id = (select id from c) and nomination_active(n)) then 'poste'
    when (select v.etat from application_visibilite v, c
          where v.application = p_app
            and v.fonction = (select fonction from profils where id = c.id)) = 'ouverte'
      then 'fonction'
    when (select v.etat from application_visibilite v, c
          where v.application = p_app
            and v.fonction = (select fonction from profils where id = c.id)) = 'sur_demande'
      then 'sur_demande'
    else 'ferme' end
  from a;
$$;

-- L'accès découle de la source : une seule règle, plus deux.
create or replace function a_acces(app text)
returns boolean language sql stable security definer set search_path = public as $$
  select source_acces(app) in ('admin','nominatif','poste','fonction');
$$;

drop function if exists mes_applications();
create or replace function mes_applications()
returns table (
  code text, nom text, nom_court text, description text, accroche text,
  logo text, couleur text, externe_url text, ordre integer,
  etat text, source text, ouvert boolean, demande_en_cours boolean,
  explication text
) language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.nom_court, a.description, a.accroche, a.logo,
         coalesce(a.couleur,'bleu'), a.externe_url, a.ordre,
         case source_acces(a.code)
           when 'ferme' then 'invisible'
           when 'sur_demande' then 'sur_demande'
           else 'ouverte' end,
         source_acces(a.code),
         source_acces(a.code) in ('admin','nominatif','poste','fonction'),
         exists (select 1 from demandes d
                 where d.profil_id = auth.uid() and d.cible = a.code
                   and d.statut in ('ouverte','en_cours')),
         case source_acces(a.code)
           when 'admin' then 'Ouverte au titre de l''administration'
           when 'nominatif' then 'Accordée nominativement par la direction'
           when 'poste' then 'Ouverte par un poste que vous occupez'
           when 'fonction' then 'Ouverte à votre fonction'
           when 'sur_demande' then 'À demander au guichet'
           else 'Non ouverte à votre fonction' end
  from applications a
  where a.actif
    and (source_acces(a.code) <> 'ferme'
         or (select v.etat from application_visibilite v
             where v.application = a.code
               and v.fonction = (select fonction from profils where id = auth.uid()))
            = 'sur_demande')
  order by a.ordre;
$$;

-- La matrice affiche désormais, en regard de chaque case, le nombre de
-- membres qui accèdent par un autre chemin : on cesse de croire qu'une
-- case « non ouverte » ferme réellement l'application.
drop function if exists matrice_acces();
create or replace function matrice_acces()
returns table (application text, app_nom text, ordre integer, droit_requis text,
               droit_nom text, fonction text, fonction_nom text, niveau integer,
               etat text, contournements integer)
language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.ordre, a.droit_requis,
         (select d.nom from droits d where d.code = a.droit_requis),
         f.code, f.nom, f.niveau,
         coalesce(v.etat, 'invisible'),
         (select count(*)::int from profils p
           where p.fonction = f.code and p.statut = 'actif'
             and source_acces(a.code, p.id) in ('nominatif','poste','admin'))
  from applications a
  cross join fonctions f
  left join application_visibilite v on v.application = a.code and v.fonction = f.code
  where a.actif and mon_niveau() >= 10
  order by a.ordre, f.niveau;
$$;

-- ---------------------------------------------------------------------
-- 2. L'ADMINISTRATEUR S'HABILITE LUI-MÊME
--    La garde tient pour tous, sauf pour lui : sans cela, aucun poste
--    vacant ne peut être amorcé.
-- ---------------------------------------------------------------------

create or replace function puis_je_agir_sur(p_profil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    -- L'administrateur agit sur lui-même et sur tous les autres.
    when (select fonction from profils where id = auth.uid()) = 'admin' then true
    when p_profil = auth.uid() then false
    else mon_poids() > poids_membre(p_profil)
  end;
$$;

create or replace function motif_refus_action(p_profil uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when (select fonction from profils where id = auth.uid()) = 'admin' then null
    when p_profil = auth.uid() then
      'Vous ne pouvez pas modifier vos propres habilitations. Seul un administrateur le peut.'
    when not puis_je_agir_sur(p_profil) then
      'Ce membre dispose d''habilitations égales ou supérieures aux vôtres. Seul un administrateur peut intervenir.'
    else null end;
$$;

-- ---------------------------------------------------------------------
-- 3. DISTINCTIONS
--    Reconnaître un engagement sans attendre un palier. Une lettre de
--    félicitations n'a pas besoin d'un barème.
-- ---------------------------------------------------------------------

create table if not exists types_distinction (
  code        text primary key,
  nom         text not null,
  description text,
  couleur     text not null default 'or',
  points      integer not null default 0,   -- bonification éventuelle
  ordre       integer not null default 100,
  actif       boolean not null default true
);

insert into types_distinction (code, nom, description, couleur, points, ordre) values
  ('felicitations', 'Lettre de félicitations',
   'Marque la reconnaissance de la fédération pour une action ou un engagement précis.',
   'bleu', 20, 10),
  ('citation', 'Citation à l''ordre de la fédération',
   'Distingue une contribution remarquable au rayonnement de la fédération.',
   'or', 50, 20),
  ('merite', 'Médaille du mérite fédéral',
   'Récompense un engagement durable et exemplaire au service de la citoyenneté.',
   'or', 100, 30),
  ('reconnaissance', 'Témoignage de reconnaissance',
   'Salue un concours ponctuel, y compris d''une personne extérieure au réseau.',
   'neutre', 10, 40)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description;

create sequence if not exists seq_distinction start 1;

create table if not exists distinctions (
  id         uuid primary key default gen_random_uuid(),
  numero     text unique not null default 'D-' || to_char(now(),'YYYY') || '-' ||
                          lpad(nextval('seq_distinction')::text, 4, '0'),
  profil_id  uuid not null references profils(id) on delete cascade,
  type       text not null references types_distinction(code),
  motif      text not null,
  texte      text,
  publique   boolean not null default true,
  decernee_par uuid references profils(id),
  decernee_le  timestamptz not null default now(),
  retiree_le   timestamptz,
  motif_retrait text
);
create index if not exists idx_distinctions_profil on distinctions(profil_id);

create or replace function decerner_distinction(
  p_profil uuid, p_type text, p_motif text, p_texte text default null,
  p_publique boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('chancellerie.promouvoir') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la chancellerie.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une distinction sans motif ne vaut rien. Dites ce qui est reconnu.');
  end if;

  insert into distinctions (profil_id, type, motif, texte, publique, decernee_par)
  values (p_profil, p_type, trim(p_motif), nullif(trim(p_texte),''),
          coalesce(p_publique,true), auth.uid())
  returning id into v_id;

  perform inscrire_acte(p_profil, 'distinction',
    'Distinction décernée : ' || (select nom from types_distinction where code = p_type),
    null, jsonb_build_object('distinction_id', v_id), false);

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function retirer_distinction(p_id uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Le retrait relève de l''administrateur.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le retrait doit être motivé.');
  end if;
  update distinctions set retiree_le = now(), motif_retrait = trim(p_motif) where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function mes_distinctions(p_profil uuid default null)
returns table (numero text, type text, type_nom text, couleur text,
               motif text, texte text, decernee_le timestamptz, par text)
language sql stable security definer set search_path = public as $$
  select d.numero, d.type, td.nom, td.couleur, d.motif, d.texte, d.decernee_le,
         trim(p.prenom || ' ' || p.nom)
  from distinctions d
  join types_distinction td on td.code = d.type
  left join profils p on p.id = d.decernee_par
  where d.profil_id = coalesce(p_profil, auth.uid())
    and d.retiree_le is null
  order by d.decernee_le desc;
$$;

-- La bonification entre dans le total des points.
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
    from b, brut),
  bonus as (
    select coalesce(sum(td.points),0)::int as n
    from distinctions d
    join types_distinction td on td.code = d.type
    join moi on moi.id = d.profil_id
    where d.retiree_le is null)
  select jsonb_build_object(
    'total', (select coalesce(sum(nb * points),0)::int from calc) + (select n from bonus),
    'detail', (select jsonb_object_agg(libelle, nb * points) from calc)
              || jsonb_build_object('Distinctions', (select n from bonus)),
    'volumes', (select jsonb_object_agg(libelle, nb) from calc),
    'distinctions', (select count(*) from distinctions d
                     join moi on moi.id = d.profil_id
                     where d.retiree_le is null),
    'echelon', (select echelon from brut),
    'echelon_nom', (select nom from echelons where niveau = (select echelon from brut)),
    'palier_actuel', (select points from echelons where niveau = (select echelon from brut)),
    'prochain', (select jsonb_build_object('niveau', e.niveau, 'nom', e.nom,
                        'points', e.points, 'ouvre', e.ouvre)
                 from echelons e where e.niveau = (select echelon from brut) + 1),
    'atteint_le_palier',
      (select coalesce(sum(nb * points),0) from calc) + (select n from bonus)
      >= coalesce((select points from echelons
                   where niveau = (select echelon from brut) + 1), 999999));
$$;

-- ---------------------------------------------------------------------
-- 4. CONFORMITÉ ÉLECTORALE
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('election.conformite', 'Statuer sur la recevabilité des candidatures', 'Structures', true, 37),
  ('election.archives',   'Consulter toutes les archives électorales',    'Structures', false, 38)
on conflict (code) do nothing;

insert into postes (code, nom, description, couleur, systeme) values
  ('conformite_election', 'Responsable de la conformité des élections',
   'Statue sur la recevabilité des candidatures, clôt les scrutins et proclame les résultats.',
   'bleu', true)
on conflict (code) do update set description = excluded.description;

insert into poste_droits (poste, droit) values
  ('conformite_election','election.conformite'),
  ('conformite_election','election.archives'),
  ('conformite_election','scrutin.proclamer'),
  ('daj','election.conformite'), ('daj','election.archives'),
  ('daj','scrutin.proclamer')
on conflict do nothing;

-- La recevabilité relève de la conformité, et d'elle seule.
create or replace function examiner_candidature(p_id uuid, p_recevable boolean,
                                                p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c candidatures; v_ref text;
begin
  if not (a_droit('election.conformite') or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'La recevabilité relève de la direction des affaires juridiques ou du responsable de la conformité des élections.');
  end if;
  if not p_recevable and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une irrecevabilité doit être motivée.');
  end if;

  select * into c from candidatures where id = p_id;
  select reference into v_ref from assemblees where id = c.assemblee_id;

  update candidatures
     set statut = case when p_recevable then 'recevable' else 'irrecevable' end,
         motif = nullif(trim(p_motif),''), examinee_par = auth.uid()
   where id = p_id;

  perform inscrire_acte(c.profil_id, 'election',
    case when p_recevable then 'Candidature déclarée recevable — ' || v_ref
         else 'Candidature écartée — ' || v_ref || ' : ' || trim(p_motif) end,
    null, jsonb_build_object('candidature_id', p_id), false);

  return jsonb_build_object('ok', true);
end $$;

create or replace function changer_phase_assemblee(p_assemblee uuid, p_statut text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ref text;
begin
  -- Ouvrir les candidatures reste à l'organisateur ; clore le scrutin
  -- relève de la conformité.
  if p_statut in ('scrutin','depouillement') then
    if not (a_droit('election.conformite') or est_admin()) then
      return jsonb_build_object('ok', false,
        'message', 'L''ouverture et la clôture du scrutin relèvent de la conformité des élections.');
    end if;
  elsif not (a_droit('scrutin.organiser') or a_droit('election.conformite') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''organisez pas ce scrutin.');
  end if;

  if p_statut = 'scrutin' and not exists (
      select 1 from candidatures where assemblee_id = p_assemblee and statut = 'recevable') then
    return jsonb_build_object('ok', false,
      'message', 'Aucune candidature recevable : le scrutin serait sans objet.');
  end if;

  select reference into v_ref from assemblees where id = p_assemblee;
  update assemblees set statut = p_statut,
         ouverture_scrutin = case when p_statut = 'scrutin'
           then coalesce(ouverture_scrutin, now()) else ouverture_scrutin end
   where id = p_assemblee;

  perform inscrire_acte(null, 'election',
    'Scrutin ' || v_ref || ' — phase : ' || p_statut, null, null, false);
  return jsonb_build_object('ok', true);
end $$;

-- Ce que la conformité doit voir sans rien rater.
create or replace function conformite_a_traiter()
returns table (candidature_id uuid, assemblee_id uuid, reference text,
               assemblee text, territoire text, date_tenue timestamptz,
               cloture_candidatures date, poste_nom text, candidat text,
               matricule text, profession_foi text, depose_le timestamptz,
               jours_avant_cloture integer)
language sql stable security definer set search_path = public as $$
  select c.id, a.id, a.reference, a.titre, t.nom, a.date_tenue,
         a.cloture_candidatures, po.nom,
         trim(p.prenom || ' ' || p.nom), p.matricule, c.profession_foi, c.cree_le,
         case when a.cloture_candidatures is not null
              then (a.cloture_candidatures - current_date)::int end
  from candidatures c
  join assemblees a on a.id = c.assemblee_id
  join postes po on po.code = c.poste
  join profils p on p.id = c.profil_id
  left join territoires t on t.id = a.territoire_id
  where c.statut = 'deposee'
    and (a_droit('election.conformite') or est_admin())
  order by a.cloture_candidatures nulls last, c.cree_le;
$$;

-- Les scrutins qui attendent une décision de la conformité.
create or replace function scrutins_a_arreter()
returns table (assemblee_id uuid, reference text, titre text, territoire text,
               statut text, date_tenue timestamptz, cloture_scrutin timestamptz,
               candidatures_a_examiner integer, recevables integer,
               votants integer, inscrits integer, action text)
language sql stable security definer set search_path = public as $$
  select a.id, a.reference, a.titre, t.nom, a.statut, a.date_tenue, a.cloture_scrutin,
         (select count(*)::int from candidatures c
           where c.assemblee_id = a.id and c.statut = 'deposee'),
         (select count(*)::int from candidatures c
           where c.assemblee_id = a.id and c.statut = 'recevable'),
         (select count(*)::int from votes v where v.assemblee_id = a.id),
         (select count(*)::int from corps_electoral(a.id)),
         case
           when exists (select 1 from candidatures c where c.assemblee_id = a.id
                        and c.statut = 'deposee') then 'Candidatures à examiner'
           when a.statut = 'candidatures' then 'Scrutin à ouvrir'
           when a.statut = 'scrutin' and a.cloture_scrutin < now() then 'Scrutin à clore'
           when a.statut = 'depouillement' then 'Résultats à proclamer'
           else null end
  from assemblees a
  left join territoires t on t.id = a.territoire_id
  where a.statut in ('candidatures','scrutin','depouillement')
    and (a_droit('election.conformite') or est_admin())
  order by a.date_tenue;
$$;

-- Les archives : ouvertes aux électeurs du scrutin, à leur territoire,
-- et sans limite à la conformité.
create or replace function archives_electorales(p_territoire uuid default null)
returns table (assemblee_id uuid, reference text, titre text, type text,
               territoire text, date_tenue timestamptz, proclame_le timestamptz,
               inscrits integer, votants integer, participation integer,
               proces_verbal text, pv_fichier text, elus jsonb, jai_participe boolean)
language sql stable security definer set search_path = public as $$
  select a.id, a.reference, a.titre, a.type, t.nom, a.date_tenue, a.proclame_le,
         (select count(*)::int from corps_electoral(a.id)),
         (select count(*)::int from votes v where v.assemblee_id = a.id),
         case when (select count(*) from corps_electoral(a.id)) = 0 then 0
              else round((select count(*) from votes v where v.assemblee_id = a.id)::numeric
                   / (select count(*) from corps_electoral(a.id)) * 100)::int end,
         a.proces_verbal, a.pv_fichier,
         coalesce((select jsonb_agg(jsonb_build_object('poste', po.nom,
                   'elu', trim(pr.prenom || ' ' || pr.nom),
                   'voix', m.voix, 'fin', m.fin))
                   from mandats m join postes po on po.code = m.poste
                   join profils pr on pr.id = m.profil_id
                   where m.assemblee_id = a.id), '[]'::jsonb),
         exists (select 1 from votes v where v.assemblee_id = a.id and v.electeur_id = auth.uid())
  from assemblees a
  left join territoires t on t.id = a.territoire_id
  where a.statut = 'proclamee'
    and (
      a_droit('election.archives') or est_admin()
      -- Un électeur du scrutin y a toujours accès.
      or exists (select 1 from votes v where v.assemblee_id = a.id and v.electeur_id = auth.uid())
      -- Les membres du territoire aussi : c'est leur histoire commune.
      or a.territoire_id in (
           with recursive remonte as (
             select tt.id, tt.parent_id from territoires tt
             where tt.id = (select territoire_id from profils where id = auth.uid())
             union all
             select tt.id, tt.parent_id from territoires tt
             join remonte r on tt.id = r.parent_id)
           select id from remonte)
      or (select territoire_id from profils where id = auth.uid())
         in (select s.id from territoires_sous(a.territoire_id) s))
    and (p_territoire is null or a.territoire_id = p_territoire)
  order by a.date_tenue desc;
$$;

-- ---------------------------------------------------------------------
-- 5. ASSISTANCE : SIGNALER UN PROBLÈME, PROPOSER UNE AMÉLIORATION
-- ---------------------------------------------------------------------

create sequence if not exists seq_ticket start 1;

create table if not exists tickets (
  id          uuid primary key default gen_random_uuid(),
  reference   text unique not null default 'T-' ||
                           lpad(nextval('seq_ticket')::text, 5, '0'),
  auteur_id   uuid not null references profils(id) on delete cascade,
  nature      text not null default 'probleme'
                check (nature in ('probleme','amelioration','question','donnee')),
  titre       text not null,
  description text not null,
  page        text,
  importance  text not null default 'normale'
                check (importance in ('basse','normale','haute','bloquante')),
  statut      text not null default 'ouvert'
                check (statut in ('ouvert','pris_en_compte','en_cours','resolu','refuse','differe')),
  assigne_a   uuid references profils(id) on delete set null,
  echeance    date,
  reponse     text,
  traite_par  uuid references profils(id),
  traite_le   timestamptz,
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
create index if not exists idx_tickets_statut on tickets(statut, importance, cree_le);

create table if not exists ticket_messages (
  id        uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references tickets(id) on delete cascade,
  auteur_id uuid not null references profils(id) on delete cascade,
  contenu   text not null,
  cree_le   timestamptz not null default now()
);

create or replace function ouvrir_ticket(p_nature text, p_titre text,
                                         p_description text, p_page text default null,
                                         p_importance text default 'normale')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if (select statut from profils where id = auth.uid()) not in ('actif','en_attente','suspendu') then
    return jsonb_build_object('ok', false, 'message', 'Compte inactif.');
  end if;
  if coalesce(trim(p_titre),'') = '' or coalesce(trim(p_description),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un titre et une description sont nécessaires.');
  end if;

  insert into tickets (auteur_id, nature, titre, description, page, importance)
  values (auth.uid(), p_nature, trim(p_titre), trim(p_description),
          nullif(trim(p_page),''),
          -- Nul ne déclare son propre signalement bloquant : la direction en juge.
          case when p_importance = 'bloquante' then 'haute' else coalesce(p_importance,'normale') end)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function traiter_ticket(
  p_id uuid, p_statut text, p_assigne uuid default null,
  p_echeance date default null, p_importance text default null,
  p_reponse text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('acces.piloter')) then
    return jsonb_build_object('ok', false, 'message', 'Réservé au pilotage.');
  end if;
  if p_statut in ('refuse','differe') and coalesce(trim(p_reponse),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Un refus ou un report doit être expliqué à celui qui a signalé.');
  end if;

  update tickets
     set statut = coalesce(p_statut, statut),
         assigne_a = coalesce(p_assigne, assigne_a),
         echeance = coalesce(p_echeance, echeance),
         importance = coalesce(p_importance, importance),
         reponse = coalesce(nullif(trim(p_reponse),''), reponse),
         traite_par = auth.uid(),
         traite_le = case when p_statut in ('resolu','refuse') then now() else traite_le end,
         maj_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function repondre_ticket(p_id uuid, p_contenu text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(p_contenu),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Message vide.');
  end if;
  if not exists (select 1 from tickets t where t.id = p_id
                 and (t.auteur_id = auth.uid() or t.assigne_a = auth.uid()
                      or est_admin() or a_droit('acces.piloter'))) then
    return jsonb_build_object('ok', false, 'message', 'Ce signalement ne vous concerne pas.');
  end if;
  insert into ticket_messages (ticket_id, auteur_id, contenu)
  values (p_id, auth.uid(), trim(p_contenu));
  update tickets set maj_le = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function liste_tickets(p_filtre text default 'ouverts')
returns table (id uuid, reference text, nature text, titre text, description text,
               page text, importance text, statut text, echeance date,
               auteur text, auteur_matricule text, assigne text, assigne_id uuid,
               reponse text, cree_le timestamptz, maj_le timestamptz,
               messages integer, retard boolean)
language sql stable security definer set search_path = public as $$
  select t.id, t.reference, t.nature, t.titre, t.description, t.page,
         t.importance, t.statut, t.echeance,
         trim(a.prenom || ' ' || a.nom), a.matricule,
         trim(g.prenom || ' ' || g.nom), t.assigne_a,
         t.reponse, t.cree_le, t.maj_le,
         (select count(*)::int from ticket_messages m where m.ticket_id = t.id),
         t.echeance is not null and t.echeance < current_date
           and t.statut not in ('resolu','refuse')
  from tickets t
  join profils a on a.id = t.auteur_id
  left join profils g on g.id = t.assigne_a
  where (est_admin() or a_droit('acces.piloter')
         or t.auteur_id = auth.uid() or t.assigne_a = auth.uid())
    and case p_filtre
      when 'ouverts' then t.statut not in ('resolu','refuse')
      when 'miens'   then t.auteur_id = auth.uid()
      when 'assignes' then t.assigne_a = auth.uid() and t.statut not in ('resolu','refuse')
      else true end
  order by
    case t.importance when 'bloquante' then 1 when 'haute' then 2
                      when 'normale' then 3 else 4 end,
    t.cree_le;
$$;

-- ---------------------------------------------------------------------
-- 6. FORMALISME DES DONNÉES
-- ---------------------------------------------------------------------

create or replace function normaliser_telephone(t text)
returns text language sql immutable as $$
  with n as (select regexp_replace(coalesce(t,''), '[^0-9+]', '', 'g') as v)
  select case
    when n.v = '' then null
    when n.v ~ '^0[1-9][0-9]{8}$' then
      substr(n.v,1,2) || ' ' || substr(n.v,3,2) || ' ' || substr(n.v,5,2) || ' ' ||
      substr(n.v,7,2) || ' ' || substr(n.v,9,2)
    when n.v ~ '^\+33[1-9][0-9]{8}$' then
      '0' || substr(n.v,4,1) || ' ' || substr(n.v,5,2) || ' ' || substr(n.v,7,2) || ' ' ||
      substr(n.v,9,2) || ' ' || substr(n.v,11,2)
    when n.v ~ '^0033[1-9][0-9]{8}$' then
      '0' || substr(n.v,5,1) || ' ' || substr(n.v,6,2) || ' ' || substr(n.v,8,2) || ' ' ||
      substr(n.v,10,2) || ' ' || substr(n.v,12,2)
    when n.v ~ '^\+[0-9]{8,15}$' then n.v      -- étranger : on laisse tel quel
    else null end
  from n;
$$;

create or replace function telephone_valide(t text)
returns boolean language sql immutable as $$
  select normaliser_telephone(t) is not null;
$$;

create or replace function code_postal_valide(t text)
returns boolean language sql immutable as $$
  select coalesce(regexp_replace(t, '[^0-9]', '', 'g'), '') ~ '^[0-9]{5}$';
$$;

-- Le numéro se met en forme à l'enregistrement : on ne renvoie pas
-- quelqu'un à son clavier pour une espace.
create or replace function normaliser_profil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.telephone is not null then
    new.telephone := coalesce(normaliser_telephone(new.telephone), new.telephone);
  end if;
  return new;
end $$;

drop trigger if exists trg_normaliser_profil on profils;
create trigger trg_normaliser_profil
  before insert or update of telephone on profils
  for each row execute function normaliser_profil();

update profils set telephone = normaliser_telephone(telephone)
 where telephone is not null and normaliser_telephone(telephone) is not null;

-- La complétude vérifie désormais le formalisme, pas seulement la
-- présence.
create or replace function completude_dossier(p_profil uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (select coalesce(p_profil, auth.uid()) as id),
  p as (select pr.* from profils pr, c where pr.id = c.id),
  a as (select da.* from dossier_adhesion da, c where da.profil_id = c.id),
  champs as (
    select * from (values
      ('prenom', 'Prénom', 'identite',
       coalesce(trim((select prenom from p)),'') <> ''),
      ('nom', 'Nom', 'identite',
       coalesce(trim((select nom from p)),'') <> ''),
      ('telephone', 'Téléphone', 'identite',
       telephone_valide((select telephone from p))),
      ('territoire', 'Département de rattachement', 'identite',
       (select territoire_id from p) is not null),
      ('date_naissance', 'Date de naissance', 'coordonnees',
       (select date_naissance from a) is not null),
      ('code_postal', 'Code postal', 'coordonnees',
       code_postal_valide((select code_postal from a))),
      ('ville', 'Ville', 'coordonnees',
       coalesce(trim((select ville from a)),'') <> ''),
      ('situation', 'Situation', 'engagement',
       coalesce(trim((select situation from a)),'') <> ''),
      ('motivation', 'Ce qui vous amène', 'engagement',
       coalesce(trim((select motivation from a)),'') <> ''),
      ('accepte_statuts', 'Acceptation des statuts', 'consentement',
       coalesce((select accepte_statuts from a), false)),
      ('accepte_rgpd', 'Politique de confidentialité', 'consentement',
       coalesce((select accepte_rgpd from a), false))
    ) as v(cle, libelle, section, ok))
  select jsonb_build_object(
    'complet', not exists (select 1 from champs where not ok),
    'manques', coalesce((select jsonb_agg(libelle order by section, libelle)
                         from champs where not ok), '[]'::jsonb),
    'manques_detail', coalesce((select jsonb_agg(jsonb_build_object(
        'cle', cle, 'libelle', libelle, 'section', section)
        order by section, libelle) from champs where not ok), '[]'::jsonb),
    'nb_manques', (select count(*) from champs where not ok),
    'total', (select count(*) from champs),
    'pourcent', round((select count(*) filter (where ok) from champs)::numeric
                      / (select count(*) from champs) * 100)::int,
    'sections', (select jsonb_object_agg(section, jsonb_build_object(
        'total', n, 'faits', f, 'complet', n = f))
      from (select section, count(*) as n, count(*) filter (where ok) as f
            from champs group by section) s));
$$;

-- ---------------------------------------------------------------------
-- 7. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table types_distinction enable row level security;
alter table distinctions      enable row level security;
alter table tickets           enable row level security;
alter table ticket_messages   enable row level security;

drop policy if exists lire_types_distinction on types_distinction;
create policy lire_types_distinction on types_distinction for select using (mon_niveau() >= 10);
drop policy if exists gerer_types_distinction on types_distinction;
create policy gerer_types_distinction on types_distinction for all
  using (a_droit('chancellerie.bareme')) with check (a_droit('chancellerie.bareme'));

drop policy if exists lire_distinctions on distinctions;
create policy lire_distinctions on distinctions for select using (
  profil_id = auth.uid() or (publique and retiree_le is null and mon_niveau() >= 10)
  or est_admin() or a_droit('chancellerie.suivre')
);

drop policy if exists lire_tickets on tickets;
create policy lire_tickets on tickets for select using (
  auteur_id = auth.uid() or assigne_a = auth.uid()
  or est_admin() or a_droit('acces.piloter')
);
drop policy if exists lire_ticket_messages on ticket_messages;
create policy lire_ticket_messages on ticket_messages for select using (
  exists (select 1 from tickets t where t.id = ticket_id
          and (t.auteur_id = auth.uid() or t.assigne_a = auth.uid()
               or est_admin() or a_droit('acces.piloter')))
);

grant select on types_distinction, distinctions, tickets, ticket_messages to authenticated;
grant update on types_distinction to authenticated;

grant execute on function source_acces(text, uuid), a_acces(text), mes_applications(),
                          matrice_acces(), puis_je_agir_sur(uuid), motif_refus_action(uuid),
                          decerner_distinction(uuid, text, text, text, boolean),
                          retirer_distinction(uuid, text), mes_distinctions(uuid),
                          points_membre(uuid),
                          examiner_candidature(uuid, boolean, text),
                          changer_phase_assemblee(uuid, text),
                          conformite_a_traiter(), scrutins_a_arreter(),
                          archives_electorales(uuid),
                          ouvrir_ticket(text, text, text, text, text),
                          traiter_ticket(uuid, text, uuid, date, text, text),
                          repondre_ticket(uuid, text), liste_tickets(text),
                          normaliser_telephone(text), telephone_valide(text),
                          code_postal_valide(text), completude_dossier(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 19
--
--  Pour nommer un responsable de la conformité des élections :
--    select nommer((select id from profils where email='…'),
--                  'conformite_election', null, null, 'Désigné par le bureau');
--
--  Vérifications :
--    select code, etat, source, explication from mes_applications();
--    select normaliser_telephone('+33 6 12 34 56 78');   -- 06 12 34 56 78
--    select completude_dossier();
--
--  Sur l'état des applications : il se calcule désormais à partir de la
--  source effective de l'accès — administration, octroi nominatif,
--  poste occupé, ou fonction. L'étiquette et la réalité ne peuvent plus
--  diverger, puisqu'elles lisent la même fonction.
-- =====================================================================
