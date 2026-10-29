// 세끼 웹 데모: 찍은 시각으로 끼니가 정해지고, 한 끼만 남겨도 연속 기록이 이어진다.
// 규칙은 앱과 같다: MealType.inferred (5~10 아침 · 11~15 점심 · 16~21 저녁 · 그 밖 간식),
// recordableMealType (이미 남긴 끼니면 간식 칸으로), isDayRecorded (한 끼라도 남기면 그날은 기록된 날).
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const here = document.currentScript.src;
  const PHOTO = { breakfast: "07", lunch: "08", dinner: "06", snack: "10" };
  const COLOR = { breakfast: "#FF9500", lunch: "#FFCC00", dinner: "#5E5CE6", snack: "#34C759" };
  const fill = (s, o) => s.replace(/\{(\w+)\}/g, (_, k) => o[k]);
  const clock = min => new Intl.DateTimeFormat(document.documentElement.lang, { hour: "numeric", minute: "2-digit" })
    .format(new Date(2026, 0, 1, 0, min));
  const inferred = min => { const h = Math.floor(min / 60);
    return h >= 5 && h <= 10 ? "breakfast" : h >= 11 && h <= 15 ? "lunch" : h >= 16 && h <= 21 ? "dinner" : "snack"; };
  const BASE = { streak: 6, total: 23 };
  const state = { min: 12 * 60 + 40, entries: [] };
  const recordable = min => { const m = inferred(min);
    return m !== "snack" && !state.entries.some(e => e.meal === m) ? m : "snack"; };

  root.innerHTML = `
    <div class="sk-stage">
      <div class="sk-stats"><span class="sk-streak"></span><span class="sk-total"></span></div>
      <p class="sk-head"></p>
      <ol class="sk-feed" aria-live="polite"></ol>
      <p class="sk-empty">${T.empty}</p>
    </div>
    <div class="sk-controls">
      <label class="sk-clock"><span>${T.clock} <b></b></span>
        <input type="range" min="0" max="1435" step="5"></label>
      <div class="sk-chips">${[8 * 60 + 10, 12 * 60 + 40, 19 * 60 + 5, 23 * 60 + 30]
        .map(m => `<button type="button" class="chip" data-min="${m}">${clock(m)}</button>`).join("")}</div>
      <button type="button" class="sk-record"><svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M9 3 7.2 5H4a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3.2L15 3H9Zm3 5a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 2a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z"/></svg><span></span></button>
      <p class="sk-msg" aria-live="polite"></p>
      <p class="muted small">${T.rule}</p>
      <button type="button" class="chip sk-reset" hidden>${T.reset}</button>
      <p class="muted small">${T.note}</p>
    </div>`;

  const $ = s => root.querySelector(s);
  const range = $("input"), clockEl = $(".sk-clock b"), recordLabel = $(".sk-record span");
  const feed = $(".sk-feed"), empty = $(".sk-empty"), head = $(".sk-head"), msg = $(".sk-msg");
  const streakEl = $(".sk-streak"), totalEl = $(".sk-total"), reset = $(".sk-reset");

  function render() {
    const any = state.entries.length > 0;
    range.value = state.min;
    clockEl.textContent = clock(state.min);
    recordLabel.textContent = fill(T.record, { meal: T.meals[recordable(state.min)] });
    streakEl.textContent = fill(T.streak, { n: BASE.streak + (any ? 1 : 0) });
    totalEl.textContent = fill(T.total, { n: BASE.total + (any ? 1 : 0) });
    head.textContent = fill(T.today, { n: state.entries.length });
    empty.hidden = any; reset.hidden = !any;
    $(".sk-record").disabled = state.entries.length >= 5;
  }

  // 피드는 앱처럼 같은 날 안에서 늦은 기록이 위로 온다.
  function renderFeed() {
    feed.innerHTML = [...state.entries].sort((a, b) => b.min - a.min).map(e => `
      <li style="--meal:${COLOR[e.meal]}">
        <img src="${new URL(`screenshots/seed/${PHOTO[e.meal]}.jpg`, here)}" alt="" width="56" height="56" decoding="async">
        <div><strong>${T.meals[e.meal]}</strong> <span class="muted">${clock(e.min)}</span>
          <em class="${e.done ? "done" : ""}">${e.done ? T.ateAll : T.before}</em></div>
        ${e.done ? "" : `<button type="button" class="sk-done" data-id="${e.id}">${T.ateAll}</button>`}
      </li>`).join("");
  }

  let id = 0;
  $(".sk-record").addEventListener("click", () => {
    const first = state.entries.length === 0;
    state.entries.push({ id: ++id, min: state.min, meal: recordable(state.min), done: false });
    if (first) { msg.textContent = T.kept; streakEl.classList.remove("bump"); void streakEl.offsetWidth; streakEl.classList.add("bump"); }
    renderFeed(); render();
  });
  range.addEventListener("input", () => { state.min = +range.value; render(); });
  root.addEventListener("click", e => {
    const chip = e.target.closest("[data-min]");
    if (chip) { state.min = +chip.dataset.min; render(); }
    const done = e.target.closest(".sk-done");
    if (done) { state.entries.find(x => x.id === +done.dataset.id).done = true; renderFeed(); }
  });
  reset.addEventListener("click", () => { state.entries = []; msg.textContent = ""; renderFeed(); render(); });

  render();
})();
