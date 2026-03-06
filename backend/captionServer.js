/**
 * captionServer.js
 * ================
 * Handles two WebSocket connection types on the SAME server:
 *
 *  1. /media-stream/:roomName  — Twilio sends raw mulaw audio here
 *  2. /captions/:roomName      — Flutter app listens here for transcriptions
 *
 * Flow:
 *   Twilio audio → Google Speech-to-Text → Flutter app
 */

const { WebSocketServer } = require("ws");
const speech = require("@google-cloud/speech");
const url = require("url");

// One Google STT client (reused across calls)
const speechClient = new speech.SpeechClient({
  keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  // OR inline credentials:
  // credentials: JSON.parse(process.env.GOOGLE_CREDENTIALS_JSON),
});

/**
 * Maps roomName → { flutterSockets: Set<WebSocket>, recognizeStream, speakerName }
 * Keeps Twilio and Flutter sockets paired by room.
 */
const rooms = new Map();

function getOrCreateRoom(roomName) {
  if (!rooms.has(roomName)) {
    rooms.set(roomName, {
      flutterSockets: new Set(), // Flutter clients listening for captions
      recognizeStream: null,     // active Google STT stream
      speakerName: "Remote",
    });
  }
  return rooms.get(roomName);
}

function cleanupRoom(roomName) {
  const room = rooms.get(roomName);
  if (room) {
    room.recognizeStream?.destroy();
    rooms.delete(roomName);
    console.log(`[Caption] Room cleaned up: ${roomName}`);
  }
}

/**
 * Starts a Google STT streaming session for a room.
 * Transcripts are broadcast to all Flutter sockets in the room.
 */
function startRecognizeStream(roomName) {
  const room = rooms.get(roomName);
  if (!room || room.recognizeStream) return;

  const recognizeStream = speechClient
    .streamingRecognize({
      config: {
        encoding: "MULAW",          // Twilio Media Streams default encoding
        sampleRateHertz: 8000,       // Twilio default sample rate
        languageCode: "en-US",
        enableAutomaticPunctuation: true,
        model: "phone_call",
        useEnhanced: true,
      },
      interimResults: true,          // send partial captions in real-time
    })
    .on("data", (data) => {
      const result = data.results[0];
      if (!result) return;

      const transcript = result.alternatives[0]?.transcript || "";
      const isFinal = result.isFinal;

      if (!transcript.trim()) return;

      // Broadcast caption to all Flutter sockets in this room
      const payload = JSON.stringify({
        type: "caption",
        roomName,
        speaker: room.speakerName,
        text: transcript,
        isFinal,
      });

      for (const socket of room.flutterSockets) {
        if (socket.readyState === 1 /* OPEN */) {
          socket.send(payload);
        }
      }

      if (isFinal) {
        console.log(`[STT] [${roomName}] Final: "${transcript}"`);
      }
    })
    .on("error", (err) => {
      console.error(`[STT] Error for room ${roomName}:`, err.message);
      // Restart stream on recoverable errors (e.g. 5-minute limit)
      room.recognizeStream = null;
      startRecognizeStream(roomName);
    })
    .on("end", () => {
      console.log(`[STT] Stream ended for room: ${roomName}`);
      room.recognizeStream = null;
    });

  room.recognizeStream = recognizeStream;
  console.log(`[STT] Stream started for room: ${roomName}`);
}

/**
 * Attach WebSocket servers to an existing HTTP server.
 * Call this once from server.js after `app.listen(...)`.
 *
 * @param {import('http').Server} httpServer
 */
function attachCaptionWebSockets(httpServer) {
  const wss = new WebSocketServer({ noServer: true });

  // Upgrade HTTP → WebSocket
  httpServer.on("upgrade", (request, socket, head) => {
    const { pathname } = url.parse(request.url);

    // Only handle our two caption paths
    if (
      pathname.startsWith("/media-stream/") ||
      pathname.startsWith("/captions/")
    ) {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit("connection", ws, request);
      });
    } else {
      socket.destroy(); // not our path — ignore
    }
  });

  wss.on("connection", (ws, request) => {
    const { pathname } = url.parse(request.url);

    // ── 1. Twilio Media Stream connection ──────────────────────
    if (pathname.startsWith("/media-stream/")) {
      const roomName = decodeURIComponent(pathname.replace("/media-stream/", ""));
      handleTwilioConnection(ws, roomName);

    // ── 2. Flutter app caption listener ────────────────────────
    } else if (pathname.startsWith("/captions/")) {
      const roomName = decodeURIComponent(pathname.replace("/captions/", ""));
      handleFlutterConnection(ws, roomName);
    }
  });

  console.log("[Caption] WebSocket server attached ✓");
}

// ─────────────────────────────────────────────────────────────
// Twilio → Server connection
// Twilio sends JSON messages with type "start", "media", or "stop"
// ─────────────────────────────────────────────────────────────
function handleTwilioConnection(ws, roomName) {
  console.log(`[Twilio] Media stream connected for room: ${roomName}`);
  const room = getOrCreateRoom(roomName);

  ws.on("message", (rawMessage) => {
    let msg;
    try {
      msg = JSON.parse(rawMessage);
    } catch {
      return;
    }

    switch (msg.event) {
      case "start":
        // Twilio tells us who is speaking (custom parameter)
        room.speakerName = msg.start?.customParameters?.speakerName || "Remote";
        console.log(`[Twilio] Stream started — speaker: ${room.speakerName}`);
        startRecognizeStream(roomName);
        break;

      case "media":
        // Audio arrives as base64-encoded mulaw payload
        if (room.recognizeStream) {
          const audioBuffer = Buffer.from(msg.media.payload, "base64");
          room.recognizeStream.write(audioBuffer);
        }
        break;

      case "stop":
        console.log(`[Twilio] Stream stopped for room: ${roomName}`);
        room.recognizeStream?.end();
        room.recognizeStream = null;
        // Notify Flutter that speaking stopped
        for (const socket of room.flutterSockets) {
          if (socket.readyState === 1) {
            socket.send(JSON.stringify({ type: "speakingStop", roomName }));
          }
        }
        break;
    }
  });

  ws.on("close", () => {
    console.log(`[Twilio] Connection closed for room: ${roomName}`);
  });

  ws.on("error", (err) => {
    console.error(`[Twilio] WebSocket error (${roomName}):`, err.message);
  });
}

// ─────────────────────────────────────────────────────────────
// Flutter app connection
// Flutter connects here and waits for caption messages
// ─────────────────────────────────────────────────────────────
function handleFlutterConnection(ws, roomName) {
  console.log(`[Flutter] Caption client connected for room: ${roomName}`);
  const room = getOrCreateRoom(roomName);
  room.flutterSockets.add(ws);

  // Send an ack so Flutter knows it's connected
  ws.send(JSON.stringify({ type: "connected", roomName }));

  ws.on("close", () => {
    room.flutterSockets.delete(ws);
    console.log(`[Flutter] Caption client disconnected (${roomName})`);
    // Clean up room if no one is left
    if (room.flutterSockets.size === 0 && !room.recognizeStream) {
      cleanupRoom(roomName);
    }
  });

  ws.on("error", (err) => {
    console.error(`[Flutter] WebSocket error (${roomName}):`, err.message);
  });
}

module.exports = { attachCaptionWebSockets };
