import Foundation

/// Drives the lock screen / Now Playing info from the episode tracklist, like Spotify.
///
/// radio.soulection.com plays through a cross-origin SoundCloud widget iframe, and
/// iOS takes Now Playing info from the media session of the frame that owns the
/// audio. So this script is injected into every frame:
///
/// - On the Soulection page it parses the tracklist rows (timestamp, artist, song),
///   the mini player's show name and cover, and the playback position (the iframe
///   reports its audio element's currentTime; the mini player's slider is the
///   fallback). A MutationObserver plus a 1-second timer recomputes the current
///   track and posts {title, artist, album, artwork, track start times} to the iframe.
/// - In the player iframe it applies that metadata, keeps the widget from
///   overwriting it, and handles nexttrack/previoustrack (seek to the next/previous
///   tracklist timestamp; previous restarts the current song after 3 seconds). It
///   clears seekforward/seekbackward so iOS shows track buttons instead of 10-second
///   skips. Play/pause stay with the widget.
///
/// It also exposes `window.__soulectionNowPlaying` for FavoritesScript: the playback
/// state (show, episode, tracklist, position), seek and pause, a metadata override,
/// and next/previous hooks so the lock screen buttons move through the favorites
/// playlist while it plays.
enum NowPlayingScript {
    static let source = #"""
        (function () {
          if (window.__soulectionNowPlaying) return;
          window.__soulectionNowPlaying = true;

          var MSG = 'soulection-nowplaying';
          var SOULECTION_ORIGIN = /^https:\/\/([a-z0-9-]+\.)*soulection\.com$/i;
          var isTop = window === window.top;

          if (isTop) {
            if (SOULECTION_ORIGIN.test(location.origin)) runPage();
          } else {
            var ancestors = location.ancestorOrigins;
            var topOrigin = ancestors && ancestors.length ? ancestors[ancestors.length - 1] : '';
            if (SOULECTION_ORIGIN.test(topOrigin)) runPlayerFrame();
          }

          function text(el) {
            return el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
          }

          function parseTimestamp(s) {
            var m = /^(\d+):(\d{1,2})(?::(\d{1,2}))?$/.exec(s);
            if (!m) return null;
            return m[3] == null ? +m[1] * 60 + +m[2] : +m[1] * 3600 + +m[2] * 60 + +m[3];
          }

          function showNumber(s) {
            var m = /#\s*(\d+)/.exec(s || '');
            return m ? m[1] : null;
          }

          // ---------------------------------------------------------------------------
          // Soulection page (top frame): work out the current track and tell the player.
          // ---------------------------------------------------------------------------
          function runPage() {
            var tracklists = {}; // show number -> [{start, artist, title}]
            var frameTime = null; // {t, at} reported by the player iframe
            var lastSent = '';
            var lastSentAt = 0;
            var scheduled = false;
            var lastState = null;
            var override = null; // metadata FavoritesScript shows while its playlist plays
            var playlist = null; // {next, previous} handlers while the favorites playlist plays
            // While a playlist plays a show in the app's own (hidden) player, that player is
            // the one to follow and control, and `direct` describes the show it plays.
            var activeFrame = null;   // contentWindow of the player in charge, or null for the site's
            var standbys = [];        // contentWindows of players loaded ahead (not in charge yet)
            var ourWins = [];         // contentWindows of all the app's own players
            var frameTimes = [];      // [{win, t, paused, duration, at}]
            var direct = null;        // {number, show, cover, episodeURL, tracks}
            // Cover addresses must be absolute: the player frame is on another site.
            function abs(u) { try { return u ? new URL(u, location.href).href : ''; } catch (e) { return u || ''; } }
            function timeOf(win) {
              for (var i = 0; i < frameTimes.length; i++) if (frameTimes[i].win === win) return frameTimes[i];
              return null;
            }

            function miniPlayer() {
              var slider = document.querySelector('[role="slider"][aria-valuenow]');
              if (!slider) return null;
              var el = slider;
              while (el && el !== document.body) {
                if (el.querySelector('img') && /fixed/.test(el.className || '')) return el;
                el = el.parentElement;
              }
              return slider.closest('div.group') || null;
            }

            function parseTracklist() {
              var rows = document.querySelectorAll('.col-span-full.grid');
              var tracks = [];
              for (var i = 0; i < rows.length; i++) {
                var spans = rows[i].querySelectorAll(':scope > span');
                if (spans.length < 3) continue;
                var start = parseTimestamp(text(spans[0]));
                if (start == null) continue;
                var artist = text(rows[i].querySelector('a[href*="/artists/"]')) || text(spans[1]);
                var title = text(rows[i].querySelector('a[href*="/songs/"]')) || text(spans[2]);
                tracks.push({ start: start, artist: artist, title: title, row: rows[i] });
              }
              tracks.sort(function (a, b) { return a.start - b.start; });
              return tracks;
            }

            function episodeOnPage() {
              var h1 = document.querySelector('#episode-card-header h1, main h1');
              return h1 ? text(h1) : '';
            }

            function currentState() {
              var player = miniPlayer();
              if (!player) return null;
              var showLine = '';
              var lines = player.querySelectorAll('.content-col > div');
              if (lines.length) showLine = text(lines[0]);
              var playerSong = lines.length > 1 ? text(lines[1]) : '';
              if (direct) { showLine = direct.show || ('Show #' + direct.number); playerSong = ''; }
              var number = direct ? direct.number : showNumber(showLine);
              if (direct && direct.tracks && direct.tracks.length && !tracklists[number]) {
                var dt = direct.tracks.slice();
                dt.url = direct.episodeURL;
                tracklists[number] = dt;
              }

              // Cache the tracklist when the page shows the episode that is playing.
              var pageEpisode = episodeOnPage();
              if (number && showNumber(pageEpisode) === number) {
                var parsed = parseTracklist();
                if (parsed.length) {
                  parsed.url = location.pathname;
                  tracklists[number] = parsed;
                }
              }
              var tracks = (number && tracklists[number]) || [];

              var t = null;
              if (activeFrame) {
                var ft = timeOf(activeFrame);
                if (ft) t = ft.t + (ft.paused ? 0 : (Date.now() - ft.at) / 1000);
              } else if (frameTime && Date.now() - frameTime.at < 3000) {
                t = frameTime.t + (frameTime.paused ? 0 : (Date.now() - frameTime.at) / 1000);
              } else {
                var slider = player.querySelector('[role="slider"][aria-valuenow]');
                var v = slider && parseFloat(slider.getAttribute('aria-valuenow'));
                if (!isNaN(v)) t = v;
              }

              var album = showLine.split(' | ')[0].trim() || (number ? 'Show #' + number : 'Soulection Radio');
              var img = player.querySelector('img');
              var artwork = direct ? (direct.cover || '') : (img && img.src ? img.src : '');
              var title = '';
              var artist = '';

              var index = -1;
              if (tracks.length && t != null) {
                for (var i = 0; i < tracks.length; i++) if (tracks[i].start <= t + 0.25) index = i;
              }
              if (index < 0 && tracks.length) {
                // The highlighted tracklist row, if the page marks one.
                for (var j = 0; j < tracks.length; j++) {
                  var r = tracks[j].row;
                  if (r && r.isConnected && (r.getAttribute('aria-current') || /\b(bg-(?!gray-50)|active|current|playing)/.test(r.className))) index = j;
                }
              }
              if (index >= 0) {
                title = tracks[index].title;
                artist = tracks[index].artist;
              } else if (playerSong && !tracks.length) {
                // No tracklist for this show on hand: fall back to the mini player text.
                var parts = playerSong.split(/\s+[-–—]\s+/);
                if (parts.length > 1) { artist = parts.shift(); title = parts.join(' - '); } else { title = playerSong; }
              }
              if (!title) { title = showLine || album; artist = artist || 'Soulection Radio'; }
              if (override) {
                title = override.title;
                artist = override.artist;
                album = override.album;
                artwork = abs(override.artwork) || artwork;
              }
              var slider2 = player.querySelector('[role="slider"][aria-valuemax]');
              var duration = slider2 ? parseFloat(slider2.getAttribute('aria-valuemax')) : NaN;
              var activeTime = activeFrame ? timeOf(activeFrame) : null;
              if (activeFrame) duration = activeTime && activeTime.duration ? activeTime.duration : NaN;

              return {
                type: MSG,
                title: title,
                artist: artist,
                album: album,
                artwork: artwork,
                starts: tracks.map(function (x) { return x.start; }),
                index: index,
                t: t,
                // Used by FavoritesScript (not by the player frame).
                number: number,
                show: showLine.split(' | ')[0].trim(),
                cover: direct ? (direct.cover || '') : (img && img.src ? img.src : ''),
                episodeURL: tracks.url || '',
                tracks: tracks.map(function (x) { return { start: x.start, artist: x.artist, title: x.title }; }),
                duration: isNaN(duration) ? null : duration,
                paused: activeFrame ? (activeTime ? !!activeTime.paused : null) : (frameTime ? !!frameTime.paused : null),
                playlist: !!playlist
              };
            }

            function playerFrames() {
              var frames = document.querySelectorAll('iframe');
              var out = [];
              for (var i = 0; i < frames.length; i++) if (frames[i].contentWindow) out.push(frames[i]);
              return out;
            }

            function setMetadata(state) {
              if (!('mediaSession' in navigator) || typeof MediaMetadata === 'undefined') return;
              try {
                navigator.mediaSession.metadata = new MediaMetadata({
                  title: state.title,
                  artist: state.artist,
                  album: state.album,
                  artwork: state.artwork ? [{ src: state.artwork, sizes: '500x500', type: 'image/jpeg' }] : []
                });
              } catch (e) {}
            }

            function update() {
              scheduled = false;
              var state = currentState();
              lastState = state;
              try { window.dispatchEvent(new CustomEvent('soulection-nowplaying', { detail: state })); } catch (e) {}
              if (!state) return;
              var key = JSON.stringify([state.title, state.artist, state.album, state.artwork, state.starts, state.playlist]);
              var now = Date.now();
              if (key === lastSent && now - lastSentAt < 5000) return;
              lastSent = key;
              lastSentAt = now;
              setMetadata(state);
              playerFrames().forEach(function (f) {
                // A player loaded ahead already has the next song's info (see preview).
                if (standbys.indexOf(f.contentWindow) >= 0) return;
                try { f.contentWindow.postMessage(state, '*'); } catch (e) {}
              });
            }

            function schedule() {
              if (scheduled) return;
              scheduled = true;
              setTimeout(update, 150);
            }

            window.addEventListener('message', function (e) {
              var d = e.data;
              if (!d || d.type !== MSG + '-time') return;
              var fromPlayer = playerFrames().some(function (f) { return f.contentWindow === e.source; });
              if (!fromPlayer) return;
              if (typeof d.t === 'number') {
                var rec = timeOf(e.source);
                if (!rec) { rec = { win: e.source }; frameTimes.push(rec); }
                rec.t = d.t; rec.paused = !!d.paused; rec.at = Date.now(); rec.muted = !!d.muted;
                // Heard = playing and not muted. A heard player the app isn't following (after
                // a switch that didn't go cleanly) is reported so the app can follow it instead.
                var heard = !rec.paused && !rec.muted;
                rec.heardSince = heard ? (rec.heardSince || Date.now()) : 0;
                if (typeof d.duration === 'number' && isFinite(d.duration)) rec.duration = d.duration;
                frameTimes = frameTimes.filter(function (r) { return Date.now() - r.at < 600000; });
                try { window.dispatchEvent(new CustomEvent('soulection-frametime', { detail: { win: e.source, t: rec.t, paused: rec.paused, muted: rec.muted } })); } catch (err) {}
                // A player loaded ahead reports here too; only the one in charge counts.
                var inCharge = activeFrame ? e.source === activeFrame : (standbys.indexOf(e.source) < 0 && ourWins.indexOf(e.source) < 0);
                if (!inCharge && heard && Date.now() - rec.heardSince > 2000) {
                  var lead = activeFrame ? timeOf(activeFrame) : frameTime;
                  var leadHeard = lead && Date.now() - lead.at < 3000 && !lead.paused && !lead.muted;
                  if (!leadHeard) {
                    try { window.dispatchEvent(new CustomEvent('soulection-stray', { detail: { win: e.source } })); } catch (err) {}
                  }
                }
                if (!inCharge) return;
                frameTime = { t: d.t, paused: !!d.paused, muted: !!d.muted, at: Date.now() };
              }
              // Play/pause from the lock screen, Dynamic Island, headphones or a Bluetooth
              // speaker. iOS can send it to any of the players, so it's always passed on to
              // the one in charge (a pause goes to all of them).
              if (d.command === 'play') { toPlayer({ play: true }); schedule(); return; }
              if (d.command === 'pause') {
                playerFrames().forEach(function (f) { toFrame(f.contentWindow, { pause: true }); });
                schedule();
                return;
              }
              if (standbys.indexOf(e.source) >= 0 || (activeFrame && e.source !== activeFrame)) return;
              if (d.hello) lastSent = '';
              if (d.command && playlist) {
                // Lock screen next/previous while the favorites playlist plays.
                try { playlist[d.command === 'next' ? 'next' : 'previous'](); } catch (err) {}
              }
              if (typeof d.seekTo === 'number') {
                // The player frame couldn't seek its own media element; use the widget API.
                try {
                  playerFrames().forEach(function (f) {
                    if (f.contentWindow === e.source && window.SC && SC.Widget) SC.Widget(f).seekTo(d.seekTo * 1000);
                  });
                } catch (err) {}
              }
              schedule();
            });

            function observe() {
              new MutationObserver(schedule).observe(document.documentElement, {
                subtree: true,
                childList: true,
                characterData: true,
                attributes: true,
                attributeFilter: ['aria-valuenow', 'class', 'src', 'aria-current']
              });
            }
            if (document.documentElement) observe();
            else document.addEventListener('DOMContentLoaded', observe);

            // Timer fallback in case the page updates without DOM mutations.
            setInterval(schedule, 1000);

            function toPlayer(msg) {
              msg.type = MSG + '-control';
              if (activeFrame) {
                try { activeFrame.postMessage(msg, '*'); } catch (e) {}
                return;
              }
              playerFrames().forEach(function (f) {
                if (standbys.indexOf(f.contentWindow) >= 0 || ourWins.indexOf(f.contentWindow) >= 0) return;
                try { f.contentWindow.postMessage(msg, '*'); } catch (e) {}
              });
            }
            function toFrame(win, msg) {
              msg.type = MSG + '-control';
              try { win.postMessage(msg, '*'); } catch (e) {}
            }

            // Used by FavoritesScript to follow playback and drive the favorites playlist.
            window.__soulectionNowPlaying = {
              state: function () { return currentState(); },
              refresh: function () { lastSent = ''; update(); },
              seek: function (t) { toPlayer({ seek: t }); },
              pause: function () { toPlayer({ pause: true }); },
              play: function () { toPlayer({ play: true }); },
              setOverride: function (meta) { override = meta; lastSent = ''; schedule(); },
              setPlaylist: function (handlers) { playlist = handlers; lastSent = ''; schedule(); },
              // The app's own players (see FavoritesScript's handoff).
              setActiveFrame: function (win) { activeFrame = win || null; frameTime = null; lastSent = ''; schedule(); },
              activeFrame: function () { return activeFrame; },
              setOurs: function (win, on) {
                ourWins = ourWins.filter(function (w) { return w !== win; });
                if (on) ourWins.push(win);
              },
              setStandby: function (win, on) {
                standbys = standbys.filter(function (w) { return w !== win; });
                if (on) standbys.push(win);
              },
              setDirect: function (info) { direct = info || null; lastSent = ''; schedule(); },
              toFrame: toFrame,
              // Gives a player loaded ahead its song's lock screen info before it plays, so the
              // name and cover change together at the switch.
              preview: function (win, meta) {
                try {
                  win.postMessage({
                    type: MSG, title: meta.title || '', artist: meta.artist || '', album: meta.album || '',
                    artwork: abs(meta.artwork), starts: [], index: -1, playlist: !!playlist
                  }, '*');
                } catch (e) {}
              },
              timeOf: function (win) { return timeOf(win); }
            };
          }

          // ---------------------------------------------------------------------------
          // Player iframe (SoundCloud widget): owns the audio, so it owns Now Playing.
          // ---------------------------------------------------------------------------
          function runPlayerFrame() {
            var ms = navigator.mediaSession;
            if (!ms) return;
            var proto = Object.getPrototypeOf(ms);
            var metaDesc = Object.getOwnPropertyDescriptor(proto, 'metadata');
            var nativeSetHandler = proto.setActionHandler;
            var OWNED = ['nexttrack', 'previoustrack', 'seekforward', 'seekbackward', 'play', 'pause'];
            var state = null;
            var media = null;

            // Find the media element the widget plays (it may never be in the DOM).
            var nativePlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function () {
              track(this);
              return nativePlay.apply(this, arguments);
            };
            document.addEventListener('play', function (e) { track(e.target); }, true);
            // Each time playback starts (a switch, or you pressing play), tell iOS again what's
            // playing, so it shows in the Dynamic Island and on the lock screen.
            document.addEventListener('play', function () { setTimeout(function () { announce(true); }, 50); }, true);
            document.addEventListener('pause', function () { try { ms.playbackState = 'paused'; } catch (e) {} }, true);

            function track(el) {
              if (!(el instanceof HTMLMediaElement) || media === el) return;
              media = el;
              if (standby && pendingStart != null && Math.abs((el.currentTime || 0) - pendingStart) > 2) el.muted = true; // until it's at its song
              ['timeupdate', 'seeked', 'play', 'pause', 'loadedmetadata', 'canplay'].forEach(function (name) {
                el.addEventListener(name, reportTime);
              });
            }

            // Set when the app switched shows inside the player (sr_start in the player's
            // address): jump to the song's start once the audio is ready.
            var pendingStart = null, startTries = 0, standby = false;
            var lastMetaKey = '';
            try {
              var params = new URLSearchParams(location.search);
              var sp = params.get('sr_start');
              if (sp != null && !isNaN(parseFloat(sp))) pendingStart = parseFloat(sp);
              standby = params.get('sr_standby') === '1';
            } catch (e) {}
            function applyStart() {
              if (pendingStart == null || !media || media.readyState < 1) return;
              if (Math.abs(media.currentTime - pendingStart) < 2 && !media.paused) {
                pendingStart = null;
                // Loaded ahead: it's at its song now, so it can be heard right away.
                if (standby) { media.muted = false; standby = false; announce(true); }
                return;
              }
              if (++startTries > 20) { pendingStart = null; if (standby) { media.muted = false; standby = false; } return; }
              if (Math.abs(media.currentTime - pendingStart) >= 2) {
                if (standby && !media.paused) media.muted = true; // no blip from the wrong spot
                try { media.currentTime = pendingStart; } catch (e) {}
              }
            }

            var lastReport = 0;
            function reportTime(e) {
              if (!media) return;
              applyStart();
              var now = Date.now();
              if (e && e.type === 'timeupdate' && now - lastReport < 900) return;
              lastReport = now;
              post({ t: media.currentTime, paused: media.paused, duration: media.duration, muted: media.muted });
            }

            function post(extra) {
              var msg = { type: MSG + '-time' };
              for (var k in extra) msg[k] = extra[k];
              try { window.parent.postMessage(msg, '*'); } catch (e) {}
            }

            // While we have tracklist metadata, the widget's own updates are held back.
            if (metaDesc && metaDesc.set) {
              Object.defineProperty(ms, 'metadata', {
                configurable: true,
                get: function () { return metaDesc.get.call(ms); },
                set: function (value) {
                  if (!state) metaDesc.set.call(ms, value);
                }
              });
            }
            ms.setActionHandler = function (action, handler) {
              if (state && OWNED.indexOf(action) >= 0) return;
              return nativeSetHandler.call(ms, action, handler);
            };

            function now() {
              if (media) return media.currentTime;
              return state && typeof state.t === 'number' ? state.t : 0;
            }

            function seek(t) {
              t = Math.max(0, t);
              if (media && media.duration) t = Math.min(t, media.duration - 0.5);
              if (media) {
                media.currentTime = t;
                reportTime();
              } else {
                post({ seekTo: t });
              }
            }

            function handlers() {
              var starts = state.starts || [];
              var set = function (a, h) { try { nativeSetHandler.call(ms, a, h); } catch (e) {} };
              // Play/pause go through the page, which knows which player is in charge. Pausing
              // this one right away is always safe.
              set('play', function () { post({ command: 'play' }); });
              set('pause', function () { if (media) media.pause(); post({ command: 'pause' }); });
              if (state.playlist) {
                // The favorites playlist decides what next/previous mean.
                set('nexttrack', function () { post({ command: 'next', t: now() }); });
                set('previoustrack', function () { post({ command: 'previous', t: now() }); });
                set('seekforward', null);
                set('seekbackward', null);
                return;
              }
              set('nexttrack', starts.length ? function () {
                var t = now();
                for (var i = 0; i < starts.length; i++) if (starts[i] > t + 1) return seek(starts[i]);
              } : null);
              set('previoustrack', starts.length ? function () {
                var t = now();
                var i = -1;
                for (var j = 0; j < starts.length; j++) if (starts[j] <= t + 0.25) i = j;
                // Like Spotify: restart the current song unless it just started.
                if (i >= 0 && t - starts[i] > 3) return seek(starts[i]);
                seek(i > 0 ? starts[i - 1] : 0);
              } : null);
              // iOS shows 10-second skip buttons instead of next/previous track whenever
              // seek handlers exist, so clear them (including any the widget set earlier).
              set('seekforward', null);
              set('seekbackward', null);
            }

            window.addEventListener('message', function (e) {
              if (e.source !== window.parent || !SOULECTION_ORIGIN.test(e.origin)) return;
              var d = e.data;
              if (d && d.type === MSG + '-control') {
                if (typeof d.seek === 'number') seek(d.seek);
                if (d.pause && media) media.pause();
                // Play straight from the page (faster than going through the widget API).
                if (d.play && media) { var p = media.play(); if (p && p.catch) p.catch(function () {}); }
                if (d.unmute && media) { media.muted = false; standby = false; announce(true); }
                if (d.mute && media) media.muted = true;
                return;
              }
              if (!d || d.type !== MSG) return;
              state = d;
              announce(false);
            });

            // Sets the lock screen info. Only when it changed, unless forced: every new
            // MediaMetadata makes iOS drop the cover and fetch it again, which in the
            // background can leave the Dynamic Island without artwork for a while.
            function announce(force) {
              if (!state) return;
              var d = state;
              var metaKey = JSON.stringify([d.title || '', d.artist || '', d.album || '', d.artwork || '']);
              if (force || metaKey !== lastMetaKey) {
                lastMetaKey = metaKey;
                try {
                  metaDesc.set.call(ms, new MediaMetadata({
                    title: d.title || '',
                    artist: d.artist || '',
                    album: d.album || '',
                    artwork: d.artwork ? [{ src: d.artwork, sizes: '500x500', type: 'image/jpeg' }] : []
                  }));
                } catch (err) {}
              }
              if (force && media && !media.paused && !media.muted) { try { ms.playbackState = 'playing'; } catch (e) {} }
              handlers();
            }

            post({ hello: true });
          }
        })();
        """#
}
