/* Thinking Of You cage. Ported from Hush (rules.js + cage.js).

   Runs inside instagram.com as a WKUserScript at document start, in the page
   world, main frame only, before Instagram's own scripts.

   Native -> page:  window.__toyBoot = {unlocked, ownUsername}  (injected just
                    before this script on every page load)
                    window.__toySetState({unlocked: Bool, ownUsername: String?})
   Page -> native:  window.webkit.messageHandlers.toy.postMessage(msg) with
                    msg.type one of:
                      'ready'        {path}
                      'route'        {path, reel: Bool}
                      'blocked'      {reason, path, bounce: Bool}
                      'toast'        {text}
                      'ownUsername'  {username, source}
                      'unread'       {count}

   Layers while LOCKED, each a backstop for the one before:
   1. a blocked page never paints (immediate bounce to the inbox)
   2. clicks on links into feeds are swallowed
   3. history.pushState / replaceState / back into a feed bounce
   4. CSS hides the doorways (Home, Explore, Reels, Create, profile tabs, own profile)
   5. on a single /reel/<code>/ page: no vertical scrolling, no navigation to a
      different reel code, next-reel containers hidden
   The native WKNavigationDelegate (CageRules.swift) guards full navigations
   on top of all this. */
(function () {
  'use strict';
  if (window.__toyCage) return;
  window.__toyCage = true;

  // ---- rules (mirror of CageRules.swift) ------------------------------------
  const INBOX = '/direct/inbox/';
  const APP_ID = '936619743392459'; // instagram.com's public web app id
  const PROFILE_TABS = ['reels', 'tagged', 'saved'];
  const RESERVED = new Set([
    'direct', 'p', 'reel', 'reels', 'tv', 'stories', 'explore', 'accounts', 'about', 'legal',
    'developer', 'emails', 'challenge', 'notes', 'web', 'api', 'graphql', 'ajax', 'static',
    'create', 'session', 'privacy', 'terms', 'help', 'your_activity', 'nametag', 'qr', 'sync',
    'invites', 'lite', 'topics', 'locations', 'music', 'audio', 'threads', 'oauth', 'data', '_n', '_u',
  ]);

  // Entry points hidden on allowed pages while locked. href selectors work in
  // every UI language; aria-label selectors catch icon buttons with no href.
  const HIDE = [
    'a[href="/"]',
    'a[href="https://www.instagram.com/"]',
    'a[href^="/explore"]',
    'a[href^="/reels"]',
    'a[href*="/create/"]',
    'a[href$="/reels/"]',
    'a[href$="/tagged/"]',
    'a[href$="/saved/"]',
    'a:has(svg[aria-label="Home"])',
    'a:has(svg[aria-label="Explore"])',
    'a:has(svg[aria-label="Search"])',
    'a:has(svg[aria-label="Reels"])',
    'a:has(svg[aria-label="New post"])',
    'a:has(svg[aria-label="Create"])',
    '[role="button"]:has(> svg[aria-label="New post"])',
    '[role="button"]:has(> svg[aria-label="Create"])',
    'a[href*="threads.net"]',
    'a[href*="threads.com"]',
    'a[href*="apps.apple.com"]',
    'a[href*="itunes.apple.com"]',
    'a[href*="play.google.com"]',
    'a[href^="instagram://"]',
    '[data-toy-next-reel]',
  ];

  // Only on the inbox: its back arrow leads to the feed.
  const HIDE_INBOX = [
    'a:has(svg[aria-label="Back"])',
    '[role="button"]:has(svg[aria-label="Back"]):not(:has([role="button"]))',
  ];

  function clean(name) {
    if (typeof name !== 'string') return null;
    let n = name.trim().toLowerCase();
    if (n.startsWith('@')) n = n.slice(1);
    if (n.endsWith('/')) n = n.slice(0, -1);
    if (!/^[a-z0-9._]{1,30}$/.test(n) || RESERVED.has(n)) return null;
    return n;
  }

  function segments(path) {
    return String(path || '/').split(/[?#]/)[0].split('/').filter(Boolean);
  }

  // A first segment that can be a username (not an Instagram route).
  const isProfileSegment = (x) => /^[\w.]+$/.test(x) && !RESERVED.has(x.toLowerCase());

  // Single-reel code: /reel/<code>/ or the user-scoped /<user>/reel/<code>/.
  function reelCode(path) {
    const s = segments(path);
    if (s.length >= 2 && s[0].toLowerCase() === 'reel') return s[1];
    if (s.length >= 3 && s[1].toLowerCase() === 'reel' && isProfileSegment(s[0])) return s[2];
    return null;
  }

  const isShortcode = (x) => /^[A-Za-z0-9_-]{8,}$/.test(x);

  // /reels/<code>/ is the Reels feed parked on one reel: while locked it is
  // rewritten to the single-reel page instead of bouncing.
  function reelRedirect(path) {
    const s = segments(path);
    return s.length >= 2 && s[0].toLowerCase() === 'reels' && isShortcode(s[1]) ? '/reel/' + s[1] + '/' : null;
  }

  function anyReelCode(path) {
    const code = reelCode(path);
    if (code) return code;
    const s = segments(path);
    return s.length >= 2 && s[0].toLowerCase() === 'reels' && isShortcode(s[1]) ? s[1] : null;
  }

  // Returns the name of the trap a path leads into, or null when it's allowed.
  function blockedRoute(path) {
    const s = segments(path).map((x) => x.toLowerCase());
    if (s.length === 0) return 'The feed';
    if (s[0] === 'reels' || (s[0] === 'reel' && s.length === 1)) return 'Reels';
    if (s[0] === 'explore') return 'Explore';
    // Bare /<user>/reel/ (no code) is a doorway into Reels.
    if (s.length === 2 && s[1] === 'reel' && isProfileSegment(s[0])) return 'Reels';
    if (s.length >= 2 && /^[\w.]+$/.test(s[0]) && PROFILE_TABS.includes(s[1])) return 'That profile tab';
    const me = own();
    if (me && s[0] === me) return 'Your own profile';
    return null;
  }

  // ---- state -----------------------------------------------------------------
  const boot = window.__toyBoot || {};
  let state = { unlocked: !!boot.unlocked, ownUsername: clean(boot.ownUsername) };
  let detected = null;        // username found on this page (if native has none yet)
  let reported = null;        // last username posted to native

  const locked = () => !state.unlocked;
  const own = () => state.ownUsername || detected;
  const atInbox = () => /^\/direct\/inbox\/?$/.test(location.pathname);
  const onReel = () => !!anyReelCode(location.pathname);
  const reelLocked = () => locked() && onReel();

  function post(msg) {
    try { window.webkit.messageHandlers.toy.postMessage(msg); } catch (e) { /* not in the app */ }
  }

  function pathOf(href) {
    try {
      const u = new URL(href, location.href);
      if (u.origin !== location.origin) return null;
      return u.pathname;
    } catch (e) { return null; }
  }

  // {reason, bounce} or {redirect} when `href` is off limits right now, else null.
  function verdict(href) {
    if (!locked()) return null;
    const p = pathOf(href);
    if (p == null) return null;
    const from = anyReelCode(location.pathname);
    const to = anyReelCode(p);
    if (from && to && from !== to) return { reason: 'The next reel', bounce: false };
    // Same reel in another form (e.g. /reel/A/ -> /reels/A/): never loop.
    if (from && to && from === to) return null;
    const single = reelRedirect(p);
    if (single) return { redirect: single };
    const hit = blockedRoute(p);
    if (hit) return { reason: hit, bounce: true };
    return null;
  }

  // `force`: reload the inbox even when the URL already is the inbox. The
  // history hooks pass it, because a swallowed pushState('/') from the
  // inbox may already have the router rendering the feed under that URL.
  function bounce(reason, force) {
    post({ type: 'blocked', reason: reason, path: location.pathname, bounce: true });
    if (atInbox() && !force) return;
    location.replace(INBOX);
  }

  // Rewrites /reels/<code>/ to /reel/<code>/ once. If Instagram sends us
  // straight back (same code), stay put: the reel lock still applies there.
  function redirectToSingle(single) {
    let recent = null;
    try { recent = sessionStorage.getItem('toyReelRedirect'); } catch (e) { /* storage blocked */ }
    if (recent === single) return false;
    try { sessionStorage.setItem('toyReelRedirect', single); } catch (e) { /* storage blocked */ }
    location.replace(single);
    return true;
  }

  function refuse(v, force) {
    if (v.redirect) { location.assign(v.redirect); return; }
    if (v.bounce) { bounce(v.reason, force); return; }
    post({ type: 'blocked', reason: v.reason, path: location.pathname, bounce: false });
  }

  // ---- layer 1: never paint a blocked page -----------------------------------
  if (locked()) {
    const single = reelRedirect(location.pathname);
    if (single && redirectToSingle(single)) return;
    const hit = single ? null : blockedRoute(location.pathname);
    if (hit) { bounce(hit); return; }
  }

  // ---- layer 2: links --------------------------------------------------------
  addEventListener('click', (e) => {
    if (!locked()) return;
    const a = e.target && e.target.closest && e.target.closest('a[href]');
    if (!a) return;
    const v = verdict(a.href);
    if (v) {
      e.preventDefault();
      e.stopImmediatePropagation();
      refuse(v);
    }
  }, true);

  // ---- layer 3: client-side routing ------------------------------------------
  for (const name of ['pushState', 'replaceState']) {
    const original = history[name];
    history[name] = function (data, title, url) {
      if (locked() && url != null) {
        const v = verdict(String(url));
        if (v) { refuse(v, true); return undefined; }
      }
      const result = original.apply(this, arguments);
      onRoute();
      return result;
    };
  }

  // Catch-all for anything that changes the URL without the hooks above.
  let lastHref = location.href;
  let lastPath = location.pathname;
  function checkLocation() {
    if (location.href === lastHref) return;
    const previous = lastPath;
    if (locked()) {
      const from = anyReelCode(previous);
      const to = anyReelCode(location.pathname);
      if (from && to && from === to) {
        // Same reel in another form: nothing to block or redirect.
      } else if (!(from && to && from !== to)) {
        const single = reelRedirect(location.pathname);
        if (single && redirectToSingle(single)) return;
        const hit = single ? null : blockedRoute(location.pathname);
        if (hit) { bounce(hit); return; }
      } else {
        // Slipped onto another reel anyway: go back to the one that was open.
        post({ type: 'blocked', reason: 'The next reel', path: location.pathname, bounce: false });
        location.replace('/reel/' + from + '/');
        return;
      }
    }
    onRoute();
  }
  addEventListener('popstate', checkLocation, true);
  setInterval(checkLocation, 500);

  // ---- layer 4: CSS ----------------------------------------------------------
  const style = document.createElement('style');
  style.id = 'toy-cage';
  style.textContent = [
    ...HIDE.map((s) => `html.toy-locked ${s}{display:none!important}`),
    ...HIDE_INBOX.map((s) => `html.toy-locked.toy-inbox ${s}{display:none!important}`),
    // Layer 5's CSS half: a locked reel page doesn't scroll.
    'html.toy-locked.toy-reel,html.toy-locked.toy-reel body{overflow:hidden!important;overscroll-behavior:none!important}',
  ].join('\n');

  // Own profile links, rewritten whenever the username changes.
  const ownStyle = document.createElement('style');
  ownStyle.id = 'toy-own';

  // Always on: no scroll bars (scrolling still works).
  const chrome = document.createElement('style');
  chrome.id = 'toy-chrome';
  chrome.textContent = '*{scrollbar-width:none!important}*::-webkit-scrollbar{display:none!important;width:0!important;height:0!important}';

  function whenRoot(fn) {
    if (document.documentElement) return fn(document.documentElement);
    const mo = new MutationObserver(() => {
      if (document.documentElement) { mo.disconnect(); fn(document.documentElement); }
    });
    mo.observe(document, { childList: true });
  }

  function renderOwnStyle() {
    const me = own();
    ownStyle.textContent = me
      ? [`a[href="/${me}/"]`, `a[href^="/${me}/"]`, `a[href="https://www.instagram.com/${me}/"]`]
          .map((s) => `html.toy-locked ${s}{display:none!important}`).join('\n')
      : '';
  }

  // ---- layer 5: one reel at a time -------------------------------------------
  function isEditable(el) {
    return !!(el && el.closest && el.closest('textarea,input,select,[contenteditable=""],[contenteditable="true"]'));
  }

  // Comment sheets and other dialogs without a video still scroll.
  function exempt(el) {
    if (!el || !el.closest) return false;
    if (isEditable(el)) return true;
    const dialog = el.closest('[role="dialog"]');
    return !!(dialog && !dialog.querySelector('video'));
  }

  // DMs, the inbox and every other page scroll freely: the scroll blockers
  // below are only attached while a locked single reel is open, and are
  // removed the moment the route leaves it. (A non-passive touchmove on the
  // window would otherwise make the browser wait on JS for every DM scroll.)
  const inDirect = () => /^\/direct(\/|$)/.test(location.pathname);
  const reelScrollLocked = () => reelLocked() && !inDirect();

  let touchStart = null;
  function onTouchStart(e) {
    const t = e.touches && e.touches[0];
    touchStart = t ? { x: t.clientX, y: t.clientY } : null;
  }

  function onTouchMove(e) {
    if (!reelScrollLocked() || exempt(e.target)) return;
    const t = e.touches && e.touches[0];
    if (!t || !touchStart || (e.touches && e.touches.length > 1)) return;
    const dx = Math.abs(t.clientX - touchStart.x);
    const dy = Math.abs(t.clientY - touchStart.y);
    // Only clearly horizontal drags (scrubbing, carousel) get through.
    if (dx > dy) return;
    if (e.cancelable) e.preventDefault();
    e.stopPropagation();
  }

  function onWheel(e) {
    if (!reelScrollLocked() || exempt(e.target)) return;
    if (Math.abs(e.deltaY) >= Math.abs(e.deltaX) && e.cancelable) {
      e.preventDefault();
      e.stopPropagation();
    }
  }

  const SCROLL_KEYS = new Set(['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp', 'End', 'Home', ' ', 'Spacebar', 'j', 'k']);
  function onKeyDown(e) {
    if (!reelScrollLocked() || isEditable(e.target)) return;
    if (SCROLL_KEYS.has(e.key)) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }

  let scrollBlockersOn = false;
  function syncScrollBlockers() {
    const want = reelScrollLocked();
    if (want === scrollBlockersOn) return;
    scrollBlockersOn = want;
    const touchOpts = { capture: true, passive: true };
    const blockOpts = { capture: true, passive: false };
    if (want) {
      addEventListener('touchstart', onTouchStart, touchOpts);
      addEventListener('touchmove', onTouchMove, blockOpts);
      addEventListener('wheel', onWheel, blockOpts);
      addEventListener('keydown', onKeyDown, true);
    } else {
      removeEventListener('touchstart', onTouchStart, touchOpts);
      removeEventListener('touchmove', onTouchMove, blockOpts);
      removeEventListener('wheel', onWheel, blockOpts);
      removeEventListener('keydown', onKeyDown, true);
      touchStart = null;
    }
  }

  // Hide every reel container after the first one, pausing its video.
  function hideNextReels() {
    const marked = document.querySelectorAll('[data-toy-next-reel]');
    if (!onReel()) {
      for (const el of marked) el.removeAttribute('data-toy-next-reel');
      return;
    }
    if (!locked()) return;
    const videos = Array.from(document.querySelectorAll('video'));
    if (videos.length < 2) return;
    const first = videos[0];
    for (const v of videos.slice(1)) {
      if (first.contains(v)) continue;
      // Climb to the child of the nearest ancestor shared with the first reel.
      let el = v;
      while (el.parentElement && !el.parentElement.contains(first)) el = el.parentElement;
      if (el === document.documentElement || el === document.body || el.contains(first)) continue;
      if (!el.hasAttribute('data-toy-next-reel')) el.setAttribute('data-toy-next-reel', '');
      try { if (!v.paused) v.pause(); v.muted = true; } catch (err) { /* detached */ }
    }
  }

  // ---- own username detection (best effort) ----------------------------------
  function singleSegmentName(href) {
    const p = pathOf(href);
    if (!p) return null;
    const s = segments(p);
    return s.length === 1 ? clean(s[0]) : null;
  }

  // The tab bar / sidebar: a small container that links Home or Explore or
  // Reels AND the inbox; its one profile-shaped link is you. (A DM thread
  // header links a friend, but never Home/Explore/Reels, so it can't match.)
  function detectFromNav() {
    const anchors = document.querySelectorAll('a[href="/"], a[href^="/explore"], a[href^="/reels"]');
    for (const anchor of anchors) {
      let c = anchor.parentElement;
      for (let depth = 0; c && depth < 8; depth++, c = c.parentElement) {
        const links = c.querySelectorAll('a[href]');
        if (links.length > 14) break;
        if (!c.querySelector('a[href^="/direct/"]')) continue;
        for (const a of links) {
          const name = singleSegmentName(a.getAttribute('href'));
          if (name) return name;
        }
      }
    }
    return null;
  }

  function cookie(name) {
    const m = document.cookie.match(new RegExp('(?:^|;\\s*)' + name + '=([^;]+)'));
    return m ? decodeURIComponent(m[1]) : null;
  }

  // Inline JSON Instagram ships with the page ("viewer" blocks, or the
  // username next to the signed-in user's id).
  function detectFromInlineData() {
    const id = cookie('ds_user_id');
    const patterns = [
      /"viewer"\s*:\s*\{\s*"user"\s*:\s*\{[^{}]{0,600}?"username"\s*:\s*"([\w.]+)"/,
      /"viewer"\s*:\s*\{[^{}]{0,300}?"username"\s*:\s*"([\w.]+)"/,
    ];
    if (id && /^\d+$/.test(id)) {
      patterns.push(new RegExp('"(?:pk|id|pk_id)"\\s*:\\s*"?' + id + '"?\\s*,[^{}]{0,300}?"username"\\s*:\\s*"([\\w.]+)"'));
      patterns.push(new RegExp('"username"\\s*:\\s*"([\\w.]+)"[^{}]{0,300}?"(?:pk|id|pk_id)"\\s*:\\s*"?' + id + '"?[,}]'));
    }
    const scripts = document.querySelectorAll('script[type="application/json"], script:not([src])');
    for (const s of scripts) {
      const text = s.textContent || '';
      if (text.length < 20 || text.indexOf('username') < 0) continue;
      for (const re of patterns) {
        const m = text.match(re);
        const name = m && clean(m[1]);
        if (name) return name;
      }
    }
    return null;
  }

  async function igGet(url) {
    const res = await fetch(url, {
      credentials: 'include',
      headers: { 'X-IG-App-ID': APP_ID, 'X-Requested-With': 'XMLHttpRequest' },
    });
    if (!res.ok) throw new Error(String(res.status));
    return res.json();
  }

  // Signed-in user id -> username via Instagram's web API, cached per account.
  let apiTried = false;
  async function detectFromApi() {
    const id = cookie('ds_user_id');
    if (!id) return null;
    try {
      const cached = JSON.parse(localStorage.getItem('toyOwn') || 'null');
      if (cached && cached.id === id && clean(cached.name)) return clean(cached.name);
    } catch (e) { /* storage blocked */ }
    if (apiTried) return null;
    apiTried = true;
    let name = null;
    try {
      const j = await igGet('/api/v1/users/' + encodeURIComponent(id) + '/info/');
      name = clean(j && j.user && j.user.username);
    } catch (e) { /* endpoint changed */ }
    if (!name) {
      try {
        const j = await igGet('/api/v1/accounts/edit/web_form_data/');
        name = clean(j && j.form_data && j.form_data.username);
      } catch (e) { /* endpoint changed */ }
    }
    if (name) {
      try { localStorage.setItem('toyOwn', JSON.stringify({ id: id, name: name })); } catch (e) { /* storage blocked */ }
    }
    return name;
  }

  function found(name, source) {
    if (!name) return;
    const changed = name !== detected;
    detected = name;
    if (name !== reported) {
      reported = name;
      post({ type: 'ownUsername', username: name, source: source });
    }
    if (changed) {
      renderOwnStyle();
      // Became knowable while sitting on your own profile: leave.
      if (locked() && blockedRoute(location.pathname)) bounce(blockedRoute(location.pathname));
    }
  }

  let apiRunning = false;
  async function detectOwnUsername() {
    if (apiRunning) return;
    if (!cookie('ds_user_id') && !document.querySelector('a[href^="/direct/"]')) return; // signed out
    apiRunning = true;
    try {
      const fromApi = await detectFromApi();
      if (fromApi) { found(fromApi, 'api'); return; }
      if (detected) return;
      const fromData = detectFromInlineData();
      if (fromData) { found(fromData, 'inline'); return; }
      const fromNav = detectFromNav();
      if (fromNav) found(fromNav, 'nav');
    } finally {
      apiRunning = false;
    }
  }

  // ---- state from native -------------------------------------------------------
  function applyState() {
    const root = document.documentElement;
    if (root) {
      root.classList.toggle('toy-locked', locked());
      root.classList.toggle('toy-inbox', atInbox());
      root.classList.toggle('toy-reel', onReel() && !inDirect());
    }
    renderOwnStyle();
    hideNextReels();
    syncScrollBlockers();
  }

  window.__toySetState = function (s) {
    const wasLocked = locked();
    const next = s || {};
    state = { unlocked: !!next.unlocked, ownUsername: clean(next.ownUsername) };
    applyState();
    if (locked() && !wasLocked) {
      const hit = blockedRoute(location.pathname);
      if (hit) bounce(hit);
    }
    return true;
  };

  function onRoute() {
    lastHref = location.href;
    lastPath = location.pathname;
    if (!onReel()) {
      try { sessionStorage.removeItem('toyReelRedirect'); } catch (e) { /* storage blocked */ }
    }
    applyState();
    post({ type: 'route', path: location.pathname, reel: onReel() });
  }

  // ---- DOM sweeps ----------------------------------------------------------------
  let sweepQueued = false;
  function sweep() {
    sweepQueued = false;
    hideNextReels();
    if (!detected && !state.ownUsername) {
      const fromNav = detectFromNav();
      if (fromNav) found(fromNav, 'nav');
    }
  }
  function queueSweep() {
    if (sweepQueued) return;
    sweepQueued = true;
    setTimeout(sweep, 250);
  }

  whenRoot((root) => {
    root.appendChild(style);
    root.appendChild(ownStyle);
    root.appendChild(chrome);
    applyState();
    new MutationObserver(queueSweep).observe(root, { childList: true, subtree: true });
  });

  addEventListener('DOMContentLoaded', () => {
    onRoute();
    post({ type: 'ready', path: location.pathname });
    setTimeout(detectOwnUsername, 1500);
  });

  // ---- unread badge ----------------------------------------------------------------
  async function pollUnread() {
    if (!cookie('ds_user_id')) return;
    try {
      const j = await igGet('/api/v1/direct_v2/get_badge_count/?no_raven=1');
      if (j && typeof j.badge_count === 'number') post({ type: 'unread', count: j.badge_count });
    } catch (e) { /* not signed in or endpoint changed */ }
  }
  setTimeout(pollUnread, 4000);
  setInterval(pollUnread, 60000);
  setInterval(() => { if (!detected && !state.ownUsername) detectOwnUsername(); }, 15000);
})();
