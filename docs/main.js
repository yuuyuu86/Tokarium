/* Tokarium 公開ページ: 水槽・ターミナル・品種改良ラボ・音・言語切りかえ */
(() => {
  "use strict";
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* 保存できなくても動く */ } },
  };

  // ---------- 言語 ----------
  const EN = {
    "skip": "Skip to content",
    "nav.how": "How it works", "nav.lab": "Breeding", "nav.play": "Play", "nav.screens": "Screens", "nav.features": "Features", "nav.sources": "Supported AI",
    "nav.download": "Download", "sound.off": "Sound off", "sound.on": "Sound on",
    "hud.water": "Water: clean",
    "hero.eyebrow": "A pixel-art aquarium for your Mac",
    "hero.lead": "The more you use AI,<br>the livelier your tank.",
    "hero.sub": "Using Claude Code, Codex and more earns coins. Spend them on fish for a pixel-art tank that lives on your desktop.",
    "hero.cta": "Download for Mac", "hero.feed": "Try feeding them",
    "hero.note": "Free · macOS 14 or later · Apple silicon / Intel",
    "hero.termcap": "Tokens turn into coins and drop into the tank",
    "hero.hint": "Click the water and the fish swim over",
    "how.eyebrow": "How it works", "how.title": "Your sea grows as you work",
    "how.s1.t": "Use AI as usual", "how.s1.p": "Tokarium reads only token counts from usage records on this Mac. Nothing else to do.",
    "how.s2.t": "Earn coins", "how.s2.p": "500,000 weighted tokens make 1 coin. Input and output count as 1, cache writes as 0.25, cache reads as 0.1.",
    "how.s3.t": "Raise your fish", "how.s3.p": "Buy fish and decorations, then feed them and change the water. Two healthy adults may have fry.",
    "how.aside": "Only usage after you install counts. Your conversations are never read.",
    "lab.eyebrow": "Breeding", "lab.title": "Pick a pair, chase new colors",
    "lab.lead": "Each fish carries two color genes, one from each parent. Every species has 13 varieties, and combination varieties can only be bred.",
    "lab.p1": "Parent A", "lab.p2": "Parent B", "lab.result": "Possible fry",
    "play.eyebrow": "Play", "play.title": "A little every day, for a long time",
    "play.missions.t": "Missions and keeper rank",
    "play.missions.p": "3 daily and 2 weekly missions. Feeding and breeding earn XP, and higher ranks bring new fish to the shop. Trade mission fragments for limited decorations like the Dragon Palace.",
    "play.mood.t": "Personality and affection",
    "play.mood.p": "Gluttons, shy ones, curious ones... The better you care for a fish, the farther it swims to meet you when you tap the water.",
    "play.desk.t": "It swims on your wallpaper",
    "play.desk.p": "Desktop mode, a widget, a screen saver and a menu bar window keep the tank in view without getting in your way.",
    "play.layout.t": "Your layout gets a score",
    "play.layout.p": "About 60 decorations. Hunt for combo bonuses like Japanese Garden and Sunken Treasure.",
    "play.sound.t": "Original music and sounds",
    "play.sound.p": "Songs that change between day and night, plus sounds for feeding and water changes. All made for this app. Try ♪ at the top.",
    "play.secret.t": "Hidden fish you can't buy",
    "play.secret.p": "When conditions are right, they wander into your tank. The encyclopedia gives only hints. Memorial fish come in 3 tiers per AI at 100, 1,000 and 5,000 coins.",
    "features.title": "Features",
    "screens.eyebrow": "Screens", "screens.title": "Pixel-art panels over the water",
    "screens.tank": "Tank", "screens.care": "Care", "screens.shop": "Shop", "screens.missions": "Missions", "screens.variants": "Varieties",
    "sources.eyebrow": "Supported AI", "sources.title": "Reads records already on your Mac",
    "src.cowork": "Claude desktop (Cowork)", "src.codex": "Codex (CLI and desktop)", "src.ollama": "Ollama (app)",
    "tag.measured": "Measured", "tag.estimated": "Estimated",
    "sources.note": "ChatGPT desktop and Claude desktop chats don't keep token counts on your Mac, so they can't be read. Estimated values become coins only if you turn that on in Settings.",
    "privacy.eyebrow": "Privacy", "privacy.title": "It reads numbers, nothing more",
    "privacy.p1": "Only token counts, times and IDs to avoid double counting. Your conversations are never read.",
    "privacy.p2": "Everything stays on this Mac. API keys and cookies are never touched.",
    "privacy.p3": "Read-only. It never changes your AI tools' settings or records.",
    "dl.title": "Bring the tank to your Mac",
    "dl.p": "Free and MIT licensed. Notarized by Apple, with updates delivered inside the app.",
    "dl.cta": "Download Tokarium", "dl.brew": "Or install with Homebrew", "dl.req": "macOS 14 Sonoma or later · Apple silicon / Intel",
    "install.1": "Open the downloaded <b>Tokarium.dmg</b>",
    "install.2": "Drag <b>Tokarium</b> into your Applications folder",
    "install.3": "Open it, choose which AI to read, and click <b>Start</b>",
    "faq.q1": "Does past usage count?", "faq.a1": "No. Only usage after the first launch becomes coins. You start with 1 fish, 50 coins and 20 servings of food.",
    "faq.q2": "Can my fish die if I forget them?", "faq.a2": "If you keep forgetting food and water changes, they weaken and eventually die. Time while your Mac is closed counts for at most 48 hours, and that alone never kills a fish.",
    "faq.q3": "Can I keep one tank on several Macs?", "faq.a3": "Yes. Sync with iCloud Drive, and coins add up AI usage from every Mac.",
    "faq.q4": "How do I uninstall it?", "faq.a4": "Move Tokarium to the Trash. To remove its data too, delete <code>~/Library/Application Support/Tokarium</code>.",
    "footer.bottom": "You've reached the sea floor.", "footer.up": "Back to the surface ▲", "footer.privacy": "Privacy",
    "footer.license": "MIT License. Font: DotGothic16 (SIL OFL). Original music and sound effects.",
  };
  const JA = {};
  $$("[data-i18n]").forEach(el => { JA[el.dataset.i18n] = el.textContent; });
  $$("[data-i18n-html]").forEach(el => { JA[el.dataset.i18nHtml] = el.innerHTML; });
  JA["sound.on"] = "音 ON";
  const EN_EXTRA = {
    genes: { wild: "Wild", albino: "Albino", black: "Black", gold: "Gold", blue: "Blue", red: "Red", pastel: "Pastel" },
    variants: { wild: "Wild type", albino: "Albino", black: "Black", gold: "Gold", blue: "Blue", red: "Red", pastel: "Pastel",
      sunset: "Sunset", sky: "Sky", panda: "Panda", purple: "Purple", platinum: "Platinum", sakura: "Sakura" },
    species: { guppy: "Guppy", neon: "Neon tetra", goldfish: "Goldfish", betta: "Betta" },
    geneA: "Gene 1", geneB: "Gene 2",
    secrets: [["Firefly Tetra", "At night, near something that glows"], ["Blind Cave Fish", "Somewhere to swim through, very clean water"],
      ["Rainbow Medaka", "For keepers of many varieties"], ["Oarfish", "An extra-large, lively tank"], ["Coelacanth", "Ancient ruins and a long life"]],
    alt: { tank: "Tank screen", care: "Care screen", shop: "Shop screen", missions: "Missions screen", variants: "Variety encyclopedia" },
    tankLabel: "A tank with swimming fish. Click and they swim over.",
  };
  const JA_EXTRA = {
    genes: { wild: "野生型", albino: "アルビノ", black: "ブラック", gold: "ゴールド", blue: "ブルー", red: "レッド", pastel: "パステル" },
    variants: { wild: "原種", albino: "アルビノ", black: "ブラック", gold: "ゴールド", blue: "ブルー", red: "レッド", pastel: "パステル",
      sunset: "サンセット", sky: "スカイ", panda: "パンダ", purple: "パープル", platinum: "プラチナ", sakura: "サクラ" },
    species: { guppy: "グッピー", neon: "ネオンテトラ", goldfish: "金魚", betta: "ベタ" },
    geneA: "遺伝子1", geneB: "遺伝子2",
    secrets: [["ホタルテトラ", "夜、光るもののそばに…"], ["ドウクツギョ", "くぐれる場所と、とてもきれいな水"],
      ["ニジイロメダカ", "いろいろな品種を育てた人に"], ["リュウグウノツカイ", "特大の、にぎやかな水槽に"], ["シーラカンス", "古代の遺跡と、長い時"]],
    alt: { tank: "水槽の画面", care: "お世話の画面", shop: "お店の画面", missions: "ミッションの画面", variants: "品種の図鑑" },
    tankLabel: "魚が泳ぐ水槽。クリックすると魚が寄ってきます",
  };
  let lang = store.get("lang") || "ja";
  const t = () => (lang === "en" ? EN_EXTRA : JA_EXTRA);

  function applyLang() {
    document.documentElement.lang = lang;
    const dict = lang === "en" ? EN : JA;
    $$("[data-i18n]").forEach(el => { const v = dict[el.dataset.i18n]; if (v != null) el.textContent = v; });
    $$("[data-i18n-html]").forEach(el => { const v = dict[el.dataset.i18nHtml]; if (v != null) el.innerHTML = v; });
    const btn = $("#lang");
    btn.textContent = lang === "en" ? "日本語" : "EN";
    btn.setAttribute("aria-label", lang === "en" ? "日本語で表示" : "Show in English");
    $("#tank").setAttribute("aria-label", t().tankLabel);
    updateSoundLabel();
    renderSecrets();
    renderLab();
    renderFeatures();
    const cur = $(".window__tabs [aria-selected=true]");
    if (cur) $("#shot").alt = t().alt[cur.dataset.shot];
  }
  $("#lang").addEventListener("click", () => {
    lang = lang === "en" ? "ja" : "en";
    store.set("lang", lang);
    applyLang();
    sfx("click");
  });

  // ---------- 音 ----------
  let soundOn = false;
  const bgm = $("#bgm");
  bgm.volume = 0.35;
  const sfxCache = {};
  const lastPlayed = {};
  function sfx(name, gap = 0.08) {
    if (!soundOn) return;
    const now = performance.now() / 1000;
    if (lastPlayed[name] && now - lastPlayed[name] < gap) return;
    lastPlayed[name] = now;
    const a = (sfxCache[name] ||= new Audio(`assets/sounds/sfx_${name}.m4a`));
    const node = a.paused ? a : a.cloneNode();
    node.volume = 0.5;
    node.currentTime = 0;
    node.play().catch(() => {});
  }
  function updateSoundLabel() {
    const btn = $("#sound");
    btn.setAttribute("aria-pressed", String(soundOn));
    const label = $("[data-i18n]", btn);
    label.dataset.i18n = soundOn ? "sound.on" : "sound.off";
    label.textContent = (lang === "en" ? EN : JA)[label.dataset.i18n];
    document.body.classList.toggle("is-sound", soundOn);
  }
  $("#sound").addEventListener("click", () => {
    soundOn = !soundOn;
    if (soundOn) { bgm.play().catch(() => {}); sfx("sparkle"); } else bgm.pause();
    updateSoundLabel();
  });

  // ---------- 画像 ----------
  const images = {};
  function img(src) {
    if (images[src]) return images[src];
    const i = new Image();
    i.src = src;
    images[src] = i;
    return i;
  }
  const ready = i => i.complete && i.naturalWidth > 0;

  // ---------- 水槽 ----------
  const canvas = $("#tank");
  const ctx = canvas.getContext("2d");
  let W = 0, H = 0, P = 3, dpr = 1, sandTop = 0, visible = true;
  let backdrop = null;

  const DECOS = [
    ["tallgrass", 0.05, 0], ["sword", 0.13, 1], ["castle", 0.24, 0], ["anemone", 0.34, 1], ["coral", 0.42, 0],
    ["airstone", 0.49, 1], ["chest", 0.56, 1], ["ship", 0.7, 0], ["fern", 0.82, 1], ["starfish", 0.2, 1], ["lotus", 0.92, 0],
  ].map(([id, x, layer]) => ({ id, x, layer, img: img(`assets/sprites/deco/${id}.png`) }));

  const FISH = [
    ["neon", null, "any", 0.09, true], ["neon", null, "any", 0.09, true], ["neon", null, "any", 0.09, true], ["neon", null, "any", 0.09, true],
    ["neon", null, "any", 0.09, true], ["guppy", "gold", "upper", 0.07], ["guppy", "sunset", "upper", 0.07], ["clown", null, "any", 0.08],
    ["angel", null, "any", 0.06], ["goldfish", "red", "any", 0.05], ["betta", "purple", "upper", 0.05], ["cory", null, "bottom", 0.05],
    ["m_claude2", null, "any", 0.07], ["hotaru", null, "any", 0.08],
  ].map(([id, variant, zone, speed, school], i) => {
    const frames = variant
      ? [img(`assets/sprites/variants/${id}-${variant}.png`), img(`assets/sprites/variants/${id}-${variant}.png`)]
      : [img(`assets/sprites/fish/${id}-0.png`), img(`assets/sprites/fish/${id}-1.png`)];
    const y = zone === "bottom" ? 0.83 : zone === "upper" ? 0.2 + Math.random() * 0.25 : 0.25 + Math.random() * 0.45;
    return { id, frames, zone, speed, school: !!school, x: 0.1 + Math.random() * 0.8, y, vx: 0, vy: 0, tx: Math.random(), ty: y,
             right: Math.random() < 0.5, phase: Math.random() * 10, retarget: 0, leader: school && i > 0 ? 0 : -1, rank: i };
  });

  const pellets = [], bubbles = [], ripples = [], coins = [], sparkles = [];
  let attract = null, attractUntil = 0, time = 0, last = 0;

  function resize() {
    const r = canvas.getBoundingClientRect();
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = Math.round(r.width); H = Math.round(r.height);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    P = Math.max(2, Math.floor(Math.min(W, H) / 190));
    sandTop = H - P * 16;
    backdrop = drawBackdrop();
    const hud = $(".hud");
    hud.style.top = innerWidth <= 720 ? `${canvas.offsetTop + 10}px` : "";
  }

  function drawBackdrop() {
    const off = document.createElement("canvas");
    off.width = canvas.width; off.height = canvas.height;
    const g = off.getContext("2d");
    g.scale(dpr, dpr);
    // 水の色の段
    const bands = ["#5BB8EA", "#4AA8E0", "#3A98D4", "#2E86C4", "#2574B0", "#1E639C", "#185489", "#134677"];
    const bh = Math.ceil(sandTop / bands.length / P) * P;
    bands.forEach((c, i) => { g.fillStyle = c; g.fillRect(0, i * bh, W, bh + 1); });
    // 水面のゆらぎ
    g.fillStyle = "rgba(255,255,255,.35)";
    for (let x = 0; x < W; x += P * 6) g.fillRect(x, 0, P * 3, P);
    // 奥の岩かげ
    g.fillStyle = "rgba(10,40,80,.35)";
    for (let x = 0, i = 0; x < W; i++) {
      const w = P * (10 + ((i * 37) % 17)), h = P * (4 + ((i * 53) % 7));
      g.fillRect(x, sandTop - h, w, h); x += w + P * ((i * 29) % 9);
    }
    // 砂
    g.fillStyle = "#D8BE7E"; g.fillRect(0, sandTop, W, H - sandTop);
    g.fillStyle = "#E8D49A"; g.fillRect(0, sandTop, W, P);
    let seed = 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < (W * (H - sandTop)) / (P * P * 18); i++) {
      g.fillStyle = rnd() < 0.5 ? "#C8A96A" : "#EEDDB0";
      g.fillRect(Math.floor(rnd() * W / P) * P, sandTop + P * 2 + Math.floor(rnd() * (H - sandTop) / P) * P, P, P);
    }
    return off;
  }

  const snap = v => Math.round(v / P) * P;

  function drawDeco(d) {
    if (!ready(d.img)) return;
    const s = P;
    const w = d.img.naturalWidth * s, h = d.img.naturalHeight * s;
    ctx.drawImage(d.img, snap(d.x * W - w / 2), snap(sandTop + P * (d.layer ? 3 : 1) - h), w, h);
  }

  function fishRect(f) {
    const im = f.frames[0];
    if (!ready(im)) return null;
    const s = Math.round(P * 1.6);
    const w = im.naturalWidth * s, h = im.naturalHeight * s;
    const bob = Math.sin(f.phase * 0.5) * P * 0.6;
    return { x: snap(f.x * W - w / 2), y: snap(f.y * H - h / 2 + bob), w, h };
  }

  function yRange(f) {
    const bottom = (sandTop - P * 6) / H;
    if (f.zone === "upper") return [0.12, 0.5];
    if (f.zone === "bottom") return [bottom - 0.03, bottom];
    return [0.14, bottom - 0.06];
  }

  function step(dt) {
    time += dt;
    const aspect = W / Math.max(1, H);
    if (attract && time > attractUntil) attract = null;
    for (const f of FISH) {
      let speed = f.speed * (reduced ? 0.5 : 1);
      let chasing = false;
      const [lo, hi] = yRange(f);
      if (attract && Math.hypot((attract.x - f.x) * aspect, attract.y - f.y) < 0.7) {
        f.tx = attract.x + Math.sin(f.phase) * 0.03;
        f.ty = f.zone === "bottom" ? f.ty : Math.min(hi, Math.max(lo, attract.y + Math.cos(f.phase) * 0.03));
        speed *= 1.8; chasing = true;
      } else {
        let best = null, bd = 0.7;
        pellets.forEach((p, i) => { const d = Math.hypot((p.x - f.x) * aspect, p.y - f.y); if (d < bd) { bd = d; best = i; } });
        if (best != null) {
          const p = pellets[best];
          f.tx = p.x; f.ty = Math.min(hi, p.y); speed *= 2; chasing = true;
          if (bd < 0.03) { pellets.splice(best, 1); sfx("eat", 0.15); sparkles.push({ x: f.x, y: f.y, t: time }); }
        } else if (f.leader >= 0) {
          const l = FISH[f.leader];
          const back = l.right ? -1 : 1, row = Math.ceil(f.rank / 2) * 0.035, side = f.rank % 2 ? -1 : 1;
          f.tx = l.x + back * row; f.ty = Math.min(hi, Math.max(lo, l.y + side * row * 0.8)); speed *= 1.15;
        } else if (time > f.retarget || Math.hypot((f.tx - f.x) * aspect, f.ty - f.y) < 0.02) {
          f.tx = 0.06 + Math.random() * 0.88; f.ty = lo + Math.random() * (hi - lo); f.retarget = time + 3 + Math.random() * 6;
        }
      }
      const dx = (f.tx - f.x) * aspect, dy = f.ty - f.y, dist = Math.max(1e-4, Math.hypot(dx, dy));
      const ease = Math.min(1, dt * (chasing ? 3 : 1.2));
      f.vx += (dx / dist * speed / aspect - f.vx) * ease;
      f.vy += (dy / dist * speed * 0.6 - f.vy) * ease;
      f.x = Math.min(0.97, Math.max(0.03, f.x + f.vx * dt));
      f.y = Math.min(hi, Math.max(0.08, f.y + f.vy * dt));
      if (f.vx > 0.004) f.right = true; else if (f.vx < -0.004) f.right = false;
      f.phase += dt * (2 + speed * 30);
    }
    // 餌が沈む
    for (const p of pellets) if (p.y < (sandTop - P) / H) { p.y += 0.04 * dt; p.x += Math.sin(time * 2 + p.x * 20) * 0.002 * dt; } else p.landed ??= time;
    for (let i = pellets.length - 1; i >= 0; i--) if (pellets[i].landed && time - pellets[i].landed > 20) pellets.splice(i, 1);
    // 泡（エアストーンから）
    if (Math.random() < dt * 4) bubbles.push({ x: 0.49 + (Math.random() - 0.5) * 0.01, y: (sandTop - P * 3) / H, s: 0.06 + Math.random() * 0.05, w: Math.random() * 6 });
    for (const b of bubbles) b.y -= b.s * dt;
    for (let i = bubbles.length - 1; i >= 0; i--) if (bubbles[i].y < 0.02) bubbles.splice(i, 1);
    // コインが落ちる
    for (const c of coins) { c.vy += 0.5 * dt; c.y += c.vy * dt; if (c.y > (sandTop - P * 2) / H && !c.done) { c.done = time; sparkles.push({ x: c.x, y: c.y, t: time }); } }
    for (let i = coins.length - 1; i >= 0; i--) if (coins[i].done && time - coins[i].done > 0.4) coins.splice(i, 1);
    for (let i = ripples.length - 1; i >= 0; i--) if (time - ripples[i].t > 1.2) ripples.splice(i, 1);
    for (let i = sparkles.length - 1; i >= 0; i--) if (time - sparkles[i].t > 0.6) sparkles.splice(i, 1);
  }

  function draw() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, W, H);
    if (backdrop) { ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.drawImage(backdrop, 0, 0); ctx.restore(); }
    // 光の筋
    ctx.fillStyle = "rgba(255,255,255,.07)";
    for (let k = 0; k < 4; k++) {
      const x0 = W * (0.12 + k * 0.24) + Math.sin(time * 0.3 + k) * P * 6;
      ctx.beginPath(); ctx.moveTo(x0, 0); ctx.lineTo(x0 + P * 14, 0); ctx.lineTo(x0 + P * 40, sandTop); ctx.lineTo(x0 + P * 22, sandTop); ctx.fill();
    }
    DECOS.filter(d => d.layer === 0).forEach(drawDeco);
    // 泡
    ctx.fillStyle = "rgba(255,255,255,.6)";
    for (const b of bubbles) {
      const bx = snap(b.x * W + Math.sin(time * 3 + b.w) * P), by = snap(b.y * H);
      ctx.fillRect(bx, by - P, P, P); ctx.fillRect(bx - P, by, P, P); ctx.fillRect(bx + P, by, P, P); ctx.fillRect(bx, by + P, P, P);
    }
    // 餌
    ctx.fillStyle = "#8B4A1C";
    for (const p of pellets) ctx.fillRect(snap(p.x * W), snap(p.y * H), P, P);
    // 魚
    for (const f of FISH) {
      const r = fishRect(f); if (!r) continue;
      const im = f.frames[Math.floor(f.phase) % 2];
      if (!ready(im)) continue;
      ctx.save();
      if (!f.right) { ctx.translate(r.x + r.w / 2, 0); ctx.scale(-1, 1); ctx.translate(-(r.x + r.w / 2), 0); }
      ctx.drawImage(im, r.x, r.y, r.w, r.h);
      ctx.restore();
    }
    DECOS.filter(d => d.layer === 1).forEach(drawDeco);
    // コイン
    for (const c of coins) {
      const cx = snap(c.x * W), cy = snap(c.y * H), wob = Math.abs(Math.cos(time * 8 + c.x * 10));
      const w = Math.max(1, Math.round(3 * wob)) * P;
      ctx.fillStyle = "#6A4A00"; ctx.fillRect(cx - w / 2 - P, cy - P * 2, w + P * 2, P * 5);
      ctx.fillStyle = "#FFD54F"; ctx.fillRect(cx - w / 2, cy - P * 2, w, P * 5);
      ctx.fillStyle = "#FFF0A0"; ctx.fillRect(cx - w / 2, cy - P, Math.max(P, w / 3), P * 2);
    }
    // 波紋
    for (const rp of ripples) {
      const age = (time - rp.t) / 1.2, rad = snap(age * P * 14 + P * 2);
      ctx.fillStyle = `rgba(255,255,255,${0.7 * (1 - age)})`;
      for (let k = 0; k < 16; k++) {
        const a = (k / 16) * Math.PI * 2;
        ctx.fillRect(snap(rp.x * W + Math.cos(a) * rad), snap(rp.y * H + Math.sin(a) * rad * 0.6), P, P);
      }
    }
    // きらっ
    ctx.fillStyle = "#FFF6B0";
    for (const s of sparkles) {
      const age = (time - s.t) / 0.6, sx = snap(s.x * W), sy = snap(s.y * H - age * P * 8);
      ctx.fillRect(sx, sy - P, P, P * 3); ctx.fillRect(sx - P, sy, P * 3, P);
    }
  }

  function loop(ts) {
    const dt = last ? Math.min(0.1, (ts - last) / 1000) : 0;
    last = ts;
    // 見えていないときは動きを止める（絵は最後の状態のまま描く）
    if (visible && !document.hidden) step(dt);
    if (visible) draw();
    requestAnimationFrame(loop);
  }

  function pointIn(e) {
    const r = canvas.getBoundingClientRect();
    return { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height };
  }
  canvas.addEventListener("click", e => {
    const p = pointIn(e);
    attract = { x: p.x, y: Math.min(p.y, (sandTop - P * 4) / H) };
    attractUntil = time + 4;
    ripples.push({ x: p.x, y: p.y, t: time });
    sfx("tap", 0.1);
  });
  function feed() {
    const c = 0.3 + Math.random() * 0.4;
    for (let i = 0; i < 16; i++) pellets.push({ x: Math.min(0.97, Math.max(0.03, c + (Math.random() - 0.5) * 0.24)), y: 0.02 + Math.random() * 0.03 });
    sfx("feed");
  }
  $("#feed").addEventListener("click", feed);

  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }, { threshold: 0.01 }).observe(canvas);
  addEventListener("resize", resize);

  // ---------- ターミナル → コイン ----------
  const TERM = [
    { cmd: '$ claude "fix the flaky test"', out: ["  ⏺ Read src/parser.ts", "  ⏺ Update src/parser.ts (+12 −3)"], tok: 486210 },
    { cmd: '$ codex "add a dark mode toggle"', out: ["  • Edited App.tsx", "  • Ran npm test — 42 passed"], tok: 1024880 },
    { cmd: '$ gemini "summarize this log"', out: ["  ✦ 3 warnings, 0 errors"], tok: 512400 },
    { cmd: '$ claude "write the release notes"', out: ["  ⏺ Write CHANGELOG.md"], tok: 538920 },
  ];
  const term = $("#term");
  let coinCount = 2180;
  const coinEl = $("#coins");
  const fmt = n => n.toLocaleString("en-US");

  function addLine(html, cls) {
    const line = document.createElement("div");
    if (cls) line.className = cls;
    line.innerHTML = html;
    term.appendChild(line);
    while (term.children.length > 7) term.removeChild(term.firstChild);
    return line;
  }
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  async function type(line, text) {
    if (reduced) { line.textContent = text; return; }
    for (let i = 1; i <= text.length; i++) { line.textContent = text.slice(0, i); await sleep(28 + Math.random() * 30); }
  }
  function flyToken(fromEl, amount) {
    const coinsGot = Math.max(1, Math.round(amount / 500000));
    const r = fromEl.getBoundingClientRect(), target = coinEl.getBoundingClientRect();
    const chip = document.createElement("span");
    chip.className = "token";
    chip.textContent = `+${coinsGot}`;
    chip.style.left = `${r.left + 20}px`; chip.style.top = `${r.top}px`;
    document.body.appendChild(chip);
    requestAnimationFrame(() => {
      chip.style.transform = `translate(${target.left - r.left - 20}px, ${target.top - r.top}px) scale(.8)`;
      chip.style.opacity = "0.2";
    });
    setTimeout(() => {
      chip.remove();
      coinCount += coinsGot;
      coinEl.textContent = fmt(coinCount);
      const badge = coinEl.closest(".badge");
      badge.classList.remove("is-pop"); void badge.offsetWidth; badge.classList.add("is-pop");
      for (let i = 0; i < coinsGot; i++) coins.push({ x: 0.55 + Math.random() * 0.35, y: -0.02 - i * 0.05, vy: 0.05 });
      sfx("coin", 0.3);
    }, reduced ? 0 : 900);
  }
  async function runTerm() {
    let i = 0;
    for (;;) {
      if ((document.hidden || !visible) && i > 0) { await sleep(800); continue; }
      const job = TERM[i++ % TERM.length];
      const cmd = addLine("", "t-cmd");
      await type(cmd, job.cmd);
      await sleep(400);
      for (const o of job.out) { addLine("", "t-dim").textContent = o; await sleep(500); }
      const tok = addLine(`  ✻ <span class="t-tok">${fmt(job.tok)}</span> tokens`, "");
      flyToken(tok, job.tok);
      await sleep(reduced ? 6000 : 2600);
    }
  }

  // ---------- 品種改良ラボ ----------
  const GENES = ["wild", "albino", "black", "gold", "blue", "red", "pastel"];
  const SWATCH = { wild: "#9DB4CC", albino: "#F8F0F0", black: "#2A2A34", gold: "#F0C030", blue: "#3A7AE0", red: "#E03040", pastel: "#F0C8E0" };
  const RECIPES = [[["gold", "red"], "sunset"], [["blue", "pastel"], "sky"], [["black", "albino"], "panda"],
                   [["blue", "red"], "purple"], [["gold", "albino"], "platinum"], [["red", "pastel"], "sakura"]];
  const STRONG = ["black", "red", "blue", "gold", "pastel", "albino"];
  const COMBOS = new Set(RECIPES.map(r => r[1]));
  function variantOf(a, b) {
    if (a === b) return a;
    if (a === "wild" || b === "wild") return "wild";
    const hit = RECIPES.find(([g]) => g.includes(a) && g.includes(b));
    if (hit) return hit[1];
    return STRONG.find(g => g === a || g === b);
  }
  const lab = { species: "guppy", parents: [["gold", "wild"], ["red", "wild"]] };
  function renderLab() {
    const sp = $("#lab-species");
    sp.innerHTML = "";
    for (const id of ["guppy", "neon", "goldfish", "betta"]) {
      const b = document.createElement("button");
      b.type = "button"; b.setAttribute("role", "radio"); b.setAttribute("aria-checked", String(lab.species === id));
      b.textContent = t().species[id];
      b.addEventListener("click", () => { lab.species = id; renderLab(); sfx("click"); });
      sp.appendChild(b);
    }
    $$(".parent").forEach(el => {
      const i = +el.dataset.parent, [a, b] = lab.parents[i], v = variantOf(a, b);
      const fish = $(".parent__fish", el);
      fish.src = `assets/sprites/variants/${lab.species}-${v}.png`;
      fish.alt = `${t().species[lab.species]}（${t().variants[v]}）`;
      $(".parent__variant", el).textContent = t().variants[v];
      const genes = $(".genes", el);
      genes.innerHTML = "";
      [0, 1].forEach(slot => {
        const row = document.createElement("div");
        row.className = "genes__row";
        row.innerHTML = `<b>${slot ? t().geneB : t().geneA}</b>`;
        for (const g of GENES) {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.setAttribute("aria-pressed", String(lab.parents[i][slot] === g));
          btn.innerHTML = `<span class="swatch" style="background:${SWATCH[g]}"></span>${t().genes[g]}`;
          btn.addEventListener("click", () => { lab.parents[i][slot] = g; renderLab(); sfx("click"); });
          row.appendChild(btn);
        }
        genes.appendChild(row);
      });
    });
    // 生まれうる品種（両親から1つずつ）
    const count = {};
    for (const a of lab.parents[0]) for (const b of lab.parents[1]) { const v = variantOf(a, b); count[v] = (count[v] || 0) + 0.25; }
    const list = $("#outcomes");
    list.innerHTML = "";
    Object.entries(count).sort((x, y) => y[1] - x[1]).forEach(([v, p], k) => {
      const li = document.createElement("li");
      li.className = "outcome" + (COMBOS.has(v) ? " outcome--new" : "");
      li.style.animationDelay = `${k * 70}ms`;
      li.innerHTML = `<img class="sprite" src="assets/sprites/variants/${lab.species}-${v}.png" alt="">
        <div><span class="outcome__name">${t().variants[v]}</span><span class="outcome__bar" style="width:${p * 100}%"></span></div>
        <span class="outcome__pct">${Math.round(p * 100)}%</span>`;
      list.appendChild(li);
    });
  }

  // ---------- 隠れた魚 ----------
  function renderSecrets() {
    const el = $("#secrets");
    el.innerHTML = "";
    ["hotaru", "cavefish", "rainbowmedaka", "oarfish", "coelacanth"].forEach((id, i) => {
      const [name, hint] = t().secrets[i];
      const d = document.createElement("div");
      d.className = "secret";
      d.innerHTML = `<img class="sprite" src="assets/sprites/fish/${id}-0.png" alt=""><b>？？？</b><span>${hint}</span>`;
      d.title = name;
      el.appendChild(d);
    });
  }


  // ---------- 機能一覧 ----------
  const F = "assets/sprites/fish/", D = "assets/sprites/deco/";
  const CATS = [
    ["all", "すべて", "All"], ["care", "育てる", "Care"], ["collect", "集める", "Collect"], ["play", "遊ぶ", "Play"],
    ["view", "見る・聴く", "Look & listen"], ["ai", "AIとコイン", "AI & coins"], ["safe", "安心して使う", "Peace of mind"],
  ];
  // [分類, アイコン, 日本語の名前, 日本語の説明, 英語の名前, 英語の説明]
  const FEATURES = [
    ["care", F + "neon-0.png", "餌やりと水換え", "餌は1日1〜2回、水換えは数日に1回。あげすぎると水が汚れます。", "Feeding and water changes", "Feed once or twice a day, change the water every few days. Overfeeding dirties the water."],
    ["care", F + "guppy-0.png", "成長", "稚魚から若魚、成魚へ。よく世話をすると約1週間で大人に。", "Growth", "Fry grow into juveniles, then adults, in about a week of good care."],
    ["care", D + "flowercoral.png", "繁殖と世代", "元気な成魚が2匹いると稚魚が生まれることも。何代目かも記録します。", "Breeding and generations", "Two healthy adults may have fry. Every generation is recorded."],
    ["care", D + "pot.png", "病気と薬", "汚れた水が続くと病気に。薬や水換えで治ります。", "Illness and medicine", "Dirty water can make fish sick. Medicine and clean water help."],
    ["care", D + "memorial.png", "寿命と天寿", "種類ごとに寿命があり、まっとうすると図鑑に記録されます。", "Lifespan", "Each species has a lifespan. A full life is noted in the encyclopedia."],
    ["care", F + "betta-0.png", "性格6種", "くいしんぼう・人なつこい・臆病・元気・のんびり・好奇心旺盛。泳ぎ方が変わります。", "6 personalities", "Glutton, friendly, shy, lively, laid-back, curious. Each swims differently."],
    ["care", F + "clown-0.png", "なつき度", "世話をするほどなつき、水をたたくと遠くから寄ってきます。", "Affection", "Well-loved fish swim over from farther away when you tap the water."],
    ["care", F + "cory-0.png", "魚どうしの関わり", "群れで泳ぐ魚、水を掃除する魚、相性の悪い組み合わせ、イソギンチャクとクマノミの共生。", "Fish get along (or don't)", "Schooling fish, cleaners, bad pairings, and clownfish that love anemones."],
    ["care", D + "airstone.png", "設備", "自動給餌器とろ過フィルターで、お世話を少し楽に。", "Equipment", "An auto feeder and a filter make care a little easier."],
    ["care", D + "castle.png", "水槽の拡張", "小さな水槽から特大の水槽まで4段階。魚は最大32匹。", "Bigger tanks", "Four sizes, from small to extra-large. Up to 32 fish."],
    ["care", D + "shell.png", "里親に出す", "水槽がいっぱいになったら、魚を新しいおうちへ送り出せます。", "Rehoming", "When the tank is full, send a fish to a new home."],
    ["collect", F + "angel-0.png", "魚54種", "お店の33種に、季節・隠れた魚・記念の魚を合わせて54種。", "54 species", "33 in the shop plus seasonal, hidden and memorial fish."],
    ["collect", "assets/sprites/variants/guppy-sunset.png", "品種13", "1種類の魚につき13品種。2色の組み合わせは繁殖でしか生まれません。", "13 varieties", "13 per species. Combination colors can only be bred."],
    ["collect", F + "rainbowmedaka-0.png", "色違い", "まれにきらきら光る色違いが生まれます。", "Shiny fish", "Now and then, a sparkling shiny fish is born."],
    ["collect", D + "ship.png", "装飾57種", "水草・石・サンゴ・置きもの。限定の装飾もあります。", "57 decorations", "Plants, stones, corals and ornaments, including limited ones."],
    ["collect", D + "lighthouse.png", "図鑑", "迎えた数・生まれた数・世代・品種を種類ごとに記録。", "Encyclopedia", "Counts, births, generations and varieties for every species."],
    ["collect", F + "hotaru-0.png", "隠れた魚5種", "条件がそろうと迷いこんでくる、お店に並ばない魚。", "5 hidden fish", "Fish you can't buy. They wander in when conditions are right."],
    ["collect", F + "m_claude-0.png", "記念の魚", "よく使うAIごとに、100・1000・5000コインで3段階。", "Memorial fish", "For each AI you use, three tiers at 100, 1,000 and 5,000 coins."],
    ["collect", D + "goldshell.png", "実績27と称号", "達成した実績は、称号として画面の上に表示できます。", "27 achievements and titles", "Show any achievement you've earned as a title."],
    ["collect", D + "familystone.png", "殿堂と思い出", "いちばん長生き・大きい・新しい世代の魚と、お別れした魚の思い出。", "Hall of fame and memories", "The longest-lived, biggest and newest-generation fish, and fish you've said goodbye to."],
    ["play", D + "glassfloat.png", "ミッション", "毎日3つ・毎週2つ。ごほうびは経験値・餌・薬・かけら。", "Missions", "3 daily and 2 weekly. Rewards are XP, food, medicine and fragments."],
    ["play", D + "starlamp.png", "飼育員ランク", "ランク1〜20。上がるとお店に新しい魚や装飾が並びます。", "Keeper rank", "Ranks 1 to 20. New fish and decorations unlock as you rise."],
    ["play", D + "ryugu.png", "かけらの交換所", "ミッションのかけらで、竜宮城などの限定の装飾と交換。", "Fragment exchange", "Trade mission fragments for limited decorations like the Dragon Palace."],
    ["play", "assets/sprites/variants/neon-blue.png", "今日の入荷", "毎日2匹、品種の魚がお店に並びます。", "Today's arrivals", "Two variety fish arrive in the shop every day."],
    ["play", D + "chest.png", "宝箱", "AIをたくさん使った日は、宝箱が流れてきます。", "Treasure chests", "On days you use AI a lot, a treasure chest drifts in."],
    ["play", D + "pumpkin.png", "季節のイベント", "お正月・夏祭り・ハロウィン・クリスマスに限定の魚と装飾。", "Seasonal events", "Limited fish and decorations for New Year, summer festival, Halloween and Christmas."],
    ["play", D + "torii.png", "レイアウトの評価", "配置に100点満点の点数。組み合わせのボーナスも8種。", "Layout score", "Your layout is scored out of 100, with 8 combo bonuses."],
    ["play", D + "anemone.png", "水槽と遊ぶ", "水をたたくと魚が寄り、餌を落とすと食べに来ます。", "Play with the tank", "Tap the water and fish come over. Drop food and they eat."],
    ["play", D + "gems.png", "写真を撮る", "操作パネルを消した水槽の写真を、ワンクリックで保存。", "Take photos", "Save a photo of your tank without the panels, in one click."],
    ["view", D + "tallgrass.png", "ウィンドウ表示", "大きさを自由に変えられる窓で、水槽を眺めます。", "Window mode", "Watch the tank in a window you can resize."],
    ["view", D + "wood.png", "デスクトップ表示", "壁紙の上・アイコンの下に水槽。壁紙の設定は変えません。", "Desktop mode", "The tank sits above your wallpaper and below your icons."],
    ["view", D + "bluerock.png", "ウィジェット", "お気に入りの魚と水槽の様子を、デスクトップのウィジェットで。", "Widget", "See your favorite fish and tank status in a desktop widget."],
    ["view", D + "stonelantern.png", "スクリーンセーバー", "あなたの水槽が、Macのスクリーンセーバーになります。", "Screen saver", "Your own tank becomes your Mac's screen saver."],
    ["view", D + "marimo.png", "メニューバーの小窓", "メニューバーから小さな水槽をのぞいて、すぐお世話。", "Menu bar window", "Peek at a small tank from the menu bar and care for it right away."],
    ["view", D + "lotus.png", "時間帯と季節", "朝焼け・夕焼け・夜の光。春は花びら、秋は葉、冬はマリンスノー。", "Time of day and seasons", "Dawn, dusk and night light. Petals in spring, leaves in fall, marine snow in winter."],
    ["view", D + "furin.png", "BGMと効果音", "昼と夜で変わる曲と16種の効果音。すべてオリジナル。", "Music and sound", "Day and night songs plus 16 sound effects, all original."],
    ["ai", D + "aimonument.png", "8つのAIに対応", "Claude Code・Codex・Gemini CLI・Qwen Code・OpenCode・Copilot CLI など。", "8 AI sources", "Claude Code, Codex, Gemini CLI, Qwen Code, OpenCode, Copilot CLI and more."],
    ["ai", D + "treasurepile.png", "コインの換算", "重み付きで50万トークン＝1コイン。キャッシュは軽めに数えます。", "Coin conversion", "500,000 weighted tokens = 1 coin. Cache tokens count for less."],
    ["ai", D + "pillars.png", "AI利用量のグラフ", "日ごと・AIごとに、どれだけコインになったかを表示。", "Usage chart", "See how many coins each AI earned, day by day."],
    ["ai", D + "arch.png", "Claudeの利用枠の目安", "5時間枠の使用量と、リセットまでの時間を表示。", "Claude limit estimate", "Shows usage in the 5-hour window and time until reset."],
    ["ai", D + "coral.png", "複数のMacで合算", "iCloud Drive で同期すると、Macごとの利用を合計します。", "Combine Macs", "With iCloud Drive sync, usage from every Mac adds up."],
    ["safe", D + "rock.png", "自動バックアップ", "1日1回・7世代。データが壊れても自動で戻します。", "Auto backup", "Daily, 7 generations. Broken data is restored automatically."],
    ["safe", D + "stack.png", "省電力", "窓が隠れたら止め、バッテリーや低電力モードでは控えめに。", "Power saving", "Pauses when hidden and slows down on battery or Low Power Mode."],
    ["safe", D + "anchor.png", "ゆるめの難しさ", "Macを閉じていた間の反映は最大48時間。それだけで魚は死にません。", "Gentle pacing", "Time away counts for at most 48 hours, and that alone never kills a fish."],
    ["safe", D + "sword.png", "アクセシビリティ", "VoiceOver で魚を1匹ずつ読み上げ。キーボード操作、動きを減らす設定にも対応。", "Accessibility", "VoiceOver reads each fish. Keyboard shortcuts and reduced motion are supported."],
    ["safe", D + "redgrass.png", "日本語と英語", "システムの言語に合わせて切りかわります。", "Japanese and English", "Follows your system language."],
    ["safe", D + "fern.png", "自動アップデートと通知", "新しい版はアプリの中から。危険な魚やお世話の時間を通知でお知らせ。", "Updates and reminders", "Updates arrive in the app. Notifications warn about fish in danger and remind you to feed."],
  ];
  let cat = "all";
  function renderFeatures() {
    const en = lang === "en";
    const filters = $("#feature-filters");
    filters.innerHTML = "";
    for (const [id, ja, e] of CATS) {
      const b = document.createElement("button");
      b.type = "button";
      b.setAttribute("aria-pressed", String(cat === id));
      const n = id === "all" ? FEATURES.length : FEATURES.filter(f => f[0] === id).length;
      b.innerHTML = `${en ? e : ja}<span class="mono">${n}</span>`;
      b.addEventListener("click", () => { cat = id; renderFeatures(); sfx("click"); });
      filters.appendChild(b);
    }
    const list = $("#feature-list");
    list.innerHTML = "";
    const shown = FEATURES.filter(f => cat === "all" || f[0] === cat);
    shown.forEach((f, k) => {
      const li = document.createElement("li");
      li.className = "feature";
      li.style.animationDelay = `${Math.min(k, 20) * 25}ms`;
      li.innerHTML = `<span class="feature__icon"><img class="sprite" src="${f[1]}" alt="" loading="lazy"></span>
        <span class="feature__text"><b>${en ? f[4] : f[2]}</b><span>${en ? f[5] : f[3]}</span></span>`;
      // ドット絵は整数倍で、枠に収まるいちばん大きな倍率にする
      const im = $("img", li);
      const fit = () => {
        const k = Math.max(1, Math.floor(Math.min(44 / im.naturalWidth, 32 / im.naturalHeight)));
        im.style.width = `${im.naturalWidth * k}px`;
      };
      if (im.complete && im.naturalWidth) fit(); else im.addEventListener("load", fit);
      list.appendChild(li);
    });
    $("#feature-count").textContent = en ? `${shown.length} features` : `${shown.length} 個の機能`;
  }

  // ---------- 画面の切りかえ ----------
  $$(".window__tabs button").forEach(b => b.addEventListener("click", () => {
    $$(".window__tabs button").forEach(x => x.setAttribute("aria-selected", String(x === b)));
    const shot = $("#shot");
    shot.src = `assets/shots/${b.dataset.shot}.png`;
    shot.alt = t().alt[b.dataset.shot];
    shot.classList.remove("is-changing"); void shot.offsetWidth; shot.classList.add("is-changing");
    sfx("click");
  }));

  // ---------- 出てくる・潜る ----------
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); } }),
    { threshold: 0.15 });
  $$(".reveal").forEach(el => io.observe(el));

  const mix = (a, b, k) => {
    const pa = a.match(/\w\w/g).map(h => parseInt(h, 16)), pb = b.match(/\w\w/g).map(h => parseInt(h, 16));
    return "#" + pa.map((v, i) => Math.round(v + (pb[i] - v) * k).toString(16).padStart(2, "0")).join("");
  };
  const root = document.documentElement;
  const depth = $(".depth"), depthNum = $(".depth__num");
  const navLinks = $$(".nav__links a");
  function onScroll() {
    const max = Math.max(1, document.body.scrollHeight - innerHeight);
    const k = Math.min(1, Math.max(0, scrollY / max));
    root.style.setProperty("--sea-top", mix("1B5E96", "061224", Math.min(1, k * 1.3)));
    root.style.setProperty("--sea-bottom", mix("0E3563", "030A16", k));
    root.style.setProperty("--snow", String(Math.min(1, k * 2)));
    depth.style.setProperty("--depth", String(k));
    depthNum.textContent = String(Math.round(k * 200));
    depth.classList.toggle("is-on", scrollY > innerHeight * 0.5);
    let here = null;
    for (const a of navLinks) { const s = $(a.getAttribute("href")); if (s && s.getBoundingClientRect().top < innerHeight * 0.4) here = a; }
    navLinks.forEach(a => a.classList.toggle("is-here", a === here));
  }
  addEventListener("scroll", onScroll, { passive: true });

  // ---------- 海底 ----------
  const floor = $("#floor");
  [["tallgrass", 3, 4, true], ["rock", 9, 4], ["pineapple", 16, 4], ["grass", 24, 4, true], ["gems", 31, 4], ["torii", 40, 4],
   ["stonelantern", 50, 4], ["ryugu", 60, 4], ["redgrass", 72, 4, true], ["lighthouse", 79, 4], ["anchor", 88, 4], ["sword", 95, 4, true]]
    .forEach(([id, left, scale, sway]) => {
      const i = document.createElement("img");
      i.src = `assets/sprites/deco/${id}.png`; i.alt = "";
      i.className = sway ? "sway" : "";
      i.style.left = `${left}%`;
      const k = innerWidth <= 720 ? scale / 2 : scale;
      i.addEventListener("load", () => { i.style.width = `${i.naturalWidth * k}px`; i.style.marginLeft = `${-i.naturalWidth * k / 2}px`; });
      floor.appendChild(i);
    });

  // ---------- はじめる ----------
  if (!store.get("lang")) lang = (navigator.language || "ja").toLowerCase().startsWith("ja") ? "ja" : "en";
  applyLang();
  resize();
  onScroll();
  requestAnimationFrame(loop);
  runTerm();
})();
