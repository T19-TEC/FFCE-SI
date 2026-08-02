/* =====================================================================
   ÉVÉNEMENTS
   Créer, ouvrir les inscriptions, tenir la liste, contrôler les
   entrées. Trois choses gouvernent l'écran :

   · une inscription externe est une donnée de tiers — elle porte une
     échéance d'effacement, et l'écran le dit à qui s'inscrit ;
   · un billet n'ouvre que ce qu'il porte : le contrôle vérifie la
     catégorie présentée, sans quoi « répartir les entrées » ne veut
     rien dire ;
   · un double passage est signalé, pas refusé. Une porte qui refuse
     sans expliquer crée une file et un conflit.
   ===================================================================== */
import { html, db, useState, useEffect, useCallback, jour, nomComplet } from './socle.js';
import { qrMatrice } from './membre.js';

const NATURE_EV = { rencontre:'Rencontre', forum:'Forum', formation:'Formation',
  assises:'Assises', ceremonie:'Cérémonie', repas:'Repas', sortie:'Sortie',
  autre:'Autre' };
const OUVERTURE_EV = { interne:'Réservé aux membres', ouverte:'Ouverte au public',
  sur_invitation:'Sur invitation' };
const STATUT_EV = { projet:['Projet',''], ouvert:['Inscriptions ouvertes','vert'],
  complet:['Complet','or'], clos:['Clos',''], annule:['Annulé','rouge'] };

export function Evenements({ p }){
  const [l, setL] = useState([]);
  const [filtre, setFiltre] = useState('a_venir');
  const [ouvert, setOuvert] = useState(null);
  const [creer, setCreer] = useState(false);
  const [msg, setMsg] = useState('');

  const charger = useCallback(() =>
    db.rpc('mes_evenements', { p_filtre: filtre }).then(({data}) => setL(data || [])),
    [filtre]);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return null; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return null; }
    if (ok) setMsg(ok);
    charger(); return data;
  };

  if (ouvert) return html`<${Evenement} p=${p} id=${ouvert}
    fermer=${()=>{setOuvert(null); charger();}} />`;

  const peutCreer = l.some(x => x.je_tiens) || p.niveau >= 60;

  return html`
    <div>
      <div class="eyebrow">Événements</div>
      <h1 style="margin:6px 0 8px">Réunir, et savoir qui vient</h1>
      <p class="muted" style="max-width:62ch">
        Un événement porte des catégories d\u2019entrée — plénière, atelier,
        repas — chacune avec sa capacité. Le billet de chacun n\u2019ouvre que
        celles auxquelles il s\u2019est inscrit, et le contrôle à l\u2019entrée le
        vérifie.
      </p>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:20px">${msg}</div>`}

      <div class="row" style="margin:24px 0 20px;gap:8px;flex-wrap:wrap">
        ${[['a_venir','À venir'],['inscrit','Où je suis inscrit'],
           ['miens','Que j\u2019organise'],['tous','Tous']].map(([k,t]) => html`
          <button key=${k} class=${'btn sm ' + (filtre===k ? '' : 'light')}
            onClick=${()=>setFiltre(k)}>${t}</button>`)}
        ${peutCreer && html`
          <button class="btn sm" onClick=${()=>setCreer(!creer)}>
            ${creer ? 'Fermer' : 'Créer un événement'}</button>`}
      </div>

      ${creer && html`<${FormulaireEvenement} p=${p}
        enregistrer=${async d => {
          const r = await appel('enregistrer_evenement', { d },
            'Événement créé. Ajoutez ses catégories d\u2019entrée, puis ouvrez les inscriptions.');
          if (r){ setCreer(false); setOuvert(r.id); }
        }} />`}

      <div class="panneau">
        ${l.length === 0
          ? html`<div class="corps muted">Aucun événement.</div>`
          : l.map(e => html`
            <div class="ligne" key=${e.id} style="align-items:flex-start">
              <div style="flex:1;min-width:250px;cursor:pointer"
                onClick=${()=>setOuvert(e.id)}>
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span style="font-weight:600">${e.titre}</span>
                  <span class=${'tag ' + (STATUT_EV[e.statut]||['',''])[1]}>
                    ${(STATUT_EV[e.statut]||[e.statut])[0]}</span>
                  ${e.ouverture === 'ouverte' && html`<span class="tag bleu">Public</span>`}
                  ${e.mon_inscription === 'validee' && html`
                    <span class="tag vert">Vous êtes inscrit</span>`}
                  ${e.mon_inscription === 'deposee' && html`
                    <span class="tag or">Inscription en attente</span>`}
                </div>
                <div class="small muted" style="margin-top:3px">
                  ${NATURE_EV[e.nature] || e.nature}
                  · ${new Date(e.debut).toLocaleString('fr-FR',
                      {weekday:'long', day:'numeric', month:'long',
                       hour:'2-digit', minute:'2-digit'})}
                  ${e.lieu ? ' · ' + e.lieu : ''}
                  ${e.territoire ? ' · ' + e.territoire : ''}
                </div>
                ${e.partenaire && html`<div class="small muted" style="margin-top:2px">
                  Avec ${e.partenaire}</div>`}
                ${e.objet && html`<div class="small" style="margin-top:5px">${e.objet}</div>`}
              </div>
              <div class="row" style="gap:10px;align-items:flex-start">
                <div style="text-align:right">
                  <div class="mono">${e.inscrits}${e.capacite ? ' / ' + e.capacite : ''}</div>
                  <div class="small muted">inscrit(s)</div>
                </div>
                <button class="btn sm light" onClick=${()=>setOuvert(e.id)}>Ouvrir</button>
              </div>
            </div>`)}
      </div>
    </div>`;
}

/* --- Le formulaire de création ------------------------------------------ */
function FormulaireEvenement({ p, enregistrer, initial }){
  const [f, setF] = useState(initial || { titre:'', objet:'', nature:'rencontre',
    ouverture:'interne', lieu:'', adresse:'', debut:'', fin:'', capacite:'',
    validation_requise:false, cloture_inscriptions:'', conservation_jours:180 });
  const [partenaires, setPartenaires] = useState([]);
  const maj = (k,v) => setF(o => ({...o, [k]: v}));

  useEffect(() => {
    db.rpc('v_contacts', { p_filtre: 'partenaires' })
      .then(({data}) => setPartenaires(data || []));
  }, []);

  return html`
    <form class="panneau" style="margin-bottom:24px" onSubmit=${e=>{
      e.preventDefault(); enregistrer(f);
    }}>
      <div class="tete"><h3 style="font-size:17px">
        ${f.id ? 'Modifier l\u2019événement' : 'Nouvel événement'}</h3></div>
      <div class="corps stack">
        <div class="field" style="margin:0"><label>Titre</label>
          <input value=${f.titre} placeholder="Forum des associations de Toulouse"
            onInput=${e=>maj('titre', e.target.value)} /></div>

        <div class="row" style="gap:16px;align-items:flex-start">
          <div class="field" style="flex:1;min-width:160px;margin:0">
            <label>Nature</label>
            <select value=${f.nature} onChange=${e=>maj('nature', e.target.value)}>
              ${Object.entries(NATURE_EV).map(([k,v]) =>
                html`<option value=${k}>${v}</option>`)}
            </select></div>
          <div class="field" style="flex:1;min-width:190px;margin:0">
            <label>Qui peut s\u2019inscrire</label>
            <select value=${f.ouverture} onChange=${e=>maj('ouverture', e.target.value)}>
              ${Object.entries(OUVERTURE_EV).map(([k,v]) =>
                html`<option value=${k}>${v}</option>`)}
            </select></div>
          <div class="field" style="flex:1;min-width:180px;margin:0">
            <label>Partenaire (facultatif)</label>
            <select value=${f.partenaire_id || ''}
              onChange=${e=>maj('partenaire_id', e.target.value)}>
              <option value="">— Aucun —</option>
              ${partenaires.map(c => html`<option value=${c.id}>${c.nom}</option>`)}
            </select></div>
        </div>

        <div class="field"><label>Objet</label>
          <textarea value=${f.objet} style="min-height:60px"
            placeholder="Ce qui s\u2019y passe, et pour qui."
            onInput=${e=>maj('objet', e.target.value)}></textarea></div>

        <div class="row" style="gap:16px;align-items:flex-start">
          <div class="field" style="flex:1;min-width:200px;margin:0"><label>Début</label>
            <input type="datetime-local" value=${f.debut}
              onInput=${e=>maj('debut', e.target.value)} /></div>
          <div class="field" style="flex:1;min-width:200px;margin:0"><label>Fin</label>
            <input type="datetime-local" value=${f.fin}
              onInput=${e=>maj('fin', e.target.value)} /></div>
        </div>

        <div class="row" style="gap:16px;align-items:flex-start">
          <div class="field" style="flex:1;min-width:160px;margin:0"><label>Lieu</label>
            <input value=${f.lieu} onInput=${e=>maj('lieu', e.target.value)} /></div>
          <div class="field" style="flex:2;min-width:200px;margin:0"><label>Adresse</label>
            <input value=${f.adresse} onInput=${e=>maj('adresse', e.target.value)} /></div>
          <div class="field" style="flex:0 0 120px;margin:0"><label>Capacité</label>
            <input type="number" min="1" value=${f.capacite}
              onInput=${e=>maj('capacite', e.target.value)} /></div>
        </div>

        <div class="row" style="gap:16px;align-items:flex-end">
          <div class="field" style="flex:0 0 190px;margin:0">
            <label>Clôture des inscriptions</label>
            <input type="date" value=${f.cloture_inscriptions}
              onInput=${e=>maj('cloture_inscriptions', e.target.value)} /></div>
          <div class="field" style="flex:0 0 200px;margin:0">
            <label>Conservation des données (jours)</label>
            <input type="number" min="30" value=${f.conservation_jours}
              onInput=${e=>maj('conservation_jours', e.target.value)} /></div>
        </div>

        <label class="row" style="gap:8px;align-items:center">
          <input type="checkbox" style="width:auto" checked=${!!f.validation_requise}
            onChange=${e=>maj('validation_requise', e.target.checked)} />
          <span class="small">Chaque inscription doit être validée avant de valoir billet</span>
        </label>

        <p class="small muted" style="margin:0">
          Les inscriptions de personnes extérieures s\u2019effacent automatiquement
          après le délai de conservation. L\u2019échéance est fixée maintenant,
          pour n\u2019avoir pas à en décider plus tard.
        </p>

        <div><button class="btn">${f.id ? 'Enregistrer' : 'Créer l\u2019événement'}</button></div>
      </div>
    </form>`;
}

/* --- Un événement ouvert ------------------------------------------------ */
export function Evenement({ p, id, fermer }){
  const [e, setE] = useState(null);
  const [tb, setTb] = useState(null);
  const [inscrits, setInscrits] = useState([]);
  const [onglet, setOnglet] = useState('presentation');
  const [msg, setMsg] = useState('');
  const [choix, setChoix] = useState([]);
  const [besoin, setBesoin] = useState('');

  const charger = useCallback(async () => {
    const [l, t] = await Promise.all([
      db.rpc('mes_evenements', { p_filtre: 'tous' }),
      db.rpc('tableau_evenement', { p_evenement: id })
    ]);
    const ev = (l.data || []).find(x => x.id === id) || null;
    setE(ev); setTb(t.data);
    if (ev && ev.je_tiens){
      const { data } = await db.rpc('liste_inscrits', { p_evenement: id, p_filtre: 'tous' });
      setInscrits(data || []);
    }
  }, [id]);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return null; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return null; }
    if (ok) setMsg(ok);
    charger(); return data;
  };

  if (!e || !tb) return html`<div class="vide">Chargement…</div>`;

  const cats = tb.categories || [];
  const lienPublic = location.origin + location.pathname + '#/evenement/' + e.jeton_public;
  const tabs = [['presentation','L\u2019événement']];
  if (e.je_tiens) tabs.push(['inscrits','Inscrits'], ['entrees','Contrôle des entrées'],
                            ['reglages','Réglages']);

  return html`
    <div>
      <a href="#" onClick=${ev=>{ev.preventDefault();fermer()}}
        class="lien-discret">← Tous les événements</a>

      <div class="spread" style="margin-top:12px;flex-wrap:wrap;gap:10px">
        <div>
          <div class="eyebrow">${NATURE_EV[e.nature] || e.nature}</div>
          <h1 style="margin:6px 0 4px">${e.titre}</h1>
          <div class="muted">
            ${new Date(e.debut).toLocaleString('fr-FR',
              {weekday:'long', day:'numeric', month:'long', year:'numeric',
               hour:'2-digit', minute:'2-digit'})}
            ${e.lieu ? ' · ' + e.lieu : ''}
          </div>
        </div>
        <span class=${'tag ' + (STATUT_EV[e.statut]||['',''])[1]}>
          ${(STATUT_EV[e.statut]||[e.statut])[0]}</span>
      </div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:20px">${msg}</div>`}

      ${tabs.length > 1 && html`
        <div class="row" style="margin:24px 0 20px;gap:0;border-bottom:1px solid var(--filet);
          flex-wrap:wrap">
          ${tabs.map(([k,t]) => html`
            <button key=${k} class="btn light" style=${'border:0;border-bottom:2px solid '
              + (onglet===k?'var(--framboise)':'transparent')
              + ';border-radius:0;background:transparent'}
              onClick=${()=>{setOnglet(k);setMsg('')}}>${t}${
                k==='inscrits' && tb.a_valider ? ' (' + tb.a_valider + ')' : ''}</button>`)}
        </div>`}

      ${onglet === 'presentation' && html`
        <div style=${tabs.length > 1 ? '' : 'margin-top:24px'}>
          ${e.objet && html`<p style="max-width:62ch">${e.objet}</p>`}

          ${e.je_tiens && html`
            <div class="chiffres" style="margin:24px 0">
              <div><div class="n" style="font-size:28px">${tb.inscrits}</div>
                <div class="l">Inscrits</div></div>
              <div><div class="n" style="font-size:28px">${tb.externes}</div>
                <div class="l">Personnes extérieures</div></div>
              <div><div class="n" style="font-size:28px">${tb.presents}</div>
                <div class="l">Entrées constatées</div></div>
              <div><div class="n" style="font-size:28px">${tb.besoins}</div>
                <div class="l">Besoins signalés</div></div>
            </div>`}

          <div class="panneau" style="margin-top:20px">
            <div class="tete"><h3 style="font-size:17px">Ce que comprend l\u2019événement</h3></div>
            ${cats.map(c => html`
              <div class="ligne" key=${c.code}>
                <div style="flex:1;min-width:200px">
                  <div class="row" style="gap:8px;flex-wrap:wrap">
                    <span>${c.nom}</span>
                    ${!c.externe_admis && html`<span class="tag">Membres seulement</span>`}
                  </div>
                  <div class="small muted">${c.horaire || ''}
                    ${c.capacite ? ' · ' + c.inscrits + ' / ' + c.capacite + ' places'
                                 : ' · ' + c.inscrits + ' inscrit(s)'}</div>
                </div>
                ${e.je_tiens && html`<span class="mono small muted">
                  ${c.entrees} entrée(s)</span>`}
              </div>`)}
          </div>

          ${!e.je_tiens && e.statut === 'ouvert' && !e.mon_inscription && html`
            <div class="panneau" style="margin-top:20px;border-color:var(--framboise)">
              <div class="tete" style="border-bottom-color:var(--framboise)">
                <h3 style="font-size:17px">S\u2019inscrire</h3></div>
              <div class="corps stack">
                <div class="field" style="margin:0">
                  <label>À quoi participez-vous ?</label>
                  <div class="row" style="gap:6px;flex-wrap:wrap">
                    ${cats.map(c => html`
                      <button type="button" key=${c.code}
                        class=${'btn sm ' + (choix.includes(c.code) ? '' : 'light')}
                        disabled=${c.capacite !== null && c.inscrits >= c.capacite}
                        onClick=${()=>setChoix(s => s.includes(c.code)
                          ? s.filter(x=>x!==c.code) : [...s, c.code])}>
                        ${c.nom}${c.capacite !== null && c.inscrits >= c.capacite
                          ? ' — complet' : ''}</button>`)}
                  </div>
                </div>
                <div class="field"><label>Un besoin à signaler ?</label>
                  <input value=${besoin}
                    placeholder="Accessibilité, régime alimentaire, horaire…"
                    onInput=${ev=>setBesoin(ev.target.value)} /></div>
                <div><button class="btn" disabled=${choix.length === 0}
                  onClick=${()=>appel('inscrire_a_evenement',
                    { p_evenement: id, p_categories: choix, p_besoin: besoin || null },
                    'Inscription enregistrée.')}>M\u2019inscrire</button></div>
              </div>
            </div>`}

          ${e.mon_inscription && html`
            <${MonBillet} id=${id} statut=${e.mon_inscription} />`}
        </div>`}

      ${onglet === 'inscrits' && html`
        <${ListeInscrits} id=${id} inscrits=${inscrits} appel=${appel}
          titre=${e.titre} setMsg=${setMsg} />`}

      ${onglet === 'entrees' && html`
        <${ControleEntrees} cats=${cats} setMsg=${setMsg} recharger=${charger} />`}

      ${onglet === 'reglages' && html`
        <${ReglagesEvenement} e=${e} cats=${cats} lienPublic=${lienPublic}
          appel=${appel} setMsg=${setMsg} />`}
    </div>`;
}

/* --- Mon billet ---------------------------------------------------------
   Le code présenté à l'entrée. Il n'ouvre que les catégories choisies,
   et ne donne accès à rien d'autre.
   --------------------------------------------------------------------- */
function MonBillet({ id, statut }){
  const [b, setB] = useState(null);
  useEffect(() => {
    db.from('inscriptions_evenement').select('jeton,categories,statut,besoin')
      .eq('evenement_id', id).limit(1)
      .then(({data}) => setB(data && data[0]));
  }, [id]);
  if (!b) return null;

  if (statut === 'deposee') return html`
    <div class="alerte" style="margin-top:20px;border-left:3px solid var(--laiton)">
      Votre inscription est enregistrée et attend d\u2019être validée par les
      organisateurs. Votre billet apparaîtra ici une fois validée.
    </div>`;

  const m = qrMatrice(String(b.jeton));
  const N = m.length;

  return html`
    <div class="panneau" style="margin-top:20px;border-color:var(--vert)">
      <div class="tete" style="border-bottom-color:var(--vert)">
        <h3 style="font-size:17px">Votre billet</h3></div>
      <div class="corps" style="display:flex;gap:20px;align-items:center;flex-wrap:wrap">
        <div style="background:#fff;padding:8px;border:1px solid var(--filet);border-radius:6px">
          <svg viewBox=${'0 0 ' + N + ' ' + N} width="150" height="150"
            shape-rendering="crispEdges" style="display:block">
            <rect width=${N} height=${N} fill="#fff" />
            ${m.map((ligne,y) => ligne.map((v,x) => v
              ? html`<rect key=${y+'-'+x} x=${x} y=${y} width="1" height="1"
                  fill="#1E2A38" />` : null))}
          </svg>
        </div>
        <div style="flex:1;min-width:200px">
          <div class="small muted">Ce billet ouvre</div>
          <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:6px">
            ${(b.categories||[]).map((c,i) => html`<span class="tag vert" key=${i}>${c}</span>`)}
          </div>
          <div class="mono" style="margin-top:14px;letter-spacing:1px">${b.jeton}</div>
          <p class="small muted" style="margin:10px 0 0">
            Présentez ce code à l\u2019entrée. Il ne couvre que ce qui est listé
            ci-dessus, et ne donne accès à aucune donnée de votre compte.
          </p>
        </div>
      </div>
    </div>`;
}

/* --- La liste des inscrits ---------------------------------------------- */
function ListeInscrits({ id, inscrits, appel, titre, setMsg }){
  const [filtre, setFiltre] = useState('tous');
  const liste = inscrits.filter(x =>
    filtre === 'tous' ? true
    : filtre === 'a_valider' ? x.statut === 'deposee'
    : filtre === 'externes' ? x.externe
    : filtre === 'besoins' ? !!x.besoin
    : x.entrees.length > 0);

  function exporter(){
    const cols = ['Nom','Matricule','Courriel','Téléphone','Organisme','Externe',
                  'Catégories','Besoin','Statut','Entrées','Inscrit le'];
    const ech = v => { const t = String(v ?? '').replace(/"/g,'""');
                       return /[";\n]/.test(t) ? '"'+t+'"' : t; };
    const csv = '\ufeff' + cols.join(';') + '\n' + liste.map(x => [
      x.nom, x.matricule || '', x.courriel || '', x.telephone || '', x.organisme || '',
      x.externe ? 'oui' : 'non', (x.categories||[]).join(' + '), x.besoin || '',
      x.statut, (x.entrees||[]).join(' + '),
      new Date(x.cree_le).toLocaleString('fr-FR')
    ].map(ech).join(';')).join('\n');
    const url = URL.createObjectURL(new Blob([csv], { type:'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url; a.download = 'inscrits-' + titre.slice(0,30).replace(/[^\w]/g,'_') + '.csv';
    a.click(); URL.revokeObjectURL(url);
  }

  return html`
    <div>
      <div class="row" style="gap:8px;margin-bottom:16px;flex-wrap:wrap;align-items:center">
        ${[['tous','Tous'],['a_valider','À valider'],['externes','Extérieurs'],
           ['besoins','Besoins signalés'],['presents','Entrés']].map(([k,t]) => html`
          <button key=${k} class=${'btn sm ' + (filtre===k ? '' : 'light')}
            onClick=${()=>setFiltre(k)}>${t}</button>`)}
        <button class="btn sm light" onClick=${exporter}>Exporter en CSV</button>
      </div>

      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="corps muted">Aucun inscrit dans cette vue.</div>`
          : liste.map(x => html`
            <div class="ligne" key=${x.id} style="align-items:flex-start">
              <div style="flex:1;min-width:250px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span style="font-weight:600">${x.nom}</span>
                  ${x.externe && html`<span class="tag bleu">Extérieur</span>`}
                  ${x.statut === 'deposee' && html`<span class="tag or">À valider</span>`}
                  ${x.statut === 'refusee' && html`<span class="tag rouge">Refusé</span>`}
                  ${(x.entrees||[]).length > 0 && html`<span class="tag vert">Entré</span>`}
                </div>
                <div class="small muted" style="margin-top:3px">
                  ${x.matricule ? x.matricule + ' · ' : ''}${x.courriel || ''}
                  ${x.organisme ? ' · ' + x.organisme : ''}
                </div>
                <div class="row" style="gap:5px;margin-top:5px;flex-wrap:wrap">
                  ${(x.categories||[]).map((c,i) => html`
                    <span class="tag" key=${i}>${c}</span>`)}
                </div>
                ${x.besoin && html`<div class="small" style="margin-top:5px;
                  color:var(--laiton)">Besoin : ${x.besoin}</div>`}
              </div>
              ${x.statut === 'deposee' && html`
                <div class="row" style="gap:6px">
                  <button class="btn sm" onClick=${()=>appel('valider_inscription',
                    { p_id:x.id, p_ok:true, p_motif:null }, 'Inscription validée.')}>
                    Valider</button>
                  <button class="btn sm light" onClick=${()=>{
                    const m = prompt('Motif du refus (obligatoire)');
                    if (m) appel('valider_inscription',
                      { p_id:x.id, p_ok:false, p_motif:m }, 'Inscription refusée.');
                  }}>Refuser</button>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}

/* --- Le contrôle des entrées --------------------------------------------
   Un double passage est signalé avec l'heure du premier, jamais refusé
   en silence : une porte qui refuse sans expliquer crée une file et un
   conflit ; une porte qui informe laisse l'humain décider.
   --------------------------------------------------------------------- */
function ControleEntrees({ cats, setMsg, recharger }){
  const [categorie, setCategorie] = useState(cats[0]?.code || 'general');
  const [jeton, setJeton] = useState('');
  const [res, setRes] = useState(null);
  const [journal, setJournal] = useState([]);

  async function scanner(e){
    e.preventDefault();
    if (!jeton.trim()) return;
    const { data, error } = await db.rpc('controler_entree',
      { p_jeton: jeton.trim(), p_categorie: categorie });
    if (error) return setMsg('Erreur : ' + error.message);
    setRes(data); setJeton('');
    setJournal(j => [{ ...data, quand: new Date(), cat: categorie }, ...j].slice(0, 30));
    if (data.ok && !data.deja) recharger();
  }

  const teinte = !res ? '' : !res.ok ? 'err' : res.deja ? '' : 'ok';

  return html`
    <div>
      <div class="panneau" style="margin-bottom:20px">
        <div class="tete"><h3 style="font-size:17px">Contrôle des entrées</h3></div>
        <div class="corps stack">
          <div class="field" style="margin:0">
            <label>Quelle entrée contrôlez-vous ?</label>
            <select value=${categorie} onChange=${e=>setCategorie(e.target.value)}>
              ${cats.map(c => html`<option value=${c.code}>${c.nom}</option>`)}
            </select>
          </div>
          <form onSubmit=${scanner} class="row" style="gap:10px">
            <input value=${jeton} placeholder="Scanner ou saisir le code du billet"
              style="flex:1;min-width:220px" autofocus
              onInput=${e=>setJeton(e.target.value)} />
            <button class="btn">Contrôler</button>
          </form>

          ${res && html`
            <div class=${'alerte ' + teinte} style=${'margin:0;border-left:3px solid '
              + (!res.ok ? 'var(--rouge)' : res.deja ? 'var(--laiton)' : 'var(--vert)')}>
              <div style="font-weight:600">${res.message}</div>
              ${res.ok && res.externe && html`
                <div class="small" style="margin-top:4px">
                  Personne extérieure${res.organisme ? ' — ' + res.organisme : ''}</div>`}
              ${res.ok && res.besoin && html`
                <div class="small" style="margin-top:4px;color:var(--laiton)">
                  Besoin signalé : ${res.besoin}</div>`}
              ${res.ouvre && html`
                <div class="row" style="gap:5px;margin-top:6px;flex-wrap:wrap">
                  <span class="small muted">Ce billet ouvre :</span>
                  ${res.ouvre.map((c,i) => html`<span class="tag" key=${i}>${c}</span>`)}
                </div>`}
            </div>`}
        </div>
      </div>

      ${journal.length > 0 && html`
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Derniers contrôles</h3>
            <span class="tag">${journal.length}</span></div>
          ${journal.map((x,i) => html`
            <div class="ligne" key=${i}>
              <div style="flex:1;min-width:200px">
                <div>${x.membre || '—'}</div>
                <div class="small muted">${x.cat} ·
                  ${x.quand.toLocaleTimeString('fr-FR')}</div>
              </div>
              <span class=${'tag ' + (!x.ok ? 'rouge' : x.deja ? 'or' : 'vert')}>
                ${!x.ok ? 'Refusé' : x.deja ? 'Déjà passé' : 'Entré'}</span>
            </div>`)}
        </div>`}
    </div>`;
}

/* --- Les réglages -------------------------------------------------------- */
function ReglagesEvenement({ e, cats, lienPublic, appel, setMsg }){
  const [c, setC] = useState({ code:'', nom:'', description:'', capacite:'',
                               horaire:'', externe_admis:true, ordre:100 });
  const [modif, setModif] = useState(false);

  return html`
    <div>
      ${modif
        ? html`<${FormulaireEvenement} initial=${{
            id: e.id, titre: e.titre, objet: e.objet || '', nature: e.nature,
            ouverture: e.ouverture, lieu: e.lieu || '', adresse: e.adresse || '',
            debut: e.debut ? e.debut.slice(0,16) : '',
            fin: e.fin ? e.fin.slice(0,16) : '',
            capacite: e.capacite || '', validation_requise: false,
            cloture_inscriptions: '', conservation_jours: 180
          }} enregistrer=${async d => {
            const r = await appel('enregistrer_evenement', { d }, 'Événement mis à jour.');
            if (r) setModif(false);
          }} />`
        : html`
          <div class="panneau" style="margin-bottom:20px">
            <div class="tete spread">
              <h3 style="font-size:17px">L\u2019événement</h3>
              <button class="btn sm light" onClick=${()=>setModif(true)}>Modifier</button>
            </div>
            <div class="corps row" style="gap:10px;flex-wrap:wrap">
              ${e.statut === 'projet' && html`
                <button class="btn sm" onClick=${()=>appel('changer_statut_evenement',
                  { p_id: e.id, p_statut: 'ouvert', p_motif: null },
                  'Inscriptions ouvertes.')}>Ouvrir les inscriptions</button>`}
              ${e.statut === 'ouvert' && html`
                <button class="btn sm light" onClick=${()=>appel('changer_statut_evenement',
                  { p_id: e.id, p_statut: 'complet', p_motif: null },
                  'Événement marqué complet.')}>Marquer complet</button>
                <button class="btn sm light" onClick=${()=>appel('changer_statut_evenement',
                  { p_id: e.id, p_statut: 'clos', p_motif: null },
                  'Inscriptions closes.')}>Clore les inscriptions</button>`}
              ${e.statut !== 'annule' && html`
                <button class="btn sm danger" onClick=${()=>{
                  const m = prompt('Motif de l\u2019annulation (obligatoire) — '
                    + 'les inscrits doivent savoir pourquoi');
                  if (m) appel('changer_statut_evenement',
                    { p_id: e.id, p_statut: 'annule', p_motif: m }, 'Événement annulé.');
                }}>Annuler l\u2019événement</button>`}
            </div>
          </div>`}

      ${e.ouverture === 'ouverte' && html`
        <div class="panneau" style="margin-bottom:20px">
          <div class="tete"><h3 style="font-size:17px">Lien public d\u2019inscription</h3></div>
          <div class="corps">
            <p class="small muted" style="margin:0 0 12px">
              Ce lien s\u2019ouvre sans compte. Une personne extérieure y laisse son
              nom et son adresse, et reçoit un code à présenter à l\u2019entrée.
              Elle ne crée aucun compte et n\u2019accède à rien d\u2019autre.
            </p>
            <div class="row" style="gap:8px">
              <input readonly value=${lienPublic} style="flex:1;min-width:220px"
                onClick=${ev=>ev.target.select()} />
              <button class="btn sm light" onClick=${()=>{
                navigator.clipboard.writeText(lienPublic); setMsg('Lien copié.');
              }}>Copier</button>
            </div>
          </div>
        </div>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Catégories d\u2019entrée</h3>
          <span class="tag">${cats.length}</span></div>
        <div class="corps small muted" style="padding-bottom:0">
          Un billet n\u2019ouvre que les catégories auxquelles la personne s\u2019est
          inscrite. C\u2019est ce qui permet de répartir les entrées : plénière
          pour tous, atelier sur inscription, repas pour ceux qui l\u2019ont
          demandé.
        </div>
        ${cats.map(x => html`
          <div class="ligne" key=${x.code}>
            <div style="flex:1;min-width:200px">
              <div class="row" style="gap:8px;flex-wrap:wrap">
                <span>${x.nom}</span>
                <span class="mono muted small">${x.code}</span>
                ${!x.externe_admis && html`<span class="tag">Membres seulement</span>`}
              </div>
              <div class="small muted">${x.horaire || ''}
                ${x.capacite ? ' · ' + x.capacite + ' places' : ' · sans limite'}</div>
            </div>
            <span class="mono small muted">${x.inscrits} inscrit(s)</span>
          </div>`)}

        <form class="corps stack" onSubmit=${async ev => {
          ev.preventDefault();
          const r = await appel('regler_categorie',
            { d: { ...c, evenement_id: e.id } }, 'Catégorie enregistrée.');
          if (r) setC({ code:'', nom:'', description:'', capacite:'', horaire:'',
                        externe_admis:true, ordre:100 });
        }}>
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:0 0 130px;margin:0"><label>Code</label>
              <input value=${c.code} placeholder="atelier_a"
                onInput=${ev=>setC(o=>({...o,code:ev.target.value}))} /></div>
            <div class="field" style="flex:2;min-width:180px;margin:0"><label>Nom</label>
              <input value=${c.nom} placeholder="Atelier A — financement des projets"
                onInput=${ev=>setC(o=>({...o,nom:ev.target.value}))} /></div>
            <div class="field" style="flex:0 0 130px;margin:0"><label>Horaire</label>
              <input value=${c.horaire} placeholder="14h–16h"
                onInput=${ev=>setC(o=>({...o,horaire:ev.target.value}))} /></div>
            <div class="field" style="flex:0 0 110px;margin:0"><label>Places</label>
              <input type="number" min="1" value=${c.capacite}
                onInput=${ev=>setC(o=>({...o,capacite:ev.target.value}))} /></div>
          </div>
          <label class="row" style="gap:8px;align-items:center">
            <input type="checkbox" style="width:auto" checked=${c.externe_admis}
              onChange=${ev=>setC(o=>({...o,externe_admis:ev.target.checked}))} />
            <span class="small">Ouverte aux personnes extérieures</span>
          </label>
          <div><button class="btn sm">Ajouter ou modifier</button></div>
        </form>
      </div>
    </div>`;
}

/* --- La page publique d'inscription --------------------------------------
   Elle s'ouvre sans compte. On y laisse le minimum : de quoi être
   reconnu à l'entrée et prévenu si l'événement change. L'échéance
   d'effacement est annoncée, parce qu'une durée de conservation qu'on
   ne dit pas n'en est pas une.
   --------------------------------------------------------------------- */
export function EvenementPublic({ jeton }){
  const [e, setE] = useState(null);
  const [f, setF] = useState({ nom:'', prenom:'', email:'', telephone:'',
                               organisme:'', besoin:'', categories:[] });
  const [fait, setFait] = useState(null);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    db.rpc('evenement_public', { p_jeton: jeton }).then(({data}) => setE(data));
  }, [jeton]);

  if (!e) return html`
    <div class="contenu"><div class="vide" style="padding:80px">
      Cet événement n\u2019existe pas, ou n\u2019accepte plus d\u2019inscription.
    </div></div>`;

  async function envoyer(ev){
    ev.preventDefault();
    setMsg('');
    const { data, error } = await db.rpc('inscription_publique',
      { p_jeton: jeton, d: f });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg(data.message);
    setFait(data);
  }

  if (fait) return html`
    <div class="contenu" style="max-width:640px">
      <div class="panneau" style="margin-top:40px;border-color:var(--vert)">
        <div class="corps" style="text-align:center;padding:40px 24px">
          <div style=${'width:60px;height:60px;border-radius:50%;margin:0 auto 18px;'
            + 'background:var(--vert);color:#fff;display:flex;align-items:center;'
            + 'justify-content:center;font-size:30px'}>✓</div>
          <h2 style="font-size:21px;margin:0 0 10px">${e.titre}</h2>
          <p class="muted" style="margin:0 0 18px">${fait.message}</p>
          ${!fait.validation && html`
            <div class="mono" style=${'font-size:19px;letter-spacing:2px;padding:14px;'
              + 'background:var(--papier);border-radius:6px;display:inline-block'}>
              ${fait.jeton}</div>`}
          <p class="small muted" style="max-width:44ch;margin:18px auto 0">
            Un courriel vous sera envoyé si l\u2019événement change. Vos
            coordonnées seront effacées après l\u2019événement : elles ne servent
            qu\u2019à vous accueillir.
          </p>
        </div>
      </div>
    </div>`;

  return html`
    <div class="contenu" style="max-width:640px">
      <div style="margin-top:36px">
        <div class="eyebrow">${e.territoire || 'FFCE'}${
          e.partenaire ? ' · avec ' + e.partenaire : ''}</div>
        <h1 style="margin:8px 0 6px">${e.titre}</h1>
        <div class="muted">
          ${new Date(e.debut).toLocaleString('fr-FR',
            {weekday:'long', day:'numeric', month:'long', year:'numeric',
             hour:'2-digit', minute:'2-digit'})}
          ${e.lieu ? ' · ' + e.lieu : ''}
        </div>
        ${e.adresse && html`<div class="small muted">${e.adresse}</div>`}
        ${e.objet && html`<p style="margin-top:18px">${e.objet}</p>`}
      </div>

      ${!e.ouverte
        ? html`<div class="alerte" style="margin-top:24px">
            Les inscriptions ne sont pas ouvertes${
              e.cloture ? ' — elles étaient closes le ' + jour(e.cloture) : ''}.
          </div>`
        : html`
          <form onSubmit=${envoyer} class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">S\u2019inscrire</h3></div>
            <div class="corps stack">
              ${msg && html`<div class="alerte err" style="margin:0">${msg}</div>`}

              ${(e.categories||[]).length > 1 && html`
                <div class="field" style="margin:0">
                  <label>À quoi souhaitez-vous participer ?</label>
                  <div class="row" style="gap:6px;flex-wrap:wrap">
                    ${e.categories.map(c => html`
                      <button type="button" key=${c.code}
                        class=${'btn sm ' + (f.categories.includes(c.code) ? '' : 'light')}
                        disabled=${c.restantes !== null && c.restantes <= 0}
                        onClick=${()=>setF(o=>({...o, categories:
                          o.categories.includes(c.code)
                            ? o.categories.filter(x=>x!==c.code)
                            : [...o.categories, c.code]}))}>
                        ${c.nom}${c.horaire ? ' · ' + c.horaire : ''}${
                          c.restantes !== null && c.restantes <= 0 ? ' — complet' : ''}
                      </button>`)}
                  </div>
                </div>`}

              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:1;min-width:150px;margin:0">
                  <label>Prénom</label>
                  <input value=${f.prenom}
                    onInput=${ev=>setF(o=>({...o,prenom:ev.target.value}))} /></div>
                <div class="field" style="flex:1;min-width:150px;margin:0">
                  <label>Nom</label>
                  <input required value=${f.nom}
                    onInput=${ev=>setF(o=>({...o,nom:ev.target.value}))} /></div>
              </div>
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:1;min-width:180px;margin:0">
                  <label>Courriel</label>
                  <input required type="email" value=${f.email}
                    onInput=${ev=>setF(o=>({...o,email:ev.target.value}))} /></div>
                <div class="field" style="flex:1;min-width:150px;margin:0">
                  <label>Téléphone (facultatif)</label>
                  <input value=${f.telephone}
                    onInput=${ev=>setF(o=>({...o,telephone:ev.target.value}))} /></div>
              </div>
              <div class="field"><label>Organisme (facultatif)</label>
                <input value=${f.organisme}
                  onInput=${ev=>setF(o=>({...o,organisme:ev.target.value}))} /></div>
              <div class="field"><label>Un besoin à signaler ?</label>
                <input value=${f.besoin}
                  placeholder="Accessibilité, régime alimentaire…"
                  onInput=${ev=>setF(o=>({...o,besoin:ev.target.value}))} /></div>

              <p class="small muted" style="margin:0">
                Vos coordonnées servent uniquement à vous accueillir et à vous
                prévenir si l\u2019événement change. Elles sont effacées après
                l\u2019événement, et ne sont transmises à personne.
                ${e.validation_requise
                  ? ' Votre inscription sera examinée par les organisateurs.' : ''}
              </p>

              <div><button class="btn">M\u2019inscrire</button></div>
            </div>
          </form>`}
    </div>`;
}
