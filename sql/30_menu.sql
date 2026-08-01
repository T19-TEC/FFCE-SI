-- =====================================================================
--  FFCE — Migration 30 — LE MENU REMIS D'APLOMB
--
--  Le menu mêlait deux registres : ce que je fais (Mon activité) et
--  l'organisation de la fédération (les directions). Une même
--  application ne relève pourtant pas du même bloc selon qui regarde :
--  le Pilotage du réseau est un outil de la Direction générale vue du
--  national, et un outil de sa propre structure vu d'un responsable
--  local. On introduit donc un second rattachement — `direction_locale`
--  — qui ne vaut que pour les échelons territoriaux.
--
--  Une seule règle, explicite : au-dessus du niveau 80 on voit
--  l'organigramme fédéral ; en dessous, on voit le sien.
--
--  Prérequis : 01 à 29.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LE SECOND RATTACHEMENT
-- ---------------------------------------------------------------------

alter table applications
  add column if not exists direction_locale text references directions(code);

comment on column applications.direction_locale is
  'Direction sous laquelle l''application se range pour les échelons territoriaux (niveau < 80). Null : même rattachement pour tous.';

-- ---------------------------------------------------------------------
-- 2. LES RATTACHEMENTS CORRIGÉS
--
--    Chancellerie quittait la Formation : elle traite des distinctions,
--    des promotions et des échelons, c'est-à-dire des personnes et de
--    leur reconnaissance, pas de l'apprentissage.
--
--    Mon comité rejoint la Vie associative : les deux parlaient de la
--    même chose depuis deux endroits éloignés du menu.
--
--    Pilotage, Rapport d'activité et À relayer gardent leur direction
--    fédérale, mais se rangent avec Mon comité pour qui travaille sur
--    un territoire — au lieu d'apparaître seuls sous une direction
--    dont l'intéressé ne voit rien d'autre.
-- ---------------------------------------------------------------------

update applications set direction = 'dg' where code = 'chancellerie';

-- Mon comité ne change pas de rattachement fédéral : au national, il
-- reste une application personnelle. C'est sur un territoire qu'il
-- devient le cœur du bloc « Ma structure », avec ce qui l'entoure.
update applications set direction_locale = 'dvie'
 where code in ('comite', 'pilotage', 'rapport', 'publier', 'annuaire');

-- ---------------------------------------------------------------------
-- 3. LES NOMS QUI DISAIENT AUTRE CHOSE QUE CE QU'ILS SONT
--    « Accueil » ne disait pas de quoi il s'agissait ; « Rapport »
--    laissait croire à un rapport quelconque.
-- ---------------------------------------------------------------------

update applications set nom_court = 'Parcours adhérent' where code = 'parcours';
update applications set nom_court = 'Rapport d''activité', nom = 'Rapport d''activité'
 where code = 'rapport';
update applications set nom_court = 'À relayer' where code = 'publier';

-- La Vie associative devient le bloc de la structure : elle porte
-- désormais le comité, le parcours, les assemblées et, pour les
-- territoriaux, le pilotage et le rapport.
update directions
   set nom = 'Vie associative et structures',
       nom_court = 'Ma structure',
       description = 'Le comité, les adhérents accueillis, les assemblées, le pilotage de la structure.'
 where code = 'dvie';

-- ---------------------------------------------------------------------
-- 4. LA LISTE DES APPLICATIONS, SELON LE REGARD
--    Mêmes colonnes qu'avant : seule la direction renvoyée change.
-- ---------------------------------------------------------------------

create or replace function mes_applications()
returns table (
  code text, nom text, nom_court text, description text, accroche text,
  logo text, couleur text, externe_url text, ordre integer,
  direction text, direction_nom text, direction_ordre integer,
  etat text, source text, ouvert boolean, demande_en_cours boolean,
  explication text, personnelle boolean
) language sql stable security definer set search_path = public as $$
  with vu as (select mon_niveau() >= 80 as federal)
  select a.code, a.nom, a.nom_court, a.description, a.accroche, a.logo,
         coalesce(a.couleur,'bleu'), a.externe_url, a.ordre,
         d.code, d.nom_court, coalesce(d.ordre, 999),
         case source_acces(a.code)
           when 'ferme' then 'invisible'
           when 'sur_demande' then 'sur_demande'
           else 'ouverte' end,
         source_acces(a.code),
         source_acces(a.code) in ('admin','nominatif','poste','fonction'),
         exists (select 1 from demandes dm
                 where dm.profil_id = auth.uid() and dm.cible = a.code
                   and dm.statut in ('ouverte','en_cours')),
         case source_acces(a.code)
           when 'admin' then 'Ouverte au titre de l''administration'
           when 'nominatif' then 'Accordée nominativement par la direction'
           when 'poste' then 'Ouverte par un poste que vous occupez'
           when 'fonction' then 'Ouverte à votre fonction'
           when 'sur_demande' then 'À demander au guichet'
           else 'Non ouverte à votre fonction' end,
         d.code is null
  from applications a
  cross join vu
  -- Le rattachement effectif : fédéral au-dessus de 80, territorial en
  -- dessous. C'est le seul endroit où la règle est écrite.
  left join directions d
    on d.code = case when vu.federal then a.direction
                     else coalesce(a.direction_locale, a.direction) end
  where a.actif
    and (source_acces(a.code) <> 'ferme'
         or (select v.etat from application_visibilite v
             where v.application = a.code
               and v.fonction = (select fonction from profils where id = auth.uid()))
            = 'sur_demande')
  order by coalesce(d.ordre, 0), a.ordre;
$$;

-- Les directions du menu suivent la même règle, sans quoi un bloc
-- pourrait s'afficher vide ou une application se retrouver orpheline.
create or replace function mes_directions()
returns table (code text, nom text, nom_court text, couleur text, ordre integer,
               par_poste boolean, postes text[])
language sql stable security definer set search_path = public as $$
  with vu as (select mon_niveau() >= 80 as federal)
  select d.code, d.nom, d.nom_court, d.couleur, d.ordre,
         exists (select 1 from nominations n
                 join postes po on po.code = n.poste
                 where n.profil_id = auth.uid() and nomination_active(n)
                   and po.direction = d.code),
         coalesce(array(select po.nom from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = auth.uid() and nomination_active(n)
                          and po.direction = d.code), '{}')
  from directions d, vu
  where d.actif
    and (
      exists (select 1 from nominations n join postes po on po.code = n.poste
              where n.profil_id = auth.uid() and nomination_active(n)
                and po.direction = d.code)
      or exists (select 1 from applications a
                 where a.actif
                   and d.code = case when vu.federal then a.direction
                                     else coalesce(a.direction_locale, a.direction) end
                   and source_acces(a.code) in ('admin','nominatif','poste','fonction'))
    )
  order by d.ordre;
$$;

-- ---------------------------------------------------------------------
-- 5. LE RANGEMENT SE RÈGLE, IL NE SE CODE PAS
--    L'écran d'identité des applications permettait déjà de changer le
--    nom, l'accroche et la couleur. Il manquait l'essentiel : où
--    l'application se range, et dans quel ordre. On complète plutôt que
--    de laisser ces deux-là en dur dans les migrations.
-- ---------------------------------------------------------------------

drop function if exists regler_application(text, text, text, text, text, text, text);

create or replace function regler_application(
  p_code text, p_nom text, p_nom_court text, p_description text,
  p_accroche text, p_couleur text, p_logo text,
  p_direction text default null, p_direction_locale text default null,
  p_ordre integer default null)
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
         logo = coalesce(nullif(p_logo,''), logo),
         -- La chaîne vide vaut « aucune direction » : l'application
         -- retourne sous « Mon activité ». C'est un choix, pas un oubli.
         direction = case when p_direction is null then direction
                          else nullif(p_direction,'') end,
         direction_locale = case when p_direction_locale is null then direction_locale
                                 else nullif(p_direction_locale,'') end,
         ordre = coalesce(p_ordre, ordre)
   where code = p_code;

  return jsonb_build_object('ok', true);
end $$;

-- La liste des directions, pour peupler les menus déroulants.
drop function if exists liste_directions();
create or replace function liste_directions()
returns table (code text, nom text, nom_court text, ordre integer)
language sql stable security definer set search_path = public as $$
  select d.code, d.nom, d.nom_court, d.ordre
  from directions d where d.actif order by d.ordre;
$$;

grant execute on function mes_applications(), mes_directions(), liste_directions(),
                          regler_application(text, text, text, text, text, text, text,
                                             text, text, integer)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 30
--
--  Vérifications :
--    select code, nom_court, direction, direction_nom from mes_applications();
--    select * from mes_directions();
--
--  Sur le double rattachement : il ne duplique pas l'application, il
--  la range ailleurs. Une application reste unique, ses droits restent
--  les mêmes ; seul le bloc du menu change. Si l'on voulait un jour
--  qu'une application apparaisse à deux endroits, il faudrait le dire
--  autrement — et ce serait probablement une mauvaise idée.
-- =====================================================================
