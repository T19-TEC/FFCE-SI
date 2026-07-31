-- =====================================================================
--  FFCE — Fédération Française pour la Citoyenneté et l'Égalité des Chances
--  Migration 01 — SOCLE
--
--  Contenu : maillage territorial, fonctions et échelons, profils,
--            périmètre de visibilité, applications, guichet de demandes,
--            contenus de la vitrine, journal, sécurité RLS.
--
--  À coller dans Supabase → SQL Editor → New query → Run.
--  Attendu : « Success. No rows returned ».
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. MAILLAGE TERRITORIAL
--    Un arbre : national → région → département → antenne locale.
--    Tout le système de droits repose dessus.
-- ---------------------------------------------------------------------

create table if not exists territoires (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references territoires(id) on delete restrict,
  echelle     text not null check (echelle in ('national','region','departement','local')),
  code        text not null,
  nom         text not null,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now(),
  unique (echelle, code)
);

create index if not exists idx_territoires_parent on territoires(parent_id);

-- National
insert into territoires (echelle, code, nom)
values ('national','FR','France')
on conflict (echelle, code) do nothing;

-- Régions
insert into territoires (parent_id, echelle, code, nom)
select t.id, 'region', v.code, v.nom
from territoires t, (values
  ('R84','Auvergne-Rhône-Alpes'), ('R27','Bourgogne-Franche-Comté'),
  ('R53','Bretagne'),             ('R24','Centre-Val de Loire'),
  ('R94','Corse'),                ('R44','Grand Est'),
  ('R32','Hauts-de-France'),      ('R11','Île-de-France'),
  ('R28','Normandie'),            ('R75','Nouvelle-Aquitaine'),
  ('R76','Occitanie'),            ('R52','Pays de la Loire'),
  ('R93','Provence-Alpes-Côte d''Azur'),
  ('R01','Guadeloupe'), ('R02','Martinique'), ('R03','Guyane'),
  ('R04','La Réunion'), ('R06','Mayotte')
) as v(code,nom)
where t.echelle = 'national' and t.code = 'FR'
on conflict (echelle, code) do nothing;

-- Départements
insert into territoires (parent_id, echelle, code, nom)
select r.id, 'departement', v.code, v.nom
from (values
  ('R84','01','Ain'),('R84','03','Allier'),('R84','07','Ardèche'),('R84','15','Cantal'),
  ('R84','26','Drôme'),('R84','38','Isère'),('R84','42','Loire'),('R84','43','Haute-Loire'),
  ('R84','63','Puy-de-Dôme'),('R84','69','Rhône'),('R84','73','Savoie'),('R84','74','Haute-Savoie'),
  ('R27','21','Côte-d''Or'),('R27','25','Doubs'),('R27','39','Jura'),('R27','58','Nièvre'),
  ('R27','70','Haute-Saône'),('R27','71','Saône-et-Loire'),('R27','89','Yonne'),('R27','90','Territoire de Belfort'),
  ('R53','22','Côtes-d''Armor'),('R53','29','Finistère'),('R53','35','Ille-et-Vilaine'),('R53','56','Morbihan'),
  ('R24','18','Cher'),('R24','28','Eure-et-Loir'),('R24','36','Indre'),('R24','37','Indre-et-Loire'),
  ('R24','41','Loir-et-Cher'),('R24','45','Loiret'),
  ('R94','2A','Corse-du-Sud'),('R94','2B','Haute-Corse'),
  ('R44','08','Ardennes'),('R44','10','Aube'),('R44','51','Marne'),('R44','52','Haute-Marne'),
  ('R44','54','Meurthe-et-Moselle'),('R44','55','Meuse'),('R44','57','Moselle'),('R44','67','Bas-Rhin'),
  ('R44','68','Haut-Rhin'),('R44','88','Vosges'),
  ('R32','02','Aisne'),('R32','59','Nord'),('R32','60','Oise'),('R32','62','Pas-de-Calais'),('R32','80','Somme'),
  ('R11','75','Paris'),('R11','77','Seine-et-Marne'),('R11','78','Yvelines'),('R11','91','Essonne'),
  ('R11','92','Hauts-de-Seine'),('R11','93','Seine-Saint-Denis'),('R11','94','Val-de-Marne'),('R11','95','Val-d''Oise'),
  ('R28','14','Calvados'),('R28','27','Eure'),('R28','50','Manche'),('R28','61','Orne'),('R28','76','Seine-Maritime'),
  ('R75','16','Charente'),('R75','17','Charente-Maritime'),('R75','19','Corrèze'),('R75','23','Creuse'),
  ('R75','24','Dordogne'),('R75','33','Gironde'),('R75','40','Landes'),('R75','47','Lot-et-Garonne'),
  ('R75','64','Pyrénées-Atlantiques'),('R75','79','Deux-Sèvres'),('R75','86','Vienne'),('R75','87','Haute-Vienne'),
  ('R76','09','Ariège'),('R76','11','Aude'),('R76','12','Aveyron'),('R76','30','Gard'),('R76','31','Haute-Garonne'),
  ('R76','32','Gers'),('R76','34','Hérault'),('R76','46','Lot'),('R76','48','Lozère'),('R76','65','Hautes-Pyrénées'),
  ('R76','66','Pyrénées-Orientales'),('R76','81','Tarn'),('R76','82','Tarn-et-Garonne'),
  ('R52','44','Loire-Atlantique'),('R52','49','Maine-et-Loire'),('R52','53','Mayenne'),('R52','72','Sarthe'),('R52','85','Vendée'),
  ('R93','04','Alpes-de-Haute-Provence'),('R93','05','Hautes-Alpes'),('R93','06','Alpes-Maritimes'),
  ('R93','13','Bouches-du-Rhône'),('R93','83','Var'),('R93','84','Vaucluse'),
  ('R01','971','Guadeloupe'),('R02','972','Martinique'),('R03','973','Guyane'),
  ('R04','974','La Réunion'),('R06','976','Mayotte')
) as v(reg,code,nom)
join territoires r on r.echelle = 'region' and r.code = v.reg
on conflict (echelle, code) do nothing;


-- ---------------------------------------------------------------------
-- 2. FONCTIONS
--    Le « poste » occupé. Le niveau d'autorité est un entier : il sert
--    partout, et il suffit de le comparer pour ouvrir ou fermer un droit.
-- ---------------------------------------------------------------------

create table if not exists fonctions (
  code            text primary key,
  nom             text not null,
  famille         text not null check (famille in ('adhesion','encadrement','direction')),
  niveau          integer not null,          -- 10 → 100
  echelle_requise text                       -- échelle territoriale attendue
);

insert into fonctions (code, nom, famille, niveau, echelle_requise) values
  ('adherent',              'Adhérent',                 'adhesion',    10, null),
  ('benevole',              'Bénévole',                 'adhesion',    20, null),
  ('membre_actif',          'Membre actif',             'adhesion',    30, null),
  ('animateur_local',       'Animateur local',          'encadrement', 40, 'local'),
  ('responsable_local',     'Responsable local',        'encadrement', 50, 'local'),
  ('referent_departemental','Référent départemental',   'encadrement', 60, 'departement'),
  ('delegue_regional',      'Délégué régional',         'encadrement', 70, 'region'),
  ('directeur_pole',        'Directeur de pôle',        'direction',   80, 'national'),
  ('direction_generale',    'Direction générale',       'direction',   90, 'national'),
  ('admin',                 'Administrateur',           'direction',  100, 'national')
on conflict (code) do update
  set nom = excluded.nom, famille = excluded.famille,
      niveau = excluded.niveau, echelle_requise = excluded.echelle_requise;


-- ---------------------------------------------------------------------
-- 3. ÉCHELONS
--    La progression personnelle, indépendante du poste. Un référent
--    départemental peut être échelon 2 ; un bénévole peut être échelon 5.
--    L'échelon reconnaît l'expérience, la fonction donne le pouvoir.
-- ---------------------------------------------------------------------

create table if not exists echelons (
  niveau  integer primary key,
  nom     text not null,
  points  integer not null,
  ouvre   text
);

insert into echelons (niveau, nom, points, ouvre) values
  (1,'Engagé',                0,    null),
  (2,'Engagé confirmé',       60,   'Signaler un contenu'),
  (3,'Animateur',             180,  'Créer un groupe de travail'),
  (4,'Animateur confirmé',    400,  'Encadrer une formation'),
  (5,'Coordinateur',          750,  'Valider une certification'),
  (6,'Coordinateur principal',1300, 'Modérer les échanges'),
  (7,'Pilier fédéral',        2200, 'Modération complète')
on conflict (niveau) do update
  set nom = excluded.nom, points = excluded.points, ouvre = excluded.ouvre;


-- ---------------------------------------------------------------------
-- 4. PROFILS
-- ---------------------------------------------------------------------

create sequence if not exists seq_matricule start 1;

create table if not exists profils (
  id             uuid primary key references auth.users(id) on delete cascade,
  matricule      text unique not null default 'FFCE-' || to_char(now(),'YYYY') || '-' ||
                                lpad(nextval('seq_matricule')::text, 4, '0'),
  prenom         text not null default '',
  nom            text not null default '',
  email          text not null default '',
  telephone      text,
  fonction       text not null default 'adherent' references fonctions(code),
  territoire_id  uuid references territoires(id),
  echelon        integer not null default 1 references echelons(niveau),
  statut         text not null default 'en_attente'
                   check (statut in ('en_attente','actif','suspendu','archive')),
  date_adhesion  date,
  photo_url      text,
  bio            text,
  visible_public boolean not null default false,
  webmail        text,                       -- adresse @ffce-asso.fr si accordée
  cree_le        timestamptz not null default now(),
  maj_le         timestamptz not null default now()
);

create index if not exists idx_profils_territoire on profils(territoire_id);
create index if not exists idx_profils_statut     on profils(statut);

-- Création automatique du profil à l'inscription, toujours « en attente ».
create or replace function creer_profil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profils (id, email, prenom, nom)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'prenom',''),
          coalesce(new.raw_user_meta_data->>'nom',''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists trg_creer_profil on auth.users;
create trigger trg_creer_profil
  after insert on auth.users
  for each row execute function creer_profil();


-- ---------------------------------------------------------------------
-- 5. LECTURE DES DROITS
--    Fonctions SECURITY DEFINER : elles lisent profils sans repasser par
--    RLS, ce qui évite toute récursion dans les politiques.
-- ---------------------------------------------------------------------

create or replace function mon_niveau()
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(
    (select f.niveau from profils p join fonctions f on f.code = p.fonction
      where p.id = auth.uid() and p.statut = 'actif'), 0);
$$;

create or replace function mon_echelon()
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select echelon from profils where id = auth.uid() and statut = 'actif'), 0);
$$;

create or replace function mon_territoire()
returns uuid language sql stable security definer set search_path = public as $$
  select territoire_id from profils where id = auth.uid();
$$;

create or replace function est_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select mon_niveau() >= 90;
$$;

-- Tous les territoires situés sous un territoire donné, lui compris.
create or replace function territoires_sous(racine uuid)
returns table (id uuid) language sql stable security definer set search_path = public as $$
  with recursive arbre as (
    select t.id from territoires t where t.id = racine
    union all
    select t.id from territoires t join arbre a on t.parent_id = a.id
  )
  select id from arbre;
$$;

-- Le cœur du système : la cible est-elle dans mon périmètre ?
create or replace function dans_mon_perimetre(cible uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() then true
    when mon_territoire() is null then false
    when cible is null then false
    else exists (select 1 from territoires_sous(mon_territoire()) s where s.id = cible)
  end;
$$;

-- Niveau à partir duquel on encadre du monde (référent départemental).
create or replace function est_encadrant()
returns boolean language sql stable security definer set search_path = public as $$
  select mon_niveau() >= 50;
$$;


-- ---------------------------------------------------------------------
-- 6. GARDE-FOUS
--    Personne ne se promeut soi-même. Le dernier administrateur reste.
-- ---------------------------------------------------------------------

create or replace function verifier_changement_profil()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  nb_admins integer;
begin
  -- Nul ne modifie sa propre fonction, son échelon, son statut, son territoire.
  if auth.uid() = new.id and not est_admin() then
    -- Le territoire fait exception : il se renseigne une fois, à l'inscription.
    -- Une fois posé, seule la Direction générale peut muter quelqu'un.
    if new.fonction is distinct from old.fonction
       or new.echelon is distinct from old.echelon
       or new.statut  is distinct from old.statut
       or (old.territoire_id is not null
           and new.territoire_id is distinct from old.territoire_id) then
      raise exception 'Ces informations sont modifiées par la Direction générale, pas depuis votre compte.';
    end if;
  end if;

  -- Un administrateur ne se rétrograde pas lui-même.
  if auth.uid() = new.id and old.fonction = 'admin' and new.fonction <> 'admin' then
    raise exception 'Un administrateur ne peut pas retirer ses propres droits.';
  end if;

  -- Il reste toujours au moins un administrateur actif.
  if old.fonction = 'admin' and new.fonction <> 'admin' then
    select count(*) into nb_admins from profils
      where fonction = 'admin' and statut = 'actif' and id <> old.id;
    if nb_admins = 0 then
      raise exception 'La fédération doit conserver au moins un administrateur actif.';
    end if;
  end if;

  new.maj_le := now();
  return new;
end $$;

drop trigger if exists trg_verifier_profil on profils;
create trigger trg_verifier_profil
  before update on profils
  for each row execute function verifier_changement_profil();


-- ---------------------------------------------------------------------
-- 7. APPLICATIONS
--    Chaque brique du système d'information est une « application ».
--    L'admin l'ouvre à qui de droit depuis le tableau de bord.
-- ---------------------------------------------------------------------

create table if not exists applications (
  code        text primary key,
  nom         text not null,
  description text,
  icone       text,
  niveau_min  integer not null default 10,   -- ouverture automatique à ce niveau
  sur_demande boolean not null default false,-- sinon : accordée nominativement
  externe_url text,                          -- Google Workspace, webmail…
  ordre       integer not null default 100,
  actif       boolean not null default true
);

insert into applications (code, nom, description, icone, niveau_min, sur_demande, externe_url, ordre) values
  ('annuaire',   'Annuaire fédéral',   'Les membres de votre périmètre.',                       'users',    50, false, null, 10),
  ('formations', 'Formations',         'Cours, quiz et certifications.',                        'book',     10, false, null, 20),
  ('groupes',    'Groupes de travail', 'Projets, documents partagés, tâches.',                  'layers',   20, false, null, 30),
  ('messagerie', 'Messagerie interne', 'Échanges privés et de groupe.',                         'message',  10, false, null, 40),
  ('notes_frais','Notes de frais',     'Déposer et suivre le remboursement de vos dépenses.',   'receipt',  20, true,  null, 50),
  ('tresorerie', 'Direction financière','Instruction et paiement des notes de frais.',          'wallet',   80, true,  null, 60),
  ('validation', 'Vérifications',      'Inscriptions, demandes et accès restreints.',           'check',    90, false, null, 70),
  ('reseau',     'Réseau et fonctions','Nommer, muter, faire progresser.',                      'network',  90, false, null, 80),
  ('vitrine',    'Site public',        'Textes et chiffres du site public.',                    'globe',    90, false, null, 90),
  ('workspace',  'Google Workspace',   'Drive, Agenda et Docs de la fédération.',               'drive',    20, false, 'https://workspace.google.com/dashboard', 100),
  ('webmail',    'Webmail FFCE',       'Votre adresse @ffce-asso.fr.',                          'mail',     20, true,  'https://mail.google.com/a/ffce-asso.fr', 110)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description, icone = excluded.icone,
      niveau_min = excluded.niveau_min, sur_demande = excluded.sur_demande,
      externe_url = excluded.externe_url, ordre = excluded.ordre;

create table if not exists acces_applications (
  id           uuid primary key default gen_random_uuid(),
  profil_id    uuid not null references profils(id) on delete cascade,
  application  text not null references applications(code) on delete cascade,
  statut       text not null default 'accorde' check (statut in ('accorde','revoque')),
  motif        text,
  accorde_par  uuid references profils(id),
  cree_le      timestamptz not null default now(),
  unique (profil_id, application)
);

-- Un membre a-t-il accès à une application ?
create or replace function a_acces(app text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from applications a
    where a.code = app and a.actif
      and (
        (not a.sur_demande and mon_niveau() >= a.niveau_min)
        or exists (select 1 from acces_applications x
                   where x.profil_id = auth.uid() and x.application = app and x.statut = 'accorde')
      )
  );
$$;


-- ---------------------------------------------------------------------
-- 8. GUICHET DE DEMANDES
--    Un seul endroit pour tout ce qui doit être validé : extension de
--    compte, accès applicatif, adhésion à un groupe, promotion.
-- ---------------------------------------------------------------------

create table if not exists demandes (
  id            uuid primary key default gen_random_uuid(),
  profil_id     uuid not null references profils(id) on delete cascade,
  type          text not null check (type in
                  ('extension_compte','acces_application','adhesion_groupe','promotion','autre')),
  objet         text not null,
  message       text,
  cible         text,                        -- code application, id de groupe…
  statut        text not null default 'ouverte'
                  check (statut in ('ouverte','en_cours','acceptee','refusee')),
  traite_par    uuid references profils(id),
  traite_le     timestamptz,
  motif_reponse text,
  cree_le       timestamptz not null default now()
);

create index if not exists idx_demandes_statut on demandes(statut);


-- ---------------------------------------------------------------------
-- 9. CONTENUS DE LA VITRINE
--    Aucun texte public n'est écrit en dur dans le code.
-- ---------------------------------------------------------------------

create table if not exists contenus (
  cle      text primary key,
  valeur   text not null default '',
  libelle  text not null,
  format   text not null default 'texte' check (format in ('texte','long','nombre','url')),
  section  text not null default 'general',
  ordre    integer not null default 100
);

insert into contenus (cle, libelle, format, section, ordre, valeur) values
  ('accroche',     'Accroche de la page d''accueil','long','accueil',10,
   'La citoyenneté ne se décrète pas. Elle s''apprend, se pratique, et se transmet.'),
  ('sous_accroche','Paragraphe d''introduction','long','accueil',20,
   'La FFCE fédère des bénévoles dans toute la France pour porter l''éducation à la citoyenneté, la transmission des valeurs de la République et l''égalité des chances auprès des jeunes générations.'),
  ('mission',      'Notre mission','long','association',10,
   'Promouvoir l''apprentissage de la citoyenneté active, contribuer à l''éducation civique et à la culture démocratique, favoriser l''émancipation individuelle et collective, et transmettre les valeurs de la République auprès des jeunes générations.'),
  ('histoire',     'Notre histoire','long','association',20,
   'Déclarée le 12 août 2020, la Fédération intervient en milieu scolaire, périscolaire et extra-scolaire.'),
  ('nb_benevoles', 'Bénévoles engagés','nombre','chiffres',10,'0'),
  ('nb_departements','Départements couverts','nombre','chiffres',20,'0'),
  ('nb_actions',   'Actions menées','nombre','chiffres',30,'0'),
  ('nb_jeunes',    'Jeunes touchés','nombre','chiffres',40,'0'),
  ('nom_legal',    'Nom exact en préfecture','texte','legal',10,
   'Fédération Française pour la Citoyenneté et l''Égalité des Chances'),
  ('siege',        'Siège social','texte','legal',20,'8 rue du Faubourg Poissonnière, 75010 Paris'),
  ('rna',          'Numéro RNA','texte','legal',30,'W604008669'),
  ('siren',        'SIREN','texte','legal',40,'889 357 620'),
  ('president',    'Président','texte','legal',50,''),
  ('email_contact','Adresse de contact','texte','contact',10,'contact@ffce-asso.fr'),
  ('mentions',     'Mentions légales','long','legal',60,''),
  ('confidentialite','Politique de confidentialité','long','legal',70,'')
on conflict (cle) do nothing;


-- ---------------------------------------------------------------------
-- 10. JOURNAL
--     Toute décision d'accès laisse une trace. Non modifiable.
-- ---------------------------------------------------------------------

create table if not exists journal (
  id      bigserial primary key,
  acteur  uuid references profils(id),
  action  text not null,
  cible   text,
  details jsonb,
  cree_le timestamptz not null default now()
);


-- =====================================================================
--  11. SÉCURITÉ — Row Level Security
--      Toute la protection vit ici. Jamais dans l'interface.
-- =====================================================================

alter table territoires        enable row level security;
alter table fonctions          enable row level security;
alter table echelons           enable row level security;
alter table profils            enable row level security;
alter table applications       enable row level security;
alter table acces_applications enable row level security;
alter table demandes           enable row level security;
alter table contenus           enable row level security;
alter table journal            enable row level security;

-- Référentiels : lecture libre, écriture réservée à l'administration.
drop policy if exists lire_territoires on territoires;
create policy lire_territoires on territoires for select using (true);
drop policy if exists ecrire_territoires on territoires;
create policy ecrire_territoires on territoires for all using (est_admin()) with check (est_admin());

drop policy if exists lire_fonctions on fonctions;
create policy lire_fonctions on fonctions for select using (true);

drop policy if exists lire_echelons on echelons;
create policy lire_echelons on echelons for select using (true);

drop policy if exists lire_applications on applications;
create policy lire_applications on applications for select using (true);
drop policy if exists ecrire_applications on applications;
create policy ecrire_applications on applications for all using (est_admin()) with check (est_admin());

-- PROFILS
-- Chacun se voit. L'encadrement voit son périmètre. L'admin voit tout.
-- La vitrine publique voit les seuls profils qui ont coché la case.
drop policy if exists lire_profils on profils;
create policy lire_profils on profils for select using (
      auth.uid() = id
   or est_admin()
   or (visible_public and statut = 'actif')
   or (est_encadrant() and statut in ('actif','en_attente') and dans_mon_perimetre(territoire_id))
);

drop policy if exists maj_mon_profil on profils;
create policy maj_mon_profil on profils for update
  using (auth.uid() = id) with check (auth.uid() = id);

-- La Direction générale nomme, mute, suspend.
drop policy if exists maj_profils_admin on profils;
create policy maj_profils_admin on profils for update
  using (est_admin()) with check (est_admin());

-- ACCÈS APPLICATIFS
drop policy if exists lire_acces on acces_applications;
create policy lire_acces on acces_applications for select using (
  auth.uid() = profil_id or est_admin()
);
drop policy if exists ecrire_acces on acces_applications;
create policy ecrire_acces on acces_applications for all
  using (est_admin()) with check (est_admin());

-- DEMANDES
drop policy if exists lire_demandes on demandes;
create policy lire_demandes on demandes for select using (
  auth.uid() = profil_id or est_admin()
);
drop policy if exists creer_demande on demandes;
create policy creer_demande on demandes for insert with check (auth.uid() = profil_id);
drop policy if exists traiter_demande on demandes;
create policy traiter_demande on demandes for update
  using (est_admin()) with check (est_admin());

-- CONTENUS
drop policy if exists lire_contenus on contenus;
create policy lire_contenus on contenus for select using (true);
drop policy if exists ecrire_contenus on contenus;
create policy ecrire_contenus on contenus for all
  using (est_admin()) with check (est_admin());

-- JOURNAL : on écrit, on ne réécrit pas.
drop policy if exists lire_journal on journal;
create policy lire_journal on journal for select using (est_admin());
drop policy if exists ecrire_journal on journal;
create policy ecrire_journal on journal for insert with check (auth.uid() = acteur);


-- ---------------------------------------------------------------------
-- 12. VUES DE CONFORT
-- ---------------------------------------------------------------------

drop view if exists v_annuaire;
create view v_annuaire with (security_invoker = true) as
select p.id, p.matricule, p.prenom, p.nom, p.email, p.telephone,
       p.fonction, f.nom as fonction_nom, f.niveau, f.famille,
       p.echelon, e.nom as echelon_nom,
       p.territoire_id, t.nom as territoire_nom, t.echelle as territoire_echelle,
       p.statut, p.date_adhesion, p.photo_url, p.bio, p.visible_public, p.cree_le
from profils p
join fonctions f  on f.code = p.fonction
join echelons e   on e.niveau = p.echelon
left join territoires t on t.id = p.territoire_id;

-- Chemin territorial lisible : « Occitanie › Ariège › Foix »
create or replace function chemin_territoire(cible uuid)
returns text language sql stable security definer set search_path = public as $$
  with recursive chemin as (
    select t.id, t.parent_id, t.nom, 1 as prof from territoires t where t.id = cible
    union all
    select t.id, t.parent_id, t.nom, c.prof + 1 from territoires t join chemin c on t.id = c.parent_id
  )
  select string_agg(nom, ' › ' order by prof desc) from chemin;
$$;

-- =====================================================================
--  FIN DE LA MIGRATION 01
--
--  APRÈS EXÉCUTION — deux gestes à faire une seule fois :
--
--  1. Créez votre compte sur le site.
--  2. Revenez ici et exécutez, en remplaçant l'adresse :
--
--     update profils
--        set fonction = 'admin', statut = 'actif', echelon = 7,
--            territoire_id = (select id from territoires where echelle='national')
--      where email = 'votre.adresse@exemple.fr';
--
--  Sans ce geste, personne n'est administrateur et rien ne peut être validé.
-- =====================================================================
