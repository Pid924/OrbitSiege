// Orbit Siege online glue: a tiny wrapper over PeerJS (WebRTC data channel) that Godot polls.
// Godot calls osNet.host(code) / osNet.join(code) / osNet.send(text) / osNet.poll() / osNet.close().
// The free PeerJS cloud only introduces the two phones; game data then goes phone to phone.
// For local tests: ?peerhost=127.0.0.1&peerport=9000 uses a self-run `peer` server instead.
(function () {
  var PREFIX = "orbitsiege-v1-";
  var peer = null, conn = null, events = [];
  function opts() {
    var q = new URLSearchParams(location.search);
    var o = { debug: 0, config: { iceServers: [
      { urls: "stun:stun.l.google.com:19302" }, { urls: "stun:global.stun.twilio.com:3478" } ] } };
    if (q.get("peerhost")) { o.host = q.get("peerhost"); o.port = +(q.get("peerport") || 9000); o.secure = false; o.path = "/"; }
    return o;
  }
  function push(e) { events.push(e); }
  function wire(c) {
    conn = c;
    c.on("open", function () { push({ t: "conn" }); });
    c.on("data", function (d) { push({ t: "msg", d: String(d) }); });
    c.on("close", function () { push({ t: "close" }); });
    c.on("error", function (e) { push({ t: "err", e: String(e && e.type || e) }); });
  }
  function reset() {
    try { if (conn) conn.close(); } catch (e) {}
    try { if (peer) peer.destroy(); } catch (e) {}
    peer = null; conn = null;
  }
  // Closing the tab: tell the other phone right away instead of letting it time out.
  window.addEventListener("pagehide", function () {
    try { if (conn && conn.open) conn.send(JSON.stringify({ k: "bye" })); } catch (e) {}
  });
  window.osNet = {
    host: function (code) {
      reset(); events = [];
      window.osNet.code = code;
      peer = new Peer(PREFIX + code, opts());
      peer.on("open", function () { push({ t: "open" }); });
      peer.on("connection", function (c) {
        if (conn) { c.close(); return; } // room is full
        wire(c);
      });
      peer.on("error", function (e) { push({ t: "err", e: String(e && e.type || e) }); });
      // Phones drop the signalling socket while the app is in the background (e.g. while the
      // host sends the code in a chat app); just reconnect, the room code stays the same.
      peer.on("disconnected", function () { try { if (peer && !peer.destroyed) peer.reconnect(); } catch (e) {} });
    },
    join: function (code) {
      reset(); events = [];
      peer = new Peer(opts());
      peer.on("open", function () {
        push({ t: "open" });
        wire(peer.connect(PREFIX + code, { reliable: true, serialization: "raw" }));
      });
      peer.on("error", function (e) { push({ t: "err", e: String(e && e.type || e) }); });
    },
    send: function (text) { if (conn && conn.open) conn.send(text); },
    poll: function () { var out = JSON.stringify(events); events = []; return out; },
    close: function () { reset(); events = []; }
  };
})();
