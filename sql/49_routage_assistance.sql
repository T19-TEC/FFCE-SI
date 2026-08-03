-- =====================================================================
-- 49 — Routage automatique de « un souci, une idée »
--
-- POURQUOI : jusqu'ici, un ticket ouvert par un adhérent n'avait pas de
-- destinataire choisi à la création — assigne_a restait vide, réglé
-- ensuite à la main par un administrateur via traiter_ticket. Le réseau
-- veut désormais qu'un problème technique parte directement vers
-- l'assistance technique, qu'une idée parte vers la direction générale,
-- et que le reste (donnée erronée, question) remonte à la présidence,
-- sans passer par un tri manuel.
--
-- CHOIX : un déclencheur (trigger), pas une réécriture de ouvrir_ticket.
-- Cette fonction n'a jamais été vue dans son corps réel — seule sa
-- signature figure dans SCHEMA.md, qui est un abrégé, pas le code
-- source. La réécrire à l'aveugle (create or replace) risquerait
-- d'effacer en silence une logique existante (numérotation de la
-- référence, contrôles, etc. — famille d'erreur n° 3). Un trigger
-- BEFORE INSERT est additif : il complète la ligne avant son
-- écriture, sans toucher à la fonction existante ni à ce qu'elle fait.
--
-- Le déclencheur ne s'applique que si assigne_a est encore vide : si
-- un jour ouvrir_ticket ou un autre appelant choisit lui-même un
-- destinataire, ce choix n'est jamais écrasé.
--
-- Si le poste visé n'a personne en fonction, le ticket reste sans
-- destinataire — exactement le comportement d'aujourd'hui. Rien ne se
-- perd, rien n'échoue.
-- =====================================================================

create or replace function router_ticket_destinataire()
returns trigger
language plpgsql
as $$
declare
  v_poste text;
begin
  if new.assigne_a is not null then
    return new;
  end if;

  v_poste := case new.nature
    when 'probleme'     then 'assistance_technique'
    when 'amelioration' then 'directeur_general'
    else 'president_federation'
  end;

  select n.profil_id into new.assigne_a
  from nominations n
  where n.poste = v_poste
    and n.revoque_le is null
    and (n.fin is null or n.fin > now())
  order by n.cree_le desc
  limit 1;

  return new;
end;
$$;

drop trigger if exists tr_router_ticket_destinataire on tickets;

create trigger tr_router_ticket_destinataire
before insert on tickets
for each row
execute function router_ticket_destinataire();

-- VÉRIFICATIONS à faire après dépôt :
-- - le poste 'assistance_technique' doit exister (postes.code) et avoir
--   un titulaire (nomination active) pour que le routage produise un
--   effet visible ; sinon les tickets « problème » restent non assignés
--   comme aujourd'hui.
-- - le poste 'directeur_general' est confirmé comme existant par
--   l'utilisateur ; je n'ai pas pu vérifier son code exact dans
--   SCHEMA.md (qui ne liste pas les données de la table postes, "postes
--   à pourvoir" en § 9 de PASSATION.md ne mentionne que
--   president_federation, affaires_publiques, evenementiel).
--
-- PIÈGE LAISSÉ : si le code réel du poste DG n'est pas exactement
-- 'directeur_general', le routage vers la direction générale échouera
-- en silence (aucun titulaire trouvé => ticket non assigné). Aucune
-- erreur ne remontera. À vérifier au premier ticket « amélioration ».
