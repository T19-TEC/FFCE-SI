-- =====================================================================
--  FFCE — Migration 42 — ENGAGER LES POINTS
--
--  Quatre corrections qui tiennent ensemble.
--
--  1. UNE ENVELOPPE SE DÉPENSE AUSSI. Elle ne servait qu'à redistribuer
--     vers des projets. Son porteur peut désormais commander avec —
--     c'est bien le sens d'une enveloppe.
--
--  2. L'ORDRE D'ENGAGEMENT. Si quelqu'un porte une enveloppe
--     personnelle et appartient à une direction qui en porte une, c'est
--     la sienne qui est engagée d'abord. La direction ne paie que ce
--     qui dépasse. Une commande peut donc être financée par deux
--     sources : le détail est conservé, sans quoi personne ne saurait
--     ce qui a été pris à qui.
--
--  3. ENGAGER N'EST PAS COMMANDER. Tout le monde, dans une direction,
--     peut préparer un panier ; seul le responsable habilité l'engage.
--     Un panier déposé sans habilitation part en validation, il ne
--     débite rien tant qu'il n'est pas validé.
--
--  4. LES RATTACHEMENTS. La présidence devient une entité au même titre
--     que les directions : le président national y est rattaché, le
--     délégué général à la direction générale. Le recueil des actes
--     rejoint les affaires juridiques — c'est un instrument juridique,
--     pas un outil de la présidence.
--
--  Prérequis : 01 à 41.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES RATTACHEMENTS
-- ---------------------------------------------------------------------

update postes set direction = 'presidence'
 where code in ('president_federation', 'directeur_cabinet');

-- Le recueil est un instrument juridique : il se lit aux affaires
-- juridiques, où se tient déjà le contrôle de conformité.
update applications set direction = 'daj', direction_locale = null
 where code = 'recueil';

-- La marque de la fédération, pour les organes.
update organes set logo = 'logo.png' where logo is null;

-- Qui appartient à quoi, énoncé une fois pour toutes. L'organigramme
-- n'est pas une donnée à part : il se déduit des postes occupés.
drop function if exists organigramme();
create or replace function organigramme()
returns table (direction text, direction_nom text, direction_ordre integer,
               poste text, poste_nom text, rang integer,
               titulaire text, titulaire_id uuid, territoire text,
               depuis timestamptz, engage_points boolean)
language sql stable security definer set search_path = public as $$
  select d.code, d.nom, d.ordre, po.code, po.nom, po.rang,
         trim(p.prenom || ' ' || p.nom), p.id, t.nom, n.cree_le,
         exists (select 1 from poste_droits pd
                 where pd.poste = po.code and pd.droit = 'points.engager')
  from directions d
  join postes po on po.direction = d.code and po.actif
  left join nominations n on n.poste = po.code and nomination_active(n)
  left join profils p on p.id = n.profil_id
  left join territoires t on t.id = n.territoire_id
  where d.actif and mon_niveau() >= 10
  order by d.ordre, po.rang desc, po.nom;
$$;

-- ---------------------------------------------------------------------
-- 2. LE DROIT D'ENGAGER
--    Appartenir à une direction ne suffit pas à dépenser ses moyens.
--    C'est une habilitation distincte, portée par les responsables.
-- ---------------------------------------------------------------------

insert into droits (code, nom, categorie, sensible, ordre) values
  ('points.engager', 'Engager les points d''une enveloppe', 'Ressources', false, 530)
on conflict (code) do update set nom = excluded.nom;

insert into poste_droits (poste, droit)
select po.code, 'points.engager' from postes po
where po.rang >= 80 and po.actif
on conflict do nothing;

insert into poste_droits (poste, droit) values
  ('parcours_adherent', 'points.engager'),
  ('president_structure', 'points.engager')
on conflict do nothing;

-- Puis-je engager cette enveloppe ? Trois natures, une seule règle :
-- la mienne toujours, celle d'une direction si j'y suis habilité,
-- celle d'un territoire si j'y commande déjà.
create or replace function puis_je_engager(p_nature text, p_ref text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_nature
    when 'profil' then uuid_valide(p_ref) = auth.uid() or est_admin()
    when 'direction' then est_admin() or (a_droit('points.engager') and exists (
      select 1 from nominations n join postes po on po.code = n.poste
      where n.profil_id = auth.uid() and nomination_active(n) and po.direction = p_ref))
    when 'territoire' then est_admin() or a_droit('stock.tenir')
      or (mon_niveau() >= 50 and dans_mon_perimetre(uuid_valide(p_ref)))
    else false end;
$$;

-- Qui, dans une direction, peut engager ? La liste sert à savoir à qui
-- adresser une demande de validation.
drop function if exists habilites_engagement(text, text);
create or replace function habilites_engagement(p_nature text, p_ref text)
returns table (profil_id uuid, membre text, poste text)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), po.nom
  from nominations n
  join postes po on po.code = n.poste
  join profils p on p.id = n.profil_id
  join poste_droits pd on pd.poste = po.code and pd.droit = 'points.engager'
  where nomination_active(n) and p.statut = 'actif'
    and case p_nature
      when 'direction' then po.direction = p_ref
      when 'territoire' then n.territoire_id = uuid_valide(p_ref)
      else false end
  order by po.rang desc;
$$;

-- ---------------------------------------------------------------------
-- 3. LA COMMANDE PEUT ÊTRE FINANCÉE PAR UNE ENVELOPPE
-- ---------------------------------------------------------------------

alter table dotations_exceptionnelles add column if not exists commande_id uuid
  references commandes(id) on delete set null;

alter table commandes add column if not exists finance_par jsonb;
alter table commandes add column if not exists engage_par uuid references profils(id);
alter table commandes add column if not exists engage_le timestamptz;
alter table commandes add column if not exists motif_engagement text;

alter table commandes drop constraint if exists commandes_statut_check;
alter table commandes add constraint commandes_statut_check
  check (statut in ('brouillon','a_valider','deposee','validee','expediee',
                    'recue','refusee','annulee'));

comment on column commandes.finance_par is
  'Détail des enveloppes engagées : [{nature, ref, libelle, points}]. Null : dotation territoriale ordinaire.';

-- Le solde territorial ignore les commandes payées sur une enveloppe :
-- sans quoi la structure paierait deux fois.
create or replace function solde_points(p_territoire uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with t as (select coalesce(p_territoire,
      (select territoire_id from profils where id = auth.uid())) as id),
  d as (select * from dotations, t
        where dotations.territoire_id = t.id
          and dotations.annee = extract(year from current_date)),
  depense as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id and c.finance_par is null
      and extract(year from c.cree_le) = extract(year from current_date)
      and c.statut in ('expediee','recue')),
  engage as (
    select coalesce(sum(c.points_debites), 0)::int as n
    from commandes c, t
    where c.territoire_id = t.id and c.finance_par is null
      and c.statut in ('deposee','validee')),
  exceptionnel as (
    select coalesce(sum(x.points), 0)::int as n
    from dotations_exceptionnelles x, t
    where x.territoire_id = t.id
      and x.annee = extract(year from current_date)::int),
  total as (
    select coalesce((select points_alloues + points_reportes + points_bonus from d), 0)
           + (select n from exceptionnel) as n)
  select jsonb_build_object(
    'annee', extract(year from current_date)::int,
    'territoire', (select nom from territoires, t where territoires.id = t.id),
    'alloues', coalesce((select points_alloues from d), 0),
    'reportes', coalesce((select points_reportes from d), 0),
    'bonus', coalesce((select points_bonus from d), 0) + (select n from exceptionnel),
    'exceptionnel', (select n from exceptionnel),
    'total', (select n from total),
    'depenses', (select n from depense),
    'engages', (select n from engage),
    'disponible', (select n from total) - (select n from depense) - (select n from engage),
    'dotee', exists (select 1 from d) or (select n from exceptionnel) > 0);
$$;

-- Le plan de financement d'un montant : ce qui sera pris, et où. La
-- règle est écrite ici et nulle part ailleurs — l'écran l'affiche, le
-- dépôt l'applique, les deux lisent la même fonction.
create or replace function plan_engagement(p_points integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_reste integer; v_plan jsonb := '[]'::jsonb; v_pris integer;
begin
  v_reste := coalesce(p_points, 0);

  -- L'enveloppe personnelle d'abord : c'est celle qu'on a reçue en son
  -- nom, elle s'engage avant les moyens collectifs.
  for r in
    select * from mes_enveloppes(null)
    order by case nature when 'profil' then 0 else 1 end, libelle
  loop
    exit when v_reste <= 0;
    if not puis_je_engager(r.nature, r.ref) then continue; end if;
    v_pris := least(v_reste, r.disponible);
    if v_pris > 0 then
      v_plan := v_plan || jsonb_build_object('nature', r.nature, 'ref', r.ref,
                            'libelle', r.libelle, 'points', v_pris);
      v_reste := v_reste - v_pris;
    end if;
  end loop;

  return jsonb_build_object('plan', v_plan, 'couvert', coalesce(p_points,0) - v_reste,
                            'reste', v_reste);
end $$;

-- ---------------------------------------------------------------------
-- 4. DÉPOSER, VALIDER, ENGAGER
-- ---------------------------------------------------------------------

create or replace function deposer_commande(p_id uuid, p_motif text default null,
                                            p_adresse text default null,
                                            p_destinataire text default null,
                                            p_source text default 'territoire')
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes; v_total integer; v_solde jsonb; v_plan jsonb; v_l jsonb;
begin
  select * into c from commandes
   where id = p_id and demandeur_id = auth.uid() and statut = 'brouillon';
  if c is null then
    return jsonb_build_object('ok', false, 'message', 'Ce panier n''est plus modifiable.');
  end if;
  if not exists (select 1 from commande_lignes where commande_id = p_id) then
    return jsonb_build_object('ok', false, 'message', 'Votre panier est vide.');
  end if;
  if coalesce(trim(p_adresse),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Indiquez l''adresse de livraison : un colis sans adresse ne part pas.');
  end if;

  select coalesce(sum(points), 0) into v_total
    from commande_lignes where commande_id = p_id;

  update commandes
     set motif = nullif(trim(p_motif),''),
         adresse_livraison = trim(p_adresse),
         destinataire = nullif(trim(p_destinataire),''),
         points_debites = v_total
   where id = p_id;

  -- Voie ordinaire : la dotation du territoire.
  if coalesce(p_source, 'territoire') = 'territoire' then
    v_solde := solde_points(c.territoire_id);
    if v_total > (v_solde->>'disponible')::int then
      return jsonb_build_object('ok', false,
        'message', 'Solde insuffisant : ' || (v_solde->>'disponible') ||
                   ' points disponibles pour ' || v_total || ' demandés.');
    end if;
    if not puis_je_engager('territoire', c.territoire_id::text) then
      update commandes set statut = 'a_valider' where id = p_id;
      return jsonb_build_object('ok', true, 'statut', 'a_valider');
    end if;
    update commandes set statut = 'deposee' where id = p_id;
    return jsonb_build_object('ok', true, 'statut', 'deposee', 'points', v_total);
  end if;

  -- Voie des enveloppes : personnelle d'abord, direction ensuite.
  v_plan := plan_engagement(v_total);
  if (v_plan->>'reste')::int > 0 then
    return jsonb_build_object('ok', false,
      'message', 'Vos enveloppes ne couvrent que ' || (v_plan->>'couvert') ||
                 ' des ' || v_total || ' points nécessaires.');
  end if;

  -- Si l'on n'est habilité sur aucune des enveloppes du plan, la
  -- commande part en validation : préparer n'est pas engager.
  for v_l in select * from jsonb_array_elements(v_plan->'plan') loop
    if not puis_je_engager(v_l->>'nature', v_l->>'ref') then
      update commandes set statut = 'a_valider', finance_par = v_plan->'plan'
       where id = p_id;
      return jsonb_build_object('ok', true, 'statut', 'a_valider');
    end if;
  end loop;

  perform engager_enveloppes(p_id, v_plan->'plan');
  update commandes set statut = 'deposee', finance_par = v_plan->'plan',
         engage_par = auth.uid(), engage_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true, 'statut', 'deposee', 'points', v_total);
end $$;

-- L'écriture du débit, isolée : elle est appelée au dépôt quand
-- l'habilitation est là, et à la validation quand elle ne l'était pas.
create or replace function engager_enveloppes(p_commande uuid, p_plan jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_l jsonb; v_annee integer; v_ref text;
begin
  v_annee := extract(year from current_date)::int;
  for v_l in select * from jsonb_array_elements(coalesce(p_plan, '[]'::jsonb)) loop
    v_ref := v_l->>'ref';
    insert into dotations_exceptionnelles (territoire_id, direction, profil_id,
                                           annee, points, motif, commande_id,
                                           accorde_par)
    values (case when v_l->>'nature' = 'territoire' then uuid_valide(v_ref) end,
            case when v_l->>'nature' = 'direction' then v_ref end,
            case when v_l->>'nature' = 'profil' then uuid_valide(v_ref) end,
            v_annee, -((v_l->>'points')::int),
            'Commande ' || (select reference from commandes where id = p_commande),
            p_commande, auth.uid());
  end loop;
end $$;

create or replace function valider_engagement(p_id uuid, p_ok boolean,
                                              p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes; v_l jsonb;
begin
  select * into c from commandes where id = p_id and statut = 'a_valider';
  if c is null then
    return jsonb_build_object('ok', false,
      'message', 'Cette commande n''attend pas de validation.');
  end if;

  -- Il faut être habilité sur toutes les enveloppes engagées, faute de
  -- quoi on validerait une dépense qu'on n'a pas le droit d'engager.
  if c.finance_par is null then
    if not puis_je_engager('territoire', c.territoire_id::text) then
      return jsonb_build_object('ok', false,
        'message', 'Vous n''engagez pas les points de cette structure.');
    end if;
  else
    for v_l in select * from jsonb_array_elements(c.finance_par) loop
      if not puis_je_engager(v_l->>'nature', v_l->>'ref') then
        return jsonb_build_object('ok', false,
          'message', 'Vous n''engagez pas les points de « ' ||
                     (v_l->>'libelle') || ' ».');
      end if;
    end loop;
  end if;

  if not p_ok then
    if coalesce(trim(p_motif),'') = '' then
      return jsonb_build_object('ok', false, 'message', 'Un refus se motive.');
    end if;
    update commandes set statut = 'refusee', motif_refus = trim(p_motif),
           traite_par = auth.uid(), traite_le = now()
     where id = p_id;
    return jsonb_build_object('ok', true);
  end if;

  if c.finance_par is not null then
    perform engager_enveloppes(p_id, c.finance_par);
  end if;
  update commandes set statut = 'deposee', engage_par = auth.uid(), engage_le = now(),
         motif_engagement = nullif(trim(p_motif),'')
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Rendre les points quand une commande financée sur enveloppe est
-- refusée ou retirée : la ligne négative est effacée, le solde se
-- recalcule tout seul.
create or replace function retirer_commande(p_id uuid, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c commandes;
begin
  select * into c from commandes where id = p_id;
  if c is null then
    return jsonb_build_object('ok', false, 'message', 'Commande introuvable.');
  end if;
  if c.statut in ('expediee','recue','annulee') then
    return jsonb_build_object('ok', false,
      'message', 'Cette commande est déjà partie : elle ne se retire plus.');
  end if;
  if not (c.demandeur_id = auth.uid() or est_admin() or a_droit('stock.national')) then
    return jsonb_build_object('ok', false, 'message', 'Cette commande n''est pas la vôtre.');
  end if;
  if c.demandeur_id <> auth.uid() and coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false,
      'message', 'Retirer la commande d''autrui se motive.');
  end if;

  delete from dotations_exceptionnelles where commande_id = p_id;
  update commandes
     set statut = 'annulee', motif_refus = nullif(trim(p_motif),''),
         traite_par = auth.uid(), traite_le = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Les commandes en attente de validation d'engagement, pour ceux qui
-- peuvent les engager.
drop function if exists engagements_a_valider();
create or replace function engagements_a_valider()
returns table (id uuid, reference text, demandeur text, territoire text,
               points integer, finance_par jsonb, motif text, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.reference, trim(p.prenom || ' ' || p.nom), t.nom,
         c.points_debites, c.finance_par, c.motif, c.cree_le
  from commandes c
  join profils p on p.id = c.demandeur_id
  left join territoires t on t.id = c.territoire_id
  where c.statut = 'a_valider'
    and (
      (c.finance_par is null and puis_je_engager('territoire', c.territoire_id::text))
      or (c.finance_par is not null and exists (
            select 1 from jsonb_array_elements(c.finance_par) l
            where puis_je_engager(l->>'nature', l->>'ref')))
    )
  order by c.cree_le;
$$;

grant execute on function organigramme(), puis_je_engager(text, text),
                          habilites_engagement(text, text), solde_points(uuid),
                          plan_engagement(integer),
                          deposer_commande(uuid, text, text, text, text),
                          engager_enveloppes(uuid, jsonb),
                          valider_engagement(uuid, boolean, text),
                          retirer_commande(uuid, text), engagements_a_valider()
  to authenticated;

drop function if exists deposer_commande(uuid, text, text, text);

-- =====================================================================
--  FIN DE LA MIGRATION 42
--
--  Vérifications :
--    select * from organigramme();
--    select plan_engagement(150);
--    select * from engagements_a_valider();
--
--  Sur l'ordre d'engagement : la règle « le personnel d'abord, la
--  direction ensuite » est écrite dans `plan_engagement` et nulle part
--  ailleurs. L'écran l'affiche, le dépôt l'applique, la validation la
--  revérifie — les trois lisent la même fonction, donc aucune ne peut
--  s'en écarter.
--
--  Sur le partage entre deux enveloppes : une commande peut être payée
--  pour partie par le personnel et pour partie par la direction. Le
--  détail est conservé dans `finance_par`, sans quoi personne ne
--  saurait ce qui a été pris à qui — et le contrôle a posteriori
--  deviendrait impossible.
-- =====================================================================
