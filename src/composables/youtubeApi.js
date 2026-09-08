// Share in-flight loads, but never cache a failed load across retries.
export function createYouTubeLoader(win, doc, { timeoutMs = 20000, pollMs = 100 } = {}) {
  let pending;
  return function loadYouTube() {
    if (win.YT?.Player) return Promise.resolve(win.YT);
    if (pending) return pending;
    pending = new Promise((resolve, reject) => {
      let done = false;
      const previous = win.onYouTubeIframeAPIReady;
      const script = doc.createElement('script');
      let timeout, poll;
      const finish = error => {
        if (done) return;
        done = true;
        clearTimeout(timeout);
        clearInterval(poll);
        if (win.onYouTubeIframeAPIReady === ready) win.onYouTubeIframeAPIReady = previous;
        if (error) { script.remove(); reject(error); }
        else resolve(win.YT);
      };
      const ready = () => {
        try { previous?.(); } catch { /* Another widget cannot prevent our initialization. */ }
        if (win.YT?.Player) finish();
      };
      win.onYouTubeIframeAPIReady = ready;
      script.src = 'https://www.youtube.com/iframe_api';
      script.async = true;
      script.referrerPolicy = 'strict-origin-when-cross-origin';
      script.onerror = () => finish(new Error('YouTube’s player script could not load. Retry, or open this room in your regular browser if a content blocker or WebView blocks YouTube.'));
      timeout = setTimeout(() => finish(new Error('YouTube’s player connection timed out. Retry to reconnect, or try your regular browser.')), timeoutMs);
      // Some WebViews or other widgets replace the global readiness callback.
      poll = setInterval(() => { if (win.YT?.Player) finish(); }, pollMs);
      doc.head.append(script);
    }).catch(error => { pending = undefined; throw error; });
    return pending;
  };
}

export function youtubeError(code) {
  return ({
    2: 'YouTube rejected this video ID. Paste its share link again.',
    5: 'YouTube could not decode this video in this browser. Try your regular browser.',
    100: 'This YouTube video is private, removed, or unavailable.',
    101: 'The owner has disabled embedded playback for this YouTube video.',
    150: 'The owner has disabled embedded playback for this YouTube video.',
    153: 'YouTube requires this app’s referrer. Open the room in your regular browser; some WebViews and privacy tools remove it.',
  })[code] || `YouTube could not play this video (error ${code}). Retry or choose another video.`;
}
