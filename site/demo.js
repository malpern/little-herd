/* A working miniature of the Little Herd window.
 *
 * This is a recreation, not a screenshot, and it is labelled as one on the
 * page. Everything it does is something the real app does: the same four
 * metrics, the same segmented bars, the same green-yellow-orange-red ramp, the
 * same green dot for live and red for unreachable, and above all the same
 * hover behaviour -- putting the machine you are pointing at into the header,
 * which is the app's central idea and impossible to convey in a still.
 *
 * Numbers are invented and drift on a random walk. Nothing here reports a real
 * machine, and no claim is made that it does.
 *
 * THE STRUCTURAL RULE: the DOM is built once and afterwards only mutated.
 * The first version rebuilt innerHTML on every tick, which broke three things
 * at once and each looked like a separate bug -- the element under the pointer
 * was destroyed mid-hover so the header snapped back to idle, every CSS
 * transition was thrown away so values stepped instead of easing, and a
 * changing number of rows resized the window and shoved the page around under
 * the reader. Never rebuild. Update in place, and keep every box a fixed size.
 */
(() => {
  const SEGMENTS = 10;
  const TICK_MS = 2600;   // how often a new target is chosen
  const EASE = 0.075;     // how fast the displayed value chases that target
  const SLOTS = 4;        // fixed row count, so a session leaving cannot resize

  const MACHINES = [
    { name: "Air", avatar: "chick-laptop",
      cpu: 51, mem: 62, disk: 74, free: "121 GB free",
      procs: { cpu: [["Xcode", "3.2 cores"], ["Claude Code", "0.9 cores"], ["Chrome", "0.4 cores"]],
               mem: [["Dia", "4.56 GB"], ["Claude Code", "1.43 GB"], ["Xcode", "1.1 GB"]],
               disk: [["Macintosh HD", "121 GB free of 460 GB"]] } },
    { name: "Mini", avatar: "calf-mini",
      cpu: 13, mem: 44, disk: 39, free: "1.2 TB free",
      procs: { cpu: [["codex", "1.4 cores"], ["node", "0.6 cores"]],
               mem: [["codex", "2.10 GB"], ["node", "0.88 GB"]],
               disk: [["Macintosh HD", "1.2 TB free of 2 TB"]] } },
    { name: "Linux", avatar: "ox-gpu",
      cpu: 6, mem: 31, disk: 52, free: "460 GB free",
      procs: { cpu: [["docker", "0.9 cores"], ["restic", "0.3 cores"]],
               mem: [["docker", "1.62 GB"], ["restic", "0.31 GB"]],
               disk: [["nvme0n1p2", "460 GB free of 1 TB"]] } },
    { name: "Synology", avatar: "piglet-nas",
      cpu: 3, mem: 26, disk: 67, free: "2.6 TB free",
      procs: { cpu: [["synoindexd", "0.2 cores"]],
               mem: [["synoindexd", "0.44 GB"]],
               disk: [["Volume 1", "2.6 TB free of 8.1 TB"]] } },
  ];

  const AGENT_POOL = [
    { agent: "Claude Code", project: "little-herd", machine: "Air", step: "4/6" },
    { agent: "Codex", project: "dotfiles", machine: "Mini", step: "2/3" },
    { agent: "Claude Code", project: "attgw", machine: "Mini", step: "7/7" },
    { agent: "Codex", project: "vm-lab", machine: "Linux", step: "1/4" },
    { agent: "Claude Code", project: "keypath", machine: "Air", step: "3/5" },
    { agent: "Codex", project: "add-secret", machine: "Mini", step: "2/5" },
  ];
  const STATE_LABEL = { running: "running", waiting: "waiting for you", done: "finished" };

  const METRICS = [
    { key: "cpu", label: "CPU" }, { key: "mem", label: "Memory" },
    { key: "disk", label: "Disk" }, { key: "ai", label: "AI" },
  ];

  const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const pick = (a) => a[Math.floor(Math.random() * a.length)];

  // On the real site an avatar is a file beside the page. In a single-file
  // Artifact there is no beside, so the preview build injects window.LH_ASSETS
  // with the same images as data URIs.
  const asset = (n) => (window.LH_ASSETS && window.LH_ASSETS[n]) || `images/herdware/${n}.png`;

  const tone = (p) => (p >= 90 ? "red" : p >= 75 ? "orange" : p >= 55 ? "yellow" : "green");

  function build(root) {
    let view = root.dataset.view === "ai" ? "ai" : "cpu";
    let hover = null;

    const machines = MACHINES.map((m) => ({
      ...m, live: true,
      shown: { cpu: m.cpu, mem: m.mem, disk: m.disk },   // what is on screen
      target: { cpu: m.cpu, mem: m.mem, disk: m.disk },  // what it is heading for
    }));
    const slots = Array.from({ length: SLOTS }, (_, i) => ({
      ...AGENT_POOL[i], state: ["running", "waiting", "running", "done"][i],
    }));

    root.innerHTML = `
      <div class="lh-chrome"><i class="r"></i><i class="y"></i><i class="g"></i></div>
      <div class="lh-head">
        <div class="lh-idle">
          <span class="lh-metric"></span>
          <span class="lh-sub"><span class="lh-dot live"></span><span class="lh-sub-text"></span></span>
        </div>
        <div class="lh-hover" hidden>
          <div class="lh-hover-top">
            <span class="lh-dot live"></span><img alt=""><b></b><span class="lh-tag"></span>
          </div>
          <div class="lh-hover-rows"></div>
        </div>
      </div>
      <div class="lh-stage">
        <div class="lh-cols"></div>
        <div class="lh-rows" hidden></div>
      </div>
      <div class="lh-tabs" role="tablist"></div>`;

    const $ = (s) => root.querySelector(s);
    const idle = $(".lh-idle"), hoverBox = $(".lh-hover");
    const metricEl = $(".lh-metric"), subText = $(".lh-sub-text"), subDot = $(".lh-sub .lh-dot");
    const hDot = hoverBox.querySelector(".lh-dot"), hImg = hoverBox.querySelector("img");
    const hName = hoverBox.querySelector("b"), hTag = hoverBox.querySelector(".lh-tag");
    const hRows = hoverBox.querySelector(".lh-hover-rows");
    const cols = $(".lh-cols"), rows = $(".lh-rows"), tabs = $(".lh-tabs");

    function bindHover(el, get) {
      const on = () => { hover = get(); paintHead(); };
      const off = () => { hover = null; paintHead(); };
      el.addEventListener("mouseenter", on);
      el.addEventListener("focus", on);
      el.addEventListener("mouseleave", off);
      el.addEventListener("blur", off);
    }

    const colEls = machines.map((m) => {
      const el = document.createElement("div");
      el.className = "lh-col";
      el.tabIndex = 0;
      el.innerHTML = `
        <span class="lh-pct"></span>
        <span class="lh-bar">${"<i></i>".repeat(SEGMENTS)}</span>
        <img src="${asset(m.avatar)}" alt="">
        <span class="lh-name"><span class="lh-dot live"></span>${m.name}</span>
        <span class="lh-free"></span>`;
      bindHover(el, () => ({ kind: "machine", data: m }));
      cols.appendChild(el);
      return { pct: el.querySelector(".lh-pct"), segs: [...el.querySelectorAll(".lh-bar i")],
               dot: el.querySelector(".lh-name .lh-dot"), free: el.querySelector(".lh-free") };
    });

    const rowEls = slots.map((s) => {
      const el = document.createElement("div");
      el.className = "lh-agent";
      el.tabIndex = 0;
      el.innerHTML = `
        <span class="lh-dot"></span>
        <span class="lh-agent-name"><b></b><i></i></span>
        <span class="lh-step"></span>`;
      bindHover(el, () => ({ kind: "agent", data: s }));
      rows.appendChild(el);
      return { el, dot: el.querySelector(".lh-dot"), name: el.querySelector("b"),
               sub: el.querySelector("i"), step: el.querySelector(".lh-step") };
    });

    METRICS.forEach((m) => {
      const b = document.createElement("button");
      b.type = "button"; b.role = "tab"; b.textContent = m.label; b.dataset.key = m.key;
      b.addEventListener("click", () => { view = m.key; hover = null; switchView(); });
      tabs.appendChild(b);
    });

    function switchView() {
      cols.hidden = view === "ai";
      rows.hidden = view !== "ai";
      tabs.querySelectorAll("button").forEach((x) =>
        x.setAttribute("aria-selected", String(x.dataset.key === view)));
      paintHead(); paintCols(); paintRows();
    }

    function paintHead() {
      const liveCount = machines.filter((m) => m.live).length;
      idle.hidden = !!hover;
      hoverBox.hidden = !hover;
      if (!hover) {
        metricEl.textContent = METRICS.find((m) => m.key === view).label;
        subDot.className = "lh-dot " + (liveCount === machines.length ? "live" : "down");
        subText.textContent = view === "ai"
          ? `${slots.filter((s) => s.state !== "done").length} of ${SLOTS} working`
          : `${liveCount} of ${machines.length} live`;
        return;
      }
      if (hover.kind === "machine") {
        const m = hover.data;
        hDot.className = "lh-dot " + (m.live ? "live" : "down");
        hImg.hidden = false; hImg.src = asset(m.avatar);
        hName.textContent = m.name;
        hTag.innerHTML = view === "mem" ? "Memory pressure <em>Normal</em>" : "";
        hRows.innerHTML = (view === "ai" ? [] : m.procs[view] || [])
          .map(([n, v]) => `<span><b>${n}</b><i>${v}</i></span>`).join("");
      } else {
        const a = hover.data;
        hDot.className = "lh-dot " + a.state;
        hImg.hidden = true;
        hName.textContent = a.agent;
        hTag.textContent = `${a.project} on ${a.machine}`;
        hRows.innerHTML = `<span><b>${STATE_LABEL[a.state]}</b><i>step ${a.step}</i></span>`;
      }
    }

    function paintCols() {
      if (view === "ai") return;
      machines.forEach((m, i) => {
        const c = colEls[i], v = Math.round(m.shown[view]);
        c.pct.textContent = m.live ? v + "%" : "–";
        c.pct.classList.toggle("hot", m.live && v >= 90);
        c.dot.className = "lh-dot " + (m.live ? "live" : "down");
        const filled = m.live ? Math.round((v / 100) * SEGMENTS) : 0;
        const t = tone(v);
        // index 0 is the top of the bar, so it fills from the bottom up
        c.segs.forEach((seg, s) => { seg.className = SEGMENTS - s <= filled ? t : ""; });
        c.free.textContent = view === "disk" && m.live ? m.free : "";
      });
    }

    function paintRows() {
      if (view !== "ai") return;
      slots.forEach((s, i) => {
        const r = rowEls[i];
        r.dot.className = "lh-dot " + s.state;
        r.name.textContent = s.agent;
        r.sub.textContent = `${s.project} · ${s.machine}`;
        r.step.innerHTML = s.state === "done" ? "&#10003;" : s.step;
      });
    }

    // A tick only moves the targets; this loop walks the shown values towards
    // them, so bars and numbers glide rather than jump. It stops itself once
    // everything has arrived, so an idle demo costs nothing.
    let raf = null, lastFrameAt = 0;
    function frame() {
      lastFrameAt = performance.now();
      let moving = false;
      machines.forEach((m) => {
        ["cpu", "mem", "disk"].forEach((k) => {
          const d = m.target[k] - m.shown[k];
          if (Math.abs(d) > 0.15) { m.shown[k] += d * EASE; moving = true; }
          else m.shown[k] = m.target[k];
        });
      });
      paintCols();
      raf = moving ? requestAnimationFrame(frame) : null;
    }
    const nudge = () => { if (raf === null) raf = requestAnimationFrame(frame); };

    function tick() {
      // requestAnimationFrame does not run in a hidden or heavily throttled
      // tab, and every column repaint hangs off it. Without this the CPU view
      // would freeze outright there rather than simply stop being smooth, so
      // if no frame has run since the last tick, land on the old target before
      // choosing a new one. Where rAF is healthy the easing has long since
      // finished and this does nothing.
      const easing = performance.now() - lastFrameAt < TICK_MS;
      if (!easing) {
        machines.forEach((m) =>
          ["cpu", "mem", "disk"].forEach((k) => { m.shown[k] = m.target[k]; }));
      }

      machines.forEach((m) => {
        // small steps: a monitor that lurches reads as broken, not busy
        m.target.cpu = clamp(Math.round(m.target.cpu + (Math.random() - 0.45) * 16), 2, 97);
        m.target.mem = clamp(Math.round(m.target.mem + (Math.random() - 0.5) * 5), 14, 90);
        m.target.disk = clamp(Math.round(m.target.disk + (Math.random() - 0.5) * 1.1), 20, 95);
        if (m.live && Math.random() < 0.015) m.live = false;
        else if (!m.live && Math.random() < 0.5) m.live = true;
      });

      // At most one row changes per tick, so the panel reads as a place where
      // things happen rather than a slot machine. A finished session is
      // replaced in place -- the row never leaves, so nothing reflows.
      const s = slots[Math.floor(Math.random() * SLOTS)];
      if (s.state === "done") {
        const fresh = pick(AGENT_POOL.filter((p) => !slots.some((x) => x.project === p.project)));
        if (fresh) Object.assign(s, fresh, { state: "running" });
      } else if (Math.random() < 0.5) {
        s.state = s.state === "running" ? (Math.random() < 0.5 ? "waiting" : "done") : "running";
      }

      // Do not repaint the header while it is showing something hovered --
      // the pointer is on it and the reader is reading it.
      if (!hover) paintHead();
      paintRows();
      paintCols();   // always paint: rAF only supplies the in-between frames
      nudge();
    }

    switchView();

    const still = window.matchMedia("(prefers-reduced-motion: reduce)");
    let timer = null;
    const start = () => { if (!timer && !still.matches) timer = setInterval(tick, TICK_MS); };
    const stop = () => {
      clearInterval(timer); timer = null;
      if (raf !== null) { cancelAnimationFrame(raf); raf = null; }
    };
    still.addEventListener?.("change", () => (still.matches ? stop() : start()));

    // Only run while on screen -- but START FIRST and let the observer stop it.
    // In a context reporting a zero-height viewport the observer never fires at
    // all, and gating on it left the demo frozen with nothing to explain why.
    start();
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? start() : stop())),
        { threshold: 0.1 }).observe(root);
    }
  }

  document.querySelectorAll("[data-lh-demo]").forEach(build);
})();
