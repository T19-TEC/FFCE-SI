import { Postes } from './direction.js';
import { FilDossier } from './membre.js';
import { ETAPE_NOM, GRAVITE, MESURES, PHASES, PHASE_NOM, TYPE_AG, db, html, jour, nomComplet, useCallback, useEffect, useState } from './socle.js';

export function Discipline({ p }){
  const [onglet, setOnglet] = useState('ouverts');
  const [dossiers, setDossiers] = useState([]);
  const [archives, setArchives] = useState([]);
  const [suivis, setSuivis] = useState([]);
  const [gens, setGens] = useState([]);
  const [detail, setDetail] = useState(null);
  const [creation, setCreation] = useState(false);
  const [f, setF] = useState({profil:'', objet:'', qualification:'', gravite:'moyenne'});
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b,c,d] = await Promise.all([
      db.rpc('dossiers_discipline', { p_filtre: 'ouverts' }),
      db.rpc('dossiers_discipline', { p_filtre: 'archives' }),
      db.rpc('suivi_en_cours'),
      db.rpc('membres_pour_discipline', { p_recherche: null })
    ]);
    setDossiers(a.data||[]); setArchives(b.data||[]);
    setSuivis(c.data||[]); setGens(d.data||[]);
    if (detail){
      const maj = [...(a.data||[]), ...(b.data||[])].find(x => x.id === detail.id);
      if (maj) setDetail(maj);
    }
  }, [detail]);
  useEffect(() => { charger(); }, []);

  // Extraction du registre : la DAJ a dans sa mission de tenir une
  // sauvegarde à jour. Chaque extraction est tracée au journal.
  async function exporter(){
    const { data, error } = await db.rpc('registre_discipline');
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data || data.length === 0) return setMsg('Erreur : registre vide ou accès refusé.');

    const colonnes = Object.keys(data[0]);
    const echappe = v => {
      if (v === null || v === undefined) return '';
      const t = String(v).replace(/"/g, '""');
      return /[";\n]/.test(t) ? '"' + t + '"' : t;
    };
    const csv = '\ufeff' + colonnes.join(';') + '\n' +
      data.map(l => colonnes.map(c => echappe(l[c])).join(';')).join('\n');

    const nom = 'FFCE-registre-discipline-' +
      new Date().toISOString().slice(0,10) + '.csv';
    const url = URL.createObjectURL(new Blob([csv], {type:'text/csv;charset=utf-8'}));
    const a = document.createElement('a');
    a.href = url; a.download = nom; a.click();
    URL.revokeObjectURL(url);

    await db.rpc('tracer_export', { p_objet: nom, p_lignes: data.length });
    setMsg(data.length + ' ligne(s) extraites. Déposez le fichier sur le Drive de la fédération.');
  }

  async function ouvrir(e){
    e.preventDefault();
    const { data, error } = await db.rpc('ouvrir_dossier', {
      p_profil: f.profil, p_objet: f.objet,
      p_qualification: f.qualification || null, p_gravite: f.gravite, p_signalement: null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({profil:'', objet:'', qualification:'', gravite:'moyenne'}); setCreation(false);
    setMsg('Dossier ouvert. L\u2019intéressé est placé sous protection renforcée.');
    charger();
  }

  if (detail) return html`<${DossierDetail} p=${p} d=${detail} gens=${gens}
    fermer=${()=>{ setDetail(null); charger(); }} />`;

  const ligne = d => html`
    <div class="ligne" style="cursor:pointer" onClick=${()=>setDetail(d)}>
      <div style="flex:1;min-width:240px">
        <div>${d.objet}</div>
        <div class="small muted">
          <span class="mono">${d.reference}</span> · ${d.concerne}
          <span class="mono">${d.matricule}</span>
          ${d.territoire_nom ? ' · ' + d.territoire_nom : ''}
          · ${d.nb_pieces} pièce${d.nb_pieces>1?'s':''}
        </div>
        ${d.qualification && html`<div class="small muted">${d.qualification}</div>`}
      </div>
      <div class="row">
        ${d.recours_en_attente > 0 && html`
          <span class="tag or">${d.recours_en_attente} recours</span>`}
        <span class=${'tag '+(GRAVITE[d.gravite]||['',''])[1]}>
          ${(GRAVITE[d.gravite]||['',''])[0]}</span>
        <span class="tag">${ETAPE_NOM[d.statut]}</span>
      </div>
    </div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Discipline et recours</div>
          <h1 style="margin:6px 0 0">Dossiers</h1>
        </div>
        <button class="btn" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Ouvrir un dossier'}</button>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${creation && html`
        <form onSubmit=${ouvrir} class="panneau" style="margin-top:24px">
          <div class="corps stack">
            <div class="field"><label>Membre concerné</label>
              <select required value=${f.profil} onChange=${e=>setF(o=>({...o,profil:e.target.value}))}>
                <option value="">Choisir…</option>
                ${gens.map(g => html`<option value=${g.id}>
                  ${nomComplet(g)} — ${g.fonction_nom}${g.territoire_nom?' · '+g.territoire_nom:''}
                  ${g.dossiers_ouverts > 0 ? ' · '+g.dossiers_ouverts+' dossier(s) en cours' : ''}
                </option>`)}
              </select></div>
            <div class="field"><label>Objet</label>
              <input required value=${f.objet} onInput=${e=>setF(o=>({...o,objet:e.target.value}))}
                placeholder="Manquement au cadre d\u2019intervention du 12 mars" /></div>
            <div class="field"><label>Qualification retenue</label>
              <input value=${f.qualification}
                onInput=${e=>setF(o=>({...o,qualification:e.target.value}))}
                placeholder="Article 8 du règlement intérieur" /></div>
            <div class="field"><label>Gravité</label>
              <select value=${f.gravite} onChange=${e=>setF(o=>({...o,gravite:e.target.value}))}>
                <option value="faible">Faible</option>
                <option value="moyenne">Moyenne</option>
                <option value="elevee">Élevée</option>
              </select></div>
            <div><button class="btn">Ouvrir le dossier</button></div>
            <p class="small muted">
              L\u2019ouverture place l\u2019intéressé sous protection renforcée : toute
              consultation de son profil sera tracée et signalée.
            </p>
          </div>
        </form>`}

      <div class="spread" style="margin-top:24px">
        <span class="small muted">
          ${dossiers.length} dossier${dossiers.length>1?'s':''} en cours
          · ${archives.length} archivé${archives.length>1?'s':''}
        </span>
        <button class="btn light" onClick=${exporter}>Extraire le registre</button>
      </div>

      <div class="row" style="margin:24px 0;gap:0;border-bottom:1px solid var(--filet)">
        ${[['ouverts','En cours'],['suivi','Suivi des usages'],['archives','Archives']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--encre)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}${k==='suivi'&&suivis.length?' ('+suivis.length+')':''}</button>`)}
      </div>

      ${onglet === 'ouverts' && html`
        <div class="panneau">
          ${dossiers.length === 0
            ? html`<div class="vide">Aucun dossier en cours.</div>`
            : dossiers.map(ligne)}
        </div>`}

      ${onglet === 'archives' && html`
        <div class="panneau">
          ${archives.length === 0
            ? html`<div class="vide">Aucun dossier archivé.</div>`
            : archives.map(ligne)}
        </div>`}

      ${onglet === 'suivi' && html`<${SuiviUsages} recharger=${charger} />`}
    </div>`;
}


/* --- Suivi des usages, agrégé par membre -------------------------------
   Une liste d'événements bruts ne se suit pas. On regroupe par
   personne, avec la dernière activité et ce qui reste à examiner.
   --------------------------------------------------------------------- */
export function SuiviUsages({ recharger }){
  const [liste, setListe] = useState(null);
  const [detail, setDetail] = useState(null);
  const [evenements, setEvenements] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const { data } = await db.rpc('suivi_en_cours');
    setListe(data || []);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function ouvrir(x){
    setDetail(x);
    const { data } = await db.rpc('detail_suivi', { p_profil: x.profil_id });
    setEvenements(data || []);
  }

  async function marquer(x){
    const { data, error } = await db.rpc('marquer_suivi_vu', { p_profil: x.profil_id });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setMsg('Alertes classées.'); charger(); recharger && recharger();
  }

  if (!liste) return html`<div class="vide">Chargement…</div>`;

  if (detail) return html`
    <div>
      <button class="lien-discret" onClick=${()=>setDetail(null)}>← Tous les suivis</button>
      <h2 style="font-size:23px;margin:12px 0 4px">${detail.membre}</h2>
      <div class="small muted"><span class="mono">${detail.matricule}</span>
        ${detail.territoire_nom ? ' · ' + detail.territoire_nom : ''}
        · dossier <span class="mono">${detail.dossier_reference}</span></div>
      <div class="alerte" style="margin-top:16px">${detail.motif}</div>
      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Activité enregistrée</h3>
          <span class="tag">${evenements.length}</span></div>
        ${evenements.length === 0
          ? html`<div class="vide">Aucune activité depuis la mise sous suivi.</div>`
          : evenements.map(e => html`
            <div class="ligne">
              <span>${e.app_nom || e.application}</span>
              <div class="row">
                ${!e.vue_le && html`<span class="tag or">Non examinée</span>`}
                <span class="small muted">${new Date(e.cree_le).toLocaleString('fr-FR',
                  {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</span>
              </div>
            </div>`)}
      </div>
    </div>`;

  return html`
    <div>
      ${msg && html`<div class="alerte ok" style="margin-bottom:16px">${msg}</div>`}
      <p class="small muted" style="margin-bottom:16px;max-width:62ch">
        Ces comptes font l\u2019objet d\u2019une mesure de suivi prononcée et notifiée.
        Chaque ouverture d\u2019application y est enregistrée. La mesure s\u2019éteint
        seule à sa date de fin.
      </p>
      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Aucun compte sous mesure de suivi.</div>`
          : liste.map(x => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px;cursor:pointer" onClick=${()=>ouvrir(x)}>
                <div class="row" style="gap:8px">
                  <strong>${x.membre}</strong>
                  ${x.alertes_non_vues > 0 && html`
                    <span class="pastille">${x.alertes_non_vues}</span>`}
                </div>
                <div class="small muted">
                  <span class="mono">${x.matricule}</span>
                  ${x.territoire_nom ? ' · ' + x.territoire_nom : ''}
                  · dossier <span class="mono">${x.dossier_reference}</span>
                  ${x.instructeur ? ' · instruit par ' + x.instructeur : ''}
                </div>
                <div class="small muted" style="margin-top:4px">
                  Effet au ${jour(x.date_effet)}
                  ${x.date_fin ? ' · fin le ' + jour(x.date_fin) : ' · sans terme'}
                  · ${x.alertes_total} événement${x.alertes_total>1?'s':''}
                  ${x.derniere_activite
                    ? ' · dernière activité ' + jour(x.derniere_activite)
                    : ' · aucune activité'}
                </div>
                ${x.applications && html`<div class="small muted" style="margin-top:4px">
                  Trente derniers jours : ${x.applications}</div>`}
              </div>
              <div class="row">
                <button class="btn sm light" onClick=${()=>ouvrir(x)}>Détail</button>
                ${x.alertes_non_vues > 0 && html`
                  <button class="btn sm" onClick=${()=>marquer(x)}>Tout classer</button>`}
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function DossierDetail({ p, d, gens, fermer }){
  const [pieces, setPieces] = useState([]);
  const [mesures, setMesures] = useState([]);
  const [recours, setRecours] = useState([]);
  const [piece, setPiece] = useState({type:'note_instruction', titre:'', contenu:'', communicable:false});
  const [fichier, setFichier] = useState(null);
  const [courrier, setCourrier] = useState(null);

  // Dépôt d'un courrier dans le dépôt privé des dossiers.
  async function deposerCourrier(f){
    if (!f) return null;
    if (f.size > 10 * 1024 * 1024) throw new Error('Le courrier ne doit pas dépasser 10 Mo.');
    const ext = f.name.split('.').pop();
    const chemin = p.id + '/' + d.id + '-' + Date.now() + '.' + ext;
    const { error } = await db.storage.from('dossiers').upload(chemin, f);
    if (error) throw error;
    return chemin;
  }
  const [mes, setMes] = useState({type:'avertissement', motif:'', texte:'', effet:'', fin:''});
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b] = await Promise.all([
      db.from('dossier_pieces').select('*').eq('dossier_id', d.id).order('cree_le'),
      db.from('mesures').select('*').eq('dossier_id', d.id).order('prise_le', {ascending:false})
    ]);
    setPieces(a.data||[]); setMesures(b.data||[]);
    if (b.data && b.data.length){
      const { data: r } = await db.from('recours').select('*')
        .in('mesure_id', b.data.map(x => x.id)).order('cree_le',{ascending:false});
      setRecours(r||[]);
    }
  }, [d.id]);
  useEffect(() => { charger(); }, [charger]);

  const nomDe = i => { const g = gens.find(x => x.id === i); return g ? nomComplet(g) : '—'; };

  async function verser(e){
    e.preventDefault();
    let chemin = null;
    try {
      if (fichier){
        if (fichier.size > 10 * 1024 * 1024)
          throw new Error('Le document ne doit pas dépasser 10 Mo.');
        const ext = fichier.name.split('.').pop();
        chemin = p.id + '/' + d.id + '-' + Date.now() + '.' + ext;
        const { error: eUp } = await db.storage.from('dossiers').upload(chemin, fichier);
        if (eUp) throw eUp;
      }
    } catch (err){ return setMsg('Erreur : ' + (err.message||'téléversement impossible')); }

    const { data, error } = await db.rpc('verser_piece', {
      p_dossier: d.id, p_type: piece.type, p_titre: piece.titre,
      p_contenu: piece.contenu || null, p_fichier: chemin,
      p_communicable: piece.communicable
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setPiece({type:'note_instruction', titre:'', contenu:'', communicable:false});
    setFichier(null);
    setMsg('Pièce versée au dossier.'); charger();
  }

  async function ouvrirFichier(pc){
    const { data, error } = await db.storage.from('dossiers')
      .createSignedUrl(pc.fichier, 120);
    if (error) return setMsg('Document introuvable.');
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  async function prononcer(e){
    e.preventDefault();
    let chemin = null;
    try { chemin = await deposerCourrier(courrier); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('prononcer_mesure', {
      p_dossier: d.id, p_type: mes.type, p_motif: mes.motif,
      p_texte: mes.texte || null, p_effet: mes.effet || null, p_fin: mes.fin || null,
      p_fichier: chemin
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMes({type:'avertissement', motif:'', texte:'', effet:'', fin:''});
    setCourrier(null);
    setMsg('Mesure prononcée. Elle ne produira effet qu\u2019une fois notifiée.');
    charger();
  }

  async function notifier(m, f){
    if (!confirm('Notifier cette décision ? Elle deviendra exécutoire et le délai de recours s\u2019ouvrira.')) return;
    let chemin = null;
    try { chemin = await deposerCourrier(f); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('notifier_mesure',
      { p_mesure: m.id, p_courrier: chemin });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Décision notifiée.'); charger();
  }

  async function statuer(r, issue, f){
    const decision = prompt('Décision motivée (obligatoire)');
    if (!decision) return;
    let chemin = null;
    try { chemin = await deposerCourrier(f); }
    catch (err){ return setMsg('Erreur : ' + err.message); }
    const { data, error } = await db.rpc('statuer_recours', {
      p_recours: r.id, p_issue: issue, p_decision: decision,
      p_suspensif: false, p_fichier: chemin
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Recours tranché.'); charger();
  }

  async function clore(){
    const conclusion = prompt('Conclusion du dossier (obligatoire)');
    if (!conclusion) return;
    const { data, error } = await db.rpc('clore_dossier',
      { p_dossier: d.id, p_conclusion: conclusion });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    fermer();
  }

  return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Tous les dossiers</a>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:28px">${d.objet}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${d.reference}</span> · ${d.concerne}
            <span class="mono">${d.matricule}</span>
            ${d.territoire_nom ? ' · ' + d.territoire_nom : ''}
            · ouvert le ${jour(d.ouvert_le)}
          </div>
        </div>
        <span class=${'tag '+(GRAVITE[d.gravite]||['',''])[1]}>
          ${(GRAVITE[d.gravite]||['',''])[0]}</span>
      </div>

      <div class="panneau" style="margin-top:24px"><div class="corps">
        <${FilDossier} d=${d} />
      </div></div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Mesures</h3>
          <span class="tag">${mesures.length}</span></div>
        ${mesures.length === 0
          ? html`<div class="vide">Aucune mesure prononcée.</div>`
          : mesures.map(m => {
            const rs = recours.filter(r => r.mesure_id === m.id);
            return html`
              <div class="ligne" style="align-items:flex-start">
                <div style="flex:1;min-width:240px">
                  <div><strong>${MESURES[m.type]||m.type}</strong></div>
                  <div class="small" style="margin-top:4px">${m.motif}</div>
                  <div class="small muted" style="margin-top:4px">
                    Prononcée le ${jour(m.prise_le)} par ${nomDe(m.prise_par)}
                    · effet au ${jour(m.date_effet)}
                    ${m.date_fin ? ' · fin le ' + jour(m.date_fin) : ''}
                    ${m.notifiee_le ? ' · notifiée le ' + jour(m.notifiee_le) : ''}
                    ${m.accusee_le ? ' · réception accusée le ' + jour(m.accusee_le) : ''}
                  </div>
                  ${rs.map(r => html`
                    <div style="margin-top:12px;padding:12px;background:var(--papier);
                         border:1px solid var(--filet);border-radius:2px">
                      <div class="spread">
                        <span class="small"><strong>Recours du ${jour(r.cree_le)}</strong></span>
                        <span class="tag">${r.statut}</span>
                      </div>
                      <p class="small" style="margin:8px 0 0;white-space:pre-wrap">${r.contenu}</p>
                      ${r.decision
                        ? html`<p class="small muted" style="margin:8px 0 0">
                            Décision : ${r.decision}</p>`
                        : html`<div class="row" style="margin-top:12px">
                            <button class="btn sm" onClick=${()=>statuer(r,'accepte',null)}>Accueillir</button>
                            <button class="btn sm light" onClick=${()=>statuer(r,'rejete',null)}>Rejeter</button>
                            <button class="btn sm light" onClick=${()=>statuer(r,'irrecevable',null)}>Irrecevable</button>
                          </div>`}
                    </div>`)}
                </div>
                <div class="row">
                  <span class=${'tag '+(m.statut==='executee'?'rouge':m.statut==='annulee'?'vert':'')}>
                    ${m.statut}</span>
                  ${!m.notifiee_le && html`
                    <label class="btn sm light" style="margin:0;cursor:pointer;
                        text-transform:none;letter-spacing:.02em">
                      Joindre le courrier
                      <input type="file" accept=".pdf,image/*" style="display:none"
                        onChange=${ev => notifier(m, ev.target.files[0])} />
                    </label>
                    <button class="btn sm" onClick=${()=>notifier(m, null)}>Notifier</button>`}
                  ${m.fichier && html`<button class="btn sm light"
                    onClick=${()=>ouvrirFichier({fichier:m.fichier})}>Courrier</button>`}
                </div>
              </div>`;
          })}
      </div>

      ${d.statut === 'clos' && html`
        <div class="alerte" style="margin-top:24px;border-left-color:var(--laiton)">
          Ce dossier est clos et scellé le ${jour(d.clos_le)}. Aucune pièce, mesure
          ou recours ne peut plus y être versé.
          ${d.conclusion ? ' Conclusion : ' + d.conclusion : ''}
        </div>`}

      ${d.statut !== 'clos' && html`
      <form onSubmit=${prononcer} class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Prononcer une mesure</h3></div>
        <div class="corps stack">
          <div class="field"><label>Nature</label>
            <select value=${mes.type} onChange=${e=>setMes(o=>({...o,type:e.target.value}))}>
              ${Object.entries(MESURES).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
            </select></div>
          <div class="field"><label>Motif</label>
            <textarea required value=${mes.motif}
              onInput=${e=>setMes(o=>({...o,motif:e.target.value}))}
              placeholder="Les faits reprochés, les éléments retenus, la règle appliquée." /></div>
          <div class="field"><label>Texte complémentaire</label>
            <textarea value=${mes.texte} onInput=${e=>setMes(o=>({...o,texte:e.target.value}))} /></div>
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Date d\u2019effet</label>
              <input type="date" value=${mes.effet}
                onInput=${e=>setMes(o=>({...o,effet:e.target.value}))} /></div>
            <div class="field" style="flex:1;min-width:150px;margin:0"><label>Fin (facultatif)</label>
              <input type="date" value=${mes.fin}
                onInput=${e=>setMes(o=>({...o,fin:e.target.value}))} /></div>
          </div>
          <div class="field"><label>Courrier de décision (PDF)</label>
            <input type="file" accept=".pdf,image/*"
              onChange=${e=>setCourrier(e.target.files[0]||null)} />
            <p class="small muted" style="margin:6px 0 0">
              Il sera versé au dossier et communicable à l\u2019intéressé.</p>
          </div>
          <div><button class="btn">Prononcer</button></div>
          <p class="small muted">
            Une mesure prononcée ne produit aucun effet tant qu\u2019elle n\u2019a pas été
            notifiée. La notification ouvre le délai de recours.
          </p>
        </div>
      </form>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Pièces</h3>
          <span class="tag">${pieces.length}</span></div>
        ${pieces.map(pc => html`
          <div class="ligne">
            <div style="flex:1;min-width:240px">
              <div>${pc.fichier
                ? html`<a href="#" onClick=${e=>{e.preventDefault();ouvrirFichier(pc)}}>
                    ${pc.titre} ↗</a>`
                : pc.titre}</div>
              ${pc.contenu && html`<div class="small muted"
                style="margin-top:4px;white-space:pre-wrap;max-width:60ch">${pc.contenu}</div>`}
              <div class="small muted" style="margin-top:4px">
                ${pc.type} · ${nomDe(pc.auteur_id)} · ${jour(pc.cree_le)}</div>
            </div>
            ${pc.communicable
              ? html`<span class="tag vert">Communicable</span>`
              : html`<span class="tag or">Non communicable</span>`}
          </div>`)}
      </div>

      ${d.statut !== 'clos' && html`
      <form onSubmit=${verser} class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Verser une pièce</h3></div>
        <div class="corps stack">
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:180px;margin:0"><label>Nature</label>
              <select value=${piece.type} onChange=${e=>setPiece(o=>({...o,type:e.target.value}))}>
                <option value="note_instruction">Note d\u2019instruction</option>
                <option value="temoignage">Témoignage</option>
                <option value="piece_jointe">Pièce</option>
                <option value="convocation">Convocation</option>
              </select></div>
            <div class="field" style="flex:1;min-width:200px;margin:0"><label>Titre</label>
              <input required value=${piece.titre}
                onInput=${e=>setPiece(o=>({...o,titre:e.target.value}))} /></div>
          </div>
          <div class="field"><label>Contenu</label>
            <textarea value=${piece.contenu}
              onInput=${e=>setPiece(o=>({...o,contenu:e.target.value}))} /></div>
          <label class="row" style="text-transform:none;letter-spacing:0;
              font-size:14px;color:var(--encre);margin:0;cursor:pointer">
            <input type="checkbox" style="width:auto" checked=${piece.communicable}
              onChange=${e=>setPiece(o=>({...o,communicable:e.target.checked}))} />
            <span>Communicable à l\u2019intéressé</span>
          </label>
          <p class="small muted">
            Une pièce non communicable existe et reste datée au dossier, mais son
            contenu n\u2019est pas ouvert — cela protège l\u2019identité d\u2019un témoin.
            Le contradictoire suppose que ce soit l\u2019exception.
          </p>
          <div class="field">
            <label>Document</label>
            <input type="file" accept="image/*,.pdf,.doc,.docx"
              onChange=${e=>setFichier(e.target.files[0]||null)} />
          </div>
          <div><button class="btn">Verser</button></div>
        </div>
      </form>`}

      ${d.statut !== 'clos' && html`
        <div style="margin-top:32px">
          <button class="btn light" onClick=${clore}>Clore le dossier</button>
          <p class="small muted" style="margin-top:8px">
            La clôture scelle le dossier. Tous les recours doivent avoir été
            tranchés au préalable.
          </p>
        </div>`}
    </div>`;
}


export function Assemblees({ p }){
  const [liste, setListe] = useState(null);
  const [ouverte, setOuverte] = useState(null);
  const [creation, setCreation] = useState(false);
  const [terr, setTerr] = useState([]);
  const [renouveler, setRenouveler] = useState([]);
  const [f, setF] = useState({territoire:'', titre:'', type:'ordinaire', date:'',
    lieu:'', ordre:'', cloture_cand:'', ouverture_scrutin:'', cloture_scrutin:'',
    quorum:'25', duree:'3'});
  const [msg, setMsg] = useState('');

  const organise = p.niveau >= 60 || (p.postes||[]).length > 0;

  const charger = useCallback(async () => {
    const [a, b, c] = await Promise.all([
      db.rpc('mes_assemblees'),
      db.from('territoires').select('id,nom,echelle').eq('actif',true).order('echelle').order('nom'),
      db.rpc('mandats_a_renouveler')
    ]);
    setListe(a.data||[]); setTerr(b.data||[]); setRenouveler(c.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function creer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('creer_assemblee', {
      p_territoire: f.territoire, p_titre: f.titre, p_type: f.type,
      p_date: f.date, p_lieu: f.lieu || null, p_ordre_du_jour: f.ordre || null,
      p_cloture_cand: f.cloture_cand || null,
      p_ouverture_scrutin: f.ouverture_scrutin || null,
      p_cloture_scrutin: f.cloture_scrutin || null,
      p_quorum: Number(f.quorum||0), p_duree: Number(f.duree||3)
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setCreation(false); setMsg('Assemblée convoquée. L\u2019appel à candidatures est ouvert.');
    charger(); setOuverte(data.id);
  }

  if (!liste) return html`<div class="vide">Chargement…</div>`;
  if (ouverte) return html`<${Assemblee} p=${p} id=${ouverte}
    fermer=${()=>{ setOuverte(null); charger(); }} />`;

  const enCours = liste.filter(x => x.statut !== 'proclamee' && x.statut !== 'annulee');
  const passees = liste.filter(x => x.statut === 'proclamee' || x.statut === 'annulee');
  const aFaire = liste.filter(x =>
    (x.statut === 'candidatures' && x.electeur && !x.ma_candidature) ||
    (x.statut === 'scrutin' && x.electeur && !x.a_vote));

  const ligne = x => html`
    <div class="ligne" style="cursor:pointer" onClick=${()=>setOuverte(x.id)}>
      <div style="flex:1;min-width:230px">
        <div class="row" style="gap:8px">
          <span>${x.titre}</span>
          ${x.type === 'constitutive' && html`<span class="tag or">Constitutive</span>`}
        </div>
        <div class="small muted">
          <span class="mono">${x.reference}</span> · ${x.territoire}
          · ${new Date(x.date_tenue).toLocaleDateString('fr-FR',
              {day:'numeric',month:'long',year:'numeric'})}
          ${x.lieu ? ' · ' + x.lieu : ''}
        </div>
        <div class="small muted">
          ${x.candidats} candidature${x.candidats>1?'s':''}
          ${x.inscrits ? ' · ' + x.votants + '/' + x.inscrits + ' votants' : ''}
        </div>
      </div>
      <div class="row">
        ${x.statut === 'scrutin' && x.electeur && !x.a_vote && html`
          <span class="tag rouge">À voter</span>`}
        ${x.a_vote && html`<span class="tag vert">Vous avez voté</span>`}
        ${x.ma_candidature && html`<span class="tag bleu">Candidat</span>`}
        <span class="tag">${PHASE_NOM[x.statut]}</span>
      </div>
    </div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Vie statutaire</div>
          <h1 style="margin:6px 0 0">Assemblées et mandats</h1>
        </div>
        ${organise && html`<button class="btn" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Convoquer une assemblée'}</button>`}
      </div>
      <p class="muted" style="max-width:60ch;margin-top:12px">
        Un mandat électif vient du vote des adhérents et a un terme fixé par les
        statuts. Il ne se retire pas par décision : il s\u2019éteint, ou une
        nouvelle assemblée le renouvelle.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${aFaire.length > 0 && html`
        <div class="alerte" style="margin-top:24px;border-left-color:var(--bordeaux)">
          ${aFaire.length} assemblée${aFaire.length>1?'s':''} attend
          ${aFaire.length>1?'ent':''} votre participation.
        </div>`}

      ${renouveler.length > 0 && organise && html`
        <div class="panneau" style="margin-top:24px;border-color:var(--brun)">
          <div class="tete" style="border-bottom-color:var(--brun)">
            <h3 style="font-size:17px">Mandats arrivant à terme</h3>
            <span class="tag or">${renouveler.length}</span>
          </div>
          ${renouveler.map(m => html`
            <div class="ligne">
              <div>
                <div>${m.membre} — ${m.poste_nom}</div>
                <div class="small muted">${m.territoire || 'National'}
                  · mandat du ${jour(m.debut)} au ${jour(m.fin)}</div>
              </div>
              <span class=${'tag '+(m.jours_restants < 0 ? 'rouge' : 'or')}>
                ${m.jours_restants < 0
                  ? 'Échu depuis ' + Math.abs(m.jours_restants) + ' j'
                  : m.jours_restants + ' jours'}</span>
            </div>`)}
        </div>`}

      ${creation && html`
        <form onSubmit=${creer} class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Convocation</h3></div>
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:2;min-width:200px;margin:0"><label>Structure</label>
                <select required value=${f.territoire}
                  onChange=${e=>setF(o=>({...o,territoire:e.target.value}))}>
                  <option value="">Choisir…</option>
                  ${terr.map(t => html`<option value=${t.id}>${t.nom} (${t.echelle})</option>`)}
                </select></div>
              <div class="field" style="flex:1;min-width:170px;margin:0"><label>Nature</label>
                <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
                  ${Object.entries(TYPE_AG).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
                </select></div>
            </div>
            <div class="field"><label>Intitulé</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))}
                placeholder="Assemblée générale constitutive de l\u2019unité locale de Foix" /></div>
            <div class="field"><label>Ordre du jour</label>
              <textarea value=${f.ordre}
                onInput=${e=>setF(o=>({...o,ordre:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:190px;margin:0"><label>Date de tenue</label>
                <input type="datetime-local" required value=${f.date}
                  onInput=${e=>setF(o=>({...o,date:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:190px;margin:0"><label>Lieu</label>
                <input value=${f.lieu} onInput=${e=>setF(o=>({...o,lieu:e.target.value}))} /></div>
            </div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:170px;margin:0">
                <label>Clôture des candidatures</label>
                <input type="date" value=${f.cloture_cand}
                  onInput=${e=>setF(o=>({...o,cloture_cand:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:190px;margin:0">
                <label>Clôture du scrutin</label>
                <input type="datetime-local" value=${f.cloture_scrutin}
                  onInput=${e=>setF(o=>({...o,cloture_scrutin:e.target.value}))} /></div>
            </div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Quorum requis (%)</label>
                <input type="number" min="0" max="100" value=${f.quorum}
                  onInput=${e=>setF(o=>({...o,quorum:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Durée du mandat (ans)</label>
                <input type="number" min="1" max="6" value=${f.duree}
                  onInput=${e=>setF(o=>({...o,duree:e.target.value}))} /></div>
            </div>
            <div><button class="btn">Convoquer</button></div>
            <p class="small muted">
              Un quorum non atteint interdit la proclamation. Fixez-le selon vos
              statuts — 25 % est un usage courant pour une unité locale.
            </p>
          </div>
        </form>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">En cours</h3>
          <span class="tag">${enCours.length}</span></div>
        ${enCours.length === 0
          ? html`<div class="vide">Aucune assemblée en cours.</div>`
          : enCours.map(ligne)}
      </div>

      ${passees.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Archives</h3></div>
          ${passees.map(ligne)}
        </div>`}
    </div>`;
}


export function Assemblee({ p, id, fermer }){
  const [a, setA] = useState(null);
  const [cands, setCands] = useState([]);
  const [corps, setCorps] = useState([]);
  const [dep, setDep] = useState(null);
  const [choix, setChoix] = useState({});
  const [foi, setFoi] = useState('');
  const [postePostule, setPostePostule] = useState('');
  const [postes, setPostes] = useState([]);
  const [msg, setMsg] = useState('');

  const organise = p.niveau >= 60 || (p.postes||[]).length > 0;

  const charger = useCallback(async () => {
    const [l, c, e, d, po] = await Promise.all([
      db.rpc('mes_assemblees'),
      db.from('candidatures').select('*').eq('assemblee_id', id),
      db.rpc('corps_electoral', { p_assemblee: id }),
      db.rpc('depouillement', { p_assemblee: id }),
      db.from('postes').select('code,nom,description').eq('actif',true)
    ]);
    setA((l.data||[]).find(x => x.id === id) || null);
    setCorps(e.data||[]); setDep(d.data); setPostes(po.data||[]);

    const cs = c.data || [];
    if (cs.length){
      const { data: gens } = await db.from('v_annuaire')
        .select('id,prenom,nom,matricule,fonction_nom').in('id', cs.map(x=>x.profil_id));
      const m = Object.fromEntries((gens||[]).map(g => [g.id, g]));
      setCands(cs.map(x => ({...x, personne: m[x.profil_id]})));
    } else setCands([]);
  }, [id]);
  useEffect(() => { charger(); }, [charger]);

  if (!a) return html`<div class="vide">Assemblée introuvable.</div>`;
  const i = PHASES.indexOf(a.statut);
  const nomPoste = c => (postes.find(x=>x.code===c)||{}).nom || c;

  async function postuler(e){
    e.preventDefault();
    const { data, error } = await db.rpc('deposer_candidature', {
      p_assemblee: id, p_poste: postePostule, p_profession_foi: foi, p_fichier: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setFoi(''); setPostePostule(''); setMsg('Candidature déposée.'); charger();
  }

  async function examiner(c, ok){
    const motif = ok ? null : prompt('Motif de l\u2019irrecevabilité (obligatoire)');
    if (!ok && !motif) return;
    const { data, error } = await db.rpc('examiner_candidature',
      { p_id: c.id, p_recevable: ok, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    charger();
  }

  async function phase(st){
    const { data, error } = await db.rpc('changer_phase_assemblee',
      { p_assemblee: id, p_statut: st });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Phase modifiée.'); charger();
  }

  async function envoyerVote(){
    const postesOuverts = [...new Set(cands.filter(c=>c.statut==='recevable').map(c=>c.poste))];
    if (postesOuverts.some(x => !choix[x]))
      return setMsg('Erreur : exprimez-vous sur chaque poste, ou votez blanc.');
    if (!confirm('Votre vote est définitif. Confirmez-vous ?')) return;
    const { data, error } = await db.rpc('voter', { p_assemblee: id, p_choix: choix });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Vote enregistré. Merci.'); charger();
  }

  async function proclamerResultats(){
    const pv = prompt('Procès-verbal (obligatoire)\n\nRésumé des opérations, incidents éventuels, résultats.');
    if (!pv) return;
    const { data, error } = await db.rpc('proclamer',
      { p_assemblee: id, p_pv: pv, p_pv_fichier: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(data.elus + ' mandat(s) proclamé(s), jusqu\u2019au ' + jour(data.fin_mandat) + '.');
    charger();
  }

  const lienPublic = location.origin + location.pathname + '#/appel/' + a.public_token;
  const recevables = cands.filter(c => c.statut === 'recevable');
  const postesOuverts = [...new Set(recevables.map(c => c.poste))];

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Toutes les assemblées</button>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:28px">${a.titre}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${a.reference}</span> · ${a.territoire}
            · ${new Date(a.date_tenue).toLocaleString('fr-FR',
                {day:'numeric',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'})}
            ${a.lieu ? ' · ' + a.lieu : ''}
          </div>
        </div>
        <span class="tag">${PHASE_NOM[a.statut]}</span>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="panneau" style="margin-top:24px"><div class="corps">
        <div class="row" style="gap:0;flex-wrap:nowrap;overflow-x:auto">
          ${PHASES.map((ph, n) => html`
            <div style=${'flex:1;min-width:96px;padding-right:8px;'+(n<=i?'':'opacity:.35')}>
              <div style=${'height:3px;background:'+(n<=i?'var(--bleu)':'var(--filet)')}></div>
              <div class="small" style="margin-top:6px;line-height:1.3">${PHASE_NOM[ph]}</div>
            </div>`)}
        </div>
      </div></div>

      ${organise && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Appel public</h3></div>
          <div class="corps">
            <p class="small muted" style="margin:0 0 10px">
              Ce lien s\u2019ouvre sans compte : diffusez-le pour toucher des
              personnes qui ne sont pas encore sur la plateforme.
            </p>
            <div class="row" style="gap:8px">
              <input readonly value=${lienPublic} style="flex:1;min-width:220px"
                onClick=${e=>e.target.select()} />
              <button class="btn sm light" onClick=${()=>{
                navigator.clipboard.writeText(lienPublic); setMsg('Lien copié.');
              }}>Copier</button>
            </div>
          </div>
          <div class="corps row" style="border-top:1px solid var(--filet);gap:10px">
            ${a.statut === 'candidatures' && html`
              <button class="btn sm" onClick=${()=>phase('scrutin')}>Ouvrir le scrutin</button>`}
            ${a.statut === 'scrutin' && html`
              <button class="btn sm" onClick=${()=>phase('depouillement')}>Clore le scrutin</button>`}
            ${(a.statut === 'depouillement' || a.statut === 'scrutin') && html`
              <button class="btn sm" onClick=${proclamerResultats}>Proclamer</button>`}
          </div>
        </div>`}

      ${a.statut === 'candidatures' && a.electeur && !a.ma_candidature && html`
        <form onSubmit=${postuler} class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Me porter candidat</h3></div>
          <div class="corps stack">
            <div class="field"><label>Poste</label>
              <select required value=${postePostule}
                onChange=${e=>setPostePostule(e.target.value)}>
                <option value="">Choisir…</option>
                ${postes.filter(x => x.code.endsWith('_structure')).map(x =>
                  html`<option value=${x.code}>${x.nom}</option>`)}
              </select></div>
            <div class="field"><label>Profession de foi</label>
              <textarea required value=${foi} style="min-height:140px"
                onInput=${e=>setFoi(e.target.value)}
                placeholder="Ce que vous voulez faire, pourquoi, et ce que vous savez faire." /></div>
            <div><button class="btn">Déposer ma candidature</button></div>
            <p class="small muted">
              Elle sera visible des électeurs et sur l\u2019appel public, sous la
              forme « Prénom N. ».
            </p>
          </div>
        </form>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Candidatures</h3>
          <span class="tag">${cands.length}</span></div>
        ${cands.length === 0
          ? html`<div class="vide">Aucune candidature déposée.</div>`
          : cands.map(c => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <strong>${c.personne ? nomComplet(c.personne) : 'Membre'}</strong>
                  <span class="tag">${nomPoste(c.poste)}</span>
                </div>
                <p class="small" style="margin:8px 0 0;white-space:pre-wrap;max-width:60ch">
                  ${c.profession_foi}</p>
                ${c.motif && html`<p class="small" style="margin:6px 0 0;color:var(--bordeaux)">
                  ${c.motif}</p>`}
              </div>
              <div class="row">
                <span class=${'tag '+(c.statut==='elue'?'vert':
                  c.statut==='recevable'?'bleu':c.statut==='irrecevable'?'rouge':'')}>
                  ${c.statut}</span>
                ${organise && c.statut === 'deposee' && html`
                  <button class="btn sm" onClick=${()=>examiner(c,true)}>Recevable</button>
                  <button class="btn sm light" onClick=${()=>examiner(c,false)}>Écarter</button>`}
              </div>
            </div>`)}
      </div>

      ${a.statut === 'scrutin' && a.electeur && !a.a_vote && postesOuverts.length > 0 && html`
        <div class="panneau" style="margin-top:24px;border-color:var(--bordeaux)">
          <div class="tete" style="border-bottom-color:var(--bordeaux)">
            <h3 style="font-size:17px">Votre bulletin</h3>
          </div>
          <div class="corps">
            <p class="small muted" style="margin:0 0 16px">
              Votre vote est secret : la plateforme enregistre que vous avez voté,
              et ce qui a été voté, mais jamais le lien entre les deux.
            </p>
            ${postesOuverts.map(po => html`
              <div style="margin-bottom:20px;padding-bottom:16px;
                   border-bottom:1px solid var(--filet)">
                <div class="eyebrow" style="margin-bottom:10px">${nomPoste(po)}</div>
                ${recevables.filter(c => c.poste === po).map(c => html`
                  <label class="row" style="text-transform:none;letter-spacing:0;
                      font-size:15px;color:var(--nuit);padding:7px 0;margin:0;cursor:pointer">
                    <input type="radio" style="width:auto" name=${'p_'+po}
                      checked=${choix[po] === c.id}
                      onChange=${()=>setChoix(o=>({...o,[po]:c.id}))} />
                    <span>${c.personne ? nomComplet(c.personne) : 'Candidat'}</span>
                  </label>`)}
                <label class="row" style="text-transform:none;letter-spacing:0;
                    font-size:15px;color:var(--gris);padding:7px 0;margin:0;cursor:pointer">
                  <input type="radio" style="width:auto" name=${'p_'+po}
                    checked=${choix[po] === 'blanc'}
                    onChange=${()=>setChoix(o=>({...o,[po]:'blanc'}))} />
                  <span>Voter blanc</span>
                </label>
              </div>`)}
            <button class="btn" onClick=${envoyerVote}>Déposer mon bulletin</button>
            <p class="small muted" style="margin:10px 0 0">Le vote est définitif.</p>
          </div>
        </div>`}

      ${dep && (a.statut === 'depouillement' || a.statut === 'proclamee' || organise) && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Participation</h3>
            <span class=${'tag '+(dep.quorum_atteint?'vert':'rouge')}>
              ${dep.quorum_atteint ? 'Quorum atteint' : 'Quorum non atteint'}</span></div>
          <div class="ligne"><span class="muted">Inscrits</span>
            <span class="mono">${dep.inscrits}</span></div>
          <div class="ligne"><span class="muted">Votants</span>
            <span class="mono">${dep.votants}</span></div>
          <div class="ligne"><span class="muted">Participation</span>
            <span class="mono">${dep.participation} %
              ${dep.quorum_requis > 0 ? ' (quorum ' + dep.quorum_requis + ' %)' : ''}</span></div>
        </div>`}

      ${dep && Object.keys(dep.resultats||{}).length > 0 &&
        (a.statut === 'depouillement' || a.statut === 'proclamee') && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Résultats</h3></div>
          <div class="corps">
            ${Object.entries(dep.resultats).map(([po, lignes]) => {
              const total = lignes.reduce((n,x)=>n+x.voix,0) || 1;
              return html`
                <div style="margin-bottom:22px">
                  <div class="eyebrow" style="margin-bottom:10px">${po}</div>
                  ${lignes.map((x, n) => html`
                    <div style="padding:6px 0">
                      <div class="spread small">
                        <span>${n===0 && a.statut==='proclamee'
                          ? html`<strong>${x.nom}</strong>` : x.nom}</span>
                        <span class="mono">${x.voix} voix · ${Math.round(x.voix/total*100)} %</span>
                      </div>
                      <div class="jauge" style="margin-top:5px">
                        <i style=${'width:'+Math.round(x.voix/total*100)+'%;background:'+
                          (x.candidature_id ? 'var(--bleu)' : 'var(--gris-bleu)')}></i></div>
                    </div>`)}
                </div>`;
            })}
          </div>
        </div>`}

      ${a.statut === 'scrutin' && a.electeur && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Émargement</h3>
            <span class="tag">${corps.filter(c=>c.a_vote).length}/${corps.length}</span></div>
          <div class="corps">
            <div class="row" style="gap:6px">
              ${corps.map(c => html`
                <span class=${'tag '+(c.a_vote?'vert':'')}>${c.membre}</span>`)}
            </div>
            <p class="small muted" style="margin:12px 0 0">
              L\u2019émargement est ouvert au corps électoral : chacun doit pouvoir
              vérifier le quorum. Le contenu des bulletins, lui, n\u2019est
              accessible à personne.
            </p>
          </div>
        </div>`}
    </div>`;
}

/* --- L'appel public, hors connexion ----------------------------------- */

export function AppelPublic({ token }){
  const [a, setA] = useState(undefined);
  useEffect(() => {
    db.rpc('appel_public', { p_token: token }).then(({data}) => setA(data || null));
  }, [token]);

  if (a === undefined) return html`<div class="vide" style="padding:120px">Chargement…</div>`;
  if (!a) return html`
    <section class="bloc blanc"><div class="wrap">
      <h1>Appel introuvable</h1>
      <p style="margin-top:16px">Ce lien n\u2019est plus valide.
        <a href="#/">Retour à l\u2019accueil</a></p>
    </div></section>`;

  return html`
    <section class="bloc blanc">
      <div class="wrap" style="max-width:780px">
        <div class="eyebrow">Appel à candidatures</div>
        <h1 style="margin:8px 0 12px">${a.titre}</h1>
        <p class="muted">${a.chemin || a.territoire}
          · <span class="mono">${a.reference}</span></p>

        <div class="panneau" style="margin-top:32px">
          <div class="tete"><h3 style="font-size:17px">L\u2019assemblée</h3>
            <span class="tag">${PHASE_NOM[a.statut] || a.statut}</span></div>
          <div class="ligne"><span class="muted">Date</span>
            <span>${new Date(a.date_tenue).toLocaleString('fr-FR',
              {day:'numeric',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'})}</span></div>
          ${a.lieu && html`<div class="ligne"><span class="muted">Lieu</span>
            <span>${a.lieu}</span></div>`}
          ${a.cloture && html`<div class="ligne"><span class="muted">Dépôt des candidatures</span>
            <span>jusqu\u2019au ${jour(a.cloture)}</span></div>`}
          <div class="ligne"><span class="muted">Durée des mandats</span>
            <span>${a.duree_mandat} an${a.duree_mandat>1?'s':''}</span></div>
        </div>

        ${a.ordre_du_jour && html`
          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">Ordre du jour</h3></div>
            <div class="corps" style="white-space:pre-wrap">${a.ordre_du_jour}</div>
          </div>`}

        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Postes à pourvoir</h3></div>
          ${(a.postes||[]).map(x => html`
            <div class="ligne">
              <div><div>${x.nom}</div>
                <div class="small muted" style="max-width:52ch">${x.description||''}</div></div>
            </div>`)}
        </div>

        ${(a.candidats||[]).length > 0 && html`
          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">Candidatures déclarées</h3></div>
            ${a.candidats.map(c => html`
              <div class="ligne" style="align-items:flex-start">
                <div>
                  <div class="row" style="gap:8px">
                    <strong>${c.nom}</strong><span class="tag">${c.poste}</span>
                  </div>
                  <p class="small muted" style="margin:8px 0 0;white-space:pre-wrap;max-width:56ch">
                    ${c.profession_foi}</p>
                </div>
              </div>`)}
          </div>`}

        ${a.resultats && html`
          <div class="panneau" style="margin-top:24px;border-color:var(--bleu)">
            <div class="tete" style="border-bottom-color:var(--bleu)">
              <h3 style="font-size:17px">Résultats proclamés</h3></div>
            ${a.resultats.map(r => html`
              <div class="ligne">
                <div><div>${r.poste}</div>
                  <div class="small muted">Mandat jusqu\u2019au ${jour(r.fin)}</div></div>
                <strong>${r.elu}</strong>
              </div>`)}
          </div>`}

        <div class="panneau" style="margin-top:32px">
          <div class="corps">
            <h3 style="font-size:17px;margin-bottom:8px">Vous voulez vous présenter ?</h3>
            <p class="small muted">
              Seuls les membres actifs rattachés à ce territoire peuvent déposer
              une candidature. Si vous n\u2019êtes pas encore adhérent, c\u2019est le
              moment.
            </p>
            <div class="row" style="margin-top:16px">
              <a class="btn" href="#/inscription">Adhérer à la fédération</a>
              <a class="btn ghost" href="#/espace">J\u2019ai déjà un compte</a>
            </div>
          </div>
        </div>
      </div>
    </section>`;
}

export function Conformite({ p }){
  const [cands, setCands] = useState([]);
  const [scrutins, setScrutins] = useState([]);
  const [archives, setArchives] = useState([]);
  const [onglet, setOnglet] = useState('candidatures');
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b,c] = await Promise.all([
      db.rpc('conformite_a_traiter'),
      db.rpc('scrutins_a_arreter'),
      db.rpc('archives_electorales', { p_territoire: null })
    ]);
    setCands(a.data||[]); setScrutins(b.data||[]); setArchives(c.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function examiner(c, ok){
    const motif = ok ? null : prompt('Motif de l\u2019irrecevabilité (obligatoire)');
    if (!ok && !motif) return;
    const { data, error } = await db.rpc('examiner_candidature',
      { p_id: c.candidature_id, p_recevable: ok, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Décision enregistrée et transmise à l\u2019administrateur.'); charger();
  }

  async function phase(s, st){
    const { data, error } = await db.rpc('changer_phase_assemblee',
      { p_assemblee: s.assemblee_id, p_statut: st });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Phase modifiée.'); charger();
  }

  const aFaire = scrutins.filter(s => s.action);

  return html`
    <div>
      <div class="eyebrow">Conformité des élections</div>
      <h1 style="margin:6px 0 8px">Contrôle des scrutins</h1>
      <p class="muted" style="max-width:60ch">
        La recevabilité des candidatures, l\u2019ouverture et la clôture du scrutin,
        la proclamation : chacune de ces décisions est inscrite au registre des
        actes et remonte à l\u2019administrateur.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:30px">${cands.length}</div>
          <div class="l">Candidatures à examiner</div></div>
        <div><div class="n" style="font-size:30px">${aFaire.length}</div>
          <div class="l">Scrutins en attente</div></div>
        <div><div class="n" style="font-size:30px">${archives.length}</div>
          <div class="l">Scrutins archivés</div></div>
        <div><div class="n" style="font-size:30px">
          ${cands.filter(c => c.jours_avant_cloture !== null
            && c.jours_avant_cloture <= 3).length}</div>
          <div class="l">Clôture imminente</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['candidatures','Candidatures'],['scrutins','Scrutins'],['archives','Archives']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'candidatures' && html`
        <div class="panneau">
          ${cands.length === 0
            ? html`<div class="vide">Aucune candidature en attente d\u2019examen.</div>`
            : cands.map(c => html`
              <div class="ligne" style="align-items:flex-start">
                <div style="flex:1;min-width:250px">
                  <div class="row" style="gap:8px">
                    <strong>${c.candidat}</strong>
                    <span class="tag">${c.poste_nom}</span>
                    ${c.jours_avant_cloture !== null && c.jours_avant_cloture <= 3 && html`
                      <span class="tag rouge">
                        ${c.jours_avant_cloture < 0 ? 'Clôture passée'
                          : 'Clôture dans ' + c.jours_avant_cloture + ' j'}</span>`}
                  </div>
                  <div class="small muted" style="margin-top:4px">
                    <span class="mono">${c.matricule}</span> · ${c.assemblee}
                    · ${c.territoire||''}
                    · déposée le ${jour(c.depose_le)}
                  </div>
                  <p class="small" style="margin:8px 0 0;white-space:pre-wrap;max-width:58ch">
                    ${c.profession_foi}</p>
                </div>
                <div class="row">
                  <button class="btn sm" onClick=${()=>examiner(c,true)}>Recevable</button>
                  <button class="btn sm light" onClick=${()=>examiner(c,false)}>Écarter</button>
                </div>
              </div>`)}
        </div>`}

      ${onglet === 'scrutins' && html`
        <div class="panneau">
          ${scrutins.length === 0
            ? html`<div class="vide">Aucun scrutin en cours.</div>`
            : scrutins.map(sc => html`
              <div class="ligne">
                <div style="flex:1;min-width:240px">
                  <div>${sc.titre}</div>
                  <div class="small muted">
                    <span class="mono">${sc.reference}</span> · ${sc.territoire||''}
                    · ${jour(sc.date_tenue)}
                  </div>
                  <div class="small muted">
                    ${sc.candidatures_a_examiner} à examiner ·
                    ${sc.recevables} recevable${sc.recevables>1?'s':''}
                    ${sc.inscrits ? ' · ' + sc.votants + '/' + sc.inscrits + ' votants' : ''}
                  </div>
                </div>
                <div class="row">
                  ${sc.action && html`<span class="tag or">${sc.action}</span>`}
                  ${sc.statut === 'candidatures' && sc.recevables > 0 && html`
                    <button class="btn sm" onClick=${()=>phase(sc,'scrutin')}>
                      Ouvrir le scrutin</button>`}
                  ${sc.statut === 'scrutin' && html`
                    <button class="btn sm" onClick=${()=>phase(sc,'depouillement')}>
                      Clore</button>`}
                  <a class="btn sm light" href="#/espace/assemblees">Ouvrir</a>
                </div>
              </div>`)}
        </div>`}

      ${onglet === 'archives' && html`<${ArchivesElectorales} archives=${archives} />`}
    </div>`;
}


export function ArchivesElectorales({ archives }){
  const [ouvert, setOuvert] = useState(null);
  return html`
    <div>
      <p class="small muted" style="margin-bottom:16px;max-width:62ch">
        Les procès-verbaux sont consultables par les électeurs du scrutin, par les
        membres du territoire concerné, et sans limite par la direction des
        affaires juridiques.
      </p>
      <div class="panneau">
        ${archives.length === 0
          ? html`<div class="vide">Aucun scrutin archivé.</div>`
          : archives.map(a => html`
            <div style="border-bottom:1px solid var(--filet)">
              <div class="ligne" style="cursor:pointer;border:0"
                onClick=${()=>setOuvert(ouvert===a.assemblee_id?null:a.assemblee_id)}>
                <div style="flex:1;min-width:230px">
                  <div class="row" style="gap:8px">
                    <span>${a.titre}</span>
                    ${a.jai_participe && html`<span class="tag vert">Vous avez voté</span>`}
                  </div>
                  <div class="small muted">
                    <span class="mono">${a.reference}</span> · ${a.territoire||''}
                    · ${jour(a.date_tenue)}
                    · ${a.votants}/${a.inscrits} votants (${a.participation} %)
                  </div>
                </div>
                <button class="btn sm light">
                  ${ouvert===a.assemblee_id ? 'Replier' : 'Consulter'}</button>
              </div>
              ${ouvert === a.assemblee_id && html`
                <div class="corps" style="background:var(--papier)">
                  <div class="eyebrow" style="margin-bottom:10px">Élus</div>
                  ${(a.elus||[]).map(e => html`
                    <div class="spread small" style="padding:4px 0">
                      <span>${e.poste} — <strong>${e.elu}</strong></span>
                      <span class="muted">${e.voix} voix · mandat jusqu\u2019au ${jour(e.fin)}</span>
                    </div>`)}
                  ${a.proces_verbal && html`
                    <div style="margin-top:18px">
                      <div class="eyebrow" style="margin-bottom:8px">Procès-verbal</div>
                      <div class="small" style="white-space:pre-wrap">${a.proces_verbal}</div>
                    </div>`}
                  <div class="small muted" style="margin-top:14px">
                    Proclamé le ${jour(a.proclame_le)}
                  </div>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}
