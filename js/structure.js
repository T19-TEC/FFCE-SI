import { EquipesLocales, Groupes } from './collectif.js';
import { Habilitations, Postes, Publier, RecueilListe } from './direction.js';
import { BilansMission, FicheOuverture, MesAlertesParcours, MesCreneaux, Tunnel } from './membre.js';
import { Info, Portrait, STATUT_PROJET, STATUT_PROP, TYPE_ACTE, db, h, html, jour, nomComplet, urlPublique, useCallback, useEffect, useState } from './socle.js';
import { Contact, Rejoindre } from './vitrine.js';

export function Structures({ setMsg, ouvrir }){
  const [echelle, setEchelle] = useState('departement');
  const [liste, setListe] = useState(null);
  const [q, setQ] = useState('');
  const [vacants, setVacants] = useState(false);

  useEffect(() => {
    setListe(null);
    db.rpc('etat_reseau', { p_echelle: echelle }).then(({data}) => setListe(data||[]));
  }, [echelle]);

  if (!liste) return html`<div class="vide">Chargement…</div>`;

  const filtre = liste
    .filter(x => !vacants || x.mandats_pourvus < 3)
    .filter(x => (x.territoire + ' ' + (x.parent||'')).toLowerCase().includes(q.toLowerCase()));

  const sansPersonne = liste.filter(x => x.membres === 0).length;
  const sansBureau = liste.filter(x => x.mandats_pourvus === 0).length;

  return html`
    <div>
      <div class="chiffres" style="margin:0 0 24px">
        <div><div class="n" style="font-size:30px">${liste.length}</div>
          <div class="l">Structures</div></div>
        <div><div class="n" style="font-size:30px">
          ${liste.reduce((n,x)=>n+x.actifs,0)}</div>
          <div class="l">Membres actifs</div></div>
        <div><div class="n" style="font-size:30px">${sansPersonne}</div>
          <div class="l">Sans aucun membre</div></div>
        <div><div class="n" style="font-size:30px">${sansBureau}</div>
          <div class="l">Sans bureau constitué</div></div>
      </div>

      <div class="row" style="margin-bottom:20px;gap:12px">
        <div class="field" style="width:auto;margin:0">
          <select value=${echelle} onChange=${e=>setEchelle(e.target.value)}>
            <option value="region">Régions</option>
            <option value="departement">Départements</option>
            <option value="local">Antennes locales</option>
          </select>
        </div>
        <div class="field" style="flex:1;min-width:200px;margin:0">
          <input placeholder="Rechercher…" value=${q} onInput=${e=>setQ(e.target.value)} />
        </div>
        <label class="row" style="text-transform:none;letter-spacing:0;font-size:13.5px;
            color:var(--nuit);margin:0;cursor:pointer;width:auto">
          <input type="checkbox" style="width:auto" checked=${vacants}
            onChange=${e=>setVacants(e.target.checked)} />
          <span>Bureaux incomplets seulement</span>
        </label>
      </div>

      <div class="panneau" style="overflow-x:auto">
        <table>
          <thead><tr>
            <th>Structure</th><th>Membres</th><th>Encadrants</th>
            <th>Président</th><th>Trésorier</th><th>Secrétaire</th>
            <th>Groupes</th><th>Heures ce mois</th>
          </tr></thead>
          <tbody>
            ${filtre.map(x => html`
              <tr>
                <td>
                  <div>${x.territoire}</div>
                  ${x.parent && html`<div class="small muted">${x.parent}</div>`}
                </td>
                <td class="mono">${x.actifs}${x.membres > x.actifs
                  ? html`<span class="small muted"> /${x.membres}</span>` : ''}</td>
                <td class="mono">${x.encadrants}</td>
                <td class="small">${x.president
                  || html`<span class="tag rouge">Vacant</span>`}</td>
                <td class="small">${x.tresorier
                  || html`<span class="tag">Vacant</span>`}</td>
                <td class="small">${x.secretaire
                  || html`<span class="tag">Vacant</span>`}</td>
                <td class="mono">${x.groupes}</td>
                <td class="mono">${Number(x.engagement_mois||0)} h</td>
              </tr>`)}
          </tbody>
        </table>
        ${filtre.length === 0 && html`<div class="vide">Aucun résultat.</div>`}
      </div>
      <p class="small muted" style="margin-top:12px;max-width:62ch">
        Les mandats de bureau se confient depuis la fiche d\u2019un membre, onglet
        Membres : postes Président, Trésorier et Secrétaire de structure, avec le
        territoire comme périmètre.
      </p>
    </div>`;
}

/* --- Postes et droits, réunis ----------------------------------------- */

/* =====================================================================
   PARCOURS ADHÉRENT
   Six marches, de l'inscription à la première mission. Chacune est
   datée par le système quand il peut la constater.
   ===================================================================== */

export function ParcoursAdherent({ p }){
  const [onglet, setOnglet] = useState('accueillir');
  const [liste, setListe] = useState([]);
  const [tunnel, setTunnel] = useState(null);
  const [creneaux, setCreneaux] = useState([]);
  const [rdv, setRdv] = useState([]);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    // On rafraîchit les jalons avant de lire : une étape constatable —
    // dossier complet, adhésion validée, formation acquise — ne doit pas
    // être périmée au moment où quelqu'un la regarde.
    await db.rpc('rafraichir_jalons');
    const [a,b,c,d] = await Promise.all([
      db.rpc('nouveaux_a_accueillir_maj', { p_territoire: null }),
      db.rpc('tunnel_benevole', { p_territoire: null, p_mois: 6 }),
      db.from('creneaux').select('*').eq('hote_id', p.id).is('annule_le', null)
        .gte('debut', new Date().toISOString()).order('debut'),
      db.rpc('mes_rendez_vous')
    ]);
    setListe(a.data||[]); setTunnel(b.data);
    setCreneaux(c.data||[]); setRdv(d.data||[]);
  }, [p.id]);
  useEffect(() => { charger(); }, [charger]);

  const enRetard = liste.filter(x => x.jours > 14);

  return html`
    <div>
      <div class="eyebrow">Parcours adhérent</div>
      <h1 style="margin:6px 0 8px">Accueillir</h1>
      <p class="muted" style="max-width:60ch">
        Personne ne doit se perdre entre l\u2019inscription et la première mission.
        Chaque étape se date d\u2019elle-même quand le système peut la constater.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:30px">${liste.length}</div>
          <div class="l">À accompagner</div></div>
        <div><div class="n" style="font-size:30px">${enRetard.length}</div>
          <div class="l">Sans réponse depuis 15 j</div></div>
        <div><div class="n" style="font-size:30px">
          ${rdv.filter(r=>!r.passe).length}</div>
          <div class="l">Rendez-vous à venir</div></div>
        <div><div class="n" style="font-size:30px">
          ${tunnel && tunnel.retention_6m !== null ? tunnel.retention_6m + ' %' : '—'}</div>
          <div class="l">Encore là à six mois</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['accueillir','À accompagner'],['repartir','Répartir'],
           ['bilans','Bilans de mission'],['rdv','Rendez-vous'],
           ['creneaux','Mes disponibilités'],['tunnel','Le tunnel']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'accueillir' && html`<${FileAccueil} liste=${liste}
        recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'repartir' && html`<${RepartirNouveaux} setMsg=${setMsg} />`}

      ${onglet === 'bilans' && html`<${BilansMission} setMsg=${setMsg} />`}

      ${onglet === 'rdv' && html`
        <div class="panneau">
          ${rdv.length === 0
            ? html`<div class="vide">Aucun rendez-vous.</div>`
            : rdv.map(r => html`
              <div class="ligne">
                <div>
                  <div>${r.avec} <span class="small muted">${r.avec_fonction||''}</span></div>
                  <div class="small muted">
                    ${new Date(r.debut).toLocaleString('fr-FR',
                      {weekday:'long',day:'numeric',month:'long',hour:'2-digit',minute:'2-digit'})}
                    · ${r.duree_min} min
                    ${r.lieu ? ' · ' + r.lieu : ''}
                  </div>
                  ${r.visio && html`<a class="small" href=${r.visio}
                    target="_blank" rel="noopener">Rejoindre en visioconférence ↗</a>`}
                </div>
                <div class="row">
                  ${r.passe
                    ? html`<span class="tag">Passé</span>`
                    : html`<button class="btn sm light" onClick=${async ()=>{
                        const m = prompt('Motif de l\u2019annulation') || '';
                        await db.rpc('annuler_creneau', { p_creneau: r.id, p_motif: m });
                        charger();
                      }}>Annuler</button>`}
                </div>
              </div>`)}
        </div>`}

      ${onglet === 'creneaux' && html`<${MesCreneaux} p=${p} creneaux=${creneaux}
        recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'tunnel' && tunnel && html`<${Tunnel} t=${tunnel} />`}
    </div>`;
}


/* --- La file d'accueil -------------------------------------------------
   Une ligne, une action évidente. Ce qui n'a pas eu de nouvelles depuis
   une semaine remonte en tête, et on peut agir sur plusieurs personnes
   d'un coup : le suivi ne doit pas coûter plus cher que le geste qu'il
   enregistre.
   --------------------------------------------------------------------- */
/* --- Ce que les échelons supérieurs me signalent ---------------------- */


export function FileAccueil({ liste, recharger, setMsg }){
  const [choisis, setChoisis] = useState([]);
  const [ouvert, setOuvert] = useState(null);

  const basculer = id => setChoisis(c =>
    c.includes(id) ? c.filter(x => x !== id) : [...c, id]);

  async function agir(id, action, texte){
    const { data, error } = await db.rpc('agir_parcours',
      { p_profil: id, p_action: action, p_texte: texte || null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Enregistré.'); recharger();
  }

  async function agirGroupe(action, texte){
    if (choisis.length === 0) return;
    const { data, error } = await db.rpc('agir_parcours_groupe',
      { p_profils: choisis, p_action: action, p_texte: texte || null });
    if (error) return setMsg('Erreur : ' + error.message);
    setMsg(data.traites + ' membre(s) traité(s)' +
           (data.echecs ? ', ' + data.echecs + ' hors périmètre' : '') + '.');
    setChoisis([]); recharger();
  }

  const urgents = liste.filter(x => x.mon_role === 'responsable'
                                 && x.priorite <= 3);

  return html`
    <div>
      <${MesAlertesParcours} recharger=${recharger} />
      ${urgents.length > 0 && html`
        <div class="alerte" style="margin-bottom:16px;border-left-color:var(--bordeaux)">
          ${urgents.length} personne${urgents.length>1?'s':''} que vous accompagnez
          appelle${urgents.length>1?'nt':''} une action.
        </div>`}

      ${choisis.length > 0 && html`
        <div class="panneau" style="margin-bottom:16px;border-color:var(--action)">
          <div class="corps row" style="gap:10px">
            <span class="small"><strong>${choisis.length}</strong> sélectionné${choisis.length>1?'s':''}</span>
            <button class="btn sm" onClick=${()=>agirGroupe('prendre_en_charge')}>
              Je m\u2019en charge</button>
            <button class="btn sm light" onClick=${()=>{
              const t = prompt('Note commune (facultatif)');
              if (t !== null) agirGroupe('contact', t);
            }}>Marquer contactés</button>
            <button class="btn sm light" onClick=${()=>{
              const t = prompt('Objet de la relance (facultatif)');
              if (t !== null) agirGroupe('relancer', t);
            }}>Relancer</button>
            <button class="btn sm light" onClick=${()=>setChoisis([])}>Désélectionner</button>
          </div>
        </div>`}

      <div class="panneau">
        <div class="tete">
          <label class="row" style="text-transform:none;letter-spacing:0;margin:0;
              font-size:13px;color:var(--gris);cursor:pointer">
            <input type="checkbox" style="width:auto"
              checked=${choisis.length === liste.length && liste.length > 0}
              onChange=${e=>setChoisis(e.target.checked ? liste.map(x=>x.profil_id) : [])} />
            <span>Tout sélectionner</span>
          </label>
          <span class="tag">${liste.length}</span>
        </div>

        ${liste.length === 0
          ? html`<div class="vide">Personne n\u2019attend. C\u2019est bon signe.</div>`
          : liste.map(x => html`
            <div style=${'border-bottom:1px solid var(--filet);'+
                 (x.priorite <= 2 ? 'border-left:3px solid var(--bordeaux)' : '')}>
              <div class="ligne" style="border:0;align-items:flex-start">
                <input type="checkbox" style="width:auto;margin-top:4px"
                  checked=${choisis.includes(x.profil_id)}
                  onChange=${()=>basculer(x.profil_id)} />

                <div style="flex:1;min-width:230px;cursor:pointer"
                  onClick=${()=>setOuvert(ouvert===x.profil_id?null:x.profil_id)}>
                  <div class="row" style="gap:8px">
                    <strong>${x.membre}</strong>
                    <span class="tag">${x.etape_rang}/6 · ${x.etape}</span>
                    ${x.priorite <= 2 && html`
                      <span class="tag rouge">${x.jours} j</span>`}
                  </div>
                  <div class="small muted" style="margin-top:4px">
                    ${x.territoire || 'sans territoire'} · inscrit le ${jour(x.inscrit_le)}
                    ${x.referent ? ' · suivi par ' + x.referent : ''}
                  </div>
                  <div style="display:flex;gap:3px;margin-top:8px;max-width:220px">
                    ${[1,2,3,4,5,6].map(n => html`
                      <div style=${'height:4px;flex:1;background:'+
                        (n <= x.etape_rang ? 'var(--bleu)' : 'var(--filet)')}></div>`)}
                  </div>
                  ${x.prochaine_action && html`
                    <div class="small" style="margin-top:8px;color:var(--action)">
                      → ${x.prochaine_action}</div>`}
                </div>

                <div class="row" style="gap:6px">
                  ${x.email && html`<a class="btn sm light"
                    href=${'mailto:'+x.email+'?subject='+encodeURIComponent(
                      'Bienvenue à la FFCE')}
                    onClick=${()=>agir(x.profil_id,'contact','courriel envoyé')}>
                    Écrire</a>`}
                  ${x.telephone && html`<a class="btn sm light"
                    href=${'tel:'+x.telephone.replace(/\s/g,'')}
                    onClick=${()=>agir(x.profil_id,'contact','appel téléphonique')}>
                    Appeler</a>`}
                  ${x.etape_rang === 2 && html`<button class="btn sm"
                    onClick=${()=>agir(x.profil_id,'valider')}>Valider l\u2019adhésion</button>`}
                  ${!x.referent && html`<button class="btn sm light"
                    onClick=${()=>agir(x.profil_id,'prendre_en_charge')}>
                    Je m\u2019en charge</button>`}
                </div>
              </div>

              ${ouvert === x.profil_id && html`
                <div class="corps" style="background:var(--papier);padding-top:0">
                  <div class="row" style="gap:24px;align-items:flex-start;
                       padding-top:16px;border-top:1px solid var(--filet)">
                    <div style="flex:1;min-width:200px">
                      <div class="eyebrow" style="margin-bottom:8px">Coordonnées</div>
                      <div class="small"><span class="mono">${x.matricule}</span></div>
                      <div class="small">${x.email}</div>
                      ${x.telephone && html`<div class="small">${x.telephone}</div>`}
                    </div>
                    <div style="flex:1;min-width:200px">
                      <div class="eyebrow" style="margin-bottom:8px">Dossier</div>
                      <div class="jauge" style="margin:0;height:5px">
                        <i style=${'width:'+x.completude+'%;background:'+
                          (x.completude===100?'var(--valide)':'var(--brun)')}></i></div>
                      <div class="small muted" style="margin-top:6px">
                        ${x.completude} %${x.manques ? ' — manque ' + x.manques : ' — complet'}
                      </div>
                    </div>
                  </div>
                  ${x.rdv_le && html`<p class="small" style="margin:14px 0 0">
                    Rendez-vous le ${new Date(x.rdv_le).toLocaleString('fr-FR',
                      {weekday:'long',day:'numeric',month:'long',
                       hour:'2-digit',minute:'2-digit'})}</p>`}
                  ${x.notes && html`
                    <div style="margin-top:14px">
                      <div class="eyebrow" style="margin-bottom:6px">Suivi</div>
                      <div class="small" style="white-space:pre-wrap">${x.notes}</div>
                    </div>`}
                  <div class="row" style="margin-top:16px;gap:8px">
                    <button class="btn sm light" onClick=${()=>{
                      const t = prompt('Ajouter au suivi');
                      if (t) agir(x.profil_id,'contact',t);
                    }}>Ajouter une note</button>
                    <button class="btn sm light" onClick=${()=>{
                      const t = prompt('Pourquoi le parcours s\u2019arrête (obligatoire)');
                      if (t) agir(x.profil_id,'clore',t);
                    }}>Clore le parcours</button>
                    ${x.mon_role !== 'responsable' && x.accompagnant_id && html`
                      <button class="btn sm light" onClick=${async ()=>{
                        const m = prompt('Que voulez-vous signaler à ' +
                          x.accompagnant + ' ?');
                        if (!m) return;
                        const { data } = await db.rpc('signaler_a_accompagnant',
                          { p_profil: x.profil_id, p_message: m,
                            p_nature: 'observation' });
                        if (data && data.ok){
                          setMsg('Message transmis à l\u2019accompagnant.');
                          recharger();
                        }
                      }}>Signaler à l\u2019accompagnant</button>`}
                  </div>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}


/* =====================================================================
   PILOTAGE DU RÉSEAU
   Trois vues selon l'échelon : local, territorial, national.
   ===================================================================== */
export function Pilotage({ p }){
  const national = p.niveau >= 80;
  const [onglet, setOnglet] = useState(national ? 'national' : 'local');

  const vues = [['local','Mon terrain']];
  if (p.niveau >= 50) vues.push(['tunnel','Tunnel du bénévole']);
  if (p.niveau >= 60) vues.push(['structures','Structures']);
  if (national) vues.push(['national','Vue nationale']);

  return html`
    <div>
      <div class="eyebrow">Pilotage</div>
      <h1 style="margin:6px 0 8px">Où le réseau tient, où il lâche</h1>

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${vues.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'local'      && html`<${BordLocal} />`}
      ${onglet === 'tunnel'     && html`<${BordTunnel} p=${p} />`}
      ${onglet === 'structures' && html`<${Structures} setMsg=${()=>{}} ouvrir=${()=>{}} />`}
      ${onglet === 'national'   && html`<${BordNational} />`}
    </div>`;
}

/* --- Local : quatre choses, pas une de plus --------------------------- */

export function BordLocal(){
  const [b, setB] = useState(null);
  useEffect(() => { db.rpc('bord_local').then(({data}) => setB(data)); }, []);
  if (!b) return html`<div class="vide">Chargement…</div>`;

  return html`
    <div>
      <p class="muted" style="max-width:56ch;margin-bottom:24px">
        ${b.territoire || 'Votre territoire'} — quatre choses, rien de plus.
      </p>

      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:24px">
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Mes membres</h3></div>
          <div class="ligne"><span class="muted">Actifs</span>
            <span class="mono" style="font-size:16px">${b.membres.total}</span></div>
          <div class="ligne"><span class="muted">Arrivés ce mois</span>
            <span class="mono">${b.membres.nouveaux}</span></div>
          <div class="ligne">
            <span class="muted">À accueillir</span>
            <span class=${b.membres.a_accueillir > 0 ? 'tag rouge' : 'mono'}>
              ${b.membres.a_accueillir}</span></div>
        </div>

        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Ce qui attend une réponse</h3></div>
          ${(b.attentes||[]).length === 0
            ? html`<div class="corps small muted">Rien en attente.</div>`
            : b.attentes.map(x => html`
              <div class="ligne">
                <a href=${x.lien} class="small">${x.libelle}</a>
                <span class="pastille">${x.nombre}</span>
              </div>`)}
        </div>
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Mes actions à venir</h3></div>
        ${(b.actions||[]).length === 0
          ? html`<div class="vide">Aucune action programmée.</div>`
          : b.actions.map(a => html`
            <div class="ligne">
              <div>
                <div>${a.titre}</div>
                <div class="small muted">
                  ${a.debut ? jour(a.debut) : 'sans date'}${a.lieu ? ' · ' + a.lieu : ''}</div>
              </div>
              <span class="tag">${a.retenus}/${a.places} place${a.places>1?'s':''}</span>
            </div>`)}
      </div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Mes tâches</h3></div>
        ${(b.taches||[]).length === 0
          ? html`<div class="vide">Aucune tâche assignée.</div>`
          : b.taches.map(t => html`
            <div class="ligne">
              <div>
                <div>${t.titre}</div>
                <div class="small muted">${t.groupe}
                  ${t.echeance ? ' · ' + jour(t.echeance) : ''}</div>
              </div>
              <div class="row">
                ${t.retard && html`<span class="tag rouge">En retard</span>`}
                <a class="btn sm light" href=${'#/espace/groupe/'+t.groupe_id}>Ouvrir</a>
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function BordTunnel({ p }){
  const [t, setT] = useState(null);
  const [terr, setTerr] = useState([]);
  const [filtre, setFiltre] = useState('');
  const [mois, setMois] = useState('6');
  const [liste, setListe] = useState([]);

  useEffect(() => {
    db.from('territoires').select('id,nom,echelle')
      .in('echelle',['region','departement']).eq('actif',true).order('nom')
      .then(({data}) => setTerr(data||[]));
  }, []);
  useEffect(() => {
    db.rpc('tunnel_benevole', { p_territoire: filtre||null, p_mois: Number(mois) })
      .then(({data}) => setT(data));
    db.rpc('nouveaux_a_accueillir', { p_territoire: filtre||null })
      .then(({data}) => setListe(data||[]));
  }, [filtre, mois]);

  return html`
    <div>
      <div class="row" style="margin-bottom:24px;gap:12px">
        <div class="field" style="width:auto;margin:0">
          <label>Périmètre</label>
          <select value=${filtre} onChange=${e=>setFiltre(e.target.value)}>
            <option value="">Mon périmètre</option>
            ${terr.map(x => html`<option value=${x.id}>${x.nom}</option>`)}
          </select>
        </div>
        <div class="field" style="width:auto;margin:0">
          <label>Sur</label>
          <select value=${mois} onChange=${e=>setMois(e.target.value)}>
            <option value="3">3 mois</option><option value="6">6 mois</option>
            <option value="12">12 mois</option><option value="24">24 mois</option>
          </select>
        </div>
      </div>

      ${t && html`<${Tunnel} t=${t} />`}

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Qui attend, et quoi</h3>
          <span class="tag">${liste.length}</span></div>
        ${liste.length === 0
          ? html`<div class="vide">Personne en attente.</div>`
          : liste.slice(0,40).map(x => html`
            <div class="ligne">
              <div style="flex:1;min-width:220px">
                <div>${x.membre} <span class="tag">${x.etape}</span></div>
                <div class="small muted">
                  ${x.territoire||''} · inscrit il y a ${x.jours} jour${x.jours>1?'s':''}
                  ${x.referent ? ' · suivi par ' + x.referent : ' · sans référent'}
                </div>
                ${x.prochaine_action && html`<div class="small"
                  style="color:var(--action);margin-top:4px">→ ${x.prochaine_action}</div>`}
              </div>
              ${x.jours > 14 && html`<span class="tag rouge">Relancer</span>`}
            </div>`)}
      </div>
    </div>`;
}

/* --- National : on ne regarde que ce qui va mal ----------------------- */

export function BordNational(){
  const [b, setB] = useState(null);
  const [exc, setExc] = useState([]);
  useEffect(() => {
    db.rpc('bord_national').then(({data}) => setB(data));
    db.rpc('exceptions_reseau').then(({data}) => setExc(data||[]));
  }, []);
  if (!b) return html`<div class="vide">Chargement…</div>`;
  if (b.erreur) return html`<div class="alerte err">${b.erreur}</div>`;

  const a = b.alertes;
  const cartes = [
    ['Structures sans président élu', a.structures_sans_president, '#/espace/habilitations', true],
    ['Structures sans aucun membre', a.structures_vides, '#/espace/habilitations', true],
    ['Structures sans action depuis 6 mois', a.structures_inactives, '#/espace/habilitations', true],
    ['Mandats échus', a.mandats_echus, '#/espace/assemblees', true],
    ['Mandats à renouveler sous 6 mois', a.mandats_proches, '#/espace/assemblees', false],
    ['Habilitations expirant sous 90 jours', a.habilitations_expirantes, '#/espace/habilitations', false],
    ['Accès ouverts jamais utilisés', a.acces_dormants, '#/espace/habilitations', false],
    ['Encadrants sans formation aux outils', a.formation_accueil_manquante, '#/espace/pilotage', false],
    ['Actes en attente de contrôle', a.actes_a_controler, '#/espace/validation', true],
    ['Dossiers disciplinaires ouverts', a.dossiers_disciplinaires, '#/espace/discipline', false]
  ].filter(x => x[1] > 0);

  return html`
    <div>
      <div class="chiffres" style="margin:0 0 24px">
        <div><div class="n" style="font-size:30px">${b.membres_actifs}</div>
          <div class="l">Membres actifs</div></div>
        <div><div class="n" style="font-size:30px">${b.nouveaux_30j}</div>
          <div class="l">Arrivés ce mois</div></div>
        <div><div class="n" style="font-size:30px">${b.departements_couverts}</div>
          <div class="l">Départements couverts</div></div>
        <div><div class="n" style="font-size:30px">${Number(b.heures_mois||0)}</div>
          <div class="l">Heures ce mois</div></div>
      </div>

      <div class="spread" style="margin-bottom:12px">
        <div class="row" style="gap:8px">
          <h2 style="font-size:22px">Ce qui appelle une décision</h2>
          <${Info} texte="Le national ne regarde pas les 101 départements : il regarde ceux qui vont mal. Cette liste ne montre que les écarts, et disparaît quand tout va bien." />
        </div>
      </div>

      ${cartes.length === 0
        ? html`<div class="panneau"><div class="vide">
            Aucune alerte. Le réseau est en ordre.</div></div>`
        : html`
          <div class="tuiles">
            ${cartes.map(([nom, n, lien, urgent]) => html`
              <a class="tuile" href=${lien} style=${'border-top:3px solid '+
                  (urgent?'var(--bordeaux)':'var(--brun)')}>
                <div style=${'font-family:var(--titre);font-weight:900;font-size:32px;'+
                  'line-height:1;color:'+(urgent?'var(--bordeaux)':'var(--brun)')}>${n}</div>
                <p style="margin-top:8px">${nom}</p>
              </a>`)}
          </div>`}

      ${exc.length > 0 && html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">Structures à reprendre</h3>
            <span class="tag rouge">${exc.length}</span></div>
          <div style="overflow-x:auto">
            <table>
              <thead><tr><th>Structure</th><th>Rattachement</th>
                <th>Membres</th><th>Constat</th></tr></thead>
              <tbody>
                ${exc.slice(0,40).map(x => html`
                  <tr>
                    <td>${x.territoire}</td>
                    <td class="small muted">${x.parent||'—'}</td>
                    <td class="mono">${x.membres}</td>
                    <td><span class=${'tag '+(x.gravite<=2?'rouge':'or')}>${x.alerte}</span></td>
                  </tr>`)}
              </tbody>
            </table>
          </div>
        </div>`}

      <${PropositionsNationales} setMsg=${()=>{}} />

      <div style="margin-top:24px"><${Tunnel} t=${b.tunnel} compact=${true} /></div>

      <div class="panneau" style="margin-top:24px">
        <div class="tete"><h3 style="font-size:17px">Répartition par région</h3></div>
        <div class="corps">
          ${(b.top_regions||[]).map(r => {
            const max = Math.max(...(b.top_regions||[{membres:1}]).map(x=>x.membres));
            return html`
              <div style="padding:6px 0">
                <div class="spread small"><span>${r.nom}</span>
                  <span class="mono">${r.membres}</span></div>
                <div class="jauge" style="margin-top:5px">
                  <i style=${'width:'+Math.round(r.membres/Math.max(max,1)*100)+
                    '%;background:var(--bleu)'}></i></div>
              </div>`;
          })}
        </div>
      </div>
    </div>`;
}

/* --- Prendre rendez-vous, côté nouvel adhérent ------------------------ */


export function MonComite({ p, apps }){
  const [c, setC] = useState(null);
  const [onglet, setOnglet] = useState('vie');
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const { data } = await db.rpc('mon_comite', { p_territoire: null });
    setC(data);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  if (!c) return html`<div class="vide">Chargement…</div>`;
  const t = c.territoire || {};
  // Les publications à relayer se lisent là où l'équipe locale regarde
  // déjà, plutôt que sous une direction dont elle ne voit rien d'autre.
  const peutRelayer = (apps||[]).some(a => a.code === 'publier' && a.ouvert);

  return html`
    <div>
      <div class="eyebrow">Mon comité</div>
      <h1 style="margin:6px 0 4px">${t.nom || 'Votre territoire'}</h1>
      <p class="muted">${t.chemin || ''}</p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:30px">${c.effectif.actifs}</div>
          <div class="l">Membres actifs</div></div>
        <div><div class="n" style="font-size:30px">${c.effectif.nouveaux_30j}</div>
          <div class="l">Arrivés ce mois</div></div>
        <div><div class="n" style="font-size:30px">
          ${(c.projets||[]).filter(x=>x.statut==='en_cours').length}</div>
          <div class="l">Projets en cours</div></div>
        <div><div class="n" style="font-size:30px">${Number(c.effectif.heures_mois||0)}</div>
          <div class="l">Heures ce mois</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['vie','La vie du comité'],['projets','Projets'],
           ['propositions','Propositions'],['equipe','Qui anime'],
           ['equipes','Équipes'],
           ...(peutRelayer ? [['relayer','À relayer']] : [])]
          .map(([k,lab]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${lab}${k==='propositions'&&(c.propositions||[]).length
              ? ' ('+c.propositions.length+')' : ''}</button>`)}
      </div>

      ${onglet === 'relayer' && html`<${Publier} p=${p} />`}

      ${onglet === 'equipes' && html`
        <div>
          <p class="muted" style="max-width:60ch;margin:0 0 4px">
            Le pendant local des groupes de travail : une équipe de structure
            réunit quelques personnes autour d\u2019un projet, avec ses documents
            et ses tâches. Elle se propose, se valide, et se dissout quand
            l\u2019objet est atteint.
          </p>
          <${EquipesLocales} p=${p} apps=${apps} territoire=${t.id} setMsg=${setMsg} />
        </div>`}

      ${onglet === 'vie' && html`
        <div>
          <div class="panneau">
            <div class="tete"><h3 style="font-size:17px">Ce qui arrive</h3></div>
            ${(c.agenda||[]).length === 0
              ? html`<div class="vide">Rien de programmé pour l\u2019instant.</div>`
              : (c.agenda||[]).map(x => html`
                <a class="ligne" href=${x.lien} style="color:var(--nuit)">
                  <div style="flex:1;min-width:200px">
                    <div class="row" style="gap:8px">
                      <span>${x.titre}</span>
                      <span class="tag">${x.type === 'mission' ? 'Mission'
                        : x.type === 'assemblee' ? 'Assemblée' : 'Projet'}</span>
                    </div>
                    <div class="small muted">
                      ${x.date ? new Date(x.date).toLocaleDateString('fr-FR',
                        {weekday:'long',day:'numeric',month:'long'}) : ''}
                      ${x.lieu ? ' · ' + x.lieu : ''}</div>
                  </div>
                </a>`)}
          </div>

          ${(c.a_relayer||[]).length > 0 && html`
            <div class="panneau" style="margin-top:24px;border-left:3px solid var(--framboise)">
              <div class="tete">
                <div class="row" style="gap:8px">
                  <h3 style="font-size:17px">À relayer sur vos réseaux</h3>
                  <${Info} texte="La direction de la communication a préparé ces publications. Adaptez-les à ce qui s'est passé chez vous, et publiez." />
                </div>
                <a class="btn sm" href="#/espace/publier">Ouvrir</a>
              </div>
              ${(c.a_relayer||[]).slice(0,4).map(x => html`
                <a class="ligne" href="#/espace/publier" style="color:var(--nuit)">
                  ${x.visuel && html`<img src=${urlPublique(x.visuel)} alt=""
                    style="width:48px;height:48px;object-fit:cover;flex:0 0 48px;
                           border:1px solid var(--filet)" />`}
                  <div style="flex:1;min-width:200px">
                    <div class="row" style="gap:8px">
                      <span>${x.titre}</span>
                      ${x.priorite === 'urgente' && html`
                        <span class="tag rouge">Sans délai</span>`}
                    </div>
                    <div class="small muted">${x.contexte || ''}
                      ${x.a_publier_le ? ' · vers le ' + jour(x.a_publier_le) : ''}</div>
                  </div>
                </a>`)}
            </div>`}

          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">Projets en cours</h3></div>
            ${(c.projets||[]).filter(x=>x.statut==='en_cours').length === 0
              ? html`<div class="vide">Aucun projet en cours.</div>`
              : (c.projets||[]).filter(x=>x.statut==='en_cours').map(pj => html`
                <div class="ligne">
                  <div style="flex:1;min-width:220px">
                    <div>${pj.titre}</div>
                    <div class="small muted">${pj.responsable || 'sans responsable'}
                      · ${pj.participants} participant${pj.participants>1?'s':''}</div>
                    <div class="jauge" style="margin-top:8px;max-width:200px">
                      <i style=${'width:'+pj.avancement+'%;background:var(--valide)'}></i></div>
                  </div>
                  <span class="mono">${pj.avancement} %</span>
                </div>`)}
          </div>
        </div>`}

      ${onglet === 'projets' && html`<${ProjetsComite} c=${c} p=${p}
        recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'propositions' && html`<${PropositionsComite} c=${c}
        recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'equipe' && html`
        <div>
          <div class="panneau">
            <div class="tete"><h3 style="font-size:17px">Le bureau</h3></div>
            ${(c.bureau||[]).length === 0
              ? html`<div class="corps small muted">
                  Aucun bureau constitué. Une assemblée peut être convoquée pour
                  élire un président, un trésorier et un secrétaire.</div>`
              : (c.bureau||[]).map(b => html`
                <div class="ligne">
                  <div class="row" style="gap:14px">
                    <${Portrait} chemin=${b.photo} nom=${b.nom} taille=${44} />
                    <div>
                      <div>${b.nom}</div>
                      <div class="small muted">${b.poste}
                        · depuis le ${jour(b.depuis)}
                        ${b.jusqu_au ? ' · mandat jusqu\u2019au ' + jour(b.jusqu_au) : ''}</div>
                    </div>
                  </div>
                  <span class="insigne">${b.echelon}</span>
                </div>`)}
          </div>

          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">L\u2019encadrement</h3>
              <span class="tag">${(c.encadrement||[]).length}</span></div>
            ${(c.encadrement||[]).length === 0
              ? html`<div class="vide">Aucun encadrant sur ce territoire.</div>`
              : (c.encadrement||[]).map(e => html`
                <div class="ligne">
                  <div class="row" style="gap:14px">
                    <${Portrait} chemin=${e.photo} nom=${e.nom} taille=${38} />
                    <div>
                      <div>${e.nom}</div>
                      <div class="small muted">${e.fonction}
                        ${e.territoire ? ' · ' + e.territoire : ''}</div>
                    </div>
                  </div>
                  <a class="btn sm light" href="#/espace/messagerie">Écrire</a>
                </div>`)}
          </div>

          <${NommerLocal} p=${p} territoire=${t.id} setMsg=${setMsg} />
        </div>`}
    </div>`;
}


export function ProjetsComite({ c, p, recharger, setMsg }){
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({titre:'', objet:'', lieu:'', debut:'', fin:'',
                              statut:'idee', avancement:'0', public:'', partenaires:''});

  async function enregistrer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('enregistrer_projet', {
      p_id: null, p_titre: f.titre, p_objet: f.objet || null,
      p_lieu: f.lieu || null, p_debut: f.debut || null, p_fin: f.fin || null,
      p_statut: f.statut, p_avancement: Number(f.avancement||0),
      p_public: f.public || null, p_partenaires: f.partenaires || null,
      p_budget: null, p_territoire: null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'', objet:'', lieu:'', debut:'', fin:'', statut:'idee',
          avancement:'0', public:'', partenaires:''});
    setOuvert(false); setMsg('Projet créé.'); recharger();
  }

  async function avancer(pj, val){
    await db.rpc('enregistrer_projet', {
      p_id: pj.id, p_titre: pj.titre, p_objet: pj.objet, p_lieu: pj.lieu,
      p_debut: pj.debut, p_fin: pj.fin, p_statut: pj.statut,
      p_avancement: Number(val), p_public: null, p_partenaires: null,
      p_budget: null, p_territoire: null
    });
    recharger();
  }

  const peutCreer = p.niveau >= 40 || c.je_pilote;

  return html`
    <div>
      ${peutCreer && html`
        <div class="spread" style="margin-bottom:16px">
          <span class="small muted">${(c.projets||[]).length} projet(s)</span>
          <button class="btn sm" onClick=${()=>setOuvert(o=>!o)}>
            ${ouvert ? 'Annuler' : 'Nouveau projet'}</button>
        </div>`}

      ${ouvert && html`
        <form onSubmit=${enregistrer} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Intitulé</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field"><label>De quoi s\u2019agit-il</label>
              <textarea value=${f.objet}
                onInput=${e=>setF(o=>({...o,objet:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:160px;margin:0"><label>Lieu</label>
                <input value=${f.lieu} onInput=${e=>setF(o=>({...o,lieu:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Début</label>
                <input type="date" value=${f.debut}
                  onInput=${e=>setF(o=>({...o,debut:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:140px;margin:0"><label>Fin</label>
                <input type="date" value=${f.fin}
                  onInput=${e=>setF(o=>({...o,fin:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Public visé</label>
              <input value=${f.public} placeholder="Collégiens, quartier des Tilleuls…"
                onInput=${e=>setF(o=>({...o,public:e.target.value}))} /></div>
            <div class="field"><label>Partenaires</label>
              <input value=${f.partenaires}
                onInput=${e=>setF(o=>({...o,partenaires:e.target.value}))} /></div>
            <div class="field"><label>État</label>
              <select value=${f.statut} onChange=${e=>setF(o=>({...o,statut:e.target.value}))}>
                ${Object.entries(STATUT_PROJET).filter(([k])=>k!=='abandonne')
                  .map(([k,v]) => html`<option value=${k}>${v[0]}</option>`)}
              </select></div>
            <div><button class="btn">Créer</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${(c.projets||[]).length === 0
          ? html`<div class="vide">Aucun projet. C\u2019est peut-être le moment
              d\u2019en proposer un.</div>`
          : (c.projets||[]).map(pj => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px">
                  <strong>${pj.titre}</strong>
                  <span class=${'tag '+(STATUT_PROJET[pj.statut]||['',''])[1]}>
                    ${(STATUT_PROJET[pj.statut]||[pj.statut,''])[0]}</span>
                </div>
                ${pj.objet && html`<div class="small muted"
                  style="margin-top:4px;max-width:56ch">${pj.objet}</div>`}
                <div class="small muted" style="margin-top:4px">
                  <span class="mono">${pj.reference}</span>
                  ${pj.responsable ? ' · ' + pj.responsable : ''}
                  ${pj.lieu ? ' · ' + pj.lieu : ''}
                  ${pj.debut ? ' · ' + jour(pj.debut) : ''}
                  · ${pj.participants} participant${pj.participants>1?'s':''}
                </div>
                <div class="row" style="margin-top:10px;gap:10px;align-items:center">
                  <div class="jauge" style="flex:1;max-width:180px;margin:0">
                    <i style=${'width:'+pj.avancement+'%;background:var(--valide)'}></i></div>
                  ${c.je_pilote
                    ? html`<input type="range" min="0" max="100" step="10"
                        value=${pj.avancement} style="width:140px;padding:0;
                        accent-color:var(--valide)"
                        onChange=${e=>avancer(pj, e.target.value)} />`
                    : ''}
                  <span class="mono small">${pj.avancement} %</span>
                </div>
              </div>
              <button class=${'btn sm '+(pj.je_participe?'light':'')}
                onClick=${async ()=>{
                  await db.rpc('rejoindre_projet', { p_projet: pj.id, p_role: 'participant' });
                  recharger();
                }}>${pj.je_participe ? 'Je me retire' : 'Je participe'}</button>
            </div>`)}
      </div>
    </div>`;
}


export function PropositionsComite({ c, recharger, setMsg }){
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({titre:'', description:'', besoin:'', public:''});

  async function envoyer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('proposer', {
      p_titre: f.titre, p_description: f.description,
      p_besoin: f.besoin || null, p_public: f.public || null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'', description:'', besoin:'', public:''});
    setOuvert(false); setMsg('Proposition déposée. Votre responsable local vous répondra.');
    recharger();
  }

  async function soutenir(pr){
    await db.rpc('soutenir', { p_proposition: pr.id });
    recharger();
  }

  async function statuer(pr, statut){
    const reponse = prompt(statut === 'ecartee'
      ? 'Expliquez à l\u2019auteur pourquoi (obligatoire)'
      : 'Votre réponse à l\u2019auteur (obligatoire)');
    if (!reponse) return;
    const projet = statut === 'retenue'
      && confirm('Créer un projet à partir de cette proposition ?');
    const { data, error } = await db.rpc('statuer_proposition', {
      p_id: pr.id, p_statut: statut, p_reponse: reponse, p_creer_projet: projet
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg(data.projet_id ? 'Proposition retenue et projet créé.' : 'Réponse enregistrée.');
    recharger();
  }

  async function remonter(pr){
    const motif = prompt(
      'Pourquoi cette idée mérite-t-elle d\u2019être généralisée ? (obligatoire)');
    if (!motif) return;
    const { data, error } = await db.rpc('faire_remonter', { p_id: pr.id, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Proposition transmise au national.'); recharger();
  }

  const props = c.propositions || [];

  return html`
    <div>
      <div class="spread" style="margin-bottom:16px">
        <p class="small muted" style="margin:0;max-width:44ch">
          Une idée pour votre territoire ? Proposez-la. Votre responsable local
          vous répondra, et ce qui mérite d\u2019être généralisé remonte au national.
        </p>
        <button class="btn" onClick=${()=>setOuvert(o=>!o)}>
          ${ouvert ? 'Annuler' : 'Proposer une idée'}</button>
      </div>

      ${ouvert && html`
        <form onSubmit=${envoyer} class="panneau" style="margin-bottom:24px">
          <div class="corps stack">
            <div class="field"><label>Votre idée, en une ligne</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))}
                placeholder="Un atelier d\u2019éducation aux médias au collège Voltaire" /></div>
            <div class="field"><label>Ce que vous proposez</label>
              <textarea required value=${f.description} style="min-height:110px"
                onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
            <div class="field"><label>À qui cela s\u2019adresse</label>
              <input value=${f.public}
                onInput=${e=>setF(o=>({...o,public:e.target.value}))} /></div>
            <div class="field"><label>Ce qu\u2019il faudrait</label>
              <textarea value=${f.besoin}
                onInput=${e=>setF(o=>({...o,besoin:e.target.value}))}
                placeholder="Des bénévoles, une salle, un partenariat…" /></div>
            <div><button class="btn">Déposer</button></div>
          </div>
        </form>`}

      <div class="panneau">
        ${props.length === 0
          ? html`<div class="vide">Aucune proposition. Lancez-vous.</div>`
          : props.map(pr => html`
            <div class="ligne" style="align-items:flex-start">
              <button class=${'btn sm '+(pr.je_soutiens?'':'light')}
                style="flex-direction:column;min-width:56px;padding:8px 6px"
                onClick=${()=>soutenir(pr)}>
                <span style="font-family:var(--titre);font-weight:900;font-size:17px;
                  display:block;line-height:1">${pr.soutiens}</span>
                <span style="font-size:9.5px;letter-spacing:.04em">
                  ${pr.je_soutiens ? 'soutenu' : 'soutenir'}</span>
              </button>

              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <strong>${pr.titre}</strong>
                  <span class=${'tag '+(STATUT_PROP[pr.statut]||['',''])[1]}>
                    ${(STATUT_PROP[pr.statut]||[pr.statut,''])[0]}</span>
                  ${pr.mienne && html`<span class="tag bleu">La vôtre</span>`}
                </div>
                <p class="small" style="margin:8px 0 0;max-width:58ch">${pr.description}</p>
                ${pr.besoin && html`<p class="small muted" style="margin:6px 0 0">
                  Il faudrait : ${pr.besoin}</p>`}
                <div class="small muted" style="margin-top:6px">
                  ${pr.auteur} · ${jour(pr.cree_le)}
                  · <span class="mono">${pr.reference}</span>
                </div>
                ${pr.reponse && html`
                  <div class="small" style="margin-top:10px;padding:10px;
                       background:var(--papier);border-radius:2px">
                    <strong>Réponse :</strong> ${pr.reponse}</div>`}
              </div>

              ${c.je_pilote && ['deposee','a_l_etude'].includes(pr.statut) && html`
                <div class="row" style="gap:6px">
                  <button class="btn sm" onClick=${()=>statuer(pr,'retenue')}>Retenir</button>
                  <button class="btn sm light" onClick=${()=>remonter(pr)}>
                    Faire remonter</button>
                  <button class="btn sm light" onClick=${()=>statuer(pr,'ecartee')}>
                    Écarter</button>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}

/* --- Ce qui remonte, côté national ------------------------------------ */

export function PropositionsNationales({ setMsg }){
  const [liste, setListe] = useState([]);
  const charger = useCallback(() =>
    db.rpc('propositions_remontees').then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);
  if (liste.length === 0) return null;

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Idées remontées du terrain</h3>
          <${Info} texte="Des propositions qu'un responsable local a jugées généralisables. C'est le canal qui manque le plus souvent : les bonnes idées meurent à l'échelon local faute de chemin pour monter." />
        </div>
        <span class="tag or">${liste.length}</span>
      </div>
      ${liste.map(x => html`
        <div class="ligne" style="align-items:flex-start">
          <div style="flex:1;min-width:240px">
            <div class="row" style="gap:8px">
              <strong>${x.titre}</strong>
              <span class="tag or">${x.soutiens} soutien${x.soutiens>1?'s':''}</span>
            </div>
            <p class="small" style="margin:8px 0 0;max-width:58ch">${x.description}</p>
            <div class="small muted" style="margin-top:6px">
              ${x.auteur}${x.territoire ? ' · ' + x.territoire : ''}
              · remontée par ${x.remontee_par} le ${jour(x.remontee_le)}
            </div>
            ${x.motif_remontee && html`
              <div class="small" style="margin-top:8px;padding:10px;
                   background:var(--papier);border-radius:2px">
                <strong>Pourquoi :</strong> ${x.motif_remontee}</div>`}
          </div>
        </div>`)}
    </div>`;
}

export function RepartirNouveaux({ setMsg }){
  const [liste, setListe] = useState([]);
  const [gens, setGens] = useState([]);
  const charger = useCallback(async () => {
    await db.rpc('rafraichir_jalons');
    const [a,b] = await Promise.all([
      db.rpc('nouveaux_a_repartir'),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom,territoire_nom')
        .eq('statut','actif').order('nom')
    ]);
    setListe(a.data||[]); setGens(b.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function affecter(x, id){
    const { data, error } = await db.rpc('affecter_accompagnant',
      { p_profil: x.profil_id, p_accompagnant: id, p_motif: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Accompagnant désigné.'); charger();
  }

  const orphelins = liste.filter(x => x.priorite === 1);

  return html`
    <div>
      ${orphelins.length > 0 && html`
        <div class="alerte err" style="margin-bottom:16px">
          <strong>${orphelins.length} adhérent${orphelins.length>1?'s':''} sans bureau local
          ni accompagnant.</strong> C\u2019est là qu\u2019on perd les gens : désignez
          quelqu\u2019un, même hors du département.
        </div>`}

      <div class="panneau">
        ${liste.length === 0
          ? html`<div class="vide">Tout le monde est accompagné.</div>`
          : liste.map(x => html`
            <div class="ligne" style=${x.priorite===1
              ? 'border-left:3px solid var(--bordeaux)' : ''}>
              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <strong>${x.membre}</strong>
                  ${!x.bureau_local && html`<span class="tag rouge">Sans bureau local</span>`}
                  ${x.jours > 14 && html`<span class="tag or">${x.jours} jours</span>`}
                </div>
                <div class="small muted">
                  <span class="mono">${x.matricule}</span>
                  · ${x.territoire || 'sans territoire'}
                  · inscrit le ${jour(x.inscrit_le)}
                </div>
              </div>
              <div style="min-width:220px">
                <select value=${x.accompagnant_id||''}
                  onChange=${e=>e.target.value && affecter(x, e.target.value)}>
                  <option value="">Désigner un accompagnant…</option>
                  ${gens.map(g => html`<option value=${g.id}>
                    ${nomComplet(g)}${g.territoire_nom ? ' · '+g.territoire_nom : ''}</option>`)}
                </select>
              </div>
            </div>`)}
      </div>
    </div>`;
}

/* --- Ma chaîne : qui dépend de qui ------------------------------------- */


/* --- Nommer dans sa structure ------------------------------------------
   La liste des postes vient de `postes_conferables` : l'écran ne peut
   pas proposer ce que la base refusera. Si elle est vide, on le dit.
   --------------------------------------------------------------------- */
export function NommerLocal({ p, territoire, setMsg }){
  const [postes, setPostes] = useState([]);
  const [gens, setGens] = useState([]);
  const [noms, setNoms] = useState([]);
  const [f, setF] = useState({ profil:'', poste:'', fin:'', motif:'' });
  const [ouvert, setOuvert] = useState(false);
  const [fiche, setFiche] = useState(null);

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('postes_conferables', { p_territoire: territoire || null }),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom,territoire_nom,photo_url')
        .eq('statut','actif').order('nom')
    ]);
    setPostes(a.data||[]); setGens(b.data||[]);
    // Sans territoire, il n'y a pas de nominations locales à lister — et
    // une chaîne vide n'est pas un identifiant valide.
    if (!territoire){ setNoms([]); return; }
    const { data } = await db.from('nominations')
      .select('id,poste,fin,cree_le,profil_id,territoire_id,postes(nom,rang)')
      .is('revoque_le', null).eq('territoire_id', territoire);
    setNoms(data || []);
  }, [territoire]);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) return setMsg('Erreur : ' + error.message);
    if (data && data.ok === false) return setMsg('Erreur : ' + data.message);
    setMsg(ok); charger();
  };

  const nomDe = id => {
    const g = gens.find(x => x.id === id);
    return g ? nomComplet(g) : 'Membre';
  };

  async function nommer(e){
    e.preventDefault();
    if (!f.profil || !f.poste) return setMsg('Erreur : choisissez un membre et un poste.');
    const ok = await appel('nommer', {
      p_profil: f.profil, p_poste: f.poste, p_territoire: territoire || null,
      p_fin: f.fin || null, p_motif: f.motif || null
    }, 'Nomination enregistrée. Les accès du poste sont ouverts.');
    setF({ profil:'', poste:'', fin:'', motif:'' }); setOuvert(false);
  }

  return html`
    <div class="panneau" style="margin-top:24px">
      <div class="tete spread">
        <h3 style="font-size:17px">Confier un poste</h3>
        ${postes.length > 0 && html`
          <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
            ${ouvert ? 'Fermer' : 'Nommer quelqu\u2019un'}</button>`}
      </div>

      ${postes.length === 0
        ? html`<div class="corps small muted">
            Vous ne pouvez conférer aucun poste ici. On ne nomme qu\u2019en dessous
            de soi, dans son périmètre, et jamais à un poste ouvrant des droits
            sensibles \u2014 ceux-là restent à la direction.</div>`
        : ouvert && html`
          <form onSubmit=${nommer} class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:2;min-width:200px;margin:0">
                <label>Membre</label>
                <select value=${f.profil}
                  onChange=${e=>setF(o=>({...o,profil:e.target.value}))}>
                  <option value="">— Choisir —</option>
                  ${gens.map(g => html`<option value=${g.id}>
                    ${nomComplet(g)} · ${g.fonction_nom}${
                      g.territoire_nom ? ' · '+g.territoire_nom : ''}</option>`)}
                </select></div>
              <div class="field" style="flex:1;min-width:180px;margin:0">
                <label>Poste</label>
                <select value=${f.poste}
                  onChange=${e=>setF(o=>({...o,poste:e.target.value}))}>
                  <option value="">— Choisir —</option>
                  ${postes.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
                </select></div>
              <div class="field" style="flex:0 0 160px;margin:0">
                <label>Fin du mandat</label>
                <input type="date" value=${f.fin}
                  onInput=${e=>setF(o=>({...o,fin:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Motif</label>
              <input value=${f.motif} placeholder="Élu en assemblée du…, désigné par le bureau…"
                onInput=${e=>setF(o=>({...o,motif:e.target.value}))} /></div>
            ${f.poste && html`<div class="small muted">
              ${(postes.find(x=>x.code===f.poste)||{}).description || ''}</div>`}
            <div><button class="btn">Nommer</button></div>
          </form>`}

      ${noms.length > 0 && html`
        <div>
          ${noms.map(n => html`
            <div class="ligne" key=${n.id} style="align-items:flex-start">
              <div style="flex:1;min-width:200px">
                <div>${nomDe(n.profil_id)}</div>
                <div class="small muted">${n.postes?.nom || n.poste}
                  · depuis le ${jour(n.cree_le)}
                  ${n.fin ? ' · jusqu\u2019au ' + jour(n.fin) : ''}</div>
              </div>
              <div class="row" style="gap:8px">
                <button class="btn sm light"
                  onClick=${()=>setFiche(fiche===n.profil_id?null:n.profil_id)}>
                  ${fiche===n.profil_id ? 'Masquer' : 'Ce qui lui manque'}</button>
                <button class="btn sm light" onClick=${()=>{
                  const m = prompt('Motif du retrait (obligatoire)');
                  if (m) appel('revoquer', { p_nomination:n.id, p_motif:m },
                    'Poste retiré. Les accès qu\u2019il ouvrait se referment.');
                }}>Retirer</button>
              </div>
            </div>
            ${fiche === n.profil_id && html`
              <div style="padding:0 20px 20px">
                <${FicheOuverture} profil=${n.profil_id}
                  titre=${'Ouverture du dossier de ' + nomDe(n.profil_id)} />
              </div>`}`)}
        </div>`}
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
export function GestionLocale({ p }){
  const [onglet, setOnglet] = useState('fiche');
  const [terr, setTerr] = useState(p.territoire_id || null);
  const [fiche, setFiche] = useState(null);
  const [msg, setMsg] = useState('');
  const admin = p.niveau >= 80;

  const charger = useCallback(async () => {
    if (!terr) return;
    const { data } = await db.rpc('fiche_territoire', { p_territoire: terr });
    setFiche(data);
  }, [terr]);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    setMsg('');
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (data && data.ok === false){ setMsg('Erreur : ' + data.message); return false; }
    setMsg(ok); charger(); return true;
  };

  if (!terr) return html`
    <div class="vide" style="padding:80px">
      Votre profil n\u2019est rattaché à aucun territoire.
      <div class="small muted" style="margin-top:10px">
        Sans rattachement, il n\u2019y a pas de structure à gérer.</div>
    </div>`;

  const tabs = [['fiche','La structure'], ['acces','Accès du périmètre'],
                ['actes','Actes locaux']];
  if (admin) tabs.push(['plan','Plan du réseau']);

  return html`
    <div>
      <div class="eyebrow">Gestion de la structure</div>
      <h1 style="margin:6px 0 8px">${fiche?.nom || 'Ma structure'}</h1>
      <p class="muted" style="max-width:62ch">
        Ce qui relève de votre ressort : l\u2019identité de la structure, les accès
        de ses membres, et les décisions que vous prenez en son nom. Ce que la
        fédération vous délègue est écrit noir sur blanc — comme ce qu\u2019elle
        ne vous délègue pas.
      </p>

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet);
        flex-wrap:wrap">
        ${tabs.map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>{setOnglet(k);setMsg('')}}>${t}</button>`)}
      </div>

      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-bottom:20px">${msg}</div>`}

      ${onglet === 'fiche' && html`<${GlFiche} fiche=${fiche} appel=${appel} />`}
      ${onglet === 'acces' && html`<${GlAcces} p=${p} territoire=${terr}
        appel=${appel} setMsg=${setMsg} />`}
      ${onglet === 'actes' && html`<${GlActes} p=${p} territoire=${terr}
        appel=${appel} setMsg=${setMsg} />`}
      ${onglet === 'plan' && html`<${GlPlan} appel=${appel} setMsg=${setMsg}
        ouvrir=${t=>{setTerr(t);setOnglet('fiche')}} />`}
    </div>`;
}

/* --- La fiche d'identité ------------------------------------------------ */

export function GlFiche({ fiche, appel }){
  const [f, setF] = useState(null);
  const [edit, setEdit] = useState(false);
  useEffect(() => { if (fiche) setF({ ...fiche }); }, [fiche]);
  if (!fiche || !f) return html`<div class="vide">Chargement…</div>`;

  const pts = fiche.points || {};
  const ETAT_T = { projet:['Projet','or'], constitution:['En constitution','or'],
    active:['Active','vert'], sommeil:['En sommeil',''], dissoute:['Dissoute','rouge'] };

  return html`
    <div>
      <div class="chiffres" style="margin-bottom:24px">
        <div><div class="n" style="font-size:28px">${fiche.effectif}</div>
          <div class="l">Adhérents actifs</div></div>
        <div><div class="n" style="font-size:28px">${fiche.encadrants}</div>
          <div class="l">Encadrants</div></div>
        <div><div class="n" style="font-size:28px">${pts.disponible ?? 0}</div>
          <div class="l">Points disponibles</div></div>
        <div><div class="n" style="font-size:28px">${fiche.actes_locaux}</div>
          <div class="l">Actes locaux en vigueur</div></div>
      </div>

      ${fiche.en_attente > 0 && html`
        <div class="alerte" style="margin-bottom:24px">
          ${fiche.en_attente} inscription(s) en attente de vérification sur votre
          périmètre. <a href="#/espace/parcours">Les accompagner</a>
        </div>`}

      <div class="panneau" style="margin-bottom:24px">
        <div class="tete spread">
          <h3 style="font-size:17px">Identité</h3>
          <div class="row" style="gap:8px">
            <span class=${'tag '+(ETAT_T[fiche.etat]||['',''])[1]}>
              ${(ETAT_T[fiche.etat]||[fiche.etat])[0]}</span>
            <button class="btn sm light" onClick=${()=>setEdit(!edit)}>
              ${edit ? 'Fermer' : 'Modifier'}</button>
          </div>
        </div>
        ${edit
          ? html`<form class="corps stack" onSubmit=${async e=>{
              e.preventDefault();
              const ok = await appel('regler_territoire',
                { p_territoire: fiche.id, d: {
                  nom: f.nom, academie: f.academie, siege: f.siege,
                  courriel: f.courriel, telephone: f.telephone,
                  population: f.population, note: f.note, creee_le: f.creee_le } },
                'Fiche mise à jour.');
              if (ok) setEdit(false);
            }}>
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:2;min-width:200px;margin:0">
                  <label>Nom</label>
                  <input value=${f.nom||''}
                    onInput=${e=>setF(o=>({...o,nom:e.target.value}))} /></div>
                <div class="field" style="flex:1;min-width:150px;margin:0">
                  <label>Académie</label>
                  <input value=${f.academie||''} placeholder="Toulouse, Créteil…"
                    onInput=${e=>setF(o=>({...o,academie:e.target.value}))} /></div>
                <div class="field" style="flex:0 0 140px;margin:0">
                  <label>Constituée le</label>
                  <input type="date" value=${f.creee_le||''}
                    onInput=${e=>setF(o=>({...o,creee_le:e.target.value}))} /></div>
              </div>
              <div class="field"><label>Siège</label>
                <input value=${f.siege||''}
                  onInput=${e=>setF(o=>({...o,siege:e.target.value}))} /></div>
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:1;margin:0"><label>Courriel</label>
                  <input value=${f.courriel||''}
                    onInput=${e=>setF(o=>({...o,courriel:e.target.value}))} /></div>
                <div class="field" style="flex:1;margin:0"><label>Téléphone</label>
                  <input value=${f.telephone||''}
                    onInput=${e=>setF(o=>({...o,telephone:e.target.value}))} /></div>
                <div class="field" style="flex:0 0 140px;margin:0">
                  <label>Population</label>
                  <input type="number" value=${f.population||''}
                    onInput=${e=>setF(o=>({...o,population:e.target.value}))} /></div>
              </div>
              <div class="field"><label>Note interne</label>
                <textarea value=${f.note||''} style="min-height:60px"
                  onInput=${e=>setF(o=>({...o,note:e.target.value}))}></textarea></div>
              <div><button class="btn">Enregistrer</button></div>
            </form>`
          : html`
            <div class="ligne"><span class="muted">Code</span>
              <span class="mono">${fiche.code}</span></div>
            <div class="ligne"><span class="muted">Rattachement</span>
              <span>${fiche.parent || '—'}</span></div>
            <div class="ligne"><span class="muted">Académie</span>
              <span>${fiche.academie || '—'}</span></div>
            <div class="ligne"><span class="muted">Siège</span>
              <span>${fiche.siege || '—'}</span></div>
            <div class="ligne"><span class="muted">Contact</span>
              <span>${[fiche.courriel, fiche.telephone].filter(Boolean).join(' · ') || '—'}</span></div>
            <div class="ligne"><span class="muted">Constituée le</span>
              <span>${fiche.creee_le ? jour(fiche.creee_le) : '—'}</span></div>
            ${fiche.note && html`<div class="corps small muted">${fiche.note}</div>`}`}
      </div>

      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Bureau</h3></div>
        ${(fiche.bureau||[]).length === 0
          ? html`<div class="corps muted">
              Aucun mandat en cours. Une structure sans bureau ne peut ni
              engager de dépense ni se faire représenter.
              <a href="#/espace/comite">Constituer le bureau</a></div>`
          : fiche.bureau.map((b,i) => html`
            <div class="ligne" key=${i}>
              <div style="flex:1;min-width:200px">
                <div>${b.membre}</div>
                <div class="small muted">${b.poste}</div>
              </div>
              <span class="small muted">depuis le ${jour(b.depuis)}</span>
            </div>`)}
      </div>

      ${(fiche.enfants||[]).length > 0 && html`
        <div class="panneau">
          <div class="tete"><h3 style="font-size:17px">Structures rattachées</h3>
            <span class="tag">${fiche.enfants.length}</span></div>
          ${fiche.enfants.map(e => html`
            <div class="ligne" key=${e.id}>
              <div style="flex:1">${e.nom}</div>
              <span class=${'tag '+(ETAT_T[e.etat]||['',''])[1]}>
                ${(ETAT_T[e.etat]||[e.etat])[0]}</span>
            </div>`)}
        </div>`}
    </div>`;
}

/* --- Les accès du périmètre --------------------------------------------- */

export function GlAcces({ p, territoire, appel, setMsg }){
  const [gens, setGens] = useState([]);
  const [apps, setApps] = useState([]);
  const [ouvert, setOuvert] = useState(null);
  const [q, setQ] = useState('');

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.rpc('acces_du_perimetre', { p_territoire: territoire }),
      db.rpc('applications_delegables')
    ]);
    setGens(a.data||[]); setApps(b.data||[]);
  }, [territoire]);
  useEffect(() => { charger(); }, [charger]);

  const ouvrables = apps.filter(a => a.ouvrable);
  const liste = gens.filter(g => q === '' ||
    (g.membre + ' ' + g.matricule).toLowerCase().includes(q.toLowerCase()));

  async function ouvrir(g, code){
    const { data, error } = await db.rpc('accorder_acces', {
      p_profil: g.profil_id, p_app: code,
      p_motif: 'Ouvert par la structure', p_expire: null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Accès ouvert à ' + g.membre + '.'); charger();
  }

  return html`
    <div>
      <div class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Ce que la fédération vous délègue</h3></div>
        <div class="corps">
          <p class="small muted" style="margin:0 0 14px">
            Le national décide de la liste, vous décidez des personnes. Une
            application non déléguée reste demandable au guichet, par le membre
            lui-même.
          </p>
          <div class="row" style="gap:8px;flex-wrap:wrap">
            ${apps.map(a => html`
              <span key=${a.code} class=${'tag '+(a.ouvrable?'vert':'')}
                title=${a.motif}>${a.nom_court || a.nom}</span>`)}
          </div>
        </div>
      </div>

      <input value=${q} placeholder="Rechercher un membre" style="margin-bottom:16px"
        onInput=${e=>setQ(e.target.value)} />

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Membres du périmètre</h3>
          <span class="tag">${liste.length}</span></div>
        ${liste.length === 0
          ? html`<div class="corps muted">Aucun membre.</div>`
          : liste.map(g => html`
            <div key=${g.profil_id}>
              <div class="ligne" style="align-items:flex-start">
                <div style="flex:1;min-width:240px">
                  <div class="row" style="gap:8px;flex-wrap:wrap">
                    <span style="font-weight:600">${g.membre}</span>
                    <span class="mono muted small">${g.matricule}</span>
                    ${g.statut !== 'actif' && html`<span class="tag or">${g.statut}</span>`}
                  </div>
                  <div class="small muted" style="margin-top:3px">
                    ${g.fonction} · ${g.echelon}${g.territoire ? ' · ' + g.territoire : ''}
                  </div>
                  <div class="row" style="gap:5px;margin-top:6px;flex-wrap:wrap">
                    ${(g.postes||[]).map((x,i) => html`
                      <span class="tag bleu" key=${'p'+i}>${x}</span>`)}
                    ${(g.applications||[]).map((x,i) => html`
                      <span class="tag" key=${'a'+i}>${x}</span>`)}
                    ${(g.applications||[]).length === 0 && html`
                      <span class="small muted">Aucune application ouverte</span>`}
                  </div>
                </div>
                ${ouvrables.length > 0 && g.profil_id !== p.id && html`
                  <button class="btn sm light"
                    onClick=${()=>setOuvert(ouvert===g.profil_id?null:g.profil_id)}>
                    ${ouvert===g.profil_id ? 'Fermer' : 'Ouvrir un accès'}</button>`}
              </div>
              ${ouvert === g.profil_id && html`
                <div class="corps" style="background:var(--papier);
                  border-bottom:1px solid var(--filet)">
                  <div class="small muted" style="margin-bottom:8px">
                    Applications que vous pouvez lui ouvrir</div>
                  <div class="row" style="gap:6px;flex-wrap:wrap">
                    ${ouvrables.map(a => html`
                      <button class="btn sm light" key=${a.code}
                        onClick=${()=>ouvrir(g, a.code)}>${a.nom_court || a.nom}</button>`)}
                  </div>
                  <div class="small muted" style="margin-top:10px">
                    On ne donne que ce qu\u2019on a : cette liste se limite aux
                    applications dont vous disposez vous-même.
                  </div>
                </div>`}
            </div>`)}
      </div>
    </div>`;
}

/* --- Les actes locaux ---------------------------------------------------- */

export function GlActes({ p, territoire, appel, setMsg }){
  const [actes, setActes] = useState([]);
  const [postes, setPostes] = useState([]);
  const [gens, setGens] = useState([]);
  const [ouvert, setOuvert] = useState(false);
  const [f, setF] = useState({ type:'decision', objet:'', visas:'', considerants:'',
                               destinataire:'', poste:'', effet:'' });
  const [articles, setArticles] = useState(['']);
  const [texte, setTexte] = useState(null);
  const [lu, setLu] = useState(null);

  const charger = useCallback(async () => {
    const [a, b, c] = await Promise.all([
      db.rpc('recueil_actes', { p_filtre: 'locaux' }),
      db.rpc('postes_conferables', { p_territoire: territoire }),
      db.from('v_annuaire').select('id,prenom,nom,fonction_nom')
        .eq('statut','actif').order('nom')
    ]);
    setActes(a.data||[]); setPostes(b.data||[]); setGens(c.data||[]);
  }, [territoire]);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(e){
    e.preventDefault();
    const arts = articles.map(a => a.trim()).filter(Boolean);
    if (arts.length === 0)
      return setMsg('Erreur : un acte sans article ne décide rien.');
    const { data, error } = await db.rpc('prendre_acte', {
      p_type: f.type, p_objet: f.objet, p_visas: f.visas || null,
      p_considerants: f.considerants || null, p_articles: arts,
      p_destinataire: f.destinataire || null, p_poste: f.poste || null,
      p_effet: f.effet || null, p_territoire: territoire
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({ type:'decision', objet:'', visas:'', considerants:'',
           destinataire:'', poste:'', effet:'' });
    setArticles(['']); setOuvert(false);
    setMsg('Projet d\u2019acte enregistré. Il ne produit effet qu\u2019à la signature.');
    charger();
  }

  async function lire(a){
    if (lu === a.id){ setLu(null); setTexte(null); return; }
    const { data } = await db.rpc('texte_acte', { p_id: a.id });
    setLu(a.id); setTexte(data);
  }

  const projets = actes.filter(a => a.statut === 'projet');

  return html`
    <div>
      <div class="alerte" style="margin-bottom:24px;border-left:3px solid var(--bordeaux)">
        <strong>Un acte local n\u2019est lu que dans son ressort.</strong>
        Il apparaît au recueil des adhérents de votre périmètre, sous bannière
        locale, et nulle part ailleurs. La présidence de structure, elle, ne se
        confère pas localement : elle est annoncée par l\u2019échelon supérieur.
      </div>

      <div class="spread" style="margin-bottom:16px">
        <h3 style="font-size:17px;margin:0">Actes de la structure</h3>
        <button class="btn sm" onClick=${()=>setOuvert(!ouvert)}>
          ${ouvert ? 'Fermer' : 'Prendre un acte'}</button>
      </div>

      ${ouvert && html`
        <form class="panneau" style="margin-bottom:24px" onSubmit=${enregistrer}>
          <div class="tete"><h3 style="font-size:17px">Nouvel acte local</h3></div>
          <div class="corps stack">
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:170px;margin:0">
                <label>Nature</label>
                <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
                  ${Object.entries(TYPE_ACTE).filter(([k]) => k !== 'abrogation')
                    .map(([k,v]) => html`<option value=${k}>${v}</option>`)}
                </select></div>
              <div class="field" style="flex:0 0 160px;margin:0">
                <label>Prend effet le</label>
                <input type="date" value=${f.effet}
                  onInput=${e=>setF(o=>({...o,effet:e.target.value}))} /></div>
            </div>
            <div class="field"><label>Objet</label>
              <input value=${f.objet} placeholder="Désignation du référent du parcours"
                onInput=${e=>setF(o=>({...o,objet:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:2;min-width:200px;margin:0">
                <label>${f.type === 'nomination' ? 'Personne nommée' : 'Destinataire'}</label>
                <select value=${f.destinataire}
                  onChange=${e=>setF(o=>({...o,destinataire:e.target.value}))}>
                  <option value="">— Aucun —</option>
                  ${gens.map(g => html`<option value=${g.id}>
                    ${nomComplet(g)} · ${g.fonction_nom}</option>`)}
                </select></div>
              ${f.type === 'nomination' && html`
                <div class="field" style="flex:1;min-width:180px;margin:0">
                  <label>Poste conféré</label>
                  <select value=${f.poste} onChange=${e=>setF(o=>({...o,poste:e.target.value}))}>
                    <option value="">— Choisir —</option>
                    ${postes.map(x => html`<option value=${x.code}>${x.nom}</option>`)}
                  </select>
                  ${postes.length === 0 && html`<div class="small muted">
                    Aucun poste conférable à votre niveau.</div>`}
                </div>`}
            </div>
            <div class="field"><label>Visas</label>
              <textarea value=${f.visas} style="min-height:60px"
                placeholder="Vu les statuts, vu la délibération du bureau du…"
                onInput=${e=>setF(o=>({...o,visas:e.target.value}))}></textarea></div>
            <div class="field"><label>Considérants</label>
              <textarea value=${f.considerants} style="min-height:60px"
                onInput=${e=>setF(o=>({...o,considerants:e.target.value}))}></textarea></div>
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
        </form>`}

      ${projets.length > 0 && html`
        <div class="panneau" style="margin-bottom:24px;border-color:var(--laiton)">
          <div class="tete" style="border-bottom-color:var(--laiton)">
            <h3 style="font-size:17px">En attente de signature</h3></div>
          ${projets.map(a => html`
            <div class="ligne" key=${a.id} style="align-items:flex-start">
              <div style="flex:1;min-width:240px">
                <div class="row" style="gap:8px;flex-wrap:wrap">
                  <span class="mono muted small">${a.reference}</span>
                  <span class="tag">${TYPE_ACTE[a.type] || a.type}</span>
                </div>
                <div style="margin-top:4px">${a.objet}</div>
                ${a.destinataire && html`<div class="small muted" style="margin-top:3px">
                  ${a.destinataire}${a.poste_nom ? ' · ' + a.poste_nom : ''}</div>`}
              </div>
              <div class="row" style="gap:6px">
                <button class="btn sm" onClick=${()=>appel('signer_acte', { p_id:a.id },
                  'Acte signé et notifié.')}>Signer</button>
                <button class="btn sm light" onClick=${()=>{
                  const m = prompt('Motif du retrait');
                  if (m) appel('abroger_acte', { p_id:a.id, p_motif:m }, 'Projet retiré.');
                }}>Retirer</button>
              </div>
            </div>`)}
        </div>`}

      <${RecueilListe} actes=${actes.filter(a => a.statut !== 'projet')}
        ouvert=${lu} texte=${texte} lire=${lire}
        telecharger=${()=>{}} abroger=${(id)=>{
          const m = prompt('Motif de l\u2019abrogation (obligatoire)');
          if (m) appel('abroger_acte', { p_id:id, p_motif:m }, 'Acte abrogé.');
        }} />
    </div>`;
}


/* --- Le plan du réseau ---------------------------------------------------
   Ni carte ni dessin : un arbre, avec ce qui sert à décider. Le
   rattachement et la fusion s'y font, parce que c'est là qu'on voit ce
   qu'on déplace.
   --------------------------------------------------------------------- */
export function GlPlan({ appel, setMsg, ouvrir }){
  const [l, setL] = useState([]);
  const [q, setQ] = useState('');
  const [choix, setChoix] = useState(null);
  const [indicateur, setIndicateur] = useState('effectif');
  const [carte, setCarte] = useState(true);

  const charger = useCallback(() =>
    db.rpc('plan_territoires').then(({data}) => setL(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  const liste = l.filter(t => q === '' ||
    (t.nom + ' ' + (t.code||'') + ' ' + (t.academie||''))
      .toLowerCase().includes(q.toLowerCase()));

  const ETAT_T = { projet:['Projet','or'], constitution:['Constitution','or'],
    active:['Active','vert'], sommeil:['Sommeil',''], dissoute:['Dissoute','rouge'] };

  async function rattacher(t){
    const cible = prompt('Identifiant du nouveau territoire parent '
      + '(laisser vide pour détacher)');
    if (cible === null) return;
    await appel('rattacher_territoire',
      { p_territoire: t.id, p_parent: cible || null }, 'Rattachement modifié.');
    charger();
  }
  async function fusionner(t){
    if (!choix){ setChoix(t); return setMsg('Choisissez maintenant le territoire qui absorbe « '
      + t.nom + ' ».'); }
    if (choix.id === t.id){ setChoix(null); return setMsg(''); }
    const m = prompt('Motif de la fusion de « ' + choix.nom + ' » dans « ' + t.nom + ' »');
    if (!m) return;
    if (!confirm('Fusionner « ' + choix.nom + ' » dans « ' + t.nom + ' » ? '
      + 'Tous les membres, mandats, commandes et documents seront reportés. '
      + 'Cette opération ne se défait pas.')) return;
    await appel('fusionner_territoires',
      { p_source: choix.id, p_cible: t.id, p_motif: m }, 'Fusion effectuée.');
    setChoix(null); charger();
  }

  return html`
    <div>
      <p class="muted" style="max-width:60ch;margin:0 0 16px">
        L\u2019arbre du réseau, avec ce qui sert à décider : effectif, encadrement,
        bureau constitué, dotation. Une structure sans président ni trésorier
        est signalée — c\u2019est ce qui l\u2019empêche de fonctionner.
      </p>

      ${choix && html`
        <div class="alerte" style="margin-bottom:16px;border-left:3px solid var(--bordeaux)">
          Fusion en cours : « ${choix.nom} » sera absorbée. Choisissez le
          territoire qui l\u2019accueille, ou
          <a href="#" onClick=${e=>{e.preventDefault();setChoix(null);setMsg('')}}>annulez</a>.
        </div>`}

      <div class="spread" style="margin-bottom:12px">
        <span class="small muted">${l.length} territoire(s)</span>
        <button class="btn sm light" onClick=${()=>setCarte(!carte)}>
          ${carte ? 'Masquer la carte' : 'Afficher la carte'}</button>
      </div>

      <${Organigramme} />

      ${carte && html`<${CarteReseau} territoires=${l} indicateur=${indicateur}
        ouvrir=${(id, ind) => { if (ind) setIndicateur(ind); else if (id) ouvrir(id); }} />`}

      <input value=${q} placeholder="Rechercher un territoire, un code, une académie"
        style="margin-bottom:16px" onInput=${e=>setQ(e.target.value)} />

      <div class="panneau">
        <div style="overflow-x:auto">
          <table>
            <thead><tr>
              <th style="min-width:240px">Territoire</th>
              <th>Académie</th>
              <th style="text-align:right">Membres</th>
              <th>Bureau</th>
              <th style="text-align:right">Points</th>
              <th></th>
            </tr></thead>
            <tbody>
              ${liste.map(t => html`
                <tr key=${t.id}>
                  <td>
                    <div style=${'padding-left:'+(t.profondeur*16)+'px'}>
                      <a href="#" onClick=${e=>{e.preventDefault();ouvrir(t.id)}}>${t.nom}</a>
                      <span class=${'tag '+(ETAT_T[t.etat]||['',''])[1]}
                        style="margin-left:6px">${(ETAT_T[t.etat]||[t.etat])[0]}</span>
                    </div>
                    <div class="mono muted small" style=${'padding-left:'+(t.profondeur*16)+'px'}>
                      ${t.echelle} · ${t.code}</div>
                  </td>
                  <td class="small muted">${t.academie || '—'}</td>
                  <td class="mono" style="text-align:right">${t.effectif}
                    <div class="small muted">${t.encadrants} encadrant(s)</div></td>
                  <td class="small">
                    ${t.president
                      ? html`<div>${t.president}</div>`
                      : t.echelle !== 'national'
                        ? html`<div style="color:var(--rouge)">Sans président</div>` : ''}
                    ${t.tresorier
                      ? html`<div class="muted">${t.tresorier}</div>`
                      : t.echelle !== 'national'
                        ? html`<div style="color:var(--rouge)">Sans trésorier</div>` : ''}
                  </td>
                  <td class="mono" style="text-align:right">${t.dotation}</td>
                  <td style="text-align:right;white-space:nowrap">
                    <button class="btn sm light" onClick=${()=>rattacher(t)}>Rattacher</button>
                    ${t.enfants === 0 && t.echelle !== 'national' && html`
                      <button class=${'btn sm '+(choix && choix.id===t.id ? '' : 'light')}
                        onClick=${()=>fusionner(t)}>
                        ${choix && choix.id===t.id ? 'À fusionner' : 'Fusionner'}</button>`}
                  </td>
                </tr>`)}
            </tbody>
          </table>
        </div>
      </div>
    </div>`;
}


/* =====================================================================
   LA CARTE DU RÉSEAU
   Le fond de carte pèse trop lourd pour vivre dans ce fichier : il est
   chargé à la demande depuis un dépôt public, et mis en cache pour la
   session. Si le chargement échoue — réseau coupé, dépôt déplacé — le
   tableau reste, et le dit. La carte est un confort, jamais le seul
   moyen d'atteindre un territoire.

   Les codes INSEE du fond correspondent aux nôtres : « 31 » pour un
   département, « R76 » pour une région une fois le préfixe ajouté.
   L'outre-mer n'y figure pas et se lit sous la carte.
   ===================================================================== */
export const FOND = 'https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/';

export const cacheFond = {};


export async function chargerFond(echelle){
  if (cacheFond[echelle]) return cacheFond[echelle];
  const f = echelle === 'region'
    ? 'regions-version-simplifiee.geojson'
    : 'departements-version-simplifiee.geojson';
  const r = await fetch(FOND + f);
  if (!r.ok) throw new Error('fond indisponible');
  const j = await r.json();
  cacheFond[echelle] = j;
  return j;
}


/* Projection conique simple, suffisante à l'échelle d'un pays : on
   corrige la longitude par le cosinus de la latitude moyenne, sans quoi
   la France paraît écrasée en largeur. */
export function projeter(coords, b, L, H){
  const lat0 = (b.minY + b.maxY) / 2 * Math.PI / 180;
  const k = Math.cos(lat0);
  const x0 = b.minX * k, x1 = b.maxX * k;
  const ex = (x1 - x0) || 1, ey = (b.maxY - b.minY) || 1;
  const e = Math.min((L - 20) / ex, (H - 20) / ey);
  const dx = (L - ex * e) / 2, dy = (H - ey * e) / 2;
  return coords.map(([lon, lat]) => [
    (lon * k - x0) * e + dx,
    H - ((lat - b.minY) * e + dy)
  ]);
}


export function bornes(features){
  let minX = 180, maxX = -180, minY = 90, maxY = -90;
  const voir = c => { if (c[0] < minX) minX = c[0]; if (c[0] > maxX) maxX = c[0];
                      if (c[1] < minY) minY = c[1]; if (c[1] > maxY) maxY = c[1]; };
  features.forEach(f => anneaux(f).forEach(a => a.forEach(voir)));
  return { minX, maxX, minY, maxY };
}


export function anneaux(f){
  const g = f.geometry;
  if (!g) return [];
  return g.type === 'Polygon' ? g.coordinates
       : g.type === 'MultiPolygon' ? g.coordinates.flat() : [];
}


export function CarteReseau({ territoires, ouvrir, indicateur }){
  const [echelle, setEchelle] = useState('departement');
  const [geo, setGeo] = useState(null);
  const [erreur, setErreur] = useState(null);
  const [survol, setSurvol] = useState(null);
  const L = 640, H = 620;

  useEffect(() => {
    setGeo(null); setErreur(null);
    chargerFond(echelle).then(setGeo)
      .catch(() => setErreur('Le fond de carte n\u2019a pas pu être chargé.'));
  }, [echelle]);

  // On rapproche les codes du fond de ceux de la fédération.
  const par = {};
  (territoires || []).forEach(t => {
    if (t.echelle === echelle) par[t.code] = t;
  });
  const cle = c => echelle === 'region' ? 'R' + c : c;

  const valeur = t => !t ? null
    : indicateur === 'effectif' ? t.effectif
    : indicateur === 'dotation' ? t.dotation
    : (t.president ? 1 : 0) + (t.tresorier ? 1 : 0);

  const vals = Object.values(par).map(valeur).filter(v => v !== null);
  const haut = Math.max(1, ...vals);

  const teinte = t => {
    if (!t) return 'var(--papier)';
    if (indicateur === 'bureau')
      return valeur(t) === 2 ? 'var(--vert)'
           : valeur(t) === 1 ? 'var(--laiton)' : 'var(--rouge-clair)';
    const p = valeur(t) / haut;
    return p === 0 ? 'var(--papier)'
         : 'color-mix(in srgb, var(--bleu) ' + Math.round(12 + p * 78) + '%, white)';
  };

  const outreMer = (territoires || []).filter(t =>
    t.echelle === echelle && !Object.keys(par).some(c => false)
      && ['971','972','973','974','976','R01','R02','R03','R04','R06'].includes(t.code));

  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete spread">
        <h3 style="font-size:17px">Carte du réseau</h3>
        <div class="row" style="gap:8px">
          <select value=${echelle} style="width:auto;padding:5px 8px;font-size:13px"
            onChange=${e=>setEchelle(e.target.value)}>
            <option value="departement">Départements</option>
            <option value="region">Régions</option>
          </select>
        </div>
      </div>

      ${erreur
        ? html`<div class="corps small muted">
            ${erreur} Le tableau ci-dessous reste utilisable : la carte n\u2019est
            qu\u2019un confort, jamais le seul moyen d\u2019atteindre un territoire.</div>`
        : !geo
          ? html`<div class="corps muted">Chargement du fond de carte…</div>`
          : html`
            <div class="corps" style="padding-top:12px">
              <svg viewBox=${'0 0 ' + L + ' ' + H} style="width:100%;height:auto;
                max-height:640px;display:block">
                ${(() => {
                  const b = bornes(geo.features);
                  return geo.features.map((f,i) => {
                    const t = par[cle(f.properties.code)];
                    const d = anneaux(f).map(a =>
                      'M' + projeter(a, b, L, H).map(p =>
                        p[0].toFixed(1) + ',' + p[1].toFixed(1)).join('L') + 'Z').join(' ');
                    return html`<path key=${i} d=${d}
                      fill=${teinte(t)}
                      stroke=${survol === f.properties.code ? 'var(--nuit)' : 'var(--filet)'}
                      stroke-width=${survol === f.properties.code ? 1.6 : 0.6}
                      style=${'cursor:' + (t ? 'pointer' : 'default')}
                      onMouseEnter=${()=>setSurvol(f.properties.code)}
                      onMouseLeave=${()=>setSurvol(null)}
                      onClick=${()=>{ if (t) ouvrir(t.id); }}>
                      <title>${f.properties.nom}${t
                        ? ' — ' + t.effectif + ' membre(s)'
                          + (t.president ? '' : ' · sans président')
                          + (t.tresorier ? '' : ' · sans trésorier')
                        : ' — aucune structure'}</title>
                    </path>`;
                  });
                })()}
              </svg>

              <div class="row" style="gap:16px;margin-top:12px;flex-wrap:wrap;
                align-items:center">
                <span class="small muted">Colorer par</span>
                ${[['effectif','Effectif'],['bureau','Bureau constitué'],
                   ['dotation','Dotation']].map(([k,t]) => html`
                  <button class=${'btn sm ' + (indicateur===k ? '' : 'light')} key=${k}
                    onClick=${()=>ouvrir(null, k)}>${t}</button>`)}
              </div>
              <div class="small muted" style="margin-top:8px">
                ${indicateur === 'bureau'
                  ? 'Vert : président et trésorier. Ambre : l\u2019un des deux. Rouge : aucun.'
                  : 'Plus le bleu est soutenu, plus la valeur est élevée. Blanc : aucune structure.'}
                Les territoires d\u2019outre-mer ne figurent pas sur ce fond de carte ;
                ils restent dans le tableau.
              </div>
            </div>`}
    </div>`;
}


/* =====================================================================
   L'ORGANIGRAMME
   Qui appartient à quoi. Ce n'est pas une donnée à part : il se déduit
   des postes occupés, donc il ne peut pas être périmé. Les postes qui
   engagent les points de leur direction sont signalés — c'est à eux
   qu'on adresse une demande de validation.
   ===================================================================== */
export function Organigramme(){
  const [l, setL] = useState([]);
  useEffect(() => {
    db.rpc('organigramme').then(({data}) => setL(data || []));
  }, []);
  if (l.length === 0) return null;

  const dirs = [...new Set(l.map(x => x.direction))];

  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete"><h3 style="font-size:17px">Organigramme</h3></div>
      <div class="corps small muted" style="padding-bottom:0">
        Il se déduit des mandats en cours : il ne peut donc pas être périmé.
        Un poste marqué « engage » peut dépenser les points de son entité.
      </div>
      ${dirs.map(d => {
        const postes = l.filter(x => x.direction === d);
        return html`
          <div key=${d}>
            <div class="corps" style="padding-bottom:6px;padding-top:16px">
              <div class="eyebrow">${postes[0].direction_nom}</div>
            </div>
            ${postes.map((x,i) => html`
              <div class="ligne" key=${i} style="align-items:flex-start">
                <div style="flex:1;min-width:220px">
                  <div class="row" style="gap:8px;flex-wrap:wrap">
                    <span>${x.poste_nom}</span>
                    ${x.engage_points && html`<span class="tag bleu">engage</span>`}
                  </div>
                  ${x.titulaire
                    ? html`<div class="small muted" style="margin-top:3px">
                        ${x.titulaire}${x.territoire ? ' · ' + x.territoire : ''}
                        ${x.depuis ? ' · depuis le ' + jour(x.depuis) : ''}</div>`
                    : html`<div class="small" style="margin-top:3px;color:var(--rouge)">
                        Vacant</div>`}
                </div>
                <span class="mono muted small">${x.rang}</span>
              </div>`)}
          </div>`;
      })}
    </div>`;
}
