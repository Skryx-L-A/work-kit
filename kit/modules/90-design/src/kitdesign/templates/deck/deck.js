// kit-design HTML deck. Keys: arrows/space/PageUp/PageDown, Home/End, n = speaker notes,
// f = fullscreen. The slide number is kept in the URL (#3). Print to PDF: one slide per page.
(function () {
  var slides = Array.prototype.slice.call(document.querySelectorAll(".slide"));
  var deck = document.querySelector(".deck");
  var current = 0;

  function fit() {
    var s = Math.min(window.innerWidth / 1280, window.innerHeight / 720);
    deck.style.transform = "translate(-50%, -50%) scale(" + s + ")";
  }
  function show(i) {
    current = Math.max(0, Math.min(slides.length - 1, i));
    slides.forEach(function (el, n) { el.classList.toggle("active", n === current); });
    if (location.hash !== "#" + (current + 1)) history.replaceState(null, "", "#" + (current + 1));
  }
  document.addEventListener("keydown", function (e) {
    var k = e.key;
    if (k === "ArrowRight" || k === "ArrowDown" || k === " " || k === "PageDown") show(current + 1);
    else if (k === "ArrowLeft" || k === "ArrowUp" || k === "PageUp") show(current - 1);
    else if (k === "Home") show(0);
    else if (k === "End") show(slides.length - 1);
    else if (k === "n") document.body.classList.toggle("show-notes");
    else if (k === "f" && document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
    else return;
    e.preventDefault();
  });
  document.addEventListener("click", function (e) {
    if (e.target.closest("a")) return;
    show(current + (e.clientX < window.innerWidth / 3 ? -1 : 1));
  });
  window.addEventListener("resize", fit);
  window.addEventListener("hashchange", function () { show(parseInt(location.hash.slice(1), 10) - 1 || 0); });
  fit();
  show(parseInt(location.hash.slice(1), 10) - 1 || 0);
})();
