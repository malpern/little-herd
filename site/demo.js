/* A working miniature of the Little Herd window.
 *
 * This is a recreation, not a screenshot, and it is labelled as one on the
 * page. Everything it does is something the real app does: the same four
 * metrics, the same segmented bars, the same green-yellow-orange-red ramp, the
 * same green dot for live and red for unreachable, and above all the same
 * hover behaviour -- putting the machine you are pointing at into the header,
 * which is the app's central idea and impossible to convey in a still.
 *
 * Numbers are invented and move on a random walk. Nothing here reports a real
 * machine, and no claim is made that it does.
 */
(() => {
  const SEGMENTS = 10;
  const TICK_MS = 1800;

  const MACHINES = [
    { id: "air", name: "Air", avatar: "chick-laptop",
      cpu: 51, mem: 62, disk: 74, free: "121 GB free",
      procs: { cpu: [["Xcode", "3.2 cores"], ["Claude Code", "0.9 cores"], ["Chrome", "0.4 cores"]],
               mem: [["Dia", "4.56 GB"], ["Claude Code", "1.43 GB"], ["Xcode", "1.1 GB"]],
               disk: [["Macintosh HD", "121 GB free of 460 GB"]] } },
    { id: "mini", name: "Mini", avatar: "calf-mini",
      cpu: 13, mem: 44, disk: 39, free: "1.2 TB free",
      procs: { cpu: [["codex", "1.4 cores"], ["node", "0.6 cores"]],
               mem: [["codex", "2.10 GB"], ["node", "0.88 GB"]],
               disk: [["Macintosh HD", "1.2 TB free of 2 TB"]] } },
    { id: "linux", name: "Linux", avatar: "ox-gpu",
      cpu: 6, mem: 31, disk: 52, free: "460 GB free",
      procs: { cpu: [["docker", "0.9 cores"], ["restic", "0.3 cores"]],
               mem: [["docker", "1.62 GB"], ["restic", "0.31 GB"]],
               disk: [["nvme0n1p2", "460 GB free of 1 TB"]] } },
    { id: "nas", name: "Synology", avatar: "piglet-nas",
      cpu: 3, mem: 26, disk: 67, free: "2.6 TB free",
      procs: { cpu: [["synoindexd", "0.2 cores"]],
               mem: [["synoindexd", "0.44 GB"]],
               disk: [["Volume 1", "2.6 TB free of 8.1 TB"]] } },
  ];

  // Agents drift between these states the way real sessions do.
  const AGENT_POOL = [
    { agent: "Claude Code", project: "little-herd", machine: "Air", step: "4/6" },
    { agent: "Codex", project: "dotfiles", machine: "Mini", step: "2/3" },
    { agent: "Claude Code", project: "attgw", machine: "Mini", step: "7/7" },
    { agent: "Codex", project: "vm-lab", machine: "Linux", step: "1/4" },
    { agent: "Claude Code", project: "keypath", machine: "Air", step: "3/5" },
  ];
  const STATES = ["running", "waiting", "done"];
  const STATE_LABEL = { running: "running", waiting: "waiting for you", done: "finished" };

  const METRICS = [
    { key: "cpu", label: "CPU" },
    { key: "mem", label: "Memory" },
    { key: "disk", label: "Disk" },
    { key: "ai", label: "AI" },
  ];

  // On the real site an avatar is just a file beside the page. In a
  // single-file Artifact there is no beside, so the preview build injects
  // window.LH_ASSETS with the same images as data URIs.
  const asset = (name) =>
    (window.LH_ASSETS && window.LH_ASSETS[name]) || `images/herdware/${name}.png`;

  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const pick = (a) => a[Math.floor(Math.random() * a.length)];

  // Green up to half, then yellow, orange, red -- the app's own ramp.
  function ramp(pct, i) {
    const filled = Math.round((pct / 100) * SEGMENTS);
    if (SEGMENTS - i > filled) return "off";
    if (pct >= 90) return "red";
    if (pct >= 75) return "orange";
    if (pct >= 55) return "yellow";
    return "green";
  }

  function build(root) {
    const state = {
      view: root.dataset.view === "ai" ? "ai" : "cpu",
      hover: null,
      machines: MACHINES.map((m) => ({ ...m, live: true })),
      agents: AGENT_POOL.slice(0, 3).map((a, i) => ({ ...a, state: STATES[i % 3] })),
    };

    root.innerHTML = `
      <div class="lh-chrome"><i class="r"></i><i class="y"></i><i class="g"></i></div>
      <div class="lh-head"></div>
      <div class="lh-body"></div>
      <div class="lh-tabs" role="tablist"></div>`;

    const head = root.querySelector(".lh-head");
    const body = root.querySelector(".lh-body");
    const tabs = root.querySelector(".lh-tabs");

    METRICS.forEach((m) => {
      const b = document.createElement("button");
      b.type = "button";
      b.role = "tab";
      b.textContent = m.label;
      b.onclick = () => { state.view = m.key; state.hover = null; render(); };
      b.dataset.key = m.key;
      tabs.appendChild(b);
    });

    function renderHead() {
      const live = state.machines.filter((m) => m.live).length;
      const metric = METRICS.find((m) => m.key === state.view);

      if (state.hover && state.hover.kind === "machine") {
        const m = state.hover.data;
        const rows = state.view === "ai" ? [] : m.procs[state.view] || [];
        head.innerHTML = `
          <div class="lh-hover">
            <div class="lh-hover-top">
              <span class="lh-dot ${m.live ? "live" : "down"}"></span>
              <img src="${asset(m.avatar)}" alt="">
              <b>${m.name}</b>
              ${state.view === "mem" ? '<span class="lh-tag">Memory pressure <em>Normal</em></span>' : ""}
            </div>
            <div class="lh-hover-rows">
              ${rows.map(([n, v]) => `<span><b>${n}</b><i>${v}</i></span>`).join("")}
            </div>
          </div>`;
        return;
      }
      if (state.hover && state.hover.kind === "agent") {
        const a = state.hover.data;
        head.innerHTML = `
          <div class="lh-hover">
            <div class="lh-hover-top">
              <span class="lh-dot ${a.state}"></span><b>${a.agent}</b>
              <span class="lh-tag">${a.project} on ${a.machine}</span>
            </div>
            <div class="lh-hover-rows"><span><b>${STATE_LABEL[a.state]}</b><i>step ${a.step}</i></span></div>
          </div>`;
        return;
      }
      head.innerHTML = `
        <div class="lh-title">
          <span class="lh-metric">${metric.label}</span>
          <span class="lh-sub"><span class="lh-dot ${live === state.machines.length ? "live" : "down"}"></span>
            ${state.view === "ai" ? `${state.agents.length} agents` : `${live} of ${state.machines.length} live`}</span>
        </div>`;
    }

    function renderBody() {
      if (state.view === "ai") {
        body.className = "lh-body lh-rows";
        body.innerHTML = state.agents.map((a, i) => `
          <div class="lh-agent" tabindex="0" data-agent="${i}">
            <span class="lh-dot ${a.state}"></span>
            <span class="lh-agent-name"><b>${a.agent}</b><i>${a.project} &middot; ${a.machine}</i></span>
            <span class="lh-step">${a.state === "done" ? "&#10003;" : a.step}</span>
          </div>`).join("");
        return;
      }
      body.className = "lh-body lh-cols";
      body.innerHTML = state.machines.map((m, i) => {
        const pct = m.live ? m[state.view] : m[state.view];
        const segs = Array.from({ length: SEGMENTS }, (_, s) =>
          `<i class="${m.live ? ramp(pct, s) : "off"}"></i>`).join("");
        return `
          <div class="lh-col" tabindex="0" data-machine="${i}">
            <span class="lh-pct ${pct >= 90 ? "hot" : ""}">${m.live ? pct + "%" : "&ndash;"}</span>
            <span class="lh-bar">${segs}</span>
            <img src="${asset(m.avatar)}" alt="">
            <span class="lh-name"><span class="lh-dot ${m.live ? "live" : "down"}"></span>${m.name}</span>
            ${state.view === "disk" && m.live ? `<span class="lh-free">${m.free}</span>` : ""}
          </div>`;
      }).join("");
    }

    function render() {
      tabs.querySelectorAll("button").forEach((b) =>
        b.setAttribute("aria-selected", String(b.dataset.key === state.view)));
      renderHead();
      renderBody();
      wire();
    }

    function wire() {
      body.querySelectorAll("[data-machine]").forEach((el) => {
        const m = state.machines[+el.dataset.machine];
        const on = () => { state.hover = { kind: "machine", data: m }; renderHead(); };
        const off = () => { state.hover = null; renderHead(); };
        el.onmouseenter = on; el.onfocus = on;
        el.onmouseleave = off; el.onblur = off;
      });
      body.querySelectorAll("[data-agent]").forEach((el) => {
        const a = state.agents[+el.dataset.agent];
        const on = () => { state.hover = { kind: "agent", data: a }; renderHead(); };
        const off = () => { state.hover = null; renderHead(); };
        el.onmouseenter = on; el.onfocus = on;
        el.onmouseleave = off; el.onblur = off;
      });
    }

    function tick() {
      // random-walk the metrics, with the odd machine dropping off and coming back
      state.machines.forEach((m) => {
        m.cpu = clamp(Math.round(m.cpu + (Math.random() - 0.45) * 22), 1, 99);
        m.mem = clamp(Math.round(m.mem + (Math.random() - 0.5) * 6), 12, 92);
        m.disk = clamp(Math.round(m.disk + (Math.random() - 0.5) * 1.2), 20, 95);
        if (Math.random() < 0.02) m.live = false;
        else if (!m.live && Math.random() < 0.4) m.live = true;
      });
      // agents arrive, progress, and leave
      state.agents.forEach((a) => {
        if (Math.random() < 0.25) a.state = pick(STATES);
      });
      if (state.agents.length > 2 && Math.random() < 0.2) {
        const i = state.agents.findIndex((a) => a.state === "done");
        if (i > -1) state.agents.splice(i, 1);
      } else if (state.agents.length < 4 && Math.random() < 0.25) {
        const missing = AGENT_POOL.filter((p) =>
          !state.agents.some((a) => a.project === p.project));
        if (missing.length) state.agents.push({ ...pick(missing), state: "running" });
      }
      // a hovered header must not be yanked out from under the pointer
      render();
    }

    render();
    const still = window.matchMedia("(prefers-reduced-motion: reduce)");
    let timer = null;
    const start = () => { if (!timer && !still.matches) timer = setInterval(tick, TICK_MS); };
    const stop = () => { clearInterval(timer); timer = null; };
    still.addEventListener?.("change", () => (still.matches ? stop() : start()));

    // Only run while it is on screen -- a menu-bar app's own point is that it
    // costs nothing when you are not looking at it. But START FIRST and let the
    // observer stop it, rather than waiting to be told it is visible: in a
    // context that reports a zero-height viewport the observer never fires at
    // all, and gating on it left the demo frozen with no error to explain why.
    start();
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? start() : stop())),
        { threshold: 0.15 }).observe(root);
    }
  }

  document.querySelectorAll("[data-lh-demo]").forEach(build);
})();
