-- =====================================================================
--  FFCE — Migration 37 — LES AFFAIRES PUBLIQUES
--
--  Une fédération vit de ses relations : collectivités, institutions,
--  entreprises, fondations, autres associations, presse. Ces relations
--  existent aujourd'hui dans des carnets d'adresses personnels, ce qui
--  veut dire qu'elles disparaissent avec ceux qui les tiennent.
--
--  Trois principes ont guidé le dessin.
--
--  LE FICHIER EST FÉDÉRAL, LE PARTAGE EST GRADUÉ. Un contact n'est pas
--  public par défaut. Une structure locale ou un groupe de travail
--  sollicite le service ; celui-ci répond en partageant ce qu'il juge
--  utile — parfois un contact, parfois une liste, parfois rien, avec un
--  motif. Un partage a une portée et peut avoir un terme.
--
--  LES PERSONNES SONT SÉPARÉES DES ORGANISMES. Le nom d'une mairie
--  n'est pas une donnée personnelle ; le portable de son directeur de
--  cabinet en est une. Les deux ne sont donc ni dans la même table, ni
--  soumis à la même règle de lecture.
--
--  TOUT REMONTE AU CABINET. Une note d'affaires publiques rejoint les
--  remontées de la présidence, par le canal déjà en place. On n'en crée
--  pas un second.
--
--  Prérequis : 01 à 36.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DROITS ET LE POSTE
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('ap.tenir',     'Tenir le fichier des relations extérieures', 'Affaires publiques', false, 500),
  ('ap.personnes', 'Accéder aux interlocuteurs nommément',       'Affaires publiques', true,  510),
  ('ap.partager',  'Partager des contacts avec le réseau',       'Affaires publiques', false, 520)
on conflict (code) do update set nom = excluded.nom, sensible = excluded.sensible;

insert into postes (code, nom, description, couleur, systeme, direction, rang) values
  ('affaires_publiques', 'Affaires publiques et partenariats',
   'Tient le fichier des relations extérieures, répond aux sollicitations du réseau, conduit la prospection.',
   'bleu', true, 'dg', 80),
  ('charge_relations', 'Chargé de relations extérieures',
   'Consigne les échanges, prépare les rendez-vous. N''accède pas aux interlocuteurs nommément.',
   'bleu', true, 'dg', 55)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      direction = excluded.direction, rang = excluded.rang;

insert into poste_droits (poste, droit) values
  ('affaires_publiques', 'ap.tenir'),
  ('affaires_publiques', 'ap.personnes'),
  ('affaires_publiques', 'ap.partager'),
  ('charge_relations',   'ap.tenir'),
  ('delegue_admin',      'ap.tenir')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2. LES ORGANISMES
-- ---------------------------------------------------------------------

create table if not exists contacts (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null,
  sigle         text,
  type          text not null default 'autre' check (type in
                  ('collectivite','institution','entreprise','fondation',
                   'association','media','elu','autre')),
  echelle       text not null default 'national' check (echelle in
                  ('national','region','departement','local')),
  territoire_id uuid references territoires(id) on delete set null,
  site          text,
  adresse       text,
  objet         text,                    -- ce qu'il fait, en une phrase
  interet       text,                    -- ce qu'il représente pour nous
  statut        text not null default 'prospect' check (statut in
                  ('prospect','contact_pris','en_relation','partenaire',
                   'sommeil','rompu')),
  -- Une relation peut être délicate : négociation en cours, litige,
  -- personne publique. Le service la garde alors pour lui.
  reserve       boolean not null default false,
  motif_reserve text,
  cree_par      uuid references profils(id),
  maj_le        timestamptz not null default now(),
  cree_le       timestamptz not null default now()
);
create index if not exists idx_contacts_type on contacts(type, statut);
create index if not exists idx_contacts_terr on contacts(territoire_id);

-- Les interlocuteurs. Données personnelles de tiers : lecture
-- strictement réservée, jamais incluse dans un partage.
create table if not exists contact_personnes (
  id         uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts(id) on delete cascade,
  prenom     text,
  nom        text not null,
  fonction   text,
  email      text,
  telephone  text,
  notes      text,
  actif      boolean not null default true,
  cree_le    timestamptz not null default now()
);
create index if not exists idx_cp_contact on contact_personnes(contact_id);

create table if not exists contact_echanges (
  id         uuid primary key default gen_random_uuid(),
  contact_id uuid not null references contacts(id) on delete cascade,
  date_echange date not null default current_date,
  nature     text not null default 'echange' check (nature in
               ('rendez_vous','appel','courriel','courrier','evenement','echange')),
  objet      text not null,
  compte_rendu text,
  suite      text,                       -- ce qu'il faut faire ensuite
  echeance   date,
  par_id     uuid references profils(id),
  cree_le    timestamptz not null default now()
);
create index if not exists idx_ce_contact on contact_echanges(contact_id, date_echange desc);

-- ---------------------------------------------------------------------
-- 3. LE PARTAGE GRADUÉ
--    Un partage vise un territoire ou un groupe de travail, jamais une
--    personne : ce qui est confié l'est à une structure, et survit donc
--    au départ de celui qui l'avait demandé.
-- ---------------------------------------------------------------------

create table if not exists contact_partages (
  id            uuid primary key default gen_random_uuid(),
  contact_id    uuid not null references contacts(id) on delete cascade,
  territoire_id uuid references territoires(id) on delete cascade,
  groupe_id     uuid references groupes_travail(id) on delete cascade,
  portee        text not null default 'fiche' check (portee in ('fiche','echanges')),
  motif         text,
  expire_le     date,
  accorde_par   uuid references profils(id),
  retire_le     timestamptz,
  cree_le       timestamptz not null default now(),
  check (territoire_id is not null or groupe_id is not null)
);
create index if not exists idx_cpart on contact_partages(contact_id);

create table if not exists sollicitations_ap (
  id            uuid primary key default gen_random_uuid(),
  demandeur_id  uuid not null references profils(id) on delete cascade,
  territoire_id uuid references territoires(id) on delete set null,
  groupe_id     uuid references groupes_travail(id) on delete set null,
  objet         text not null,
  besoin        text not null,
  echeance      date,
  statut        text not null default 'deposee' check (statut in
                  ('deposee','instruite','satisfaite','ecartee')),
  reponse       text,
  traite_par    uuid references profils(id),
  traite_le     timestamptz,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_sap on sollicitations_ap(statut, cree_le desc);

-- ---------------------------------------------------------------------
-- 4. LA PROSPECTION
--    Ce qu'on cherche à obtenir, de qui, pour quand. Distinct du
--    fichier : un contact est un fait, une piste est une intention.
-- ---------------------------------------------------------------------

create table if not exists pistes_ap (
  id           uuid primary key default gen_random_uuid(),
  intitule     text not null,
  cible        text,                     -- qui l'on vise
  contact_id   uuid references contacts(id) on delete set null,
  objectif     text not null,            -- ce qu'on cherche à obtenir
  enjeu        text,                     -- pourquoi cela compte
  echeance     date,
  etat         text not null default 'ouverte' check (etat in
                 ('ouverte','en_cours','aboutie','abandonnee')),
  conclusion   text,
  responsable_id uuid references profils(id),
  maj_le       timestamptz not null default now(),
  cree_le      timestamptz not null default now()
);
create index if not exists idx_pistes on pistes_ap(etat, echeance);

-- ---------------------------------------------------------------------
-- 5. QUI VOIT QUOI
-- ---------------------------------------------------------------------

create or replace function ap_service()
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('ap.tenir');
$$;

-- Un contact m'est-il visible ? Soit je tiens le fichier, soit il m'a
-- été partagé — à ma structure ou à un groupe dont je suis membre.
create or replace function contact_visible(p_contact uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select ap_service()
      or exists (
        select 1 from contact_partages cp
        left join contacts c on c.id = cp.contact_id
        where cp.contact_id = p_contact
          and cp.retire_le is null
          and (cp.expire_le is null or cp.expire_le >= current_date)
          and not coalesce(c.reserve, false)
          and (
            (cp.territoire_id is not null and dans_mon_perimetre(cp.territoire_id))
            or (cp.groupe_id is not null and est_membre_gt(cp.groupe_id))
          ));
$$;

alter table contacts          enable row level security;
alter table contact_personnes enable row level security;
alter table contact_echanges  enable row level security;
alter table contact_partages  enable row level security;
alter table sollicitations_ap enable row level security;
alter table pistes_ap         enable row level security;

drop policy if exists lire_contacts on contacts;
create policy lire_contacts on contacts for select using (contact_visible(id));

drop policy if exists gerer_contacts on contacts;
create policy gerer_contacts on contacts for all
  using (ap_service()) with check (ap_service());

-- Les interlocuteurs ne sortent jamais du service : un partage porte
-- sur l'organisme, pas sur les personnes qui y travaillent.
drop policy if exists lire_personnes on contact_personnes;
create policy lire_personnes on contact_personnes for select
  using (est_admin() or a_droit('ap.personnes'));
drop policy if exists gerer_personnes on contact_personnes;
create policy gerer_personnes on contact_personnes for all
  using (est_admin() or a_droit('ap.personnes'))
  with check (est_admin() or a_droit('ap.personnes'));

drop policy if exists lire_echanges on contact_echanges;
create policy lire_echanges on contact_echanges for select using (
  ap_service()
  or exists (select 1 from contact_partages cp
             where cp.contact_id = contact_echanges.contact_id
               and cp.portee = 'echanges' and cp.retire_le is null
               and (cp.expire_le is null or cp.expire_le >= current_date)
               and ((cp.territoire_id is not null and dans_mon_perimetre(cp.territoire_id))
                    or (cp.groupe_id is not null and est_membre_gt(cp.groupe_id)))));
drop policy if exists gerer_echanges on contact_echanges;
create policy gerer_echanges on contact_echanges for all
  using (ap_service()) with check (ap_service());

drop policy if exists lire_partages on contact_partages;
create policy lire_partages on contact_partages for select using (
  ap_service()
  or (territoire_id is not null and dans_mon_perimetre(territoire_id))
  or (groupe_id is not null and est_membre_gt(groupe_id)));

drop policy if exists lire_sollicitations on sollicitations_ap;
create policy lire_sollicitations on sollicitations_ap for select using (
  demandeur_id = auth.uid() or ap_service());

drop policy if exists lire_pistes on pistes_ap;
create policy lire_pistes on pistes_ap for select using (
  ap_service() or responsable_id = auth.uid());
drop policy if exists gerer_pistes on pistes_ap;
create policy gerer_pistes on pistes_ap for all
  using (ap_service()) with check (ap_service());

grant select on contacts, contact_personnes, contact_echanges,
                contact_partages, sollicitations_ap, pistes_ap to authenticated;

-- ---------------------------------------------------------------------
-- 6. TENIR LE FICHIER
-- ---------------------------------------------------------------------

create or replace function enregistrer_contact(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not ap_service() then
    return jsonb_build_object('ok', false,
      'message', 'Le fichier des relations extérieures est tenu par les affaires publiques.');
  end if;
  if coalesce(trim(d->>'nom'),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un contact a un nom.');
  end if;
  if coalesce((d->>'reserve')::boolean, false)
     and coalesce(trim(d->>'motif_reserve'),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Réserver un contact au service se motive : sans quoi la réserve devient l''habitude.');
  end if;

  v_id := uuid_valide(d->>'id');
  if v_id is null then
    insert into contacts (nom, sigle, type, echelle, territoire_id, site, adresse,
                          objet, interet, statut, reserve, motif_reserve, cree_par)
    values (trim(d->>'nom'), nullif(trim(d->>'sigle'),''),
            coalesce(d->>'type','autre'), coalesce(d->>'echelle','national'),
            uuid_valide(d->>'territoire_id'), nullif(trim(d->>'site'),''),
            nullif(trim(d->>'adresse'),''), nullif(trim(d->>'objet'),''),
            nullif(trim(d->>'interet'),''), coalesce(d->>'statut','prospect'),
            coalesce((d->>'reserve')::boolean, false),
            nullif(trim(d->>'motif_reserve'),''), auth.uid())
    returning id into v_id;
  else
    update contacts set
      nom = trim(d->>'nom'), sigle = nullif(trim(d->>'sigle'),''),
      type = coalesce(d->>'type', type), echelle = coalesce(d->>'echelle', echelle),
      territoire_id = uuid_valide(d->>'territoire_id'),
      site = nullif(trim(d->>'site'),''), adresse = nullif(trim(d->>'adresse'),''),
      objet = nullif(trim(d->>'objet'),''), interet = nullif(trim(d->>'interet'),''),
      statut = coalesce(d->>'statut', statut),
      reserve = coalesce((d->>'reserve')::boolean, reserve),
      motif_reserve = nullif(trim(d->>'motif_reserve'),''),
      maj_le = now()
    where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function enregistrer_interlocuteur(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (est_admin() or a_droit('ap.personnes')) then
    return jsonb_build_object('ok', false,
      'message', 'Les interlocuteurs sont des personnes : leur fiche est réservée.');
  end if;
  if coalesce(trim(d->>'nom'),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un interlocuteur a un nom.');
  end if;

  v_id := uuid_valide(d->>'id');
  if v_id is null then
    insert into contact_personnes (contact_id, prenom, nom, fonction, email, telephone, notes)
    values (uuid_valide(d->>'contact_id'), nullif(trim(d->>'prenom'),''),
            trim(d->>'nom'), nullif(trim(d->>'fonction'),''),
            nullif(trim(d->>'email'),''), nullif(trim(d->>'telephone'),''),
            nullif(trim(d->>'notes'),''))
    returning id into v_id;
  else
    update contact_personnes set
      prenom = nullif(trim(d->>'prenom'),''), nom = trim(d->>'nom'),
      fonction = nullif(trim(d->>'fonction'),''), email = nullif(trim(d->>'email'),''),
      telephone = nullif(trim(d->>'telephone'),''), notes = nullif(trim(d->>'notes'),''),
      actif = coalesce((d->>'actif')::boolean, actif)
    where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function consigner_echange(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not ap_service() then
    return jsonb_build_object('ok', false, 'message', 'Vous ne tenez pas ce fichier.');
  end if;
  if coalesce(trim(d->>'objet'),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un échange a un objet.');
  end if;
  insert into contact_echanges (contact_id, date_echange, nature, objet,
                                compte_rendu, suite, echeance, par_id)
  values (uuid_valide(d->>'contact_id'),
          coalesce((d->>'date_echange')::date, current_date),
          coalesce(d->>'nature','echange'), trim(d->>'objet'),
          nullif(trim(d->>'compte_rendu'),''), nullif(trim(d->>'suite'),''),
          (d->>'echeance')::date, auth.uid());
  update contacts set maj_le = now() where id = uuid_valide(d->>'contact_id');
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. SOLLICITER, PARTAGER
-- ---------------------------------------------------------------------

create or replace function solliciter_ap(p_objet text, p_besoin text,
                                         p_groupe uuid default null,
                                         p_echeance date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if mon_niveau() < 40 and not est_admin()
     and not (p_groupe is not null and est_membre_gt(p_groupe)) then
    return jsonb_build_object('ok', false,
      'message', 'Les sollicitations viennent de l''encadrement ou d''un groupe de travail.');
  end if;
  if coalesce(trim(p_objet),'') = '' or coalesce(trim(p_besoin),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites ce que vous cherchez et pourquoi : sans quoi on ne peut rien vous partager d''utile.');
  end if;

  insert into sollicitations_ap (demandeur_id, territoire_id, groupe_id,
                                 objet, besoin, echeance)
  values (auth.uid(), (select territoire_id from profils where id = auth.uid()),
          p_groupe, trim(p_objet), trim(p_besoin), p_echeance);
  return jsonb_build_object('ok', true);
end $$;

-- Partager, c'est confier à une structure ou à un groupe — jamais à une
-- personne. Ce qui est confié survit ainsi au départ de qui l'a demandé.
create or replace function partager_contacts(
  p_contacts uuid[], p_territoire uuid default null, p_groupe uuid default null,
  p_portee text default 'fiche', p_motif text default null,
  p_expire date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c uuid; v_n integer := 0;
begin
  if not (est_admin() or a_droit('ap.partager')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne partagez pas ce fichier.');
  end if;
  if p_territoire is null and p_groupe is null then
    return jsonb_build_object('ok', false,
      'message', 'Un partage vise une structure ou un groupe de travail.');
  end if;

  foreach v_c in array coalesce(p_contacts, '{}') loop
    -- Un contact réservé ne se partage pas : c'est le sens de la réserve.
    if not exists (select 1 from contacts where id = v_c and reserve) then
      insert into contact_partages (contact_id, territoire_id, groupe_id,
                                    portee, motif, expire_le, accorde_par)
      values (v_c, p_territoire, p_groupe, coalesce(p_portee,'fiche'),
              nullif(trim(p_motif),''), p_expire, auth.uid());
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'partages', v_n,
    'ecartes', coalesce(array_length(p_contacts,1),0) - v_n);
end $$;

create or replace function retirer_partage(p_id uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('ap.partager')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne partagez pas ce fichier.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un retrait se motive.');
  end if;
  update contact_partages
     set retire_le = now(), motif = coalesce(motif,'') || ' — retiré : ' || trim(p_motif)
   where id = p_id and retire_le is null;
  return jsonb_build_object('ok', true);
end $$;

create or replace function traiter_sollicitation(p_id uuid, p_statut text,
                                                 p_reponse text,
                                                 p_contacts uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $$
declare s sollicitations_ap; v_res jsonb;
begin
  if not ap_service() then
    return jsonb_build_object('ok', false, 'message', 'Vous ne traitez pas ces demandes.');
  end if;
  select * into s from sollicitations_ap where id = p_id;
  if s is null then
    return jsonb_build_object('ok', false, 'message', 'Sollicitation introuvable.');
  end if;
  if coalesce(trim(p_reponse),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une réponse s''écrit, même quand elle est négative.');
  end if;

  if p_statut = 'satisfaite' and coalesce(array_length(p_contacts,1),0) > 0 then
    v_res := partager_contacts(p_contacts, s.territoire_id, s.groupe_id,
                               'fiche', 'Sollicitation : ' || s.objet, null);
    if not (v_res->>'ok')::boolean then return v_res; end if;
  end if;

  update sollicitations_ap
     set statut = p_statut, reponse = trim(p_reponse),
         traite_par = auth.uid(), traite_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true, 'partages', coalesce(v_res->>'partages','0'));
end $$;

-- ---------------------------------------------------------------------
-- 8. CE QUE L'ON LIT
-- ---------------------------------------------------------------------

drop function if exists v_contacts(text);
create or replace function v_contacts(p_filtre text default 'tous')
returns table (id uuid, nom text, sigle text, type text, statut text,
               echelle text, territoire text, objet text, interet text,
               site text, reserve boolean, interlocuteurs integer,
               dernier_echange date, partages integer, maj_le timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.nom, c.sigle, c.type, c.statut, c.echelle, t.nom,
         c.objet, c.interet, c.site, c.reserve,
         (select count(*)::int from contact_personnes cp
          where cp.contact_id = c.id and cp.actif
            and (est_admin() or a_droit('ap.personnes'))),
         (select max(e.date_echange) from contact_echanges e where e.contact_id = c.id),
         (select count(*)::int from contact_partages x
          where x.contact_id = c.id and x.retire_le is null),
         c.maj_le
  from contacts c
  left join territoires t on t.id = c.territoire_id
  where contact_visible(c.id)
    and case p_filtre
      when 'partenaires' then c.statut = 'partenaire'
      when 'prospects'   then c.statut in ('prospect','contact_pris')
      when 'partages'    then not ap_service()
      else true end
  order by c.statut, c.nom;
$$;

drop function if exists sollicitations_ap_a_traiter(text);
create or replace function sollicitations_ap_a_traiter(p_filtre text default 'ouvertes')
returns table (id uuid, objet text, besoin text, echeance date, statut text,
               demandeur text, fonction text, territoire text, groupe text,
               reponse text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.objet, s.besoin, s.echeance, s.statut,
         trim(p.prenom || ' ' || p.nom), f.nom, t.nom, g.nom, s.reponse, s.cree_le
  from sollicitations_ap s
  join profils p on p.id = s.demandeur_id
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = s.territoire_id
  left join groupes_travail g on g.id = s.groupe_id
  where (s.demandeur_id = auth.uid() or ap_service())
    and case p_filtre
      when 'ouvertes' then s.statut in ('deposee','instruite')
      when 'miennes'  then s.demandeur_id = auth.uid()
      else true end
  order by s.statut, coalesce(s.echeance, s.cree_le::date), s.cree_le;
$$;

create or replace function tableau_ap()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'service', ap_service(),
    'contacts', (select count(*)::int from contacts where contact_visible(id)),
    'partenaires', (select count(*)::int from contacts
                    where statut = 'partenaire' and contact_visible(id)),
    'prospects', (select count(*)::int from contacts
                  where statut in ('prospect','contact_pris') and contact_visible(id)),
    'sollicitations', (select count(*)::int from sollicitations_ap_a_traiter('ouvertes')),
    'pistes_ouvertes', (select count(*)::int from pistes_ap
                        where etat in ('ouverte','en_cours')),
    'pistes_echues', (select count(*)::int from pistes_ap
                      where etat in ('ouverte','en_cours')
                        and echeance is not null and echeance < current_date),
    -- Une suite annoncée et jamais tenue est le premier signe qu'une
    -- relation s'éteint.
    'suites_en_retard', (select count(*)::int from contact_echanges
                         where suite is not null and echeance is not null
                           and echeance < current_date and ap_service()),
    'partages_actifs', (select count(*)::int from contact_partages
                        where retire_le is null
                          and (expire_le is null or expire_le >= current_date)));
$$;

create or replace function enregistrer_piste(d jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not ap_service() then
    return jsonb_build_object('ok', false, 'message', 'La prospection revient au service.');
  end if;
  if coalesce(trim(d->>'intitule'),'') = '' or coalesce(trim(d->>'objectif'),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Une piste dit ce qu''on cherche à obtenir. Sans objectif, ce n''est qu''une intention.');
  end if;

  v_id := uuid_valide(d->>'id');
  if v_id is null then
    insert into pistes_ap (intitule, cible, contact_id, objectif, enjeu,
                           echeance, etat, responsable_id)
    values (trim(d->>'intitule'), nullif(trim(d->>'cible'),''),
            uuid_valide(d->>'contact_id'), trim(d->>'objectif'),
            nullif(trim(d->>'enjeu'),''), (d->>'echeance')::date,
            coalesce(d->>'etat','ouverte'), auth.uid())
    returning id into v_id;
  else
    update pistes_ap set
      intitule = trim(d->>'intitule'), cible = nullif(trim(d->>'cible'),''),
      contact_id = uuid_valide(d->>'contact_id'), objectif = trim(d->>'objectif'),
      enjeu = nullif(trim(d->>'enjeu'),''), echeance = (d->>'echeance')::date,
      etat = coalesce(d->>'etat', etat), conclusion = nullif(trim(d->>'conclusion'),''),
      maj_le = now()
    where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

grant execute on function ap_service(), contact_visible(uuid),
                          enregistrer_contact(jsonb), enregistrer_interlocuteur(jsonb),
                          consigner_echange(jsonb), solliciter_ap(text, text, uuid, date),
                          partager_contacts(uuid[], uuid, uuid, text, text, date),
                          retirer_partage(uuid, text),
                          traiter_sollicitation(uuid, text, text, uuid[]),
                          v_contacts(text), sollicitations_ap_a_traiter(text),
                          tableau_ap(), enregistrer_piste(jsonb)
  to authenticated;

-- ---------------------------------------------------------------------
-- 9. L'APPLICATION
-- ---------------------------------------------------------------------

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre,
                          droit_requis)
values ('affaires_publiques', 'Affaires publiques', 'Affaires publiques',
        'Fichier des relations extérieures, sollicitations du réseau, prospection.',
        'Ce que la fédération a tissé, et avec qui.',
        40, true, 'bleu', 'dg', 18, 'ap.tenir')
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction, droit_requis = excluded.droit_requis;

-- Invisible par défaut : c'est le poste qui l'ouvre. Elle reste
-- demandable au guichet à partir de l'encadrement, pour que celui qui
-- reçoit un partage sache où le lire.
insert into application_visibilite (application, fonction, etat)
select 'affaires_publiques', f.code,
       case when f.code = 'admin' then 'ouverte'
            when f.niveau >= 40 then 'sur_demande'
            else 'invisible' end
from fonctions f
on conflict (application, fonction) do nothing;

insert into poste_applications (poste, application) values
  ('affaires_publiques', 'affaires_publiques'),
  ('charge_relations', 'affaires_publiques')
on conflict do nothing;

-- =====================================================================
--  FIN DE LA MIGRATION 37
--
--  Pour désigner le responsable des affaires publiques :
--    select nommer((select id from profils where email='…'),
--                  'affaires_publiques', null, null, 'Désigné le …');
--
--  Vérifications :
--    select tableau_ap();
--    select nom, statut, partages from v_contacts('tous');
--    select * from sollicitations_ap_a_traiter('ouvertes');
--
--  Sur la séparation des personnes et des organismes : un partage porte
--  sur l'organisme et son objet, jamais sur les personnes qui y
--  travaillent. Le droit `ap.personnes` est marqué sensible : il pèse
--  donc dans la garde hiérarchique et ne se confère pas localement.
--
--  Sur la réserve : un contact réservé n'apparaît dans aucun partage,
--  même consenti par erreur — la fonction de partage l'écarte
--  silencieusement et le compte à part. Réserver se motive, sans quoi
--  la réserve devient l'habitude et le fichier redevient un carnet
--  personnel.
-- =====================================================================
