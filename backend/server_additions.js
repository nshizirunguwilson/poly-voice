// ─────────────────────────────────────────────────────────────────────────────
// ADD THIS TO YOUR EXISTING server.js
// ─────────────────────────────────────────────────────────────────────────────

// 1. Add this require at the top of server.js (with your other requires):
const { attachCaptionWebSockets } = require("./captionServer");

// ─────────────────────────────────────────────────────────────────────────────
// 2. Add this new route anywhere in your routes section:
// ─────────────────────────────────────────────────────────────────────────────

/**
 * POST /api/twilio/media-stream-twiml
 *
 * Called by Twilio when a call/room needs a Media Stream.
 * Returns TwiML that tells Twilio to pipe audio to our WebSocket server.
 *
 * Your Flutter app should hit this endpoint when a call starts,
 * then Twilio will connect the audio stream automatically.
 */
app.post("/api/twilio/media-stream-twiml", authenticateToken, (req, res) => {
  const { roomName, speakerName } = req.body;

  if (!roomName) {
    return res.status(400).json({ error: "roomName is required" });
  }

  // The WebSocket URL Twilio will connect to (your deployed server)
  // On Railway/Render this will be wss://your-app.railway.app/media-stream/roomName
  const wsBaseUrl = process.env.SERVER_WS_URL; // e.g. wss://your-app.railway.app
  const streamUrl = `${wsBaseUrl}/media-stream/${encodeURIComponent(roomName)}`;

  // TwiML response — tells Twilio to stream audio to our WebSocket
  const twiml = `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Start>
    <Stream url="${streamUrl}" track="inbound_track">
      <Parameter name="speakerName" value="${speakerName || "Remote"}" />
    </Stream>
  </Start>
  <Pause length="40"/>
</Response>`;

  res.type("text/xml").send(twiml);
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. REPLACE your existing app.listen(...) at the bottom of server.js with this:
// ─────────────────────────────────────────────────────────────────────────────

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`
  ╔══════════════════════════════════════════╗
  ║   🤟 PolyVoice API Server               ║
  ║   Running on http://0.0.0.0:${PORT}        ║
  ║   Environment: ${process.env.NODE_ENV || "development"}          ║
  ╚══════════════════════════════════════════╝
  `);
});

// Attach the caption WebSocket server to the same HTTP server
attachCaptionWebSockets(server);
