-- =====================================================================
--  FFCE — Migration 32 — LE CABINET DE LA PRÉSIDENCE
--
--  La présidence est nationale. Son cabinet n'est pas un outil de plus
--  dans chaque structure : c'est l'organe central vers lequel tout
--  converge, et depuis lequel s'écrivent les actes qui engagent la
--  fédération entière.
--
--  Deux mouvements, en sens inverse :
--
--    MONTANT — n'importe quel responsable, à n'importe quelle échelle,
--    porte au cabinet une information, une alerte, une proposition ou
--    une demande d'arbitrage. Elle y arrive et y reste jusqu'à ce qu'on
--    l'ait traitée. Aucun filtre de périmètre : le cabinet voit tout.
--
--    DESCENDANT — la présidence prend des actes. Un acte porte des
--    visas, des considérants et des articles numérotés ; il vise un
--    territoire ou la fédération entière ; il se signe, se notifie, et
--    reste au recueil, consultable par tout adhérent.
--
--  Un acte de nomination produit la nomination : une seule saisie, deux
--  effets, aucune divergence possible entre le texte et le fait.
--
--  Prérequis : 01 à 31.
--  Ré-exécutable : oui. Si une version antérieure a été passée, celle-ci
--  retire ce qu'elle avait posé à tort au niveau des structures.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES DROITS ET LES POSTES DE LA PRÉSIDENCE
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('actes.prendre',    'Signer les actes de la présidence',  'Présidence', true,  400),
  ('actes.recueil',    'Administrer le recueil des actes',   'Présidence', false, 410),
  ('cabinet.arbitrer', 'Instruire les remontées au cabinet', 'Présidence', false, 420)
on conflict (code) do update
  set nom = excluded.nom, sensible = excluded.sensible;

insert into postes (code, nom, description, couleur, systeme, direction, rang) values
  ('president_federation', 'Présidence de la fédération',
   'Signe les actes qui engagent la fédération, arbitre les remontées du réseau.',
   'nuit', true, 'dg', 95),
  ('directeur_cabinet', 'Direction du cabinet de la présidence',
   'Instruit les remontées, prépare les projets d''actes, tient le recueil.',
   'nuit', true, 'dg', 85)
on conflict (code) do update
  set nom = excluded.nom, description = excluded.description,
      direction = excluded.direction, rang = excluded.rang;

insert into poste_droits (poste, droit) values
  ('president_federation', 'actes.prendre'),
  ('president_federation', 'cabinet.arbitrer'),
  ('president_federation', 'actes.recueil'),
  ('directeur_cabinet',    'cabinet.arbitrer'),
  ('directeur_cabinet',    'actes.recueil'),
  ('delegue_admin',        'actes.recueil')
on conflict do nothing;

-- Rattrapage : une version antérieure confiait ces droits aux bureaux
-- de structure. Le cabinet n'est pas local, il n'y en a qu'un.
delete from poste_droits
 where poste in ('president_structure','secretaire_structure')
   and droit in ('actes.prendre','actes.recueil','cabinet.arbitrer');

-- ---------------------------------------------------------------------
-- 2. LE RECUEIL DES ACTES
--    `territoire_id` désigne la portée de l'acte, non le lieu où il est
--    pris : null vaut « toute la fédération ». C'est toujours la
--    présidence nationale qui signe.
-- ---------------------------------------------------------------------

create sequence if not exists seq_acte_interne start 1;

create table if not exists actes_internes (
  id             uuid primary key default gen_random_uuid(),
  reference      text unique not null default 'ACTE-' || to_char(now(),'YYYY') || '-' ||
                             lpad(nextval('seq_acte_interne')::text, 4, '0'),
  territoire_id  uuid references territoires(id) on delete set null,
  auteur_id      uuid not null references profils(id) on delete cascade,
  type           text not null default 'decision' check (type in
                   ('nomination','delegation','decision','convocation',
                    'motion','note','abrogation')),
  objet          text not null,
  visas          text,
  considerants   text,
  articles       jsonb not null default '[]'::jsonb,
  destinataire_id uuid references profils(id) on delete set null,
  poste_confie   text references postes(code),
  prend_effet_le date,
  statut         text not null default 'projet'
                   check (statut in ('projet','signe','notifie','abroge')),
  signe_par      uuid references profils(id) on delete set null,
  signe_le       timestamptz,
  notifie_le     timestamptz,
  abroge_par     uuid references actes_internes(id) on delete set null,
  motif_abrogation text,
  cree_le        timestamptz not null default now()
);
create index if not exists idx_actes_internes on actes_internes(statut, cree_le desc);

-- ---------------------------------------------------------------------
-- 3. LES REMONTÉES AU CABINET
-- ---------------------------------------------------------------------

create table if not exists remontees_cabinet (
  id            uuid primary key default gen_random_uuid(),
  auteur_id     uuid not null references profils(id) on delete cascade,
  territoire_id uuid references territoires(id) on delete set null,
  nature        text not null default 'information' check (nature in
                  ('information','alerte','proposition','arbitrage','contact')),
  objet         text not null,
  corps         text not null,
  lien          text,
  statut        text not null default 'deposee'
                  check (statut in ('deposee','lue','arbitree','classee')),
  traite_par    uuid references profils(id) on delete set null,
  traite_le     timestamptz,
  reponse       text,
  acte_id       uuid references actes_internes(id) on delete set null,
  cree_le       timestamptz not null default now()
);
create index if not exists idx_remontees on remontees_cabinet(statut, cree_le desc);

-- ---------------------------------------------------------------------
-- 4. PRENDRE UN ACTE
--    Le cabinet rédige les projets ; la présidence seule signe. Cette
--    séparation est la raison d'être d'un cabinet.
-- ---------------------------------------------------------------------

create or replace function puis_je_signer_acte()
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('actes.prendre');
$$;

create or replace function puis_je_prendre_acte(p_territoire uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('actes.prendre') or a_droit('cabinet.arbitrer');
$$;

create or replace function prendre_acte(
  p_type text, p_objet text, p_visas text default null,
  p_considerants text default null, p_articles jsonb default '[]'::jsonb,
  p_destinataire uuid default null, p_poste text default null,
  p_effet date default null, p_territoire uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not puis_je_prendre_acte(null) then
    return jsonb_build_object('ok', false,
      'message', 'Les actes se préparent au cabinet de la présidence.');
  end if;
  if coalesce(trim(p_objet),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un acte a un objet.');
  end if;
  if jsonb_array_length(coalesce(p_articles,'[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false,
      'message', 'Un acte sans article ne décide rien. Écrivez au moins un article.');
  end if;
  if p_type = 'nomination' and (p_destinataire is null or p_poste is null) then
    return jsonb_build_object('ok', false,
      'message', 'Un acte de nomination désigne une personne et un poste.');
  end if;

  insert into actes_internes (territoire_id, auteur_id, type, objet, visas,
                              considerants, articles, destinataire_id,
                              poste_confie, prend_effet_le)
  values (p_territoire, auth.uid(), p_type, trim(p_objet), nullif(trim(p_visas),''),
          nullif(trim(p_considerants),''), coalesce(p_articles,'[]'::jsonb),
          p_destinataire, p_poste, coalesce(p_effet, current_date))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function signer_acte(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a actes_internes; v_conv uuid; v_res jsonb; v_texte text; v_signataire text;
begin
  select * into a from actes_internes where id = p_id;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Acte introuvable.');
  end if;
  if a.statut <> 'projet' then
    return jsonb_build_object('ok', false, 'message', 'Cet acte est déjà signé.');
  end if;
  if not puis_je_signer_acte() then
    return jsonb_build_object('ok', false,
      'message', 'Le cabinet prépare les actes ; seule la présidence les signe.');
  end if;

  -- L'acte de nomination produit la nomination. Si celle-ci est
  -- refusée, l'acte n'est pas signé : on ne laisse pas un texte
  -- affirmer ce qui n'a pas eu lieu.
  if a.type = 'nomination' then
    v_res := nommer(a.destinataire_id, a.poste_confie, a.territoire_id,
                    null, 'Acte ' || a.reference);
    if not (v_res->>'ok')::boolean then
      return jsonb_build_object('ok', false,
        'message', 'L''acte ne peut pas être signé : ' || (v_res->>'message'));
    end if;
  end if;

  update actes_internes
     set statut = 'signe', signe_le = now(), signe_par = auth.uid(),
         prend_effet_le = coalesce(prend_effet_le, current_date)
   where id = p_id;

  -- Notification par messagerie interne, au nom du secrétariat.
  if a.destinataire_id is not null then
    select trim(pr.prenom || ' ' || pr.nom) into v_signataire
      from profils pr where pr.id = auth.uid();

    select c.id into v_conv from conversations c
     where c.type = 'privee'
       and (select count(*) from conv_participants x where x.conversation_id = c.id) = 2
       and exists (select 1 from conv_participants x
                   where x.conversation_id = c.id and x.profil_id = auth.uid())
       and exists (select 1 from conv_participants x
                   where x.conversation_id = c.id and x.profil_id = a.destinataire_id)
     limit 1;
    if v_conv is null then
      insert into conversations (type, cree_par) values ('privee', auth.uid())
      returning id into v_conv;
      insert into conv_participants (conversation_id, profil_id)
      values (v_conv, auth.uid()), (v_conv, a.destinataire_id);
    end if;

    v_texte := 'Secrétariat de la présidence — notification de l''acte '
      || a.reference || E'\n\n' || a.objet || E'\n\n'
      || 'Cet acte prend effet le '
      || to_char(coalesce(a.prend_effet_le, current_date), 'DD/MM/YYYY')
      || '. Son texte intégral est consultable et téléchargeable au recueil '
      || 'des actes.' || E'\n\n' || 'Pour ' || coalesce(v_signataire, 'la présidence') || '.';

    insert into messages (conversation_id, auteur_id, contenu)
    values (v_conv, auth.uid(), v_texte);
    update conversations set derniere_activite = now() where id = v_conv;

    update actes_internes set statut = 'notifie', notifie_le = now() where id = p_id;
  end if;

  perform inscrire_acte(a.destinataire_id, 'acte_interne',
    'Acte ' || a.reference || ' — ' || a.objet, null,
    jsonb_build_object('acte_id', p_id, 'type', a.type), false);

  return jsonb_build_object('ok', true);
end $$;

create or replace function abroger_acte(p_id uuid, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a actes_internes; v_new jsonb;
begin
  select * into a from actes_internes where id = p_id;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Acte introuvable.');
  end if;
  if a.statut = 'abroge' then
    return jsonb_build_object('ok', false, 'message', 'Cet acte est déjà abrogé.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Une abrogation se motive.');
  end if;

  -- Un projet jamais signé se retire ; un acte signé s'abroge par un
  -- autre acte, qui reste au recueil.
  if a.statut = 'projet' then
    if not (puis_je_prendre_acte(null) and
            (a.auteur_id = auth.uid() or puis_je_signer_acte())) then
      return jsonb_build_object('ok', false, 'message', 'Ce projet n''est pas le vôtre.');
    end if;
    delete from actes_internes where id = p_id;
    return jsonb_build_object('ok', true, 'supprime', true);
  end if;

  if not puis_je_signer_acte() then
    return jsonb_build_object('ok', false,
      'message', 'Seule la présidence abroge ce qu''elle a signé.');
  end if;

  v_new := prendre_acte('abrogation',
    'Abrogation de l''acte ' || a.reference, 'Vu l''acte ' || a.reference || ',',
    trim(p_motif),
    jsonb_build_array('L''acte ' || a.reference || ' est abrogé à compter de ce jour.'),
    a.destinataire_id, null, current_date, a.territoire_id);
  if not (v_new->>'ok')::boolean then return v_new; end if;

  update actes_internes
     set statut = 'abroge', abroge_par = (v_new->>'id')::uuid,
         motif_abrogation = trim(p_motif)
   where id = p_id;
  perform signer_acte((v_new->>'id')::uuid);
  return jsonb_build_object('ok', true, 'acte', v_new->>'id');
end $$;

-- ---------------------------------------------------------------------
-- 5. LIRE LE RECUEIL
--    Un acte en vigueur est connu de toute la fédération : c'est ce qui
--    distingue un recueil d'un tiroir. Seuls les projets restent au
--    cabinet, tant qu'ils ne sont pas signés.
-- ---------------------------------------------------------------------

drop function if exists recueil_actes(text);
create or replace function recueil_actes(p_filtre text default 'tous')
returns table (id uuid, reference text, type text, objet text, statut text,
               auteur text, auteur_fonction text, portee text,
               destinataire text, poste_nom text, prend_effet_le date,
               signe_le timestamptz, abroge boolean, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.reference, a.type, a.objet, a.statut,
         trim(au.prenom || ' ' || au.nom), f.nom,
         coalesce(t.nom, 'Toute la fédération'),
         trim(de.prenom || ' ' || de.nom),
         (select po.nom from postes po where po.code = a.poste_confie),
         a.prend_effet_le, a.signe_le, a.statut = 'abroge', a.cree_le
  from actes_internes a
  join profils au on au.id = a.auteur_id
  join fonctions f on f.code = au.fonction
  left join territoires t on t.id = a.territoire_id
  left join profils de on de.id = a.destinataire_id
  where (
      a.statut in ('signe','notifie','abroge')
      or est_admin() or a_droit('actes.recueil') or a_droit('cabinet.arbitrer')
      or a.auteur_id = auth.uid()
    )
    and case p_filtre
      when 'projets'    then a.statut = 'projet'
      when 'en_vigueur' then a.statut in ('signe','notifie')
      when 'miens'      then a.destinataire_id = auth.uid()
      else true end
  order by a.cree_le desc;
$$;

create or replace function texte_acte(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'reference', a.reference, 'type', a.type, 'objet', a.objet,
    'visas', a.visas, 'considerants', a.considerants, 'articles', a.articles,
    'statut', a.statut, 'prend_effet_le', a.prend_effet_le,
    'signe_le', a.signe_le, 'notifie_le', a.notifie_le,
    'motif_abrogation', a.motif_abrogation,
    'auteur', trim(au.prenom || ' ' || au.nom),
    'auteur_fonction', f.nom,
    'signataire', (select trim(s.prenom || ' ' || s.nom)
                   from profils s where s.id = a.signe_par),
    'portee', coalesce(t.nom, 'Toute la fédération'),
    'destinataire', trim(de.prenom || ' ' || de.nom),
    'poste', (select po.nom from postes po where po.code = a.poste_confie))
  from actes_internes a
  join profils au on au.id = a.auteur_id
  join fonctions f on f.code = au.fonction
  left join territoires t on t.id = a.territoire_id
  left join profils de on de.id = a.destinataire_id
  where a.id = p_id
    and (a.statut in ('signe','notifie','abroge')
         or est_admin() or a_droit('actes.recueil') or a_droit('cabinet.arbitrer')
         or a.auteur_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- 6. LE CANAL MONTANT
--    Ouvert à tout l'encadrement, à toute échelle. Le cabinet lit tout,
--    sans filtre territorial : c'est précisément sa fonction.
-- ---------------------------------------------------------------------

create or replace function flecher_vers_cabinet(
  p_nature text, p_objet text, p_corps text, p_lien text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if mon_niveau() < 40 and not est_admin() then
    return jsonb_build_object('ok', false,
      'message', 'Les remontées au cabinet viennent de l''encadrement. Passez par votre responsable.');
  end if;
  if coalesce(trim(p_objet),'') = '' or coalesce(trim(p_corps),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un objet et un corps sont attendus.');
  end if;

  insert into remontees_cabinet (auteur_id, territoire_id, nature, objet, corps, lien)
  values (auth.uid(), (select territoire_id from profils where id = auth.uid()),
          coalesce(p_nature,'information'), trim(p_objet), trim(p_corps),
          nullif(trim(p_lien),''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function traiter_remontee(p_id uuid, p_statut text,
                                            p_reponse text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (est_admin() or a_droit('cabinet.arbitrer')) then
    return jsonb_build_object('ok', false, 'message', 'Ce n''est pas votre cabinet.');
  end if;
  if not exists (select 1 from remontees_cabinet where id = p_id) then
    return jsonb_build_object('ok', false, 'message', 'Remontée introuvable.');
  end if;
  if p_statut = 'arbitree' and coalesce(trim(p_reponse),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un arbitrage se motive.');
  end if;

  update remontees_cabinet
     set statut = p_statut, traite_par = auth.uid(), traite_le = now(),
         reponse = coalesce(nullif(trim(p_reponse),''), reponse)
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

drop function if exists remontees_du_cabinet(text);
create or replace function remontees_du_cabinet(p_filtre text default 'ouvertes')
returns table (id uuid, nature text, objet text, corps text, lien text,
               statut text, auteur text, auteur_fonction text, territoire text,
               reponse text, traite_par text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.nature, r.objet, r.corps, r.lien, r.statut,
         trim(p.prenom || ' ' || p.nom), f.nom,
         coalesce(t.nom, 'National'), r.reponse,
         (select trim(x.prenom || ' ' || x.nom) from profils x where x.id = r.traite_par),
         r.cree_le
  from remontees_cabinet r
  join profils p on p.id = r.auteur_id
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = r.territoire_id
  where (r.auteur_id = auth.uid() or est_admin() or a_droit('cabinet.arbitrer'))
    and case p_filtre
      when 'ouvertes' then r.statut in ('deposee','lue')
      when 'miennes'  then r.auteur_id = auth.uid()
      else true end
  order by case r.nature when 'alerte' then 0 when 'arbitrage' then 1 else 2 end,
           r.cree_le desc;
$$;

-- ---------------------------------------------------------------------
-- 7. LA TABLE DU CABINET
--    Ce que la présidence doit voir de la fédération entière, en un
--    objet. Rien n'est stocké : tout se recalcule à la lecture.
-- ---------------------------------------------------------------------

create or replace function tableau_cabinet()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'remontees_ouvertes', (select count(*)::int from remontees_du_cabinet('ouvertes')),
    'alertes', (select count(*)::int from remontees_du_cabinet('ouvertes')
                where nature = 'alerte'),
    'arbitrages', (select count(*)::int from remontees_du_cabinet('ouvertes')
                   where nature = 'arbitrage'),
    'actes_projets', (select count(*)::int from actes_internes where statut = 'projet'),
    'actes_en_vigueur', (select count(*)::int from actes_internes
                         where statut in ('signe','notifie')),
    'adherents', (select count(*)::int from profils where statut = 'actif'),
    'en_attente', (select count(*)::int from profils where statut = 'en_attente'),
    'encadrants', (select count(*)::int from profils p
                   join fonctions f on f.code = p.fonction
                   where p.statut = 'actif' and f.niveau >= 40),
    'structures', (select count(*)::int from territoires
                   where echelle in ('local','departement') and etat = 'active'),
    -- Une structure sans président n'a personne pour la représenter.
    'sans_president', (select count(*)::int from territoires t
      where t.echelle in ('local','departement') and t.etat = 'active'
        and not exists (select 1 from nominations n
                        where n.territoire_id = t.id
                          and n.poste = 'president_structure'
                          and nomination_active(n))),
    'sans_tresorier', (select count(*)::int from territoires t
      where t.echelle in ('local','departement') and t.etat = 'active'
        and not exists (select 1 from nominations n
                        where n.territoire_id = t.id
                          and n.poste = 'tresorier_structure'
                          and nomination_active(n))),
    'discipline_en_cours', (select count(*)::int from dossiers
                            where statut <> 'clos'),
    'actes_a_controler', (select count(*)::int from actes_sensibles
                          where statut = 'a_controler'));
$$;

-- ---------------------------------------------------------------------
-- 8. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table actes_internes    enable row level security;
alter table remontees_cabinet enable row level security;

drop policy if exists lire_actes_internes on actes_internes;
create policy lire_actes_internes on actes_internes for select using (
  statut in ('signe','notifie','abroge')
  or est_admin() or a_droit('actes.recueil') or a_droit('cabinet.arbitrer')
  or auteur_id = auth.uid()
);

drop policy if exists lire_remontees on remontees_cabinet;
create policy lire_remontees on remontees_cabinet for select using (
  auteur_id = auth.uid() or est_admin() or a_droit('cabinet.arbitrer')
);

grant select on actes_internes, remontees_cabinet to authenticated;

grant execute on function puis_je_prendre_acte(uuid), puis_je_signer_acte(),
                          prendre_acte(text, text, text, text, jsonb, uuid, text, date, uuid),
                          signer_acte(uuid), abroger_acte(uuid, text),
                          recueil_actes(text), texte_acte(uuid),
                          flecher_vers_cabinet(text, text, text, text),
                          traiter_remontee(uuid, text, text),
                          remontees_du_cabinet(text), tableau_cabinet()
  to authenticated;

-- ---------------------------------------------------------------------
-- 9. LES APPLICATIONS
--    Deux portes distinctes : le cabinet, poste de travail réservé ;
--    le recueil, ouvert à tous. Un recueil que personne ne peut lire
--    ne sert à rien.
-- ---------------------------------------------------------------------

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre,
                          droit_requis)
values ('cabinet', 'Cabinet de la présidence', 'Cabinet',
        'Remontées du réseau, actes de la présidence, état de la fédération.',
        'Tout remonte ici, tout en repart.',
        80, false, 'nuit', 'dg', 5, 'cabinet.arbitrer')
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction, ordre = excluded.ordre,
      droit_requis = excluded.droit_requis;

-- Le cabinet n'a pas de version locale : il n'y en a qu'un.
update applications set direction_locale = null where code = 'cabinet';

insert into applications (code, nom, nom_court, description, accroche,
                          niveau_min, sur_demande, couleur, direction, ordre)
values ('recueil', 'Recueil des actes', 'Recueil',
        'Les actes de la présidence en vigueur, consultables et téléchargeables.',
        'Ce que la fédération a décidé, et quand.',
        10, false, 'nuit', 'daj', 45)
on conflict (code) do update
  set nom = excluded.nom, nom_court = excluded.nom_court,
      description = excluded.description, accroche = excluded.accroche,
      direction = excluded.direction;

-- Le cabinet s'ouvre par le poste, jamais par la fonction.
insert into application_visibilite (application, fonction, etat)
select 'cabinet', f.code, case when f.code = 'admin' then 'ouverte' else 'invisible' end
from fonctions f
on conflict (application, fonction) do update
  set etat = case when application_visibilite.fonction = 'admin'
                  then 'ouverte' else 'invisible' end;

-- Le recueil s'ouvre à tous.
insert into application_visibilite (application, fonction, etat)
select 'recueil', f.code, 'ouverte' from fonctions f
on conflict (application, fonction) do update set etat = 'ouverte';

insert into poste_applications (poste, application) values
  ('president_federation', 'cabinet'),
  ('directeur_cabinet', 'cabinet')
on conflict do nothing;

-- Rattrapage : la présidence de structure n'ouvre pas le cabinet.
delete from poste_applications
 where poste = 'president_structure' and application = 'cabinet';

-- =====================================================================
--  FIN DE LA MIGRATION 32
--
--  Pour désigner le président de la fédération :
--    select nommer((select id from profils where email='…'),
--                  'president_federation', null, null,
--                  'Élu par l''assemblée générale du …');
--
--  Vérifications :
--    select tableau_cabinet();
--    select reference, objet, portee, statut from recueil_actes('tous');
--    select * from remontees_du_cabinet('ouvertes');
--
--  Sur la portée : `territoire_id` dit où l'acte s'applique, pas d'où
--  il est pris. Null vaut « toute la fédération ».
--
--  Sur la préparation : le cabinet rédige, la présidence signe. Cette
--  séparation est la raison d'être d'un cabinet — et elle se lit dans
--  la base, pas seulement dans l'interface.
-- =====================================================================
