-- =====================================================================
--  FFCE — Migration 36 — LA DÉPENSE ET L'ENGAGEMENT
--
--  Deux choses.
--
--  1. Une note de frais se jouait en tout ou rien : instruite ou
--     refusée. Or l'instructeur a rarement un doute sur la note entière
--     — il en a un sur une ligne. Il refusait donc tout, et le déposant
--     recommençait tout. On introduit l'état des lignes : retenue,
--     écartée, à préciser. Une note peut alors revenir à son auteur pour
--     complément sans perdre ce qui était acquis.
--
--     Conséquence importante : le total ne compte plus les lignes
--     écartées. Sans cela, on paierait ce qu'on a refusé.
--
--  2. Le déposant ne voyait qu'un mot — « déposée », « instruite » — sans
--     savoir ce qui restait ni qui l'avait entre les mains. Un suivi
--     d'étapes, comme pour les recours, dit où en est le dossier.
--
--  3. « Mon engagement » listait des choses sans les totaliser. Il dit
--     désormais ce que la personne a accompli dans l'année, d'où
--     viennent ses heures — déclarées ou attestées par un bilan — et ce
--     qui la sépare de l'échelon suivant. Rien de nouveau n'est stocké :
--     tout existait déjà, dispersé.
--
--  Prérequis : 01 à 35.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. L'ÉTAT D'UNE LIGNE
-- ---------------------------------------------------------------------

alter table nf_lignes add column if not exists etat text not null default 'proposee';
alter table nf_lignes drop constraint if exists nf_lignes_etat_check;
alter table nf_lignes add constraint nf_lignes_etat_check
  check (etat in ('proposee','retenue','ecartee','a_preciser'));
alter table nf_lignes add column if not exists observation text;

alter table notes_frais drop constraint if exists notes_frais_statut_check;
alter table notes_frais add constraint notes_frais_statut_check
  check (statut in ('brouillon','deposee','a_completer','instruite',
                    'validee','payee','refusee'));

alter table notes_frais add column if not exists demande_precisions text;
alter table notes_frais add column if not exists precisions_le timestamptz;

-- Le total ignore ce qui a été écarté. C'est la seule définition qui
-- puisse servir à la fois d'affichage et de montant payé.
create or replace function total_note(p_note uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(montant_ligne(l)), 0)
  from nf_lignes l where l.note_id = p_note and l.etat <> 'ecartee';
$$;

-- Ce qui a été écarté, pour que le déposant sache ce qu'il ne touchera pas.
create or replace function total_ecarte(p_note uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(montant_ligne(l)), 0)
  from nf_lignes l where l.note_id = p_note and l.etat = 'ecartee';
$$;

-- ---------------------------------------------------------------------
-- 2. INSTRUIRE LIGNE À LIGNE
-- ---------------------------------------------------------------------

create or replace function observer_ligne(p_ligne uuid, p_etat text,
                                          p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_note uuid; v_statut text;
begin
  select l.note_id, n.statut into v_note, v_statut
    from nf_lignes l join notes_frais n on n.id = l.note_id
   where l.id = p_ligne;
  if v_note is null then
    return jsonb_build_object('ok', false, 'message', 'Ligne introuvable.');
  end if;
  if v_statut not in ('deposee','a_completer') then
    return jsonb_build_object('ok', false,
      'message', 'Cette note n''est plus en cours d''instruction.');
  end if;
  if not (puis_je_instruire(v_note) or est_tresorier() or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'Cette note ne relève pas de votre périmètre.');
  end if;
  if p_etat not in ('proposee','retenue','ecartee','a_preciser') then
    return jsonb_build_object('ok', false, 'message', 'État inconnu.');
  end if;
  -- Écarter ou demander une précision, c'est décider : cela se motive.
  if p_etat in ('ecartee','a_preciser') and coalesce(trim(p_observation),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites pourquoi : sans motif, le déposant ne peut rien corriger.');
  end if;

  update nf_lignes
     set etat = p_etat, observation = nullif(trim(p_observation),'')
   where id = p_ligne;
  return jsonb_build_object('ok', true, 'total', total_note(v_note),
                            'ecarte', total_ecarte(v_note));
end $$;

-- Renvoyer la note pour complément, sans perdre ce qui est acquis.
create or replace function demander_precisions(p_note uuid, p_message text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if not (puis_je_instruire(p_note) or est_tresorier() or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'Cette note ne relève pas de votre périmètre.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'deposee') then
    return jsonb_build_object('ok', false,
      'message', 'Cette note n''est pas en attente d''instruction.');
  end if;
  if coalesce(trim(p_message),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Dites ce que vous attendez, sinon la demande est incompréhensible.');
  end if;

  select count(*) into v_n from nf_lignes
   where note_id = p_note and etat = 'a_preciser';
  if v_n = 0 then
    return jsonb_build_object('ok', false,
      'message', 'Marquez d''abord les lignes à préciser : une demande porte sur quelque chose.');
  end if;

  update notes_frais
     set statut = 'a_completer', demande_precisions = trim(p_message),
         precisions_le = now(), instruit_par = auth.uid()
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_precisions', p_note::text,
          jsonb_build_object('lignes', v_n));
  return jsonb_build_object('ok', true, 'lignes', v_n);
end $$;

-- Le déposant renvoie sa note corrigée. Les lignes qu'il a reprises
-- redeviennent proposées : l'instructeur les réexamine.
create or replace function completer_note(p_note uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sans integer;
begin
  if not exists (select 1 from notes_frais
                 where id = p_note and profil_id = auth.uid() and statut = 'a_completer') then
    return jsonb_build_object('ok', false,
      'message', 'Cette note n''attend pas de complément de votre part.');
  end if;

  select count(*) into v_sans from nf_lignes
   where note_id = p_note and categorie <> 'kilometres'
     and etat <> 'ecartee' and coalesce(justificatif,'') = '';
  if v_sans > 0 then
    return jsonb_build_object('ok', false,
      'message', v_sans || ' dépense(s) sans justificatif. Joignez-les avant de renvoyer.');
  end if;

  update nf_lignes set etat = 'proposee'
   where note_id = p_note and etat = 'a_preciser';
  update notes_frais set statut = 'deposee', deposee_le = now()
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_completee', p_note::text,
          jsonb_build_object('total', total_note(p_note)));
  return jsonb_build_object('ok', true, 'total', total_note(p_note));
end $$;

-- L'instruction ne peut plus laisser une ligne sans décision : ce qui
-- reste « proposé » au moment de conclure est réputé retenu, mais on le
-- dit explicitement plutôt que de le laisser entendre.
create or replace function instruire_note(p_note uuid, p_favorable boolean, p_avis text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not puis_je_instruire(p_note) then
    return jsonb_build_object('ok', false,
      'message', 'Cette note ne relève pas de votre périmètre.');
  end if;
  if not exists (select 1 from notes_frais where id = p_note and statut = 'deposee') then
    return jsonb_build_object('ok', false,
      'message', 'Cette note n''est pas en attente d''instruction.');
  end if;
  if not p_favorable and coalesce(trim(p_avis),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un avis défavorable doit être motivé.');
  end if;
  if p_favorable and total_note(p_note) <= 0 then
    return jsonb_build_object('ok', false,
      'message', 'Toutes les lignes sont écartées : il n''y a plus rien à instruire favorablement.');
  end if;

  if p_favorable then
    update nf_lignes set etat = 'retenue'
     where note_id = p_note and etat in ('proposee','a_preciser');
  end if;

  update notes_frais
     set statut = case when p_favorable then 'instruite' else 'refusee' end,
         instruit_par = auth.uid(), instruit_le = now(),
         avis = nullif(trim(p_avis),''),
         motif_refus = case when p_favorable then null else trim(p_avis) end
   where id = p_note;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'note_instruite', p_note::text,
          jsonb_build_object('favorable', p_favorable,
                             'retenu', total_note(p_note),
                             'ecarte', total_ecarte(p_note)));
  return jsonb_build_object('ok', true);
end $$;

-- Le déposant retrouve la main sur les lignes à préciser.
drop policy if exists ecrire_lignes on nf_lignes;
create policy ecrire_lignes on nf_lignes for all using (
  exists (select 1 from notes_frais n where n.id = note_id
          and n.profil_id = auth.uid()
          and (n.statut = 'brouillon'
               or (n.statut = 'a_completer' and nf_lignes.etat = 'a_preciser')))
) with check (
  exists (select 1 from notes_frais n where n.id = note_id
          and n.profil_id = auth.uid()
          and n.statut in ('brouillon','a_completer'))
);

-- ---------------------------------------------------------------------
-- 3. OÙ EN EST MA NOTE
--    Les mêmes étapes pour tout le monde, dans le même ordre, avec le
--    nom de qui les a franchies. Un dossier arrêté s'arrête visiblement.
-- ---------------------------------------------------------------------

drop function if exists suivi_note(uuid);
create or replace function suivi_note(p_note uuid)
returns table (rang integer, etape text, etat text, quand timestamptz,
               par text, detail text)
language sql stable security definer set search_path = public as $$
  with n as (select * from notes_frais where id = p_note and accede_note(p_note))
  select * from (
    select 1, 'Dépôt',
      case when (select statut from n) = 'brouillon' then 'en_cours' else 'fait' end,
      (select deposee_le from n),
      (select trim(p.prenom || ' ' || p.nom) from profils p, n where p.id = n.profil_id),
      'La note est constituée et les justificatifs joints.'
    union all
    select 2, 'Instruction',
      case (select statut from n)
        when 'brouillon' then 'a_venir'
        when 'deposee' then 'en_cours'
        when 'a_completer' then 'suspendu'
        when 'refusee' then 'arrete'
        else 'fait' end,
      (select instruit_le from n),
      (select trim(p.prenom || ' ' || p.nom) from profils p, n where p.id = n.instruit_par),
      coalesce((select demande_precisions from n where n.statut = 'a_completer'),
               (select motif_refus from n),
               (select avis from n),
               'Votre responsable vérifie le bien-fondé de la dépense.')
    union all
    select 3, 'Ordonnancement',
      case (select statut from n)
        when 'validee' then 'fait' when 'payee' then 'fait'
        when 'instruite' then 'en_cours'
        when 'refusee' then 'arrete' else 'a_venir' end,
      (select valide_le from n),
      (select trim(p.prenom || ' ' || p.nom) from profils p, n where p.id = n.valide_par),
      'L''ordonnateur autorise la dépense. Il ne peut pas être celui qui paie.'
    union all
    select 4, 'Paiement',
      case (select statut from n)
        when 'payee' then 'fait'
        when 'validee' then 'en_cours'
        when 'refusee' then 'arrete' else 'a_venir' end,
      (select payee_le from n),
      null,
      coalesce('Virement ' || (select reference_paiement from n),
               'Le virement est exécuté par la trésorerie.')
  ) as x(rang, etape, etat, quand, par, detail)
  where exists (select 1 from n)
  order by rang;
$$;

-- La liste des notes porte désormais le montant écarté et la demande
-- de précisions : sans quoi l'écran devrait les recalculer lui-même.
drop function if exists v_notes(text);
create or replace function v_notes(p_filtre text default 'miennes')
returns table (
  id uuid, reference text, objet text, statut text, total numeric,
  ecarte numeric, nb_lignes integer, cree_le timestamptz, deposee_le timestamptz,
  profil_id uuid, deposant text, matricule text, territoire_nom text,
  groupe_nom text, avis text, motif_refus text, reference_paiement text,
  instruit_nom text, valide_nom text, demande_precisions text
) language sql stable security definer set search_path = public as $$
  select n.id, n.reference, n.objet, n.statut, total_note(n.id), total_ecarte(n.id),
         (select count(*)::int from nf_lignes l where l.note_id = n.id),
         n.cree_le, n.deposee_le,
         n.profil_id, trim(p.prenom || ' ' || p.nom), p.matricule, t.nom,
         g.nom, n.avis, n.motif_refus, n.reference_paiement,
         trim(i.prenom || ' ' || i.nom), trim(v.prenom || ' ' || v.nom),
         n.demande_precisions
  from notes_frais n
  join profils p on p.id = n.profil_id
  left join territoires t     on t.id = p.territoire_id
  left join groupes_travail g on g.id = n.groupe_id
  left join profils i on i.id = n.instruit_par
  left join profils v on v.id = n.valide_par
  where case p_filtre
    when 'miennes'   then n.profil_id = auth.uid()
    when 'instruire' then n.statut = 'deposee' and puis_je_instruire(n.id)
    when 'tresorerie'then est_tresorier() and n.statut in ('instruite','validee')
    when 'toutes'    then est_tresorier() or est_admin()
    else false end
  order by n.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 4. MON ENGAGEMENT
--    Ce qui existait est conservé. S'y ajoutent le cumul de l'année, la
--    part attestée des heures, et la distance à l'échelon suivant.
--    Rien n'est stocké : tout se recalcule à la lecture.
-- ---------------------------------------------------------------------

create or replace function mon_engagement()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mois', date_trunc('month', current_date)::date,
    'heures_visees', coalesce((select heures_visees from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date), 0),
    'heures_realisees', (select heures_realisees from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date),
    'declare', exists (select 1 from engagements
      where profil_id = auth.uid() and mois = date_trunc('month', current_date)::date),

    -- Ce que l'année cumule. Les heures attestées viennent des bilans de
    -- mission : c'est la même source que l'engagement mensuel, jamais un
    -- second compteur.
    'annee', jsonb_build_object(
      'heures', coalesce((select sum(e.heures_realisees) from engagements e
        where e.profil_id = auth.uid()
          and e.mois >= date_trunc('year', current_date)::date), 0),
      'heures_visees', coalesce((select sum(e.heures_visees) from engagements e
        where e.profil_id = auth.uid()
          and e.mois >= date_trunc('year', current_date)::date), 0),
      'heures_attestees', coalesce((select sum(b.heures) from bilans_mission b
        where b.profil_id = auth.uid()
          and b.cree_le >= date_trunc('year', current_date)), 0),
      'missions', (select count(*)::int from bilans_mission b
        where b.profil_id = auth.uid()
          and b.cree_le >= date_trunc('year', current_date)),
      'taches_faites', (select count(*)::int from gt_taches k
        where k.assigne_a = auth.uid() and k.statut = 'faite'
          and k.faite_le >= date_trunc('year', current_date)),
      'formations', (select count(*)::int from certifications_obtenues c
        where c.profil_id = auth.uid()
          and c.obtenue_le >= date_trunc('year', current_date)::date)),

    -- La progression, telle que la chancellerie la calcule. On ne
    -- recalcule pas : on cite.
    'progression', points_membre(),

    'historique', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mois', e.mois, 'visees', e.heures_visees, 'realisees', e.heures_realisees)
        order by e.mois desc)
      from engagements e where e.profil_id = auth.uid()
        and e.mois >= (date_trunc('month', current_date) - interval '11 months')::date),
      '[]'::jsonb),
    'taches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'titre', k.titre, 'echeance', k.echeance,
        'priorite', k.priorite, 'statut', k.statut, 'groupe', g.nom,
        'groupe_id', g.id,
        'retard', k.echeance is not null and k.echeance < current_date)
        order by k.echeance nulls last)
      from gt_taches k join groupes_travail g on g.id = k.groupe_id
      where k.assigne_a = auth.uid() and k.statut in ('a_faire','en_cours')),
      '[]'::jsonb),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'titre', m.titre, 'debut', m.debut, 'fin', m.fin, 'lieu', m.lieu,
        'statut', c.statut) order by m.debut nulls last)
      from mission_candidatures c join missions m on m.id = c.mission_id
      where c.profil_id = auth.uid() and c.statut in ('candidat','retenu')
        and (m.fin is null or m.fin >= current_date)),
      '[]'::jsonb),
    'formations_en_cours', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'titre', f.titre, 'pourcent', av.pourcent))
      from formations f
      cross join lateral avancement(f.id) av
      where f.publiee and av.pourcent between 1 and 99),
      '[]'::jsonb),
    'missions_disponibles', (select count(*)::int from missions_ouvertes()
      where obstacle is null and ma_candidature is null),
    'bilans_a_rediger', (select count(*)::int from bilans_a_rediger())
  );
$$;

grant execute on function total_note(uuid), total_ecarte(uuid),
                          observer_ligne(uuid, text, text),
                          demander_precisions(uuid, text), completer_note(uuid),
                          instruire_note(uuid, boolean, text),
                          suivi_note(uuid), v_notes(text), mon_engagement()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 36
--
--  Vérifications :
--    select * from suivi_note('<uuid>');
--    select reference, total, ecarte, statut from v_notes('miennes');
--    select mon_engagement()->'annee', mon_engagement()->'progression';
--
--  Sur le total : il ignore les lignes écartées. Toute lecture du
--  montant — affichage, contrôle de plafond, ordonnancement, paiement —
--  passe par `total_note`, donc aucune ne peut diverger d'une autre.
--
--  Sur le renvoi pour complément : il exige d'avoir marqué au moins une
--  ligne à préciser. Une demande qui ne porte sur rien n'est pas une
--  demande, c'est un délai.
-- =====================================================================
