import { Groupes } from './collectif.js';
import { Habilitations } from './direction.js';
import { Engagement } from './membre.js';
import { CATEGORIES, ETAT_INV, EURO, Info, ORIGINE_INV, STATUT_EX, aller, db, etatCmd, etatInv, etatNote, h, html, jour, nomComplet, useCallback, useEffect, useState } from './socle.js';
import { Structures } from './structure.js';


export function NotesFrais({ p }){
  const [notes, setNotes] = useState(null);
  const [param, setParam] = useState({});
  const [ouverte, setOuverte] = useState(null);
  const [creation, setCreation] = useState(false);
  const [objet, setObjet] = useState('');
  const [groupe, setGroupe] = useState('');
  const [mesGroupes, setMesGroupes] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [{ data: ns }, { data: ps }, { data: gm }] = await Promise.all([
      db.rpc('v_notes', { p_filtre: 'miennes' }),
      db.from('parametres_frais').select('*'),
      db.from('gt_membres').select('groupe_id').eq('profil_id', p.id).eq('statut','actif')
    ]);
    setNotes(ns || []);
    setParam(Object.fromEntries((ps||[]).map(x => [x.cle, Number(x.valeur)])));
    if (gm && gm.length){
      const { data: gs } = await db.from('v_groupes').select('id,nom')
        .in('id', gm.map(x => x.groupe_id));
      setMesGroupes(gs || []);
    }
  }, [p.id]);

  useEffect(() => { charger(); }, [charger]);

  async function creer(e){
    e.preventDefault(); setMsg('');
    const { data, error } = await db.from('notes_frais')
      .insert({ profil_id: p.id, objet, groupe_id: groupe || null })
      .select().single();
    if (error) return setMsg(error.message);
    setObjet(''); setGroupe(''); setCreation(false); setOuverte(data.id); charger();
  }

  if (!notes) return html`<div class="vide">Chargement…</div>`;
  if (ouverte) return html`<${NoteFrais} p=${p} id=${ouverte} param=${param}
    fermer=${() => { setOuverte(null); charger(); }} />`;

  const aRembourser = notes.filter(n => ['deposee','instruite','ordonnancee'].includes(n.statut))
                           .reduce((t,n) => t + Number(n.total||0), 0);

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Notes de frais</div>
          <h1 style="margin:6px 0 0">Mes dépenses</h1>
        </div>
        <button class="btn" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Nouvelle note'}</button>
      </div>
      <p class="muted" style="max-width:58ch;margin-top:12px">
        Indemnité kilométrique à ${EURO(param.taux_km||0)} du kilomètre.
        Plafond de ${EURO(param.plafond_note||0)} par note.
        Un justificatif est exigé pour chaque dépense réelle.
      </p>

      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}

      ${aRembourser > 0 && html`
        <div class="alerte" style="margin-top:24px">
          ${EURO(aRembourser)} en cours de traitement.
        </div>`}

      ${creation && html`
        <form onSubmit=${creer} class="panneau" style="margin-top:24px">
          <div class="corps stack">
            <div class="field"><label>Objet</label>
              <input required value=${objet} onInput=${e=>setObjet(e.target.value)}
                placeholder="Déplacement au collège Jean-Moulin, 12 mars" /></div>
            ${mesGroupes.length > 0 && html`
              <div class="field"><label>Rattacher à un projet</label>
                <select value=${groupe} onChange=${e=>setGroupe(e.target.value)}>
                  <option value="">Aucun</option>
                  ${mesGroupes.map(g => html`<option value=${g.id}>${g.nom}</option>`)}
                </select></div>`}
            <div><button class="btn">Créer la note</button></div>
          </div>
        </form>`}

      <div class="panneau" style="margin-top:24px">
        ${notes.length === 0
          ? html`<div class="vide">Aucune note de frais. Créez-en une quand vous avancez des frais.</div>`
          : notes.map(n => html`
            <div class="ligne" style="cursor:pointer" onClick=${()=>setOuverte(n.id)}>
              <div style="flex:1;min-width:220px">
                <div>${n.objet}</div>
                <div class="small muted">
                  <span class="mono">${n.reference}</span> · ${n.nb_lignes} ligne${n.nb_lignes>1?'s':''}
                  ${n.groupe_nom ? ' · ' + n.groupe_nom : ''}
                  ${n.deposee_le ? ' · déposée le ' + jour(n.deposee_le) : ''}
                </div>
                ${n.motif_refus && html`<div class="small" style="color:var(--rouge);margin-top:4px">
                  ${n.motif_refus}</div>`}
              </div>
              <div class="row">
                <span class="mono">${EURO(n.total)}</span>
                ${etatNote(n.statut)}
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function NoteFrais({ p, id, param, fermer }){
  const [note, setNote] = useState(null);
  const [lignes, setLignes] = useState([]);
  const [f, setF] = useState({date_depense:'', categorie:'transport',
                              description:'', montant:'', kilometres:''});
  const [fichier, setFichier] = useState(null);
  const [msg, setMsg] = useState('');
  const [envoi, setEnvoi] = useState(false);

  const charger = useCallback(async () => {
    const { data: ns } = await db.rpc('v_notes', { p_filtre: 'miennes' });
    setNote((ns||[]).find(x => x.id === id) || null);
    const { data: ls } = await db.from('nf_lignes').select('*')
      .eq('note_id', id).order('date_depense');
    setLignes(ls || []);
  }, [id]);

  useEffect(() => { charger(); }, [charger]);

  if (!note) return html`<div class="vide">Note introuvable.</div>`;
  // À compléter : seules les lignes que l'instructeur a marquées sont
  // reprises. Le reste est acquis et ne se retouche plus.
  const modifiable = note.statut === 'brouillon';
  const aCompleter = note.statut === 'a_completer';

  async function renvoyerNote(){
    const { data, error } = await db.rpc('completer_note', { p_note: id });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setMsg(''); charger();
  }

  const montantDe = l => l.categorie === 'kilometres'
    ? (Number(l.kilometres||0) * (param.taux_km||0))
    : Number(l.montant||0);
  const total = lignes.reduce((t,l) => t + montantDe(l), 0);

  async function ajouter(e){
    e.preventDefault(); setMsg(''); setEnvoi(true);
    let chemin = null;
    try {
      if (fichier){
        if (fichier.size > 5 * 1024 * 1024)
          throw new Error('Le justificatif ne doit pas dépasser 5 Mo.');
        const ext = fichier.name.split('.').pop();
        chemin = p.id + '/' + id + '-' + Date.now() + '.' + ext;
        const { error: eUp } = await db.storage.from('justificatifs')
          .upload(chemin, fichier);
        if (eUp) throw eUp;
      }
      const { error } = await db.from('nf_lignes').insert({
        note_id: id, date_depense: f.date_depense, categorie: f.categorie,
        description: f.description,
        montant: f.categorie === 'kilometres' ? null : Number(f.montant||0),
        kilometres: f.categorie === 'kilometres' ? Number(f.kilometres||0) : null,
        justificatif: chemin
      });
      if (error) throw error;
      setF({date_depense:'', categorie:'transport', description:'', montant:'', kilometres:''});
      setFichier(null);
      const champ = document.getElementById('justif'); if (champ) champ.value = '';
      charger();
    } catch (err){
      setMsg(err.message || 'Ajout impossible.');
    }
    setEnvoi(false);
  }

  async function retirer(l){
    if (!confirm('Retirer cette dépense ?')) return;
    if (l.justificatif) await db.storage.from('justificatifs').remove([l.justificatif]);
    await db.from('nf_lignes').delete().eq('id', l.id);
    charger();
  }

  async function voirJustificatif(chemin){
    const { data, error } = await db.storage.from('justificatifs')
      .createSignedUrl(chemin, 120);
    if (error) return setMsg('Justificatif introuvable.');
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  async function deposer(){
    setMsg(''); setEnvoi(true);
    const { data, error } = await db.rpc('deposer_note', { p_note: id });
    setEnvoi(false);
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    charger();
  }

  async function supprimer(){
    if (!confirm('Supprimer définitivement cette note ?')) return;
    await db.from('notes_frais').delete().eq('id', id);
    fermer();
  }

  return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Toutes mes notes</a>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:30px">${note.objet}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${note.reference}</span>
            ${note.groupe_nom ? ' · ' + note.groupe_nom : ''}
          </div>
        </div>
        ${etatNote(note.statut)}
      </div>

      ${aCompleter && html`
        <div class="alerte" style="margin-top:16px;border-left:3px solid var(--laiton)">
          <strong>Complément demandé</strong> — ${note.demande_precisions}
          <div class="small" style="margin-top:8px">
            Corrigez les lignes marquées « à préciser », puis renvoyez la note.
            Ce qui a déjà été retenu n\u2019est pas remis en cause.
          </div>
          <div style="margin-top:12px">
            <button class="btn sm" onClick=${renvoyerNote}>Renvoyer la note</button>
          </div>
        </div>`}

      ${Number(note.ecarte) > 0 && html`
        <div class="alerte" style="margin-top:16px">
          ${EURO(note.ecarte)} écarté${note.statut === 'payee' ? '' : ' du remboursement'}.
          Le détail figure au regard de chaque dépense.
        </div>`}

      ${note.avis && html`<div class="alerte" style="margin-top:16px">
        Avis de l\u2019encadrement : ${note.avis}</div>`}
      ${note.motif_refus && html`<div class="alerte err" style="margin-top:16px">
        ${note.motif_refus}</div>`}
      ${note.statut === 'payee' && html`<div class="alerte ok" style="margin-top:16px">
        ${note.mode_remboursement === 'abandon_creance'
          ? 'Créance abandonnée. Reçu fiscal ' + (note.recu_fiscal||'') + '.'
          : 'Payée' + (note.reference_paiement ? ' — référence ' + note.reference_paiement : '') + '.'}
        </div>`}
      ${note.statut === 'ordonnancee' && html`<div class="alerte" style="margin-top:16px">
        Dépense ordonnancée. Le paiement sera exécuté par la direction financière.</div>`}
      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}

      ${note.statut !== 'brouillon' && html`<${SuiviNote} id=${id} />`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <h3 style="font-size:17px">Dépenses</h3>
          <span class="mono" style="font-size:16px">${EURO(total)}</span>
        </div>
        ${lignes.length === 0
          ? html`<div class="vide">Aucune dépense saisie.</div>`
          : lignes.map(l => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div>${l.description}</div>
                <div class="small muted">
                  ${CATEGORIES[l.categorie]} · ${jour(l.date_depense)}
                  ${l.categorie === 'kilometres' ? ' · ' + l.kilometres + ' km' : ''}
                </div>
              </div>
              <div class="row">
                ${l.justificatif
                  ? html`<button class="btn sm light"
                      onClick=${()=>voirJustificatif(l.justificatif)}>Justificatif</button>`
                  : (l.categorie !== 'kilometres'
                      ? html`<span class="tag rouge">Sans justificatif</span>` : null)}
                <span class="mono">${EURO(montantDe(l))}</span>
                ${modifiable && html`<button class="btn sm light"
                  onClick=${()=>retirer(l)}>Retirer</button>`}
              </div>
            </div>`)}
      </div>

      ${modifiable && html`
        <form onSubmit=${ajouter} class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Ajouter une dépense</h3></div>
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0"><label>Date</label>
                <input type="date" required value=${f.date_depense}
                  onInput=${e=>setF(o=>({...o,date_depense:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:180px;margin:0"><label>Nature</label>
                <select value=${f.categorie} onChange=${e=>setF(o=>({...o,categorie:e.target.value}))}>
                  ${Object.entries(CATEGORIES).map(([k,v]) => html`<option value=${k}>${v}</option>`)}
                </select></div>
            </div>
            <div class="field"><label>Description</label>
              <input required value=${f.description}
                onInput=${e=>setF(o=>({...o,description:e.target.value}))}
                placeholder="Aller-retour Foix – Pamiers" /></div>

            ${f.categorie === 'kilometres'
              ? html`
                <div class="field"><label>Distance parcourue (km)</label>
                  <input type="number" step="0.1" min="0" required value=${f.kilometres}
                    onInput=${e=>setF(o=>({...o,kilometres:e.target.value}))} />
                  <p class="small muted" style="margin:6px 0 0">
                    Soit ${EURO((Number(f.kilometres)||0) * (param.taux_km||0))}
                    au barème en vigueur. Aucun justificatif n\u2019est demandé.</p>
                </div>`
              : html`
                <div class="field"><label>Montant (€)</label>
                  <input type="number" step="0.01" min="0" required value=${f.montant}
                    onInput=${e=>setF(o=>({...o,montant:e.target.value}))} /></div>
                <div class="field"><label>Justificatif</label>
                  <input id="justif" type="file" accept="image/*,.pdf"
                    onChange=${e=>setFichier(e.target.files[0]||null)} />
                  <p class="small muted" style="margin:6px 0 0">
                    Photo ou PDF, 5 Mo maximum. Exigé pour déposer la note.</p>
                </div>`}

            <div><button class="btn" disabled=${envoi}>
              ${envoi ? 'Ajout…' : 'Ajouter la dépense'}</button></div>
          </div>
        </form>`}

      ${modifiable && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Mode de remboursement</h3></div>
          <div class="corps stack">
            <div class="field" style="margin:0">
              <select value=${note.mode_remboursement||'virement'} onChange=${async e => {
                await db.from('notes_frais').update({ mode_remboursement: e.target.value })
                  .eq('id', id);
                charger();
              }}>
                <option value="virement">Virement sur mon compte</option>
                <option value="abandon_creance">J’abandonne la créance — reçu fiscal</option>
              </select>
            </div>
            <p class="small muted">
              L’abandon de créance vaut don à la fédération : vous renoncez au
              remboursement et recevez un reçu fiscal ouvrant droit à réduction
              d’impôt. Le virement exige des coordonnées bancaires enregistrées
              dans Mon compte.
            </p>
          </div>
        </div>

        <div class="row" style="margin-top:32px">
          <button class="btn" onClick=${deposer} disabled=${envoi || lignes.length===0}>
            Déposer la note</button>
          <button class="btn light" onClick=${supprimer}>Supprimer</button>
        </div>
        <p class="small muted" style="margin-top:12px">
          Une fois déposée, la note n\u2019est plus modifiable. Elle part à votre
          encadrement, qui donne un avis, puis à la direction financière.
        </p>`}
    </div>`;
}

/* --- Finances : instruction, ordonnancement, paiement ------------------
   Trois écrans distincts pour trois responsabilités distinctes. La
   séparation doit se voir, sinon elle ne sert à rien.

   --------------------------------------------------------------------- */
export function Finances({ p, role }){
  // role : 'tresorerie' (instruire + payer) ou 'ordonnancement'
  const [onglet, setOnglet] = useState(role === 'ordonnancement' ? 'ordonnancer' : 'instruire');
  const [listes, setListes] = useState({});
  const [param, setParam] = useState([]);
  const [detail, setDetail] = useState(null);
  const [lignes, setLignes] = useState([]);
  const [rib, setRib] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const filtres = ['avis','instruire','ordonnancer','payer','toutes'];
    const res = await Promise.all(filtres.map(f => db.rpc('v_notes', { p_filtre: f })));
    setListes(Object.fromEntries(filtres.map((f,i) => [f, res[i].data || []])));
    const { data: pr } = await db.from('parametres_frais').select('*').order('cle');
    setParam(pr || []);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function ouvrir(n){
    setDetail(n); setMsg(''); setRib(null);
    const { data } = await db.from('nf_lignes').select('*')
      .eq('note_id', n.id).order('date_depense');
    setLignes(data || []);
  }

  async function justificatif(chemin){
    const { data, error } = await db.storage.from('justificatifs').createSignedUrl(chemin, 120);
    if (error) return setMsg('Justificatif introuvable.');
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  async function voirRib(n){
    const { data, error } = await db.rpc('lire_rib', { p_note: n.id });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setRib(data);
    setMsg('Consultation enregistrée : le membre en sera informé.');
  }

  const appel = async (fn, args, ok) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(ok); setDetail(null); charger();
  };

  async function avis(n, favorable){
    const t = prompt(favorable ? 'Avis (facultatif)' : 'Motif de l\u2019avis défavorable');
    if (!favorable && !t) return;
    appel('donner_avis', { p_note: n.id, p_favorable: favorable, p_avis: t || '' },
      'Avis enregistré.');
  }
  async function instruire(n, ok){
    const t = prompt(ok ? 'Imputation budgétaire (facultatif)' : 'Motif du rejet (obligatoire)');
    if (!ok && !t) return;
    appel('instruire_note', { p_note: n.id, p_favorable: ok, p_avis: t || '' },
      ok ? 'Note instruite. Elle passe à l\u2019ordonnateur.' : 'Note rejetée.');
  }
  async function ordonnancer(n, ok){
    const t = ok ? null : prompt('Motif du refus (obligatoire)');
    if (!ok && !t) return;
    appel('ordonnancer_note', { p_note: n.id, p_ok: ok, p_motif: t },
      ok ? 'Dépense ordonnancée. Elle passe au paiement.' : 'Dépense refusée.');
  }
  async function payer(n){
    const ref = prompt('Référence du virement (facultatif)') || '';
    appel('payer_note', { p_note: n.id, p_reference: ref }, 'Note payée.');
  }
  async function majParam(cle, valeur){
    const { error } = await db.from('parametres_frais')
      .update({ valeur: Number(valeur) }).eq('cle', cle);
    setMsg(error ? 'Erreur : ' + error.message : 'Barème enregistré.');
    charger();
  }

  const taux = Number((param.find(x=>x.cle==='taux_km')||{}).valeur || 0);
  const montantDe = l => l.categorie === 'kilometres'
    ? Number(l.kilometres||0) * taux : Number(l.montant||0);

  const ligneNote = (n, actions) => html`
    <div class="ligne">
      <div style="flex:1;min-width:240px;cursor:pointer" onClick=${()=>ouvrir(n)}>
        <div>${n.objet}</div>
        <div class="small muted">
          ${n.deposant} <span class="mono">${n.matricule}</span>
          ${n.territoire_nom ? ' · ' + n.territoire_nom : ''}
          · <span class="mono">${n.reference}</span>
          ${n.deposee_le ? ' · ' + jour(n.deposee_le) : ''}
        </div>
        ${n.avis && html`<div class="small muted">Avis : ${n.avis}</div>`}
        ${n.mode_remboursement === 'abandon_creance' && html`
          <div style="margin-top:6px"><span class="tag vert">Abandon de créance</span></div>`}
        ${n.mode_remboursement === 'virement' && !n.a_un_rib && html`
          <div style="margin-top:6px"><span class="tag rouge">Sans coordonnées bancaires</span></div>`}
      </div>
      <div class="row">
        <span class="mono" style="font-size:15px">${EURO(n.total)}</span>
        ${etatNote(n.statut)}
        ${actions}
      </div>
    </div>`;

  if (detail) return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();setDetail(null)}}>← Retour</a>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:28px">${detail.objet}</h1>
          <div class="small muted" style="margin-top:4px">
            ${detail.deposant} <span class="mono">${detail.matricule}</span>
            ${detail.territoire_nom ? ' · ' + detail.territoire_nom : ''}
            · <span class="mono">${detail.reference}</span>
          </div>
        </div>
        ${etatNote(detail.statut)}
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${['deposee','a_completer'].includes(detail.statut)
        && (onglet === 'instruire' || onglet === 'avis') && html`
        <${InstruireLignes} note=${detail} lignes=${lignes}
          param=${Object.fromEntries(param.map(x => [x.cle, Number(x.valeur)]))}
          recharger=${async ()=>{
            await charger();
            const { data } = await db.from('nf_lignes').select('*')
              .eq('note_id', detail.id).order('date_depense');
            setLignes(data || []);
            const { data: ns } = await db.rpc('v_notes', { p_filtre: 'toutes' });
            const maj = (ns||[]).find(x => x.id === detail.id);
            if (maj) setDetail(maj);
          }} setMsg=${setMsg} />`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Suivi</h3></div>
        ${detail.avis_nom && html`<div class="ligne">
          <span class="muted">Avis hiérarchique</span>
          <span>${detail.avis_nom} — ${detail.avis||''}</span></div>`}
        ${detail.instruit_nom && html`<div class="ligne">
          <span class="muted">Instruite par</span>
          <span>${detail.instruit_nom}${detail.imputation ? ' · ' + detail.imputation : ''}</span></div>`}
        ${detail.ordonnance_nom && html`<div class="ligne">
          <span class="muted">Ordonnancée par</span><span>${detail.ordonnance_nom}</span></div>`}
        ${detail.paye_nom && html`<div class="ligne">
          <span class="muted">Payée par</span>
          <span>${detail.paye_nom}${detail.reference_paiement ? ' · ' + detail.reference_paiement : ''}</span></div>`}
        <div class="ligne"><span class="muted">Mode de remboursement</span>
          <span>${detail.mode_remboursement === 'abandon_creance'
            ? 'Abandon de créance — reçu fiscal'
            : 'Virement bancaire'}</span></div>
        ${detail.motif_refus && html`<div class="ligne">
          <span class="muted">Motif du refus</span>
          <span style="color:var(--rouge)">${detail.motif_refus}</span></div>`}
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Dépenses</h3>
          <span class="mono" style="font-size:16px">${EURO(detail.total)}</span></div>
        ${lignes.map(l => html`
          <div class="ligne">
            <div style="flex:1;min-width:200px">
              <div>${l.description}</div>
              <div class="small muted">${CATEGORIES[l.categorie]} · ${jour(l.date_depense)}
                ${l.categorie === 'kilometres' ? ' · ' + l.kilometres + ' km' : ''}</div>
            </div>
            <div class="row">
              ${l.justificatif && html`<button class="btn sm light"
                onClick=${()=>justificatif(l.justificatif)}>Justificatif</button>`}
              <span class="mono">${EURO(montantDe(l))}</span>
            </div>
          </div>`)}
      </div>

      ${detail.statut === 'ordonnancee' && detail.mode_remboursement === 'virement' && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Coordonnées bancaires</h3></div>
          <div class="corps">
            ${rib
              ? html`<div class="stack">
                  <div><span class="muted small">Titulaire</span><div>${rib.titulaire}</div></div>
                  <div><span class="muted small">IBAN</span>
                    <div class="mono" style="font-size:15px">${rib.iban}</div></div>
                  ${rib.bic && html`<div><span class="muted small">BIC</span>
                    <div class="mono">${rib.bic}</div></div>`}
                </div>`
              : html`<div>
                  <p class="small muted">La consultation est tracée et le membre en est informé.</p>
                  <button class="btn sm" onClick=${()=>voirRib(detail)}>Afficher l\u2019IBAN</button>
                </div>`}
          </div>
        </div>`}

      <div class="row" style="margin-top:32px">
        ${detail.statut === 'deposee' && a('avis') && html`
          <button class="btn light" onClick=${()=>avis(detail,true)}>Avis favorable</button>
          <button class="btn light" onClick=${()=>avis(detail,false)}>Avis défavorable</button>`}
        ${detail.statut === 'deposee' && role === 'tresorerie' && html`
          <button class="btn" onClick=${()=>instruire(detail,true)}>Instruire</button>
          <button class="btn light" onClick=${()=>instruire(detail,false)}>Rejeter</button>`}
        ${detail.statut === 'instruite' && role === 'ordonnancement' && html`
          <button class="btn" onClick=${()=>ordonnancer(detail,true)}>Ordonnancer</button>
          <button class="btn light" onClick=${()=>ordonnancer(detail,false)}>Refuser</button>`}
        ${detail.statut === 'ordonnancee' && role === 'tresorerie' && html`
          <button class="btn" onClick=${()=>payer(detail)}>Marquer comme payée</button>`}
      </div>
    </div>`;

  function a(k){ return (listes[k]||[]).length > 0; }
  const L = k => listes[k] || [];
  const paye = L('toutes').filter(n => n.statut === 'payee')
                          .reduce((t,n) => t + Number(n.total||0), 0);

  const onglets = role === 'ordonnancement'
    ? [['ordonnancer','À ordonnancer'],['toutes','Toutes']]
    : [['avis','Avis à donner'],['instruire','À instruire'],['payer','À payer'],
       ['virements','Suivi des paiements'],['toutes','Toutes'],['bareme','Barème']];

  return html`
    <div>
      <div class="eyebrow">${role === 'ordonnancement' ? 'Ordonnancement' : 'Direction financière'}</div>
      <h1 style="margin:6px 0 8px">
        ${role === 'ordonnancement' ? 'Engager les dépenses' : 'Instruire et payer'}</h1>
      <p class="muted" style="max-width:60ch">
        ${role === 'ordonnancement'
          ? 'Vous décidez d\u2019engager les dépenses instruites par la direction financière. Vous n\u2019exécutez pas les paiements.'
          : 'Vous contrôlez la forme des notes et exécutez les paiements ordonnancés. Vous ne décidez pas de l\u2019engagement.'}
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        ${role === 'tresorerie' && html`
          <div><div class="n" style="font-size:32px">${L('instruire').length}</div>
            <div class="l">À instruire</div></div>`}
        <div><div class="n" style="font-size:32px">${L('ordonnancer').length}</div>
          <div class="l">À ordonnancer</div></div>
        ${role === 'tresorerie' && html`
          <div><div class="n" style="font-size:32px">${L('payer').length}</div>
            <div class="l">À payer</div></div>`}
        <div><div class="n" style="font-size:32px">${EURO(paye)}</div>
          <div class="l">Déjà remboursé</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${onglets.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--encre)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'virements' && html`<${SuiviVirements} setMsg=${setMsg} />`}

      ${onglet === 'ordonnancer' && html`<${InvestissementsAOrdonnancer}
        setMsg=${setMsg} />`}

      ${onglet !== 'bareme' && onglet !== 'virements' && html`
        <div class="panneau">
          ${L(onglet).length === 0
            ? html`<div class="vide">Rien à traiter ici.</div>`
            : L(onglet).map(n => ligneNote(n, html`
                <button class="btn sm" onClick=${()=>ouvrir(n)}>Ouvrir</button>`))}
        </div>`}

      ${onglet === 'bareme' && html`
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Barème et plafonds</h3></div>
          <div class="corps stack">
            ${param.map(x => html`
              <div class="field">
                <label>${x.libelle} (${x.unite})</label>
                <input type="number" step="0.001" defaultValue=${x.valeur}
                  onBlur=${e=>majParam(x.cle, e.target.value)} />
              </div>`)}
            <p class="small muted">Enregistré à la sortie du champ.</p>
          </div>
        </div>`}
    </div>`;
}


/* --- Suivi des virements, côté direction financière ------------------- */
export function SuiviVirements({ setMsg }){
  const [liste, setListe] = useState([]);
  const charger = useCallback(() =>
    db.rpc('virements_a_suivre').then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function attestation(x, fichier){
    if (!fichier) return;
    try {
      if (fichier.size > 5 * 1024 * 1024) throw new Error('5 Mo maximum.');
      const ext = fichier.name.split('.').pop();
      const chemin = x.deposant_id + '/attestation-' + x.note_id + '.' + ext;
      const { error: e1 } = await db.storage.from('justificatifs').upload(chemin, fichier,
        { upsert: true });
      if (e1) throw e1;
      const { data, error } = await db.rpc('deposer_attestation',
        { p_note: x.note_id, p_fichier: chemin });
      if (error) throw error;
      if (!data.ok) throw new Error(data.message);
      setMsg('Attestation déposée. Le donateur peut la télécharger.'); charger();
    } catch (err){ setMsg('Erreur : ' + (err.message||'dépôt impossible')); }
  }

  const etats = {
    conteste:['Contesté','rouge'], sans_reponse:['Sans réponse depuis 15 j','or'],
    attestation_manquante:['Attestation à déposer','or'],
    en_attente:['En attente d\u2019accusé',''], accuse:['Reçu','vert']
  };
  const urgents = liste.filter(x => x.etat === 'conteste' || x.etat === 'sans_reponse');

  return html`
    <div>
      ${urgents.length > 0 && html`
        <div class="alerte err" style="margin-bottom:16px">
          ${urgents.length} paiement${urgents.length>1?'s':''} appelle
          ${urgents.length>1?'nt':''} une vérification.
        </div>`}
      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Tous les paiements sont confirmés.</div>`
          : liste.map(x => html`
            <div class="ligne" style=${x.etat==='conteste'
              ? 'border-left:3px solid var(--bordeaux)' : ''}>
              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <span>${x.objet}</span>
                  <span class=${'tag '+(etats[x.etat]||['',''])[1]}>
                    ${(etats[x.etat]||[x.etat,''])[0]}</span>
                </div>
                <div class="small muted">
                  ${x.deposant} · <span class="mono">${x.reference}</span>
                  · ${EURO(x.total)}
                  · payé le ${jour(x.payee_le)} (il y a ${x.jours} j)
                  · ${x.mode === 'abandon_creance' ? 'abandon de créance' : 'virement'}
                </div>
                ${x.motif_contestation && html`
                  <div class="small" style="color:var(--bordeaux);margin-top:6px">
                    « ${x.motif_contestation} »</div>`}
              </div>
              <div class="row">
                ${x.mode === 'abandon_creance' && !x.attestation && html`
                  <label class="btn sm" style="margin:0;cursor:pointer;
                      text-transform:none;letter-spacing:.02em">
                    Déposer l\u2019attestation
                    <input type="file" accept=".pdf,image/*" style="display:none"
                      onChange=${e=>attestation(x, e.target.files[0])} />
                  </label>`}
                ${x.attestation && html`<span class="tag vert">Attestation déposée</span>`}
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function Budget({ p }){
  const [exercices, setExercices] = useState([]);
  const [actif, setActif] = useState(null);
  const [b, setB] = useState(null);
  const [onglet, setOnglet] = useState('budget');
  const [sauv, setSauv] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a, c] = await Promise.all([
      db.rpc('mes_exercices'), db.rpc('etat_sauvegardes')
    ]);
    setExercices(a.data||[]); setSauv(c.data);
    const id = actif || (a.data||[])[0]?.id;
    if (id){
      setActif(id);
      const { data } = await db.rpc('budget_exercice', { p_exercice: id });
      setB(data);
    }
  }, [actif]);
  useEffect(() => { charger(); }, [charger]);

  async function ouvrir(){
    const annee = prompt('Année de l\u2019exercice', new Date().getFullYear());
    if (!annee) return;
    const { data, error } = await db.rpc('ouvrir_exercice',
      { p_annee: Number(annee), p_territoire: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setActif(data.id); setMsg('Exercice ouvert.'); charger();
  }

  async function regler(ligne, champ, valeur){
    const { data, error } = await db.rpc('regler_ligne',
      { p_id: ligne.id, p_champ: champ, p_valeur: String(valeur) });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    charger();
  }

  async function statut(st){
    const obs = st === 'arrete'
      ? prompt('Observations sur l\u2019arrêté des comptes (facultatif)') : null;
    const { data, error } = await db.rpc('changer_statut_exercice',
      { p_id: actif, p_statut: st, p_observations: obs });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Exercice mis à jour.'); charger();
  }

  async function exporter(quoi){
    const fn = quoi === 'budget' ? 'export_budget' : 'export_depenses';
    const { data, error } = await db.rpc(fn, { p_exercice: actif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data || data.length === 0) return setMsg('Rien à exporter.');
    const cols = Object.keys(data[0]);
    const ech = v => {
      if (v === null || v === undefined) return '';
      const t = String(v).replace(/"/g,'""');
      return /[";\n]/.test(t) ? '"'+t+'"' : t;
    };
    const csv = '\ufeff' + cols.join(';') + '\n' +
      data.map(l => cols.map(c => ech(l[c])).join(';')).join('\n');
    const ex = exercices.find(x => x.id === actif);
    const nom = 'FFCE-' + (quoi === 'budget' ? 'budget' : 'depenses') +
      '-' + (ex ? ex.annee : '') + '.csv';
    const url = URL.createObjectURL(new Blob([csv], {type:'text/csv;charset=utf-8'}));
    const a = document.createElement('a'); a.href = url; a.download = nom; a.click();
    URL.revokeObjectURL(url);
    await db.rpc('tracer_export', { p_objet: nom, p_lignes: data.length });
    setMsg(data.length + ' ligne(s) exportées. Déposez le fichier sur le Drive.');
  }

  if (!b && exercices.length === 0) return html`
    <div>
      <div class="eyebrow">Budget et comptes</div>
      <h1 style="margin:6px 0 16px">Aucun exercice ouvert</h1>
      <p class="muted" style="max-width:56ch">
        Un exercice couvre une année civile. Une fois ouvert, les dépenses
        payées, les abandons de frais et le bénévolat valorisé s\u2019y inscrivent
        d\u2019eux-mêmes.
      </p>
      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}
      <div style="margin-top:24px"><button class="btn" onClick=${ouvrir}>
        Ouvrir un exercice</button></div>
    </div>`;
  if (!b) return html`<div class="vide">Chargement…</div>`;

  const ex = b.exercice || {};
  const lignes = b.lignes || [];
  const produits = lignes.filter(l => l.sens === 'produit');
  const charges  = lignes.filter(l => l.sens === 'charge');
  const fige = ['arrete','clos'].includes(ex.statut);

  const bloc = (titre, liste) => {
    const cats = [...new Set(liste.map(l => l.categorie))];
    return html`
      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">${titre}</h3></div>
        <div style="overflow-x:auto">
          <table>
            <thead><tr>
              <th style="min-width:220px">Poste</th>
              <th style="text-align:right">Prévu</th>
              <th style="text-align:right">Réalisé</th>
              <th style="text-align:right">Écart</th>
              <th></th>
            </tr></thead>
            <tbody>
              ${cats.map(cat => html`
                <tr><td colspan="5" style="background:var(--papier);
                  font-family:var(--titre);font-weight:700;font-size:11px;
                  letter-spacing:.1em;text-transform:uppercase;color:var(--gris)">
                  ${cat}</td></tr>
                ${liste.filter(l => l.categorie === cat).map(l => {
                  const ecart = Number(l.realise||0) - Number(l.prevu||0);
                  return html`
                    <tr>
                      <td>
                        <div class="row" style="gap:8px">
                          <span class="mono muted">${l.poste}</span>
                          <span>${l.libelle}</span>
                          ${l.automatique && html`
                            <${Info} texte=${'Calculé automatiquement : ' + (l.source||'')} />`}
                        </div>
                        ${!fige && html`<input defaultValue=${l.intitule||''}
                          placeholder="Précision (facultatif)"
                          style="margin-top:6px;font-size:13px;padding:5px 8px"
                          onBlur=${e=>regler(l,'libelle',e.target.value)} />`}
                      </td>
                      <td style="text-align:right">
                        ${fige
                          ? html`<span class="mono">${EURO(l.prevu)}</span>`
                          : html`<input type="number" step="0.01" defaultValue=${l.prevu}
                              style="width:110px;text-align:right"
                              onBlur=${e=>regler(l,'prevu',e.target.value)} />`}
                      </td>
                      <td style="text-align:right">
                        ${l.automatique
                          ? html`<span class="mono" title="Calculé">${EURO(l.realise)}</span>`
                          : fige
                            ? html`<span class="mono">${EURO(l.realise)}</span>`
                            : html`<input type="number" step="0.01" defaultValue=${l.realise_saisi}
                                style="width:110px;text-align:right"
                                onBlur=${e=>regler(l,'realise',e.target.value)} />`}
                      </td>
                      <td style="text-align:right" class="mono"
                        style=${'text-align:right;color:'+(ecart<0?'var(--bordeaux)':'var(--gris)')}>
                        ${ecart === 0 ? '—' : EURO(ecart)}</td>
                      <td style="width:34px">
                        ${l.automatique && html`<span class="tag">auto</span>`}</td>
                    </tr>`;
                })}`)}
            </tbody>
          </table>
        </div>
      </div>`;
  };

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Budget et comptes</div>
          <h1 style="margin:6px 0 0">Exercice ${ex.annee || ''}</h1>
        </div>
        <div class="row">
          <select style="width:auto" value=${actif}
            onChange=${e=>{ setActif(e.target.value); setB(null); }}>
            ${exercices.map(x => html`<option value=${x.id}>
              ${x.annee}${x.territoire ? ' · '+x.territoire : ' · national'}</option>`)}
          </select>
          <button class="btn sm light" onClick=${ouvrir}>Nouvel exercice</button>
        </div>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${sauv && !sauv.faite_ce_mois && html`
        <div class="alerte" style="margin-top:24px;border-left-color:var(--bordeaux)">
          <strong>Sauvegarde du mois non effectuée.</strong>
          ${sauv.derniere
            ? ' Dernière : ' + sauv.derniere.periode + ', il y a ' + sauv.jours_depuis + ' jours.'
            : ' Aucune sauvegarde n\u2019a jamais été déclarée.'}
          <button class="btn sm" style="margin-left:10px" onClick=${async ()=>{
            const ou = prompt('Où avez-vous déposé la sauvegarde ?',
              'Drive FFCE / Sauvegardes');
            if (!ou) return;
            const { data } = await db.rpc('declarer_sauvegarde',
              { p_portee: 'complete', p_emplacement: ou, p_observation: null });
            if (data?.ok){ setMsg('Sauvegarde enregistrée. Merci.'); charger(); }
          }}>C\u2019est fait</button>
        </div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:28px">${EURO(b.produits_realises)}</div>
          <div class="l">Produits réalisés</div></div>
        <div><div class="n" style="font-size:28px">${EURO(b.charges_realisees)}</div>
          <div class="l">Charges réalisées</div></div>
        <div><div class="n" style=${'font-size:28px;color:'+
          (Number(b.resultat_realise)<0?'var(--bordeaux)':'var(--valide)')}>
          ${EURO(b.resultat_realise)}</div>
          <div class="l">Résultat</div></div>
        <div><div class="n" style="font-size:28px">${EURO(b.benevolat)}</div>
          <div class="l">Bénévolat valorisé</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['budget','Budget et réalisé'],['synthese','Synthèse'],
           ['sauvegardes','Sauvegardes']].map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'budget' && html`
        <div>
          <div class="spread" style="margin-bottom:16px">
            <span class=${'tag '+(STATUT_EX[ex.statut]||['',''])[1]}>
              ${(STATUT_EX[ex.statut]||[ex.statut,''])[0]}
              ${ex.arrete_le ? ' le ' + jour(ex.arrete_le) : ''}</span>
            <div class="row">
              <button class="btn sm light" onClick=${()=>exporter('budget')}>
                Exporter le budget</button>
              <button class="btn sm light" onClick=${()=>exporter('depenses')}>
                Exporter les dépenses</button>
              ${!fige && html`
                <select style="width:auto" value=${ex.statut}
                  onChange=${e=>statut(e.target.value)}>
                  ${Object.entries(STATUT_EX).map(([k,v]) =>
                    html`<option value=${k}>${v[0]}</option>`)}
                </select>`}
            </div>
          </div>
          ${bloc('Produits', produits)}
          ${bloc('Charges', charges)}
        </div>`}

      ${onglet === 'synthese' && html`
        <div>
          <div class="panneau">
            <div class="tete"><h3 style="font-size:17px">Compte de résultat</h3></div>
            <div class="ligne"><span class="muted">Total des produits</span>
              <span class="mono" style="font-size:15px">${EURO(b.produits_realises)}</span></div>
            <div class="ligne"><span class="muted">Total des charges</span>
              <span class="mono" style="font-size:15px">${EURO(b.charges_realisees)}</span></div>
            <div class="ligne" style="background:var(--papier)">
              <strong>Résultat de l\u2019exercice</strong>
              <span class="mono" style=${'font-size:17px;font-weight:700;color:'+
                (Number(b.resultat_realise)<0?'var(--bordeaux)':'var(--valide)')}>
                ${EURO(b.resultat_realise)}</span></div>
            <div class="corps small muted" style="border-top:1px solid var(--filet)">
              Le bénévolat valorisé (${EURO(b.benevolat)}) figure en produit comme
              en charge, conformément au plan comptable associatif : il ne change
              pas le résultat, mais il montre le poids réel de l\u2019engagement —
              ce que tout financeur regarde.
            </div>
          </div>

          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">Exécution du budget</h3>
              ${b.execution !== null && html`<span class="mono">${b.execution} %</span>`}</div>
            <div class="corps">
              <div class="spread small"><span>Charges prévues</span>
                <span class="mono">${EURO(b.charges)}</span></div>
              <div class="jauge" style="margin-top:8px;height:8px">
                <i style=${'width:'+Math.min(b.execution||0,100)+'%;background:'+
                  ((b.execution||0)>100?'var(--bordeaux)':'var(--bleu)')}></i></div>
              <div class="spread small muted" style="margin-top:6px">
                <span>Réalisé ${EURO(b.charges_realisees)}</span>
                <span>${(b.execution||0) > 100 ? 'Dépassement' : 'Dans l\u2019enveloppe'}</span>
              </div>
            </div>
          </div>
        </div>`}

      ${onglet === 'sauvegardes' && sauv && html`
        <div>
          <p class="small muted" style="margin-bottom:16px;max-width:62ch">
            Le plan gratuit de Supabase ne fournit aucune sauvegarde automatique.
            Exportez chaque mois le budget, les dépenses, le registre des adhésions
            et le registre disciplinaire, déposez-les sur le Drive de la fédération,
            puis déclarez-le ici.
          </p>
          <div class="panneau">
            <div class="tete">
              <h3 style="font-size:17px">${sauv.periode}</h3>
              ${sauv.faite_ce_mois
                ? html`<span class="tag vert">Faite</span>`
                : html`<span class="tag rouge">À faire</span>`}
            </div>
            ${(sauv.historique||[]).length === 0
              ? html`<div class="vide">Aucune sauvegarde déclarée.</div>`
              : (sauv.historique||[]).map(h => html`
                <div class="ligne">
                  <div>
                    <div>${h.periode} — ${h.portee}</div>
                    <div class="small muted">${h.par} · ${jour(h.le)}
                      ${h.emplacement ? ' · ' + h.emplacement : ''}</div>
                  </div>
                  <span class="tag vert">Déclarée</span>
                </div>`)}
          </div>
        </div>`}
    </div>`;
}

/* =====================================================================
   RAPPORT D'ACTIVITÉ
   Les chiffres se calculent, le récit se rédige.

   ===================================================================== */
export function Rapport({ p }){
  const [annee, setAnnee] = useState(new Date().getFullYear() - 1);
  const [c, setC] = useState(null);
  const [r, setR] = useState({});
  const [edition, setEdition] = useState(false);
  const [msg, setMsg] = useState('');

  const peutRediger = p.niveau >= 60 || (p.postes||[]).length > 0;

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('chiffres_annee', { p_annee: annee, p_territoire: null }),
      db.from('rapports').select('*').eq('annee', annee).is('territoire_id', null).maybeSingle()
    ]);
    setC(a.data); setR(b.data || {annee});
  }, [annee]);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(e, statut){
    if (e) e.preventDefault();
    const { data, error } = await db.rpc('enregistrer_rapport', {
      p_annee: annee, p_territoire: null, p_titre: r.titre || null,
      p_edito: r.edito || null, p_faits: r.faits_marquants || null,
      p_perspectives: r.perspectives || null, p_remerciements: r.remerciements || null,
      p_statut: statut || r.statut || 'brouillon'
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setEdition(false); setMsg('Rapport enregistré.'); charger();
  }

  async function exporter(){
    if (!c) return;
    const plat = [];
    const parcourir = (obj, prefixe) => {
      Object.entries(obj).forEach(([k,v]) => {
        if (v && typeof v === 'object' && !Array.isArray(v)) parcourir(v, prefixe + k + ' / ');
        else plat.push({ indicateur: prefixe + k, valeur: v });
      });
    };
    parcourir(c, '');
    const csv = '\ufeff' + 'indicateur;valeur\n' +
      plat.map(l => l.indicateur + ';' + l.valeur).join('\n');
    const url = URL.createObjectURL(new Blob([csv], {type:'text/csv;charset=utf-8'}));
    const a = document.createElement('a');
    a.href = url; a.download = 'FFCE-chiffres-' + annee + '.csv'; a.click();
    URL.revokeObjectURL(url);
    setMsg('Chiffres exportés.');
  }

  if (!c) return html`<div class="vide">Chargement…</div>`;

  const carte = (titre, entrees) => html`
    <div class="panneau" style="margin-bottom:20px">
      <div class="tete"><h3 style="font-size:17px">${titre}</h3></div>
      <div class="corps">
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:18px">
          ${entrees.map(([lab, val]) => html`
            <div>
              <div style="font-family:var(--titre);font-weight:900;font-size:26px;
                color:var(--framboise);line-height:1">${val ?? 0}</div>
              <div class="small muted" style="margin-top:4px">${lab}</div>
            </div>`)}
        </div>
      </div>
    </div>`;

  const champ = (cle, lab, aide) => html`
    <div class="field">
      <label>${lab}</label>
      <textarea value=${r[cle]||''} style="min-height:120px"
        onInput=${e=>setR(o=>({...o,[cle]:e.target.value}))} placeholder=${aide} />
    </div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Rapport d\u2019activité</div>
          <h1 style="margin:6px 0 0">${r.titre || 'Année ' + annee}</h1>
        </div>
        <div class="row">
          <select style="width:auto" value=${annee}
            onChange=${e=>setAnnee(Number(e.target.value))}>
            ${[0,1,2,3].map(n => {
              const a = new Date().getFullYear() - n;
              return html`<option value=${a}>${a}</option>`;
            })}
          </select>
          <button class="btn sm light" onClick=${exporter}>Exporter les chiffres</button>
          ${peutRediger && html`<button class="btn sm"
            onClick=${()=>setEdition(x=>!x)}>
            ${edition ? 'Annuler' : 'Rédiger'}</button>`}
        </div>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${r.statut && html`<div style="margin-top:16px">
        <span class=${'tag '+(r.statut==='adopte'||r.statut==='publie'?'vert':'')}>
          ${r.statut}${r.adopte_le ? ' le ' + jour(r.adopte_le) : ''}</span></div>`}

      ${edition
        ? html`
          <form onSubmit=${e=>enregistrer(e)} class="panneau" style="margin-top:24px">
            <div class="corps stack">
              <div class="field"><label>Titre du rapport</label>
                <input value=${r.titre||''}
                  onInput=${e=>setR(o=>({...o,titre:e.target.value}))}
                  placeholder=${'Rapport d\u2019activité ' + annee} /></div>
              ${champ('edito','Éditorial',
                'Le mot d\u2019introduction — ce que cette année a représenté.')}
              ${champ('faits_marquants','Faits marquants',
                'Trois à cinq moments qui ont compté.')}
              ${champ('perspectives','Perspectives',
                'Ce que la fédération entend faire l\u2019an prochain.')}
              ${champ('remerciements','Remerciements',
                'Partenaires, financeurs, bénévoles.')}
              <div class="row">
                <button class="btn">Enregistrer</button>
                <button type="button" class="btn light"
                  onClick=${()=>enregistrer(null,'adopte')}>Enregistrer et adopter</button>
              </div>
              <p class="small muted">
                Un rapport adopté devient lisible de tous les membres.
              </p>
            </div>
          </form>`
        : html`
          <div style="margin-top:24px">
            ${r.edito && html`
              <div class="panneau" style="margin-bottom:20px">
                <div class="tete"><h3 style="font-size:17px">Éditorial</h3></div>
                <div class="corps" style="white-space:pre-wrap;max-width:66ch">
                  ${r.edito}</div>
              </div>`}

            ${carte('Les adhérents', [
              ['Membres actifs', c.adherents.total_fin_annee],
              ['Nouvelles adhésions', c.adherents.nouveaux]
            ])}
            ${carte('Le bénévolat', [
              ['Heures données', Number(c.benevolat.heures||0)],
              ['Bénévoles actifs', c.benevolat.benevoles_actifs]
            ])}
            ${carte('Les actions', [
              ['Missions organisées', c.actions.missions],
              ['Participations', c.actions.participations],
              ['Projets menés', c.actions.projets],
              ['Bénéficiaires', c.actions.beneficiaires]
            ])}
            ${carte('La formation', [
              ['Certifications délivrées', c.formation.certifications],
              ['Parcours disponibles', c.formation.formations_publiees]
            ])}
            ${carte('Le réseau', [
              ['Départements couverts', c.reseau.departements],
              ['Structures actives', c.reseau.structures_actives],
              ['Assemblées tenues', c.reseau.assemblees],
              ['Groupes de travail', c.reseau.groupes_travail]
            ])}
            ${carte('La vie démocratique', [
              ['Propositions déposées', c.vie_democratique.propositions],
              ['Propositions retenues', c.vie_democratique.propositions_retenues]
            ])}

            ${r.faits_marquants && html`
              <div class="panneau" style="margin-bottom:20px">
                <div class="tete"><h3 style="font-size:17px">Faits marquants</h3></div>
                <div class="corps" style="white-space:pre-wrap;max-width:66ch">
                  ${r.faits_marquants}</div>
              </div>`}
            ${r.perspectives && html`
              <div class="panneau" style="margin-bottom:20px">
                <div class="tete"><h3 style="font-size:17px">Perspectives</h3></div>
                <div class="corps" style="white-space:pre-wrap;max-width:66ch">
                  ${r.perspectives}</div>
              </div>`}
            ${r.remerciements && html`
              <div class="panneau">
                <div class="tete"><h3 style="font-size:17px">Remerciements</h3></div>
                <div class="corps" style="white-space:pre-wrap;max-width:66ch">
                  ${r.remerciements}</div>
              </div>`}
          </div>`}
    </div>`;
}


/* =====================================================================
   PUBLIER LOCALEMENT
   Le national prépare, le local adapte et publie. Les [crochets] sont
   délibérés : une publication identique partout sonne faux, une
   publication entièrement libre dérive.


export function Ressources({ p }){
  const [onglet, setOnglet]   = useState('catalogue');
  const [solde, setSolde]     = useState(null);
  const [cats, setCats]       = useState([]);
  const [articles, setArt]    = useState([]);
  const [commandes, setCmd]   = useState([]);
  const [panier, setPanier]   = useState(null);
  const [lignes, setLignes]   = useState([]);
  const [invent, setInvent]   = useState([]);
  const [inv, setInv]         = useState({ miennes:[], a_instruire:[], a_ordonnancer:[] });
  const [regles, setRegles]   = useState([]);
  const [dotations, setDot]   = useState([]);
  const [msg, setMsg]         = useState('');
  const [pret, setPret]       = useState(false);

  const charger = useCallback(async () => {
    const annee = new Date().getFullYear();
    const [s, c, a, cmd, ivt, rg, dt, i1, i2, i3] = await Promise.all([
      db.rpc('solde_points', {}),
      db.from('categories_ressource').select('*').order('ordre'),
      db.from('articles_catalogue').select('*').order('ordre'),
      db.from('commandes').select('*, territoires(nom)')
        .order('cree_le', { ascending:false }),
      db.from('inventaire').select('*, articles_catalogue(nom,reference,unite)')
        .order('maj_le', { ascending:false }),
      db.from('regles_dotation').select('*').order('ordre'),
      db.from('dotations').select('*, territoires(nom)').eq('annee', annee),
      db.rpc('investissements_a_traiter', { p_filtre:'miennes' }),
      db.rpc('investissements_a_traiter', { p_filtre:'a_instruire' }),
      db.rpc('investissements_a_traiter', { p_filtre:'a_ordonnancer' })
    ]);
    setSolde(s.data || null);
    setCats(c.data || []);
    setArt(a.data || []);
    setCmd(cmd.data || []);
    setInvent(ivt.data || []);
    setRegles(rg.data || []);
    setDot(dt.data || []);
    setInv({ miennes:i1.data || [], a_instruire:i2.data || [],
             a_ordonnancer:i3.data || [] });

    // Le panier : la commande en brouillon que j'ai ouverte.
    const br = (cmd.data || []).find(x => x.statut === 'brouillon' && x.demandeur_id === p.id);
    setPanier(br || null);
    if (br){
      const { data } = await db.from('commande_lignes')
        .select('*, articles_catalogue(nom,reference,unite,cout_points)')
        .eq('commande_id', br.id);
      setLignes(data || []);
    } else setLignes([]);
    setPret(true);
  }, [p.id]);
  useEffect(() => { charger(); }, [charger]);

  /* Un seul chemin pour tous les appels : la base répond, on affiche. */
  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return false; }
    setMsg(ok); charger(); return true;
  };

  if (!pret) return html`<div class="vide" style="padding:120px">Chargement…</div>`;

  // Les droits viennent de `mes_droits()` : l'étiquette affichée et la
  // réalité lisent la même source.
  const droits  = p.droits || [];
  const admin   = p.niveau >= 90;
  const peutLog = admin || droits.includes('stock.national');
  const peutDot = admin || droits.includes('stock.dotation');

  const mesCmd    = commandes.filter(c => c.demandeur_id === p.id && c.statut !== 'brouillon');
  const cmdReseau = commandes.filter(c => c.demandeur_id !== p.id);
  const aTraiter  = cmdReseau.filter(c => ['deposee','validee'].includes(c.statut));

  const tabs = [['catalogue','Catalogue'], ['commandes','Commandes'],
                ['inventaire','Inventaire'], ['investissements','Investissements']];
  if (peutLog) tabs.push(['logistique','Logistique']);
  if (peutDot) tabs.push(['dotations','Dotations']);

  return html`
    <div>
      <div class="eyebrow">Ressources et matériel</div>
      <h1 style="margin:6px 0 8px">Ce que nous avons, ce qu\u2019il nous faut</h1>
      <p class="muted" style="max-width:62ch">
        Le catalogue fédéral s\u2019obtient en points : une dotation annuelle,
        calculée sur l\u2019effectif et l\u2019activité de la structure. Ce que le
        catalogue ne propose pas se demande en investissement, et suit alors
        le circuit ordinaire de la dépense.
      </p>

      <${ResSolde} solde=${solde} />

      <div style="margin-top:28px"><${MesEnveloppes} setMsg=${setMsg} /></div>

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet);
        flex-wrap:wrap">
        ${tabs.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--brun)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>{setOnglet(k);setMsg('')}}>${t}${
              k==='commandes' && lignes.length ? ' ('+lignes.length+')' : ''}${
              k==='logistique' && aTraiter.length ? ' ('+aTraiter.length+')' : ''}${
              k==='investissements' && (inv.a_instruire.length+inv.a_ordonnancer.length)
                ? ' ('+(inv.a_instruire.length+inv.a_ordonnancer.length)+')' : ''}</button>`)}
      </div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-bottom:20px">${msg}</div>`}

      ${onglet === 'catalogue' && html`<${ResCatalogue} cats=${cats} articles=${articles}
        lignes=${lignes} appel=${appel} aller=${()=>setOnglet('commandes')} />`}
      ${onglet === 'commandes' && html`<${ResCommandes} p=${p} panier=${panier}
        lignes=${lignes} mesCmd=${mesCmd} cmdReseau=${cmdReseau} solde=${solde}
        appel=${appel} />`}
      ${onglet === 'inventaire' && html`<${ResInventaire} invent=${invent}
        articles=${articles} peutLog=${peutLog} appel=${appel} setMsg=${setMsg} />`}
      ${onglet === 'investissements' && html`<${ResInvestissements} inv=${inv}
        appel=${appel} />`}
      ${onglet === 'logistique' && html`<${ResLogistique} aTraiter=${aTraiter}
        articles=${articles} cats=${cats} appel=${appel} recharger=${charger}
        setMsg=${setMsg} />`}
      ${onglet === 'dotations' && html`<${ResDotations} regles=${regles}
        dotations=${dotations} p=${p} appel=${appel} setMsg=${setMsg} />`}
    </div>`;
}


/* --- Le solde de points, en tête de tous les volets ------------------- */
export function ResSolde({ solde }){
  if (!solde) return null;
  if (!solde.dotee) return html`
    <div class="alerte" style="margin-top:24px;border-left:3px solid var(--brun)">
      Votre structure n\u2019a pas encore reçu sa dotation ${solde.annee}.
      Les commandes au catalogue seront possibles dès son attribution par la
      direction financière.
    </div>`;
  const total = Number(solde.total) || 0;
  const dep   = Number(solde.depenses) || 0;
  const pct   = total ? Math.min(100, Math.round(dep * 100 / total)) : 0;
  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete spread">
        <h3 style="font-size:17px">Dotation ${solde.annee} — ${solde.territoire || ''}</h3>
        <span class="mono" style="font-size:15px">${solde.disponible} points disponibles</span>
      </div>
      <div class="corps">
        <div class="row" style="gap:28px;flex-wrap:wrap">
          <div><div class="small muted">Alloués</div>
            <div class="mono" style="font-size:19px">${solde.alloues}</div></div>
          <div><div class="small muted">Reportés</div>
            <div class="mono" style="font-size:19px">${solde.reportes}</div></div>
          ${Number(solde.bonus) > 0 && html`<div><div class="small muted">Bonus${
            Number(solde.exceptionnel) > 0 ? ' et exceptionnel' : ''}</div>
            <div class="mono" style="font-size:19px">${solde.bonus}</div></div>`}
          <div><div class="small muted">Dépensés</div>
            <div class="mono" style="font-size:19px">${solde.depenses}</div></div>
          <div><div class="small muted">Engagés (en cours)</div>
            <div class="mono" style="font-size:19px">${solde.engages}</div></div>
        </div>
        <div class="jauge"><i style=${'width:'+pct+'%'}></i></div>
        <div class="small muted" style="margin-top:6px">
          ${pct} % de la dotation consommée. Un panier en cours ne coûte rien :
          les points sont retenus au dépôt de la commande, et rendus si elle
          est refusée ou retirée. Les points non dépensés sont reportables en
          partie sur l\u2019exercice suivant.
        </div>
      </div>
    </div>`;
}


/* --- Le catalogue ---------------------------------------------------- */
export function ResCatalogue({ cats, articles, lignes, appel, aller }){
  const [qte, setQte] = useState({});
  const [variante, setVariante] = useState({});
  const actifs = articles.filter(a => a.actif);

  async function ajouter(a){
    const n = Number(qte[a.id] || 1);
    if (!(n > 0)) return;
    const v = (a.variantes && a.variantes.length) ? variante[a.id] : null;
    const ok = await appel('ajouter_au_panier',
      { p_article:a.id, p_quantite:n, p_variante: v || null, p_commande: null },
      n + ' × ' + a.nom + (v ? ' (' + v + ')' : '') + ' ajouté au panier.');
    if (ok) setQte({ ...qte, [a.id]: '' });
  }

  return html`
    <div>
      ${lignes.length > 0 && html`
        <div class="alerte" style="margin-bottom:20px">
          ${lignes.length} article(s) dans votre panier.
          <a href="#" onClick=${e=>{e.preventDefault();aller()}}>Voir et déposer la commande</a>
        </div>`}

      ${cats.map(c => {
        const liste = actifs.filter(a => a.categorie === c.code);
        if (liste.length === 0) return null;
        return html`
          <div class="panneau" style="margin-bottom:24px">
            <div class="tete"><h3 style="font-size:17px">${c.nom}</h3></div>
            ${liste.map(a => {
              const rupture = a.stock_national !== null && a.stock_national <= 0;
              const bas = a.stock_national !== null && !rupture
                          && a.stock_national <= (a.seuil_alerte || 0);
              return html`
                <div class="ligne" style="align-items:flex-start">
                  <div style="flex:1;min-width:260px">
                    <div class="row" style="gap:8px;flex-wrap:wrap">
                      <span style="font-weight:600">${a.nom}</span>
                      <span class="mono muted small">${a.reference}</span>
                      ${rupture && html`<span class="tag rouge">Rupture</span>`}
                      ${bas && html`<span class="tag or">Stock bas</span>`}
                    </div>
                    ${a.description && html`
                      <div class="small muted" style="margin-top:3px">${a.description}</div>`}
                    <div class="small muted" style="margin-top:4px">
                      ${a.conditionnement || a.unite}${a.stock_national === null
                        ? ' · à la demande'
                        : ' · ' + a.stock_national + ' en stock national'}${
                        a.plafond_annuel ? ' · plafond de ' + a.plafond_annuel
                                           + ' par an et par structure' : ''}
                    </div>
                  </div>
                  <div class="row" style="gap:8px">
                    <span class="mono" style="font-size:15px">${a.cout_points} pts</span>
                    ${a.variantes && a.variantes.length > 0 && html`
                      <select value=${variante[a.id] || ''} style="width:auto;
                        padding:6px 8px;font-size:14px"
                        onChange=${e=>setVariante({ ...variante, [a.id]: e.target.value })}>
                        <option value="">${a.variante_libelle || 'Choisir'}</option>
                        ${a.variantes.map(v => html`<option value=${v}>${v}</option>`)}
                      </select>`}
                    <input type="number" min="1" value=${qte[a.id] || ''} placeholder="1"
                      style="width:74px;padding:6px 8px;font-size:14px"
                      onInput=${e=>setQte({ ...qte, [a.id]: e.target.value })} />
                    <button class="btn sm" disabled=${rupture}
                      onClick=${()=>ajouter(a)}>Ajouter</button>
                  </div>
                </div>`;
            })}
          </div>`;
      })}
      ${actifs.length === 0 && html`<div class="vide">Le catalogue est vide.</div>`}
    </div>`;
}


/* --- Le panier et les commandes -------------------------------------- */
export function ResCommandes({ p, panier, lignes, mesCmd, cmdReseau, solde, appel }){
  const [motif, setMotif] = useState('');
  const [adresse, setAdresse] = useState('');
  const [destinataire, setDestinataire] = useState('');
  const [source, setSource] = useState('territoire');
  const [plan, setPlan] = useState(null);
  const [aValider, setAValider] = useState([]);

  const total0 = lignes.reduce((s,l) => s + Number(l.points||0), 0);

  // Le plan d'engagement vient de la base : l'écran ne recalcule pas la
  // règle « personnel d'abord, direction ensuite », il l'affiche.
  useEffect(() => {
    if (source !== 'enveloppe' || total0 <= 0) return setPlan(null);
    db.rpc('plan_engagement', { p_points: total0 }).then(({data}) => setPlan(data));
  }, [source, total0]);

  useEffect(() => {
    db.rpc('engagements_a_valider').then(({data}) => setAValider(data || []));
  }, [mesCmd]);
  const total = lignes.reduce((s,l) => s + Number(l.points||0), 0);
  const dispo = solde ? Number(solde.disponible) || 0 : 0;

  // Le total n'est jamais recalculé ici : la base s'en charge, sans quoi
  // l'affichage et le montant débité pourraient diverger.
  const regler = (l, n) => appel('regler_ligne_panier',
    { p_ligne: l.id, p_quantite: n },
    n > 0 ? 'Quantité corrigée.' : 'Article retiré du panier.');

  return html`
    <div>
      <div class="panneau" style="margin-bottom:28px">
        <div class="tete spread">
          <h3 style="font-size:17px">Panier</h3>
          ${panier && html`<span class="mono small muted">${panier.reference}</span>`}
        </div>
        ${lignes.length === 0
          ? html`<div class="corps muted">
              Votre panier est vide. Choisissez au catalogue.</div>`
          : html`
            ${lignes.map(l => html`
              <div class="ligne">
                <div style="flex:1;min-width:220px">
                  <div>${l.articles_catalogue?.nom || 'Article'}${
                    l.variante ? ' · ' + l.variante : ''}</div>
                  <div class="small muted">
                    <span class="mono">${l.articles_catalogue?.reference || ''}</span>
                    · ${l.quantite} ${l.articles_catalogue?.unite || 'unité'}
                  </div>
                </div>
                <div class="row" style="gap:10px">
                  <input type="number" min="1" defaultValue=${l.quantite}
                    style="width:70px;padding:6px 8px;font-size:14px;text-align:right"
                    onBlur=${e=>{
                      const n = Number(e.target.value);
                      if (n !== l.quantite) regler(l, n);
                    }} />
                  <span class="mono">${l.points} pts</span>
                  <button class="btn sm light" onClick=${()=>regler(l, 0)}>Retirer</button>
                </div>
              </div>`)}
            <div class="corps">
              <div class="spread" style="margin-bottom:14px">
                <span class="muted">Total de la commande</span>
                <span class="mono" style="font-size:17px">${total} points</span>
              </div>
              ${total > dispo && html`
                <div class="alerte err" style="margin-bottom:14px">
                  Solde insuffisant : ${dispo} points disponibles pour ${total} demandés.
                </div>`}
              <div class="field">
                <label>Motif de la commande</label>
                <textarea value=${motif} style="min-height:70px"
                  placeholder="À quoi ce matériel va-t-il servir ?"
                  onInput=${e=>setMotif(e.target.value)}></textarea>
              </div>
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:2;min-width:220px">
                  <label>Adresse de livraison</label>
                  <textarea value=${adresse} style="min-height:70px"
                    placeholder="Numéro, rue, complément, code postal, commune"
                    onInput=${e=>setAdresse(e.target.value)}></textarea>
                </div>
                <div class="field" style="flex:1;min-width:180px">
                  <label>À l\u2019attention de</label>
                  <input value=${destinataire} placeholder="Qui réceptionne"
                    onInput=${e=>setDestinataire(e.target.value)} />
                </div>
              </div>
              <div class="field">
                <label>Sur quels points</label>
                <select value=${source} onChange=${e=>setSource(e.target.value)}>
                  <option value="territoire">La dotation de ma structure</option>
                  <option value="enveloppe">Mes enveloppes (personnelle, puis direction)</option>
                </select>
              </div>

              ${source === 'enveloppe' && plan && html`
                <div class="alerte" style="margin:0">
                  ${(plan.plan||[]).length === 0
                    ? 'Vous ne portez aucune enveloppe engageable.'
                    : html`
                      <div class="small" style="margin-bottom:6px">
                        Ce qui sera engagé, dans cet ordre :</div>
                      ${plan.plan.map((x,i) => html`
                        <div class="small" key=${i}>
                          ${x.libelle} — <span class="mono">${x.points} pts</span></div>`)}`}
                  ${plan.reste > 0 && html`
                    <div class="small" style="color:var(--rouge);margin-top:6px">
                      Il manque ${plan.reste} points : vos enveloppes ne couvrent pas
                      cette commande.</div>`}
                </div>`}

              <div class="small muted">
                Les points ne sont retenus qu\u2019au dépôt, et rendus si la
                commande est refusée ou retirée. Si vous n\u2019êtes pas habilité à
                engager, la commande partira en validation auprès du responsable
                \u2014 préparer n\u2019est pas engager.
              </div>
              <div style="margin-top:14px">
                <button class="btn"
                  disabled=${!adresse.trim()
                    || (source === 'territoire' && total > dispo)
                    || (source === 'enveloppe' && (!plan || plan.reste > 0))}
                  onClick=${async ()=>{
                    const r = await appel('deposer_commande',
                      { p_id: panier.id, p_motif: motif, p_adresse: adresse,
                        p_destinataire: destinataire || null, p_source: source },
                      'Commande transmise.');
                  }}>
                  Déposer la commande</button>
              </div>
            </div>`}
      </div>

      ${aValider.length > 0 && html`
        <h3 style="font-size:17px;margin-bottom:12px">Engagements à valider</h3>
        <div class="panneau" style="margin-bottom:28px;border-color:var(--brun)">
          <div class="corps small muted" style="padding-bottom:0">
            Ces paniers ont été préparés par des membres qui n\u2019ont pas
            l\u2019habilitation d\u2019engager les points. Rien n\u2019est débité tant que
            vous n\u2019avez pas validé.
          </div>
          ${aValider.map(c => html`
            <div class="ligne" key=${c.id} style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px">
                  <span class="mono">${c.reference}</span>
                  <span class="mono muted small">${c.points} pts</span>
                </div>
                <div class="small muted" style="margin-top:3px">
                  ${c.demandeur}${c.territoire ? ' · ' + c.territoire : ''}
                  · ${jour(c.cree_le)}</div>
                ${c.motif && html`<div class="small" style="margin-top:4px">${c.motif}</div>`}
                ${(c.finance_par||[]).map((x,i) => html`
                  <div class="small muted" key=${i} style="margin-top:2px">
                    Sur ${x.libelle} — ${x.points} pts</div>`)}
              </div>
              <div class="row" style="gap:6px">
                <button class="btn sm" onClick=${()=>appel('valider_engagement',
                  { p_id:c.id, p_ok:true, p_motif:null },
                  'Engagement validé. Les points sont retenus.')}>Engager</button>
                <button class="btn sm light" onClick=${()=>{
                  const m = prompt('Motif du refus (obligatoire)');
                  if (m) appel('valider_engagement', { p_id:c.id, p_ok:false, p_motif:m },
                    'Demande refusée.');
                }}>Refuser</button>
              </div>
            </div>`)}
        </div>`}

      <h3 style="font-size:17px;margin-bottom:12px">Mes commandes</h3>
      <div class="panneau" style="margin-bottom:28px">
        ${mesCmd.length === 0
          ? html`<div class="corps muted">Aucune commande déposée.</div>`
          : mesCmd.map(c => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px">
                  <span class="mono">${c.reference}</span>
                  <span class="mono muted small">${c.points_debites} pts</span>
                </div>
                <div class="small muted" style="margin-top:3px">
                  Déposée le ${jour(c.cree_le)}${c.motif ? ' · ' + c.motif : ''}
                </div>
                ${c.motif_refus && html`
                  <div class="small" style="color:var(--rouge);margin-top:4px">
                    Refus : ${c.motif_refus}</div>`}
                ${c.expediee_le && html`
                  <div class="small muted" style="margin-top:4px">
                    Expédiée le ${jour(c.expediee_le)}${
                      c.transporteur ? ' par ' + c.transporteur : ''}${
                      c.suivi ? ' · suivi ' + c.suivi : ''}</div>`}
              </div>
              <div class="row" style="gap:10px">
                ${etatCmd(c.statut)}
                ${['deposee','validee'].includes(c.statut) && html`
                  <button class="btn sm light" onClick=${()=>appel('retirer_commande',
                    { p_id:c.id, p_motif:null },
                    'Commande retirée. Les points vous sont rendus.')}>
                    Retirer</button>`}
                ${c.statut === 'expediee' && html`
                  <button class="btn sm" onClick=${()=>appel('traiter_commande',
                    { p_id:c.id, p_statut:'recue', p_motif:null,
                      p_transporteur:null, p_suivi:null },
                    'Réception enregistrée. Le matériel entre à votre inventaire.')}>
                    Signaler la réception</button>`}
              </div>
            </div>`)}
      </div>

      ${cmdReseau.length > 0 && html`
        <h3 style="font-size:17px;margin-bottom:12px">Commandes du réseau</h3>
        <div class="panneau">
          ${cmdReseau.slice(0,25).map(c => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <span class="mono">${c.reference}</span>
                <div class="small muted">${c.territoires?.nom || ''} ·
                  ${c.points_debites} pts · ${jour(c.cree_le)}</div>
              </div>
              ${etatCmd(c.statut)}
            </div>`)}
        </div>`}
    </div>`;
}


/* --- L'inventaire ---------------------------------------------------- */
export function ResInventaire({ invent, articles, peutLog, appel, setMsg }){
  const vierge = { id:null, article_id:'', libelle_libre:'', quantite:1,
                   etat:'bon', emplacement:'', origine:'achat_local',
                   valeur_euros:'', observation:'' };
  const [f, setF] = useState(vierge);
  const [ouvert, setOuvert] = useState(false);
  const [reseau, setReseau] = useState(null);
  const maj = (k,v) => setF({ ...f, [k]: v });

  function editer(i){
    setF({ id:i.id, article_id:i.article_id || '', libelle_libre:i.libelle_libre || '',
           quantite:i.quantite, etat:i.etat, emplacement:i.emplacement || '',
           origine:i.origine, valeur_euros:i.valeur_euros || '',
           observation:i.observation || '' });
    setOuvert(true);
  }

  async function enregistrer(){
    if (!f.article_id && !String(f.libelle_libre).trim())
      return setMsg('Erreur : choisissez un article du catalogue ou donnez un libellé.');
    const ok = await appel('enregistrer_inventaire', {
      p_id: f.id, p_article: f.article_id || null,
      p_libelle: f.libelle_libre || null, p_quantite: Number(f.quantite) || 0,
      p_etat: f.etat, p_emplacement: f.emplacement || null,
      p_origine: f.origine,
      p_valeur: f.valeur_euros === '' ? null : Number(f.valeur_euros),
      p_observation: f.observation || null
    }, 'Inventaire mis à jour.');
    if (ok){ setF(vierge); setOuvert(false); }
  }

  async function voirReseau(){
    const { data, error } = await db.rpc('etat_ressources', { p_territoire: null });
    if (error) return setMsg('Erreur : ' + error.message);
    setReseau(data || []);
  }

  function exporter(){
    if (!reseau || reseau.length === 0) return setMsg('Rien à exporter.');
    const cols = Object.keys(reseau[0]);
    const ech = v => {
      if (v === null || v === undefined) return '';
      const t = String(v).replace(/"/g,'""');
      return /[";\n]/.test(t) ? '"'+t+'"' : t;
    };
    const csv = '\ufeff' + cols.join(';') + '\n' +
      reseau.map(l => cols.map(c => ech(l[c])).join(';')).join('\n');
    const url = URL.createObjectURL(new Blob([csv], { type:'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url; a.download = 'FFCE-inventaire.csv'; a.click();
    URL.revokeObjectURL(url);
  }

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px;flex-wrap:wrap;gap:10px">
        <p class="muted" style="max-width:56ch;margin:0">
          Ce que la structure détient, quel qu\u2019en soit l\u2019origine : commandé au
          catalogue, acheté sur place, reçu en don ou financé par un
          investissement. Ce qui arrive par commande s\u2019y inscrit tout seul.
        </p>
        <div class="row" style="gap:8px">
          ${peutLog && html`<button class="btn light sm" onClick=${voirReseau}>
            Vue du réseau</button>`}
          <button class="btn sm" onClick=${()=>{setF(vierge);setOuvert(!ouvert)}}>
            ${ouvert ? 'Fermer' : 'Ajouter une entrée'}</button>
        </div>
      </div>

      ${ouvert && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete"><h3 style="font-size:17px">
            ${f.id ? 'Modifier l\u2019entrée' : 'Nouvelle entrée'}</h3></div>
          <div class="corps">
            <div class="field">
              <label>Article du catalogue</label>
              <select value=${f.article_id} disabled=${!!f.id}
                onInput=${e=>maj('article_id', e.target.value)}>
                <option value="">— Hors catalogue (libellé libre) —</option>
                ${articles.map(a => html`
                  <option value=${a.id}>${a.reference} · ${a.nom}</option>`)}
              </select>
            </div>
            ${!f.article_id && html`
              <div class="field">
                <label>Libellé</label>
                <input value=${f.libelle_libre} placeholder="Ordinateur portable, tables…"
                  onInput=${e=>maj('libelle_libre', e.target.value)} />
              </div>`}
            <div class="row" style="gap:16px;margin-top:16px;align-items:flex-end">
              <div style="flex:1;min-width:110px">
                <label>Quantité</label>
                <input type="number" min="0" value=${f.quantite}
                  onInput=${e=>maj('quantite', e.target.value)} /></div>
              <div style="flex:1;min-width:150px">
                <label>État</label>
                <select value=${f.etat} onInput=${e=>maj('etat', e.target.value)}>
                  ${Object.entries(ETAT_INV).map(([k,v]) => html`
                    <option value=${k}>${v}</option>`)}
                </select></div>
              <div style="flex:1;min-width:150px">
                <label>Origine</label>
                <select value=${f.origine} disabled=${!!f.id}
                  onInput=${e=>maj('origine', e.target.value)}>
                  ${Object.entries(ORIGINE_INV).map(([k,v]) => html`
                    <option value=${k}>${v}</option>`)}
                </select></div>
            </div>
            <div class="row" style="gap:16px;margin-top:16px;align-items:flex-end">
              <div style="flex:1;min-width:160px">
                <label>Emplacement</label>
                <input value=${f.emplacement} placeholder="Local, armoire, chez qui…"
                  onInput=${e=>maj('emplacement', e.target.value)} /></div>
              <div style="flex:1;min-width:130px">
                <label>Valeur (€)</label>
                <input type="number" step="0.01" min="0" value=${f.valeur_euros}
                  onInput=${e=>maj('valeur_euros', e.target.value)} /></div>
            </div>
            <div class="field" style="margin-top:16px">
              <label>Observation</label>
              <input value=${f.observation} placeholder="Facultatif"
                onInput=${e=>maj('observation', e.target.value)} />
            </div>
            <div style="margin-top:18px">
              <button class="btn" onClick=${enregistrer}>Enregistrer</button>
            </div>
          </div>
        </div>`}

      ${reseau && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete spread">
            <h3 style="font-size:17px">Inventaire consolidé — ${reseau.length} ligne(s)</h3>
            <div class="row" style="gap:8px">
              <button class="btn sm light" onClick=${exporter}>Exporter en CSV</button>
              <button class="btn sm light" onClick=${()=>setReseau(null)}>Fermer</button>
            </div>
          </div>
          <div style="overflow-x:auto">
            <table>
              <thead><tr><th>Structure</th><th>Article</th><th>Catégorie</th>
                <th style="text-align:right">Qté</th><th>État</th>
                <th style="text-align:right">Valeur</th></tr></thead>
              <tbody>
                ${reseau.slice(0,300).map((l,i) => html`
                  <tr key=${i}>
                    <td>${l.territoire}</td>
                    <td>${l.article}${l.reference
                      ? html` <span class="mono muted small">${l.reference}</span>` : ''}</td>
                    <td class="small muted">${l.categorie || '—'}</td>
                    <td style="text-align:right" class="mono">${l.quantite}</td>
                    <td class="small">${ETAT_INV[l.etat] || l.etat}</td>
                    <td style="text-align:right" class="mono">
                      ${l.valeur ? EURO(l.valeur) : '—'}</td>
                  </tr>`)}
              </tbody>
            </table>
          </div>
        </div>`}

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Inventaire de la structure</h3></div>
        ${invent.length === 0
          ? html`<div class="corps muted">Rien d\u2019inscrit pour l\u2019instant.</div>`
          : invent.map(i => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span>${i.articles_catalogue?.nom || i.libelle_libre || 'Sans libellé'}</span>
                  ${i.articles_catalogue?.reference && html`
                    <span class="mono muted small">${i.articles_catalogue.reference}</span>`}
                  ${['a_remplacer','hors_service'].includes(i.etat) && html`
                    <span class="tag rouge">${ETAT_INV[i.etat]}</span>`}
                </div>
                <div class="small muted" style="margin-top:3px">
                  ${i.quantite} ${i.articles_catalogue?.unite || 'unité'}
                  · ${ETAT_INV[i.etat] || i.etat}
                  · ${ORIGINE_INV[i.origine] || i.origine}
                  ${i.emplacement ? ' · ' + i.emplacement : ''}
                  ${i.valeur_euros ? ' · ' + EURO(i.valeur_euros) : ''}
                </div>
                ${i.observation && html`
                  <div class="small muted" style="margin-top:3px">${i.observation}</div>`}
              </div>
              <button class="btn sm light" onClick=${()=>editer(i)}>Modifier</button>
            </div>`)}
      </div>
    </div>`;
}


/* --- Les investissements --------------------------------------------- */
export function ResInvestissements({ inv, appel }){
  const vierge = { intitule:'', justification:'', usage:'', montant:'',
                   fournisseur:'', beneficiaires:'' };
  const [f, setF] = useState(vierge);
  const [ouvert, setOuvert] = useState(false);
  const maj = (k,v) => setF({ ...f, [k]: v });

  async function demander(){
    const ok = await appel('demander_investissement', {
      p_intitule: f.intitule, p_justification: f.justification,
      p_usage: f.usage || null, p_montant: Number(f.montant) || 0,
      p_fournisseur: f.fournisseur || null, p_devis: null,
      p_beneficiaires: f.beneficiaires === '' ? null : Number(f.beneficiaires),
      p_mission: null, p_projet: null
    }, 'Demande déposée. Elle sera instruite, puis ordonnancée.');
    if (ok){ setF(vierge); setOuvert(false); }
  }

  const fiche = (i, actions) => html`
    <div class="ligne" style="align-items:flex-start">
      <div style="flex:1;min-width:260px">
        <div class="row" style="gap:8px;flex-wrap:wrap">
          <span style="font-weight:600">${i.intitule}</span>
          <span class="mono muted small">${i.reference}</span>
        </div>
        <div class="small muted" style="margin-top:3px">
          ${i.demandeur}${i.territoire ? ' · ' + i.territoire : ''} · ${jour(i.cree_le)}
          ${i.beneficiaires ? ' · ' + i.beneficiaires + ' bénéficiaires' : ''}
          ${i.fournisseur ? ' · ' + i.fournisseur : ''}
          ${i.mission ? ' · mission ' + i.mission : ''}
          ${i.projet ? ' · projet ' + i.projet : ''}
        </div>
        <div class="small" style="margin-top:6px">${i.justification}</div>
        ${i.usage_prevu && html`
          <div class="small muted" style="margin-top:3px">Usage prévu : ${i.usage_prevu}</div>`}
        ${i.avis_logistique && html`
          <div class="small muted" style="margin-top:3px">Avis : ${i.avis_logistique}</div>`}
        ${i.poste_budget && html`
          <div class="small muted" style="margin-top:3px">Imputation : ${i.poste_budget}</div>`}
      </div>
      <div class="row" style="gap:10px;align-items:flex-start">
        <span class="mono" style="font-size:15px">${EURO(i.montant)}</span>
        ${etatInv(i.statut)}
        ${actions}
      </div>
    </div>`;

  async function instruire(i, favorable){
    const t = prompt(favorable
      ? 'Avis favorable — motivez-le (obligatoire)'
      : 'Motif du rejet (obligatoire)');
    if (!t) return;
    const poste = favorable ? (prompt('Poste comptable (facultatif)') || null) : null;
    appel('instruire_investissement',
      { p_id:i.id, p_favorable:favorable, p_avis:t, p_poste:poste, p_exercice:null },
      favorable ? 'Avis enregistré. La demande passe à l\u2019ordonnateur.'
                : 'Demande rejetée.');
  }
  async function ordonnancer(i, ok){
    const t = ok ? null : prompt('Motif du refus (obligatoire)');
    if (!ok && !t) return;
    appel('ordonnancer_investissement', { p_id:i.id, p_ok:ok, p_motif:t },
      ok ? 'Investissement ordonnancé.' : 'Investissement refusé.');
  }

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px;flex-wrap:wrap;gap:10px">
        <p class="muted" style="max-width:56ch;margin:0">
          Un investissement n\u2019est pas une note de frais : c\u2019est une décision
          d\u2019équipement. Elle se motive, elle est instruite, puis ordonnancée
          par quelqu\u2019un d\u2019autre que son demandeur.
        </p>
        <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
          ${ouvert ? 'Fermer' : 'Demander un investissement'}</button>
      </div>

      ${ouvert && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete"><h3 style="font-size:17px">Nouvelle demande</h3></div>
          <div class="corps">
            <div class="field">
              <label>Intitulé</label>
              <input value=${f.intitule} placeholder="Vidéoprojecteur pour les ateliers"
                onInput=${e=>maj('intitule', e.target.value)} />
            </div>
            <div class="field">
              <label>Pourquoi est-ce nécessaire ?</label>
              <textarea value=${f.justification}
                placeholder="C\u2019est ce qui sera examiné : soyez précis."
                onInput=${e=>maj('justification', e.target.value)}></textarea>
            </div>
            <div class="field">
              <label>Ce que cela permettra de faire</label>
              <textarea value=${f.usage} style="min-height:70px"
                onInput=${e=>maj('usage', e.target.value)}></textarea>
            </div>
            <div class="row" style="gap:16px;margin-top:16px;align-items:flex-end">
              <div style="flex:1;min-width:130px">
                <label>Montant estimé (€)</label>
                <input type="number" step="0.01" min="0" value=${f.montant}
                  onInput=${e=>maj('montant', e.target.value)} /></div>
              <div style="flex:1;min-width:150px">
                <label>Fournisseur envisagé</label>
                <input value=${f.fournisseur}
                  onInput=${e=>maj('fournisseur', e.target.value)} /></div>
              <div style="flex:1;min-width:120px">
                <label>Bénéficiaires</label>
                <input type="number" min="0" value=${f.beneficiaires}
                  onInput=${e=>maj('beneficiaires', e.target.value)} /></div>
            </div>
            <div style="margin-top:18px">
              <button class="btn" onClick=${demander}>Déposer la demande</button>
            </div>
          </div>
        </div>`}

      ${inv.a_instruire.length > 0 && html`
        <h3 style="font-size:17px;margin-bottom:12px">À instruire</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${inv.a_instruire.map(i => fiche(i, html`
            <div class="row" style="gap:6px">
              <button class="btn sm" onClick=${()=>instruire(i, true)}>Avis favorable</button>
              <button class="btn sm danger" onClick=${()=>instruire(i, false)}>Rejeter</button>
            </div>`))}
        </div>`}

      ${inv.a_ordonnancer.length > 0 && html`
        <h3 style="font-size:17px;margin-bottom:12px">À ordonnancer</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${inv.a_ordonnancer.map(i => fiche(i, html`
            <div class="row" style="gap:6px">
              <button class="btn sm" onClick=${()=>ordonnancer(i, true)}>Ordonnancer</button>
              <button class="btn sm danger" onClick=${()=>ordonnancer(i, false)}>Refuser</button>
            </div>`))}
        </div>`}

      <h3 style="font-size:17px;margin-bottom:12px">Demandes de ma structure</h3>
      <div class="panneau">
        ${inv.miennes.length === 0
          ? html`<div class="corps muted">Aucune demande d\u2019investissement.</div>`
          : inv.miennes.map(i => fiche(i,
              ['ordonnancee','engagee'].includes(i.statut) ? html`
                <button class="btn sm" onClick=${()=>{
                  const fac = prompt('Référence de la facture (facultatif)') || '';
                  appel('receptionner_investissement', { p_id:i.id, p_facture:fac },
                    'Réception enregistrée. Le bien entre à votre inventaire.');
                }}>Signaler la réception</button>` : null))}
      </div>
    </div>`;
}


/* --- La logistique fédérale ------------------------------------------ */
export function ResLogistique({ aTraiter, articles, cats, appel, recharger, setMsg }){
  const [vue, setVue] = useState('commandes');
  const vierge = { reference:'', nom:'', description:'', categorie:'communication',
                   cout_points:0, valeur_euros:'', unite:'unité',
                   stock_national:'', seuil_alerte:10, plafond_annuel:'' };
  const [f, setF] = useState(vierge);
  const [ouvert, setOuvert] = useState(false);
  const maj = (k,v) => setF({ ...f, [k]: v });

  async function traiter(c, statut){
    if (statut === 'refusee'){
      const m = prompt('Motif du refus (obligatoire)');
      if (!m) return;
      return appel('traiter_commande', { p_id:c.id, p_statut:'refusee', p_motif:m,
        p_transporteur:null, p_suivi:null }, 'Commande refusée.');
    }
    if (statut === 'expediee'){
      const tr = prompt('Transporteur (facultatif)') || null;
      const su = prompt('Numéro de suivi (facultatif)') || null;
      return appel('traiter_commande', { p_id:c.id, p_statut:'expediee', p_motif:null,
        p_transporteur:tr, p_suivi:su }, 'Expédition enregistrée.');
    }
    appel('traiter_commande', { p_id:c.id, p_statut:statut, p_motif:null,
      p_transporteur:null, p_suivi:null }, 'Commande validée.');
  }

  async function majArticle(a, champ, valeur){
    const v = valeur === '' ? null : (champ === 'actif' ? valeur : Number(valeur));
    const { error } = await db.from('articles_catalogue')
      .update({ [champ]: v }).eq('id', a.id);
    if (error) return setMsg('Erreur : ' + error.message);
    setMsg('Catalogue mis à jour.'); recharger();
  }

  async function creer(){
    if (!f.reference.trim() || !f.nom.trim())
      return setMsg('Erreur : la référence et le nom sont obligatoires.');
    const { error } = await db.from('articles_catalogue').insert({
      reference: f.reference.trim(), nom: f.nom.trim(),
      description: f.description || null, categorie: f.categorie,
      cout_points: Number(f.cout_points) || 0,
      valeur_euros: f.valeur_euros === '' ? null : Number(f.valeur_euros),
      unite: f.unite || 'unité',
      stock_national: f.stock_national === '' ? null : Number(f.stock_national),
      seuil_alerte: Number(f.seuil_alerte) || 0,
      plafond_annuel: f.plafond_annuel === '' ? null : Number(f.plafond_annuel)
    });
    if (error) return setMsg('Erreur : ' + error.message);
    setF(vierge); setOuvert(false); setMsg('Article ajouté au catalogue.'); recharger();
  }

  return html`
    <div>
      <div class="row" style="gap:8px;margin-bottom:20px">
        ${[['commandes','Commandes à traiter'],['catalogue','Tenue du catalogue']]
          .map(([k,t]) => html`
            <button class=${'btn sm '+(vue===k?'':'light')}
              onClick=${()=>setVue(k)}>${t}</button>`)}
      </div>

      ${vue === 'commandes' && html`
        <div class="panneau">
          ${aTraiter.length === 0
            ? html`<div class="corps muted">Aucune commande en attente.</div>`
            : aTraiter.map(c => html`
              <div class="ligne" style="align-items:flex-start">
                <div style="flex:1;min-width:240px">
                  <div class="row" style="gap:8px">
                    <span class="mono">${c.reference}</span>
                    <span class="mono muted small">${c.points_debites} pts</span>
                  </div>
                  <div class="small muted" style="margin-top:3px">
                    ${c.territoires?.nom || ''} · déposée le ${jour(c.cree_le)}
                  </div>
                  ${c.adresse_livraison && html`
                    <div class="small muted" style="margin-top:4px;white-space:pre-wrap">
                      Livraison : ${c.adresse_livraison}${
                        c.destinataire ? ' — ' + c.destinataire : ''}</div>`}
                  ${c.motif && html`
                    <div class="small" style="margin-top:4px">${c.motif}</div>`}
                </div>
                <div class="row" style="gap:6px">
                  ${etatCmd(c.statut)}
                  ${c.statut === 'deposee' && html`
                    <button class="btn sm" onClick=${()=>traiter(c,'validee')}>Valider</button>
                    <button class="btn sm danger"
                      onClick=${()=>traiter(c,'refusee')}>Refuser</button>`}
                  ${c.statut === 'validee' && html`
                    <button class="btn sm"
                      onClick=${()=>traiter(c,'expediee')}>Expédier</button>`}
                </div>
              </div>`)}
        </div>`}

      ${vue === 'catalogue' && html`
        <div>
          <div class="spread" style="margin-bottom:16px">
            <p class="muted" style="max-width:52ch;margin:0">
              Le stock national se décrémente à l\u2019expédition, pas à la commande.
              Un article sans stock indiqué est produit à la demande.
            </p>
            <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
              ${ouvert ? 'Fermer' : 'Ajouter un article'}</button>
          </div>

          ${ouvert && html`
            <div class="panneau" style="margin-bottom:24px">
              <div class="tete"><h3 style="font-size:17px">Nouvel article</h3></div>
              <div class="corps">
                <div class="row" style="gap:16px;align-items:flex-end">
                  <div style="flex:1;min-width:130px">
                    <label>Référence</label>
                    <input value=${f.reference} placeholder="COM-005"
                      onInput=${e=>maj('reference', e.target.value)} /></div>
                  <div style="flex:2;min-width:200px">
                    <label>Nom</label>
                    <input value=${f.nom}
                      onInput=${e=>maj('nom', e.target.value)} /></div>
                  <div style="flex:1;min-width:170px">
                    <label>Catégorie</label>
                    <select value=${f.categorie}
                      onInput=${e=>maj('categorie', e.target.value)}>
                      ${cats.map(c => html`<option value=${c.code}>${c.nom}</option>`)}
                    </select></div>
                </div>
                <div class="field" style="margin-top:16px">
                  <label>Description</label>
                  <input value=${f.description}
                    onInput=${e=>maj('description', e.target.value)} />
                </div>
                <div class="row" style="gap:16px;margin-top:16px;align-items:flex-end">
                  <div style="flex:1;min-width:100px"><label>Coût (points)</label>
                    <input type="number" min="0" value=${f.cout_points}
                      onInput=${e=>maj('cout_points', e.target.value)} /></div>
                  <div style="flex:1;min-width:100px"><label>Valeur (€)</label>
                    <input type="number" step="0.01" min="0" value=${f.valeur_euros}
                      onInput=${e=>maj('valeur_euros', e.target.value)} /></div>
                  <div style="flex:1;min-width:110px"><label>Unité</label>
                    <input value=${f.unite}
                      onInput=${e=>maj('unite', e.target.value)} /></div>
                </div>
                <div class="row" style="gap:16px;margin-top:16px;align-items:flex-end">
                  <div style="flex:1;min-width:120px"><label>Stock national</label>
                    <input type="number" min="0" value=${f.stock_national}
                      placeholder="vide = illimité"
                      onInput=${e=>maj('stock_national', e.target.value)} /></div>
                  <div style="flex:1;min-width:110px"><label>Seuil d\u2019alerte</label>
                    <input type="number" min="0" value=${f.seuil_alerte}
                      onInput=${e=>maj('seuil_alerte', e.target.value)} /></div>
                  <div style="flex:1;min-width:130px"><label>Plafond annuel</label>
                    <input type="number" min="0" value=${f.plafond_annuel}
                      placeholder="par structure"
                      onInput=${e=>maj('plafond_annuel', e.target.value)} /></div>
                </div>
                <div style="margin-top:18px">
                  <button class="btn" onClick=${creer}>Ajouter au catalogue</button>
                </div>
              </div>
            </div>`}

          <div class="panneau">
            <div style="overflow-x:auto">
              <table>
                <thead><tr>
                  <th style="min-width:200px">Article</th>
                  <th>Catégorie</th>
                  <th style="text-align:right">Points</th>
                  <th style="text-align:right">Stock</th>
                  <th></th>
                </tr></thead>
                <tbody>
                  ${articles.map(a => html`
                    <tr key=${a.id}>
                      <td>
                        <div>${a.nom}</div>
                        <div class="mono muted small">${a.reference}</div>
                      </td>
                      <td class="small muted">
                        ${(cats.find(c => c.code === a.categorie) || {}).nom || a.categorie}</td>
                      <td style="text-align:right">
                        <input type="number" min="0" defaultValue=${a.cout_points}
                          style="width:80px;padding:5px 8px;font-size:13px;text-align:right"
                          onBlur=${e=>majArticle(a,'cout_points',e.target.value)} /></td>
                      <td style="text-align:right">
                        <input type="number" min="0"
                          defaultValue=${a.stock_national === null ? '' : a.stock_national}
                          placeholder="∞"
                          style="width:80px;padding:5px 8px;font-size:13px;text-align:right"
                          onBlur=${e=>majArticle(a,'stock_national',e.target.value)} /></td>
                      <td style="text-align:right">
                        <button class="btn sm light"
                          onClick=${()=>majArticle(a,'actif',!a.actif)}>
                          ${a.actif ? 'Retirer' : 'Remettre'}</button></td>
                    </tr>`)}
                </tbody>
              </table>
            </div>
          </div>
        </div>`}
    </div>`;
}


/* --- Les dotations en points ----------------------------------------- */
export function ResDotations({ regles, dotations, p, appel, setMsg }){
  const [simul, setSimul] = useState(null);
  const [exc, setExc] = useState(false);
  const [excs, setExcs] = useState([]);
  const [terr, setTerr] = useState([]);
  const [dirs, setDirs] = useState([]);
  const [cadres, setCadres] = useState([]);
  const [fe, setFe] = useState({ points:'', portee:'territoires', echelle:'departement',
                                 cibles:[], dirs:[], profils:[], motif:'', campagne:'' });
  const annee = new Date().getFullYear();

  const chargerExc = useCallback(async () => {
    const [a, b, c, d] = await Promise.all([
      db.rpc('dotations_exceptionnelles_recentes', { p_annee: annee }),
      db.from('territoires').select('id,nom,echelle')
        .in('echelle',['region','departement','local']).order('nom'),
      db.rpc('liste_directions'),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom,niveau')
        .eq('statut','actif').gte('niveau', 40).order('nom')
    ]);
    setExcs(a.data || []); setTerr(b.data || []);
    setDirs(c.data || []); setCadres(d.data || []);
  }, [annee]);
  useEffect(() => { chargerExc(); }, [chargerExc]);

  async function doter(e){
    e.preventDefault();
    const ok = await appel('doter_exceptionnellement', {
      p_points: Number(fe.points) || 0, p_motif: fe.motif, p_portee: fe.portee,
      p_territoires: fe.portee === 'territoires' ? fe.cibles : [],
      p_echelle: fe.portee === 'echelle' ? fe.echelle : null,
      p_campagne: fe.campagne || null, p_annee: annee,
      p_directions: fe.portee === 'directions' ? fe.dirs : [],
      p_profils: fe.portee === 'responsables' ? fe.profils : []
    }, 'Dotation exceptionnelle attribuée.');
    if (ok){ setFe({ points:'', portee:'territoires', echelle:'departement',
      cibles:[], dirs:[], profils:[], motif:'', campagne:'' });
      setExc(false); chargerExc(); }
  }

  async function simuler(){
    if (!p.territoire_id) return setMsg('Erreur : votre profil n\u2019a pas de territoire.');
    const { data, error } = await db.rpc('calculer_dotation',
      { p_territoire: p.territoire_id, p_annee: annee });
    if (error) return setMsg('Erreur : ' + error.message);
    setSimul(data);
  }

  async function attribuer(){
    const a = prompt('Année d\u2019attribution', String(annee));
    if (!a) return;
    appel('attribuer_dotations', { p_annee: Number(a) },
      'Dotations attribuées pour ' + a + '.');
  }

  const totalPts = dotations.reduce((s,d) =>
    s + Number(d.points_alloues||0) + Number(d.points_reportes||0)
      + Number(d.points_bonus||0), 0);

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px;flex-wrap:wrap;gap:10px">
        <p class="muted" style="max-width:56ch;margin:0">
          Les points sont une monnaie annuelle. Le barème et les règles de
          report se règlent ici, jamais dans le code. L\u2019attribution recalcule
          la dotation de chaque structure locale et départementale ; une
          dotation exceptionnelle s\u2019ajoute en cours d\u2019année, sans la modifier.
        </p>
        <div class="row" style="gap:8px">
          <button class="btn sm light" onClick=${simuler}>Simuler pour ma structure</button>
          <button class="btn sm light" onClick=${()=>setExc(!exc)}>
            ${exc ? 'Fermer' : 'Dotation exceptionnelle'}</button>
          <button class="btn sm" onClick=${attribuer}>Attribuer les dotations</button>
        </div>
      </div>

      ${exc && html`
        <form class="panneau" style="margin-bottom:24px" onSubmit=${doter}>
          <div class="tete"><h3 style="font-size:17px">Dotation exceptionnelle</h3></div>
          <div class="corps stack">
            <p class="small muted" style="margin:0">
              Elle ne modifie pas le calcul annuel : elle s\u2019y ajoute, se lit à
              part, et reste rattachée à son motif. Un même geste peut viser une
              structure, toutes celles d\u2019une échelle, ou le réseau entier.
            </p>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:0 0 120px;margin:0">
                <label>Points</label>
                <input type="number" value=${fe.points}
                  onInput=${e=>setFe(o=>({...o,points:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:170px;margin:0">
                <label>Portée</label>
                <select value=${fe.portee}
                  onChange=${e=>setFe(o=>({...o,portee:e.target.value}))}>
                  <option value="territoires">Des structures choisies</option>
                  <option value="echelle">Toutes celles d\u2019une échelle</option>
                  <option value="reseau">Tout le réseau</option>
                  <option value="directions">Des directions</option>
                  <option value="responsables">Des responsables</option>
                </select></div>
              ${fe.portee === 'echelle' && html`
                <div class="field" style="flex:1;min-width:150px;margin:0">
                  <label>Échelle</label>
                  <select value=${fe.echelle}
                    onChange=${e=>setFe(o=>({...o,echelle:e.target.value}))}>
                    <option value="region">Régions</option>
                    <option value="departement">Départements</option>
                    <option value="local">Structures locales</option>
                  </select></div>`}
            </div>
            ${fe.portee === 'directions' && html`
              <div class="field">
                <label>Directions dotées</label>
                <div class="row" style="gap:6px;flex-wrap:wrap">
                  ${dirs.map(d => html`
                    <button type="button" key=${d.code}
                      class=${'btn sm ' + (fe.dirs.includes(d.code) ? '' : 'light')}
                      onClick=${()=>setFe(o=>({...o, dirs: o.dirs.includes(d.code)
                        ? o.dirs.filter(x=>x!==d.code) : [...o.dirs, d.code]}))}>
                      ${d.nom_court || d.nom}</button>`)}
                </div>
                <div class="small muted">Une direction répartit ensuite son
                  enveloppe sur les projets qu\u2019elle retient.</div>
              </div>`}

            ${fe.portee === 'responsables' && html`
              <div class="field">
                <label>Responsables dotés</label>
                <div class="row" style="gap:6px;flex-wrap:wrap;max-height:150px;
                  overflow-y:auto;padding:4px 0">
                  ${cadres.map(g => html`
                    <button type="button" key=${g.id}
                      class=${'btn sm ' + (fe.profils.includes(g.id) ? '' : 'light')}
                      onClick=${()=>setFe(o=>({...o, profils: o.profils.includes(g.id)
                        ? o.profils.filter(x=>x!==g.id) : [...o.profils, g.id]}))}>
                      ${nomComplet(g)}</button>`)}
                </div>
                <div class="small muted">Une enveloppe personnelle sert à
                  répartir, jamais à consommer : son porteur l\u2019affecte à des
                  projets, il ne commande pas avec.</div>
              </div>`}

            ${fe.portee === 'territoires' && html`
              <div class="field">
                <label>Structures visées</label>
                <div class="row" style="gap:6px;flex-wrap:wrap;max-height:150px;
                  overflow-y:auto;padding:4px 0">
                  ${terr.map(t => html`
                    <button type="button" key=${t.id}
                      class=${'btn sm ' + (fe.cibles.includes(t.id) ? '' : 'light')}
                      onClick=${()=>setFe(o=>({...o, cibles: o.cibles.includes(t.id)
                        ? o.cibles.filter(x=>x!==t.id) : [...o.cibles, t.id]}))}>
                      ${t.nom}</button>`)}
                </div>
              </div>`}
            <div class="field"><label>Motif</label>
              <input value=${fe.motif} placeholder="Forum des associations, sinistre, réussite…"
                onInput=${e=>setFe(o=>({...o,motif:e.target.value}))} /></div>
            <div class="field" style="max-width:280px"><label>Campagne (facultatif)</label>
              <input value=${fe.campagne} placeholder="Rentrée 2026"
                onInput=${e=>setFe(o=>({...o,campagne:e.target.value}))} /></div>
            <div><button class="btn">Attribuer</button></div>
          </div>
        </form>`}

      ${excs.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete"><h3 style="font-size:17px">Dotations exceptionnelles de l\u2019année</h3>
            <span class="tag">${excs.length}</span></div>
          ${excs.slice(0,30).map(x => html`
            <div class="ligne" key=${x.id}>
              <div style="flex:1;min-width:220px">
                <div>${x.territoire}</div>
                <div class="small muted">${x.motif}${
                  x.campagne ? ' · ' + x.campagne : ''} · ${jour(x.cree_le)}
                  ${x.accorde_par ? ' · ' + x.accorde_par : ''}</div>
              </div>
              <span class="mono">${x.points > 0 ? '+' : ''}${x.points} pts</span>
            </div>`)}
        </div>`}

      ${simul && html`
        <div class="panneau" style="margin-bottom:24px">
          <div class="tete spread">
            <h3 style="font-size:17px">Simulation ${annee}</h3>
            <button class="btn sm light" onClick=${()=>setSimul(null)}>Fermer</button>
          </div>
          <div class="ligne"><span class="muted">Base par structure</span>
            <span class="mono">${simul.base} pts</span></div>
          <div class="ligne"><span class="muted">Effectif actif</span>
            <span class="mono">${simul.effectif} · ${simul.points_effectif} pts</span></div>
          <div class="ligne"><span class="muted">Missions de l\u2019an passé</span>
            <span class="mono">${simul.missions} · ${simul.points_missions} pts</span></div>
          <div class="ligne"><span class="muted">Reliquat reportable</span>
            <span class="mono">${simul.reliquat} → ${simul.report} pts</span></div>
          <div class="ligne"><span style="font-weight:600">Total</span>
            <span class="mono" style="font-size:17px">${simul.total} pts</span></div>
        </div>`}

      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Barème</h3></div>
        ${regles.map(r => html`
          <div class="ligne" key=${r.cle}>
            <div style="flex:1;min-width:220px">
              <div>${r.libelle}</div>
              <div class="mono muted small">${r.cle}</div>
            </div>
            <div class="row" style="gap:8px">
              <input type="number" step="0.01" defaultValue=${r.valeur}
                style="width:100px;padding:6px 9px;font-size:14px;text-align:right"
                onBlur=${e=>appel('regler_dotation',
                  { p_cle:r.cle, p_valeur:Number(e.target.value) },
                  'Barème mis à jour.')} />
              <span class="small muted" style="min-width:48px">${r.unite}</span>
            </div>
          </div>`)}
      </div>

      <div class="panneau">
        <div class="tete spread">
          <h3 style="font-size:17px">Dotations ${annee}</h3>
          <span class="mono small muted">${dotations.length} structure(s) ·
            ${totalPts} points</span>
        </div>
        ${dotations.length === 0
          ? html`<div class="corps muted">
              Aucune dotation attribuée pour ${annee}.</div>`
          : dotations.map(d => html`
            <div class="ligne" key=${d.id}>
              <div style="flex:1;min-width:200px">
                <div>${d.territoires?.nom || '—'}</div>
                <div class="small muted">Attribuée le ${jour(d.attribuee_le)}</div>
              </div>
              <span class="mono">${Number(d.points_alloues) + Number(d.points_reportes)
                + Number(d.points_bonus)} pts</span>
            </div>`)}
      </div>
    </div>`;
}

/* =====================================================================
   MES MANDATS
   Ce qu'on me demande à moi se répond ici, jamais depuis l'application
   concernée. Un intérim proposé à quelqu'un qui n'a pas Habilitations
   restait sans réponse possible : la file de travail renvoyait vers une
   porte fermée. Cet écran est ouvert à tout membre actif, sans droit.

   ===================================================================== */
export function SuiviNote({ id }){
  const [e, setE] = useState([]);
  useEffect(() => {
    db.rpc('suivi_note', { p_note: id }).then(({data}) => setE(data||[]));
  }, [id]);
  if (e.length === 0) return null;

  const couleur = { fait:'var(--vert)', en_cours:'var(--action)',
                    suspendu:'var(--laiton)', arrete:'var(--rouge)',
                    a_venir:'var(--filet)' };
  const mot = { fait:'Fait', en_cours:'En cours', suspendu:'En attente de vous',
                arrete:'Arrêté', a_venir:'' };

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete"><h3 style="font-size:17px">Où en est votre note</h3></div>
      <div class="corps">
        <div class="row" style="gap:0;margin-bottom:22px;align-items:center">
          ${e.map((x,i) => html`
            <div key=${x.rang} style="flex:1;display:flex;align-items:center">
              <div style=${'width:12px;height:12px;border-radius:50%;flex:0 0 12px;'
                + 'background:' + couleur[x.etat]}></div>
              ${i < e.length - 1 && html`<div style=${'flex:1;height:2px;background:'
                + (x.etat === 'fait' ? 'var(--vert)' : 'var(--filet)')}></div>`}
            </div>`)}
        </div>
        ${e.map(x => html`
          <div class="ligne" key=${x.rang} style="align-items:flex-start;padding-left:0;
            padding-right:0;border:0">
            <div style="flex:1;min-width:220px">
              <div class="row" style="gap:8px;flex-wrap:wrap">
                <span style=${x.etat === 'a_venir' ? 'color:var(--gris)' : 'font-weight:600'}>
                  ${x.etape}</span>
                ${mot[x.etat] && html`<span class=${'tag ' + (
                  x.etat==='fait' ? 'vert' : x.etat==='arrete' ? 'rouge'
                  : x.etat==='suspendu' ? 'or' : 'bleu')}>${mot[x.etat]}</span>`}
              </div>
              <div class="small muted" style="margin-top:3px">${x.detail}</div>
            </div>
            <div class="small muted" style="text-align:right;min-width:130px">
              ${x.quand ? jour(x.quand) : ''}${x.par ? html`<div>${x.par}</div>` : ''}
            </div>
          </div>`)}
      </div>
    </div>`;
}

/* --- Instruire ligne à ligne --------------------------------------------
   L'instructeur avait un doute sur une ligne et refusait la note
   entière. Il marque désormais chaque ligne, et peut renvoyer la note
   pour complément sans faire perdre ce qui était acquis.

   --------------------------------------------------------------------- */
export function InstruireLignes({ note, lignes, param, recharger, setMsg }){
  const [msgLocal, setMsgLocal] = useState('');

  const montantDe = l => l.categorie === 'kilometres'
    ? (Number(l.kilometres||0) * (param.taux_km||0))
    : Number(l.montant||0);

  async function marquer(l, etat){
    const obs = ['ecartee','a_preciser'].includes(etat)
      ? prompt(etat === 'ecartee'
          ? 'Pourquoi cette dépense est-elle écartée ?'
          : 'Que faut-il préciser ou corriger ?')
      : null;
    if (['ecartee','a_preciser'].includes(etat) && !obs) return;
    const { data, error } = await db.rpc('observer_ligne',
      { p_ligne: l.id, p_etat: etat, p_observation: obs });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    recharger();
  }

  async function renvoyer(){
    const m = prompt('Ce que vous attendez du déposant (obligatoire)');
    if (!m) return;
    const { data, error } = await db.rpc('demander_precisions',
      { p_note: note.id, p_message: m });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Note renvoyée pour complément. Ce qui est acquis le reste.');
    recharger();
  }

  const retenu = lignes.filter(l => l.etat !== 'ecartee')
                       .reduce((t,l) => t + montantDe(l), 0);
  const ecarte = lignes.filter(l => l.etat === 'ecartee')
                       .reduce((t,l) => t + montantDe(l), 0);
  const aPreciser = lignes.filter(l => l.etat === 'a_preciser').length;

  return html`
    <div class="panneau" style="margin-top:24px;border-color:var(--brun)">
      <div class="tete spread" style="border-bottom-color:var(--brun)">
        <h3 style="font-size:17px">Examen ligne à ligne</h3>
        <span class="mono">${EURO(retenu)} retenu${
          ecarte > 0 ? ' · ' + EURO(ecarte) + ' écarté' : ''}</span>
      </div>
      ${lignes.map(l => html`
        <div class="ligne" key=${l.id} style="align-items:flex-start">
          <div style="flex:1;min-width:240px">
            <div class="row" style="gap:8px;flex-wrap:wrap">
              <span style=${l.etat === 'ecartee' ? 'text-decoration:line-through' : ''}>
                ${l.description}</span>
              ${l.etat === 'ecartee' && html`<span class="tag rouge">Écartée</span>`}
              ${l.etat === 'a_preciser' && html`<span class="tag or">À préciser</span>`}
              ${l.etat === 'retenue' && html`<span class="tag vert">Retenue</span>`}
            </div>
            <div class="small muted" style="margin-top:3px">
              ${CATEGORIES[l.categorie]} · ${jour(l.date_depense)} · ${EURO(montantDe(l))}
            </div>
            ${l.observation && html`<div class="small" style="margin-top:4px;
              color:var(--laiton)">${l.observation}</div>`}
          </div>
          <div class="row" style="gap:6px">
            <button class="btn sm light" onClick=${()=>marquer(l,'retenue')}>Retenir</button>
            <button class="btn sm light" onClick=${()=>marquer(l,'a_preciser')}>Préciser</button>
            <button class="btn sm light" onClick=${()=>marquer(l,'ecartee')}>Écarter</button>
          </div>
        </div>`)}
      <div class="corps">
        <p class="small muted" style="margin:0 0 14px">
          Écarter, c\u2019est retirer la dépense du montant remboursé. Demander une
          précision, c\u2019est rendre la note à son auteur sans lui faire tout
          recommencer : ce qui est retenu le reste.
        </p>
        <button class="btn light" disabled=${aPreciser === 0} onClick=${renvoyer}>
          Renvoyer pour complément${aPreciser ? ' (' + aPreciser + ' ligne(s))' : ''}
        </button>
      </div>
    </div>`;
}

/* =====================================================================
   LE BILAN DE L'ANNÉE
   « Mon engagement » listait sans totaliser. Il dit maintenant ce que
   l'année cumule, d'où viennent les heures — déclarées ou attestées par
   un bilan de mission — et ce qui sépare de l'échelon suivant.

   Rien n'est stocké : la chancellerie calcule déjà tout cela pour ses
   promotions. On ne recalcule pas, on cite.

   ===================================================================== */
export function InvestissementsAOrdonnancer({ setMsg }){
  const [l, setL] = useState([]);
  const charger = useCallback(() =>
    db.rpc('investissements_a_traiter', { p_filtre: 'a_ordonnancer' })
      .then(({data}) => setL(data || [])), []);
  useEffect(() => { charger(); }, [charger]);

  async function decider(i, ok){
    const m = ok ? null : prompt('Motif du refus (obligatoire)');
    if (!ok && !m) return;
    const { data, error } = await db.rpc('ordonnancer_investissement',
      { p_id: i.id, p_ok: ok, p_motif: m });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(ok ? 'Investissement ordonnancé.' : 'Investissement refusé.');
    charger();
  }

  if (l.length === 0) return null;
  return html`
    <div class="panneau" style="margin-bottom:24px;border-color:var(--brun)">
      <div class="tete spread" style="border-bottom-color:var(--brun)">
        <h3 style="font-size:17px">Investissements à ordonnancer</h3>
        <span class="mono">${EURO(l.reduce((t,i) => t + Number(i.montant||0), 0))}</span>
      </div>
      ${l.map(i => html`
        <div class="ligne" key=${i.id} style="align-items:flex-start">
          <div style="flex:1;min-width:260px">
            <div class="row" style="gap:8px;flex-wrap:wrap">
              <span style="font-weight:600">${i.intitule}</span>
              <span class="mono muted small">${i.reference}</span>
            </div>
            <div class="small muted" style="margin-top:3px">
              ${i.demandeur}${i.territoire ? ' · ' + i.territoire : ''}
              ${i.fournisseur ? ' · ' + i.fournisseur : ''}
              ${i.poste_budget ? ' · imputation ' + i.poste_budget : ''}
            </div>
            <div class="small" style="margin-top:6px">${i.justification}</div>
            ${i.avis_logistique && html`<div class="small muted" style="margin-top:3px">
              Avis : ${i.avis_logistique}</div>`}
          </div>
          <div class="row" style="gap:10px;align-items:flex-start">
            <span class="mono" style="font-size:15px">${EURO(i.montant)}</span>
            <button class="btn sm" onClick=${()=>decider(i, true)}>Ordonnancer</button>
            <button class="btn sm light" onClick=${()=>decider(i, false)}>Refuser</button>
          </div>
        </div>`)}
      <div class="corps small muted">
        Un investissement ordonnancé entre au budget de l\u2019exercice en cours,
        au poste 215, sans ressaisie.
      </div>
    </div>`;
}

/* =====================================================================
   LA GESTION LOCALE
   Voir avant de décider. Quatre volets : la fiche du territoire, les
   accès du périmètre, les actes locaux, et — pour qui pilote le réseau
   — le plan d'ensemble.

   Ce que le national délègue est une donnée, pas une règle codée :
   l'écran affiche la liste et dit, pour chaque application, pourquoi
   elle est ouvrable ou non.

   ===================================================================== */
export function MesEnveloppes({ setMsg }){
  const [env, setEnv] = useState([]);
  const [projets, setProjets] = useState([]);
  const [source, setSource] = useState(null);
  const [choisi, setChoisi] = useState(null);
  const [f, setF] = useState({ points:'', motif:'' });
  const [soutiens, setSoutiens] = useState({});

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('mes_enveloppes', { p_annee: null }),
      db.rpc('projets_a_soutenir', { p_filtre: 'tous' })
    ]);
    setEnv(a.data || []); setProjets(b.data || []);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function voirSoutiens(p){
    if (soutiens[p.id]) return setSoutiens(s => { const c={...s}; delete c[p.id]; return c; });
    const { data } = await db.rpc('soutiens_projet', { p_projet: p.id });
    setSoutiens(s => ({ ...s, [p.id]: data || [] }));
  }

  async function affecter(e){
    e.preventDefault();
    if (!source) return setMsg('Erreur : choisissez d\u2019abord une enveloppe.');
    const { data, error } = await db.rpc('affecter_points_projet', {
      p_nature: source.nature, p_ref: source.ref, p_projet: choisi.id,
      p_points: Number(f.points) || 0, p_motif: f.motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(data.points + ' points affectés. Il vous en reste ' + data.restant + '.');
    setF({ points:'', motif:'' }); setChoisi(null); charger();
  }

  if (env.length === 0) return null;

  return html`
    <div style="margin-bottom:28px">
      <h3 style="font-size:17px;margin-bottom:12px">Mes enveloppes</h3>
      <div class="panneau" style="margin-bottom:20px">
        <div class="corps small muted" style="padding-bottom:0">
          Une enveloppe se répartit, elle ne se dépense pas. Vous l\u2019affectez
          aux projets que vous retenez ; les points arrivent alors à la
          structure qui les porte, et servent à commander au catalogue.
        </div>
        ${env.map(x => html`
          <div class="ligne" key=${x.nature + x.ref} style="align-items:flex-start">
            <div style="flex:1;min-width:200px">
              <div style="font-weight:600">${x.libelle}</div>
              <div class="small muted" style="margin-top:3px">
                ${x.recu} reçus · ${x.redistribue} redistribués
              </div>
            </div>
            <div class="row" style="gap:10px;align-items:center">
              <span class="mono" style="font-size:16px">${x.disponible} pts</span>
              <button class=${'btn sm ' + (source && source.ref === x.ref ? '' : 'light')}
                disabled=${x.disponible <= 0}
                onClick=${()=>setSource(source && source.ref === x.ref ? null : x)}>
                ${source && source.ref === x.ref ? 'Sélectionnée' : 'Répartir'}</button>
            </div>
          </div>`)}
      </div>

      ${source && html`
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">
            Projets à soutenir — ${source.libelle}</h3>
            <span class="mono">${source.disponible} pts disponibles</span></div>
          ${projets.length === 0
            ? html`<div class="corps muted">
                Aucun projet en préparation ou en cours dans votre ressort.</div>`
            : projets.map(p => html`
              <div key=${p.id}>
                <div class="ligne" style="align-items:flex-start">
                  <div style="flex:1;min-width:250px">
                    <div class="row" style="gap:8px;flex-wrap:wrap">
                      <span style="font-weight:600">${p.titre}</span>
                      <span class="mono muted small">${p.reference}</span>
                      ${p.points_recus > 0 && html`
                        <span class="tag vert">${p.points_recus} pts reçus</span>`}
                    </div>
                    <div class="small muted" style="margin-top:3px">
                      ${p.territoire}${p.responsable ? ' · ' + p.responsable : ''}
                      ${p.debut ? ' · à partir du ' + jour(p.debut) : ''}
                      ${p.budget_estime ? ' · budget ' + EURO(p.budget_estime) : ''}
                    </div>
                    ${p.objet && html`<div class="small" style="margin-top:5px">${p.objet}</div>`}
                  </div>
                  <div class="row" style="gap:6px">
                    ${p.points_recus > 0 && html`
                      <button class="btn sm light" onClick=${()=>voirSoutiens(p)}>
                        ${soutiens[p.id] ? 'Masquer' : 'D\u2019où viennent les points'}</button>`}
                    <button class="btn sm"
                      onClick=${()=>setChoisi(choisi && choisi.id === p.id ? null : p)}>
                      ${choisi && choisi.id === p.id ? 'Fermer' : 'Affecter'}</button>
                  </div>
                </div>

                ${soutiens[p.id] && html`
                  <div class="corps" style="background:var(--papier);
                    border-bottom:1px solid var(--filet)">
                    ${soutiens[p.id].length === 0
                      ? html`<div class="small muted">Aucun soutien enregistré.</div>`
                      : soutiens[p.id].map((s,i) => html`
                        <div class="small" key=${i} style="margin-bottom:6px">
                          <strong>${-s.points} pts</strong> — ${s.origine}
                          <span class="muted"> · ${jour(s.cree_le)}</span>
                          <div class="muted">${s.motif}</div>
                        </div>`)}
                  </div>`}

                ${choisi && choisi.id === p.id && html`
                  <form class="corps stack" onSubmit=${affecter}
                    style="background:var(--papier);border-bottom:1px solid var(--filet)">
                    <div class="row" style="gap:16px;align-items:flex-start">
                      <div class="field" style="flex:0 0 130px;margin:0">
                        <label>Points affectés</label>
                        <input type="number" min="1" max=${source.disponible}
                          value=${f.points}
                          onInput=${e=>setF(o=>({...o,points:e.target.value}))} /></div>
                      <div class="field" style="flex:1;min-width:220px;margin:0">
                        <label>Pourquoi ce projet</label>
                        <input value=${f.motif}
                          placeholder="Ce qui justifie l\u2019affectation"
                          onInput=${e=>setF(o=>({...o,motif:e.target.value}))} /></div>
                    </div>
                    <div><button class="btn sm">Affecter à ${p.titre}</button></div>
                  </form>`}
              </div>`)}
        </div>`}
    </div>`;
}

/* =====================================================================
   LE FIL D'ACTUALITÉ
   Ce qu'on attend de la personne passe avant ce qui s'est passé. Un fil
   qui commencerait par des nouvelles laisserait les demandes en attente
   sous la ligne de flottaison.
