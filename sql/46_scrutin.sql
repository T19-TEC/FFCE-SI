-- =====================================================================
--  FFCE — Migration 46 — LE SCRUTIN TENU CORRECTEMENT
--
--  Cinq manques, tous du même ordre : ce qui se fait sur une table avec
--  du papier n'avait pas d'équivalent ici.
--
--  1. LES POUVOIRS NE S'EXERÇAIENT PAS. La migration 45 permet de
--     donner pouvoir ; personne ne pouvait s'en servir. Un mandataire
--     dépose désormais un bulletin par mandant, et chaque mandant est
--     émargé — c'est ainsi que les voix se comptent, et c'est ce qui
--     empêche un mandant de voter ensuite lui-même.
--
--  2. AUCUNE PREUVE D'AVOIR VOTÉ. Un électeur n'avait rien à opposer si
--     l'on prétendait qu'il n'avait pas voté. Il obtient un récépissé
--     d'émargement : horodaté, vérifiable par un tiers, et qui ne dit
--     RIEN de son choix. Un récépissé qui prouverait le vote détruirait
--     le secret du scrutin — c'est ce qui rend l'achat de voix possible.
--
--  3. LA DOUBLE CLÉ NE BLOQUAIT RIEN. Deux signatures sont maintenant
--     exigées pour proclamer.
--
--  4. NI FEUILLE DE PRÉSENCE NI PROCÈS-VERBAL. Les deux se composent à
--     la lecture, à partir de ce qui existe déjà.
--
--  5. LE QUORUM IGNORAIT LES POUVOIRS. Un mandant représenté est
--     présent au sens statutaire.
--
--  Prérequis : 01 à 45.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE RÉCÉPISSÉ D'ÉMARGEMENT
--    Il atteste d'une participation, jamais d'un contenu. L'empreinte
--    porte sur l'émargement — assemblée, électeur, horodatage — et sur
--    rien d'autre : il est donc impossible d'en déduire un bulletin.
-- ---------------------------------------------------------------------

alter table votes add column if not exists recepisse text;
alter table votes add column if not exists pouvoirs_exerces integer not null default 0;

create or replace function empreinte_emargement(p_assemblee uuid, p_electeur uuid,
                                                p_quand timestamptz)
returns text language sql immutable as $$
  select upper(substr(encode(digest(
    p_assemblee::text || '|' || p_electeur::text || '|' ||
    to_char(p_quand at time zone 'UTC', 'YYYYMMDD"T"HH24MISS'), 'sha256'), 'hex'), 1, 16));
$$;

-- Le récépissé de l'électeur : ce qu'il peut montrer.
create or replace function mon_recepisse(p_assemblee uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when v.id is null then jsonb_build_object('ok', false,
                'message', 'Vous n''avez pas émargé à cette assemblée.')
  else jsonb_build_object(
    'ok', true,
    'reference', a.reference,
    'assemblee', a.titre,
    'date', a.date_tenue,
    'electeur', trim(p.prenom || ' ' || p.nom),
    'matricule', p.matricule,
    'emarge_le', v.cree_le,
    'pouvoirs_exerces', v.pouvoirs_exerces,
    'empreinte', coalesce(v.recepisse,
                          empreinte_emargement(a.id, p.id, v.cree_le)),
    'mention', 'Ce récépissé atteste d''une participation au scrutin. '
             || 'Il ne comporte aucune indication du vote exprimé, et n''en '
             || 'permet aucune déduction.')
  end
  from assemblees a
  join profils p on p.id = auth.uid()
  left join votes v on v.assemblee_id = a.id and v.electeur_id = auth.uid()
  where a.id = p_assemblee;
$$;

-- La vérification par un tiers : on donne une empreinte, on obtient
-- oui ou non. Aucun nom n'en sort si l'empreinte est fausse.
create or replace function verifier_recepisse(p_assemblee uuid, p_empreinte text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('ok', true, 'valide', true,
      'assemblee', a.titre, 'date', a.date_tenue,
      'electeur', trim(p.prenom || ' ' || p.nom),
      'emarge_le', v.cree_le)
    from votes v
    join assemblees a on a.id = v.assemblee_id
    join profils p on p.id = v.electeur_id
    where v.assemblee_id = p_assemblee
      and coalesce(v.recepisse, empreinte_emargement(v.assemblee_id, v.electeur_id, v.cree_le))
          = upper(trim(p_empreinte))
      and (est_admin() or a_droit('scrutin.organiser') or v.electeur_id = auth.uid())),
    jsonb_build_object('ok', true, 'valide', false,
      'message', 'Aucun émargement ne correspond à cette empreinte.'));
$$;

-- ---------------------------------------------------------------------
-- 2. VOTER, POUR SOI ET POUR CEUX QUI ONT DONNÉ POUVOIR
--    Un mandataire dépose un bulletin par voix qu'il porte. Les
--    mandants sont émargés au même instant : leur voix est exprimée,
--    ils ne peuvent plus voter eux-mêmes.
-- ---------------------------------------------------------------------

create or replace function voter(p_assemblee uuid, p_choix jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; v_poste text; v_cand text; v_id uuid;
        v_quand timestamptz; v_pouvoirs uuid[]; v_m uuid; v_n integer;
begin
  select * into a from assemblees where id = p_assemblee;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.');
  end if;
  if a.statut <> 'scrutin' then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin n''est pas ouvert.');
  end if;
  if a.cloture_scrutin is not null and a.cloture_scrutin < now() then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin est clos.');
  end if;
  if not suis_je_electeur(p_assemblee) then
    return jsonb_build_object('ok', false,
      'message', 'Vous n''appartenez pas au corps électoral.');
  end if;
  if exists (select 1 from votes where assemblee_id = p_assemblee
             and electeur_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Vous avez déjà voté.');
  end if;

  -- Les pouvoirs valides dont les mandants n'ont pas encore émargé.
  select coalesce(array_agg(pa.mandant_id), '{}') into v_pouvoirs
  from pouvoirs_ag pa
  where pa.assemblee_id = p_assemblee and pa.mandataire_id = auth.uid()
    and pa.statut = 'valide'
    and not exists (select 1 from votes v where v.assemblee_id = p_assemblee
                    and v.electeur_id = pa.mandant_id);
  v_n := coalesce(array_length(v_pouvoirs, 1), 0);
  v_quand := now();

  -- L'émargement d'abord : il engage l'électeur et ceux qu'il représente.
  insert into votes (assemblee_id, electeur_id, cree_le, pouvoirs_exerces)
  values (p_assemblee, auth.uid(), v_quand, v_n);
  update votes set recepisse = empreinte_emargement(p_assemblee, auth.uid(), v_quand)
   where assemblee_id = p_assemblee and electeur_id = auth.uid();

  foreach v_m in array v_pouvoirs loop
    insert into votes (assemblee_id, electeur_id, cree_le)
    values (p_assemblee, v_m, v_quand)
    on conflict do nothing;
    update votes set recepisse = empreinte_emargement(p_assemblee, v_m, v_quand)
     where assemblee_id = p_assemblee and electeur_id = v_m;
  end loop;

  -- Puis les bulletins, sans aucun lien avec les électeurs. Autant de
  -- bulletins que de voix portées.
  for v_poste, v_cand in select key, value #>> '{}' from jsonb_each(p_choix) loop
    v_id := case when v_cand = 'blanc' then null else uuid_valide(v_cand) end;
    if v_id is not null and not exists (
         select 1 from candidatures c
          where c.id = v_id and c.assemblee_id = p_assemblee and c.poste = v_poste) then
      v_id := null;
    end if;
    for i in 0 .. v_n loop
      insert into bulletins (assemblee_id, poste, candidature_id, blanc)
      values (p_assemblee, v_poste, v_id, v_id is null);
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'voix', v_n + 1,
    'empreinte', empreinte_emargement(p_assemblee, auth.uid(), v_quand));
end $$;

-- Ce que je porte : ma voix, et celles qu'on m'a confiées.
create or replace function mes_voix(p_assemblee uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'electeur', suis_je_electeur(p_assemblee),
    'a_vote', exists (select 1 from votes v where v.assemblee_id = p_assemblee
                      and v.electeur_id = auth.uid()),
    'mandants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nom', trim(m.prenom || ' ' || m.nom), 'matricule', m.matricule,
        'a_vote', exists (select 1 from votes v where v.assemblee_id = p_assemblee
                          and v.electeur_id = pa.mandant_id)))
      from pouvoirs_ag pa join profils m on m.id = pa.mandant_id
      where pa.assemblee_id = p_assemblee and pa.mandataire_id = auth.uid()
        and pa.statut = 'valide'), '[]'::jsonb),
    'mon_mandataire', (
      select trim(t.prenom || ' ' || t.nom) from pouvoirs_ag pa
      join profils t on t.id = pa.mandataire_id
      where pa.assemblee_id = p_assemblee and pa.mandant_id = auth.uid()
        and pa.statut = 'valide'));
$$;

-- ---------------------------------------------------------------------
-- 3. LA FEUILLE DE PRÉSENCE
--    Présent, représenté, absent. Un membre représenté est présent au
--    sens statutaire : c'est tout l'objet d'un pouvoir.
-- ---------------------------------------------------------------------

drop function if exists feuille_presence(uuid);
create or replace function feuille_presence(p_assemblee uuid)
returns table (profil_id uuid, membre text, matricule text, fonction text,
               territoire text, etat text, mandataire text,
               emarge_le timestamptz, constate_le timestamptz)
language sql stable security definer set search_path = public as $$
  select c.profil_id, c.membre, p.matricule, f.nom, t.nom,
         case
           when pr.profil_id is not null then 'present'
           when po.mandataire_id is not null then 'represente'
           when v.electeur_id is not null then 'a_vote'
           else 'absent' end,
         trim(md.prenom || ' ' || md.nom),
         v.cree_le, pr.constate_le
  from corps_electoral(p_assemblee) c
  join profils p on p.id = c.profil_id
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  left join presences_assemblee pr
         on pr.assemblee_id = p_assemblee and pr.profil_id = c.profil_id
  left join votes v on v.assemblee_id = p_assemblee and v.electeur_id = c.profil_id
  left join pouvoirs_ag po on po.assemblee_id = p_assemblee
         and po.mandant_id = c.profil_id and po.statut = 'valide'
  left join profils md on md.id = po.mandataire_id
  where est_admin() or a_droit('scrutin.organiser') or a_droit('scrutin.proclamer')
  order by p.nom, p.prenom;
$$;

-- Le quorum compte les présents, les représentés et les votants.
create or replace function participation(p_assemblee uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (select count(*)::int n from corps_electoral(p_assemblee)),
  pres as (select count(*)::int n from presences_assemblee
           where assemblee_id = p_assemblee),
  vot as (select count(*)::int n from votes where assemblee_id = p_assemblee),
  repr as (select count(*)::int n from pouvoirs_ag
           where assemblee_id = p_assemblee and statut = 'valide'),
  compte as (
    select count(distinct x)::int n from (
      select profil_id x from presences_assemblee where assemblee_id = p_assemblee
      union
      select electeur_id from votes where assemblee_id = p_assemblee
      union
      select mandant_id from pouvoirs_ag
       where assemblee_id = p_assemblee and statut = 'valide') s)
  select jsonb_build_object(
    'inscrits', (select n from c),
    'presents', (select n from pres),
    'representes', (select n from repr),
    'votants', (select n from vot),
    'comptes', (select n from compte),
    'participation', case when (select n from c) = 0 then 0
      else round((select n from compte)::numeric * 100 / (select n from c)) end,
    'quorum_requis', (select quorum_requis from assemblees where id = p_assemblee),
    'quorum_atteint', case when (select n from c) = 0 then false else
      round((select n from compte)::numeric * 100 / (select n from c))
      >= (select quorum_requis from assemblees where id = p_assemblee) end);
$$;

-- ---------------------------------------------------------------------
-- 4. LE PROCÈS-VERBAL
--    Composé à la lecture. Il porte les résultats, la participation, la
--    feuille de présence en nombre, et les deux signataires du
--    dépouillement. Aucun bulletin nominatif n'y figure : il n'en
--    existe pas.
-- ---------------------------------------------------------------------

create or replace function projet_pv(p_assemblee uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (est_admin() or a_droit('scrutin.organiser')
                        or a_droit('scrutin.proclamer'))
    then jsonb_build_object('ok', false, 'message', 'Réservé au bureau de vote.')
  else jsonb_build_object(
    'ok', true,
    'reference', a.reference,
    'titre', a.titre,
    'type', a.type,
    'date', a.date_tenue,
    'lieu', a.lieu,
    'territoire', coalesce(t.nom, 'National'),
    'statut', a.statut,
    'participation', participation(p_assemblee),
    'presents', coalesce((select jsonb_agg(jsonb_build_object(
        'membre', fp.membre, 'matricule', fp.matricule, 'etat', fp.etat,
        'mandataire', fp.mandataire) order by fp.membre)
      from feuille_presence(p_assemblee) fp where fp.etat <> 'absent'), '[]'::jsonb),
    'resultats', coalesce((select jsonb_agg(jsonb_build_object(
        'poste', x.poste, 'candidat', x.candidat, 'voix', x.voix) order by x.poste, x.voix desc)
      from (
        select b.poste,
               coalesce(trim(p.prenom || ' ' || p.nom), 'Bulletins blancs') as candidat,
               count(*)::int as voix
        from bulletins b
        left join candidatures ca on ca.id = b.candidature_id
        left join profils p on p.id = ca.profil_id
        where b.assemblee_id = p_assemblee
        group by b.poste, coalesce(trim(p.prenom || ' ' || p.nom), 'Bulletins blancs')
      ) x), '[]'::jsonb),
    'signataires', coalesce((select jsonb_agg(jsonb_build_object(
        'membre', cd.membre, 'role', cd.role, 'signe_le', cd.signe_le))
      from cles_du_depouillement(p_assemblee) cd), '[]'::jsonb),
    'proces_verbal', a.proces_verbal)
  end
  from assemblees a
  left join territoires t on t.id = a.territoire_id
  where a.id = p_assemblee;
$$;

-- ---------------------------------------------------------------------
-- 5. LA PROCLAMATION EXIGE LES DEUX CLÉS
--    Sans cela, la double signature était décorative — et une décision
--    qui n'engage personne n'engage rien.
-- ---------------------------------------------------------------------

create or replace function proclamer(p_assemblee uuid, p_pv text,
                                     p_pv_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; d jsonb; r record; v_nom uuid; v_fin date; v_elus int := 0;
        v_cles int;
begin
  if not (a_droit('scrutin.proclamer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'La proclamation relève de la direction.');
  end if;
  select * into a from assemblees where id = p_assemblee;
  if a.statut not in ('scrutin','depouillement') then
    return jsonb_build_object('ok', false,
      'message', 'Ce scrutin n''est pas en état d''être proclamé.');
  end if;
  if coalesce(trim(p_pv),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le procès-verbal est obligatoire.');
  end if;

  -- Deux personnes distinctes doivent avoir signé le dépouillement.
  select count(*) into v_cles from cles_depouillement where assemblee_id = p_assemblee;
  if v_cles < 2 then
    return jsonb_build_object('ok', false,
      'message', 'Le dépouillement n''est signé que par ' || v_cles ||
                 ' personne(s). Deux signatures distinctes sont requises avant de proclamer.');
  end if;

  d := participation(p_assemblee);
  if not (d->>'quorum_atteint')::boolean then
    return jsonb_build_object('ok', false,
      'message', 'Quorum non atteint : ' || (d->>'participation') || ' % pour ' ||
                 (d->>'quorum_requis') || ' % requis. Convoquez une nouvelle assemblée.');
  end if;

  v_fin := (a.date_tenue + (a.duree_mandat_ans || ' years')::interval)::date;

  for r in
    select distinct on (b.poste) b.poste, b.candidature_id, count(*)::int as voix
    from bulletins b
    where b.assemblee_id = p_assemblee and b.candidature_id is not null
    group by b.poste, b.candidature_id
    order by b.poste, count(*) desc
  loop
    update mandats set fin_anticipee = a.date_tenue::date,
           motif_fin = 'Fin de mandat — renouvellement'
     where poste = r.poste and territoire_id = a.territoire_id
       and fin_anticipee is null and fin >= current_date;
    update nominations set revoque_le = now(),
           motif_revocation = 'Renouvellement par élection'
     where poste = r.poste and territoire_id = a.territoire_id and revoque_le is null;

    insert into nominations (profil_id, poste, territoire_id, debut, fin, motif, nomme_par)
    select c.profil_id, r.poste, a.territoire_id, a.date_tenue::date, v_fin,
           'Élu en assemblée ' || a.reference, auth.uid()
    from candidatures c where c.id = r.candidature_id
    returning id into v_nom;

    insert into mandats (assemblee_id, nomination_id, profil_id, poste, territoire_id,
                         debut, fin, voix, suffrages)
    select p_assemblee, v_nom, c.profil_id, r.poste, a.territoire_id,
           a.date_tenue::date, v_fin, r.voix, (d->>'votants')::int
    from candidatures c where c.id = r.candidature_id;

    update candidatures set statut = 'elue' where id = r.candidature_id;
    update candidatures set statut = 'non_elue'
     where assemblee_id = p_assemblee and poste = r.poste
       and id <> r.candidature_id and statut = 'recevable';
    v_elus := v_elus + 1;
  end loop;

  update assemblees
     set statut = 'proclamee', proces_verbal = trim(p_pv),
         pv_fichier = nullif(p_pv_fichier,''),
         proclame_par = auth.uid(), proclame_le = now()
   where id = p_assemblee;

  if a.type = 'constitutive' then
    update territoires set etat = 'active', agree_le = current_date
     where id = a.territoire_id and etat = 'constitution';
    insert into structure_journal (territoire_id, etat, motif, acteur)
    values (a.territoire_id, 'active',
            'Constituée par l''assemblée ' || a.reference, auth.uid());
  end if;

  return jsonb_build_object('ok', true, 'elus', v_elus, 'fin_mandat', v_fin,
                            'signataires', v_cles);
end $$;

grant execute on function empreinte_emargement(uuid, uuid, timestamptz),
                          mon_recepisse(uuid), verifier_recepisse(uuid, text),
                          voter(uuid, jsonb), mes_voix(uuid),
                          feuille_presence(uuid), participation(uuid),
                          projet_pv(uuid), proclamer(uuid, text, text)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 46
--
--  Vérifications :
--    select mes_voix('<uuid>');
--    select * from feuille_presence('<uuid>');
--    select participation('<uuid>');
--    select projet_pv('<uuid>');
--
--  Sur le récépissé : l'empreinte est calculée sur l'émargement seul —
--  assemblée, électeur, horodatage. Aucun bulletin n'entre dans le
--  calcul, et les bulletins n'ont de toute façon aucun lien avec les
--  électeurs. Le récépissé prouve donc qu'on a voté, jamais ce qu'on a
--  voté. C'est la seule forme acceptable : un récépissé opposable sur
--  le contenu du vote rendrait l'achat de voix vérifiable, donc
--  possible.
--
--  Sur les pouvoirs exercés : le mandataire dépose autant de bulletins
--  identiques qu'il porte de voix, et chaque mandant est émargé au même
--  instant. Un mandant qui aurait voté avant que son mandataire ne le
--  fasse n'est pas compté deux fois : la requête écarte ceux qui ont
--  déjà émargé.
--
--  Reste à faire : le `digest()` employé par l'empreinte suppose
--  l'extension `pgcrypto`, active par défaut sur Supabase. Si elle ne
--  l'était pas : `create extension if not exists pgcrypto;`
-- =====================================================================
