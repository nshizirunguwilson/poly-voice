/**
 * PolyVoice Backend Server
 * ========================
 * Handles authentication, Twilio Video token generation,
 * call signaling, and user management.
 */

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
const Database = require("better-sqlite3");
const twilio = require("twilio");

const http = require("http");
const { Server } = require("socket.io");

const app = express();
const PORT = process.env.PORT || 3000;

// Create HTTP server and attach Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] },
});

// ─── Middleware ───────────────────────────────────────
app.use(helmet());
app.use(cors());
app.use(morgan("dev"));
app.use(express.json());

// ─── Database Setup (SQLite — zero config) ───────────
const db = new Database("polyvoice.db");
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('deaf', 'blind', 'normal')),
    display_name TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_online INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS call_logs (
    id TEXT PRIMARY KEY,
    caller_id TEXT NOT NULL,
    callee_id TEXT NOT NULL,
    room_name TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    started_at DATETIME,
    ended_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (caller_id) REFERENCES users(id),
    FOREIGN KEY (callee_id) REFERENCES users(id)
  );
`);

// ─── Twilio Client ───────────────────────────────────
const AccessToken = twilio.jwt.AccessToken;
const VideoGrant = AccessToken.VideoGrant;

// ─── Auth Middleware ─────────────────────────────────
function authenticateToken(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) return res.status(401).json({ error: "Access token required" });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch {
    return res.status(403).json({ error: "Invalid or expired token" });
  }
}

// ─── Health Check ────────────────────────────────────
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "PolyVoice API",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// AUTH ROUTES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/**
 * POST /api/auth/register
 * Register a new user with role selection
 */
app.post("/api/auth/register", async (req, res) => {
  try {
    const { username, email, password, role, displayName } = req.body;

    if (!username || !email || !password || !role || !displayName) {
      return res.status(400).json({ error: "All fields are required" });
    }

    if (!["deaf", "blind", "normal"].includes(role)) {
      return res.status(400).json({ error: "Role must be: deaf, blind, or normal" });
    }

    // Check existing user
    const existing = db.prepare("SELECT id FROM users WHERE username = ? OR email = ?").get(username, email);
    if (existing) {
      return res.status(409).json({ error: "Username or email already exists" });
    }

    const id = uuidv4();
    const passwordHash = await bcrypt.hash(password, 12);

    db.prepare(`
      INSERT INTO users (id, username, email, password_hash, role, display_name)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, username, email, passwordHash, role, displayName);

    const token = jwt.sign(
      { id, username, role, displayName },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    res.status(201).json({
      message: "Registration successful",
      token,
      user: { id, username, email, role, displayName },
    });
  } catch (err) {
    console.error("Registration error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * POST /api/auth/login
 */
app.post("/api/auth/login", async (req, res) => {
  try {
    const { username, password } = req.body;

    const user = db.prepare("SELECT * FROM users WHERE username = ?").get(username);
    if (!user) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    // Set online
    db.prepare("UPDATE users SET is_online = 1 WHERE id = ?").run(user.id);

    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role, displayName: user.display_name },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role,
        displayName: user.display_name,
      },
    });
  } catch (err) {
    console.error("Login error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * GET /api/auth/me — get current user profile
 */
app.get("/api/auth/me", authenticateToken, (req, res) => {
  const user = db.prepare("SELECT id, username, email, role, display_name, is_online FROM users WHERE id = ?").get(req.user.id);
  if (!user) return res.status(404).json({ error: "User not found" });
  res.json({ user });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// USER ROUTES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/**
 * GET /api/users — list all users (for contact list)
 */
app.get("/api/users", authenticateToken, (req, res) => {
  const users = db
    .prepare("SELECT id, username, display_name, role, is_online FROM users WHERE id != ?")
    .all(req.user.id);
  res.json({ users });
});

/**
 * PATCH /api/users/status — update online status
 */
app.patch("/api/users/status", authenticateToken, (req, res) => {
  const { isOnline } = req.body;
  db.prepare("UPDATE users SET is_online = ? WHERE id = ?").run(isOnline ? 1 : 0, req.user.id);
  res.json({ success: true });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TWILIO VIDEO TOKEN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/**
 * POST /api/twilio/token
 * Generate a Twilio Video access token for a room
 */
app.post("/api/twilio/token", authenticateToken, (req, res) => {
  try {
    const { roomName } = req.body;

    if (!roomName) {
      return res.status(400).json({ error: "roomName is required" });
    }

    const token = new AccessToken(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_API_KEY_SID,
      process.env.TWILIO_API_KEY_SECRET,
      { identity: req.user.username, ttl: 3600 }
    );

    const videoGrant = new VideoGrant({ room: roomName });
    token.addGrant(videoGrant);

    res.json({
      token: token.toJwt(),
      roomName,
      identity: req.user.username,
    });
  } catch (err) {
    console.error("Token generation error:", err);
    res.status(500).json({ error: "Failed to generate token" });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CALL MANAGEMENT
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/**
 * POST /api/calls/initiate — start a call
 */
app.post("/api/calls/initiate", authenticateToken, (req, res) => {
  try {
    const { calleeId } = req.body;
    const callerId = req.user.id;

    if (!calleeId) {
      return res.status(400).json({ error: "calleeId is required" });
    }

    const callee = db.prepare("SELECT id, username, role, display_name FROM users WHERE id = ?").get(calleeId);
    if (!callee) {
      return res.status(404).json({ error: "User not found" });
    }

    const callId = uuidv4();
    const roomName = `polyvoice-${callId}`;

    db.prepare(`
      INSERT INTO call_logs (id, caller_id, callee_id, room_name, status)
      VALUES (?, ?, ?, ?, 'pending')
    `).run(callId, callerId, calleeId, roomName);

    // Generate tokens for both participants
    const callerToken = new AccessToken(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_API_KEY_SID,
      process.env.TWILIO_API_KEY_SECRET,
      { identity: req.user.username, ttl: 3600 }
    );
    callerToken.addGrant(new VideoGrant({ room: roomName }));

    res.json({
      callId,
      roomName,
      token: callerToken.toJwt(),
      callee: {
        id: callee.id,
        username: callee.username,
        role: callee.role,
        displayName: callee.display_name,
      },
    });
  } catch (err) {
    console.error("Call initiation error:", err);
    res.status(500).json({ error: "Failed to initiate call" });
  }
});

/**
 * POST /api/calls/:callId/accept
 */
app.post("/api/calls/:callId/accept", authenticateToken, (req, res) => {
  try {
    const { callId } = req.params;

    const call = db.prepare("SELECT * FROM call_logs WHERE id = ?").get(callId);
    if (!call) return res.status(404).json({ error: "Call not found" });

    db.prepare("UPDATE call_logs SET status = 'active', started_at = CURRENT_TIMESTAMP WHERE id = ?").run(callId);

    // Generate token for callee
    const calleeToken = new AccessToken(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_API_KEY_SID,
      process.env.TWILIO_API_KEY_SECRET,
      { identity: req.user.username, ttl: 3600 }
    );
    calleeToken.addGrant(new VideoGrant({ room: call.room_name }));

    res.json({
      callId,
      roomName: call.room_name,
      token: calleeToken.toJwt(),
    });
  } catch (err) {
    console.error("Call accept error:", err);
    res.status(500).json({ error: "Failed to accept call" });
  }
});

/**
 * POST /api/calls/:callId/end
 */
app.post("/api/calls/:callId/end", authenticateToken, (req, res) => {
  try {
    const { callId } = req.params;

    db.prepare("UPDATE call_logs SET status = 'ended', ended_at = CURRENT_TIMESTAMP WHERE id = ?").run(callId);
    res.json({ success: true, callId });
  } catch (err) {
    console.error("Call end error:", err);
    res.status(500).json({ error: "Failed to end call" });
  }
});

/**
 * GET /api/calls/pending — check for incoming calls
 */
app.get("/api/calls/pending", authenticateToken, (req, res) => {
  const calls = db
    .prepare(`
      SELECT cl.*, u.username as caller_username, u.display_name as caller_name, u.role as caller_role
      FROM call_logs cl
      JOIN users u ON cl.caller_id = u.id
      WHERE cl.callee_id = ? AND cl.status = 'pending'
      ORDER BY cl.created_at DESC
    `)
    .all(req.user.id);

  res.json({ calls });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SOCKET.IO SIGNALING SERVER
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Track which rooms have which sockets
const rooms = new Map(); // roomName -> Set<socketId>

io.on("connection", (socket) => {
  console.log(`[Socket.IO] Client connected: ${socket.id}`);
  let currentRoom = null;

  socket.on("join-room", (data) => {
    const { roomName, username, role } = data;
    currentRoom = roomName;

    socket.join(roomName);
    if (!rooms.has(roomName)) rooms.set(roomName, new Set());
    rooms.get(roomName).add(socket.id);

    console.log(`[Socket.IO] ${username} (${role}) joined room ${roomName} — ${rooms.get(roomName).size} peer(s)`);

    // Notify other peers in the room that a new user joined
    socket.to(roomName).emit("user-joined", { username, role, socketId: socket.id });
  });

  socket.on("offer", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("offer", data);
  });

  socket.on("answer", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("answer", data);
  });

  socket.on("ice-candidate", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("ice-candidate", data);
  });

  socket.on("call-connected", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("call-connected", data);
  });

  socket.on("text-message", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("text-message", data);
  });

  socket.on("partial-speech", (data) => {
    const { roomName } = data;
    socket.to(roomName).emit("partial-speech", data);
  });

  socket.on("leave-room", () => {
    if (currentRoom) {
      socket.to(currentRoom).emit("user-left", { socketId: socket.id });
      socket.leave(currentRoom);
      if (rooms.has(currentRoom)) {
        rooms.get(currentRoom).delete(socket.id);
        if (rooms.get(currentRoom).size === 0) rooms.delete(currentRoom);
      }
      console.log(`[Socket.IO] ${socket.id} left room ${currentRoom}`);
      currentRoom = null;
    }
  });

  socket.on("disconnect", () => {
    if (currentRoom) {
      socket.to(currentRoom).emit("user-left", { socketId: socket.id });
      if (rooms.has(currentRoom)) {
        rooms.get(currentRoom).delete(socket.id);
        if (rooms.get(currentRoom).size === 0) rooms.delete(currentRoom);
      }
    }
    console.log(`[Socket.IO] Client disconnected: ${socket.id}`);
  });
});

// ─── Start Server ────────────────────────────────────
server.listen(PORT, "0.0.0.0", () => {
  console.log(`
  ╔══════════════════════════════════════════╗
  ║   PolyVoice API Server                  ║
  ║   Running on http://0.0.0.0:${PORT}        ║
  ║   Socket.IO signaling: enabled          ║
  ║   Environment: ${process.env.NODE_ENV || "development"}          ║
  ╚══════════════════════════════════════════╝
  `);
});
