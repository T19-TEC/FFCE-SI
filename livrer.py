"""FFCE — Une seule commande avant chaque livraison.

    python3 livrer.py 48_ma_migration.sql

Régénère les deux abrégés, passe les dix-huit contrôles, charge
réellement les modules, et dit si l'on peut déployer.
"""
import subprocess, sys, os

def run(cmd, sortie=None):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if sortie and r.returncode == 0:
        open(sortie, 'w', encoding='utf-8').write(r.stdout)
    return r

print("· Abrégé du schéma …", end=' ')
r = run('python3 schema.py', 'SCHEMA.md')
print("SCHEMA.md régénéré" if r.returncode == 0 else "ÉCHEC\n" + r.stderr)

print("· Carte des modules …", end=' ')
r = run('python3 carte.py', 'CARTE.md')
print("CARTE.md régénéré" if r.returncode == 0 else "ÉCHEC\n" + r.stderr)

print("· Contrôles …\n")
r = subprocess.run([sys.executable, 'controles.py'] + sys.argv[1:],
                   capture_output=True, text=True)
print(r.stdout)
if r.stderr: print(r.stderr)

ok = 'ANOMALIES BLOQUANTES : 0' in r.stdout
print("\n" + ("─" * 62))
print("PRÊT À DÉPLOYER." if ok else "NE PAS DÉPLOYER — corrigez les anomalies ci-dessus.")
print("─" * 62)
sys.exit(0 if ok else 1)
