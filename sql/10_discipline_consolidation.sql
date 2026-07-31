-- =====================================================================
--  FFCE — Migration 10 — DISCIPLINE : CONSOLIDATION JURIDIQUE
--
--  Cinq manques comblés, tous tenus par la base et non par l'interface.
--
--  1. CLÔTURE VERROUILLANTE. Un dossier clos est scellé : plus aucune
--     pièce, mesure ou recours ne peut y être versé. Sans cela, un
--     dossier peut être réécrit après décision — ce qui vide la
--     procédure de son sens.
--
--  2. LIMITATION DES RECOURS. Un seul recours gracieux par mesure, sauf
--     décision contraire. On ne rejuge pas indéfiniment le même acte.
--
--  3. RENONCIATION. L'intéressé peut renoncer à ses voies de recours
--     gracieux, ce qui met fin aux recours en cours et clôt le délai.
--     Elle est écrite, datée, versée au dossier, et irréversible.
--
--  4. PIÈCES JOINTES. Documents téléversés des deux côtés, dans un
--     dépôt privé.
--
--  5. REGISTRE EXPORTABLE. La direction des affaires juridiques tient
--     un registre sauvegardé. Elle doit pouvoir l'extraire en entier.
--
--  Prérequis : 01 à 09.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. NOUVEAUX CHAMPS
-- ---------------------------------------------------------------------

alter table mesures add column if not exists max_recours integer not null default 1;
alter table mesures add column if not exists renonce_le timestamptz;
alter table mesures add column if not exists renonce_texte text;

alter table dossiers add column if not exists scelle_le timestamptz;

alter table recours drop constraint if exists recours_statut_check;
alter table recours add constraint recours_statut_check
  check (statut in ('depose','recevable','irrecevable','accepte','rejete','partiel','retire'));

-- ---------------------------------------------------------------------
-- 2. LE RECOURS, BORNÉ
--    Trois conditions cumulatives : la mesure est notifiée, le délai
--    court encore, et le quota n'est pas épuisé.
-- ---------------------------------------------------------------------

create or replace function recours_deja_formes(p_mesure uuid)
returns integer language sql stable security definer set search_path = public as $$
  select count(*)::int from recours
   where mesure_id = p_mesure and statut <> 'retire';
$$;

create or replace function recours_ouvert(m mesures)
returns boolean language sql stable security definer set search_path = public as $$
  select m.notifiee_le is not null
     and m.renonce_le is null
     and m.type <> 'classement'
     and m.statut not in ('annulee','echue')
     and (limite_recours(m) is null or limite_recours(m) >= current_date)
     and recours_deja_formes(m.id) < m.max_recours
     and not exists (select 1 from dossiers d
                     where d.id = m.dossier_id and d.statut = 'clos');
$$;

-- Pourquoi le recours est-il fermé ? L'intéressé a droit à la raison.
create or replace function motif_fermeture_recours(m mesures)
returns text language sql stable security definer set search_path = public as $$
  select case
    when m.notifiee_le is null then 'La décision ne vous a pas encore été notifiée.'
    when m.renonce_le is not null then
      'Vous avez renoncé à vos voies de recours gracieux le ' ||
      to_char(m.renonce_le, 'DD/MM/YYYY') || '.'
    when m.type = 'classement' then 'Un classement sans suite ne fait pas grief.'
    when m.statut in ('annulee','echue') then 'Cette mesure ne produit plus d''effet.'
    when exists (select 1 from dossiers d where d.id = m.dossier_id and d.statut = 'clos')
      then 'Le dossier est clos.'
    when recours_deja_formes(m.id) >= m.max_recours then
      'Vous avez épuisé les voies de recours gracieux pour cette décision.'
    when limite_recours(m) < current_date then
      'Le délai de recours a expiré le ' || to_char(limite_recours(m), 'DD/MM/YYYY') || '.'
    else null end;
$$;

-- ---------------------------------------------------------------------
-- 3. RENONCIATION
--    Un acte grave : il ferme définitivement la voie gracieuse. Il est
--    donc écrit, daté, versé au dossier, et sans retour.
-- ---------------------------------------------------------------------

create or replace function renoncer_gracieux(p_dossier uuid, p_texte text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_nb int;
begin
  if not exists (select 1 from dossiers where id = p_dossier and profil_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Ce dossier ne vous concerne pas.');
  end if;
  if exists (select 1 from dossiers where id = p_dossier and statut = 'clos') then
    return jsonb_build_object('ok', false, 'message', 'Ce dossier est clos.');
  end if;
  if coalesce(trim(p_texte),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'La renonciation doit être écrite de votre main.');
  end if;

  -- Les recours en cours sont retirés.
  update recours r set statut = 'retire',
         decision = 'Retiré à la suite de la renonciation de l''intéressé',
         decide_le = now()
   from mesures m
   where m.id = r.mesure_id and m.dossier_id = p_dossier
     and r.auteur_id = auth.uid() and r.statut in ('depose','recevable');

  update mesures set renonce_le = now(), renonce_texte = trim(p_texte)
   where dossier_id = p_dossier and notifiee_le is not null and renonce_le is null;
  get diagnostics v_nb = row_count;

  insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
  values (p_dossier, 'recours', 'Renonciation aux voies de recours gracieux',
          trim(p_texte), auth.uid(), true);

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'renonciation_gracieuse', p_dossier::text,
          jsonb_build_object('mesures', v_nb));

  return jsonb_build_object('ok', true, 'mesures', v_nb);
end $$;

-- ---------------------------------------------------------------------
-- 4. CLÔTURE VERROUILLANTE
--    Le déclencheur est la garantie. Une interface peut être contournée ;
--    une contrainte de base ne l'est pas.
-- ---------------------------------------------------------------------

create or replace function refuser_si_scelle()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_dossier uuid; v_statut text;
begin
  v_dossier := case tg_table_name
    when 'dossier_pieces' then new.dossier_id
    when 'mesures'        then new.dossier_id
    when 'recours'        then (select dossier_id from mesures where id = new.mesure_id)
  end;

  select statut into v_statut from dossiers where id = v_dossier;
  if v_statut = 'clos' then
    raise exception 'Ce dossier est clos. Plus aucune pièce ne peut y être versée.';
  end if;
  return new;
end $$;

drop trigger if exists trg_scelle_pieces on dossier_pieces;
create trigger trg_scelle_pieces before insert on dossier_pieces
  for each row execute function refuser_si_scelle();

drop trigger if exists trg_scelle_mesures on mesures;
create trigger trg_scelle_mesures before insert on mesures
  for each row execute function refuser_si_scelle();

drop trigger if exists trg_scelle_recours on recours;
create trigger trg_scelle_recours before insert on recours
  for each row execute function refuser_si_scelle();

-- Clore : on refuse tant qu'un recours attend, sauf à le trancher.
create or replace function clore_dossier(p_dossier uuid, p_conclusion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_concerne uuid; v_recours int;
begin
  if not a_droit('discipline.decider') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au conseil de discipline.');
  end if;
  if coalesce(trim(p_conclusion),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'La clôture doit être motivée.');
  end if;

  select count(*) into v_recours
    from recours r join mesures m on m.id = r.mesure_id
   where m.dossier_id = p_dossier and r.statut in ('depose','recevable');
  if v_recours > 0 then
    return jsonb_build_object('ok', false,
      'message', v_recours || ' recours attend d''être tranché. Statuez avant de clore.');
  end if;

  insert into dossier_pieces (dossier_id, type, titre, contenu, auteur_id, communicable)
  values (p_dossier, 'decision', 'Clôture du dossier', trim(p_conclusion), auth.uid(), true);

  update dossiers
     set statut = 'clos', clos_le = now(), clos_par = auth.uid(),
         conclusion = trim(p_conclusion), scelle_le = now()
   where id = p_dossier
  returning profil_id into v_concerne;

  if not exists (select 1 from dossiers where profil_id = v_concerne and statut <> 'clos') then
    update profils set protege = false, motif_protection = null
     where id = v_concerne and motif_protection = 'Dossier disciplinaire en cours';
  end if;

  insert into journal (acteur, action, cible) values (auth.uid(), 'dossier_clos', p_dossier::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. LE REGISTRE, EXPORTABLE
--    La DAJ a dans sa mission de tenir un registre sauvegardé. Elle
--    doit pouvoir l'extraire en entier, y compris les dossiers clos.
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre)
values ('discipline.exporter', 'Extraire le registre disciplinaire', 'Discipline', true, 155)
on conflict (code) do nothing;

insert into poste_droits (poste, droit) values ('daj','discipline.exporter')
on conflict do nothing;

create or replace function registre_discipline()
returns table (
  reference text, ouvert_le timestamptz, clos_le timestamptz, statut text,
  gravite text, origine text, objet text, qualification text, conclusion text,
  concerne text, matricule text, territoire text, fonction text,
  ouvert_par text, mesure_type text, mesure_motif text, mesure_statut text,
  mesure_effet date, mesure_fin date, notifiee_le timestamptz,
  accusee_le timestamptz, renonce_le timestamptz,
  recours_statut text, recours_le timestamptz, recours_decision text,
  nb_pieces integer, nb_pieces_non_communicables integer
) language sql stable security definer set search_path = public as $$
  select d.reference, d.ouvert_le, d.clos_le, d.statut, d.gravite, d.origine,
         d.objet, d.qualification, d.conclusion,
         trim(p.prenom || ' ' || p.nom), p.matricule, t.nom, f.nom,
         trim(o.prenom || ' ' || o.nom),
         m.type, m.motif, m.statut, m.date_effet, m.date_fin,
         m.notifiee_le, m.accusee_le, m.renonce_le,
         r.statut, r.cree_le, r.decision,
         (select count(*)::int from dossier_pieces x where x.dossier_id = d.id),
         (select count(*)::int from dossier_pieces x
           where x.dossier_id = d.id and not x.communicable)
  from dossiers d
  join profils p    on p.id = d.profil_id
  join fonctions f  on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  left join profils o on o.id = d.ouvert_par
  left join mesures m on m.dossier_id = d.id
  left join recours r on r.mesure_id = m.id
  where a_droit('discipline.exporter')
  order by d.ouvert_le desc, m.prise_le, r.cree_le;
$$;

-- Chaque extraction est tracée : c'est une sortie massive de données
-- sensibles, elle ne doit pas être silencieuse.
create or replace function tracer_export(p_objet text, p_lignes integer)
returns void language sql security definer set search_path = public as $$
  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'export_registre', p_objet,
          jsonb_build_object('lignes', p_lignes));
$$;

-- ---------------------------------------------------------------------
-- 6. CE QUI ATTEND, POUR LE TABLEAU DE BORD
--    Les alertes de suivi passaient inaperçues au fond d'un onglet.
--    Cette fonction remonte tout ce qui attend une action de ma part.
-- ---------------------------------------------------------------------

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
    ('taches', 'tâche(s) qui vous sont assignées',
      (select count(*)::int from gt_taches
        where assigne_a = auth.uid() and statut in ('a_faire','en_cours')),
      '#/espace/groupes', 'normale'),
    ('invitations', 'invitation(s) à un groupe de travail',
      (select count(*)::int from gt_membres
        where profil_id = auth.uid() and statut = 'invite'),
      '#/espace/groupes', 'normale'),
    ('messages', 'conversation(s) non lue(s)',
      (select count(*)::int from mes_conversations() c where c.non_lus > 0),
      '#/espace/messagerie', 'normale')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

-- ---------------------------------------------------------------------
-- 7. PIÈCES JOINTES
--    Le dépôt existe depuis la migration 08. On ouvre l'écriture à
--    l'intéressé, dans son propre dossier, ce qui était déjà le cas.
-- ---------------------------------------------------------------------

create or replace function url_piece(p_piece uuid)
returns text language sql stable security definer set search_path = public as $$
  select pc.fichier from dossier_pieces pc
  where pc.id = p_piece
    and (a_droit('discipline.instruire') or a_droit('discipline.decider')
         or a_droit('discipline.recours')
         or (pc.communicable and exists (select 1 from dossiers d
             where d.id = pc.dossier_id and d.profil_id = auth.uid())));
$$;

-- ---------------------------------------------------------------------
-- 8. DROITS
-- ---------------------------------------------------------------------

grant execute on function recours_deja_formes(uuid), recours_ouvert(mesures),
                          motif_fermeture_recours(mesures),
                          renoncer_gracieux(uuid, text), clore_dossier(uuid, text),
                          registre_discipline(), tracer_export(text, integer),
                          ce_qui_attend(), url_piece(uuid)
  to authenticated;

-- ---------------------------------------------------------------------
-- 9. LA VUE DE L'INTÉRESSÉ, ENRICHIE
-- ---------------------------------------------------------------------

create or replace function mon_dossier()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'statut_compte', (select statut from profils where id = auth.uid()),
    'sous_suivi',    (select sous_suivi from profils where id = auth.uid()),
    'dossiers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'reference', d.reference, 'objet', d.objet,
        'qualification', d.qualification, 'gravite', d.gravite,
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
            'texte', m.texte_decision, 'statut', m.statut,
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
                'decision', rc.decision, 'cree_le', rc.cree_le,
                'decide_le', rc.decide_le) order by rc.cree_le)
              from recours rc where rc.mesure_id = m.id), '[]'::jsonb))
            order by m.prise_le desc)
          from mesures m where m.dossier_id = d.id and m.notifiee_le is not null),
          '[]'::jsonb))
        order by d.ouvert_le desc)
      from dossiers d where d.profil_id = auth.uid()), '[]'::jsonb)
  );
$$;

grant execute on function mon_dossier() to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 10
--
--  Pour porter à deux le nombre de recours possibles sur une mesure :
--    update mesures set max_recours = 2 where id = '…';
--
--  Vérifications :
--    select * from ce_qui_attend();
--    select count(*) from registre_discipline();
--
--  Le point à ne jamais assouplir : la clôture scelle. Trois
--  déclencheurs l'imposent sur les pièces, les mesures et les recours.
--  Une interface se contourne ; une contrainte de base, non.
-- =====================================================================
