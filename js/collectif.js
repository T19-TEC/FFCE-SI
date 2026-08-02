import { ProfilInterne } from './membre.js';
import { aller, db, html, jour, nomComplet, useCallback, useEffect, useState } from './socle.js';
import { Rejoindre } from './vitrine.js';

   ===================================================================== */

export function Groupes({ p }){
  const [liste, setListe] = useState(null);
  const [miens, setMiens] = useState({});
  const [certifs, setCertifs] = useState([]);
  const [terr, setTerr] = useState([]);
  const [creer, setCreer] = useState(false);
  const [f, setF] = useState({nom:'',objet:'',territoire:'',certification:'',niveau:'10',ouvert:'true'});
  const [msg, setMsg] = useState('');

  const peutCreer = p.echelon >= 3 || p.niveau >= 50;

  const charger = useCallback(async () => {
    const [{ data: gs }, { data: ms }, { data: cs }, { data: ts }] = await Promise.all([
      db.from('v_groupes').select('*').eq('statut','actif').order('nom'),
      db.from('gt_membres').select('groupe_id,role,statut').eq('profil_id', p.id),
      db.from('certifications').select('code,nom').eq('actif', true).order('nom'),
      db.from('territoires').select('id,nom,echelle').order('echelle').order('nom')
    ]);
    setListe(gs || []);
    setMiens(Object.fromEntries((ms||[]).map(m => [m.groupe_id, m])));
    setCertifs(cs || []); setTerr(ts || []);
  }, [p.id]);

  useEffect(() => { charger(); }, [charger]);

  async function rejoindre(id){
    setMsg('');
    const { data, error } = await db.rpc('rejoindre_groupe', { p_groupe: id });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    charger();
  }

  async function repondre(id, oui){
    await db.rpc('repondre_invitation', { p_groupe: id, p_accepte: oui });
    charger();
  }

  async function envoyerCreation(e){
    e.preventDefault(); setMsg('');
    const { data, error } = await db.rpc('creer_groupe', {
      p_nom: f.nom, p_objet: f.objet,
      p_territoire: f.territoire || null,
      p_certification: f.certification || null,
      p_niveau_min: Number(f.niveau),
      p_ouvert: f.ouvert === 'true'
    });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setCreer(false); setF({nom:'',objet:'',territoire:'',certification:'',niveau:'10',ouvert:'true'});
    aller('/espace/groupe/' + data.id);
  }

  if (!liste) return html`<div class="vide">Chargement…</div>`;

  const invitations = liste.filter(g => miens[g.id]?.statut === 'invite');
  const mesGroupes  = liste.filter(g => miens[g.id]?.statut === 'actif');
  const autres      = liste.filter(g => !miens[g.id] || miens[g.id].statut === 'parti');

  const carteGroupe = (g, action) => html`
    <div class="ligne">
      <div style="flex:1;min-width:220px">
        <div>${g.nom}</div>
        <div class="small muted">${g.objet || ''}</div>
        <div class="row" style="margin-top:8px;gap:6px">
          <span class="tag">${g.nb_membres} membre${g.nb_membres>1?'s':''}</span>
          ${g.territoire_nom && html`<span class="tag">${g.territoire_nom}</span>`}
          ${g.certification_nom && html`<span class="tag or">${g.certification_nom} requis</span>`}
          ${!g.ouvert && html`<span class="tag">Sur invitation</span>`}
        </div>
      </div>
      ${action}
    </div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Groupes de travail</div>
          <h1 style="margin:6px 0 0">Projets et chantiers</h1>
        </div>
        ${peutCreer && html`<button class="btn" onClick=${()=>setCreer(c=>!c)}>
          ${creer ? 'Annuler' : 'Créer un groupe'}</button>`}
      </div>
      <p class="muted" style="max-width:58ch;margin-top:12px">
        Certains groupes exigent une certification. Vous l\u2019obtenez en
        achevant la formation correspondante.
      </p>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:24px">${msg}</div>`}

      <div style="margin-top:24px">
        <${CandidaturesGroupe} setMsg=${setMsg} />
        <${GroupesOuverts} setMsg=${setMsg} />
      </div>

      ${creer && html`
        <form onSubmit=${envoyerCreation} class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Nouveau groupe</h3></div>
          <div class="corps stack">
            <div class="field"><label>Nom</label>
              <input required value=${f.nom} onInput=${e=>setF(o=>({...o,nom:e.target.value}))} /></div>
            <div class="field"><label>Objet</label>
              <textarea required value=${f.objet}
                onInput=${e=>setF(o=>({...o,objet:e.target.value}))}
                placeholder="À quoi sert ce groupe, en deux phrases."></textarea></div>
            <div class="field"><label>Périmètre</label>
              <select value=${f.territoire} onChange=${e=>setF(o=>({...o,territoire:e.target.value}))}>
                <option value="">National — ouvert à tous</option>
                ${terr.map(t => html`<option value=${t.id}>${t.nom} (${t.echelle})</option>`)}
              </select></div>
            <div class="field"><label>Certification exigée</label>
              <select value=${f.certification} onChange=${e=>setF(o=>({...o,certification:e.target.value}))}>
                <option value="">Aucune</option>
                ${certifs.map(c => html`<option value=${c.code}>${c.nom}</option>`)}
              </select></div>
            <div class="field"><label>Entrée</label>
              <select value=${f.ouvert} onChange=${e=>setF(o=>({...o,ouvert:e.target.value}))}>
                <option value="true">Libre — on rejoint seul</option>
                <option value="false">Sur invitation du responsable</option>
              </select></div>
            <div><button class="btn">Créer le groupe</button></div>
            <p class="small muted">Vous en serez le responsable.</p>
          </div>
        </form>`}

      ${invitations.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Invitations reçues</h3>
            <span class="tag bleu">${invitations.length}</span></div>
          ${invitations.map(g => carteGroupe(g, html`
            <div class="row">
              <button class="btn sm" onClick=${()=>repondre(g.id,true)}>Accepter</button>
              <button class="btn sm light" onClick=${()=>repondre(g.id,false)}>Décliner</button>
            </div>`))}
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Mes groupes</h3>
          <span class="tag">${mesGroupes.length}</span></div>
        ${mesGroupes.length === 0
          ? html`<div class="vide">Vous ne participez à aucun groupe pour l\u2019instant.</div>`
          : mesGroupes.map(g => carteGroupe(g, html`
              <div class="row">
                ${miens[g.id]?.role === 'responsable' && html`<span class="tag or">Responsable</span>`}
                <a class="btn sm" href=${'#/espace/groupe/'+g.id}>Ouvrir</a>
              </div>`))}
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Autres groupes</h3></div>
        ${autres.length === 0
          ? html`<div class="vide">Rien d\u2019autre à rejoindre.</div>`
          : autres.map(g => carteGroupe(g,
              g.ouvert
                ? html`<button class="btn sm light" onClick=${()=>rejoindre(g.id)}>Rejoindre</button>`
                : html`<span class="tag">Sur invitation</span>`))}
      </div>
    </div>`;
}


export function Groupe({ p, id }){
  const [g, setG] = useState(null);
  const [onglet, setOnglet] = useState('taches');
  const [membres, setMembres] = useState([]);
  const [docs, setDocs] = useState([]);
  const [taches, setTaches] = useState([]);
  const [gens, setGens] = useState({});     // id → profil, pour les noms
  const [msg, setMsg] = useState('');
  const [refuse, setRefuse] = useState('');

  const charger = useCallback(async () => {
    const { data: gr } = await db.from('v_groupes').select('*').eq('id', id).maybeSingle();
    setG(gr);
    if (!gr) return;

    const { data: ms } = await db.from('gt_membres').select('*').eq('groupe_id', id);
    setMembres(ms || []);

    const [{ data: ds }, { data: ts }] = await Promise.all([
      db.from('gt_documents').select('*').eq('groupe_id', id).order('cree_le', {ascending:false}),
      db.from('gt_taches').select('*').eq('groupe_id', id).order('echeance', {nullsFirst:false})
    ]);
    setDocs(ds || []); setTaches(ts || []);

    // gt_taches pointe deux fois vers profils : on lit les noms à part.
    const ids = [...new Set([
      ...(ms||[]).map(m => m.profil_id),
      ...(ts||[]).map(t => t.assigne_a).filter(Boolean),
      ...(ds||[]).map(d => d.depose_par).filter(Boolean)
    ])];
    if (ids.length){
      const { data: ps } = await db.from('v_annuaire')
        .select('id,prenom,nom,matricule,fonction_nom,echelon').in('id', ids);
      setGens(Object.fromEntries((ps||[]).map(x => [x.id, x])));
    }
  }, [id]);

  useEffect(() => { charger(); }, [charger]);

  useEffect(() => { (async () => {
    const { data } = await db.rpc('obstacle_groupe', { p_groupe: id });
    setRefuse(data || '');
  })(); }, [id]);

  if (!g) return html`<div class="vide">Groupe introuvable ou fermé.</div>`;

  const moi = membres.find(m => m.profil_id === p.id && m.statut === 'actif');
  const responsable = moi?.role === 'responsable' || p.niveau >= 90;

  if (!moi) return html`
    <div>
      <a class="small" href="#/espace/groupes">← Tous les groupes</a>
      <h1 style="margin:12px 0 8px">${g.nom}</h1>
      <p class="muted" style="max-width:58ch">${g.objet||''}</p>
      <div class="alerte" style="margin-top:24px">
        ${refuse
          ? refuse
          : (g.ouvert
              ? 'Vous ne participez pas encore à ce groupe.'
              : 'Ce groupe se rejoint sur invitation de son responsable.')}
      </div>
      ${!refuse && g.ouvert && html`
        <div style="margin-top:24px">
          <button class="btn" onClick=${async ()=>{
            const { data } = await db.rpc('rejoindre_groupe', { p_groupe: id });
            if (data?.ok) charger(); else setMsg(data?.message||'');
          }}>Rejoindre ce groupe</button>
        </div>`}
      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}
    </div>`;

  return html`
    <div>
      <a class="small" href="#/espace/groupes">← Tous les groupes</a>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1>${g.nom}</h1>
          <div class="row" style="margin-top:8px;gap:6px">
            <span class="tag">${g.nb_membres} membre${g.nb_membres>1?'s':''}</span>
            ${g.territoire_nom && html`<span class="tag">${g.territoire_nom}</span>`}
            ${g.certification_nom && html`<span class="tag or">${g.certification_nom}</span>`}
            ${responsable && html`<span class="tag or">Vous êtes responsable</span>`}
          </div>
        </div>
      </div>
      <p class="muted" style="max-width:60ch;margin-top:16px">${g.objet||''}</p>

      <div style="margin-top:24px">
        <button class="btn light" onClick=${async ()=>{
          const { data } = await db.rpc('conversation_groupe', { p_groupe: id });
          if (data?.ok) aller('/espace/messagerie'); else setMsg(data?.message||'');
        }}>Ouvrir la discussion du groupe</button>
      </div>

      <div class="row" style="margin:32px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['taches','Tâches'],['documents','Documents'],['membres','Membres']].map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--encre)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${msg && html`<div class="alerte err" style="margin-bottom:16px">${msg}</div>`}

      ${onglet === 'taches' && html`<${GtTaches} p=${p} groupe=${g} taches=${taches}
        membres=${membres} gens=${gens} responsable=${responsable} recharger=${charger} />`}
      ${onglet === 'documents' && html`<${GtDocuments} p=${p} groupe=${g} docs=${docs}
        gens=${gens} responsable=${responsable} recharger=${charger} />`}
      ${onglet === 'membres' && html`<${GtMembres} p=${p} groupe=${g} membres=${membres}
        gens=${gens} responsable=${responsable} recharger=${charger} />`}
    </div>`;
}


export function GtTaches({ p, groupe, taches, membres, gens, responsable, recharger }){
  const [ouvrir, setOuvrir] = useState(false);
  const [f, setF] = useState({titre:'',description:'',assigne:'',echeance:'',priorite:'normale'});
  const [msg, setMsg] = useState('');

  const actifs = membres.filter(m => m.statut === 'actif');

  async function ajouter(e){
    e.preventDefault(); setMsg('');
    const { error } = await db.from('gt_taches').insert({
      groupe_id: groupe.id, titre: f.titre, description: f.description || null,
      assigne_a: f.assigne || null, echeance: f.echeance || null,
      priorite: f.priorite, cree_par: p.id
    });
    if (error) return setMsg(error.message);
    setF({titre:'',description:'',assigne:'',echeance:'',priorite:'normale'});
    setOuvrir(false); recharger();
  }

  async function changer(t, statut){
    const { error } = await db.from('gt_taches').update({
      statut, faite_le: statut === 'faite' ? new Date().toISOString() : null
    }).eq('id', t.id);
    if (error) setMsg(error.message);
    recharger();
  }

  const enCours = taches.filter(t => t.statut === 'a_faire' || t.statut === 'en_cours');
  const closes  = taches.filter(t => t.statut === 'faite' || t.statut === 'abandonnee');
  const retard  = t => t.echeance && new Date(t.echeance) < new Date() && t.statut !== 'faite';

  const ligneTache = t => html`
    <div class="ligne">
      <div style="flex:1;min-width:220px">
        <div style=${t.statut==='faite'||t.statut==='abandonnee' ? 'opacity:.55' : ''}>${t.titre}</div>
        ${t.description && html`<div class="small muted">${t.description}</div>`}
        <div class="row" style="margin-top:8px;gap:6px">
          ${t.assigne_a
            ? html`<span class="tag bleu">${nomComplet(gens[t.assigne_a]||{})}</span>`
            : html`<span class="tag">Non assignée</span>`}
          ${t.echeance && html`<span class=${'tag'+(retard(t)?' rouge':'')}>
            ${retard(t)?'En retard · ':''}${jour(t.echeance)}</span>`}
          ${t.priorite === 'haute' && html`<span class="tag rouge">Prioritaire</span>`}
        </div>
      </div>
      <div class="row">
        ${t.statut === 'a_faire' && html`
          <button class="btn sm light" onClick=${()=>changer(t,'en_cours')}>Commencer</button>`}
        ${(t.statut === 'a_faire' || t.statut === 'en_cours') && html`
          <button class="btn sm" onClick=${()=>changer(t,'faite')}>Terminer</button>`}
        ${(t.statut === 'faite' || t.statut === 'abandonnee') && html`
          <button class="btn sm light" onClick=${()=>changer(t,'a_faire')}>Rouvrir</button>`}
      </div>
    </div>`;

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <span class="small muted">${enCours.length} tâche${enCours.length>1?'s':''} en cours</span>
        <button class="btn sm" onClick=${()=>setOuvrir(o=>!o)}>
          ${ouvrir ? 'Annuler' : 'Ajouter une tâche'}</button>
      </div>
      ${msg && html`<div class="alerte err" style="margin-bottom:16px">${msg}</div>`}

      ${ouvrir && html`
        <form onSubmit=${ajouter} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Intitulé</label>
              <input required value=${f.titre} onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field"><label>Précisions</label>
              <textarea value=${f.description} onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:180px"><label>Assignée à</label>
                <select value=${f.assigne} onChange=${e=>setF(o=>({...o,assigne:e.target.value}))}>
                  <option value="">Personne</option>
                  ${actifs.map(m => html`<option value=${m.profil_id}>
                    ${nomComplet(gens[m.profil_id]||{})}</option>`)}
                </select></div>
              <div class="field" style="flex:1;min-width:140px;margin-top:0"><label>Échéance</label>
                <input type="date" value=${f.echeance}
                  onInput=${e=>setF(o=>({...o,echeance:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin-top:0"><label>Priorité</label>
                <select value=${f.priorite} onChange=${e=>setF(o=>({...o,priorite:e.target.value}))}>
                  <option value="basse">Basse</option>
                  <option value="normale">Normale</option>
                  <option value="haute">Haute</option>
                </select></div>
            </div>
            <div><button class="btn">Ajouter</button></div>
          </div>
        </form>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">À faire</h3></div>
        ${enCours.length === 0
          ? html`<div class="vide">Rien en cours. C\u2019est peut-être le moment d\u2019ajouter une tâche.</div>`
          : enCours.map(ligneTache)}
      </div>

      ${closes.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Terminées</h3>
            <span class="tag">${closes.length}</span></div>
          ${closes.map(ligneTache)}
        </div>`}
    </div>`;
}


export function GtDocuments({ p, groupe, docs, gens, responsable, recharger }){
  const [ouvrir, setOuvrir] = useState(false);
  const [f, setF] = useState({titre:'',type:'drive',url:'',description:''});
  const [msg, setMsg] = useState('');

  const libelle = { lien:'Lien', drive:'Drive', docs:'Document', sheets:'Tableur',
                    agenda:'Agenda', note:'Note' };

  async function ajouter(e){
    e.preventDefault(); setMsg('');
    const { error } = await db.from('gt_documents').insert({
      groupe_id: groupe.id, titre: f.titre, type: f.type,
      url: f.url || null, description: f.description || null, depose_par: p.id
    });
    if (error) return setMsg(error.message);
    setF({titre:'',type:'drive',url:'',description:''}); setOuvrir(false); recharger();
  }

  async function retirer(d){
    if (!confirm('Retirer « ' + d.titre + ' » de ce groupe ?')) return;
    await db.from('gt_documents').delete().eq('id', d.id);
    recharger();
  }

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <span class="small muted">
          Les fichiers restent sur le Drive de la fédération. On n\u2019en garde ici que le lien.
        </span>
        <button class="btn sm" onClick=${()=>setOuvrir(o=>!o)}>
          ${ouvrir ? 'Annuler' : 'Ajouter un document'}</button>
      </div>
      ${msg && html`<div class="alerte err" style="margin-bottom:16px">${msg}</div>`}

      ${ouvrir && html`
        <form onSubmit=${ajouter} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Titre</label>
              <input required value=${f.titre} onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field"><label>Nature</label>
              <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
                ${Object.entries(libelle).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
              </select></div>
            <div class="field"><label>Adresse</label>
              <input type="url" value=${f.url} placeholder="https://docs.google.com/…"
                onInput=${e=>setF(o=>({...o,url:e.target.value}))} /></div>
            <div class="field"><label>À quoi sert ce document</label>
              <textarea value=${f.description}
                onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
            <div><button class="btn">Ajouter</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${docs.length === 0
          ? html`<div class="vide">Aucun document partagé pour l\u2019instant.</div>`
          : docs.map(d => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div>${d.url
                  ? html`<a href=${d.url} target="_blank" rel="noopener">${d.titre} ↗</a>`
                  : d.titre}</div>
                ${d.description && html`<div class="small muted">${d.description}</div>`}
                <div class="row" style="margin-top:8px;gap:6px">
                  <span class="tag">${libelle[d.type]||d.type}</span>
                  <span class="small muted">
                    ${nomComplet(gens[d.depose_par]||{})} · ${jour(d.cree_le)}</span>
                </div>
              </div>
              ${(d.depose_par === p.id || responsable) && html`
                <button class="btn sm light" onClick=${()=>retirer(d)}>Retirer</button>`}
            </div>`)}
      </div>
    </div>`;
}


export function GtMembres({ p, groupe, membres, gens, responsable, recharger }){
  const [candidats, setCandidats] = useState([]);
  const [choix, setChoix] = useState('');
  const [msg, setMsg] = useState('');

  useEffect(() => { (async () => {
    if (!responsable) return;
    const { data } = await db.rpc('destinataires_possibles');
    setCandidats(data || []);
  })(); }, [responsable]);

  async function inviter(e){
    e.preventDefault(); setMsg('');
    const { data, error } = await db.rpc('inviter_au_groupe',
      { p_groupe: groupe.id, p_profil: choix });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setChoix(''); setMsg('Invitation envoyée.'); recharger();
  }

  async function changerRole(m, role){
    await db.from('gt_membres').update({ role }).eq('id', m.id);
    recharger();
  }

  async function retirer(m){
    if (!confirm('Retirer ce membre du groupe ?')) return;
    await db.from('gt_membres').update({ statut: 'parti' }).eq('id', m.id);
    recharger();
  }

  async function partir(){
    const { data } = await db.rpc('quitter_groupe', { p_groupe: groupe.id });
    if (!data.ok) return setMsg(data.message);
    aller('/espace/groupes');
  }

  const dejaLa = new Set(membres.map(m => m.profil_id));
  const actifs = membres.filter(m => m.statut === 'actif');
  const invites = membres.filter(m => m.statut === 'invite');

  return html`
    <div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Invitation')?'ok':'err')}
        style="margin-bottom:16px">${msg}</div>`}

      ${responsable && html`
        <form onSubmit=${inviter} class="panneau" style="margin-bottom:24px">
          <div class="tete"><h3 style="font-size:17px">Inviter un membre</h3></div>
          <div class="corps row" style="align-items:flex-end;gap:12px">
            <div class="field" style="flex:1;min-width:220px;margin:0">
              <label>Membre</label>
              <select required value=${choix} onChange=${e=>setChoix(e.target.value)}>
                <option value="">Choisir…</option>
                ${candidats.filter(c => !dejaLa.has(c.id)).map(c => html`
                  <option value=${c.id}>${nomComplet(c)} — ${c.fonction_nom}</option>`)}
              </select>
            </div>
            <button class="btn">Inviter</button>
          </div>
        </form>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Membres</h3>
          <span class="tag">${actifs.length}</span></div>
        ${actifs.map(m => {
          const g = gens[m.profil_id] || {};
          return html`
            <div class="ligne">
              <div>
                <div>${nomComplet(g)}
                  ${m.role === 'responsable' && html`<span class="tag or"
                    style="margin-left:8px">Responsable</span>`}</div>
                <div class="small muted">${g.fonction_nom||''}
                  <span class="mono">${g.matricule||''}</span></div>
              </div>
              ${responsable && m.profil_id !== p.id && html`
                <div class="row">
                  ${m.role === 'membre'
                    ? html`<button class="btn sm light"
                        onClick=${()=>changerRole(m,'responsable')}>Nommer responsable</button>`
                    : html`<button class="btn sm light"
                        onClick=${()=>changerRole(m,'membre')}>Retirer la responsabilité</button>`}
                  <button class="btn sm light" onClick=${()=>retirer(m)}>Retirer</button>
                </div>`}
            </div>`;
        })}
      </div>

      ${invites.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Invitations en attente</h3></div>
          ${invites.map(m => html`
            <div class="ligne">
              <div>${nomComplet(gens[m.profil_id]||{})}</div>
              <span class="tag bleu">Invité</span>
            </div>`)}
        </div>`}

      <div style="margin-top:32px">
        <button class="btn light" onClick=${partir}>Quitter ce groupe</button>
      </div>
    </div>`;
}


/* =====================================================================
   5 quater. MESSAGERIE
   Conversations privées et de groupe. La supervision hiérarchique est
   annoncée à l'écran, toujours — c'est une obligation, pas une option.

   ===================================================================== */

export function Messagerie({ p, ouvrir }){
  const [convs, setConvs] = useState(null);
  const [active, setActive] = useState(ouvrir || null);
  const [nouvelle, setNouvelle] = useState(false);
  const [candidats, setCandidats] = useState([]);
  const [mesGroupes, setMesGroupes] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const { data, error } = await db.rpc('mes_conversations');
    if (error) setMsg(error.message);
    setConvs(data || []);
  }, []);

  useEffect(() => { charger(); }, [charger]);

  useEffect(() => { (async () => {
    // Voir l'annuaire et pouvoir écrire sont deux droits distincts :
    // un adhérent ne consulte pas la liste de son département, mais il
    // peut y adresser un message. D'où cette fonction dédiée.
    const [{ data: ps }, { data: ms }] = await Promise.all([
      db.rpc('destinataires_possibles'),
      db.from('gt_membres').select('groupe_id').eq('profil_id', p.id).eq('statut','actif')
    ]);
    setCandidats(ps || []);
    if (ms && ms.length){
      const { data: gs } = await db.from('v_groupes').select('id,nom')
        .in('id', ms.map(m => m.groupe_id));
      setMesGroupes(gs || []);
    }
  })(); }, [p.id]);

  async function ouvrirPrivee(idAutre){
    setMsg('');
    const { data, error } = await db.rpc('conversation_privee', { p_autre: idAutre });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setNouvelle(false); setActive(data.id); charger();
  }

  async function ouvrirGroupe(idG){
    setMsg('');
    const { data, error } = await db.rpc('conversation_groupe', { p_groupe: idG });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setNouvelle(false); setActive(data.id); charger();
  }

  if (!convs) return html`<div class="vide">Chargement…</div>`;

  if (active) return html`<${Conversation} p=${p} id=${active}
    fermer=${() => { setActive(null); charger(); }} />`;

  const nonLus = convs.reduce((n,c) => n + (c.non_lus||0), 0);

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Messagerie</div>
          <h1 style="margin:6px 0 0">Échanges</h1>
        </div>
        <button class="btn" onClick=${()=>setNouvelle(n=>!n)}>
          ${nouvelle ? 'Annuler' : 'Nouvelle conversation'}</button>
      </div>

      <p class="small muted" style="margin-top:12px;max-width:62ch">
        Les échanges internes peuvent être consultés par l’encadrement dans le
        cadre de ses fonctions. <a href="#/confidentialite">En savoir plus</a>.
      </p>

      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}

      ${nouvelle && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Écrire à</h3></div>
          <div class="corps stack">
            <div class="field">
              <label>Un membre</label>
              <select onChange=${e => e.target.value && ouvrirPrivee(e.target.value)}>
                <option value="">Choisir…</option>
                ${candidats.map(c => html`<option value=${c.id}>
                  ${nomComplet(c)} — ${c.fonction_nom}${c.territoire_nom ? ' · '+c.territoire_nom : ''}
                </option>`)}
              </select>
            </div>
            ${mesGroupes.length > 0 && html`
              <div class="field">
                <label>Un de mes groupes</label>
                <select onChange=${e => e.target.value && ouvrirGroupe(e.target.value)}>
                  <option value="">Choisir…</option>
                  ${mesGroupes.map(g => html`<option value=${g.id}>${g.nom}</option>`)}
                </select>
              </div>`}
          </div>
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <h3 style="font-size:17px">Conversations</h3>
          ${nonLus > 0 && html`<span class="tag bleu">${nonLus} non lu${nonLus>1?'s':''}</span>`}
        </div>
        ${convs.length === 0
          ? html`<div class="vide">Aucune conversation. Commencez par en ouvrir une.</div>`
          : convs.map(c => html`
            <div class="ligne" style="cursor:pointer" onClick=${()=>setActive(c.id)}>
              <div style="flex:1;min-width:200px">
                <div class="row" style="gap:8px">
                  <span style=${c.non_lus>0 ? 'font-weight:600' : ''}>${c.titre||'Conversation'}</span>
                  ${c.type === 'groupe' && html`<span class="tag">Groupe</span>`}
                  ${c.superviseur && html`<span class="tag or">Supervision</span>`}
                </div>
                <div class="small muted" style="margin-top:4px;max-width:52ch;
                  overflow:hidden;text-overflow:ellipsis;white-space:nowrap">
                  ${c.dernier_message || 'Pas encore de message'}
                </div>
              </div>
              <div class="row">
                ${c.non_lus > 0 && html`<span class="tag bleu">${c.non_lus}</span>`}
                <span class="small muted">${jour(c.derniere_activite)}</span>
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function Conversation({ p, id, fermer }){
  const [entete, setEntete] = useState(null);
  const [gens, setGens] = useState([]);
  const [messages, setMessages] = useState([]);
  const [texte, setTexte] = useState('');
  const [msg, setMsg] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [signaler, setSignaler] = useState(false);
  const [motif, setMotif] = useState('propos_deplaces');
  const [details, setDetails] = useState('');
  const [piece, setPiece] = useState(null);
  const [profilOuvert, setProfilOuvert] = useState(null);
  const [liens, setLiens] = useState({});
  const [organes, setOrganes] = useState([]);
  const [auNom, setAuNom] = useState(false);

  useEffect(() => {
    db.rpc('mes_organes').then(({data}) => { setOrganes(data || []); });
  }, []);

  const charger = useCallback(async () => {
    const [{ data: cs }, { data: ps }, { data: ms }] = await Promise.all([
      db.rpc('mes_conversations'),
      db.rpc('participants_conversation', { p_conv: id }),
      db.from('messages').select('*').eq('conversation_id', id)
        .order('cree_le', { ascending: true })
    ]);
    setEntete((cs||[]).find(c => c.id === id) || null);
    setGens(ps || []);
    setMessages(ms || []);
    await db.rpc('marquer_lu', { p_conv: id });
  }, [id]);

  useEffect(() => { charger(); }, [charger]);

  // Rafraîchissement discret, toutes les quinze secondes.
  useEffect(() => {
    const t = setInterval(charger, 15000);
    return () => clearInterval(t);
  }, [charger]);

  async function envoyer(e){
    e.preventDefault();
    if (!texte.trim() && !piece) return;
    setEnvoi(true); setMsg('');

    // Le chemin commence par l'identifiant de la conversation : c'est ce
    // qui permet à Storage d'appliquer la règle d'accès de la messagerie
    // au lieu d'en écrire une seconde.
    let chemin = null;
    if (piece){
      if (piece.size > 10485760){
        setEnvoi(false);
        return setMsg('Fichier trop lourd : 10 Mo au maximum.');
      }
      chemin = id + '/' + crypto.randomUUID() + '-' + piece.name.replace(/[^\w.\-]/g,'_');
      const { error: eUp } = await db.storage.from('pieces').upload(chemin, piece);
      if (eUp){ setEnvoi(false); return setMsg('Dépôt impossible : ' + eUp.message); }
    }

    const { data, error } = await db.rpc('envoyer_message', {
      p_conv: id, p_contenu: texte || null, p_piece: chemin,
      p_piece_nom: piece ? piece.name : null,
      p_taille: piece ? piece.size : null,
      p_type: piece ? (piece.type || null) : null,
      // On ne signe d'un organe que si l'on en est un servant, et que
      // la conversation lui appartient.
      p_au_nom_de: (auNom && entete && entete.organe) ? entete.organe : null
    });
    setEnvoi(false);
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setTexte(''); setPiece(null); charger();
  }

  // Les liens de téléchargement sont signés et expirent : une pièce ne
  // circule pas hors de la conversation qui la porte.
  async function ouvrirPiece(m){
    if (liens[m.id]){ window.open(liens[m.id], '_blank'); return; }
    const { data, error } = await db.storage.from('pieces')
      .createSignedUrl(m.piece, 120);
    if (error) return setMsg('Pièce indisponible : ' + error.message);
    setLiens(l => ({ ...l, [m.id]: data.signedUrl }));
    window.open(data.signedUrl, '_blank');
  }

  const sertOrgane = !!(entete?.organe
    && organes.some(o => o.code === entete.organe));

  async function retirer(m){
    if (!confirm('Retirer ce message ? La pièce jointe sera effacée.')) return;
    const { data, error } = await db.rpc('retirer_message', { p_id: m.id });
    if (error) return setMsg(error.message);
    if (data && !data.ok) return setMsg(data.message);
    // La base a coupé le lien ; elle ne peut pas atteindre Storage. On
    // efface le fichier ici, faute de quoi il resterait accessible à qui
    // en connaîtrait le chemin.
    if (data.piece){
      const { error: eDel } = await db.storage.from('pieces').remove([data.piece]);
      if (eDel) setMsg('Message retiré, mais le fichier n\u2019a pas pu être effacé : '
        + eDel.message);
    }
    charger();
  }

  async function envoyerSignalement(e){
    e.preventDefault(); setMsg('');
    const { data, error } = await db.rpc('signaler_conversation',
      { p_conv: id, p_motif: motif, p_details: details, p_message: null });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setSignaler(false); setDetails('');
    setMsg('Signalement transmis. La direction l\u2019examinera.');
    charger();
  }

  const nom = i => {
    const g = gens.find(x => x.profil_id === i);
    return g ? [g.prenom, g.nom].filter(Boolean).join(' ') || g.matricule : 'Membre';
  };
  const superviseur = entete?.superviseur;

  return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Toutes les conversations</a>
      <div class="spread" style="margin-top:12px">
        <h1 style="font-size:28px">${entete?.titre || 'Conversation'}</h1>
        ${entete?.type === 'groupe' && html`<span class="tag">Groupe de travail</span>`}
      </div>
      ${entete?.organe && html`
        <div class="row" style="gap:12px;align-items:center;margin-top:10px;
          padding:12px 14px;background:var(--papier);border-radius:6px">
          ${entete.organe_logo
            ? html`<img src=${entete.organe_logo} alt=${entete.organe_nom}
                style="height:34px;width:auto" />`
            : html`<div style=${'width:34px;height:34px;border-radius:50%;flex:0 0 34px;'
                + 'background:var(--nuit);color:#fff;display:flex;align-items:center;'
                + 'justify-content:center;font-weight:700;font-size:13px'}>FFCE</div>`}
          <div style="min-width:0">
            <div style="font-weight:600">${entete.organe_nom}</div>
            <div class="small muted">
              ${sertOrgane
                ? 'Vous servez cet organe : ce que vous écrivez peut être signé de son nom.'
                : 'Une boîte de l\u2019institution, non d\u2019une personne. Votre réponse '
                  + 'parvient à tous ceux qui en ont la charge.'}
            </div>
          </div>
        </div>`}

      <div class="small muted" style="margin-top:6px">
        ${gens.map((g,i) => html`${i>0 ? ' · ' : ''}<a href="#"
          onClick=${e=>{e.preventDefault();
            setProfilOuvert(profilOuvert===g.profil_id?null:g.profil_id)}}
          >${[g.prenom,g.nom].filter(Boolean).join(' ')}</a>`)}
      </div>
      ${profilOuvert && html`<${ProfilInterne} profil=${profilOuvert}
        fermer=${()=>setProfilOuvert(null)} />`}

      ${superviseur && html`
        <p class="small muted" style="margin-top:16px">
          Consultation au titre de l’encadrement. Vous ne participez pas à cet
          échange et ne pouvez pas y écrire.
        </p>`}

      ${entete?.signale && html`
        <p class="small" style="margin-top:8px;color:var(--laiton)">
          Cette conversation fait l’objet d’un examen.
        </p>`}

      <div class="panneau" style="margin-top:24px">
        <div class="corps" style="max-height:52vh;overflow-y:auto">
          ${messages.length === 0
            ? html`<div class="vide">Aucun message. À vous d\u2019ouvrir l\u2019échange.</div>`
            : messages.map(m => {
              const moi = m.auteur_id === p.id;
              return html`
                <div style=${'margin-bottom:20px;'+(moi?'text-align:right':'')}>
                  <div class="small muted" style="margin-bottom:4px">
                    ${moi ? 'Vous' : nom(m.auteur_id)} ·
                    ${new Date(m.cree_le).toLocaleString('fr-FR',
                      {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}
                  </div>
                  <div style=${'display:inline-block;text-align:left;max-width:80%;'+
                    'padding:10px 14px;border:1px solid var(--filet);border-radius:2px;'+
                    'white-space:pre-wrap;'+
                    (moi ? 'background:var(--bleu-clair);border-color:#C9D8EC' : 'background:#fff')}>
                    ${m.organe && html`
                      <div class="row" style="gap:8px;align-items:center;
                        margin-bottom:8px;padding-bottom:8px;
                        border-bottom:1px solid var(--filet)">
                        <div style=${'width:22px;height:22px;border-radius:50%;'
                          + 'flex:0 0 22px;background:var(--nuit);color:#fff;'
                          + 'display:flex;align-items:center;justify-content:center;'
                          + 'font-weight:700;font-size:9px'}>FFCE</div>
                        <span class="small" style="font-weight:600">
                          ${entete?.organe_nom || 'Organe de la fédération'}</span>
                      </div>`}
                    ${m.retire
                      ? html`<span class="muted"><em>Message retiré</em></span>`
                      : m.contenu}
                    ${!m.retire && m.piece && html`
                      <div style="margin-top:10px;padding-top:10px;
                        border-top:1px solid var(--filet)">
                        <a href="#" onClick=${e=>{e.preventDefault();ouvrirPiece(m)}}>
                          ${m.piece_nom || 'Pièce jointe'}</a>
                        <span class="small muted"> · ${m.piece_taille
                          ? (m.piece_taille >= 1048576
                             ? (m.piece_taille/1048576).toFixed(1)+' Mo'
                             : Math.round(m.piece_taille/1024)+' ko')
                          : ''}</span>
                      </div>`}
                  </div>
                  ${!m.retire && (moi || p.echelon >= 6 || p.niveau >= 90) && html`
                    <div><button class="btn sm light" style="margin-top:6px;border:0;
                      background:transparent;padding:2px 0;font-size:12px"
                      onClick=${()=>retirer(m)}>Retirer</button></div>`}
                </div>`;
            })}
        </div>

        ${!superviseur && html`
          <form onSubmit=${envoyer} style="border-top:1px solid var(--filet);padding:16px 20px">
            <div class="field" style="margin:0">
              <textarea value=${texte} onInput=${e=>setTexte(e.target.value)}
                placeholder="Votre message" style="min-height:80px"
                onKeyDown=${e => { if (e.key==='Enter' && (e.metaKey||e.ctrlKey)) envoyer(e); }} />
            </div>
            ${sertOrgane && html`
              <label class="row" style="gap:8px;align-items:center;margin-top:10px">
                <input type="checkbox" style="width:auto" checked=${auNom}
                  onChange=${e=>setAuNom(e.target.checked)} />
                <span class="small">Répondre au nom du ${entete.organe_nom}
                  \u2014 votre nom reste enregistré, la signature est celle de
                  l\u2019institution</span>
              </label>`}
            <div class="row" style="gap:10px;margin-top:10px;align-items:center;flex-wrap:wrap">
              <input type="file" style="width:auto;font-size:13px;padding:4px 0;border:0"
                onChange=${e=>setPiece(e.target.files[0] || null)} />
              ${piece && html`<span class="small muted">${piece.name} ·
                ${Math.round(piece.size/1024)} ko
                <a href="#" onClick=${e=>{e.preventDefault();setPiece(null)}}>retirer</a>
              </span>`}
              <span class="small muted">10 Mo au maximum. Tout envoi est
                consigné : qui, quand, vers qui — jamais le contenu.</span>
            </div>
            <div class="spread" style="margin-top:12px">
              <span class="small muted">Ctrl + Entrée pour envoyer</span>
              <button class="btn" disabled=${envoi || !texte.trim()}>
                ${envoi ? 'Envoi…' : 'Envoyer'}</button>
            </div>
          </form>`}
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Signalement')?'ok':'err')}
        style="margin-top:16px">${msg}</div>`}

      ${!superviseur && html`
        <div style="margin-top:24px">
          ${signaler
            ? html`
              <form class="panneau" onSubmit=${envoyerSignalement}>
                <div class="tete"><h3 style="font-size:17px">Signaler cette conversation</h3></div>
                <div class="corps stack">
                  <div class="field"><label>Motif</label>
                    <select value=${motif} onChange=${e=>setMotif(e.target.value)}>
                      <option value="propos_deplaces">Propos déplacés</option>
                      <option value="harcelement">Harcèlement</option>
                      <option value="securite">Situation préoccupante</option>
                      <option value="hors_sujet">Usage hors mission</option>
                      <option value="autre">Autre</option>
                    </select></div>
                  <div class="field"><label>Ce que vous voulez dire</label>
                    <textarea required value=${details} onInput=${e=>setDetails(e.target.value)}
                      placeholder="Ce qui vous a alerté, en quelques lignes." /></div>
                  <div class="row">
                    <button class="btn">Transmettre à la direction</button>
                    <button type="button" class="btn light"
                      onClick=${()=>setSignaler(false)}>Annuler</button>
                  </div>
                  <p class="small muted">
                    Le signalement est examiné par la Direction générale, qui peut le
                    confier à un encadrant. Les personnes concernées n’en sont pas
                    averties automatiquement.
                  </p>
                </div>
              </form>`
            : html`<button class="btn light" style="border:0;background:transparent;
                padding:0;font-size:13px;color:var(--gris)"
                onClick=${()=>setSignaler(true)}>Signaler cette conversation</button>`}
        </div>`}
    </div>`;
}


/* =====================================================================
   5 quinquies. NOTES DE FRAIS ET DIRECTION FINANCIÈRE
   Circuit à trois temps : le membre dépose, son encadrement instruit,
   le trésorier valide puis paie.

   --------------------------------------------------------------------- */
export function JournalPieces({ setMsg }){
  const [l, setL] = useState([]);
  const [jours, setJours] = useState(30);
  const charger = useCallback(() =>
    db.rpc('journal_pieces', { p_jours: jours }).then(({data}) => setL(data||[])),
    [jours]);
  useEffect(() => { charger(); }, [charger]);

  const ko = n => n ? (n >= 1048576
    ? (n/1048576).toFixed(1) + ' Mo' : Math.round(n/1024) + ' ko') : '—';

  return html`
    <div class="panneau">
      <div class="tete spread">
        <h3 style="font-size:17px">Pièces échangées en messagerie</h3>
        <div class="row" style="gap:8px">
          <select value=${jours} style="width:auto;padding:5px 8px;font-size:13px"
            onChange=${e=>setJours(Number(e.target.value))}>
            <option value="7">7 jours</option>
            <option value="30">30 jours</option>
            <option value="90">90 jours</option>
          </select>
          <button class="btn sm light" onClick=${async ()=>{
            const { data } = await db.rpc('marquer_pieces_vues');
            if (data && data.ok) setMsg('Contrôle enregistré.');
          }}>J\u2019ai contrôlé</button>
        </div>
      </div>
      <div class="corps small muted" style="padding-bottom:0">
        Le journal dit qu\u2019un fichier est parti, de qui, vers qui et quand. Il
        ne donne ni le message, ni le moyen d\u2019ouvrir la pièce : la
        traçabilité n\u2019est pas un droit de lecture.
      </div>
      ${l.length === 0
        ? html`<div class="corps muted">Aucun envoi sur la période.</div>`
        : html`<div style="overflow-x:auto;padding:16px 20px">
            <table>
              <thead><tr><th>Date</th><th>De</th><th>Vers</th>
                <th>Fichier</th><th style="text-align:right">Taille</th></tr></thead>
              <tbody>
                ${l.map((x,i) => html`
                  <tr key=${i}>
                    <td class="small">${new Date(x.envoye_le).toLocaleString('fr-FR',
                      {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</td>
                    <td><div>${x.auteur}</div>
                      <div class="small muted">${x.auteur_fonction}${
                        x.territoire ? ' · '+x.territoire : ''}</div></td>
                    <td class="small">${x.destinataires || '—'}</td>
                    <td class="small mono">${x.nom || 'sans nom'}</td>
                    <td class="small mono" style="text-align:right">${ko(x.taille)}</td>
                  </tr>`)}
              </tbody>
            </table>
          </div>`}
    </div>`;
}

/* =====================================================================
   LES ÉQUIPES
   Un groupe ne se rejoint plus d'un clic : on postule, on est retenu.
   Une équipe locale se propose, et la présidence de la structure la
   valide — sauf si c'est elle qui l'a proposée.

   Une équipe n'hérite d'aucun droit. Elle reçoit une fiche, comme un
   poste, remplie par qui valide et bornée à ce qu'il détient lui-même.

   ===================================================================== */
export function GroupesOuverts({ setMsg }){
  const [l, setL] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [motivation, setMotivation] = useState('');

  const charger = useCallback(() =>
    db.rpc('groupes_ouverts').then(({data}) => setL(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function postuler(e, g){
    e.preventDefault();
    const { data, error } = await db.rpc('postuler_groupe',
      { p_groupe: g.id, p_motivation: motivation });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMotivation(''); setOuvert(null);
    setMsg('Candidature déposée. Le responsable du groupe vous répondra.');
    charger();
  }

  if (l.length === 0) return null;
  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete"><h3 style="font-size:17px">Groupes qui recrutent</h3>
        <span class="tag">${l.length}</span></div>
      ${l.map(g => html`
        <div key=${g.id}>
          <div class="ligne" style="align-items:flex-start">
            <div style="flex:1;min-width:240px">
              <div class="row" style="gap:8px;flex-wrap:wrap">
                <span style="font-weight:600">${g.nom}</span>
                <span class="tag">${g.portee === 'locale' ? g.territoire : 'National'}</span>
                <span class="small muted">${g.membres} membre(s)</span>
              </div>
              ${g.objet && html`<div class="small muted" style="margin-top:4px">${g.objet}</div>`}
            </div>
            ${g.ma_candidature === 'deposee'
              ? html`<span class="tag or">Candidature déposée</span>`
              : g.ma_candidature === 'ecartee'
                ? html`<span class="tag muted">Non retenue</span>`
                : html`<button class="btn sm"
                    onClick=${()=>setOuvert(ouvert===g.id?null:g.id)}>
                    ${ouvert===g.id ? 'Fermer' : 'Postuler'}</button>`}
          </div>
          ${ouvert === g.id && html`
            <form class="corps stack" onSubmit=${e=>postuler(e,g)}
              style="background:var(--papier);border-bottom:1px solid var(--filet)">
              <div class="field" style="margin:0">
                <label>Pourquoi souhaitez-vous rejoindre ce groupe ?</label>
                <textarea value=${motivation} style="min-height:80px"
                  placeholder="Ce que vous savez faire, ce que vous voulez y apporter."
                  onInput=${e=>setMotivation(e.target.value)}></textarea>
              </div>
              <div><button class="btn sm">Déposer ma candidature</button></div>
            </form>`}
        </div>`)}
    </div>`;
}


/* --- Les candidatures reçues, côté responsable de groupe --------------- */
export function CandidaturesGroupe({ setMsg }){
  const [l, setL] = useState([]);
  const charger = useCallback(() =>
    db.rpc('candidatures_groupe', { p_groupe: null }).then(({data}) => setL(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  const traiter = async (c, retenue) => {
    const r = retenue ? (prompt('Mot d\u2019accueil (facultatif)') || '')
                      : prompt('Motif du refus (obligatoire)');
    if (!retenue && !r) return;
    const { data, error } = await db.rpc('retenir_candidature',
      { p_id: c.id, p_retenue: retenue, p_reponse: r || null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(retenue ? 'Candidature retenue. Le groupe lui est ouvert.'
                   : 'Candidature écartée.');
    charger();
  };

  if (l.length === 0) return null;
  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete"><h3 style="font-size:17px">Candidatures reçues</h3>
        <span class="tag">${l.length}</span></div>
      ${l.map(c => html`
        <div class="ligne" key=${c.id} style="align-items:flex-start">
          <div style="flex:1;min-width:260px">
            <div class="row" style="gap:8px;flex-wrap:wrap">
              <span style="font-weight:600">${c.candidat}</span>
              <span class="tag">${c.groupe}</span>
            </div>
            <div class="small muted" style="margin-top:3px">
              ${c.fonction}${c.territoire ? ' · ' + c.territoire : ''} · ${jour(c.cree_le)}
            </div>
            <div class="small" style="margin-top:6px">${c.motivation}</div>
          </div>
          <div class="row" style="gap:6px">
            <button class="btn sm" onClick=${()=>traiter(c, true)}>Retenir</button>
            <button class="btn sm light" onClick=${()=>traiter(c, false)}>Écarter</button>
          </div>
        </div>`)}
    </div>`;
}

/* --- Constituer une équipe locale --------------------------------------
   La fiche ne peut contenir que des applications que le proposant
   détient. Au moment de valider, elle est ramenée à ce que le
   validateur détient : il engage sa signature, pas celle du proposant.

   --------------------------------------------------------------------- */
export function EquipesLocales({ p, apps, territoire, setMsg }){
  const [aValider, setAValider] = useState([]);
  const [gens, setGens] = useState([]);
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ nom:'', objet:'' });
  const [membres, setMembres] = useState([]);
  const [fiche, setFiche] = useState([]);

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('equipes_a_valider'),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom')
        .eq('statut','actif').order('nom')
    ]);
    setAValider(a.data||[]); setGens(b.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const partageables = (apps||[]).filter(a => a.ouvert && a.code !== 'groupes');

  async function proposer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('proposer_equipe', {
      p_nom: f.nom, p_objet: f.objet, p_territoire: territoire || null,
      p_membres: membres, p_applications: fiche
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({ nom:'', objet:'' }); setMembres([]); setFiche([]); setOuvert(false);
    setMsg(data.statut === 'actif'
      ? 'Équipe créée. Les membres reçoivent une invitation à accepter.'
      : 'Équipe proposée. La présidence de la structure la validera.');
    charger();
  }

  async function valider(g, ok){
    const m = ok ? null : prompt('Motif du refus (obligatoire)');
    if (!ok && !m) return;
    const { data, error } = await db.rpc('valider_equipe',
      { p_groupe: g.id, p_ok: ok, p_motif: m });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(ok ? 'Équipe validée.' : 'Proposition refusée.');
    charger();
  }

  const bascule = (liste, set, v) =>
    set(liste.includes(v) ? liste.filter(x => x !== v) : [...liste, v]);

  return html`
    <div style="margin-top:24px">
      ${aValider.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--bordeaux)">
          <div class="tete" style="border-bottom-color:var(--bordeaux)">
            <h3 style="font-size:17px">Équipes proposées</h3>
            <span class="tag">${aValider.length}</span></div>
          ${aValider.map(g => html`
            <div class="ligne" key=${g.id} style="align-items:flex-start">
              <div style="flex:1;min-width:250px">
                <div style="font-weight:600">${g.nom}</div>
                <div class="small muted" style="margin-top:3px">
                  Proposée par ${g.propose_par} · ${g.territoire}
                  · ${g.membres} personne(s) · ${jour(g.cree_le)}
                </div>
                <div class="small" style="margin-top:6px">${g.objet}</div>
                ${(g.applications||[]).length > 0 && html`
                  <div class="row" style="gap:6px;margin-top:8px;flex-wrap:wrap">
                    <span class="small muted">Fiche demandée :</span>
                    ${g.applications.map((a,i) => html`<span class="tag" key=${i}>${a}</span>`)}
                  </div>`}
              </div>
              <div class="row" style="gap:6px">
                <button class="btn sm" onClick=${()=>valider(g, true)}>Valider</button>
                <button class="btn sm light" onClick=${()=>valider(g, false)}>Refuser</button>
              </div>
            </div>`)}
          <div class="corps small muted">
            En validant, la fiche est ramenée aux applications que vous détenez
            vous-même : vous engagez votre signature, pas celle du proposant.
          </div>
        </div>`}

      <div class="panneau">
        <div class="tete spread">
          <h3 style="font-size:17px">Constituer une équipe</h3>
          <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
            ${ouvert ? 'Fermer' : 'Proposer une équipe'}</button>
        </div>
        ${ouvert
          ? html`<form class="corps stack" onSubmit=${proposer}>
              <div class="field" style="margin:0"><label>Nom de l\u2019équipe</label>
                <input value=${f.nom} placeholder="Équipe animation du forum des associations"
                  onInput=${e=>setF(o=>({...o,nom:e.target.value}))} /></div>
              <div class="field"><label>Objet</label>
                <textarea value=${f.objet} style="min-height:70px"
                  placeholder="Ce qu\u2019elle est chargée de faire, et jusqu\u2019à quand."
                  onInput=${e=>setF(o=>({...o,objet:e.target.value}))}></textarea></div>

              <div class="field">
                <label>Qui en fait partie</label>
                <div class="row" style="gap:6px;flex-wrap:wrap;max-height:180px;
                  overflow-y:auto;padding:4px 0">
                  ${gens.map(g => html`
                    <button type="button" key=${g.id}
                      class=${'btn sm ' + (membres.includes(g.id) ? '' : 'light')}
                      onClick=${()=>bascule(membres, setMembres, g.id)}>
                      ${nomComplet(g)}</button>`)}
                </div>
                <div class="small muted">Chacun recevra une invitation à accepter.
                  On n\u2019enrôle personne malgré lui.</div>
              </div>

              ${partageables.length > 0 && html`
                <div class="field">
                  <label>Ce que l\u2019appartenance ouvrira</label>
                  <div class="row" style="gap:6px;flex-wrap:wrap">
                    ${partageables.map(a => html`
                      <button type="button" key=${a.code}
                        class=${'btn sm ' + (fiche.includes(a.code) ? '' : 'light')}
                        onClick=${()=>bascule(fiche, setFiche, a.code)}>
                        ${a.nom_court || a.nom}</button>`)}
                  </div>
                  <div class="small muted">
                    Une équipe n\u2019hérite de rien : elle reçoit une fiche, comme un
                    poste. Vous ne pouvez y mettre que ce dont vous disposez.
                  </div>
                </div>`}

              <div><button class="btn">Proposer</button></div>
            </form>`
          : html`<div class="corps small muted">
              Une équipe de structure permet de travailler à plusieurs sur un
              projet local : documents partagés, tâches, échanges. Si vous
              présidez la structure, votre proposition vaut décision ; sinon
              elle est soumise à la présidence.</div>`}
      </div>
    </div>`;
}

/* =====================================================================
   LE SUIVI D'UNE NOTE
   Le déposant ne voyait qu'un mot. Il voit maintenant les quatre
   étapes, laquelle est franchie, par qui, et ce qui reste. Un dossier
   arrêté s'arrête visiblement plutôt que de rester en suspens.
