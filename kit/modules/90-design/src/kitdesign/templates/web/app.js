// Prototype behaviour: filter, select, show states. Runs from file:// without a server.
(function () {
  var data = window.DATA || [];
  var rows = document.getElementById("rows");
  var table = document.getElementById("table");
  var stateBox = document.getElementById("state");
  var q = document.getElementById("q");
  var status = document.getElementById("status");
  var count = document.getElementById("count");
  var detail = document.getElementById("detail");
  var forced = new URLSearchParams(location.search).get("state");

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function setState(kind, text) {
    stateBox.hidden = !kind;
    stateBox.className = "state" + (kind === "error" ? " error" : "");
    stateBox.textContent = text || "";
    table.hidden = !!kind;
  }
  function render() {
    if (forced === "loading") { count.textContent = ""; return setState("loading", "Loading requests…"); }
    if (forced === "error") { count.textContent = ""; return setState("error", "Requests could not be loaded. Try again or contact the service desk."); }
    var term = q.value.trim().toLowerCase();
    var list = forced === "empty" ? [] : data.filter(function (r) {
      return (!status.value || r.status === status.value) &&
        (!term || (r.id + " " + r.title + " " + r.team).toLowerCase().indexOf(term) >= 0);
    });
    count.textContent = list.length + " of " + data.length;
    if (!list.length) return setState("empty", "No requests match. Clear the search or choose another status.");
    setState(null);
    rows.innerHTML = list.map(function (r) {
      return '<tr tabindex="0" data-id="' + esc(r.id) + '"><td>' + esc(r.id) + "</td><td>" + esc(r.title) + "</td><td>" + esc(r.team) +
        '</td><td><span class="pill" data-s="' + esc(r.status) + '">' + esc(r.status) + '</span></td><td class="num">' + r.age + "</td></tr>";
    }).join("");
  }
  function select(id) {
    var r = data.find(function (x) { return x.id === id; });
    if (!r) return;
    Array.prototype.forEach.call(rows.children, function (tr) { tr.setAttribute("aria-selected", String(tr.dataset.id === id)); });
    detail.innerHTML = '<p class="muted">' + esc(r.id) + "</p><h2>" + esc(r.title) + "</h2><dl><dt>Team</dt><dd>" + esc(r.team) +
      "</dd><dt>Status</dt><dd>" + esc(r.status) + "</dd><dt>Owner</dt><dd>" + esc(r.owner) + "</dd><dt>Age</dt><dd>" + r.age +
      " days</dd></dl><p>" + esc(r.detail) + '</p><button type="button">Assign to me</button>';
  }
  rows.addEventListener("click", function (e) { var tr = e.target.closest("tr"); if (tr) select(tr.dataset.id); });
  rows.addEventListener("keydown", function (e) { if (e.key === "Enter" && e.target.dataset.id) select(e.target.dataset.id); });
  q.addEventListener("input", render);
  status.addEventListener("change", render);
  render();
})();
