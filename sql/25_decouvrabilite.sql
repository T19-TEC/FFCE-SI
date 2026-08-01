-- =====================================================================
--  FFCE — Migration 25 — LE CONTENU VIENT AUX ÉQUIPES
--
--  Le défaut : « Publier localement » était rangé sous la direction de
--  la communication. Un responsable local voyait donc apparaître dans
--  son menu une direction dont il ne relève pas, et devait penser à
--  l'ouvrir pour découvrir qu'on l'attendait.
--
--  Un outil qu'il faut penser à ouvrir n'est pas utilisé. Le contenu
--  doit venir à ceux qui doivent l'employer.
--
--  Trois corrections :
--    — l'application rejoint l'activité personnelle, pas une direction ;
--    — ce qui est à relayer apparaît sur la table de contrôle ;
--    — et dans « Mon comité », là où l'équipe locale regarde déjà.
--
--  Prérequis : 01 à 24.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. L'APPLICATION CHANGE DE PLACE
-- ---------------------------------------------------------------------

update applications
   set direction = null,           -- activité personnelle, pas une direction
       nom = 'Relayer nos actions',
       nom_court = 'À relayer',
       accroche = 'Des publications prêtes à adapter pour vos réseaux.',
       ordre = 12
 where code = 'publier';

-- Elle s'ouvre dès le rôle d'animateur, comme avant.
insert into application_visibilite (application, fonction, etat)
select 'publier', f.code, case when f.niveau >= 40 then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do update
  set etat = case when (select niveau from fonctions
                        where code = application_visibilite.fonction) >= 40
                  then 'ouverte' else 'invisible' end;

-- ---------------------------------------------------------------------
-- 2. CE QUI M'ATTEND EN MATIÈRE DE PUBLICATION
-- ---------------------------------------------------------------------

create or replace function publications_a_relayer()
returns integer language sql stable security definer set search_path = public as $$
  select case when mon_niveau() < 40 then 0
    else (select count(*)::int from suggestions_disponibles()
          where not je_lai_reprise
            and (a_publier_le is null or a_publier_le <= current_date + 7))
  end;
$$;

-- La file de travail intègre les publications en attente.
create or replace function ce_qui_attend()
returns table (code text, libelle text, nombre integer, lien text, urgence text)
language sql stable security definer set search_path = public as $$
  select * from (
    values
    ('inscriptions', 'inscription(s) à vérifier',
      (select count(*)::int from profils where statut = 'en_attente'
        and (est_admin() or a_droit('membres.valider'))),
      '#/espace/validation', 'normale'),
    ('demandes', 'demande(s) d''accès en attente',
      (select count(*)::int from demandes where statut in ('ouverte','en_cours')
        and est_admin()),
      '#/espace/validation', 'normale'),
    ('signalements', 'signalement(s) à examiner',
      (select count(*)::int from signalements s where s.statut in ('ouvert','en_cours')
        and (est_admin() or s.assigne_a = auth.uid())),
      '#/espace/validation', 'haute'),
    ('alertes_rgpd', 'consultation(s) de dossier protégé',
      (select count(*)::int from consultations
        where alerte and vue_le is null and (est_admin() or a_droit('rgpd.alertes'))),
      '#/espace/validation', 'haute'),
    ('alertes_suivi', 'alerte(s) de suivi des usages',
      (select count(*)::int from alertes_suivi
        where vue_le is null and (est_admin() or a_droit('discipline.instruire'))),
      '#/espace/discipline', 'haute'),
    ('recours', 'recours à trancher',
      (select count(*)::int from recours r where r.statut in ('depose','recevable')
        and a_droit('discipline.recours')),
      '#/espace/discipline', 'haute'),
    ('candidatures', 'candidature(s) à examiner',
      (select count(*)::int from conformite_a_traiter()),
      '#/espace/conformite', 'haute'),
    ('actes', 'acte(s) sensible(s) à contrôler',
      (select count(*)::int from actes_sensibles where statut = 'a_controler'
        and est_admin()),
      '#/espace/validation', 'haute'),
    ('publications', 'publication(s) à relayer sur vos réseaux',
      publications_a_relayer(),
      '#/espace/publier', 'normale'),
    ('accueil', 'nouvel(le)(s) adhérent(s) à accueillir',
      (select count(*)::int from nouveaux_a_accueillir_maj(null) where sans_nouvelles),
      '#/espace/parcours', 'haute'),
    ('notes_avis', 'note(s) de frais en attente de votre avis',
      (select count(*)::int from notes_frais n where n.statut = 'deposee'
        and puis_je_instruire(n.id)),
      '#/espace/tresorerie', 'normale'),
    ('notes_instruire', 'note(s) de frais à instruire',
      (select count(*)::int from notes_frais where statut = 'deposee'
        and a_droit('finance.instruire')),
      '#/espace/tresorerie', 'normale'),
    ('notes_ordonnancer', 'dépense(s) à ordonnancer',
      (select count(*)::int from notes_frais where statut = 'instruite'
        and est_ordonnateur()),
      '#/espace/ordonnancement', 'normale'),
    ('notes_payer', 'paiement(s) à exécuter',
      (select count(*)::int from notes_frais where statut = 'ordonnancee'
        and a_droit('finance.payer')),
      '#/espace/tresorerie', 'normale'),
    ('virements', 'paiement(s) sans accusé depuis 15 jours',
      (select count(*)::int from virements_a_suivre()
        where etat in ('conteste','sans_reponse')),
      '#/espace/tresorerie', 'haute'),
    ('propositions', 'proposition(s) d''adhérent sans réponse',
      (select count(*)::int from propositions pr
        where pr.statut = 'deposee'
          and (est_admin() or mon_niveau() >= 50)
          and dans_mon_perimetre(pr.territoire_id)),
      '#/espace/comite', 'normale'),
    ('taches', 'tâche(s) qui vous sont assignées',
      (select count(*)::int from gt_taches
        where assigne_a = auth.uid() and statut in ('a_faire','en_cours')),
      '#/espace/groupes', 'normale'),
    ('invitations', 'invitation(s) à un groupe de travail',
      (select count(*)::int from gt_membres
        where profil_id = auth.uid() and statut = 'invite'),
      '#/espace/groupes', 'normale'),
    ('scrutins', 'scrutin(s) où vous n''avez pas voté',
      (select count(*)::int from mes_assemblees()
        where statut = 'scrutin' and electeur and not a_vote),
      '#/espace/assemblees', 'haute'),
    ('interims', 'intérim(s) qui vous sont proposés',
      (select count(*)::int from mes_interims()
        where statut = 'propose' and je_suis_interimaire),
      '#/espace/habilitations', 'normale'),
    ('messages', 'conversation(s) non lue(s)',
      (select count(*)::int from mes_conversations() c where c.non_lus > 0),
      '#/espace/messagerie', 'normale')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

-- ---------------------------------------------------------------------
-- 3. LES PUBLICATIONS DANS « MON COMITÉ »
--    Là où l'équipe locale regarde déjà.
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
        'depuis', n.debut, 'jusqu_au', n.fin, 'echelon', p.echelon)
        order by case po.code when 'president_structure' then 1
                              when 'tresorier_structure' then 2
                              when 'secretaire_structure' then 3 else 4 end)
      from nominations n
      join postes po on po.code = n.poste
      join profils p on p.id = n.profil_id
      join moi on moi.terr = n.territoire_id
      where nomination_active(n) and po.code like '%_structure'), '[]'::jsonb),

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

    -- Ce qu'il y a à relayer, pour ceux qui le peuvent.
    'a_relayer', case when mon_niveau() >= 40 then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sd.id, 'titre', sd.titre, 'contexte', sd.contexte,
        'priorite', sd.priorite, 'a_publier_le', sd.a_publier_le,
        'visuel', sd.visuel, 'canaux', sd.canaux)
        order by case sd.priorite when 'urgente' then 1
                                  when 'importante' then 2 else 3 end,
                 sd.a_publier_le nulls last)
      from suggestions_disponibles() sd
      where not sd.je_lai_reprise), '[]'::jsonb) else '[]'::jsonb end,

    'je_pilote', (select mon_niveau() >= 50 or est_admin()
                  or exists (select 1 from nominations n, moi
                             where n.profil_id = auth.uid() and nomination_active(n)
                               and n.territoire_id = moi.terr))
  );
$$;

grant execute on function publications_a_relayer(), ce_qui_attend(), mon_comite(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 25
--
--  Vérifications :
--    select * from ce_qui_attend();
--    select mon_comite() -> 'a_relayer';
--
--  Le principe : un outil qu'il faut penser à ouvrir n'est pas
--  utilisé. Ce qui attend une action doit apparaître là où la personne
--  regarde déjà — sa table de contrôle, et son comité.
-- =====================================================================
