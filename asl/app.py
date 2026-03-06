import base64

import numpy as np
import cv2
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit

from asl_classifier import ASLClassifier

app = Flask(__name__)
app.config["SECRET_KEY"] = "asl-realtime-translator"
socketio = SocketIO(app, cors_allowed_origins="*")

classifier = ASLClassifier()


# ------------------------------------------------------------------
# Pages
# ------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("index.html")


# ------------------------------------------------------------------
# REST API
# ------------------------------------------------------------------

@app.route("/api/train", methods=["POST"])
def train():
    result = classifier.train()
    return jsonify(result)


@app.route("/api/status")
def status():
    return jsonify(
        {
            "model_loaded": classifier.model is not None,
            "samples": classifier.get_sample_counts(),
        }
    )


@app.route("/api/delete_samples", methods=["POST"])
def delete_samples():
    data = request.get_json() or {}
    letter = data.get("letter")
    classifier.delete_samples(letter)
    return jsonify({"success": True, "samples": classifier.get_sample_counts()})


# ------------------------------------------------------------------
# WebSocket events
# ------------------------------------------------------------------

@socketio.on("connect")
def on_connect():
    emit(
        "status",
        {
            "model_loaded": classifier.model is not None,
            "samples": classifier.get_sample_counts(),
        },
    )


@socketio.on("frame")
def handle_frame(data):
    try:
        mode = data.get("mode", "detect")
        letter = data.get("letter")
        image_data = data.get("image", "")

        # Strip the data-URL prefix if present
        if "," in image_data:
            image_data = image_data.split(",", 1)[1]

        img_bytes = base64.b64decode(image_data)
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if frame is None:
            emit("result", {"error": "Invalid frame"})
            return

        landmarks, bbox = classifier.extract_landmarks(frame)

        result = {
            "landmarks": None,
            "bbox": None,
            "letter": None,
            "confidence": 0,
            "collected": False,
            "sample_count": 0,
        }

        if landmarks is not None:
            result["landmarks"] = landmarks
            result["bbox"] = bbox

            if mode == "collect" and letter:
                count = classifier.collect_sample(landmarks, letter)
                result["collected"] = True
                result["sample_count"] = count
            elif mode == "detect" and classifier.model is not None:
                pred, conf = classifier.predict(landmarks)
                result["letter"] = pred
                result["confidence"] = conf

        emit("result", result)

    except Exception as e:
        emit("result", {"error": str(e)})


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 50)
    print("  ASL Real-Time Translator")
    print("  Open http://localhost:8000 in your browser")
    print("=" * 50)
    socketio.run(app, host="0.0.0.0", port=8000, debug=True, allow_unsafe_werkzeug=True)
