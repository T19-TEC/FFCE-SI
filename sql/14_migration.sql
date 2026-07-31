-- =====================================================================
--  FFCE — Migration 14 — SITE PUBLIC ET COMMUNICATION
--
--  Deux chantiers qui vont ensemble : l'un produit, l'autre publie.
--
--  1. LE SITE PUBLIC DEVIENT MODIFIABLE. Jusqu'ici, seuls des textes
--     isolés l'étaient. Désormais : des blocs qu'on ajoute, réordonne
--     et retire, des actualités, et des images déposées depuis
--     l'interface. Plus une ligne de contenu dans le code.
--
--  2. L'APPLICATION COMMUNICATION. Un calendrier éditorial, des
--     publications qui passent par une validation, des modèles réutilisables
--     et le rappel des règles de la charte. Parce qu'une charte qu'on
--     doit rouvrir en PDF à chaque fois n'est pas appliquée.
--
--  Prérequis : 01 à 13.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DÉPÔT PUBLIC D'IMAGES
--    Celui-ci est public : ce sont les visuels du site vitrine.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('public', 'public', true, 5242880)
on conflict (id) do update set public = true, file_size_limit = 5242880;

drop policy if exists lecture_public on storage.objects;
create policy lecture_public on storage.objects for select
  using (bucket_id = 'public');

drop policy if exists depot_public on storage.objects;
create policy depot_public on storage.objects for insert to authenticated
  with check (bucket_id = 'public'
              and (a_droit('vitrine.editer') or a_droit('com.rediger') or est_admin()));

drop policy if exists suppr_public on storage.objects;
create policy suppr_public on storage.objects for delete to authenticated
  using (bucket_id = 'public'
         and (a_droit('vitrine.editer') or est_admin()));

-- ---------------------------------------------------------------------
-- 2. BLOCS DE CONTENU
--    Des éléments répétables : cartes d'action, chiffres, témoignages,
--    encarts. On les ajoute, on les réordonne, on les dépublie.
-- ---------------------------------------------------------------------

create table if not exists blocs_vitrine (
  id         uuid primary key default gen_random_uuid(),
  page       text not null default 'accueil'
               check (page in ('accueil','association','actions','reseau','rejoindre','contact')),
  type       text not null default 'carte'
               check (type in ('carte','chiffre','citation','encart','etape')),
  titre      text not null,
  contenu    text,
  image      text,
  lien       text,
  lien_texte text,
  ordre      integer not null default 100,
  publie     boolean not null default true,
  maj_par    uuid references profils(id),
  maj_le     timestamptz not null default now(),
  cree_le    timestamptz not null default now()
);
create index if not exists idx_blocs_page on blocs_vitrine(page, ordre);

-- On reprend en base les cartes qui vivaient dans le code.
insert into blocs_vitrine (page, type, titre, contenu, ordre)
select 'accueil', 'carte', v.t, v.c, v.o from (values
  ('Éducation à la citoyenneté',
   'Ateliers d''éducation civique et de culture démocratique, du collège au lycée.', 10),
  ('Mémoire et transmission',
   'Transmission de l''histoire des grandes luttes républicaines et du devoir de mémoire auprès des jeunes générations.', 20),
  ('Égalité des chances',
   'Lutte contre les discriminations et le harcèlement, égalité entre les femmes et les hommes.', 30),
  ('Éducation aux médias',
   'Comprendre l''information, ses circuits et ses pièges, pour exercer un esprit critique.', 40)
) as v(t,c,o)
where not exists (select 1 from blocs_vitrine where page = 'accueil' and type = 'carte');

insert into blocs_vitrine (page, type, titre, contenu, ordre)
select 'actions', 'carte', v.t, v.c, v.o from (values
  ('Quartiers d''été', 'Un relais local dans chaque département, pour faire vivre l''été des quartiers populaires.', 10),
  ('Interventions scolaires', 'Ateliers citoyenneté, valeurs de la République et lutte contre le harcèlement.', 20),
  ('Mémoire vivante', 'Rencontres, visites et travaux d''élèves autour des grandes luttes républicaines.', 30),
  ('Jeunesse et institutions', 'Temps d''échange encadrés pour rétablir un dialogue direct.', 40),
  ('Éducation aux médias', 'Décryptage de l''information et sensibilisation à la désinformation.', 50),
  ('Orientation', 'Accompagnement des lycéens dans la construction de leur parcours.', 60)
) as v(t,c,o)
where not exists (select 1 from blocs_vitrine where page = 'actions');

-- Réglages généraux du site, au-delà des seuls textes.
insert into contenus (cle, libelle, format, section, ordre, valeur) values
  ('hero_image',      'Image du bandeau d''accueil','url','apparence',10,''),
  ('hero_bouton',     'Texte du bouton principal','texte','apparence',20,'Rejoindre la fédération'),
  ('hero_bouton_lien','Lien du bouton principal','texte','apparence',30,'#/rejoindre'),
  ('titre_actions',   'Titre du bloc « ce que nous faisons »','texte','apparence',40,
   'Quatre terrains d''engagement'),
  ('intro_actions',   'Introduction du bloc « ce que nous faisons »','long','apparence',50,
   'Nous intervenons en milieu scolaire, périscolaire et extra-scolaire, aux côtés des établissements, des collectivités et des acteurs de terrain.'),
  ('titre_chiffres',  'Titre du bloc chiffres','texte','apparence',60,'Une fédération de terrain'),
  ('appel_final',     'Phrase d''appel en bas d''accueil','long','apparence',70,
   'Un engagement se construit, il ne s''impose pas.'),
  ('appel_final_texte','Paragraphe d''appel','long','apparence',80,
   'Il n''y a ni parcours attendu, ni profil imposé. Les rôles se construisent avec chacun, selon les disponibilités et les envies.'),
  ('afficher_actualites','Afficher les actualités sur l''accueil (oui / non)','texte','apparence',90,'oui'),
  ('reseaux_instagram','Compte Instagram','url','contact',20,''),
  ('reseaux_linkedin', 'Page LinkedIn','url','contact',30,''),
  ('reseaux_facebook', 'Page Facebook','url','contact',40,''),
  ('telephone',        'Téléphone','texte','contact',50,'')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 3. ACTUALITÉS
-- ---------------------------------------------------------------------

create table if not exists articles (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  titre      text not null,
  chapo      text,
  contenu    text,
  image      text,
  categorie  text default 'Actualité',
  territoire_id uuid references territoires(id),
  publie     boolean not null default false,
  publie_le  timestamptz,
  auteur_id  uuid references profils(id),
  maj_le     timestamptz not null default now(),
  cree_le    timestamptz not null default now()
);
create index if not exists idx_articles_publie on articles(publie, publie_le desc);

-- Une translittération sommaire, suffisante pour des adresses lisibles.
-- Elle doit précéder slugifier() : PostgreSQL vérifie le corps des
-- fonctions SQL au moment de leur création.
create or replace function unaccent_simple(t text)
returns text language sql immutable as $$
  select translate(coalesce(t,''),
    'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ',
    'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY');
$$;

create or replace function slugifier(t text)
returns text language sql immutable as $$
  select trim(both '-' from regexp_replace(
    lower(unaccent_simple(coalesce(t,''))), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function enregistrer_article(
  p_id uuid, p_titre text, p_chapo text, p_contenu text,
  p_image text, p_categorie text, p_publie boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_slug text;
begin
  if not (a_droit('vitrine.editer') or a_droit('com.publier')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne publiez pas sur le site.');
  end if;
  if coalesce(trim(p_titre),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le titre est obligatoire.');
  end if;

  v_slug := slugifier(p_titre);
  if p_id is null then
    -- Un suffixe si l'adresse est déjà prise.
    while exists (select 1 from articles where slug = v_slug) loop
      v_slug := v_slug || '-' || floor(random()*900+100)::text;
    end loop;
    insert into articles (slug, titre, chapo, contenu, image, categorie,
                          publie, publie_le, auteur_id)
    values (v_slug, trim(p_titre), nullif(trim(p_chapo),''), p_contenu,
            nullif(p_image,''), coalesce(nullif(trim(p_categorie),''),'Actualité'),
            coalesce(p_publie,false),
            case when p_publie then now() end, auth.uid())
    returning id into v_id;
  else
    update articles
       set titre = trim(p_titre), chapo = nullif(trim(p_chapo),''),
           contenu = p_contenu, image = nullif(p_image,''),
           categorie = coalesce(nullif(trim(p_categorie),''),'Actualité'),
           publie = coalesce(p_publie,false),
           publie_le = case when p_publie and publie_le is null then now() else publie_le end,
           maj_le = now()
     where id = p_id
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug);
end $$;

-- ---------------------------------------------------------------------
-- 4. DROITS ET POSTE DE LA COMMUNICATION
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('com.rediger', 'Rédiger des publications',        'Communication', false, 210),
  ('com.valider', 'Valider une publication',         'Communication', false, 220),
  ('com.publier', 'Publier sur le site et les réseaux','Communication', true, 230)
on conflict (code) do nothing;

insert into postes (code, nom, description, couleur, systeme) values
  ('dircom', 'Direction de la communication',
   'Conduit la communication de la fédération, valide les publications et tient la charte graphique.',
   'bleu', true),
  ('charge_com', 'Chargé de communication',
   'Rédige et prépare les publications, soumises à validation de la DIRCOM.',
   'neutre', true)
on conflict (code) do update set nom = excluded.nom, description = excluded.description;

insert into poste_droits (poste, droit) values
  ('dircom','com.rediger'), ('dircom','com.valider'), ('dircom','com.publier'),
  ('dircom','vitrine.editer'),
  ('charge_com','com.rediger')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 5. CAMPAGNES ET PUBLICATIONS
-- ---------------------------------------------------------------------

create table if not exists campagnes (
  id          uuid primary key default gen_random_uuid(),
  titre       text not null,
  objectif    text,
  debut       date,
  fin         date,
  statut      text not null default 'preparation'
                check (statut in ('preparation','en_cours','terminee','annulee')),
  responsable uuid references profils(id),
  cree_par    uuid references profils(id),
  cree_le     timestamptz not null default now()
);

create table if not exists publications (
  id          uuid primary key default gen_random_uuid(),
  campagne_id uuid references campagnes(id) on delete set null,
  canal       text not null default 'instagram'
                check (canal in ('instagram','linkedin','facebook','x','site','newsletter','presse')),
  titre       text not null,
  texte       text,
  image       text,
  lien        text,
  date_prevue timestamptz,
  statut      text not null default 'brouillon'
                check (statut in ('brouillon','a_valider','validee','publiee','refusee','archivee')),
  auteur_id   uuid references profils(id),
  valide_par  uuid references profils(id),
  valide_le   timestamptz,
  observation text,
  publie_le   timestamptz,
  cree_le     timestamptz not null default now()
);
create index if not exists idx_pub_statut on publications(statut, date_prevue);

-- Modèles réutilisables : on ne réécrit pas un communiqué de zéro.
create table if not exists modeles_com (
  id        uuid primary key default gen_random_uuid(),
  titre     text not null,
  canal     text,
  contenu   text not null,
  conseils  text,
  cree_par  uuid references profils(id),
  cree_le   timestamptz not null default now()
);

insert into modeles_com (titre, canal, contenu, conseils)
select v.t, v.c, v.x, v.a from (values
  ('Annonce d''action locale', 'instagram',
   E'[Territoire] — [Date]\n\nLa FFCE était à [lieu] pour [action], aux côtés de [partenaires].\n\n[Une phrase sur ce qui s''est passé, concrète.]\n\n[Une phrase sur ce que cela change pour les jeunes présents.]\n\nMerci à [personnes ou structures].\n\n#FFCE #Citoyenneté #ÉgalitéDesChances',
   'Une photo nette, jamais de visage de mineur sans autorisation écrite. Le logo ne se superpose pas à une image chargée : réservez-lui un fond uni de la palette.'),
  ('Communiqué de presse', 'presse',
   E'COMMUNIQUÉ DE PRESSE\nParis, le [date]\n\n[TITRE EN CAPITALES, UNE LIGNE]\n\n[Chapô : qui, quoi, où, quand, pourquoi — cinq lignes maximum.]\n\n[Développement en deux ou trois paragraphes.]\n\n« [Citation d''un responsable, attribuée avec nom et fonction]. »\n\nÀ propos de la FFCE\nLa Fédération française pour la citoyenneté et l''égalité des chances est une association d''éducation populaire qui agit pour renforcer le lien entre les jeunes et la démocratie.\n\nContact presse : [nom] — [adresse] — [téléphone]',
   'Une page maximum. Le nom complet de la fédération apparaît au moins une fois. Aucune prise de position partisane : notre indépendance est notre crédibilité.'),
  ('Appel à bénévoles', 'linkedin',
   E'Nous cherchons [nombre] bénévoles pour [mission], à [lieu], [dates].\n\nCe qu''il y a à faire : [en une phrase].\nCe que cela demande : [disponibilité, aucune compétence particulière si c''est le cas].\nCe que cela apporte : [formation, expérience, collectif].\n\nAucun diplôme n''est exigé. On se forme en faisant, accompagné.\n\nPour candidater : [lien]',
   'Dire ce qu''on attend en heures. Ne jamais laisser croire qu''un profil est requis : c''est ce qui écarte celles et ceux qu''on veut atteindre.'),
  ('Publication de mémoire', 'instagram',
   E'[Date de la commémoration]\n\n[Fait historique, deux phrases, sans emphase.]\n\n[Ce que la FFCE en transmet aujourd''hui, une phrase.]\n\nFaire mémoire, c''est refuser l''oubli.',
   'Sobriété absolue. Aucun emoji. Fond uni bleu nuit ou blanc cassé. Vérifier chaque date et chaque nom avant publication.')
) as v(t,c,x,a)
where not exists (select 1 from modeles_com);

create or replace function soumettre_publication(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from publications
                 where id = p_id and auteur_id = auth.uid() and statut = 'brouillon') then
    return jsonb_build_object('ok', false, 'message', 'Cette publication n''est plus modifiable.');
  end if;
  update publications set statut = 'a_valider' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function statuer_publication(p_id uuid, p_issue text, p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('com.valider') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction de la communication.');
  end if;
  if p_issue = 'refusee' and coalesce(trim(p_observation),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un refus doit être motivé.');
  end if;

  update publications
     set statut = p_issue, valide_par = auth.uid(), valide_le = now(),
         observation = nullif(trim(p_observation),''),
         publie_le = case when p_issue = 'publiee' then now() else publie_le end
   where id = p_id;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'publication_' || p_issue, p_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function calendrier_com(p_depuis date default null, p_jusqu date default null)
returns table (
  id uuid, titre text, canal text, statut text, date_prevue timestamptz,
  campagne text, auteur text, valideur text, observation text, image text
) language sql stable security definer set search_path = public as $$
  select p.id, p.titre, p.canal, p.statut, p.date_prevue, c.titre,
         trim(a.prenom || ' ' || a.nom), trim(v.prenom || ' ' || v.nom),
         p.observation, p.image
  from publications p
  left join campagnes c on c.id = p.campagne_id
  left join profils a   on a.id = p.auteur_id
  left join profils v   on v.id = p.valide_par
  where (a_droit('com.rediger') or a_droit('com.valider') or est_admin())
    and (p_depuis is null or p.date_prevue >= p_depuis)
    and (p_jusqu is null or p.date_prevue < p_jusqu + 1)
  order by p.date_prevue nulls last, p.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 6. LECTURE PUBLIQUE
-- ---------------------------------------------------------------------

create or replace function vitrine_blocs(p_page text)
returns table (id uuid, type text, titre text, contenu text, image text,
               lien text, lien_texte text, ordre integer)
language sql stable security definer set search_path = public as $$
  select b.id, b.type, b.titre, b.contenu, b.image, b.lien, b.lien_texte, b.ordre
  from blocs_vitrine b
  where b.page = p_page and b.publie
  order by b.ordre;
$$;

create or replace function actualites(p_limite integer default 6)
returns table (slug text, titre text, chapo text, image text,
               categorie text, publie_le timestamptz, auteur text)
language sql stable security definer set search_path = public as $$
  select a.slug, a.titre, a.chapo, a.image, a.categorie, a.publie_le,
         trim(p.prenom || ' ' || p.nom)
  from articles a left join profils p on p.id = a.auteur_id
  where a.publie
  order by a.publie_le desc nulls last
  limit greatest(coalesce(p_limite,6), 1);
$$;

create or replace function article(p_slug text)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(x) from (
    select a.slug, a.titre, a.chapo, a.contenu, a.image, a.categorie,
           a.publie_le, trim(p.prenom || ' ' || p.nom) as auteur
    from articles a left join profils p on p.id = a.auteur_id
    where a.slug = p_slug and a.publie) x;
$$;

-- =====================================================================
--  7. SÉCURITÉ
-- =====================================================================

alter table blocs_vitrine enable row level security;
alter table articles      enable row level security;
alter table campagnes     enable row level security;
alter table publications  enable row level security;
alter table modeles_com   enable row level security;

drop policy if exists lire_blocs on blocs_vitrine;
create policy lire_blocs on blocs_vitrine for select using (publie or a_droit('vitrine.editer'));
drop policy if exists gerer_blocs on blocs_vitrine;
create policy gerer_blocs on blocs_vitrine for all
  using (a_droit('vitrine.editer')) with check (a_droit('vitrine.editer'));

drop policy if exists lire_articles on articles;
create policy lire_articles on articles for select using (
  publie or a_droit('vitrine.editer') or a_droit('com.rediger') or auteur_id = auth.uid()
);
drop policy if exists gerer_articles on articles;
create policy gerer_articles on articles for all
  using (a_droit('vitrine.editer') or a_droit('com.publier'))
  with check (a_droit('vitrine.editer') or a_droit('com.publier'));

drop policy if exists lire_campagnes on campagnes;
create policy lire_campagnes on campagnes for select
  using (a_droit('com.rediger') or a_droit('com.valider') or est_admin());
drop policy if exists gerer_campagnes on campagnes;
create policy gerer_campagnes on campagnes for all
  using (a_droit('com.valider')) with check (a_droit('com.valider'));

drop policy if exists lire_publications on publications;
create policy lire_publications on publications for select
  using (a_droit('com.rediger') or a_droit('com.valider') or est_admin());
drop policy if exists creer_publications on publications;
create policy creer_publications on publications for insert
  with check (a_droit('com.rediger') and auteur_id = auth.uid());
-- L'auteur modifie tant que c'est un brouillon ; la DIRCOM à tout moment.
drop policy if exists maj_publications on publications;
create policy maj_publications on publications for update using (
  (auteur_id = auth.uid() and statut in ('brouillon','refusee')) or a_droit('com.valider')
);
drop policy if exists suppr_publications on publications;
create policy suppr_publications on publications for delete using (
  (auteur_id = auth.uid() and statut = 'brouillon') or a_droit('com.valider')
);

drop policy if exists lire_modeles on modeles_com;
create policy lire_modeles on modeles_com for select using (a_droit('com.rediger') or est_admin());
drop policy if exists gerer_modeles on modeles_com;
create policy gerer_modeles on modeles_com for all
  using (a_droit('com.valider')) with check (a_droit('com.valider'));

grant select on blocs_vitrine, articles, campagnes, publications, modeles_com
  to anon, authenticated;
grant insert, update, delete on blocs_vitrine, articles, campagnes,
      publications, modeles_com to authenticated;

grant execute on function slugifier(text), unaccent_simple(text),
                          enregistrer_article(uuid, text, text, text, text, text, boolean),
                          soumettre_publication(uuid),
                          statuer_publication(uuid, text, text),
                          calendrier_com(date, date),
                          vitrine_blocs(text), actualites(integer), article(text)
  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. L'APPLICATION
-- ---------------------------------------------------------------------

insert into applications (code, nom, description, icone, niveau_min, sur_demande,
                          droit_requis, ordre)
values ('communication', 'Communication',
        'Calendrier éditorial, publications, modèles et règles de la charte.',
        'megaphone', 100, true, 'com.rediger', 85)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      droit_requis = excluded.droit_requis, ordre = excluded.ordre;

insert into application_visibilite (application, fonction, etat)
select 'communication', f.code, 'invisible' from fonctions f
on conflict (application, fonction) do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 14
--
--  Pour ouvrir la communication à votre équipe :
--    select nommer((select id from profils where email='dircom@ffce-asso.fr'),
--                  'dircom', null, null, 'Direction de la communication');
--    select nommer((select id from profils where email='…'),
--                  'charge_com', null, null, 'Chargé de communication');
--
--  Le circuit : un chargé de com rédige, la DIRCOM valide, puis publie.
--  Nul ne valide sa propre publication à moins de porter les deux
--  droits — ce qui est le cas de la DIRCOM, et c'est assumé : une
--  équipe de deux personnes ne peut pas s'imposer trois signatures.
-- =====================================================================
