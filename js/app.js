/* =====================================================================
   FFCE — Point d'entrée
   Le navigateur charge ce module ; les autres suivent par leurs
   imports. Aucune compilation : les modules ES sont natifs depuis 2018.

   Un seul montage, ici. Si un jour la page devait afficher autre chose
   avant l'authentification, c'est le seul endroit à modifier.
   ===================================================================== */
import { html, render } from './socle.js';
import { Site } from './vitrine.js';

render(html`<${Site} />`, document.getElementById('racine'));
