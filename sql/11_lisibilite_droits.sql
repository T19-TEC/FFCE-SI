-- =====================================================================
--  FFCE — Migration 11 — LISIBILITÉ DES DROITS
--
--  Trois manques, tous du même ordre : le système savait qui pouvait
--  quoi, mais ne le disait à personne.
--
--  1. LA MATRICE DES ACCÈS. Chaque application prend, pour chaque
--     fonction, l'un de trois états : ouverte, sur demande, ou
--     invisible. Cela se règle dans un tableau, sans SQL.
--
--  2. LA FICHE MEMBRE. L'annuaire n'affichait qu'une ligne. Il ouvre
--     désormais une fiche où les informations se révèlent par paliers :
--     ce qui est d'usage courant, ce qui relève de l'encadrement, et ce
--     qui exige une habilitation particulière. Toute révélation est
--     tracée.
--
--  3. LE RÉFÉRENTIEL. Une page qui expose, à tous les membres, les
--     fonctions, les échelons, les postes et les droits qu'ils
--     ouvrent. Un système de droits que personne ne comprend n'est pas
--     accepté : il est subi.
--
--  Prérequis : 01 à 10.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LA MATRICE
-- ---------------------------------------------------------------------

create table if not exists application_visibilite (
  application text not null references applications(code) on delete cascade,
  fonction    text not null references fonctions(code) on delete cascade,
  etat        text not null default 'invisible'
                check (etat in ('ouverte','sur_demande','invisible')),
  note        text,
  maj_par     uuid references profils(id),
  maj_le      timestamptz not null default now(),
  primary key (application, fonction)
);

-- On amorce la matrice à partir des règles déjà en vigueur, pour ne
-- rien changer aux accès existants.
insert into application_visibilite (application, fonction, etat)
select a.code, f.code,
       case
         when a.droit_requis is not null then 'invisible'
         when a.sur_demande then (case when f.niveau >= a.niveau_min
                                       then 'sur_demande' else 'invisible' end)
         when f.niveau >= a.niveau_min then 'ouverte'
         else 'invisible'
       end
from applications a cross join fonctions f
on conflict (application, fonction) do nothing;

create or replace function etat_application(p_app text, p_fonction text default null)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select v.etat from application_visibilite v
      where v.application = p_app
        and v.fonction = coalesce(p_fonction,
              (select fonction from profils where id = auth.uid()))),
    'invisible');
$$;

-- L'accès, revu : la matrice d'abord, puis les postes, puis l'octroi
-- nominatif. Un droit de poste passe outre la matrice, c'est voulu —
-- un référent RGPD doit atteindre son outil quelle que soit sa fonction.
create or replace function a_acces(app text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from applications a
    where a.code = app and a.actif
      and (
        etat_application(app) = 'ouverte'
        or (a.droit_requis is not null and a_droit(a.droit_requis))
        or exists (select 1 from acces_applications x
                   where x.profil_id = auth.uid() and x.application = app
                     and x.statut = 'accorde' and x.revoque_le is null
                     and (x.expire_le is null or x.expire_le >= current_date))
      )
  );
$$;

-- Ce que je dois voir sur mon tableau de bord, et dans quel état.
create or replace function mes_applications()
returns table (
  code text, nom text, description text, externe_url text, ordre integer,
  etat text, ouvert boolean, demande_en_cours boolean
) language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.description, a.externe_url, a.ordre,
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

create or replace function regler_matrice(p_app text, p_fonction text, p_etat text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('acces.piloter') then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas les accès.');
  end if;
  insert into application_visibilite (application, fonction, etat, maj_par)
  values (p_app, p_fonction, p_etat, auth.uid())
  on conflict (application, fonction) do update
    set etat = excluded.etat, maj_par = auth.uid(), maj_le = now();

  insert into journal (acteur, action, cible, details)
  values (auth.uid(), 'matrice_reglee', p_app,
          jsonb_build_object('fonction', p_fonction, 'etat', p_etat));
  return jsonb_build_object('ok', true);
end $$;

create or replace function matrice_acces()
returns table (application text, app_nom text, ordre integer, droit_requis text,
               fonction text, fonction_nom text, niveau integer, etat text)
language sql stable security definer set search_path = public as $$
  select a.code, a.nom, a.ordre, a.droit_requis,
         f.code, f.nom, f.niveau,
         coalesce(v.etat, 'invisible')
  from applications a
  cross join fonctions f
  left join application_visibilite v on v.application = a.code and v.fonction = f.code
  where a.actif and mon_niveau() >= 10
  order by a.ordre, f.niveau;
$$;

-- ---------------------------------------------------------------------
-- 2. LA FICHE MEMBRE
--
--    Trois paliers :
--      libre      — ce que tout membre peut voir d'un autre
--      encadrement— coordonnées, réservées au périmètre hiérarchique
--      habilite   — situation administrative, protection, dossiers
--
--    La révélation des paliers supérieurs est tracée, et le membre
--    concerné peut la consulter.
-- ---------------------------------------------------------------------

create or replace function fiche_membre(p_profil uuid, p_reveler boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_moi boolean; v_terr uuid; v_protege boolean;
  v_encadrement boolean; v_habilite boolean; v_res jsonb;
begin
  select territoire_id, protege into v_terr, v_protege from profils where id = p_profil;
  if not found then
    return jsonb_build_object('erreur', 'Membre introuvable.');
  end if;
  v_moi := (p_profil = auth.uid());

  v_encadrement := v_moi or est_admin() or a_droit('membres.consulter')
                   or (est_encadrant() and dans_mon_perimetre(v_terr));
  v_habilite    := v_moi or est_admin() or a_droit('donnees.protegees')
                   or a_droit('membres.nommer');

  if v_protege and not v_habilite then
    return jsonb_build_object('erreur',
      'Ce dossier fait l''objet d''une protection renforcée. Son accès est réservé.');
  end if;

  -- Palier libre : identité fédérale, jamais les coordonnées.
  select jsonb_build_object(
    'id', p.id, 'matricule', p.matricule,
    'prenom', p.prenom, 'nom', p.nom,
    'fonction', f.nom, 'niveau', f.niveau, 'famille', f.famille,
    'echelon', p.echelon, 'echelon_nom', e.nom,
    'territoire', t.nom, 'chemin', chemin_territoire(p.territoire_id),
    'bio', p.bio, 'photo_url', p.photo_url,
    'membre_depuis', p.cree_le,
    'protege', p.protege,
    'postes', coalesce((
      select jsonb_agg(jsonb_build_object('nom', po.nom, 'couleur', po.couleur,
                                          'territoire', tn.nom, 'fin', n.fin))
      from nominations n join postes po on po.code = n.poste
      left join territoires tn on tn.id = n.territoire_id
      where n.profil_id = p.id and po.actif and nomination_active(n)), '[]'::jsonb),
    'certifications', coalesce((
      select jsonb_agg(jsonb_build_object('nom', c.nom, 'obtenue_le', co.obtenue_le,
                                          'expire_le', co.expire_le, 'numero', co.numero))
      from certifications_obtenues co join certifications c on c.code = co.code
      where co.profil_id = p.id), '[]'::jsonb),
    'groupes', coalesce((
      select jsonb_agg(jsonb_build_object('nom', g.nom, 'role', m.role))
      from gt_membres m join groupes_travail g on g.id = m.groupe_id
      where m.profil_id = p.id and m.statut = 'actif' and g.statut = 'actif'), '[]'::jsonb)
  ) into v_res
  from profils p
  join fonctions f on f.code = p.fonction
  join echelons e  on e.niveau = p.echelon
  left join territoires t on t.id = p.territoire_id
  where p.id = p_profil;

  v_res := v_res || jsonb_build_object(
    'droit_encadrement', v_encadrement,
    'droit_habilite', v_habilite,
    'revele', false);

  -- Les paliers supérieurs ne sortent que si on les demande. C'est ce
  -- qui rend la trace honnête : on n'enregistre pas une consultation
  -- que personne n'a voulue.
  if p_reveler and v_encadrement then
    v_res := v_res || (
      select jsonb_build_object(
        'email', p.email, 'telephone', p.telephone,
        'webmail', p.webmail, 'date_adhesion', p.date_adhesion,
        'revele', true)
      from profils p where p.id = p_profil);

    if v_habilite then
      v_res := v_res || (
        select jsonb_build_object(
          'statut', p.statut, 'sous_suivi', p.sous_suivi,
          'motif_protection', p.motif_protection,
          'dossiers_ouverts', (select count(*) from dossiers d
                               where d.profil_id = p.id and d.statut <> 'clos'),
          'dossiers_clos', (select count(*) from dossiers d
                            where d.profil_id = p.id and d.statut = 'clos'),
          'acces_nominatifs', coalesce((
            select jsonb_agg(jsonb_build_object('app', ap.nom, 'statut', x.statut))
            from acces_applications x join applications ap on ap.code = x.application
            where x.profil_id = p.id), '[]'::jsonb))
        from profils p where p.id = p_profil);
    end if;

    if not v_moi then
      insert into consultations (observateur, observe, contexte, alerte)
      values (auth.uid(), p_profil, 'Fiche membre — coordonnées révélées',
              coalesce(v_protege, false));
    end if;
  end if;

  return v_res;
end $$;

-- Qui a consulté mon dossier ? Chacun a le droit de le savoir.
create or replace function qui_ma_consulte()
returns table (observateur text, fonction text, contexte text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select trim(p.prenom || ' ' || p.nom), f.nom, c.contexte, c.cree_le
  from consultations c
  join profils p   on p.id = c.observateur
  join fonctions f on f.code = p.fonction
  where c.observe = auth.uid()
  order by c.cree_le desc
  limit 50;
$$;

-- ---------------------------------------------------------------------
-- 3. LE RÉFÉRENTIEL, OUVERT À TOUS LES MEMBRES
--    Un système de droits que personne ne comprend n'est pas accepté :
--    il est subi. Tout est donc public au sein de la fédération.
-- ---------------------------------------------------------------------

create or replace function referentiel()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'fonctions', (select jsonb_agg(jsonb_build_object(
        'code', f.code, 'nom', f.nom, 'niveau', f.niveau,
        'famille', f.famille, 'echelle', f.echelle_requise,
        'effectif', (select count(*) from profils p
                     where p.fonction = f.code and p.statut = 'actif'))
        order by f.niveau) from fonctions f),
    'echelons', (select jsonb_agg(jsonb_build_object(
        'niveau', e.niveau, 'nom', e.nom, 'points', e.points, 'ouvre', e.ouvre,
        'effectif', (select count(*) from profils p
                     where p.echelon = e.niveau and p.statut = 'actif'))
        order by e.niveau) from echelons e),
    'postes', (select jsonb_agg(jsonb_build_object(
        'code', po.code, 'nom', po.nom, 'description', po.description,
        'couleur', po.couleur, 'actif', po.actif,
        'droits', (select jsonb_agg(d.nom order by d.ordre)
                   from poste_droits pd join droits d on d.code = pd.droit
                   where pd.poste = po.code),
        'titulaires', (select jsonb_agg(trim(p.prenom || ' ' || p.nom))
                       from nominations n join profils p on p.id = n.profil_id
                       where n.poste = po.code and nomination_active(n)))
        order by po.nom) from postes po where po.actif),
    'applications', (select jsonb_agg(jsonb_build_object(
        'code', a.code, 'nom', a.nom, 'description', a.description,
        'droit_requis', (select d.nom from droits d where d.code = a.droit_requis),
        'mon_etat', etat_application(a.code))
        order by a.ordre) from applications a where a.actif),
    'ma_fonction', (select f.nom from profils p join fonctions f on f.code = p.fonction
                    where p.id = auth.uid()),
    'mon_echelon', (select echelon from profils where id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------
-- 4. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table application_visibilite enable row level security;

drop policy if exists lire_matrice on application_visibilite;
create policy lire_matrice on application_visibilite for select using (mon_niveau() >= 10);
drop policy if exists ecrire_matrice on application_visibilite;
create policy ecrire_matrice on application_visibilite for all
  using (a_droit('acces.piloter')) with check (a_droit('acces.piloter'));

grant select on application_visibilite to authenticated;
grant insert, update, delete on application_visibilite to authenticated;

grant execute on function etat_application(text, text), a_acces(text),
                          mes_applications(), regler_matrice(text, text, text),
                          matrice_acces(), fiche_membre(uuid, boolean),
                          qui_ma_consulte(), referentiel()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 11
--
--  Vérifications :
--    select * from mes_applications();
--    select * from matrice_acces() where application = 'notes_frais';
--    select referentiel();
--
--  Le principe : un droit de poste passe outre la matrice. Un référent
--  RGPD doit atteindre son outil quelle que soit sa fonction dans la
--  hiérarchie — sinon le poste ne servirait à rien.
-- =====================================================================
