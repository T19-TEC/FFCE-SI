-- =====================================================================
--  FFCE — Migration 47 — LES ÉVÉNEMENTS
--
--  Une fédération d'éducation populaire organise des forums, des
--  formations ouvertes, des assises, des repas. Jusqu'ici tout cela
--  vivait dans des tableurs, avec les conséquences habituelles : des
--  listes qui divergent, des inscrits qu'on ne retrouve pas, et des
--  données personnelles de tiers qui traînent sans échéance.
--
--  Trois principes ont guidé le dessin.
--
--  L'INSCRIPTION EXTERNE EST UNE DONNÉE DE TIERS. Une personne qui
--  n'est pas adhérente confie un nom et un courriel pour venir un jour
--  donné. Ces données ont une durée de vie : elles portent une date
--  d'effacement, et la fédération n'a pas à les garder au-delà.
--
--  UN BILLET N'OUVRE QUE CE QU'IL DIT. Un événement se compose de
--  catégories d'entrée — plénière, atelier, repas — chacune avec sa
--  capacité. Le contrôle à l'entrée vérifie que le billet couvre bien
--  la catégorie présentée. Sans quoi « habilitation d'entrée » ne veut
--  rien dire.
--
--  ON NE COMPTE PAS DEUX FOIS. Une entrée scannée est enregistrée ; la
--  seconde présentation du même billet sur la même catégorie est
--  signalée, pas refusée en silence.
--
--  Prérequis : 01 à 46.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DROITS ET LE POSTE
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('evenements.tenir',    'Créer et tenir des événements',        'Événements', false, 600),
  ('evenements.controler','Contrôler les entrées à un événement', 'Événements', false, 610),
  ('evenements.inscrits', 'Accéder à la liste nominative des inscrits', 'Événements', true, 620)
on conflict (code) do update
  set nom = excluded.nom, sensible = excluded.sensible;

insert into postes (code, nom, description, couleur, systeme, direction, rang) values
  ('evenementiel', 'Coordination événementielle',
   'Crée les événements, ouvre les inscriptions, tient les listes et le contrôle des entrées.',
   'framboise', true, 'dircom', 70)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      direction = excluded.direction, rang = excluded.rang;

insert into poste_droits (poste, droit) values
  ('evenementiel', 'evenements.tenir'),
  ('evenementiel', 'evenements.controler'),
  ('evenementiel', 'evenements.inscrits'),
  ('dircom',       'evenements.tenir'),
  ('dircom',       'evenements.inscrits'),
  ('charge_com',   'evenements.controler'),
  ('president_structure', 'evenements.tenir'),
  ('president_structure', 'evenements.controler')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2. LES ÉVÉNEMENTS
-- ---------------------------------------------------------------------

create table if not exists evenements (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'EV-' || to_char(now(),'YYYY') || '-' ||
                          upper(substr(encode(gen_random_bytes(3),'hex'), 1, 5)),
  titre         text not null,
  objet         text,
  nature        text not null default 'rencontre' check (nature in
                  ('rencontre','forum','formation','assises','ceremonie',
                   'repas','sortie','autre')),
  ouverture     text not null default 'interne' check (ouverture in
                  ('interne','ouverte','sur_invitation')),
  territoire_id uuid references territoires(id) on delete set null,
  groupe_id     uuid references groupes_travail(id) on delete set null,
  -- Un événement peut être porté pour un partenaire : le fichier des
  -- relations extérieures sert alors de répertoire, sans duplication.
  partenaire_id uuid references contacts(id) on delete set null,
  organisateur_id uuid not null references profils(id) on delete cascade,
  lieu          text,
  adresse       text,
  debut         timestamptz not null,
  fin           timestamptz,
  capacite      integer,
  validation_requise boolean not null default false,
  cloture_inscriptions date,
  statut        text not null default 'projet' check (statut in
                  ('projet','ouvert','complet','clos','annule')),
  motif_annulation text,
  jeton_public  text unique not null default encode(gen_random_bytes(12), 'hex'),
  -- Les inscriptions externes s'effacent : on fixe l'échéance à la
  -- création, on ne la décide pas après coup.
  conservation_jours integer not null default 180,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_ev on evenements(statut, debut);

-- Les catégories d'entrée. Un événement sans catégorie déclarée en a
-- une par défaut : « Accès général ».
create table if not exists evenement_categories (
  id           uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references evenements(id) on delete cascade,
  code         text not null,
  nom          text not null,
  description  text,
  capacite     integer,
  horaire      text,
  externe_admis boolean not null default true,
  ordre        integer not null default 100,
  unique (evenement_id, code)
);

create table if not exists inscriptions_evenement (
  id           uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references evenements(id) on delete cascade,
  profil_id    uuid references profils(id) on delete cascade,
  -- Renseignés pour les personnes extérieures uniquement.
  nom          text,
  prenom       text,
  email        text,
  telephone    text,
  organisme    text,
  besoin       text,                     -- accessibilité, régime, etc.
  categories   text[] not null default '{}',
  statut       text not null default 'deposee' check (statut in
                 ('deposee','validee','refusee','annulee')),
  motif        text,
  valide_par   uuid references profils(id),
  valide_le    timestamptz,
  jeton        text unique not null default encode(gen_random_bytes(9), 'hex'),
  efface_le    date,                     -- échéance de conservation
  cree_le      timestamptz not null default now()
);
create index if not exists idx_insc on inscriptions_evenement(evenement_id, statut);
create unique index if not exists idx_insc_membre
  on inscriptions_evenement(evenement_id, profil_id) where profil_id is not null;

create table if not exists entrees_evenement (
  id             uuid primary key default gen_random_uuid(),
  inscription_id uuid not null references inscriptions_evenement(id) on delete cascade,
  categorie      text not null,
  scanne_le      timestamptz not null default now(),
  scanne_par     uuid references profils(id),
  unique (inscription_id, categorie)
);

-- ---------------------------------------------------------------------
-- 3. QUI VOIT QUOI
--    La liste nominative est un droit sensible : elle contient des
--    données de personnes extérieures à la fédération.
-- ---------------------------------------------------------------------

create or replace function puis_je_tenir_evenement(p_evenement uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from evenements e
    where e.id = p_evenement
      and (e.organisateur_id = auth.uid()
           or (a_droit('evenements.tenir')
               and (e.territoire_id is null or dans_mon_perimetre(e.territoire_id)))));
$$;

alter table evenements            enable row level security;
alter table evenement_categories  enable row level security;
alter table inscriptions_evenement enable row level security;
alter table entrees_evenement     enable row level security;

drop policy if exists lire_evenements on evenements;
create policy lire_evenements on evenements for select using (
  statut in ('ouvert','complet','clos')
  or organisateur_id = auth.uid() or est_admin() or a_droit('evenements.tenir'));

drop policy if exists lire_ev_categories on evenement_categories;
create policy lire_ev_categories on evenement_categories for select using (true);

drop policy if exists lire_inscriptions on inscriptions_evenement;
create policy lire_inscriptions on inscriptions_evenement for select using (
  profil_id = auth.uid() or est_admin()
  or a_droit('evenements.inscrits') or puis_je_tenir_evenement(evenement_id));

drop policy if exists lire_entrees on entrees_evenement;
create policy lire_entrees on entrees_evenement for select using (
  est_admin() or a_droit('evenements.controler') or a_droit('evenements.inscrits'));

grant select on evenements, evenement_categories to anon, authenticated;
grant select on inscriptions_evenement, entrees_evenement to authenticated;

-- ---------------------------------------------------------------------
-- 4. TENIR UN ÉVÉNEMENT
-- ---------------------------------------------------------------------

create or replace function enregistrer_evenement(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_terr uuid;
begin
  v_id := uuid_valide(d->>'id');
  if v_id is null then
    if not (est_admin() or a_droit('evenements.tenir')) then
      return jsonb_build_object('ok', false,
        'message', 'La création d''événements revient à la coordination événementielle.');
    end if;
  elsif not puis_je_tenir_evenement(v_id) then
    return jsonb_build_object('ok', false, 'message', 'Cet événement n''est pas le vôtre.');
  end if;

  if coalesce(trim(d->>'titre'),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un événement porte un titre.');
  end if;
  if (d->>'debut') is null or trim(d->>'debut') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Indiquez la date et l''heure : c''est ce que les gens cherchent en premier.');
  end if;

  v_terr := coalesce(uuid_valide(d->>'territoire_id'),
                     (select territoire_id from profils where id = auth.uid()));

  if v_id is null then
    insert into evenements (titre, objet, nature, ouverture, territoire_id, groupe_id,
                            partenaire_id, organisateur_id, lieu, adresse, debut, fin,
                            capacite, validation_requise, cloture_inscriptions,
                            conservation_jours)
    values (trim(d->>'titre'), nullif(trim(d->>'objet'),''),
            coalesce(d->>'nature','rencontre'), coalesce(d->>'ouverture','interne'),
            v_terr, uuid_valide(d->>'groupe_id'), uuid_valide(d->>'partenaire_id'),
            auth.uid(), nullif(trim(d->>'lieu'),''), nullif(trim(d->>'adresse'),''),
            (d->>'debut')::timestamptz, nullif(d->>'fin','')::timestamptz,
            nullif(d->>'capacite','')::int,
            coalesce((d->>'validation_requise')::boolean, false),
            nullif(d->>'cloture_inscriptions','')::date,
            coalesce(nullif(d->>'conservation_jours','')::int, 180))
    returning id into v_id;

    -- Tout événement a au moins une porte d'entrée.
    insert into evenement_categories (evenement_id, code, nom, capacite, ordre)
    values (v_id, 'general', 'Accès général', nullif(d->>'capacite','')::int, 10);
  else
    update evenements set
      titre = trim(d->>'titre'), objet = nullif(trim(d->>'objet'),''),
      nature = coalesce(d->>'nature', nature),
      ouverture = coalesce(d->>'ouverture', ouverture),
      territoire_id = v_terr,
      partenaire_id = uuid_valide(d->>'partenaire_id'),
      lieu = nullif(trim(d->>'lieu'),''), adresse = nullif(trim(d->>'adresse'),''),
      debut = (d->>'debut')::timestamptz, fin = nullif(d->>'fin','')::timestamptz,
      capacite = nullif(d->>'capacite','')::int,
      validation_requise = coalesce((d->>'validation_requise')::boolean, validation_requise),
      cloture_inscriptions = nullif(d->>'cloture_inscriptions','')::date
    where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function regler_categorie(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ev uuid;
begin
  v_ev := uuid_valide(d->>'evenement_id');
  if not puis_je_tenir_evenement(v_ev) then
    return jsonb_build_object('ok', false, 'message', 'Cet événement n''est pas le vôtre.');
  end if;
  if coalesce(trim(d->>'nom'),'') = '' or coalesce(trim(d->>'code'),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une catégorie a un code et un nom.');
  end if;

  insert into evenement_categories (evenement_id, code, nom, description, capacite,
                                    horaire, externe_admis, ordre)
  values (v_ev, lower(trim(d->>'code')), trim(d->>'nom'),
          nullif(trim(d->>'description'),''), nullif(d->>'capacite','')::int,
          nullif(trim(d->>'horaire'),''),
          coalesce((d->>'externe_admis')::boolean, true),
          coalesce(nullif(d->>'ordre','')::int, 100))
  on conflict (evenement_id, code) do update
    set nom = excluded.nom, description = excluded.description,
        capacite = excluded.capacite, horaire = excluded.horaire,
        externe_admis = excluded.externe_admis, ordre = excluded.ordre;
  return jsonb_build_object('ok', true);
end $$;

create or replace function changer_statut_evenement(p_id uuid, p_statut text,
                                                    p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not puis_je_tenir_evenement(p_id) then
    return jsonb_build_object('ok', false, 'message', 'Cet événement n''est pas le vôtre.');
  end if;
  if p_statut = 'annule' and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une annulation se motive : les inscrits doivent savoir pourquoi.');
  end if;
  update evenements set statut = p_statut,
         motif_annulation = case when p_statut = 'annule' then trim(p_motif) end
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. S'INSCRIRE
--    Un membre s'inscrit avec son compte. Une personne extérieure passe
--    par le lien public et laisse le minimum : de quoi la reconnaître à
--    l'entrée et la prévenir si l'événement change.
-- ---------------------------------------------------------------------

create or replace function places_restantes(p_evenement uuid, p_categorie text default null)
returns integer language sql stable security definer set search_path = public as $$
  select case
    when p_categorie is null then
      (select e.capacite from evenements e where e.id = p_evenement)
      - (select count(*)::int from inscriptions_evenement i
         where i.evenement_id = p_evenement and i.statut in ('deposee','validee'))
    else
      (select c.capacite from evenement_categories c
       where c.evenement_id = p_evenement and c.code = p_categorie)
      - (select count(*)::int from inscriptions_evenement i
         where i.evenement_id = p_evenement and i.statut in ('deposee','validee')
           and p_categorie = any (i.categories))
  end;
$$;

create or replace function inscrire_a_evenement(p_evenement uuid,
                                                p_categories text[] default '{}',
                                                p_besoin text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e evenements; v_cat text[]; v_c text; v_reste integer;
begin
  select * into e from evenements where id = p_evenement;
  if e is null or e.statut <> 'ouvert' then
    return jsonb_build_object('ok', false,
      'message', 'Les inscriptions ne sont pas ouvertes.');
  end if;
  if e.cloture_inscriptions is not null and e.cloture_inscriptions < current_date then
    return jsonb_build_object('ok', false, 'message', 'Les inscriptions sont closes.');
  end if;
  if exists (select 1 from inscriptions_evenement i
             where i.evenement_id = p_evenement and i.profil_id = auth.uid()
               and i.statut in ('deposee','validee')) then
    return jsonb_build_object('ok', false, 'message', 'Vous êtes déjà inscrit.');
  end if;

  v_cat := case when coalesce(array_length(p_categories,1),0) = 0
                then array['general'] else p_categories end;

  foreach v_c in array v_cat loop
    v_reste := places_restantes(p_evenement, v_c);
    if v_reste is not null and v_reste <= 0 then
      return jsonb_build_object('ok', false,
        'message', 'Plus de place pour « ' ||
          coalesce((select nom from evenement_categories
                    where evenement_id = p_evenement and code = v_c), v_c) || ' ».');
    end if;
  end loop;

  insert into inscriptions_evenement (evenement_id, profil_id, categories, besoin,
                                      statut, efface_le)
  values (p_evenement, auth.uid(), v_cat, nullif(trim(p_besoin),''),
          case when e.validation_requise then 'deposee' else 'validee' end,
          (coalesce(e.fin, e.debut) + (e.conservation_jours || ' days')::interval)::date);

  return jsonb_build_object('ok', true,
    'statut', case when e.validation_requise then 'deposee' else 'validee' end);
end $$;

-- La page publique : ce qu'un visiteur voit avec le seul lien.
create or replace function evenement_public(p_jeton text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'reference', e.reference, 'titre', e.titre, 'objet', e.objet,
    'nature', e.nature, 'lieu', e.lieu, 'adresse', e.adresse,
    'debut', e.debut, 'fin', e.fin, 'statut', e.statut,
    'territoire', t.nom,
    'partenaire', (select c.nom from contacts c where c.id = e.partenaire_id),
    'cloture', e.cloture_inscriptions,
    'validation_requise', e.validation_requise,
    'ouverte', e.statut = 'ouvert' and e.ouverture = 'ouverte'
               and (e.cloture_inscriptions is null
                    or e.cloture_inscriptions >= current_date),
    'inscrits', (select count(*)::int from inscriptions_evenement i
                 where i.evenement_id = e.id and i.statut in ('deposee','validee')),
    'categories', coalesce((select jsonb_agg(jsonb_build_object(
        'code', c.code, 'nom', c.nom, 'description', c.description,
        'horaire', c.horaire,
        'restantes', places_restantes(e.id, c.code)) order by c.ordre)
      from evenement_categories c
      where c.evenement_id = e.id and c.externe_admis), '[]'::jsonb))
  from evenements e
  left join territoires t on t.id = e.territoire_id
  where e.jeton_public = p_jeton
    and e.statut in ('ouvert','complet','clos');
$$;

-- L'inscription d'une personne extérieure. Elle ne crée aucun compte et
-- ne donne accès à rien : c'est un billet, pas une adhésion.
create or replace function inscription_publique(p_jeton text, d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e evenements; v_cat text[]; v_c text; v_reste integer; v_jeton text;
begin
  select * into e from evenements
   where jeton_public = p_jeton and statut = 'ouvert' and ouverture = 'ouverte';
  if e is null then
    return jsonb_build_object('ok', false,
      'message', 'Les inscriptions ne sont pas ouvertes pour cet événement.');
  end if;
  if e.cloture_inscriptions is not null and e.cloture_inscriptions < current_date then
    return jsonb_build_object('ok', false, 'message', 'Les inscriptions sont closes.');
  end if;
  if coalesce(trim(d->>'nom'),'') = '' or coalesce(trim(d->>'email'),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Votre nom et votre adresse électronique sont nécessaires pour vous inscrire.');
  end if;
  if position('@' in (d->>'email')) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Cette adresse ne semble pas valide.');
  end if;
  if exists (select 1 from inscriptions_evenement i
             where i.evenement_id = e.id and lower(i.email) = lower(trim(d->>'email'))
               and i.statut in ('deposee','validee')) then
    return jsonb_build_object('ok', false,
      'message', 'Une inscription existe déjà avec cette adresse.');
  end if;

  v_cat := case when d ? 'categories' and jsonb_array_length(d->'categories') > 0
                then array(select jsonb_array_elements_text(d->'categories'))
                else array['general'] end;

  foreach v_c in array v_cat loop
    if not exists (select 1 from evenement_categories c
                   where c.evenement_id = e.id and c.code = v_c and c.externe_admis) then
      return jsonb_build_object('ok', false,
        'message', 'Cette partie de l''événement n''est pas ouverte au public.');
    end if;
    v_reste := places_restantes(e.id, v_c);
    if v_reste is not null and v_reste <= 0 then
      return jsonb_build_object('ok', false, 'message', 'Plus de place disponible.');
    end if;
  end loop;

  insert into inscriptions_evenement (evenement_id, nom, prenom, email, telephone,
                                      organisme, besoin, categories, statut, efface_le)
  values (e.id, trim(d->>'nom'), nullif(trim(d->>'prenom'),''),
          lower(trim(d->>'email')), nullif(trim(d->>'telephone'),''),
          nullif(trim(d->>'organisme'),''), nullif(trim(d->>'besoin'),''),
          v_cat, case when e.validation_requise then 'deposee' else 'validee' end,
          (coalesce(e.fin, e.debut) + (e.conservation_jours || ' days')::interval)::date)
  returning jeton into v_jeton;

  return jsonb_build_object('ok', true, 'jeton', v_jeton,
    'validation', e.validation_requise,
    'message', case when e.validation_requise
      then 'Votre demande est enregistrée. Elle sera examinée par les organisateurs.'
      else 'Votre inscription est enregistrée. Conservez ce code : il vous sera demandé à l''entrée.'
      end);
end $$;

grant execute on function evenement_public(text),
                          inscription_publique(text, jsonb),
                          places_restantes(uuid, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. VALIDER, CONTRÔLER
-- ---------------------------------------------------------------------

create or replace function valider_inscription(p_id uuid, p_ok boolean,
                                               p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare i inscriptions_evenement;
begin
  select * into i from inscriptions_evenement where id = p_id;
  if i is null then
    return jsonb_build_object('ok', false, 'message', 'Inscription introuvable.');
  end if;
  if not puis_je_tenir_evenement(i.evenement_id) then
    return jsonb_build_object('ok', false, 'message', 'Cet événement n''est pas le vôtre.');
  end if;
  if not p_ok and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Un refus se motive : la personne doit savoir pourquoi.');
  end if;

  update inscriptions_evenement
     set statut = case when p_ok then 'validee' else 'refusee' end,
         motif = nullif(trim(p_motif),''), valide_par = auth.uid(), valide_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Le contrôle à l'entrée. Un billet n'ouvre que ce qu'il porte : c'est
-- ce qui donne un sens à la répartition par catégorie.
create or replace function controler_entree(p_jeton text, p_categorie text default 'general')
returns jsonb language plpgsql security definer set search_path = public as $$
declare i inscriptions_evenement; e evenements; v_nom text; v_deja timestamptz;
begin
  if not (est_admin() or a_droit('evenements.controler')) then
    return jsonb_build_object('ok', false,
      'message', 'Le contrôle des entrées relève de l''équipe de l''événement.');
  end if;
  select * into i from inscriptions_evenement where jeton = trim(p_jeton);
  if i is null then
    return jsonb_build_object('ok', false, 'motif', 'inconnu',
      'message', 'Billet inconnu.');
  end if;
  select * into e from evenements where id = i.evenement_id;

  if i.statut = 'refusee' then
    return jsonb_build_object('ok', false, 'motif', 'refusee',
      'message', 'Cette inscription a été refusée.');
  end if;
  if i.statut = 'annulee' then
    return jsonb_build_object('ok', false, 'motif', 'annulee',
      'message', 'Cette inscription a été annulée.');
  end if;
  if i.statut = 'deposee' then
    return jsonb_build_object('ok', false, 'motif', 'en_attente',
      'message', 'Inscription en attente de validation.');
  end if;

  -- Le billet couvre-t-il ce qu'on présente ?
  if not (p_categorie = any (i.categories)) then
    return jsonb_build_object('ok', false, 'motif', 'hors_billet',
      'message', 'Ce billet ne couvre pas « ' ||
        coalesce((select nom from evenement_categories
                  where evenement_id = e.id and code = p_categorie), p_categorie) || ' ».',
      'ouvre', i.categories);
  end if;

  select scanne_le into v_deja from entrees_evenement
   where inscription_id = i.id and categorie = p_categorie;

  v_nom := coalesce(
    (select trim(p.prenom || ' ' || p.nom) from profils p where p.id = i.profil_id),
    trim(coalesce(i.prenom,'') || ' ' || i.nom));

  if v_deja is not null then
    -- On ne refuse pas : on signale. Un double passage a souvent une
    -- explication, et c'est à l'humain de trancher.
    return jsonb_build_object('ok', true, 'deja', true, 'membre', v_nom,
      'scanne_le', v_deja, 'externe', i.profil_id is null,
      'message', v_nom || ' est déjà passé à ' ||
                 to_char(v_deja, 'HH24:MI') || '.');
  end if;

  insert into entrees_evenement (inscription_id, categorie, scanne_par)
  values (i.id, p_categorie, auth.uid());

  return jsonb_build_object('ok', true, 'deja', false, 'membre', v_nom,
    'externe', i.profil_id is null, 'organisme', i.organisme,
    'besoin', i.besoin, 'ouvre', i.categories,
    'message', 'Entrée constatée : ' || v_nom || '.');
end $$;

-- ---------------------------------------------------------------------
-- 7. CE QUE L'ON LIT
-- ---------------------------------------------------------------------

drop function if exists mes_evenements(text);
create or replace function mes_evenements(p_filtre text default 'a_venir')
returns table (id uuid, reference text, titre text, objet text, nature text,
               ouverture text, lieu text, debut timestamptz, fin timestamptz,
               statut text, territoire text, partenaire text, organisateur text,
               jeton_public text, capacite integer, inscrits integer,
               presents integer, mon_inscription text, je_tiens boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.reference, e.titre, e.objet, e.nature, e.ouverture, e.lieu,
         e.debut, e.fin, e.statut, t.nom,
         (select c.nom from contacts c where c.id = e.partenaire_id),
         trim(o.prenom || ' ' || o.nom), e.jeton_public, e.capacite,
         (select count(*)::int from inscriptions_evenement i
          where i.evenement_id = e.id and i.statut in ('deposee','validee')),
         (select count(distinct en.inscription_id)::int from entrees_evenement en
          join inscriptions_evenement i2 on i2.id = en.inscription_id
          where i2.evenement_id = e.id),
         (select i.statut from inscriptions_evenement i
          where i.evenement_id = e.id and i.profil_id = auth.uid()),
         puis_je_tenir_evenement(e.id)
  from evenements e
  left join territoires t on t.id = e.territoire_id
  join profils o on o.id = e.organisateur_id
  where (e.statut in ('ouvert','complet','clos')
         or e.organisateur_id = auth.uid() or est_admin() or a_droit('evenements.tenir'))
    and (e.ouverture <> 'interne' or e.territoire_id is null
         or dans_mon_perimetre(e.territoire_id) or puis_je_tenir_evenement(e.id))
    and case p_filtre
      when 'a_venir' then coalesce(e.fin, e.debut) >= now() and e.statut <> 'annule'
      when 'miens'   then e.organisateur_id = auth.uid()
      when 'inscrit' then exists (select 1 from inscriptions_evenement i
                                  where i.evenement_id = e.id and i.profil_id = auth.uid()
                                    and i.statut in ('deposee','validee'))
      else true end
  order by e.debut;
$$;

drop function if exists liste_inscrits(uuid, text);
create or replace function liste_inscrits(p_evenement uuid, p_filtre text default 'tous')
returns table (id uuid, nom text, matricule text, courriel text, telephone text,
               organisme text, externe boolean, categories text[], besoin text,
               statut text, entrees text[], cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id,
         coalesce(trim(p.prenom || ' ' || p.nom),
                  trim(coalesce(i.prenom,'') || ' ' || i.nom)),
         p.matricule, coalesce(p.email, i.email), coalesce(p.telephone, i.telephone),
         i.organisme, i.profil_id is null, i.categories, i.besoin, i.statut,
         coalesce(array(select en.categorie from entrees_evenement en
                        where en.inscription_id = i.id), '{}'),
         i.cree_le
  from inscriptions_evenement i
  left join profils p on p.id = i.profil_id
  where i.evenement_id = p_evenement
    and (est_admin() or a_droit('evenements.inscrits')
         or puis_je_tenir_evenement(p_evenement))
    and case p_filtre
      when 'a_valider' then i.statut = 'deposee'
      when 'presents'  then exists (select 1 from entrees_evenement en
                                    where en.inscription_id = i.id)
      else i.statut in ('deposee','validee') end
  order by 2;
$$;

create or replace function tableau_evenement(p_evenement uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'inscrits', (select count(*)::int from inscriptions_evenement i
                 where i.evenement_id = p_evenement and i.statut in ('deposee','validee')),
    'a_valider', (select count(*)::int from inscriptions_evenement i
                  where i.evenement_id = p_evenement and i.statut = 'deposee'),
    'externes', (select count(*)::int from inscriptions_evenement i
                 where i.evenement_id = p_evenement and i.profil_id is null
                   and i.statut in ('deposee','validee')),
    'presents', (select count(distinct en.inscription_id)::int
                 from entrees_evenement en
                 join inscriptions_evenement i on i.id = en.inscription_id
                 where i.evenement_id = p_evenement),
    'besoins', (select count(*)::int from inscriptions_evenement i
                where i.evenement_id = p_evenement and i.besoin is not null
                  and i.statut in ('deposee','validee')),
    'categories', coalesce((select jsonb_agg(jsonb_build_object(
        'code', c.code, 'nom', c.nom, 'capacite', c.capacite,
        'horaire', c.horaire, 'externe_admis', c.externe_admis,
        'inscrits', (select count(*)::int from inscriptions_evenement i
                     where i.evenement_id = p_evenement
                       and i.statut in ('deposee','validee')
                       and c.code = any (i.categories)),
        'entrees', (select count(*)::int from entrees_evenement en
                    join inscriptions_evenement i on i.id = en.inscription_id
                    where i.evenement_id = p_evenement and en.categorie = c.code))
        order by c.ordre)
      from evenement_categories c where c.evenement_id = p_evenement), '[]'::jsonb));
$$;

-- L'effacement des données de tiers. À passer périodiquement — ou à la
-- main : ce qui compte est que l'échéance soit posée dès l'inscription.
create or replace function purger_inscriptions_echues()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''administrateur.');
  end if;
  with efface as (
    delete from inscriptions_evenement
     where profil_id is null and efface_le is not null and efface_le < current_date
     returning 1)
  select count(*)::int into v_n from efface;
  return jsonb_build_object('ok', true, 'effacees', v_n);
end $$;

grant execute on function puis_je_tenir_evenement(uuid),
                          enregistrer_evenement(jsonb), regler_categorie(jsonb),
                          changer_statut_evenement(uuid, text, text),
                          inscrire_a_evenement(uuid, text[], text),
                          valider_inscription(uuid, boolean, text),
                          controler_entree(text, text), mes_evenements(text),
                          liste_inscrits(uuid, text), tableau_evenement(uuid),
                          purger_inscriptions_echues()
  to authenticated;

-- ---------------------------------------------------------------------
-- 8. L'APPLICATION
-- ---------------------------------------------------------------------

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction,
                          direction_locale, ordre, droit_requis)
values ('evenements', 'Événements', 'Événements',
        'Création, inscriptions ouvertes, contrôle des entrées, listes.',
        'Réunir, et savoir qui vient.',
        40, true, 'framboise', 'dircom', 'dvie', 35, 'evenements.tenir')
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction, direction_locale = excluded.direction_locale,
      droit_requis = excluded.droit_requis;

-- Ouverte à l'encadrement : s'inscrire et voir les événements de son
-- ressort ne demande pas d'habilitation particulière.
insert into application_visibilite (application, fonction, etat)
select 'evenements', f.code,
       case when f.niveau >= 40 then 'ouverte' else 'sur_demande' end
from fonctions f
on conflict (application, fonction) do nothing;

update applications set delegable_local = true where code = 'evenements';

insert into poste_applications (poste, application) values
  ('evenementiel', 'evenements'), ('dircom', 'evenements'),
  ('charge_com', 'evenements'), ('president_structure', 'evenements')
on conflict do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 47
--
--  Vérifications :
--    select * from mes_evenements('a_venir');
--    select evenement_public('<jeton>');
--    select tableau_evenement('<uuid>');
--
--  Sur les données de tiers : une inscription externe porte une date
--  d'effacement fixée à la création — fin de l'événement plus la durée
--  de conservation, 180 jours par défaut. `purger_inscriptions_echues()`
--  les efface. L'échéance est posée d'emblée précisément pour qu'on
--  n'ait pas à décider plus tard : c'est ce qui distingue une durée de
--  conservation d'un oubli.
--
--  Sur le contrôle des entrées : un double passage n'est pas refusé, il
--  est signalé avec l'heure du premier. Une porte qui refuse sans
--  expliquer crée une file d'attente et un conflit ; une porte qui
--  informe laisse la personne décider.
--
--  Non fait, et à décider : un partenaire n'a pas de compte. Un
--  événement peut lui être rattaché — le fichier des relations
--  extérieures sert de répertoire — mais c'est un membre de la
--  fédération qui le tient. Donner un accès direct à un partenaire
--  supposerait un type de compte nouveau, avec tout ce que cela
--  implique de droits et de RGPD. C'est une décision de gouvernance.
-- =====================================================================
