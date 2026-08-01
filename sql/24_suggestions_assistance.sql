-- =====================================================================
--  FFCE — Migration 24 — SUGGESTIONS DE PUBLICATION ET ASSISTANCE
--
--  1. LES SUGGESTIONS. La direction de la communication prépare des
--     publications prêtes à l'emploi, que chaque équipe locale adapte
--     et publie sur ses propres réseaux. C'est ce qui permet à une
--     fédération de parler d'une seule voix sans que le national ait à
--     tout écrire — et ce qui évite qu'une équipe locale publie seule
--     quelque chose de maladroit.
--
--  2. LES OUTILS. Canva, Drive, banques d'images : les liens vivent
--     dans la plateforme plutôt que dans un pense-bête.
--
--  3. L'ASSISTANCE. Signaler devient un geste rapide, avec un degré
--     d'urgence honnête et un fil de discussion.
--
--  Prérequis : 01 à 23.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. SUGGESTIONS DE PUBLICATION
-- ---------------------------------------------------------------------

create sequence if not exists seq_suggestion start 1;

create table if not exists suggestions_com (
  id            uuid primary key default gen_random_uuid(),
  reference     text unique not null default 'S-' || to_char(now(),'YYYY') || '-' ||
                              lpad(nextval('seq_suggestion')::text, 3, '0'),
  titre         text not null,
  contexte      text,               -- pourquoi cette publication, maintenant
  texte         text not null,      -- le contenu, avec des [crochets] à remplir
  canaux        text[] not null default array['instagram','facebook','linkedin'],
  visuel        text,               -- image prête, dépôt public
  lien_canva    text,               -- modèle à dupliquer
  hashtags      text,
  a_publier_le  date,
  expire_le     date,
  territoire_id uuid references territoires(id) on delete set null,
  campagne_id   uuid references campagnes(id) on delete set null,
  consignes     text,               -- ce qu'il ne faut pas faire
  priorite      text not null default 'normale'
                  check (priorite in ('normale','importante','urgente')),
  statut        text not null default 'active'
                  check (statut in ('brouillon','active','archivee')),
  cree_par      uuid references profils(id),
  cree_le       timestamptz not null default now()
);
create index if not exists idx_sugg_statut on suggestions_com(statut, a_publier_le);

-- Qui l'a reprise, où, et quand : la direction sait ce qui vit.
create table if not exists suggestions_reprises (
  id            uuid primary key default gen_random_uuid(),
  suggestion_id uuid not null references suggestions_com(id) on delete cascade,
  profil_id     uuid not null references profils(id) on delete cascade,
  territoire_id uuid references territoires(id),
  canal         text,
  publie_le     timestamptz not null default now(),
  lien          text,
  observation   text
);

create or replace function creer_suggestion(
  p_titre text, p_contexte text, p_texte text, p_canaux text[],
  p_visuel text default null, p_canva text default null,
  p_hashtags text default null, p_publier_le date default null,
  p_expire_le date default null, p_consignes text default null,
  p_priorite text default 'normale', p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (a_droit('com.valider') or a_droit('com.rediger') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la communication.');
  end if;
  if coalesce(trim(p_titre),'') = '' or coalesce(trim(p_texte),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un titre et un texte sont nécessaires.');
  end if;

  insert into suggestions_com (titre, contexte, texte, canaux, visuel, lien_canva,
                               hashtags, a_publier_le, expire_le, consignes,
                               priorite, territoire_id, cree_par,
                               statut)
  values (trim(p_titre), nullif(trim(p_contexte),''), trim(p_texte),
          coalesce(p_canaux, array['instagram','facebook','linkedin']),
          nullif(p_visuel,''), nullif(trim(p_canva),''), nullif(trim(p_hashtags),''),
          p_publier_le, p_expire_le, nullif(trim(p_consignes),''),
          coalesce(p_priorite,'normale'), p_territoire, auth.uid(),
          case when a_droit('com.valider') or est_admin() then 'active' else 'brouillon' end)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function declarer_reprise(p_suggestion uuid, p_canal text,
                                            p_lien text default null,
                                            p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  insert into suggestions_reprises (suggestion_id, profil_id, territoire_id,
                                    canal, lien, observation)
  values (p_suggestion, auth.uid(),
          (select territoire_id from profils where id = auth.uid()),
          p_canal, nullif(trim(p_lien),''), nullif(trim(p_observation),''));
  return jsonb_build_object('ok', true);
end $$;

-- Ce que je vois : les suggestions actives qui concernent mon territoire.
create or replace function suggestions_disponibles()
returns table (id uuid, reference text, titre text, contexte text, texte text,
               canaux text[], visuel text, lien_canva text, hashtags text,
               a_publier_le date, expire_le date, consignes text, priorite text,
               campagne text, territoire text, auteur text,
               reprises integer, je_lai_reprise boolean, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.reference, s.titre, s.contexte, s.texte, s.canaux, s.visuel,
         s.lien_canva, s.hashtags, s.a_publier_le, s.expire_le, s.consignes,
         s.priorite, c.titre, t.nom, trim(p.prenom || ' ' || p.nom),
         (select count(*)::int from suggestions_reprises r where r.suggestion_id = s.id),
         exists (select 1 from suggestions_reprises r
                 where r.suggestion_id = s.id and r.profil_id = auth.uid()),
         s.cree_le
  from suggestions_com s
  left join campagnes c on c.id = s.campagne_id
  left join territoires t on t.id = s.territoire_id
  left join profils p on p.id = s.cree_par
  where s.statut = 'active'
    and (s.expire_le is null or s.expire_le >= current_date)
    and mon_niveau() >= 10
    -- Une suggestion ciblée ne s'affiche que sur son périmètre.
    and (s.territoire_id is null
         or (select territoire_id from profils where id = auth.uid())
            in (select x.id from territoires_sous(s.territoire_id) x))
  order by
    case s.priorite when 'urgente' then 1 when 'importante' then 2 else 3 end,
    s.a_publier_le nulls last, s.cree_le desc;
$$;

-- Le suivi, côté direction de la communication.
create or replace function suivi_suggestions()
returns table (id uuid, reference text, titre text, priorite text, statut text,
               a_publier_le date, reprises integer, territoires text,
               canaux_utilises text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.reference, s.titre, s.priorite, s.statut, s.a_publier_le,
         (select count(*)::int from suggestions_reprises r where r.suggestion_id = s.id),
         (select string_agg(distinct t.nom, ', ') from suggestions_reprises r
          left join territoires t on t.id = r.territoire_id
          where r.suggestion_id = s.id),
         (select string_agg(distinct r.canal, ', ') from suggestions_reprises r
          where r.suggestion_id = s.id),
         s.cree_le
  from suggestions_com s
  where a_droit('com.rediger') or a_droit('com.valider') or est_admin()
  order by s.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 2. OUTILS DE LA COMMUNICATION
--    Les liens vivent dans la plateforme, pas dans un pense-bête.
-- ---------------------------------------------------------------------

create table if not exists outils_com (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null,
  url         text not null,
  description text,
  categorie   text not null default 'creation',
  ordre       integer not null default 100,
  actif       boolean not null default true
);

insert into outils_com (nom, url, description, categorie, ordre)
select v.n, v.u, v.d, v.c, v.o from (values
  ('Canva — modèles FFCE', 'https://www.canva.com/',
   'Les gabarits aux couleurs de la fédération. Dupliquez, adaptez, exportez.',
   'creation', 10),
  ('Drive — banque d''images', 'https://drive.google.com/',
   'Photos libres de droits de nos actions, classées par thème et par territoire.',
   'ressources', 20),
  ('Charte graphique', '#/espace/communication',
   'Couleurs, typographies et règles d''usage du logo.', 'ressources', 30),
  ('Logos et déclinaisons', 'https://drive.google.com/',
   'Le logo aux formats PNG et SVG, fond clair et fond sombre.', 'ressources', 40),
  ('Autorisation de droit à l''image', 'https://drive.google.com/',
   'Le formulaire à faire signer avant toute photo de mineur. Sans exception.',
   'juridique', 50)
) as v(n,u,d,c,o)
where not exists (select 1 from outils_com);

-- ---------------------------------------------------------------------
-- 3. ASSISTANCE : SIGNALER PLUS VITE ET MIEUX
-- ---------------------------------------------------------------------

alter table tickets add column if not exists urgent boolean not null default false;
alter table tickets add column if not exists contexte jsonb;
alter table tickets add column if not exists vu_par_auteur_le timestamptz;

create or replace function ouvrir_ticket(
  p_nature text, p_titre text, p_description text, p_page text default null,
  p_importance text default 'normale', p_urgent boolean default false,
  p_contexte jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ref text;
begin
  if (select statut from profils where id = auth.uid())
     not in ('actif','en_attente','suspendu') then
    return jsonb_build_object('ok', false, 'message', 'Compte inactif.');
  end if;
  if coalesce(trim(p_titre),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Dites en une ligne ce qui se passe.');
  end if;

  insert into tickets (auteur_id, nature, titre, description, page, importance,
                       urgent, contexte)
  values (auth.uid(), coalesce(p_nature,'probleme'), trim(p_titre),
          coalesce(nullif(trim(p_description),''), trim(p_titre)),
          nullif(trim(p_page),''),
          -- L'urgence déclarée relève l'importance sans la laisser au maximum :
          -- c'est la direction qui juge du bloquant.
          case when coalesce(p_urgent,false) then 'haute'
               else coalesce(p_importance,'normale') end,
          coalesce(p_urgent,false), p_contexte)
  returning id, reference into v_id, v_ref;

  return jsonb_build_object('ok', true, 'id', v_id, 'reference', v_ref);
end $$;

-- Le fil d'échange d'un signalement.
create or replace function fil_ticket(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not exists (
      select 1 from tickets t where t.id = p_id
        and (t.auteur_id = auth.uid() or t.assigne_a = auth.uid()
             or est_admin() or a_droit('acces.piloter')))
    then jsonb_build_object('erreur', 'Ce signalement ne vous concerne pas.')
    else jsonb_build_object(
      'ticket', (select to_jsonb(t) from tickets t where t.id = p_id),
      'auteur', (select trim(p.prenom || ' ' || p.nom) from tickets t
                 join profils p on p.id = t.auteur_id where t.id = p_id),
      'assigne', (select trim(p.prenom || ' ' || p.nom) from tickets t
                  join profils p on p.id = t.assigne_a where t.id = p_id),
      'messages', coalesce((
        select jsonb_agg(jsonb_build_object(
          'contenu', m.contenu, 'cree_le', m.cree_le,
          'auteur', trim(p.prenom || ' ' || p.nom),
          'moi', m.auteur_id = auth.uid()) order by m.cree_le)
        from ticket_messages m join profils p on p.id = m.auteur_id
        where m.ticket_id = p_id), '[]'::jsonb))
    end;
$$;

-- Ce que la direction doit voir en premier.
create or replace function tickets_urgents()
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from tickets
  where statut not in ('resolu','refuse')
    and (urgent or importance in ('haute','bloquante'))
    and (est_admin() or a_droit('acces.piloter'));
$$;

-- ---------------------------------------------------------------------
-- 4. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table suggestions_com      enable row level security;
alter table suggestions_reprises enable row level security;
alter table outils_com           enable row level security;

drop policy if exists lire_suggestions on suggestions_com;
create policy lire_suggestions on suggestions_com for select using (
  (statut = 'active' and mon_niveau() >= 10)
  or a_droit('com.rediger') or a_droit('com.valider') or est_admin()
);
drop policy if exists gerer_suggestions on suggestions_com;
create policy gerer_suggestions on suggestions_com for all
  using (a_droit('com.valider') or cree_par = auth.uid())
  with check (a_droit('com.rediger') or a_droit('com.valider'));

drop policy if exists lire_reprises on suggestions_reprises;
create policy lire_reprises on suggestions_reprises for select using (
  profil_id = auth.uid() or a_droit('com.rediger') or a_droit('com.valider') or est_admin()
);

drop policy if exists lire_outils on outils_com;
create policy lire_outils on outils_com for select using (mon_niveau() >= 10);
drop policy if exists gerer_outils on outils_com;
create policy gerer_outils on outils_com for all
  using (a_droit('com.valider')) with check (a_droit('com.valider'));

grant select on suggestions_com, suggestions_reprises, outils_com to authenticated;
grant insert, update, delete on suggestions_com, suggestions_reprises,
      outils_com to authenticated;

grant execute on function creer_suggestion(text, text, text, text[], text, text,
                                           text, date, date, text, text, uuid),
                          declarer_reprise(uuid, text, text, text),
                          suggestions_disponibles(), suivi_suggestions(),
                          ouvrir_ticket(text, text, text, text, text, boolean, jsonb),
                          fil_ticket(uuid), tickets_urgents()
  to authenticated;

-- L'espace de publication, ouvert à toute l'animation locale.
insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre)
values ('publier', 'Publier localement', 'Publier',
        'Des publications prêtes à adapter pour vos réseaux, et les outils pour les créer.',
        'Parler d''une seule voix, depuis chaque territoire.',
        40, false, 'framboise', 'dircom', 87)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction;

insert into application_visibilite (application, fonction, etat)
select 'publier', f.code, case when f.niveau >= 40 then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do update
  set etat = case when (select niveau from fonctions
                        where code = application_visibilite.fonction) >= 40
                  then 'ouverte' else 'invisible' end;

-- =====================================================================
--  FIN DE LA MIGRATION 24
--
--  Vérifications :
--    select * from suggestions_disponibles();
--    select * from suivi_suggestions();
--
--  Sur les suggestions : le texte contient des [crochets] à remplir par
--  l'équipe locale. C'est délibéré — une publication identique partout
--  sonne faux, et une publication entièrement libre dérive. Le crochet
--  est le juste milieu : la structure vient du national, les faits du
--  terrain.
-- =====================================================================
