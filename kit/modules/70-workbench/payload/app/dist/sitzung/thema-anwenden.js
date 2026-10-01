"use strict";
(() => {
  // src/sitzung/thema-anwenden.ts
  var bruecke = window.awbSitzung;
  var sondeEl = document.getElementById("thema-testsonde");
  function themaAnwenden(d) {
    document.documentElement.dataset.thema = d.wirksam;
    document.documentElement.style.setProperty("--zustand-laeuft", d.zustandsfarbenLesbar.laeuft ?? "");
    document.documentElement.style.setProperty("--zustand-wartet", d.zustandsfarbenLesbar.wartet ?? "");
    if (sondeEl) {
      const stil = getComputedStyle(document.documentElement);
      sondeEl.value = JSON.stringify({
        dataThema: document.documentElement.dataset.thema ?? "",
        zustandLaeuft: stil.getPropertyValue("--zustand-laeuft").trim(),
        zustandWartet: stil.getPropertyValue("--zustand-wartet").trim(),
        grund: stil.getPropertyValue("--grund").trim()
      });
    }
  }
  bruecke.onThema(themaAnwenden);
  void bruecke.thema().then(themaAnwenden);
})();
