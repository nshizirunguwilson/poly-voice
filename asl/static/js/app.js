(function () {
    "use strict";

    // ── State ────────────────────────────────────────────
    const state = {
        mode: "detect",
        collecting: false,
        selectedLetter: "A",
        modelLoaded: false,
        samples: {},
        translatedText: "",

        // Detection stability tracking
        lastDetected: null,
        consecutiveCount: 0,
        cooldown: 0,

        // Settings
        threshold: 70,
        holdFrames: 10,

        // Frame-rate control
        fps: 10,
        lastFrameTime: 0,

        // Socket
        socket: null,
        connected: false,
        processing: false,
    };

    // ── DOM refs ─────────────────────────────────────────
    const $ = (id) => document.getElementById(id);

    const els = {
        webcam: $("webcam"),
        canvas: $("landmark-canvas"),
        handStatus: $("hand-status"),
        currentDetection: $("current-detection"),
        detectedChar: $("detected-char"),
        confidenceFill: $("confidence-fill"),
        confidenceText: $("confidence-text"),
        stabilityFill: $("stability-fill"),
        stabilityText: $("stability-text"),
        textContent: $("text-content"),
        connectionStatus: $("connection-status"),
        noModelWarning: $("no-model-warning"),
        threshold: $("threshold"),
        thresholdVal: $("threshold-val"),
        holdFrames: $("hold-frames"),
        holdVal: $("hold-val"),
        letterGrid: $("letter-grid"),
        currentLetter: $("current-letter"),
        sampleCount: $("sample-count"),
        trainResult: $("train-result"),
        detectPanel: $("detect-panel"),
        collectPanel: $("collect-panel"),
    };

    // MediaPipe hand skeleton connections
    const HAND_CONNECTIONS = [
        [0, 1], [1, 2], [2, 3], [3, 4],
        [0, 5], [5, 6], [6, 7], [7, 8],
        [5, 9], [9, 10], [10, 11], [11, 12],
        [9, 13], [13, 14], [14, 15], [15, 16],
        [13, 17], [17, 18], [18, 19], [19, 20],
        [0, 17],
    ];

    // Off-screen canvas for JPEG capture
    const captureCanvas = document.createElement("canvas");
    const captureCtx = captureCanvas.getContext("2d");

    // ── Initialisation ───────────────────────────────────
    function init() {
        setupWebcam();
        setupSocket();
        setupUI();
        buildLetterGrid();
        requestAnimationFrame(loop);
    }

    async function setupWebcam() {
        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" },
            });
            els.webcam.srcObject = stream;
            els.webcam.addEventListener("loadedmetadata", () => {
                captureCanvas.width = els.webcam.videoWidth;
                captureCanvas.height = els.webcam.videoHeight;
                els.canvas.width = els.webcam.videoWidth;
                els.canvas.height = els.webcam.videoHeight;
            });
        } catch (err) {
            console.error("Webcam error:", err);
            els.handStatus.textContent = "Camera unavailable";
        }
    }

    function setupSocket() {
        state.socket = io();

        state.socket.on("connect", () => {
            state.connected = true;
            els.connectionStatus.textContent = "Connected";
            els.connectionStatus.className = "status connected";
        });

        state.socket.on("disconnect", () => {
            state.connected = false;
            els.connectionStatus.textContent = "Disconnected";
            els.connectionStatus.className = "status disconnected";
        });

        state.socket.on("status", (data) => {
            state.modelLoaded = data.model_loaded;
            state.samples = data.samples || {};
            refreshUI();
        });

        state.socket.on("result", handleResult);
    }

    // ── UI wiring ────────────────────────────────────────
    function setupUI() {
        // Mode tabs
        document.querySelectorAll(".tab").forEach((tab) => {
            tab.addEventListener("click", () => {
                document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
                tab.classList.add("active");
                state.mode = tab.dataset.mode;
                els.detectPanel.classList.toggle("hidden", state.mode !== "detect");
                els.collectPanel.classList.toggle("hidden", state.mode !== "collect");
            });
        });

        // Text actions
        $("btn-space").addEventListener("click", () => { state.translatedText += " "; updateText(); });
        $("btn-backspace").addEventListener("click", () => { state.translatedText = state.translatedText.slice(0, -1); updateText(); });
        $("btn-clear").addEventListener("click", () => { state.translatedText = ""; updateText(); });
        $("btn-copy").addEventListener("click", () => {
            navigator.clipboard.writeText(state.translatedText).catch(() => {});
        });

        // Settings sliders
        els.threshold.addEventListener("input", () => {
            state.threshold = +els.threshold.value;
            els.thresholdVal.textContent = state.threshold + "%";
        });
        els.holdFrames.addEventListener("input", () => {
            state.holdFrames = +els.holdFrames.value;
            els.holdVal.textContent = state.holdFrames;
        });

        // Collect button (hold to collect)
        const btnCollect = $("btn-collect");
        const startCollect = (e) => {
            if (e) e.preventDefault();
            state.collecting = true;
            btnCollect.classList.add("collecting");
            btnCollect.textContent = "Collecting...";
        };
        const stopCollect = () => {
            state.collecting = false;
            btnCollect.classList.remove("collecting");
            btnCollect.textContent = "Hold to Collect";
        };
        btnCollect.addEventListener("mousedown", startCollect);
        btnCollect.addEventListener("mouseup", stopCollect);
        btnCollect.addEventListener("mouseleave", stopCollect);
        btnCollect.addEventListener("touchstart", startCollect);
        btnCollect.addEventListener("touchend", stopCollect);
        btnCollect.addEventListener("touchcancel", stopCollect);

        // Train
        $("btn-train").addEventListener("click", trainModel);

        // Delete
        $("btn-delete").addEventListener("click", () => {
            if (!confirm('Delete all samples for "' + state.selectedLetter + '"?')) return;
            fetch("/api/delete_samples", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ letter: state.selectedLetter }),
            })
                .then((r) => r.json())
                .then((data) => { state.samples = data.samples; refreshUI(); });
        });
    }

    function buildLetterGrid() {
        const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        els.letterGrid.innerHTML = "";
        letters.split("").forEach((letter) => {
            const btn = document.createElement("button");
            btn.className = "letter-btn";
            btn.textContent = letter;
            btn.dataset.letter = letter;
            if (letter === state.selectedLetter) btn.classList.add("selected");
            btn.addEventListener("click", () => {
                document.querySelectorAll(".letter-btn").forEach((b) => b.classList.remove("selected"));
                btn.classList.add("selected");
                state.selectedLetter = letter;
                els.currentLetter.textContent = letter;
                els.sampleCount.textContent = state.samples[letter] || 0;
            });
            els.letterGrid.appendChild(btn);
        });
    }

    // ── Main Loop ────────────────────────────────────────
    function loop(ts) {
        requestAnimationFrame(loop);
        if (ts - state.lastFrameTime < 1000 / state.fps) return;
        state.lastFrameTime = ts;
        if (!state.connected || state.processing) return;
        if (els.webcam.readyState < 2) return;
        sendFrame();
    }

    function sendFrame() {
        captureCtx.drawImage(els.webcam, 0, 0);
        const dataUrl = captureCanvas.toDataURL("image/jpeg", 0.7);
        state.processing = true;
        state.socket.emit("frame", {
            image: dataUrl,
            mode: state.mode === "collect" && state.collecting ? "collect" : "detect",
            letter: state.selectedLetter,
        });
    }

    // ── Result handler ───────────────────────────────────
    function handleResult(data) {
        state.processing = false;
        if (data.error) { console.error("Backend error:", data.error); return; }

        const ctx = els.canvas.getContext("2d");
        ctx.clearRect(0, 0, els.canvas.width, els.canvas.height);

        if (data.landmarks) {
            els.handStatus.textContent = "Hand detected";
            els.handStatus.classList.add("detected");
            drawLandmarks(ctx, data.landmarks);
        } else {
            els.handStatus.textContent = "No hand detected";
            els.handStatus.classList.remove("detected");
            els.currentDetection.classList.add("hidden");
            state.consecutiveCount = 0;
            state.lastDetected = null;
            return;
        }

        // Collection feedback
        if (data.collected) {
            state.samples[state.selectedLetter] = data.sample_count;
            els.sampleCount.textContent = data.sample_count;
            updateLetterGrid();
        }

        // Detection display
        if (state.mode === "detect" && data.letter) {
            updateDetection(data.letter, data.confidence);
        } else if (state.mode !== "detect" || !state.modelLoaded) {
            els.currentDetection.classList.add("hidden");
        }
    }

    function updateDetection(letter, confidence) {
        const pct = Math.round(confidence * 100);
        const above = pct >= state.threshold;

        // Show overlay
        els.currentDetection.classList.remove("hidden");
        els.detectedChar.textContent = letter;
        els.confidenceFill.style.width = pct + "%";
        els.confidenceText.textContent = pct + "%";
        els.confidenceFill.classList.toggle("high", above);

        // Cooldown after accepting a letter
        if (state.cooldown > 0) {
            state.cooldown--;
            els.stabilityFill.style.width = "0%";
            els.stabilityText.textContent = "Wait";
            return;
        }

        // Stability tracking
        if (above && letter === state.lastDetected) {
            state.consecutiveCount++;
        } else if (above) {
            state.lastDetected = letter;
            state.consecutiveCount = 1;
        } else {
            state.consecutiveCount = 0;
            state.lastDetected = null;
        }

        // Stability bar
        const progress = Math.min(state.consecutiveCount / state.holdFrames, 1);
        els.stabilityFill.style.width = (progress * 100) + "%";
        els.stabilityText.textContent = progress < 1 ? "Hold" : "OK";

        // Accept letter when stable enough
        if (state.consecutiveCount >= state.holdFrames) {
            state.translatedText += letter;
            updateText();

            // Visual flash
            els.detectedChar.classList.add("confirmed");
            setTimeout(() => els.detectedChar.classList.remove("confirmed"), 400);

            state.consecutiveCount = 0;
            state.cooldown = 5;
        }
    }

    // ── Drawing ──────────────────────────────────────────
    function drawLandmarks(ctx, landmarks) {
        const w = els.canvas.width;
        const h = els.canvas.height;

        const pts = [];
        for (let i = 0; i < 21; i++) {
            pts.push({ x: landmarks[i * 3] * w, y: landmarks[i * 3 + 1] * h });
        }

        // Connections
        ctx.strokeStyle = "rgba(16, 185, 129, 0.55)";
        ctx.lineWidth = 2;
        HAND_CONNECTIONS.forEach(([a, b]) => {
            ctx.beginPath();
            ctx.moveTo(pts[a].x, pts[a].y);
            ctx.lineTo(pts[b].x, pts[b].y);
            ctx.stroke();
        });

        // Joints
        const fingertips = new Set([4, 8, 12, 16, 20]);
        pts.forEach((p, i) => {
            ctx.beginPath();
            ctx.arc(p.x, p.y, fingertips.has(i) ? 5 : 3, 0, Math.PI * 2);
            ctx.fillStyle = fingertips.has(i) ? "#e94560" : "#10b981";
            ctx.fill();
        });
    }

    // ── UI helpers ───────────────────────────────────────
    function updateText() {
        els.textContent.textContent = state.translatedText;
    }

    function refreshUI() {
        els.noModelWarning.classList.toggle("hidden", state.modelLoaded);
        els.sampleCount.textContent = state.samples[state.selectedLetter] || 0;
        updateLetterGrid();
    }

    function updateLetterGrid() {
        document.querySelectorAll(".letter-btn").forEach((btn) => {
            const count = state.samples[btn.dataset.letter] || 0;
            btn.classList.toggle("has-data", count > 0);
            btn.title = btn.dataset.letter + ": " + count + " samples";
        });
    }

    async function trainModel() {
        const el = els.trainResult;
        el.className = "train-result info";
        el.textContent = "Training model...";
        $("btn-train").disabled = true;

        try {
            const res = await fetch("/api/train", { method: "POST" });
            const data = await res.json();
            if (data.success) {
                el.className = "train-result success";
                el.textContent = data.message;
                state.modelLoaded = true;
                refreshUI();
            } else {
                el.className = "train-result error";
                el.textContent = data.message;
            }
        } catch (err) {
            el.className = "train-result error";
            el.textContent = "Training failed: " + err.message;
        } finally {
            $("btn-train").disabled = false;
        }
    }

    // ── Boot ─────────────────────────────────────────────
    init();
})();
