"""FFCE — Génère CARTE.md, la carte des modules d'interface.

Pour router une demande vers le bon fichier, il ne faut pas lire le code :
il faut savoir ce que chaque module contient. Cette carte liste, pour
chaque module, ses composants et la première phrase de leur commentaire.
Elle tient en quelques centaines de lignes.

C'est ce qui permet à l'IA de répondre « envoyez-moi js/finances.js »
sans avoir vu une seule ligne de finances.js.

    python3 carte.py > CARTE.md
"""
import re, glob, os, sys

def phrase(commentaire):
    """La première phrase utile d'un commentaire de bloc."""
    t = re.sub(r'/\*|\*/', ' ', commentaire)
    t = re.sub(r'[-=]{4,}', ' ', t)                    # filets décoratifs
    t = re.sub(r'^\s*\*', ' ', t, flags=re.M)
    t = re.sub(r'\s+', ' ', t).strip()
    t = re.sub(r"^[A-ZÀ-Ÿ' ]{5,}(?=[A-ZÀ-Ÿ][a-zà-ÿ])", '', t)   # titre en capitales
    m = re.split(r'(?<=[.!?])\s', t)
    return (m[0] if m else t)[:190]

def analyser(chemin):
    src = open(chemin, encoding='utf-8').read()
    lignes = src.split('\n')
    entete = ''
    m = re.match(r'\s*/\*(.*?)\*/', src, re.S)
    if m: entete = phrase(m.group(0))

    items, rpc = [], set()
    for i, l in enumerate(lignes):
        d = re.match(r'(?:export )?(?:async )?function ([A-Z]\w+)', l)
        if not d: continue
        # commentaire de bloc juste au-dessus
        j, com = i - 1, []
        while j >= 0 and (lignes[j].strip() == '' or not lignes[j].strip().endswith('*/')):
            if lignes[j].strip() != '': break
            j -= 1
        if j >= 0 and lignes[j].strip().endswith('*/'):
            k = j
            while k >= 0 and '/*' not in lignes[k]: k -= 1
            if k >= 0: com = lignes[k:j+1]
        # portée
        fin = next((x for x in range(i+1, len(lignes))
                    if re.match(r'(?:export )?(?:async )?function |^(?:export )?const [A-Z]',
                                lignes[x])), len(lignes))
        items.append({
            'nom': d.group(1),
            'exporte': l.startswith('export'),
            'lignes': fin - i,
            'quoi': phrase('\n'.join(com)) if com else '',
        })
    rpc = sorted(set(re.findall(r"rpc\('(\w+)'", src)))
    return entete, items, rpc, src.count('\n')

if __name__ == '__main__':
    o = sys.stdout.write
    fichiers = sorted(glob.glob('js/*.js'))
    o("# FFCE — Carte des modules d'interface\n\n")
    o("> Généré par `carte.py`. **Ne pas modifier à la main.** Régénérer "
      "après chaque livraison.\n\n")
    o("> À joindre en début de session avec `SCHEMA.md` et `PASSATION.md`. "
      "Elle permet de désigner le module à modifier **sans lire le code** : "
      "c'est ce qui rend une reprise économe.\n\n")

    total = 0
    resume = []
    for f in fichiers:
        e, items, rpc, n = analyser(f)
        total += n
        resume.append((os.path.basename(f), n, len(items), e))
    o("| Module | Lignes | Composants | Ce qu'il contient |\n|---|---|---|---|\n")
    for nom, n, c, e in resume:
        o("| `js/%s` | %d | %d | %s |\n" % (nom, n, c, e.replace('|', '—')))
    o("\n**Total : %d lignes d'interface.**\n\n---\n\n" % total)

    for f in fichiers:
        e, items, rpc, n = analyser(f)
        nom = os.path.basename(f)
        o("## `js/%s`\n\n" % nom)
        if e: o("%s\n\n" % e)
        o("*%d lignes · %d composants*\n\n" % (n, len(items)))
        if items:
            for it in sorted(items, key=lambda x: -x['lignes']):
                o("- **`%s`**%s — %d lignes%s\n" % (
                    it['nom'],
                    '' if it['exporte'] else ' *(interne)*',
                    it['lignes'],
                    ('  \n  ' + it['quoi']) if it['quoi'] else ''))
            o("\n")
        if rpc:
            o("Fonctions SQL appelées : %s\n\n"
              % ", ".join("`%s`" % x for x in rpc))
