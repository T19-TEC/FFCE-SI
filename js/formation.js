import { Publier } from './direction.js';
import { TYPES_LECON, db, h, html, jour, useCallback, useEffect, useState } from './socle.js';

   ===================================================================== */

export function Formations({ p }){
  const [liste, setListe] = useState(null);
  const [certifs, setCertifs] = useState([]);

  useEffect(() => { (async () => {
    const { data: fs } = await db.from('formations').select('*')
      .eq('publiee', true).order('ordre');
    const avec = await Promise.all((fs||[]).map(async f => {
      const { data } = await db.rpc('avancement', { p_formation: f.id });
      const a = Array.isArray(data) ? data[0] : data;
      return { ...f, ...(a || {total:0, faites:0, pourcent:0}) };
    }));
    setListe(avec);
    const { data: c } = await db.from('certifications_obtenues')
      .select('*, certifications(nom, description)').eq('profil_id', p.id);
    setCertifs(c || []);
  })(); }, [p.id]);

  if (!liste) return html`<div class="vide">Chargement…</div>`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Formations</div>
          <h1 style="margin:6px 0 0">Se former</h1>
        </div>
        ${(p.niveau >= 90 || (p.postes||[]).length > 0) && html`
          <a class="btn light" href="#/espace/editeur">Rédiger les parcours</a>`}
      </div>
      <p class="muted" style="max-width:56ch">
        Chaque parcours achevé délivre une certification inscrite à votre
        compte. Certains projets et groupes de travail l'exigeront.
      </p>

      ${certifs.length > 0 && html`
        <div class="panneau" style="margin-top:32px">
          <div class="tete"><h3 style="font-size:17px">Mes certifications</h3></div>
          ${certifs.map(c => html`
            <div class="ligne">
              <div>
                <div>${c.certifications?.nom || c.code}</div>
                <div class="small muted">
                  Délivrée le ${jour(c.obtenue_le)}
                  ${c.expire_le ? ' · valable jusqu\u2019au ' + jour(c.expire_le) : ''}
                </div>
              </div>
              <span class="mono muted">${c.numero}</span>
            </div>`)}
        </div>`}

      <div class="tuiles" style="margin-top:32px">
        ${liste.map(f => html`
          <a class="tuile" href=${'#/espace/formation/'+f.id}>
            <h3>${f.titre}</h3>
            <p>${f.resume || ''}</p>
            <div class="jauge" style="margin-top:14px">
              <i style=${'width:'+(f.pourcent||0)+'%'}></i></div>
            <div class="small muted" style="margin-top:8px">
              ${f.faites}/${f.total} leçons
              ${f.duree_min ? ' · ' + f.duree_min + ' min' : ''}
              ${f.pourcent === 100 ? ' · achevé' : ''}
            </div>
          </a>`)}
      </div>
      ${liste.length === 0 && html`<div class="vide">Aucune formation publiée pour l\u2019instant.</div>`}
    </div>`;
}


export function Formation({ p, id }){
  const [f, setF] = useState(null);
  const [parcours, setParcours] = useState([]);
  const [faites, setFaites] = useState({});
  const [ouverte, setOuverte] = useState(null);   // leçon affichée

  const charger = useCallback(async () => {
    const { data: form } = await db.from('formations').select('*').eq('id', id).maybeSingle();
    setF(form);
    const { data: par } = await db.from('v_parcours').select('*')
      .eq('formation_id', id).order('rang');
    setParcours(par || []);
    const { data: pr } = await db.from('progression').select('lecon_id,score')
      .eq('profil_id', p.id);
    setFaites(Object.fromEntries((pr||[]).map(x => [x.lecon_id, x.score])));
  }, [id, p.id]);

  useEffect(() => { charger(); }, [charger]);

  if (!f) return html`<div class="vide">Chargement…</div>`;

  const total = parcours.length;
  const nbFaites = parcours.filter(l => l.lecon_id in faites).length;
  const pct = total ? Math.round(nbFaites / total * 100) : 0;

  // Une leçon est ouverte si la précédente est achevée.
  const estOuverte = i => i === 0 || (parcours[i-1] && parcours[i-1].lecon_id in faites);

  if (ouverte){
    const i = parcours.findIndex(l => l.lecon_id === ouverte);
    return html`<${Lecon} lecon=${parcours[i]} suivante=${parcours[i+1]}
      dejaFaite=${ouverte in faites}
      fermer=${() => { setOuverte(null); charger(); }}
      allerSuivante=${() => { setOuverte(parcours[i+1]?.lecon_id || null); charger(); }} />`;
  }

  const modules = [];
  parcours.forEach(l => {
    let m = modules.find(x => x.id === l.module_id);
    if (!m){ m = { id: l.module_id, titre: l.module_titre, lecons: [] }; modules.push(m); }
    m.lecons.push(l);
  });

  const picto = { lecture:'Lecture', video:'Vidéo', document:'Document', quiz:'Quiz' };

  return html`
    <div>
      <a class="small" href="#/espace/formations">← Toutes les formations</a>
      <h1 style="margin:12px 0 8px">${f.titre}</h1>
      <p class="muted" style="max-width:60ch">${f.description || f.resume || ''}</p>

      <div class="panneau" style="margin-top:24px">
        <div class="corps">
          <div class="spread">
            <span class="small">${nbFaites} leçon${nbFaites>1?'s':''} sur ${total}</span>
            <span class="mono">${pct} %</span>
          </div>
          <div class="jauge" style="margin-top:10px"><i style=${'width:'+pct+'%'}></i></div>
          ${pct === 100 && html`<div class="alerte ok" style="margin-top:16px">
            Parcours achevé. Votre certification est inscrite à votre compte.</div>`}
        </div>
      </div>

      ${modules.map(m => html`
        <div class="panneau" style="margin-top:24px">
          <div class="tete"><h3 style="font-size:17px">${m.titre}</h3></div>
          ${m.lecons.map(l => {
            const i = parcours.findIndex(x => x.lecon_id === l.lecon_id);
            const faite = l.lecon_id in faites;
            const ok = estOuverte(i);
            return html`
              <div class="ligne">
                <div>
                  <div style=${ok ? '' : 'opacity:.5'}>${l.lecon_titre}</div>
                  <div class="small muted">
                    ${picto[l.type]}${l.duree_min ? ' · ' + l.duree_min + ' min' : ''}
                    ${faite && faites[l.lecon_id] != null ? ' · ' + faites[l.lecon_id] + ' %' : ''}
                  </div>
                </div>
                ${faite
                  ? html`<div class="row"><span class="tag vert">Achevée</span>
                      <button class="btn sm light" onClick=${()=>setOuverte(l.lecon_id)}>Revoir</button></div>`
                  : ok
                    ? html`<button class="btn sm" onClick=${()=>setOuverte(l.lecon_id)}>Commencer</button>`
                    : html`<span class="tag">Verrouillée</span>`}
              </div>`;
          })}
        </div>`)}
    </div>`;
}


export function Lecon({ lecon, suivante, dejaFaite, fermer, allerSuivante }){
  const [detail, setDetail] = useState(null);
  const [questions, setQuestions] = useState([]);
  const [choix, setChoix] = useState({});      // question_id → Set d'id de réponses
  const [resultat, setResultat] = useState(null);
  const [msg, setMsg] = useState('');
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => { (async () => {
    const { data: l } = await db.from('lecons').select('*').eq('id', lecon.lecon_id).maybeSingle();
    setDetail(l);
    if (l && l.type === 'quiz'){
      const { data: qs } = await db.from('questions').select('*')
        .eq('lecon_id', l.id).order('ordre');
      const avec = await Promise.all((qs||[]).map(async q => {
        const { data: rs } = await db.from('v_choix').select('id,texte,ordre')
          .eq('question_id', q.id).order('ordre');
        return { ...q, choix: rs || [] };
      }));
      setQuestions(avec);
    }
  })(); }, [lecon.lecon_id]);

  if (!detail) return html`<div class="vide">Chargement…</div>`;

  function cocher(qid, rid){
    setChoix(c => {
      const s = new Set(c[qid] || []);
      s.has(rid) ? s.delete(rid) : s.add(rid);
      return { ...c, [qid]: s };
    });
  }

  async function achever(){
    setEnvoi(true); setMsg('');
    const { data, error } = await db.rpc('terminer_lecon', { p_lecon: detail.id });
    setEnvoi(false);
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    suivante ? allerSuivante() : fermer();
  }

  async function corriger(){
    setEnvoi(true); setMsg('');
    const tous = Object.values(choix).flatMap(s => [...s]);
    const { data, error } = await db.rpc('valider_quiz',
      { p_lecon: detail.id, p_choix: tous });
    setEnvoi(false);
    if (error) return setMsg(error.message);
    if (!data.ok) return setMsg(data.message);
    setResultat(data);
  }

  return html`
    <div>
      <a class="small" href="#" onClick=${e=>{e.preventDefault();fermer()}}>← Retour au parcours</a>
      <div class="eyebrow" style="margin-top:16px">${lecon.module_titre}</div>
      <h1 style="margin:6px 0 24px">${detail.titre}</h1>

      ${detail.type === 'lecture' && html`
        <div class="panneau"><div class="corps"
          style="white-space:pre-wrap;font-size:16px;max-width:62ch">${detail.contenu||''}</div></div>`}

      ${detail.type === 'video' && html`
        <div class="panneau"><div class="corps">
          <p><a class="btn" href=${detail.url} target="_blank" rel="noopener">Ouvrir la vidéo ↗</a></p>
          ${detail.contenu && html`<div style="white-space:pre-wrap;margin-top:16px">${detail.contenu}</div>`}
        </div></div>`}

      ${detail.type === 'document' && html`
        <div class="panneau"><div class="corps">
          <p><a class="btn" href=${detail.url} target="_blank" rel="noopener">Ouvrir le document ↗</a></p>
          ${detail.contenu && html`<div style="white-space:pre-wrap;margin-top:16px">${detail.contenu}</div>`}
        </div></div>`}

      ${detail.type === 'quiz' && html`
        <div>
          ${resultat && html`
            <div class=${'alerte ' + (resultat.reussi ? 'ok' : 'err')} style="margin-bottom:24px">
              ${resultat.justes} bonne${resultat.justes>1?'s':''} réponse${resultat.justes>1?'s':''}
              sur ${resultat.total} — ${resultat.score} %.
              ${resultat.reussi
                ? ' Quiz validé.'
                : ' Il en faut ' + resultat.seuil + ' % pour valider. Reprenez vos réponses.'}
            </div>`}

          ${questions.map((q, n) => html`
            <div class="panneau" style="margin-bottom:16px">
              <div class="corps">
                <div class="mono muted">Question ${n+1} sur ${questions.length}</div>
                <div style="font-size:16px;margin:8px 0 16px">${q.enonce}</div>
                ${q.choix.map(r => html`
                  <label class="row" style="text-transform:none;letter-spacing:0;
                      font-size:15px;color:var(--encre);padding:6px 0;margin:0;cursor:pointer">
                    <input type="checkbox" style="width:auto"
                      checked=${(choix[q.id]||new Set()).has(r.id)}
                      onChange=${()=>cocher(q.id, r.id)} />
                    <span>${r.texte}</span>
                  </label>`)}
                ${q.aide && html`<p class="small muted" style="margin:12px 0 0">${q.aide}</p>`}
              </div>
            </div>`)}
          <p class="small muted">Une question peut appeler plusieurs réponses.</p>
        </div>`}

      ${msg && html`<div class="alerte err" style="margin-top:24px">${msg}</div>`}

      <div class="row" style="margin-top:32px">
        ${detail.type === 'quiz'
          ? (resultat && resultat.reussi
              ? (suivante
                  ? html`<button class="btn" onClick=${allerSuivante}>Leçon suivante</button>`
                  : html`<button class="btn" onClick=${fermer}>Terminer le parcours</button>`)
              : html`<button class="btn" onClick=${corriger} disabled=${envoi}>
                  ${envoi ? 'Correction…' : (resultat ? 'Corriger à nouveau' : 'Valider mes réponses')}</button>`)
          : (dejaFaite
              ? (suivante
                  ? html`<button class="btn" onClick=${allerSuivante}>Leçon suivante</button>`
                  : html`<button class="btn" onClick=${fermer}>Retour au parcours</button>`)
              : html`<button class="btn" onClick=${achever} disabled=${envoi}>
                  ${envoi ? 'Enregistrement…' : 'J\u2019ai terminé cette leçon'}</button>`)}
        <button class="btn light" onClick=${fermer}>Revenir au parcours</button>
      </div>
    </div>`;
}


/* =====================================================================
   5 ter. GROUPES DE TRAVAIL
   Le catalogue, l'entrée dans un groupe, les documents, les tâches.
   Un groupe peut exiger une certification : la formation conditionne
   alors l'accès au projet.

   --------------------------------------------------------------------- */
export function Chancellerie({ p }){
  const [onglet, setOnglet] = useState('synthese');
  const [s, setS] = useState(null);
  const [bareme, setBareme] = useState([]);
  const [classement, setClassement] = useState([]);
  const [promos, setPromos] = useState([]);
  const [terr, setTerr] = useState([]);
  const [filtreT, setFiltreT] = useState('');
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b,c,d,e] = await Promise.all([
      db.rpc('chancellerie_synthese'),
      db.from('bareme_points').select('*').order('ordre'),
      db.rpc('classement_merites', { p_territoire: filtreT || null, p_limite: 60 }),
      db.from('promotions').select('*').order('cree_le',{ascending:false}).limit(40),
      db.from('territoires').select('id,nom,echelle').in('echelle',['region','departement']).order('nom')
    ]);
    setS(a.data); setBareme(b.data||[]); setClassement(c.data||[]);
    setPromos(d.data||[]); setTerr(e.data||[]);
  }, [filtreT]);
  useEffect(() => { charger(); }, [charger]);

  async function reglerPoints(cle, points){
    const { data, error } = await db.rpc('regler_bareme',
      { p_cle: cle, p_points: Number(points) });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Barème enregistré. Tous les totaux sont recalculés.');
    charger();
  }

  async function promouvoirMembre(x){
    const motif = prompt('Motif de la promotion (obligatoire)\n\n' +
      x.membre + ' — échelon ' + x.echelon + ' → ' + (x.echelon+1) +
      '\n' + x.points + ' points');
    if (!motif) return;
    const { data, error } = await db.rpc('promouvoir',
      { p_profil: x.profil_id, p_echelon: x.echelon + 1, p_motif: motif });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Promotion arrêtée.'); charger();
  }

  if (!s) return html`<div class="vide">Chargement…</div>`;
  if (s.erreur) return html`<div class="alerte err">${s.erreur}</div>`;

  const aPromouvoir = classement.filter(x => x.atteint);

  return html`
    <div>
      <div class="eyebrow">Chancellerie</div>
      <h1 style="margin:6px 0 8px">Valorisation des compétences</h1>
      <p class="muted" style="max-width:60ch">
        Reconnaître ce qui est donné. Le barème fixe la valeur de chaque
        contribution ; les points se recalculent à chaque lecture, jamais
        stockés. Atteindre un palier ne promeut pas : vous décidez, et vous
        motivez.
      </p>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="chiffres" style="margin:24px 0">
        <div><div class="n" style="font-size:30px">${aPromouvoir.length}</div>
          <div class="l">Paliers atteints</div></div>
        <div><div class="n" style="font-size:30px">${Number(s.heures_mois||0)}</div>
          <div class="l">Heures ce mois</div></div>
        <div><div class="n" style="font-size:30px">${s.certifications_mois}</div>
          <div class="l">Certifications ce mois</div></div>
        <div><div class="n" style="font-size:30px">${s.dormants}</div>
          <div class="l">Membres sans activité</div></div>
      </div>

      <div class="row" style="margin:0 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['synthese','Synthèse'],['classement','Classement'],
           ['promouvoir','À promouvoir'],['distinctions','Distinctions'],
           ['bareme','Barème'],['historique','Décisions']]
          .map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}${k==='promouvoir'&&aPromouvoir.length
              ? ' ('+aPromouvoir.length+')' : ''}</button>`)}
      </div>

      ${onglet === 'synthese' && html`
        <div>
          <div class="panneau">
            <div class="tete"><h3 style="font-size:17px">Répartition par échelon</h3></div>
            <div class="corps">
              ${Object.entries(s.par_echelon || {}).map(([nom, n]) => {
                const max = Math.max(...Object.values(s.par_echelon||{1:1}));
                return html`
                  <div style="padding:7px 0">
                    <div class="spread small">
                      <span>${nom}</span><span class="mono">${n}</span>
                    </div>
                    <div class="jauge" style="margin-top:5px">
                      <i style=${'width:'+Math.round(n/Math.max(max,1)*100)+'%'}></i></div>
                  </div>`;
              })}
            </div>
          </div>
          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">L\u2019année en cours</h3></div>
            <div class="ligne"><span class="muted">Heures de bénévolat déclarées</span>
              <span class="mono">${Number(s.heures_annee||0)} h</span></div>
            <div class="ligne"><span class="muted">Promotions arrêtées</span>
              <span class="mono">${s.promotions_annee}</span></div>
            <div class="ligne"><span class="muted">Membres actifs</span>
              <span class="mono">${s.membres_actifs}</span></div>
            <div class="corps small muted" style="border-top:1px solid var(--filet)">
              Un membre est dit sans activité s\u2019il n\u2019a ouvert aucune application
              depuis 90 jours et n\u2019a déclaré aucune heure depuis trois mois.
              Ce n\u2019est pas un reproche : c\u2019est un signal pour reprendre contact.
            </div>
          </div>
        </div>`}

      ${(onglet === 'classement' || onglet === 'promouvoir') && html`
        <div>
          <div class="field" style="max-width:280px;margin-bottom:20px">
            <label>Périmètre</label>
            <select value=${filtreT} onChange=${e=>setFiltreT(e.target.value)}>
              <option value="">Toute la fédération</option>
              ${terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
            </select>
          </div>
          <div class="panneau" style="overflow-x:auto">
            <table>
              <thead><tr><th></th><th>Membre</th><th>Échelon</th><th>Points</th>
                <th>Heures cette année</th><th>Missions</th><th>Certifications</th>
                <th></th></tr></thead>
              <tbody>
                ${(onglet === 'promouvoir' ? aPromouvoir : classement).map((x, i) => html`
                  <tr>
                    <td class="mono muted">${onglet === 'classement' ? i+1 : ''}</td>
                    <td><div>${x.membre}</div>
                      <div class="small muted">${x.fonction}
                        ${x.territoire ? ' · ' + x.territoire : ''}</div></td>
                    <td><span class="tag or">${x.echelon}</span></td>
                    <td><span class="mono" style="font-size:15px">${x.points}</span>
                      ${x.palier_suivant && html`<span class="small muted">
                        /${x.palier_suivant}</span>`}</td>
                    <td class="mono">${Number(x.heures_annee||0)}</td>
                    <td class="mono">${x.missions}</td>
                    <td class="mono">${x.certifications}</td>
                    <td>${x.atteint && x.palier_suivant
                      ? html`<button class="btn sm"
                          onClick=${()=>promouvoirMembre(x)}>Promouvoir</button>`
                      : ''}</td>
                  </tr>`)}
              </tbody>
            </table>
            ${(onglet === 'promouvoir' ? aPromouvoir : classement).length === 0 && html`
              <div class="vide">${onglet === 'promouvoir'
                ? 'Personne n\u2019a atteint son palier.' : 'Aucun membre.'}</div>`}
          </div>
        </div>`}

      ${onglet === 'distinctions' && html`<${Distinctions} classement=${classement}
        recharger=${charger} setMsg=${setMsg} />`}

      ${onglet === 'bareme' && html`
        <div>
          <p class="small muted" style="margin-bottom:20px;max-width:62ch">
            Modifier une valeur recalcule aussitôt les totaux de tous les
            membres. Rien n\u2019est stocké : personne ne perd de points, les
            équilibres changent simplement.
          </p>

          <${BaremeEchelons} setMsg=${setMsg} />

          <h3 style="font-size:17px;margin-bottom:12px">Valeur des contributions</h3>
          <div class="panneau">
            ${bareme.map(b => html`
              <div class="ligne">
                <div style="flex:1;min-width:220px">
                  <div>${b.libelle}</div>
                  <div class="small muted">${b.unite}
                    ${b.maj_le ? ' · révisé le ' + jour(b.maj_le) : ''}</div>
                </div>
                <div class="row" style="gap:8px">
                  <input type="number" min="0" max="500" defaultValue=${b.points}
                    style="width:90px;text-align:right"
                    onBlur=${e=>reglerPoints(b.cle, e.target.value)} />
                  <span class="small muted">points</span>
                </div>
              </div>`)}
          </div>
          <div class="panneau" style="margin-top:24px">
            <div class="tete"><h3 style="font-size:17px">Paliers d\u2019échelon</h3></div>
            <div class="corps small muted">
              Les seuils se règlent dans la table <span class="mono">echelons</span>.
              Modifier un seuil ne rétrograde jamais personne : un échelon acquis
              reste acquis jusqu\u2019à décision motivée.
            </div>
          </div>
        </div>`}

      ${onglet === 'historique' && html`
        <div class="panneau">
          ${promos.length === 0
            ? html`<div class="vide">Aucune promotion arrêtée.</div>`
            : promos.map(x => {
              const m = classement.find(c => c.profil_id === x.profil_id);
              return html`
                <div class="ligne">
                  <div style="flex:1;min-width:220px">
                    <div>${m ? m.membre : 'Membre'} — échelon ${x.ancien} → ${x.nouveau}</div>
                    <div class="small muted">${x.motif}</div>
                  </div>
                  <div class="row">
                    <span class="tag or">${x.points} pts</span>
                    <span class="small muted">${jour(x.cree_le)}</span>
                  </div>
                </div>`;
            })}
        </div>`}
    </div>`;
}


/* =====================================================================
   VIE STATUTAIRE
   Un mandat électif n'est pas une fonction opérationnelle. Le mandat
   vient du vote et a un terme ; la fonction vient de la nomination et
   se retire par décision.

   --------------------------------------------------------------------- */
export function Distinctions({ classement, recharger, setMsg }){
  const [types, setTypes] = useState([]);
  const [recues, setRecues] = useState([]);
  const [f, setF] = useState({profil:'', type:'felicitations', motif:'', texte:'', publique:true});
  const [q, setQ] = useState('');

  const charger = useCallback(async () => {
    const [a, b] = await Promise.all([
      db.from('types_distinction').select('*').eq('actif',true).order('ordre'),
      db.from('distinctions').select('*, types_distinction(nom,couleur)')
        .is('retiree_le', null).order('decernee_le',{ascending:false}).limit(50)
    ]);
    setTypes(a.data||[]); setRecues(b.data||[]);
  }, []);
  useEffect(() => { charger(); }, [charger]);

  async function decerner(e){
    e.preventDefault();
    const { data, error } = await db.rpc('decerner_distinction', {
      p_profil: f.profil, p_type: f.type, p_motif: f.motif,
      p_texte: f.texte || null, p_publique: f.publique
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({profil:'', type:'felicitations', motif:'', texte:'', publique:true});
    setMsg('Distinction décernée.'); charger(); recharger && recharger();
  }

  const nomDe = id => (classement.find(c => c.profil_id === id)||{}).membre || 'Membre';
  const candidats = classement.filter(c =>
    (c.membre||'').toLowerCase().includes(q.toLowerCase()));

  return html`
    <div>
      <p class="small muted" style="margin-bottom:20px;max-width:62ch">
        Toute reconnaissance n\u2019attend pas un palier. Une distinction se
        décerne quand elle est méritée, quelle que soit la place au classement —
        et elle bonifie le total de points de son titulaire.
      </p>

      <form onSubmit=${decerner} class="panneau" style="margin-bottom:24px">
        <div class="tete"><h3 style="font-size:17px">Décerner</h3></div>
        <div class="corps stack">
          <div class="field"><label>Membre</label>
            <input placeholder="Rechercher…" value=${q}
              onInput=${e=>setQ(e.target.value)} style="margin-bottom:8px" />
            <select required value=${f.profil}
              onChange=${e=>setF(o=>({...o,profil:e.target.value}))}>
              <option value="">Choisir…</option>
              ${candidats.slice(0,60).map(c => html`
                <option value=${c.profil_id}>${c.membre} — ${c.fonction}
                  ${c.territoire ? ' · '+c.territoire : ''}</option>`)}
            </select></div>
          <div class="field"><label>Nature</label>
            <select value=${f.type} onChange=${e=>setF(o=>({...o,type:e.target.value}))}>
              ${types.map(t => html`<option value=${t.code}>
                ${t.nom}${t.points ? ' (+' + t.points + ' points)' : ''}</option>`)}
            </select>
            ${types.find(t=>t.code===f.type) && html`
              <p class="small muted" style="margin:6px 0 0">
                ${types.find(t=>t.code===f.type).description}</p>`}
          </div>
          <div class="field"><label>Motif</label>
            <textarea required value=${f.motif} style="min-height:80px"
              onInput=${e=>setF(o=>({...o,motif:e.target.value}))}
              placeholder="Ce qui est reconnu, précisément. C\u2019est ce que la personne lira." /></div>
          <div class="field"><label>Texte de la citation</label>
            <textarea value=${f.texte}
              onInput=${e=>setF(o=>({...o,texte:e.target.value}))}
              placeholder="Facultatif — le texte lu en assemblée, s\u2019il y a lieu." /></div>
          <label class="row" style="text-transform:none;letter-spacing:0;font-size:14px;
              color:var(--nuit);margin:0;cursor:pointer">
            <input type="checkbox" style="width:auto" checked=${f.publique}
              onChange=${e=>setF(o=>({...o,publique:e.target.checked}))} />
            <span>Visible des autres membres</span>
          </label>
          <div><button class="btn">Décerner</button></div>
        </div>
      </form>

      <div class="panneau">
        <div class="tete"><h3 style="font-size:17px">Distinctions décernées</h3>
          <span class="tag">${recues.length}</span></div>
        ${recues.length === 0
          ? html`<div class="vide">Aucune distinction décernée.</div>`
          : recues.map(d => html`
            <div class="ligne" style="align-items:flex-start">
              <div style="flex:1;min-width:230px">
                <div class="row" style="gap:8px">
                  <strong>${nomDe(d.profil_id)}</strong>
                  <span class=${'tag '+((d.types_distinction||{}).couleur||'or')}>
                    ${(d.types_distinction||{}).nom || d.type}</span>
                  ${!d.publique && html`<span class="tag">Non publiée</span>`}
                </div>
                <p class="small" style="margin:8px 0 0;max-width:58ch">${d.motif}</p>
                <div class="small muted" style="margin-top:4px">
                  <span class="mono">${d.numero}</span> · ${jour(d.decernee_le)}</div>
              </div>
            </div>`)}
      </div>
    </div>`;
}


export function EditeurFormations({ p }){
  const [liste, setListe] = useState([]);
  const [ouverte, setOuverte] = useState(null);
  const [creation, setCreation] = useState(false);
  const [f, setF] = useState({titre:'', resume:'', description:'',
    niveau_min:'10', duree:'', seuil:'80'});
  const [msg, setMsg] = useState('');

  const charger = useCallback(() =>
    db.from('formations').select('*').order('ordre')
      .then(({data}) => setListe(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function creer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('enregistrer_formation', {
      p_id: null, p_code: null, p_titre: f.titre, p_resume: f.resume || null,
      p_description: f.description || null, p_niveau_min: Number(f.niveau_min),
      p_duree: f.duree ? Number(f.duree) : null, p_seuil: Number(f.seuil||80),
      p_publiee: false, p_ordre: 100, p_image: null, p_prerequis: null
    });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setF({titre:'', resume:'', description:'', niveau_min:'10', duree:'', seuil:'80'});
    setCreation(false); setOuverte(data.id); charger();
  }

  if (ouverte) return html`<${EditeurParcours} id=${ouverte}
    fermer=${()=>{ setOuverte(null); charger(); }} />`;

  return html`
    <div>
      <div class="spread">
        <div>
          <div class="eyebrow">Formations</div>
          <h1 style="margin:6px 0 0">Rédiger les parcours</h1>
        </div>
        <button class="btn" onClick=${()=>setCreation(c=>!c)}>
          ${creation ? 'Annuler' : 'Nouvelle formation'}</button>
      </div>
      ${msg && html`<div class="alerte err" style="margin-top:16px">${msg}</div>`}

      ${creation && html`
        <form onSubmit=${creer} class="panneau" style="margin-top:24px">
          <div class="corps stack">
            <div class="field"><label>Titre</label>
              <input required value=${f.titre}
                onInput=${e=>setF(o=>({...o,titre:e.target.value}))} /></div>
            <div class="field"><label>Résumé</label>
              <input value=${f.resume} onInput=${e=>setF(o=>({...o,resume:e.target.value}))}
                placeholder="Une ligne, affichée sur la tuile." /></div>
            <div class="field"><label>Description</label>
              <textarea value=${f.description}
                onInput=${e=>setF(o=>({...o,description:e.target.value}))} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:150px;margin:0">
                <label>Ouverte à partir de</label>
                <select value=${f.niveau_min}
                  onChange=${e=>setF(o=>({...o,niveau_min:e.target.value}))}>
                  <option value="10">Tous les adhérents</option>
                  <option value="40">Animateurs locaux</option>
                  <option value="60">Référents départementaux</option>
                  <option value="80">Direction</option>
                </select></div>
              <div class="field" style="flex:1;min-width:120px;margin:0">
                <label>Durée (min)</label>
                <input type="number" value=${f.duree}
                  onInput=${e=>setF(o=>({...o,duree:e.target.value}))} /></div>
              <div class="field" style="flex:1;min-width:120px;margin:0">
                <label>Seuil des quiz (%)</label>
                <input type="number" min="50" max="100" value=${f.seuil}
                  onInput=${e=>setF(o=>({...o,seuil:e.target.value}))} /></div>
            </div>
            <div><button class="btn">Créer et rédiger</button></div>
          </div>
        </form>`}

      <div class="panneau" style="margin-top:24px">
        ${liste.length === 0
          ? html`<div class="vide">Aucune formation.</div>`
          : liste.map(x => html`
            <div class="ligne" style="cursor:pointer" onClick=${()=>setOuverte(x.id)}>
              <div style="flex:1;min-width:220px">
                <div class="row" style="gap:8px">
                  <span>${x.titre}</span>
                  ${x.publiee
                    ? html`<span class="tag vert">Publiée</span>`
                    : html`<span class="tag">Brouillon</span>`}
                </div>
                <div class="small muted">${x.resume || ''}
                  ${x.duree_min ? ' · ' + x.duree_min + ' min' : ''}
                  · <span class="mono">${x.code}</span></div>
              </div>
              <button class="btn sm light">Rédiger</button>
            </div>`)}
      </div>
    </div>`;
}


export function EditeurParcours({ id, fermer }){
  const [f, setF] = useState(null);
  const [onglet, setOnglet] = useState('contenu');
  const [verif, setVerif] = useState(null);
  const [suivi, setSuivi] = useState([]);
  const [lecon, setLecon] = useState(null);
  const [msg, setMsg] = useState('');

  const charger = useCallback(async () => {
    const [a,b,c] = await Promise.all([
      db.rpc('formation_complete', { p_formation: id }),
      db.rpc('verifier_formation', { p_formation: id }),
      db.rpc('suivi_formation', { p_formation: id })
    ]);
    setF(a.data); setVerif(b.data); setSuivi(c.data||[]);
  }, [id]);
  useEffect(() => { charger(); }, [charger]);

  const appel = async (fn, args, ok) => {
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (!data.ok){ setMsg('Erreur : ' + data.message); return false; }
    if (ok) setMsg(ok);
    charger(); return data;
  };

  if (!f) return html`<div class="vide">Chargement…</div>`;
  if (f.erreur) return html`<div class="alerte err">${f.erreur}</div>`;
  const fo = f.formation;

  if (lecon) return html`<${EditeurLecon} lecon=${lecon}
    fermer=${()=>{ setLecon(null); charger(); }} />`;

  async function publier(){
    if (!verif.publiable && !fo.publiee){
      return setMsg('Erreur : corrigez d\u2019abord les points signalés.');
    }
    await appel('enregistrer_formation', {
      p_id: id, p_code: fo.code, p_titre: fo.titre, p_resume: fo.resume,
      p_description: fo.description, p_niveau_min: fo.niveau_min,
      p_duree: fo.duree_min, p_seuil: fo.seuil_quiz, p_publiee: !fo.publiee,
      p_ordre: fo.ordre, p_image: null, p_prerequis: fo.prerequis
    }, fo.publiee ? 'Formation dépubliée.' : 'Formation publiée.');
  }

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Toutes les formations</button>
      <div class="spread" style="margin-top:12px">
        <div>
          <h1 style="font-size:28px">${fo.titre}</h1>
          <div class="small muted" style="margin-top:4px">
            <span class="mono">${fo.code}</span>
            · ${f.inscrits} membre${f.inscrits>1?'s':''} engagé${f.inscrits>1?'s':''}
          </div>
        </div>
        <div class="row">
          ${fo.publiee
            ? html`<span class="tag vert">Publiée</span>`
            : html`<span class="tag">Brouillon</span>`}
          <button class=${'btn sm '+(fo.publiee?'light':'')} onClick=${publier}>
            ${fo.publiee ? 'Dépublier' : 'Publier'}</button>
        </div>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      ${verif && !verif.publiable && html`
        <div class="alerte err" style="margin-top:20px">
          <strong>À corriger avant publication :</strong>
          <ul style="margin:8px 0 0;padding-left:18px">
            ${(verif.soucis||[]).map(x => html`<li class="small">${x}</li>`)}
          </ul>
        </div>`}

      <div class="row" style="margin:28px 0 24px;gap:0;border-bottom:1px solid var(--filet)">
        ${[['contenu','Contenu'],['reglages','Réglages'],
           ['suivi','Qui suit ('+suivi.length+')']].map(([k,t]) => html`
          <button class="btn light" style=${'border:0;border-bottom:2px solid '+
            (onglet===k?'var(--bordeaux)':'transparent')+';border-radius:0;background:transparent'}
            onClick=${()=>setOnglet(k)}>${t}</button>`)}
      </div>

      ${onglet === 'contenu' && html`
        <div>
          ${(f.modules||[]).map((m, im) => html`
            <div class="panneau" style="margin-bottom:16px">
              <div class="tete">
                <div style="flex:1">
                  <input defaultValue=${m.titre} style="font-family:var(--titre);
                    font-weight:700;font-size:16px;border-color:transparent;padding:4px 6px"
                    onBlur=${e=>appel('enregistrer_module',
                      { p_id: m.id, p_formation: id, p_titre: e.target.value,
                        p_resume: m.resume })} />
                  <input defaultValue=${m.resume||''} placeholder="Résumé du module"
                    style="font-size:13px;border-color:transparent;padding:2px 6px;
                           color:var(--gris)"
                    onBlur=${e=>appel('enregistrer_module',
                      { p_id: m.id, p_formation: id, p_titre: m.titre,
                        p_resume: e.target.value })} />
                </div>
                <div class="row" style="gap:4px">
                  <button class="btn sm light" disabled=${im===0}
                    onClick=${()=>appel('deplacer',{p_table:'module',p_id:m.id,p_sens:-1})}>↑</button>
                  <button class="btn sm light" disabled=${im===(f.modules||[]).length-1}
                    onClick=${()=>appel('deplacer',{p_table:'module',p_id:m.id,p_sens:1})}>↓</button>
                  <button class="btn sm light" onClick=${()=>{
                    if (confirm('Supprimer « ' + m.titre + ' » ?'))
                      appel('supprimer_element',{p_table:'module',p_id:m.id},'Module supprimé.');
                  }}>Supprimer</button>
                </div>
              </div>

              ${(m.lecons||[]).map((l, il) => html`
                <div class="ligne">
                  <div style="flex:1;min-width:200px;cursor:pointer"
                    onClick=${()=>setLecon(l)}>
                    <div class="row" style="gap:8px">
                      <span>${l.titre}</span>
                      <span class="tag">${TYPES_LECON[l.type]||l.type}</span>
                      ${l.type === 'quiz' && html`<span class="tag">
                        ${(l.questions||[]).length} question(s)</span>`}
                    </div>
                    <div class="small muted">
                      ${l.duree_min ? l.duree_min + ' min' : 'sans durée'}
                      ${l.faites > 0 ? ' · achevée par ' + l.faites + ' membre(s)' : ''}
                    </div>
                  </div>
                  <div class="row" style="gap:4px">
                    <button class="btn sm light" disabled=${il===0}
                      onClick=${()=>appel('deplacer',{p_table:'lecon',p_id:l.id,p_sens:-1})}>↑</button>
                    <button class="btn sm light" disabled=${il===(m.lecons||[]).length-1}
                      onClick=${()=>appel('deplacer',{p_table:'lecon',p_id:l.id,p_sens:1})}>↓</button>
                    <button class="btn sm light" onClick=${()=>setLecon(l)}>Ouvrir</button>
                    <button class="btn sm light" onClick=${()=>{
                      if (confirm('Supprimer « ' + l.titre + ' » ?'))
                        appel('supprimer_element',{p_table:'lecon',p_id:l.id},'Leçon supprimée.');
                    }}>×</button>
                  </div>
                </div>`)}

              <div class="corps" style="border-top:1px solid var(--filet)">
                <div class="row" style="gap:8px">
                  ${Object.entries(TYPES_LECON).map(([k,v]) => html`
                    <button class="btn sm light" onClick=${async ()=>{
                      const t = prompt('Titre de la leçon');
                      if (!t) return;
                      const r = await appel('enregistrer_lecon',
                        { p_id:null, p_module:m.id, p_titre:t, p_type:k,
                          p_contenu:null, p_url:null, p_duree:null });
                      if (r) setMsg('Leçon ajoutée.');
                    }}>+ ${v}</button>`)}
                </div>
              </div>
            </div>`)}

          <button class="btn" onClick=${async ()=>{
            const t = prompt('Titre du module');
            if (!t) return;
            appel('enregistrer_module', { p_id:null, p_formation:id,
              p_titre:t, p_resume:null }, 'Module ajouté.');
          }}>Ajouter un module</button>
        </div>`}

      ${onglet === 'reglages' && html`
        <div class="panneau">
          <div class="corps stack">
            <div class="field"><label>Titre</label>
              <input defaultValue=${fo.titre}
                onBlur=${e=>appel('enregistrer_formation',
                  {p_id:id, p_code:fo.code, p_titre:e.target.value, p_resume:fo.resume,
                   p_description:fo.description, p_niveau_min:fo.niveau_min,
                   p_duree:fo.duree_min, p_seuil:fo.seuil_quiz, p_publiee:fo.publiee,
                   p_ordre:fo.ordre, p_image:null, p_prerequis:fo.prerequis},
                  'Enregistré.')} /></div>
            <div class="field"><label>Résumé</label>
              <input defaultValue=${fo.resume||''}
                onBlur=${e=>appel('enregistrer_formation',
                  {p_id:id, p_code:fo.code, p_titre:fo.titre, p_resume:e.target.value,
                   p_description:fo.description, p_niveau_min:fo.niveau_min,
                   p_duree:fo.duree_min, p_seuil:fo.seuil_quiz, p_publiee:fo.publiee,
                   p_ordre:fo.ordre, p_image:null, p_prerequis:fo.prerequis},
                  'Enregistré.')} /></div>
            <div class="field"><label>Description</label>
              <textarea defaultValue=${fo.description||''}
                onBlur=${e=>appel('enregistrer_formation',
                  {p_id:id, p_code:fo.code, p_titre:fo.titre, p_resume:fo.resume,
                   p_description:e.target.value, p_niveau_min:fo.niveau_min,
                   p_duree:fo.duree_min, p_seuil:fo.seuil_quiz, p_publiee:fo.publiee,
                   p_ordre:fo.ordre, p_image:null, p_prerequis:fo.prerequis},
                  'Enregistré.')} /></div>
            <div class="row" style="gap:16px;align-items:flex-start">
              <div class="field" style="flex:1;min-width:130px;margin:0">
                <label>Durée (min)</label>
                <input type="number" defaultValue=${fo.duree_min||''}
                  onBlur=${e=>appel('enregistrer_formation',
                    {p_id:id, p_code:fo.code, p_titre:fo.titre, p_resume:fo.resume,
                     p_description:fo.description, p_niveau_min:fo.niveau_min,
                     p_duree:Number(e.target.value)||null, p_seuil:fo.seuil_quiz,
                     p_publiee:fo.publiee, p_ordre:fo.ordre, p_image:null,
                     p_prerequis:fo.prerequis}, 'Enregistré.')} /></div>
              <div class="field" style="flex:1;min-width:130px;margin:0">
                <label>Seuil des quiz (%)</label>
                <input type="number" min="50" max="100" defaultValue=${fo.seuil_quiz}
                  onBlur=${e=>appel('enregistrer_formation',
                    {p_id:id, p_code:fo.code, p_titre:fo.titre, p_resume:fo.resume,
                     p_description:fo.description, p_niveau_min:fo.niveau_min,
                     p_duree:fo.duree_min, p_seuil:Number(e.target.value),
                     p_publiee:fo.publiee, p_ordre:fo.ordre, p_image:null,
                     p_prerequis:fo.prerequis}, 'Enregistré.')} /></div>
            </div>

            <div style="padding-top:16px;border-top:1px solid var(--filet)">
              <div class="eyebrow" style="margin-bottom:10px">Certification délivrée</div>
              ${f.certification
                ? html`<div class="row" style="gap:8px">
                    <span class="tag or">${f.certification.nom}</span>
                    <span class="small muted">
                      ${f.certification.validite_mois
                        ? 'valable ' + f.certification.validite_mois + ' mois'
                        : 'sans expiration'}</span>
                  </div>`
                : html`<button class="btn sm" onClick=${async ()=>{
                    const nom = prompt('Nom de la certification', fo.titre);
                    if (!nom) return;
                    const v = prompt('Validité en mois (vide = sans expiration)');
                    appel('enregistrer_certification',
                      { p_code:null, p_nom:nom, p_description:null,
                        p_formation:id, p_validite: v ? Number(v) : null },
                      'Certification créée.');
                  }}>Créer la certification</button>`}
            </div>
          </div>
        </div>`}

      ${onglet === 'suivi' && html`
        <div class="panneau" style="overflow-x:auto">
          ${suivi.length === 0
            ? html`<div class="vide">Personne n\u2019a encore commencé.</div>`
            : html`<table>
                <thead><tr><th>Membre</th><th>Territoire</th>
                  <th>Avancement</th><th>Dernière activité</th><th></th></tr></thead>
                <tbody>
                  ${suivi.map(x => html`
                    <tr>
                      <td>${x.membre}</td>
                      <td class="small muted">${x.territoire||'—'}</td>
                      <td style="min-width:150px">
                        <div class="jauge" style="margin:0">
                          <i style=${'width:'+x.pourcent+'%;background:'+
                            (x.pourcent===100?'var(--valide)':'var(--bleu)')}></i></div>
                        <span class="small muted">${x.lecons_faites}/${x.total}</span>
                      </td>
                      <td class="small">${jour(x.derniere_activite)}</td>
                      <td>${x.certifie && html`<span class="tag or">Certifié</span>`}</td>
                    </tr>`)}
                </tbody>
              </table>`}
        </div>`}
    </div>`;
}


export function EditeurLecon({ lecon, fermer }){
  const [l, setL] = useState(lecon);
  const [msg, setMsg] = useState('');

  const appel = async (fn, args, ok) => {
    const { data, error } = await db.rpc(fn, args);
    if (error){ setMsg('Erreur : ' + error.message); return false; }
    if (!data.ok){ setMsg('Erreur : ' + data.message); return false; }
    if (ok) setMsg(ok);
    return data;
  };

  async function recharger(){
    const { data } = await db.from('lecons').select('*').eq('id', l.id).maybeSingle();
    if (!data) return;
    if (data.type === 'quiz'){
      const { data: qs } = await db.from('questions').select('*')
        .eq('lecon_id', l.id).order('ordre');
      const avec = await Promise.all((qs||[]).map(async q => {
        const { data: rs } = await db.from('reponses').select('*')
          .eq('question_id', q.id).order('ordre');
        return { ...q, reponses: rs||[] };
      }));
      setL({ ...data, questions: avec });
    } else setL(data);
  }
  useEffect(() => { recharger(); }, []);

  async function enregistrer(champ, valeur){
    await appel('enregistrer_lecon', {
      p_id: l.id, p_module: l.module_id, p_titre: champ==='titre'?valeur:l.titre,
      p_type: l.type, p_contenu: champ==='contenu'?valeur:l.contenu,
      p_url: champ==='url'?valeur:l.url,
      p_duree: champ==='duree'?(Number(valeur)||null):l.duree_min
    }, 'Enregistré.');
    recharger();
  }

  return html`
    <div>
      <button class="lien-discret" onClick=${fermer}>← Retour au parcours</button>
      <div class="spread" style="margin-top:12px">
        <h1 style="font-size:26px">${l.titre}</h1>
        <span class="tag">${TYPES_LECON[l.type]||l.type}</span>
      </div>
      ${msg && html`<div class=${'alerte '+(msg.startsWith('Erreur')?'err':'ok')}
        style="margin-top:16px">${msg}</div>`}

      <div class="panneau" style="margin-top:24px">
        <div class="corps stack">
          <div class="field"><label>Titre</label>
            <input defaultValue=${l.titre}
              onBlur=${e=>enregistrer('titre', e.target.value)} /></div>
          <div class="field"><label>Durée indicative (min)</label>
            <input type="number" defaultValue=${l.duree_min||''}
              onBlur=${e=>enregistrer('duree', e.target.value)} /></div>

          ${l.type === 'lecture' && html`
            <div class="field"><label>Texte de la leçon</label>
              <textarea defaultValue=${l.contenu||''} style="min-height:320px;font-size:15px"
                onBlur=${e=>enregistrer('contenu', e.target.value)} />
              <p class="small muted" style="margin:6px 0 0">
                Une ligne vide sépare deux paragraphes. Écrivez court : on lit mal
                à l\u2019écran.</p>
            </div>`}

          ${(l.type === 'video' || l.type === 'document') && html`
            <div class="field"><label>Adresse</label>
              <input type="url" defaultValue=${l.url||''}
                onBlur=${e=>enregistrer('url', e.target.value)}
                placeholder=${l.type==='video'?'https://…':'https://drive.google.com/…'} />
            </div>
            <div class="field"><label>Introduction</label>
              <textarea defaultValue=${l.contenu||''}
                onBlur=${e=>enregistrer('contenu', e.target.value)} /></div>`}
        </div>
      </div>

      ${l.type === 'quiz' && html`
        <div style="margin-top:24px">
          ${(l.questions||[]).map((q, iq) => html`
            <div class="panneau" style="margin-bottom:16px">
              <div class="tete">
                <div style="flex:1">
                  <textarea defaultValue=${q.enonce} style="min-height:52px;
                    border-color:transparent;font-size:15px;padding:6px"
                    onBlur=${async e=>{
                      await appel('enregistrer_question',
                        { p_id:q.id, p_lecon:l.id, p_enonce:e.target.value, p_aide:q.aide });
                      recharger();
                    }} />
                </div>
                <div class="row" style="gap:4px">
                  <button class="btn sm light" disabled=${iq===0}
                    onClick=${async ()=>{ await appel('deplacer',
                      {p_table:'question',p_id:q.id,p_sens:-1}); recharger(); }}>↑</button>
                  <button class="btn sm light"
                    disabled=${iq===(l.questions||[]).length-1}
                    onClick=${async ()=>{ await appel('deplacer',
                      {p_table:'question',p_id:q.id,p_sens:1}); recharger(); }}>↓</button>
                  <button class="btn sm light" onClick=${async ()=>{
                    if (!confirm('Supprimer cette question ?')) return;
                    await appel('supprimer_element',{p_table:'question',p_id:q.id});
                    recharger();
                  }}>×</button>
                </div>
              </div>
              <div class="corps">
                ${(q.reponses||[]).map(r => html`
                  <div class="row" style="gap:10px;padding:5px 0">
                    <input type="checkbox" style="width:auto" checked=${r.correcte}
                      title="Bonne réponse"
                      onChange=${async e=>{
                        await appel('enregistrer_reponse',
                          { p_id:r.id, p_question:q.id, p_texte:r.texte,
                            p_correcte:e.target.checked });
                        recharger();
                      }} />
                    <input defaultValue=${r.texte} style="flex:1"
                      onBlur=${async e=>{
                        await appel('enregistrer_reponse',
                          { p_id:r.id, p_question:q.id, p_texte:e.target.value,
                            p_correcte:r.correcte });
                        recharger();
                      }} />
                    <button class="btn sm light" onClick=${async ()=>{
                      await appel('supprimer_element',{p_table:'reponse',p_id:r.id});
                      recharger();
                    }}>×</button>
                  </div>`)}
                <button class="btn sm light" style="margin-top:8px"
                  onClick=${async ()=>{
                    await appel('enregistrer_reponse',
                      { p_id:null, p_question:q.id, p_texte:'Nouvelle proposition',
                        p_correcte:false });
                    recharger();
                  }}>+ Proposition</button>
                <p class="small muted" style="margin:10px 0 0">
                  Cochez chaque bonne réponse. Une question peut en avoir plusieurs.
                </p>
              </div>
            </div>`)}

          <button class="btn" onClick=${async ()=>{
            const e = prompt('Énoncé de la question');
            if (!e) return;
            await appel('enregistrer_question',
              { p_id:null, p_lecon:l.id, p_enonce:e, p_aide:null }, 'Question ajoutée.');
            recharger();
          }}>Ajouter une question</button>
        </div>`}
    </div>`;
}


/* =====================================================================
   PASSEPORT D'ENGAGEMENT
   Le relevé qu'un bénévole peut présenter ailleurs — CV, VAE, dossier
   de candidature. C'est la contrepartie de ce qu'il donne.

   ===================================================================== */
export function BaremeEchelons({ setMsg }){
  const [l, setL] = useState([]);
  const [edit, setEdit] = useState(null);
  const [f, setF] = useState({});

  const charger = useCallback(() =>
    db.rpc('bareme_echelons').then(({data}) => setL(data||[])), []);
  useEffect(() => { charger(); }, [charger]);

  async function enregistrer(e){
    e.preventDefault();
    const { data, error } = await db.rpc('regler_echelon', {
      p_niveau: edit, p_nom: f.nom, p_points: Number(f.points) || 0,
      p_ouvre: f.ouvre || null, p_description: f.description || null });
    if (error) return setMsg('Erreur : ' + error.message);
    if (!data.ok) return setMsg('Erreur : ' + data.message);
    setMsg('Échelon mis à jour.'); setEdit(null); charger();
  }

  return html`
    <div class="panneau" style="margin-bottom:24px">
      <div class="tete"><h3 style="font-size:17px">Barème des échelons</h3></div>
      <div class="corps small muted" style="padding-bottom:0">
        La terminologie de la progression appartient à la fédération, pas au
        code. Changer un nom ici le change partout — passeport, engagement,
        annuaire, promotions.
      </div>
      ${l.map(e => html`
        <div key=${e.niveau}>
          <div class="ligne" style="align-items:flex-start">
            <div style="flex:1;min-width:220px">
              <div class="row" style="gap:8px;flex-wrap:wrap">
                <span class="mono muted small">${e.niveau}</span>
                <span style="font-weight:600">${e.nom}</span>
                <span class="tag">${e.points} pts</span>
                <span class="small muted">${e.membres} membre(s)</span>
              </div>
              ${e.ouvre && html`<div class="small muted" style="margin-top:3px">
                Ouvre : ${e.ouvre}</div>`}
              ${e.description && html`<div class="small" style="margin-top:3px">
                ${e.description}</div>`}
            </div>
            <button class="btn sm light" onClick=${()=>{
              setEdit(edit===e.niveau ? null : e.niveau);
              setF({ nom:e.nom, points:e.points, ouvre:e.ouvre||'',
                     description:e.description||'' });
            }}>${edit===e.niveau ? 'Fermer' : 'Modifier'}</button>
          </div>
          ${edit === e.niveau && html`
            <form class="corps stack" onSubmit=${enregistrer}
              style="background:var(--papier);border-bottom:1px solid var(--filet)">
              <div class="row" style="gap:16px;align-items:flex-start">
                <div class="field" style="flex:2;min-width:180px;margin:0">
                  <label>Nom</label>
                  <input value=${f.nom}
                    onInput=${ev=>setF(o=>({...o,nom:ev.target.value}))} /></div>
                <div class="field" style="flex:0 0 130px;margin:0">
                  <label>Seuil (points)</label>
                  <input type="number" min="0" value=${f.points}
                    onInput=${ev=>setF(o=>({...o,points:ev.target.value}))} /></div>
              </div>
              <div class="field" style="margin:0"><label>Ce que l\u2019échelon ouvre</label>
                <input value=${f.ouvre}
                  onInput=${ev=>setF(o=>({...o,ouvre:ev.target.value}))} /></div>
              <div class="field"><label>Description</label>
                <input value=${f.description}
                  onInput=${ev=>setF(o=>({...o,description:ev.target.value}))} /></div>
              <div><button class="btn sm">Enregistrer</button></div>
            </form>`}
        </div>`)}
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
