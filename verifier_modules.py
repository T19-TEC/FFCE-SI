"""FFCE — Charge réellement les modules ES, avec des substituts locaux.

`node --check` analyse en mode SCRIPT : il accepte des fichiers qui sont
invalides en mode module, et il a laissé passer un commentaire de bloc
coupé en deux. Ce script fait la seule vérification qui vaille : il
importe les modules pour de bon.

    python3 verifier_modules.py
"""
import glob, os, re, shutil, subprocess, sys, tempfile

STUBS = {
 'preact.js':  "export const h=(...a)=>({a}); export const render=()=>{};",
 'hooks.js':   "export const useState=v=>[v,()=>{}];\n"
               "export const useEffect=()=>{}; export const useCallback=f=>f;",
 'htm.js':     "export default { bind: () => (...a) => a };",
 'supabase.js':"export const createClient=()=>({auth:{},from:()=>({}),"
               "rpc:()=>({}),storage:{from:()=>({})}});",
}
REMPLACE = [
 ("https://esm.sh/preact@10.19.3/hooks", "../stub/hooks.js"),
 ("https://esm.sh/preact@10.19.3", "../stub/preact.js"),
 ("https://esm.sh/htm@3.1.1", "../stub/htm.js"),
 ("https://esm.sh/@supabase/supabase-js@2.39.3", "../stub/supabase.js"),
]

def main():
    mods = sorted(f for f in glob.glob('js/*.js') if os.path.basename(f) != 'app.js')
    if not mods:
        print("Aucun module dans js/."); return 1
    t = tempfile.mkdtemp()
    os.makedirs(t + '/js'); os.makedirs(t + '/stub')
    for n, c in STUBS.items():
        open(t + '/stub/' + n, 'w', encoding='utf-8').write(c)
    noms = []
    for f in mods:
        s = open(f, encoding='utf-8').read()
        for a, b in REMPLACE: s = s.replace(a, b)
        # Le montage appelle document : on ne le charge pas ici.
        s = re.sub(r"^render\(.*\);\s*$", '', s, flags=re.M)
        open(t + '/js/' + os.path.basename(f), 'w', encoding='utf-8').write(s)
        noms.append(os.path.basename(f)[:-3])
    prog = "\n".join("import * as m%d from './%s.js';" % (i, n)
                     for i, n in enumerate(noms))
    prog += ("\nconst n=[%s].reduce((t,m)=>t+Object.keys(m).length,0);"
             % ",".join("m%d" % i for i in range(len(noms))))
    prog += "\nconsole.log('MODULES OK — '+n+' exports résolus');"
    open(t + '/js/_verif.js', 'w', encoding='utf-8').write(prog)

    r = subprocess.run(['node', t + '/js/_verif.js'], capture_output=True, text=True)
    shutil.rmtree(t, ignore_errors=True)
    if r.returncode == 0:
        print(r.stdout.strip()); return 0
    print("ÉCHEC DE CHARGEMENT :\n" + (r.stderr or r.stdout).strip()[:1200])
    return 1

if __name__ == '__main__':
    sys.exit(main())
