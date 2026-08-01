-- =====================================================================
--  FFCE — Migration 02 — FORMATIONS
--
--  Parcours → modules → leçons (lecture, vidéo, document, quiz).
--  Déblocage dans l'ordre, progression calculée jamais stockée,
--  certifications délivrées automatiquement à l'achèvement.
--
--  Prérequis : 01_socle.sql.
--  À coller dans Supabase → SQL Editor → New query → Run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PARCOURS DE FORMATION
-- ---------------------------------------------------------------------

create table if not exists formations (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  titre       text not null,
  resume      text,
  description text,
  niveau_min  integer not null default 10,   -- fonction minimale pour y accéder
  duree_min   integer,                       -- durée indicative, en minutes
  seuil_quiz  integer not null default 80,   -- % exigé pour valider un quiz
  publiee     boolean not null default false,
  ordre       integer not null default 100,
  cree_par    uuid references profils(id),
  cree_le     timestamptz not null default now()
);

create table if not exists modules (
  id           uuid primary key default gen_random_uuid(),
  formation_id uuid not null references formations(id) on delete cascade,
  titre        text not null,
  resume       text,
  ordre        integer not null default 100
);
create index if not exists idx_modules_formation on modules(formation_id);

create table if not exists lecons (
  id        uuid primary key default gen_random_uuid(),
  module_id uuid not null references modules(id) on delete cascade,
  titre     text not null,
  type      text not null default 'lecture'
              check (type in ('lecture','video','document','quiz')),
  contenu   text,        -- texte de la leçon
  url       text,        -- lien vidéo ou document
  duree_min integer,
  ordre     integer not null default 100
);
create index if not exists idx_lecons_module on lecons(module_id);

-- ---------------------------------------------------------------------
-- 2. QUIZ
--    La bonne réponse ne sort jamais de PostgreSQL. Le navigateur reçoit
--    les questions sans les corrections, et la correction se fait ici.
-- ---------------------------------------------------------------------

create table if not exists questions (
  id       uuid primary key default gen_random_uuid(),
  lecon_id uuid not null references lecons(id) on delete cascade,
  enonce   text not null,
  aide     text,
  ordre    integer not null default 100
);
create index if not exists idx_questions_lecon on questions(lecon_id);

create table if not exists reponses (
  id          uuid primary key default gen_random_uuid(),
  question_id uuid not null references questions(id) on delete cascade,
  texte       text not null,
  correcte    boolean not null default false,
  ordre       integer not null default 100
);
create index if not exists idx_reponses_question on reponses(question_id);

-- ---------------------------------------------------------------------
-- 3. PROGRESSION
--    Une ligne par leçon achevée. Le pourcentage n'est jamais stocké :
--    il se recalcule à la lecture, donc il est toujours juste.
-- ---------------------------------------------------------------------

create table if not exists progression (
  id         uuid primary key default gen_random_uuid(),
  profil_id  uuid not null references profils(id) on delete cascade,
  lecon_id   uuid not null references lecons(id) on delete cascade,
  score      integer,                 -- % pour un quiz, null sinon
  tentatives integer not null default 1,
  termine_le timestamptz not null default now(),
  unique (profil_id, lecon_id)
);
create index if not exists idx_progression_profil on progression(profil_id);

-- ---------------------------------------------------------------------
-- 4. CERTIFICATIONS
--    Le label inscrit au compte. C'est lui qui ouvrira l'accès à
--    certains projets et groupes de travail.
-- ---------------------------------------------------------------------

create table if not exists certifications (
  code          text primary key,
  nom           text not null,
  description   text,
  formation_id  uuid references formations(id) on delete set null,
  validite_mois integer,               -- null = sans expiration
  actif         boolean not null default true
);

create sequence if not exists seq_certificat start 1;

create table if not exists certifications_obtenues (
  id          uuid primary key default gen_random_uuid(),
  profil_id   uuid not null references profils(id) on delete cascade,
  code        text not null references certifications(code) on delete cascade,
  numero      text unique not null default 'C-' || to_char(now(),'YYYY') || '-' ||
                            lpad(nextval('seq_certificat')::text, 5, '0'),
  obtenue_le  timestamptz not null default now(),
  expire_le   timestamptz,
  delivree_par uuid references profils(id),   -- null = délivrance automatique
  unique (profil_id, code)
);
create index if not exists idx_certifs_profil on certifications_obtenues(profil_id);

-- ---------------------------------------------------------------------
-- 5. LE PARCOURS À PLAT
--    Chaque leçon reçoit un rang unique dans sa formation. C'est ce rang
--    qui décide du déblocage : on n'ouvre la suivante que si la
--    précédente est achevée.
-- ---------------------------------------------------------------------

drop view if exists v_parcours;
create view v_parcours with (security_invoker = true) as
select l.id            as lecon_id,
       l.titre         as lecon_titre,
       l.type, l.duree_min, l.ordre as lecon_ordre,
       m.id            as module_id,
       m.titre         as module_titre,
       m.ordre         as module_ordre,
       f.id            as formation_id,
       f.code          as formation_code,
       f.titre         as formation_titre,
       f.seuil_quiz,
       row_number() over (partition by f.id order by m.ordre, l.ordre, l.titre) as rang
from lecons l
join modules m    on m.id = l.module_id
join formations f on f.id = m.formation_id;

-- Une leçon est-elle ouverte pour moi ?
create or replace function lecon_ouverte(p_lecon uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_form uuid; v_rang bigint; v_precedente uuid;
begin
  select formation_id, rang into v_form, v_rang from v_parcours where lecon_id = p_lecon;
  if v_form is null then return false; end if;
  if v_rang = 1 then return true; end if;

  select lecon_id into v_precedente
    from v_parcours where formation_id = v_form and rang = v_rang - 1;

  return exists (select 1 from progression
                 where profil_id = auth.uid() and lecon_id = v_precedente);
end $$;

-- Où en suis-je dans une formation ?
create or replace function avancement(p_formation uuid, p_profil uuid default null)
returns table (total integer, faites integer, pourcent integer)
language sql stable security definer set search_path = public as $$
  select count(*)::int,
         count(pr.id)::int,
         case when count(*) = 0 then 0
              else round(count(pr.id)::numeric / count(*) * 100)::int end
  from v_parcours v
  left join progression pr
         on pr.lecon_id = v.lecon_id
        and pr.profil_id = coalesce(p_profil, auth.uid())
  where v.formation_id = p_formation;
$$;

-- ---------------------------------------------------------------------
-- 6. ACHEVER UNE LEÇON
-- ---------------------------------------------------------------------

create or replace function terminer_lecon(p_lecon uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if not lecon_ouverte(p_lecon) then
    return jsonb_build_object('ok', false, 'message', 'Terminez d''abord la leçon précédente.');
  end if;

  select type into v_type from lecons where id = p_lecon;
  if v_type = 'quiz' then
    return jsonb_build_object('ok', false, 'message', 'Cette leçon se valide par le quiz.');
  end if;

  insert into progression (profil_id, lecon_id)
  values (auth.uid(), p_lecon)
  on conflict (profil_id, lecon_id) do nothing;

  perform delivrer_certifications();
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. CORRIGER UN QUIZ
--    p_choix : tableau des identifiants de réponses cochées.
--    Une question compte juste si toutes ses bonnes réponses sont
--    cochées et aucune mauvaise ne l'est.
-- ---------------------------------------------------------------------

create or replace function valider_quiz(p_lecon uuid, p_choix uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_justes int; v_score int; v_seuil int; v_reussi boolean;
begin
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if not lecon_ouverte(p_lecon) then
    return jsonb_build_object('ok', false, 'message', 'Terminez d''abord la leçon précédente.');
  end if;

  select seuil_quiz into v_seuil from v_parcours where lecon_id = p_lecon limit 1;
  select count(*) into v_total from questions where lecon_id = p_lecon;
  if v_total = 0 then
    return jsonb_build_object('ok', false, 'message', 'Ce quiz ne contient aucune question.');
  end if;

  select count(*) into v_justes from questions q
  where q.lecon_id = p_lecon
    and not exists (
      select 1 from reponses r
      where r.question_id = q.id
        and r.correcte <> (r.id = any(coalesce(p_choix, '{}'::uuid[])))
    );

  v_score  := round(v_justes::numeric / v_total * 100)::int;
  v_reussi := v_score >= coalesce(v_seuil, 80);

  if v_reussi then
    insert into progression (profil_id, lecon_id, score)
    values (auth.uid(), p_lecon, v_score)
    on conflict (profil_id, lecon_id)
      do update set score = greatest(progression.score, excluded.score),
                    tentatives = progression.tentatives + 1,
                    termine_le = now();
    perform delivrer_certifications();
  end if;

  return jsonb_build_object(
    'ok', true, 'score', v_score, 'justes', v_justes,
    'total', v_total, 'seuil', coalesce(v_seuil,80), 'reussi', v_reussi);
end $$;

-- ---------------------------------------------------------------------
-- 8. DÉLIVRANCE AUTOMATIQUE DES CERTIFICATIONS
--    Appelée après chaque leçon achevée. Ne délivre jamais deux fois.
-- ---------------------------------------------------------------------

create or replace function delivrer_certifications()
returns void language plpgsql security definer set search_path = public as $$
declare c record; v_reste int;
begin
  for c in select * from certifications where actif and formation_id is not null loop
    select count(*) into v_reste
      from v_parcours v
      left join progression pr on pr.lecon_id = v.lecon_id and pr.profil_id = auth.uid()
     where v.formation_id = c.formation_id and pr.id is null;

    if v_reste = 0 and exists (select 1 from v_parcours where formation_id = c.formation_id) then
      insert into certifications_obtenues (profil_id, code, expire_le)
      values (auth.uid(), c.code,
              case when c.validite_mois is null then null
                   else now() + (c.validite_mois || ' months')::interval end)
      on conflict (profil_id, code) do nothing;
    end if;
  end loop;
end $$;

-- Ai-je telle certification, toujours valide ?
create or replace function a_certification(p_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from certifications_obtenues
                 where profil_id = auth.uid() and code = p_code
                   and (expire_le is null or expire_le > now()));
$$;

-- =====================================================================
--  9. SÉCURITÉ
-- =====================================================================

alter table formations             enable row level security;
alter table modules                enable row level security;
alter table lecons                 enable row level security;
alter table questions              enable row level security;
alter table reponses               enable row level security;
alter table progression            enable row level security;
alter table certifications         enable row level security;
alter table certifications_obtenues enable row level security;

-- Catalogue : visible aux membres actifs dont la fonction atteint le niveau.
drop policy if exists lire_formations on formations;
create policy lire_formations on formations for select using (
  est_admin() or (publiee and mon_niveau() >= niveau_min)
);
drop policy if exists gerer_formations on formations;
create policy gerer_formations on formations for all
  using (est_admin()) with check (est_admin());

drop policy if exists lire_modules on modules;
create policy lire_modules on modules for select using (
  exists (select 1 from formations f where f.id = formation_id
          and (est_admin() or (f.publiee and mon_niveau() >= f.niveau_min)))
);
drop policy if exists gerer_modules on modules;
create policy gerer_modules on modules for all
  using (est_admin()) with check (est_admin());

drop policy if exists lire_lecons on lecons;
create policy lire_lecons on lecons for select using (
  exists (select 1 from modules m join formations f on f.id = m.formation_id
          where m.id = module_id
            and (est_admin() or (f.publiee and mon_niveau() >= f.niveau_min)))
);
drop policy if exists gerer_lecons on lecons;
create policy gerer_lecons on lecons for all
  using (est_admin()) with check (est_admin());

drop policy if exists lire_questions on questions;
create policy lire_questions on questions for select using (
  exists (select 1 from lecons l join modules m on m.id = l.module_id
                 join formations f on f.id = m.formation_id
          where l.id = lecon_id
            and (est_admin() or (f.publiee and mon_niveau() >= f.niveau_min)))
);
drop policy if exists gerer_questions on questions;
create policy gerer_questions on questions for all
  using (est_admin()) with check (est_admin());

-- RÉPONSES : aucune politique de lecture pour les membres.
-- Le navigateur n'obtient jamais la colonne « correcte ». Il passe par la
-- vue v_choix, puis la correction se fait dans valider_quiz().
drop policy if exists gerer_reponses on reponses;
create policy gerer_reponses on reponses for all
  using (est_admin()) with check (est_admin());

drop view if exists v_choix;
create view v_choix with (security_invoker = false) as
  select id, question_id, texte, ordre from reponses order by ordre;

-- PROGRESSION : la sienne, celle de son périmètre pour l'encadrement.
drop policy if exists lire_progression on progression;
create policy lire_progression on progression for select using (
  auth.uid() = profil_id or est_admin()
  or exists (select 1 from profils p where p.id = profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);

-- CERTIFICATIONS
drop policy if exists lire_certifications on certifications;
create policy lire_certifications on certifications for select using (true);
drop policy if exists gerer_certifications on certifications;
create policy gerer_certifications on certifications for all
  using (est_admin()) with check (est_admin());

drop policy if exists lire_certifs_obtenues on certifications_obtenues;
create policy lire_certifs_obtenues on certifications_obtenues for select using (
  auth.uid() = profil_id or est_admin()
  or exists (select 1 from profils p where p.id = profil_id
             and est_encadrant() and dans_mon_perimetre(p.territoire_id))
);
drop policy if exists gerer_certifs_obtenues on certifications_obtenues;
create policy gerer_certifs_obtenues on certifications_obtenues for all
  using (est_admin()) with check (est_admin());

-- ---------------------------------------------------------------------
-- 10. DROITS DE BASE
--     Les politiques RLS autorisent, les GRANT permettent d'atteindre.
--     Il faut les deux.
-- ---------------------------------------------------------------------

grant select on formations, modules, lecons, questions,
                certifications, certifications_obtenues, progression
  to authenticated;
grant select on v_parcours, v_choix to authenticated;
grant all on formations, modules, lecons, questions, reponses,
             certifications, certifications_obtenues to authenticated;
grant execute on function lecon_ouverte(uuid), avancement(uuid, uuid),
                          terminer_lecon(uuid), valider_quiz(uuid, uuid[]),
                          a_certification(text)
  to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ---------------------------------------------------------------------
-- 11. UNE FORMATION POUR DÉMARRER
--     « Socle citoyen » : le parcours d'accueil de tout nouveau membre.
--     Vous pourrez la modifier depuis l'onglet Formations.
-- ---------------------------------------------------------------------

insert into formations (code, titre, resume, description, niveau_min, duree_min, publiee, ordre)
values ('socle', 'Socle citoyen',
        'Le parcours d''accueil de tout nouveau membre de la fédération.',
        'Ce que fait la FFCE, comment elle s''organise, et ce qu''on attend de vous sur le terrain.',
        10, 45, true, 10)
on conflict (code) do nothing;

do $$
declare f uuid; m1 uuid; m2 uuid; l uuid; q uuid;
begin
  select id into f from formations where code = 'socle';
  if exists (select 1 from modules where formation_id = f) then return; end if;

  insert into modules (formation_id, titre, resume, ordre)
  values (f, 'La fédération', 'Son objet, son histoire, ses terrains d''action.', 10)
  returning id into m1;

  insert into lecons (module_id, titre, type, contenu, duree_min, ordre) values
   (m1, 'Notre raison d''être', 'lecture',
    'La FFCE promeut l''apprentissage de la citoyenneté active, contribue à l''éducation civique et à la culture démocratique, et transmet les valeurs de la République auprès des jeunes générations.

Déclarée le 12 août 2020, elle intervient en milieu scolaire, périscolaire et extra-scolaire.

Quatre terrains structurent son action : l''éducation à la citoyenneté, la mémoire et la transmission, l''égalité des chances, et l''éducation aux médias.', 10, 10),
   (m1, 'Comment nous sommes organisés', 'lecture',
    'La fédération est structurée à quatre échelles.

Au national, la Direction générale et les pôles fixent le cap, valident les accès et animent le réseau.

En région, le délégué régional coordonne les référents départementaux.

Au département, le référent départemental anime les responsables locaux et suit les adhérents de son territoire.

En local, le responsable local conduit les actions au plus près du terrain, avec ses animateurs.

Chacun voit et accompagne son territoire et tout ce qui en dépend — jamais celui du voisin.', 10, 20);

  insert into modules (formation_id, titre, resume, ordre)
  values (f, 'S''engager sereinement', 'Le cadre, les règles, les repères.', 20)
  returning id into m2;

  insert into lecons (module_id, titre, type, contenu, duree_min, ordre) values
   (m2, 'Le cadre de l''intervention', 'lecture',
    'Intervenir auprès de mineurs engage la fédération autant que vous.

Trois règles ne souffrent aucune exception :

Jamais d''échange privé non supervisé entre un adulte et un mineur. La messagerie de la plateforme est supervisée, et cela est annoncé à tous.

Aucune donnée personnelle collectée sans usage justifiable.

Toute difficulté rencontrée se signale sans délai à votre responsable local ou à votre référent départemental.', 10, 10)
  returning id into l;

  insert into lecons (module_id, titre, type, duree_min, ordre)
  values (m2, 'Vérifions ensemble', 'quiz', 5, 20)
  returning id into l;

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Qui anime les responsables locaux d''un département ?', 10) returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'Le référent départemental', true, 10),
    (q, 'Le délégué régional', false, 20),
    (q, 'La Direction générale', false, 30);

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Un échange privé entre un adulte et un mineur peut-il avoir lieu hors supervision ?', 20) returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'Jamais', true, 10),
    (q, 'Oui, si les deux sont d''accord', false, 20),
    (q, 'Oui, en dehors des heures d''activité', false, 30);

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Quels sont les terrains d''action de la fédération ?', 30) returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'L''éducation à la citoyenneté', true, 10),
    (q, 'La mémoire et la transmission', true, 20),
    (q, 'L''égalité des chances', true, 30),
    (q, 'La gestion de patrimoine', false, 40);
end $$;

insert into certifications (code, nom, description, formation_id, validite_mois)
select 'socle_citoyen', 'Socle citoyen',
       'Atteste de la connaissance du cadre, de l''organisation et des règles d''intervention de la fédération.',
       id, 24
from formations where code = 'socle'
on conflict (code) do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 02
--
--  Vérification :
--    select titre, (avancement(id)).* from formations;
--
--  L'onglet Formations est désormais ouvert à tous les membres actifs.
-- =====================================================================
