import { h, render } from 'https://esm.sh/preact@10.19.3';
import { useState, useEffect, useCallback } from 'https://esm.sh/preact@10.19.3/hooks';
import htm from 'https://esm.sh/htm@3.1.1';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

// Réexportés pour que les autres modules n'aient pas à connaître
// l'adresse d'esm.sh : la version de Preact se change ici seulement.
export { h, render, useState, useEffect, useCallback, createClient };


export const html = htm.bind(h);

/* =====================================================================
   1. CONNEXION À LA BASE
   Ces deux valeurs sont publiques par conception : elles sont faites
   pour vivre dans le navigateur. La clé « secret » ne quitte jamais
   le tableau de bord Supabase.

   ===================================================================== */
export const SUPABASE_URL = 'https://ibxydmtqdyynteiopjiv.supabase.co';

export const SUPABASE_KEY = 'sb_publishable_A-2UHxGyxQ1--eEnsULBlQ_eyebc9dh';


export const db = createClient(SUPABASE_URL, SUPABASE_KEY);


/* Liens externes de la fédération -------------------------------------- */
export const EXTERNE = {
  webmail:   'https://mail.google.com/a/ffce-asso.fr',
  drive:     'https://drive.google.com/drive/u/0/',
  agenda:    'https://calendar.google.com/',
  adhesion:  ''   // adresse de la campagne HelloAsso, à coller ici
};

/* =====================================================================
   2. PETITS OUTILS

   ===================================================================== */
export const jour = d => d ? new Date(d).toLocaleDateString('fr-FR',
  {day:'numeric',month:'long',year:'numeric'}) : '—';

export const initiales = p => ((p?.prenom?.[0]||'') + (p?.nom?.[0]||'')).toUpperCase() || '?';

export const nomComplet = p => [p?.prenom, p?.nom].filter(Boolean).join(' ') || p?.email || 'Sans nom';


export function useRoute(){
  const [route, setRoute] = useState(location.hash.slice(1) || '/');
  useEffect(() => {
    const f = () => { setRoute(location.hash.slice(1) || '/'); window.scrollTo(0,0); };
    addEventListener('hashchange', f);
    return () => removeEventListener('hashchange', f);
  }, []);
  return route;
}

export const aller = r => { location.hash = r; };

/* =====================================================================
   3. VITRINE PUBLIQUE

   ===================================================================== */

/* Le maillage : la fédération est un réseau de territoires. Le motif du
   héros le dit littéralement — des points reliés, densité variable. */
export function Maillage(){
  const pts = [];
  for(let i=0;i<44;i++){
    pts.push({ x: (i*137.5)%100, y: ((i*61.8)%100), r: i%7===0 ? 3 : 1.6 });
  }
  return html`
    <svg class="maillage" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
      ${pts.map((p,i)=> i<pts.length-1 && html`
        <line x1=${p.x} y1=${p.y} x2=${pts[i+1].x} y2=${pts[i+1].y}
              stroke="#E5E7EB" stroke-width=".14" />`)}
      ${pts.map((p,i)=> html`<circle cx=${p.x} cy=${p.y} r=${p.r/8}
              fill=${p.r>2 ? (i%3===0 ? '#A5053C' : '#00325B') : '#B0B8C1'} />`)}
    </svg>`;
}


/* --- Logo -------------------------------------------------------------
   La charte interdit toute modification du logo. On affiche donc le
   fichier officiel (logo.png, à déposer à la racine du dépôt). S'il est
   absent, repli sur le sigle composé en Raleway Black — jamais sur une
   imitation du symbole.

   --------------------------------------------------------------------- */
export function Logo({ href = '#/', baseline = true, clair = false }){
  const [image, setImage] = useState(true);
  // Le logo porte déjà le sigle et la dénomination : rien ne doit
  // l'accompagner. Le texte n'apparaît que si le fichier est absent.
  if (image) return html`
    <a class="logo" href=${href}>
      <img src=${clair ? 'logo-blanc.png' : 'logo.png'} alt="FFCE — Fédération française pour la citoyenneté et l\u2019égalité des chances"
        onError=${() => setImage(false)} />
    </a>`;
  return html`
    <a class="logo" href=${href}>
      <span>
        <span class="sigle">FFCE</span>
        ${baseline && html`<span class="baseline">
          Fédération française pour la citoyenneté<br/>et l\u2019égalité des chances
        </span>`}
      </span>
    </a>`;
}

   --------------------------------------------------------------------- */
export function Portrait({ chemin, nom, taille = 40 }){
  const [url, setUrl] = useState(null);
  useEffect(() => { (async () => {
    if (!chemin) return;
    const { data } = await db.storage.from('portraits').createSignedUrl(chemin, 3600);
    if (data) setUrl(data.signedUrl);
  })(); }, [chemin]);

  const style = `width:${taille}px;height:${taille}px;border-radius:50%;
    flex:0 0 ${taille}px;object-fit:cover;display:block;border:1px solid var(--filet)`;

  if (url) return html`<img src=${url} alt="" style=${style} />`;
  return html`
    <span style=${style + `;background:var(--bleu);color:#fff;display:flex;
      align-items:center;justify-content:center;font-family:var(--titre);
      font-weight:900;font-size:${Math.round(taille*0.38)}px;letter-spacing:.02em`}>
      ${initiales({prenom: (nom||'').split(' ')[0], nom: (nom||'').split(' ')[1]})}
    </span>`;
}

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


/* --- Progression : les points d'échelon ------------------------------- */
export function Progression(){
  const [x, setX] = useState(null);
  const [ouvert, setOuvert] = useState(false);
  useEffect(() => { db.rpc('points_membre').then(({data}) => setX(data)); }, []);
  if (!x) return null;

  const socle = Number(x.palier_actuel || 0);
  const cible = x.prochain ? Number(x.prochain.points) : null;
  const pct = cible ? Math.min(Math.round((x.total - socle) / (cible - socle) * 100), 100) : 100;

  return html`
    <div class="panneau">
      <div class="tete">
        <div class="row" style="gap:8px">
          <h3 style="font-size:17px">Échelon ${x.echelon} · ${x.echelon_nom}</h3>
          <${Info} texte="Les points se calculent à la lecture, jamais stockés : ils sont donc toujours justes. Atteindre un palier ne promeut pas automatiquement — la Direction générale décide, et doit motiver." />
        </div>
        <span style="font-family:var(--titre);font-weight:900;font-size:26px;
                     color:var(--bordeaux);line-height:1">${x.total}
          <span style="font-size:13px;color:var(--gris);font-weight:700"> pts</span></span>
      </div>
      <div class="corps">
        ${x.prochain
          ? html`
            <div class="spread small">
              <span class="muted">Vers ${x.prochain.nom}</span>
              <span class="mono">${x.total} / ${cible}</span>
            </div>
            <div class="jauge" style="margin-top:8px;height:6px">
              <i style=${'width:'+pct+'%;background:var(--bordeaux)'}></i></div>
            ${x.prochain.ouvre && html`<p class="small muted" style="margin:10px 0 0">
              Cet échelon ouvre : ${x.prochain.ouvre}</p>`}
            ${x.atteint_le_palier && html`<div class="alerte ok" style="margin-top:12px">
              Vous avez atteint le palier. La Direction générale examinera votre
              progression.</div>`}`
          : html`<p class="small muted" style="margin:0">
              Vous occupez le dernier échelon de la fédération.</p>`}

        <button class="lien-discret" style="margin-top:14px"
          onClick=${()=>setOuvert(o=>!o)}>
          ${ouvert ? 'Masquer le détail' : 'D\u2019où viennent mes points ?'}</button>
        ${ouvert && html`
          <div style="margin-top:12px">
            ${Object.entries(x.detail).map(([k,v]) => html`
              <div class="spread small" style="padding:4px 0">
                <span class="muted">${k}</span><span class="mono">${v}</span>
              </div>`)}
          </div>`}
      </div>
    </div>`;
}


/* --- Ce qui attend : la file de travail personnelle -------------------
   Les alertes se perdaient au fond des onglets. Elles remontent ici,
   en tête du tableau de bord, triées par urgence.

   ===================================================================== */

export const EURO = n => (Number(n)||0).toLocaleString('fr-FR',
  {style:'currency', currency:'EUR'});


export const ETAT_NOTE = {
  brouillon: ['Brouillon', ''],
  deposee:   ['Déposée', 'bleu'],
  a_completer:['À compléter', 'or'],
  instruite: ['Avis favorable', 'bleu'],
  ordonnancee:['Ordonnancée', 'vert'],
  payee:     ['Payée', 'vert'],
  refusee:   ['Refusée', 'rouge']
};

export const etatNote = st => {
  const [t, c] = ETAT_NOTE[st] || [st, ''];
  return html`<span class=${'tag '+c}>${t}</span>`;
};


export const CATEGORIES = {
  transport:'Transport', kilometres:'Indemnité kilométrique', repas:'Repas',
  hebergement:'Hébergement', materiel:'Matériel', autre:'Autre'
};

export const MESURES = {
  classement:          'Classement sans suite',
  rappel_regles:       'Rappel des règles',
  avertissement:       'Avertissement',
  suivi_usages:        'Suivi des usages',
  retrait_habilitation:'Retrait des habilitations',
  suspension:          'Suspension du compte',
  radiation:           'Radiation'
};

export const GRAVITE = { faible:['Faible',''], moyenne:['Moyenne','bleu'], elevee:['Élevée','rouge'] };

export const ETAPES = ['ouvert','instruction','decision','notifie','recours','clos'];

export const ETAPE_NOM = {
  ouvert:'Dossier ouvert', instruction:'Instruction en cours',
  decision:'Décision prise', notifie:'Décision notifiée',
  recours:'Recours en examen', clos:'Dossier clos'
};

   ===================================================================== */

/* Une explication brève, à la demande. Pas un long texte : une phrase
   au moment où la question se pose. */
export function Info({ texte }){
  const [ouvert, setOuvert] = useState(false);
  return html`
    <span style="position:relative;display:inline-block">
      <button onClick=${()=>setOuvert(o=>!o)} aria-label="Explication"
        style="border:1px solid var(--filet);background:#fff;color:var(--gris);
               width:17px;height:17px;border-radius:50%;font-size:11px;
               line-height:1;padding:0;font-family:var(--titre);font-weight:700">i</button>
      ${ouvert && html`
        <span onClick=${()=>setOuvert(false)} style="position:absolute;z-index:60;
          left:0;top:22px;width:270px;padding:12px 14px;background:#fff;
          border:1px solid var(--nuit);border-radius:2px;font-size:13px;
          line-height:1.45;color:var(--nuit);font-weight:400;text-transform:none;
          letter-spacing:0;display:block">${texte}</span>`}
    </span>`;
}

/* --- Fiche membre ------------------------------------------------------
   Trois paliers. Les coordonnées ne sortent que si on les demande, et
   la demande est tracée — c'est ce qui rend la trace honnête.

   ===================================================================== */

export const MOIS = ['janvier','février','mars','avril','mai','juin','juillet',
              'août','septembre','octobre','novembre','décembre'];

export const nomMois = d => { const x = new Date(d); return MOIS[x.getMonth()] + ' ' + x.getFullYear(); };

   --------------------------------------------------------------------- */
export const SECTIONS_DOSSIER = [
  ['identite',    'Vous',            'Nom, téléphone, rattachement'],
  ['coordonnees', 'Vos coordonnées', 'Naissance, ville, code postal'],
  ['engagement',  'Votre engagement','Situation et motivation'],
  ['consentement','Vos accords',     'Statuts et données personnelles']
];

   --------------------------------------------------------------------- */
/* --- Complétude d'un dossier ------------------------------------------ */
export function Completude({ id }){
  const [c, setC] = useState(null);
  useEffect(() => {
    db.rpc('completude_dossier', { p_profil: id || null }).then(({data}) => setC(data));
  }, [id]);
  if (!c) return null;
  return html`
    <div style="margin-top:8px">
      <div class="row" style="gap:8px">
        <div class="jauge" style="flex:1;max-width:180px;margin:0;height:5px">
          <i style=${'width:'+c.pourcent+'%;background:'+
            (c.complet?'var(--valide)':'var(--brun)')}></i></div>
        <span class=${'small '+(c.complet?'':'muted')}
          style=${c.complet?'color:var(--valide)':''}>
          ${c.complet ? 'Dossier complet' : c.pourcent + ' % — manque ' + c.manques.join(', ')}
        </span>
      </div>
    </div>`;
}

   ===================================================================== */

export const CANAUX = { instagram:'Instagram', linkedin:'LinkedIn', facebook:'Facebook',
                 x:'X', site:'Site public', newsletter:'Infolettre', presse:'Presse' };

export const ETAT_PUB = {
  brouillon:['Brouillon',''], a_valider:['À valider','bleu'],
  validee:['Validée','vert'], publiee:['Publiée','vert'],
  refusee:['À reprendre','rouge'], archivee:['Archivée','']
};


/* Adresse publique d'une image du dépôt vitrine. */
export const urlPublique = chemin => chemin
  ? SUPABASE_URL + '/storage/v1/object/public/public/' + chemin : null;


/* Dépôt d'image partagé par la vitrine et la communication. */
export async function deposerImage(fichier, prefixe){
  if (!fichier) return null;
  if (fichier.size > 5 * 1024 * 1024)
    throw new Error('L\u2019image ne doit pas dépasser 5 Mo.');
  const ext = fichier.name.split('.').pop();
  const chemin = prefixe + '/' + Date.now() + '.' + ext;
  const { error } = await db.storage.from('public').upload(chemin, fichier);
  if (error) throw error;
  return chemin;
}

   ===================================================================== */

export const PHASES = ['annoncee','candidatures','scrutin','depouillement','proclamee'];

export const PHASE_NOM = { annoncee:'Convoquée', candidatures:'Appel à candidatures',
  scrutin:'Scrutin ouvert', depouillement:'Dépouillement', proclamee:'Proclamée',
  annulee:'Annulée' };

export const TYPE_AG = { constitutive:'Constitutive', ordinaire:'Ordinaire',
                  extraordinaire:'Extraordinaire' };


/* --- Assistance : signaler, proposer ---------------------------------- */
export const NATURES_TICKET = { probleme:'Un problème', amelioration:'Une amélioration',
                         question:'Une question', donnee:'Une donnée erronée' };

export const ETAT_TICKET = { ouvert:['Reçu',''], pris_en_compte:['Pris en compte','bleu'],
  en_cours:['En cours','bleu'], resolu:['Résolu','vert'],
  refuse:['Écarté','rouge'], differe:['Différé','or'] };

   ===================================================================== */

export const STATUT_PROJET = {
  idee:['Idée',''], preparation:['En préparation','bleu'],
  en_cours:['En cours','vert'], termine:['Terminé',''], abandonne:['Abandonné','rouge']
};

export const STATUT_PROP = {
  deposee:['Déposée',''], a_l_etude:['À l\u2019étude','bleu'],
  retenue:['Retenue','vert'], remontee:['Remontée au national','or'],
  nationale:['Reprise au national','or'], ecartee:['Écartée','rouge']
};

   ===================================================================== */

export const STATUT_EX = { prevision:['Prévision',''], vote:['Voté','bleu'],
  en_cours:['En cours','vert'], arrete:['Arrêté','or'], clos:['Clos',''] };

   ===================================================================== */

export const RESEAUX = {
  instagram:['Instagram','https://www.instagram.com/'],
  facebook:['Facebook','https://www.facebook.com/'],
  linkedin:['LinkedIn','https://www.linkedin.com/'],
  x:['X','https://x.com/compose/post'],
  presse:['Presse',''], newsletter:['Infolettre','']
};

   ===================================================================== */

export const TYPES_LECON = { lecture:'Texte', video:'Vidéo',
                      document:'Document', quiz:'Quiz' };

   ===================================================================== */

export const MERITES = { a_progresser:['À consolider',''], satisfaisant:['Satisfaisant','bleu'],
  remarquable:['Remarquable','or'], exemplaire:['Exemplaire','or'] };

   ===================================================================== */

export const ETAT_INV = { neuf:'Neuf', bon:'Bon état', usage:'Usagé',
                   a_remplacer:'À remplacer', hors_service:'Hors service' };

export const ORIGINE_INV = { catalogue:'Catalogue fédéral', achat_local:'Achat local',
                      don:'Don', investissement:'Investissement' };


/* Les états d'une commande et d'un investissement, avec leur couleur. */
export const etatCmd = s => {
  const t = { brouillon:['Panier',''], a_valider:['En validation','or'],
              deposee:['Déposée','bleu'],
              validee:['Validée','bleu'], expediee:['Expédiée','or'],
              recue:['Reçue','vert'], refusee:['Refusée','rouge'],
              annulee:['Annulée','rouge'] }[s] || [s, ''];
  return html`<span class=${'tag '+t[1]}>${t[0]}</span>`;
};

export const etatInv = s => {
  const t = { deposee:['Déposée','bleu'], instruite:['Instruite','or'],
              ordonnancee:['Ordonnancée','or'], engagee:['Engagée','or'],
              recue:['Reçue','vert'], refusee:['Refusée','rouge'],
              ajournee:['Ajournée','rouge'] }[s] || [s, ''];
  return html`<span class=${'tag '+t[1]}>${t[0]}</span>`;
};

   ===================================================================== */
export const NATURE_REMONTEE = { information:'Information', alerte:'Alerte',
  proposition:'Proposition', arbitrage:'Demande d\u2019arbitrage', contact:'Contact' };

export const TYPE_ACTE = { nomination:'Nomination', delegation:'Délégation',
  decision:'Décision', convocation:'Convocation', motion:'Motion',
  note:'Note de service', abrogation:'Abrogation' };

   ===================================================================== */
export const TYPE_CONTACT = { collectivite:'Collectivité', institution:'Institution',
  entreprise:'Entreprise', fondation:'Fondation', association:'Association',
  media:'Média', elu:'Élu', autre:'Autre' };

export const STATUT_CONTACT = { prospect:['Prospect',''], contact_pris:['Contact pris','bleu'],
  en_relation:['En relation','bleu'], partenaire:['Partenaire','vert'],
  sommeil:['En sommeil','or'], rompu:['Rompue','rouge'] };

export const NATURE_ECHANGE = { rendez_vous:'Rendez-vous', appel:'Appel',
  courriel:'Courriel', courrier:'Courrier', evenement:'Événement', echange:'Échange' };

   ===================================================================== */
export const NATURE_FIL = {
  attente:     ['À traiter',     'var(--rouge)'],
  assemblee:   ['Vie statutaire','var(--bordeaux)'],
  acte:        ['Décision',      'var(--nuit)'],
  publication: ['À relayer',     'var(--action)'],
  mission:     ['Engagement',    'var(--vert)'],
  formation:   ['Formation',     'var(--laiton)'],
  projet:      ['Ma structure',  'var(--bleu)']
};
