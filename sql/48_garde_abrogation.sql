-- =====================================================================
--  FFCE — Migration 48 — UNE CONVERSION OUBLIÉE
--
--  `abroger_acte` convertit en `uuid` une valeur relue d'un jsonb, sans
--  garde. C'est la onzième famille d'erreur du dossier de passation :
--  une conversion qui échoue lève une exception au lieu de refuser
--  proprement.
--
--  Le risque est ici faible — la valeur vient de `prendre_acte`, appelée
--  deux lignes plus haut dans la même transaction. Mais la règle ne
--  souffre pas d'exception : dès qu'on tolère un cast non gardé « parce
--  qu'on sait d'où il vient », on cesse de contrôler les autres. Et le
--  jour où la forme du jsonb change, l'abrogation d'un acte devient
--  impossible sans qu'on comprenne pourquoi.
--
--  Le corps est repris à l'identique de la migration 32 : seules les
--  deux conversions changent.
--
--  Prérequis : 01 à 47.
-- =====================================================================

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
    if not (puis_je_prendre_acte(a.territoire_id) and
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

  -- Les deux conversions gardées : `uuid_valide` renvoie null plutôt
  -- que de lever une exception si la forme n'est pas celle attendue.
  update actes_internes
     set statut = 'abroge', abroge_par = uuid_valide(v_new->>'id'),
         motif_abrogation = trim(p_motif)
   where id = p_id;
  perform signer_acte(uuid_valide(v_new->>'id'));
  return jsonb_build_object('ok', true, 'acte', v_new->>'id');
end $$;

grant execute on function abroger_acte(uuid, text) to authenticated;

-- =====================================================================
--  FIN DE LA MIGRATION 48
--
--  Vérification :
--    select prosrc like '%uuid_valide%' from pg_proc where proname = 'abroger_acte';
--    -- doit renvoyer true
-- =====================================================================
