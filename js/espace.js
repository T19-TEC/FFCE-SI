/* =====================================================================
   ESPACE
   La charpente de l'intranet : le menu latéral, le routeur des
   applications, le tableau de bord, le fil d'actualité, la file de
   travail, le guichet des demandes et le référentiel des droits.

   C'est ici qu'on ajoute la route d'une nouvelle application.
   ===================================================================== */
import { Groupe, Groupes, Messagerie } from './collectif.js';
import { AffairesPubliques, Cabinet, Communication, EnAttente, Habilitations, Postes, Publier, Recueil, Validation, VersLeCabinet, VitrineAdmin } from './direction.js';
import { Budget, Finances, NotesFrais, Rapport, Ressources } from './finances.js';
import { Chancellerie, EditeurFormations, Formation, Formations } from './formation.js';
import { Annuaire, CarteAdherent, CurseurEngagement, DossierIncomplet, Engagement, FicheOuverture, MesDemandes, MesMandats, MesVirements, MonCompte, MonDossier, Passeport, PrendreRendezVous } from './membre.js';
import { ETAT_TICKET, EXTERNE, Info, Logo, NATURES_TICKET, NATURE_FIL, Portrait, Progression, aller, db, html, jour, nomComplet, urlPublique, useCallback, useEffect, useState } from './socle.js';
import { Assemblees, Conformite, Discipline } from './statutaire.js';
import { GestionLocale, MonComite, ParcoursAdherent, Pilotage } from './structure.js';
import { CarteFederale } from './vitrine.js';


/* --- Menu latéral ------------------------------------------------------
   Trois blocs et pas un de plus : qui je suis, ce que je fais, ce que
   j'administre. Le guichet et le référentiel ne sont plus des onglets
   permanents — on y accède au moment où on en a besoin.
   --------------------------------------------------------------------- */
/* --- Menu latéral ------------------------------------------------------
   Le menu suit l'organigramme, pas la liste des tables. Trois strates :
   qui je suis, mon activité de membre, puis les directions dont je
   relève — chacune avec ses outils. C'est ainsi que s'organisent les
   grandes fédérations : on n'appartient pas à « des responsabilités »
   en vrac, on appartient à une direction.
   --------------------------------------------------------------------- */
export function Flanc({ p, apps, page, directions, ouvert, fermer, attentes }){
  const item = (r, t, marque, pivot) => html`
    <a href=${'#/espace/'+r} onClick=${()=>fermer && fermer()}
       class=${(pivot?'pivot ':'') + (page===r?'on':'')}>
      <span class="spread" style="gap:8px">
        <span>${t}</span>
        ${marque > 0 && html`<span class="pastille">${marque}</span>`}
      </span>
    </a>`;

  // Une pastille devant une application veut dire : quelque chose vous y
  // attend. Le compte vient de la file de travail, donc de la base — pas
  // d'un second calcul qui pourrait diverger.
  const marques = {};
  (attentes||[]).forEach(x => {
    const c = (x.lien||'').replace('#/espace/','');
    marques[c] = (marques[c] || 0) + Number(x.nombre || 0);
  });
  const ouvertes = (apps||[]).filter(a => a.ouvert);

  // Une direction qui n'ouvre qu'une seule application ne forme pas un
  // bloc : elle laisse un titre pour une ligne. Ces solitaires
  // rejoignent « Mon activité ». La règle vaut pour tous, plutôt que
  // d'aller corriger chaque cas à la main.
  const groupes = (directions||[]).map(d => ({
    ...d, apps: ouvertes.filter(a => a.direction === d.code)
  }));
  // Une direction qui n'ouvre qu'une application ne forme pas un bloc —
  // sauf celles dont l'existence même est signifiante, marquées
  // `bloc_permanent` en base. La Présidence en est une : la voir sous
  // « Mon activité » dirait le contraire de ce qu'elle est.
  const dirs = groupes.filter(d => d.apps.length > 1
    || (d.bloc_permanent && d.apps.length === 1));
  const solitaires = groupes.filter(d => d.apps.length === 1 && !d.bloc_permanent)
    .flatMap(d => d.apps);
  const perso = ouvertes.filter(a => a.personnelle).concat(solitaires);

  const nom = a => a.nom_court || a.nom;

  return html`
    <aside class=${'flanc'+(ouvert?' ouvert':'')}>
      <div class="entete-flanc">
        <${Logo} baseline=${false} />
      </div>

      <a class=${'moi'+(page==='compte'?' on':'')} href="#/espace/compte"
         onClick=${()=>fermer && fermer()}>
        <${Portrait} chemin=${p.photo_url} nom=${nomComplet(p)} taille=${42} />
        <span style="min-width:0">
          <span class="moi-nom">${nomComplet(p)}</span>
          <span class="moi-role">${p.fonction_nom} · échelon ${p.echelon}</span>
        </span>
      </a>

      <nav>
        ${item('', 'Table de contrôle', 0, true)}

        <div class="groupe">Mon activité</div>
        ${item('mandats', 'Mes mandats', marques['mandats'])}
        ${perso.map(a => item(a.code, nom(a), marques[a.code]))}

        ${dirs.map(d => html`
          <div class=${'groupe direction '+d.couleur}>${d.nom_court || d.nom}</div>
          ${d.par_poste && d.postes.length > 0 && html`
            <div class="mandat">${d.postes.join(' · ')}</div>`}
          ${d.apps.map(a => item(a.code, nom(a), marques[a.code]))}`)}

        <div class="groupe">Ailleurs</div>
        <a href=${EXTERNE.drive} target="_blank" rel="noopener">Drive ↗</a>
        <a href=${EXTERNE.agenda} target="_blank" rel="noopener">Agenda ↗</a>
        ${p.webmail && html`<a href=${EXTERNE.webmail} target="_blank" rel="noopener">Webmail ↗</a>`}
        <a href="#/" onClick=${()=>db.auth.signOut()}>Se déconnecter</a>
      </nav>
    </aside>`;
}

/* --- Progression : les points d'échelon ------------------------------- */

/* --- Ce qui attend : la file de travail personnelle -------------------
   Les alertes se perdaient au fond des onglets. Elles remontent ici,
   en tête du tableau de bord, triées par urgence.
   --------------------------------------------------------------------- */
export function CeQuiAttend({ items }){
  if (!items || items.length === 0) return null;

  const urgents = items.filter(x => x.urgence === 'haute');
  const normaux = items.filter(x => x.urgence !== 'haute');

  const carte = (x, haute) => html`
    <a href=${x.lien} style=${'display:block;background:var(--blanc);padding:18px 20px;'+
        'color:var(--encre);border-left:3px solid '+(haute?'var(--rouge)':'var(--bleu)')}>
      <div class="row" style="gap:10px;align-items:baseline">
        <span style=${'font-family:var(--serif);font-size:30px;line-height:1;color:'+
          (haute?'var(--rouge)':'var(--bleu)')}>${x.nombre}</span>
        <span class="small">${x.libelle}</span>
      </div>
    </a>`;

  return html`
    <div>
      <div class="spread" style="margin-bottom:12px">
        <div class="eyebrow">Ce qui attend</div>
        ${urgents.length > 0 && html`
          <span class="tag rouge">${urgents.reduce((n,x)=>n+x.nombre,0)} à traiter sans délai</span>`}
      </div>
      <div class="tuiles" style="grid-template-columns:repeat(auto-fill,minmax(230px,1fr))">
        ${urgents.map(x => carte(x, true))}
        ${normaux.map(x => carte(x, false))}
      </div>
    </div>`;
}

import { Evenements } from './evenements.js';

export function TableauDeBord({ p, apps, chemin, demandes, attentes }){
  const ouvertes = demandes.filter(d => d.statut === 'ouverte' || d.statut === 'en_cours');
  return html`
    <div class="stack" style="gap:32px;display:flex;flex-direction:column">
      <div class="spread">
        <div>
          <div class="eyebrow">Table de contrôle</div>
          <h1 style="margin-top:6px">Bonjour, ${p.prenom || 'bienvenue'}.</h1>
        </div>
        <a class="btn light" href="#/espace/demandes">Guichet des demandes</a>
      </div>

      <${CarteAdherent} />

      <${MonDossier} p=${p} entier=${false} />

      <${FicheOuverture} compact=${true}
        titre="Ce qu\u2019il vous reste à faire pour être pleinement outillé" />

      ${p.niveau >= 40 && html`<${VersLeCabinet} />`}

      <${Delegations} />

      <${MesVirements} />

      <${PrendreRendezVous} />

      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px">
        <${CurseurEngagement} compact=${true} />
        <${Progression} />
      </div>

      <${FilActualite} p=${p} />

      <${CeQuiAttend} items=${attentes} />

      <div class="spread" style="align-items:stretch;gap:24px;flex-wrap:wrap">
        <div style="flex:1;min-width:280px"><${CarteFederale} p=${p} chemin=${chemin} /></div>
      </div>

      ${ouvertes.length > 0 && html`
        <div class="alerte">
          ${ouvertes.length} demande${ouvertes.length>1?'s':''} en cours d'instruction.
          <a href="#/espace/demandes">Voir le suivi</a>
        </div>`}

      <div>
        <div class="spread" style="margin-bottom:16px">
          <div class="row" style="gap:8px">
            <h2 style="font-size:22px">Mes applications</h2>
            <${Info} texte="Ce que vous voyez ici dépend de votre fonction. Une application grisée peut être demandée au guichet ; une application absente n'est pas ouverte à votre fonction. La page « Comprendre mes droits » détaille tout." />
          </div>
          <a class="small" href="#/espace/referentiel">Comprendre mes droits</a>
        </div>
        <div class="tuiles">
          ${apps.filter(a => a.actif).map(a => {
            const lien = a.externe_url || ('#/espace/'+a.code);
            const cible = a.externe_url ? '_blank' : null;
            if (!a.ouvert) return html`
              <div class="tuile bloquee">
                <h3>${a.nom_court || a.nom}</h3>
                <p>${a.accroche || a.description}</p>
                <div style="margin-top:12px">
                  ${a.demande_en_cours
                    ? html`<span class="tag bleu">Demande en cours</span>`
                    : html`<a class="btn sm light" href="#/espace/demandes">Demander l\u2019accès</a>`}
                </div>
                <div class="small muted" style="margin-top:6px">${a.explication}</div>
              </div>`;
            const teinte = {bleu:'var(--bleu)', bordeaux:'var(--bordeaux)',
              nuit:'var(--nuit)', brun:'var(--brun)', action:'var(--action)',
              framboise:'var(--framboise)'}[a.couleur] || 'var(--bleu)';
            return html`
              <a class="tuile" href=${lien} target=${cible} rel="noopener"
                 style=${'border-top:3px solid '+teinte}
                 onClick=${()=>db.rpc('tracer_acces', { p_app: a.code })}>
                <div class="row" style="gap:10px;align-items:flex-start">
                  ${a.logo && html`<img src=${urlPublique(a.logo)} alt=""
                    style="width:30px;height:30px;object-fit:contain;flex:0 0 30px" />`}
                  <h3 style=${'color:'+teinte}>${a.nom_court || a.nom}${a.externe_url ? ' ↗' : ''}</h3>
                </div>
                <p style="margin-top:8px">${a.accroche || a.description}</p>
                ${a.source !== 'fonction' && html`
                  <div style="margin-top:10px">
                    <span class=${'tag '+(a.source==='nominatif'?'bleu':
                      a.source==='poste'?'or':a.source==='admin'?'':'')}>
                      ${a.source === 'nominatif' ? 'Accordée'
                        : a.source === 'poste' ? 'Par votre poste'
                        : a.source === 'admin' ? 'Administration' : ''}</span>
                  </div>`}
              </a>`;
          })}
        </div>
      </div>
    </div>`;
}

export function EspaceSuspendu({ p }){
  return html`
    <div style="min-height:100vh;background:var(--papier)">
      <header class="entete"><div class="wrap">
        <${Logo} />
        <a class="btn ghost sm" href="#/" onClick=${()=>db.auth.signOut()}>Se déconnecter</a>
      </div></header>

      <div class="wrap" style="max-width:760px;padding-top:56px;padding-bottom:80px">
        <div class="eyebrow">Accès restreint</div>
        <h1 style="margin:8px 0 16px">Votre compte est suspendu</h1>
        <p class="muted" style="max-width:58ch">
          Vos accès à la plateforme sont interrompus. Cette page reste ouverte :
          elle vous permet de suivre votre dossier, d\u2019y verser vos observations
          et d\u2019exercer vos voies de recours.
        </p>

        <div class="panneau" style="margin:32px 0">
          <div class="tete"><h3 style="font-size:17px">Vos droits</h3></div>
          <div class="corps">
            <p class="small">Vous pouvez à tout moment :</p>
            <ul class="small" style="color:var(--gris);padding-left:18px;margin:8px 0 0">
              <li>consulter les pièces communicables de votre dossier ;</li>
              <li>y verser vos observations, qui seront lues par l\u2019instruction ;</li>
              <li>former un recours gracieux contre toute décision notifiée,
                  dans le délai indiqué ;</li>
              <li>demander l\u2019accès à vos données personnelles et leur
                  rectification, auprès du référent à la protection des données ;</li>
              <li>être accompagné par la personne de votre choix.</li>
            </ul>
            <p class="small muted" style="margin-top:16px">
              L\u2019épuisement du recours gracieux ne vous prive d\u2019aucun droit
              devant les juridictions compétentes.
            </p>
          </div>
        </div>

        <${MonDossier} p=${p} entier=${true} />

        <div class="panneau" style="margin-top:24px">
          <div class="corps small muted">
            Pour toute question sur la procédure, écrivez à la direction des
            affaires juridiques à l\u2019adresse de contact de la fédération.
          </div>
        </div>
      </div>
    </div>`;
}

/* --- L'application Discipline ---------------------------------------- */

export function Referentiel(){
  const [r, setR] = useState(null);
  const [onglet, setOnglet] = useState('fonctions');
  useEffect(() => { db.rpc('referentiel').then(({data}) => setR(data)); }, []);
  if (!r) return html`<div class="vide">Chargement…</div>`;

  const etat = e => ({
    ouverte:    html`<span class="tag vert">Ouverte</span>`,
    sur_demande:html`<span class="tag or">Sur demande</span>`,
    invisible:  html`<span class="tag">Non ouverte</span>`
  })[e];

  return html`
    <div>
      <div class="eyebrow">Référentiel</div>
      <h1 style="margin:6px 0 12px">Comprendre les droits</h1>
      <p class="muted" style="max-width:62ch">
        Rien n\u2019est caché ici. Un système de droits que personne ne comprend
        n\u2019est pas accepté : il est subi. Vous êtes
        <strong>${r.ma_fonction}</strong>, à l\u2019échelon <strong>${r.mon_echelon}</strong>.
      </p>

      <div class="row" style="margin:32px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['fonctions','Fonctions'],['echelons','Échelons'],['postes','Postes'],
           ['applications','Applications']].map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'fonctions' && html`
        <div>
          <p class="intro" style="margin-bottom:20px">
            La fonction est le poste que vous occupez dans la fédération. Elle
            détermine votre <strong>périmètre</strong> : vous voyez et accompagnez
            votre territoire et tout ce qui en dépend, jamais celui du voisin.
          </p>
          <div class="panneau" style="overflow-x:auto">
            <table>
              <thead><tr><th>Fonction</th><th>Famille</th><th>Échelle</th>
                <th>Niveau</th><th>Membres</th></tr></thead>
              <tbody>
                ${r.fonctions.map(f => html`
                  <tr>
                    <td>${f.nom}</td>
                    <td class="small muted">${f.famille}</td>
                    <td class="small muted">${f.echelle || '—'}</td>
                    <td class="mono">${f.niveau}</td>
                    <td class="mono">${f.effectif}</td>
                  </tr>`)}
              </tbody>
            </table>
          </div>
        </div>`}

      ${onglet === 'echelons' && html`
        <div>
          <p class="intro" style="margin-bottom:20px">
            L\u2019échelon reconnaît l\u2019expérience, indépendamment du poste.
            <strong>La fonction donne le pouvoir, l\u2019échelon reconnaît le parcours.</strong>
            Un bénévole de longue date peut être échelon 5 sans encadrer personne.
          </p>
          <div class="panneau">
            ${r.echelons.map(e => html`
              <div class="ligne">
                <div>
                  <div><strong>${e.niveau}. ${e.nom}</strong></div>
                  <div class="small muted">${e.ouvre || 'Aucun pouvoir particulier'}</div>
                </div>
                <div class="row">
                  <span class="tag">${e.points} points</span>
                  <span class="tag or">${e.effectif} membre${e.effectif>1?'s':''}</span>
                </div>
              </div>`)}
          </div>
        </div>`}

      ${onglet === 'postes' && html`
        <div>
          <p class="intro" style="margin-bottom:20px">
            Un poste est un mandat nommé, cumulable et révocable, indépendant du
            grade. Il ouvre des droits que la fonction ne donne pas. Savoir qui
            est référent RGPD ou membre du conseil de discipline fait partie du
            fonctionnement normal d\u2019une association.
          </p>
          ${r.postes.map(po => html`
            <div class="panneau" style="margin-bottom:16px">
              <div class="tete">
                <div>
                  <h3 style="font-size:17px">${po.nom}</h3>
                  ${po.description && html`<div class="small muted"
                    style="margin-top:4px;max-width:58ch">${po.description}</div>`}
                </div>
                <span class=${'tag '+(po.couleur==='neutre'?'':po.couleur)}>
                  ${(po.titulaires||[]).length} titulaire${(po.titulaires||[]).length>1?'s':''}</span>
              </div>
              <div class="corps">
                <div class="eyebrow" style="margin-bottom:8px">Droits ouverts</div>
                <div class="row" style="gap:6px">
                  ${(po.droits||[]).map(d => html`<span class="tag">${d}</span>`)}
                  ${(po.droits||[]).length === 0 && html`<span class="small muted">Aucun</span>`}
                </div>
                ${(po.titulaires||[]).length > 0 && html`
                  <div style="margin-top:16px">
                    <div class="eyebrow" style="margin-bottom:8px">Titulaires</div>
                    <div class="small">${po.titulaires.join(' · ')}</div>
                  </div>`}
              </div>
            </div>`)}
        </div>`}

      ${onglet === 'applications' && html`
        <div>
          <p class="intro" style="margin-bottom:20px">
            Voici ce que votre fonction vous ouvre aujourd\u2019hui.
            <strong>Ouverte</strong> : accessible immédiatement.
            <strong>Sur demande</strong> : à solliciter au guichet, la Direction
            générale décide. <strong>Non ouverte</strong> : hors de votre fonction,
            sauf poste particulier.
          </p>
          <div class="panneau">
            ${r.applications.map(a => html`
              <div class="ligne">
                <div style="flex:1;min-width:220px">
                  <div>${a.nom}</div>
                  <div class="small muted">${a.description || ''}</div>
                  ${a.droit_requis && html`<div class="small muted" style="margin-top:4px">
                    Exige le droit : ${a.droit_requis}</div>`}
                </div>
                ${etat(a.mon_etat)}
              </div>`)}
          </div>
        </div>`}
    </div>`;
}

/* --- La matrice des accès, côté pilotage ------------------------------ */

export function Matrice({ setMsg }){
  const [m, setM] = useState([]);
  const charger = useCallback(async () => {
    const { data } = await db.rpc('matrice_acces');
    setM(data || []);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const suivant = { ouverte:'sur_demande', sur_demande:'invisible', invisible:'ouverte' };
  const style = {
    ouverte:    'background:var(--valide-clair);color:var(--valide);border-color:#C8DED3',
    sur_demande:'background:var(--brun-clair);color:var(--brun);border-color:#E0D5CC',
    invisible:  'background:var(--papier);color:var(--gris-bleu);border-color:var(--filet)'
  };
  const signe = { ouverte:'Ouverte', sur_demande:'Sur demande', invisible:'—' };

  async function basculer(c){
    const { data, error } = await db.rpc('regler_matrice',
      { p_app: c.application, p_fonction: c.fonction, p_etat: suivant[c.etat] });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    charger();
  }

  const apps = [...new Map(m.map(x => [x.application,
    {code:x.application, nom:x.app_nom, droit:x.droit_requis}])).values()];
  const fonctions = [...new Map(m.map(x => [x.fonction,
    {code:x.fonction, nom:x.fonction_nom, niveau:x.niveau}])).values()]
    .sort((a,b) => a.niveau - b.niveau);

  return html`
    <div>
      <p class="small muted" style="margin-bottom:16px;max-width:64ch">
        Cliquez une case pour la faire tourner : ouverte → sur demande → non
        ouverte. Une application <strong>ouverte</strong> apparaît et fonctionne.
        <strong>Sur demande</strong>, elle apparaît grisée avec un bouton de
        demande. <strong>Non ouverte</strong>, elle n\u2019apparaît pas du tout.
        Un poste passe outre : un référent RGPD atteint son outil quelle que soit
        sa fonction. Le chiffre en brun sous une case indique combien de membres
        de cette fonction y accèdent malgré tout — par un poste ou un octroi
        nominatif. Fermer la case ne les ferme pas.
      </p>
      <div class="panneau" style="overflow-x:auto">
        <table style="font-size:12.5px">
          <thead><tr>
            <th style="position:sticky;left:0;background:#fff;min-width:190px">Application</th>
            ${fonctions.map(f => html`<th style="text-align:center;min-width:96px">
              ${f.nom}</th>`)}
          </tr></thead>
          <tbody>
            ${apps.map(a => html`
              <tr>
                <td style="position:sticky;left:0;background:#fff">
                  <div>${a.nom}</div>
                  ${a.droit && html`<div class="small muted">${a.droit_nom||'poste requis'}</div>`}
                </td>
                ${fonctions.map(f => {
                  const c = m.find(x => x.application === a.code && x.fonction === f.code);
                  if (!c) return html`<td></td>`;
                  return html`
                    <td style="text-align:center;padding:6px">
                      <button onClick=${()=>basculer(c)}
                        style=${'width:100%;padding:6px 4px;border:1px solid;border-radius:2px;'+
                          'font-family:var(--titre);font-weight:700;font-size:10px;'+
                          'letter-spacing:.04em;text-transform:uppercase;'+style[c.etat]}>
                        ${signe[c.etat]}</button>
                      ${c.contournements > 0 && html`
                        <div class="small" style="color:var(--brun);margin-top:3px;font-size:10px"
                          title="Membres qui y accèdent par un poste ou un octroi nominatif">
                          +${c.contournements}</div>`}
                    </td>`;
                })}
              </tr>`)}
          </tbody>
        </table>
      </div>
    </div>`;
}


export function Assistance({ p }){
  const [ouvert, setOuvert] = useState(false);
  const [miens, setMiens] = useState([]);
  const [nature, setNature] = useState(null);
  const [f, setF] = useState({titre:'', description:'', urgent:false});
  const [fil, setFil] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(() =>
    db.rpc('liste_tickets', { p_filtre: 'miens' }).then(({data}) => setMiens(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  // Quatre portes d'entrée, pas un formulaire : on choisit d'abord de
  // quoi on parle, le reste s'adapte.
  const PORTES = [
    ['probleme',    'Quelque chose ne marche pas',
     'Un bouton sans effet, une page en erreur, une lenteur.'],
    ['amelioration','J\u2019ai une idée',
     'Quelque chose qui vous ferait gagner du temps.'],
    ['donnee',      'Une information est fausse',
     'Un nom, un chiffre, un rattachement erroné.'],
    ['question',    'Je ne comprends pas',
     'Un écran, une règle, un mot que vous ne saisissez pas.']
  ];

  async function envoyer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('ouvrir_ticket', {
      p_nature: nature, p_titre: f.titre, p_description: f.description || f.titre,
      p_page: location.hash, p_importance: f.urgent ? 'haute' : 'normale',
      p_urgent: f.urgent,
      p_contexte: { navigateur: navigator.userAgent.slice(0,120),
                    largeur: window.innerWidth }
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'', description:'', urgent:false}); setNature(null); setOuvert(false);
    setMsg('Merci. Signalement ' + data.reference + ' transmis.');
    charger();
  }

  async function ouvrirFil(t){
    const { data } = await db.rpc('fil_ticket', { p_id: t.id });
    setFil(data);
  }

  async function repondre(){
    const texte = prompt('Votre message');
    if (!texte) return;
    await db.rpc('repondre_ticket', { p_id: fil.ticket.id, p_contenu: texte });
    ouvrirFil({ id: fil.ticket.id });
  }

  if (fil) return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <div>
          <h3 style="font-size:17px">${fil.ticket.titre}</h3>
          <div class="small muted"><span class="mono">${fil.ticket.reference}</span>
            · ${jour(fil.ticket.cree_le)}</div>
        </div>
        <button class="btn sm light" onClick=${()=>setFil(null)}>Fermer</button>
      </div>
      <div class="corps">
        <div class="small" style="white-space:pre-wrap">${fil.ticket.description}</div>
        ${fil.ticket.reponse && html`
          <div class="alerte ok" style="margin-top:16px">${fil.ticket.reponse}</div>`}
        ${(fil.messages||[]).map(m => html`
          <div style=${'margin-top:14px;padding:10px 12px;border-radius:2px;background:'+
            (m.moi?'var(--action-clair)':'var(--papier)')}>
            <div class="small muted">${m.moi ? 'Vous' : m.auteur} ·
              ${new Date(m.cree_le).toLocaleString('fr-FR',
                {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</div>
            <div class="small" style="margin-top:4px;white-space:pre-wrap">${m.contenu}</div>
          </div>`)}
        <div class="row" style="margin-top:16px">
          <button class="btn sm light" onClick=${repondre}>Ajouter un message</button>
          <span class=${'tag '+(ETAT_TICKET[fil.ticket.statut]||['',''])[1]}>
            ${(ETAT_TICKET[fil.ticket.statut]||[fil.ticket.statut,''])[0]}</span>
        </div>
      </div>
    </div>`;

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Un souci, une idée ?</h3>
          <${Info} texte="Tout est lu. Vous verrez la réponse ici même, et vous pourrez échanger sur votre signalement." />
        </div>
        ${!ouvert && html`<button class="btn sm" onClick=${()=>setOuvert(true)}>
          Nous en parler</button>`}
      </div>
      ${msg && html`<div class="corps"><div class=${'alerte '+
        (msg.startsWith('Erreur')?'err':'ok')}>${msg}</div></div>`}

      ${ouvert && !nature && html`
        <div class="corps">
          <p class="small muted" style="margin:0 0 14px">De quoi s\u2019agit-il ?</p>
          <div class="tuiles" style="grid-template-columns:repeat(auto-fit,minmax(230px,1fr))">
            ${PORTES.map(([k, titre, aide]) => html`
              <button class="tuile" style="text-align:left;border:0;min-height:auto"
                onClick=${()=>setNature(k)}>
                <h3 style="font-size:15px">${titre}</h3>
                <p style="margin-top:6px">${aide}</p>
              </button>`)}
          </div>
          <button class="lien-discret" style="margin-top:14px"
            onClick=${()=>setOuvert(false)}>Annuler</button>
        </div>`}

      ${ouvert && nature && html`
        <form onSubmit=${envoyer} class="corps stack">
          <div class="row" style="gap:8px">
            <span class="tag bleu">${(PORTES.find(x=>x[0]===nature)||[])[1]}</span>
            <button type="button" class="lien-discret"
              onClick=${()=>setNature(null)}>Changer</button>
          </div>
          <div class="field">
            <label>${nature === 'amelioration' ? 'Votre idée, en une ligne'
              : nature === 'question' ? 'Votre question'
              : 'En une ligne'}</label>
            <input required autofocus value=${f.titre}
              onInput=${e=>setF(o=>({...o,titre:e.target.value}))} />
          </div>
          <div class="field">
            <label>${nature === 'probleme'
              ? 'Ce que vous faisiez, et ce qui est arrivé'
              : 'Précisions (facultatif)'}</label>
            <textarea value=${f.description} style="min-height:90px"
              onInput=${e=>setF(o=>({...o,description:e.target.value}))} />
          </div>
          <label class="row" style="text-transform:none;letter-spacing:0;
              font-size:14px;color:var(--nuit);margin:0;cursor:pointer">
            <input type="checkbox" style="width:auto" checked=${f.urgent}
              onChange=${e=>setF(o=>({...o,urgent:e.target.checked}))} />
            <span>C\u2019est urgent — cela m\u2019empêche de travailler</span>
          </label>
          <div class="row">
            <button class="btn">Envoyer</button>
            <button type="button" class="btn light"
              onClick=${()=>{setOuvert(false);setNature(null)}}>Annuler</button>
          </div>
          <p class="small muted">
            La page où vous êtes et votre navigateur sont joints automatiquement :
            cela nous évite de vous les demander.
          </p>
        </form>`}

      ${!ouvert && miens.length > 0 && html`
        <div>
          ${miens.slice(0,6).map(t => html`
            <div class="ligne" style="cursor:pointer" onClick=${()=>ouvrirFil(t)}>
              <div style="flex:1;min-width:200px">
                <div class="row" style="gap:8px">
                  <span>${t.titre}</span>
                  ${t.urgent && html`<span class="tag rouge">Urgent</span>`}
                </div>
                <div class="small muted">
                  <span class="mono">${t.reference}</span> · ${jour(t.cree_le)}
                  ${t.assigne ? ' · ' + t.assigne + ' s\u2019en occupe' : ''}
                  ${t.messages > 0 ? ' · ' + t.messages + ' message(s)' : ''}
                </div>
              </div>
              <span class=${'tag '+(ETAT_TICKET[t.statut]||['',''])[1]}>
                ${(ETAT_TICKET[t.statut]||[t.statut,''])[0]}</span>
            </div>`)}
        </div>`}
      ${!ouvert && miens.length === 0 && html`
        <div class="corps small muted">
          Vous n\u2019avez rien signalé. Si quelque chose vous gêne, dites-le :
          c\u2019est ainsi que la plateforme s\u2019améliore.
        </div>`}
    </div>`;
}

/* --- Assistance, côté pilotage ---------------------------------------- */

export function AssistanceAdmin({ setMsg }){
  const [liste, setListe] = useState([]);
  const [filtre, setFiltre] = useState('ouverts');
  const [gens, setGens] = useState([]);

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('liste_tickets', { p_filtre: filtre }),
      db.from('v_annuaire').select('id,prenom,nom').eq('statut','actif').order('nom')
    ]);
    setListe(a.data||[]); setGens(b.data||[]);
  }, [filtre]);
  useEffect(() => { charger(); }, [charger]);

  async function traiter(t, champs){
    const { data, error } = await db.rpc('traiter_ticket', {
      p_id: t.id, p_statut: champs.statut || null, p_assigne: champs.assigne || null,
      p_echeance: champs.echeance || null, p_importance: champs.importance || null,
      p_reponse: champs.reponse || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    charger();
  }

  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete">
        <h3 style="font-size:17px">Signalements et propositions</h3>
        <div class="row">
          <select style="width:auto" value=${filtre} onChange=${e=>setFiltre(e.target.value)}>
            <option value="ouverts">En cours</option>
            <option value="assignes">Qui me sont assignés</option>
            <option value="tous">Tous</option>
          </select>
          <span class="tag">${liste.length}</span>
        </div>
      </div>
      ${liste.length === 0
        ? html`<div class="vide">Aucun signalement.</div>`
        : html`<div style="overflow-x:auto">
            <table>
              <thead><tr><th>Signalement</th><th>Par</th><th>Assigné à</th>
                <th>Échéance</th><th>Importance</th><th>État</th><th></th></tr></thead>
              <tbody>
                ${liste.map(t => html`
                  <tr>
                    <td style="max-width:280px">
                      <div class="row" style="gap:6px">
                        <span>${t.titre}</span>
                        ${t.urgent && html`<span class="tag rouge">Urgent</span>`}
                      </div>
                      <div class="small muted">${NATURES_TICKET[t.nature]||t.nature}
                        · <span class="mono">${t.reference}</span>
                        ${t.page ? ' · ' + t.page : ''}</div>
                      <div class="small muted" style="margin-top:4px;white-space:pre-wrap">
                        ${t.description}</div>
                    </td>
                    <td class="small">${t.auteur}
                      <div class="mono muted">${t.auteur_matricule}</div></td>
                    <td>
                      <select value=${t.assigne_id||''} style="min-width:130px"
                        onChange=${e=>traiter(t,{assigne:e.target.value||null,
                          statut: e.target.value ? 'pris_en_compte' : null})}>
                        <option value="">—</option>
                        ${gens.map(g => html`<option value=${g.id}>${nomComplet(g)}</option>`)}
                      </select></td>
                    <td>
                      <input type="date" defaultValue=${t.echeance||''} style="min-width:130px"
                        onBlur=${e=>traiter(t,{echeance:e.target.value||null})} />
                      ${t.retard && html`<div class="small"
                        style="color:var(--bordeaux)">En retard</div>`}</td>
                    <td>
                      <select value=${t.importance} style="min-width:110px"
                        onChange=${e=>traiter(t,{importance:e.target.value})}>
                        <option value="basse">Basse</option>
                        <option value="normale">Normale</option>
                        <option value="haute">Haute</option>
                        <option value="bloquante">Bloquante</option>
                      </select></td>
                    <td>
                      <select value=${t.statut} style="min-width:130px"
                        onChange=${e=>{
                          const st = e.target.value;
                          if (st === 'refuse' || st === 'differe'){
                            const r = prompt('Expliquez à la personne qui a signalé (obligatoire)');
                            if (!r) return charger();
                            return traiter(t,{statut:st, reponse:r});
                          }
                          traiter(t,{statut:st});
                        }}>
                        ${Object.entries(ETAT_TICKET).map(([k,v]) =>
                          html`<option value=${k}>${v[0]}</option>`)}
                      </select></td>
                    <td>
                      <button class="btn sm light" onClick=${()=>{
                        const r = prompt('Réponse à la personne', t.reponse||'');
                        if (r !== null) traiter(t,{reponse:r});
                      }}>Répondre</button></td>
                  </tr>`)}
              </tbody>
            </table>
          </div>`}
    </div>`;
}

/* --- Conformité des élections ----------------------------------------- */

/* --- Mes délégations en cours ------------------------------------------
   Agir au nom d'un autre doit toujours se voir.
   --------------------------------------------------------------------- */
export function Delegations(){
  const [d, setD] = useState([]);
  useEffect(() => { db.rpc('mes_delegations').then(({data}) => setD(data||[])); }, []);
  if (d.length === 0) return null;
  return html`
    <div class="alerte" style="margin-bottom:24px;border-left-color:var(--brun)">
      ${d.map(x => html`
        <div>Vous exercez <strong>${x.poste}</strong> au nom de ${x.au_nom_de},
          jusqu\u2019au ${jour(x.jusqu_au)}.</div>`)}
    </div>`;
}

/* --- Intérim -------------------------------------------------------- */


export function FilActualite({ p }){
  const [l, setL] = useState(null);
  const [filtre, setFiltre] = useState('tout');

  useEffect(() => {
    db.rpc('fil_actualite', { p_limite: 40 }).then(({data}) => setL(data || []));
  }, []);
  if (!l) return html`<div class="vide" style="padding:60px">Chargement…</div>`;

  const natures = [...new Set(l.map(x => x.nature))];
  const liste = filtre === 'tout' ? l : l.filter(x => x.nature === filtre);
  const urgents = l.filter(x => x.urgent).length;

  return html`
    <div style="margin-bottom:32px">
      <div class="spread" style="margin-bottom:14px;flex-wrap:wrap;gap:10px">
        <div>
          <h2 style="font-size:22px;margin:0">Bonjour ${p.prenom}</h2>
          <div class="small muted" style="margin-top:3px">
            ${urgents > 0
              ? urgents + ' chose(s) demandent votre attention aujourd\u2019hui.'
              : 'Rien d\u2019urgent. Voici ce qui se passe dans la fédération.'}
          </div>
        </div>
      </div>

      ${natures.length > 1 && html`
        <div class="row" style="gap:6px;margin-bottom:16px;flex-wrap:wrap">
          <button class=${'btn sm ' + (filtre==='tout' ? '' : 'light')}
            onClick=${()=>setFiltre('tout')}>Tout</button>
          ${natures.map(n => html`
            <button key=${n} class=${'btn sm ' + (filtre===n ? '' : 'light')}
              onClick=${()=>setFiltre(n)}>
              ${(NATURE_FIL[n] || [n])[0]}</button>`)}
        </div>`}

      ${liste.length === 0
        ? html`<div class="vide">Rien à afficher pour l\u2019instant.</div>`
        : html`<div class="panneau">
            ${liste.map((x,i) => html`
              <div class="ligne" key=${i} style=${'align-items:flex-start;border-left:3px solid '
                + (x.urgent ? 'var(--rouge)' : (NATURE_FIL[x.nature] || ['','var(--filet)'])[1])}>
                <div style="flex:1;min-width:250px">
                  <div class="row" style="gap:8px;flex-wrap:wrap;align-items:center">
                    <span class="small" style=${'font-weight:600;color:'
                      + (NATURE_FIL[x.nature] || ['','var(--gris)'])[1]}>
                      ${(NATURE_FIL[x.nature] || [x.nature])[0]}</span>
                    ${x.urgent && html`<span class="tag rouge">À faire</span>`}
                    <span class="small muted">${x.portee}</span>
                  </div>
                  <div style="margin-top:5px;font-weight:${x.urgent ? '600' : '400'}">
                    ${x.titre}</div>
                  ${x.corps && html`<div class="small muted" style="margin-top:3px">
                    ${x.corps}</div>`}
                  ${x.quand && html`<div class="small muted" style="margin-top:3px">
                    ${jour(x.quand)}</div>`}
                </div>
                <a class=${'btn sm ' + (x.urgent ? '' : 'light')} href=${x.lien}>
                  ${x.action}</a>
              </div>`)}
          </div>`}
    </div>`;
}


export function Espace({ session, sous }){
  const [p, setP] = useState(null);
  const [apps, setApps] = useState([]);
  const [demandes, setDemandes] = useState([]);
  const [chemin, setChemin] = useState('');
  const [blocage, setBlocage] = useState(null);
  const [directions, setDirections] = useState([]);
  const [attentes, setAttentes] = useState([]);
  const [menu, setMenu] = useState(false);
  const [pret, setPret] = useState(false);

  const charger = useCallback(async () => {
    const { data: profil } = await db.from('v_annuaire').select('*')
      .eq('id', session.user.id).maybeSingle();
    if (!profil){ setPret(true); return; }
    setP(profil);

    // La matrice décide de ce qui s'affiche, de ce qui est grisé, et de
    // ce qui n'apparaît pas du tout. Elle se règle dans Habilitations.
    const [{ data: liste }, { data: mesDem }, { data: dirs },
           { data: mesDroits }, { data: file }] = await Promise.all([
      db.rpc('mes_applications'),
      db.from('demandes').select('*').eq('profil_id', session.user.id)
        .order('cree_le',{ascending:false}),
      db.rpc('mes_directions'),
      db.rpc('mes_droits'),
      db.rpc('ce_qui_attend')
    ]);
    setApps((liste||[]).map(a => ({ ...a, actif: true })));
    setDirections(dirs || []);
    setDemandes(mesDem || []);
    setAttentes(file || []);
    // Les droits sont énoncés par la base. L'interface ne les devine plus :
    // `v_annuaire` ne les porte pas, la devinette était toujours fausse.
    profil.droits = (mesDroits || []).map(d => d.code);

    // Les postes occupés : ils ouvrent des droits que la fonction ne
    // donne pas — référent RGPD, ordonnateur, conseil de discipline…
    const { data: mp } = await db.rpc('mes_postes');
    profil.postes = mp || [];
    setP({ ...profil });

    // Un dossier incomplet retient le membre sur son compte : la
    // fédération ne peut pas travailler avec des fiches à trous.
    const { data: comp } = await db.rpc('completude_bloquante');
    setBlocage(comp && comp.bloquant ? comp.manques : null);

    if (profil.territoire_id){
      const { data } = await db.rpc('chemin_territoire', { cible: profil.territoire_id });
      setChemin(data || '');
    }
    setPret(true);
  }, [session.user.id]);

  useEffect(() => { charger(); }, [charger]);

  if (!pret) return html`<div class="vide" style="padding:120px">Chargement…</div>`;
  if (!p) return html`<div class="vide" style="padding:120px">
    Profil introuvable. <a href="#/" onClick=${()=>db.auth.signOut()}>Se déconnecter</a></div>`;
  if (p.statut === 'suspendu') return html`<${EspaceSuspendu} p=${p} />`;
  if (blocage && sous !== 'compte') return html`
    <div class="app">
      <${Flanc} p=${p} apps=${apps} directions=${directions} page="compte"
        ouvert=${false} fermer=${()=>{}} attentes=${attentes} />
      <main class="contenu"><${DossierIncomplet} p=${p} manques=${blocage} /></main>
    </div>`;
  if (p.statut !== 'actif') return html`<${EnAttente} p=${p} />`;

  const admin = p.niveau >= 90;
  const acces = c => apps.find(a => a.code === c && a.ouvert);
  const refus = html`<div class="alerte err">Cette application ne vous est pas ouverte.
    <a href="#/espace/demandes">Déposer une demande</a></div>`;

  let vue;
  if (sous.startsWith('groupe/')){
    const idG = sous.slice('groupe/'.length);
    return html`
      <div class="app">
        <${Flanc} p=${p} apps=${apps} directions=${directions} page="groupes"
          attentes=${attentes} />
        <main class="contenu">
          ${acces('groupes') ? html`<${Groupe} p=${p} id=${idG} />` : refus}
        </main>
      </div>`;
  }
  if (sous.startsWith('formation/')){
    const idF = sous.slice('formation/'.length);
    return html`
      <div class="app">
        <${Flanc} p=${p} apps=${apps} directions=${directions} page="formations"
          attentes=${attentes} />
        <main class="contenu">
          ${acces('formations') ? html`<${Formation} p=${p} id=${idF} />` : refus}
        </main>
      </div>`;
  }
  switch (sous){
    case '':           vue = html`<${TableauDeBord} p=${p} apps=${apps} chemin=${chemin}
                         demandes=${demandes} attentes=${attentes} />`; break;
    case 'mandats':    vue = html`<${MesMandats} p=${p} recharger=${charger} />`; break;
    case 'cabinet':    vue = acces('cabinet') ? html`<${Cabinet} p=${p} />` : refus; break;
    case 'recueil':    vue = html`<${Recueil} />`; break;
    case 'evenements': vue = acces('evenements')
                       ? html`<${Evenements} p=${p} />` : refus; break;
    case 'gestion_locale': vue = acces('gestion_locale')
                       ? html`<${GestionLocale} p=${p} />` : refus; break;
    case 'affaires_publiques': vue = acces('affaires_publiques')
                       ? html`<${AffairesPubliques} p=${p} />` : refus; break;
    case 'compte':     vue = html`<${MonCompte} p=${p} recharger=${charger} />`; break;
    case 'mon-dossier':vue = html`<${MonDossier} p=${p} entier=${true} />`; break;
    case 'referentiel':vue = html`<${Referentiel} />`; break;
    case 'engagement': vue = acces('engagement') ? html`<${Engagement} p=${p} />` : refus; break;
    case 'comite':     vue = acces('comite')
                       ? html`<${MonComite} p=${p} apps=${apps} />` : refus; break;
    case 'budget':     vue = acces('budget') ? html`<${Budget} p=${p} />` : refus; break;
    case 'publier':    vue = acces('publier') ? html`<${Publier} p=${p} />` : refus; break;
    case 'editeur':    vue = (admin || (p.postes||[]).length > 0)
                       ? html`<${EditeurFormations} p=${p} />` : refus; break;
    // Le rapport n'a plus d'entrée de menu : il est un onglet du
    // cabinet. Sa route reste ouverte pour que les liens existants
    // continuent de fonctionner.
    case 'rapport':    vue = (acces('rapport') || acces('cabinet'))
                       ? html`<${Rapport} p=${p} />` : refus; break;
    case 'passeport':  vue = html`<${Passeport} p=${p} />`; break;
    case 'conformite': vue = html`<${Conformite} p=${p} />`; break;
    case 'parcours':   vue = acces('parcours')
                          ? html`<${ParcoursAdherent} p=${p} />` : refus; break;
    case 'pilotage':   vue = acces('pilotage')
                          ? html`<${Pilotage} p=${p} />` : refus; break;
    case 'assemblees': vue = acces('assemblees')
                          ? html`<${Assemblees} p=${p} />` : refus; break;
    case 'chancellerie': vue = acces('chancellerie')
                          ? html`<${Chancellerie} p=${p} />` : refus; break;
    case 'communication': vue = acces('communication')
                          ? html`<${Communication} p=${p} />` : refus; break;
    case 'discipline': vue = acces('discipline') ? html`<${Discipline} p=${p} />` : refus; break;
    case 'demandes':   vue = html`<${MesDemandes} p=${p} apps=${apps} demandes=${demandes} recharger=${charger} />`; break;
    case 'annuaire':   vue = acces('annuaire') ? html`<${Annuaire} p=${p} />` : refus; break;
    case 'validation': vue = (admin || (p.droits||[]).includes('membres.valider')
                          || (p.droits||[]).includes('rgpd.alertes'))
                          ? html`<${Validation} p=${p} />` : refus; break;
    case 'reseau':     vue = admin ? html`<${Habilitations} p=${p} />` : refus; break;
    case 'vitrine':    vue = admin ? html`<${VitrineAdmin} />` : refus; break;
    case 'habilitations': vue = (admin || p.droits?.includes('habilitations.gerer'))
                          ? html`<${Habilitations} p=${p} />` : refus; break;
    case 'formations': vue = acces('formations') ? html`<${Formations} p=${p} />` : refus; break;
    case 'groupes':    vue = acces('groupes') ? html`<${Groupes} p=${p} />` : refus; break;
    case 'messagerie': vue = acces('messagerie') ? html`<${Messagerie} p=${p} />` : refus; break;
    case 'notes_frais':vue = acces('notes_frais') ? html`<${NotesFrais} p=${p} />` : refus; break;
    case 'tresorerie': vue = acces('tresorerie')
                       ? html`<${Finances} p=${p} role="tresorerie" />` : refus; break;
    case 'ordonnancement': vue = acces('ordonnancement')
                       ? html`<${Finances} p=${p} role="ordonnancement" />` : refus; break;
    case 'ressources': vue = acces('ressources')
                       ? html`<${Ressources} p=${p} />` : refus; break;
    // Le webmail et l'espace de travail viennent plus tard : d'ici là,
    // on dit ce qu'il en est plutôt que d'annoncer une page inconnue.
    default:           vue = html`
      <div class="panneau" style="margin-top:40px">
        <div class="tete"><h3 style="font-size:17px">Bientôt disponible</h3></div>
        <div class="corps">
          <p style="margin:0 0 12px">
            Cette fonction n\u2019est pas encore ouverte. Elle le sera lors d\u2019une
            prochaine mise à jour de la plateforme.
          </p>
          <p class="small muted" style="margin:0">
            Si vous êtes arrivé ici depuis un lien de la plateforme, signalez-le :
            c\u2019est peut-être un lien qui pointe au mauvais endroit.
          </p>
          <div style="margin-top:16px">
            <a class="btn light" href="#/espace">Retour à mon espace</a>
          </div>
        </div>
      </div>`;
  }

  return html`
    <div class="app">
      <div class="bascule">
        <${Logo} baseline=${false} />
        <div class="row" style="gap:10px">
          <a href="#/espace/compte">
            <${Portrait} chemin=${p.photo_url} nom=${nomComplet(p)} taille=${38} />
          </a>
          <button aria-label="Menu" onClick=${()=>setMenu(true)}>
            <span class="barres"></span></button>
        </div>
      </div>
      <div class=${'voile'+(menu?' ouvert':'')} onClick=${()=>setMenu(false)}></div>
      <${Flanc} p=${p} apps=${apps} directions=${directions} page=${sous}
        ouvert=${menu} fermer=${()=>setMenu(false)} attentes=${attentes} />
      <main class="contenu">${vue}</main>
    </div>`;
}
