"""Contrôles de livraison FFCE — les douze familles."""
import re, sys, glob

FS = sorted(glob.glob('sql/SQL/*.sql'))
SRC = "\n".join(open(f, encoding='utf-8').read() for f in FS)

def objets():
    t = {}
    for m in re.finditer(r'create table if not exists (\w+)\s*\((.*?)\n\);', SRC, re.S):
        cols = set()
        for l in m.group(2).split('\n'):
            c = re.match(r'\s*([a-z_][a-z0-9_]*)\s', l)
            if c and c.group(1) not in ('primary','unique','check','constraint','foreign'):
                cols.add(c.group(1))
        t[m.group(1)] = cols
    for m in re.finditer(r'alter table (\w+)\s+add column if not exists (\w+)', SRC):
        t.setdefault(m.group(1), set()).add(m.group(2))
    for m in re.finditer(r'create (?:or replace )?view (\w+)', SRC):
        t.setdefault(m.group(1), set())
    f = set(re.findall(r'create (?:or replace )?function ([a-z_0-9]+)', SRC))
    return t, f

TABLES, FONCTIONS = objets()
# Les colonnes d'une vue sont celles de son select : on ne les déclare
# pas, donc on ne peut pas les contrôler. On les écarte plutôt que de
# signaler des erreurs qui n'en sont pas.
VUES = set(re.findall(r'create (?:or replace )?view (\w+)', SRC))
BRUIT = {'on','using','old','new','storage','now','age','coalesce','current_date','of',
 'select','case','exists','table','function','only','lateral','values','public','set',
 'greatest','string_agg','jsonb_build_array','trim','count','buckets','objects','pg_proc',
 'regexp_replace','jsonb_each','jsonb_array_elements_text','jsonb_array_elements',
 'unnest','generate_series','p_territoire','information_schema'}

def sans_commentaires(s):
    """Les contrôles portent sur le code, pas sur ce qu'on en dit."""
    return re.sub(r'--[^\n]*', '', s)

def definitions_en_vigueur():
    """La dernière définition d'une fonction est la seule qui compte :
    une migration ultérieure remplace la précédente."""
    vig = {}
    for f in FS:
        s = sans_commentaires(open(f, encoding='utf-8').read())
        for m in re.finditer(r'create or replace function (\w+)\s*\((.*?)\)\s*returns(.*?)as \$\$(.*?)\$\$\s*;', s, re.S):
            vig[m.group(1)] = (f.split('/')[-1], m.group(4))
    return vig

def js_du_html(path='index.html'):
    h = open(path, encoding='utf-8').read()
    return re.search(r'<script type="module">(.*)</script>', h, re.S).group(1), h

def ctrl_1_2_3(js):
    a = set(re.findall(r'<\$\{(\w+)\}', js))
    d = (set(re.findall(r'^function (\w+)', js, re.M))
         | set(re.findall(r'^const (\w+)\s*=\s*\(', js, re.M)))
    yield "1. Composants appelés non définis", sorted(a - d)
    rpc = set(re.findall(r"(?:rpc|appel)\('(\w+)'", js))
    yield "2. Fonctions SQL absentes", [f for f in sorted(rpc) if ('function '+f+'(') not in SRC]
    noms = re.findall(r'^function (\w+)', js, re.M) + re.findall(r'^const (\w+)\s*=', js, re.M)
    yield "3. Définitions en double", [n for n in sorted(set(noms)) if noms.count(n) > 1]

    # 16 — composant défini mais jamais appelé. C'est le symptôme d'une
    # livraison à moitié appliquée : le composant existe, la page ne le
    # montre pas, et rien ne signale l'anomalie. Les composants racines
    # (montés par le routeur) sont exclus par la liste ci-dessous.
    RACINES = {'App','Site','Espace','Entete','Pied','Flanc','Accueil'}
    orphelins = sorted(d - a - RACINES - set(re.findall(r'html`<\$\{(\w+)', js)))
    # Un composant nommé dans le routeur est monté, même sans balise htm.
    monte = set(re.findall(r'\$\{(\w+)\}\s', js)) | set(re.findall(r'<\$\{(\w+)\}', js))
    yield "16. Composants définis mais jamais montés", [
        n for n in orphelins if n not in monte and n[0].isupper()]

def ctrl_6():
    ko = []
    for f in FS:
        for m in re.finditer(r'from\s+\w+\s+\w+\s*,\s*\w+[\s\S]{0,40}?\bjoin\b',
                             open(f, encoding='utf-8').read()):
            ko.append(f.split('/')[-1] + ' : ' + re.sub(r'\s+',' ',m.group(0))[:60])
    yield "6. Jointures mêlées", ko

def ctrl_4_5():
    """4 — une fonction `returns table` redéfinie exige un `drop` préalable
    si ses colonnes changent ; on signale toute redéfinition sans drop,
    à relire.
    5 — une table ou une fonction lue avant sa création dans le MÊME
    fichier : PostgreSQL résout le corps d'une fonction `language sql`
    au moment du CREATE. C'est ce qui a manqué à la migration 38."""
    ko4, ko5 = [], []
    for f in FS:
        brut = open(f, encoding='utf-8').read()
        s = sans_commentaires(brut)
        nom_f = f.split('/')[-1]

        # 4 — cf. plus bas : le contrôle 4 se fait globalement, en
        # comparant chaque définition à celle qui la précède.
        # 5 — position de la création par rapport à la première lecture
        crees = {}
        for m in re.finditer(r'create table if not exists (\w+)', s):
            crees.setdefault(m.group(1), m.start())
        for m in re.finditer(r'create (?:or replace )?function ([a-z_0-9]+)', s):
            crees.setdefault(m.group(1), m.start())
        for obj, pos in crees.items():
            for m in re.finditer(r'\b(?:from|join|insert into|update|delete from)\s+'
                                 + obj + r'\b', s):
                if m.start() < pos:
                    ko5.append(f"{nom_f} : {obj} lu ligne "
                               f"{s[:m.start()].count(chr(10))+1}, créé ligne "
                               f"{s[:pos].count(chr(10))+1}")
                    break
    # Chaque fonction `returns table` est comparée à sa définition
    # immédiatement précédente : c'est le seul enchaînement que
    # PostgreSQL exécute réellement.
    defs = {}
    for f in FS:
        s = sans_commentaires(open(f, encoding='utf-8').read())
        drops = set(re.findall(r'drop function if exists (\w+)', s))
        for m in re.finditer(r'create or replace function (\w+)\s*\([^)]*\)\s*'
                             r'returns table\s*\((.*?)\)\s*language', s, re.S):
            n = m.group(1)
            cols = re.sub(r'\s+', ' ', m.group(2)).strip()
            av = defs.get(n)
            if av and av[1] != cols and n not in drops:
                ko4.append(f"{f.split('/')[-1]} : {n} — colonnes changées depuis "
                           f"{av[0]}, `drop function` requis")
            defs[n] = (f.split('/')[-1], cols)
    yield "4. Redéfinitions `returns table` sans drop", sorted(set(ko4))
    yield "5. Objet lu avant sa création dans le même fichier", sorted(set(ko5))

def ctrl_9():
    defs = {}
    for f in FS:
        s = open(f, encoding='utf-8').read()
        for m in re.finditer(r'create or replace function (\w+)\s*\((.*?)\)\s*returns(.*?)as \$\$(.*?)\$\$\s*;', s, re.S):
            n, e, c = m.group(1), m.group(3), m.group(4)
            defs[n] = ('stable' if re.search(r'\b(stable|immutable)\b', e) else 'volatile',
                       bool(re.search(r'(insert\s+into|update\s+[a-z_]+\b|delete\s+from)', c, re.I)), c)
    for n in ('consulter_profil','fiche_membre','nouveaux_a_accueillir_maj'):
        if n in defs: defs[n] = ('volatile',) + defs[n][1:]
    def ecrit(n, vus=None):
        vus = vus or set()
        if n in vus or n not in defs: return False
        vus.add(n); v, e, c = defs[n]
        return e or any(ecrit(a, vus) for a in defs if a != n and re.search(r'\b'+a+r'\s*\(', c))
    yield "9. Non volatiles qui écrivent", [n for n in sorted(defs)
                                            if defs[n][0] != 'volatile' and ecrit(n)]

def ctrl_10():
    ko = []
    for f in FS:
        s = open(f, encoding='utf-8').read()
        # `extract(year from c.cree_le)` n'est pas une clause FROM :
        # sans cette précaution le contrôle signale l'alias comme table.
        s = re.sub(r'extract\s*\([^)]*\)', 'extract()', s, flags=re.I)
        # `is distinct from x` n'est pas une clause FROM non plus.
        s = re.sub(r'is\s+(?:not\s+)?distinct\s+from\s+\S+', 'is_distinct', s, flags=re.I)
        loc = set(re.findall(r'\b([a-z_][a-z0-9_]*)\s+as\s*\(', s))
        for c in set(re.findall(r'(?:from|join|update|insert into|delete from)\s+([a-z_][a-z0-9_]*)', s)):
            if c not in BRUIT and c not in loc and c not in TABLES and c not in FONCTIONS:
                ko.append(f.split('/')[-1] + ' : ' + c)
    yield "10. Objets cités inexistants", sorted(set(ko))

def ctrl_11():
    """Conversion vers uuid sans garde, dans le code en vigueur.

    Deux sources : le corps des fonctions telles qu'elles existent après
    la dernière migration, et les politiques de sécurité — où une
    conversion qui échoue transforme un refus en panne."""
    ko = []
    for nom, (fichier, corps) in definitions_en_vigueur().items():
        if nom == 'uuid_valide':      # la garde elle-même, protégée par sa regex
            continue
        for m in re.finditer(r'([^\s(,]+)::uuid', corps):
            v = m.group(1)
            if v.startswith(("'", 'gen_random', 'auth.uid()')): continue
            ko.append(f"{fichier} · fonction {nom} : {v}::uuid")

    # Les politiques ne sont pas des fonctions : on les lit à part, et
    # seule la dernière version de chaque politique compte.
    pol = {}
    for f in FS:
        s = sans_commentaires(open(f, encoding='utf-8').read())
        for m in re.finditer(r'create policy (\w+) on ([\w.]+)(.*?);', s, re.S):
            pol[(m.group(1), m.group(2))] = (f.split('/')[-1], m.group(3))
    for (nom, tbl), (fichier, corps) in pol.items():
        for m in re.finditer(r'([^\s(,]+)::uuid', corps):
            if m.group(1).startswith(("'", 'auth.uid()')): continue
            ko.append(f"{fichier} · politique {nom} : {m.group(1)}::uuid")
    yield "11. Conversions ::uuid sans garde", sorted(ko)

def ctrl_13():
    """Colonne citée sous la forme alias.colonne, absente de la table à
    laquelle l'alias renvoie. Trois erreurs déjà commises : `maj_le` pour
    `faite_le`, `attribue_le` pour `decernee_le`, `titre` pour `nom`.

    La portée d'un alias est l'instruction, pas le fichier : on découpe
    donc chaque migration en corps de fonction et en instructions
    isolées. Un alias qui désigne ailleurs une CTE ou une fonction
    renvoyant une table est écarté — leurs colonnes ne sont pas
    déclarées, les contrôler produirait du bruit, et le bruit ne se
    contrôle plus."""
    MOTS = {'on','as','where','and','set','using','join','left','right','group',
            'order','cross','lateral','inner','outer','full','select','into','values'}
    ko = []
    for f in FS:
        s = sans_commentaires(open(f, encoding='utf-8').read())
        s = re.sub(r"'[^']*'", "''", s)          # une chaîne n'est pas du code
        for chunk in re.split(r'\$\$;|;\s*\n', s):
            # Alias qui désignent autre chose qu'une table : à écarter.
            opaques = set(re.findall(r'\b(?:from|join)\s+[a-z_][a-z0-9_]*\s*\([^)]*\)\s+(?:as\s+)?([a-z][a-z0-9_]{0,4})\b', chunk))
            opaques |= set(re.findall(r'\b([a-z_][a-z0-9_]*)\s+as\s*\(', chunk))
            liens = {}
            for m in re.finditer(r'\b(?:from|join)\s+([a-z_][a-z0-9_]*)\s+(?:as\s+)?([a-z][a-z0-9_]{0,4})\b', chunk):
                tbl, alias = m.group(1), m.group(2)
                if tbl in TABLES and tbl not in VUES and alias not in MOTS:
                    liens.setdefault(alias, set()).add(tbl)
            for m in re.finditer(r'\b([a-z][a-z0-9_]{0,4})\.([a-z_][a-z0-9_]+)\b', chunk):
                alias, col = m.group(1), m.group(2)
                if alias not in liens or alias in opaques: continue
                if any(col in TABLES[t] for t in liens[alias]): continue
                ko.append(f"{f.split('/')[-1]} : {alias}.{col} "
                          f"(alias de {', '.join(sorted(liens[alias]))})")
    yield "13. Colonnes absentes de la table visée", sorted(set(ko))

def colonnes_des_fonctions():
    """Les colonnes déclarées par chaque fonction `returns table`, dans
    sa définition en vigueur."""
    cols = {}
    for f in FS:
        src = sans_commentaires(open(f, encoding='utf-8').read())
        for m in re.finditer(r'create or replace function (\w+)\s*\([^)]*\)\s*'
                             r'returns table\s*\((.*?)\)\s*language', src, re.S):
            noms = set()
            for c in re.split(r',(?![^(]*\))', m.group(2)):
                x = re.match(r'\s*([a-z_][a-z0-9_]*)\s', c)
                if x: noms.add(x.group(1))
            cols[m.group(1)] = noms
    return cols

COLS_FN = colonnes_des_fonctions()

def ctrl_15():
    """Colonne citée sur le résultat d'une fonction `returns table`, mais
    absente de ses colonnes déclarées. Le contrôle 13 écarte ces alias
    parce qu'ils ne renvoient pas à une table ; ils sont pourtant tout
    aussi vérifiables, et l'erreur y est aussi facile — `date_assemblee`
    au lieu de `date_tenue`."""
    MOTS = {'on','as','where','and','set','using','join','left','right','group',
            'order','cross','lateral','inner','outer','full','select','into','values'}
    ko = []
    for f in FS:
        src = sans_commentaires(open(f, encoding='utf-8').read())
        src = re.sub(r"'[^']*'", "''", src)
        for chunk in re.split(r'\$\$;|;\s*\n', src):
            liens, aussi = {}, {}
            for m in re.finditer(r'\b(?:from|join)\s+([a-z_][a-z0-9_]*)\s*\([^)]*\)\s+'
                                 r'(?:as\s+)?([a-z][a-z0-9_]{0,4})\b', chunk):
                fn, alias = m.group(1), m.group(2)
                if fn in COLS_FN and alias not in MOTS:
                    liens.setdefault(alias, set()).add(fn)
            # Un même alias peut désigner une table ailleurs dans la même
            # fonction — `m` pour `missions_ouvertes()` ici, pour `modules`
            # là. On ne signale que si la colonne n'existe nulle part.
            for m in re.finditer(r'\b(?:from|join)\s+([a-z_][a-z0-9_]*)\s+'
                                 r'(?:as\s+)?([a-z][a-z0-9_]{0,4})\b', chunk):
                tbl, alias = m.group(1), m.group(2)
                if tbl in TABLES and alias not in MOTS:
                    aussi.setdefault(alias, set()).update(TABLES[tbl])
            for m in re.finditer(r'\b([a-z][a-z0-9_]{0,4})\.([a-z_][a-z0-9_]+)\b', chunk):
                alias, col = m.group(1), m.group(2)
                if alias not in liens: continue
                if any(col in COLS_FN[fn] for fn in liens[alias]): continue
                if col in aussi.get(alias, set()): continue
                ko.append(f"{f.split('/')[-1]} : {alias}.{col} "
                          f"(résultat de {', '.join(sorted(liens[alias]))})")
    yield "15. Colonnes absentes du résultat d'une fonction", sorted(set(ko))

def ctrl_14():
    """Droit invoqué par `a_droit()` mais jamais déclaré dans la table
    `droits`. Il renvoie alors toujours faux : la fonction paraît
    fonctionner, mais refuse tout le monde en silence."""
    declares = set()
    for m in re.finditer(r"insert into droits[^;]+;", SRC, re.S):
        declares |= set(re.findall(r"\('([a-z_]+\.[a-z_]+)'", m.group(0)))
    cites = set(re.findall(r"a_droit\('([a-z_.]+)'\)", SRC))
    yield "14. Droits invoqués mais non déclarés", sorted(cites - declares)

def ctrl_12(nouvelles):
    """Fonction redéfinie sous un nom qui n'existait pas ailleurs."""
    anciens = "\n".join(open(f, encoding='utf-8').read() for f in FS
                        if f.split('/')[-1] not in nouvelles)
    ko = []
    for n in nouvelles:
        s = open('sql/SQL/'+n, encoding='utf-8').read()
        for fn in set(re.findall(r'create or replace function (\w+)', s)):
            if ('function '+fn+'(') not in anciens:
                ko.append(n + ' : ' + fn + ' (nouvelle — à confirmer)')
    yield "12. Fonctions créées, non redéfinies", sorted(ko)

if __name__ == '__main__':
    nouvelles = sys.argv[1:]
    js, h = js_du_html()
    flux = list(ctrl_1_2_3(js)) + list(ctrl_4_5()) + list(ctrl_6()) + list(ctrl_9()) \
         + list(ctrl_10()) + list(ctrl_11()) + list(ctrl_13()) + list(ctrl_15()) + list(ctrl_14()) \
         + list(ctrl_12(nouvelles))
    dur = 0
    for titre, ko in flux:
        if ko:
            print(f"{titre} :")
            for x in ko: print("   ", x)
            if not titre.startswith('12'): dur += len(ko)
        else:
            print(f"{titre} : aucun")
    print(f"\n{len(TABLES)} tables/vues, {len(FONCTIONS)} fonctions, "
          f"{h.count(chr(10))} lignes d'index.html")
    print("ANOMALIES BLOQUANTES :", dur)
