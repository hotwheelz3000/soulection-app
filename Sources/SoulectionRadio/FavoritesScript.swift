import Foundation

/// Favorites, listening history and a random-show button: hearts on songs, a sheet with
/// Favorites and History tabs, playlists from either, and a dice in the top bar.
///
/// - History: a song is recorded as soon as it starts playing (like Spotify's
///   Recently played), saved in the app, newest first, with replays moved to the top.
/// - Full player: tap or swipe up on the mini player for a Spotify-style full-screen
///   player (big cover, song, scrubber, previous/play/next, heart, sleep timer, AirPlay).
///   Play/pause is sent straight to the audio as well as through the site, so it's quick.
/// - Mixtape: a cassette in the top bar plays random songs from random shows, endlessly;
///   each song goes straight into Likes and History.
/// - Sleep timer: a zZZ icon in the top bar that pulses while a timer runs. Fixed times run in the app (so they keep
///   going while locked); "End of song" and "End of show" follow playback here.
/// - Dice: picks a random episode from the site's sitemap and home page and plays it
///   from the start (it waits for the new page, presses that show's Play, then 0:00).
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

          // Sleep timer icon: three Z's, small to big, that light up in a wave while it's on.
          var MOON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><g transform="rotate(-10 12 12)"><path class="sr-z sr-z1" d="M1.6 15.4h3.6l-3.6 4.2h3.6"/><path class="sr-z sr-z2" d="M7.4 11.6h4.6l-4.6 5.6h4.6"/><path class="sr-z sr-z3" d="M14.2 7h6.6l-6.6 7.6h6.6"/></g></svg>';

          // Mixtape: a cassette whose reels turn while it plays.
          var CASSETTE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="5" width="20" height="14" rx="2.5"/><path d="M6.5 19l1.4-3.2h8.2l1.4 3.2"/><g class="sr-reel sr-reel1"><circle cx="8" cy="11" r="2.1"/><path d="M8 9.4v3.2M6.6 11h2.8"/></g><g class="sr-reel sr-reel2"><circle cx="16" cy="11" r="2.1"/><path d="M16 9.4v3.2M14.6 11h2.8"/></g><path d="M10.1 11h3.8"/></svg>';

          var CLOUD = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17.5 19a4.5 4.5 0 1 0-1.4-8.8A6 6 0 0 0 4.3 13 3 3 0 0 0 6 19z"/></svg>';

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
            '.sr-auto{display:flex;align-items:center;gap:10px;margin-top:10px;font-size:12px;line-height:16px;color:' + MUTED + '}',
            '.sr-auto .sr-auto-text{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-auto .sr-auto-text b{color:' + TEXT + ';font-weight:600}',
            '.sr-auto .sr-btn{padding:7px 12px;font-size:13px;line-height:18px;gap:6px;flex:none}',
            '.sr-auto .sr-btn svg{width:15px;height:15px}',
            '.sr-tape-top{font-size:25px;padding:8px;margin:0 -4px 0 0;flex:none;align-self:center}',
            '.sr-tape-top[aria-pressed="true"]{color:#fff}',
            '.sr-tape-top[aria-pressed="true"] svg{fill:none}',
            '.sr-reel{transform-box:fill-box;transform-origin:center}',
            '.sr-tape-top[aria-pressed="true"] .sr-reel{animation:sr-spin 2.4s linear infinite}',
            '.sr-tape-top[aria-busy="true"] .sr-reel{animation:sr-spin .8s linear infinite}',
            // Favorites | History switch at the top of the sheet.
            '.sr-tabs{display:flex;gap:18px;align-items:baseline}',
            '.sr-tabbtn{-webkit-appearance:none;appearance:none;background:none;border:0;padding:0;margin:0;font-family:' + FONT + ';font-size:18px;line-height:24px;font-weight:600;color:' + MUTED + ';cursor:pointer;-webkit-tap-highlight-color:transparent}',
            '.sr-tabbtn[aria-pressed="true"]{color:' + TEXT + '}',
            '.sr-clear[hidden]{display:none}',
            // Sleep timer: moon in the top bar (with time left) and its panel.
            '.sr-moon-top{font-size:25px;padding:8px;margin:0 -4px 0 0;flex:none;align-self:center;gap:4px}',
            '.sr-moon-top[aria-pressed="true"]{color:#fff}',
            '.sr-moon-top[aria-pressed="true"] svg{fill:none}',
            '.sr-moon-top[aria-pressed="true"] .sr-z{animation:sr-zz 1.8s ease-in-out infinite}',
            '.sr-moon-top[aria-pressed="true"] .sr-z2{animation-delay:.3s}',
            '.sr-moon-top[aria-pressed="true"] .sr-z3{animation-delay:.6s}',
            '@keyframes sr-zz{0%,100%{opacity:.4}45%{opacity:1}}',
            '.sr-sleep .sr-sheet{min-height:0}',
            '.sr-sleep-title{font-size:13px;line-height:18px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:' + MUTED + ';margin:0}',
            '.sr-sleep-status{font-size:12px;line-height:16px;color:' + MUTED + ';margin-top:3px}',
            '.sr-sleep-count{display:block;font-size:40px;line-height:46px;font-weight:600;color:#fff;font-variant-numeric:tabular-nums;letter-spacing:-.01em;margin-top:4px}',
            '.sr-sleep-row{display:flex;align-items:center;gap:12px;width:100%;min-height:52px;padding:0;margin:0;background:none;border:0;border-bottom:1px solid ' + BORDER + ';-webkit-appearance:none;appearance:none;font-family:' + FONT + ';font-size:17px;line-height:22px;color:' + TEXT + ';text-align:left;cursor:pointer;-webkit-tap-highlight-color:transparent}',
            '.sr-sleep-row:last-child{border-bottom:0}',
            '.sr-sleep-row:active{background:' + HOVER + '}',
            '.sr-sleep-row[aria-current="true"]{font-weight:600}',
            '.sr-sleep-row .sr-grow{flex:1}',
            '.sr-step{display:inline-flex;align-items:center;justify-content:center;width:38px;height:38px;border-radius:9999px;border:1px solid ' + BORDER + ';background:none;color:' + TEXT + ';font-size:22px;line-height:1;padding:0;-webkit-appearance:none;appearance:none;cursor:pointer}',
            '.sr-step:active{background:' + HOVER + '}',
            '.sr-sleep-off{color:' + TEXT + ';font-weight:600}',
            // Full-size player.
            '.sr-np{position:fixed;inset:0;z-index:45;background:' + BG + ';color:' + TEXT + ';font-family:' + FONT + ';overflow:hidden;transform:translate3d(0,100%,0);will-change:transform;-webkit-user-select:none;user-select:none}',
            '.sr-np-morph{position:fixed;z-index:46;object-fit:cover;pointer-events:none;box-shadow:0 18px 40px rgba(0,0,0,.45);will-change:left,top,width,height}',
            '.sr-np[hidden]{display:none}',
            '.sr-np-bg{position:absolute;inset:-60px;background-size:cover;background-position:center;filter:blur(50px) saturate(1.2);opacity:.35;pointer-events:none}',
            '.sr-np-bg::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(26,26,26,.2) 0%,rgba(26,26,26,.85) 55%,' + BG + ' 100%)}',
            '.sr-np-inner{position:relative;height:100%;box-sizing:border-box;display:flex;flex-direction:column;padding:calc(env(safe-area-inset-top) + 6px) 24px calc(env(safe-area-inset-bottom) + 18px)}',
            '.sr-np-top{display:flex;align-items:center;gap:8px;flex:none}',
            '.sr-np-from{flex:1;min-width:0;text-align:center}',
            '.sr-np-from-label{font-size:11px;line-height:14px;letter-spacing:.08em;text-transform:uppercase;color:' + MUTED + '}',
            '.sr-np-show{font-size:13px;line-height:18px;font-weight:600;color:' + TEXT + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-np-icon{-webkit-appearance:none;appearance:none;background:none;border:0;margin:0;padding:8px;color:' + TEXT + ';display:inline-flex;align-items:center;justify-content:center;cursor:pointer;-webkit-tap-highlight-color:transparent;flex:none;font-size:26px;line-height:1}',
            '.sr-np-icon svg{width:1em;height:1em;display:block}',
            '.sr-np-icon:active{opacity:.6}',
            '.sr-np-spacer{width:42px}',
            '.sr-np-art{flex:1;min-height:0;display:flex;align-items:center;justify-content:center;padding:18px 0}',
            '.sr-np-cover{width:100%;max-width:min(100%,52vh);aspect-ratio:1;object-fit:cover;border-radius:6px;box-shadow:0 18px 40px rgba(0,0,0,.5);background:' + TRACK + '}',
            '.sr-np-meta{display:flex;align-items:center;gap:12px;flex:none}',
            '.sr-np-text{flex:1;min-width:0}',
            '.sr-np-title{font-size:22px;line-height:28px;font-weight:600;color:#fff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-np-artist{font-size:16px;line-height:22px;color:' + TEXT + ';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
            '.sr-np-meta .sr-heart{font-size:26px;padding:8px;margin-right:-8px;flex:none}',
            '.sr-np-meta .sr-heart[hidden]{display:none}',
            '.sr-np-bar{flex:none;padding:16px 0 4px;touch-action:none}',
            '.sr-np-track{position:relative;height:4px;border-radius:9999px;background:' + TRACK + '}',
            '.sr-np-fill{position:absolute;left:0;top:0;bottom:0;border-radius:9999px;background:#fff}',
            '.sr-np-knob{position:absolute;top:50%;width:12px;height:12px;margin:-6px 0 0 -6px;border-radius:9999px;background:#fff;transition:transform .15s}',
            '.sr-np-scrubbing .sr-np-knob{transform:scale(1.4)}',
            '.sr-np-times{display:flex;justify-content:space-between;margin-top:8px;font-size:12px;line-height:16px;color:' + MUTED + ';font-variant-numeric:tabular-nums}',
            '.sr-np-controls{flex:none;display:flex;align-items:center;justify-content:space-between;padding:10px 12px 6px}',
            '.sr-np-controls .sr-np-icon{font-size:36px;color:#fff}',
            '.sr-np-play{-webkit-appearance:none;appearance:none;width:72px;height:72px;border-radius:9999px;border:0;padding:0;margin:0;background:#fff;color:' + BG + ';display:inline-flex;align-items:center;justify-content:center;cursor:pointer;-webkit-tap-highlight-color:transparent;transition:transform .12s}',
            '.sr-np-play:active{transform:scale(.92)}',
            '.sr-np-play svg{width:34px;height:34px;display:block}',
            '.sr-np-extras{flex:none;display:flex;justify-content:space-between;padding-top:8px}',
            '.sr-np-extras .sr-np-icon{font-size:24px}',
            '.sr-np-sleep[aria-pressed="true"]{color:#fff}',
            '.sr-np-sleep[aria-pressed="true"] .sr-z{animation:sr-zz 1.8s ease-in-out infinite}',
            '.sr-np-sleep[aria-pressed="true"] .sr-z2{animation-delay:.3s}',
            '.sr-np-sleep[aria-pressed="true"] .sr-z3{animation-delay:.6s}',
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
          var history = [];
          var autoBackup = { on: false }; // from the app: {on, folder, lastSaved, error, restoreOffer}   // songs listened to, oldest first (favoritedAt = when played)
          var resumeAfterLoad = null; // playlist to continue once the app has sent the favorites
          var sheet = null; // {root, backdrop, panel, list, sub, playBtn, shuffleBtn}
          var tab = null;
          var dice = null;
          var moon = null;
          var tape = null;
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
          function lookup(source, id) {
            if (source === 'history') return historyById(id);
            if (source === 'mixtape') {
              var items = (playlist && playlist.items) || [];
              for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i];
              return null;
            }
            return byId(id);
          }
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
          // Listening history: a song is saved as soon as it starts playing.
          // ---------------------------------------------------------------------------
          var listen = null; // {track, played: seconds heard so far, last: ms, done}
          function followListening(st) {
            if (direct && playlist && playlist.current) {
              var f = playlist.current;
              if (arriving || (listen && listen.track.id === f.id && listen.done)) return;
              listen = { track: f, done: true, played: 0, last: Date.now(), lastT: st && st.t };
              var entry = {};
              for (var k in f) entry[k] = f[k];
              entry.favoritedAt = Date.now();
              history = history.filter(function (h) { return h.id !== entry.id; }).concat([entry]);
              native({ op: 'played', favorite: entry });
              schedule();
              return;
            }
            var t = currentTrack();
            if (!t || !st) { listen = null; return; }
            var now = Date.now();
            if (!listen || listen.track.id !== t.id) listen = { track: t, played: 0, last: now, lastT: st.t, done: false };
            // Count time only while it's actually playing (the position must be moving too,
            // in case the player hasn't reported paused/playing).
            var moving = st.t != null && listen.lastT != null && st.t > listen.lastT;
            var playing = st.paused === false || (st.paused == null && moving);
            listen.last = now;
            listen.lastT = st.t;
            // Saved the moment it starts playing, like Spotify's Recently played, but only
            // once playback is really inside this song's timestamps (not the intro before the
            // first song), and not while a playlist or Mixtape is still jumping to its song
            // (playback can pass over the neighbouring songs on the way).
            if (listen.done || !playing) return;
            var inRange = st.t != null && st.t >= t.start - 0.5 && (t.end == null || st.t < t.end);
            if (!inRange) return;
            if (playlist && (arriving || !playlist.current || playlist.current.id !== t.id)) return;
            listen.done = true;
            var entry = {};
            for (var k in t) entry[k] = t[k];
            entry.start = Number(entry.start) || 0;
            entry.cover = entry.cover || '';
            entry.favoritedAt = now;
            history = history.filter(function (h) { return h.id !== entry.id; }).concat([entry]);
            native({ op: 'played', favorite: entry });
            schedule();
          }

          window.__soulectionFavorites = {
            toast: function (message) { showToast(message); },
            sleepFired: function () { sleep = null; saveSleep(); renderMoon(); },
            receive: function (list, opts) {
              favorites = Array.isArray(list) ? list : [];
              if (opts && Array.isArray(opts.history)) history = opts.history;
              if (opts && opts.autoBackup) {
                autoBackup = opts.autoBackup;
                if (autoBackup.restoreOffer) offerRestore();
              }
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
            if (reminded || autoBackup.on) return;
            reminded = true;
            var n = showNote(
              '<div class="sr-note-title">Back up your favorites?</div>' +
              '<div>Turn on auto-backup to iCloud Drive and your Likes and History are kept even if the app is deleted.</div>' +
              '<div class="sr-actions"></div>', 0);
            if (!n) { reminded = false; return; }
            var actions = n.querySelector('.sr-actions');
            var onBtn = el('button', 'sr-btn', CLOUD + '<span>Turn on</span>');
            var laterBtn = el('button', 'sr-btn', '<span>Later</span>');
            onBtn.type = laterBtn.type = 'button';
            onBtn.addEventListener('click', function () { hideNote(); native({ op: 'backupFolder' }); });
            laterBtn.addEventListener('click', function () { hideNote(); native({ op: 'backupLater' }); });
            actions.appendChild(onBtn);
            actions.appendChild(laterBtn);
          }

          // After a reinstall (nothing saved yet), offer to bring a backup back.
          var restoreShown = false;
          function offerRestore() {
            if (restoreShown) return;
            restoreShown = true;
            setTimeout(function () {
              var n = showNote(
                '<div class="sr-note-title">Restore your Likes and History?</div>' +
                '<div>If you had auto-backup on, pick your backup file (Soulection Radio Backup.json, e.g. in iCloud Drive). Everything comes back and auto-backup keeps going.</div>' +
                '<div class="sr-actions"></div>', 0);
              if (!n) return;
              var actions = n.querySelector('.sr-actions');
              var pickBtn = el('button', 'sr-btn', IMPORT + '<span>Pick backup file</span>');
              var noBtn = el('button', 'sr-btn', '<span>Not now</span>');
              pickBtn.type = noBtn.type = 'button';
              pickBtn.addEventListener('click', function () { hideNote(); native({ op: 'restoreBackup' }); });
              noBtn.addEventListener('click', function () { hideNote(); native({ op: 'restoreDismissed' }); });
              actions.appendChild(pickBtn);
              actions.appendChild(noBtn);
            }, 1500);
          }

          function renderAutoBackup() {
            if (!sheet || !sheet.autoText) return;
            var html, btn;
            if (autoBackup.on) {
              var when = autoBackup.lastSaved ? ' · saved ' + ago(autoBackup.lastSaved).toLowerCase() : '';
              html = autoBackup.error
                ? 'Auto-backup: <b>can\'t reach ' + esc(autoBackup.folder || 'folder') + '</b>'
                : 'Auto-backup: <b>on</b> · ' + esc(autoBackup.folder || '') + esc(when);
              btn = 'Change';
            } else {
              html = 'Auto-backup: <b>off</b>';
              btn = 'Turn on';
            }
            if (sheet.autoText.innerHTML !== html) sheet.autoText.innerHTML = html;
            var span = sheet.autoBtn.querySelector('span');
            if (span.textContent !== btn) span.textContent = btn;
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

          function pageRows(doc) {
            var rows = (doc || document).querySelectorAll('.col-span-full.grid');
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

          // The site's × (close) button on the mini player: found by its label or text, or as
          // a small button sitting on the card's top-right corner.
          function hideMiniClose(player) {
            var scope = player.parentElement || player;
            var pr = player.getBoundingClientRect();
            var play = sitePlayButton();
            var btns = scope.querySelectorAll('button');
            for (var i = 0; i < btns.length; i++) {
              var b = btns[i];
              if (b === play || b.closest('.sr-fav-root') || /\bsr-/.test(b.className || '')) continue;
              if (b.getAttribute('data-sr-hidden')) continue;
              var label = (b.getAttribute('aria-label') || '') + ' ' + (b.textContent || '');
              var r = b.getBoundingClientRect();
              var cornerish = r.width > 0 && r.width <= 48 && r.height <= 48 &&
                Math.abs(r.right - pr.right) < 36 && Math.abs(r.top - pr.top) < 36;
              if (/close|dismiss|×|✕/i.test(label) || (cornerish && b !== play && !b.closest('[role="slider"]'))) {
                b.setAttribute('data-sr-hidden', '1');
                b.style.setProperty('display', 'none', 'important');
              }
            }
          }
          // On iPad the site shows the mini player as a small card in the corner; make it
          // span the bottom edge like on iPhone.
          function fullWidthMini(player) {
            if (window.innerWidth < 640) {
              if (player.getAttribute('data-sr-full')) {
                ['left', 'right', 'bottom', 'width', 'max-width', 'border-radius', 'margin', 'transform'].forEach(function (p) { player.style.removeProperty(p); });
                player.removeAttribute('data-sr-full');
              }
              return;
            }
            if (player.getAttribute('data-sr-full')) return;
            player.setAttribute('data-sr-full', '1');
            var set = function (p, v) { player.style.setProperty(p, v, 'important'); };
            set('left', '0'); set('right', '0'); set('bottom', '0'); set('width', 'auto');
            set('max-width', 'none'); set('border-radius', '0'); set('margin', '0'); set('transform', 'none');
          }

          function renderMiniPlayer(player) {
            if (!player) return;
            hideMiniClose(player);
            fullWidthMini(player);
            if (!player.querySelector(':scope > .sr-grab')) {
              var g = el('button', 'sr-grab');
              g.type = 'button';
              g.setAttribute('aria-label', 'Open player');
              g.addEventListener('click', function (e) { e.stopPropagation(); openPlayer(); });
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
            var auto = el('div', 'sr-auto', '<span class="sr-auto-text"></span>');
            var autoBtn = el('button', 'sr-btn', CLOUD + '<span></span>');
            autoBtn.type = 'button';
            autoBtn.addEventListener('click', function () { native({ op: 'backupFolder' }); });
            auto.appendChild(autoBtn);
            head.appendChild(auto);
            var list = el('div', 'sr-list');
            panel.appendChild(head);
            panel.appendChild(list);
            root.appendChild(backdrop);
            root.appendChild(panel);
            document.body.appendChild(root);
            backdrop.addEventListener('click', closeSheet);
            sheet = { root: root, backdrop: backdrop, panel: panel, head: head, list: list, sub: sub, playBtn: playBtn, shuffleBtn: shuffleBtn, clearBtn: clearBtn, favTab: favTab, histTab: histTab, autoText: auto.querySelector('.sr-auto-text'), autoBtn: autoBtn, mode: 'favorites', key: '' };
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
            renderAutoBackup();
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
            if (!moon) {
              moon = heartButton('sr-moon-top');
              moon.innerHTML = MOON;
              moon.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); openSleep(); });
            }
            if (!tape) {
              tape = heartButton('sr-tape-top');
              tape.innerHTML = CASSETTE;
              tape.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); toggleMixtape(); });
            }
            if (tape.previousElementSibling !== dice) box.parentElement.insertBefore(tape, dice.nextSibling);
            if (moon.previousElementSibling !== tape) box.parentElement.insertBefore(moon, tape.nextSibling);
            renderTape();
            renderMoon();
          }

          // ---------------------------------------------------------------------------
          // Sleep timer
          // ---------------------------------------------------------------------------
          var SLEEP_KEY = 'sr-sleep';
          var CUSTOM_KEY = 'sr-sleep-custom';
          var sleep = null;      // {type: 'time', endsAt} | {type: 'song', id} | {type: 'show', number}
          var sleepPanel = null; // {root, list, status}
          var sleepTick = null;
          try { sleep = JSON.parse(sessionStorage.getItem(SLEEP_KEY) || 'null'); } catch (e) {}
          if (sleep && sleep.type === 'time' && sleep.endsAt <= Date.now()) sleep = null;
          var customMinutes = 45;
          try { customMinutes = Math.min(720, Math.max(5, parseInt(localStorage.getItem(CUSTOM_KEY), 10) || 45)); } catch (e) {}

          function saveSleep() {
            try { if (sleep) sessionStorage.setItem(SLEEP_KEY, JSON.stringify(sleep)); else sessionStorage.removeItem(SLEEP_KEY); } catch (e) {}
          }
          function durationLabel(min) {
            var h = Math.floor(min / 60), m = min % 60;
            var parts = [];
            if (h) parts.push(h + (h === 1 ? ' hour' : ' hours'));
            if (m || !h) parts.push(m + (m === 1 ? ' minute' : ' minutes'));
            return parts.join(', ');
          }
          function clock(sec) {
            sec = Math.max(0, Math.ceil(sec));
            var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
            var mm = (h && m < 10 ? '0' : '') + m;
            return (h ? h + ':' : '') + mm + ':' + (s < 10 ? '0' : '') + s;
          }
          function sleepText() {
            if (!sleep) return '';
            if (sleep.type === 'time') return clock((sleep.endsAt - Date.now()) / 1000);
            return sleep.type === 'song' ? 'Song' : 'Show';
          }
          function renderMoon() {
            if (!moon) return;
            var on = !!sleep;
            if (moon.getAttribute('aria-pressed') !== String(on)) moon.setAttribute('aria-pressed', String(on));
            var label = on ? 'Sleep timer on, ' + (sleep.type === 'time' ? sleepText() + ' left' : 'stops at the end of the ' + (sleep.type === 'song' ? 'song' : 'show')) : 'Sleep timer';
            if (moon.getAttribute('aria-label') !== label) moon.setAttribute('aria-label', label);
            if (sleepPanel && sleepPanel.root.classList.contains('sr-open')) renderSleepStatus();
          }
          function startTick() {
            if (sleepTick) return;
            sleepTick = setInterval(function () {
              if (!sleep) { clearInterval(sleepTick); sleepTick = null; }
              renderMoon();
            }, 1000);
          }

          function setSleep(next) {
            sleep = next;
            saveSleep();
            if (sleep && sleep.type === 'time') native({ op: 'sleepStart', seconds: (sleep.endsAt - Date.now()) / 1000 });
            else native({ op: 'sleepCancel' });
            if (sleep) startTick();
            renderMoon();
          }
          function startTimer(minutes) { setSleep({ type: 'time', endsAt: Date.now() + minutes * 60000 }); closeSleep(); showToast('Sleep timer: ' + durationLabel(minutes) + '.'); }
          function stopAfterSong() {
            var t = currentTrack();
            if (!t) return showToast('Play a song from a show first.');
            setSleep({ type: 'song', id: t.id, end: t.end });
            closeSleep();
            showToast('Stopping at the end of this song.');
          }
          function stopAfterShow() {
            var st = npState();
            if (!st || !st.number) return showToast('Play a show first.');
            setSleep({ type: 'show', number: st.number });
            closeSleep();
            showToast('Stopping at the end of this show.');
          }
          function sleepNow() {
            setSleep(null);
            endPlaylist(false); // so a playlist or Mixtape can't start the next song
            native({ op: 'sleepNow' });
            var n = np();
            n && n.pause();
            showToast('Sleep timer: paused.');
          }
          // "End of song" / "End of show" follow playback.
          var SLEEP_FADE = 15; // seconds of fade before "End of song" / "End of show"
          function followSleep(st) {
            if (!sleep || sleep.type === 'time' || !st) return;
            // Start fading a little before the end.
            if (!sleep.fading && st.t != null && st.paused === false) {
              var end = sleep.type === 'song' ? sleep.end : st.duration;
              var left = end != null ? end - st.t : null;
              if (left != null && left > 0.5 && left <= SLEEP_FADE) {
                sleep.fading = true;
                saveSleep();
                native({ op: 'sleepFade', seconds: left });
              }
            }
            if (sleep.type === 'song') {
              var t = currentTrack();
              var past = sleep.end != null && st.t != null && st.t >= sleep.end - 0.6;
              if (past || (t && t.id !== sleep.id) || (!t && st.index != null && st.index >= 0)) sleepNow();
            } else if (sleep.type === 'show') {
              var ended = st.duration && st.t != null && st.t >= st.duration - 1;
              if (ended || (st.number && st.number !== sleep.number)) sleepNow();
            }
          }

          function buildSleep() {
            if (sleepPanel || !document.body) return;
            var root = el('div', 'sr-fav-root sr-sleep');
            var backdrop = el('div', 'sr-backdrop');
            var panel = el('div', 'sr-sheet');
            panel.setAttribute('role', 'dialog');
            panel.setAttribute('aria-label', 'Sleep timer');
            backdrop.hidden = panel.hidden = true;
            var head = el('div', 'sr-sheet-head');
            head.appendChild(el('div', 'sr-sheet-grab'));
            head.appendChild(el('h2', 'sr-sleep-title', 'Sleep timer'));
            var status = el('div', 'sr-sleep-status');
            head.appendChild(status);
            var list = el('div', 'sr-list');
            panel.appendChild(head);
            panel.appendChild(list);
            root.appendChild(backdrop);
            root.appendChild(panel);
            document.body.appendChild(root);
            backdrop.addEventListener('click', closeSleep);
            // Swipe down to close.
            var y0 = 0, dy = 0, dragging = false;
            panel.addEventListener('touchstart', function (e) { y0 = e.touches[0].clientY; dy = 0; dragging = list.scrollTop <= 0; }, { passive: true });
            panel.addEventListener('touchmove', function (e) {
              if (!dragging) return;
              dy = Math.max(0, e.touches[0].clientY - y0);
              if (dy > 0) { panel.style.transition = 'none'; panel.style.transform = 'translateY(' + dy + 'px)'; }
            }, { passive: true });
            panel.addEventListener('touchend', function () {
              panel.style.transition = '';
              if (dragging && dy > 90) closeSleep(); else panel.style.transform = '';
            });
            sleepPanel = { root: root, backdrop: backdrop, panel: panel, list: list, status: status };
          }
          function row(label, onTap, extra) {
            var r = el('button', 'sr-sleep-row', '<span class="sr-grow">' + esc(label) + '</span>');
            r.type = 'button';
            r.addEventListener('click', onTap);
            if (extra) extra(r);
            return r;
          }
          function renderSleepStatus() {
            if (!sleepPanel) return;
            var html = !sleep ? 'Off'
              : sleep.type === 'time' ? '<span class="sr-sleep-count">' + esc(sleepText()) + '</span>left · fades out at the end'
              : sleep.type === 'song' ? 'Fades out at the end of this song' : 'Fades out at the end of this show';
            if (sleepPanel.status.innerHTML !== html) sleepPanel.status.innerHTML = html;
          }
          function renderSleep() {
            var list = sleepPanel.list;
            list.textContent = '';
            if (sleep) {
              var off = row('Turn off timer', function () { setSleep(null); closeSleep(); showToast('Sleep timer off.'); });
              off.classList.add('sr-sleep-off');
              list.appendChild(off);
            }
            [5, 15, 30, 60].forEach(function (m) {
              list.appendChild(row(m === 60 ? '1 hour' : m + ' minutes', function () { startTimer(m); }));
            });
            var songRow = row('End of song', stopAfterSong);
            if (sleep && sleep.type === 'song') songRow.setAttribute('aria-current', 'true');
            list.appendChild(songRow);
            var showRow = row('End of show', stopAfterShow);
            if (sleep && sleep.type === 'show') showRow.setAttribute('aria-current', 'true');
            list.appendChild(showRow);
            // Custom time: tap the label to start, -/+ change it by 5 minutes.
            var custom = row(durationLabel(customMinutes), function () { startTimer(customMinutes); }, function (r) {
              [['−', -5, 'Less time'], ['+', 5, 'More time']].forEach(function (b) {
                var step = el('span', 'sr-step', b[0]);
                step.setAttribute('role', 'button');
                step.setAttribute('aria-label', b[2]);
                step.addEventListener('click', function (e) {
                  e.stopPropagation();
                  customMinutes = Math.min(720, Math.max(5, customMinutes + b[1]));
                  try { localStorage.setItem(CUSTOM_KEY, String(customMinutes)); } catch (err) {}
                  r.querySelector('.sr-grow').textContent = durationLabel(customMinutes);
                });
                r.appendChild(step);
              });
            });
            list.appendChild(custom);
            renderSleepStatus();
          }
          function openSleep() {
            buildSleep();
            if (!sleepPanel) return;
            closeSheet();
            renderSleep();
            sleepPanel.backdrop.hidden = sleepPanel.panel.hidden = false;
            sleepPanel.panel.style.transform = '';
            document.documentElement.classList.add('sr-lock');
            void sleepPanel.panel.offsetHeight;
            sleepPanel.root.classList.add('sr-open');
          }
          function closeSleep() {
            if (!sleepPanel || !sleepPanel.root.classList.contains('sr-open')) return;
            sleepPanel.root.classList.remove('sr-open');
            sleepPanel.panel.style.transform = '';
            document.documentElement.classList.remove('sr-lock');
            setTimeout(function () {
              if (sleepPanel.root.classList.contains('sr-open')) return;
              sleepPanel.backdrop.hidden = sleepPanel.panel.hidden = true;
            }, 300);
          }
          if (sleep) {
            // Page reloaded while a timer was running: make sure the app's timer matches.
            if (sleep.type === 'time') native({ op: 'sleepStart', seconds: (sleep.endsAt - Date.now()) / 1000 });
            startTick();
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
          function episodeHeading() { return text(document.querySelector('#episode-card-header h1')); }
          function goTo(path, storeKey, storeValue) {
            if (location.pathname.replace(/\/$/, '') === path) return true;
            if (window.next && window.next.router && window.next.router.push) {
              window.next.router.push(path);
              return true;
            }
            try { sessionStorage.setItem(storeKey, storeValue); } catch (e) {}
            location.assign(path);
            return false; // the page reloads; it picks up again from sessionStorage
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
              closePlayer();
              var oldHeading = here === path ? null : episodeHeading();
              if (goTo(path, RANDOM_KEY, path)) startShowFromTop(path, oldHeading);
            });
          }
          // Waits for the new episode page to replace the old one, presses that show's own
          // Play button, then makes sure it starts at 0:00.
          function startShowFromTop(path, oldHeading) {
            var deadline = Date.now() + 15000;
            (function tryPlay() {
              var heading = episodeHeading();
              var ready = location.pathname.replace(/\/$/, '') === path && heading && heading !== oldHeading;
              if (ready) {
                var header = document.querySelector('#episode-card-header');
                var scope = (header && header.parentElement) || document.querySelector('main') || document.body;
                var btns = scope.querySelectorAll('button');
                var play = null;
                for (var i = 0; i < btns.length && !play; i++) {
                  var b = btns[i];
                  if (b.closest('.sr-fav-root, .col-span-full.grid') || b.classList.contains('sr-heart')) continue;
                  if (/^\s*play\s*$/i.test(b.textContent || '')) play = b;
                }
                if (!play) {
                  var rows = pageRows();
                  play = rows.length ? rows[0].row.querySelector(':scope > button') : null;
                }
                if (play) {
                  play.click();
                  ensureFromStart(showNumber(heading));
                  return;
                }
              }
              if (Date.now() < deadline) setTimeout(tryPlay, 250);
              else showToast("Couldn't start that show.");
            })();
          }
          // If the site resumes where you left off, jump back to the beginning.
          function ensureFromStart(number) {
            var deadline = Date.now() + 10000;
            (function check() {
              var st = npState();
              if (st && st.number === number && st.t != null) {
                if (st.t > 3) { var n = np(); n && n.seek(0); }
                return;
              }
              if (Date.now() < deadline) setTimeout(check, 300);
            })();
          }

          // ---------------------------------------------------------------------------
          // Mixtape: endless random songs from random shows. Each one goes straight into
          // Likes and History.
          // ---------------------------------------------------------------------------
          var MIX_KEY = 'sr-mixtape-pending';
          var mixNext = null; // a promise for the next song, fetched ahead of time
          function isMixtape() { return !!(playlist && playlist.source === 'mixtape'); }
          function renderTape() {
            if (!tape) return;
            var on = isMixtape();
            if (tape.getAttribute('aria-pressed') !== String(on)) tape.setAttribute('aria-pressed', String(on));
            var label = on ? 'Stop Mixtape' : 'Start Mixtape';
            if (tape.getAttribute('aria-label') !== label) tape.setAttribute('aria-label', label);
          }
          // Picks a random song (not a voice-over, and not the last song) from a random show.
          function randomSong(tries) {
            tries = tries || 0;
            return loadEpisodes().then(function (paths) {
              if (!paths.length) throw new Error('no shows');
              var path = paths[Math.floor(Math.random() * paths.length)];
              return fetch(path, { credentials: 'same-origin' }).then(function (r) { return r.text(); }).then(function (html) {
                var doc = new DOMParser().parseFromString(html, 'text/html');
                var rows = pageRows(doc);
                var picks = [];
                for (var i = 0; i < rows.length - 1; i++) if (!rows[i].vo) picks.push(i);
                if (!picks.length) throw new Error('no tracklist');
                var i2 = picks[Math.floor(Math.random() * picks.length)];
                var row = rows[i2];
                var h1 = doc.querySelector('#episode-card-header h1, main h1');
                var number = showNumber(text(h1));
                if (!number) throw new Error('no show number');
                var img = doc.querySelector('#episode-card-header img');
                var cover = img ? (img.getAttribute('src') || '') : '';
                if (cover && cover.charAt(0) === '/') cover = location.origin + cover;
                var item = {
                  id: favId(path, row.start), song: row.song, artist: row.artist, show: 'Show #' + number,
                  episodeURL: path, cover: cover, start: row.start, end: rows[i2 + 1].start, favoritedAt: Date.now()
                };
                episodeAudio[path] = soundcloudLink(doc);
                return item;
              });
            }).catch(function (err) {
              if (tries < 4) return randomSong(tries + 1);
              throw err;
            });
          }
          function prefetchMix() { mixNext = randomSong(); mixNext.catch(function () {}); }
          function toggleMixtape() {
            if (isMixtape()) { endPlaylist(true); showToast('Mixtape off.'); return; }
            if (tape.getAttribute('aria-busy') === 'true') return;
            tape.setAttribute('aria-busy', 'true');
            closeSheet();
            closePlayer();
            randomSong().then(function (item) {
              tape.removeAttribute('aria-busy');
              endPlaylist(false);
              playlist = { ids: [item.id], items: [item], pos: 0, mode: 'mixtape', source: 'mixtape', current: null };
              showToast('Mixtape on. Every song goes into your Likes.');
              playCurrent();
              prefetchMix();
            }).catch(function () {
              tape.removeAttribute('aria-busy');
              showToast("Couldn't start Mixtape.");
            });
          }
          // Adds the next random song to the Mixtape and plays it.
          function mixtapeAdvance() {
            var list = playlist;
            var pending = mixNext || randomSong();
            mixNext = null;
            pending.then(function (item) {
              if (playlist !== list) return; // stopped meanwhile
              list.items.push(item);
              list.ids.push(item.id);
              list.pos = list.ids.length - 1;
              playCurrent();
              prefetchMix();
            }).catch(function () { if (playlist === list) endPlaylist(true); });
          }
          // Every Mixtape song goes straight into Likes (History records it as it plays).
          function mixtapeLike(f) {
            if (byId(f.id)) return;
            var fav = {};
            for (var k in f) fav[k] = f[k];
            fav.favoritedAt = Date.now();
            toggle(fav);
          }

          // Swipe up on the mini player to open the full player, like Spotify.
          function attachOpenGesture() {
            var y0 = null, x0 = 0, mode = null, track = null;
            document.addEventListener('touchstart', function (e) {
              y0 = null; mode = null;
              if (e.touches.length !== 1 || isOpen() || isPlayerOpen()) return;
              var t = e.target;
              var player = miniPlayer();
              var onPlayer = player && player.contains(t) && !(t.closest && t.closest('[data-orientation="horizontal"], [role="slider"]'));
              if (!onPlayer) return;
              y0 = e.touches[0].clientY; x0 = e.touches[0].clientX;
              track = velocityTracker();
              track.add(y0);
            }, { passive: true, capture: true });
            // The player follows the finger as it slides up, like Spotify.
            document.addEventListener('touchmove', function (e) {
              if (y0 == null) return;
              var y = e.touches[0].clientY, dy = y - y0, dx = e.touches[0].clientX - x0;
              if (!mode) {
                if (Math.abs(dy) < 8 && Math.abs(dx) < 8) return;
                mode = dy < 0 && Math.abs(dy) > Math.abs(dx) ? 'open' : 'other';
                if (mode === 'open' && !beginPlayerDrag()) mode = 'other';
              }
              if (mode !== 'open') return;
              e.preventDefault();
              track.add(y);
              setProgress(Math.max(0, Math.min(1, -dy / window.innerHeight)));
            }, { passive: false, capture: true });
            document.addEventListener('touchend', function () {
              if (y0 == null) return;
              y0 = null;
              if (mode !== 'open') return;
              mode = null;
              settlePlayer(-track.velocity() / window.innerHeight);
            }, { passive: true, capture: true });
            // Tapping the mini player (anywhere but its buttons and slider) opens it too,
            // and play/pause goes straight to the audio so it reacts right away.
            document.addEventListener('click', function (e) {
              var player = miniPlayer();
              var t = e.target;
              if (!player || !t || !t.closest || !player.contains(t)) return;
              var btn = t.closest('button, a, input, [role="slider"], [data-orientation="horizontal"]');
              if (btn) {
                // Play/pause goes straight to the audio only; the site's button follows
                // along from the player's play/pause events.
                if (btn === sitePlayButton() && fastPlayPause()) { e.preventDefault(); e.stopPropagation(); }
                return;
              }
              e.preventDefault();
              e.stopPropagation();
              openPlayer();
            }, true);
          }

          // ---------------------------------------------------------------------------
          // Snappier play/pause
          // ---------------------------------------------------------------------------
          var optimistic = null; // {paused, until} shown right after a tap, before the player confirms
          function sitePlayButton() {
            var player = miniPlayer();
            var row = player && player.querySelector('.content-col');
            row = row && row.parentElement && row.parentElement.parentElement;
            return row ? row.querySelector(':scope > button:not(.sr-heart)') : null;
          }
          function isPaused() {
            if (optimistic && Date.now() < optimistic.until) return optimistic.paused;
            var st = npState();
            return !st || st.paused !== false;
          }
          // Sends play/pause straight to the audio in the player. Returns false when the
          // player hasn't reported its state yet, so the site's own button handles it.
          function fastPlayPause() {
            var st = npState();
            var n = np();
            if (!st || st.paused == null || !n || !n.play) return false;
            var wantPause = !isPaused();
            if (wantPause) n.pause(); else n.play();
            optimistic = { paused: wantPause, until: Date.now() + 1500 };
            renderPlayer();
            return true;
          }
          function togglePlay() {
            if (fastPlayPause()) return;
            var btn = sitePlayButton();
            if (btn) btn.click();
          }

          // ---------------------------------------------------------------------------
          // Full-size player (tap or swipe up on the mini player)
          // ---------------------------------------------------------------------------
          var fp = null; // full player elements
          var fpTimer = null;
          var scrubbing = null; // {t} while dragging the progress bar
          var PREV = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 5h2v14H6zM20 5v14L9.5 12z"/></svg>';
          var NEXT = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16 5h2v14h-2zM4 5v14l10.5-7z"/></svg>';
          var PLAYBIG = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13l10.5-6.5z"/></svg>';
          var PAUSEBIG = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"/></svg>';
          var CHEVRON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>';
          var AIRPLAY = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1"/><path d="m12 15 5 6H7z"/></svg>';

          function isPlayerOpen() { return !!(fp && fp.root.classList.contains('sr-open')); }
          function bigCover(src) {
            if (!src) return '';
            return src.replace(/([?&])w=\d+/, '$1w=1080').replace(/-(large|t\d+x\d+)\./, '-t500x500.');
          }
          function miniShowLine() {
            var player = miniPlayer();
            var lines = player ? player.querySelectorAll('.content-col > div') : [];
            return lines.length ? text(lines[0]) : '';
          }

          function buildPlayer() {
            if (fp || !document.body) return;
            var root = el('div', 'sr-fav-root sr-np');
            root.hidden = true;
            root.setAttribute('role', 'dialog');
            root.setAttribute('aria-label', 'Now playing');
            root.innerHTML =
              '<div class="sr-np-bg"></div>' +
              '<div class="sr-np-inner">' +
                '<div class="sr-np-top">' +
                  '<button type="button" class="sr-np-icon sr-np-close" aria-label="Close player">' + CHEVRON + '</button>' +
                  '<div class="sr-np-from"><div class="sr-np-from-label">Playing from</div><div class="sr-np-show"></div></div>' +
                  '<span class="sr-np-icon sr-np-spacer"></span>' +
                '</div>' +
                '<div class="sr-np-art"><img class="sr-np-cover" alt=""></div>' +
                '<div class="sr-np-meta"><div class="sr-np-text"><div class="sr-np-title"></div><div class="sr-np-artist"></div></div></div>' +
                '<div class="sr-np-bar"><div class="sr-np-track"><div class="sr-np-fill"></div><div class="sr-np-knob"></div></div>' +
                  '<div class="sr-np-times"><span class="sr-np-elapsed">0:00</span><span class="sr-np-left">-0:00</span></div></div>' +
                '<div class="sr-np-controls">' +
                  '<button type="button" class="sr-np-icon sr-np-prev" aria-label="Previous song">' + PREV + '</button>' +
                  '<button type="button" class="sr-np-play" aria-label="Play"></button>' +
                  '<button type="button" class="sr-np-icon sr-np-next" aria-label="Next song">' + NEXT + '</button>' +
                '</div>' +
                '<div class="sr-np-extras">' +
                  '<button type="button" class="sr-np-icon sr-np-sleep" aria-label="Sleep timer">' + MOON + '</button>' +
                  '<button type="button" class="sr-np-icon sr-np-airplay" aria-label="AirPlay">' + AIRPLAY + '</button>' +
                '</div>' +
              '</div>';
            document.body.appendChild(root);
            fp = {
              root: root, bg: root.querySelector('.sr-np-bg'), show: root.querySelector('.sr-np-show'),
              cover: root.querySelector('.sr-np-cover'), title: root.querySelector('.sr-np-title'),
              artist: root.querySelector('.sr-np-artist'), meta: root.querySelector('.sr-np-meta'),
              track: root.querySelector('.sr-np-track'), fill: root.querySelector('.sr-np-fill'),
              knob: root.querySelector('.sr-np-knob'), elapsed: root.querySelector('.sr-np-elapsed'),
              left: root.querySelector('.sr-np-left'), play: root.querySelector('.sr-np-play'),
              sleep: root.querySelector('.sr-np-sleep'), heart: heartButton('sr-np-heart')
            };
            fp.meta.appendChild(fp.heart);
            root.querySelector('.sr-np-close').addEventListener('click', closePlayer);
            fp.play.addEventListener('click', togglePlay);
            root.querySelector('.sr-np-prev').addEventListener('click', previousSong);
            root.querySelector('.sr-np-next').addEventListener('click', nextSong);
            fp.sleep.addEventListener('click', function () { openSleep(); });
            root.querySelector('.sr-np-airplay').addEventListener('click', function () { native({ op: 'airplay' }); });
            fp.heart.addEventListener('click', function () {
              var t = currentTrack();
              if (t) { t.favoritedAt = Date.now(); toggle(t); renderPlayer(); }
            });
            attachScrub();
            attachPlayerDrag();
          }

          // Opening and closing are driven by a progress value p (0 = closed, 1 = open)
          // with spring physics, and the cover art grows out of the mini player's thumbnail.
          var fpP = 0, fpV = 0, fpAnim = null, morph = null;
          function velocityTracker() {
            var pts = [];
            return {
              add: function (y) { var t = performance.now(); pts.push({ y: y, t: t }); while (pts.length > 2 && t - pts[0].t > 100) pts.shift(); },
              velocity: function () { // px per second, positive = downwards
                if (pts.length < 2) return 0;
                var a = pts[0], b = pts[pts.length - 1];
                return b.t > a.t ? (b.y - a.y) / ((b.t - a.t) / 1000) : 0;
              }
            };
          }
          function thumbRect() {
            var player = miniPlayer();
            var img = player && player.querySelector('img');
            var r = img && img.getBoundingClientRect();
            return r && r.width ? r : null;
          }
          function finalCoverRect() {
            var prev = fp.root.style.transform;
            fp.root.style.transform = 'none';
            var r = fp.cover.getBoundingClientRect();
            fp.root.style.transform = prev;
            return r.width ? r : null;
          }
          function startMorph() {
            endMorph();
            var from = thumbRect(), to = finalCoverRect();
            if (!from || !to || !fp.cover.getAttribute('src')) return;
            var img = el('img', 'sr-np-morph');
            img.alt = '';
            img.src = fp.cover.currentSrc || fp.cover.src;
            document.body.appendChild(img);
            fp.cover.style.visibility = 'hidden';
            morph = { img: img, from: from, to: to };
          }
          function endMorph() {
            if (!morph) return;
            morph.img.remove();
            morph = null;
            if (fp) fp.cover.style.visibility = '';
          }
          function setProgress(p) {
            fpP = p;
            fp.root.style.transform = 'translate3d(0,' + ((1 - p) * window.innerHeight).toFixed(1) + 'px,0)';
            if (!morph) return;
            var e = Math.max(0, Math.min(1, p)), f = morph.from, t = morph.to;
            var st = morph.img.style;
            st.left = (f.left + (t.left - f.left) * e) + 'px';
            st.top = (f.top + (t.top - f.top) * e) + 'px';
            st.width = (f.width + (t.width - f.width) * e) + 'px';
            st.height = (f.height + (t.height - f.height) * e) + 'px';
            st.borderRadius = (2 + 4 * e) + 'px';
          }
          function animateTo(target, velocity, done) {
            cancelAnimationFrame(fpAnim);
            fpV = velocity || 0;
            var last = performance.now();
            var k = 340, c = 2 * Math.sqrt(k) * 0.9; // a quick spring with a hint of bounce
            function step(now) {
              var dt = Math.min(0.032, (now - last) / 1000);
              last = now;
              fpV += (-k * (fpP - target) - c * fpV) * dt;
              var p = fpP + fpV * dt;
              if (Math.abs(p - target) < 0.002 && Math.abs(fpV) < 0.03) {
                setProgress(target);
                fpAnim = null;
                if (done) done();
                return;
              }
              setProgress(Math.max(-0.03, Math.min(1.03, p)));
              fpAnim = requestAnimationFrame(step);
            }
            fpAnim = requestAnimationFrame(step);
          }
          // Shows the player (at the current progress) so a drag or animation can move it.
          function beginPlayerDrag() {
            if (!miniPlayer()) return false;
            buildPlayer();
            if (!fp) return false;
            cancelAnimationFrame(fpAnim);
            if (!isPlayerOpen()) {
              closeSheet();
              fp.root.hidden = false;
              fp.root.classList.add('sr-open');
              document.documentElement.classList.add('sr-lock');
              renderPlayer();
              setProgress(0);
              clearInterval(fpTimer);
              fpTimer = setInterval(renderPlayer, 250);
            }
            startMorph();
            setProgress(fpP);
            return true;
          }
          // Lets go of a drag: open or close depending on where it is and how fast it moves.
          function settlePlayer(velocity) {
            var open = velocity > 0.6 || (velocity > -0.6 && fpP > 0.35);
            animateTo(open ? 1 : 0, velocity, open ? endMorph : finishClose);
          }
          function openPlayer() {
            if (isPlayerOpen() && fpP > 0.99) return;
            if (!beginPlayerDrag()) return;
            animateTo(1, 0, endMorph);
          }
          function closePlayer() {
            if (!isPlayerOpen()) return;
            startMorph();
            setProgress(fpP);
            animateTo(0, 0, finishClose);
          }
          function finishClose() {
            endMorph();
            if (!fp) return;
            fp.root.classList.remove('sr-open');
            fp.root.hidden = true;
            fpP = 0;
            document.documentElement.classList.remove('sr-lock');
            clearInterval(fpTimer);
            fpTimer = null;
          }

          function songBounds(st) {
            if (!st || !st.tracks || st.index == null || st.index < 0) return null;
            var cur = st.tracks[st.index];
            var nxt = st.tracks[st.index + 1];
            return cur ? { start: cur.start, end: nxt ? nxt.start : st.duration } : null;
          }
          function nextSong() {
            if (playlist) return nextFavorite();
            var st = npState();
            if (!st || !st.tracks || st.t == null) return;
            for (var i = 0; i < st.tracks.length; i++) {
              if (st.tracks[i].start > st.t + 1) { np().seek(st.tracks[i].start); return; }
            }
          }
          function previousSong() {
            if (playlist) return previousFavorite();
            var st = npState();
            if (!st || !st.tracks || st.t == null) return;
            var i = -1;
            for (var j = 0; j < st.tracks.length; j++) if (st.tracks[j].start <= st.t + 0.25) i = j;
            // Like Spotify: restart the song unless it just started.
            if (i >= 0 && st.t - st.tracks[i].start > 3) return np().seek(st.tracks[i].start);
            np().seek(i > 0 ? st.tracks[i - 1].start : 0);
          }

          function renderPlayer() {
            if (!fp || !isPlayerOpen()) return;
            if (!miniPlayer()) return closePlayer();
            var st = npState() || {};
            var t = currentTrack();
            var song = t ? t.song : (st.title || '');
            var artist = t ? t.artist : (st.artist || '');
            if (playlist && playlist.current) { song = playlist.current.song; artist = playlist.current.artist; }
            if (fp.title.textContent !== song) fp.title.textContent = song;
            if (fp.artist.textContent !== artist) fp.artist.textContent = artist;
            var show = miniShowLine() || st.show || '';
            if (fp.show.textContent !== show) fp.show.textContent = show;
            var cover = bigCover(st.cover || '');
            if (cover && fp.cover.getAttribute('src') !== cover) {
              fp.cover.src = cover;
              fp.cover.onerror = function () { if (st.cover && fp.cover.src !== st.cover) fp.cover.src = st.cover; };
              fp.bg.style.backgroundImage = 'url("' + cover.replace(/"/g, '%22') + '")';
            }
            fp.heart.hidden = !t;
            if (t) setHeart(fp.heart, !!byId(t.id), t.song);
            var paused = isPaused();
            var icon = paused ? 'play' : 'pause';
            if (fp.play.getAttribute('data-icon') !== icon) {
              fp.play.setAttribute('data-icon', icon);
              fp.play.innerHTML = paused ? PLAYBIG : PAUSEBIG;
              fp.play.setAttribute('aria-label', paused ? 'Play' : 'Pause');
            }
            fp.sleep.setAttribute('aria-pressed', sleep ? 'true' : 'false');
            var dur = st.duration || 0;
            var pos = scrubbing ? scrubbing.t : (st.t || 0);
            var frac = dur ? Math.min(1, Math.max(0, pos / dur)) : 0;
            fp.fill.style.width = (frac * 100) + '%';
            fp.knob.style.left = (frac * 100) + '%';
            fp.elapsed.textContent = clock(pos).replace(/^0(\d:)/, '$1');
            fp.left.textContent = '-' + clock(Math.max(0, dur - pos)).replace(/^0(\d:)/, '$1');
          }

          // Drag the progress bar to move through the show.
          function attachScrub() {
            function at(x) {
              var r = fp.track.getBoundingClientRect();
              var st = npState() || {};
              var frac = Math.min(1, Math.max(0, (x - r.left) / r.width));
              return frac * (st.duration || 0);
            }
            fp.track.parentElement.addEventListener('touchstart', function (e) {
              e.stopPropagation();
              scrubbing = { t: at(e.touches[0].clientX) };
              fp.root.classList.add('sr-np-scrubbing');
              renderPlayer();
            }, { passive: true });
            fp.track.parentElement.addEventListener('touchmove', function (e) {
              if (!scrubbing) return;
              e.preventDefault();
              e.stopPropagation();
              scrubbing.t = at(e.touches[0].clientX);
              renderPlayer();
            }, { passive: false });
            function end() {
              if (!scrubbing) return;
              var target = scrubbing.t;
              fp.root.classList.remove('sr-np-scrubbing');
              var n = np();
              n && n.seek(target);
              setTimeout(function () { scrubbing = null; }, 600); // let the player catch up
              renderPlayer();
            }
            fp.track.parentElement.addEventListener('touchend', end);
            fp.track.parentElement.addEventListener('touchcancel', end);
            fp.track.parentElement.addEventListener('click', function (e) {
              if ('ontouchstart' in window) return;
              var n = np();
              n && n.seek(at(e.clientX));
            });
          }

          // Swipe down anywhere (except the progress bar) to close.
          function attachPlayerDrag() {
            var y0 = 0, x0 = 0, mode = null, track = null;
            fp.root.addEventListener('touchstart', function (e) {
              if (e.touches.length !== 1) return;
              y0 = e.touches[0].clientY; x0 = e.touches[0].clientX; mode = null;
              track = velocityTracker();
              track.add(y0);
            }, { passive: true });
            fp.root.addEventListener('touchmove', function (e) {
              if (scrubbing) return;
              var y = e.touches[0].clientY, ddy = y - y0, ddx = e.touches[0].clientX - x0;
              if (!mode) {
                if (Math.abs(ddy) < 8 && Math.abs(ddx) < 8) return;
                mode = ddy > 0 && Math.abs(ddy) > Math.abs(ddx) ? 'drag' : 'other';
                if (mode === 'drag') beginPlayerDrag();
              }
              if (mode !== 'drag') return;
              e.preventDefault();
              track.add(y);
              setProgress(1 - Math.max(0, ddy) / window.innerHeight);
            }, { passive: false });
            fp.root.addEventListener('touchend', function () {
              if (mode !== 'drag') return;
              mode = null;
              settlePlayer(-track.velocity() / window.innerHeight);
            });
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
            mixNext = null;
            direct = null;
            renderTape();
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
            if (playlist.source === 'mixtape') { mixtapeLike(f); renderTape(); }
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
            if (document.hidden) switchInPlayer(f);
            else openEpisodeAndPlay(f);
          }

          // ---------------------------------------------------------------------------
          // Switching shows while the app is in the background. iOS stops drawing the page
          // then, so opening the next show's page never finishes. Instead, load the show's
          // audio straight into the site's SoundCloud player and jump to the song. The page
          // catches up when the app comes back.
          // ---------------------------------------------------------------------------
          var episodeAudio = {}; // episode path -> SoundCloud link
          var direct = null;     // {number, id} while the player plays a show the page doesn't show
          function soundcloudLink(doc) {
            var a = doc.querySelector('a[href*="soundcloud.com/"]');
            return a ? a.getAttribute('href') : null;
          }
          function audioLink(path) {
            if (episodeAudio[path]) return Promise.resolve(episodeAudio[path]);
            return fetch(path, { credentials: 'same-origin' }).then(function (r) { return r.text(); }).then(function (html) {
              var link = soundcloudLink(new DOMParser().parseFromString(html, 'text/html'));
              if (link) episodeAudio[path] = link;
              return link;
            });
          }
          function soundcloudFrame() {
            return document.querySelector('iframe[src*="w.soundcloud.com"]');
          }
          function switchInPlayer(f) {
            var frame = soundcloudFrame();
            if (!frame || !window.SC || !SC.Widget) return openEpisodeAndPlay(f);
            audioLink(f.episodeURL).then(function (link) {
              if (!playlist || playlist.current !== f) return;
              if (!link) return openEpisodeAndPlay(f);
              var widget = SC.Widget(frame);
              var ms = Math.max(0, f.start) * 1000;
              direct = { number: showNumber(f.show), id: f.id };
              arriving = { id: f.id, since: Date.now(), tries: 1 };
              var onPlay = function () {
                widget.unbind(SC.Widget.Events.PLAY);
                widget.seekTo(ms);
              };
              widget.load(link, {
                auto_play: true,
                callback: function () {
                  widget.bind(SC.Widget.Events.PLAY, onPlay);
                  widget.play();
                  widget.seekTo(ms);
                }
              });
            }).catch(function () { if (playlist && playlist.current === f) openEpisodeAndPlay(f); });
          }
          // Back in the app after a background switch: show the playing show's page and let
          // the site take over from the same spot.
          document.addEventListener('visibilitychange', function () {
            if (document.hidden || !direct || !playlist || !playlist.current) return;
            var f = playlist.current;
            var st = npState();
            var at = st && st.t != null ? st.t : f.start;
            direct = null;
            arriving = { id: f.id, since: Date.now(), tries: 0, at: at };
            openEpisodeAndPlay(f, at);
          });

          // Opens the favorite's episode page and taps its tracklist row, which is how the
          // site itself starts an episode at a song.
          function openEpisodeAndPlay(f, resumeAt) {
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
            var wantNumber = showNumber(f.show);
            (function tryClick() {
              if (!playlist || !arriving || arriving.id !== f.id) return;
              var onPage = location.pathname.replace(/\/$/, '') === f.episodeURL &&
                (!wantNumber || showNumber(episodeHeading()) === wantNumber);
              if (onPage) {
                var rows = pageRows();
                var best = null;
                rows.forEach(function (r) { if (r.start <= f.start + 1 && (!best || r.start > best.start)) best = r; });
                if (best) {
                  var btn = best.row.querySelector(':scope > button');
                  if (btn) {
                    arriving.tries++;
                    arriving.since = Date.now();
                    btn.click();
                    var target = resumeAt != null ? resumeAt : f.start;
                    if (Math.abs(best.start - target) > 1) setTimeout(function () { var n = np(); n && n.seek(target); }, 1500);
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
            // Sleep timer set to "End of song" / "End of show": stop instead of moving on.
            if (sleep && sleep.type !== 'time') return sleepNow();
            if (playlist.source === 'mixtape' && playlist.pos >= playlist.ids.length - 1) return mixtapeAdvance();
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
            // After a background switch the site's mini player still shows the old show,
            // but the player is playing this one.
            var playingNumber = direct && direct.id === f.id ? direct.number : (st && st.number);
            if (arriving) {
              var at = arriving.at != null ? arriving.at : f.start;
              if (st && playingNumber === number && st.t != null && st.t >= at - 2 && st.t <= at + 20) {
                arriving = null;
              } else if (Date.now() - arriving.since > 7000) {
                if (st && playingNumber === number && arriving.tries < 3) {
                  arriving.tries++;
                  arriving.since = Date.now();
                  var n = np();
                  n && n.seek(at);
                } else if (arriving.tries >= 3 || Date.now() - arriving.since > 20000) {
                  endPlaylist(false);
                }
              }
              return;
            }
            if (!st || st.t == null) return;
            if (playingNumber !== number) return endPlaylist(false);
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
            followSleep(e.detail);
            renderPlayer();
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
