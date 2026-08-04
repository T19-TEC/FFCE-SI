import { Groupes } from './collectif.js';
import { Habilitations, Postes, Publier } from './direction.js';
import { Assistance } from './espace.js';
import { Distinctions, Formations } from './formation.js';
import { ETAPES, ETAPE_NOM, EURO, Info, MERITES, MESURES, Portrait, SECTIONS_DOSSIER, db, h, html, jour, nomComplet, nomMois, useCallback, useEffect, useState } from './socle.js';
import { Rejoindre } from './vitrine.js';


/* --- Mon portrait ------------------------------------------------------
   Deux mégaoctets, dépôt privé, dossier nommé par l'identifiant : nul
   ne peut déposer chez un autre.
   --------------------------------------------------------------------- */
export function MonPortrait({ p, recharger }){
  const [msg, setMsg] = useState('');
  const [envoi, setEnvoi] = useState(false);

  async function deposer(e){
    const fichier = e.target.files[0];
    if (!fichier) return;
    setEnvoi(true); setMsg('');
    try {
      if (fichier.size > 2 * 1024 * 1024)
        throw new Error('Le portrait ne doit pas dépasser 2 Mo.');
      const ext = fichier.name.split('.').pop();
      const chemin = p.id + '/portrait-' + Date.now() + '.' + ext;
      const { error: eUp } = await db.storage.from('portraits').upload(chemin, fichier);
      if (eUp) throw eUp;
      const { error } = await db.from('profils').update({ photo_url: chemin }).eq('id', p.id);
      if (error) throw error;
      setMsg('Portrait mis à jour.');
      recharger();
    } catch (err){ setMsg(err.message || 'Dépôt impossible.'); }
    setEnvoi(false);
  }

  async function retirer(){
    await db.from('profils').update({ photo_url: null }).eq('id', p.id);
    setMsg('Portrait retiré.'); recharger();
  }

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="corps row" style="gap:20px">
        <${Portrait} chemin=${p.photo_url} nom=${nomComplet(p)} taille=${88} />
        <div style="flex:1;min-width:220px">
          <div style="font-family:var(--titre);font-weight:700;font-size:16px;
                      color:var(--bleu)">${nomComplet(p)}</div>
          <div class="small muted">${p.fonction_nom} · ${p.territoire_nom || 'sans rattachement'}</div>
          ${p.devise && html`<div class="small" style="margin-top:6px;font-style:italic">
            « ${p.devise} »</div>`}
          <div class="row" style="margin-top:12px;gap:10px">
            <label class="btn sm light" style="margin:0;text-transform:none;
                letter-spacing:.02em;cursor:pointer;display:inline-block">
              ${envoi ? 'Envoi…' : (p.photo_url ? 'Changer' : 'Ajouter un portrait')}
              <input type="file" accept="image/*" style="display:none" onChange=${deposer} />
            </label>
            ${p.photo_url && html`<button class="btn sm light" onClick=${retirer}>Retirer</button>`}
          </div>
          ${msg && html`<p class="small" style="margin:10px 0 0;color:var(--gris)">${msg}</p>`}
        </div>
      </div>
    </div>`;
}


export function MonCompte({ p, recharger }){
  const [f, setF] = useState({
    prenom:p.prenom, nom:p.nom, telephone:p.telephone||'',
    pronoms:p.pronoms||'', langues:p.langues||'', devise:p.devise||'',
    bio:p.bio||'', visible_public:!!p.visible_public
  });
  const [msg, setMsg] = useState('');
  const maj = (k,v) => setF(o => ({...o,[k]:v}));

  async function enregistrer(e){
    e.preventDefault(); setMsg('');
    const { error } = await db.from('profils').update(f).eq('id', p.id);
    setMsg(error ? 'Enregistrement impossible : ' + error.message : 'Modifications enregistrées.');
    if (!error) recharger();
  }

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Mon compte</div>
          <h1 style="margin:6px 0 0">Mes informations</h1>
        </div>
        <div class="row">
          <a class="btn light" href="#/espace/demandes">Mes demandes</a>
          <a class="btn light" href="#/espace/referentiel">Comprendre mes droits</a>
        </div>
      </div>

      <${MonPortrait} p=${p} recharger=${recharger} />
      <div style="height:24px"></div>

      <${DossierAdhesion} p=${p} recharger=${recharger} />
      <div style="height:24px"></div>

      <form onSubmit=${enregistrer} class="panneau">
        <div class="corps stack">
          <div class="row" style="gap:16px">
            <div class="field" style="flex:1;min-width:160px">
              <label>Prénom</label>
              <input value=${f.prenom} onInput=${e=>maj('prenom',e.target.value)} />
            </div>
            <div class="field" style="flex:1;min-width:160px;margin-top:0">
              <label>Nom</label>
              <input value=${f.nom} onInput=${e=>maj('nom',e.target.value)} />
            </div>
          </div>
          <div class="field">
            <label>Téléphone</label>
            <input value=${f.telephone} onInput=${e=>maj('telephone',e.target.value)} />
          </div>
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:150px;margin:0">
              <label>Pronoms</label>
              <input value=${f.pronoms} placeholder="elle, il, iel…"
                onInput=${e=>maj('pronoms',e.target.value)} />
            </div>
            <div class="field" style="flex:1;min-width:150px;margin:0">
              <label>Langues parlées</label>
              <input value=${f.langues} placeholder="français, arabe, LSF…"
                onInput=${e=>maj('langues',e.target.value)} />
            </div>
          </div>
          <div class="field">
            <label>Une phrase qui vous ressemble</label>
            <input value=${f.devise} maxlength="120"
              onInput=${e=>maj('devise',e.target.value)}
              placeholder="Elle apparaîtra en tête de votre fiche." />
          </div>
          <div class="field">
            <label>Présentation</label>
            <textarea value=${f.bio} onInput=${e=>maj('bio',e.target.value)}
              placeholder="Quelques lignes sur votre engagement."></textarea>
          </div>
          <label class="row" style="text-transform:none;letter-spacing:0;font-size:14px;color:var(--encre)">
            <input type="checkbox" style="width:auto" checked=${f.visible_public}
              onChange=${e=>maj('visible_public',e.target.checked)} />
            <span>Afficher mon nom et ma présentation sur la page publique « Le réseau »</span>
          </label>
          ${msg && html`<div class=${'alerte '+(msg.startsWith('Modif')?'ok':'err')}>${msg}</div>`}
          <div><button class="btn">Enregistrer</button></div>
        </div>
      </form>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Fonction et rattachement</h3></div>
        <div class="ligne"><span class="muted">Matricule</span><span class="mono">${p.matricule}</span></div>
        <div class="ligne"><span class="muted">Fonction</span><span>${p.fonction_nom}</span></div>
        <div class="ligne"><span class="muted">Échelon</span>
          <span class="tag or">${p.echelon} · ${p.echelon_nom}</span></div>
        <div class="ligne"><span class="muted">Territoire</span><span>${p.territoire_nom||'—'}</span></div>
        <div class="ligne"><span class="muted">Membre depuis</span><span>${jour(p.cree_le)}</span></div>
        ${p.postes && p.postes.length > 0 && html`
          <div class="ligne">
            <span class="muted">Postes occupés</span>
            <div class="row" style="gap:6px;justify-content:flex-end">
              ${p.postes.map(x => html`<span class=${'tag '+(x.couleur==='neutre'?'':x.couleur)}>
                ${x.nom}${x.fin ? ' · jusqu\u2019au '+jour(x.fin) : ''}</span>`)}
            </div>
          </div>`}
        <div class="corps small muted" style="border-top:1px solid var(--filet)">
          Ces éléments sont fixés par la Direction générale. Pour une évolution
          de fonction ou d'échelon, déposez une demande.
        </div>
      </div>

      <${MonRib} />

      <${MaChaine} />

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <div class="row" style="gap:8px">
            <h3 style="font-size:17px">Mon passeport d\u2019engagement</h3>
            <${Info} texte="Le relevé de tout ce que vous avez donné : heures, missions, compétences exercées, certifications. Imprimable, il vaut pour un CV ou une validation des acquis." />
          </div>
          <a class="btn sm light" href="#/espace/passeport">Consulter</a>
        </div>
      </div>

      <${QuiMaConsulte} />

      <${Assistance} p=${p} />
    </div>`;
}


/* --- Qui a consulté mon dossier ---------------------------------------
   Droit RGPD, exercé en un clic plutôt que par courrier.
   --------------------------------------------------------------------- */
export function QuiMaConsulte(){
  const [v, setV] = useState(null);
  const [ouvert, setOuvert] = useState(false);
  useEffect(() => { db.rpc('qui_ma_consulte').then(({data}) => setV(data||[])); }, []);
  if (!v) return null;
  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Consultations de mon dossier</h3>
          <${Info} texte="Chaque fois que quelqu'un affiche vos coordonnées, la consultation est enregistrée. Vous avez le droit de savoir qui, et quand." />
        </div>
        <div class="row">
          <span class="tag">${v.length}</span>
          ${v.length > 0 && html`<button class="btn sm light"
            onClick=${()=>setOuvert(o=>!o)}>${ouvert?'Masquer':'Voir'}</button>`}
        </div>
      </div>
      ${v.length === 0
        ? html`<div class="corps small muted">Personne n\u2019a consulté vos coordonnées.</div>`
        : ouvert && html`<div>
            ${v.map(x => html`
              <div class="ligne">
                <div><div>${x.observateur}</div>
                  <div class="small muted">${x.fonction}${x.contexte ? ' · '+x.contexte : ''}</div></div>
                <span class="small muted">${new Date(x.cree_le).toLocaleString('fr-FR',
                  {day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})}</span>
              </div>`)}
          </div>`}
    </div>`;
}


export function MesDemandes({ p, apps, demandes, recharger }){
  const [type, setType] = useState('acces_application');
  const [cible, setCible] = useState('');
  const [objet, setObjet] = useState('');
  const [message, setMessage] = useState('');
  const [msg, setMsg] = useState('');

  const fermees = apps.filter(a => !a.ouvert && a.actif);

  async function envoyer(e){
    e.preventDefault(); setMsg('');
    const app = apps.find(a => a.code === cible);
    const { error } = await db.from('demandes').insert({
      profil_id: p.id, type,
      objet: objet || (app ? 'Accès à « '+app.nom+' »' : 'Demande'),
      cible: cible || null, message
    });
    if (error) return setMsg('Envoi impossible : ' + error.message);
    setObjet(''); setMessage(''); setCible(''); setMsg('Demande transmise à la Direction générale.');
    recharger();
  }

  const etiquette = s => ({
    ouverte:  html`<span class="tag bleu">En attente</span>`,
    en_cours: html`<span class="tag bleu">En cours</span>`,
    acceptee: html`<span class="tag vert">Accordée</span>`,
    refusee:  html`<span class="tag rouge">Refusée</span>`
  })[s];

  return html`
    <div>
      <div class="eyebrow">Mes demandes</div>
      <h1 style="margin:6px 0 32px">Guichet</h1>

      <form onSubmit=${envoyer} class="panneau">
        <div class="tete"><h3 style="font-size:17px">Déposer une demande</h3></div>
        <div class="corps stack">
          <div class="field">
            <label>Nature</label>
            <select value=${type} onChange=${e=>{setType(e.target.value);setCible('')}}>
              <option value="acces_application">Accès à une application</option>
              <option value="extension_compte">Extension de compte (webmail, Workspace)</option>
              <option value="promotion">Évolution de fonction ou d'échelon</option>
              <option value="autre">Autre</option>
            </select>
          </div>
          ${type === 'acces_application' && html`
            <div class="field">
              <label>Application</label>
              <select required value=${cible} onChange=${e=>setCible(e.target.value)}>
                <option value="">Choisir…</option>
                ${fermees.map(a => html`<option value=${a.code}>${a.nom}</option>`)}
              </select>
            </div>`}
          ${type !== 'acces_application' && html`
            <div class="field">
              <label>Objet</label>
              <input required value=${objet} onInput=${e=>setObjet(e.target.value)}
                placeholder="En une ligne" />
            </div>`}
          <div class="field">
            <label>Motif</label>
            <textarea required value=${message} onInput=${e=>setMessage(e.target.value)}
              placeholder="À quoi cet accès va-t-il servir ?"></textarea>
          </div>
          ${msg && html`<div class=${'alerte '+(msg.startsWith('Demande')?'ok':'err')}>${msg}</div>`}
          <div><button class="btn">Transmettre</button></div>
        </div>
      </form>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Suivi</h3></div>
        ${demandes.length === 0
          ? html`<div class="vide">Aucune demande déposée à ce jour.</div>`
          : demandes.map(d => html`
            <div class="ligne">
              <div>
                <div>${d.objet}</div>
                <div class="small muted">Déposée le ${jour(d.cree_le)}
                  ${d.motif_reponse ? ' · ' + d.motif_reponse : ''}</div>
              </div>
              ${etiquette(d.statut)}
            </div>`)}
      </div>
    </div>`;
}


export function Annuaire({ p }){
  const [membres, setMembres] = useState(null);
  const [q, setQ] = useState('');
  const [fiche, setFiche] = useState(null);
  useEffect(() => {
    db.rpc('mon_perimetre').then(({data}) => {
      const m = (data || []).filter(x => x.statut !== 'archive');
      m.sort((a,b) => (b.niveau - a.niveau) || String(a.nom||'').localeCompare(String(b.nom||'')));
      setMembres(m);
    });
  }, []);

  if (fiche) return html`<${FicheMembre} id=${fiche} fermer=${()=>setFiche(null)} />`;
  if (!membres) return html`<div class="vide">Chargement…</div>`;
  const filtre = membres.filter(m => {
    const s = (nomComplet(m)+' '+(m.territoire_nom||'')+' '+m.fonction_nom).toLowerCase();
    return s.includes(q.toLowerCase());
  });
  const masqueActif = membres.length > 0 && membres.every(m => !m.nom && !m.prenom);

  return html`
    <div>
      <div class="eyebrow">Annuaire fédéral</div>
      <h1 style="margin:6px 0 8px">Mon périmètre</h1>
      <p class="muted" style="max-width:58ch">
        Vous voyez les membres rattachés à votre territoire et à tous ceux qui
        en dépendent. Cette limite est appliquée par la base de données.
        ${masqueActif
          ? "Les noms sont masqués pour votre catégorie de poste : seul l\u2019effectif est visible ici."
          : "Ouvrez une fiche pour en savoir plus : les coordonnées ne s\u2019affichent que sur demande, et cette demande est enregistrée."}
      </p>

      <div class="field" style="max-width:360px;margin:24px 0">
        <input placeholder="Rechercher un nom, un territoire…"
          value=${q} onInput=${e=>setQ(e.target.value)} />
      </div>

      <div class="panneau">
        <div class="tete">
          <span class="small muted">${filtre.length} membre${filtre.length>1?'s':''}</span>
        </div>
        <div style="overflow-x:auto">
          <table>
            <thead><tr>
              <th>Membre</th><th>Fonction</th><th>Territoire</th><th>Échelon</th><th>Statut</th>
            </tr></thead>
            <tbody>
              ${filtre.map(m => { const masque = !m.nom && !m.prenom; return html`
                <tr style=${masque ? '' : 'cursor:pointer'}
                    onClick=${masque ? undefined : ()=>setFiche(m.id)}>
                  <td>
                    ${masque
                      ? html`<span class="muted">Non affiché</span>`
                      : html`<div><a href="#" onClick=${e=>e.preventDefault()}>${nomComplet(m)}</a></div>
                             <div class="mono muted">${m.matricule}</div>`}
                  </td>
                  <td>${m.fonction_nom}</td>
                  <td>${m.territoire_nom || '—'}</td>
                  <td><span class="tag or">${m.echelon}</span></td>
                  <td>${m.statut === 'actif'
                    ? html`<span class="tag vert">Actif</span>`
                    : html`<span class="tag">${m.statut.replace('_',' ')}</span>`}</td>
                </tr>`; })}
            </tbody>
          </table>
        </div>
        ${filtre.length === 0 && html`<div class="vide">Aucun résultat.</div>`}
      </div>
    </div>`;
}

export function MonRib(){
  const [r, setR] = useState(null);
  const [f, setF] = useState({titulaire:'', iban:'', bic:''});
  const [ouvert, setOuvert] = useState(false);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const { data } = await db.rpc('mon_rib');
    setR(data);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('enregistrer_rib',
      { p_titulaire: f.titulaire, p_iban: f.iban, p_bic: f.bic || null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titulaire:'', iban:'', bic:''}); setOuvert(false);
    setMsg('Coordonnées enregistrées.'); charger();
  }

  if (!r) return null;
  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <h3 style="font-size:17px">Coordonnées bancaires</h3>
        <button class="btn sm light" onClick=${()=>setOuvert(o=>!o)}>
          ${ouvert ? 'Annuler' : (r.enregistre ? 'Modifier' : 'Enregistrer')}</button>
      </div>
      ${msg && html`<div class="corps"><div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}>
        ${msg}</div></div>`}
      ${r.enregistre && !ouvert && html`
        <div>
          <div class="ligne"><span class="muted">Titulaire</span><span>${r.titulaire}</span></div>
          <div class="ligne"><span class="muted">IBAN</span>
            <span class="mono">${r.iban_masque}</span></div>
          <div class="ligne"><span class="muted">Consultations par la trésorerie</span>
            <span class="mono">${r.consultations}</span></div>
        </div>`}
      ${!r.enregistre && !ouvert && html`
        <div class="corps small muted">
          Aucune coordonnée enregistrée. Elles sont nécessaires pour un
          remboursement par virement.
        </div>`}
      ${ouvert && html`
        <form onSubmit=${enregistrer} class="corps stack">
          <div class="field"><label>Titulaire du compte</label>
            <input required value=${f.titulaire}
              onInput=${e=>setF(o=>({...o,titulaire:e.target.value}))} /></div>
          <div class="field"><label>IBAN</label>
            <input required value=${f.iban} placeholder="FR76 ...."
              onInput=${e=>setF(o=>({...o,iban:e.target.value}))} /></div>
          <div class="field"><label>BIC (facultatif)</label>
            <input value=${f.bic} onInput=${e=>setF(o=>({...o,bic:e.target.value}))} /></div>
          <div><button class="btn">Enregistrer</button></div>
          <p class="small muted">
            Vos coordonnées sont conservées à part et ne sont lisibles que par la
            direction financière, au moment du paiement. Chaque consultation est
            enregistrée et vous pouvez la voir ici.
          </p>
        </form>`}
    </div>`;
}

export function FilDossier({ d, compact }){
  const i = ETAPES.indexOf(d.statut);
  return html`
    <div>
      <div class="row" style="gap:0;margin-bottom:16px;flex-wrap:nowrap;overflow-x:auto">
        ${ETAPES.map((e, n) => html`
          <div style=${'flex:1;min-width:82px;padding-right:8px;'+
            (n <= i ? '' : 'opacity:.35')}>
            <div style=${'height:3px;background:'+(n <= i ? 'var(--encre)' : 'var(--filet)')}></div>
            <div class="small" style="margin-top:6px;line-height:1.3">${ETAPE_NOM[e]}</div>
          </div>`)}
      </div>
      ${!compact && d.qualification && html`
        <p class="small muted">Qualification retenue : ${d.qualification}</p>`}
    </div>`;
}

/* --- Ce que voit un membre : bandeau, ou page entière si suspendu ----- */

export function MonDossier({ p, entier }){
  const [d, setD] = useState(null);
  const [msg, setMsg] = useState('');
  const [obs, setObs] = useState({});
  const [rec, setRec] = useState({});
  const [doc, setDoc] = useState({});
  const [renonce, setRenonce] = useState({});

  const charger = useCallback(async () => {
    const { data } = await db.rpc('mon_dossier');
    setD(data || null);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  if (!d) return null;
  const dossiers = d.dossiers || [];
  const ouverts = dossiers.filter(x => x.statut !== 'clos');
  if (!entier && ouverts.length === 0 && !d.sous_suivi) return null;

  async function accuser(m){
    const { data } = await db.rpc('accuser_reception', { p_mesure: m.id });
    if (!data.ok) return setMsg(data.message);
    setMsg('Réception accusée. Le délai de recours court à compter de ce jour.');
    charger();
  }

  async function deposerObs(dos, e){
    e.preventDefault();
    const texte = obs[dos.id] || '';
    const fichier = doc[dos.id];
    if (!texte.trim() && !fichier) return;
    let chemin = null;
    try {
      if (fichier){
        if (fichier.size > 10 * 1024 * 1024)
          throw new Error('Le document ne doit pas dépasser 10 Mo.');
        const ext = fichier.name.split('.').pop();
        chemin = p.id + '/' + dos.id + '-' + Date.now() + '.' + ext;
        const { error: eUp } = await db.storage.from('dossiers').upload(chemin, fichier);
        if (eUp) throw eUp;
      }
    } catch (err){ return setMsg(err.message || 'Téléversement impossible.'); }

    const { data, error } = await db.rpc('verser_piece', {
      p_dossier: dos.id, p_type: fichier ? 'piece_jointe' : 'observation',
      p_titre: fichier ? fichier.name : 'Observations',
      p_contenu: texte || null, p_fichier: chemin, p_communicable: true
    });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setObs(o => ({...o, [dos.id]: ''}));
    setDoc(o => ({...o, [dos.id]: null}));
    setMsg('Vos observations sont versées au dossier.');
    charger();
  }

  async function renoncer(dos, e){
    e.preventDefault();
    const texte = renonce[dos.id] || '';
    if (!texte.trim()) return;
    if (!confirm('Cette renonciation est définitive. Confirmez-vous ?')) return;
    const { data, error } = await db.rpc('renoncer_gracieux',
      { p_dossier: dos.id, p_texte: texte });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setRenonce(o => { const c = {...o}; delete c[dos.id]; return c; });
    setMsg('Renonciation enregistrée et versée au dossier.');
    charger();
  }

  async function ouvrirPiece(pc){
    if (!pc.fichier) return;
    const { data, error } = await db.storage.from('dossiers')
      .createSignedUrl(pc.fichier, 120);
    if (error) return setMsg('Document introuvable.');
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  async function deposerRecours(m, e){
    e.preventDefault();
    const texte = rec[m.id] || '';
    if (!texte.trim()) return;
    const { data, error } = await db.rpc('deposer_recours',
      { p_mesure: m.id, p_contenu: texte, p_fichier: null });
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setRec(o => ({...o, [m.id]: ''}));
    setMsg('Recours déposé. Il sera examiné et la décision vous sera notifiée.');
    charger();
  }

  const bloc = (dos) => html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete">
        <div>
          <h3 style="font-size:17px">${dos.objet}</h3>
          <div class="small muted"><span class="mono">${dos.reference}</span>
            · ouvert le ${jour(dos.ouvert_le)}</div>
        </div>
        <span class="tag">${ETAPE_NOM[dos.statut]}</span>
      </div>
      <div class="corps">
        <${FilDossier} d=${dos} />

        ${dos.conclusion && html`
          <div class="alerte" style="margin-top:16px">Conclusion : ${dos.conclusion}</div>`}

        ${(dos.mesures||[]).map(m => html`
          <div style="margin-top:24px;padding:16px;border:1px solid var(--filet);
               border-left:3px solid var(--encre);border-radius:2px">
            <div class="spread">
              <strong>${MESURES[m.type] || m.type}</strong>
              <span class=${'tag '+(m.statut==='annulee'?'vert':m.statut==='executee'?'rouge':'')}>
                ${m.statut}</span>
            </div>
            <p style="margin:8px 0 0">${m.motif}</p>
            ${m.texte && html`<p class="small" style="margin:8px 0 0;white-space:pre-wrap">${m.texte}</p>`}
            <div class="small muted" style="margin-top:8px">
              Effet au ${jour(m.date_effet)}${m.date_fin ? ' · jusqu\u2019au ' + jour(m.date_fin) : ''}
              ${m.notifiee_le ? ' · notifiée le ' + jour(m.notifiee_le) : ''}
            </div>

            ${!m.accusee_le && m.notifiee_le && html`
              <div style="margin-top:12px">
                <button class="btn sm" onClick=${()=>accuser(m)}>
                  J\u2019accuse réception de cette décision</button>
                <p class="small muted" style="margin:6px 0 0">
                  Le délai de recours de ${30} jours court à compter de votre accusé de
                  réception, ou à défaut quinze jours après la notification.</p>
              </div>`}

            ${m.recours_ouvert && m.limite_recours && html`
              <p class="small muted" style="margin-top:8px">
                Recours possible jusqu\u2019au ${jour(m.limite_recours)}
                — ${m.recours_restants} recours restant${m.recours_restants>1?'s':''}.</p>`}
            ${!m.recours_ouvert && m.motif_fermeture && html`
              <p class="small muted" style="margin-top:8px">${m.motif_fermeture}</p>`}
            ${m.renonce_le && html`
              <div style="margin-top:12px;padding:12px;background:var(--papier);
                   border:1px solid var(--filet);border-radius:2px">
                <div class="small muted">Renonciation du ${jour(m.renonce_le)}</div>
                <p class="small" style="margin:6px 0 0;white-space:pre-wrap">${m.renonce_texte}</p>
              </div>`}

            ${(m.recours||[]).map(r => html`
              <div style="margin-top:12px;padding:12px;background:var(--papier);
                   border:1px solid var(--filet);border-radius:2px">
                <div class="small muted">Recours déposé le ${jour(r.cree_le)}
                  · <span class="tag">${r.statut}</span></div>
                <p class="small" style="margin:8px 0 0;white-space:pre-wrap">${r.contenu}</p>
                ${r.decision && html`
                  <p class="small" style="margin:12px 0 0;padding-top:12px;
                     border-top:1px solid var(--filet)">
                    <strong>Décision du ${jour(r.decide_le)} :</strong> ${r.decision}</p>`}
              </div>`)}

            ${m.recours_ouvert && (m.recours||[]).filter(r =>
                ['depose','recevable'].includes(r.statut)).length === 0 && html`
              <form onSubmit=${e=>deposerRecours(m, e)} style="margin-top:16px">
                <div class="field">
                  <label>Déposer un recours gracieux</label>
                  <textarea value=${rec[m.id]||''} onInput=${e=>setRec(o=>({...o,[m.id]:e.target.value}))}
                    placeholder="Exposez les motifs pour lesquels vous contestez cette décision." />
                </div>
                <button class="btn sm" style="margin-top:8px">Déposer le recours</button>
              </form>`}
          </div>`)}

        ${(dos.pieces||[]).length > 0 && html`
          <div style="margin-top:24px">
            <div class="eyebrow" style="margin-bottom:12px">Pièces du dossier</div>
            ${dos.pieces.map(pc => html`
              <div style="padding:10px 0;border-bottom:1px solid var(--filet)">
                <div class="spread">
                  <span>${pc.fichier
                    ? html`<a href="#" onClick=${e=>{e.preventDefault();ouvrirPiece(pc)}}>
                        ${pc.titre} ↗</a>`
                    : pc.titre}</span>
                  <span class="small muted">${jour(pc.cree_le)}</span>
                </div>
                ${pc.contenu && html`<p class="small muted"
                  style="margin:6px 0 0;white-space:pre-wrap">${pc.contenu}</p>`}
              </div>`)}
            ${dos.pieces_non_communicables > 0 && html`
              <p class="small muted" style="margin-top:12px">
                ${dos.pieces_non_communicables} pièce${dos.pieces_non_communicables>1?'s':''}
                du dossier ${dos.pieces_non_communicables>1?'ne sont':'n\u2019est'} pas
                communicable${dos.pieces_non_communicables>1?'s':''}, afin de protéger
                l\u2019identité de personnes tierces.</p>`}
          </div>`}

        ${dos.scelle && html`
          <p class="small muted" style="margin-top:24px;padding-top:24px;
             border-top:1px solid var(--filet)">
            Ce dossier est clos et scellé. Plus aucune pièce ne peut y être versée.
          </p>`}

        ${!dos.scelle && html`
          <form onSubmit=${e=>deposerObs(dos, e)} style="margin-top:24px;
               padding-top:24px;border-top:1px solid var(--filet)">
            <div class="field">
              <label>Vos observations</label>
              <textarea value=${obs[dos.id]||''}
                onInput=${e=>setObs(o=>({...o,[dos.id]:e.target.value}))}
                placeholder="Tout ce que vous souhaitez porter à la connaissance de l\u2019instruction." />
            </div>
            <div class="field">
              <label>Joindre un document</label>
              <input type="file" accept="image/*,.pdf,.doc,.docx"
                onChange=${e=>setDoc(o=>({...o,[dos.id]:e.target.files[0]||null}))} />
              <p class="small muted" style="margin:6px 0 0">
                Photo, PDF ou document, 10 Mo maximum.</p>
            </div>
            <button class="btn sm" style="margin-top:8px">Verser au dossier</button>
          </form>

          ${dos.peut_renoncer && html`
            <div style="margin-top:24px;padding-top:24px;border-top:1px solid var(--filet)">
              ${renonce[dos.id] === undefined
                ? html`<button class="btn light" style="border:0;background:transparent;
                    padding:0;font-size:13px;color:var(--gris)"
                    onClick=${()=>setRenonce(o=>({...o,[dos.id]:''}))}>
                    Renoncer à mes voies de recours gracieux</button>`
                : html`
                  <form onSubmit=${e=>renoncer(dos, e)}>
                    <div class="alerte err" style="margin-bottom:16px">
                      La renonciation est définitive. Elle met fin aux recours en cours
                      et ferme la voie gracieuse pour toutes les décisions déjà notifiées
                      de ce dossier. Elle ne vous prive d\u2019aucun droit devant les
                      juridictions compétentes.
                    </div>
                    <div class="field">
                      <label>Écrivez votre renonciation</label>
                      <textarea required value=${renonce[dos.id]}
                        onInput=${e=>setRenonce(o=>({...o,[dos.id]:e.target.value}))}
                        placeholder="Je soussigné(e) …, renonce expressément aux voies de recours gracieux ouvertes contre les décisions du présent dossier." />
                    </div>
                    <div class="row" style="margin-top:12px">
                      <button class="btn danger">Je renonce</button>
                      <button type="button" class="btn light"
                        onClick=${()=>setRenonce(o=>{const c={...o};delete c[dos.id];return c})}>
                        Annuler</button>
                    </div>
                  </form>`}
            </div>`}`}
      </div>
    </div>`;

  // Bandeau, pour un compte actif.
  if (!entier) return html`
    <div style="margin-bottom:24px">
      ${d.sous_suivi && html`
        <p class="small" style="padding:10px 14px;border:1px solid var(--filet);
           border-left:3px solid var(--laiton);background:#fff;border-radius:2px">
          Votre compte fait l\u2019objet d\u2019une mesure de suivi des usages.
        </p>`}
      ${ouverts.length > 0 && html`
        <div class="alerte" style=${d.sous_suivi?'margin-top:8px':''}>
          ${ouverts.length === 1
            ? 'Un dossier vous concernant est en cours : ' + ETAPE_NOM[ouverts[0].statut].toLowerCase() + '.'
            : ouverts.length + ' dossiers vous concernant sont en cours.'}
          <a href="#/espace/mon-dossier">Consulter et répondre</a>
        </div>`}
    </div>`;

  // Page entière.
  return html`
    <div>
      <div class="eyebrow">Mon dossier</div>
      <h1 style="margin:6px 0 8px">Suivi et voies de recours</h1>
      <p class="muted" style="max-width:60ch">
        Vous trouvez ici l\u2019état de chaque dossier vous concernant, les pièces
        qui vous sont communicables, les décisions prises et les délais dont
        vous disposez pour les contester.
      </p>
      ${msg && html`<div class="alerte ok" style="margin:24px 0">${msg}</div>`}
      <div style="margin-top:24px">
        ${dossiers.length === 0
          ? html`<div class="panneau"><div class="vide">
              Aucun dossier ne vous concerne.</div></div>`
          : dossiers.map(bloc)}
      </div>
    </div>`;
}

/* --- L'écran d'un compte suspendu ------------------------------------ */


/* --- Fiche membre ------------------------------------------------------
   Trois paliers. Les coordonnées ne sortent que si on les demande, et
   la demande est tracée — c'est ce qui rend la trace honnête.
   --------------------------------------------------------------------- */
export function FicheMembre({ id, fermer }){
  const [f, setF] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async (reveler) => {
    const { data, error } = await db.rpc('fiche_membre',
      { p_profil: id, p_reveler: !!reveler });
    if (error) return setMsg(error.message);
    setF(data);
    if (reveler) setMsg('Consultation enregistrée. Le membre peut la voir.');
  }, [id]);
  useEffect(() => { charger(false); }, [charger]);

  if (!f) return html`<div class="vide">Chargement…</div>`;
  if (f.erreur) return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Annuaire</a>
      <div class="alerte err" style="margin-top:16px">${f.erreur}</div>
    </div>`;

  const nom = [f.prenom, f.nom].filter(Boolean).join(' ') || f.matricule;

  return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Annuaire</a>
      ${msg && html`<div class="alerte ok" style="margin-top:16px">${msg}</div>`}

      <div class="carte" style="margin-top:16px">
        <div class="matricule">${f.matricule}</div>
        <div class="nom">${nom}</div>
        <div class="poste">${f.fonction}</div>
        <div class="lieu">${f.chemin || f.territoire || 'Sans rattachement'}</div>
        ${f.postes.length > 0 && html`
          <div class="row" style="margin-top:12px;gap:6px">
            ${f.postes.map(x => html`<span class=${'tag '+(x.couleur==='neutre'?'':x.couleur)}>
              ${x.nom}${x.territoire ? ' · '+x.territoire : ''}</span>`)}
          </div>`}
        <div class="ech">
          <span class="tag or">Échelon ${f.echelon} · ${f.echelon_nom}</span>
          <span class="small muted">Membre depuis ${jour(f.membre_depuis)}</span>
        </div>
        <div class="jauge"><i style=${'width:'+Math.round(f.echelon/7*100)+'%'}></i></div>
      </div>

      ${f.bio && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Présentation</h3></div>
          <div class="corps" style="white-space:pre-wrap">${f.bio}</div>
        </div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <div class="row" style="gap:8px">
            <h3 style="font-size:17px">Coordonnées</h3>
            <${Info} texte="Les coordonnées d'un membre ne s'affichent pas d'emblée. Il faut les demander, et la demande est enregistrée : l'intéressé peut voir qui a consulté son dossier." />
          </div>
          ${!f.revele && f.droit_encadrement && html`
            <button class="btn sm light" onClick=${()=>charger(true)}>Afficher</button>`}
        </div>
        ${f.revele
          ? html`
            <div>
              <div class="ligne"><span class="muted">Adresse</span>
                <a href=${'mailto:'+f.email}>${f.email}</a></div>
              ${f.telephone && html`<div class="ligne"><span class="muted">Téléphone</span>
                <span>${f.telephone}</span></div>`}
              ${f.webmail && html`<div class="ligne"><span class="muted">Webmail</span>
                <span class="mono">${f.webmail}</span></div>`}
              ${f.date_adhesion && html`<div class="ligne"><span class="muted">Adhésion</span>
                <span>${jour(f.date_adhesion)}</span></div>`}
            </div>`
          : html`<div class="corps small muted">
              ${f.droit_encadrement
                ? 'Réservées. Cliquez sur Afficher : votre consultation sera enregistrée.'
                : 'Réservées à l\u2019encadrement du territoire de ce membre.'}
            </div>`}
      </div>

      ${f.revele && f.droit_habilite && html`
        <div class="panneau" style="margin-top:24px;border-color:var(--brun)">
          <div class="tete" style="border-bottom-color:var(--brun)">
            <h3 style="font-size:17px">Situation administrative</h3>
            <span class="tag or">Habilitation requise</span>
          </div>
          <div class="ligne"><span class="muted">Statut du compte</span>
            <span class=${'tag '+(f.statut==='actif'?'vert':'rouge')}>${f.statut}</span></div>
          ${f.protege && html`<div class="ligne"><span class="muted">Protection renforcée</span>
            <span>${f.motif_protection||'Oui'}</span></div>`}
          ${f.sous_suivi && html`<div class="ligne"><span class="muted">Suivi des usages</span>
            <span class="tag rouge">Sous mesure</span></div>`}
          <div class="ligne"><span class="muted">Dossiers disciplinaires</span>
            <span>${f.dossiers_ouverts} en cours · ${f.dossiers_clos} clos</span></div>
          ${(f.acces_nominatifs||[]).length > 0 && html`
            <div class="ligne"><span class="muted">Accès nominatifs</span>
              <div class="row" style="gap:6px;justify-content:flex-end">
                ${f.acces_nominatifs.map(x => html`
                  <span class=${'tag '+(x.statut==='accorde'?'vert':'rouge')}>${x.app}</span>`)}
              </div></div>`}
        </div>`}

      ${f.certifications.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Certifications</h3></div>
          ${f.certifications.map(c => html`
            <div class="ligne">
              <div><div>${c.nom}</div>
                <div class="small muted">Délivrée le ${jour(c.obtenue_le)}
                  ${c.expire_le ? ' · valable jusqu\u2019au ' + jour(c.expire_le) : ''}</div></div>
              <span class="mono muted">${c.numero}</span>
            </div>`)}
        </div>`}

      ${f.groupes.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Groupes de travail</h3></div>
          ${f.groupes.map(g => html`
            <div class="ligne"><span>${g.nom}</span>
              ${g.role === 'responsable' && html`<span class="tag or">Responsable</span>`}</div>`)}
        </div>`}
    </div>`;
}

/* --- Le référentiel, ouvert à tous ------------------------------------ */

export function CurseurEngagement({ compact }){
  const [e, setE] = useState(null);
  const [h, setH] = useState(0);
  const [enregistre, setEnregistre] = useState(false);

  const charger = useCallback(async () => {
    const { data } = await db.rpc('mon_engagement');
    setE(data); setH(Number(data?.heures_visees || 0));
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function poser(valeur){
    setH(valeur);
    await db.rpc('regler_engagement',
      { p_mois: null, p_visees: valeur, p_realisees: null, p_commentaire: null });
    setEnregistre(true);
    setTimeout(() => setEnregistre(false), 2000);
    charger();
  }

  if (!e) return null;
  const fait = Number(e.heures_realisees || 0);
  const pct = h > 0 ? Math.min(Math.round(fait / h * 100), 100) : 0;

  return html`
    <div class="panneau">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Mon engagement — ${nomMois(e.mois)}</h3>
          <${Info} texte="Vous dites ce que vous pouvez donner ce mois-ci. Cela sert à s'organiser collectivement, jamais à vous être reproché : un bénévole n'est pas un salarié." />
        </div>
        ${enregistre && html`<span class="tag vert">Enregistré</span>`}
      </div>
      <div class="corps">
        <div class="spread" style="align-items:baseline">
          <span class="small muted">Je peux donner</span>
          <span style="font-family:var(--titre);font-weight:900;font-size:34px;
                       color:var(--bordeaux);line-height:1">
            ${h}<span style="font-size:16px;color:var(--gris)"> h</span></span>
        </div>
        <input type="range" min="0" max="40" step="1" value=${h}
          onInput=${ev => setH(Number(ev.target.value))}
          onChange=${ev => poser(Number(ev.target.value))}
          style="width:100%;margin-top:12px;accent-color:var(--bordeaux);padding:0" />
        <div class="spread small muted" style="margin-top:2px">
          <span>0 h</span><span>20 h</span><span>40 h et plus</span>
        </div>

        ${h > 0 && html`
          <div style="margin-top:20px;padding-top:16px;border-top:1px solid var(--filet)">
            <div class="spread">
              <span class="small muted">Heures déjà réalisées</span>
              <span class="mono">${fait} / ${h} h</span>
            </div>
            <div class="jauge" style="margin-top:8px">
              <i style=${'width:'+pct+'%;background:var(--bleu)'}></i></div>
            <div class="row" style="margin-top:12px;gap:8px">
              ${[1,2,3,5].map(n => html`
                <button class="btn sm light" onClick=${async ()=>{
                  await db.rpc('regler_engagement', { p_mois:null, p_visees:h,
                    p_realisees: fait + n, p_commentaire:null });
                  charger();
                }}>+${n} h</button>`)}
              ${fait > 0 && html`<button class="btn sm light" onClick=${async ()=>{
                await db.rpc('regler_engagement', { p_mois:null, p_visees:h,
                  p_realisees: 0, p_commentaire:null });
                charger();
              }}>Remettre à zéro</button>`}
            </div>
          </div>`}

        ${!compact && (e.historique||[]).length > 1 && html`
          <div style="margin-top:24px;padding-top:16px;border-top:1px solid var(--filet)">
            <div class="eyebrow" style="margin-bottom:10px">Douze derniers mois</div>
            <div style="display:flex;gap:4px;align-items:flex-end;height:56px">
              ${[...e.historique].reverse().map(x => {
                const v = Number(x.visees||0), r = Number(x.realisees||0);
                const max = Math.max(v, r, 1);
                return html`
                  <div style="flex:1;display:flex;flex-direction:column;
                              justify-content:flex-end;height:100%" title=${nomMois(x.mois)}>
                    <div style=${'height:'+Math.round(r/max*100)+'%;background:var(--bleu);min-height:2px'}></div>
                    <div style=${'height:'+Math.round(Math.max(v-r,0)/max*100)+'%;background:var(--filet)'}></div>
                  </div>`;
              })}
            </div>
            <div class="small muted" style="margin-top:6px">
              En bleu, les heures réalisées ; en gris, ce qui restait annoncé.
            </div>
          </div>`}
      </div>
    </div>`;
}


export function Engagement({ p }){
  const [e, setE] = useState(null);
  const [missions, setMissions] = useState([]);
  const [creation, setCreation] = useState(false);
  const [f, setF] = useState({titre:'',description:'',lieu:'',debut:'',fin:'',
                              heures:'',places:'1',territoire:'',certification:''});
  const [terr, setTerr] = useState([]);
  const [certifs, setCertifs] = useState([]);
  const [msg, setMsg] = useState('');

  const peutProposer = p.echelon >= 3 || p.niveau >= 50;

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('mon_engagement'), db.rpc('missions_ouvertes')
    ]);
    setE(a.data); setMissions(b.data || []);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  useEffect(() => { (async () => {
    if (!peutProposer) return;
    const [t, c] = await Promise.all([
      db.from('territoires').select('id,nom,echelle').order('echelle').order('nom'),
      db.from('certifications').select('code,nom').eq('actif',true).order('nom')
    ]);
    setTerr(t.data||[]); setCertifs(c.data||[]);
  })(); }, [peutProposer]);

  async function postuler(m){
    const message = prompt('Un mot pour le porteur de la mission (facultatif)') || '';
    const { data, error } = await db.rpc('postuler_mission',
      { p_mission: m.id, p_message: message });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Candidature transmise.'); charger();
  }

  async function proposer(ev){
    ev.preventDefault();
    const { data, error } = await db.rpc('creer_mission', {
      p_titre: f.titre, p_description: f.description || null,
      p_territoire: f.territoire || null, p_groupe: null,
      p_certification: f.certification || null, p_lieu: f.lieu || null,
      p_debut: f.debut || null, p_fin: f.fin || null,
      p_heures: f.heures ? Number(f.heures) : null,
      p_places: Number(f.places||1)
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'',description:'',lieu:'',debut:'',fin:'',heures:'',places:'1',
          territoire:'',certification:''});
    setCreation(false); setMsg('Mission publiée.'); charger();
  }

  if (!e) return html`<div class="vide">Chargement…</div>`;
  const taches = e.taches || [];
  const retards = taches.filter(t => t.retard);

  return html`
    <div>
      <div class="eyebrow">Mon engagement</div>
      <h1 style="margin:6px 0 8px">Ce que je donne, ce qui m\u2019attend</h1>
      <p class="muted" style="max-width:58ch">
        Vous fixez vous-même ce que vous pouvez donner. Rien ici n\u2019est un
        objectif imposé : c\u2019est un repère, pour vous et pour celles et ceux
        qui organisent les actions.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <${BilanAnnee} e=${e} />

      <div style="margin-top:24px"><${CurseurEngagement} /></div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete">
          <h3 style="font-size:17px">Mes tâches</h3>
          <div class="row">
            ${retards.length > 0 && html`<span class="tag rouge">${retards.length} en retard</span>`}
            <span class="tag">${taches.length}</span>
          </div>
        </div>
        ${taches.length === 0
          ? html`<div class="vide">Aucune tâche ne vous est assignée.</div>`
          : taches.map(t => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div>${t.titre}</div>
                <div class="small muted">${t.groupe}
                  ${t.echeance ? ' · ' + jour(t.echeance) : ' · sans échéance'}</div>
              </div>
              <div class="row">
                ${t.retard && html`<span class="tag rouge">En retard</span>`}
                ${t.priorite === 'haute' && html`<span class="tag rouge">Prioritaire</span>`}
                <a class="btn sm light" href=${'#/espace/groupe/'+t.groupe_id}>Ouvrir</a>
              </div>
            </div>`)}
      </div>

      ${(e.formations_en_cours||[]).length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Formations commencées</h3></div>
          ${e.formations_en_cours.map(x => html`
            <div class="ligne">
              <div style="flex:1;min-width:200px">
                <div>${x.titre}</div>
                <div class="jauge" style="margin-top:8px">
                  <i style=${'width:'+x.pourcent+'%'}></i></div>
              </div>
              <div class="row">
                <span class="mono">${x.pourcent} %</span>
                <a class="btn sm light" href=${'#/espace/formation/'+x.id}>Reprendre</a>
              </div>
            </div>`)}
        </div>`}

      ${(e.missions||[]).length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Mes missions</h3></div>
          ${e.missions.map(m => html`
            <div class="ligne">
              <div><div>${m.titre}</div>
                <div class="small muted">${m.lieu||''}
                  ${m.debut ? ' · ' + jour(m.debut) : ''}</div></div>
              <span class=${'tag '+(m.statut==='retenu'?'vert':'bleu')}>
                ${m.statut === 'retenu' ? 'Retenu' : 'Candidature déposée'}</span>
            </div>`)}
        </div>`}

      <div class="spread" style="margin-top:40px">
        <div>
          <h2 style="font-size:23px">Missions ouvertes</h2>
          <p class="small muted" style="margin:4px 0 0">
            Des actions auxquelles vous pouvez vous porter volontaire.</p>
        </div>
        ${peutProposer && html`<button class="btn" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Proposer une mission'}</button>`}
      </div>

      ${creation && html`
        <form onSubmit=${proposer} class="panneau" style="margin-top:20px">
          <div class="corps stack">
            <div class="field"><label>Intitulé</label>
              <input required value=${f.titre} onInput=${ev=>setF(o=>({...o,titre:ev.target.value}))}
                placeholder="Animer un atelier citoyenneté au collège Jean-Moulin" /></div>
            <div class="field"><label>Description</label>
              <textarea value=${f.description}
                onInput=${ev=>setF(o=>({...o,description:ev.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:160px;margin:0"><label>Lieu</label>
                <input value=${f.lieu} onInput=${ev=>setF(o=>({...o,lieu:ev.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Début</label>
                <input type="date" value=${f.debut}
                  onInput=${ev=>setF(o=>({...o,debut:ev.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Fin</label>
                <input type="date" value=${f.fin}
                  onInput=${ev=>setF(o=>({...o,fin:ev.target.value}))} /></div>
            </div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:120px;margin:0"><label>Heures estimées</label>
                <input type="number" step="0.5" min="0" value=${f.heures}
                  onInput=${ev=>setF(o=>({...o,heures:ev.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:100px;margin:0"><label>Places</label>
                <input type="number" min="1" value=${f.places}
                  onInput=${ev=>setF(o=>({...o,places:ev.target.value}))} /></div>
            </div>
            <div class="field"><label>Territoire</label>
              <select value=${f.territoire} onChange=${ev=>setF(o=>({...o,territoire:ev.target.value}))}>
                <option value="">Toute la France</option>
                ${terr.map(t => html`<option value=${t.id}>${t.nom} (${t.echelle})</option>`)}
              </select></div>
            <div class="field"><label>Certification exigée</label>
              <select value=${f.certification}
                onChange=${ev=>setF(o=>({...o,certification:ev.target.value}))}>
                <option value="">Aucune</option>
                ${certifs.map(c => html`<option value=${c.code}>${c.nom}</option>`)}
              </select></div>
            <div><button class="btn">Publier la mission</button></div>
          </div>
        </form>`}

      <div class="tuiles" style="margin-top:20px">
        ${missions.length === 0
          ? html`<div class="tuile"><div class="vide">Aucune mission ouverte pour l\u2019instant.</div></div>`
          : missions.map(m => html`
            <div class="tuile" style="min-height:auto">
              <h3>${m.titre}</h3>
              <p>${m.description || ''}</p>
              <div class="row" style="margin-top:12px;gap:6px">
                ${m.lieu && html`<span class="tag">${m.lieu}</span>`}
                ${m.debut && html`<span class="tag">${jour(m.debut)}</span>`}
                ${m.heures_estimees && html`<span class="tag">${m.heures_estimees} h</span>`}
                <span class="tag">${m.retenus}/${m.places} place${m.places>1?'s':''}</span>
                ${m.certification_nom && html`<span class="tag or">${m.certification_nom}</span>`}
              </div>
              <div style="margin-top:14px">
                ${m.ma_candidature
                  ? html`<span class=${'tag '+(m.ma_candidature==='retenu'?'vert':'bleu')}>
                      ${m.ma_candidature === 'retenu' ? 'Vous êtes retenu' :
                        m.ma_candidature === 'candidat' ? 'Candidature déposée' : m.ma_candidature}
                    </span>`
                  : m.obstacle
                    ? html`<span class="small muted">${m.obstacle}</span>`
                    : html`<button class="btn sm" onClick=${()=>postuler(m)}>
                        Je me porte volontaire</button>`}
              </div>
              ${m.porteur && html`<div class="small muted" style="margin-top:10px">
                Proposée par ${m.porteur}</div>`}
            </div>`)}
      </div>
    </div>`;
}


export function DossierAdhesion({ p, recharger }){
  const [a, setA] = useState(null);
  const [c, setC] = useState(null);
  const [f, setF] = useState({});
  const [section, setSection] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [x, y] = await Promise.all([
      db.rpc('mon_adhesion'), db.rpc('completude_dossier', { p_profil: null })
    ]);
    setA(x.data || {}); setC(y.data);
    setF({ ...(x.data||{}), prenom: p?.prenom||'', nom: p?.nom||'',
           telephone: p?.telephone||'', territoire_id: p?.territoire_id||'' });
  }, [p]);
  useEffect(() => { charger(); }, [charger]);

  const [terr, setTerr] = useState([]);
  useEffect(() => {
    db.from('territoires').select('id,nom').eq('echelle','departement')
      .eq('actif',true).order('code').then(({data}) => setTerr(data||[]));
  }, []);

  if (!c) return null;
  const maj = (k,v) => setF(o => ({...o, [k]: v}));
  const manque = cle => (c.manques_detail||[]).some(m => m.cle === cle);

  // Le téléphone se met en forme pendant la frappe.
  function formatTel(v){
    const n = v.replace(/[^0-9+]/g, '');
    if (n.startsWith('0') && n.length <= 10)
      return n.replace(/(\d{2})(?=\d)/g, '$1 ').trim();
    return v;
  }

  async function enregistrer(e){
    e.preventDefault(); setMsg('');
    // Identité : elle vit dans profils.
    const majProfil = {};
    if (f.prenom !== p.prenom) majProfil.prenom = f.prenom;
    if (f.nom !== p.nom) majProfil.nom = f.nom;
    if (f.telephone !== p.telephone) majProfil.telephone = f.telephone;
    if (f.territoire_id && f.territoire_id !== p.territoire_id)
      majProfil.territoire_id = f.territoire_id;
    if (Object.keys(majProfil).length){
      const { error } = await db.from('profils').update(majProfil).eq('id', p.id);
      if (error) return setMsg('Erreur : ' + error.message);
    }
    // Le reste vit dans dossier_adhesion.
    const { data, error } = await db.rpc('enregistrer_adhesion', {
      d: { ...f, accepte_statuts: true, accepte_rgpd: true }
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setSection(null); setMsg('Enregistré.');
    charger(); recharger && recharger();
  }

  const champ = (cle, label, contenu) => html`
    <div class="field">
      <label style=${manque(cle)?'color:var(--bordeaux)':''}>
        ${label}${manque(cle) ? ' — à compléter' : ''}</label>
      ${contenu}
    </div>`;

  return html`
    <div class="panneau" style=${c.complet ? '' : 'border-left:3px solid var(--bordeaux)'}>
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Mon dossier d\u2019adhésion</h3>
          <${Info} texte="Ces informations sont conservées à part de l'annuaire et ne sont lisibles que par les personnes chargées de valider les adhésions." />
        </div>
        <span class=${'tag '+(c.complet?'vert':'rouge')}>
          ${c.complet ? 'Complet' : c.nb_manques + ' à compléter'}</span>
      </div>

      <div class="corps">
        <div class="jauge" style="height:6px;margin:0">
          <i style=${'width:'+c.pourcent+'%;background:'+
            (c.complet?'var(--valide)':'var(--bordeaux)')}></i></div>
        <div class="spread small muted" style="margin-top:6px">
          <span>${c.total - c.nb_manques} sur ${c.total} renseignés</span>
          <span class="mono">${c.pourcent} %</span>
        </div>
        ${!c.complet && html`
          <p class="small" style="margin:14px 0 0">
            Il manque : ${(c.manques||[]).join(', ')}.
          </p>`}
      </div>

      ${msg && html`<div class="corps" style="padding-top:0">
        <div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}>${msg}</div></div>`}

      ${SECTIONS_DOSSIER.map(([cle, titre, resume]) => {
        const st = (c.sections||{})[cle] || {total:0, faits:0, complet:true};
        const ouvert = section === cle;
        return html`
          <div style="border-top:1px solid var(--filet)">
            <div class="ligne" style="cursor:pointer"
              onClick=${()=>setSection(ouvert ? null : cle)}>
              <div>
                <div class="row" style="gap:8px">
                  <span style=${st.complet?'':'font-weight:700'}>${titre}</span>
                  ${st.complet
                    ? html`<span class="tag vert">Fait</span>`
                    : html`<span class="tag rouge">${st.total - st.faits} manquant${st.total-st.faits>1?'s':''}</span>`}
                </div>
                <div class="small muted">${resume}</div>
              </div>
              <button class="btn sm light">${ouvert ? 'Replier' : 'Compléter'}</button>
            </div>

            ${ouvert && html`
              <form onSubmit=${enregistrer} class="corps stack"
                style="background:var(--papier)">
                ${cle === 'identite' && html`
                  <div class="row" style="gap:16px;align-items:flex-start">
                    <div style="flex:1;min-width:150px">
                      ${champ('prenom','Prénom', html`<input required value=${f.prenom||''}
                        onInput=${e=>maj('prenom', e.target.value)} />`)}
                    </div>
                    <div style="flex:1;min-width:150px">
                      ${champ('nom','Nom', html`<input required value=${f.nom||''}
                        onInput=${e=>maj('nom', e.target.value)} />`)}
                    </div>
                  </div>
                  ${champ('telephone','Téléphone', html`
                    <div>
                      <input type="tel" value=${f.telephone||''} placeholder="06 12 34 56 78"
                        onInput=${e=>maj('telephone', formatTel(e.target.value))} />
                      <p class="small muted" style="margin:6px 0 0">
                        Dix chiffres commençant par 0, ou format international
                        (+33…). La mise en forme est automatique.</p>
                    </div>`)}
                  ${champ('territoire','Département de rattachement', html`
                    <select required value=${f.territoire_id||''}
                      onChange=${e=>maj('territoire_id', e.target.value)}>
                      <option value="">Choisir…</option>
                      ${terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
                    </select>`)}`}

                ${cle === 'coordonnees' && html`
                  ${champ('date_naissance','Date de naissance', html`
                    <input type="date" required value=${f.date_naissance||''}
                      onInput=${e=>maj('date_naissance', e.target.value)} />`)}
                  <div class="field"><label>Adresse</label>
                    <input value=${f.adresse||''}
                      onInput=${e=>maj('adresse', e.target.value)} /></div>
                  <div class="row" style="gap:16px;align-items:flex-start">
                    <div style="flex:0 0 130px">
                      ${champ('code_postal','Code postal', html`
                        <input required maxlength="5" inputmode="numeric"
                          value=${f.code_postal||''}
                          onInput=${e=>maj('code_postal', e.target.value.replace(/[^0-9]/g,''))} />`)}
                    </div>
                    <div style="flex:1;min-width:180px">
                      ${champ('ville','Ville', html`<input required value=${f.ville||''}
                        onInput=${e=>maj('ville', e.target.value)} />`)}
                    </div>
                  </div>`}

                ${cle === 'engagement' && html`
                  ${champ('situation','Votre situation', html`
                    <select required value=${f.situation||''}
                      onChange=${e=>maj('situation', e.target.value)}>
                      <option value="">Choisir…</option>
                      ${['Lycéen·ne','Étudiant·e','En emploi','En recherche d\u2019emploi',
                         'En service civique','Retraité·e','Autre'].map(x =>
                        html`<option value=${x}>${x}</option>`)}
                    </select>`)}
                  <div class="field"><label>Profession ou formation</label>
                    <input value=${f.profession||''}
                      onInput=${e=>maj('profession', e.target.value)} /></div>
                  ${champ('motivation','Ce qui vous amène à la FFCE', html`
                    <textarea required value=${f.motivation||''} style="min-height:90px"
                      onInput=${e=>maj('motivation', e.target.value)}
                      placeholder="Quelques lignes suffisent." />`)}
                  <div class="field"><label>Compétences et savoir-faire</label>
                    <textarea value=${f.competences||''} style="min-height:70px"
                      onInput=${e=>maj('competences', e.target.value)}
                      placeholder="Animation, graphisme, droit, langues, comptabilité…" /></div>
                  <div class="field"><label>Disponibilités habituelles</label>
                    <input value=${f.disponibilites||''}
                      onInput=${e=>maj('disponibilites', e.target.value)}
                      placeholder="Soirs de semaine, samedis, vacances scolaires…" /></div>
                  <div class="field"><label>Comment nous avez-vous connus ?</label>
                    <input value=${f.origine||''}
                      onInput=${e=>maj('origine', e.target.value)} /></div>`}

                ${cle === 'consentement' && html`
                  <p class="small muted" style="margin:0">
                    En enregistrant, vous confirmez adhérer aux statuts de la
                    fédération et avoir pris connaissance de la
                    <a href="#/confidentialite">politique de confidentialité</a>.
                    Ces deux accords sont nécessaires à toute adhésion.
                  </p>
                  <label class="row" style="text-transform:none;letter-spacing:0;
                      font-size:14px;color:var(--nuit);margin:0;cursor:pointer">
                    <input type="checkbox" style="width:auto" checked=${!!f.accepte_image}
                      onChange=${e=>maj('accepte_image', e.target.checked)} />
                    <span>J\u2019autorise la fédération à utiliser mon image sur ses
                      supports de communication (facultatif)</span>
                  </label>`}

                <div class="row">
                  <button class="btn">Enregistrer</button>
                  <button type="button" class="btn light"
                    onClick=${()=>setSection(null)}>Annuler</button>
                </div>
              </form>`}
          </div>`;
      })}
    </div>`;
}


/* --- Le dossier d'adhésion, vu par la validation ----------------------
   Replié par défaut : on ne consulte pas des données personnelles par
   inadvertance, on les ouvre parce qu'on en a besoin.
   --------------------------------------------------------------------- */
/* --- Complétude d'un dossier ------------------------------------------ */


export function ApercuAdhesion({ id }){
  const [d, setD] = useState(null);
  const [ouvert, setOuvert] = useState(false);

  async function ouvrir(){
    setOuvert(true);
    const { data } = await db.from('dossier_adhesion').select('*').eq('profil_id', id).maybeSingle();
    setD(data || {});
  }
  if (!ouvert) return html`
    <button class="btn sm light" style="margin-top:8px;border:0;background:transparent;
      padding:0;font-size:12.5px;color:var(--action)"
      onClick=${ouvrir}>Voir le dossier d\u2019adhésion</button>`;
  if (!d) return html`<div class="small muted" style="margin-top:8px">Chargement…</div>`;
  if (Object.keys(d).length === 0) return html`
    <div class="small muted" style="margin-top:8px">Dossier non complété par le membre.</div>`;

  const ligne = (l, v) => v ? html`
    <div style="display:flex;gap:8px;padding:3px 0">
      <span class="small muted" style="min-width:140px">${l}</span>
      <span class="small">${v}</span>
    </div>` : null;

  return html`
    <div style="margin-top:10px;padding:12px;background:var(--papier);
         border:1px solid var(--filet);border-radius:2px">
      ${ligne('Naissance', d.date_naissance ? jour(d.date_naissance) : null)}
      ${ligne('Adresse', [d.adresse, d.code_postal, d.ville].filter(Boolean).join(', '))}
      ${ligne('Situation', d.situation)}
      ${ligne('Profession', d.profession)}
      ${ligne('Compétences', d.competences)}
      ${ligne('Disponibilités', d.disponibilites)}
      ${ligne('Motivation', d.motivation)}
      ${ligne('Nous a connus par', d.origine)}
      ${ligne('Droit à l\u2019image', d.accepte_image ? 'Accordé' : 'Refusé')}
    </div>`;
}

/* --- Dossier incomplet : on ne va pas plus loin ------------------------
   Ni un mur ni une fenêtre qu'on referme : la page qui suit la
   connexion, tant qu'il manque l'essentiel.
   --------------------------------------------------------------------- */
export function DossierIncomplet({ p, manques }){
  return html`
    <div>
      <div class="eyebrow">Avant de continuer</div>
      <h1 style="margin:6px 0 12px">Votre dossier est incomplet</h1>
      <p class="muted" style="max-width:58ch">
        Il manque ${manques.length} information${manques.length>1?'s':''} pour que
        la fédération puisse vous rattacher à une structure, vous proposer des
        missions et tenir ses registres. Complétez-les ci-dessous : l\u2019accès à
        la plateforme s\u2019ouvrira aussitôt.
      </p>

      <div class="panneau" style="margin-top:24px;border-left:3px solid var(--bordeaux)">
        <div class="corps">
          <div class="eyebrow" style="margin-bottom:10px">Ce qui manque</div>
          <div class="row" style="gap:6px">
            ${manques.map(m => html`<span class="tag rouge">${m}</span>`)}
          </div>
        </div>
      </div>

      <div style="margin-top:24px">
        <${MonCompte} p=${p} recharger=${()=>location.reload()} />
      </div>
    </div>`;
}

export function MesAlertesParcours({ recharger }){
  const [liste, setListe] = useState([]);
  const charger = useCallback(() =>
    db.rpc('mes_alertes_parcours').then(({data}) =>
      setListe((data||[]).filter(x => !x.traite_le))), []);
  useEffect(() => { charger(); }, [charger]);
  if (liste.length === 0) return null;

  return html`
    <div class="panneau" style="margin-bottom:16px;border-left:3px solid var(--action)">
      <div class="tete"><h3 style="font-size:17px">On vous signale</h3>
        <span class="tag bleu">${liste.length}</span></div>
      ${liste.map(a => html`
        <div class="ligne" style="align-items:flex-start">
          <div style="flex:1;min-width:230px">
            <div class="row" style="gap:8px">
              <strong>${a.membre}</strong>
              <span class="tag">${a.nature}</span>
            </div>
            <p class="small" style="margin:8px 0 0;max-width:58ch">${a.message}</p>
            <div class="small muted" style="margin-top:4px">
              ${a.auteur} · ${a.auteur_fonction} · ${jour(a.cree_le)}</div>
          </div>
          <button class="btn sm light" onClick=${async ()=>{
            const r = prompt('Votre réponse (facultatif)') || '';
            await db.rpc('repondre_alerte_parcours', { p_id: a.id, p_reponse: r });
            charger(); recharger && recharger();
          }}>Traiter</button>
        </div>`)}
    </div>`;
}


export function MesCreneaux({ p, creneaux, recharger, setMsg }){
  const [f, setF] = useState({date:'', heures:'', duree:'30', lieu:'', visio:''});

  async function poser(e){
    e.preventDefault();
    const liste = f.heures.split(',').map(h => h.trim()).filter(Boolean)
      .map(h => new Date(f.date + 'T' + h).toISOString());
    if (liste.length === 0) return setMsg('Erreur : indiquez au moins une heure.');
    const { data, error } = await db.rpc('poser_creneaux', {
      p_creneaux: liste, p_duree: Number(f.duree||30),
      p_lieu: f.lieu || null, p_visio: f.visio || null,
      p_territoire: p.territoire_id || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({date:'', heures:'', duree:'30', lieu:'', visio:''});
    setMsg(data.poses + ' créneau(x) posé(s).'); recharger();
  }

  return html`
    <div>
      <form onSubmit=${poser} class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Ouvrir des créneaux</h3></div>
        <div class="corps stack">
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:160px;margin:0"><label>Jour</label>
              <input type="date" required value=${f.date}
                onInput=${e=>setF(o=>({...o,date:e.target.value}))} /></div>
            <div class="field" style="flex:2;min-width:200px;margin:0"><label>Heures</label>
              <input required value=${f.heures} placeholder="18:00, 18:30, 19:00"
                onInput=${e=>setF(o=>({...o,heures:e.target.value}))} /></div>
            <div class="field" style="flex:0 0 110px;margin:0"><label>Durée</label>
              <input type="number" min="15" step="15" value=${f.duree}
                onInput=${e=>setF(o=>({...o,duree:e.target.value}))} /></div>
          </div>
          <div class="row" style="gap:16px;align-items:flex-start">
            <div class="field" style="flex:1;min-width:180px;margin:0"><label>Lieu</label>
              <input value=${f.lieu} placeholder="Maison des associations"
                onInput=${e=>setF(o=>({...o,lieu:e.target.value}))} /></div>
            <div class="field" style="flex:1;min-width:180px;margin:0"><label>Lien visio</label>
              <input type="url" value=${f.visio}
                onInput=${e=>setF(o=>({...o,visio:e.target.value}))} /></div>
          </div>
          <div><button class="btn">Ouvrir ces créneaux</button></div>
          <p class="small muted">
            Séparez les heures par des virgules. Ils seront proposés aux nouveaux
            adhérents de votre territoire et de ceux qui en dépendent.
          </p>
        </div>
      </form>

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Créneaux ouverts</h3>
          <span class="tag">${creneaux.length}</span></div>
        ${creneaux.length === 0
          ? html`<div class="vide">Aucun créneau ouvert.</div>`
          : creneaux.map(c => html`
            <div class="ligne">
              <div>
                <div>${new Date(c.debut).toLocaleString('fr-FR',
                  {weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})}</div>
                <div class="small muted">${c.duree_min} min
                  ${c.lieu ? ' · ' + c.lieu : ''}${c.visio ? ' · visioconférence' : ''}</div>
              </div>
              <div class="row">
                ${c.reserve_par
                  ? html`<span class="tag vert">Réservé</span>`
                  : html`<span class="tag">Libre</span>
                    <button class="btn sm light" onClick=${async ()=>{
                      await db.from('creneaux').delete().eq('id', c.id);
                      recharger();
                    }}>Retirer</button>`}
              </div>
            </div>`)}
      </div>
    </div>`;
}

/* --- Le tunnel : chaque marche perdue se voit ------------------------- */

export function Tunnel({ t, compact }){
  if (!t || t.erreur) return html`<div class="alerte err">${t?.erreur||'Indisponible.'}</div>`;
  const depart = t.marches[0].n || 1;
  return html`
    <div>
      <div class="panneau">
        <div class="tete">
          <div class="row" style="gap:8px">
            <h3 style="font-size:17px">De l\u2019inscription à la première mission</h3>
            <${Info} texte="Sur les six derniers mois. Chaque marche montre combien de personnes l'ont franchie, et combien s'y sont arrêtées. C'est là qu'il faut agir." />
          </div>
          <span class="small muted">${t.periode_mois} derniers mois</span>
        </div>
        <div class="corps">
          ${t.marches.map(m => {
            const pct = Math.round(m.n / depart * 100);
            return html`
              <div style="margin-bottom:14px">
                <div class="spread small">
                  <span>${m.rang}. ${m.nom}</span>
                  <span>
                    <span class="mono">${m.n}</span>
                    <span class="muted"> · ${pct} %</span>
                    ${m.perte > 0 && html`<span style="color:var(--bordeaux)">
                      · ${m.perte} perdu${m.perte>1?'s':''}</span>`}
                  </span>
                </div>
                <div style="height:22px;background:var(--filet);margin-top:5px;position:relative">
                  <div style=${'height:100%;width:'+pct+'%;background:'+
                    (m.rang===6?'var(--valide)':'var(--bleu)')}></div>
                </div>
              </div>`;
          })}
        </div>
      </div>

      ${!compact && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Ce que disent les délais</h3></div>
          <div class="ligne"><span class="muted">Délai médian de validation</span>
            <span class="mono">${t.delai_median_validation !== null
              ? t.delai_median_validation + ' jours' : '—'}</span></div>
          <div class="ligne"><span class="muted">Délai médian jusqu\u2019à la formation</span>
            <span class="mono">${t.delai_median_formation !== null
              ? t.delai_median_formation + ' jours' : '—'}</span></div>
          <div class="ligne"><span class="muted">Encore présents à six mois</span>
            <span class="mono">${t.retention_6m !== null
              ? t.retention_6m + ' %' : '—'}
              ${t.cohorte_6m ? html`<span class="muted"> sur ${t.cohorte_6m}</span>` : ''}</span></div>
          <div class="ligne"><span class="muted">Parcours interrompus</span>
            <span class="mono">${t.abandons}</span></div>
        </div>`}
    </div>`;
}

export function PrendreRendezVous(){
  const [libres, setLibres] = useState([]);
  const [miens, setMiens] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b] = await Promise.all([
      db.rpc('creneaux_disponibles'), db.rpc('mes_rendez_vous')
    ]);
    setLibres(a.data||[]); setMiens((b.data||[]).filter(x => !x.je_suis_hote && !x.passe));
  }, []);
  useEffect(() => { charger(); }, [charger]);

  if (miens.length === 0 && libres.length === 0) return null;

  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete"><h3 style="font-size:17px">Rendez-vous d\u2019accueil</h3></div>
      ${msg && html`<div class="corps"><div class="alerte ok">${msg}</div></div>`}
      ${miens.length > 0
        ? miens.map(r => html`
          <div class="ligne">
            <div>
              <div>Avec ${r.avec}</div>
              <div class="small muted">
                ${new Date(r.debut).toLocaleString('fr-FR',
                  {weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})}
                ${r.lieu ? ' · ' + r.lieu : ''}</div>
              ${r.visio && html`<a class="small" href=${r.visio} target="_blank"
                rel="noopener">Rejoindre en visioconférence ↗</a>`}
            </div>
            <button class="btn sm light" onClick=${async ()=>{
              await db.rpc('annuler_creneau', { p_creneau: r.id, p_motif: '' });
              setMsg('Rendez-vous annulé.'); charger();
            }}>Annuler</button>
          </div>`)
        : html`
          <div class="corps">
            <p class="small muted" style="margin:0 0 14px">
              Un temps d\u2019échange avec votre référent pour comprendre où vous
              pouvez agir. Choisissez ce qui vous arrange.
            </p>
            ${libres.slice(0,8).map(c => html`
              <div class="ligne" style="padding-left:0;padding-right:0">
                <div>
                  <div>${new Date(c.debut).toLocaleString('fr-FR',
                    {weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})}</div>
                  <div class="small muted">Avec ${c.hote} · ${c.duree_min} min
                    ${c.lieu ? ' · ' + c.lieu : ''}${c.visio ? ' · visioconférence' : ''}</div>
                </div>
                <button class="btn sm" onClick=${async ()=>{
                  const { data } = await db.rpc('reserver_creneau', { p_creneau: c.id });
                  if (!data.ok) return setMsg(data.message);
                  setMsg('Rendez-vous confirmé.'); charger();
                }}>Réserver</button>
              </div>`)}
          </div>`}
    </div>`;
}

export function MesDistinctions({ profil }){
  const [d, setD] = useState([]);
  useEffect(() => {
    db.rpc('mes_distinctions', { p_profil: profil || null })
      .then(({data}) => setD(data||[]));
  }, [profil]);
  if (d.length === 0) return null;
  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete"><h3 style="font-size:17px">Distinctions</h3>
        <span class="tag or">${d.length}</span></div>
      ${d.map(x => html`
        <div class="ligne" style="align-items:flex-start">
          <div style="flex:1;min-width:220px">
            <div class="row" style="gap:8px">
              <span class=${'tag '+(x.couleur||'or')}>${x.type_nom}</span>
            </div>
            <p class="small" style="margin:8px 0 0;max-width:56ch">${x.motif}</p>
            ${x.texte && html`<p class="small muted" style="margin:6px 0 0;
              font-style:italic">${x.texte}</p>`}
          </div>
          <div class="row">
            <span class="mono muted">${x.numero}</span>
            <span class="small muted">${jour(x.decernee_le)}</span>
          </div>
        </div>`)}
    </div>`;
}

/* --- Assistance : signaler, proposer ---------------------------------- */

export function MesVirements(){
  const [liste, setListe] = useState([]);
  const [msg, setMsg] = useState('');
  const charger = useCallback(() =>
    db.rpc('mes_virements_a_confirmer').then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);
  if (liste.length === 0) return null;

  async function repondre(x, recu){
    const motif = recu ? null : prompt(
      'Que se passe-t-il ?\n\nMontant incorrect, virement non reçu, autre — précisez.');
    if (!recu && !motif) return;
    const { data, error } = await db.rpc('accuser_virement',
      { p_note: x.note_id, p_recu: recu, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(recu ? 'Merci de votre confirmation.'
                : 'Signalement transmis à la direction financière.');
    charger();
  }

  async function telecharger(chemin){
    const { data, error } = await db.storage.from('justificatifs')
      .createSignedUrl(chemin, 300);
    if (error) return setMsg('Document introuvable.');
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  return html`
    <div class="panneau" style="margin-bottom:24px;border-left:3px solid var(--action)">
      <div class="tete"><h3 style="font-size:17px">Paiements à confirmer</h3>
        <span class="tag bleu">${liste.length}</span></div>
      ${msg && html`<div class="corps"><div class=${'alerte '+
        (msg.startsWith('Erreur')?'err':'ok')}>${msg}</div></div>`}
      ${liste.map(x => html`
        <div class="ligne">
          <div style="flex:1;min-width:220px">
            <div>${x.objet} — <span class="mono">${EURO(x.total)}</span></div>
            <div class="small muted">
              <span class="mono">${x.reference}</span>
              · ${x.mode === 'abandon_creance' ? 'abandon de créance' : 'virement'}
              ${x.reference_paiement ? ' · réf. ' + x.reference_paiement : ''}
              · émis le ${jour(x.payee_le)}
              ${x.jours > 15 ? ' — il y a ' + x.jours + ' jours' : ''}
            </div>
            ${x.recu_fiscal && html`<div class="small muted">
              Reçu fiscal ${x.recu_fiscal}</div>`}
          </div>
          <div class="row">
            ${x.attestation && html`<button class="btn sm light"
              onClick=${()=>telecharger(x.attestation)}>Attestation</button>`}
            ${x.mode === 'virement'
              ? html`
                <button class="btn sm" onClick=${()=>repondre(x,true)}>
                  J\u2019ai bien reçu</button>
                <button class="btn sm light" onClick=${()=>repondre(x,false)}>
                  Signaler un problème</button>`
              : html`<button class="btn sm" onClick=${()=>repondre(x,true)}>
                  J\u2019en prends acte</button>`}
          </div>
        </div>`)}
    </div>`;
}


export function Passeport({ p, profil }){
  const [d, setD] = useState(null);
  useEffect(() => {
    db.rpc('passeport', { p_profil: profil || null }).then(({data}) => setD(data));
  }, [profil]);
  if (!d) return html`<div class="vide">Chargement…</div>`;
  if (d.erreur) return html`<div class="alerte err">${d.erreur}</div>`;
  const i = d.identite, t = d.totaux;

  function imprimer(){ window.print(); }

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Passeport d\u2019engagement</div>
          <h1 style="margin:6px 0 0">${i.nom}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono" style="font-size:13px">${i.matricule}</span>
            · ${i.fonction} · échelon ${i.echelon} (${i.echelon_nom})
            ${i.territoire ? ' · ' + i.territoire : ''}
          </div>
        </div>
        <button class="btn light" onClick=${imprimer}>Imprimer</button>
      </div>

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:32px">${Number(t.heures||0)}</div>
          <div class="l">Heures de bénévolat</div></div>
        <div><div class="n" style="font-size:32px">${t.missions}</div>
          <div class="l">Missions accomplies</div></div>
        <div><div class="n" style="font-size:32px">${(d.certifications||[]).length}</div>
          <div class="l">Certifications</div></div>
        <div><div class="n" style="font-size:32px">${t.annees}</div>
          <div class="l">Années d\u2019engagement</div></div>
      </div>

      ${(d.competences_exercees||[]).length > 0 && html`
        <div class="panneau" style="margin-bottom:20px">
          <div class="tete"><h3 style="font-size:17px">Compétences exercées</h3></div>
          <div class="corps row" style="gap:6px">
            ${d.competences_exercees.map(c => html`<span class="tag bleu">${c}</span>`)}
          </div>
        </div>`}

      <div class="panneau" style="margin-bottom:20px">
        <div class="tete"><h3 style="font-size:17px">Missions</h3>
          <span class="tag">${(d.missions||[]).length}</span></div>
        ${(d.missions||[]).length === 0
          ? html`<div class="vide">Aucune mission attestée pour l\u2019instant.</div>`
          : (d.missions||[]).map(m => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px">
                  <strong>${m.titre}</strong>
                  ${m.merite && html`<span class=${'tag '+(MERITES[m.merite]||['',''])[1]}>
                    ${(MERITES[m.merite]||[m.merite,''])[0]}</span>`}
                </div>
                <div class="small muted" style="margin-top:4px">
                  ${m.lieu ? m.lieu + ' · ' : ''}
                  ${m.debut ? jour(m.debut) : ''}
                  · ${m.heures} heures
                </div>
                <p class="small" style="margin:8px 0 0;max-width:60ch">${m.realise}</p>
                ${(m.competences||[]).length > 0 && html`
                  <div class="row" style="margin-top:8px;gap:5px">
                    ${m.competences.map(c => html`<span class="tag">${c}</span>`)}
                  </div>`}
                ${m.appreciation && html`<p class="small muted"
                  style="margin:8px 0 0;font-style:italic">« ${m.appreciation} »</p>`}
                <div class="small muted" style="margin-top:6px">
                  Attesté par ${m.atteste_par}</div>
              </div>
            </div>`)}
      </div>

      ${(d.certifications||[]).length > 0 && html`
        <div class="panneau" style="margin-bottom:20px">
          <div class="tete"><h3 style="font-size:17px">Formations certifiées</h3></div>
          ${d.certifications.map(c => html`
            <div class="ligne">
              <div><div>${c.nom}</div>
                <div class="small muted">Obtenue le ${jour(c.obtenue_le)}
                  ${c.expire_le ? ' · valable jusqu\u2019au ' + jour(c.expire_le) : ''}</div></div>
              <span class="mono muted">${c.numero}</span>
            </div>`)}
        </div>`}

      ${(d.distinctions||[]).length > 0 && html`
        <div class="panneau" style="margin-bottom:20px">
          <div class="tete"><h3 style="font-size:17px">Distinctions</h3></div>
          ${d.distinctions.map(x => html`
            <div class="ligne" style="align-items:flex-start">
              <div><div class="row" style="gap:8px">
                  <span class="tag or">${x.nom}</span>
                  <span class="small muted">${jour(x.le)}</span></div>
                <p class="small" style="margin:6px 0 0;max-width:56ch">${x.motif}</p></div>
              <span class="mono muted">${x.numero}</span>
            </div>`)}
        </div>`}

      ${(d.mandats||[]).length > 0 && html`
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Mandats électifs</h3></div>
          ${d.mandats.map(m => html`
            <div class="ligne">
              <span>${m.poste}${m.territoire ? ' — ' + m.territoire : ''}</span>
              <span class="small muted">${jour(m.debut)} au ${jour(m.fin)}</span>
            </div>`)}
        </div>`}

      <p class="small muted" style="margin-top:24px;max-width:62ch">
        Ce relevé est établi par la Fédération française pour la citoyenneté et
        l\u2019égalité des chances. Chaque mission y est attestée par le responsable
        qui l\u2019a encadrée.
      </p>
    </div>`;
}

/* --- Bilans de mission à rédiger --------------------------------------- */

export function BilansMission({ setMsg }){
  const [liste, setListe] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [f, setF] = useState({heures:'', realise:'', competences:'',
                              appreciation:'', merite:''});

  const charger = useCallback(() =>
    db.rpc('bilans_a_rediger').then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(e, x){
    e.preventDefault();
    const comp = f.competences.split(',').map(c=>c.trim()).filter(Boolean);
    const { data, error } = await db.rpc('rediger_bilan', {
      p_mission: x.mission_id, p_profil: x.profil_id,
      p_heures: Number(f.heures), p_realise: f.realise,
      p_competences: comp.length ? comp : null,
      p_appreciation: f.appreciation || null, p_merite: f.merite || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({heures:'', realise:'', competences:'', appreciation:'', merite:''});
    setOuvert(null); setMsg('Bilan enregistré. Les heures sont portées au compte du bénévole.');
    charger();
  }

  return html`
    <div>
      <p class="small muted" style="margin-bottom:16px;max-width:62ch">
        Après chaque mission, dites ce qui a été fait et combien d\u2019heures ont été
        données. C\u2019est ce qui alimente le passeport d\u2019engagement du bénévole —
        et ce qu\u2019il présentera un jour à un employeur.
      </p>
      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Aucun bilan en attente.</div>`
          : liste.map(x => html`
            <div style="border-bottom:1px solid var(--filet)">
              <div class="ligne" style="border:0">
                <div style="flex:1;min-width:230px">
                  <div class="row" style="gap:8px">
                    <strong>${x.membre}</strong>
                    ${x.jours_depuis > 14 && html`
                      <span class="tag rouge">${x.jours_depuis} jours</span>`}
                  </div>
                  <div class="small muted">
                    ${x.mission}${x.lieu ? ' · ' + x.lieu : ''}
                    ${x.fin ? ' · terminée le ' + jour(x.fin) : ''}
                  </div>
                </div>
                <button class="btn sm" onClick=${()=>setOuvert(
                  ouvert===x.mission_id+x.profil_id ? null : x.mission_id+x.profil_id)}>
                  ${ouvert===x.mission_id+x.profil_id ? 'Fermer' : 'Rédiger'}</button>
              </div>

              ${ouvert === x.mission_id+x.profil_id && html`
                <form onSubmit=${e=>enregistrer(e, x)} class="corps stack"
                  style="background:var(--papier)">
                  <div class="field"><label>Heures effectuées</label>
                    <input type="number" step="0.5" min="0.5" required value=${f.heures}
                      onInput=${e=>setF(o=>({...o,heures:e.target.value}))}
                      style="max-width:140px" /></div>
                  <div class="field"><label>Ce qui a été fait</label>
                    <textarea required value=${f.realise} style="min-height:90px"
                      onInput=${e=>setF(o=>({...o,realise:e.target.value}))}
                      placeholder="Animation d\u2019un atelier citoyenneté auprès de deux classes de 4e." /></div>
                  <div class="field"><label>Compétences exercées</label>
                    <input value=${f.competences}
                      onInput=${e=>setF(o=>({...o,competences:e.target.value}))}
                      placeholder="Animation de groupe, prise de parole, médiation" />
                    <p class="small muted" style="margin:6px 0 0">Séparées par des virgules.</p>
                  </div>
                  <div class="field"><label>Appréciation</label>
                    <textarea value=${f.appreciation}
                      onInput=${e=>setF(o=>({...o,appreciation:e.target.value}))}
                      placeholder="Elle figurera dans son passeport : écrivez ce que vous diriez de lui." /></div>
                  <div class="field"><label>Mérite</label>
                    <select value=${f.merite}
                      onChange=${e=>setF(o=>({...o,merite:e.target.value}))}>
                      <option value="">Non renseigné</option>
                      ${Object.entries(MERITES).map(([k,v]) =>
                        html`<option value=${k}>${v[0]}</option>`)}
                    </select></div>
                  <div><button class="btn">Enregistrer le bilan</button></div>
                </form>`}
            </div>`)}
      </div>
    </div>`;
}

/* --- Répartition des nouveaux adhérents -------------------------------- */

export function MaChaine(){
  const [c, setC] = useState(null);
  useEffect(() => { db.rpc('ma_chaine').then(({data}) => setC(data)); }, []);
  if (!c) return null;

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Ma chaîne</h3>
          <${Info} texte="Qui vous accompagne, et de qui relève votre territoire. C'est le chemin à suivre pour faire remonter une question." />
        </div>
      </div>
      ${c.mon_accompagnant && html`
        <div class="ligne">
          <span class="muted small">Mon accompagnant</span>
          <strong>${c.mon_accompagnant.nom}</strong>
        </div>`}
      ${(c.chaine||[]).map(x => html`
        <div class="ligne" style="align-items:flex-start">
          <div style="flex:1;min-width:200px">
            <div class="row" style="gap:8px">
              <span>${x.territoire}</span>
              <span class="tag">${x.echelle}</span>
            </div>
            <div class="row" style="margin-top:6px;gap:6px">
              ${(x.responsables||[]).map(r => html`
                <span class="tag or">${r.nom} — ${r.poste}</span>`)}
              ${(x.encadrants||[]).slice(0,3).map(e => html`
                <span class="tag">${e.nom} — ${e.fonction}</span>`)}
              ${(x.responsables||[]).length === 0 && (x.encadrants||[]).length === 0 && html`
                <span class="small muted">Personne à cet échelon</span>`}
            </div>
          </div>
        </div>`)}
      ${(c.dont_je_reponds||[]).length > 0 && html`
        <div class="corps" style="border-top:1px solid var(--filet)">
          <div class="eyebrow" style="margin-bottom:8px">
            ${c.dont_je_reponds.length} personne(s) dans mon périmètre</div>
          <div class="row" style="gap:6px">
            ${c.dont_je_reponds.slice(0,12).map(x => html`
              <span class="tag">${x.nom}</span>`)}
          </div>
        </div>`}
    </div>`;
}

/* --- Direction générale : vérifications ------------------------------ */


/* =====================================================================
   MES MANDATS
   Ce qu'on me demande à moi se répond ici, jamais depuis l'application
   concernée. Un intérim proposé à quelqu'un qui n'a pas Habilitations
   restait sans réponse possible : la file de travail renvoyait vers une
   porte fermée. Cet écran est ouvert à tout membre actif, sans droit.
   ===================================================================== */
export function MesMandats({ p, recharger }){
  const [interims, setInterims] = useState([]);
  const [invits, setInvits] = useState([]);
  const [droits, setDroits] = useState([]);
  const [gens, setGens] = useState([]);
  const [confier, setConfier] = useState(false);
  const [ci, setCi] = useState({ profil:'', poste:'', debut:'', fin:'', motif:'' });
  const [msg, setMsg] = useState('');
  const [pret, setPret] = useState(false);

  const charger = useCallback(async () => {
    const [a, b, c, g] = await Promise.all([
      db.rpc('mes_interims'),
      db.rpc('mes_invitations_groupe'),
      db.rpc('mes_droits'),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom')
        .eq('statut','actif').order('nom')
    ]);
    setInterims(a.data || []); setInvits(b.data || []); setDroits(c.data || []);
    setGens(g.data || []);
    setPret(true);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error) return setMsg('Erreur : ' + error.message);
    if (data && data.ok === false) return setMsg('Erreur : ' + data.message);
    setMsg(ok); charger(); if (recharger) recharger();
  };

  if (!pret) return html`<div class="vide" style="padding:120px">Chargement…</div>`;

  const proposes = interims.filter(i => i.statut === 'propose' && i.je_suis_interimaire);
  const miens    = interims.filter(i => i.je_suis_interimaire && i.statut !== 'propose');
  const confies  = interims.filter(i => !i.je_suis_interimaire);
  const parCat   = [...new Set(droits.map(d => d.categorie))];

  const etatInterim = s => {
    const t = { propose:['Proposé','bleu'], a_venir:['À venir','or'],
                en_cours:['En cours','vert'], echu:['Échu',''],
                clos:['Clos',''], refuse:['Refusé','rouge'] }[s] || [s,''];
    return html`<span class=${'tag '+t[1]}>${t[0]}</span>`;
  };

  return html`
    <div>
      <div class="eyebrow">Mes mandats</div>
      <h1 style="margin:6px 0 8px">Ce que je porte, ce qu\u2019on me propose</h1>
      <p class="muted" style="max-width:62ch">
        Les postes que j\u2019occupe, les intérims qu\u2019on me confie ou que je
        confie, les invitations qui m\u2019attendent, et la liste exacte des
        droits qui en découlent. Cet écran ne demande aucun accès : ce
        qu\u2019on vous demande, vous devez pouvoir y répondre.
      </p>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin:20px 0">${msg}</div>`}

      ${proposes.length > 0 && html`
        <h3 style="font-size:17px;margin:28px 0 12px">On vous propose un intérim</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${proposes.map(i => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div style="font-weight:600">${i.poste_nom}</div>
                <div class="small muted" style="margin-top:3px">
                  Au nom de ${i.titulaire} · du ${jour(i.debut)} au ${jour(i.fin)}
                </div>
                ${i.motif && html`<div class="small" style="margin-top:4px">${i.motif}</div>`}
              </div>
              <div class="row" style="gap:6px">
                <button class="btn sm" onClick=${()=>appel('repondre_interim',
                  { p_id:i.id, p_accepte:true },
                  'Intérim accepté. Les droits du poste vous sont ouverts.')}>
                  Accepter</button>
                <button class="btn sm light" onClick=${()=>appel('repondre_interim',
                  { p_id:i.id, p_accepte:false }, 'Intérim refusé.')}>
                  Refuser</button>
              </div>
            </div>`)}
        </div>`}

      ${invits.length > 0 && html`
        <h3 style="font-size:17px;margin:28px 0 12px">On vous invite à un groupe de travail</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${invits.map(g => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div style="font-weight:600">${g.titre}</div>
                <div class="small muted" style="margin-top:3px">
                  Invité par ${g.invite_par || '—'}
                  ${g.responsable ? ' · animé par ' + g.responsable : ''}
                  ${g.territoire ? ' · ' + g.territoire : ''}
                </div>
                ${g.objet && html`<div class="small" style="margin-top:4px">${g.objet}</div>`}
              </div>
              <div class="row" style="gap:6px">
                <button class="btn sm" onClick=${()=>appel('repondre_invitation',
                  { p_groupe:g.groupe_id, p_accepte:true },
                  'Invitation acceptée. Le groupe apparaît dans vos applications.')}>
                  Rejoindre</button>
                <button class="btn sm light" onClick=${()=>appel('repondre_invitation',
                  { p_groupe:g.groupe_id, p_accepte:false }, 'Invitation déclinée.')}>
                  Décliner</button>
              </div>
            </div>`)}
        </div>`}

      <div class="spread" style="margin:28px 0 12px">
        <h3 style="font-size:17px">Mes postes</h3>
        ${(p.postes||[]).length > 0 && html`
          <button class="btn sm light" onClick=${()=>setConfier(!confier)}>
            ${confier ? 'Fermer' : 'Confier un intérim'}</button>`}
      </div>
      <div class="panneau" style="margin-bottom:28px">
        ${(p.postes||[]).length === 0
          ? html`<div class="corps muted">
              Vous n\u2019occupez aucun poste. Vos accès découlent de votre fonction.</div>`
          : (p.postes||[]).map((x,i) => html`
            <div class="ligne" key=${i}>
              <div style="flex:1;min-width:200px">
                <div>${x.nom}</div>
                <div class="small muted">${x.territoire_nom || 'National'}</div>
              </div>
              ${x.fin
                ? html`<span class="small muted">jusqu\u2019au ${jour(x.fin)}</span>`
                : html`<span class="tag vert">Sans terme</span>`}
            </div>`)}
        ${confier && html`
          <form class="corps stack" onSubmit=${e=>{
            e.preventDefault();
            appel('confier_interim', {
              p_interimaire: ci.profil, p_poste: ci.poste,
              p_debut: ci.debut || null, p_fin: ci.fin || null, p_motif: ci.motif
            }, 'Intérim proposé. La personne le verra dans ses mandats.');
            setCi({ profil:'', poste:'', debut:'', fin:'', motif:'' }); setConfier(false);
          }}>
            <p class="small muted" style="margin:0">
              On ne délègue qu\u2019un poste qu\u2019on occupe, pour six mois au plus.
              Au-delà, il faut nommer. L\u2019intérimaire doit accepter.
            </p>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:180px;margin:0">
                <label>Poste délégué</label>
                <select value=${ci.poste} onChange=${e=>setCi(o=>({...o,poste:e.target.value}))}>
                  <option value="">— Choisir —</option>
                  ${(p.postes||[]).map(x => html`
                    <option value=${x.poste || x.code}>${x.nom}</option>`)}
                </select></div>
              <div class="field" style="flex:2;min-width:200px;margin:0">
                <label>Intérimaire</label>
                <select value=${ci.profil} onChange=${e=>setCi(o=>({...o,profil:e.target.value}))}>
                  <option value="">— Choisir —</option>
                  ${gens.map(g => html`<option value=${g.id}>
                    ${nomComplet(g)} · ${g.fonction_nom}</option>`)}
                </select></div>
            </div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;margin:0"><label>Début</label>
                <input type="date" value=${ci.debut}
                  onInput=${e=>setCi(o=>({...o,debut:e.target.value}))} /></div>
              <div class="field" style="flex:1;margin:0"><label>Fin</label>
                <input type="date" value=${ci.fin}
                  onInput=${e=>setCi(o=>({...o,fin:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Motif</label>
              <input value=${ci.motif} placeholder="Absence, congé, empêchement…"
                onInput=${e=>setCi(o=>({...o,motif:e.target.value}))} /></div>
            <div><button class="btn">Proposer l\u2019intérim</button></div>
          </form>`}
      </div>

      ${(miens.length > 0 || confies.length > 0) && html`
        <h3 style="font-size:17px;margin:28px 0 12px">Intérims</h3>
        <div class="panneau" style="margin-bottom:28px">
          ${miens.map(i => html`
            <div class="ligne" key=${i.id}>
              <div style="flex:1;min-width:220px">
                <div>${i.poste_nom}</div>
                <div class="small muted">Au nom de ${i.titulaire}
                  · ${jour(i.debut)} → ${jour(i.fin)}</div>
              </div>
              <div class="row" style="gap:10px">
                ${i.statut === 'en_cours' && i.jours_restants >= 0 && html`
                  <span class="small muted">${i.jours_restants} jour(s)</span>`}
                ${etatInterim(i.statut)}
              </div>
            </div>`)}
          ${confies.map(i => html`
            <div class="ligne" key=${i.id}>
              <div style="flex:1;min-width:220px">
                <div>${i.poste_nom}</div>
                <div class="small muted">Confié à ${i.interimaire}
                  · ${jour(i.debut)} → ${jour(i.fin)}</div>
              </div>
              <div class="row" style="gap:8px">
                ${etatInterim(i.statut)}
                ${['en_cours','a_venir','propose'].includes(i.statut) && html`
                  <button class="btn sm light" onClick=${()=>appel('clore_interim',
                    { p_id:i.id }, 'Intérim clos.')}>Clore</button>`}
              </div>
            </div>`)}
        </div>`}

      <h3 style="font-size:17px;margin:28px 0 12px">Les droits qui en découlent</h3>
      <div class="panneau">
        ${droits.length === 0
          ? html`<div class="corps muted">
              Aucun droit atomique. Vos accès viennent de votre fonction.
              <a href="#/espace/referentiel">Comprendre mes droits</a></div>`
          : parCat.map(cat => html`
            <div class="ligne" key=${cat} style="align-items:flex-start">
              <div class="small muted" style="min-width:150px">${cat}</div>
              <div class="row" style="gap:6px;flex-wrap:wrap;flex:1;justify-content:flex-end">
                ${droits.filter(d => d.categorie === cat).map(d => html`
                  <span class=${'tag '+(d.sensible?'rouge':'')} title=${d.code}>${d.nom}</span>`)}
              </div>
            </div>`)}
      </div>
    </div>`;
}


/* =====================================================================
   LA FICHE D'OUVERTURE
   « Comment tout lui débloquer, et rien de plus. » La question se posait
   à chaque arrivée sans réponse écrite. Le membre et celui qui
   l'accompagne lisent maintenant la même liste, dans les mêmes mots.
   ===================================================================== */
export function FicheOuverture({ profil, titre, compact }){
  const [l, setL] = useState(null);
  useEffect(() => {
    db.rpc('checklist_ouverture', { p_profil: profil || null })
      .then(({data}) => setL(data || []));
  }, [profil]);
  if (!l) return null;

  const reste = l.filter(x => x.etat !== 'fait');
  if (compact && reste.length === 0) return null;

  const marque = e => e === 'fait'
    ? html`<span class="tag vert">Fait</span>`
    : e === 'bloquant'
      ? html`<span class="tag rouge">Bloquant</span>`
      : html`<span class="tag or">À faire</span>`;

  const lignes = compact ? reste : l;

  return html`
    <div class="panneau">
      <div class="tete spread">
        <h3 style="font-size:17px">${titre || 'Ce qu\u2019il reste à ouvrir'}</h3>
        <span class="small muted">${l.filter(x=>x.etat==='fait').length} sur ${l.length}</span>
      </div>
      ${lignes.map(x => html`
        <div class="ligne" key=${x.code} style="align-items:flex-start">
          <div style="flex:1;min-width:220px">
            <div>${x.libelle}</div>
            <div class="small muted" style="margin-top:3px">${x.detail}</div>
          </div>
          <div class="row" style="gap:10px">
            ${marque(x.etat)}
            ${x.etat !== 'fait' && html`<a class="btn sm light" href=${x.lien}>Ouvrir</a>`}
          </div>
        </div>`)}
    </div>`;
}


/* =====================================================================
   LE PROFIL INTERNE
   Ce que la fédération montre d'un membre à un autre. Ni courriel, ni
   téléphone, ni adresse : ceux-là relèvent de la fiche membre, dont la
   consultation se journalise et déclenche une alerte si le dossier est
   protégé. Ici, rien de plus que ce qui est déjà interne-public.
   ===================================================================== */
export function ProfilInterne({ profil, fermer }){
  const [d, setD] = useState(null);
  useEffect(() => {
    db.rpc('profil_interne', { p_profil: profil }).then(({data}) => setD(data));
  }, [profil]);
  if (!d) return null;

  if (!d.ok) return html`
    <div class="panneau" style="margin-top:16px">
      <div class="corps small muted">${d.message}
        <a href="#" onClick=${e=>{e.preventDefault();fermer()}}>Fermer</a></div>
    </div>`;

  return html`
    <div class="panneau" style="margin-top:16px">
      <div class="corps">
        <div class="spread" style="align-items:flex-start;gap:18px">
          <div class="row" style="gap:16px;align-items:flex-start;min-width:0">
            <${Portrait} chemin=${d.photo_url} nom=${d.nom} taille=${64} />
            <div style="min-width:0">
              <div style="font-weight:600;font-size:18px">${d.nom}</div>
              <div class="small muted" style="margin-top:2px">
                ${d.fonction}${d.echelon ? ' · ' + d.echelon : ''}
              </div>
              <div class="small muted">${d.territoire || 'National'}
                ${d.depuis ? ' · adhérent depuis le ' + jour(d.depuis) : ''}</div>
              <div class="mono muted small" style="margin-top:2px">${d.matricule}</div>
            </div>
          </div>
          <button class="btn sm light" onClick=${fermer}>Fermer</button>
        </div>

        ${d.bio && html`<p class="small" style="margin-top:14px">${d.bio}</p>`}

        ${(d.postes||[]).length > 0 && html`
          <div style="margin-top:14px">
            <div class="small muted" style="margin-bottom:6px">Mandats en cours</div>
            <div class="row" style="gap:6px;flex-wrap:wrap">
              ${d.postes.map((x,i) => html`<span class="tag" key=${i}>${x.nom}${
                x.territoire ? ' · ' + x.territoire : ''}</span>`)}
            </div>
          </div>`}

        ${(d.distinctions||[]).length > 0 && html`
          <div style="margin-top:14px">
            <div class="small muted" style="margin-bottom:6px">Distinctions</div>
            <div class="row" style="gap:6px;flex-wrap:wrap">
              ${d.distinctions.map((x,i) => html`<span class="tag or" key=${i}>${x}</span>`)}
            </div>
          </div>`}
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
export function BilanAnnee({ e }){
  if (!e || !e.annee) return null;
  const a = e.annee, pr = e.progression || {};
  const total = Number(pr.total || 0);
  const palier = pr.prochain ? Number(pr.prochain.points || 0) : null;
  const depart = Number(pr.palier_actuel || 0);
  const pct = palier && palier > depart
    ? Math.max(0, Math.min(100, Math.round((total - depart) * 100 / (palier - depart))))
    : 100;

  const declarees = Number(a.heures || 0);
  const attestees = Number(a.heures_attestees || 0);

  return html`
    <div style="margin-top:24px">
      <div class="chiffres" style="margin-bottom:24px">
        <div><div class="n" style="font-size:30px">${declarees}</div>
          <div class="l">Heures déclarées cette année</div></div>
        <div><div class="n" style="font-size:30px">${attestees}</div>
          <div class="l">Dont attestées par un bilan</div></div>
        <div><div class="n" style="font-size:30px">${a.missions}</div>
          <div class="l">Missions accomplies</div></div>
        <div><div class="n" style="font-size:30px">${a.taches_faites}</div>
          <div class="l">Tâches achevées</div></div>
      </div>

      ${attestees > declarees && html`
        <div class="alerte" style="margin-bottom:24px">
          Vos bilans de mission attestent ${attestees} heures, plus que les
          ${declarees} que vous avez déclarées. Les heures attestées font foi :
          ce sont elles que la chancellerie retient.
        </div>`}

      ${e.bilans_a_rediger > 0 && html`
        <div class="alerte" style="margin-bottom:24px;border-left:3px solid var(--laiton)">
          ${e.bilans_a_rediger} bilan(s) de mission à rédiger. Tant qu\u2019ils ne le
          sont pas, ces heures ne comptent pour personne.
          <a href="#/espace/parcours">Les rédiger</a>
        </div>`}

      <div class="panneau">
        <div class="tete spread">
          <h3 style="font-size:17px">Ma progression</h3>
          <span class="small muted">${pr.echelon_nom || ''}</span>
        </div>
        <div class="corps">
          ${pr.prochain
            ? html`
              <div class="spread" style="margin-bottom:10px">
                <span class="muted">Vers ${pr.prochain.nom}</span>
                <span class="mono">${total} / ${palier} points</span>
              </div>
              <div class="jauge"><i style=${'width:'+pct+'%'}></i></div>
              <div class="small muted" style="margin-top:8px">
                ${total >= palier
                  ? 'Vous remplissez les conditions du palier suivant. La promotion '
                    + 'reste une décision de la chancellerie : elle se motive et ne '
                    + 's\u2019obtient pas automatiquement.'
                  : (palier - total) + ' point(s) vous en séparent.'}
                ${pr.prochain.ouvre ? ' Cet échelon ouvre : ' + pr.prochain.ouvre + '.' : ''}
              </div>`
            : html`<div class="muted">Vous êtes au dernier échelon.</div>`}

          ${pr.detail && html`
            <div style="margin-top:20px">
              <div class="small muted" style="margin-bottom:8px">D\u2019où viennent vos points</div>
              <div class="row" style="gap:8px;flex-wrap:wrap">
                ${Object.entries(pr.detail).filter(([,v]) => Number(v) > 0)
                  .sort((a,b) => Number(b[1]) - Number(a[1]))
                  .map(([k,v]) => html`<span class="tag" key=${k}>${k} · ${v}</span>`)}
              </div>
            </div>`}

          <p class="small muted" style="margin-top:18px;margin-bottom:0">
            Ces points se recalculent à chaque lecture, à partir de vos
            formations, missions, responsabilités, tâches, heures et
            ancienneté. Rien n\u2019est figé : rien n\u2019est perdu non plus.
          </p>
        </div>
      </div>
    </div>`;
}


/* --- La carte d'adhérent -------------------------------------------------
   Le QR est dessiné à la main : un code de version fixe suffit pour un
   identifiant, et cela évite une bibliothèque de plus. Le jeton qu'il
   porte n'est pas l'identifiant du compte — le photographier ne donne
   accès à rien.
   --------------------------------------------------------------------- */
export function qrMatrice(texte){
  // Encodage QR version 4, correction L, mode octet. Suffisant pour un
  // identifiant de 36 caractères, et entièrement déterministe.
  const N = 33, T = 80;                       // 33 modules, 80 octets utiles
  const oct = [0x40 | (texte.length >> 4), ((texte.length & 15) << 4)];
  for (let i = 0; i < texte.length; i++){
    const c = texte.charCodeAt(i);
    oct[oct.length - 1] |= (c >> 4);
    oct.push((c & 15) << 4);
  }
  while (oct.length < T) oct.push(oct.length % 2 ? 0x11 : 0xEC);

  const m = Array.from({length:N}, () => Array(N).fill(null));
  const rep = (r,c) => {
    for (let i = -1; i <= 7; i++) for (let j = -1; j <= 7; j++){
      if (r+i < 0 || r+i >= N || c+j < 0 || c+j >= N) continue;
      m[r+i][c+j] = (i>=0&&i<=6&&(j===0||j===6)) || (j>=0&&j<=6&&(i===0||i===6))
                 || (i>=2&&i<=4&&j>=2&&j<=4);
    }
  };
  rep(0,0); rep(0,N-7); rep(N-7,0);
  for (let i = 8; i < N-8; i++){ m[6][i] = i % 2 === 0; m[i][6] = i % 2 === 0; }
  for (let i = -2; i <= 2; i++) for (let j = -2; j <= 2; j++)
    m[N-7+i][N-7+j] = Math.max(Math.abs(i), Math.abs(j)) !== 1;

  let bit = 0, haut = true;
  for (let col = N-1; col > 0; col -= 2){
    if (col === 6) col--;
    for (let k = 0; k < N; k++){
      const row = haut ? N-1-k : k;
      for (let d = 0; d < 2; d++){
        const c = col - d;
        if (m[row][c] !== null) continue;
        let v = bit < T*8 ? ((oct[bit >> 3] >> (7 - (bit & 7))) & 1) === 1 : false;
        if ((row + c) % 2 === 0) v = !v;      // masque 0
        m[row][c] = v; bit++;
      }
    }
    haut = !haut;
  }
  return m;
}


export function CarteAdherent(){
  const [c, setC] = useState(null);
  const [grand, setGrand] = useState(false);
  const [msg, setMsg] = useState('');

  const charger = useCallback(() =>
    db.rpc('ma_carte').then(({data}) => setC(data)), []);
  useEffect(() => { charger(); }, [charger]);
  if (!c) return null;

  const m = qrMatrice(String(c.jeton));
  const N = m.length, cote = grand ? 260 : 128;

  return html`
    <div class="panneau" style="margin-bottom:24px;overflow:hidden">
      <div class=${'corps'} style=${'background:var(--nuit);color:#fff;'
        + 'display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap'}>
        <div style="flex:1;min-width:220px">
          <div class="eyebrow" style="color:rgba(255,255,255,.6)">
            Fédération française pour la citoyenneté et l\u2019égalité des chances</div>
          <div style="font-size:22px;font-weight:700;margin-top:8px">${c.nom}</div>
          <div style="opacity:.8;margin-top:4px">${c.fonction} · ${c.echelon}</div>
          <div style="opacity:.6;font-size:14px;margin-top:2px">${c.territoire}</div>
          <div class="mono" style="opacity:.6;font-size:13px;margin-top:8px">
            ${c.matricule}</div>
          ${(c.postes||[]).length > 0 && html`
            <div class="row" style="gap:5px;margin-top:10px;flex-wrap:wrap">
              ${c.postes.map((x,i) => html`
                <span key=${i} style=${'font-size:12px;padding:2px 8px;border-radius:20px;'
                  + 'background:rgba(255,255,255,.14)'}>${x}</span>`)}
            </div>`}
          <div style="margin-top:12px;font-size:13px;opacity:.75">
            ${c.valide
              ? 'Adhésion à jour' + (c.depuis ? ' depuis le ' + jour(c.depuis) : '')
              : 'Adhésion non validée — cette carte n\u2019a pas cours'}
          </div>
        </div>

        <div style="text-align:center">
          <div style=${'background:#fff;padding:8px;border-radius:6px;cursor:pointer'}
            onClick=${()=>setGrand(!grand)}>
            <svg viewBox=${'0 0 ' + N + ' ' + N} width=${cote} height=${cote}
              shape-rendering="crispEdges" style="display:block">
              <rect width=${N} height=${N} fill="#fff" />
              ${m.map((ligne,y) => ligne.map((v,x) => v
                ? html`<rect key=${y+'-'+x} x=${x} y=${y} width="1" height="1"
                    fill="#1E2A38" />` : null))}
            </svg>
          </div>
          <div style="font-size:11px;opacity:.6;margin-top:6px">
            ${grand ? 'Toucher pour réduire' : 'Toucher pour agrandir'}</div>
        </div>
      </div>

      <div class="corps small muted">
        Présentez ce code à l\u2019accueil d\u2019une assemblée : il constate votre
        présence, rien d\u2019autre. Il ne donne accès ni à votre compte ni à vos
        données. Si votre carte a circulé,
        <a href="#" onClick=${async e=>{
          e.preventDefault();
          const { data } = await db.rpc('regenerer_jeton_carte');
          if (data?.ok){ setMsg('Nouveau code généré : l\u2019ancien ne vaut plus rien.');
            charger(); }
        }}>générez-en un nouveau</a> — l\u2019ancien cesse aussitôt de valoir.
        ${msg && html`<div style="color:var(--vert);margin-top:6px">${msg}</div>`}
      </div>
    </div>`;
}
