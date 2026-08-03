-- =====================================================================
--  FFCE — Migration 44 — POUVOIRS ET CLÉS DE DÉPOUILLEMENT
--
--  Cette migration n'a pas été écrite dans la série principale. Elle est
--  conservée parce que le dépôt doit refléter la base : ses deux tables
--  existent en production et servent toujours.
--
--  Ses CINQ FONCTIONS D'ORIGINE ONT ÉTÉ RETIRÉES DE CE FICHIER, et
--  supprimées en base par la migration 45. Elles étaient inutilisables
--  ou dangereuses :
--
--    · `scanner_emargement_qr` lisait une table `jetons_carte` qui
--      n'existe pas — le jeton est une colonne de `profils` — et
--      écrivait dans une colonne `mode_presence` inexistante. Elle
--      échouait à chaque appel, et faisait doublon avec
--      `emarger_par_carte`, livrée en migration 43.
--
--    · `mes_pouvoirs_ag` était `security definer` sans aucun contrôle
--      d'accès : n'importe quel membre pouvait lister qui avait donné
--      pouvoir à qui, sur n'importe quelle assemblée.
--
--    · `signer_cles_depouillement` n'exigeait aucune habilitation, et
--      rien ne l'exigeait en retour : la double clé était décorative.
--
--    · `donner_pouvoir` ne vérifiait ni que le mandant est électeur, ni
--      que le mandataire l'est, et figeait le plafond dans son corps.
--
--    · Les politiques de lecture s'appuyaient sur
--      `puis_je_lire_journal_pieces()`, qui gouverne les pièces jointes
--      de la messagerie — sans rapport avec le sujet.
--
--  Les versions correctes sont dans la migration 45. Les laisser ici
--  ferait croire qu'une table `jetons_carte` existe, et le prochain qui
--  écrirait du code s'y fierait.
--
--  À EXÉCUTER TOUJOURS AVANT LA 45. Ré-exécutable sans dommage.
-- =====================================================================

create table if not exists pouvoirs_ag (
  id            uuid primary key default gen_random_uuid(),
  assemblee_id  uuid not null references assemblees(id) on delete cascade,
  mandant_id    uuid not null references profils(id) on delete cascade,
  mandataire_id uuid not null references profils(id) on delete cascade,
  statut        text not null default 'valide'
                  check (statut in ('propose', 'valide', 'annule', 'refuse')),
  motif         text,
  cree_le       timestamptz not null default now(),
  unique (assemblee_id, mandant_id)
);
alter table pouvoirs_ag enable row level security;

create table if not exists cles_depouillement (
  id           uuid primary key default gen_random_uuid(),
  assemblee_id uuid not null references assemblees(id) on delete cascade,
  profil_id    uuid not null references profils(id) on delete cascade,
  signe_le     timestamptz not null default now(),
  unique (assemblee_id, profil_id)
);
alter table cles_depouillement enable row level security;

-- Les politiques de lecture et les fonctions sont posées par la 45.

-- =====================================================================
--  FIN DE LA MIGRATION 44
-- =====================================================================
