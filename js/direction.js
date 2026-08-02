import { Conversation, Groupes, JournalPieces } from './collectif.js';
import { AssistanceAdmin, Espace, Matrice } from './espace.js';
import { Rapport, Ressources } from './finances.js';
import { Formations } from './formation.js';
import { ApercuAdhesion, Engagement, MesDistinctions } from './membre.js';
import { CANAUX, Completude, ETAT_PUB, Info, NATURE_ECHANGE, NATURE_REMONTEE, Portrait, RESEAUX, STATUT_CONTACT, TYPE_ACTE, TYPE_CONTACT, db, deposerImage, html, jour, nomComplet, urlPublique, useCallback, useEffect, useState } from './socle.js';
import { Discipline } from './statutaire.js';
import { Pilotage, Structures } from './structure.js';
import { Accueil, Blocs, CarteFederale, Contact, Site } from './vitrine.js';

   ===================================================================== */
export function Habilitations({ p }){
  const [onglet, setOnglet] = useState('membres');
  const [msg, setMsg] = useState('');
  const [fiche, setFiche] = useState(null);

  if (fiche) return html`<${FicheAdmin} p=${p} id=${fiche}
    fermer=${()=>setFiche(null)} setMsg=${setMsg} />`;

  return html`
    <div>
      <div class="eyebrow">Pilotage</div>
      <h1 style="margin:6px 0 8px">Réseau et habilitations</h1>
      <p class="muted" style="max-width:62ch">
        Deux entrées : par la <strong>personne</strong>, pour tout régler sur une
        fiche unique ; par la <strong>structure</strong>, pour voir où le réseau
        tient et où il manque du monde.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="row" style="margin:32px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['membres','Membres'],['structures','Structures'],
           ['postes','Postes et droits'],['interims','Intérims'],
           ['conformite','Conformité des postes'],['applications','Applications']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'membres'      && html`<${ListeMembres} ouvrir=${setFiche} />`}
      ${onglet === 'structures'   && html`<${Structures} setMsg=${setMsg} ouvrir=${setFiche} />`}
      ${onglet === 'postes'       && html`<${PostesEtDroits} setMsg=${setMsg} />`}
      ${onglet === 'interims'   && html`<${Interims} p=${p} setMsg=${setMsg} />`}
      ${onglet === 'conformite' && html`<${ConformitePostes} setMsg=${setMsg} />`}
      ${onglet === 'applications' && html`<${IdentiteApplications} setMsg=${setMsg} />`}
    </div>`;
}


/* --- Liste des membres, une seule porte d'entrée ---------------------- */
export function ListeMembres({ ouvrir }){
  const [m, setM] = useState(null);
  const [q, setQ] = useState('');
  const [filtre, setFiltre] = useState('actifs');

  useEffect(() => {
    db.from('v_annuaire').select('*').order('niveau',{ascending:false}).order('nom')
      .then(({data}) => setM(data||[]));
  }, []);
  if (!m) return html`<div class="vide">Chargement…</div>`;

  const liste = m
    .filter(x => filtre === 'tous' ? true
      : filtre === 'actifs' ? x.statut === 'actif'
      : filtre === 'attente' ? x.statut === 'en_attente'
      : x.statut === 'suspendu')
    .filter(x => (nomComplet(x)+' '+(x.territoire_nom||'')+' '+x.matricule+' '+x.fonction_nom)
      .toLowerCase().includes(q.toLowerCase()));

  return html`
    <div>
      <div class="row" style="margin-bottom:20px;gap:12px">
        <div class="field" style="flex:1;min-width:220px;margin:0">
          <input placeholder="Rechercher un nom, un matricule, un territoire…"
            value=${q} onInput=${e=>setQ(e.target.value)} />
        </div>
        <div class="field" style="width:auto;margin:0">
          <select value=${filtre} onChange=${e=>setFiltre(e.target.value)}>
            <option value="actifs">Actifs</option>
            <option value="attente">En attente</option>
            <option value="suspendus">Suspendus</option>
            <option value="tous">Tous</option>
          </select>
        </div>
      </div>

      <div class="panneau">
        <div class="tete"><span class="small muted">
          ${liste.length} membre${liste.length>1?'s':''}</span></div>
        ${liste.length === 0
          ? html`<div class="vide">Aucun résultat.</div>`
          : liste.slice(0, 200).map(x => html`
            <div class="ligne" style="cursor:pointer" onClick=${()=>ouvrir(x.id)}>
              <div style="flex:1;min-width:200px">
                <div class="row" style="gap:8px">
                  <a href="#" onClick=${e=>e.preventDefault()}>${nomComplet(x)}</a>
                  ${x.protege && html`<span class="tag or">Protégé</span>`}
                </div>
                <div class="small muted">
                  <span class="mono">${x.matricule}</span> · ${x.fonction_nom}
                  ${x.territoire_nom ? ' · ' + x.territoire_nom : ''}
                </div>
              </div>
              <div class="row">
                <span class="tag or">Éch. ${x.echelon}</span>
                <span class=${'tag '+(x.statut==='actif'?'vert':
                  x.statut==='suspendu'?'rouge':'')}>${x.statut.replace('_',' ')}</span>
              </div>
            </div>`)}
        ${liste.length > 200 && html`<div class="corps small muted">
          Seuls les 200 premiers résultats sont affichés. Affinez votre recherche.</div>`}
      </div>
    </div>`;
}


/* --- La fiche unique : tout se règle ici ------------------------------ */
export function FicheAdmin({ p, id, fermer, setMsg }){
  const [f, setF] = useState(null);
  const [ref, setRef] = useState({fonctions:[], terr:[], postes:[], apps:[]});
  const [nouveauPoste, setNouveauPoste] = useState({poste:'', territoire:'', fin:'', motif:''});
  const [nouvelAcces, setNouvelAcces] = useState({app:'', motif:'', expire:''});
  const [tous, setTous] = useState([]);
  const [local, setLocal] = useState('');

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('fiche_admin', { p_profil: id }),
      db.rpc('acces_complets', { p_profil: id })
    ]);
    setF(a.data); setTous(b.data || []);
  }, [id]);
  useEffect(() => { charger(); }, [charger]);

  useEffect(() => { (async () => {
    const [a,b,c,d] = await Promise.all([
      db.from('fonctions').select('*').order('niveau'),
      db.from('territoires').select('id,nom,echelle').order('echelle').order('nom'),
      db.from('postes').select('code,nom').eq('actif',true).order('nom'),
      db.from('applications').select('code,nom').eq('actif',true).order('ordre')
    ]);
    setRef({fonctions:a.data||[], terr:b.data||[], postes:c.data||[], apps:d.data||[]});
  })(); }, []);

  if (!f) return html`<div class="vide">Chargement…</div>`;
  if (f.erreur) return html`<div class="alerte err">${f.erreur}</div>`;
  const i = f.identite;

  // Toute modification passe par modifier_membre() : la garde
  // hiérarchique et l'inscription au registre des actes y sont tenues.
  async function modifier(champ, valeur){
    const { data, error } = await db.rpc('modifier_membre',
      { p_profil: id, p_champ: champ, p_valeur: String(valeur) });
    if (error) return setLocal('Erreur : ' + error.message);
    if (!data.ok) return setLocal('Erreur : ' + data.message);
    setLocal('Enregistré. L\u2019acte est soumis au contrôle de l\u2019administrateur.');
    setTimeout(()=>setLocal(''), 4000);
    charger();
  }

  async function nommerA(e){
    e.preventDefault();
    const { data, error } = await db.rpc('nommer', {
      p_profil: id, p_poste: nouveauPoste.poste,
      p_territoire: nouveauPoste.territoire || null,
      p_fin: nouveauPoste.fin || null, p_motif: nouveauPoste.motif || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setNouveauPoste({poste:'', territoire:'', fin:'', motif:''});
    setMsg('Nomination enregistrée.'); charger();
  }

  async function revoquerPoste(n){
    const motif = prompt('Motif de la révocation (obligatoire)');
    if (!motif) return;
    const { data, error } = await db.rpc('revoquer',
      { p_nomination: n.nomination_id, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Nomination révoquée.'); charger();
  }

  async function ouvrirAcces(e){
    e.preventDefault();
    const { data, error } = await db.rpc('accorder_acces', {
      p_profil: id, p_app: nouvelAcces.app,
      p_motif: nouvelAcces.motif || null, p_expire: nouvelAcces.expire || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setNouvelAcces({app:'', motif:'', expire:''});
    setMsg('Accès ouvert.'); charger();
  }

  async function ouvrirDirect(app){
    const motif = prompt('Motif de l\u2019ouverture (facultatif)') || '';
    const { data, error } = await db.rpc('accorder_acces',
      { p_profil: id, p_app: app, p_motif: motif, p_expire: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Accès ouvert.'); charger();
  }

  async function fermerAcces(a){
    const motif = prompt('Motif de la révocation (obligatoire)');
    if (!motif) return;
    const { data, error } = await db.rpc('revoquer_acces',
      { p_profil: id, p_app: a.application, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Accès révoqué.'); charger();
  }

  const c = f.completude;

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Tous les membres</button>

      <div class="row" style="margin-top:16px;gap:18px;align-items:flex-start">
        <${Portrait} chemin=${i.photo_url} nom=${[i.prenom,i.nom].join(' ')} taille=${72} />
        <div style="flex:1;min-width:220px">
          <h1 style="font-size:29px">${[i.prenom,i.nom].filter(Boolean).join(' ') || i.matricule}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${i.matricule}</span> · ${i.email}
            ${i.telephone ? ' · ' + i.telephone : ''}
          </div>
          <div class="row" style="margin-top:10px;gap:6px">
            <span class="tag or">${f.points.total} points</span>
            <span class=${'tag '+(i.statut==='actif'?'vert':i.statut==='suspendu'?'rouge':'')}>
              ${i.statut.replace('_',' ')}</span>
            ${i.protege && html`<span class="tag or">Dossier protégé</span>`}
            ${i.sous_suivi && html`<span class="tag rouge">Sous suivi</span>`}
            ${f.dossiers.ouverts > 0 && html`
              <span class="tag rouge">${f.dossiers.ouverts} dossier(s) en cours</span>`}
          </div>
        </div>
      </div>
      ${local && html`<div class="alerte ok" style="margin-top:16px">${local}</div>`}

      ${!c.complet && html`
        <div class="alerte" style="margin-top:24px;border-left-color:var(--brun)">
          Dossier d\u2019adhésion à ${c.pourcent} %. Manque : ${c.manques.join(', ')}.
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Position dans la fédération</h3></div>
        <div class="corps stack">
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:190px;margin:0"><label>Fonction</label>
              <select value=${i.fonction} onChange=${e=>modifier('fonction', e.target.value)}>
                ${ref.fonctions.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:190px;margin:0"><label>Territoire</label>
              <select value=${i.territoire_id||''}
                onChange=${e=>modifier('territoire_id', e.target.value||null)}>
                <option value="">—</option>
                ${ref.terr.map(t => html`<option value=${t.id}>${t.nom} (${t.echelle})</option>`)}
              </select></div>
          </div>
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:130px;margin:0"><label>Échelon</label>
              <select value=${i.echelon}
                onChange=${e=>modifier('echelon', Number(e.target.value))}>
                ${[1,2,3,4,5,6,7].map(n => html`<option value=${n}>${n}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Statut</label>
              <select value=${i.statut} onChange=${e=>modifier('statut', e.target.value)}>
                ${['en_attente','actif','suspendu','archive'].map(x =>
                  html`<option value=${x}>${x.replace('_',' ')}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:170px;margin:0"><label>Protection</label>
              <select value=${i.protege ? 'oui':'non'}
                onChange=${e=>modifier('protege', e.target.value==='oui')}>
                <option value="non">Normale</option>
                <option value="oui">Renforcée — consultations tracées</option>
              </select></div>
          </div>
          <p class="small muted">
            ${i.chemin || 'Sans rattachement'} · membre depuis ${jour(i.cree_le)}
            ${i.date_adhesion ? ' · adhésion au ' + jour(i.date_adhesion) : ''}
          </p>
        </div>
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Postes occupés</h3>
          <span class="tag">${f.postes.length}</span></div>
        ${f.postes.length === 0
          ? html`<div class="corps small muted">Aucun mandat en cours.</div>`
          : f.postes.map(x => html`
            <div class="ligne">
              <div>
                <div class="row" style="gap:8px">
                  <span class=${'tag '+(x.couleur==='neutre'?'':x.couleur)}>${x.nom}</span>
                </div>
                <div class="small muted" style="margin-top:4px">
                  ${x.territoire || 'National'} · depuis le ${jour(x.debut)}
                  ${x.fin ? ' · jusqu\u2019au ' + jour(x.fin) : ' · sans terme'}
                </div>
              </div>
              <button class="btn sm light" onClick=${()=>revoquerPoste(x)}>Révoquer</button>
            </div>`)}
        <form onSubmit=${nommerA} class="corps"
          style="border-top:1px solid var(--filet)">
          <div class="row" style="gap:12px;align-items:flex-end">
            <div class="field" style="flex:1;min-width:170px;margin:0"><label>Nommer à</label>
              <select required value=${nouveauPoste.poste}
                onChange=${e=>setNouveauPoste(o=>({...o,poste:e.target.value}))}>
                <option value="">Choisir…</option>
                ${ref.postes.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Périmètre</label>
              <select value=${nouveauPoste.territoire}
                onChange=${e=>setNouveauPoste(o=>({...o,territoire:e.target.value}))}>
                <option value="">National</option>
                ${ref.terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
              </select></div>
            <div class="field" style="flex:0 0 150px;margin:0"><label>Fin</label>
              <input type="date" value=${nouveauPoste.fin}
                onInput=${e=>setNouveauPoste(o=>({...o,fin:e.target.value}))} /></div>
            <button class="btn sm">Nommer</button>
          </div>
        </form>
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <div class="row" style="gap:8px">
            <h3 style="font-size:17px">Tous les accès numériques</h3>
            <${Info} texte="Un accès vient de trois sources : la fonction (par la matrice), un poste occupé, ou un octroi nominatif. Seuls les octrois nominatifs se retirent ici — les deux autres se règlent en changeant la fonction ou le poste." />
          </div>
          <span class="tag">${tous.filter(a=>a.ouvert).length} ouverts</span>
        </div>
        ${tous.map(a => html`
          <div class="ligne">
            <div style="flex:1;min-width:230px">
              <div class="row" style="gap:8px">
                <span style=${a.ouvert?'':'color:var(--gris-bleu)'}>${a.nom}</span>
                <span class=${'tag '+(a.origine==='Octroi nominatif'?'bleu':
                  a.origine==='Poste occupé'?'or':a.origine==='Fonction'?'vert':'')}>
                  ${a.origine}</span>
              </div>
              <div class="small muted" style="margin-top:4px">
                ${a.detail}
                ${a.expire_le ? ' · expire le ' + jour(a.expire_le) : ''}
                ${a.ouvert ? (a.derniere_utilisation
                    ? ' · dernier usage ' + jour(a.derniere_utilisation)
                      + ' · ' + a.nb_ouvertures + ' ouverture(s)'
                    : ' · jamais utilisé') : ''}
              </div>
            </div>
            <div class="row">
              ${a.ouvert
                ? html`<span class="tag vert">Ouvert</span>`
                : html`<span class="tag">Fermé</span>`}
              ${a.retirable
                ? html`<button class="btn sm light"
                    onClick=${()=>fermerAcces({application:a.application, nom:a.nom})}>
                    Retirer</button>`
                : (!a.ouvert && html`<button class="btn sm light"
                    onClick=${()=>ouvrirDirect(a.application)}>Ouvrir</button>`)}
            </div>
          </div>`)}
        <form onSubmit=${ouvrirAcces} class="corps" style="border-top:1px solid var(--filet)">
          <div class="row" style="gap:12px;align-items:flex-end">
            <div class="field" style="flex:1;min-width:170px;margin:0"><label>Ouvrir</label>
              <select required value=${nouvelAcces.app}
                onChange=${e=>setNouvelAcces(o=>({...o,app:e.target.value}))}>
                <option value="">Choisir…</option>
                ${ref.apps.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Motif</label>
              <input value=${nouvelAcces.motif}
                onInput=${e=>setNouvelAcces(o=>({...o,motif:e.target.value}))} /></div>
            <div class="field" style="flex:0 0 150px;margin:0"><label>Expire le</label>
              <input type="date" value=${nouvelAcces.expire}
                onInput=${e=>setNouvelAcces(o=>({...o,expire:e.target.value}))} /></div>
            <button class="btn sm">Ouvrir</button>
          </div>
        </form>
      </div>

      <${MesDistinctions} profil=${id} />

      <div class="row" style="margin-top:24px;gap:24px;align-items:flex-start">
        <div class="panneau" style="flex:1;min-width:260px">
          <div class="tete"><h3 style="font-size:17px">Formations</h3></div>
          ${f.formations.length === 0
            ? html`<div class="corps small muted">Aucune certification.</div>`
            : f.formations.map(x => html`
              <div class="ligne"><span>${x.nom}</span>
                <span class="small muted">${jour(x.obtenue_le)}</span></div>`)}
        </div>
        <div class="panneau" style="flex:1;min-width:260px">
          <div class="tete"><h3 style="font-size:17px">Groupes de travail</h3></div>
          ${f.groupes.length === 0
            ? html`<div class="corps small muted">Aucun groupe.</div>`
            : f.groupes.map(x => html`
              <div class="ligne"><span>${x.nom}</span>
                ${x.role === 'responsable' && html`<span class="tag or">Responsable</span>`}</div>`)}
        </div>
      </div>
    </div>`;
}


/* --- Postes et droits, réunis ----------------------------------------- */
export function PostesEtDroits({ setMsg }){
  const [vue, setVue] = useState('postes');
  const [postes, setPostes] = useState([]);
  const [droits, setDroits] = useState([]);
  const [liens, setLiens] = useState([]);

  const charger = useCallback(async () => {
    const [a,b,c] = await Promise.all([
      db.from('postes').select('*').order('nom'),
      db.from('droits').select('*').order('ordre'),
      db.from('poste_droits').select('*')
    ]);
    setPostes(a.data||[]); setDroits(b.data||[]); setLiens(c.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  return html`
    <div>
      <div class="row" style="margin-bottom:20px;gap:10px">
        ${[['postes','Postes'],['matrice','Matrice des accès']].map(([k,t]) => html`
          <button class=${'btn sm '+(vue===k?'':'light')} onClick=${()=>setVue(k)}>${t}</button>`)}
      </div>
      ${vue === 'postes'  && html`<${Postes} postes=${postes} droits=${droits}
        liens=${liens} recharger=${charger} setMsg=${setMsg} />`}
      ${vue === 'matrice' && html`<${Matrice} setMsg=${setMsg} />`}
    </div>`;
}


/* --- Identité des applications ---------------------------------------- */
export function IdentiteApplications({ setMsg }){
  const [apps, setApps] = useState([]);
  const [dirs, setDirs] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [f, setF] = useState({});
  const [fichier, setFichier] = useState(null);

  const charger = useCallback(async () => {
    const [a, d] = await Promise.all([
      db.from('applications').select('*').eq('actif',true).order('ordre'),
      db.rpc('liste_directions')
    ]);
    setApps(a.data||[]); setDirs(d.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const TEINTES = { bleu:'Bleu profond', bordeaux:'Rouge bordeaux', nuit:'Bleu nuit',
                    brun:'Brun chaud', action:'Bleu vif', framboise:'Rose framboise' };
  const HEX = { bleu:'#00325B', bordeaux:'#A5053C', nuit:'#1E2A38',
                brun:'#6B4C3B', action:'#0045D1', framboise:'#E80855' };

  function editer(a){
    setOuvert(a.code);
    setF({nom:a.nom, nom_court:a.nom_court||'', description:a.description||'',
          accroche:a.accroche||'', couleur:a.couleur||'bleu', logo:a.logo||'',
          direction:a.direction||'', direction_locale:a.direction_locale||'',
          ordre:a.ordre});
    setFichier(null);
  }

  async function enregistrer(e, code){
    e.preventDefault();
    let logo = f.logo;
    try { if (fichier) logo = await deposerImage(fichier, 'apps'); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('regler_application', {
      p_code: code, p_nom: f.nom, p_nom_court: f.nom_court,
      p_description: f.description, p_accroche: f.accroche,
      p_couleur: f.couleur, p_logo: logo,
      p_direction: f.direction, p_direction_locale: f.direction_locale,
      p_ordre: Number(f.ordre) || 100
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setOuvert(null); setMsg('Application mise à jour.'); charger();
  }

  return html`
    <div>
      <p class="small muted" style="margin-bottom:20px;max-width:62ch">
        Chaque outil porte le nom que la fédération lui donne, se range sous la
        direction qu\u2019elle décide et dans l\u2019ordre qu\u2019elle choisit. Le second
        rangement, dit territorial, ne vaut que pour les échelons locaux :
        c\u2019est ainsi que le Pilotage se lit sous la Direction générale au
        national et sous Ma structure sur le terrain.
      </p>
      ${apps.map(a => html`
        <div class="panneau" style="margin-bottom:16px">
          <div class="tete">
            <div class="row" style="gap:12px">
              ${a.logo
                ? html`<img src=${urlPublique(a.logo)} alt=""
                    style="width:28px;height:28px;object-fit:contain" />`
                : html`<span style=${'width:14px;height:14px;border-radius:2px;background:'
                    +(HEX[a.couleur]||HEX.bleu)}></span>`}
              <div>
                <h3 style="font-size:17px">${a.nom_court || a.nom}</h3>
                <div class="small muted">${a.accroche || a.description || ''}</div>
              </div>
            </div>
            <button class="btn sm light" onClick=${()=>ouvert===a.code?setOuvert(null):editer(a)}>
              ${ouvert===a.code ? 'Annuler' : 'Personnaliser'}</button>
          </div>
          ${ouvert === a.code && html`
            <form onSubmit=${e=>enregistrer(e, a.code)} class="corps stack">
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:2;min-width:200px;margin:0"><label>Nom complet</label>
                  <input value=${f.nom} onInput=${e=>setF(o=>({...o,nom:e.target.value}))} /></div>
                <div class="field" style="flex:1;min-width:150px;margin:0"><label>Nom court</label>
                  <input value=${f.nom_court} placeholder="Sur la tuile"
                    onInput=${e=>setF(o=>({...o,nom_court:e.target.value}))} /></div>
              </div>
              <div class="field"><label>Accroche</label>
                <input value=${f.accroche} maxlength="90"
                  onInput=${e=>setF(o=>({...o,accroche:e.target.value}))} /></div>
              <div class="field"><label>Description</label>
                <textarea value=${f.description}
                  onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
              <div class="field"><label>Couleur</label>
                <select value=${f.couleur} onChange=${e=>setF(o=>({...o,couleur:e.target.value}))}>
                  ${Object.entries(TEINTES).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
                </select></div>
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:1;min-width:170px;margin:0">
                  <label>Direction (vue fédérale)</label>
                  <select value=${f.direction}
                    onChange=${e=>setF(o=>({...o,direction:e.target.value}))}>
                    <option value="">Mon activité — aucune direction</option>
                    ${dirs.map(d => html`<option value=${d.code}>${d.nom_court || d.nom}</option>`)}
                  </select></div>
                <div class="field" style="flex:1;min-width:170px;margin:0">
                  <label>Direction (vue territoriale)</label>
                  <select value=${f.direction_locale}
                    onChange=${e=>setF(o=>({...o,direction_locale:e.target.value}))}>
                    <option value="">Le même rangement pour tous</option>
                    ${dirs.map(d => html`<option value=${d.code}>${d.nom_court || d.nom}</option>`)}
                  </select></div>
                <div class="field" style="flex:0 0 110px;margin:0">
                  <label>Ordre</label>
                  <input type="number" min="1" value=${f.ordre}
                    onInput=${e=>setF(o=>({...o,ordre:e.target.value}))} /></div>
              </div>
              <div class="field"><label>Pictogramme</label>
                ${f.logo && html`<img src=${urlPublique(f.logo)} alt=""
                  style="width:44px;height:44px;object-fit:contain;display:block;margin-bottom:8px" />`}
                <input type="file" accept="image/png,image/svg+xml"
                  onChange=${e=>setFichier(e.target.files[0]||null)} />
                <p class="small muted" style="margin:6px 0 0">
                  PNG transparent ou SVG, carré. Le logo de la fédération ne se
                  décline pas : n\u2019utilisez pas ses éléments ici.</p>
              </div>
              <div><button class="btn">Enregistrer</button></div>
            </form>`}
        </div>`)}
    </div>`;
}

export function Postes({ postes, droits, liens, recharger, setMsg }){
  const [creation, setCreation] = useState(false);
  const [f, setF] = useState({code:'', nom:'', description:'', couleur:'neutre'});
  const [ouvert, setOuvert] = useState(null);

  async function creer(e){
    e.preventDefault();
    const code = f.code.trim().toLowerCase().replace(/[^a-z0-9_]/g,'_');
    const { error } = await db.from('postes').insert({
      code, nom: f.nom, description: f.description || null, couleur: f.couleur
    });
    if (error) return setMsg('Erreur : ' + error.message);
    setF({code:'', nom:'', description:'', couleur:'neutre'}); setCreation(false);
    setMsg('Poste créé. Cochez maintenant ses droits.'); recharger();
  }

  async function basculer(poste, droit, coche){
    if (coche)
      await db.from('poste_droits').insert({ poste, droit });
    else
      await db.from('poste_droits').delete().eq('poste', poste).eq('droit', droit);
    recharger();
  }

  async function desactiver(x){
    if (!confirm('Désactiver « ' + x.nom + ' » ? Les nominations en cours cessent de produire effet.')) return;
    await db.from('postes').update({ actif: !x.actif }).eq('code', x.code);
    recharger();
  }

  const categories = [...new Set(droits.map(d => d.categorie))];

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <span class="small muted">${postes.length} poste${postes.length>1?'s':''}</span>
        <button class="btn sm" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Créer un poste'}</button>
      </div>

      ${creation && html`
        <form onSubmit=${creer} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:200px;margin:0"><label>Nom</label>
                <input required value=${f.nom} onInput=${e=>setF(o=>({...o,nom:e.target.value}))}
                  placeholder="Référent laïcité" /></div>
              <div class="field" style="flex:1;min-width:160px;margin:0"><label>Identifiant</label>
                <input required value=${f.code} onInput=${e=>setF(o=>({...o,code:e.target.value}))}
                  placeholder="ref_laicite" /></div>
            </div>
            <div class="field"><label>À quoi sert ce poste</label>
              <textarea value=${f.description}
                onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
            <div class="field"><label>Couleur de l\u2019étiquette</label>
              <select value=${f.couleur} onChange=${e=>setF(o=>({...o,couleur:e.target.value}))}>
                <option value="neutre">Neutre</option><option value="or">Or</option>
                <option value="bleu">Bleu</option><option value="vert">Vert</option>
                <option value="rouge">Rouge</option>
              </select></div>
            <div><button class="btn">Créer</button></div>
          </div>
        </form>`}

      ${postes.map(x => {
        const siens = liens.filter(l => l.poste === x.code).map(l => l.droit);
        return html`
          <div class="panneau" style="margin-bottom:16px">
            <div class="tete">
              <div>
                <div class="row" style="gap:8px">
                  <h3 style="font-size:17px">${x.nom}</h3>
                  <span class=${'tag '+(x.couleur==='neutre'?'':x.couleur)}>${siens.length} droit${siens.length>1?'s':''}</span>
                  ${!x.actif && html`<span class="tag rouge">Désactivé</span>`}
                  ${x.systeme && html`<span class="tag">Fourni d\u2019origine</span>`}
                </div>
                ${x.description && html`<div class="small muted" style="margin-top:4px;max-width:60ch">
                  ${x.description}</div>`}
              </div>
              <div class="row">
                <button class="btn sm light" onClick=${()=>setOuvert(o => o===x.code?null:x.code)}>
                  ${ouvert===x.code ? 'Replier' : 'Droits'}</button>
                <button class="btn sm light" onClick=${()=>desactiver(x)}>
                  ${x.actif ? 'Désactiver' : 'Réactiver'}</button>
              </div>
            </div>
            ${ouvert === x.code && html`
              <div class="corps">
                ${categories.map(cat => html`
                  <div style="margin-bottom:20px">
                    <div class="eyebrow" style="margin-bottom:8px">${cat}</div>
                    ${droits.filter(d => d.categorie === cat).map(d => html`
                      <label class="row" style="text-transform:none;letter-spacing:0;
                          font-size:14px;color:var(--encre);padding:4px 0;margin:0;cursor:pointer">
                        <input type="checkbox" style="width:auto"
                          checked=${siens.includes(d.code)}
                          onChange=${e=>basculer(x.code, d.code, e.target.checked)} />
                        <span>${d.nom}</span>
                        ${d.sensible && html`<span class="tag or">Sensible</span>`}
                      </label>`)}
                  </div>`)}
              </div>`}
          </div>`;
      })}
    </div>`;
}


export function Communication({ p }){
  const [onglet, setOnglet] = useState('calendrier');
  const [pubs, setPubs] = useState([]);
  const [campagnes, setCampagnes] = useState([]);
  const [modeles, setModeles] = useState([]);
  const [edition, setEdition] = useState(null);
  const [msg, setMsg] = useState('');

  const valide = (p.postes||[]).some(x => x.nom.includes('communication')) || p.niveau >= 90;

  const charger = useCallback(async () => {
    const [a, b, c] = await Promise.all([
      db.rpc('calendrier_com', { p_depuis: null, p_jusqu: null }),
      db.from('campagnes').select('*').order('debut', {nullsFirst:false}),
      db.from('modeles_com').select('*').order('titre')
    ]);
    setPubs(a.data||[]); setCampagnes(b.data||[]); setModeles(c.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function statuer(pub, issue){
    const obs = issue === 'refusee' ? prompt('Ce qu\u2019il faut reprendre (obligatoire)') : null;
    if (issue === 'refusee' && !obs) return;
    const { data, error } = await db.rpc('statuer_publication',
      { p_id: pub.id, p_issue: issue, p_observation: obs });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Publication mise à jour.'); charger();
  }

  async function soumettre(pub){
    const { data, error } = await db.rpc('soumettre_publication', { p_id: pub.id });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Transmise à la direction de la communication.'); charger();
  }

  if (edition) return html`<${EditionPublication} p=${p} pub=${edition}
    campagnes=${campagnes} modeles=${modeles}
    fermer=${()=>{ setEdition(null); charger(); }} />`;

  const aValider = pubs.filter(x => x.statut === 'a_valider');
  const aVenir = pubs.filter(x => ['validee','a_valider','brouillon'].includes(x.statut)
    && x.date_prevue && new Date(x.date_prevue) >= new Date());

  const lignePub = x => html`
    <div class="ligne" style="align-items:flex-start">
      ${x.image && html`<img src=${urlPublique(x.image)} alt=""
        style="width:64px;height:64px;object-fit:cover;border:1px solid var(--filet);
               border-radius:2px;flex:0 0 64px" />`}
      <div style="flex:1;min-width:220px;cursor:pointer" onClick=${()=>setEdition(x)}>
        <div>${x.titre}</div>
        <div class="small muted">
          ${CANAUX[x.canal]||x.canal}
          ${x.campagne ? ' · ' + x.campagne : ''}
          ${x.date_prevue ? ' · ' + new Date(x.date_prevue).toLocaleString('fr-FR',
              {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}) : ' · sans date'}
          ${x.auteur ? ' · ' + x.auteur : ''}
        </div>
        ${x.observation && html`<div class="small" style="color:var(--bordeaux);margin-top:4px">
          ${x.observation}</div>`}
      </div>
      <div class="row">
        <span class=${'tag '+(ETAT_PUB[x.statut]||['',''])[1]}>
          ${(ETAT_PUB[x.statut]||[x.statut,''])[0]}</span>
        ${x.statut === 'brouillon' && html`
          <button class="btn sm light" onClick=${()=>soumettre(x)}>Soumettre</button>`}
        ${x.statut === 'a_valider' && valide && html`
          <button class="btn sm" onClick=${()=>statuer(x,'validee')}>Valider</button>
          <button class="btn sm light" onClick=${()=>statuer(x,'refusee')}>À reprendre</button>`}
        ${x.statut === 'validee' && valide && html`
          <button class="btn sm" onClick=${()=>statuer(x,'publiee')}>Marquer publiée</button>`}
      </div>
    </div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Communication</div>
          <h1 style="margin:6px 0 0">Calendrier éditorial</h1>
        </div>
        <button class="btn" onClick=${()=>setEdition({nouveau:true})}>
          Nouvelle publication</button>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:32px">${aValider.length}</div>
          <div class="l">À valider</div></div>
        <div><div class="n" style="font-size:32px">${aVenir.length}</div>
          <div class="l">À venir</div></div>
        <div><div class="n" style="font-size:32px">
          ${pubs.filter(x=>x.statut==='publiee').length}</div>
          <div class="l">Publiées</div></div>
        <div><div class="n" style="font-size:32px">
          ${campagnes.filter(c=>c.statut==='en_cours').length}</div>
          <div class="l">Campagnes en cours</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['calendrier','Calendrier'],['valider','À valider'],
           ['suggestions','Suggestions au réseau'],['campagnes','Campagnes'],
           ['modeles','Modèles'],['charte','La charte']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'calendrier' && html`
        <div class="panneau">
          ${pubs.length === 0
            ? html`<div class="vide">Aucune publication. Commencez par en créer une.</div>`
            : pubs.map(lignePub)}
        </div>`}

      ${onglet === 'valider' && html`
        <div class="panneau">
          ${aValider.length === 0
            ? html`<div class="vide">Rien à valider.</div>`
            : aValider.map(lignePub)}
        </div>`}

      ${onglet === 'suggestions' && html`<${SuggestionsAdmin} setMsg=${setMsg} />`}

      ${onglet === 'campagnes' && html`<${Campagnes} valide=${valide}
        campagnes=${campagnes} recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'modeles' && html`
        <div>
          <p class="small muted" style="margin-bottom:16px;max-width:62ch">
            Des trames éprouvées. On les copie, on les adapte : personne ne
            réécrit un communiqué de zéro à minuit.
          </p>
          ${modeles.map(m => html`
            <div class="panneau" style="margin-bottom:16px">
              <div class="tete">
                <h3 style="font-size:17px">${m.titre}</h3>
                <div class="row">
                  ${m.canal && html`<span class="tag">${CANAUX[m.canal]||m.canal}</span>`}
                  <button class="btn sm light" onClick=${()=>{
                    navigator.clipboard.writeText(m.contenu);
                    setMsg('Modèle copié.');
                  }}>Copier</button>
                </div>
              </div>
              <div class="corps">
                <pre style="white-space:pre-wrap;font-family:var(--sans);font-size:14px;
                     margin:0;background:var(--papier);padding:14px;border-radius:2px">${m.contenu}</pre>
                ${m.conseils && html`<p class="small muted" style="margin:12px 0 0">
                  ${m.conseils}</p>`}
              </div>
            </div>`)}
        </div>`}

      ${onglet === 'charte' && html`<${RappelCharte} />`}
    </div>`;
}

/* --- La charte, sous la main -------------------------------------------
   Une charte qu'il faut rouvrir en PDF n'est pas appliquée.

   --------------------------------------------------------------------- */
export function RappelCharte(){
  const couleurs = [
    ['#00325B','Bleu profond','Couleur maîtresse. Identité, titres, fonds institutionnels.'],
    ['#A5053C','Rouge bordeaux','Couleur maîtresse. Engagement, fraternité, accents forts.'],
    ['#1E2A38','Bleu nuit','Arrière-plans, texte courant.'],
    ['#0045D1','Bleu vif','Action seulement : boutons, liens, appels à l\u2019engagement.'],
    ['#E80855','Rose framboise','Chiffres-clés et mobilisation. Jamais dominant.'],
    ['#DDE6F0','Bleu ciel désaturé','Fonds subtils, encadrés discrets.'],
    ['#6B4C3B','Brun chaud','Chaleur, contextes particuliers.'],
    ['#4B4F56','Gris anthracite','Sous-titres, légendes, métadonnées.'],
    ['#F5F5F5','Blanc cassé','Alternative douce au blanc pur.']
  ];
  const regles = [
    'Le logo ne se modifie jamais : ni couleur, ni proportions, ni disposition.',
    'Zone de protection : la largeur du E de « FFCE » tout autour, libre de tout élément.',
    'Largeur minimale du logo : 150 pixels. En dessous, il devient illisible.',
    'Jamais de logo sur une image, un fond chargé, ou l\u2019une de ses propres couleurs.',
    'Raleway pour les titres — Black pour les principaux, Bold pour les sous-titres.',
    'Calibri pour le corps de texte. Les deux ne se mélangent jamais dans un même bloc.',
    'Interlignage : 130 à 150 % pour l\u2019écran, 120 à 130 % pour l\u2019imprimé.',
    'Aucun effet décoratif : pas d\u2019ombre portée, pas de contour, pas de dégradé.',
    'Marges claires, mise en page aérée.'
  ];
  return html`
    <div>
      <p class="intro" style="margin-bottom:24px">
        L\u2019essentiel de la charte, à portée de main. Elle s\u2019applique à tous
        les supports, imprimés comme numériques.
      </p>

      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Palette</h3></div>
        <div class="corps">
          ${couleurs.map(([hex, nom, usage]) => html`
            <div class="row" style="padding:8px 0;border-bottom:1px solid var(--filet);gap:14px">
              <span style=${'width:42px;height:42px;flex:0 0 42px;background:'+hex+
                ';border:1px solid var(--filet);border-radius:2px'}></span>
              <span style="flex:1;min-width:180px">
                <span style="display:block;font-family:var(--titre);font-weight:700">${nom}</span>
                <span class="small muted">${usage}</span>
              </span>
              <button class="btn sm light" onClick=${()=>navigator.clipboard.writeText(hex)}>
                <span class="mono">${hex}</span></button>
            </div>`)}
        </div>
      </div>

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Règles d\u2019usage</h3></div>
        <div class="corps">
          ${regles.map(r => html`
            <div style="padding:7px 0;border-bottom:1px solid var(--filet);font-size:14.5px">
              ${r}</div>`)}
        </div>
      </div>
    </div>`;
}


export function Campagnes({ valide, campagnes, recharger, setMsg }){
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({titre:'',objectif:'',debut:'',fin:''});

  async function creer(e){
    e.preventDefault();
    const { error } = await db.from('campagnes').insert({
      titre: f.titre, objectif: f.objectif || null,
      debut: f.debut || null, fin: f.fin || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    setF({titre:'',objectif:'',debut:'',fin:''}); setOuvert(false);
    setMsg('Campagne créée.'); recharger();
  }

  return html`
    <div>
      ${valide && html`
        <div class="spread" style="margin-bottom:16px">
          <span class="small muted">${campagnes.length} campagne${campagnes.length>1?'s':''}</span>
          <button class="btn sm" onClick=${()=>setOuvert(o=>!o)}>
            ${ouvert ? 'Annuler' : 'Nouvelle campagne'}</button>
        </div>`}
      ${ouvert && html`
        <form onSubmit=${creer} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Titre</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field"><label>Objectif</label>
              <textarea value=${f.objectif}
                onInput=${e=>setF(o=>({...o,objectif:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Début</label>
                <input type="date" value=${f.debut}
                  onInput=${e=>setF(o=>({...o,debut:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Fin</label>
                <input type="date" value=${f.fin}
                  onInput=${e=>setF(o=>({...o,fin:e.target.value}))} /></div>
            </div>
            <div><button class="btn">Créer</button></div>
          </div>
        </form>`}
      <div class="panneau">
        ${campagnes.length === 0
          ? html`<div class="vide">Aucune campagne.</div>`
          : campagnes.map(c => html`
            <div class="ligne">
              <div><div>${c.titre}</div>
                <div class="small muted">${c.objectif||''}
                  ${c.debut ? ' · ' + jour(c.debut) : ''}
                  ${c.fin ? ' au ' + jour(c.fin) : ''}</div></div>
              <span class="tag">${c.statut.replace('_',' ')}</span>
            </div>`)}
      </div>
    </div>`;
}


export function EditionPublication({ p, pub, campagnes, modeles, fermer }){
  const neuf = !!pub.nouveau;
  const [f, setF] = useState({
    titre: pub.titre||'', canal: pub.canal||'instagram', texte: pub.texte||'',
    lien: pub.lien||'', campagne_id: pub.campagne_id||'',
    date_prevue: pub.date_prevue ? pub.date_prevue.slice(0,16) : '', image: pub.image||''
  });
  const [fichier, setFichier] = useState(null);
  const [msg, setMsg] = useState('');
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => { (async () => {
    if (neuf || !pub.id) return;
    const { data } = await db.from('publications').select('*').eq('id', pub.id).maybeSingle();
    if (data) setF({
      titre:data.titre, canal:data.canal, texte:data.texte||'', lien:data.lien||'',
      campagne_id:data.campagne_id||'', image:data.image||'',
      date_prevue: data.date_prevue ? data.date_prevue.slice(0,16) : ''
    });
  })(); }, [pub.id, neuf]);

  async function enregistrer(e){
    e.preventDefault(); setEnvoi(true); setMsg('');
    try {
      let image = f.image;
      if (fichier) image = await deposerImage(fichier, 'com');
      const corps = {
        titre: f.titre, canal: f.canal, texte: f.texte || null,
        lien: f.lien || null, campagne_id: f.campagne_id || null,
        date_prevue: f.date_prevue || null, image: image || null
      };
      if (neuf){
        const { error } = await db.from('publications')
          .insert({ ...corps, auteur_id: p.id });
        if (error) throw error;
      } else {
        const { error } = await db.from('publications').update(corps).eq('id', pub.id);
        if (error) throw error;
      }
      fermer();
    } catch (err){ setMsg(err.message || 'Enregistrement impossible.'); }
    setEnvoi(false);
  }

  const limites = { instagram:2200, x:280, linkedin:3000, facebook:5000 };
  const limite = limites[f.canal];

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Calendrier</button>
      <h1 style="font-size:28px;margin:12px 0 24px">
        ${neuf ? 'Nouvelle publication' : f.titre || 'Publication'}</h1>
      ${msg && html`<div class="alerte err" style="margin-bottom:16px">${msg}</div>`}

      <form onSubmit=${enregistrer} class="panneau">
        <div class="corps stack">
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:2;min-width:200px;margin:0"><label>Titre interne</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Canal</label>
              <select value=${f.canal} onChange=${e=>setF(o=>({...o,canal:e.target.value}))}>
                ${Object.entries(CANAUX).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
              </select></div>
          </div>

          <div class="field">
            <div class="spread" style="margin-bottom:6px">
              <label style="margin:0">Texte</label>
              ${limite && html`<span class=${'small '+(f.texte.length>limite?'':'muted')}
                style=${f.texte.length>limite?'color:var(--bordeaux)':''}>
                ${f.texte.length} / ${limite} signes</span>`}
            </div>
            <textarea value=${f.texte} style="min-height:180px"
              onInput=${e=>setF(o=>({...o,texte:e.target.value}))} />
          </div>

          ${modeles.length > 0 && html`
            <div class="field">
              <label>Partir d\u2019un modèle</label>
              <select value="" onChange=${e=>{
                const m = modeles.find(x => x.id === e.target.value);
                if (m) setF(o => ({...o, texte: m.contenu}));
              }}>
                <option value="">Choisir…</option>
                ${modeles.map(m => html`<option value=${m.id}>${m.titre}</option>`)}
              </select>
            </div>`}

          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:190px;margin:0"><label>Campagne</label>
              <select value=${f.campagne_id}
                onChange=${e=>setF(o=>({...o,campagne_id:e.target.value}))}>
                <option value="">Aucune</option>
                ${campagnes.map(c => html`<option value=${c.id}>${c.titre}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:190px;margin:0"><label>Date prévue</label>
              <input type="datetime-local" value=${f.date_prevue}
                onInput=${e=>setF(o=>({...o,date_prevue:e.target.value}))} /></div>
          </div>

          <div class="field"><label>Lien</label>
            <input type="url" value=${f.lien}
              onInput=${e=>setF(o=>({...o,lien:e.target.value}))} /></div>

          <div class="field"><label>Visuel</label>
            ${f.image && html`<img src=${urlPublique(f.image)} alt=""
              style="max-width:220px;display:block;margin-bottom:10px;
                     border:1px solid var(--filet);border-radius:2px" />`}
            <input type="file" accept="image/*"
              onChange=${e=>setFichier(e.target.files[0]||null)} />
            <p class="small muted" style="margin:6px 0 0">
              Cinq mégaoctets maximum. Aucun visage de mineur sans autorisation écrite.
            </p>
          </div>

          <div><button class="btn" disabled=${envoi}>
            ${envoi ? 'Enregistrement…' : 'Enregistrer'}</button></div>
        </div>
      </form>
    </div>`;
}


/* --- Dossier incomplet : on ne va pas plus loin ------------------------
   Ni un mur ni une fenêtre qu'on referme : la page qui suit la
   connexion, tant qu'il manque l'essentiel.


/* --- Intérim -------------------------------------------------------- */
export function Interims({ p, setMsg }){
  const [liste, setListe] = useState([]);
  const [gens, setGens] = useState([]);
  const [mesPostes, setMesPostes] = useState([]);
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({interimaire:'', poste:'', debut:'', fin:'', motif:''});

  const charger = useCallback(async () => {
    const [a,b] = await Promise.all([
      db.rpc('mes_interims'),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom')
        .eq('statut','actif').order('nom')
    ]);
    setListe(a.data||[]); setGens((b.data||[]).filter(x => x.id !== p.id));
    setMesPostes(p.postes || []);
  }, [p]);
  useEffect(() => { charger(); }, [charger]);

  async function confier(e){
    e.preventDefault();
    const { data, error } = await db.rpc('confier_interim', {
      p_interimaire: f.interimaire, p_poste: f.poste,
      p_debut: f.debut || null, p_fin: f.fin, p_motif: f.motif
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({interimaire:'', poste:'', debut:'', fin:'', motif:''}); setOuvert(false);
    setMsg('Intérim proposé. Il prendra effet dès acceptation.'); charger();
  }

  async function repondre(x, ok){
    const { data, error } = await db.rpc('repondre_interim', { p_id: x.id, p_accepte: ok });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(ok ? 'Intérim accepté.' : 'Intérim décliné.'); charger();
  }

  const proposes = liste.filter(x => x.statut === 'propose' && x.je_suis_interimaire);
  const codes = { propose:['Proposé','bleu'], en_cours:['En cours','vert'],
    a_venir:['À venir',''], echu:['Échu',''], clos:['Clos',''], refuse:['Décliné','rouge'] };

  return html`
    <div>
      <p class="small muted" style="margin-bottom:16px;max-width:62ch">
        Un intérim délègue un poste pour une durée limitée. L\u2019intérimaire
        exerce les droits du poste, mais il agit visiblement au nom du
        titulaire — et cela figure au registre. Six mois maximum : au-delà,
        il faut nommer.
      </p>

      ${proposes.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--action)">
          <div class="tete" style="border-bottom-color:var(--action)">
            <h3 style="font-size:17px">Un intérim vous est proposé</h3></div>
          ${proposes.map(x => html`
            <div class="ligne">
              <div>
                <div><strong>${x.poste_nom}</strong> au nom de ${x.titulaire}</div>
                <div class="small muted">Du ${jour(x.debut)} au ${jour(x.fin)}
                  · ${x.motif}</div>
              </div>
              <div class="row">
                <button class="btn sm" onClick=${()=>repondre(x,true)}>Accepter</button>
                <button class="btn sm light" onClick=${()=>repondre(x,false)}>Décliner</button>
              </div>
            </div>`)}
        </div>`}

      ${mesPostes.length > 0 && html`
        <div class="spread" style="margin-bottom:16px">
          <span class="small muted">Vous occupez ${mesPostes.length} poste${mesPostes.length>1?'s':''}</span>
          <button class="btn sm" onClick=${()=>setOuvert(o=>!o)}>
            ${ouvert ? 'Annuler' : 'Confier un intérim'}</button>
        </div>`}

      ${ouvert && html`
        <form onSubmit=${confier} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Poste à déléguer</label>
              <select required value=${f.poste}
                onChange=${e=>setF(o=>({...o,poste:e.target.value}))}>
                <option value="">Choisir…</option>
                ${mesPostes.map(x => html`<option value=${x.poste}>${x.nom}</option>`)}
              </select></div>
            <div class="field"><label>À qui</label>
              <select required value=${f.interimaire}
                onChange=${e=>setF(o=>({...o,interimaire:e.target.value}))}>
                <option value="">Choisir…</option>
                ${gens.map(g => html`<option value=${g.id}>
                  ${nomComplet(g)} — ${g.fonction_nom}</option>`)}
              </select></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0"><label>Du</label>
                <input type="date" value=${f.debut}
                  onInput=${e=>setF(o=>({...o,debut:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:150px;margin:0"><label>Au</label>
                <input type="date" required value=${f.fin}
                  onInput=${e=>setF(o=>({...o,fin:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Motif</label>
              <input required value=${f.motif}
                onInput=${e=>setF(o=>({...o,motif:e.target.value}))}
                placeholder="Congé, mission à l\u2019étranger, arrêt…" /></div>
            <div><button class="btn">Proposer</button></div>
          </div>
        </form>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Intérims</h3>
          <span class="tag">${liste.length}</span></div>
        ${liste.length === 0
          ? html`<div class="vide">Aucun intérim.</div>`
          : liste.map(x => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div>${x.poste_nom}</div>
                <div class="small muted">
                  ${x.interimaire} au nom de ${x.titulaire}
                  · du ${jour(x.debut)} au ${jour(x.fin)}
                  ${x.statut === 'en_cours' && x.jours_restants >= 0
                    ? ' · ' + x.jours_restants + ' jours restants' : ''}
                </div>
                <div class="small muted">${x.motif}</div>
              </div>
              <div class="row">
                <span class=${'tag '+(codes[x.statut]||['',''])[1]}>
                  ${(codes[x.statut]||[x.statut,''])[0]}</span>
                ${x.statut === 'en_cours' && !x.je_suis_interimaire && html`
                  <button class="btn sm light" onClick=${async ()=>{
                    await db.rpc('clore_interim', { p_id: x.id });
                    setMsg('Intérim clos.'); charger();
                  }}>Clore</button>`}
              </div>
            </div>`)}
      </div>
    </div>`;
}


/* --- Conformité des postes -------------------------------------------- */
export function ConformitePostes({ setMsg }){
  const [liste, setListe] = useState([]);
  useEffect(() => {
    db.rpc('postes_non_conformes').then(({data}) => setListe(data||[]));
  }, []);
  return html`
    <div>
      <p class="small muted" style="margin-bottom:16px;max-width:62ch">
        Un poste emporte des formations obligatoires. Cette liste montre qui ne
        les a pas encore suivies — et depuis combien de temps.
      </p>
      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Tous les titulaires sont à jour.</div>`
          : liste.map(x => html`
            <div class="ligne">
              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <strong>${x.membre}</strong>
                  <span class="tag">${x.poste_nom}</span>
                  ${x.delai_depasse && html`<span class="tag rouge">Délai dépassé</span>`}
                </div>
                <div class="small muted">
                  ${x.territoire || 'National'} · en poste depuis ${x.jours} jours
                </div>
                <div class="small" style="color:var(--bordeaux);margin-top:4px">
                  Manque : ${x.manquantes}
                </div>
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function Publier({ p }){
  const [liste, setListe] = useState([]);
  const [outils, setOutils] = useState([]);
  const [ouverte, setOuverte] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b] = await Promise.all([
      db.rpc('suggestions_disponibles'),
      db.from('outils_com').select('*').eq('actif',true).order('ordre')
    ]);
    setListe(a.data||[]); setOutils(b.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  if (ouverte) return html`<${Suggestion} s=${ouverte} outils=${outils}
    fermer=${()=>{ setOuverte(null); charger(); }} />`;

  const urgentes = liste.filter(x => x.priorite === 'urgente');
  const cats = [...new Set(outils.map(o => o.categorie))];
  const nomCat = { creation:'Créer', ressources:'Ressources', juridique:'Cadre juridique' };

  return html`
    <div>
      <div class="eyebrow">Publier localement</div>
      <h1 style="margin:6px 0 8px">Faire connaître nos actions</h1>
      <p class="muted" style="max-width:60ch">
        La direction de la communication prépare des publications prêtes à
        adapter. Remplissez les <span class="mono">[crochets]</span> avec ce qui
        s\u2019est passé chez vous, et publiez sur vos réseaux.
      </p>
      ${msg && html`<div class="alerte ok" style="margin-top:16px">${msg}</div>`}

      ${urgentes.length > 0 && html`
        <div class="alerte" style="margin-top:24px;border-left-color:var(--bordeaux)">
          ${urgentes.length} publication${urgentes.length>1?'s':''} à relayer sans délai.
        </div>`}

      <div class="tuiles" style="margin-top:24px">
        ${liste.length === 0
          ? html`<div class="tuile"><div class="vide">
              Aucune publication proposée pour l\u2019instant.</div></div>`
          : liste.map(x => html`
            <div class="tuile" style=${'min-height:auto;cursor:pointer;border-top:3px solid '+
                (x.priorite==='urgente'?'var(--bordeaux)':
                 x.priorite==='importante'?'var(--brun)':'var(--framboise)')}
              onClick=${()=>setOuverte(x)}>
              ${x.visuel && html`<img src=${urlPublique(x.visuel)} alt=""
                style="width:100%;height:120px;object-fit:cover;margin-bottom:12px;
                       border:1px solid var(--filet)" />`}
              <h3>${x.titre}</h3>
              ${x.contexte && html`<p style="margin-top:6px">${x.contexte}</p>`}
              <div class="row" style="margin-top:12px;gap:6px">
                ${(x.canaux||[]).map(c => html`
                  <span class="tag">${(RESEAUX[c]||[c])[0]}</span>`)}
              </div>
              <div class="small muted" style="margin-top:10px">
                ${x.a_publier_le ? 'À publier vers le ' + jour(x.a_publier_le) : ''}
                ${x.reprises > 0 ? ' · repris ' + x.reprises + ' fois' : ''}
              </div>
              ${x.je_lai_reprise && html`<div style="margin-top:8px">
                <span class="tag vert">Vous l\u2019avez publiée</span></div>`}
            </div>`)}
      </div>

      <h2 style="font-size:22px;margin:40px 0 16px">Vos outils</h2>
      ${cats.map(cat => html`
        <div class="panneau" style="margin-bottom:16px">
          <div class="tete"><h3 style="font-size:17px">${nomCat[cat]||cat}</h3></div>
          ${outils.filter(o => o.categorie === cat).map(o => html`
            <a class="ligne" href=${o.url}
              target=${o.url.startsWith('#') ? null : '_blank'} rel="noopener"
              style="color:var(--nuit)">
              <div>
                <div>${o.nom}${o.url.startsWith('#') ? '' : ' ↗'}</div>
                <div class="small muted">${o.description||''}</div>
              </div>
            </a>`)}
        </div>`)}
    </div>`;
}


export function Suggestion({ s, outils, fermer }){
  const [texte, setTexte] = useState(s.texte);
  const [msg, setMsg] = useState('');
  const [copie, setCopie] = useState(false);

  // Les crochets restants : ce qui n'a pas encore été personnalisé.
  const restants = (texte.match(/\[[^\]]+\]/g) || []);

  function copier(){
    navigator.clipboard.writeText(
      texte + (s.hashtags ? '\n\n' + s.hashtags : ''));
    setCopie(true);
    setTimeout(() => setCopie(false), 2500);
  }

  async function publier(canal){
    copier();
    const url = (RESEAUX[canal]||[])[1];
    if (url) window.open(url, '_blank', 'noopener');
    const { error } = await db.rpc('declarer_reprise', {
      p_suggestion: s.id, p_canal: canal, p_lien: null, p_observation: null });
    if (error) return setMsg('Erreur : ' + error.message);
    setMsg('Texte copié et publication enregistrée. Collez-le sur ' +
           (RESEAUX[canal]||[canal])[0] + '.');
  }

  const canva = s.lien_canva || (outils.find(o => o.nom.includes('Canva'))||{}).url;

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Toutes les publications</button>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:28px">${s.titre}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${s.reference}</span>
            ${s.auteur ? ' · ' + s.auteur : ''}
            ${s.a_publier_le ? ' · à publier vers le ' + jour(s.a_publier_le) : ''}
            ${s.reprises > 0 ? ' · repris ' + s.reprises + ' fois' : ''}
          </div>
        </div>
        ${s.priorite !== 'normale' && html`
          <span class=${'tag '+(s.priorite==='urgente'?'rouge':'or')}>
            ${s.priorite === 'urgente' ? 'Sans délai' : 'Important'}</span>`}
      </div>

      ${s.contexte && html`<div class="alerte" style="margin-top:20px">${s.contexte}</div>`}
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${s.visuel && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Le visuel</h3>
            <a class="btn sm light" href=${urlPublique(s.visuel)}
              download target="_blank" rel="noopener">Télécharger</a></div>
          <div class="corps">
            <img src=${urlPublique(s.visuel)} alt=""
              style="max-width:100%;border:1px solid var(--filet)" />
          </div>
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <div class="row" style="gap:8px">
            <h3 style="font-size:17px">Le texte, à adapter</h3>
            <${Info} texte="Remplacez chaque [crochet] par ce qui s'est passé chez vous. Une publication identique partout sonne faux ; celle qui parle de votre territoire touche vos voisins." />
          </div>
          ${restants.length > 0
            ? html`<span class="tag or">${restants.length} à remplir</span>`
            : html`<span class="tag vert">Prêt</span>`}
        </div>
        <div class="corps">
          <textarea value=${texte} style="min-height:230px;font-size:15px"
            onInput=${e=>setTexte(e.target.value)} />
          <div class="spread" style="margin-top:10px">
            <span class="small muted">
              ${texte.length} signes
              ${restants.length > 0
                ? ' · reste : ' + restants.slice(0,3).join(' ') +
                  (restants.length > 3 ? '…' : '')
                : ''}
            </span>
            <button class="btn sm light" onClick=${copier}>
              ${copie ? 'Copié' : 'Copier le texte'}</button>
          </div>
          ${s.hashtags && html`
            <div style="margin-top:14px;padding-top:14px;border-top:1px solid var(--filet)">
              <div class="eyebrow" style="margin-bottom:6px">Mots-clics</div>
              <div class="small mono">${s.hashtags}</div>
            </div>`}
        </div>
      </div>

      ${s.consignes && html`
        <div class="panneau" style="margin-top:24px;border-left:3px solid var(--bordeaux)">
          <div class="tete"><h3 style="font-size:17px">À ne pas oublier</h3></div>
          <div class="corps" style="white-space:pre-wrap">${s.consignes}</div>
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Publier</h3></div>
        <div class="corps">
          ${restants.length > 0 && html`
            <div class="alerte" style="margin-bottom:16px">
              Il reste ${restants.length} passage${restants.length>1?'s':''} entre
              crochets. Complétez-les avant de publier.
            </div>`}
          <div class="row" style="gap:10px">
            ${(s.canaux||[]).map(c => html`
              <button class="btn" onClick=${()=>publier(c)}>
                ${(RESEAUX[c]||[c])[0]}</button>`)}
          </div>
          <p class="small muted" style="margin:14px 0 0">
            Le texte est copié dans votre presse-papiers et le réseau s\u2019ouvre :
            il ne reste qu\u2019à coller. Votre publication est comptée, ce qui permet
            à la direction de savoir ce qui vit.
          </p>
          ${canva && html`
            <div style="margin-top:16px;padding-top:16px;border-top:1px solid var(--filet)">
              <a class="btn light" href=${canva} target="_blank" rel="noopener">
                Créer un visuel sur Canva ↗</a>
            </div>`}
        </div>
      </div>
    </div>`;
}


/* --- Suggestions, côté direction -------------------------------------- */
export function SuggestionsAdmin({ setMsg }){
  const [liste, setListe] = useState([]);
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({titre:'', contexte:'', texte:'', hashtags:'',
    consignes:'', priorite:'normale', publier_le:'', expire_le:'',
    canaux:['instagram','facebook','linkedin'], canva:''});
  const [fichier, setFichier] = useState(null);

  const charger = useCallback(() =>
    db.rpc('suivi_suggestions').then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  function basculerCanal(c){
    setF(o => ({...o, canaux: o.canaux.includes(c)
      ? o.canaux.filter(x => x !== c) : [...o.canaux, c]}));
  }

  async function creer(e){
    e.preventDefault();
    let visuel = null;
    try { if (fichier) visuel = await deposerImage(fichier, 'suggestions'); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('creer_suggestion', {
      p_titre: f.titre, p_contexte: f.contexte || null, p_texte: f.texte,
      p_canaux: f.canaux, p_visuel: visuel, p_canva: f.canva || null,
      p_hashtags: f.hashtags || null,
      p_publier_le: f.publier_le || null, p_expire_le: f.expire_le || null,
      p_consignes: f.consignes || null, p_priorite: f.priorite, p_territoire: null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'', contexte:'', texte:'', hashtags:'', consignes:'',
      priorite:'normale', publier_le:'', expire_le:'',
      canaux:['instagram','facebook','linkedin'], canva:''});
    setFichier(null); setOuvert(false);
    setMsg('Suggestion publiée auprès des équipes locales.'); charger();
  }

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <p class="small muted" style="margin:0;max-width:46ch">
          Préparez une publication ; chaque équipe locale l\u2019adaptera à son
          territoire. Écrivez entre <span class="mono">[crochets]</span> ce
          qu\u2019elle devra compléter.
        </p>
        <button class="btn" onClick=${()=>setOuvert(o=>!o)}>
          ${ouvert ? 'Annuler' : 'Nouvelle suggestion'}</button>
      </div>

      ${ouvert && html`
        <form onSubmit=${creer} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Titre</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))}
                placeholder="Journée nationale de la laïcité" /></div>
            <div class="field"><label>Pourquoi maintenant</label>
              <input value=${f.contexte}
                onInput=${e=>setF(o=>({...o,contexte:e.target.value}))}
                placeholder="Une ligne pour situer l\u2019enjeu." /></div>
            <div class="field"><label>Le texte</label>
              <textarea required value=${f.texte} style="min-height:180px"
                onInput=${e=>setF(o=>({...o,texte:e.target.value}))}
                placeholder=${'Le [date], la FFCE [territoire] était à [lieu]...'} /></div>
            <div class="field"><label>Mots-clics</label>
              <input value=${f.hashtags}
                onInput=${e=>setF(o=>({...o,hashtags:e.target.value}))}
                placeholder="#FFCE #Citoyenneté #ÉgalitéDesChances" /></div>
            <div class="field"><label>Canaux</label>
              <div class="row" style="gap:8px">
                ${Object.entries(RESEAUX).map(([k,v]) => html`
                  <button type="button"
                    class=${'btn sm '+(f.canaux.includes(k)?'':'light')}
                    onClick=${()=>basculerCanal(k)}>${v[0]}</button>`)}
              </div></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>À publier vers le</label>
                <input type="date" value=${f.publier_le}
                  onInput=${e=>setF(o=>({...o,publier_le:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Ne plus proposer après</label>
                <input type="date" value=${f.expire_le}
                  onInput=${e=>setF(o=>({...o,expire_le:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0">
                <label>Priorité</label>
                <select value=${f.priorite}
                  onChange=${e=>setF(o=>({...o,priorite:e.target.value}))}>
                  <option value="normale">Normale</option>
                  <option value="importante">Importante</option>
                  <option value="urgente">Sans délai</option>
                </select></div>
            </div>
            <div class="field"><label>Modèle Canva</label>
              <input type="url" value=${f.canva}
                onInput=${e=>setF(o=>({...o,canva:e.target.value}))}
                placeholder="https://www.canva.com/design/…" /></div>
            <div class="field"><label>Visuel</label>
              <input type="file" accept="image/*"
                onChange=${e=>setFichier(e.target.files[0]||null)} /></div>
            <div class="field"><label>À ne pas oublier</label>
              <textarea value=${f.consignes}
                onInput=${e=>setF(o=>({...o,consignes:e.target.value}))}
                placeholder="Aucun visage de mineur sans autorisation écrite. Ne pas modifier le logo." /></div>
            <div><button class="btn">Publier auprès des équipes</button></div>
          </div>
        </form>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Ce qui circule</h3>
          <span class="tag">${liste.length}</span></div>
        ${liste.length === 0
          ? html`<div class="vide">Aucune suggestion.</div>`
          : liste.map(x => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div class="row" style="gap:8px">
                  <span>${x.titre}</span>
                  ${x.priorite !== 'normale' && html`
                    <span class=${'tag '+(x.priorite==='urgente'?'rouge':'or')}>
                      ${x.priorite}</span>`}
                </div>
                <div class="small muted">
                  <span class="mono">${x.reference}</span> · ${jour(x.cree_le)}
                  ${x.a_publier_le ? ' · pour le ' + jour(x.a_publier_le) : ''}
                </div>
                ${x.territoires && html`<div class="small muted" style="margin-top:4px">
                  Repris par : ${x.territoires}
                  ${x.canaux_utilises ? ' — ' + x.canaux_utilises : ''}</div>`}
              </div>
              <div class="row">
                <span class=${'tag '+(x.reprises>0?'vert':'')}>
                  ${x.reprises} reprise${x.reprises>1?'s':''}</span>
                <span class="tag">${x.statut}</span>
              </div>
            </div>`)}
      </div>
    </div>`;
}


/* =====================================================================
   ÉDITEUR DE FORMATIONS
   Une formation en cours de rédaction ne doit jamais casser le
   parcours de quelqu'un : supprimer une leçon achevée est refusé,
   déplacer échange les rangs sans toucher à la progression acquise.


/* --- Direction générale : vérifications ------------------------------ */
export function Validation({ p }){
  const [attente, setAttente] = useState([]);
  const [demandes, setDemandes] = useState([]);
  const [signalements, setSignalements] = useState([]);
  const [alertes, setAlertes] = useState([]);
  const [actes, setActes] = useState([]);
  const [encadrants, setEncadrants] = useState([]);
  const [journal, setJournal] = useState(false);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    db.rpc('puis_je_lire_journal_pieces').then(({data}) => setJournal(!!data));
  }, []);

  const charger = useCallback(async () => {
    // La table demandes pointe deux fois vers profils (profil_id et
    // traite_par). On lit donc les deux séparément plutôt que de laisser
    // PostgREST deviner de quel lien il s'agit.
    const [a, d, sg, al, ac] = await Promise.all([
      db.from('v_annuaire').select('*').eq('statut','en_attente').order('cree_le'),
      db.from('demandes').select('*').in('statut',['ouverte','en_cours']).order('cree_le'),
      db.rpc('signalements_a_traiter'),
      db.rpc('alertes_consultation'),
      db.rpc('actes_a_controler')
    ]);
    setActes(ac.data || []);
    setSignalements(sg.data || []);
    setAlertes(al.data || []);
    const { data: enc } = await db.from('v_annuaire')
      .select('id,prenom,nom,fonction_nom,niveau').eq('statut','actif').gte('niveau', 50)
      .order('niveau', { ascending: false });
    setEncadrants(enc || []);
    if (d.error) setMsg('Lecture des demandes impossible : ' + d.error.message);
    const dem = d.data || [];

    let auteurs = {};
    if (dem.length){
      const ids = [...new Set(dem.map(x => x.profil_id))];
      const { data: ps } = await db.from('v_annuaire')
        .select('id,prenom,nom,matricule,email,fonction_nom,territoire_nom').in('id', ids);
      auteurs = Object.fromEntries((ps||[]).map(x => [x.id, x]));
    }
    setAttente(a.data || []);
    setDemandes(dem.map(x => ({ ...x, auteur: auteurs[x.profil_id] || null })));
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function validerMembre(id, ok, forcer){
    const { data, error } = await db.rpc('valider_inscription',
      { p_profil: id, p_accepter: ok, p_forcer: !!forcer });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok){
      if (data.incomplet){
        if (confirm(data.message + '\n\nActiver quand même ? Le forçage sera inscrit au journal.'))
          return validerMembre(id, true, true);
        return setMsg(data.message);
      }
      return setMsg('Erreur : ' + data.message);
    }
    setMsg(ok ? 'Compte activé.' : 'Compte écarté.');
    charger();
  }

  async function controler(x, confirmer){
    const obs = confirmer ? null : prompt('Motif de l\u2019annulation (facultatif)');
    if (!confirmer && obs === null) return;
    const { data, error } = await db.rpc('controler_acte',
      { p_acte: x.id, p_confirmer: confirmer, p_observation: obs });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(confirmer ? 'Acte validé.' : 'Acte annulé, état antérieur rétabli.');
    charger();
  }

  const motifLisible = {
    propos_deplaces:'Propos déplacés', harcelement:'Harcèlement',
    securite:'Situation préoccupante', hors_sujet:'Usage hors mission', autre:'Autre'
  };

  async function confier(sg, a){
    const { data, error } = await db.rpc('confier_signalement',
      { p_sig: sg.id, p_a: a });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setMsg(a ? 'Signalement confié. L\u2019encadrant a désormais accès à cette conversation.'
             : 'Signalement repris par la Direction générale.');
    charger();
  }

  // Export du registre des adhésions. Réservé au droit membres.exporter,
  // et tracé comme toute sortie massive de données personnelles.
  async function exporterAdhesions(){
    const { data, error } = await db.rpc('registre_adhesions');
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data || data.length === 0)
      return setMsg('Erreur : accès refusé ou registre vide.');
    const cols = Object.keys(data[0]);
    const ech = v => {
      if (v === null || v === undefined) return '';
      const t = String(v).replace(/"/g, '""');
      return /[";\n]/.test(t) ? '"' + t + '"' : t;
    };
    const csv = '\ufeff' + cols.join(';') + '\n' +
      data.map(l => cols.map(c => ech(l[c])).join(';')).join('\n');
    const nom = 'FFCE-registre-adhesions-' + new Date().toISOString().slice(0,10) + '.csv';
    const url = URL.createObjectURL(new Blob([csv], {type:'text/csv;charset=utf-8'}));
    const a = document.createElement('a');
    a.href = url; a.download = nom; a.click();
    URL.revokeObjectURL(url);
    await db.rpc('tracer_export', { p_objet: nom, p_lignes: data.length });
    setMsg(data.length + ' adhésion(s) extraites. Déposez le fichier sur le Drive.');
  }

  async function ouvrirDossier(sg){
    const cible = prompt(
      'Identifiant du membre mis en cause (copiez-le depuis l\u2019annuaire), ' +
      'ou laissez vide pour ouvrir le dossier sur l\u2019auteur du signalement.');
    const objet = prompt('Objet du dossier (obligatoire)');
    if (!objet) return;
    const { data, error } = await db.rpc('ouvrir_dossier', {
      p_profil: cible || sg.id, p_objet: objet,
      p_qualification: null, p_gravite: 'moyenne', p_signalement: sg.id
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Dossier ouvert. Poursuivez dans Discipline et recours.');
    charger();
  }

  async function clore(sg, fonde){
    const decision = prompt(fonde
      ? 'Décision et suite donnée (obligatoire)'
      : 'Motif du classement sans suite (obligatoire)');
    if (!decision) return;
    const { data, error } = await db.rpc('clore_signalement',
      { p_sig: sg.id, p_fonde: fonde, p_decision: decision });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setMsg('Signalement clos.');
    charger();
  }

  async function traiter(d, ok){
    const motif = prompt(ok ? "Motif de l'accord (facultatif)" : 'Motif du refus') ;
    if (!ok && motif === null) return;
    const { data:{ user } } = await db.auth.getUser();
    await db.from('demandes').update({
      statut: ok ? 'acceptee' : 'refusee',
      traite_par: user.id, traite_le: new Date().toISOString(),
      motif_reponse: motif || null
    }).eq('id', d.id);

    if (ok && d.type === 'acces_application' && d.cible){
      await db.from('acces_applications').upsert({
        profil_id: d.profil_id, application: d.cible,
        statut: 'accorde', accorde_par: user.id, motif: motif || null
      }, { onConflict: 'profil_id,application' });
    }
    setMsg('Demande traitée.');
    charger();
  }

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Direction générale</div>
          <h1 style="margin:6px 0 0">Vérifications</h1>
        </div>
        <button class="btn light" onClick=${exporterAdhesions}>
          Extraire le registre des adhésions</button>
      </div>
      <div style="height:32px"></div>
      ${msg && html`<div class="alerte ok" style="margin-bottom:24px">${msg}</div>`}

      <${AssistanceAdmin} setMsg=${setMsg} />

      ${journal && html`<div style="margin-bottom:24px">
        <${JournalPieces} setMsg=${setMsg} /></div>`}

      ${actes.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--brun)">
          <div class="tete" style="border-bottom-color:var(--brun)">
            <div class="row" style="gap:8px">
              <h3 style="font-size:17px">Actes à contrôler</h3>
              <${Info} texte="Ces actes ont déjà pris effet : on ne bloque pas le réseau en attendant une signature. Vous les confirmez, ou vous les annulez — et l'état antérieur est rétabli." />
            </div>
            <span class="tag or">${actes.length}</span>
          </div>
          <div style="overflow-x:auto">
            <table>
              <thead><tr><th>Quand</th><th>Qui</th><th>Sur qui</th>
                <th>Acte</th><th></th></tr></thead>
              <tbody>
                ${actes.map(x => html`
                  <tr>
                    <td class="small muted">${new Date(x.cree_le).toLocaleString('fr-FR',
                      {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</td>
                    <td><div>${x.auteur}</div>
                      <div class="small muted">${x.auteur_fonction}</div></td>
                    <td><div>${x.cible || '—'}</div>
                      <div class="mono muted">${x.cible_matricule || ''}</div></td>
                    <td class="small">${x.libelle}</td>
                    <td>
                      <div class="row" style="justify-content:flex-end">
                        <button class="btn sm" onClick=${()=>controler(x, true)}>Valider</button>
                        ${x.reversible
                          ? html`<button class="btn sm light"
                              onClick=${()=>controler(x, false)}>Annuler l\u2019acte</button>`
                          : html`<span class="tag">Non réversible</span>`}
                      </div>
                    </td>
                  </tr>`)}
              </tbody>
            </table>
          </div>
        </div>`}

      ${alertes.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--laiton)">
          <div class="tete" style="border-bottom-color:var(--laiton)">
            <h3 style="font-size:17px">Consultations de dossiers protégés</h3>
            <span class="tag or">${alertes.length}</span>
          </div>
          ${alertes.map(al => html`
            <div class="ligne">
              <div style="flex:1;min-width:240px">
                <div>${al.observateur_nom} a consulté le dossier de ${al.observe_nom}</div>
                <div class="small muted">
                  ${al.observateur_fonction}
                  · <span class="mono">${al.observe_matricule}</span>
                  · ${new Date(al.cree_le).toLocaleString('fr-FR',
                      {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}
                  ${al.contexte ? ' · ' + al.contexte : ''}
                </div>
              </div>
              <button class="btn sm light" onClick=${async ()=>{
                await db.rpc('marquer_alerte_vue', { p_id: al.id });
                charger();
              }}>Pris connaissance</button>
            </div>`)}
        </div>`}

      ${signalements.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--laiton)">
          <div class="tete" style="border-bottom-color:var(--laiton)">
            <h3 style="font-size:17px">Signalements</h3>
            <span class="tag or">${signalements.length}</span>
          </div>
          ${signalements.map(sg => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div>${motifLisible[sg.motif] || sg.motif}</div>
                <div class="small muted" style="margin-top:4px">
                  Signalé par ${sg.auteur_nom} <span class="mono">${sg.auteur_matricule}</span>
                  · ${jour(sg.cree_le)}
                </div>
                <div class="small muted">
                  Conversation entre ${sg.participants} · ${sg.nb_messages} message${sg.nb_messages>1?'s':''}
                </div>
                ${sg.details && html`<div class="small" style="margin-top:8px;max-width:56ch">
                  « ${sg.details} »</div>`}
                ${sg.assigne_nom && html`<div style="margin-top:8px">
                  <span class="tag bleu">Confié à ${sg.assigne_nom}</span></div>`}
              </div>
              <div class="stack" style="min-width:220px">
                <div class="field" style="margin:0">
                  <label>Confier à</label>
                  <select value=${sg.assigne_a || ''}
                    onChange=${e => confier(sg, e.target.value || null)}>
                    <option value="">Direction générale</option>
                    ${encadrants.map(x => html`<option value=${x.id}>
                      ${nomComplet(x)} — ${x.fonction_nom}</option>`)}
                  </select>
                </div>
                <div class="row">
                  <a class="btn sm light" href="#/espace/messagerie">Lire l'échange</a>
                  <button class="btn sm" onClick=${()=>ouvrirDossier(sg)}>Ouvrir un dossier</button>
                  <button class="btn sm light" onClick=${()=>clore(sg, true)}>Fondé</button>
                  <button class="btn sm light" onClick=${()=>clore(sg, false)}>Non fondé</button>
                </div>
              </div>
            </div>`)}
        </div>`}

      <div class="panneau">
        <div class="tete">
          <h3 style="font-size:17px">Inscriptions à vérifier</h3>
          <span class="tag">${attente.length}</span>
        </div>
        ${attente.length === 0
          ? html`<div class="vide">Aucune inscription en attente.</div>`
          : attente.map(m => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div>${nomComplet(m)} <span class="mono muted">${m.matricule}</span></div>
                <div class="small muted">${m.email} · ${m.territoire_nom || 'sans territoire'}
                  · inscrit le ${jour(m.cree_le)}</div>
                <${Completude} id=${m.id} />
                <${ApercuAdhesion} id=${m.id} />
              </div>
              <div class="row">
                <button class="btn sm" onClick=${()=>validerMembre(m.id,true)}>Activer</button>
                <button class="btn sm light" onClick=${()=>validerMembre(m.id,false)}>Écarter</button>
              </div>
            </div>`)}
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <h3 style="font-size:17px">Demandes d'accès</h3>
          <span class="tag">${demandes.length}</span>
        </div>
        ${demandes.length === 0
          ? html`<div class="vide">Aucune demande en instance.</div>`
          : demandes.map(d => html`
            <div class="ligne">
              <div>
                <div>${d.objet}</div>
                <div class="small muted">
                  ${d.auteur ? nomComplet(d.auteur) : 'Membre inconnu'}
                  <span class="mono">${d.auteur?.matricule||''}</span>
                  ${d.auteur?.territoire_nom ? ' · ' + d.auteur.territoire_nom : ''}
                  · ${jour(d.cree_le)}
                </div>
                ${d.message && html`<div class="small" style="margin-top:6px;max-width:56ch">
                  « ${d.message} »</div>`}
              </div>
              <div class="row">
                <button class="btn sm" onClick=${()=>traiter(d,true)}>Accorder</button>
                <button class="btn sm light" onClick=${()=>traiter(d,false)}>Refuser</button>
              </div>
            </div>`)}
      </div>
    </div>`;
}

/* --- Direction générale : le site public ------------------------------
   Textes, blocs répétables et actualités. Plus une ligne de contenu
   public n'est écrite dans le code.

   --------------------------------------------------------------------- */
export function VitrineAdmin(){
  const [onglet, setOnglet] = useState('textes');
  const [msg, setMsg] = useState('');
  return html`
    <div>
      <div class="eyebrow">Pilotage</div>
      <h1 style="margin:6px 0 8px">Site public</h1>
      <p class="muted" style="max-width:60ch">
        Tout ce que voient les visiteurs se règle ici. Aucun texte, aucun
        chiffre, aucune carte n\u2019est écrit dans le code.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="row" style="margin:32px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['textes','Textes et chiffres'],['blocs','Blocs de page'],
           ['articles','Actualités']].map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'textes'   && html`<${VitrineTextes} setMsg=${setMsg} />`}
      ${onglet === 'blocs'    && html`<${VitrineBlocs} setMsg=${setMsg} />`}
      ${onglet === 'articles' && html`<${VitrineArticles} setMsg=${setMsg} />`}
    </div>`;
}


export function VitrineTextes({ setMsg }){
  const [c, setC] = useState([]);
  const charger = useCallback(() =>
    db.from('contenus').select('*').order('section').order('ordre')
      .then(({data}) => setC(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(cle, valeur){
    const { error } = await db.from('contenus').update({ valeur }).eq('cle', cle);
    setMsg(error ? 'Erreur : ' + error.message : 'Texte publié.');
  }

  const sections = [...new Set(c.map(x => x.section))];
  const titre = { accueil:'Page d\u2019accueil', apparence:'Apparence et blocs',
                  association:'La fédération', chiffres:'Chiffres-clés',
                  contact:'Contact et réseaux', legal:'Mentions légales', general:'Général' };

  return html`
    <div>
      ${sections.map(sec => html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete"><h3 style="font-size:17px">${titre[sec]||sec}</h3></div>
          <div class="corps stack">
            ${c.filter(x => x.section === sec).map(x => html`
              <div class="field">
                <label>${x.libelle}</label>
                ${x.format === 'long'
                  ? html`<textarea defaultValue=${x.valeur}
                      onBlur=${e=>enregistrer(x.cle, e.target.value)} />`
                  : html`<input type=${x.format==='nombre'?'text':'text'}
                      defaultValue=${x.valeur}
                      onBlur=${e=>enregistrer(x.cle, e.target.value)} />`}
              </div>`)}
            <p class="small muted">Enregistré à la sortie du champ.</p>
          </div>
        </div>`)}
    </div>`;
}


export function VitrineBlocs({ setMsg }){
  const [blocs, setBlocs] = useState([]);
  const [page, setPage] = useState('accueil');
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({titre:'',contenu:'',type:'carte',lien:'',lien_texte:''});
  const [fichier, setFichier] = useState(null);

  const charger = useCallback(() =>
    db.from('blocs_vitrine').select('*').order('page').order('ordre')
      .then(({data}) => setBlocs(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  const PAGES = { accueil:'Accueil', association:'La fédération', actions:'Nos actions',
                  reseau:'Le réseau', rejoindre:'Nous rejoindre', contact:'Contact' };
  const TYPES = { carte:'Carte', chiffre:'Chiffre', citation:'Citation',
                  encart:'Encart', etape:'Étape' };

  async function ajouter(e){
    e.preventDefault();
    let image = null;
    try { image = fichier ? await deposerImage(fichier, 'vitrine') : null; }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const max = Math.max(0, ...blocs.filter(b => b.page === page).map(b => b.ordre));
    const { error } = await db.from('blocs_vitrine').insert({
      page, type: f.type, titre: f.titre, contenu: f.contenu || null,
      lien: f.lien || null, lien_texte: f.lien_texte || null,
      image, ordre: max + 10
    });
    if (error) return setMsg('Erreur : ' + error.message);
    setF({titre:'',contenu:'',type:'carte',lien:'',lien_texte:''});
    setFichier(null); setOuvert(false); setMsg('Bloc ajouté.'); charger();
  }

  async function modifier(b, champ, valeur){
    const { error } = await db.from('blocs_vitrine')
      .update({ [champ]: valeur, maj_le: new Date().toISOString() }).eq('id', b.id);
    setMsg(error ? 'Erreur : ' + error.message : 'Enregistré.');
    charger();
  }

  async function deplacer(b, sens){
    const memePage = blocs.filter(x => x.page === b.page).sort((a,c)=>a.ordre-c.ordre);
    const i = memePage.findIndex(x => x.id === b.id);
    const j = i + sens;
    if (j < 0 || j >= memePage.length) return;
    await db.from('blocs_vitrine').update({ ordre: memePage[j].ordre }).eq('id', b.id);
    await db.from('blocs_vitrine').update({ ordre: b.ordre }).eq('id', memePage[j].id);
    charger();
  }

  async function retirer(b){
    if (!confirm('Supprimer « ' + b.titre + ' » ?')) return;
    await db.from('blocs_vitrine').delete().eq('id', b.id);
    setMsg('Bloc supprimé.'); charger();
  }

  const liste = blocs.filter(b => b.page === page);

  return html`
    <div>
      <div class="spread" style="margin-bottom:20px">
        <div class="field" style="margin:0;max-width:260px">
          <label>Page</label>
          <select value=${page} onChange=${e=>setPage(e.target.value)}>
            ${Object.entries(PAGES).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
          </select>
        </div>
        <button class="btn sm" onClick=${()=>setOuvert(o=>!o)}>
          ${ouvert ? 'Annuler' : 'Ajouter un bloc'}</button>
      </div>

      ${ouvert && html`
        <form onSubmit=${ajouter} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:2;min-width:200px;margin:0"><label>Titre</label>
                <input required value=${f.titre}
                  onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Type</label>
                <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
                  ${Object.entries(TYPES).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
                </select></div>
            </div>
            <div class="field"><label>Contenu</label>
              <textarea value=${f.contenu}
                onInput=${e=>setF(o=>({...o,contenu:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:180px;margin:0"><label>Lien</label>
                <input value=${f.lien} placeholder="#/actions"
                  onInput=${e=>setF(o=>({...o,lien:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:180px;margin:0"><label>Texte du lien</label>
                <input value=${f.lien_texte}
                  onInput=${e=>setF(o=>({...o,lien_texte:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Image</label>
              <input type="file" accept="image/*"
                onChange=${e=>setFichier(e.target.files[0]||null)} /></div>
            <div><button class="btn">Ajouter</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Aucun bloc sur cette page.</div>`
          : liste.map((b, i) => html`
            <div class="ligne" style="align-items:flex-start">
              ${b.image && html`<img src=${urlPublique(b.image)} alt=""
                style="width:56px;height:56px;object-fit:cover;flex:0 0 56px;
                       border:1px solid var(--filet);border-radius:2px" />`}
              <div style="flex:1;min-width:220px">
                <input defaultValue=${b.titre} style="font-weight:700"
                  onBlur=${e=>modifier(b,'titre',e.target.value)} />
                <textarea defaultValue=${b.contenu||''} style="min-height:64px;margin-top:8px"
                  onBlur=${e=>modifier(b,'contenu',e.target.value)} />
                <div class="row" style="margin-top:8px;gap:6px">
                  <span class="tag">${TYPES[b.type]||b.type}</span>
                  <span class="mono muted">ordre ${b.ordre}</span>
                </div>
              </div>
              <div class="row">
                <button class="btn sm light" onClick=${()=>deplacer(b,-1)}
                  disabled=${i===0}>↑</button>
                <button class="btn sm light" onClick=${()=>deplacer(b,1)}
                  disabled=${i===liste.length-1}>↓</button>
                <button class="btn sm light"
                  onClick=${()=>modifier(b,'publie',!b.publie)}>
                  ${b.publie ? 'Masquer' : 'Publier'}</button>
                <button class="btn sm light" onClick=${()=>retirer(b)}>Supprimer</button>
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function VitrineArticles({ setMsg }){
  const [liste, setListe] = useState([]);
  const [edition, setEdition] = useState(null);
  const [f, setF] = useState({titre:'',chapo:'',contenu:'',categorie:'Actualité',
                              publie:false, image:''});
  const [fichier, setFichier] = useState(null);

  const charger = useCallback(() =>
    db.from('articles').select('*').order('cree_le', {ascending:false})
      .then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  function ouvrir(a){
    setEdition(a || {nouveau:true});
    setF(a ? {titre:a.titre, chapo:a.chapo||'', contenu:a.contenu||'',
              categorie:a.categorie||'Actualité', publie:a.publie, image:a.image||''}
           : {titre:'',chapo:'',contenu:'',categorie:'Actualité',publie:false,image:''});
    setFichier(null);
  }

  async function enregistrer(e){
    e.preventDefault();
    let image = f.image;
    try { if (fichier) image = await deposerImage(fichier, 'articles'); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('enregistrer_article', {
      p_id: edition.nouveau ? null : edition.id,
      p_titre: f.titre, p_chapo: f.chapo || null, p_contenu: f.contenu || null,
      p_image: image || null, p_categorie: f.categorie, p_publie: f.publie
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setEdition(null); setMsg('Article enregistré.'); charger();
  }

  async function retirer(a){
    if (!confirm('Supprimer « ' + a.titre + ' » ?')) return;
    await db.from('articles').delete().eq('id', a.id);
    setMsg('Article supprimé.'); charger();
  }

  if (edition) return html`
    <div>
      <button class="lien-discret" onClick=${()=>setEdition(null)}>← Toutes les actualités</button>
      <form onSubmit=${enregistrer} class="panneau" style="margin-top:16px">
        <div class="corps stack">
          <div class="field"><label>Titre</label>
            <input required value=${f.titre}
              onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
          <div class="field"><label>Chapô</label>
            <textarea value=${f.chapo} style="min-height:70px"
              onInput=${e=>setF(o=>({...o,chapo:e.target.value}))} /></div>
          <div class="field"><label>Texte</label>
            <textarea value=${f.contenu} style="min-height:260px"
              onInput=${e=>setF(o=>({...o,contenu:e.target.value}))} /></div>
          <div class="field"><label>Catégorie</label>
            <input value=${f.categorie}
              onInput=${e=>setF(o=>({...o,categorie:e.target.value}))} /></div>
          <div class="field"><label>Image</label>
            ${f.image && html`<img src=${urlPublique(f.image)} alt=""
              style="max-width:260px;display:block;margin-bottom:10px;
                     border:1px solid var(--filet);border-radius:2px" />`}
            <input type="file" accept="image/*"
              onChange=${e=>setFichier(e.target.files[0]||null)} /></div>
          <label class="row" style="text-transform:none;letter-spacing:0;font-size:14px;
              color:var(--nuit);margin:0;cursor:pointer">
            <input type="checkbox" style="width:auto" checked=${f.publie}
              onChange=${e=>setF(o=>({...o,publie:e.target.checked}))} />
            <span>Publier sur le site</span>
          </label>
          <div><button class="btn">Enregistrer</button></div>
        </div>
      </form>
    </div>`;

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <span class="small muted">${liste.length} article${liste.length>1?'s':''}</span>
        <button class="btn sm" onClick=${()=>ouvrir(null)}>Nouvel article</button>
      </div>
      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Aucun article.</div>`
          : liste.map(a => html`
            <div class="ligne">
              ${a.image && html`<img src=${urlPublique(a.image)} alt=""
                style="width:56px;height:56px;object-fit:cover;flex:0 0 56px;
                       border:1px solid var(--filet);border-radius:2px" />`}
              <div style="flex:1;min-width:220px">
                <div>${a.titre}</div>
                <div class="small muted">${a.categorie}
                  ${a.publie_le ? ' · ' + jour(a.publie_le) : ' · non publié'}
                  · <span class="mono">/${a.slug}</span></div>
              </div>
              <div class="row">
                ${a.publie
                  ? html`<span class="tag vert">En ligne</span>`
                  : html`<span class="tag">Brouillon</span>`}
                <button class="btn sm light" onClick=${()=>ouvrir(a)}>Ouvrir</button>
                <button class="btn sm light" onClick=${()=>retirer(a)}>Supprimer</button>
              </div>
            </div>`)}
      </div>
    </div>`;
}


/* --- Coquille de l'espace membre ------------------------------------- */
export function EnAttente({ p }){
  return html`
    <section class="bloc blanc">
      <div class="wrap" style="max-width:560px">
        <div class="eyebrow">Espace membre</div>
        <h1 style="margin:8px 0 24px">Votre dossier est en cours de vérification</h1>
        <div class="alerte">
          La Direction générale vérifie votre inscription avant d'ouvrir vos accès.
          Vous recevrez un message dès qu'elle sera validée.
        </div>
        <div style="margin-top:32px">
          <${CarteFederale} p=${p} />
        </div>
        <p style="margin-top:32px">
          <a href="#/" onClick=${()=>db.auth.signOut()}>Se déconnecter</a>
        </p>
      </div>
    </section>`;
}

/* =====================================================================
   RESSOURCES ET MATÉRIEL
   Le pendant d'interface de la migration 28. Six volets, qui suivent le
   trajet réel d'un objet : on le choisit au catalogue, on le commande
   avec des points, on le reçoit, il entre à l'inventaire. Ce que le
   catalogue ne propose pas se demande en investissement, et passe alors
   par l'ordonnateur comme toute dépense.

   Aucun droit n'est vérifié ici : les fonctions de la base refusent
   elles-mêmes ce qui n'est pas permis, avec leurs propres mots. Les
   volets d'administration ne sont masqués que pour ne pas encombrer.


export function Cabinet({ p }){
  const [onglet, setOnglet] = useState('table');
  const [tb, setTb] = useState(null);
  const [remontees, setRemontees] = useState([]);
  const [actes, setActes] = useState([]);
  const [signataire, setSignataire] = useState(false);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a, b, c, s] = await Promise.all([
      db.rpc('tableau_cabinet'),
      db.rpc('remontees_du_cabinet', { p_filtre: 'ouvertes' }),
      db.rpc('recueil_actes', { p_filtre: 'tous' }),
      db.rpc('puis_je_signer_acte')
    ]);
    setTb(a.data); setRemontees(b.data || []); setActes(c.data || []);
    setSignataire(!!s.data);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return false; }
    setMsg(ok); charger(); return true;
  };

  if (!tb) return html`<div class="vide" style="padding:120px">Chargement…</div>`;

  const projets = actes.filter(a => a.statut === 'projet');
  const tabs = [['table','L\u2019état de la fédération'], ['remontees','Remontées'],
                ['actes','Actes'], ['rapport','Rapport d\u2019activité']];

  return html`
    <div>
      <div class="eyebrow">Cabinet de la présidence</div>
      <h1 style="margin:6px 0 8px">Tout remonte ici, tout en repart</h1>
      <p class="muted" style="max-width:62ch">
        Le réseau adresse à la présidence ce qu\u2019il veut porter à sa
        connaissance, à toute échelle et sans filtre. La présidence répond
        par des actes : visas, considérants, articles. Un acte se signe, se
        notifie, et reste au recueil, que tout adhérent peut lire.
        ${signataire
          ? ' Vous signez.'
          : ' Vous préparez les projets ; la présidence les signe.'}
      </p>

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet);
        flex-wrap:wrap">
        ${tabs.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--nuit)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>{setOnglet(k);setMsg('')}}>${t}${
              k==='remontees' && tb.remontees_ouvertes ? ' ('+tb.remontees_ouvertes+')' : ''}${
              k==='actes' && projets.length ? ' ('+projets.length+')' : ''}</button>`)}
      </div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-bottom:20px">${msg}</div>`}

      ${onglet === 'table' && html`<${CabinetEtat} tb=${tb} />`}
      ${onglet === 'remontees' && html`<${CabinetRemontees}
        remontees=${remontees} appel=${appel} />`}
      ${onglet === 'actes' && html`<${CabinetActes} p=${p} actes=${actes}
        projets=${projets} signataire=${signataire} appel=${appel} setMsg=${setMsg} />`}
      ${onglet === 'rapport' && html`<${Rapport} p=${p} />`}
    </div>`;
}


/* --- L'état de la fédération, vu d'en haut ------------------------------ */
export function CabinetEtat({ tb }){
  const alerte = (cond, texte, lien) => cond && html`
    <div class="ligne">
      <div style="flex:1;min-width:240px">${texte}</div>
      <a class="btn sm light" href=${lien}>Ouvrir</a>
    </div>`;

  return html`
    <div>
      <div class="chiffres" style="margin-bottom:28px">
        <div><div class="n" style="font-size:30px">${tb.adherents}</div>
          <div class="l">Adhérents actifs</div></div>
        <div><div class="n" style="font-size:30px">${tb.encadrants}</div>
          <div class="l">Encadrants</div></div>
        <div><div class="n" style="font-size:30px">${tb.structures}</div>
          <div class="l">Structures actives</div></div>
        <div><div class="n" style="font-size:30px">${tb.actes_en_vigueur}</div>
          <div class="l">Actes en vigueur</div></div>
      </div>

      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Ce qui appelle une décision</h3></div>
        ${alerte(tb.alertes > 0,
          tb.alertes + ' alerte(s) du réseau sans réponse.', '#/espace/cabinet')}
        ${alerte(tb.arbitrages > 0,
          tb.arbitrages + ' demande(s) d\u2019arbitrage en attente.', '#/espace/cabinet')}
        ${alerte(tb.sans_president > 0,
          tb.sans_president + ' structure(s) active(s) sans président. '
          + 'Une structure sans président n\u2019a personne pour la représenter.',
          '#/espace/pilotage')}
        ${alerte(tb.sans_tresorier > 0,
          tb.sans_tresorier + ' structure(s) sans trésorier : elles ne peuvent '
          + 'ni engager ni justifier une dépense.', '#/espace/pilotage')}
        ${alerte(tb.en_attente > 0,
          tb.en_attente + ' inscription(s) en attente de vérification.',
          '#/espace/validation')}
        ${alerte(tb.actes_a_controler > 0,
          tb.actes_a_controler + ' acte(s) sensible(s) à contrôler a posteriori.',
          '#/espace/validation')}
        ${alerte(tb.discipline_en_cours > 0,
          tb.discipline_en_cours + ' dossier(s) disciplinaire(s) en cours. '
          + 'Le cabinet en connaît le nombre, pas le contenu.', '#/espace/discipline')}
        ${(tb.alertes + tb.arbitrages + tb.sans_president + tb.sans_tresorier
           + tb.en_attente + tb.actes_a_controler + tb.discipline_en_cours) === 0
          && html`<div class="corps muted">Rien n\u2019appelle de décision aujourd\u2019hui.</div>`}
      </div>

      <p class="small muted" style="max-width:60ch">
        Le cabinet voit les nombres, pas les pièces. Les dossiers
        disciplinaires suivent leur circuit propre et les bulletins de vote
        n\u2019ont aucune politique de lecture : rien ici ne les ouvre.
      </p>
    </div>`;
}


/* --- Les remontées du réseau -------------------------------------------- */
export function CabinetRemontees({ remontees, appel }){
  return html`
    <div class="panneau">
      <div class="tete"><h3 style="font-size:17px">Adressé à la présidence</h3>
        <span class="tag">${remontees.length}</span></div>
      ${remontees.length === 0
        ? html`<div class="corps muted">
            Rien en attente. Tout encadrant, à toute échelle, peut adresser au
            cabinet une information, une alerte, une proposition ou une demande
            d\u2019arbitrage depuis son tableau de bord.</div>`
        : remontees.map(r => html`
          <div class="ligne" key=${r.id} style="align-items:flex-start">
            <div style="flex:1;min-width:260px">
              <div class="row" style="gap:8px;flex-wrap:wrap">
                <span style="font-weight:600">${r.objet}</span>
                <span class=${'tag '+(r.nature==='alerte'?'rouge'
                  :r.nature==='arbitrage'?'or':'')}>
                  ${NATURE_REMONTEE[r.nature] || r.nature}</span>
              </div>
              <div class="small muted" style="margin-top:3px">
                ${r.auteur} · ${r.auteur_fonction} · ${r.territoire} · ${jour(r.cree_le)}
              </div>
              <div class="small" style="margin-top:6px">${r.corps}</div>
              ${r.lien && html`<div style="margin-top:6px">
                <a class="small" href=${r.lien}>Ouvrir l\u2019écran concerné</a></div>`}
            </div>
            <div class="row" style="gap:6px">
              <button class="btn sm" onClick=${()=>{
                const t = prompt('Réponse ou décision (obligatoire)');
                if (t) appel('traiter_remontee',
                  { p_id:r.id, p_statut:'arbitree', p_reponse:t }, 'Arbitrage enregistré.');
              }}>Arbitrer</button>
              <button class="btn sm light" onClick=${()=>appel('traiter_remontee',
                { p_id:r.id, p_statut:'classee', p_reponse:null }, 'Remontée classée.')}>
                Classer</button>
            </div>
          </div>`)}
    </div>`;
}


/* --- Préparer, signer, abroger ------------------------------------------ */
export function CabinetActes({ p, actes, projets, signataire, appel, setMsg }){
  const vierge = { type:'decision', objet:'', visas:'', considerants:'',
                   destinataire:'', poste:'', effet:'', territoire:'' };
  const [f, setF] = useState(vierge);
  const [articles, setArticles] = useState(['']);
  const [gens, setGens] = useState([]);
  const [postes, setPostes] = useState([]);
  const [terr, setTerr] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [texte, setTexte] = useState(null);
  const maj = (k,v) => setF(o => ({...o, [k]: v}));

  useEffect(() => {
    db.from('v_annuaire').select('id,prenom,nom,fonction_nom,territoire_nom')
      .eq('statut','actif').order('nom').then(({data}) => setGens(data||[]));
    db.from('postes').select('code,nom,rang').eq('actif',true)
      .order('rang',{ascending:false}).then(({data}) => setPostes(data||[]));
    db.from('territoires').select('id,nom,echelle').order('nom')
      .then(({data}) => setTerr(data||[]));
  }, []);

  async function enregistrer(e){
    e.preventDefault();
    const arts = articles.map(a => a.trim()).filter(Boolean);
    if (arts.length === 0)
      return setMsg('Erreur : un acte sans article ne décide rien.');
    const ok = await appel('prendre_acte', {
      p_type: f.type, p_objet: f.objet, p_visas: f.visas || null,
      p_considerants: f.considerants || null, p_articles: arts,
      p_destinataire: f.destinataire || null, p_poste: f.poste || null,
      p_effet: f.effet || null, p_territoire: f.territoire || null
    }, 'Projet d\u2019acte enregistré. Il ne produit effet qu\u2019à la signature.');
    if (ok){ setF(vierge); setArticles(['']); }
  }

  async function lire(a){
    if (ouvert === a.id){ setOuvert(null); setTexte(null); return; }
    const { data } = await db.rpc('texte_acte', { p_id: a.id });
    setOuvert(a.id); setTexte(data);
  }

  function telecharger(){
    if (!texte) return;
    const l = [];
    l.push('FÉDÉRATION FRANÇAISE POUR LA CITOYENNETÉ ET L\u2019ÉGALITÉ DES CHANCES');
    l.push('Présidence de la fédération');
    l.push(''); l.push(texte.reference);
    l.push((TYPE_ACTE[texte.type] || texte.type).toUpperCase());
    l.push(''); l.push(texte.objet);
    l.push('Portée : ' + texte.portee); l.push('');
    if (texte.visas){ l.push(texte.visas); l.push(''); }
    if (texte.considerants){ l.push(texte.considerants); l.push(''); }
    (texte.articles||[]).forEach((a,i) => { l.push('Article '+(i+1)+' — '+a); l.push(''); });
    l.push('Prend effet le ' + jour(texte.prend_effet_le)); l.push('');
    l.push((texte.signataire || texte.auteur) + ', ' + texte.auteur_fonction);
    l.push('Pour le secrétariat de la présidence.');
    const url = URL.createObjectURL(new Blob([l.join('\n')],
      { type:'text/plain;charset=utf-8' }));
    const el = document.createElement('a');
    el.href = url; el.download = texte.reference + '.txt'; el.click();
    URL.revokeObjectURL(url);
  }

  return html`
    <div>
      <form onSubmit=${enregistrer} class="panneau" style="margin-bottom:28px">
        <div class="tete"><h3 style="font-size:17px">Nouveau projet d\u2019acte</h3></div>
        <div class="corps stack">
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:170px;margin:0">
              <label>Nature</label>
              <select value=${f.type} onChange=${e=>maj('type', e.target.value)}>
                ${Object.entries(TYPE_ACTE).filter(([k]) => k !== 'abrogation')
                  .map(([k,v]) => html`<option value=${k}>${v}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:190px;margin:0">
              <label>Portée</label>
              <select value=${f.territoire} onChange=${e=>maj('territoire', e.target.value)}>
                <option value="">Toute la fédération</option>
                ${terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
              </select></div>
            <div class="field" style="flex:0 0 160px;margin:0">
              <label>Prend effet le</label>
              <input type="date" value=${f.effet}
                onInput=${e=>maj('effet', e.target.value)} /></div>
          </div>

          <div class="field"><label>Objet</label>
            <input value=${f.objet}
              placeholder="Nomination du référent départemental de la Haute-Garonne"
              onInput=${e=>maj('objet', e.target.value)} /></div>

          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:2;min-width:200px;margin:0">
              <label>${f.type === 'nomination'
                ? 'Personne nommée' : 'Destinataire (facultatif)'}</label>
              <select value=${f.destinataire}
                onChange=${e=>maj('destinataire', e.target.value)}>
                <option value="">— Aucun —</option>
                ${gens.map(g => html`<option value=${g.id}>
                  ${nomComplet(g)} · ${g.fonction_nom}${
                    g.territoire_nom ? ' · '+g.territoire_nom : ''}</option>`)}
              </select></div>
            ${f.type === 'nomination' && html`
              <div class="field" style="flex:1;min-width:190px;margin:0">
                <label>Poste conféré</label>
                <select value=${f.poste} onChange=${e=>maj('poste', e.target.value)}>
                  <option value="">— Choisir —</option>
                  ${postes.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
                </select></div>`}
          </div>

          <div class="field"><label>Visas</label>
            <textarea value=${f.visas} style="min-height:70px"
              placeholder="Vu les statuts de la fédération, vu la délibération du bureau du…"
              onInput=${e=>maj('visas', e.target.value)}></textarea></div>

          <div class="field"><label>Considérants</label>
            <textarea value=${f.considerants} style="min-height:70px"
              placeholder="Considérant que…"
              onInput=${e=>maj('considerants', e.target.value)}></textarea></div>

          <div class="field">
            <label>Articles</label>
            ${articles.map((a,i) => html`
              <div class="row" style="gap:10px;margin-bottom:8px;align-items:flex-start" key=${i}>
                <span class="mono muted small" style="padding-top:11px;white-space:nowrap">
                  Art. ${i+1}</span>
                <textarea value=${a} style="min-height:60px"
                  onInput=${e=>{const c=[...articles]; c[i]=e.target.value; setArticles(c)}}
                ></textarea>
                ${articles.length > 1 && html`
                  <button type="button" class="btn sm light"
                    onClick=${()=>setArticles(articles.filter((_,j)=>j!==i))}>—</button>`}
              </div>`)}
            <button type="button" class="btn sm light"
              onClick=${()=>setArticles([...articles,''])}>Ajouter un article</button>
          </div>

          <div><button class="btn">Enregistrer le projet</button></div>
        </div>
      </form>

      ${projets.length > 0 && html`
        <h3 style="font-size:17px;margin-bottom:12px">
          En attente de signature${signataire ? '' : ' de la présidence'}</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${projets.map(a => html`
            <div class="ligne" key=${a.id} style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span class="mono muted small">${a.reference}</span>
                  <span class="tag">${TYPE_ACTE[a.type] || a.type}</span>
                  <span class="tag">${a.portee}</span>
                </div>
                <div style="margin-top:4px">${a.objet}</div>
                ${a.destinataire && html`<div class="small muted" style="margin-top:3px">
                  ${a.destinataire}${a.poste_nom ? ' · ' + a.poste_nom : ''}</div>`}
                <div class="small muted" style="margin-top:3px">
                  Préparé par ${a.auteur}</div>
              </div>
              <div class="row" style="gap:6px">
                ${signataire && html`
                  <button class="btn sm" onClick=${()=>appel('signer_acte', { p_id:a.id },
                    'Acte signé. L\u2019intéressé en est informé par messagerie interne.')}>
                    Signer</button>`}
                <button class="btn sm light" onClick=${()=>{
                  const m = prompt('Motif du retrait du projet');
                  if (m) appel('abroger_acte', { p_id:a.id, p_motif:m }, 'Projet retiré.');
                }}>Retirer</button>
              </div>
            </div>`)}
        </div>`}

      <h3 style="font-size:17px;margin-bottom:12px">Recueil</h3>
      <${RecueilListe} actes=${actes.filter(a => a.statut !== 'projet')}
        ouvert=${ouvert} texte=${texte} lire=${lire} telecharger=${telecharger}
        abroger=${signataire ? (id) => {
          const m = prompt('Motif de l\u2019abrogation (obligatoire)');
          if (m) appel('abroger_acte', { p_id:id, p_motif:m },
            'Acte abrogé par un acte d\u2019abrogation, versé au recueil.');
        } : null} />
    </div>`;
}


/* --- Le recueil : la même liste pour le cabinet et pour les adhérents --- */
export function RecueilListe({ actes, ouvert, texte, lire, telecharger, abroger }){
  return html`
    <div class="panneau">
      <div class="tete"><h3 style="font-size:17px">Actes de la présidence</h3>
        <span class="tag">${actes.length}</span></div>
      ${actes.length === 0
        ? html`<div class="corps muted">Le recueil est vide.</div>`
        : actes.map(a => html`
          <div key=${a.id}>
            <div class="ligne" style="align-items:flex-start;cursor:pointer"
              onClick=${()=>lire(a)}>
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span class="mono muted small">${a.reference}</span>
                  <span class="tag">${TYPE_ACTE[a.type] || a.type}</span>
                  ${a.abroge
                    ? html`<span class="tag rouge">Abrogé</span>`
                    : html`<span class="tag vert">En vigueur</span>`}
                </div>
                <div style="margin-top:4px">${a.objet}</div>
                <div class="small muted" style="margin-top:3px">
                  ${a.portee}${a.prend_effet_le ? ' · effet le ' + jour(a.prend_effet_le) : ''}
                </div>
              </div>
              <span class="small muted">${ouvert === a.id ? 'Replier' : 'Lire'}</span>
            </div>
            ${ouvert === a.id && texte && html`
              <div class="corps" style="background:var(--papier);border-bottom:1px solid var(--filet)">
                <div class="spread" style="margin-bottom:16px">
                  <span class="eyebrow">${TYPE_ACTE[texte.type] || texte.type}
                    · ${texte.portee}</span>
                  <div class="row" style="gap:6px">
                    <button class="btn sm light" onClick=${telecharger}>Télécharger</button>
                    ${abroger && !a.abroge && html`
                      <button class="btn sm light"
                        onClick=${()=>abroger(a.id)}>Abroger</button>`}
                  </div>
                </div>
                ${texte.visas && html`<p style="font-style:italic;margin-bottom:12px">
                  ${texte.visas}</p>`}
                ${texte.considerants && html`<p style="margin-bottom:16px">
                  ${texte.considerants}</p>`}
                ${(texte.articles||[]).map((art,i) => html`
                  <p style="margin-bottom:10px" key=${i}>
                    <strong>Article ${i+1}</strong> — ${art}</p>`)}
                ${texte.destinataire && html`<div class="small muted" style="margin-top:12px">
                  Notifié à ${texte.destinataire}${texte.poste ? ' · ' + texte.poste : ''}</div>`}
                ${texte.motif_abrogation && html`
                  <div class="small" style="color:var(--rouge);margin-top:12px">
                    Abrogé : ${texte.motif_abrogation}</div>`}
                <div class="small muted" style="margin-top:16px">
                  ${texte.signataire || texte.auteur}, ${texte.auteur_fonction}
                  — pour le secrétariat de la présidence.
                </div>
              </div>`}
          </div>`)}
    </div>`;
}


/* --- Le recueil, application ouverte à tous ----------------------------- */
export function Recueil(){
  const [actes, setActes] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [texte, setTexte] = useState(null);

  useEffect(() => {
    db.rpc('recueil_actes', { p_filtre: 'en_vigueur' })
      .then(({data}) => setActes(data || []));
  }, []);

  async function lire(a){
    if (ouvert === a.id){ setOuvert(null); setTexte(null); return; }
    const { data } = await db.rpc('texte_acte', { p_id: a.id });
    setOuvert(a.id); setTexte(data);
  }
  function telecharger(){
    if (!texte) return;
    const l = ['FÉDÉRATION FRANÇAISE POUR LA CITOYENNETÉ ET L\u2019ÉGALITÉ DES CHANCES',
      'Présidence de la fédération', '', texte.reference,
      (TYPE_ACTE[texte.type] || texte.type).toUpperCase(), '', texte.objet,
      'Portée : ' + texte.portee, ''];
    if (texte.visas){ l.push(texte.visas); l.push(''); }
    if (texte.considerants){ l.push(texte.considerants); l.push(''); }
    (texte.articles||[]).forEach((a,i) => { l.push('Article '+(i+1)+' — '+a); l.push(''); });
    l.push('Prend effet le ' + jour(texte.prend_effet_le)); l.push('');
    l.push((texte.signataire || texte.auteur) + ', ' + texte.auteur_fonction);
    const url = URL.createObjectURL(new Blob([l.join('\n')],
      { type:'text/plain;charset=utf-8' }));
    const el = document.createElement('a');
    el.href = url; el.download = texte.reference + '.txt'; el.click();
    URL.revokeObjectURL(url);
  }

  return html`
    <div>
      <div class="eyebrow">Recueil des actes</div>
      <h1 style="margin:6px 0 8px">Ce que la fédération a décidé</h1>
      <p class="muted" style="max-width:62ch">
        Les actes pris par la présidence, en vigueur ou abrogés. Chacun
        indique sa portée, sa date d\u2019effet et son signataire. Un acte
        abrogé reste ici : on doit pouvoir savoir ce qui s\u2019appliquait hier.
      </p>
      <div style="margin-top:24px">
        <${RecueilListe} actes=${actes} ouvert=${ouvert} texte=${texte}
          lire=${lire} telecharger=${telecharger} abroger=${null} />
      </div>
    </div>`;
}


/* --- Porter au cabinet, depuis n'importe où ----------------------------- */
export function VersLeCabinet(){
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ nature:'information', objet:'', corps:'' });
  const [msg, setMsg] = useState('');

  async function envoyer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('flecher_vers_cabinet', {
      p_nature: f.nature, p_objet: f.objet, p_corps: f.corps,
      p_lien: location.hash || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({ nature:'information', objet:'', corps:'' });
    setMsg('Transmis au cabinet de la présidence.');
    setOuvert(false);
  }

  return html`
    <div class="panneau">
      <div class="tete spread">
        <h3 style="font-size:17px">Porter à la présidence</h3>
        <button class="btn sm light" onClick=${()=>setOuvert(!ouvert)}>
          ${ouvert ? 'Fermer' : 'Écrire'}</button>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin:16px 20px 0">${msg}</div>`}
      ${ouvert
        ? html`<form onSubmit=${envoyer} class="corps stack">
            <div class="field"><label>Nature</label>
              <select value=${f.nature}
                onChange=${e=>setF(o=>({...o,nature:e.target.value}))}>
                ${Object.entries(NATURE_REMONTEE).map(([k,v]) =>
                  html`<option value=${k}>${v}</option>`)}
              </select></div>
            <div class="field"><label>Objet</label>
              <input value=${f.objet}
                onInput=${e=>setF(o=>({...o,objet:e.target.value}))} /></div>
            <div class="field"><label>Ce que vous voulez porter à sa connaissance</label>
              <textarea value=${f.corps}
                onInput=${e=>setF(o=>({...o,corps:e.target.value}))}></textarea></div>
            <div><button class="btn">Transmettre</button></div>
          </form>`
        : html`<div class="corps small muted">
            Une information, une alerte, une proposition ou une demande
            d\u2019arbitrage. Elle arrive directement au cabinet, quelle que soit
            votre échelle, et y reste jusqu\u2019à ce qu\u2019on l\u2019ait traitée
            \u2014 elle ne se perd pas en conversation.</div>`}
    </div>`;
}

/* =====================================================================
   LE PROFIL INTERNE
   Ce que la fédération montre d'un membre à un autre. Ni courriel, ni
   téléphone, ni adresse : ceux-là relèvent de la fiche membre, dont la
   consultation se journalise et déclenche une alerte si le dossier est
   protégé. Ici, rien de plus que ce qui est déjà interne-public.


export function AffairesPubliques({ p }){
  const [onglet, setOnglet] = useState('fichier');
  const [tb, setTb] = useState(null);
  const [contacts, setContacts] = useState([]);
  const [demandes, setDemandes] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a, b, c] = await Promise.all([
      db.rpc('tableau_ap'),
      db.rpc('v_contacts', { p_filtre: 'tous' }),
      db.rpc('sollicitations_ap_a_traiter', { p_filtre: 'ouvertes' })
    ]);
    setTb(a.data); setContacts(b.data||[]); setDemandes(c.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return false; }
    setMsg(ok); charger(); return true;
  };

  if (!tb) return html`<div class="vide" style="padding:120px">Chargement…</div>`;
  const service = tb.service;

  const tabs = [['fichier','Le fichier'], ['demandes','Sollicitations']];
  if (service) tabs.push(['prospection','Prospection']);

  return html`
    <div>
      <div class="eyebrow">Affaires publiques</div>
      <h1 style="margin:6px 0 8px">Ce que la fédération a tissé</h1>
      <p class="muted" style="max-width:62ch">
        ${service
          ? html`Le fichier est fédéral : rien n\u2019en sort sans que vous le
              partagiez. Un partage vise une structure ou un groupe de travail,
              jamais une personne \u2014 ce qui est confié survit ainsi au départ
              de qui l\u2019a demandé. Les interlocuteurs, eux, ne se partagent pas.`
          : html`Vous voyez ici les contacts que les affaires publiques ont
              partagés avec votre structure ou vos groupes. Pour en obtenir
              d\u2019autres, adressez-leur une demande : dites ce que vous cherchez
              et pourquoi.`}
      </p>

      <div class="chiffres" style="margin-top:24px">
        <div><div class="n" style="font-size:28px">${tb.contacts}</div>
          <div class="l">Contacts accessibles</div></div>
        <div><div class="n" style="font-size:28px">${tb.partenaires}</div>
          <div class="l">Partenaires</div></div>
        ${service && html`
          <div><div class="n" style="font-size:28px">${tb.prospects}</div>
            <div class="l">Prospects</div></div>
          <div><div class="n" style="font-size:28px">${tb.sollicitations}</div>
            <div class="l">Demandes en attente</div></div>`}
      </div>

      ${service && tb.suites_en_retard > 0 && html`
        <div class="alerte" style="margin-top:24px;border-left:3px solid var(--laiton)">
          ${tb.suites_en_retard} suite(s) annoncée(s) et non tenue(s) à échéance.
          C\u2019est le premier signe qu\u2019une relation s\u2019éteint.
        </div>`}

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet);
        flex-wrap:wrap">
        ${tabs.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bleu)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>{setOnglet(k);setMsg('')}}>${t}${
              k==='demandes' && tb.sollicitations ? ' ('+tb.sollicitations+')' : ''}</button>`)}
      </div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-bottom:20px">${msg}</div>`}

      ${onglet === 'fichier' && html`<${ApFichier} p=${p} contacts=${contacts}
        service=${service} appel=${appel} setMsg=${setMsg} recharger=${charger} />`}
      ${onglet === 'demandes' && html`<${ApSollicitations} demandes=${demandes}
        contacts=${contacts} service=${service} appel=${appel} />`}
      ${onglet === 'prospection' && html`<${ApProspection} contacts=${contacts}
        appel=${appel} />`}
    </div>`;
}


/* --- Le fichier --------------------------------------------------------- */
export function ApFichier({ p, contacts, service, appel, setMsg, recharger }){
  const [q, setQ] = useState('');
  const [filtre, setFiltre] = useState('tous');
  const [ouvert, setOuvert] = useState(null);
  const [edition, setEdition] = useState(false);
  const [f, setF] = useState({});
  const [selection, setSelection] = useState([]);
  const [terr, setTerr] = useState([]);

  useEffect(() => {
    db.from('territoires').select('id,nom,echelle').order('nom')
      .then(({data}) => setTerr(data||[]));
  }, []);

  const liste = contacts.filter(c =>
    (filtre === 'tous' || c.statut === filtre)
    && (q === '' || (c.nom + ' ' + (c.sigle||'') + ' ' + (c.objet||''))
        .toLowerCase().includes(q.toLowerCase())));

  function nouveau(){
    setF({ nom:'', sigle:'', type:'collectivite', echelle:'departement',
           territoire_id:'', site:'', adresse:'', objet:'', interet:'',
           statut:'prospect', reserve:false, motif_reserve:'' });
    setEdition(true); setOuvert(null);
  }
  function editer(c){
    setF({ ...c, territoire_id: c.territoire_id || '' });
    setEdition(true);
  }
  async function enregistrer(e){
    e.preventDefault();
    const ok = await appel('enregistrer_contact', { d: {
      ...f, territoire_id: f.territoire_id || null } }, 'Contact enregistré.');
    if (ok) setEdition(false);
  }

  async function partager(){
    if (selection.length === 0) return setMsg('Erreur : sélectionnez des contacts.');
    const t = prompt('Identifiant du territoire destinataire (laisser vide pour un groupe)');
    const g = t ? null : prompt('Identifiant du groupe de travail destinataire');
    if (!t && !g) return;
    const m = prompt('Motif du partage');
    const ok = await appel('partager_contacts', {
      p_contacts: selection, p_territoire: t || null, p_groupe: g || null,
      p_portee: 'fiche', p_motif: m || null, p_expire: null
    }, 'Partage enregistré.');
    if (ok) setSelection([]);
  }

  return html`
    <div>
      <div class="row" style="gap:12px;margin-bottom:20px;flex-wrap:wrap;align-items:center">
        <input value=${q} placeholder="Rechercher un organisme"
          style="flex:1;min-width:200px" onInput=${e=>setQ(e.target.value)} />
        <select value=${filtre} style="width:auto"
          onChange=${e=>setFiltre(e.target.value)}>
          <option value="tous">Tous les états</option>
          ${Object.entries(STATUT_CONTACT).map(([k,v]) =>
            html`<option value=${k}>${v[0]}</option>`)}
        </select>
        ${service && html`
          <button class="btn sm" onClick=${nouveau}>Ajouter</button>
          ${selection.length > 0 && html`
            <button class="btn sm light" onClick=${partager}>
              Partager ${selection.length}</button>`}`}
      </div>

      ${edition && html`
        <form class="panneau" style="margin-bottom:24px" onSubmit=${enregistrer}>
          <div class="tete spread">
            <h3 style="font-size:17px">${f.id ? 'Modifier' : 'Nouvel organisme'}</h3>
            <button type="button" class="btn sm light"
              onClick=${()=>setEdition(false)}>Fermer</button>
          </div>
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:2;min-width:200px;margin:0">
                <label>Nom</label>
                <input value=${f.nom||''}
                  onInput=${e=>setF(o=>({...o,nom:e.target.value}))} /></div>
              <div class="field" style="flex:0 0 120px;margin:0">
                <label>Sigle</label>
                <input value=${f.sigle||''}
                  onInput=${e=>setF(o=>({...o,sigle:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Type</label>
                <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
                  ${Object.entries(TYPE_CONTACT).map(([k,v]) =>
                    html`<option value=${k}>${v}</option>`)}
                </select></div>
            </div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Échelle</label>
                <select value=${f.echelle} onChange=${e=>setF(o=>({...o,echelle:e.target.value}))}>
                  <option value="national">Nationale</option>
                  <option value="region">Régionale</option>
                  <option value="departement">Départementale</option>
                  <option value="local">Locale</option>
                </select></div>
              <div class="field" style="flex:2;min-width:180px;margin:0">
                <label>Territoire concerné</label>
                <select value=${f.territoire_id}
                  onChange=${e=>setF(o=>({...o,territoire_id:e.target.value}))}>
                  <option value="">— Aucun —</option>
                  ${terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
                </select></div>
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>État de la relation</label>
                <select value=${f.statut} onChange=${e=>setF(o=>({...o,statut:e.target.value}))}>
                  ${Object.entries(STATUT_CONTACT).map(([k,v]) =>
                    html`<option value=${k}>${v[0]}</option>`)}
                </select></div>
            </div>
            <div class="field"><label>Ce qu\u2019il fait</label>
              <input value=${f.objet||''}
                onInput=${e=>setF(o=>({...o,objet:e.target.value}))} /></div>
            <div class="field"><label>Ce qu\u2019il représente pour nous</label>
              <textarea value=${f.interet||''} style="min-height:60px"
                onInput=${e=>setF(o=>({...o,interet:e.target.value}))}></textarea></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;margin:0"><label>Site</label>
                <input value=${f.site||''}
                  onInput=${e=>setF(o=>({...o,site:e.target.value}))} /></div>
              <div class="field" style="flex:1;margin:0"><label>Adresse</label>
                <input value=${f.adresse||''}
                  onInput=${e=>setF(o=>({...o,adresse:e.target.value}))} /></div>
            </div>
            <label class="row" style="gap:8px;align-items:center">
              <input type="checkbox" style="width:auto" checked=${!!f.reserve}
                onChange=${e=>setF(o=>({...o,reserve:e.target.checked}))} />
              <span class="small">Réserver au service \u2014 ce contact ne pourra
                être inclus dans aucun partage</span>
            </label>
            ${f.reserve && html`
              <div class="field" style="margin:0"><label>Pourquoi</label>
                <input value=${f.motif_reserve||''}
                  placeholder="Négociation en cours, litige, personne publique…"
                  onInput=${e=>setF(o=>({...o,motif_reserve:e.target.value}))} /></div>`}
            <div><button class="btn">Enregistrer</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="corps muted">
              ${service ? 'Aucun contact ne correspond.'
                : 'Aucun contact ne vous a été partagé pour l\u2019instant.'}</div>`
          : liste.map(c => html`
            <div key=${c.id}>
              <div class="ligne" style="align-items:flex-start">
                ${service && html`
                  <input type="checkbox" style="width:auto;margin-top:4px"
                    checked=${selection.includes(c.id)} disabled=${c.reserve}
                    onChange=${()=>setSelection(s => s.includes(c.id)
                      ? s.filter(x=>x!==c.id) : [...s, c.id])} />`}
                <div style="flex:1;min-width:240px;cursor:pointer"
                  onClick=${()=>setOuvert(ouvert===c.id?null:c.id)}>
                  <div class="row" style="gap:8px;flex-wrap:wrap">
                    <span style="font-weight:600">${c.nom}</span>
                    ${c.sigle && html`<span class="mono muted small">${c.sigle}</span>`}
                    <span class=${'tag '+(STATUT_CONTACT[c.statut]||['',''])[1]}>
                      ${(STATUT_CONTACT[c.statut]||[c.statut])[0]}</span>
                    ${c.reserve && html`<span class="tag rouge">Réservé</span>`}
                  </div>
                  <div class="small muted" style="margin-top:3px">
                    ${TYPE_CONTACT[c.type] || c.type}
                    ${c.territoire ? ' · ' + c.territoire : ''}
                    ${c.dernier_echange ? ' · dernier échange ' + jour(c.dernier_echange)
                      : ' · aucun échange consigné'}
                    ${service && c.partages > 0 ? ' · partagé ' + c.partages + ' fois' : ''}
                  </div>
                  ${c.objet && html`<div class="small" style="margin-top:4px">${c.objet}</div>`}
                </div>
                ${service && html`
                  <button class="btn sm light" onClick=${()=>editer(c)}>Modifier</button>`}
              </div>
              ${ouvert === c.id && html`
                <${ApContact} contact=${c} service=${service}
                  appel=${appel} recharger=${recharger} />`}
            </div>`)}
      </div>
    </div>`;
}


/* --- Le détail d'un contact -------------------------------------------- */
export function ApContact({ contact, service, appel, recharger }){
  const [gens, setGens] = useState([]);
  const [echanges, setEchanges] = useState([]);
  const [ajout, setAjout] = useState(null);
  const [e, setE] = useState({ date_echange:'', nature:'rendez_vous', objet:'',
                               compte_rendu:'', suite:'', echeance:'' });
  const [i, setI] = useState({ prenom:'', nom:'', fonction:'', email:'', telephone:'' });

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.from('contact_personnes').select('*').eq('contact_id', contact.id)
        .eq('actif', true).order('nom'),
      db.from('contact_echanges').select('*').eq('contact_id', contact.id)
        .order('date_echange', { ascending:false })
    ]);
    setGens(a.data||[]); setEchanges(b.data||[]);
  }, [contact.id]);
  useEffect(() => { charger(); }, [charger]);

  return html`
    <div class="corps" style="background:var(--papier);border-bottom:1px solid var(--filet)">
      ${contact.interet && html`
        <p class="small" style="margin:0 0 16px"><strong>Ce qu\u2019il représente</strong> —
          ${contact.interet}</p>`}
      ${contact.reserve && html`
        <p class="small" style="color:var(--rouge);margin:0 0 16px">
          Contact réservé au service : il ne peut être inclus dans aucun partage.</p>`}

      ${gens.length > 0 && html`
        <div style="margin-bottom:18px">
          <div class="small muted" style="margin-bottom:8px">Interlocuteurs</div>
          ${gens.map(g => html`
            <div class="small" key=${g.id} style="margin-bottom:6px">
              <strong>${[g.prenom,g.nom].filter(Boolean).join(' ')}</strong>
              ${g.fonction ? ' — ' + g.fonction : ''}
              ${g.email ? html` · <a href=${'mailto:'+g.email}>${g.email}</a>` : ''}
              ${g.telephone ? ' · ' + g.telephone : ''}
            </div>`)}
        </div>`}

      ${!service && html`
        <p class="small muted" style="margin:0 0 16px">
          Les interlocuteurs nommément ne sortent pas du service : un partage
          porte sur l\u2019organisme, pas sur les personnes qui y travaillent.
          Passez par une sollicitation pour être mis en relation.
        </p>`}

      <div class="spread" style="margin-bottom:10px">
        <div class="small muted">Échanges consignés</div>
        ${service && html`
          <div class="row" style="gap:6px">
            <button class="btn sm light" onClick=${()=>setAjout(ajout==='e'?null:'e')}>
              Consigner un échange</button>
            <button class="btn sm light" onClick=${()=>setAjout(ajout==='i'?null:'i')}>
              Ajouter un interlocuteur</button>
          </div>`}
      </div>

      ${ajout === 'e' && html`
        <form class="stack" style="margin-bottom:16px" onSubmit=${async ev=>{
          ev.preventDefault();
          const ok = await appel('consigner_echange', { d: { ...e,
            contact_id: contact.id, date_echange: e.date_echange || null,
            echeance: e.echeance || null } }, 'Échange consigné.');
          if (ok){ setAjout(null); setE({ date_echange:'', nature:'rendez_vous',
            objet:'', compte_rendu:'', suite:'', echeance:'' }); charger(); }
        }}>
          <div class="row" style="gap:12px;align-items:flex-start">
            <div class="field" style="flex:0 0 150px;margin:0"><label>Date</label>
              <input type="date" value=${e.date_echange}
                onInput=${ev=>setE(o=>({...o,date_echange:ev.target.value}))} /></div>
            <div class="field" style="flex:0 0 160px;margin:0"><label>Nature</label>
              <select value=${e.nature} onChange=${ev=>setE(o=>({...o,nature:ev.target.value}))}>
                ${Object.entries(NATURE_ECHANGE).map(([k,v]) =>
                  html`<option value=${k}>${v}</option>`)}
              </select></div>
            <div class="field" style="flex:1;min-width:180px;margin:0"><label>Objet</label>
              <input value=${e.objet}
                onInput=${ev=>setE(o=>({...o,objet:ev.target.value}))} /></div>
          </div>
          <div class="field"><label>Compte rendu</label>
            <textarea value=${e.compte_rendu} style="min-height:70px"
              onInput=${ev=>setE(o=>({...o,compte_rendu:ev.target.value}))}></textarea></div>
          <div class="row" style="gap:12px;align-items:flex-start">
            <div class="field" style="flex:1;margin:0"><label>Suite à donner</label>
              <input value=${e.suite}
                onInput=${ev=>setE(o=>({...o,suite:ev.target.value}))} /></div>
            <div class="field" style="flex:0 0 150px;margin:0"><label>Pour le</label>
              <input type="date" value=${e.echeance}
                onInput=${ev=>setE(o=>({...o,echeance:ev.target.value}))} /></div>
          </div>
          <div><button class="btn sm">Consigner</button></div>
        </form>`}

      ${ajout === 'i' && html`
        <form class="stack" style="margin-bottom:16px" onSubmit=${async ev=>{
          ev.preventDefault();
          const ok = await appel('enregistrer_interlocuteur',
            { d: { ...i, contact_id: contact.id } }, 'Interlocuteur enregistré.');
          if (ok){ setAjout(null); setI({ prenom:'', nom:'', fonction:'',
            email:'', telephone:'' }); charger(); }
        }}>
          <div class="row" style="gap:12px;align-items:flex-start">
            <div class="field" style="flex:1;margin:0"><label>Prénom</label>
              <input value=${i.prenom}
                onInput=${ev=>setI(o=>({...o,prenom:ev.target.value}))} /></div>
            <div class="field" style="flex:1;margin:0"><label>Nom</label>
              <input value=${i.nom}
                onInput=${ev=>setI(o=>({...o,nom:ev.target.value}))} /></div>
            <div class="field" style="flex:1;margin:0"><label>Fonction</label>
              <input value=${i.fonction}
                onInput=${ev=>setI(o=>({...o,fonction:ev.target.value}))} /></div>
          </div>
          <div class="row" style="gap:12px;align-items:flex-start">
            <div class="field" style="flex:1;margin:0"><label>Courriel</label>
              <input value=${i.email}
                onInput=${ev=>setI(o=>({...o,email:ev.target.value}))} /></div>
            <div class="field" style="flex:1;margin:0"><label>Téléphone</label>
              <input value=${i.telephone}
                onInput=${ev=>setI(o=>({...o,telephone:ev.target.value}))} /></div>
          </div>
          <div><button class="btn sm">Enregistrer</button></div>
        </form>`}

      ${echanges.length === 0
        ? html`<div class="small muted">Aucun échange consigné.</div>`
        : echanges.map(x => html`
          <div class="small" key=${x.id} style="margin-bottom:12px;padding-left:12px;
            border-left:2px solid var(--filet)">
            <div><strong>${jour(x.date_echange)}</strong> ·
              ${NATURE_ECHANGE[x.nature] || x.nature} · ${x.objet}</div>
            ${x.compte_rendu && html`<div class="muted" style="margin-top:2px">
              ${x.compte_rendu}</div>`}
            ${x.suite && html`<div style=${'margin-top:2px;color:'
              + (x.echeance && new Date(x.echeance) < new Date()
                 ? 'var(--rouge)' : 'var(--laiton)')}>
              Suite : ${x.suite}${x.echeance ? ' — pour le ' + jour(x.echeance) : ''}</div>`}
          </div>`)}
    </div>`;
}


/* --- Les sollicitations du réseau -------------------------------------- */
export function ApSollicitations({ demandes, contacts, service, appel }){
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ objet:'', besoin:'', echeance:'' });
  const [choix, setChoix] = useState({});

  async function demander(e){
    e.preventDefault();
    const ok = await appel('solliciter_ap', {
      p_objet: f.objet, p_besoin: f.besoin, p_groupe: null,
      p_echeance: f.echeance || null
    }, 'Demande transmise aux affaires publiques.');
    if (ok){ setF({ objet:'', besoin:'', echeance:'' }); setOuvert(false); }
  }

  async function repondre(d, statut){
    const r = prompt(statut === 'satisfaite'
      ? 'Réponse au demandeur (obligatoire)'
      : 'Pourquoi cette demande est-elle écartée ? (obligatoire)');
    if (!r) return;
    await appel('traiter_sollicitation', {
      p_id: d.id, p_statut: statut, p_reponse: r,
      p_contacts: statut === 'satisfaite' ? (choix[d.id] || []) : []
    }, statut === 'satisfaite'
      ? 'Réponse envoyée et contacts partagés.' : 'Demande écartée.');
    setChoix(c => ({ ...c, [d.id]: [] }));
  }

  const partageables = contacts.filter(c => !c.reserve);

  return html`
    <div>
      ${!service && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete spread">
            <h3 style="font-size:17px">Demander un contact</h3>
            <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
              ${ouvert ? 'Fermer' : 'Écrire'}</button>
          </div>
          ${ouvert
            ? html`<form class="corps stack" onSubmit=${demander}>
                <div class="field" style="margin:0"><label>Objet</label>
                  <input value=${f.objet} placeholder="Partenaire pour le forum de septembre"
                    onInput=${e=>setF(o=>({...o,objet:e.target.value}))} /></div>
                <div class="field"><label>Ce que vous cherchez, et pourquoi</label>
                  <textarea value=${f.besoin} style="min-height:90px"
                    placeholder="Plus vous êtes précis, plus ce qu\u2019on vous partagera sera utile."
                    onInput=${e=>setF(o=>({...o,besoin:e.target.value}))}></textarea></div>
                <div class="field" style="max-width:200px"><label>Pour quand</label>
                  <input type="date" value=${f.echeance}
                    onInput=${e=>setF(o=>({...o,echeance:e.target.value}))} /></div>
                <div><button class="btn">Transmettre</button></div>
              </form>`
            : html`<div class="corps small muted">
                Le service dispose du fichier fédéral. Dites ce que vous cherchez
                et pourquoi : il vous partagera ce qu\u2019il juge utile, ou vous
                expliquera pourquoi il ne le fait pas.</div>`}
        </div>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">
          ${service ? 'Demandes du réseau' : 'Mes demandes'}</h3>
          <span class="tag">${demandes.length}</span></div>
        ${demandes.length === 0
          ? html`<div class="corps muted">Rien en attente.</div>`
          : demandes.map(d => html`
            <div key=${d.id}>
              <div class="ligne" style="align-items:flex-start">
                <div style="flex:1;min-width:250px">
                  <div class="row" style="gap:8px;flex-wrap:wrap">
                    <span style="font-weight:600">${d.objet}</span>
                    ${d.echeance && html`<span class=${'tag '+(
                      new Date(d.echeance) < new Date() ? 'rouge' : 'or')}>
                      pour le ${jour(d.echeance)}</span>`}
                  </div>
                  <div class="small muted" style="margin-top:3px">
                    ${d.demandeur} · ${d.fonction}
                    ${d.territoire ? ' · ' + d.territoire : ''}
                    ${d.groupe ? ' · ' + d.groupe : ''} · ${jour(d.cree_le)}
                  </div>
                  <div class="small" style="margin-top:6px">${d.besoin}</div>
                  ${d.reponse && html`<div class="small" style="margin-top:6px;
                    color:var(--laiton)">Réponse : ${d.reponse}</div>`}
                </div>
                ${service && html`
                  <div class="row" style="gap:6px">
                    <button class="btn sm" onClick=${()=>repondre(d,'satisfaite')}>
                      Répondre${(choix[d.id]||[]).length
                        ? ' et partager ' + choix[d.id].length : ''}</button>
                    <button class="btn sm light" onClick=${()=>repondre(d,'ecartee')}>
                      Écarter</button>
                  </div>`}
              </div>
              ${service && html`
                <div class="corps" style="background:var(--papier);
                  border-bottom:1px solid var(--filet);padding-top:12px">
                  <div class="small muted" style="margin-bottom:8px">
                    Contacts à partager avec ${d.groupe || d.territoire || 'le demandeur'}</div>
                  <div class="row" style="gap:6px;flex-wrap:wrap;max-height:130px;
                    overflow-y:auto">
                    ${partageables.map(c => html`
                      <button type="button" key=${c.id}
                        class=${'btn sm ' + ((choix[d.id]||[]).includes(c.id) ? '' : 'light')}
                        onClick=${()=>setChoix(x => {
                          const l = x[d.id] || [];
                          return { ...x, [d.id]: l.includes(c.id)
                            ? l.filter(y=>y!==c.id) : [...l, c.id] };
                        })}>${c.sigle || c.nom}</button>`)}
                  </div>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}


/* --- La prospection ----------------------------------------------------- */
export function ApProspection({ contacts, appel }){
  const [l, setL] = useState([]);
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ intitule:'', cible:'', contact_id:'', objectif:'',
                               enjeu:'', echeance:'', etat:'ouverte' });

  const charger = useCallback(() =>
    db.from('pistes_ap').select('*').order('echeance', { nullsFirst:false })
      .then(({data}) => setL(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  const ETAT = { ouverte:['Ouverte','bleu'], en_cours:['En cours','or'],
                 aboutie:['Aboutie','vert'], abandonnee:['Abandonnée','rouge'] };

  async function enregistrer(e){
    e.preventDefault();
    const ok = await appel('enregistrer_piste', { d: { ...f,
      contact_id: f.contact_id || null, echeance: f.echeance || null } },
      'Piste enregistrée.');
    if (ok){ setF({ intitule:'', cible:'', contact_id:'', objectif:'', enjeu:'',
      echeance:'', etat:'ouverte' }); setOuvert(false); charger(); }
  }

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px;flex-wrap:wrap;gap:10px">
        <p class="muted" style="max-width:56ch;margin:0">
          Un contact est un fait, une piste est une intention. On y écrit ce
          qu\u2019on cherche à obtenir, de qui, pour quand — de sorte que la
          prospection ne dépende pas de la mémoire d\u2019une seule personne.
        </p>
        <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
          ${ouvert ? 'Fermer' : 'Ouvrir une piste'}</button>
      </div>

      ${ouvert && html`
        <form class="panneau" style="margin-bottom:24px" onSubmit=${enregistrer}>
          <div class="tete"><h3 style="font-size:17px">Nouvelle piste</h3></div>
          <div class="corps stack">
            <div class="field" style="margin:0"><label>Intitulé</label>
              <input value=${f.intitule} placeholder="Convention avec la région"
                onInput=${e=>setF(o=>({...o,intitule:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:160px;margin:0"><label>Cible</label>
                <input value=${f.cible}
                  onInput=${e=>setF(o=>({...o,cible:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:180px;margin:0">
                <label>Contact rattaché</label>
                <select value=${f.contact_id}
                  onChange=${e=>setF(o=>({...o,contact_id:e.target.value}))}>
                  <option value="">— Aucun —</option>
                  ${contacts.map(c => html`<option value=${c.id}>${c.nom}</option>`)}
                </select></div>
              <div class="field" style="flex:0 0 150px;margin:0"><label>Échéance</label>
                <input type="date" value=${f.echeance}
                  onInput=${e=>setF(o=>({...o,echeance:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Ce qu\u2019on cherche à obtenir</label>
              <textarea value=${f.objectif} style="min-height:60px"
                onInput=${e=>setF(o=>({...o,objectif:e.target.value}))}></textarea></div>
            <div class="field"><label>Pourquoi cela compte</label>
              <textarea value=${f.enjeu} style="min-height:60px"
                onInput=${e=>setF(o=>({...o,enjeu:e.target.value}))}></textarea></div>
            <div><button class="btn">Enregistrer</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${l.length === 0
          ? html`<div class="corps muted">Aucune piste ouverte.</div>`
          : l.map(x => html`
            <div class="ligne" key=${x.id} style="align-items:flex-start">
              <div style="flex:1;min-width:250px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span style="font-weight:600">${x.intitule}</span>
                  <span class=${'tag '+(ETAT[x.etat]||['',''])[1]}>
                    ${(ETAT[x.etat]||[x.etat])[0]}</span>
                  ${x.echeance && ['ouverte','en_cours'].includes(x.etat)
                    && new Date(x.echeance) < new Date()
                    && html`<span class="tag rouge">Échue</span>`}
                </div>
                <div class="small muted" style="margin-top:3px">
                  ${x.cible || '—'}${x.echeance ? ' · pour le ' + jour(x.echeance) : ''}
                </div>
                <div class="small" style="margin-top:6px">${x.objectif}</div>
                ${x.enjeu && html`<div class="small muted" style="margin-top:3px">
                  ${x.enjeu}</div>`}
              </div>
              <div class="row" style="gap:6px">
                ${['ouverte','en_cours'].includes(x.etat) && html`
                  <button class="btn sm light" onClick=${async ()=>{
                    const c = prompt('Ce qui a été obtenu');
                    if (c) { await appel('enregistrer_piste',
                      { d: { ...x, etat:'aboutie', conclusion:c } }, 'Piste aboutie.');
                      charger(); }
                  }}>Aboutie</button>
                  <button class="btn sm light" onClick=${async ()=>{
                    const c = prompt('Pourquoi on abandonne');
                    if (c) { await appel('enregistrer_piste',
                      { d: { ...x, etat:'abandonnee', conclusion:c } }, 'Piste close.');
                      charger(); }
                  }}>Abandonner</button>`}
              </div>
            </div>`)}
      </div>
    </div>`;
}

/* =====================================================================
   LES INVESTISSEMENTS À ORDONNANCER
   Ils n'apparaissaient que dans Ressources, alors qu'ordonnancer est le
   métier de l'ordonnateur, qui travaille dans son écran. Même fonction,
   deux endroits — pas deux circuits.
