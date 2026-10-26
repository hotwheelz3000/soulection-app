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
///   tracklist timestamp; previous restarts the current song after 3 seconds) and
///   10-second seekforward/seekbackward. Play/pause stay with the widget.
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
              var number = showNumber(showLine);

              // Cache the tracklist when the page shows the episode that is playing.
              var pageEpisode = episodeOnPage();
              if (number && showNumber(pageEpisode) === number) {
                var parsed = parseTracklist();
                if (parsed.length) tracklists[number] = parsed;
              }
              var tracks = (number && tracklists[number]) || [];

              var t = null;
              if (frameTime && Date.now() - frameTime.at < 3000) {
                t = frameTime.t + (frameTime.paused ? 0 : (Date.now() - frameTime.at) / 1000);
              } else {
                var slider = player.querySelector('[role="slider"][aria-valuenow]');
                var v = slider && parseFloat(slider.getAttribute('aria-valuenow'));
                if (!isNaN(v)) t = v;
              }

              var album = showLine.split(' | ')[0].trim() || (number ? 'Show #' + number : 'Soulection Radio');
              var img = player.querySelector('img');
              var artwork = img && img.src ? img.src : '';
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

              return {
                type: MSG,
                title: title,
                artist: artist,
                album: album,
                artwork: artwork,
                starts: tracks.map(function (x) { return x.start; }),
                index: index,
                t: t
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
              if (!state) return;
              var key = JSON.stringify([state.title, state.artist, state.album, state.artwork, state.starts]);
              var now = Date.now();
              if (key === lastSent && now - lastSentAt < 5000) return;
              lastSent = key;
              lastSentAt = now;
              setMetadata(state);
              playerFrames().forEach(function (f) {
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
              if (typeof d.t === 'number') frameTime = { t: d.t, paused: !!d.paused, at: Date.now() };
              if (d.hello) lastSent = '';
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
            var OWNED = ['nexttrack', 'previoustrack', 'seekforward', 'seekbackward'];
            var state = null;
            var media = null;

            // Find the media element the widget plays (it may never be in the DOM).
            var nativePlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function () {
              track(this);
              return nativePlay.apply(this, arguments);
            };
            document.addEventListener('play', function (e) { track(e.target); }, true);

            function track(el) {
              if (!(el instanceof HTMLMediaElement) || media === el) return;
              media = el;
              ['timeupdate', 'seeked', 'play', 'pause'].forEach(function (name) {
                el.addEventListener(name, reportTime);
              });
            }

            var lastReport = 0;
            function reportTime(e) {
              if (!media) return;
              var now = Date.now();
              if (e && e.type === 'timeupdate' && now - lastReport < 900) return;
              lastReport = now;
              post({ t: media.currentTime, paused: media.paused });
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
              set('seekforward', function (d) { seek(now() + ((d && d.seekOffset) || 10)); });
              set('seekbackward', function (d) { seek(now() - ((d && d.seekOffset) || 10)); });
            }

            window.addEventListener('message', function (e) {
              if (e.source !== window.parent || !SOULECTION_ORIGIN.test(e.origin)) return;
              var d = e.data;
              if (!d || d.type !== MSG) return;
              state = d;
              try {
                metaDesc.set.call(ms, new MediaMetadata({
                  title: d.title || '',
                  artist: d.artist || '',
                  album: d.album || '',
                  artwork: d.artwork ? [{ src: d.artwork, sizes: '500x500', type: 'image/jpeg' }] : []
                }));
              } catch (err) {}
              handlers();
            });

            post({ hello: true });
          }
        })();
        """#
}
