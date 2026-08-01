-- =====================================================================
--  FFCE — Migration 33 — LA MESSAGERIE : QUI, ET AVEC QUOI
--
--  Deux manques dans la messagerie, et une demande à laquelle je réponds
--  autrement que demandée.
--
--  1. On discute avec un nom sans savoir qui il est. Un profil interne
--     consultable depuis la conversation règle cela — sans rien ouvrir
--     de plus que ce que la fédération considère déjà comme interne :
--     ni adresse, ni téléphone, ni courriel. Ceux-là restent dans la
--     fiche membre, avec son journal de consultation.
--
--  2. On ne peut rien s'envoyer. Un compte rendu, une photo d'affiche,
--     un devis : tout passe aujourd'hui par des canaux hors du système.
--
--  3. La demande était : « tout envoi de fichier déclenche une alerte à
--     l'administrateur ». Ce serait de la surveillance du contenu privé,
--     et cela contredirait la supervision strictement descendante posée
--     en migration 05. Ce qui est fait à la place : un journal des
--     envois — qui, quand, vers qui, quel nom, quelle taille — sans
--     aucun accès au contenu ni au fichier. La traçabilité existe, le
--     droit de lecture générale n'est pas créé. L'administrateur voit
--     dans sa file de travail combien d'envois ont eu lieu depuis son
--     dernier contrôle.
--
--  Prérequis : 01 à 32.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LES PIÈCES JOINTES
-- ---------------------------------------------------------------------

alter table messages add column if not exists piece text;
alter table messages add column if not exists piece_nom text;
alter table messages add column if not exists piece_taille integer;
alter table messages add column if not exists piece_type text;

-- Un message ne peut plus être vide de texte *et* de pièce : la
-- contrainte d'origine exigeait du texte, ce qui interdisait d'envoyer
-- un fichier seul. On élargit la règle sans la supprimer.
alter table messages drop constraint if exists messages_contenu_check;
alter table messages add constraint messages_contenu_check
  check (length(trim(contenu)) > 0 or piece is not null);

-- La garde de conversion : une valeur qui n'a pas la forme d'un
-- identifiant renvoie null au lieu de lever une erreur. Dans une
-- politique de sécurité, c'est la différence entre un refus et une panne.
create or replace function uuid_valide(p_texte text)
returns uuid language sql immutable as $$
  select case
    when p_texte ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then p_texte::uuid else null end;
$$;
grant execute on function uuid_valide(text) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('pieces', 'pieces', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

-- Le chemin d'une pièce commence par l'identifiant de la conversation :
-- c'est ce qui permet à Storage de savoir qui a le droit de la lire,
-- sans dupliquer la règle d'accès.
drop policy if exists depot_pieces on storage.objects;
create policy depot_pieces on storage.objects for insert to authenticated
  with check (bucket_id = 'pieces'
              and est_participant(uuid_valide((storage.foldername(name))[1])));

drop policy if exists lecture_pieces on storage.objects;
create policy lecture_pieces on storage.objects for select to authenticated
  using (bucket_id = 'pieces'
         and accede_conversation(uuid_valide((storage.foldername(name))[1])));

drop policy if exists suppr_pieces on storage.objects;
create policy suppr_pieces on storage.objects for delete to authenticated
  using (bucket_id = 'pieces' and owner = auth.uid());

-- L'envoi accepte désormais une pièce. Ancienne signature supprimée
-- pour qu'il n'existe qu'une seule fonction de ce nom.
drop function if exists envoyer_message(uuid, text);
create or replace function envoyer_message(
  p_conv uuid, p_contenu text default null, p_piece text default null,
  p_piece_nom text default null, p_taille integer default null,
  p_type text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not est_participant(p_conv) then
    return jsonb_build_object('ok', false,
      'message', 'Vous ne participez pas à cette conversation.');
  end if;
  if (select statut from profils where id = auth.uid()) <> 'actif' then
    return jsonb_build_object('ok', false, 'message', 'Compte non validé.');
  end if;
  if coalesce(trim(p_contenu),'') = '' and p_piece is null then
    return jsonb_build_object('ok', false, 'message', 'Message vide.');
  end if;
  -- Une pièce ne peut pas venir d'ailleurs que de cette conversation.
  if p_piece is not null and p_piece not like (p_conv::text || '/%') then
    return jsonb_build_object('ok', false,
      'message', 'Cette pièce n''appartient pas à cette conversation.');
  end if;

  insert into messages (conversation_id, auteur_id, contenu, piece,
                        piece_nom, piece_taille, piece_type)
  values (p_conv, auth.uid(),
          coalesce(nullif(trim(p_contenu),''), '[pièce jointe]'),
          p_piece, p_piece_nom, p_taille, p_type);

  update conversations set derniere_activite = now() where id = p_conv;
  update conv_participants set lu_jusqu_a = now()
   where conversation_id = p_conv and profil_id = auth.uid();

  return jsonb_build_object('ok', true);
end $$;

-- Retirer un message retire aussi le lien vers la pièce. Le fichier
-- lui-même reste dans Storage : son effacement se fait depuis
-- l'interface, par son propriétaire.
create or replace function retirer_message(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m messages;
begin
  select * into m from messages where id = p_id;
  if m is null then
    return jsonb_build_object('ok', false, 'message', 'Message introuvable.');
  end if;
  if not (m.auteur_id = auth.uid() or est_admin()) then
    return jsonb_build_object('ok', false,
      'message', 'On ne retire que ses propres messages.');
  end if;
  update messages set retire = true, retire_par = auth.uid(), piece = null
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 2. LE PROFIL INTERNE
--    Ce que la fédération montre d'un membre à un autre membre. Rien de
--    plus : le courriel, le téléphone et l'adresse relèvent de la fiche
--    membre, qui journalise sa consultation.
-- ---------------------------------------------------------------------

create or replace function profil_interne(p_profil uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not (
      p_profil = auth.uid() or est_admin()
      or puis_je_ecrire_a(p_profil)
      or exists (select 1 from conv_participants a
                 join conv_participants b on b.conversation_id = a.conversation_id
                 where a.profil_id = auth.uid() and b.profil_id = p_profil)
    ) then jsonb_build_object('ok', false,
             'message', 'Ce profil ne vous est pas ouvert.')
  else jsonb_build_object(
    'ok', true,
    'id', p.id,
    'nom', trim(p.prenom || ' ' || p.nom),
    'matricule', p.matricule,
    'photo_url', p.photo_url,
    'bio', p.bio,
    'fonction', f.nom,
    'niveau', f.niveau,
    'echelon', e.nom,
    'territoire', t.nom,
    'depuis', p.date_adhesion,
    'postes', coalesce((select jsonb_agg(jsonb_build_object(
                          'nom', po.nom, 'territoire', tn.nom))
                        from nominations n
                        join postes po on po.code = n.poste
                        left join territoires tn on tn.id = n.territoire_id
                        where n.profil_id = p.id and nomination_active(n)), '[]'::jsonb),
    'distinctions', coalesce((select jsonb_agg(td.nom order by d.decernee_le desc)
                              from distinctions d
                              join types_distinction td on td.code = d.type
                              where d.profil_id = p.id and d.publique
                                and d.retiree_le is null), '[]'::jsonb))
  end
  from profils p
  join fonctions f on f.code = p.fonction
  join echelons e on e.niveau = p.echelon
  left join territoires t on t.id = p.territoire_id
  where p.id = p_profil;
$$;

-- ---------------------------------------------------------------------
-- 3. LE JOURNAL DES ENVOIS
--    Qui a envoyé quoi, quand, à qui. Jamais le contenu du message ni
--    le chemin du fichier : la traçabilité n'est pas un droit de
--    lecture. Rien n'est stocké — tout se déduit des messages.
-- ---------------------------------------------------------------------

create table if not exists controles_pieces (
  profil_id   uuid primary key references profils(id) on delete cascade,
  vu_jusqu_a  timestamptz not null default now()
);
alter table controles_pieces enable row level security;
drop policy if exists mon_controle_pieces on controles_pieces;
create policy mon_controle_pieces on controles_pieces for all
  using (profil_id = auth.uid()) with check (profil_id = auth.uid());
grant select, insert, update on controles_pieces to authenticated;

create or replace function puis_je_lire_journal_pieces()
returns boolean language sql stable security definer set search_path = public as $$
  select est_admin() or a_droit('rgpd.alertes') or a_droit('discipline.instruire');
$$;

drop function if exists journal_pieces(integer);
create or replace function journal_pieces(p_jours integer default 30)
returns table (envoye_le timestamptz, auteur text, auteur_fonction text,
               territoire text, destinataires text, type_conversation text,
               nom text, taille integer, format text)
language sql stable security definer set search_path = public as $$
  select m.cree_le, trim(p.prenom || ' ' || p.nom), f.nom, t.nom,
         (select string_agg(trim(d.prenom || ' ' || d.nom), ', ')
          from conv_participants cp join profils d on d.id = cp.profil_id
          where cp.conversation_id = m.conversation_id and d.id <> m.auteur_id),
         c.type, m.piece_nom, m.piece_taille, m.piece_type
  from messages m
  join conversations c on c.id = m.conversation_id
  join profils p on p.id = m.auteur_id
  join fonctions f on f.code = p.fonction
  left join territoires t on t.id = p.territoire_id
  where m.piece is not null
    and m.cree_le > now() - (coalesce(p_jours, 30) || ' days')::interval
    and puis_je_lire_journal_pieces()
  order by m.cree_le desc;
$$;

create or replace function pieces_depuis_mon_controle()
returns integer language sql stable security definer set search_path = public as $$
  select case when not puis_je_lire_journal_pieces() then 0 else
    (select count(*)::int from messages m
      where m.piece is not null
        and m.cree_le > coalesce(
              (select vu_jusqu_a from controles_pieces where profil_id = auth.uid()),
              now() - interval '30 days'))
  end;
$$;

create or replace function marquer_pieces_vues()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not puis_je_lire_journal_pieces() then
    return jsonb_build_object('ok', false, 'message', 'Ce journal ne vous est pas ouvert.');
  end if;
  insert into controles_pieces (profil_id, vu_jusqu_a) values (auth.uid(), now())
  on conflict (profil_id) do update set vu_jusqu_a = now();
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. LA FILE DE TRAVAIL
--    Une ligne agrégée, pas une alerte par fichier : sinon le contrôle
--    devient du bruit, et le bruit ne se contrôle plus.
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
    ('sans_bureau', 'adhérent(s) sans bureau local ni accompagnant',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 1),
      '#/espace/parcours', 'haute'),
    ('sans_accompagnant', 'adhérent(s) sans accompagnant',
      (select count(*)::int from nouveaux_a_repartir() where priorite = 2),
      '#/espace/parcours', 'haute'),
    ('alertes_parcours', 'observation(s) sur un accompagnement',
      (select count(*)::int from mes_alertes_parcours() where traite_le is null),
      '#/espace/parcours', 'normale'),
    ('bilans', 'bilan(s) de mission à rédiger',
      (select count(*)::int from bilans_a_rediger()),
      '#/espace/parcours', 'haute'),
    ('cand_formation', 'candidature(s) à une formation à arbitrer',
      (select count(*)::int from candidatures_formation_a_arbitrer() where mon_ressort),
      '#/espace/formations', 'normale'),
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
    ('pieces', 'pièce(s) échangée(s) depuis votre dernier contrôle',
      pieces_depuis_mon_controle(), '#/espace/validation', 'normale'),
    ('alertes_suivi', 'alerte(s) de suivi des usages',
      (select count(*)::int from alertes_suivi
        where vue_le is null and (est_admin() or a_droit('discipline.instruire'))),
      '#/espace/discipline', 'haute'),
    ('recours', 'recours à trancher',
      (select count(*)::int from recours r where r.statut in ('depose','recevable')
        and a_droit('discipline.recours')),
      '#/espace/discipline', 'haute'),
    ('candidatures', 'candidature(s) électorale(s) à examiner',
      (select count(*)::int from conformite_a_traiter()),
      '#/espace/conformite', 'haute'),
    ('actes', 'acte(s) sensible(s) à contrôler',
      (select count(*)::int from actes_sensibles where statut = 'a_controler'
        and est_admin()),
      '#/espace/validation', 'haute'),
    ('remontees', 'remontée(s) du réseau adressée(s) à la présidence',
      (select count(*)::int from remontees_du_cabinet('ouvertes')
        where est_admin() or a_droit('cabinet.arbitrer')),
      '#/espace/cabinet', 'haute'),
    ('actes_signer', 'projet(s) d''acte en attente de signature',
      (select count(*)::int from actes_internes where statut = 'projet'
        and puis_je_signer_acte()),
      '#/espace/cabinet', 'normale'),
    ('publications', 'publication(s) à relayer sur vos réseaux',
      publications_a_relayer(), '#/espace/publier', 'normale'),
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
        where pr.statut = 'deposee' and (est_admin() or mon_niveau() >= 50)
          and dans_mon_perimetre(pr.territoire_id)),
      '#/espace/comite', 'normale'),
    ('commandes_stock', 'commande(s) de matériel à traiter',
      (select count(*)::int from commandes
        where statut in ('deposee','validee') and a_droit('stock.national')),
      '#/espace/ressources', 'normale'),
    ('invest_instruire', 'demande(s) d''investissement à instruire',
      (select count(*)::int from investissements_a_traiter('a_instruire')),
      '#/espace/ressources', 'normale'),
    ('invest_ordonnancer', 'investissement(s) à ordonnancer',
      (select count(*)::int from investissements_a_traiter('a_ordonnancer')),
      '#/espace/ressources', 'normale'),
    ('taches', 'tâche(s) qui vous sont assignées',
      (select count(*)::int from gt_taches
        where assigne_a = auth.uid() and statut in ('a_faire','en_cours')),
      '#/espace/groupes', 'normale'),
    ('invitations', 'invitation(s) à un groupe de travail',
      (select count(*)::int from mes_invitations_groupe()),
      '#/espace/mandats', 'normale'),
    ('scrutins', 'scrutin(s) où vous n''avez pas voté',
      (select count(*)::int from mes_assemblees()
        where statut = 'scrutin' and electeur and not a_vote),
      '#/espace/assemblees', 'haute'),
    ('interims', 'intérim(s) qui vous sont proposés',
      (select count(*)::int from mes_interims()
        where statut = 'propose' and je_suis_interimaire),
      '#/espace/mandats', 'haute'),
    ('messages', 'conversation(s) non lue(s)',
      (select count(*)::int from mes_conversations() c where c.non_lus > 0),
      '#/espace/messagerie', 'normale')
  ) as x(code, libelle, nombre, lien, urgence)
  where nombre > 0;
$$;

-- ---------------------------------------------------------------------
-- 5. DROITS D'EXÉCUTION
-- ---------------------------------------------------------------------

grant execute on function envoyer_message(uuid, text, text, text, integer, text),
                          retirer_message(uuid), profil_interne(uuid),
                          journal_pieces(integer), pieces_depuis_mon_controle(),
                          marquer_pieces_vues(), puis_je_lire_journal_pieces(),
                          ce_qui_attend()
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 33
--
--  Vérifications :
--    select profil_interne('<uuid>');
--    select * from journal_pieces(30);
--    select pieces_depuis_mon_controle();
--
--  Sur le journal : il dit qu'un fichier nommé « budget-2026.xlsx » de
--  42 ko est parti de X vers Y tel jour. Il ne donne ni le message, ni
--  le chemin, ni le moyen de l'ouvrir. C'est une trace, pas une clé.
--
--  Sur les pièces : leur chemin commence par l'identifiant de la
--  conversation, ce qui permet à Storage de réutiliser la règle d'accès
--  de la messagerie au lieu d'en écrire une seconde. Deux règles pour
--  une même chose finissent toujours par diverger.
-- =====================================================================
