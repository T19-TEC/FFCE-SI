-- =====================================================================
--  FFCE — Migration 13 — CORRECTIFS ET PROGRESSION
--
--  1. LA DISCIPLINE EST NATIONALE. Un membre du conseil de discipline
--     ou de la DAJ doit pouvoir instruire sur n'importe quel membre,
--     quel que soit son propre rattachement territorial. La liste des
--     membres venait de l'annuaire, borné au périmètre : c'était le
--     défaut.
--
--  2. PIÈCES ET DÉCISIONS EN PDF. Une décision se notifie par courrier.
--     Le courrier se joint.
--
--  3. LA GRAVITÉ RESTE INTERNE. Elle sert à hiérarchiser l'instruction,
--     pas à qualifier quelqu'un devant lui.
--
--  4. LE SUIVI DES USAGES, AGRÉGÉ. Une liste d'événements bruts ne se
--     suit pas. On regroupe par membre, avec la dernière activité.
--
--  5. LES POINTS D'ÉCHELON. Calculés, jamais stockés.
--
--  6. LA FORMATION AUX OUTILS. « Comprendre mes droits » devient une
--     leçon dans un parcours d'accueil.
--
--  Prérequis : 01 à 12.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LA DISCIPLINE VOIT TOUTE LA FÉDÉRATION
-- ---------------------------------------------------------------------

create or replace function membres_pour_discipline(p_recherche text default null)
returns table (id uuid, prenom text, nom text, matricule text, email text,
               fonction_nom text, territoire_nom text, statut text,
               dossiers_ouverts integer)
language sql stable security definer set search_path = public as $$
  select p.id, p.prenom, p.nom, p.matricule, p.email, f.nom, t.nom, p.statut,
         (select count(*)::int from dossiers d
           where d.profil_id = p.id and d.statut <> 'clos')
  from profils p
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where (a_droit('discipline.saisir') or a_droit('discipline.instruire')
         or a_droit('discipline.decider') or a_droit('discipline.recours'))
    and p.statut <> 'archive'
    and (p_recherche is null or p_recherche = ''
         or (coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'') || ' ' ||
             p.matricule || ' ' || coalesce(t.nom,'')) ilike '%' || p_recherche || '%')
  order by p.nom, p.prenom;
$$;

-- Une nomination territoriale ne restreint pas les droits disciplinaires :
-- on n'instruit pas une affaire par département.
create or replace function a_droit(p_droit text)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or exists (
    select 1 from nominations n
    join poste_droits pd on pd.poste = n.poste
    join postes p        on p.code = n.poste
    where n.profil_id = auth.uid()
      and pd.droit = p_droit
      and p.actif
      and nomination_active(n));
$$;

-- ---------------------------------------------------------------------
-- 2. PIÈCES ET COURRIERS
-- ---------------------------------------------------------------------

alter table mesures add column if not exists fichier text;
alter table recours add column if not exists fichier_decision text;

create or replace function prononcer_mesure(
  p_dossier uuid, p_type text, p_motif text, p_texte text default null,
  p_effet date default null, p_fin date default null, p_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne prononcez pas de mesure.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Toute mesure doit être motivée.');
  end if;

  insert into mesures (dossier_id, type, motif, texte_decision, date_effet,
                       date_fin, prise_par, fichier)
  values (p_dossier, p_type, trim(p_motif), nullif(trim(p_texte),''),
          coalesce(p_effet, current_date), p_fin, auth.uid(), nullif(p_fichier,''))
  returning id into v_id;

  insert into dossier_pieces (dossier_id, type, titre, contenu, fichier,
                              auteur_id, communicable)
  values (p_dossier, 'decision', 'Décision : ' || p_type,
          trim(p_motif) || coalesce(E'\n\n' || p_texte, ''),
          nullif(p_fichier,''), auth.uid(), true);

  update dossiers set statut = 'decision' where id = p_dossier;
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'mesure_prononcee', v_id::text, jsonb_build_object('type', p_type));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Notifier en joignant le courrier de notification.
create or replace function notifier_mesure(p_mesure uuid, p_courrier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_dossier uuid;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au conseil de discipline.');
  end if;
  select dossier_id into v_dossier from mesures where id = p_mesure;

  update mesures
     set notifiee_le = now(),
         statut = case when type = 'classement' then 'echue' else 'executee' end,
         fichier = coalesce(nullif(p_courrier,''), fichier)
   where id = p_mesure and notifiee_le is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Mesure déjà notifiée.');
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, fichier,
                              auteur_id, communicable)
  values (v_dossier, 'notification', 'Notification de la décision',
          'La décision vous a été notifiée. Vous disposez d''un délai de recours gracieux.',
          nullif(p_courrier,''), auth.uid(), true);

  update dossiers set statut = 'notifie' where id = v_dossier;
  return jsonb_build_object('ok', true);
end $$;

create or replace function statuer_recours(
  p_recours uuid, p_issue text, p_decision text, p_suspensif boolean default false,
  p_fichier text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r recours; v_dossier uuid;
begin
  if not a_droit('discipline.recours') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne statuez pas sur les recours.');
  end if;
  if coalesce(trim(p_decision),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'La décision doit être motivée.');
  end if;

  select * into r from recours where id = p_recours;
  select dossier_id into v_dossier from mesures where id = r.mesure_id;

  update recours
     set statut = p_issue, decision = trim(p_decision),
         decide_par = auth.uid(), decide_le = now(),
         suspensif = coalesce(p_suspensif,false),
         fichier_decision = nullif(p_fichier,'')
   where id = p_recours;

  if p_issue = 'accepte' then
    update mesures set statut = 'annulee' where id = r.mesure_id;
  elsif coalesce(p_suspensif,false) then
    update mesures set statut = 'suspendue' where id = r.mesure_id;
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, fichier,
                              auteur_id, communicable)
  values (v_dossier, 'reponse_recours', 'Décision sur recours gracieux',
          trim(p_decision), nullif(p_fichier,''), auth.uid(), true);

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'recours_statue', p_recours::text, jsonb_build_object('issue', p_issue));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 3. LA GRAVITÉ NE SORT PLUS VERS L'INTÉRESSÉ
--    Elle hiérarchise l'instruction ; elle ne qualifie pas quelqu'un
--    devant lui. On la retire de la vue qu'il consulte.
-- ---------------------------------------------------------------------

create or replace function mon_dossier()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'statut_compte', (select statut from profils where id = auth.uid()),
    'sous_suivi',    (select sous_suivi from profils where id = auth.uid()),
    'dossiers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'reference', d.reference, 'objet', d.objet,
        'qualification', d.qualification,
        'statut', d.statut, 'ouvert_le', d.ouvert_le,
        'clos_le', d.clos_le, 'conclusion', d.conclusion,
        'scelle', d.statut = 'clos',
        'pieces', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', pc.id, 'type', pc.type, 'titre', pc.titre, 'contenu', pc.contenu,
            'fichier', pc.fichier, 'cree_le', pc.cree_le)
            order by pc.cree_le)
          from dossier_pieces pc
          where pc.dossier_id = d.id and pc.communicable), '[]'::jsonb),
        'pieces_non_communicables', (
          select count(*) from dossier_pieces pc
          where pc.dossier_id = d.id and not pc.communicable),
        'peut_renoncer', exists (
          select 1 from mesures m where m.dossier_id = d.id
            and m.notifiee_le is not null and m.renonce_le is null)
          and d.statut <> 'clos',
        'mesures', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', m.id, 'type', m.type, 'motif', m.motif,
            'texte', m.texte_decision, 'statut', m.statut, 'fichier', m.fichier,
            'date_effet', m.date_effet, 'date_fin', m.date_fin,
            'notifiee_le', m.notifiee_le, 'accusee_le', m.accusee_le,
            'renonce_le', m.renonce_le, 'renonce_texte', m.renonce_texte,
            'limite_recours', limite_recours(m),
            'recours_ouvert', recours_ouvert(m),
            'motif_fermeture', motif_fermeture_recours(m),
            'recours_restants', greatest(m.max_recours - recours_deja_formes(m.id), 0),
            'recours', coalesce((
              select jsonb_agg(jsonb_build_object(
                'contenu', rc.contenu, 'statut', rc.statut,
                'decision', rc.decision, 'fichier', rc.fichier_decision,
                'cree_le', rc.cree_le, 'decide_le', rc.decide_le) order by rc.cree_le)
              from recours rc where rc.mesure_id = m.id), '[]'::jsonb))
            order by m.prise_le desc)
          from mesures m where m.dossier_id = d.id and m.notifiee_le is not null),
          '[]'::jsonb))
        order by d.ouvert_le desc)
      from dossiers d where d.profil_id = auth.uid()), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------
-- 4. LE SUIVI DES USAGES, AGRÉGÉ PAR MEMBRE
-- ---------------------------------------------------------------------

create or replace function suivi_en_cours()
returns table (
  profil_id uuid, membre text, matricule text, territoire_nom text,
  mesure_id uuid, motif text, date_effet date, date_fin date,
  dossier_reference text, instructeur text,
  alertes_non_vues integer, alertes_total integer,
  derniere_activite timestamptz, applications text
) language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), p.matricule, t.nom,
         m.id, m.motif, m.date_effet, m.date_fin, d.reference,
         trim(i.prenom || ' ' || i.nom),
         (select count(*)::int from alertes_suivi a
           where a.profil_id = p.id and a.vue_le is null),
         (select count(*)::int from alertes_suivi a where a.profil_id = p.id),
         (select max(a.cree_le) from alertes_suivi a where a.profil_id = p.id),
         (select string_agg(distinct ap.nom, ', ') from alertes_suivi a
           join applications ap on ap.code = a.application
          where a.profil_id = p.id and a.cree_le > now() - interval '30 days')
  from profils p
  join dossiers d on d.profil_id = p.id
  join mesures m  on m.dossier_id = d.id
  left join territoires t on t.id = p.territoire_id
  left join profils i on i.id = d.instructeur_id
  where p.sous_suivi and m.type = 'suivi_usages' and m.statut = 'executee'
    and (est_admin() or a_droit('discipline.instruire') or a_droit('discipline.decider'))
  order by (select max(a.cree_le) from alertes_suivi a where a.profil_id = p.id) desc nulls last;
$$;

create or replace function marquer_suivi_vu(p_profil uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('discipline.instruire')) then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''instruction.');
  end if;
  update alertes_suivi set vue_par = auth.uid(), vue_le = now()
   where profil_id = p_profil and vue_le is null;
  return jsonb_build_object('ok', true);
end $$;

-- Le détail, quand on veut regarder de près.
create or replace function detail_suivi(p_profil uuid)
returns table (application text, app_nom text, cree_le timestamptz, vue_le timestamptz)
language sql stable security definer set search_path = public as $$
  select a.application, ap.nom, a.cree_le, a.vue_le
  from alertes_suivi a
  left join applications ap on ap.code = a.application
  where a.profil_id = p_profil
    and (est_admin() or a_droit('discipline.instruire') or a_droit('discipline.decider'))
  order by a.cree_le desc
  limit 200;
$$;

-- ---------------------------------------------------------------------
-- 5. LES POINTS D'ÉCHELON
--    Calculés à la lecture, jamais stockés : ils sont donc toujours
--    justes, et personne ne peut les « attribuer ».
-- ---------------------------------------------------------------------

create or replace function points_membre(p_profil uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with moi as (select coalesce(p_profil, auth.uid()) as id),
  detail as (
    select
      -- 25 points par certification obtenue
      (select count(*) * 25 from certifications_obtenues c, moi
        where c.profil_id = moi.id)::int as certifications,
      -- 5 points par tâche menée à terme
      (select count(*) * 5 from gt_taches k, moi
        where k.assigne_a = moi.id and k.statut = 'faite')::int as taches,
      -- 15 points par mission accomplie
      (select count(*) * 15 from mission_candidatures mc, moi
        where mc.profil_id = moi.id and mc.statut = 'retenu')::int as missions,
      -- 2 points par heure de bénévolat déclarée
      (select coalesce(sum(e.heures_realisees), 0) * 2 from engagements e, moi
        where e.profil_id = moi.id)::int as heures,
      -- 20 points par groupe de travail dont on est responsable
      (select count(*) * 20 from gt_membres g, moi
        where g.profil_id = moi.id and g.statut = 'actif'
          and g.role = 'responsable')::int as responsabilites,
      -- 3 points par mois d'ancienneté
      (select greatest(extract(month from age(now(), p.cree_le))::int
              + extract(year from age(now(), p.cree_le))::int * 12, 0) * 3
        from profils p, moi where p.id = moi.id)::int as anciennete,
      (select p.echelon from profils p, moi where p.id = moi.id) as echelon
    )
  select jsonb_build_object(
    'total', d.certifications + d.taches + d.missions + d.heures
             + d.responsabilites + d.anciennete,
    'detail', jsonb_build_object(
      'Certifications obtenues', d.certifications,
      'Tâches menées à terme', d.taches,
      'Missions accomplies', d.missions,
      'Heures de bénévolat', d.heures,
      'Responsabilités de groupe', d.responsabilites,
      'Ancienneté', d.anciennete),
    'echelon', d.echelon,
    'echelon_nom', (select nom from echelons where niveau = d.echelon),
    'palier_actuel', (select points from echelons where niveau = d.echelon),
    'prochain', (select jsonb_build_object('niveau', e.niveau, 'nom', e.nom,
                        'points', e.points, 'ouvre', e.ouvre)
                 from echelons e where e.niveau = d.echelon + 1),
    'atteint_le_palier', (
      select (d.certifications + d.taches + d.missions + d.heures
              + d.responsabilites + d.anciennete)
             >= coalesce((select points from echelons where niveau = d.echelon + 1), 999999))
  ) from detail d;
$$;

-- ---------------------------------------------------------------------
-- 6. PHOTOS DE PROFIL
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('portraits', 'portraits', false, 2097152)
on conflict (id) do update set public = false, file_size_limit = 2097152;

drop policy if exists depot_portraits on storage.objects;
create policy depot_portraits on storage.objects for insert to authenticated
  with check (bucket_id = 'portraits'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists lecture_portraits on storage.objects;
create policy lecture_portraits on storage.objects for select to authenticated
  using (bucket_id = 'portraits');

drop policy if exists suppr_portraits on storage.objects;
create policy suppr_portraits on storage.objects for delete to authenticated
  using (bucket_id = 'portraits'
         and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 7. LA FORMATION AUX OUTILS DE LA FÉDÉRATION
-- ---------------------------------------------------------------------

insert into formations (code, titre, resume, description, niveau_min, duree_min, publiee, ordre)
values ('si_ffce', 'Nouvel adhérent — la fédération et ses outils',
        'Comment nous sommes organisés, comment fonctionnent les droits, et comment utiliser la plateforme.',
        'Un parcours court pour comprendre qui fait quoi dans la fédération, ce que votre fonction vous ouvre, et comment vous servir des outils numériques sans vous perdre.',
        10, 30, true, 5)
on conflict (code) do nothing;

do $$
declare f uuid; m1 uuid; m2 uuid; l uuid; q uuid;
begin
  select id into f from formations where code = 'si_ffce';
  if exists (select 1 from modules where formation_id = f) then return; end if;

  insert into modules (formation_id, titre, resume, ordre)
  values (f, 'Comprendre les droits', 'Fonction, échelon, poste : trois notions distinctes.', 10)
  returning id into m1;

  insert into lecons (module_id, titre, type, contenu, duree_min, ordre) values
   (m1, 'Fonction, échelon, poste', 'lecture',
'Trois notions gouvernent tout le système, et elles sont indépendantes.

LA FONCTION est le poste que vous occupez dans la hiérarchie : adhérent, bénévole, animateur local, responsable local, référent départemental, délégué régional, direction. Elle détermine votre périmètre — vous voyez et accompagnez votre territoire et tout ce qui en dépend, jamais celui du voisin.

L''ÉCHELON reconnaît votre parcours, sur sept paliers. Il est indépendant de la fonction. Un bénévole engagé depuis cinq ans peut être échelon 5 sans encadrer personne, et un référent départemental fraîchement nommé peut être échelon 2. La fonction donne le pouvoir, l''échelon reconnaît l''expérience.

LE POSTE est un mandat nommé : référent à la protection des données, direction des affaires juridiques, ordonnateur, membre du conseil de discipline. Il est cumulable, révocable, parfois limité à un territoire et à une durée. Il ouvre des droits que la fonction ne donne pas. Un adhérent de base peut être référent RGPD.

Rien de tout cela n''est caché : la page « Comprendre mes droits » expose les dix fonctions, les sept échelons, tous les postes avec leurs titulaires nommés, et l''état de chaque application pour votre fonction.', 8, 10),

   (m1, 'Ce que votre fonction vous ouvre', 'lecture',
'Chaque application prend, pour chaque fonction, l''un de trois états.

OUVERTE : elle apparaît sur votre tableau de bord et fonctionne immédiatement.

SUR DEMANDE : elle apparaît grisée, avec un bouton qui mène au guichet. Vous exposez votre besoin, la Direction générale décide. C''est le cas des notes de frais, du webmail, de la direction financière.

NON OUVERTE : elle n''apparaît pas. Elle n''est pas prévue pour votre fonction — ce qui ne veut pas dire qu''elle vous est refusée : un poste peut vous l''ouvrir quelle que soit votre place dans la hiérarchie.

Un accès accordé peut avoir une date d''expiration, et il peut être révoqué avec un motif que vous pouvez consulter. Un accès qui ne sert jamais est signalé à la direction : ce n''est pas de la surveillance, c''est de l''hygiène.', 7, 20);

  insert into modules (formation_id, titre, resume, ordre)
  values (f, 'Utiliser la plateforme', 'Messagerie, groupes, dossiers : les règles du jeu.', 20)
  returning id into m2;

  insert into lecons (module_id, titre, type, contenu, duree_min, ordre) values
   (m2, 'Échanger et travailler ensemble', 'lecture',
'LA MESSAGERIE. Vous pouvez écrire aux membres de votre département, à toute votre hiérarchie jusqu''au national, et à la direction, toujours joignable. Le cercle s''élargit avec l''échelon.

Les échanges internes peuvent être consultés par l''encadrement dans le cadre de ses fonctions. Cette supervision est strictement descendante : un encadrant ne voit une conversation que si tous les autres participants ont une fonction inférieure à la sienne. Un référent départemental ne lit donc pas ce que la direction écrit. Un superviseur peut lire ; il ne peut pas écrire à votre place.

Vous pouvez signaler une conversation à tout moment. Le signalement est examiné par la Direction générale.

LES GROUPES DE TRAVAIL. Certains sont ouverts, d''autres se rejoignent sur invitation de leur responsable. Certains exigent une certification : c''est ce qui relie la formation à l''action. Chaque groupe a ses documents, ses tâches assignées et sa discussion.

LES MISSIONS. Des actions ouvertes au volontariat, avec des places et des dates. Si vous ne pouvez pas postuler, la plateforme vous dit pourquoi.', 8, 10),

   (m2, 'Vos droits sur vos données', 'lecture',
'Vos coordonnées ne s''affichent pas d''emblée dans l''annuaire. Il faut cliquer pour les révéler, et ce clic est enregistré.

Par symétrie, la page « Mon compte » vous montre qui a consulté votre dossier, avec la fonction et la date. C''est un droit du RGPD, exercé en un clic plutôt que par courrier.

Si un dossier disciplinaire vous concerne, vous en êtes informé sur votre tableau de bord. Vous accédez aux pièces qui vous sont communicables, vous pouvez y verser vos observations et vos documents, et former un recours gracieux contre toute décision notifiée, dans le délai indiqué.

Une décision ne produit aucun effet tant qu''elle ne vous a pas été notifiée, et aucune notification n''est valable sans voie de recours ouverte. Même suspendu, votre compte reste accessible pour suivre votre dossier et exercer vos droits.

Enfin : le recours gracieux interne ne vous prive d''aucun droit devant les juridictions compétentes.', 7, 20);

  insert into lecons (module_id, titre, type, duree_min, ordre)
  values (m2, 'Vérifions ensemble', 'quiz', 5, 30)
  returning id into l;

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Qu''est-ce qui détermine votre périmètre — ce que vous voyez de la fédération ?', 10)
    returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'Ma fonction et mon territoire de rattachement', true, 10),
    (q, 'Mon échelon', false, 20),
    (q, 'Mon ancienneté', false, 30);

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Un référent départemental peut-il lire un échange entre la Direction générale et un adhérent de son territoire ?', 20)
    returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'Non : la supervision ne remonte jamais', true, 10),
    (q, 'Oui, tout membre de son territoire', false, 20),
    (q, 'Oui, mais seulement en cas de signalement', false, 30);

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Une application grisée sur votre tableau de bord signifie que…', 30)
    returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'Vous pouvez en demander l''accès au guichet', true, 10),
    (q, 'Elle est en panne', false, 20),
    (q, 'Elle vous a été refusée', false, 30);

  insert into questions (lecon_id, enonce, ordre) values
    (l, 'Que se passe-t-il quand quelqu''un affiche vos coordonnées dans l''annuaire ?', 40)
    returning id into q;
  insert into reponses (question_id, texte, correcte, ordre) values
    (q, 'La consultation est enregistrée et vous pouvez la voir', true, 10),
    (q, 'Rien, c''est un usage courant', false, 20),
    (q, 'Vous recevez une alerte de la direction', false, 30);
end $$;

insert into certifications (code, nom, description, formation_id, validite_mois)
select 'usage_si', 'Usage des outils fédéraux',
       'Atteste de la compréhension de l''organisation, du système de droits et des règles d''usage de la plateforme.',
       id, null
from formations where code = 'si_ffce'
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 8. DROITS
-- ---------------------------------------------------------------------

grant execute on function membres_pour_discipline(text), a_droit(text),
                          prononcer_mesure(uuid, text, text, text, date, date, text),
                          notifier_mesure(uuid, text),
                          statuer_recours(uuid, text, text, boolean, text),
                          mon_dossier(), suivi_en_cours(), marquer_suivi_vu(uuid),
                          detail_suivi(uuid), points_membre(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 13
--
--  Vérifications :
--    select count(*) from membres_pour_discipline();
--    select points_membre();
--    select * from suivi_en_cours();
--
--  Note sur la gravité : elle reste dans la table et dans les écrans
--  d'instruction, où elle sert à hiérarchiser le travail. Elle a
--  simplement disparu de mon_dossier(), c'est-à-dire de ce que voit
--  l'intéressé. Qualifier quelqu'un d'« élevé » devant lui n'apporte
--  rien à la procédure et beaucoup à l'humiliation.
-- =====================================================================
