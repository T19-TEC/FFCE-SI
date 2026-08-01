-- =====================================================================
--  FFCE — Migration 26 — ÉDITEUR DE FORMATIONS
--
--  Jusqu'ici, ajouter un parcours demandait d'écrire du SQL. C'était le
--  dernier endroit où la plateforme obligeait à passer par la base.
--
--  Un principe a guidé l'écriture : une formation en cours de
--  rédaction ne doit jamais casser le parcours de quelqu'un. Déplacer
--  une leçon, en supprimer une, corriger un quiz — tout cela arrive
--  pendant que des membres suivent le cours. Les fonctions ci-dessous
--  préservent donc systématiquement la progression acquise.
--
--  Prérequis : 01 à 25.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DROIT ET POSTE
-- ---------------------------------------------------------------------

insert into poste_droits (poste, droit) values
  ('chancellerie','formations.editer'),
  ('delegue_admin','formations.editer')
on conflict do nothing;

alter table formations add column if not exists image text;
alter table formations add column if not exists prerequis text
  references certifications(code) on delete set null;

-- ---------------------------------------------------------------------
-- 2. LE PARCOURS COMPLET, POUR L'ÉDITEUR
-- ---------------------------------------------------------------------

create or replace function formation_complete(p_formation uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (a_droit('formations.editer') or est_admin())
    then jsonb_build_object('erreur', 'Réservé aux rédacteurs de formations.')
    else (
      select jsonb_build_object(
        'formation', to_jsonb(f),
        'certification', (select to_jsonb(c) from certifications c
                          where c.formation_id = f.id limit 1),
        'inscrits', (select count(distinct pr.profil_id) from progression pr
                     join v_parcours v on v.lecon_id = pr.lecon_id
                     where v.formation_id = f.id),
        'modules', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', m.id, 'titre', m.titre, 'resume', m.resume, 'ordre', m.ordre,
            'lecons', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', l.id, 'titre', l.titre, 'type', l.type,
                'contenu', l.contenu, 'url', l.url,
                'duree_min', l.duree_min, 'ordre', l.ordre,
                'faites', (select count(*) from progression pr where pr.lecon_id = l.id),
                'questions', case when l.type = 'quiz' then coalesce((
                  select jsonb_agg(jsonb_build_object(
                    'id', q.id, 'enonce', q.enonce, 'aide', q.aide, 'ordre', q.ordre,
                    'reponses', coalesce((
                      select jsonb_agg(jsonb_build_object(
                        'id', r.id, 'texte', r.texte, 'correcte', r.correcte,
                        'ordre', r.ordre) order by r.ordre)
                      from reponses r where r.question_id = q.id), '[]'::jsonb))
                    order by q.ordre)
                  from questions q where q.lecon_id = l.id), '[]'::jsonb) end)
                order by l.ordre)
              from lecons l where l.module_id = m.id), '[]'::jsonb))
            order by m.ordre)
          from modules m where m.formation_id = f.id), '[]'::jsonb))
      from formations f where f.id = p_formation)
    end;
$$;

-- ---------------------------------------------------------------------
-- 3. FORMATION
-- ---------------------------------------------------------------------

create or replace function enregistrer_formation(
  p_id uuid, p_code text, p_titre text, p_resume text, p_description text,
  p_niveau_min integer, p_duree integer, p_seuil integer, p_publiee boolean,
  p_ordre integer default 100, p_image text default null,
  p_prerequis text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne rédigez pas les formations.');
  end if;
  if coalesce(trim(p_titre),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le titre est obligatoire.');
  end if;

  if p_id is null then
    v_code := coalesce(nullif(trim(p_code),''),
                       slugifier(p_titre) || '-' ||
                       substr(md5(random()::text), 1, 4));
    insert into formations (code, titre, resume, description, niveau_min,
                            duree_min, seuil_quiz, publiee, ordre, image,
                            prerequis, cree_par)
    values (v_code, trim(p_titre), nullif(trim(p_resume),''),
            nullif(trim(p_description),''), coalesce(p_niveau_min,10),
            p_duree, coalesce(p_seuil,80), coalesce(p_publiee,false),
            coalesce(p_ordre,100), nullif(p_image,''), nullif(p_prerequis,''),
            auth.uid())
    returning id into v_id;
  else
    update formations set titre = trim(p_titre), resume = nullif(trim(p_resume),''),
           description = nullif(trim(p_description),''),
           niveau_min = coalesce(p_niveau_min, niveau_min),
           duree_min = p_duree, seuil_quiz = coalesce(p_seuil, seuil_quiz),
           publiee = coalesce(p_publiee, publiee), ordre = coalesce(p_ordre, ordre),
           image = coalesce(nullif(p_image,''), image),
           prerequis = nullif(p_prerequis,'')
     where id = p_id
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function supprimer_formation(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_suivi int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  select count(distinct pr.profil_id) into v_suivi
    from progression pr join v_parcours v on v.lecon_id = pr.lecon_id
   where v.formation_id = p_id;
  if v_suivi > 0 then
    return jsonb_build_object('ok', false,
      'message', v_suivi || ' membre(s) ont commencé ce parcours. Dépubliez-le plutôt que de l''effacer.');
  end if;
  delete from formations where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. MODULES ET LEÇONS
-- ---------------------------------------------------------------------

create or replace function enregistrer_module(
  p_id uuid, p_formation uuid, p_titre text, p_resume text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ordre int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  if p_id is null then
    select coalesce(max(ordre), 0) + 10 into v_ordre from modules
     where formation_id = p_formation;
    insert into modules (formation_id, titre, resume, ordre)
    values (p_formation, trim(p_titre), nullif(trim(p_resume),''), v_ordre)
    returning id into v_id;
  else
    update modules set titre = trim(p_titre), resume = nullif(trim(p_resume),'')
     where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function enregistrer_lecon(
  p_id uuid, p_module uuid, p_titre text, p_type text,
  p_contenu text default null, p_url text default null,
  p_duree integer default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ordre int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  if coalesce(trim(p_titre),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Le titre est obligatoire.');
  end if;

  if p_id is null then
    select coalesce(max(ordre), 0) + 10 into v_ordre from lecons where module_id = p_module;
    insert into lecons (module_id, titre, type, contenu, url, duree_min, ordre)
    values (p_module, trim(p_titre), coalesce(p_type,'lecture'),
            nullif(p_contenu,''), nullif(trim(p_url),''), p_duree, v_ordre)
    returning id into v_id;
  else
    update lecons set titre = trim(p_titre), type = coalesce(p_type, type),
           contenu = nullif(p_contenu,''), url = nullif(trim(p_url),''),
           duree_min = p_duree
     where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Déplacer sans casser : on échange les rangs, la progression suit.
create or replace function deplacer(p_table text, p_id uuid, p_sens integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ordre int; v_parent uuid; v_voisin uuid; v_ordre_voisin int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;

  if p_table = 'module' then
    select ordre, formation_id into v_ordre, v_parent from modules where id = p_id;
    if p_sens < 0 then
      select id, ordre into v_voisin, v_ordre_voisin from modules
       where formation_id = v_parent and ordre < v_ordre order by ordre desc limit 1;
    else
      select id, ordre into v_voisin, v_ordre_voisin from modules
       where formation_id = v_parent and ordre > v_ordre order by ordre limit 1;
    end if;
    if v_voisin is null then return jsonb_build_object('ok', true); end if;
    update modules set ordre = v_ordre_voisin where id = p_id;
    update modules set ordre = v_ordre where id = v_voisin;

  elsif p_table = 'lecon' then
    select ordre, module_id into v_ordre, v_parent from lecons where id = p_id;
    if p_sens < 0 then
      select id, ordre into v_voisin, v_ordre_voisin from lecons
       where module_id = v_parent and ordre < v_ordre order by ordre desc limit 1;
    else
      select id, ordre into v_voisin, v_ordre_voisin from lecons
       where module_id = v_parent and ordre > v_ordre order by ordre limit 1;
    end if;
    if v_voisin is null then return jsonb_build_object('ok', true); end if;
    update lecons set ordre = v_ordre_voisin where id = p_id;
    update lecons set ordre = v_ordre where id = v_voisin;

  elsif p_table = 'question' then
    select ordre, lecon_id into v_ordre, v_parent from questions where id = p_id;
    if p_sens < 0 then
      select id, ordre into v_voisin, v_ordre_voisin from questions
       where lecon_id = v_parent and ordre < v_ordre order by ordre desc limit 1;
    else
      select id, ordre into v_voisin, v_ordre_voisin from questions
       where lecon_id = v_parent and ordre > v_ordre order by ordre limit 1;
    end if;
    if v_voisin is null then return jsonb_build_object('ok', true); end if;
    update questions set ordre = v_ordre_voisin where id = p_id;
    update questions set ordre = v_ordre where id = v_voisin;
  else
    return jsonb_build_object('ok', false, 'message', 'Élément inconnu.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function supprimer_element(p_table text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_faites int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;

  if p_table = 'lecon' then
    select count(*) into v_faites from progression where lecon_id = p_id;
    if v_faites > 0 then
      return jsonb_build_object('ok', false,
        'message', v_faites || ' membre(s) ont achevé cette leçon. La supprimer effacerait leur progression.');
    end if;
    delete from lecons where id = p_id;
  elsif p_table = 'module' then
    select count(*) into v_faites from progression pr
     join lecons l on l.id = pr.lecon_id where l.module_id = p_id;
    if v_faites > 0 then
      return jsonb_build_object('ok', false,
        'message', 'Des membres ont avancé dans ce module. Videz-le d''abord.');
    end if;
    delete from modules where id = p_id;
  elsif p_table = 'question' then
    delete from questions where id = p_id;
  elsif p_table = 'reponse' then
    delete from reponses where id = p_id;
  else
    return jsonb_build_object('ok', false, 'message', 'Élément inconnu.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. QUIZ
-- ---------------------------------------------------------------------

create or replace function enregistrer_question(
  p_id uuid, p_lecon uuid, p_enonce text, p_aide text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ordre int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  if p_id is null then
    select coalesce(max(ordre),0) + 10 into v_ordre from questions where lecon_id = p_lecon;
    insert into questions (lecon_id, enonce, aide, ordre)
    values (p_lecon, trim(p_enonce), nullif(trim(p_aide),''), v_ordre)
    returning id into v_id;
  else
    update questions set enonce = trim(p_enonce), aide = nullif(trim(p_aide),'')
     where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function enregistrer_reponse(
  p_id uuid, p_question uuid, p_texte text, p_correcte boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ordre int;
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  if p_id is null then
    select coalesce(max(ordre),0) + 10 into v_ordre from reponses where question_id = p_question;
    insert into reponses (question_id, texte, correcte, ordre)
    values (p_question, trim(p_texte), coalesce(p_correcte,false), v_ordre)
    returning id into v_id;
  else
    update reponses set texte = trim(p_texte), correcte = coalesce(p_correcte, correcte)
     where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 6. CERTIFICATION LIÉE
-- ---------------------------------------------------------------------

create or replace function enregistrer_certification(
  p_code text, p_nom text, p_description text, p_formation uuid,
  p_validite integer default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (a_droit('formations.editer') or est_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Réservé aux rédacteurs.');
  end if;
  insert into certifications (code, nom, description, formation_id, validite_mois)
  values (coalesce(nullif(trim(p_code),''), slugifier(p_nom)),
          trim(p_nom), nullif(trim(p_description),''), p_formation, p_validite)
  on conflict (code) do update
    set nom = trim(p_nom), description = nullif(trim(p_description),''),
        formation_id = p_formation, validite_mois = p_validite;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. CONTRÔLE DE COHÉRENCE
--    Avant de publier, on vérifie ce qu'un rédacteur oublie souvent.
-- ---------------------------------------------------------------------

create or replace function verifier_formation(p_formation uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with pb as (
    select 'Aucun module' as souci where not exists (
      select 1 from modules where formation_id = p_formation)
    union all
    select 'Un module est vide : ' || m.titre from modules m
    where m.formation_id = p_formation
      and not exists (select 1 from lecons l where l.module_id = m.id)
    union all
    select 'Leçon sans contenu : ' || l.titre
    from lecons l join modules m on m.id = l.module_id
    where m.formation_id = p_formation and l.type in ('lecture')
      and coalesce(trim(l.contenu),'') = ''
    union all
    select 'Leçon sans adresse : ' || l.titre
    from lecons l join modules m on m.id = l.module_id
    where m.formation_id = p_formation and l.type in ('video','document')
      and coalesce(trim(l.url),'') = ''
    union all
    select 'Quiz sans question : ' || l.titre
    from lecons l join modules m on m.id = l.module_id
    where m.formation_id = p_formation and l.type = 'quiz'
      and not exists (select 1 from questions q where q.lecon_id = l.id)
    union all
    select 'Question sans bonne réponse : ' || left(q.enonce, 50)
    from questions q join lecons l on l.id = q.lecon_id
    join modules m on m.id = l.module_id
    where m.formation_id = p_formation
      and not exists (select 1 from reponses r where r.question_id = q.id and r.correcte)
    union all
    select 'Question avec moins de deux propositions : ' || left(q.enonce, 50)
    from questions q join lecons l on l.id = q.lecon_id
    join modules m on m.id = l.module_id
    where m.formation_id = p_formation
      and (select count(*) from reponses r where r.question_id = q.id) < 2)
  select jsonb_build_object(
    'publiable', not exists (select 1 from pb),
    'soucis', coalesce((select jsonb_agg(souci) from pb), '[]'::jsonb));
$$;

-- Qui suit quoi : le rédacteur doit savoir si son cours est lu.
create or replace function suivi_formation(p_formation uuid)
returns table (profil_id uuid, membre text, territoire text,
               lecons_faites integer, total integer, pourcent integer,
               derniere_activite timestamptz, certifie boolean)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), t.nom,
         count(pr.id)::int,
         (select count(*)::int from v_parcours v where v.formation_id = p_formation),
         case when (select count(*) from v_parcours v where v.formation_id = p_formation) = 0
              then 0
              else round(count(pr.id)::numeric /
                   (select count(*) from v_parcours v where v.formation_id = p_formation) * 100)::int
         end,
         max(pr.termine_le),
         exists (select 1 from certifications_obtenues co
                 join certifications c on c.code = co.code
                 where co.profil_id = p.id and c.formation_id = p_formation)
  from progression pr
  join v_parcours v on v.lecon_id = pr.lecon_id
  join profils p on p.id = pr.profil_id
  left join territoires t on t.id = p.territoire_id
  where v.formation_id = p_formation
    and (a_droit('formations.editer') or est_admin() or mon_niveau() >= 60)
  group by p.id, p.prenom, p.nom, t.nom
  order by 6 desc, max(pr.termine_le) desc;
$$;

grant execute on function formation_complete(uuid),
                          enregistrer_formation(uuid, text, text, text, text,
                                                integer, integer, integer, boolean,
                                                integer, text, text),
                          supprimer_formation(uuid),
                          enregistrer_module(uuid, uuid, text, text),
                          enregistrer_lecon(uuid, uuid, text, text, text, text, integer),
                          deplacer(text, uuid, integer),
                          supprimer_element(text, uuid),
                          enregistrer_question(uuid, uuid, text, text),
                          enregistrer_reponse(uuid, uuid, text, boolean),
                          enregistrer_certification(text, text, text, uuid, integer),
                          verifier_formation(uuid), suivi_formation(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 26
--
--  Vérifications :
--    select verifier_formation((select id from formations where code='socle'));
--    select * from suivi_formation((select id from formations where code='socle'));
--
--  Le principe : une formation en cours de rédaction ne doit jamais
--  casser le parcours de quelqu'un. Supprimer une leçon déjà achevée
--  est refusé ; déplacer un élément échange les rangs sans toucher à la
--  progression acquise.
-- =====================================================================
