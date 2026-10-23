"use strict";

const app = document.getElementById("app");
const crumbs = document.getElementById("crumbs");
const md = (s) => marked.parse(s || "");
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const enc = encodeURIComponent;

async function api(path, opts = {}) {
  const res = await fetch(path, opts);
  const body = await res.json();
  if (!res.ok) throw Object.assign(new Error(body.error || res.statusText), { status: res.status });
  return body;
}

function post(path, body) {
  return api(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body || {}) });
}

// POST that answers with Server-Sent Events. Calls onLine per output line, resolves with the "done" payload.
async function stream(path, body, onLine) {
  const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body || {}) });
  if (!res.ok) throw new Error((await res.json()).error);
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "", done = null;
  for (;;) {
    const { value, done: end } = await reader.read();
    if (end) break;
    buf += decoder.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const frame = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const event = /^event: (.*)$/m.exec(frame)?.[1];
      const data = JSON.parse(/^data: (.*)$/m.exec(frame)?.[1] || "null");
      if (event === "line") onLine(data.text);
      if (event === "done") done = data;
    }
  }
  return done;
}

function diffHtml(patch) {
  return `<pre class="diff">${patch.split("\n").map((l) => {
    const cls = l.startsWith("+") && !l.startsWith("+++") ? "add" : l.startsWith("-") && !l.startsWith("---") ? "del" : l.startsWith("@@") ? "hunk" : "";
    return `<span class="${cls}">${esc(l)}</span>`;
  }).join("\n")}</pre>`;
}

function filesHtml(files) {
  if (!files.length) return `<p class="muted">No changes.</p>`;
  return files.map((f) => f.generated
    ? `<details><summary class="muted">generated: ${esc(f.path)}</summary>${diffHtml(f.patch)}</details>`
    : `<h4>${esc(f.path)}</h4>${diffHtml(f.patch)}`).join("");
}

const STATUS_LABEL = { green: "done", open: "open", locked: "locked", skipped: "skipped", building: "being written" };
const lastCourse = () => { try { return localStorage.getItem("byox.last"); } catch { return null; } };
const rememberCourse = (slug) => { try { localStorage.setItem("byox.last", slug); } catch { /* private window */ } };

function ticks(done, total) {
  if (!total) return "";
  if (total > 60) return `<div class="ticks" aria-hidden="true"><i class="done" style="width:${Math.round((100 * done) / total)}%;height:9px;border-radius:2px"></i></div>`;
  return `<div class="ticks" aria-hidden="true">${Array.from({ length: total }, (_, i) => `<i class="${i < done ? "done" : ""}"></i>`).join("")}</div>`;
}

async function home() {
  crumbs.textContent = "";
  const { courses } = await api("/api/courses");
  const active = courses.filter((c) => c.current);
  const pick = active.find((c) => c.slug === lastCourse()) || active[0];
  const hero = pick
    ? `<section class="continue"><span class="node" aria-hidden="true"></span>
        <div><p class="eyebrow">Continue</p><h2>${esc(pick.current.title)}</h2><p class="muted">${esc(pick.title)} · ${pick.progress.done} of ${pick.progress.total} steps</p></div>
        <a href="#/c/${enc(pick.slug)}/${enc(pick.current.id)}"><button class="primary">Continue lesson</button></a></section>`
    : "";
  const cards = courses.map((c) => {
    const next = c.current ? `<a href="#/c/${enc(c.slug)}/${enc(c.current.id)}">Next: ${esc(c.current.title)}</a>` : `<span class="muted">Every lesson is done.</span>`;
    return `<article class="course-card"><h3><a href="#/c/${enc(c.slug)}">${esc(c.title)}</a></h3>
      ${ticks(c.progress.done, c.progress.total)}<p class="muted">${c.progress.done} of ${c.progress.total} steps</p><p class="where">${next}</p></article>`;
  }).join("");
  const add = `<article class="add-card"><h3>Add a course</h3>
      <p class="muted">Give Claude Code a source and say what you want to build it in.</p>
      <code>/byox-mode this transcript ~/Downloads/course.txt, Rails 8</code>
      <div class="row"><button data-copy="/byox-mode this transcript ~/Downloads/course.txt, Rails 8">Copy command</button></div></article>`;
  app.innerHTML = `<h1>Your workbench</h1><p class="muted">Each course is a list of lessons. Each lesson is steps you build and verify.</p>${hero}<div class="shelf">${cards}${add}</div>`;
  app.onclick = (ev) => {
    const b = ev.target.closest("[data-copy]");
    if (!b) return;
    navigator.clipboard?.writeText(b.dataset.copy);
    b.textContent = "Copied";
  };
}

async function courseMap(slug) {
  const c = await api(`/api/courses/${enc(slug)}`);
  rememberCourse(slug);
  crumbs.textContent = c.title;
  const lessons = c.lessons.map((l) => {
    const title = l.status === "locked" || l.status === "building" ? esc(l.title) : `<a href="#/c/${enc(slug)}/${enc(l.id)}">${esc(l.title)}</a>`;
    const node = l.status === "green" ? "&#10003;" : "";
    const steps = l.steps.map((s) => `<li class="${s.status}"><span class="dot"></span><code>${esc(s.id)}</code><span>${esc(s.title)}</span></li>`).join("");
    return `<article class="lesson ${l.status}"><span class="node" aria-hidden="true">${node}</span>
      <h3>${title} <span class="badge ${l.status}">${STATUS_LABEL[l.status] || l.status}</span>${l.track === "ops" ? ` <span class="badge">ops</span>` : ""}</h3>
      <ol class="steps">${steps}</ol></article>`;
  }).join("");
  app.innerHTML = `<p class="eyebrow">Course</p><h1>${esc(c.title)}</h1>
    <p class="muted">${c.progress.done} of ${c.progress.total} steps. Every step is a commit in the mentor's solution.</p>
    <div class="map">${lessons}</div>
    <section class="add-lessons"><h3>Add lessons</h3>
      <p class="muted">Ask the agent for more: the next chapters of your source, a new source, or a feature. It writes each lesson, reviews it, and releases it in order. This course stays usable while it works.</p>
      <textarea id="add-request" rows="3" placeholder="Add the next five lectures of ~/Downloads/part-2.txt"></textarea>
      <div class="row"><button class="primary" id="add-go">Ask the agent</button></div>
      <pre class="output" id="add-out" hidden></pre></section>`;
  document.getElementById("add-go").onclick = async (ev) => {
    const box = document.getElementById("add-request");
    const out = document.getElementById("add-out");
    if (!box.value.trim()) return box.focus();
    ev.target.disabled = true;
    out.hidden = false;
    out.textContent = "Working. This can take a few minutes per lesson.\n";
    try {
      const res = await stream(`/api/courses/${enc(slug)}/add-lessons`, { request: box.value }, (t) => { out.textContent += t; out.scrollTop = out.scrollHeight; });
      out.textContent += res?.exit === 0 ? "\nDone. Reload the map to see the new lessons.\n" : "\nThe agent stopped. Read the output above.\n";
    } catch (e) {
      out.textContent += `\n${e.message}\n`;
    } finally {
      ev.target.disabled = false;
    }
  };
}

function unclearButton(section) {
  return `<button class="link" data-unclear="${esc(section)}" title="This section is unclear">Unclear?</button>`;
}

function designHtml(s) {
  if (!s.design && !s.design_phone && !s.diff && !s.design_source && !s.design_url) return "";
  const fig = (url, cap, cls = "") => (url ? `<figure class="${cls}"><img src="${esc(url)}?t=${s.attempts}" alt="${esc(cap)}" loading="lazy"><figcaption>${esc(cap)}</figcaption></figure>` : "");
  const penpot = s.design_url ? `<p><a href="${esc(s.design_url)}" target="_blank" rel="noopener"><button>Open the design in Penpot</button></a></p>` : "";
  const source = s.design_source ? `<p class="muted">Open <code>${esc(s.design_source)}</code> in your browser and use Inspect, like a design file.</p>` : "";
  const diff = s.diff && s.status !== "green" ? fig(s.diff, "Where your page differs, in red", "differs") : "";
  return `<div class="design">${fig(s.design, "Design, desktop 1280x800")}${fig(s.design_phone, "Design, phone 390x844")}${diff}</div>${penpot}${source}`;
}

function stepHtml(s) {
  if (s.status === "locked") return `<div class="step locked" id="step-${esc(s.id)}"><h3><code>${esc(s.id)}</code> ${esc(s.title)}</h3><p>Locked. Finish the step before it.</p></div>`;
  const hints = s.hints.map((h, i) => `<div class="hint"><strong>Hint ${i + 1}.</strong> ${md(h)}</div>`).join("");
  const more = s.hints.length < s.hints_total ? `<button data-hint="${esc(s.id)}" data-n="${s.hints.length + 1}">Hint ${s.hints.length + 1} of ${s.hints_total}</button>` : "";
  const gens = s.generators.length ? `<p><strong>Run these generators.</strong> Their output is not code you type.</p><pre>${esc(s.generators.join("\n"))}</pre>` : "";
  const explain = s.last_exit && s.status !== "green" ? `<button data-explain="${esc(s.id)}">Explain failure</button>` : "";
  return `<div class="step ${s.status}" id="step-${esc(s.id)}">
    <div class="row"><h3>${s.status === "green" ? `<span class="check">&#10003;</span>` : ""}<code>${esc(s.id)}</code> ${esc(s.title)}</h3><span class="spacer"></span>${unclearButton(`step ${s.id}`)}</div>
    <p class="muted"><code>${esc(s.verify)}</code></p>
    ${md(s.instructions)}${gens}${designHtml(s)}
    ${s.gotchas ? `<p><strong>Gotchas.</strong></p>${md(s.gotchas)}` : ""}
    ${hints}
    <div class="row"><button class="primary" data-verify="${esc(s.id)}">Verify</button>${more}${explain}</div>
    <pre class="output" id="out-${esc(s.id)}" hidden></pre>
  </div>`;
}

async function lesson(slug, id) {
  let l;
  try {
    l = await api(`/api/courses/${enc(slug)}/lessons/${enc(id)}`);
  } catch (e) {
    app.innerHTML = `<h1>Locked</h1><p>${esc(e.message)}. <a href="#/c/${enc(slug)}">Back to the course map</a>.</p>`;
    return;
  }
  crumbs.innerHTML = `<a href="#/c/${enc(slug)}">${esc(slug)}</a> / ${esc(l.title)}`;
  const base = `/api/courses/${enc(slug)}`;
  const tests = l.steps.flatMap((s) => s.tests).map((t) => `<details><summary><code>${esc(t.path)}</code></summary><pre>${esc(t.code)}</pre></details>`).join("");
  const r = l.resource;
  const backup = l.resources.find((x) => !x.blocked && x !== r && x.url !== r?.url);
  const resource = r
    ? `<p><a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.url)}</a><br><strong>Read:</strong> ${esc(r.section)}<br><span class="muted">${esc(r.why)}</span></p>
       <button data-bad="${esc(r.url)}">Bad resource</button>${backup ? ` <span class="muted">Backup: <a href="${esc(backup.url)}" target="_blank" rel="noopener">${esc(backup.section)}</a></span>` : ""}`
    : `<p class="muted">Every resource for this lesson is on your blocklist. Press This lesson is broken to get a new one.</p>`;
  const concepts = l.concepts.map((c) => c.exists ? `<li><a href="#/concept/${enc(c.slug)}">${esc(c.slug)}</a></li>` : `<li class="muted">${esc(c.slug)} (missing)</li>`).join("");
  rememberCourse(slug);
  const rail = l.steps.map((s) => `<li class="${s.status}"><button data-jump="${esc(s.id)}"><code>${esc(s.id)}</code>${esc(s.title)}</button></li>`).join("");
  app.innerHTML = `<div class="lesson-page"><aside class="steprail" aria-label="Steps in this lesson"><p class="eyebrow">Steps</p><ol>${rail}</ol></aside><div class="content">
    <div class="row"><span class="badge ${l.status}">${esc(STATUS_LABEL[l.status] || l.status)}</span>${l.track === "ops" ? `<span class="badge">ops</span>` : ""}</div>
    <h1>${esc(l.title)}</h1>
    <h2>Goal</h2><div class="goal">${md(l.goal)}</div>
    <h2>Short read ${unclearButton("short_read")}</h2>${md(l.sections.short_read)}
    <h2>Task ${unclearButton("task")}</h2>${md(l.sections.task)}
    <h2>Tests in plain English ${unclearButton("tests")}</h2>${md(l.sections.tests)}
    <details><summary>Test code</summary>${tests}</details>
    <h2>Steps</h2>${l.steps.map(stepHtml).join("")}
    <h2>Resource</h2>${resource}
    <h2>Go deep</h2><ul>${concepts || `<li class="muted">No concept pages.</li>`}</ul>
    <h2>Mentor's solution</h2>
    <div id="solution">${l.solution_unlocked
      ? `<div class="row"><button data-solution>Show solution</button><button data-compare>Compare with my code</button></div>`
      : `<p class="muted">Locked until this lesson is green or skipped.</p>`}</div>
    <div class="panel row">
      ${l.status !== "green" && l.status !== "skipped" ? `<button data-skip>Skip lesson</button>` : ""}
      <button data-broken>This lesson is broken</button>
      ${l.next_lesson && (l.status === "green" || l.status === "skipped") ? `<a href="#/c/${enc(slug)}/${enc(l.next_lesson)}"><button class="primary">Next lesson</button></a>` : ""}
    </div>
    <pre class="output" id="job" hidden></pre></div></div>`;

  const job = document.getElementById("job");
  const runJob = async (path, body) => {
    job.hidden = false;
    job.textContent = "Working...\n";
    try {
      const res = await stream(path, body, (t) => { job.textContent += t; });
      job.textContent += `\n[exit ${res?.exit}]${res?.restored ? " The rewrite failed lint and was rolled back." : ""}\n`;
      return res;
    } catch (e) {
      job.textContent += `\n${e.message}\n`;
    }
  };

  app.onclick = async (ev) => {
    const b = ev.target.closest("button");
    if (!b) return;
    const d = b.dataset;
    if (d.jump) {
      document.getElementById(`step-${d.jump}`)?.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });
    } else if (d.verify) {
      const out = document.getElementById(`out-${d.verify}`);
      out.hidden = false;
      out.className = "output";
      out.textContent = "";
      b.disabled = true;
      try {
        const res = await stream(`${base}/steps/${enc(d.verify)}/verify`, {}, (t) => { out.textContent += t; out.scrollTop = out.scrollHeight; });
        out.classList.add(res.ok ? "pass" : "fail");
        if (res.lesson_green) return celebrate(slug, l);
        if (res.ok) return lesson(slug, id);
        const card = document.getElementById(`step-${d.verify}`);
        if (!card.querySelector("[data-explain]")) card.querySelector(".row:last-of-type").insertAdjacentHTML("beforeend", `<button data-explain="${esc(d.verify)}">Explain failure</button>`);
      } catch (e) {
        out.textContent += e.message;
      } finally {
        b.disabled = false;
      }
    } else if (d.hint) {
      await post(`${base}/steps/${enc(d.hint)}/hints/${d.n}`);
      lesson(slug, id);
    } else if (d.explain) {
      runJob(`${base}/steps/${enc(d.explain)}/explain`);
    } else if (d.unclear) {
      const note = prompt(`What is unclear in ${d.unclear}?`);
      if (note && (await runJob(`${base}/lessons/${enc(id)}/unclear`, { section: d.unclear, note }))) lesson(slug, id);
    } else if (d.bad) {
      if (confirm("Add this link to your blocklist and show the backup?")) { await post(`${base}/lessons/${enc(id)}/bad-resource`, { url: d.bad }); lesson(slug, id); }
    } else if (d.broken) {
      const note = prompt("What is broken? Say what you expected and what happened.");
      const failing = l.steps.find((s) => s.last_exit && s.status !== "green");
      if (note) runJob(`${base}/lessons/${enc(id)}/broken`, { note, step: failing?.id });
    } else if (d.skip !== undefined) {
      if (confirm("Skip this lesson? It unlocks the next one and the solution, and goes in your weakness log.")) { await post(`${base}/lessons/${enc(id)}/skip`); lesson(slug, id); }
    } else if (d.solution !== undefined) {
      const sol = await api(`${base}/lessons/${enc(id)}/solution`);
      document.getElementById("solution").innerHTML = sol.steps.map((s) =>
        `<h3>${esc(s.id)} ${esc(s.title)}</h3>${filesHtml(s.files)}${s.original ? `<details><summary>Original diff, before the port</summary>${diffHtml(s.original)}</details>` : ""}`).join("")
        + `<div class="row"><button data-compare>Compare with my code</button></div>`;
    } else if (d.compare !== undefined) {
      const cmp = await api(`${base}/lessons/${enc(id)}/compare`);
      document.getElementById("solution").insertAdjacentHTML("beforeend", `<h3>Your code against the solution</h3>${filesHtml(cmp.files)}`);
    }
  };
}

function celebrate(slug, l) {
  const el = document.getElementById("celebrate");
  el.innerHTML = `<h1>&#10003; ${esc(l.title)} is green</h1><p>Every step passes. The mentor's solution is unlocked.</p>
    <div class="row">${l.next_lesson ? `<button data-next>Next lesson</button>` : ""}<button data-stay>Stay here</button></div>`;
  el.hidden = false;
  el.onclick = (ev) => {
    const b = ev.target.closest("button");
    if (!b) return;
    el.hidden = true;
    if (b.dataset.next !== undefined) location.hash = `#/c/${enc(slug)}/${enc(l.next_lesson)}`;
    else lesson(slug, l.id);
  };
}

function isDark() {
  const t = document.documentElement.dataset.theme;
  return t ? t === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
}

let mermaidLoad;
function renderMermaid(root) {
  const blocks = root.querySelectorAll("code.language-mermaid");
  if (!blocks.length) return;
  blocks.forEach((code) => {
    const pre = document.createElement("pre");
    pre.className = "mermaid";
    pre.textContent = code.textContent;
    code.parentElement.replaceWith(pre);
  });
  mermaidLoad ||= new Promise((ok, fail) => {
    const s = document.createElement("script");
    s.src = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";
    s.onload = ok;
    s.onerror = fail;
    document.head.appendChild(s);
  });
  mermaidLoad.then(() => {
    mermaid.initialize({ startOnLoad: false, theme: isDark() ? "dark" : "default" });
    mermaid.run({ nodes: root.querySelectorAll("pre.mermaid") });
  }).catch(() => {});
}

async function concept(slug) {
  const c = await api(`/api/concepts/${enc(slug)}`);
  crumbs.textContent = `Concept / ${c.title}`;
  const where = c.where.map((w) => `<li><a href="#/c/${enc(w.course)}/${enc(w.lesson)}">${esc(w.course)}: ${esc(w.title)}</a></li>`).join("");
  app.innerHTML = `<h1>${esc(c.title)}</h1>${md(c.body)}<h2>Where it shows up</h2><ul>${where || `<li class="muted">No lesson uses it yet.</li>`}</ul>
    <pre class="output" id="job" hidden></pre>`;
  [...app.querySelectorAll("h2")].slice(0, -1).forEach((h) => h.insertAdjacentHTML("beforeend", unclearButton(h.textContent)));
  renderMermaid(app);
  app.onclick = async (ev) => {
    const section = ev.target.closest("button")?.dataset.unclear;
    const note = section && prompt(`What is unclear in ${section}?`);
    if (!note) return;
    const job = document.getElementById("job");
    job.hidden = false;
    job.textContent = "Working...\n";
    try {
      const res = await stream(`/api/concepts/${enc(slug)}/unclear`, { section, note }, (t) => { job.textContent += t; });
      if (!res.restored) return concept(slug);
      job.textContent += "\nThe rewrite broke the page, so it was rolled back.\n";
    } catch (e) {
      job.textContent += `\n${e.message}\n`;
    }
  };
}

async function route() {
  const [, kind, a, b] = location.hash.split("/").map(decodeURIComponent);
  document.getElementById("celebrate").hidden = true;
  app.onclick = null;
  try {
    if (kind === "c" && b) await lesson(a, b);
    else if (kind === "c") await courseMap(a);
    else if (kind === "concept") await concept(a);
    else await home();
  } catch (e) {
    app.innerHTML = `<h1>Something went wrong</h1><pre>${esc(e.message)}</pre>`;
  }
  window.scrollTo(0, 0);
}

addEventListener("hashchange", route);
route();

const fb = document.getElementById("fb");
async function fbRefresh() {
  const { items, changes } = await api("/api/feedback");
  const box = fb.querySelector(".fb-changes");
  box.hidden = changes === null || changes === undefined;
  box.querySelector("p").textContent = changes ? `${changes} changed file${changes === 1 ? "" : "s"} in your byox checkout, not uploaded yet.` : "Your byox checkout has no changes.";
  box.querySelector("[data-upload]").disabled = !changes;
  const open = items.filter((i) => i.status === "open");
  const shipped = items.filter((i) => i.status !== "open");
  fb.querySelector(".fb-list").innerHTML = open.map((i) => `<li>${esc(i.text)} <span class="muted">${esc(i.page)}</span></li>`).join("")
    + shipped.slice(-3).map((i) => `<li class="muted">${esc(i.text)} <a href="${esc(i.pr)}" target="_blank" rel="noopener">pull request</a></li>`).join("");
  const ship = fb.querySelector("[data-ship]");
  ship.disabled = open.length === 0;
  ship.textContent = open.length ? `Send ${open.length} to a pull request` : "Nothing to send";
}
document.getElementById("fb-open").onclick = async () => { await fbRefresh(); fb.showModal(); fb.querySelector("textarea").focus(); };
fb.onclick = async (ev) => {
  const b = ev.target.closest("button");
  if (!b) return;
  const out = fb.querySelector(".fb-out");
  try {
    if (b.dataset.close !== undefined) return fb.close();
    if (b.dataset.save !== undefined) {
      const box = fb.querySelector("textarea");
      if (!box.value.trim()) return box.focus();
      await post("/api/feedback", { text: box.value, page: location.hash || "#/" });
      box.value = "";
      return fbRefresh();
    }
    if (b.dataset.ship !== undefined || b.dataset.upload !== undefined) {
      const upload = b.dataset.upload !== undefined;
      const ask = upload
        ? "The feedback agent will commit your changes on a new branch, take before and after screenshots, write how to test each one, and open one pull request. Go?"
        : "The feedback agent will change byox, take before and after screenshots, and open one pull request for review. Go?";
      if (!confirm(ask)) return;
      b.disabled = true;
      out.hidden = false;
      out.textContent = "Working...\n";
      const done = await stream(upload ? "/api/feedback/upload" : "/api/feedback/ship", {}, (line) => { out.textContent += line; out.scrollTop = out.scrollHeight; });
      out.textContent += done && done.exit === 0 ? "\nDone.\n" : "\nThe agent stopped. Read the output above.\n";
      return fbRefresh();
    }
  } catch (e) {
    out.hidden = false;
    out.textContent += `${e.message}\n`;
  }
};

const themeBtn = document.getElementById("theme");
const showTheme = () => { themeBtn.textContent = `Theme: ${document.documentElement.dataset.theme || "auto"}`; };
themeBtn.onclick = () => {
  const order = ["auto", "light", "dark"];
  const next = order[(order.indexOf(document.documentElement.dataset.theme || "auto") + 1) % order.length];
  if (next === "auto") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = next;
  try { next === "auto" ? localStorage.removeItem("byox.theme") : localStorage.setItem("byox.theme", next); } catch { /* private window */ }
  showTheme();
  route();
};
showTheme();
