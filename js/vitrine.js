import { Espace } from './espace.js';
import { Formations } from './formation.js';
import { EXTERNE, Info, Logo, Maillage, Portrait, aller, db, html, jour, nomComplet, render, urlPublique, useEffect, useRoute, useState } from './socle.js';
import { AppelPublic } from './statutaire.js';


export function EntetePublique({ route, session }){
  const [ouvert, setOuvert] = useState(false);
  useEffect(() => { setOuvert(false); }, [route]);
  const liens = [
    ['/', 'Accueil'], ['/association','La fédération'], ['/actions','Nos actions'],
    ['/reseau','Le réseau'], ['/actualites','Actualités'],
    ['/rejoindre','Nous rejoindre'], ['/contact','Contact']
  ];
  return html`
    <header class="entete">
      <hr class="bicolore" />
      <div class="wrap" style="position:relative">
        <${Logo} />
        <nav class=${'nav'+(ouvert?' ouverte':'')}>
          ${liens.map(([r,t]) => html`
            <a href=${'#'+r} class=${route===r?'on':''}>${t}</a>`)}
        </nav>
        <div class="row" style="gap:10px">
          <a class="btn ghost sm" href="#/espace">
            ${session ? 'Mon espace' : 'Se connecter'}
          </a>
          <button class="burger" aria-label="Menu"
            onClick=${()=>setOuvert(o=>!o)}><span></span></button>
        </div>
      </div>
    </header>`;
}


export function Pied({ txt }){
  return html`
    <footer class="pied">
      <hr class="bicolore" />
      <div class="wrap">
        <div class="cols">
          <div>
            <div style="margin-bottom:16px"><${Logo} /></div>
            <p style="max-width:34ch">${txt.nom_legal}</p>
            <p class="mono">${txt.siege}</p>
            <p class="mono">RNA ${txt.rna} · SIREN ${txt.siren}</p>
          </div>
          <div>
            <div class="eyebrow" style="margin-bottom:8px">La fédération</div>
            <a href="#/association">Qui nous sommes</a>
            <a href="#/actions">Nos actions</a>
            <a href="#/reseau">Le réseau</a>
          </div>
          <div>
            <div class="eyebrow" style="margin-bottom:8px">Pratique</div>
            <a href="#/actualites">Actualités</a>
            <a href="#/rejoindre">Nous rejoindre</a>
            <a href="#/contact">Contact</a>
            ${txt.reseaux_instagram && html`
              <a href=${txt.reseaux_instagram} target="_blank" rel="noopener">Instagram ↗</a>`}
            ${txt.reseaux_linkedin && html`
              <a href=${txt.reseaux_linkedin} target="_blank" rel="noopener">LinkedIn ↗</a>`}
            <a href="#/espace">Espace membre</a>
            <a href="#/mentions">Mentions légales</a>
            <a href="#/confidentialite">Confidentialité</a>
          </div>
        </div>
      </div>
    </footer>`;
}

/* Un jeu de blocs administrables, pour n'importe quelle page. */

export function Blocs({ page }){
  const [b, setB] = useState([]);
  useEffect(() => {
    db.rpc('vitrine_blocs', { p_page: page }).then(({data}) => setB(data||[]));
  }, [page]);
  if (b.length === 0) return null;
  return html`
    <div class="cartes">
      ${b.map(x => html`
        <div>
          ${x.image && html`<img src=${urlPublique(x.image)} alt=""
            style="width:100%;height:150px;object-fit:cover;margin-bottom:16px;
                   border:1px solid var(--filet)" />`}
          <h3>${x.titre}</h3>
          <p>${x.contenu||''}</p>
          ${x.lien && html`<p style="margin:12px 0 0">
            <a href=${x.lien}>${x.lien_texte || 'En savoir plus'} →</a></p>`}
        </div>`)}
    </div>`;
}

/* Les actualités, sur l'accueil et sur leur page. */

export function Actualites({ limite = 3, titre = true }){
  const [a, setA] = useState([]);
  useEffect(() => {
    db.rpc('actualites', { p_limite: limite }).then(({data}) => setA(data||[]));
  }, [limite]);
  if (a.length === 0) return null;
  return html`
    <div>
      ${titre && html`<div class="spread" style="margin-bottom:24px">
        <h2>Actualités</h2>
        <a href="#/actualites">Toutes les actualités →</a>
      </div>`}
      <div class="cartes" style="margin-top:0">
        ${a.map(x => html`
          <div>
            ${x.image && html`<img src=${urlPublique(x.image)} alt=""
              style="width:100%;height:170px;object-fit:cover;margin-bottom:16px;
                     border:1px solid var(--filet)" />`}
            <div class="eyebrow" style="margin-bottom:8px">
              ${x.categorie}${x.publie_le ? ' · ' + jour(x.publie_le) : ''}</div>
            <h3><a href=${'#/actualite/'+x.slug}>${x.titre}</a></h3>
            <p>${x.chapo||''}</p>
          </div>`)}
      </div>
    </div>`;
}


export function PageActualites(){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Actualités</div>
        <h1 style="margin:8px 0 32px">Ce que nous faisons, au fil des jours</h1>
        <${Actualites} limite=${30} titre=${false} />
      </div>
    </section>`;
}


export function PageArticle({ slug }){
  const [a, setA] = useState(undefined);
  useEffect(() => {
    db.rpc('article', { p_slug: slug }).then(({data}) => setA(data || null));
  }, [slug]);
  if (a === undefined) return html`<div class="vide" style="padding:120px">Chargement…</div>`;
  if (!a) return html`
    <section class="bloc blanc"><div class="wrap">
      <h1>Article introuvable</h1>
      <p style="margin-top:16px"><a href="#/actualites">← Toutes les actualités</a></p>
    </div></section>`;
  return html`
    <article class="bloc blanc">
      <div class="wrap" style="max-width:760px">
        <a class="small" href="#/actualites">← Toutes les actualités</a>
        <div class="eyebrow" style="margin:24px 0 10px">
          ${a.categorie}${a.publie_le ? ' · ' + jour(a.publie_le) : ''}</div>
        <h1>${a.titre}</h1>
        ${a.chapo && html`<p style="font-size:19px;color:var(--gris);margin-top:20px">
          ${a.chapo}</p>`}
        ${a.image && html`<img src=${urlPublique(a.image)} alt=""
          style="width:100%;margin:32px 0;border:1px solid var(--filet)" />`}
        <div style="white-space:pre-wrap;font-size:17px;margin-top:24px">${a.contenu||''}</div>
        ${a.auteur && html`<p class="small muted" style="margin-top:40px;
          padding-top:20px;border-top:1px solid var(--filet)">Par ${a.auteur}</p>`}
      </div>
    </article>`;
}


export function Accueil({ txt }){
  return html`
    <section class="heros">
      <${Maillage} />
      <div class="wrap">
        <div class="eyebrow" style="margin-bottom:24px">Association déclarée · depuis 2020</div>
        <h1>${txt.accroche}</h1>
        <p>${txt.sous_accroche}</p>
        <div class="row" style="margin-top:36px">
          <a class="btn" href=${txt.hero_bouton_lien || '#/rejoindre'}>
            ${txt.hero_bouton || 'Rejoindre la fédération'}</a>
          <a class="btn ghost" href="#/actions">Voir nos actions</a>
        </div>
      </div>
    </section>

    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Ce que nous faisons</div>
        <h2>${txt.titre_actions || 'Nos terrains d\u2019engagement'}</h2>
        <p class="intro">${txt.intro_actions || ''}</p>
        <${Blocs} page="accueil" />
      </div>
    </section>

    <section class="bloc">
      <div class="wrap">
        <div class="eyebrow">Le réseau en chiffres</div>
        <h2>${txt.titre_chiffres || 'Une fédération de terrain'}</h2>
        <div class="chiffres">
          <div><div class="n">${txt.nb_benevoles}</div><div class="l">Bénévoles engagés</div></div>
          <div><div class="n">${txt.nb_departements}</div><div class="l">Départements couverts</div></div>
          <div><div class="n">${txt.nb_actions}</div><div class="l">Actions menées</div></div>
          <div><div class="n">${txt.nb_jeunes}</div><div class="l">Jeunes touchés</div></div>
        </div>
      </div>
    </section>

    ${txt.afficher_actualites !== 'non' && html`
      <section class="bloc blanc">
        <div class="wrap"><${Actualites} limite=${3} /></div>
      </section>`}

    <section class="bloc nuit">
      <div class="wrap spread">
        <div>
          <h2>${txt.appel_final || 'Un engagement se construit, il ne s\u2019impose pas.'}</h2>
          <p class="intro" style="margin-top:12px">${txt.appel_final_texte || ''}</p>
        </div>
        <a class="btn" style="background:#fff;color:var(--bleu);border-color:#fff"
          href="#/rejoindre">Commencer</a>
      </div>
    </section>`;
}


export function Association({ txt }){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">La fédération</div>
        <h1 style="margin:8px 0 32px">Notre raison d'être</h1>
        <div style="max-width:62ch;font-size:17px">
          <p>${txt.mission}</p>
          <p>${txt.histoire}</p>
        </div>
        <hr class="hr" />
        <div class="cartes" style="margin-top:0">
          <div><h3>Fédérer</h3><p>Réunir des bénévoles autour d'un projet commun,
            partout sur le territoire, sans condition de diplôme ou d'expérience.</p></div>
          <div><h3>Former</h3><p>Donner à chacun les repères et les outils pour
            intervenir sereinement auprès des jeunes.</p></div>
          <div><h3>Agir</h3><p>Mener des actions concrètes, mesurables, avec les
            établissements et les collectivités.</p></div>
        </div>
      </div>
    </section>`;
}


export function Actions(){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Nos actions</div>
        <h1 style="margin:8px 0 16px">Ce que nous menons sur le terrain</h1>
        <p class="intro">Chaque action est portée par une équipe locale et
        soutenue par l'équipe nationale.</p>
        <${Blocs} page="actions" />
      </div>
    </section>`;
}


export function Reseau(){
  const [terr, setTerr] = useState([]);
  const [publics, setPublics] = useState([]);
  useEffect(() => {
    db.from('territoires').select('id,nom,echelle,code,parent_id')
      .in('echelle',['region','departement']).order('nom')
      .then(({data}) => setTerr(data || []));
    // La case « afficher mon nom sur le site public » aboutit ici. Sans
    // cet endroit, elle promettait une publication qui n'existait pas.
    db.from('v_annuaire')
      .select('id,prenom,nom,photo_url,bio,fonction_nom,territoire_nom,niveau')
      .eq('visible_public', true).eq('statut','actif')
      .order('niveau', { ascending:false }).limit(60)
      .then(({data}) => setPublics(data || []));
  }, []);
  const regions = terr.filter(t => t.echelle === 'region');
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Le réseau</div>
        <h1 style="margin:8px 0 16px">Une organisation à quatre échelles</h1>
        <p class="intro">La fédération est structurée du national au local.
        Chaque échelon dispose de ses responsables et de son autonomie d'action.</p>

        <div class="cartes">
          <div><h3>National</h3><p>La Direction générale et les pôles fixent le cap,
            valident les accès et animent le réseau.</p></div>
          <div><h3>Régional</h3><p>Le délégué régional coordonne les référents
            départementaux de sa région.</p></div>
          <div><h3>Départemental</h3><p>Le référent départemental anime les
            responsables locaux et suit les adhérents de son territoire.</p></div>
          <div><h3>Local</h3><p>Le responsable local conduit les actions au plus
            près du terrain, avec ses animateurs.</p></div>
        </div>

        <hr class="hr" />
        <div class="eyebrow" style="margin-bottom:16px">Régions couvertes</div>
        <div class="row">
          ${regions.map(r => html`<span class="tag">${r.nom}</span>`)}
        </div>

        ${publics.length > 0 && html`
          <hr class="hr" />
          <div class="eyebrow" style="margin-bottom:16px">Celles et ceux qui l\u2019animent</div>
          <p class="intro" style="margin-bottom:24px">
            Les membres qui ont choisi de se présenter publiquement.
          </p>
          <div class="tuiles" style="grid-template-columns:repeat(auto-fill,minmax(260px,1fr))">
            ${publics.map(m => html`
              <div class="carte" key=${m.id}>
                <div class="row" style="gap:14px;align-items:flex-start">
                  <${Portrait} chemin=${m.photo_url} nom=${nomComplet(m)} taille=${52} />
                  <div style="min-width:0">
                    <div class="nom" style="font-size:18px">${nomComplet(m)}</div>
                    <div class="poste" style="font-size:14px">${m.fonction_nom}</div>
                    <div class="lieu">${m.territoire_nom || 'National'}</div>
                  </div>
                </div>
                ${m.bio && html`<div class="small" style="margin-top:12px">${m.bio}</div>`}
              </div>`)}
          </div>`}
      </div>
    </section>`;
}


export function Rejoindre(){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Nous rejoindre</div>
        <h1 style="margin:8px 0 16px">Trois étapes, rien de plus</h1>
        <p class="intro">L'adhésion se fait en ligne. Votre compte est ensuite
        vérifié par la Direction générale avant l'ouverture de vos accès.</p>

        <div class="cartes">
          <div>
            <div class="mono" style="color:var(--bleu)">Étape 1</div>
            <h3 style="margin-top:6px">Créer votre compte</h3>
            <p>Nom, adresse et territoire de rattachement. Trois minutes.</p>
          </div>
          <div>
            <div class="mono" style="color:var(--bleu)">Étape 2</div>
            <h3 style="margin-top:6px">Vérification</h3>
            <p>La Direction générale contrôle l'adhésion et ouvre les accès
            correspondant à votre fonction.</p>
          </div>
          <div>
            <div class="mono" style="color:var(--bleu)">Étape 3</div>
            <h3 style="margin-top:6px">Se former, agir</h3>
            <p>Formations, groupes de travail, projets locaux : tout est dans
            votre espace membre.</p>
          </div>
        </div>

        <div class="row" style="margin-top:40px">
          <a class="btn" href="#/inscription">Créer mon compte</a>
          ${EXTERNE.adhesion && html`
            <a class="btn ghost" href=${EXTERNE.adhesion} target="_blank" rel="noopener">
              Régler mon adhésion</a>`}
        </div>
      </div>
    </section>`;
}


export function Contact({ txt }){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <div class="eyebrow">Contact</div>
        <h1 style="margin:8px 0 32px">Nous écrire</h1>
        <div style="max-width:52ch">
          <p>Pour toute question sur la fédération, une action locale ou un
          partenariat :</p>
          <p><a class="mono" style="font-size:16px" href=${'mailto:'+txt.email_contact}>
            ${txt.email_contact}</a></p>
          <hr class="hr" />
          <div class="eyebrow" style="margin-bottom:8px">Siège social</div>
          <p>${txt.siege}</p>
        </div>
      </div>
    </section>`;
}


export function PageTexte({ titre, corps }){
  return html`
    <section class="bloc blanc">
      <div class="wrap">
        <h1 style="margin-bottom:24px">${titre}</h1>
        <div style="max-width:62ch;white-space:pre-wrap">
          ${corps || html`<span class="muted">Ce document n'a pas encore été publié.</span>`}
        </div>
      </div>
    </section>`;
}


/* =====================================================================
   4. CONNEXION ET INSCRIPTION
   ===================================================================== */
export function Connexion(){
  const [email, setEmail] = useState('');
  const [mdp, setMdp] = useState('');
  const [err, setErr] = useState('');
  const [envoi, setEnvoi] = useState(false);

  async function entrer(e){
    e.preventDefault(); setErr(''); setEnvoi(true);
    const { error } = await db.auth.signInWithPassword({ email, password: mdp });
    setEnvoi(false);
    if (error) setErr("Adresse ou mot de passe incorrect.");
    else aller('/espace');
  }

  return html`
    <section class="bloc blanc">
      <div class="wrap" style="max-width:440px">
        <div class="eyebrow">Espace membre</div>
        <h1 style="margin:8px 0 32px">Se connecter</h1>
        <form onSubmit=${entrer} class="stack">
          <div class="field">
            <label for="e">Adresse électronique</label>
            <input id="e" type="email" required value=${email}
              onInput=${e=>setEmail(e.target.value)} autocomplete="email" />
          </div>
          <div class="field">
            <label for="m">Mot de passe</label>
            <input id="m" type="password" required value=${mdp}
              onInput=${e=>setMdp(e.target.value)} autocomplete="current-password" />
          </div>
          ${err && html`<div class="alerte err">${err}</div>`}
          <button class="btn" style="width:100%" disabled=${envoi}>
            ${envoi ? 'Connexion…' : 'Entrer'}</button>
        </form>
        <p class="small muted" style="margin-top:24px">
          Pas encore de compte ? <a href="#/inscription">Créer un compte</a>
        </p>
      </div>
    </section>`;
}


export function Inscription(){
  const [f, setF] = useState({prenom:'',nom:'',email:'',mdp:'',territoire:''});
  const [terr, setTerr] = useState([]);
  const [err, setErr] = useState('');
  const [fait, setFait] = useState(false);
  const [envoi, setEnvoi] = useState(false);
  const maj = (k,v) => setF(o => ({...o, [k]:v}));

  useEffect(() => {
    db.from('territoires').select('id,nom,echelle').eq('echelle','departement')
      .order('code').then(({data}) => setTerr(data || []));
  }, []);

  async function creer(e){
    e.preventDefault(); setErr(''); setEnvoi(true);
    const { data, error } = await db.auth.signUp({
      email: f.email, password: f.mdp,
      options: { data: { prenom: f.prenom, nom: f.nom } }
    });
    if (error){ setErr(error.message); setEnvoi(false); return; }
    if (f.territoire && data.user){
      await db.from('profils').update({ territoire_id: f.territoire }).eq('id', data.user.id);
    }
    setEnvoi(false); setFait(true);
  }

  if (fait) return html`
    <section class="bloc blanc">
      <div class="wrap" style="max-width:520px">
        <h1 style="margin-bottom:16px">Votre demande est enregistrée</h1>
        <div class="alerte ok">
          La Direction générale vérifie votre inscription. Vous recevrez un
          message dès l'ouverture de vos accès. En attendant, connectez-vous et
          complétez votre dossier d'adhésion dans Mon compte : c'est ce qui
          permettra de vous proposer des missions qui vous correspondent.
        </div>
        <p style="margin-top:24px"><a class="btn" href="#/espace">Aller à mon espace</a></p>
      </div>
    </section>`;

  return html`
    <section class="bloc blanc">
      <div class="wrap" style="max-width:520px">
        <div class="eyebrow">Nous rejoindre</div>
        <h1 style="margin:8px 0 32px">Créer mon compte</h1>
        <form onSubmit=${creer} class="stack">
          <div class="row" style="gap:16px">
            <div class="field" style="flex:1;min-width:140px">
              <label for="p">Prénom</label>
              <input id="p" required value=${f.prenom} onInput=${e=>maj('prenom',e.target.value)} />
            </div>
            <div class="field" style="flex:1;min-width:140px;margin-top:0">
              <label for="n">Nom</label>
              <input id="n" required value=${f.nom} onInput=${e=>maj('nom',e.target.value)} />
            </div>
          </div>
          <div class="field">
            <label for="ie">Adresse électronique</label>
            <input id="ie" type="email" required value=${f.email}
              onInput=${e=>maj('email',e.target.value)} autocomplete="email" />
          </div>
          <div class="field">
            <label for="im">Mot de passe</label>
            <input id="im" type="password" required minlength="8" value=${f.mdp}
              onInput=${e=>maj('mdp',e.target.value)} autocomplete="new-password" />
            <p class="small muted" style="margin:6px 0 0">Huit caractères minimum.</p>
          </div>
          <div class="field">
            <label for="it">Département de rattachement</label>
            <select id="it" required value=${f.territoire} onChange=${e=>maj('territoire',e.target.value)}>
              <option value="">Choisir…</option>
              ${terr.map(t => html`<option value=${t.id}>${t.nom}</option>`)}
            </select>
          </div>
          ${err && html`<div class="alerte err">${err}</div>`}
          <button class="btn" style="width:100%" disabled=${envoi}>
            ${envoi ? 'Envoi…' : 'Créer mon compte'}</button>
          <p class="small muted">
            En créant un compte, vous acceptez la
            <a href="#/confidentialite">politique de confidentialité</a>.
          </p>
        </form>
      </div>
    </section>`;
}


/* =====================================================================
   5. ESPACE MEMBRE
   ===================================================================== */

export function CarteFederale({ p, chemin }){
  const e = p.echelon || 1;
  return html`
    <div class="carte">
      <div class="matricule">${p.matricule}</div>
      <div class="nom">${nomComplet(p)}</div>
      <div class="poste">${p.fonction_nom}</div>
      <div class="lieu">${chemin || p.territoire_nom || 'Rattachement à définir'}</div>
      ${p.postes && p.postes.length > 0 && html`
        <div class="row" style="margin-top:10px;gap:6px">
          ${p.postes.map(x => html`<span class=${'tag '+(x.couleur==='neutre'?'':x.couleur)}>
            ${x.nom}${x.territoire_nom ? ' · '+x.territoire_nom : ''}</span>`)}
        </div>`}
      <div class="ech">
        <span class="row" style="gap:6px">
          <span class="tag or">Échelon ${e} · ${p.echelon_nom}</span>
          <${Info} texte="La fonction donne le pouvoir, l'échelon reconnaît le parcours. Les deux sont indépendants : un bénévole de longue date peut être échelon 5 sans encadrer personne." />
        </span>
        <span class="mono muted">${p.statut === 'actif' ? 'Actif' : p.statut}</span>
      </div>
      <div class="jauge"><i style=${`width:${Math.round(e/7*100)}%`}></i></div>
    </div>`;
}


/* =====================================================================
   6. RACINE
   ===================================================================== */
export function Site(){
  const route = useRoute();
  const [session, setSession] = useState(undefined);
  const [txt, setTxt] = useState(null);

  useEffect(() => {
    db.auth.getSession().then(({data}) => setSession(data.session));
    const { data:{ subscription } } = db.auth.onAuthStateChange((_e,s) => setSession(s));
    return () => subscription.unsubscribe();
  }, []);

  useEffect(() => {
    db.from('contenus').select('cle,valeur').then(({data}) =>
      setTxt(Object.fromEntries((data||[]).map(c => [c.cle, c.valeur]))));
  }, []);

  if (session === undefined || txt === null)
    return html`<div class="vide" style="padding:140px">Chargement…</div>`;

  // Espace membre : mise en page propre, sans l'entête publique.
  if (route.startsWith('/espace')){
    if (!session) return html`
      <${EntetePublique} route=${route} session=${session} />
      <${Connexion} />
      <${Pied} txt=${txt} />`;
    const sous = route.replace('/espace','').replace(/^\//,'');
    return html`<${Espace} session=${session} sous=${sous} />`;
  }

  if (route.startsWith('/appel/')){
    return html`
      <${EntetePublique} route=${route} session=${session} />
      <${AppelPublic} token=${route.slice('/appel/'.length)} />
      <${Pied} txt=${txt} />`;
  }

  if (route.startsWith('/actualite/')){
    return html`
      <${EntetePublique} route=${route} session=${session} />
      <${PageArticle} slug=${route.slice('/actualite/'.length)} />
      <${Pied} txt=${txt} />`;
  }

  let page;
  switch (route){
    case '/':                 page = html`<${Accueil} txt=${txt} />`; break;
    case '/association':      page = html`<${Association} txt=${txt} />`; break;
    case '/actions':          page = html`<${Actions} />`; break;
    case '/reseau':           page = html`<${Reseau} />`; break;
    case '/rejoindre':        page = html`<${Rejoindre} />`; break;
    case '/contact':          page = html`<${Contact} txt=${txt} />`; break;
    case '/actualites':       page = html`<${PageActualites} />`; break;
    case '/inscription':      page = session ? html`<${Accueil} txt=${txt} />` : html`<${Inscription} />`; break;
    case '/mentions':         page = html`<${PageTexte} titre="Mentions légales" corps=${txt.mentions} />`; break;
    case '/confidentialite':  page = html`<${PageTexte} titre="Politique de confidentialité" corps=${txt.confidentialite} />`; break;
    default:                  page = html`<${PageTexte} titre="Page introuvable"
                                  corps="Le lien que vous avez suivi ne mène nulle part." />`;
  }

  return html`
    <${EntetePublique} route=${route} session=${session} />
    ${page}
    <${Pied} txt=${txt} />`;
}
