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

async function home() {
  crumbs.textContent = "";
  const { courses } = await api("/api/courses");
  app.innerHTML = `<h1>Your courses</h1>` + (courses.length ? courses.map((c) => {
    const pct = c.progress.total ? Math.round((100 * c.progress.done) / c.progress.total) : 0;
    const next = c.current ? `<a href="#/c/${enc(c.slug)}/${enc(c.current.id)}">Continue: ${esc(c.current.title)}</a>` : `<span class="muted">Finished</span>`;
    return `<div class="card"><h3><a href="#/c/${enc(c.slug)}">${esc(c.title)}</a></h3>
      <p class="muted">${c.progress.done} of ${c.progress.total} steps</p><div class="bar"><i style="width:${pct}%"></i></div><p>${next}</p></div>`;
  }).join("") : `<p class="muted">No compiled courses under this root yet. Run /byox-mode with a source.</p>`);
}

async function courseMap(slug) {
  const c = await api(`/api/courses/${enc(slug)}`);
  crumbs.textContent = c.title;
  app.innerHTML = `<h1>${esc(c.title)}</h1><p class="muted">${c.progress.done} of ${c.progress.total} steps</p>
    <ol class="map">${c.lessons.map((l) => {
      const dots = `<span class="dots">${l.steps.map((s) => `<i class="${s.status}" title="${esc(s.id)} ${esc(s.title)}"></i>`).join("")}</span>`;
      const title = l.status === "locked" ? `<span class="muted">${esc(l.title)}</span>` : `<a href="#/c/${enc(slug)}/${enc(l.id)}">${esc(l.title)}</a>`;
      return `<li>${title} <span class="badge ${l.status}">${l.status}</span>${l.track === "ops" ? ` <span class="badge">ops</span>` : ""}${dots}</li>`;
    }).join("")}</ol>`;
}

function unclearButton(section) {
  return `<button class="link" data-unclear="${esc(section)}" title="This section is unclear">Unclear?</button>`;
}

function stepHtml(s) {
  if (s.status === "locked") return `<div class="card step locked"><h3>${esc(s.id)} ${esc(s.title)}</h3><p>Locked. Finish the step before it.</p></div>`;
  const hints = s.hints.map((h, i) => `<div class="hint"><strong>Hint ${i + 1}.</strong> ${md(h)}</div>`).join("");
  const more = s.hints.length < s.hints_total ? `<button data-hint="${esc(s.id)}" data-n="${s.hints.length + 1}">Hint ${s.hints.length + 1} of ${s.hints_total}</button>` : "";
  const gens = s.generators.length ? `<p><strong>Run these generators.</strong> Their output is not code you type.</p><pre>${esc(s.generators.join("\n"))}</pre>` : "";
  const explain = s.last_exit && s.status !== "green" ? `<button data-explain="${esc(s.id)}">Explain failure</button>` : "";
  return `<div class="card step ${s.status}" id="step-${esc(s.id)}">
    <div class="row"><h3>${s.status === "green" ? `<span class="check">&#10003;</span> ` : ""}${esc(s.id)} ${esc(s.title)}</h3>${unclearButton(`step ${s.id}`)}</div>
    <p class="muted"><code>${esc(s.verify)}</code></p>
    ${md(s.instructions)}${gens}
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
  app.innerHTML = `
    <div class="row"><span class="badge ${l.status}">${esc(l.status)}</span>${l.track === "ops" ? `<span class="badge">ops</span>` : ""}</div>
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
    <pre class="output" id="job" hidden></pre>`;

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
    if (d.verify) {
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
    mermaid.initialize({ startOnLoad: false, theme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default" });
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
  const { items } = await api("/api/feedback");
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
    if (b.dataset.ship !== undefined) {
      if (!confirm("The feedback agent will change byox, take before and after screenshots, and open one pull request for review. Go?")) return;
      b.disabled = true;
      out.hidden = false;
      out.textContent = "Working...\n";
      const done = await stream("/api/feedback/ship", {}, (line) => { out.textContent += line; out.scrollTop = out.scrollHeight; });
      out.textContent += done && done.exit === 0 ? "\nDone.\n" : "\nThe agent stopped. Read the output above.\n";
      return fbRefresh();
    }
  } catch (e) {
    out.hidden = false;
    out.textContent += `${e.message}\n`;
  }
};
