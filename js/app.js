/* =====================================================================
   FFCE — Point d'entrée
   Le navigateur charge ce module ; les autres suivent par leurs
   imports. Aucune compilation : les modules ES sont natifs.

   Un seul montage, ici.
   ===================================================================== */
import { html, render } from './socle.js';
import { Site } from './vitrine.js';

render(html`<${Site} />`, document.getElementById('racine'));
