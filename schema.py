"""FFCE — Génère SCHEMA.md, l'abrégé du schéma en vigueur.

Le recueil des migrations pèse 21 000 lignes et croît à chaque lot. On
n'a pourtant besoin, pour écrire correctement, que de la FORME actuelle
du schéma : quelles tables, quelles colonnes, quelles fonctions, quelles
colonnes elles renvoient, quels droits existent.

Ce fichier tient en quelques centaines de lignes et remplace le recueil
dans 95 % des cas. Il se régénère après chaque migration :

    python3 schema.py > SCHEMA.md
"""
import re, glob, os, sys

def dossier_sql():
    """Où sont les migrations. On accepte `sql/SQL/`, `sql/` ou
    `migrations/` : le dépôt d'origine employait l'un, le dépôt actuel
    l'autre, et il serait absurde qu'un script échoue pour cela."""
    for motif in ('sql/SQL/*.sql', 'sql/*.sql', 'migrations/*.sql', '*.sql'):
        trouve = sorted(glob.glob(motif))
        if trouve:
            return trouve
    return []

FS = dossier_sql()
SRC = "\n".join(open(f, encoding='utf-8').read() for f in FS)

def sans_com(s):
    return re.sub(r'--[^\n]*', '', s)

NU = sans_com(SRC)

# ---- tables et colonnes ------------------------------------------------
tables = {}
for m in re.finditer(r'create table if not exists (\w+)\s*\((.*?)\n\);', NU, re.S):
    cols = []
    for l in m.group(2).split('\n'):
        c = re.match(r'\s*([a-z_][a-z0-9_]*)\s+([a-z][\w\[\]() ,]*?)(?:\s+(?:not null|default|references|primary|unique|check)|,|$)', l)
        if c and c.group(1) not in ('primary','unique','check','constraint','foreign'):
            cols.append((c.group(1), c.group(2).strip()))
    tables[m.group(1)] = cols
for m in re.finditer(r'alter table (\w+)\s+add column if not exists (\w+)\s+([a-z][\w\[\]()]*)', NU):
    tables.setdefault(m.group(1), []).append((m.group(2), m.group(3) + ' (ajoutée)'))

# ---- contraintes énumérées en vigueur ----------------------------------
checks = {}
for m in re.finditer(r'(\w+)\s+text\s+not null[^,\n]*check \((\w+) in \(([^)]*)\)\)', NU):
    checks[m.group(2)] = re.findall(r"'([\w]+)'", m.group(3))
for m in re.finditer(r'add constraint (\w+) check \((\w+) in \(([^)]*)\)\)', NU):
    checks[m.group(2)] = re.findall(r"'([\w]+)'", m.group(3))

# ---- fonctions : dernière définition ------------------------------------
fns = {}
for f in FS:
    s = sans_com(open(f, encoding='utf-8').read())
    for m in re.finditer(r'create or replace function (\w+)\s*\((.*?)\)\s*\n?\s*returns\s+(.*?)\s+language\s+(\w+)', s, re.S):
        nom, args, ret, lang = m.groups()
        cols = None
        rt = re.match(r'table\s*\((.*)\)\s*$', ret.strip(), re.S)
        if rt:
            cols = [x.strip() for x in re.split(r',(?![^(]*\))', rt.group(1))]
        fns[nom] = dict(fichier=os.path.basename(f), args=re.sub(r'\s+', ' ', args).strip(),
                        ret=re.sub(r'\s+', ' ', ret)[:60], lang=lang, cols=cols)

# ---- droits, postes, applications, directions ---------------------------
droits = {}
for m in re.finditer(r"insert into droits[^;]+;", NU, re.S):
    for d in re.finditer(r"\('([a-z_]+\.[a-z_]+)',\s*'([^']*)',\s*'([^']*)',\s*(true|false)", m.group(0)):
        droits[d.group(1)] = (d.group(2), d.group(3), d.group(4) == 'true')

apps = {}
for m in re.finditer(r"insert into applications \(([^)]*)\)\s*\nvalues \('(\w+)',\s*'([^']*)',\s*'([^']*)'", NU):
    apps[m.group(2)] = (m.group(3), m.group(4))

# ---- sortie -------------------------------------------------------------
o = sys.stdout.write
o("# FFCE — Abrégé du schéma en vigueur\n\n")
o("> Généré par `schema.py` à partir des %d migrations. **Ne pas modifier "
  "à la main.** Régénérer après chaque migration.\n\n" % len(FS))
o("> Ce fichier remplace le recueil des migrations pour écrire du code. "
  "N'ouvrir le recueil que pour comprendre le *pourquoi* d'une règle.\n\n")
o("**%d tables · %d fonctions · %d droits · %d applications**\n\n"
  % (len(tables), len(fns), len(droits), len(apps)))

o("---\n\n## Tables et colonnes\n\n")
for t in sorted(tables):
    o("**`%s`** — %s\n\n" % (t, ", ".join("`%s`" % c for c, _ in tables[t])))

o("---\n\n## Domaines énumérés en vigueur\n\n")
o("Avant d'insérer une valeur nouvelle, élargir la contrainte "
  "(`drop constraint` puis `add constraint`). Corriger la règle, jamais "
  "rabattre la donnée.\n\n")
for c in sorted(checks):
    o("- `%s` : %s\n" % (c, ", ".join(checks[c])))

o("\n---\n\n## Fonctions SQL\n\n")
o("Une fonction redéfinie plusieurs fois n'apparaît qu'une : la version "
  "en vigueur, avec le fichier où elle se trouve.\n\n")
for n in sorted(fns):
    d = fns[n]
    o("**`%s(%s)`** → `%s` · %s · %s\n" % (n, d['args'], d['ret'], d['lang'], d['fichier']))
    if d['cols']:
        o("  \n  colonnes : %s\n" % ", ".join("`%s`" % c.split()[0] for c in d['cols'] if c.split()))
    o("\n")

o("---\n\n## Droits atomiques\n\n")
for c in sorted(droits):
    n, cat, sens = droits[c]
    o("- `%s` — %s *(%s%s)*\n" % (c, n, cat, ", sensible" if sens else ""))

o("\n---\n\n## Applications\n\n")
for c in sorted(apps):
    o("- `%s` — %s\n" % (c, apps[c][0]))
