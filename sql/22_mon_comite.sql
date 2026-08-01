-- =====================================================================
--  FFCE — Migration 22 — MON COMITÉ
--
--  L'écran de la vie locale directe. Un adhérent n'a pas besoin de
--  comprendre l'organigramme fédéral pour agir : il a besoin de savoir
--  ce qui se passe près de chez lui, qui l'anime, et comment proposer
--  quelque chose.
--
--  Trois notions :
--
--  1. LE COMITÉ, c'est-à-dire mon territoire vu de l'intérieur : son
--     bureau, ses membres, ses actions, son agenda.
--
--  2. LES PROJETS, portés localement, avec leur avancement.
--
--  3. LES PROPOSITIONS. Un adhérent propose, le responsable local
--     décide, et s'il juge l'idée généralisable, il la fait remonter au
--     national. C'est le chemin qui manque dans la plupart des
--     fédérations : les bonnes idées meurent à l'échelon local faute
--     d'un canal pour monter.
--
--  Prérequis : 01 à 21.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PROJETS LOCAUX
-- ---------------------------------------------------------------------

create sequence if not exists seq_projet start 1;

create table if not exists projets (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'P-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_projet')::text, 4, '0'),
  territoire_id uuid not null references territoires(id) on delete cascade,
  titre         text not null,
  objet         text,
  public_vise   text,
  partenaires   text,
  lieu          text,
  debut         date,
  fin           date,
  budget_estime numeric(10,2),
  statut        text not null default 'idee' check (statut in
                  ('idee','preparation','en_cours','termine','abandonne')),
  avancement    integer not null default 0 check (avancement between 0 and 100),
  responsable_id uuid references profils(id) on delete set null,
  groupe_id     uuid references groupes_travail(id) on delete set null,
  origine_proposition uuid,     -- si né d'une proposition d'adhérent
  bilan         text,
  beneficiaires integer,
  cree_par      uuid references profils(id),
  cree_le       timestamptz not null default now(),
  maj_le        timestamptz not null default now()
);
create index if not exists idx_projets_terr on projets(territoire_id, statut);

create table if not exists projet_participants (
  projet_id uuid not null references projets(id) on delete cascade,
  profil_id uuid not null references profils(id) on delete cascade,
  role      text not null default 'participant'
              check (role in ('responsable','participant','interesse')),
  cree_le   timestamptz not null default now(),
  primary key (projet_id, profil_id)
);

-- ---------------------------------------------------------------------
-- 2. PROPOSITIONS
--    Un adhérent propose. Le responsable local décide. Ce qui mérite
--    d'être généralisé remonte au national.
-- ---------------------------------------------------------------------

create sequence if not exists seq_proposition start 1;

create table if not exists propositions (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'PR-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_proposition')::text, 4, '0'),
  auteur_id     uuid not null references profils(id) on delete cascade,
  territoire_id uuid references territoires(id) on delete set null,
  titre         text not null,
  description   text not null,
  besoin        text,          -- ce qu'il faudrait pour la mener
  public_vise   text,
  statut        text not null default 'deposee' check (statut in
                  ('deposee','a_l_etude','retenue','remontee','nationale','ecartee')),
  reponse       text,
  decide_par    uuid references profils(id),
  decide_le     timestamptz,
  projet_id     uuid references projets(id) on delete set null,
  remontee_le   timestamptz,
  remontee_par  uuid references profils(id),
  motif_remontee text,
  soutiens      integer not null default 0,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_propositions on propositions(statut, territoire_id);

create table if not exists proposition_soutiens (
  proposition_id uuid not null references propositions(id) on delete cascade,
  profil_id      uuid not null references profils(id) on delete cascade,
  cree_le        timestamptz not null default now(),
  primary key (proposition_id, profil_id)
);

-- Le compteur se tient à jour tout seul.
create or replace function maj_soutiens()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update propositions set soutiens = (
    select count(*) from proposition_soutiens
    where proposition_id = coalesce(new.proposition_id, old.proposition_id))
  where id = coalesce(new.proposition_id, old.proposition_id);
  return coalesce(new, old);
end $$;

drop trigger if exists trg_soutiens_ins on proposition_soutiens;
create trigger trg_soutiens_ins after insert on proposition_soutiens
  for each row execute function maj_soutiens();
drop trigger if exists trg_soutiens_del on proposition_soutiens;
create trigger trg_soutiens_del after delete on proposition_soutiens
  for each row execute function maj_soutiens();

create or replace function proposer(p_titre text, p_description text,
                                    p_besoin text default null,
                                    p_public text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if coalesce(trim(p_titre),'') = '' or coalesce(trim(p_description),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un titre et une description sont nécessaires.');
  end if;

  insert into propositions (auteur_id, territoire_id, titre, description, besoin, public_vise)
  values (auth.uid(), (select territoire_id from profils where id = auth.uid()),
          trim(p_titre), trim(p_description), nullif(trim(p_besoin),''),
          nullif(trim(p_public),''))
  returning id into v_id;

  -- L'auteur soutient sa propre proposition : cela évite les zéros
  -- décourageants et reflète la réalité.
  insert into proposition_soutiens (proposition_id, profil_id) values (v_id, auth.uid());

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function soutenir(p_proposition uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from proposition_soutiens
             where proposition_id = p_proposition and profil_id = auth.uid()) then
    delete from proposition_soutiens
     where proposition_id = p_proposition and profil_id = auth.uid();
    return jsonb_build_object('ok', true, 'soutien', false);
  end if;
  insert into proposition_soutiens (proposition_id, profil_id)
  values (p_proposition, auth.uid());
  return jsonb_build_object('ok', true, 'soutien', true);
end $$;

-- Le responsable local décide. Il peut retenir, écarter, ou faire
-- remonter — trois gestes distincts, tous motivés.
create or replace function statuer_proposition(p_id uuid, p_statut text,
                                               p_reponse text,
                                               p_creer_projet boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr propositions; v_projet uuid;
begin
  select * into pr from propositions where id = p_id;
  if pr is null then return jsonb_build_object('ok', false, 'message', 'Introuvable.'); end if;

  if not (est_admin() or mon_niveau() >= 50
          or a_droit('structure.animer')
          or dans_mon_perimetre(pr.territoire_id)) then
    return jsonb_build_object('ok', false,
      'message', 'Cette proposition ne relève pas de votre territoire.');
  end if;
  if coalesce(trim(p_reponse),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Répondez à l''auteur : une proposition sans réponse décourage la suivante.');
  end if;

  if coalesce(p_creer_projet, false) and p_statut = 'retenue' then
    insert into projets (territoire_id, titre, objet, public_vise, statut,
                         responsable_id, origine_proposition, cree_par)
    values (coalesce(pr.territoire_id,
              (select territoire_id from profils where id = auth.uid())),
            pr.titre, pr.description, pr.public_vise, 'preparation',
            auth.uid(), pr.id, auth.uid())
    returning id into v_projet;
  end if;

  update propositions
     set statut = p_statut, reponse = trim(p_reponse),
         decide_par = auth.uid(), decide_le = now(),
         projet_id = coalesce(v_projet, projet_id)
   where id = p_id;

  return jsonb_build_object('ok', true, 'projet_id', v_projet);
end $$;

create or replace function faire_remonter(p_id uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr propositions;
begin
  select * into pr from propositions where id = p_id;
  if not (est_admin() or mon_niveau() >= 50 or dans_mon_perimetre(pr.territoire_id)) then
    return jsonb_build_object('ok', false, 'message', 'Hors de votre périmètre.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi cette idée mérite d''être généralisée.');
  end if;

  update propositions
     set statut = 'remontee', remontee_le = now(), remontee_par = auth.uid(),
         motif_remontee = trim(p_motif)
   where id = p_id;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'proposition_remontee', p_id::text,
          jsonb_build_object('titre', pr.titre));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 3. MON COMITÉ
--    Une seule fonction pour tout l'écran : on ne fait pas huit
--    requêtes pour afficher une page d'accueil locale.
-- ---------------------------------------------------------------------

create or replace function mon_comite(p_territoire uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with moi as (
    select coalesce(p_territoire,
      (select territoire_id from profils where id = auth.uid())) as terr),
  perimetre as (select s.id from moi, territoires_sous(moi.terr) s)
  select jsonb_build_object(
    'territoire', (select jsonb_build_object(
        'id', t.id, 'nom', t.nom, 'echelle', t.echelle, 'etat', t.etat,
        'chemin', chemin_territoire(t.id),
        'parent', (select p2.nom from territoires p2 where p2.id = t.parent_id))
      from territoires t, moi where t.id = moi.terr),

    'bureau', coalesce((
      select jsonb_agg(jsonb_build_object(
        'poste', po.nom, 'code', po.code,
        'nom', trim(p.prenom || ' ' || p.nom),
        'profil_id', p.id, 'photo', p.photo_url,
        'depuis', n.debut, 'jusqu_au', n.fin,
        'echelon', p.echelon)
        order by case po.code when 'president_structure' then 1
                              when 'tresorier_structure' then 2
                              when 'secretaire_structure' then 3 else 4 end)
      from nominations n
      join postes po on po.code = n.poste
      join profils p on p.id = n.profil_id
      join moi on moi.terr = n.territoire_id
      where nomination_active(n)
        and po.code like '%_structure'), '[]'::jsonb),

    'encadrement', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nom', trim(p.prenom || ' ' || p.nom), 'profil_id', p.id,
        'fonction', f.nom, 'niveau', f.niveau, 'photo', p.photo_url,
        'territoire', t.nom)
        order by f.niveau desc)
      from profils p
      join fonctions f on f.code = p.fonction
      left join territoires t on t.id = p.territoire_id
      where p.statut = 'actif' and f.niveau >= 40
        and p.territoire_id in (select id from perimetre)), '[]'::jsonb),

    'effectif', (select jsonb_build_object(
        'actifs', count(*) filter (where p.statut = 'actif'),
        'nouveaux_30j', count(*) filter (where p.cree_le > now() - interval '30 days'),
        'heures_mois', coalesce((select sum(e.heures_realisees) from engagements e
          join profils pp on pp.id = e.profil_id
          where pp.territoire_id in (select id from perimetre)
            and e.mois = date_trunc('month', current_date)::date), 0))
      from profils p where p.territoire_id in (select id from perimetre)),

    'projets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pj.id, 'reference', pj.reference, 'titre', pj.titre,
        'objet', pj.objet, 'statut', pj.statut, 'avancement', pj.avancement,
        'debut', pj.debut, 'fin', pj.fin, 'lieu', pj.lieu,
        'responsable', trim(r.prenom || ' ' || r.nom),
        'participants', (select count(*) from projet_participants pp
                         where pp.projet_id = pj.id),
        'je_participe', exists (select 1 from projet_participants pp
                                where pp.projet_id = pj.id and pp.profil_id = auth.uid()))
        order by case pj.statut when 'en_cours' then 1 when 'preparation' then 2
                                when 'idee' then 3 else 4 end, pj.debut nulls last)
      from projets pj
      left join profils r on r.id = pj.responsable_id
      where pj.territoire_id in (select id from perimetre)
        and pj.statut <> 'abandonne'), '[]'::jsonb),

    'agenda', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', x.type, 'titre', x.titre, 'date', x.date, 'lieu', x.lieu,
        'lien', x.lien) order by x.date)
      from (
        select 'mission' as type, m.titre, m.debut::timestamptz as date, m.lieu,
               '#/espace/engagement' as lien
        from missions m
        where m.statut in ('ouverte','complete') and m.debut >= current_date
          and (m.territoire_id is null or m.territoire_id in (select id from perimetre))
        union all
        select 'assemblee', a.titre, a.date_tenue, a.lieu, '#/espace/assemblees'
        from assemblees a
        where a.date_tenue >= now() and a.statut <> 'annulee'
          and a.territoire_id in (select id from perimetre)
        union all
        select 'projet', pj.titre, pj.debut::timestamptz, pj.lieu, '#/espace/comite'
        from projets pj
        where pj.debut >= current_date and pj.statut in ('preparation','en_cours')
          and pj.territoire_id in (select id from perimetre)
      ) x limit 12), '[]'::jsonb),

    'propositions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id, 'reference', pr.reference, 'titre', pr.titre,
        'description', pr.description, 'besoin', pr.besoin,
        'statut', pr.statut, 'soutiens', pr.soutiens, 'reponse', pr.reponse,
        'auteur', trim(a.prenom || ' ' || a.nom),
        'mienne', pr.auteur_id = auth.uid(),
        'je_soutiens', exists (select 1 from proposition_soutiens ps
                               where ps.proposition_id = pr.id and ps.profil_id = auth.uid()),
        'cree_le', pr.cree_le)
        order by pr.soutiens desc, pr.cree_le desc)
      from propositions pr
      join profils a on a.id = pr.auteur_id
      where pr.territoire_id in (select id from perimetre)
        and pr.statut in ('deposee','a_l_etude','retenue','remontee')), '[]'::jsonb),

    'je_pilote', (select mon_niveau() >= 50 or est_admin()
                  or exists (select 1 from nominations n, moi
                             where n.profil_id = auth.uid() and nomination_active(n)
                               and n.territoire_id = moi.terr))
  );
$$;

-- Rejoindre ou quitter un projet.
create or replace function rejoindre_projet(p_projet uuid, p_role text default 'participant')
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from projet_participants
             where projet_id = p_projet and profil_id = auth.uid()) then
    delete from projet_participants
     where projet_id = p_projet and profil_id = auth.uid();
    return jsonb_build_object('ok', true, 'membre', false);
  end if;
  insert into projet_participants (projet_id, profil_id, role)
  values (p_projet, auth.uid(), coalesce(p_role,'participant'));
  return jsonb_build_object('ok', true, 'membre', true);
end $$;

create or replace function enregistrer_projet(
  p_id uuid, p_titre text, p_objet text, p_lieu text,
  p_debut date, p_fin date, p_statut text, p_avancement integer,
  p_public text default null, p_partenaires text default null,
  p_budget numeric default null, p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_terr uuid;
begin
  v_terr := coalesce(p_territoire, (select territoire_id from profils where id = auth.uid()));
  if not (est_admin() or mon_niveau() >= 40 or a_droit('structure.animer')) then
    return jsonb_build_object('ok', false,
      'message', 'La conduite d''un projet relève de l''animation locale.');
  end if;
  if coalesce(trim(p_titre),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le titre est obligatoire.');
  end if;

  if p_id is null then
    insert into projets (territoire_id, titre, objet, lieu, debut, fin, statut,
                         avancement, public_vise, partenaires, budget_estime,
                         responsable_id, cree_par)
    values (v_terr, trim(p_titre), nullif(trim(p_objet),''), nullif(trim(p_lieu),''),
            p_debut, p_fin, coalesce(p_statut,'idee'), coalesce(p_avancement,0),
            nullif(trim(p_public),''), nullif(trim(p_partenaires),''), p_budget,
            auth.uid(), auth.uid())
    returning id into v_id;
    insert into projet_participants (projet_id, profil_id, role)
    values (v_id, auth.uid(), 'responsable');
  else
    update projets set titre = trim(p_titre), objet = nullif(trim(p_objet),''),
           lieu = nullif(trim(p_lieu),''), debut = p_debut, fin = p_fin,
           statut = coalesce(p_statut, statut), avancement = coalesce(p_avancement, avancement),
           public_vise = nullif(trim(p_public),''),
           partenaires = nullif(trim(p_partenaires),''),
           budget_estime = coalesce(p_budget, budget_estime), maj_le = now()
     where id = p_id
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Ce qui remonte au national : les idées jugées généralisables.
create or replace function propositions_remontees()
returns table (id uuid, reference text, titre text, description text, besoin text,
               auteur text, territoire text, soutiens integer,
               remontee_le timestamptz, remontee_par text, motif_remontee text,
               statut text)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.reference, pr.titre, pr.description, pr.besoin,
         trim(a.prenom || ' ' || a.nom), t.nom, pr.soutiens,
         pr.remontee_le, trim(r.prenom || ' ' || r.nom), pr.motif_remontee, pr.statut
  from propositions pr
  join profils a on a.id = pr.auteur_id
  left join territoires t on t.id = pr.territoire_id
  left join profils r on r.id = pr.remontee_par
  where pr.statut in ('remontee','nationale')
    and (est_admin() or mon_niveau() >= 80)
  order by pr.soutiens desc, pr.remontee_le desc;
$$;

-- ---------------------------------------------------------------------
-- 4. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table projets              enable row level security;
alter table projet_participants  enable row level security;
alter table propositions         enable row level security;
alter table proposition_soutiens enable row level security;

drop policy if exists lire_projets on projets;
create policy lire_projets on projets for select using (mon_niveau() >= 10);
drop policy if exists gerer_projets on projets;
create policy gerer_projets on projets for all using (
  responsable_id = auth.uid() or est_admin() or mon_niveau() >= 50
) with check (
  responsable_id = auth.uid() or est_admin() or mon_niveau() >= 40
);

drop policy if exists lire_participants_projet on projet_participants;
create policy lire_participants_projet on projet_participants for select
  using (mon_niveau() >= 10);
drop policy if exists gerer_participants_projet on projet_participants;
create policy gerer_participants_projet on projet_participants for all
  using (profil_id = auth.uid() or est_admin() or mon_niveau() >= 50)
  with check (profil_id = auth.uid() or est_admin() or mon_niveau() >= 50);

drop policy if exists lire_propositions on propositions;
create policy lire_propositions on propositions for select using (mon_niveau() >= 10);
drop policy if exists gerer_propositions on propositions;
create policy gerer_propositions on propositions for update using (
  est_admin() or mon_niveau() >= 50
  or (auteur_id = auth.uid() and statut = 'deposee')
);

drop policy if exists lire_soutiens on proposition_soutiens;
create policy lire_soutiens on proposition_soutiens for select using (mon_niveau() >= 10);

grant select on projets, projet_participants, propositions, proposition_soutiens
  to authenticated;
grant insert, update, delete on projets, projet_participants,
      propositions, proposition_soutiens to authenticated;

grant execute on function proposer(text, text, text, text), soutenir(uuid),
                          statuer_proposition(uuid, text, text, boolean),
                          faire_remonter(uuid, text), mon_comite(uuid),
                          rejoindre_projet(uuid, text),
                          enregistrer_projet(uuid, text, text, text, date, date,
                                             text, integer, text, text, numeric, uuid),
                          propositions_remontees()
  to authenticated;

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, ordre)
values ('comite', 'Mon comité', 'Mon comité',
        'La vie de votre territoire : bureau, projets, agenda, propositions.',
        'Ce qui se passe près de chez vous.',
        10, false, 'action', 8)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      ordre = excluded.ordre;

insert into application_visibilite (application, fonction, etat)
select 'comite', f.code, 'ouverte' from fonctions f
on conflict (application, fonction) do update set etat = 'ouverte';

-- =====================================================================
--  FIN DE LA MIGRATION 22
--
--  Vérifications :
--    select mon_comite();
--    select * from propositions_remontees();
--
--  Sur les propositions : le responsable local doit répondre, même
--  pour écarter. Une proposition sans réponse décourage la suivante,
--  et c'est ainsi qu'un réseau cesse de proposer.
-- =====================================================================
