-- =====================================================================
--  FFCE — Migration 15 — PILOTAGE UNIFIÉ ET IDENTITÉ DES OUTILS
--
--  Quatre chantiers.
--
--  1. UNE FICHE, PAS CINQ TABLEAUX. Piloter un membre demandait de
--     passer par cinq onglets : réseau, nominations, accès, discipline,
--     engagement. Les grandes fédérations font l'inverse — on ouvre la
--     fiche d'une personne, et tout se fait là.
--
--  2. LES BUREAUX DE STRUCTURE. Un territoire n'est pas qu'un point sur
--     une carte : il a un président, un trésorier, un secrétaire. Ces
--     mandats existent, ils doivent être lisibles.
--
--  3. LE DOSSIER D'ADHÉSION CONDITIONNE LA VALIDATION. On n'active pas
--     un compte dont on ignore tout.
--
--  4. CHAQUE APPLICATION PORTE SON NOM ET SON SIGNE. Une fédération qui
--     nomme ses outils se les approprie.
--
--  Prérequis : 01 à 14.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. IDENTITÉ DES APPLICATIONS
-- ---------------------------------------------------------------------

alter table applications add column if not exists nom_court text;
alter table applications add column if not exists logo text;      -- dépôt public
alter table applications add column if not exists couleur text
  check (couleur is null or couleur in ('bleu','bordeaux','nuit','brun','action','framboise'));
alter table applications add column if not exists accroche text;  -- une ligne, sur la tuile

update applications set couleur = coalesce(couleur, case code
  when 'engagement'    then 'bordeaux'
  when 'formations'    then 'bleu'
  when 'groupes'       then 'bleu'
  when 'messagerie'    then 'action'
  when 'notes_frais'   then 'brun'
  when 'tresorerie'    then 'brun'
  when 'ordonnancement'then 'brun'
  when 'discipline'    then 'nuit'
  when 'communication' then 'framboise'
  else 'bleu' end);

create or replace function regler_application(
  p_code text, p_nom text, p_nom_court text, p_description text,
  p_accroche text, p_couleur text, p_logo text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les applications.');
  end if;
  update applications
     set nom = coalesce(nullif(trim(p_nom),''), nom),
         nom_court = nullif(trim(p_nom_court),''),
         description = coalesce(nullif(trim(p_description),''), description),
         accroche = nullif(trim(p_accroche),''),
         couleur = coalesce(nullif(p_couleur,''), couleur),
         logo = coalesce(nullif(p_logo,''), logo)
   where code = p_code;
  return jsonb_build_object('ok', true);
end $$;

-- On expose le nécessaire au tableau de bord.
-- La fonction gagne des colonnes : PostgreSQL refuse de remplacer une
-- fonction dont le type de retour change. On la supprime d'abord.
drop function if exists mes_applications();
create or replace function mes_applications()
returns table (
  code text, nom text, nom_court text, description text, accroche text,
  logo text, couleur text, externe_url text, ordre integer,
  etat text, ouvert boolean, demande_en_cours boolean
) language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.nom_court, a.description, a.accroche, a.logo,
         coalesce(a.couleur,'bleu'), a.externe_url, a.ordre,
         etat_application(a.code),
         a_acces(a.code),
         exists (select 1 from demandes d
                 where d.profil_id = auth.uid() and d.cible = a.code
                   and d.statut in ('ouverte','en_cours'))
  from applications a
  where a.actif
    and (etat_application(a.code) <> 'invisible' or a_acces(a.code))
  order by a.ordre;
$$;

-- ---------------------------------------------------------------------
-- 2. LES BUREAUX DE STRUCTURE
--    Un territoire a des mandats. Ce sont des postes comme les autres,
--    simplement rattachés à un territoire.
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('structure.animer', 'Animer une structure territoriale', 'Structures', false, 35)
on conflict (code) do nothing;

insert into postes (code, nom, description, couleur, systeme) values
  ('president_structure', 'Président de structure',
   'Préside une unité locale, une délégation départementale ou régionale.', 'or', true),
  ('tresorier_structure', 'Trésorier de structure',
   'Tient les comptes de sa structure et prépare le budget.', 'or', true),
  ('secretaire_structure','Secrétaire de structure',
   'Convoque, rédige les procès-verbaux, tient le registre des délibérations.', 'neutre', true)
on conflict (code) do update set description = excluded.description;

insert into poste_droits (poste, droit) values
  ('president_structure','structure.animer'),
  ('president_structure','membres.consulter'),
  ('tresorier_structure','finance.instruire'),
  ('secretaire_structure','structure.animer')
on conflict do nothing;

-- Le bureau d'un territoire, avec ses vacances.
create or replace function bureau_territoire(p_territoire uuid)
returns table (poste text, poste_nom text, titulaire text, matricule text,
               profil_id uuid, depuis date, fin date)
language sql stable security definer set search_path = public as $$
  select po.code, po.nom,
         trim(p.prenom || ' ' || p.nom), p.matricule, p.id, n.debut, n.fin
  from postes po
  left join nominations n on n.poste = po.code and n.territoire_id = p_territoire
        and nomination_active(n)
  left join profils p on p.id = n.profil_id
  where po.code in ('president_structure','tresorier_structure','secretaire_structure')
  order by case po.code when 'president_structure' then 1
                        when 'tresorier_structure' then 2 else 3 end;
$$;

-- L'état du réseau : combien de membres, quels mandats pourvus, où ça manque.
create or replace function etat_reseau(p_echelle text default 'departement')
returns table (
  territoire_id uuid, territoire text, echelle text, parent text,
  membres integer, actifs integer, encadrants integer,
  president text, tresorier text, secretaire text,
  mandats_pourvus integer, groupes integer, engagement_mois numeric
) language sql stable security definer set search_path = public as $$
  with cible as (
    select t.id, t.nom, t.echelle, pt.nom as parent
    from territoires t left join territoires pt on pt.id = t.parent_id
    where t.echelle = p_echelle and t.actif)
  select c.id, c.nom, c.echelle, c.parent,
         (select count(*)::int from profils p
           where p.territoire_id in (select s.id from territoires_sous(c.id) s)),
         (select count(*)::int from profils p
           where p.territoire_id in (select s.id from territoires_sous(c.id) s)
             and p.statut = 'actif'),
         (select count(*)::int from profils p join fonctions f on f.code = p.fonction
           where p.territoire_id in (select s.id from territoires_sous(c.id) s)
             and p.statut = 'actif' and f.niveau >= 40),
         (select trim(pr.prenom || ' ' || pr.nom) from nominations n
           join profils pr on pr.id = n.profil_id
          where n.territoire_id = c.id and n.poste = 'president_structure'
            and nomination_active(n) limit 1),
         (select trim(pr.prenom || ' ' || pr.nom) from nominations n
           join profils pr on pr.id = n.profil_id
          where n.territoire_id = c.id and n.poste = 'tresorier_structure'
            and nomination_active(n) limit 1),
         (select trim(pr.prenom || ' ' || pr.nom) from nominations n
           join profils pr on pr.id = n.profil_id
          where n.territoire_id = c.id and n.poste = 'secretaire_structure'
            and nomination_active(n) limit 1),
         (select count(*)::int from nominations n
           where n.territoire_id = c.id and nomination_active(n)
             and n.poste in ('president_structure','tresorier_structure','secretaire_structure')),
         (select count(*)::int from groupes_travail g
           where g.territoire_id = c.id and g.statut = 'actif'),
         (select coalesce(sum(e.heures_realisees),0) from engagements e
           join profils p on p.id = e.profil_id
          where p.territoire_id in (select s.id from territoires_sous(c.id) s)
            and e.mois = date_trunc('month', current_date)::date)
  from cible c
  where est_admin() or a_droit('membres.consulter') or mon_niveau() >= 60
  order by c.nom;
$$;

-- ---------------------------------------------------------------------
-- 3. COMPLÉTUDE DU DOSSIER D'ADHÉSION
--    On n'active pas un compte dont on ignore tout. La liste des
--    manques est explicite, des deux côtés.
-- ---------------------------------------------------------------------

create or replace function completude_dossier(p_profil uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (select coalesce(p_profil, auth.uid()) as id),
  p as (select pr.* from profils pr, c where pr.id = c.id),
  a as (select da.* from dossier_adhesion da, c where da.profil_id = c.id),
  manques as (
    select array_remove(array[
      case when coalesce(trim((select prenom from p)),'') = '' then 'Prénom' end,
      case when coalesce(trim((select nom from p)),'') = '' then 'Nom' end,
      case when coalesce(trim((select telephone from p)),'') = '' then 'Téléphone' end,
      case when (select territoire_id from p) is null then 'Département de rattachement' end,
      case when (select date_naissance from a) is null then 'Date de naissance' end,
      case when coalesce(trim((select ville from a)),'') = '' then 'Ville' end,
      case when coalesce(trim((select code_postal from a)),'') = '' then 'Code postal' end,
      case when coalesce(trim((select situation from a)),'') = '' then 'Situation' end,
      case when coalesce(trim((select motivation from a)),'') = '' then 'Motivation' end,
      case when not coalesce((select accepte_statuts from a), false) then 'Acceptation des statuts' end,
      case when not coalesce((select accepte_rgpd from a), false) then 'Politique de confidentialité' end
    ], null) as liste)
  select jsonb_build_object(
    'complet', cardinality(m.liste) = 0,
    'manques', to_jsonb(m.liste),
    'nb_manques', cardinality(m.liste),
    'pourcent', round((11 - cardinality(m.liste))::numeric / 11 * 100)::int)
  from manques m;
$$;

-- La validation d'une inscription passe désormais par ici.
create or replace function valider_inscription(p_profil uuid, p_accepter boolean,
                                               p_forcer boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_comp jsonb;
begin
  if not (est_admin() or a_droit('membres.valider')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne validez pas les inscriptions.');
  end if;

  if p_accepter then
    v_comp := completude_dossier(p_profil);
    if not (v_comp->>'complet')::boolean and not coalesce(p_forcer, false) then
      return jsonb_build_object('ok', false, 'incomplet', true,
        'manques', v_comp->'manques',
        'message', 'Dossier incomplet : ' ||
                   array_to_string(array(select jsonb_array_elements_text(v_comp->'manques')), ', ') || '.');
    end if;
    update profils set statut = 'actif', date_adhesion = current_date where id = p_profil;
  else
    update profils set statut = 'suspendu' where id = p_profil;
  end if;

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), case when p_accepter then 'inscription_validee' else 'inscription_ecartee' end,
          p_profil::text, jsonb_build_object('force', coalesce(p_forcer,false)));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LA FICHE ADMINISTRATIVE UNIFIÉE
--    Tout ce qu'il faut savoir et pouvoir faire sur un membre, en un
--    seul appel et un seul écran.
-- ---------------------------------------------------------------------

create or replace function fiche_admin(p_profil uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (est_admin() or a_droit('membres.nommer')
                        or a_droit('membres.valider'))
    then jsonb_build_object('erreur', 'Réservé au pilotage du réseau.')
    else jsonb_build_object(
      'identite', (select jsonb_build_object(
          'id', p.id, 'matricule', p.matricule, 'prenom', p.prenom, 'nom', p.nom,
          'email', p.email, 'telephone', p.telephone, 'photo_url', p.photo_url,
          'fonction', p.fonction, 'fonction_nom', f.nom, 'niveau', f.niveau,
          'echelon', p.echelon, 'echelon_nom', e.nom,
          'territoire_id', p.territoire_id, 'territoire', t.nom,
          'chemin', chemin_territoire(p.territoire_id),
          'statut', p.statut, 'protege', p.protege, 'sous_suivi', p.sous_suivi,
          'webmail', p.webmail, 'date_adhesion', p.date_adhesion, 'cree_le', p.cree_le)
        from profils p
        join fonctions f on f.code = p.fonction
        join echelons e on e.niveau = p.echelon
        left join territoires t on t.id = p.territoire_id
        where p.id = p_profil),
      'completude', completude_dossier(p_profil),
      'points', points_membre(p_profil),
      'postes', coalesce((select jsonb_agg(jsonb_build_object(
          'nomination_id', n.id, 'poste', po.code, 'nom', po.nom,
          'couleur', po.couleur, 'territoire', tn.nom, 'debut', n.debut, 'fin', n.fin))
        from nominations n join postes po on po.code = n.poste
        left join territoires tn on tn.id = n.territoire_id
        where n.profil_id = p_profil and nomination_active(n)), '[]'::jsonb),
      'acces', coalesce((select jsonb_agg(jsonb_build_object(
          'application', x.application, 'nom', ap.nom, 'statut', x.statut,
          'expire_le', x.expire_le, 'motif', x.motif,
          'derniere_utilisation', (select max(j.cree_le) from journal_acces j
             where j.profil_id = p_profil and j.application = x.application)))
        from acces_applications x join applications ap on ap.code = x.application
        where x.profil_id = p_profil), '[]'::jsonb),
      'formations', coalesce((select jsonb_agg(jsonb_build_object(
          'nom', c.nom, 'obtenue_le', co.obtenue_le, 'expire_le', co.expire_le))
        from certifications_obtenues co join certifications c on c.code = co.code
        where co.profil_id = p_profil), '[]'::jsonb),
      'groupes', coalesce((select jsonb_agg(jsonb_build_object(
          'nom', g.nom, 'role', m.role))
        from gt_membres m join groupes_travail g on g.id = m.groupe_id
        where m.profil_id = p_profil and m.statut = 'actif'), '[]'::jsonb),
      'dossiers', (select jsonb_build_object(
          'ouverts', count(*) filter (where d.statut <> 'clos'),
          'clos', count(*) filter (where d.statut = 'clos'))
        from dossiers d where d.profil_id = p_profil),
      'adhesion', coalesce((select to_jsonb(da) - 'profil_id'
        from dossier_adhesion da where da.profil_id = p_profil), '{}'::jsonb)
    ) end;
$$;

-- ---------------------------------------------------------------------
-- 5. DROITS
-- ---------------------------------------------------------------------

grant execute on function regler_application(text, text, text, text, text, text, text),
                          mes_applications(), bureau_territoire(uuid),
                          etat_reseau(text), completude_dossier(uuid),
                          valider_inscription(uuid, boolean, boolean),
                          fiche_admin(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 15
--
--  Vérifications :
--    select completude_dossier();
--    select * from etat_reseau('region');
--    select * from bureau_territoire((select id from territoires where code='31'));
--
--  Sur la complétude : la validation peut être forcée, et le forçage
--  est inscrit au journal. Un système qui n'admet aucune exception
--  finit contourné ; mieux vaut la rendre visible.
-- =====================================================================
