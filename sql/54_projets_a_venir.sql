-- =====================================================================
-- 54 — Projets à venir, visibles largement
--
-- POURQUOI : projets_a_soutenir() existe déjà mais sert le contexte du
-- financement (40_enveloppes.sql) — pas la bonne audience ni, sans
-- doute, le bon filtre pour un adhérent qui veut simplement voir ce
-- qui se passe autour de lui. Plutôt que de réutiliser une fonction
-- taillée pour un autre usage, dont je ne connais pas le corps, j'en
-- crée une nouvelle, en lecture seule, sur le même principe que
-- mes_evenements().
--
-- SÛRETÉ : pas de security definer. La fonction s'appuie sur les
-- politiques de sécurité déjà en place sur la table projets — elle ne
-- voit que ce que l'appelant voit déjà.
-- =====================================================================

create or replace function projets_a_venir()
returns table(
  id uuid, titre text, objet text, lieu text, debut date, fin date,
  statut text, avancement text, territoire_nom text
)
language sql
stable
as $$
  select pr.id, pr.titre, pr.objet, pr.lieu, pr.debut, pr.fin,
    pr.statut, pr.avancement, t.nom as territoire_nom
  from projets pr
  left join territoires t on t.id = pr.territoire_id
  where pr.statut not in ('termine','abandonne')
    and (pr.fin is null or pr.fin >= current_date)
  order by pr.debut nulls last
$$;

-- VÉRIFICATION à faire après dépôt : un membre sans droit particulier
-- doit voir les mêmes projets qu'aujourd'hui dans ProjetsComite, ni
-- plus ni moins — si la liste est plus large ici, c'est que la table
-- projets n'a pas de politique de sécurité par territoire, et il faut
-- me le dire avant d'aller plus loin.
