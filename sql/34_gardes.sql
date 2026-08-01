-- =====================================================================
--  FFCE — Migration 34 — DEUX ASPÉRITÉS SUPPRIMÉES
--
--  1. Retirer un message effaçait le lien vers la pièce, pas la pièce.
--     Le fichier restait dans Storage. On rend l'effacement possible et
--     l'interface l'exécute au moment du retrait.
--
--  2. Une conversion de texte en `uuid` échoue par une erreur brutale
--     quand la valeur n'a pas la bonne forme. Dans une politique de
--     sécurité, cela transforme un refus propre en panne ; dans une
--     fonction, cela remplace un message clair par un code d'erreur que
--     personne ne comprend. Cinq endroits étaient concernés, dont trois
--     recevant directement une saisie. Ils sont tous gardés par la même
--     fonction, et le contrôle de livraison interdit désormais d'écrire
--     une conversion sans garde.
--
--  Prérequis : 01 à 33.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LA GARDE
--    Renvoie l'identifiant si la forme est bonne, null sinon. Aucune
--    exception levée, donc utilisable dans une politique sans risque de
--    panne. `immutable` : la même chaîne donne toujours le même
--    résultat, PostgreSQL peut mettre le calcul en cache.
-- ---------------------------------------------------------------------

create or replace function uuid_valide(p_texte text)
returns uuid language sql immutable as $$
  select case
    when p_texte ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then p_texte::uuid else null end;
$$;

comment on function uuid_valide(text) is
  'Convertit en uuid ou renvoie null. À employer partout où la valeur convertie vient d''une saisie, d''un chemin de fichier ou d''un jsonb.';

grant execute on function uuid_valide(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. LES PIÈCES JOINTES S'EFFACENT
--    Storage n'est pas accessible depuis PostgreSQL. La base fournit
--    donc le chemin au moment du retrait, et la politique autorise
--    l'auteur ou l'administrateur à effacer — à condition de participer
--    encore à la conversation.
-- ---------------------------------------------------------------------

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
  using (bucket_id = 'pieces'
         and (owner = auth.uid() or est_admin())
         and accede_conversation(uuid_valide((storage.foldername(name))[1])));

-- Le retrait renvoie le chemin : l'interface s'en sert pour effacer le
-- fichier dans la foulée. Si l'effacement échoue, le message est retiré
-- malgré tout — on ne laisse pas un contenu visible faute d'avoir pu
-- nettoyer le fichier.
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

  update messages
     set retire = true, retire_par = auth.uid(),
         piece = null, piece_nom = null, piece_taille = null, piece_type = null
   where id = p_id;

  return jsonb_build_object('ok', true, 'piece', m.piece);
end $$;

-- ---------------------------------------------------------------------
-- 3. LES TROIS AUTRES CONVERSIONS, GARDÉES
--    Corps repris à l'identique des migrations 16 et 17 : seules les
--    conversions changent. Toute autre modification serait une décision
--    prise en passant, et les décisions ne se prennent pas en passant.
-- ---------------------------------------------------------------------

-- Mutation d'un membre : `p_valeur` vient d'un formulaire. Un
-- identifiant mal formé doit donner un refus lisible, pas une erreur
-- 22P02.
create or replace function modifier_membre(p_profil uuid, p_champ text, p_valeur text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refus text; v_avant jsonb; v_libelle text; v_terr uuid;
begin
  if not (est_admin() or a_droit('membres.nommer')) then
    return jsonb_build_object('ok', false, 'message', 'Vous ne pilotez pas le réseau.');
  end if;
  v_refus := motif_refus_action(p_profil);
  if v_refus is not null then
    return jsonb_build_object('ok', false, 'message', v_refus);
  end if;
  if p_champ not in ('fonction','echelon','statut','territoire_id','protege') then
    return jsonb_build_object('ok', false, 'message', 'Champ non modifiable ici.');
  end if;

  select jsonb_build_object('fonction', fonction, 'echelon', echelon,
                            'statut', statut, 'territoire_id', territoire_id,
                            'protege', protege)
    into v_avant from profils where id = p_profil;

  -- Nul ne hisse quelqu'un à son propre niveau ou au-dessus.
  if p_champ = 'fonction' then
    if (select niveau from fonctions where code = p_valeur) >= mon_poids()
       and not est_admin() then
      return jsonb_build_object('ok', false,
        'message', 'Vous ne pouvez pas conférer une fonction égale ou supérieure à la vôtre.');
    end if;
    update profils set fonction = p_valeur where id = p_profil;
    v_libelle := 'Fonction portée à « ' ||
                 (select nom from fonctions where code = p_valeur) || ' »';
  elsif p_champ = 'echelon' then
    update profils set echelon = p_valeur::int where id = p_profil;
    v_libelle := 'Échelon porté à ' || p_valeur;
  elsif p_champ = 'statut' then
    update profils set statut = p_valeur where id = p_profil;
    v_libelle := 'Statut du compte : ' || replace(p_valeur,'_',' ');
  elsif p_champ = 'territoire_id' then
    v_terr := uuid_valide(nullif(p_valeur,''));
    if nullif(p_valeur,'') is not null and v_terr is null then
      return jsonb_build_object('ok', false, 'message', 'Territoire inconnu.');
    end if;
    update profils set territoire_id = v_terr where id = p_profil;
    v_libelle := 'Mutation vers ' ||
                 coalesce((select nom from territoires where id = v_terr),
                          'aucun territoire');
  elsif p_champ = 'protege' then
    update profils set protege = (p_valeur = 'true') where id = p_profil;
    v_libelle := case when p_valeur = 'true' then 'Protection renforcée activée'
                      else 'Protection renforcée levée' end;
  end if;

  perform inscrire_acte(p_profil, 'profil', v_libelle, v_avant,
                        jsonb_build_object(p_champ, p_valeur));
  return jsonb_build_object('ok', true);
end $$;

-- Le scrutin : `p_choix` vient du navigateur. Un bulletin dont la
-- candidature n'existe pas ou n'appartient pas à cette assemblée n'est
-- pas un incident technique, c'est un bulletin blanc. Le faire échouer
-- laisserait l'électeur émargé sans bulletin — c'est-à-dire privé de
-- son vote sans possibilité de recommencer.
create or replace function voter(p_assemblee uuid, p_choix jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a assemblees; v_poste text; v_cand text; v_id uuid;
begin
  select * into a from assemblees where id = p_assemblee;
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Assemblée introuvable.');
  end if;
  if a.statut <> 'scrutin' then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin n''est pas ouvert.');
  end if;
  if a.cloture_scrutin is not null and a.cloture_scrutin < now() then
    return jsonb_build_object('ok', false, 'message', 'Le scrutin est clos.');
  end if;
  if not suis_je_electeur(p_assemblee) then
    return jsonb_build_object('ok', false,
      'message', 'Vous n''appartenez pas au corps électoral.');
  end if;
  if exists (select 1 from votes where assemblee_id = p_assemblee
             and electeur_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'Vous avez déjà voté.');
  end if;

  -- L'émargement d'abord : il engage l'électeur.
  insert into votes (assemblee_id, electeur_id) values (p_assemblee, auth.uid());

  -- Puis les bulletins, sans aucun lien avec lui.
  for v_poste, v_cand in select key, value #>> '{}' from jsonb_each(p_choix) loop
    v_id := case when v_cand = 'blanc' then null else uuid_valide(v_cand) end;
    if v_id is not null and not exists (
         select 1 from candidatures c
          where c.id = v_id and c.assemblee_id = p_assemblee and c.poste = v_poste) then
      v_id := null;
    end if;
    insert into bulletins (assemblee_id, poste, candidature_id, blanc)
    values (p_assemblee, v_poste, v_id, v_id is null);
  end loop;

  return jsonb_build_object('ok', true);
end $$;

-- Le contrôle d'un acte sensible relit un jsonb que la base a écrit
-- elle-même — mais une migration future pourrait en changer la forme.
-- La garde coûte moins cher qu'un rétablissement impossible.
create or replace function controler_acte(p_acte uuid, p_confirmer boolean,
                                          p_observation text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a actes_sensibles;
begin
  if not est_admin() then
    return jsonb_build_object('ok', false, 'message', 'Réservé à l''administrateur.');
  end if;
  select * into a from actes_sensibles where id = p_acte and statut = 'a_controler';
  if a is null then
    return jsonb_build_object('ok', false, 'message', 'Acte déjà contrôlé.');
  end if;

  if not p_confirmer then
    if not a.reversible then
      return jsonb_build_object('ok', false,
        'message', 'Cet acte n''est pas réversible automatiquement. Corrigez-le à la main.');
    end if;

    -- Remise en l'état, selon la nature de l'acte.
    if a.nature = 'profil' then
      update profils set
        fonction      = coalesce(a.avant->>'fonction', fonction),
        echelon       = coalesce((a.avant->>'echelon')::int, echelon),
        statut        = coalesce(a.avant->>'statut', statut),
        territoire_id = coalesce(uuid_valide(a.avant->>'territoire_id'), territoire_id),
        protege       = coalesce((a.avant->>'protege')::boolean, protege)
      where id = a.cible_id;
    elsif a.nature = 'nomination' then
      update nominations set revoque_le = now(), revoque_par = auth.uid(),
             motif_revocation = 'Annulée au contrôle'
       where id = uuid_valide(a.apres->>'nomination_id') and revoque_le is null;
    elsif a.nature = 'revocation' then
      update nominations set revoque_le = null, revoque_par = null, motif_revocation = null
       where id = uuid_valide(a.avant->>'nomination_id');
    elsif a.nature = 'acces' then
      update acces_applications set statut = coalesce(a.avant->>'statut','revoque'),
             revoque_le = case when a.avant->>'statut' = 'accorde' then null else now() end
       where profil_id = a.cible_id and application = a.apres->>'application';
    end if;
  end if;

  update actes_sensibles
     set statut = case when p_confirmer then 'confirme' else 'annule' end,
         controle_par = auth.uid(), controle_le = now(),
         observation = nullif(trim(p_observation),'')
   where id = p_acte;

  return jsonb_build_object('ok', true);
end $$;

grant execute on function retirer_message(uuid),
                          modifier_membre(uuid, text, text),
                          voter(uuid, jsonb),
                          controler_acte(uuid, boolean, text)
  to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 34
--
--  Vérifications :
--    select uuid_valide('pas-un-uuid');            -- null, sans erreur
--    select uuid_valide(gen_random_uuid()::text);  -- l'identifiant
--
--  Onzième famille d'erreur : une conversion `::uuid` appliquée à une
--  valeur venue d'une saisie, d'un chemin de fichier ou d'un jsonb lève
--  une erreur au lieu de refuser. Dans une politique RLS, elle change
--  un refus en panne. Le contrôle recense les conversions et exige une
--  garde — `uuid_valide`, un test de forme, ou une valeur produite par
--  la base dans la même transaction.
--
--  Douzième famille : une fonction redéfinie sous un nom qui n'existait
--  pas. `create or replace` ne proteste pas : il crée une seconde
--  fonction, jamais appelée, pendant que l'originale reste bugguée. Le
--  contrôle liste les fonctions redéfinies par une migration et
--  vérifie qu'elles existent déjà — toute nouveauté doit être voulue.
-- =====================================================================
