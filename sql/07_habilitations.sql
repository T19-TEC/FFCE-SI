-- =====================================================================
--  FFCE — Migration 07 — HABILITATIONS, POSTES ET PILOTAGE DES ACCÈS
--
--  Jusqu'ici, un droit ne pouvait venir que de deux endroits : la
--  fonction hiérarchique, ou un accès applicatif accordé nominativement.
--
--  Or « référent RGPD », « direction des affaires juridiques »,
--  « ordonnateur », « membre du conseil de discipline » ne sont ni l'un
--  ni l'autre. Ce sont des POSTES : des mandats nommés, cumulables,
--  révocables, parfois limités à un territoire et à une durée, et
--  indépendants du grade. Un adhérent peut être référent RGPD ; un
--  délégué régional peut ne pas l'être.
--
--  Cette migration introduit donc trois notions :
--    — le DROIT, atomique, qui ouvre une action précise ;
--    — le POSTE, qui regroupe des droits sous un nom ;
--    — la NOMINATION, qui confie un poste à quelqu'un, avec un début,
--      une fin éventuelle, et un périmètre.
--
--  Elle ajoute aussi ce qui manquait au pilotage : révocation propre,
--  journal d'usage des applications, et alerte à la consultation d'un
--  dossier protégé.
--
--  Prérequis : 01 à 06.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DROITS
--    Un droit ouvre UNE action. Jamais un ensemble : c'est le rôle du
--    poste de les regrouper.
-- ---------------------------------------------------------------------

create table if not exists droits (
  code      text primary key,
  nom       text not null,
  categorie text not null,
  sensible  boolean not null default false,  -- trace toute utilisation
  ordre     integer not null default 100
);

insert into droits (code, nom, categorie, sensible, ordre) values
  ('membres.consulter',     'Consulter l''annuaire hors de son périmètre', 'Membres', false, 10),
  ('membres.valider',       'Valider une inscription',                     'Membres', false, 20),
  ('membres.nommer',        'Nommer, muter, faire progresser',             'Membres', true,  30),
  ('membres.suspendre',     'Suspendre ou réintégrer un compte',           'Membres', true,  40),
  ('donnees.protegees',     'Consulter un dossier protégé',                'Données', true,  50),
  ('rgpd.registre',         'Tenir le registre des traitements',           'Données', false, 60),
  ('rgpd.alertes',          'Recevoir les alertes de consultation',        'Données', false, 70),
  ('finance.instruire',     'Instruire une note de frais',                 'Finances', false, 80),
  ('finance.ordonnancer',   'Ordonnancer une dépense',                     'Finances', true,  90),
  ('finance.payer',         'Mettre en paiement',                          'Finances', true, 100),
  ('finance.bareme',        'Fixer le barème et les plafonds',             'Finances', false, 110),
  ('discipline.saisir',     'Ouvrir un dossier disciplinaire',             'Discipline', false, 120),
  ('discipline.instruire',  'Instruire un dossier disciplinaire',          'Discipline', true, 130),
  ('discipline.decider',    'Prononcer une mesure',                        'Discipline', true, 140),
  ('discipline.recours',    'Statuer sur un recours gracieux',             'Discipline', true, 150),
  ('messagerie.superviser', 'Superviser les échanges de son périmètre',    'Échanges', true, 160),
  ('formations.editer',     'Créer et modifier les formations',            'Contenus', false, 170),
  ('vitrine.editer',        'Modifier le site public',                     'Contenus', false, 180),
  ('habilitations.gerer',   'Créer des postes et nommer',                  'Pilotage', true, 190),
  ('acces.piloter',         'Ouvrir et révoquer les accès applicatifs',    'Pilotage', true, 200)
on conflict (code) do update
  set nom = excluded.nom, categorie = excluded.categorie,
      sensible = excluded.sensible, ordre = excluded.ordre;

-- ---------------------------------------------------------------------
-- 2. LES POSTES
--    Créés par l'administrateur, sans toucher au code.
-- ---------------------------------------------------------------------

create table if not exists postes (
  code        text primary key,
  nom         text not null,
  description text,
  couleur     text not null default 'neutre' check (couleur in ('neutre','or','bleu','vert','rouge')),
  systeme     boolean not null default false,  -- fourni d'origine, non supprimable
  actif       boolean not null default true,
  cree_par    uuid references profils(id),
  cree_le     timestamptz not null default now()
);

create table if not exists poste_droits (
  poste text not null references postes(code) on delete cascade,
  droit text not null references droits(code) on delete cascade,
  primary key (poste, droit)
);

create table if not exists nominations (
  id            uuid primary key default gen_random_uuid(),
  profil_id     uuid not null references profils(id) on delete cascade,
  poste         text not null references postes(code) on delete cascade,
  territoire_id uuid references territoires(id),   -- null = national
  debut         date not null default current_date,
  fin           date,                              -- null = sans terme
  motif         text,
  nomme_par     uuid references profils(id),
  revoque_le    timestamptz,
  revoque_par   uuid references profils(id),
  motif_revocation text,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_nom_profil on nominations(profil_id);
create index if not exists idx_nom_poste  on nominations(poste);

-- Postes fournis d'origine.
insert into postes (code, nom, description, couleur, systeme) values
  ('ordonnateur',   'Ordonnateur',
   'Décide d''engager la dépense. Ne paie pas : cette séparation protège autant l''ordonnateur que le trésorier.',
   'or', true),
  ('dg_finance',    'Direction financière',
   'Instruit les notes de frais et procède aux paiements. N''ordonnance pas.',
   'or', true),
  ('daj',           'Direction des affaires juridiques',
   'Instruit les dossiers disciplinaires et statue sur les recours gracieux.',
   'bleu', true),
  ('ref_rgpd',      'Référent à la protection des données',
   'Tient le registre des traitements et reçoit les alertes de consultation.',
   'bleu', true),
  ('ref_discrimination', 'Référent discriminations et harcèlement',
   'Saisi de tout signalement à caractère discriminatoire ou de harcèlement.',
   'rouge', true),
  ('conseil_discipline', 'Conseil de discipline',
   'Collège qui prononce les mesures. Ne les instruit pas.',
   'rouge', true),
  ('delegue_admin', 'Délégué de l''administrateur',
   'Exerce les prérogatives de pilotage confiées par l''administrateur.',
   'or', true)
on conflict (code) do update set nom = excluded.nom, description = excluded.description;

insert into poste_droits (poste, droit) values
  ('ordonnateur','finance.ordonnancer'),
  ('dg_finance','finance.instruire'), ('dg_finance','finance.payer'),
  ('dg_finance','finance.bareme'),
  ('daj','discipline.instruire'), ('daj','discipline.recours'),
  ('daj','discipline.saisir'), ('daj','donnees.protegees'),
  ('ref_rgpd','rgpd.registre'), ('ref_rgpd','rgpd.alertes'),
  ('ref_rgpd','donnees.protegees'),
  ('ref_discrimination','discipline.saisir'), ('ref_discrimination','discipline.instruire'),
  ('conseil_discipline','discipline.decider'),
  ('delegue_admin','habilitations.gerer'), ('delegue_admin','acces.piloter'),
  ('delegue_admin','membres.valider'), ('delegue_admin','membres.nommer')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3. LIRE UN DROIT
-- ---------------------------------------------------------------------

create or replace function nomination_active(n nominations)
returns boolean language sql immutable as $$
  select n.revoque_le is null
     and n.debut <= current_date
     and (n.fin is null or n.fin >= current_date);
$$;

create or replace function a_droit(p_droit text)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from nominations n
    join poste_droits pd on pd.poste = n.poste
    join postes p        on p.code = n.poste
    where n.profil_id = auth.uid()
      and pd.droit = p_droit
      and p.actif
      and nomination_active(n));
$$;

-- Le même droit, mais borné à un territoire lorsque la nomination l'est.
create or replace function a_droit_sur(p_droit text, p_territoire uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from nominations n
    join poste_droits pd on pd.poste = n.poste
    join postes p        on p.code = n.poste
    where n.profil_id = auth.uid()
      and pd.droit = p_droit
      and p.actif
      and nomination_active(n)
      and (n.territoire_id is null
           or p_territoire is null
           or exists (select 1 from territoires_sous(n.territoire_id) s
                      where s.id = p_territoire)));
$$;

-- Mes postes, pour l'affichage.
create or replace function mes_postes()
returns table (poste text, nom text, couleur text, territoire_nom text, fin date)
language sql stable security definer set search_path = public as $$
  select p.code, p.nom, p.couleur, t.nom, n.fin
  from nominations n
  join postes p on p.code = n.poste
  left join territoires t on t.id = n.territoire_id
  where n.profil_id = auth.uid() and p.actif and nomination_active(n)
  order by p.nom;
$$;

-- ---------------------------------------------------------------------
-- 4. NOMMER ET RÉVOQUER
-- ---------------------------------------------------------------------

create or replace function nommer(
  p_profil uuid, p_poste text, p_territoire uuid default null,
  p_fin date default null, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('habilitations.gerer') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pouvez pas nommer.');
  end if;
  if not exists (select 1 from profils where id = p_profil and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas actif.');
  end if;
  if exists (select 1 from nominations n where n.profil_id = p_profil
             and n.poste = p_poste and nomination_active(n)) then
    return jsonb_build_object('ok', false, 'message', 'Ce membre occupe déjà ce poste.');
  end if;

  insert into nominations (profil_id, poste, territoire_id, fin, motif, nomme_par)
  values (p_profil, p_poste, p_territoire, p_fin, nullif(trim(p_motif),''), auth.uid());

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'nomination', p_profil::text,
          jsonb_build_object('poste', p_poste, 'fin', p_fin));
  return jsonb_build_object('ok', true);
end $$;

create or replace function revoquer(p_nomination uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('habilitations.gerer') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pouvez pas révoquer.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;

  update nominations
     set revoque_le = now(), revoque_par = auth.uid(), motif_revocation = trim(p_motif)
   where id = p_nomination and revoque_le is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Cette nomination est déjà close.');
  end if;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'revocation', p_nomination::text, jsonb_build_object('motif', p_motif));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. PILOTAGE DES ACCÈS APPLICATIFS
--    Il manquait la révocation, et surtout le suivi d'usage : un accès
--    qui ne sert jamais est un accès à retirer.
-- ---------------------------------------------------------------------

alter table applications add column if not exists droit_requis text references droits(code);

update applications set droit_requis = 'finance.instruire' where code = 'tresorerie';

alter table acces_applications add column if not exists revoque_le timestamptz;
alter table acces_applications add column if not exists revoque_par uuid references profils(id);
alter table acces_applications add column if not exists motif_revocation text;
alter table acces_applications add column if not exists expire_le date;

create table if not exists journal_acces (
  id          bigserial primary key,
  profil_id   uuid not null references profils(id) on delete cascade,
  application text not null,
  cree_le     timestamptz not null default now()
);
create index if not exists idx_ja_profil on journal_acces(profil_id, application);

create or replace function tracer_acces(p_app text)
returns void language sql security definer set search_path = public as $$
  insert into journal_acces (profil_id, application) values (auth.uid(), p_app);
$$;

-- L'accès applicatif, revu : niveau, octroi nominatif, ou poste.
create or replace function a_acces(app text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from applications a
    where a.code = app and a.actif
      and (
        (not a.sur_demande and mon_niveau() >= a.niveau_min)
        or (a.droit_requis is not null and a_droit(a.droit_requis))
        or exists (select 1 from acces_applications x
                   where x.profil_id = auth.uid() and x.application = app
                     and x.statut = 'accorde' and x.revoque_le is null
                     and (x.expire_le is null or x.expire_le >= current_date))
      )
  );
$$;

create or replace function accorder_acces(
  p_profil uuid, p_app text, p_motif text default null, p_expire date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les accès.');
  end if;
  insert into acces_applications (profil_id, application, statut, motif, accorde_par, expire_le)
  values (p_profil, p_app, 'accorde', nullif(trim(p_motif),''), auth.uid(), p_expire)
  on conflict (profil_id, application) do update
    set statut = 'accorde', revoque_le = null, revoque_par = null,
        motif_revocation = null, motif = nullif(trim(p_motif),''),
        accorde_par = auth.uid(), expire_le = p_expire;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'acces_accorde', p_profil::text, jsonb_build_object('app', p_app));
  return jsonb_build_object('ok', true);
end $$;

create or replace function revoquer_acces(p_profil uuid, p_app text, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les accès.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;

  update acces_applications
     set statut = 'revoque', revoque_le = now(), revoque_par = auth.uid(),
         motif_revocation = trim(p_motif)
   where profil_id = p_profil and application = p_app;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Aucun accès à révoquer.');
  end if;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'acces_revoque', p_profil::text,
          jsonb_build_object('app', p_app, 'motif', p_motif));
  return jsonb_build_object('ok', true);
end $$;

-- Le tableau de pilotage : qui a quoi, depuis quand, et s'en sert-il ?
create or replace function pilotage_acces()
returns table (
  profil_id uuid, membre text, matricule text, fonction_nom text, territoire_nom text,
  application text, app_nom text, origine text, accorde_le timestamptz,
  expire_le date, derniere_utilisation timestamptz, nb_ouvertures integer, statut text
) language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, f.nom, t.nom,
         x.application, a.nom, 'Octroi nominatif', x.cree_le, x.expire_le,
         (select max(j.cree_le) from journal_acces j
           where j.profil_id = p.id and j.application = x.application),
         (select count(*)::int from journal_acces j
           where j.profil_id = p.id and j.application = x.application),
         case when x.revoque_le is not null then 'Révoqué'
              when x.expire_le is not null and x.expire_le < current_date then 'Expiré'
              else 'Actif' end
  from acces_applications x
  join profils p     on p.id = x.profil_id
  join fonctions f   on f.code = p.fonction
  join applications a on a.code = x.application
  left join territoires t on t.id = p.territoire_id
  where a_droit('acces.piloter')
  order by p.nom, a.ordre;
$$;

-- ---------------------------------------------------------------------
-- 6. DOSSIERS PROTÉGÉS ET ALERTE À LA CONSULTATION
--
--    Certains membres justifient une protection renforcée : mineur,
--    victime d'un signalement, personne sous mesure disciplinaire,
--    ou simple demande de l'intéressé. Toute consultation de leur
--    dossier laisse une trace et déclenche une alerte.
-- ---------------------------------------------------------------------

alter table profils add column if not exists protege boolean not null default false;
alter table profils add column if not exists motif_protection text;

create table if not exists consultations (
  id          bigserial primary key,
  observateur uuid not null references profils(id) on delete cascade,
  observe     uuid not null references profils(id) on delete cascade,
  contexte    text,
  alerte      boolean not null default false,
  vue_par     uuid references profils(id),
  vue_le      timestamptz,
  cree_le     timestamptz not null default now()
);
create index if not exists idx_cons_alerte on consultations(alerte, vue_le);

-- Consulter un dossier passe désormais par ici. La fonction rend les
-- données ET inscrit la consultation. On ne peut pas avoir l'une sans
-- l'autre : c'est ce qui rend la trace fiable.
create or replace function consulter_profil(p_profil uuid, p_contexte text default null)
returns table (
  id uuid, matricule text, prenom text, nom text, email text, telephone text,
  fonction_nom text, echelon integer, territoire_nom text, statut text,
  date_adhesion date, bio text, protege boolean
) language plpgsql stable security definer set search_path = public as $$
declare v_protege boolean;
begin
  if not (p_profil = auth.uid() or est_admin()
          or (est_encadrant() and dans_mon_perimetre(
                (select territoire_id from profils where id = p_profil)))
          or a_droit('membres.consulter')) then
    raise exception 'Ce dossier n''est pas dans votre périmètre.';
  end if;

  select p.protege into v_protege from profils p where p.id = p_profil;

  if v_protege and not a_droit('donnees.protegees') and not est_admin() then
    raise exception 'Ce dossier fait l''objet d''une protection renforcée.';
  end if;

  if p_profil <> auth.uid() then
    insert into consultations (observateur, observe, contexte, alerte)
    values (auth.uid(), p_profil, nullif(trim(p_contexte),''), coalesce(v_protege,false));
  end if;

  return query
    select p.id, p.matricule, p.prenom, p.nom, p.email, p.telephone,
           f.nom, p.echelon, t.nom, p.statut, p.date_adhesion, p.bio, p.protege
    from profils p
    join fonctions f on f.code = p.fonction
    left join territoires t on t.id = p.territoire_id
    where p.id = p_profil;
end $$;

create or replace function alertes_consultation()
returns table (
  id bigint, observateur_nom text, observateur_fonction text,
  observe_nom text, observe_matricule text, contexte text, cree_le timestamptz
) language sql stable security definer set search_path = public as $$
  select c.id, trim(a.prenom || ' ' || a.nom), fa.nom,
         trim(b.prenom || ' ' || b.nom), b.matricule, c.contexte, c.cree_le
  from consultations c
  join profils a    on a.id = c.observateur
  join fonctions fa on fa.code = a.fonction
  join profils b    on b.id = c.observe
  where c.alerte and c.vue_le is null
    and (est_admin() or a_droit('rgpd.alertes'))
  order by c.cree_le desc;
$$;

create or replace function marquer_alerte_vue(p_id bigint)
returns void language sql security definer set search_path = public as $$
  update consultations set vue_par = auth.uid(), vue_le = now()
   where id = p_id and (est_admin() or a_droit('rgpd.alertes'));
$$;

-- =====================================================================
--  7. SÉCURITÉ
-- =====================================================================

alter table droits        enable row level security;
alter table postes        enable row level security;
alter table poste_droits  enable row level security;
alter table nominations   enable row level security;
alter table journal_acces enable row level security;
alter table consultations enable row level security;

drop policy if exists lire_droits on droits;
create policy lire_droits on droits for select using (mon_niveau() >= 10);

drop policy if exists lire_postes on postes;
create policy lire_postes on postes for select using (mon_niveau() >= 10);
drop policy if exists gerer_postes on postes;
create policy gerer_postes on postes for all
  using (a_droit('habilitations.gerer')) with check (a_droit('habilitations.gerer'));

drop policy if exists lire_poste_droits on poste_droits;
create policy lire_poste_droits on poste_droits for select using (mon_niveau() >= 10);
drop policy if exists gerer_poste_droits on poste_droits;
create policy gerer_poste_droits on poste_droits for all
  using (a_droit('habilitations.gerer')) with check (a_droit('habilitations.gerer'));

-- Les nominations sont publiques au sein de la fédération : savoir qui
-- est référent RGPD ou membre du conseil de discipline fait partie du
-- fonctionnement normal d'une association.
drop policy if exists lire_nominations on nominations;
create policy lire_nominations on nominations for select using (mon_niveau() >= 10);
drop policy if exists gerer_nominations on nominations;
create policy gerer_nominations on nominations for all
  using (a_droit('habilitations.gerer')) with check (a_droit('habilitations.gerer'));

drop policy if exists lire_journal_acces on journal_acces;
create policy lire_journal_acces on journal_acces for select
  using (profil_id = auth.uid() or a_droit('acces.piloter'));

-- Chacun voit qui a consulté son propre dossier. C'est un droit RGPD,
-- pas une faveur.
drop policy if exists lire_consultations on consultations;
create policy lire_consultations on consultations for select
  using (observe = auth.uid() or est_admin() or a_droit('rgpd.alertes'));

grant select on droits, postes, poste_droits, nominations,
                journal_acces, consultations to authenticated;
grant insert, update, delete on postes, poste_droits, nominations to authenticated;

grant execute on function a_droit(text), a_droit_sur(text, uuid), mes_postes(),
                          nommer(uuid, text, uuid, date, text), revoquer(uuid, text),
                          tracer_acces(text), a_acces(text),
                          accorder_acces(uuid, text, text, date),
                          revoquer_acces(uuid, text, text), pilotage_acces(),
                          consulter_profil(uuid, text), alertes_consultation(),
                          marquer_alerte_vue(bigint), nomination_active(nominations)
  to authenticated;


-- ---------------------------------------------------------------------
-- 8. LA VUE D'ANNUAIRE EXPOSE LA PROTECTION
-- ---------------------------------------------------------------------

drop view if exists v_annuaire;
create view v_annuaire with (security_invoker = true) as
select p.id, p.matricule, p.prenom, p.nom, p.email, p.telephone,
       p.fonction, f.nom as fonction_nom, f.niveau, f.famille,
       p.echelon, e.nom as echelon_nom,
       p.territoire_id, t.nom as territoire_nom, t.echelle as territoire_echelle,
       p.statut, p.date_adhesion, p.photo_url, p.bio, p.visible_public,
       p.protege, p.motif_protection, p.webmail, p.cree_le
from profils p
join fonctions f  on f.code = p.fonction
join echelons e   on e.niveau = p.echelon
left join territoires t on t.id = p.territoire_id;

grant select on v_annuaire to anon, authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 07
--
--  Pour nommer votre première direction financière :
--
--    select nommer(
--      (select id from profils where email = 'tresorier@ffce-asso.fr'),
--      'dg_finance', null, null, 'Élu au bureau du 12 mars');
--
--  Tout se fait ensuite depuis l'onglet Habilitations, sans SQL.
--
--  Le principe : un droit ouvre une action, un poste regroupe des
--  droits, une nomination confie un poste. Ces trois notions restent
--  séparées — les mélanger est la façon la plus sûre de perdre le
--  contrôle de qui peut faire quoi.
-- =====================================================================
