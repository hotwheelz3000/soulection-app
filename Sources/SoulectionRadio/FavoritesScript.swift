import Foundation

/// Favorites, listening history and a random-show button: hearts on songs, a sheet with
/// Favorites and History tabs, playlists from either, and a dice in the top bar.
///
/// - History: a song is recorded after it has played for 2 seconds (like Spotify's
///   Recently played), saved in the app, newest first, with replays moved to the top.
/// - Dice: picks a random episode from the site's sitemap and home page and plays it
///   from the start.
///
/// - Hearts: a small heart after each song in an episode's tracklist, and one in the
///   site's mini player for the current song. Tapping saves or removes the song.
/// - Storage: the list lives in the app (FavoritesBridge, UserDefaults), not in the
///   website's storage. The page asks for it on load and gets it back after changes.
/// - Sheet: swipe up on the mini player (it gets a grab handle), or tap the heart
///   button in the top bar, next to search. Lists favorites newest first, with swipe left
///   to remove, "Play in order" and "Shuffle", and Export/Import to back them up
///   (every 4 new favorites a reminder suggests exporting). Swipe down or tap outside to close.
///   Styled with the site's own values (read from radio.soulection.com): background
///   rgb(26,26,26), border rgb(42,42,42), 9px corners like the mini player card, Bai
///   Jamjuree, rgb(138,138,138) text with semibold song names, rgb(90,90,90) for the
///   show line, and white as the accent (filled hearts, button icons).
/// - Playlist: playing a favorite opens its episode and taps its tracklist row (the
///   site's own way to start an episode at a song). When playback reaches the
///   favorite's end (the next song's timestamp) it moves to the next favorite,
///   seeking within the episode or switching episodes. The lock screen shows the
///   favorite and its next/previous buttons move through the playlist. Tapping a song
///   in an episode yourself, or another show starting, ends playlist mode.
enum FavoritesScript {
    static let source = #"""
        (function () {
          if (window.__soulectionFavorites) return;
          var SOULECTION_ORIGIN = /^https:\/\/([a-z0-9-]+\.)*soulection\.com$/i;
          if (window !== window.top || !SOULECTION_ORIGIN.test(location.origin)) return;

          // Site styles, read from radio.soulection.com (computed values on an iPhone-sized page).
          var FONT = '"Bai Jamjuree", sans-serif';
          var BG = 'rgb(26, 26, 26)';         // body, header, mini player card
          var BORDER = 'rgb(42, 42, 42)';     // card and header borders
          var TEXT = 'rgb(138, 138, 138)';    // body text, song and artist
          var MUTED = 'rgb(90, 90, 90)';      // mini player show line, column headings
          var TRACK = 'rgb(58, 58, 58)';      // progress track
          var ACCENT = 'rgb(255, 255, 255)';  // filled hearts and icons
          var HOVER = 'rgba(51, 65, 85, 0.7)'; // tracklist row hover
          var SHADOW = 'rgba(0, 0, 0, 0.1) 0px 10px 15px -3px, rgba(0, 0, 0, 0.1) 0px 4px 6px -4px';

          var HEART = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>';
          var PLAY = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 5v14l12-7z"/></svg>';
          var SHUFFLE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m18 14 4 4-4 4"/><path d="m18 2 4 4-4 4"/><path d="M2 18h1.97a4 4 0 0 0 3.3-1.7l5.46-8.6a4 4 0 0 1 3.3-1.7H22"/><path d="M2 6h1.97a4 4 0 0 1 3.3 1.7l.53.83"/><path d="M22 18h-6.04a4 4 0 0 1-3.3-1.8l-.36-.55"/></svg>';

          var EXPORT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 8 5-5 5 5"/><path d="M5 15v4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/></svg>';
          var IMPORT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 15v4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4"/></svg>';

          var DICE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.2" fill="currentColor"/><circle cx="16" cy="8" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="8" cy="16" r="1.2" fill="currentColor"/><circle cx="16" cy="16" r="1.2" fill="currentColor"/></svg>';

          var CSS = [
            '.sr-heart{-webkit-appearance:none;appearance:none;background:none;border:0;margin:0;padding:0;display:inline-flex;align-items:center;justify-content:center;color:' + TEXT + ';cursor:pointer;pointer-events:auto;line-height:1;vertical-align:middle;-webkit-tap-highlight-color:transparent;font:inherit}',
            '.sr-heart svg{width:1em;height:1em;display:block}',
            '.sr-heart[aria-pressed="true"]{color:' + ACCENT + '}',
            '.sr-heart[aria-pressed="true"] svg{fill:currentColor}',
            '.sr-heart-row{font-size:22px;padding:6px;margin:-8px -6px -6px auto;flex:none}',
            // Hearts line up at the right of the song column, level with the first line of
            // the song name (instead of wrapping under long names).
            '.sr-song-cell{display:flex;align-items:flex-start;gap:6px}',
            '.sr-heart-mini{font-size:23px;padding:9px;border-radius:9999px;flex:none;margin-left:auto;order:1}',
            '.sr-heart-mini[hidden]{display:none}',
            '.sr-heart-top{font-size:23px;padding:8px;margin:0 -4px 0 4px;flex:none;align-self:center}',
            '.sr-dice-top{font-size:23px;padding:8px;margin:0 -4px 0 0;flex:none;align-self:center}',
            '.sr-dice-top[aria-busy="true"] svg{animation:sr-spin .8s linear infinite}',
            '@keyframes sr-spin{to{transform:rotate(360deg)}}',
            // Favorites | History switch at the top of the sheet.
            '.sr-tabs{display:flex;gap:18px;align-items:baseline}',
            '.sr-tabbtn{-webkit-appearance:none;appearance:none;background:none;border:0;padding:0;margin:0;font-family:' + FONT + ';font-size:18px;line-height:24px;font-weight:600;color:' + MUTED + ';cursor:pointer;-webkit-tap-highlight-color:transparent}',
            '.sr-tabbtn[aria-pressed="true"]{color:' + TEXT + '}',
            '.sr-clear[hidden]{display:none}',
            '.sr-grab{position:absolute;top:0;left:50%;width:64px;height:14px;margin-left:-32px;padding:0;border:0;background:none;-webkit-appearance:none;appearance:none;cursor:pointer;-webkit-tap-highlight-color:transparent}',
            '.sr-grab::after,.sr-tab-bar,.sr-sheet-grab{content:"";display:block;width:36px;height:4px;border-radius:9999px;background:' + TRACK + '}',
            '.sr-grab::after{margin:5px auto 0}',
            '.sr-tab{position:fixed;left:50%;bottom:env(safe-area-inset-bottom);z-index:20;transform:translateX(-50%);display:flex;flex-direction:column;align-items:center;gap:2px;padding:4px 14px 3px;background:' + BG + ';border:1px solid ' + BORDER + ';border-radius:9px;box-shadow:' + SHADOW + ';font-family:' + FONT + ';font-size:9px;line-height:12px;color:' + MUTED + ';cursor:pointer;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none}',
            '.sr-tab[hidden]{display:none}',
            '.sr-backdrop{position:fixed;inset:0;z-index:50;background:rgba(0,0,0,0.5);opacity:0;transition:opacity .25s ease;-webkit-tap-highlight-color:transparent}',
            '.sr-sheet{position:fixed;left:0;right:0;bottom:0;z-index:51;display:flex;flex-direction:column;min-height:55vh;max-height:85vh;background:' + BG + ';border:1px solid ' + BORDER + ';border-bottom:0;border-radius:9px 9px 0 0;box-shadow:' + SHADOW + ';font-family:' + FONT + ';font-size:12px;line-height:18px;font-weight:400;color:' + TEXT + ';transform:translateY(100%);transition:transform .28s cubic-bezier(.2,.8,.2,1);padding-bottom:env(safe-area-inset-bottom)}',
            '.sr-backdrop[hidden],.sr-sheet[hidden]{display:none}',
            '.sr-open .sr-backdrop{opacity:1}',
            '.sr-open .sr-sheet{transform:none}',
            '.sr-sheet-head{padding:5px 12px 12px;flex:none;-webkit-user-select:none;user-select:none}',
            '.sr-sheet-grab{margin:0 auto 12px}',
            '.sr-sheet-title{font-size:18px;line-height:24px;font-weight:600;color:' + TEXT + ';margin:0}',
            '.sr-sheet-sub{font-size:12px;line-height:16px;color:' + MUTED + ';margin-top:3px}',
            '.sr-actions{display:flex;gap:10px;margin-top:14px}',
            '.sr-btn{-webkit-appearance:none;appearance:none;display:inline-flex;align-items:center;gap:8px;padding:10px 16px;margin:0;background:' + BG + ';border:1px solid ' + BORDER + ';border-radius:8px;color:' + TEXT + ';font-family:' + FONT + ';font-size:15px;line-height:20px;font-weight:400;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:background-color .15s}',
            '.sr-btn svg{width:18px;height:18px;display:block;color:' + ACCENT + '}',
            '.sr-btn:active{background:' + HOVER + '}',
            '.sr-btn[disabled]{opacity:.5;cursor:default}',
            '.sr-list{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain;border-top:1px solid ' + BORDER + ';padding:0 12px}',
            '.sr-item{position:relative;overflow:hidden;border-bottom:1px solid ' + BORDER + '}',
            '.sr-item-remove{position:absolute;inset:0;display:flex;align-items:center;justify-content:flex-end;padding-right:6px;color:' + ACCENT + '}',
            '.sr-item-main{position:relative;display:flex;align-items:center;gap:12px;padding:9px 0;background:' + BG + ';cursor:pointer;-webkit-tap-highlight-color:transparent}',
            '.sr-item-main img{width:48px;height:48px;border-radius:1.5px;object-fit:cover;flex:none;background:' + TRACK + '}',
            '.sr-item-text{display:flex;flex-direction:column;gap:3px;min-width:0;flex:1}',
            '.sr-item-show{font-size:9px;line-height:12px;color:' + MUTED + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-item-line{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-item-song{font-weight:600}',
            '.sr-item-playing .sr-item-show::before{content:"";display:inline-block;width:6px;height:6px;border-radius:9999px;background:' + ACCENT + ';margin-right:5px;vertical-align:1px}',
            '.sr-item .sr-heart{font-size:23px;padding:10px;margin-right:-10px}',
            '.sr-empty{padding:24px 12px;text-align:center;color:' + MUTED + '}',
            'html.sr-lock,html.sr-lock body{overflow:hidden}',
            // Backup: Export/Import row in the sheet, a reminder card and short messages.
            '.sr-backup{display:flex;align-items:center;gap:10px;margin-top:10px;font-size:12px;line-height:16px;color:' + MUTED + '}',
            '.sr-backup .sr-btn{padding:7px 12px;font-size:13px;line-height:18px;gap:6px}',
            '.sr-backup .sr-btn svg{width:15px;height:15px}',
            '.sr-note{position:fixed;left:12px;right:12px;top:calc(env(safe-area-inset-top) + 72px);z-index:60;padding:10px 12px;background:' + BG + ';border:1px solid ' + BORDER + ';border-radius:9px;box-shadow:' + SHADOW + ';font-family:' + FONT + ';font-size:12px;line-height:18px;color:' + TEXT + ';opacity:0;transform:translateY(-8px);transition:opacity .2s ease,transform .2s ease;pointer-events:none}',
            '.sr-note.sr-show{opacity:1;transform:none;pointer-events:auto}',
            '.sr-note .sr-actions{margin-top:8px}',
            '.sr-note-title{font-weight:600}'
          ].join('\n');

          var favorites = [];
          var history = [];   // songs listened to, oldest first (favoritedAt = when played)
          var resumeAfterLoad = null; // playlist to continue once the app has sent the favorites
          var sheet = null; // {root, backdrop, panel, list, sub, playBtn, shuffleBtn}
          var tab = null;
          var dice = null;
          var renderPending = false;

          function np() { return window.__soulectionNowPlaying || null; }
          function npState() { var n = np(); return n ? n.state() : null; }
          function native(msg) {
            try { window.webkit.messageHandlers.soulectionFavorites.postMessage(msg); } catch (e) {}
          }
          function text(el) { return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
          function parseTimestamp(s) {
            var m = /^(\d+):(\d{1,2})(?::(\d{1,2}))?$/.exec(s);
            if (!m) return null;
            return m[3] == null ? +m[1] * 60 + +m[2] : +m[1] * 3600 + +m[2] * 60 + +m[3];
          }
          function showNumber(s) { var m = /#\s*(\d+)/.exec(s || ''); return m ? m[1] : null; }
          function favId(url, start) { return url + '#' + Math.round(start); }
          function byId(id) {
            for (var i = 0; i < favorites.length; i++) if (favorites[i].id === id) return favorites[i];
            return null;
          }
          function historyById(id) {
            for (var i = 0; i < history.length; i++) if (history[i].id === id) return history[i];
            return null;
          }
          function sourceList(source) { return source === 'history' ? history : favorites; }
          function lookup(source, id) { return source === 'history' ? historyById(id) : byId(id); }
          function ago(ms) {
            var s = Math.max(0, (Date.now() - ms) / 1000);
            if (s < 60) return 'Just now';
            if (s < 3600) return Math.floor(s / 60) + 'm ago';
            if (s < 86400) return Math.floor(s / 3600) + 'h ago';
            if (s < 172800) return 'Yesterday';
            if (s < 604800) return Math.floor(s / 86400) + 'd ago';
            return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
          }
          function el(tag, cls, html) {
            var e = document.createElement(tag);
            if (cls) e.className = cls;
            if (html != null) e.innerHTML = html;
            return e;
          }
          function esc(s) {
            return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
              return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
            });
          }

          // Saves or removes a song. The app keeps the list; this updates the hearts right
          // away and the app's reply replaces the list.
          function toggle(fav) {
            var existing = byId(fav.id);
            if (existing) favorites = favorites.filter(function (f) { return f.id !== fav.id; });
            else favorites = favorites.concat([fav]);
            native({ op: 'toggle', favorite: fav });
            schedule();
          }
          function remove(id) {
            favorites = favorites.filter(function (f) { return f.id !== id; });
            native({ op: 'remove', id: id });
            schedule();
          }
          function removeHistory(id) {
            history = history.filter(function (f) { return f.id !== id; });
            native({ op: 'historyRemove', id: id });
            schedule();
          }

          // ---------------------------------------------------------------------------
          // Listening history: a song counts once it has played for 2 seconds.
          // ---------------------------------------------------------------------------
          var listen = null; // {track, played: seconds heard so far, last: ms, done}
          function followListening(st) {
            var t = currentTrack();
            if (!t || !st) { listen = null; return; }
            var now = Date.now();
            if (!listen || listen.track.id !== t.id) listen = { track: t, played: 0, last: now, lastT: st.t, done: false };
            // Count time only while it's actually playing (the position must be moving too,
            // in case the player hasn't reported paused/playing).
            var moving = st.t != null && listen.lastT != null && st.t > listen.lastT;
            if (st.paused === false || (st.paused == null && moving)) listen.played += Math.min(2, (now - listen.last) / 1000);
            listen.last = now;
            listen.lastT = st.t;
            if (listen.done || listen.played < 2) return;
            listen.done = true;
            var entry = {};
            for (var k in t) entry[k] = t[k];
            entry.favoritedAt = now;
            history = history.filter(function (h) { return h.id !== entry.id; }).concat([entry]);
            native({ op: 'played', favorite: entry });
            schedule();
          }

          window.__soulectionFavorites = {
            toast: function (message) { showToast(message); },
            receive: function (list, opts) {
              favorites = Array.isArray(list) ? list : [];
              if (opts && Array.isArray(opts.history)) history = opts.history;
              // Back from "Export first": show the final warning again.
              if (clearAfterExport) { clearAfterExport = false; setTimeout(clearStepTwo, 400); }
              if (opts && opts.backupDue) maybeRemindBackup();
              if (resumeAfterLoad) {
                playlist = resumeAfterLoad;
                resumeAfterLoad = null;
                playCurrent();
              }
              schedule();
            }
          };

          // ---------------------------------------------------------------------------
          // Backup reminder and short messages
          // ---------------------------------------------------------------------------
          var note = null, noteTimer = null, reminded = false;
          function showNote(html, ms) {
            if (!document.body) return null;
            if (note) note.remove();
            clearTimeout(noteTimer);
            note = el('div', 'sr-note', html);
            note.setAttribute('role', 'status');
            document.body.appendChild(note);
            void note.offsetHeight;
            note.classList.add('sr-show');
            if (ms) noteTimer = setTimeout(hideNote, ms);
            return note;
          }
          function hideNote() {
            clearTimeout(noteTimer);
            if (!note) return;
            var n = note;
            note = null;
            n.classList.remove('sr-show');
            setTimeout(function () { n.remove(); }, 250);
          }
          function showToast(message) { showNote('<div>' + esc(message) + '</div>', 2600); }
          // Every few new favorites, suggest exporting a backup (once per page load).
          function maybeRemindBackup() {
            if (reminded) return;
            reminded = true;
            var n = showNote(
              '<div class="sr-note-title">Back up your favorites?</div>' +
              '<div>Save a copy so you keep them if the app is ever deleted.</div>' +
              '<div class="sr-actions"></div>', 0);
            if (!n) { reminded = false; return; }
            var actions = n.querySelector('.sr-actions');
            var exportBtn = el('button', 'sr-btn', EXPORT + '<span>Export</span>');
            var laterBtn = el('button', 'sr-btn', '<span>Later</span>');
            exportBtn.type = laterBtn.type = 'button';
            exportBtn.addEventListener('click', function () { hideNote(); native({ op: 'export' }); });
            laterBtn.addEventListener('click', function () { hideNote(); native({ op: 'backupLater' }); });
            actions.appendChild(exportBtn);
            actions.appendChild(laterBtn);
          }

          // ---------------------------------------------------------------------------
          // Page structure (radio.soulection.com, as probed)
          // ---------------------------------------------------------------------------
          function miniPlayer() {
            var slider = document.querySelector('[role="slider"][aria-valuenow]');
            if (!slider) return null;
            for (var e = slider; e && e !== document.body; e = e.parentElement) {
              if (e.querySelector('img') && /\bfixed\b/.test(e.className || '')) return e;
            }
            return null;
          }

          function episodePath() {
            return /^\/episodes\/[^/]+\/?$/.test(location.pathname) ? location.pathname.replace(/\/$/, '') : null;
          }

          function pageRows() {
            var rows = document.querySelectorAll('.col-span-full.grid');
            var out = [];
            for (var i = 0; i < rows.length; i++) {
              var spans = rows[i].querySelectorAll(':scope > span');
              if (spans.length < 3) continue;
              var start = parseTimestamp(text(spans[0]));
              if (start == null) continue;
              var artist = text(rows[i].querySelector('a[href*="/artists/"]')) || text(spans[1]);
              var song = text(rows[i].querySelector('a[href*="/songs/"]')) || text(spans[2]);
              // Voice-over rows ("VO - Joe Kay") are the host talking, not a song: they
              // stay in the list (for next-song timing) but get no heart.
              var vo = !song || isVoiceOver(artist);
              if (!song) { song = artist; artist = ''; }
              out.push({ row: rows[i], songCell: spans[2], start: start, artist: artist, song: song, vo: vo });
            }
            out.sort(function (a, b) { return a.start - b.start; });
            return out;
          }

          function isVoiceOver(artist) { return /^\s*VO\b/i.test(artist || ''); }

          function pageEpisodeInfo() {
            var h1 = document.querySelector('#episode-card-header h1, main h1');
            var number = showNumber(text(h1));
            var img = document.querySelector('#episode-card-header img');
            var st = npState();
            var show = st && st.number && st.number === number && st.show ? st.show : (number ? 'Show #' + number : text(h1));
            return { show: show, cover: img ? img.src : '' };
          }

          // ---------------------------------------------------------------------------
          // Hearts
          // ---------------------------------------------------------------------------
          function heartButton(cls) {
            var b = el('button', 'sr-heart ' + cls, HEART);
            b.type = 'button';
            return b;
          }
          function setHeart(b, on, label) {
            var v = on ? 'true' : 'false';
            if (b.getAttribute('aria-pressed') !== v) b.setAttribute('aria-pressed', v);
            var l = (on ? 'Remove ' : 'Add ') + label + (on ? ' from favorites' : ' to favorites');
            if (b.getAttribute('aria-label') !== l) b.setAttribute('aria-label', l);
          }

          function renderRowHearts() {
            var path = episodePath();
            if (!path) return;
            var rows = pageRows();
            if (!rows.length) return;
            var info = null;
            rows.forEach(function (r, i) {
              var b = r.songCell.querySelector(':scope > .sr-heart');
              if (r.vo) { if (b) b.remove(); return; }
              if (!b) {
                b = heartButton('sr-heart-row');
                b.addEventListener('click', function (e) {
                  e.preventDefault();
                  e.stopPropagation();
                  var current = pageRows();
                  var me = null, next = null;
                  for (var j = 0; j < current.length; j++) {
                    if (current[j].songCell === b.parentElement) { me = current[j]; next = current[j + 1] || null; }
                  }
                  if (!me) return;
                  var meta = pageEpisodeInfo();
                  toggle({
                    id: favId(path, me.start), song: me.song, artist: me.artist, show: meta.show,
                    episodeURL: path, cover: meta.cover, start: me.start, end: next ? next.start : null,
                    favoritedAt: Date.now()
                  });
                });
              }
              if (!r.songCell.classList.contains('sr-song-cell')) r.songCell.classList.add('sr-song-cell');
              if (b !== r.songCell.lastElementChild) r.songCell.appendChild(b); // keep it after the song
              setHeart(b, !!byId(favId(path, r.start)), r.song);
            });
          }

          function currentTrack() {
            var st = npState();
            if (!st || !st.episodeURL || st.index == null || st.index < 0 || !st.tracks || !st.tracks[st.index]) return null;
            var t = st.tracks[st.index];
            if (!t.title || isVoiceOver(t.artist)) return null; // no heart for voice-overs
            var next = st.tracks[st.index + 1];
            return {
              id: favId(st.episodeURL, t.start), song: t.title || t.artist, artist: t.title ? t.artist : '', show: st.show || ('Show #' + st.number),
              episodeURL: st.episodeURL, cover: st.cover, start: t.start, end: next ? next.start : null
            };
          }

          function renderMiniPlayer(player) {
            if (!player) return;
            if (!player.querySelector(':scope > .sr-grab')) {
              var g = el('button', 'sr-grab');
              g.type = 'button';
              g.setAttribute('aria-label', 'Show favorites');
              g.addEventListener('click', function (e) { e.stopPropagation(); openSheet(); });
              player.appendChild(g);
            }
            var row = player.querySelector('.content-col');
            row = row && row.parentElement && row.parentElement.parentElement; // the top row (artwork, text, play button)
            if (!row) return;
            var b = row.querySelector(':scope > .sr-heart-mini');
            if (!b) {
              b = heartButton('sr-heart-mini');
              b.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                var t = currentTrack();
                if (t) { t.favoritedAt = Date.now(); toggle(t); }
              });
              row.appendChild(b);
              var playBtn = row.querySelector(':scope > button:not(.sr-heart)');
              if (playBtn) playBtn.style.order = '2';
            }
            var t = currentTrack();
            if (!t) { if (!b.hidden) b.hidden = true; return; }
            if (b.hidden) b.hidden = false;
            setHeart(b, !!byId(t.id), t.song);
          }

          // ---------------------------------------------------------------------------
          // Favorites sheet
          // ---------------------------------------------------------------------------
          function buildSheet() {
            if (sheet || !document.body) return;
            var root = el('div', 'sr-fav-root');
            var backdrop = el('div', 'sr-backdrop');
            var panel = el('div', 'sr-sheet');
            panel.setAttribute('role', 'dialog');
            panel.setAttribute('aria-label', 'Favorites');
            backdrop.hidden = panel.hidden = true;
            var head = el('div', 'sr-sheet-head');
            head.appendChild(el('div', 'sr-sheet-grab'));
            var tabs = el('div', 'sr-tabs');
            var favTab = el('button', 'sr-tabbtn', 'Favorites');
            var histTab = el('button', 'sr-tabbtn', 'History');
            favTab.type = histTab.type = 'button';
            favTab.addEventListener('click', function () { setMode('favorites'); });
            histTab.addEventListener('click', function () { setMode('history'); });
            tabs.appendChild(favTab);
            tabs.appendChild(histTab);
            head.appendChild(tabs);
            var sub = el('div', 'sr-sheet-sub');
            head.appendChild(sub);
            var actions = el('div', 'sr-actions');
            var playBtn = el('button', 'sr-btn', PLAY + '<span>Play in order</span>');
            var shuffleBtn = el('button', 'sr-btn', SHUFFLE + '<span>Shuffle</span>');
            playBtn.type = shuffleBtn.type = 'button';
            playBtn.addEventListener('click', function () { startPlaylist('order', null, sheet.mode); });
            shuffleBtn.addEventListener('click', function () { startPlaylist('shuffle', null, sheet.mode); });
            var clearBtn = el('button', 'sr-btn sr-clear', '<span>Clear</span>');
            clearBtn.type = 'button';
            clearBtn.addEventListener('click', confirmClearHistory);
            actions.appendChild(playBtn);
            actions.appendChild(shuffleBtn);
            actions.appendChild(clearBtn);
            head.appendChild(actions);
            var backup = el('div', 'sr-backup', '<span>Back up</span>');
            var exportBtn = el('button', 'sr-btn', EXPORT + '<span>Export</span>');
            var importBtn = el('button', 'sr-btn', IMPORT + '<span>Import</span>');
            exportBtn.type = importBtn.type = 'button';
            exportBtn.addEventListener('click', function () { native({ op: 'export' }); });
            importBtn.addEventListener('click', function () { native({ op: 'import' }); });
            backup.appendChild(exportBtn);
            backup.appendChild(importBtn);
            head.appendChild(backup);
            var list = el('div', 'sr-list');
            panel.appendChild(head);
            panel.appendChild(list);
            root.appendChild(backdrop);
            root.appendChild(panel);
            document.body.appendChild(root);
            backdrop.addEventListener('click', closeSheet);
            sheet = { root: root, backdrop: backdrop, panel: panel, head: head, list: list, sub: sub, playBtn: playBtn, shuffleBtn: shuffleBtn, clearBtn: clearBtn, favTab: favTab, histTab: histTab, mode: 'favorites', key: '' };
            attachSheetDrag();
          }

          function isOpen() { return !!(sheet && sheet.root.classList.contains('sr-open')); }

          function openSheet() {
            buildSheet();
            if (!sheet || isOpen()) return;
            renderSheet();
            sheet.backdrop.hidden = sheet.panel.hidden = false;
            sheet.panel.style.transform = '';
            sheet.list.scrollTop = 0;
            document.documentElement.classList.add('sr-lock');
            void sheet.panel.offsetHeight; // start the slide-up from the closed position
            sheet.root.classList.add('sr-open');
            renderTab();
          }

          function closeSheet() {
            if (!isOpen()) return;
            sheet.root.classList.remove('sr-open');
            sheet.panel.style.transform = '';
            document.documentElement.classList.remove('sr-lock');
            setTimeout(function () {
              if (isOpen()) return;
              sheet.backdrop.hidden = sheet.panel.hidden = true;
              renderTab();
            }, 300);
          }

          function setMode(mode) {
            if (!sheet || sheet.mode === mode) return;
            sheet.mode = mode;
            sheet.key = '';
            sheet.list.scrollTop = 0;
            renderSheet();
          }

          // Clearing history takes two warnings: a first "are you sure", then a final one
          // that also offers to export a backup first.
          var clearAfterExport = false;
          function confirmClearHistory() {
            if (!history.length) return;
            var n = history.length;
            noteWithButtons(
              '<div class="sr-note-title">Clear listening history?</div>' +
              '<div>This removes all ' + n + (n === 1 ? ' song' : ' songs') + ' from History. Your favorites stay.</div>',
              [['Continue', clearStepTwo], ['Cancel', null]]);
          }
          function clearStepTwo() {
            if (!history.length) return;
            noteWithButtons(
              '<div class="sr-note-title">Are you sure?</div>' +
              '<div>This can\'t be undone.</div>',
              [['Clear history', clearHistoryNow], ['Export first', function () {
                clearAfterExport = true;
                native({ op: 'export' });
              }], ['Cancel', null]]);
          }
          function clearHistoryNow() {
            history = [];
            native({ op: 'historyClear' });
            if (sheet) { sheet.key = ''; renderSheet(); }
            showToast('Listening history cleared.');
          }
          function noteWithButtons(html, buttons) {
            var n = showNote(html + '<div class="sr-actions"></div>', 0);
            if (!n) return;
            var row = n.querySelector('.sr-actions');
            buttons.forEach(function (b) {
              var btn = el('button', 'sr-btn', '<span>' + esc(b[0]) + '</span>');
              btn.type = 'button';
              btn.addEventListener('click', function (e) {
                e.stopPropagation();
                hideNote();
                if (b[1]) b[1]();
              });
              row.appendChild(btn);
            });
          }

          function renderSheet() {
            if (!sheet) return;
            var hist = sheet.mode === 'history';
            sheet.favTab.setAttribute('aria-pressed', hist ? 'false' : 'true');
            sheet.histTab.setAttribute('aria-pressed', hist ? 'true' : 'false');
            sheet.panel.setAttribute('aria-label', hist ? 'History' : 'Favorites');
            sheet.clearBtn.hidden = !hist;
            var source = hist ? history : favorites;
            var sorted = source.slice().sort(function (a, b) { return b.favoritedAt - a.favoritedAt; });
            var playingId = playlist && playlist.current && playlist.source === sheet.mode ? playlist.current.id : null;
            // History rows show "2h ago", and hearts there follow favorites, so both go in the key.
            var key = JSON.stringify([sheet.mode, sorted.map(function (f) { return f.id + (hist ? ':' + ago(f.favoritedAt) + ':' + !!byId(f.id) : ''); }), playingId]);
            var count = sorted.length;
            sheet.sub.textContent = count === 1 ? '1 song' : count + ' songs';
            sheet.playBtn.disabled = sheet.shuffleBtn.disabled = sheet.clearBtn.disabled = !count;
            if (key === sheet.key) return;
            sheet.key = key;
            sheet.list.textContent = '';
            if (!count) {
              sheet.list.appendChild(el('div', 'sr-empty', hist
                ? 'Nothing here yet. Songs you listen to show up here.'
                : 'No favorites yet. Tap the heart next to a song to save it.'));
              return;
            }
            sorted.forEach(function (f) {
              var item = el('div', 'sr-item' + (f.id === playingId ? ' sr-item-playing' : ''));
              item.setAttribute('data-id', f.id);
              item.appendChild(el('div', 'sr-item-remove', 'Remove'));
              var showLine = esc(f.show) + (hist ? ' · ' + esc(ago(f.favoritedAt)) : '');
              var main = el('div', 'sr-item-main',
                '<img alt="" src="' + esc(f.cover) + '">' +
                '<div class="sr-item-text"><div class="sr-item-show">' + showLine + '</div>' +
                '<div class="sr-item-line"><span class="sr-item-song">' + esc(f.song) + '</span>&nbsp;<span class="sr-item-artist">' + esc(f.artist) + '</span></div></div>');
              var heart = heartButton('');
              if (hist) {
                setHeart(heart, !!byId(f.id), f.song);
                heart.addEventListener('click', function (e) {
                  e.stopPropagation();
                  var fav = {};
                  for (var k in f) fav[k] = f[k];
                  fav.favoritedAt = Date.now();
                  toggle(fav);
                });
              } else {
                setHeart(heart, true, f.song);
                heart.addEventListener('click', function (e) { e.stopPropagation(); removeItem(item, f.id, 'favorites'); });
              }
              main.appendChild(heart);
              main.addEventListener('click', function () {
                if (main.getAttribute('data-swiped')) return;
                startPlaylist('order', f.id, sheet.mode);
              });
              item.appendChild(main);
              attachSwipeToRemove(item, main, f.id, sheet.mode);
              sheet.list.appendChild(item);
            });
          }

          function removeItem(item, id, source) {
            item.style.transition = 'opacity .2s';
            item.style.opacity = '0';
            setTimeout(function () { if (source === 'history') removeHistory(id); else remove(id); }, 200);
          }

          function attachSwipeToRemove(item, main, id, source) {
            var x0 = 0, y0 = 0, dx = 0, mode = null;
            main.addEventListener('touchstart', function (e) {
              if (e.touches.length !== 1) return;
              x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; dx = 0; mode = null;
              main.style.transition = 'none';
              main.removeAttribute('data-swiped');
            }, { passive: true });
            main.addEventListener('touchmove', function (e) {
              var ddx = e.touches[0].clientX - x0, ddy = e.touches[0].clientY - y0;
              if (!mode) {
                if (Math.abs(ddx) < 8 && Math.abs(ddy) < 8) return;
                mode = Math.abs(ddx) > Math.abs(ddy) && ddx < 0 ? 'swipe' : 'other';
              }
              if (mode !== 'swipe') return;
              e.preventDefault();
              e.stopPropagation();
              dx = Math.min(0, ddx);
              main.style.transform = 'translateX(' + dx + 'px)';
            }, { passive: false });
            main.addEventListener('touchend', function () {
              if (mode !== 'swipe') return;
              main.setAttribute('data-swiped', '1');
              main.style.transition = 'transform .2s ease';
              if (dx < -main.offsetWidth * 0.35) {
                main.style.transform = 'translateX(-100%)';
                setTimeout(function () { removeItem(item, id, source); }, 150);
              } else {
                main.style.transform = '';
              }
              setTimeout(function () { main.removeAttribute('data-swiped'); }, 350);
            });
          }

          // Swipe down on the sheet (from its header, or from the list when it's scrolled
          // to the top) to close it.
          function attachSheetDrag() {
            var y0 = 0, x0 = 0, dy = 0, mode = null, fromList = false;
            sheet.panel.addEventListener('touchstart', function (e) {
              if (e.touches.length !== 1) return;
              y0 = e.touches[0].clientY; x0 = e.touches[0].clientX; dy = 0; mode = null;
              fromList = sheet.list.contains(e.target);
            }, { passive: true });
            sheet.panel.addEventListener('touchmove', function (e) {
              var ddy = e.touches[0].clientY - y0, ddx = e.touches[0].clientX - x0;
              if (!mode) {
                if (Math.abs(ddy) < 8 && Math.abs(ddx) < 8) return;
                var down = ddy > 0 && Math.abs(ddy) > Math.abs(ddx);
                mode = down && (!fromList || sheet.list.scrollTop <= 0) ? 'drag' : 'other';
                if (mode === 'drag') sheet.panel.style.transition = 'none';
              }
              if (mode !== 'drag') return;
              e.preventDefault();
              dy = Math.max(0, ddy);
              sheet.panel.style.transform = 'translateY(' + dy + 'px)';
            }, { passive: false });
            sheet.panel.addEventListener('touchend', function () {
              if (mode !== 'drag') return;
              sheet.panel.style.transition = '';
              if (dy > Math.min(120, sheet.panel.offsetHeight * 0.25)) closeSheet();
              else sheet.panel.style.transform = '';
            });
          }

          // The tab at the bottom of the screen when no show is playing.
          // A heart button in the site's top bar, next to the search box, opens the
          // Favorites sheet (it replaces the old floating tab).
          function searchBox() {
            var input = document.querySelector('input[placeholder*="Search" i]');
            if (!input) return null;
            // Climb to the box that sits beside the logo / back link in the top bar row.
            for (var e = input; e && e.parentElement && e.parentElement !== document.body; e = e.parentElement) {
              if (e.parentElement.children.length > 1) return e;
            }
            return null;
          }
          function renderTab() {
            var box = searchBox();
            if (!box || !box.parentElement) return;
            if (!tab) {
              tab = heartButton('sr-heart-top');
              tab.setAttribute('aria-label', 'Show favorites');
              tab.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); openSheet(); });
            }
            if (tab.previousElementSibling !== box) box.parentElement.insertBefore(tab, box.nextSibling);
            if (!dice) {
              dice = heartButton('sr-dice-top');
              dice.innerHTML = DICE;
              dice.removeAttribute('aria-pressed');
              dice.setAttribute('aria-label', 'Play a random show');
              dice.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); playRandomShow(); });
            }
            if (dice.previousElementSibling !== tab) box.parentElement.insertBefore(dice, tab.nextSibling);
          }

          // ---------------------------------------------------------------------------
          // Random show: the dice picks any episode the site lists and plays it from the start.
          // ---------------------------------------------------------------------------
          var RANDOM_KEY = 'sr-random-show';
          var episodeList = null;
          function episodePathsIn(html) {
            var out = {}, re = /\/episodes\/[A-Za-z0-9_-]+/g, m;
            while ((m = re.exec(html))) out[m[0]] = true;
            return Object.keys(out);
          }
          function loadEpisodes() {
            if (episodeList && episodeList.length) return Promise.resolve(episodeList);
            var found = {};
            function add(list) { list.forEach(function (p) { found[p] = true; }); }
            add(episodePathsIn(document.documentElement.innerHTML));
            function get(url) {
              return fetch(url, { credentials: 'same-origin' })
                .then(function (r) { return r.ok ? r.text() : ''; })
                .then(function (t) { add(episodePathsIn(t)); })
                .catch(function () {});
            }
            return Promise.all([get('/sitemap.xml'), get('/')]).then(function () {
              episodeList = Object.keys(found);
              return episodeList;
            });
          }
          function playRandomShow() {
            if (!dice || dice.getAttribute('aria-busy') === 'true') return;
            dice.setAttribute('aria-busy', 'true');
            loadEpisodes().then(function (paths) {
              dice.removeAttribute('aria-busy');
              var here = location.pathname.replace(/\/$/, '');
              var choices = paths.filter(function (p) { return p !== here; });
              if (!choices.length) choices = paths;
              if (!choices.length) return showToast("Couldn't find any shows.");
              var path = choices[Math.floor(Math.random() * choices.length)];
              endPlaylist(false);
              closeSheet();
              if (here !== path) {
                if (window.next && window.next.router && window.next.router.push) {
                  window.next.router.push(path);
                } else {
                  try { sessionStorage.setItem(RANDOM_KEY, path); } catch (e) {}
                  location.assign(path);
                  return;
                }
              }
              startShowFromTop(path);
            });
          }
          // Waits for the episode page, then presses its Play button (or the first song).
          function startShowFromTop(path) {
            var deadline = Date.now() + 15000;
            (function tryPlay() {
              if (location.pathname.replace(/\/$/, '') === path) {
                var main = document.querySelector('main') || document.body;
                var btns = main.querySelectorAll('button');
                for (var i = 0; i < btns.length; i++) {
                  var b = btns[i];
                  if (b.closest('.sr-fav-root, .col-span-full.grid') || b.classList.contains('sr-heart')) continue;
                  if (/^\s*play\s*$/i.test(b.textContent || '') || /^play\b/i.test(b.getAttribute('aria-label') || '')) { b.click(); return; }
                }
                var rows = pageRows();
                var first = rows.length && rows[0].row.querySelector(':scope > button');
                if (first) { first.click(); return; }
              }
              if (Date.now() < deadline) setTimeout(tryPlay, 250);
              else showToast("Couldn't start that show.");
            })();
          }

          // Swipe up on the mini player (or the tab) to open the sheet.
          function attachOpenGesture() {
            var y0 = null, x0 = 0;
            document.addEventListener('touchstart', function (e) {
              y0 = null;
              if (e.touches.length !== 1 || isOpen()) return;
              var t = e.target;
              var player = miniPlayer();
              var onPlayer = player && player.contains(t) && !(t.closest && t.closest('[data-orientation="horizontal"]'));
              var onTab = tab && tab.contains(t);
              if (!onPlayer && !onTab) return;
              y0 = e.touches[0].clientY; x0 = e.touches[0].clientX;
            }, { passive: true, capture: true });
            document.addEventListener('touchend', function (e) {
              if (y0 == null) return;
              var p = e.changedTouches[0];
              var dy = p.clientY - y0, dx = p.clientX - x0;
              y0 = null;
              if (dy < -30 && Math.abs(dy) > Math.abs(dx) * 1.5) openSheet();
            }, { passive: true, capture: true });
          }

          // ---------------------------------------------------------------------------
          // Favorites playlist
          // ---------------------------------------------------------------------------
          var PENDING_KEY = 'sr-favorites-playlist';
          var playlist = null;   // {ids, pos, mode, current}
          var arriving = null;   // {id, since, tries} while switching to a favorite
          var endTimer = null;   // fires right at the current favorite's end

          function shuffled(a) {
            for (var i = a.length - 1; i > 0; i--) {
              var j = Math.floor(Math.random() * (i + 1));
              var x = a[i]; a[i] = a[j]; a[j] = x;
            }
            return a;
          }

          // Plays favorites (oldest favorited first) or history (most recent first).
          function startPlaylist(mode, firstId, source) {
            source = source === 'history' ? 'history' : 'favorites';
            var items = sourceList(source);
            if (!items.length) return;
            var ids = items.slice()
              .sort(function (a, b) { return source === 'history' ? b.favoritedAt - a.favoritedAt : a.favoritedAt - b.favoritedAt; })
              .map(function (f) { return f.id; });
            var pos = 0;
            if (mode === 'shuffle') {
              shuffled(ids);
              if (firstId) { ids.splice(ids.indexOf(firstId), 1); ids.unshift(firstId); }
            } else if (firstId) {
              pos = Math.max(0, ids.indexOf(firstId));
            }
            playlist = { ids: ids, pos: pos, mode: mode, source: source, current: null };
            closeSheet();
            playCurrent();
          }

          function endPlaylist(pause) {
            if (!playlist) return;
            playlist = null;
            arriving = null;
            try { sessionStorage.removeItem(PENDING_KEY); } catch (e) {}
            var n = np();
            if (n) { n.setPlaylist(null); n.setOverride(null); if (pause) n.pause(); }
            schedule();
          }

          function playCurrent() {
            var f = null;
            while (playlist && playlist.pos < playlist.ids.length && !(f = lookup(playlist.source, playlist.ids[playlist.pos]))) {
              playlist.ids.splice(playlist.pos, 1); // removed since the playlist started
            }
            if (!f) return endPlaylist(true);
            var previous = playlist.current;
            playlist.current = f;
            var n = np();
            if (n) {
              n.setPlaylist({ next: nextFavorite, previous: previousFavorite });
              n.setOverride({ title: f.song, artist: f.artist, album: f.show, artwork: f.cover });
            }
            schedule();
            var st = npState();
            var sameShow = st && st.number && st.number === showNumber(f.show);
            if (sameShow) {
              // Same episode: just seek, unless it's the very next song.
              arriving = { id: f.id, since: Date.now(), tries: 1 };
              if (!(previous && previous.end != null && Math.abs(previous.end - f.start) < 1 && st.t != null && Math.abs(st.t - f.start) < 3)) {
                n && n.seek(f.start);
              }
              return;
            }
            arriving = { id: f.id, since: Date.now(), tries: 0 };
            openEpisodeAndPlay(f);
          }

          // Opens the favorite's episode page and taps its tracklist row, which is how the
          // site itself starts an episode at a song.
          function openEpisodeAndPlay(f) {
            if (location.pathname.replace(/\/$/, '') !== f.episodeURL) {
              if (window.next && window.next.router && window.next.router.push) {
                window.next.router.push(f.episodeURL);
              } else {
                try { sessionStorage.setItem(PENDING_KEY, JSON.stringify(playlist)); } catch (e) {}
                location.assign(f.episodeURL);
                return;
              }
            }
            var deadline = Date.now() + 15000;
            (function tryClick() {
              if (!playlist || !arriving || arriving.id !== f.id) return;
              if (location.pathname.replace(/\/$/, '') === f.episodeURL) {
                var rows = pageRows();
                var best = null;
                rows.forEach(function (r) { if (r.start <= f.start + 1 && (!best || r.start > best.start)) best = r; });
                if (best) {
                  var btn = best.row.querySelector(':scope > button');
                  if (btn) {
                    arriving.tries++;
                    arriving.since = Date.now();
                    btn.click();
                    if (Math.abs(best.start - f.start) > 1) setTimeout(function () { var n = np(); n && n.seek(f.start); }, 1500);
                    return;
                  }
                }
              }
              if (Date.now() < deadline) setTimeout(tryClick, 250);
              else endPlaylist(false);
            })();
          }

          function nextFavorite() {
            if (!playlist) return;
            playlist.pos++;
            if (playlist.pos >= playlist.ids.length) return endPlaylist(true);
            playCurrent();
          }

          function previousFavorite() {
            if (!playlist || !playlist.current) return;
            var st = npState();
            var f = playlist.current;
            var n = np();
            // Like the lock screen elsewhere: restart the song unless it just started.
            if ((st && st.t != null && st.t - f.start > 3) || playlist.pos === 0) {
              n && n.seek(f.start);
              return;
            }
            playlist.pos--;
            playCurrent();
          }

          // Follows playback: confirms the switch to a favorite, moves on at its end, and
          // ends playlist mode when a different show starts playing.
          function followPlayback(st) {
            if (!playlist || !playlist.current) return;
            var f = playlist.current;
            var number = showNumber(f.show);
            if (arriving) {
              if (st && st.number === number && st.t != null && st.t >= f.start - 2 && st.t <= f.start + 20) {
                arriving = null;
              } else if (Date.now() - arriving.since > 7000) {
                if (st && st.number === number && arriving.tries < 3) {
                  arriving.tries++;
                  arriving.since = Date.now();
                  var n = np();
                  n && n.seek(f.start);
                } else if (arriving.tries >= 3 || Date.now() - arriving.since > 20000) {
                  endPlaylist(false);
                }
              }
              return;
            }
            if (!st || st.t == null) return;
            if (st.number !== number) return endPlaylist(false);
            var end = f.end != null ? f.end : (st.duration || Infinity);
            var left = end - st.t;
            if (left <= 0.4) return nextFavorite();
            // Playback updates arrive about once a second; check again right at the end.
            if (left < 2.5 && !endTimer && !st.paused) {
              endTimer = setTimeout(function () {
                endTimer = null;
                followPlayback(npState());
              }, (left - 0.3) * 1000);
            }
          }

          // Starting a normal episode (tapping a tracklist row yourself) ends playlist mode.
          document.addEventListener('click', function (e) {
            if (!e.isTrusted || !playlist) return;
            var t = e.target;
            if (t && t.closest && t.closest('.col-span-full.grid > button')) endPlaylist(false);
          }, true);

          window.addEventListener('soulection-nowplaying', function (e) {
            followPlayback(e.detail);
            followListening(e.detail);
            schedule();
          });

          // ---------------------------------------------------------------------------
          // The site is server-rendered and then hydrated by React. Changing its markup
          // before hydration (adding hearts to the tracklist) makes React throw the page
          // away and re-render it, so wait until React has claimed the page. React marks the
          // nodes it owns with a "__reactFiber$..." property.
          var hydrated = false;
          var startedAt = Date.now();
          function isHydrated() {
            if (hydrated) return true;
            var probe = document.querySelector('main') || (document.body && document.body.firstElementChild);
            var keys = probe ? Object.keys(probe) : [];
            for (var i = 0; i < keys.length; i++) {
              if (keys[i].indexOf('__reactFiber$') === 0) return (hydrated = true);
            }
            // Not a React page (anymore)? Don't wait forever.
            if (document.readyState === 'complete' && Date.now() - startedAt > 4000) return (hydrated = true);
            return false;
          }

          function render() {
            renderPending = false;
            if (!document.body) return;
            if (!isHydrated()) {
              setTimeout(schedule, 200);
              return;
            }
            if (!document.getElementById('sr-fav-style')) {
              var style = el('style');
              style.id = 'sr-fav-style';
              style.textContent = CSS;
              (document.head || document.documentElement).appendChild(style);
            }
            renderRowHearts();
            renderMiniPlayer(miniPlayer());
            renderTab();
            if (isOpen()) renderSheet();
          }

          function schedule() {
            if (renderPending) return;
            renderPending = true;
            setTimeout(render, 60);
          }

          function start() {
            attachOpenGesture();
            new MutationObserver(function (mutations) {
              for (var i = 0; i < mutations.length; i++) {
                var target = mutations[i].target;
                // Ignore our own elements so updating a heart doesn't trigger another pass.
                if (target.closest && target.closest('.sr-heart, .sr-fav-root, .sr-tab, .sr-grab, .sr-note')) continue;
                return schedule();
              }
            }).observe(document.body, { childList: true, subtree: true, characterData: true });
            try {
              var pending = JSON.parse(sessionStorage.getItem(PENDING_KEY) || 'null');
              sessionStorage.removeItem(PENDING_KEY);
              if (pending && pending.ids) {
                pending.current = null;
                resumeAfterLoad = pending;
              }
            } catch (e) {}
            try {
              var randomPath = sessionStorage.getItem(RANDOM_KEY);
              sessionStorage.removeItem(RANDOM_KEY);
              if (randomPath) startShowFromTop(randomPath);
            } catch (e) {}
            native({ op: 'get' });
            schedule();
          }

          if (document.body) start();
          else document.addEventListener('DOMContentLoaded', start);
        })();
        """#
}
