-- =====================================================================
--  FFCE — Migration 43 — L'ADHÉRENT D'ABORD
--
--  Un adhérent arrivait sur un menu. Un menu ne dit pas ce qui s'est
--  passé, ni ce qu'on attend de lui : il propose des portes. Il arrive
--  désormais sur un fil, composé pour lui — son échelon, sa fonction,
--  son territoire — où chaque élément dit ce qu'il est et ce qu'on peut
--  en faire.
--
--  Et il obtient une carte : son identité fédérale, avec un jeton que
--  l'on scanne pour l'émarger à une assemblée sans passer par une liste
--  papier. Le jeton est révocable, parce qu'une carte se perd.
--
--  Prérequis : 01 à 42.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LA CARTE D'ADHÉRENT
--    Le jeton n'est pas l'identifiant du profil : le divulguer ne donne
--    donc aucun accès au compte. Il se change en un clic si la carte
--    circule là où elle ne devrait pas.
-- ---------------------------------------------------------------------

alter table profils add column if not exists jeton_carte uuid default gen_random_uuid();
create unique index if not exists idx_jeton_carte on profils(jeton_carte);

update profils set jeton_carte = gen_random_uuid() where jeton_carte is null;

create or replace function ma_carte()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'nom', trim(p.prenom || ' ' || p.nom),
    'matricule', p.matricule,
    'jeton', p.jeton_carte,
    'photo_url', p.photo_url,
    'fonction', f.nom,
    'echelon', e.nom,
    'echelon_niveau', p.echelon,
    'territoire', coalesce(t.nom, 'National'),
    'depuis', p.date_adhesion,
    'statut', p.statut,
    'valide', p.statut = 'actif',
    'postes', coalesce((select jsonb_agg(po.nom) from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = p.id and nomination_active(n)), '[]'::jsonb))
  from profils p
  join fonctions f on f.code = p.fonction
  join echelons e on e.niveau = p.echelon
  left join territoires t on t.id = p.territoire_id
  where p.id = auth.uid();
$$;

create or replace function regenerer_jeton_carte()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  v := gen_random_uuid();
  update profils set jeton_carte = v where id = auth.uid();
  return jsonb_build_object('ok', true, 'jeton', v);
end $$;

-- Lire une carte présentée. Réservé à qui tient une liste : on ne
-- transforme pas chaque adhérent en lecteur d'identités.
create or replace function lire_carte(p_jeton text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (est_admin() or a_droit('scrutin.organiser')
                        or a_droit('membres.valider') or mon_niveau() >= 50)
              then jsonb_build_object('ok', false,
                     'message', 'Vous ne relevez pas les identités.')
  else coalesce((
    select jsonb_build_object('ok', true, 'profil_id', p.id,
      'nom', trim(p.prenom || ' ' || p.nom), 'matricule', p.matricule,
      'photo_url', p.photo_url, 'fonction', f.nom,
      'territoire', coalesce(t.nom, 'National'),
      'a_jour', p.statut = 'actif')
    from profils p
    join fonctions f on f.code = p.fonction
    left join territoires t on t.id = p.territoire_id
    where p.jeton_carte = uuid_valide(p_jeton)),
    jsonb_build_object('ok', false, 'message', 'Carte inconnue ou périmée.'))
  end;
$$;

-- Émarger par la carte. L'émargement reste ce qu'il était : une
-- présence constatée, sans aucun lien avec le bulletin.
-- La présence constatée est distincte de l'émargement du scrutin :
-- on peut être présent sans voter, et le quorum se compte sur les
-- présents.
create table if not exists presences_assemblee (
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  profil_id    uuid not null references profils(id) on delete cascade,
  constate_le  timestamptz not null default now(),
  constate_par uuid references profils(id),
  primary key (assemblee_id, profil_id)
);
alter table presences_assemblee enable row level security;
drop policy if exists lire_presences on presences_assemblee;
create policy lire_presences on presences_assemblee for select using (
  profil_id = auth.uid() or est_admin() or a_droit('scrutin.organiser'));
grant select on presences_assemblee to authenticated;

create or replace function emarger_par_carte(p_jeton text, p_assemblee uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_profil uuid; v_nom text;
begin
  if not (est_admin() or a_droit('scrutin.organiser')) then
    return jsonb_build_object('ok', false,
      'message', 'La tenue de l''émargement revient à l''organisateur du scrutin.');
  end if;
  select p.id, trim(p.prenom || ' ' || p.nom) into v_profil, v_nom
    from profils p where p.jeton_carte = uuid_valide(p_jeton) and p.statut = 'actif';
  if v_profil is null then
    return jsonb_build_object('ok', false, 'message', 'Carte inconnue ou compte inactif.');
  end if;
  if not exists (select 1 from corps_electoral(p_assemblee) c
                 where c.profil_id = v_profil) then
    return jsonb_build_object('ok', false,
      'message', v_nom || ' n''appartient pas au corps électoral de cette assemblée.');
  end if;
  if exists (select 1 from votes where assemblee_id = p_assemblee
             and electeur_id = v_profil) then
    return jsonb_build_object('ok', false, 'message', v_nom || ' a déjà émargé.');
  end if;

  insert into presences_assemblee (assemblee_id, profil_id, constate_par)
  values (p_assemblee, v_profil, auth.uid())
  on conflict (assemblee_id, profil_id) do nothing;

  return jsonb_build_object('ok', true, 'membre', v_nom);
end $$;

-- ---------------------------------------------------------------------
-- 2. LE FIL D'ACTUALITÉ
--    Composé pour la personne qui le lit. Chaque élément porte sa
--    nature, sa date, son lien, et ce qu'on peut en faire. Rien n'est
--    stocké : le fil se recompose à chaque lecture.
-- ---------------------------------------------------------------------

drop function if exists fil_actualite(integer);
create or replace function fil_actualite(p_limite integer default 25)
returns table (nature text, titre text, corps text, quand timestamptz,
               lien text, action text, portee text, urgent boolean)
language sql stable security definer set search_path = public as $$
  select * from (
    -- Ce qu'on attend de moi passe avant ce qui s'est passé.
    select 'attente'::text, x.libelle, ''::text, now(), x.lien,
           'Traiter'::text, 'Vous concernant'::text, x.urgence = 'haute'
    from ce_qui_attend() x

    union all
    -- Les actes en vigueur de mon ressort : ce que la fédération a
    -- décidé et qui s'applique à moi.
    select 'acte', a.objet,
           coalesce(a.portee, 'federale') || ' · ' || a.ressort,
           coalesce(a.signe_le, a.cree_le), '#/espace/recueil',
           'Lire au recueil', 'Décisions', false
    from recueil_actes('en_vigueur') a

    union all
    -- Les publications que la fédération veut voir relayées.
    select 'publication', s.titre, coalesce(s.contexte, ''), s.cree_le,
           '#/espace/publier', 'Relayer', 'Communication', false
    from suggestions_disponibles() s
    where not s.je_lai_reprise and mon_niveau() >= 40

    union all
    -- Les assemblées à venir de mon corps électoral.
    select 'assemblee', a.titre,
           'Le ' || to_char(a.date_tenue, 'DD/MM/YYYY') ||
           coalesce(' · ' || a.lieu, '') ||
           case when a.statut = 'scrutin' then ' — scrutin ouvert' else '' end,
           a.date_tenue, '#/espace/assemblees',
           case when a.statut = 'scrutin' and not a.a_vote then 'Voter'
                else 'Consulter' end,
           'Vie statutaire',
           a.statut = 'scrutin' and a.electeur and not a.a_vote
    from mes_assemblees() a
    where a.date_tenue >= now() - interval '7 days'

    union all
    -- Les missions ouvertes que je peux rejoindre.
    select 'mission', m.titre, coalesce(m.lieu, ''),
           coalesce(m.debut::timestamptz, now()), '#/espace/engagement',
           'Se porter volontaire', 'Engagement', false
    from missions_ouvertes() m
    where m.obstacle is null and m.ma_candidature is null

    union all
    -- Les formations nouvellement ouvertes à mon échelon.
    select 'formation', f.titre, coalesce(f.resume, ''), f.cree_le,
           '#/espace/formations', 'Commencer', 'Formation', false
    from formations f
    where f.publiee and f.cree_le > now() - interval '90 days'
      and not exists (select 1 from progression pr
                      join lecons l on l.id = pr.lecon_id
                      join modules m on m.id = l.module_id
                      where pr.profil_id = auth.uid() and m.formation_id = f.id)

    union all
    -- La vie de mon comité.
    select 'projet', p.titre, coalesce(p.objet, ''), p.cree_le,
           '#/espace/comite', 'Rejoindre le projet', 'Ma structure', false
    from projets p
    where p.statut in ('preparation','en_cours')
      and p.territoire_id = (select territoire_id from profils where id = auth.uid())
  ) as f(nature, titre, corps, quand, lien, action, portee, urgent)
  order by urgent desc,
           case nature when 'attente' then 0 when 'assemblee' then 1 else 2 end,
           quand desc
  limit coalesce(p_limite, 25);
$$;

grant execute on function ma_carte(), regenerer_jeton_carte(), lire_carte(text),
                          emarger_par_carte(text, uuid), fil_actualite(integer)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 43
--
--  Vérifications :
--    select ma_carte();
--    select nature, titre, portee, urgent from fil_actualite(25);
--
--  Sur le jeton de carte : il est distinct de l'identifiant du profil.
--  Quelqu'un qui photographie une carte ne peut donc rien en faire
--  d'autre que constater une présence — et seulement s'il tient une
--  liste, ce que `lire_carte` vérifie. Le jeton se régénère si la carte
--  circule là où elle ne devrait pas.
--
--  Sur le fil : ce qu'on attend de la personne passe avant ce qui s'est
--  passé. Un fil qui commencerait par des nouvelles laisserait les
--  demandes en attente sous la ligne de flottaison, et c'est
--  exactement ce qu'on veut éviter.
-- =====================================================================
