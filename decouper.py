"""FFCE — Découpe index.html en modules ES natifs.

Aucune compilation : les navigateurs chargent nativement les modules. La
décision d'architecture n° 1 disait « pas de build » — elle est tenue.
« Un seul fichier » était un moyen, pas une fin.

Le script est mécanique : il découpe aux définitions de premier niveau,
répartit selon la carte ci-dessous, puis CALCULE les imports de chaque
module à partir des identifiants réellement employés. Rien n'est écrit
à la main, donc rien n'est oublié.
"""
import re, os, sys

# --- la carte des modules -----------------------------------------------
CARTE = {
 'socle': ['html','SUPABASE_URL','SUPABASE_KEY','db','EXTERNE','jour','initiales',
   'nomComplet','useRoute','aller','EURO','ETAT_NOTE','etatNote','CATEGORIES',
   'MESURES','GRAVITE','ETAPES','ETAPE_NOM','MOIS','nomMois','SECTIONS_DOSSIER',
   'CANAUX','ETAT_PUB','urlPublique','deposerImage','PHASES','PHASE_NOM','TYPE_AG',
   'NATURES_TICKET','ETAT_TICKET','STATUT_PROJET','STATUT_PROP','STATUT_EX',
   'RESEAUX','TYPES_LECON','MERITES','ETAT_INV','ORIGINE_INV','etatCmd','etatInv',
   'NATURE_REMONTEE','TYPE_ACTE','TYPE_CONTACT','STATUT_CONTACT','NATURE_ECHANGE',
   'NATURE_FIL','Portrait','Logo','Maillage','Info','Progression','Completude'],

 'vitrine': ['EntetePublique','Pied','Blocs','Actualites','PageActualites',
   'PageArticle','Accueil','Association','Actions','Reseau','Rejoindre','Contact',
   'PageTexte','Connexion','Inscription','CarteFederale','Site'],

 'espace': ['Flanc','CeQuiAttend','TableauDeBord','FilActualite','Espace',
   'EspaceSuspendu','Assistance','AssistanceAdmin','Referentiel','Matrice',
   'Delegations','Espace'],

 'membre': ['MonPortrait','MonCompte','QuiMaConsulte','MesDemandes','Annuaire',
   'CarteAdherent','qrMatrice','MonDossier','DossierAdhesion','ApercuAdhesion',
   'DossierIncomplet','FilDossier','FicheMembre','ProfilInterne','MesMandats',
   'FicheOuverture','Passeport','BilansMission','MesDistinctions','CurseurEngagement',
   'Engagement','BilanAnnee','MesVirements','MonRib','MesAlertesParcours',
   'MesCreneaux','PrendreRendezVous','Tunnel','MaChaine'],

 'formation': ['Formations','Formation','Lecon','EditeurFormations','EditeurParcours',
   'EditeurLecon','Chancellerie','BaremeEchelons','Distinctions'],

 'collectif': ['Groupes','Groupe','GtTaches','GtDocuments','GtMembres',
   'GroupesOuverts','CandidaturesGroupe','EquipesLocales','Messagerie',
   'Conversation','JournalPieces'],

 'finances': ['NotesFrais','NoteFrais','Finances','SuiviNote','InstruireLignes',
   'Budget','Rapport','SuiviVirements','Ressources','ResSolde','ResCatalogue',
   'ResCommandes','ResInventaire','ResInvestissements','ResLogistique',
   'ResDotations','MesEnveloppes','InvestissementsAOrdonnancer'],

 'structure': ['MonComite','ProjetsComite','PropositionsComite',
   'PropositionsNationales','GestionLocale','GlFiche','GlAcces','GlActes','GlPlan',
   'CarteReseau','FOND','cacheFond','chargerFond','projeter','bornes','anneaux',
   'Organigramme','NommerLocal','Pilotage','BordLocal','BordTunnel','BordNational',
   'ParcoursAdherent','FileAccueil','RepartirNouveaux','Structures'],

 'direction': ['Habilitations','ListeMembres','FicheAdmin','PostesEtDroits',
   'IdentiteApplications','Postes','Interims','ConformitePostes','Validation',
   'EnAttente','Cabinet','CabinetEtat','CabinetRemontees','CabinetActes',
   'RecueilListe','Recueil','VersLeCabinet','AffairesPubliques','ApFichier',
   'ApContact','ApSollicitations','ApProspection','Communication','RappelCharte',
   'Campagnes','EditionPublication','Publier','Suggestion','SuggestionsAdmin',
   'VitrineAdmin','VitrineTextes','VitrineBlocs','VitrineArticles'],

 'statutaire': ['Assemblees','Assemblee','AppelPublic','Conformite',
   'ArchivesElectorales','Discipline','SuiviUsages','DossierDetail'],
}

OU = {}
for mod, noms in CARTE.items():
    for n in noms: OU[n] = mod

def decouper(chemin='index.html'):
    h = open(chemin, encoding='utf-8').read()
    d = h.find('<script type="module">')
    f = h.rfind('</script>')
    entete, js, pied = h[:d], h[d+len('<script type="module">'):f], h[f:]
    lignes = js.split('\n')

    # Repérage des définitions, commentaire de tête inclus.
    marques = []
    for i, l in enumerate(lignes):
        m = re.match(r'(?:async\s+)?function (\w+)|^const (\w+)\s*=|^let (\w+)\s*=', l)
        if m:
            nom = next(g for g in m.groups() if g)
            debut = i
            j = i - 1
            while j >= 0 and (lignes[j].startswith('/*') or lignes[j].startswith(' *')
                              or lignes[j].startswith('//') or lignes[j].strip().endswith('*/')
                              or lignes[j].strip() == ''):
                if lignes[j].strip() == '' and j > 0 and lignes[j-1].strip() == '':
                    break
                debut = j; j -= 1
            marques.append((nom, debut, i))

    blocs, inconnus = {}, []
    for idx, (nom, debut, ligne_def) in enumerate(marques):
        fin = marques[idx+1][1] if idx+1 < len(marques) else len(lignes)
        corps = '\n'.join(lignes[debut:fin]).rstrip()
        mod = OU.get(nom)
        if mod is None:
            inconnus.append(nom); mod = 'espace'
        blocs.setdefault(mod, []).append((nom, corps))

    if inconnus:
        print("NON AFFECTÉS (placés dans espace.js) :", inconnus, file=sys.stderr)

    # L'en-tête du fichier (imports esm.sh) reste dans socle, qui
    # réexporte les hooks : chaque module les importera depuis lui, et
    # non depuis esm.sh — une seule adresse à changer le jour d'une
    # montée de version.
    tete = '\n'.join(lignes[:marques[0][1]]).strip()
    tete += ("\n\n// Réexportés pour que les autres modules n'aient pas à connaître\n"
             "// l'adresse d'esm.sh : la version de Preact se change ici seulement.\n"
             "export { h, render, useState, useEffect, useCallback, createClient };")
    HOOKS = ['useState','useEffect','useCallback','h','render','createClient']

    # Calcul des imports : ce qu'un module emploie et ne définit pas.
    tous = {n for n, _ in [(x[0], 0) for x in marques]}
    sortie = {}
    for mod, items in blocs.items():
        definis = {n for n, _ in items}
        texte = '\n'.join(c for _, c in items)
        besoin = {}
        if mod != 'socle':
            for k in HOOKS:
                if re.search(r'(?<![\w.$])' + k + r'(?![\w$])', texte):
                    besoin.setdefault('socle', set()).add(k)
        for n in tous - definis:
            if re.search(r'(?<![\w.$])' + re.escape(n) + r'(?![\w$])', texte):
                besoin.setdefault(OU.get(n, 'espace'), set()).add(n)
        besoin.pop(mod, None)
        entetes = []
        if mod != 'socle':
            for src in sorted(besoin):
                entetes.append("import { %s } from './%s.js';"
                               % (', '.join(sorted(besoin[src])), src))
        corps = '\n\n'.join(c for _, c in items)
        corps = re.sub(r'^(?=(?:async )?function \w+|const \w+\s*=|let \w+\s*=)',
                       'export ', corps, flags=re.M)
        sortie[mod] = ((tete + '\n\n' if mod == 'socle' else '')
                       + '\n'.join(entetes) + ('\n\n' if entetes else '') + corps + '\n')
    return entete, sortie, pied

if __name__ == '__main__':
    entete, mods, pied = decouper()
    os.makedirs('js', exist_ok=True)
    for m, src in mods.items():
        open('js/%s.js' % m, 'w', encoding='utf-8').write(src)
        print("js/%s.js  %d lignes" % (m, src.count('\n')))
