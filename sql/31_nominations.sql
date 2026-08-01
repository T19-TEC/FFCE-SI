-- =====================================================================
--  FFCE — Migration 31 — NOMMER, OUVRIR, ACCUEILLIR
--
--  Jusqu'ici, une seule porte : `habilitations.gerer`, un droit sensible
--  que seuls l'administrateur et son délégué détiennent. Conséquence :
--  un président de structure ne pouvait constituer son propre bureau,
--  et l'ouverture d'un nouveau membre remontait systématiquement au
--  national. Ce n'est pas tenable au-delà de quelques dizaines de
--  membres, et ce n'est pas ce que dit le fonctionnement associatif.
--
--  On ouvre donc une seconde voie, dite locale, encadrée par quatre
--  verrous qui tiennent ensemble :
--
--    1. le territoire visé est dans mon périmètre
--    2. la garde hiérarchique joue (`puis_je_agir_sur`)
--    3. le poste conféré pèse strictement moins que le mien
--    4. on ne confère jamais un poste ouvrant un droit sensible
--
--  Et une règle qui vaut pour les accès : on ne donne que ce qu'on a.
--
--  Prérequis : 01 à 30.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE POIDS D'UN POSTE
--    La garde hiérarchique pesait les personnes ; il faut aussi peser
--    les postes, sans quoi « le poste immédiatement inférieur » ne veut
--    rien dire. Le rang suit l'échelle des fonctions : un poste de rang
--    60 se confère par qui pèse plus de 60.
-- ---------------------------------------------------------------------

alter table postes add column if not exists rang integer not null default 40;

comment on column postes.rang is
  'Poids du poste sur l''échelle des fonctions (10-100). Un poste ne se confère que par plus lourd que lui.';

update postes set rang = case code
  when 'delegue_admin'        then 95
  when 'daj'                  then 90
  when 'conseil_discipline'   then 90
  when 'ordonnateur'          then 90
  when 'dg_finance'           then 90
  when 'ref_rgpd'             then 85
  when 'ref_discrimination'   then 85
  when 'conformite_election'  then 85
  when 'chancellerie'         then 85
  when 'dircom'               then 80
  when 'logistique'           then 80
  when 'parcours_adherent'    then 70
  when 'charge_com'           then 60
  when 'president_structure'  then 60
  when 'tresorier_structure'  then 50
  when 'secretaire_structure' then 50
  when 'parcours_local'       then 40
  else rang end;

-- ---------------------------------------------------------------------
-- 2. LE DROIT DE NOMMER CHEZ SOI
--    Non sensible, à la différence de `habilitations.gerer` : il ne
--    permet ni de conférer un droit sensible, ni de sortir de son
--    périmètre. Il ne pèse donc pas dans `poids_membre`.
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('habilitations.local', 'Nommer et ouvrir des accès dans sa structure',
   'Pilotage', false, 195)
on conflict (code) do nothing;

insert into poste_droits (poste, droit) values
  ('president_structure', 'habilitations.local'),
  ('parcours_local',      'habilitations.local')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3. JUSQU'OÙ JE PEUX NOMMER
--    Le plafond retient le plus lourd de mes deux titres : ma fonction
--    et mes postes. Un responsable local (50) sans poste plafonne à 50 ;
--    un président de structure (poste 60) plafonne à 60, même si sa
--    fonction est inférieure. C'est le mandat qui compte, pas le grade.
-- ---------------------------------------------------------------------

create or replace function mon_plafond_nomination()
returns integer language sql stable security definer set search_path = public as $$
  select greatest(
    coalesce(mon_niveau(), 0),
    coalesce((select max(po.rang) from nominations n
              join postes po on po.code = n.poste
              where n.profil_id = auth.uid() and po.actif and nomination_active(n)), 0));
$$;

-- Un poste ouvre-t-il un droit sensible ? Se demande à trois endroits.
create or replace function poste_sensible(p_poste text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(bool_or(d.sensible), false)
  from poste_droits pd join droits d on d.code = pd.droit
  where pd.poste = p_poste;
$$;

-- Les postes que je peux effectivement conférer sur un territoire donné.
-- L'écran s'y limite, et `nommer` revérifie : l'affichage ne peut pas
-- proposer ce que la base refusera.
drop function if exists postes_conferables(uuid);
create or replace function postes_conferables(p_territoire uuid default null)
returns table (code text, nom text, description text, rang integer,
               couleur text, sensible boolean)
language sql stable security definer set search_path = public as $$
  select po.code, po.nom, po.description, po.rang, po.couleur,
         poste_sensible(po.code)
  from postes po
  where po.actif
    and (
      -- Voie nationale : tout, sauf ce que la garde interdira au cas par cas.
      est_admin() or a_droit('habilitations.gerer')
      -- Voie locale : strictement moins lourd que moi, jamais sensible,
      -- et seulement dans mon périmètre.
      or (a_droit('habilitations.local') or mon_niveau() >= 50)
         and po.rang < mon_plafond_nomination()
         and not poste_sensible(po.code)
         and (p_territoire is null or dans_mon_perimetre(p_territoire))
    )
  order by po.rang desc, po.nom;
$$;

-- ---------------------------------------------------------------------
-- 4. NOMMER — LA SECONDE VOIE
--    Mêmes garanties qu'avant sur la voie nationale. La voie locale
--    ajoute ses quatre verrous et se journalise de la même façon.
-- ---------------------------------------------------------------------

create or replace function nommer(
  p_profil uuid, p_poste text, p_territoire uuid default null,
  p_fin date default null, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_refus text; v_national boolean; v_rang integer;
begin
  v_national := est_admin() or a_droit('habilitations.gerer');

  if not v_national then
    -- Voie locale : quatre verrous, dans l'ordre où ils se comprennent.
    if not (a_droit('habilitations.local') or mon_niveau() >= 50) then
      return jsonb_build_object('ok', false, 'message', 'Vous ne nommez pas.');
    end if;
    if p_territoire is null or not dans_mon_perimetre(p_territoire) then
      return jsonb_build_object('ok', false,
        'message', 'Vous ne pouvez nommer que dans votre périmètre.');
    end if;
    if poste_sensible(p_poste) then
      return jsonb_build_object('ok', false,
        'message', 'Ce poste ouvre des droits sensibles : seule la direction le confère.');
    end if;
    select rang into v_rang from postes where code = p_poste;
    if coalesce(v_rang, 100) >= mon_plafond_nomination() then
      return jsonb_build_object('ok', false,
        'message', 'Ce poste pèse autant ou plus que le vôtre. Vous ne pouvez nommer qu''en dessous de vous.');
    end if;
  end if;

  if not exists (select 1 from profils where id = p_profil and statut = 'actif') then
    return jsonb_build_object('ok', false, 'message', 'Ce membre n''est pas actif.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;
  if exists (select 1 from nominations n where n.profil_id = p_profil
             and n.poste = p_poste and nomination_active(n)) then
    return jsonb_build_object('ok', false, 'message', 'Ce membre occupe déjà ce poste.');
  end if;
  -- La règle d'origine, conservée : un poste sensible reste au national.
  if poste_sensible(p_poste) and mon_poids() < 90 and not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Ce poste ouvre des droits sensibles : seul un administrateur peut le conférer.');
  end if;

  insert into nominations (profil_id, poste, territoire_id, fin, motif, nomme_par)
  values (p_profil, p_poste, p_territoire, p_fin, nullif(trim(p_motif),''), auth.uid())
  returning id into v_id;

  perform inscrire_acte(p_profil, 'nomination',
    'Nommé « ' || (select nom from postes where code = p_poste) || ' »',
    null, jsonb_build_object('nomination_id', v_id, 'poste', p_poste));

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'nomination', p_profil::text,
          jsonb_build_object('poste', p_poste, 'fin', p_fin,
                             'voie', case when v_national then 'nationale' else 'locale' end));
  return jsonb_build_object('ok', true);
end $$;

-- Révoquer suit la même logique : qui a pu nommer peut retirer, dans
-- les mêmes limites. Sans cela, une nomination locale serait
-- irréversible pour celui qui l'a faite.
create or replace function revoquer(p_nomination uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n nominations; v_refus text; v_rang integer;
begin
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;
  select * into n from nominations where id = p_nomination and revoque_le is null;
  if n is null then
    return jsonb_build_object('ok', false, 'message', 'Cette nomination est déjà close.');
  end if;

  if not (est_admin() or a_droit('habilitations.gerer')) then
    if not (a_droit('habilitations.local') or mon_niveau() >= 50) then
      return jsonb_build_object('ok', false, 'message', 'Vous ne révoquez pas.');
    end if;
    if n.territoire_id is null or not dans_mon_perimetre(n.territoire_id) then
      return jsonb_build_object('ok', false,
        'message', 'Cette nomination n''est pas dans votre périmètre.');
    end if;
    select rang into v_rang from postes where code = n.poste;
    if poste_sensible(n.poste) or coalesce(v_rang, 100) >= mon_plafond_nomination() then
      return jsonb_build_object('ok', false,
        'message', 'Ce poste dépasse ce que vous pouvez retirer.');
    end if;
  end if;

  v_refus := motif_refus_action(n.profil_id);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  update nominations set revoque_le = now(), revoque_par = auth.uid(),
         motif_revocation = trim(p_motif)
   where id = p_nomination;

  perform inscrire_acte(n.profil_id, 'revocation',
    'Retrait du poste « ' || (select nom from postes where code = n.poste) || ' »',
    jsonb_build_object('nomination_id', p_nomination), null);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. OUVRIR UN ACCÈS — ON NE DONNE QUE CE QU'ON A
--    Un encadrant peut ouvrir à quelqu'un de son périmètre une
--    application qu'il détient lui-même, si elle n'exige aucun droit
--    sensible. Il ne peut donc pas fabriquer un accès qu'il n'a pas :
--    c'est ce qui empêche l'escalade.
-- ---------------------------------------------------------------------

create or replace function puis_je_ouvrir_acces(p_app text, p_profil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when est_admin() or a_droit('acces.piloter') then true
    when not (a_droit('habilitations.local') or mon_niveau() >= 50) then false
    when not puis_je_agir_sur(p_profil) then false
    when not dans_mon_perimetre(
           (select territoire_id from profils where id = p_profil)) then false
    -- L'application ne doit pas reposer sur un droit sensible…
    when exists (select 1 from applications a join droits d on d.code = a.droit_requis
                 where a.code = p_app and d.sensible) then false
    -- …et je dois moi-même y avoir accès.
    else source_acces(p_app) in ('admin','nominatif','poste','fonction')
  end;
$$;

create or replace function accorder_acces(
  p_profil uuid, p_app text, p_motif text default null, p_expire date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text; v_avant jsonb;
begin
  if not puis_je_ouvrir_acces(p_app, p_profil) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez ouvrir que des applications dont vous disposez, à des membres de votre périmètre.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  select jsonb_build_object('statut', statut) into v_avant
    from acces_applications where profil_id = p_profil and application = p_app;

  insert into acces_applications (profil_id, application, statut, motif, accorde_par, expire_le)
  values (p_profil, p_app, 'accorde', nullif(trim(p_motif),''), auth.uid(), p_expire)
  on conflict (profil_id, application) do update
    set statut = 'accorde', revoque_le = null, revoque_par = null,
        motif_revocation = null, motif = nullif(trim(p_motif),''),
        accorde_par = auth.uid(), expire_le = p_expire;

  perform inscrire_acte(p_profil, 'acces',
    'Accès ouvert : ' || (select nom from applications where code = p_app),
    v_avant, jsonb_build_object('application', p_app));
  return jsonb_build_object('ok', true);
end $$;

create or replace function revoquer_acces(p_profil uuid, p_app text, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text;
begin
  if not puis_je_ouvrir_acces(p_app, p_profil) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas cet accès.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une révocation doit être motivée.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;

  update acces_applications
     set statut = 'revoque', revoque_le = now(), revoque_par = auth.uid(),
         motif_revocation = trim(p_motif)
   where profil_id = p_profil and application = p_app;

  perform inscrire_acte(p_profil, 'acces',
    'Accès retiré : ' || (select nom from applications where code = p_app),
    jsonb_build_object('application', p_app), null);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 6. LA FICHE D'OUVERTURE
--    « Comment tout lui débloquer, et rien de plus. » La question se
--    posait à chaque arrivée, sans réponse écrite nulle part. Elle se
--    lit désormais au même endroit pour le membre lui-même et pour qui
--    l'accompagne : même fonction, même liste, mêmes mots.
-- ---------------------------------------------------------------------

drop function if exists checklist_ouverture(uuid);
create or replace function checklist_ouverture(p_profil uuid default null)
returns table (code text, libelle text, etat text, detail text, lien text, ordre integer)
language sql stable security definer set search_path = public as $$
  with c as (select coalesce(p_profil, auth.uid()) as id),
  p as (select pr.* from profils pr, c where pr.id = c.id),
  d as (select completude_dossier((select id from c)) as j)
  select * from (values
    ('dossier', 'Dossier d''adhésion complet',
     case when ((select j from d)->>'complet')::boolean then 'fait' else 'bloquant' end,
     case when ((select j from d)->>'complet')::boolean then 'Toutes les pièces sont renseignées.'
          else 'Il manque : ' || coalesce(
               (select string_agg(x, ', ') from jsonb_array_elements_text(
                  (select j from d)->'manques') as t(x)), '—') end,
     '#/espace/compte', 10),

    ('statut', 'Adhésion validée',
     case (select statut from p) when 'actif' then 'fait'
          when 'suspendu' then 'bloquant' else 'a_faire' end,
     case (select statut from p)
       when 'actif' then 'Le membre est actif.'
       when 'en_attente' then 'La validation se fait au guichet des inscriptions.'
       when 'suspendu' then 'Compte suspendu : rien ne peut être ouvert.'
       else 'Statut : ' || (select statut from p) end,
     '#/espace/validation', 20),

    ('territoire', 'Rattachement territorial',
     case when (select territoire_id from p) is not null then 'fait' else 'bloquant' end,
     coalesce((select t.nom from territoires t, p where t.id = p.territoire_id),
              'Sans territoire, ni le comité ni les accès locaux ne fonctionnent.'),
     '#/espace/compte', 30),

    ('accompagnant', 'Accompagnant désigné',
     case when exists (select 1 from parcours pa, c
                       where pa.profil_id = c.id and pa.referent_id is not null)
          then 'fait' else 'a_faire' end,
     coalesce((select trim(r.prenom || ' ' || r.nom)
               from parcours pa
               join profils r on r.id = pa.referent_id
               where pa.profil_id = (select id from c)),
              'Personne ne suit ce parcours : il faut désigner quelqu''un.'),
     '#/espace/parcours', 40),

    ('formation', 'Formations d''entrée',
     case when (select count(*) from certifications_obtenues co, c
                where co.profil_id = c.id and co.code in ('socle_citoyen','usage_si')) >= 2
          then 'fait' else 'a_faire' end,
     'Socle citoyen et Usage des outils fédéraux : ' ||
     (select count(*)::text from certifications_obtenues co, c
      where co.profil_id = c.id and co.code in ('socle_citoyen','usage_si')) || ' sur 2.',
     '#/espace/formations', 50),

    ('applications', 'Applications ouvertes',
     case when (select count(*) from applications a
                where a.actif and source_acces(a.code, (select id from c))
                      in ('admin','nominatif','poste','fonction')) > 0
          then 'fait' else 'a_faire' end,
     (select count(*)::text from applications a
      where a.actif and source_acces(a.code, (select id from c))
            in ('admin','nominatif','poste','fonction')) ||
     ' application(s) ouvertes par la fonction, les postes ou un octroi nominatif.',
     '#/espace/referentiel', 60),

    ('poste', 'Mandat confié',
     case when exists (select 1 from nominations n, c
                       where n.profil_id = c.id and nomination_active(n))
          then 'fait' else 'a_faire' end,
     coalesce((select string_agg(po.nom, ', ') from nominations n
               join postes po on po.code = n.poste
               where n.profil_id = (select id from c) and nomination_active(n)),
              'Aucun poste. Ce n''est pas un manque : tout le monde n''en occupe pas.'),
     '#/espace/mandats', 70)
  ) as x(code, libelle, etat, detail, lien, ordre)
  where (select id from c) = auth.uid()
     or est_admin() or a_droit('membres.consulter')
     or (mon_niveau() >= 40 and dans_mon_perimetre((select territoire_id from p)))
  order by ordre;
$$;

-- ---------------------------------------------------------------------
-- 7. DROITS D'EXÉCUTION
-- ---------------------------------------------------------------------

grant execute on function mon_plafond_nomination(), poste_sensible(text),
                          postes_conferables(uuid), nommer(uuid, text, uuid, date, text),
                          revoquer(uuid, text), puis_je_ouvrir_acces(text, uuid),
                          accorder_acces(uuid, text, text, date),
                          revoquer_acces(uuid, text, text),
                          checklist_ouverture(uuid)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 31
--
--  Vérifications :
--    select mon_plafond_nomination();
--    select code, nom, rang from postes_conferables(
--      (select territoire_id from profils where id = auth.uid()));
--    select code, libelle, etat, detail from checklist_ouverture();
--
--  Sur la voie locale : elle ne crée aucun droit nouveau, elle
--  redistribue l'exercice de droits existants sous quatre conditions
--  cumulatives. Le journal distingue les deux voies, de sorte qu'un
--  contrôle a posteriori peut toujours dire qui a nommé et à quel titre.
--
--  Sur les accès : « on ne donne que ce qu'on a » est la seule règle
--  qui empêche l'escalade sans exiger une liste blanche à maintenir.
-- =====================================================================
