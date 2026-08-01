-- =====================================================================
--  FFCE — Migration 21 — CORRECTIF, INTÉRIM ET SUPPLÉANCE
--
--  0. LE CORRECTIF. Un déclencheur unique servait trois tables et
--     référençait new.mesure_id, qui n'existe que sur l'une d'elles.
--     PL/pgSQL prépare l'expression entière avant de l'exécuter : tous
--     les champs cités doivent exister, même dans une branche non
--     empruntée. D'où l'erreur sur chaque action.
--
--  1. L'INTÉRIM. Un trésorier part trois semaines. Aujourd'hui : soit
--     rien, soit des droits durables. Désormais une délégation datée,
--     qui s'éteint seule, et pendant laquelle l'intérimaire agit
--     visiblement au nom de quelqu'un.
--
--  2. LA FICHE DE POSTE. Nommer quelqu'un référent départemental
--     demandait six gestes. Un poste porte désormais ses accès et ses
--     formations obligatoires : nommer ouvre tout, révoquer referme
--     tout. C'est ce qui évite les habilitations orphelines.
--
--  3. LA SUPPLÉANCE. Si le président d'une unité locale disparaît,
--     personne ne peut convoquer l'assemblée qui le remplacerait. Un
--     ordre de suppléance débloque ces situations sans passer par le
--     national.
--
--  4. LES VIREMENTS. Mise en paiement, accusé de réception, relance à
--     quinze jours, et contestation qui remonte en alerte.
--
--  Prérequis : 01 à 20.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CORRECTIF DU DÉCLENCHEUR DE CLÔTURE
-- ---------------------------------------------------------------------

drop trigger if exists trg_scelle_pieces  on dossier_pieces;
drop trigger if exists trg_scelle_mesures on mesures;
drop trigger if exists trg_scelle_recours on recours;
drop function if exists refuser_si_scelle() cascade;

create or replace function dossier_est_clos(p_dossier uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from dossiers where id = p_dossier and statut = 'clos');
$$;

-- Une fonction par table : chacune ne cite que les champs qui existent.
create or replace function scelle_sur_dossier()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if dossier_est_clos(new.dossier_id) then
    raise exception 'Ce dossier est clos. Plus aucune pièce ne peut y être versée.';
  end if;
  return new;
end $$;

create or replace function scelle_sur_recours()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_dossier uuid;
begin
  select dossier_id into v_dossier from mesures where id = new.mesure_id;
  if dossier_est_clos(v_dossier) then
    raise exception 'Ce dossier est clos. Plus aucun recours ne peut y être formé.';
  end if;
  return new;
end $$;

create trigger trg_scelle_pieces before insert on dossier_pieces
  for each row execute function scelle_sur_dossier();
create trigger trg_scelle_mesures before insert on mesures
  for each row execute function scelle_sur_dossier();
create trigger trg_scelle_recours before insert on recours
  for each row execute function scelle_sur_recours();

-- ---------------------------------------------------------------------
-- 1. FICHES DE POSTE
--    Ce qu'un poste emporte : des accès, des formations, un délai.
-- ---------------------------------------------------------------------

alter table postes add column if not exists mission text;
alter table postes add column if not exists delai_prise_fonction integer default 30;
alter table postes add column if not exists suppleant_de text references postes(code);
alter table postes add column if not exists ordre_suppleance integer;

create table if not exists poste_applications (
  poste       text not null references postes(code) on delete cascade,
  application text not null references applications(code) on delete cascade,
  primary key (poste, application)
);

create table if not exists poste_formations (
  poste        text not null references postes(code) on delete cascade,
  certification text not null references certifications(code) on delete cascade,
  obligatoire  boolean not null default true,
  delai_jours  integer not null default 90,
  primary key (poste, certification)
);

insert into poste_applications (poste, application) values
  ('dg_finance','tresorerie'), ('dg_finance','notes_frais'),
  ('ordonnateur','ordonnancement'),
  ('daj','discipline'), ('conformite_election','assemblees'),
  ('dircom','communication'), ('dircom','vitrine'),
  ('charge_com','communication'),
  ('parcours_adherent','parcours'), ('parcours_adherent','annuaire'),
  ('chancellerie','chancellerie'),
  ('tresorier_structure','notes_frais'),
  ('president_structure','pilotage'), ('president_structure','annuaire')
on conflict do nothing;

insert into poste_formations (poste, certification, obligatoire, delai_jours)
select po.code, 'usage_si', true, 60
from postes po
where po.code in ('president_structure','tresorier_structure','secretaire_structure',
                  'parcours_adherent','dircom','charge_com','dg_finance')
on conflict do nothing;

-- L'ordre de suppléance statutaire.
update postes set suppleant_de = 'president_structure', ordre_suppleance = 1
 where code = 'secretaire_structure' and suppleant_de is null;
update postes set suppleant_de = 'president_structure', ordre_suppleance = 2
 where code = 'tresorier_structure' and suppleant_de is null;

-- Nommer ouvre le paquet ; révoquer le referme.
create or replace function ouvrir_paquet_poste()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into acces_applications (profil_id, application, statut, motif, accorde_par)
  select new.profil_id, pa.application, 'accorde',
         'Ouvert par le poste « ' || (select nom from postes where code = new.poste) || ' »',
         new.nomme_par
  from poste_applications pa where pa.poste = new.poste
  on conflict (profil_id, application) do update
    set statut = 'accorde', revoque_le = null, motif_revocation = null;
  return new;
end $$;

drop trigger if exists trg_paquet_nomination on nominations;
create trigger trg_paquet_nomination
  after insert on nominations
  for each row execute function ouvrir_paquet_poste();

create or replace function fermer_paquet_poste()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.revoque_le is not null and old.revoque_le is null then
    update acces_applications x
       set statut = 'revoque', revoque_le = now(), revoque_par = new.revoque_par,
           motif_revocation = 'Fin du poste « ' ||
             (select nom from postes where code = new.poste) || ' »'
     where x.profil_id = new.profil_id
       and x.application in (select pa.application from poste_applications pa
                             where pa.poste = new.poste)
       -- On ne referme pas ce qu'un autre poste ouvre encore.
       and not exists (
         select 1 from nominations n2
         join poste_applications pa2 on pa2.poste = n2.poste
         where n2.profil_id = new.profil_id and n2.id <> new.id
           and nomination_active(n2) and pa2.application = x.application);
  end if;
  return new;
end $$;

drop trigger if exists trg_paquet_revocation on nominations;
create trigger trg_paquet_revocation
  after update on nominations
  for each row execute function fermer_paquet_poste();

-- Ce qu'un poste exige, et où en est son titulaire.
create or replace function conformite_poste(p_profil uuid, p_poste text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'formations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'certification', c.nom, 'obligatoire', pf.obligatoire,
        'delai_jours', pf.delai_jours,
        'obtenue', exists (select 1 from certifications_obtenues co
                           where co.profil_id = p_profil and co.code = pf.certification)))
      from poste_formations pf join certifications c on c.code = pf.certification
      where pf.poste = p_poste), '[]'::jsonb),
    'applications', coalesce((
      select jsonb_agg(a.nom) from poste_applications pa
      join applications a on a.code = pa.application
      where pa.poste = p_poste), '[]'::jsonb),
    'conforme', not exists (
      select 1 from poste_formations pf
      where pf.poste = p_poste and pf.obligatoire
        and not exists (select 1 from certifications_obtenues co
                        where co.profil_id = p_profil and co.code = pf.certification)));
$$;

-- Qui n'a pas suivi ce que son poste exige.
create or replace function postes_non_conformes()
returns table (profil_id uuid, membre text, poste text, poste_nom text,
               territoire text, depuis date, jours integer,
               manquantes text, delai_depasse boolean)
language sql stable security definer set search_path = public as $$
  select p.id, trim(p.prenom || ' ' || p.nom), po.code, po.nom, t.nom,
         n.debut, (current_date - n.debut)::int,
         string_agg(c.nom, ', '),
         bool_or((current_date - n.debut) > pf.delai_jours)
  from nominations n
  join postes po on po.code = n.poste
  join profils p on p.id = n.profil_id
  left join territoires t on t.id = n.territoire_id
  join poste_formations pf on pf.poste = po.code and pf.obligatoire
  join certifications c on c.code = pf.certification
  where nomination_active(n)
    and not exists (select 1 from certifications_obtenues co
                    where co.profil_id = p.id and co.code = pf.certification)
    and (est_admin() or a_droit('habilitations.gerer') or mon_niveau() >= 60)
  group by p.id, p.prenom, p.nom, po.code, po.nom, t.nom, n.debut
  order by bool_or((current_date - n.debut) > pf.delai_jours) desc, n.debut;
$$;

-- ---------------------------------------------------------------------
-- 2. INTÉRIM
-- ---------------------------------------------------------------------

create table if not exists interims (
  id            uuid primary key default gen_random_uuid(),
  titulaire_id  uuid not null references profils(id) on delete cascade,
  interimaire_id uuid not null references profils(id) on delete cascade,
  poste         text references postes(code) on delete cascade,
  debut         date not null default current_date,
  fin           date not null,
  motif         text not null,
  accepte_le    timestamptz,
  refuse_le     timestamptz,
  clos_le       timestamptz,
  decide_par    uuid references profils(id),
  cree_le       timestamptz not null default now(),
  check (fin >= debut)
);
create index if not exists idx_interims on interims(interimaire_id, debut, fin);

create or replace function interim_actif(i interims)
returns boolean language sql immutable as $$
  select i.accepte_le is not null and i.refuse_le is null and i.clos_le is null
     and current_date between i.debut and i.fin;
$$;

create or replace function confier_interim(
  p_interimaire uuid, p_poste text, p_debut date, p_fin date, p_motif text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  -- On délègue un poste qu'on occupe soi-même, ou l'administrateur délègue.
  if not (est_admin() or exists (
      select 1 from nominations n where n.profil_id = auth.uid()
        and n.poste = p_poste and nomination_active(n))) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne pouvez déléguer qu''un poste que vous occupez.');
  end if;
  if p_interimaire = auth.uid() then
    return jsonb_build_object('ok', false, 'message', 'Choisissez une autre personne.');
  end if;
  if coalesce(trim(p_motif),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Un intérim doit être motivé.');
  end if;
  if coalesce(p_fin, current_date) - coalesce(p_debut, current_date) > 180 then
    return jsonb_build_object('ok', false,
      'message', 'Un intérim ne dépasse pas six mois. Au-delà, il faut nommer.');
  end if;

  insert into interims (titulaire_id, interimaire_id, poste, debut, fin, motif)
  values (auth.uid(), p_interimaire, p_poste,
          coalesce(p_debut, current_date), p_fin, trim(p_motif))
  returning id into v_id;

  perform inscrire_acte(p_interimaire, 'interim',
    'Intérim confié : ' || (select nom from postes where code = p_poste) ||
    ' jusqu''au ' || to_char(p_fin,'DD/MM/YYYY'),
    null, jsonb_build_object('interim_id', v_id), true);

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function repondre_interim(p_id uuid, p_accepte boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update interims
     set accepte_le = case when p_accepte then now() end,
         refuse_le  = case when not p_accepte then now() end
   where id = p_id and interimaire_id = auth.uid()
     and accepte_le is null and refuse_le is null;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Cet intérim ne vous est pas proposé.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function clore_interim(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from interims where id = p_id
                 and (titulaire_id = auth.uid() or est_admin())) then
    return jsonb_build_object('ok', false, 'message', 'Cet intérim n''est pas le vôtre.');
  end if;
  update interims set clos_le = now() where id = p_id and clos_le is null;
  return jsonb_build_object('ok', true);
end $$;

-- Les droits s'étendent à l'intérim et à la suppléance.
create or replace function a_droit(p_droit text)
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin()
    -- Par un poste que j'occupe
    or exists (
      select 1 from nominations n
      join poste_droits pd on pd.poste = n.poste
      join postes p on p.code = n.poste
      where n.profil_id = auth.uid() and pd.droit = p_droit
        and p.actif and nomination_active(n))
    -- Par un intérim accepté et en cours
    or exists (
      select 1 from interims i
      join poste_droits pd on pd.poste = i.poste
      join postes p on p.code = i.poste
      where i.interimaire_id = auth.uid() and pd.droit = p_droit
        and p.actif and interim_actif(i));
$$;

create or replace function mes_interims()
returns table (id uuid, poste text, poste_nom text, titulaire text, interimaire text,
               debut date, fin date, motif text, statut text,
               je_suis_interimaire boolean, jours_restants integer)
language sql stable security definer set search_path = public as $$
  select i.id, i.poste, po.nom,
         trim(t.prenom || ' ' || t.nom), trim(m.prenom || ' ' || m.nom),
         i.debut, i.fin, i.motif,
         case when i.refuse_le is not null then 'refuse'
              when i.clos_le is not null then 'clos'
              when i.accepte_le is null then 'propose'
              when current_date > i.fin then 'echu'
              when current_date < i.debut then 'a_venir'
              else 'en_cours' end,
         i.interimaire_id = auth.uid(),
         (i.fin - current_date)::int
  from interims i
  join postes po on po.code = i.poste
  join profils t on t.id = i.titulaire_id
  join profils m on m.id = i.interimaire_id
  where i.titulaire_id = auth.uid() or i.interimaire_id = auth.uid() or est_admin()
  order by i.debut desc;
$$;

-- Au nom de qui j'agis en ce moment : à afficher, toujours.
create or replace function mes_delegations()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'poste', po.nom, 'au_nom_de', trim(t.prenom || ' ' || t.nom),
    'jusqu_au', i.fin)), '[]'::jsonb)
  from interims i
  join postes po on po.code = i.poste
  join profils t on t.id = i.titulaire_id
  where i.interimaire_id = auth.uid() and interim_actif(i);
$$;

-- ---------------------------------------------------------------------
-- 3. SUPPLÉANCE
--    Le poste est vacant ou son titulaire est empêché : le suppléant
--    statutaire peut agir, et cela se voit.
-- ---------------------------------------------------------------------

create or replace function poste_vacant(p_poste text, p_territoire uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from nominations n
    where n.poste = p_poste and nomination_active(n)
      and (p_territoire is null or n.territoire_id = p_territoire));
$$;

-- Suis-je suppléant d'un poste vacant sur ce territoire ?
create or replace function je_supplee(p_poste text, p_territoire uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select poste_vacant(p_poste, p_territoire)
     and exists (
       select 1 from nominations n
       join postes po on po.code = n.poste
       where n.profil_id = auth.uid() and nomination_active(n)
         and po.suppleant_de = p_poste
         and (p_territoire is null or n.territoire_id = p_territoire)
         -- Aucun suppléant de rang supérieur n'est en place.
         and not exists (
           select 1 from nominations n2
           join postes po2 on po2.code = n2.poste
           where nomination_active(n2) and po2.suppleant_de = p_poste
             and n2.territoire_id = n.territoire_id
             and po2.ordre_suppleance < po.ordre_suppleance));
$$;

create or replace function ma_suppleance()
returns table (poste text, poste_nom text, territoire text, territoire_id uuid,
               depuis_quand integer)
language sql stable security definer set search_path = public as $$
  select po2.code, po2.nom, t.nom, t.id,
         (current_date - n.debut)::int
  from nominations n
  join postes po on po.code = n.poste
  join postes po2 on po2.code = po.suppleant_de
  left join territoires t on t.id = n.territoire_id
  where n.profil_id = auth.uid() and nomination_active(n)
    and po.suppleant_de is not null
    and je_supplee(po.suppleant_de, n.territoire_id);
$$;

-- Organiser une assemblée devient possible pour le suppléant : c'est
-- exactement la situation qu'il faut débloquer.
create or replace function creer_assemblee(
  p_territoire uuid, p_titre text, p_type text, p_date timestamptz,
  p_lieu text, p_ordre_du_jour text, p_cloture_cand date,
  p_ouverture_scrutin timestamptz, p_cloture_scrutin timestamptz,
  p_quorum integer, p_duree integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_supplee boolean;
begin
  v_supplee := je_supplee('president_structure', p_territoire);
  if not (a_droit('scrutin.organiser') or a_droit('election.conformite')
          or est_admin() or mon_niveau() >= 60 or v_supplee) then
    return jsonb_build_object('ok', false, 'message', 'Vous n''organisez pas d''assemblée.');
  end if;

  insert into assemblees (territoire_id, titre, type, date_tenue, lieu, ordre_du_jour,
                          ouverture_candidatures, cloture_candidatures,
                          ouverture_scrutin, cloture_scrutin, quorum_requis,
                          duree_mandat_ans, organise_par, statut)
  values (p_territoire, trim(p_titre), p_type, p_date, nullif(trim(p_lieu),''),
          nullif(trim(p_ordre_du_jour),''), current_date, p_cloture_cand,
          p_ouverture_scrutin, p_cloture_scrutin, coalesce(p_quorum,0),
          coalesce(p_duree,3), auth.uid(), 'candidatures')
  returning id into v_id;

  if v_supplee then
    perform inscrire_acte(null, 'suppleance',
      'Assemblée convoquée au titre de la suppléance — présidence vacante',
      null, jsonb_build_object('assemblee_id', v_id), false);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'suppleance', v_supplee);
end $$;

-- ---------------------------------------------------------------------
-- 4. LES VIREMENTS : MISE EN PAIEMENT, ACCUSÉ, RELANCE
-- ---------------------------------------------------------------------

alter table notes_frais add column if not exists accuse_le timestamptz;
alter table notes_frais add column if not exists conteste_le timestamptz;
alter table notes_frais add column if not exists motif_contestation text;
alter table notes_frais add column if not exists attestation text;   -- dépôt privé
alter table notes_frais add column if not exists relance_le timestamptz;

create or replace function accuser_virement(p_note uuid, p_recu boolean,
                                            p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n notes_frais;
begin
  select * into n from notes_frais where id = p_note and profil_id = auth.uid();
  if n is null then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est pas la vôtre.');
  end if;
  if n.statut <> 'payee' then
    return jsonb_build_object('ok', false, 'message', 'Cette note n''est pas encore payée.');
  end if;

  if p_recu then
    update notes_frais set accuse_le = now(), conteste_le = null,
           motif_contestation = null where id = p_note;
  else
    if coalesce(trim(p_motif),'') = '' then
      return jsonb_build_object('ok', false,
        'message', 'Précisez ce qui ne va pas : montant, absence de virement, autre.');
    end if;
    update notes_frais set conteste_le = now(), motif_contestation = trim(p_motif),
           accuse_le = null where id = p_note;
    perform inscrire_acte(auth.uid(), 'finance',
      'Virement contesté — note ' || n.reference || ' : ' || trim(p_motif),
      null, jsonb_build_object('note_id', p_note), false);
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- L'attestation de don, déposée par la direction financière.
create or replace function deposer_attestation(p_note uuid, p_fichier text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not a_droit('finance.payer') then
    return jsonb_build_object('ok', false, 'message', 'Réservé à la direction financière.');
  end if;
  if coalesce(p_fichier,'') = '' then
    return jsonb_build_object('ok', false, 'message', 'Aucun fichier fourni.');
  end if;
  update notes_frais set attestation = p_fichier where id = p_note;
  return jsonb_build_object('ok', true);
end $$;

-- Ce que la direction financière doit surveiller.
create or replace function virements_a_suivre()
returns table (note_id uuid, reference text, objet text, deposant text,
               deposant_id uuid, total numeric, payee_le timestamptz,
               jours integer, etat text, motif_contestation text,
               mode text, attestation text)
language sql stable security definer set search_path = public as $$
  select n.id, n.reference, n.objet, trim(p.prenom || ' ' || p.nom), p.id,
         total_note(n.id), n.payee_le,
         extract(day from now() - n.payee_le)::int,
         case
           when n.conteste_le is not null then 'conteste'
           when n.accuse_le is not null then 'accuse'
           when n.mode_remboursement = 'abandon_creance'
                and n.attestation is null then 'attestation_manquante'
           when n.mode_remboursement = 'virement'
                and n.payee_le < now() - interval '15 days' then 'sans_reponse'
           else 'en_attente' end,
         n.motif_contestation, n.mode_remboursement, n.attestation
  from notes_frais n
  join profils p on p.id = n.profil_id
  where n.statut = 'payee'
    and (n.accuse_le is null or n.conteste_le is not null
         or (n.mode_remboursement = 'abandon_creance' and n.attestation is null))
    and (a_droit('finance.payer') or a_droit('finance.instruire') or est_admin())
  order by
    case when n.conteste_le is not null then 0
         when n.payee_le < now() - interval '15 days' then 1 else 2 end,
    n.payee_le;
$$;

-- Ce que le membre doit confirmer.
create or replace function mes_virements_a_confirmer()
returns table (note_id uuid, reference text, objet text, total numeric,
               payee_le timestamptz, jours integer, mode text,
               reference_paiement text, attestation text, recu_fiscal text)
language sql stable security definer set search_path = public as $$
  select n.id, n.reference, n.objet, total_note(n.id), n.payee_le,
         extract(day from now() - n.payee_le)::int, n.mode_remboursement,
         n.reference_paiement, n.attestation, n.recu_fiscal
  from notes_frais n
  where n.profil_id = auth.uid() and n.statut = 'payee'
    and n.accuse_le is null and n.conteste_le is null
  order by n.payee_le;
$$;

-- La relance s'inscrit une fois, à quinze jours.
create or replace function relancer_virements()
returns integer language sql security definer set search_path = public as $$
  with maj as (
    update notes_frais set relance_le = now()
     where statut = 'payee' and accuse_le is null and conteste_le is null
       and relance_le is null and payee_le < now() - interval '15 days'
    returning 1)
  select count(*)::int from maj;
$$;

-- ---------------------------------------------------------------------
-- 5. LA CHANCELLERIE SE VOIT
--    Une distinction n'a de sens que si elle est portée. On expose
--    donc l'insigne le plus élevé partout où un nom apparaît.
-- ---------------------------------------------------------------------

create or replace function insigne_membre(p_profil uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'echelon', p.echelon,
    'echelon_nom', e.nom,
    'distinction', (select td.nom from distinctions d
                    join types_distinction td on td.code = d.type
                    where d.profil_id = p.id and d.retiree_le is null and d.publique
                    order by td.points desc limit 1),
    'distinction_couleur', (select td.couleur from distinctions d
                    join types_distinction td on td.code = d.type
                    where d.profil_id = p.id and d.retiree_le is null and d.publique
                    order by td.points desc limit 1),
    'nb_distinctions', (select count(*) from distinctions d
                        where d.profil_id = p.id and d.retiree_le is null and d.publique),
    'postes', coalesce((select jsonb_agg(po.nom) from nominations n
                        join postes po on po.code = n.poste
                        where n.profil_id = p.id and nomination_active(n)), '[]'::jsonb))
  from profils p join echelons e on e.niveau = p.echelon
  where p.id = p_profil;
$$;

-- Les insignes de tous les participants d'une conversation, en un appel.
create or replace function insignes(p_profils uuid[])
returns table (profil_id uuid, echelon integer, echelon_nom text,
               distinction text, couleur text, poste text)
language sql stable security definer set search_path = public as $$
  select p.id, p.echelon, e.nom,
         (select td.nom from distinctions d join types_distinction td on td.code = d.type
          where d.profil_id = p.id and d.retiree_le is null and d.publique
          order by td.points desc limit 1),
         (select td.couleur from distinctions d join types_distinction td on td.code = d.type
          where d.profil_id = p.id and d.retiree_le is null and d.publique
          order by td.points desc limit 1),
         (select po.nom from nominations n join postes po on po.code = n.poste
          where n.profil_id = p.id and nomination_active(n)
          order by po.ordre_suppleance nulls first limit 1)
  from profils p join echelons e on e.niveau = p.echelon
  where p.id = any(coalesce(p_profils, '{}'));
$$;

-- ---------------------------------------------------------------------
-- 6. SÉCURITÉ
-- ---------------------------------------------------------------------

alter table interims           enable row level security;
alter table poste_applications enable row level security;
alter table poste_formations   enable row level security;

drop policy if exists lire_interims on interims;
create policy lire_interims on interims for select using (
  titulaire_id = auth.uid() or interimaire_id = auth.uid()
  or est_admin() or a_droit('habilitations.gerer')
);

drop policy if exists lire_poste_apps on poste_applications;
create policy lire_poste_apps on poste_applications for select using (mon_niveau() >= 10);
drop policy if exists gerer_poste_apps on poste_applications;
create policy gerer_poste_apps on poste_applications for all
  using (a_droit('habilitations.gerer')) with check (a_droit('habilitations.gerer'));

drop policy if exists lire_poste_form on poste_formations;
create policy lire_poste_form on poste_formations for select using (mon_niveau() >= 10);
drop policy if exists gerer_poste_form on poste_formations;
create policy gerer_poste_form on poste_formations for all
  using (a_droit('habilitations.gerer')) with check (a_droit('habilitations.gerer'));

grant select on interims, poste_applications, poste_formations to authenticated;
grant insert, update, delete on poste_applications, poste_formations to authenticated;

grant execute on function dossier_est_clos(uuid), conformite_poste(uuid, text),
                          postes_non_conformes(), interim_actif(interims),
                          confier_interim(uuid, text, date, date, text),
                          repondre_interim(uuid, boolean), clore_interim(uuid),
                          a_droit(text), mes_interims(), mes_delegations(),
                          poste_vacant(text, uuid), je_supplee(text, uuid),
                          ma_suppleance(),
                          creer_assemblee(uuid, text, text, timestamptz, text, text,
                                          date, timestamptz, timestamptz, integer, integer),
                          accuser_virement(uuid, boolean, text),
                          deposer_attestation(uuid, text), virements_a_suivre(),
                          mes_virements_a_confirmer(), relancer_virements(),
                          insigne_membre(uuid), insignes(uuid[])
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 21
--
--  Vérifications :
--    select * from mes_interims();
--    select * from postes_non_conformes();
--    select * from virements_a_suivre();
--    select ma_suppleance();
--
--  Sur l'intérim : les droits s'étendent, mais l'intérimaire agit
--  visiblement au nom de quelqu'un — mes_delegations() le rappelle sur
--  son écran, et le registre des actes en garde trace. Six mois
--  maximum : au-delà, il faut nommer.
-- =====================================================================
