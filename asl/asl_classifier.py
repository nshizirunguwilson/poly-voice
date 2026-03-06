import os
import json
import pickle
import threading

import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    HandLandmarker,
    HandLandmarkerOptions,
    RunningMode,
)
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler


class ASLClassifier:
    def __init__(self, data_dir="data", model_dir="model"):
        self.data_dir = data_dir
        self.model_dir = model_dir
        self.model = None
        self.scaler = None
        self._lock = threading.Lock()

        # MediaPipe Tasks hand landmarker
        model_path = os.path.join(model_dir, "hand_landmarker.task")
        options = HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=model_path),
            num_hands=1,
            min_hand_detection_confidence=0.7,
            min_hand_presence_confidence=0.7,
            min_tracking_confidence=0.5,
            running_mode=RunningMode.IMAGE,
        )
        self.landmarker = HandLandmarker.create_from_options(options)

        os.makedirs(data_dir, exist_ok=True)
        os.makedirs(model_dir, exist_ok=True)

        self.load_model()

    # ------------------------------------------------------------------
    # Hand landmark extraction
    # ------------------------------------------------------------------

    def extract_landmarks(self, frame):
        """Return (landmarks_flat_list, bbox_dict) or (None, None)."""
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        with self._lock:
            result = self.landmarker.detect(mp_image)

        if not result.hand_landmarks:
            return None, None

        hand = result.hand_landmarks[0]
        landmarks = []
        xs, ys = [], []

        for lm in hand:
            landmarks.extend([lm.x, lm.y, lm.z])
            xs.append(lm.x)
            ys.append(lm.y)

        bbox = {
            "x": min(xs),
            "y": min(ys),
            "w": max(xs) - min(xs),
            "h": max(ys) - min(ys),
        }
        return landmarks, bbox

    # ------------------------------------------------------------------
    # Feature engineering
    # ------------------------------------------------------------------

    def normalize_landmarks(self, landmarks):
        """Translate to wrist origin, scale by palm size."""
        lm = np.array(landmarks, dtype=np.float64).reshape(21, 3)
        wrist = lm[0].copy()
        lm -= wrist

        scale = np.linalg.norm(lm[9])  # wrist -> middle-finger MCP
        if scale > 0:
            lm /= scale

        return lm.flatten().tolist()

    # ------------------------------------------------------------------
    # Data collection
    # ------------------------------------------------------------------

    def collect_sample(self, landmarks, letter):
        """Append one normalized sample for *letter*. Return new count."""
        normalized = self.normalize_landmarks(landmarks)
        letter = letter.upper()
        filepath = os.path.join(self.data_dir, f"{letter}.json")

        samples = []
        if os.path.exists(filepath):
            with open(filepath, "r") as f:
                samples = json.load(f)

        samples.append(normalized)
        with open(filepath, "w") as f:
            json.dump(samples, f)

        return len(samples)

    def get_sample_counts(self):
        counts = {}
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
            filepath = os.path.join(self.data_dir, f"{letter}.json")
            if os.path.exists(filepath):
                with open(filepath, "r") as f:
                    counts[letter] = len(json.load(f))
            else:
                counts[letter] = 0
        return counts

    def delete_samples(self, letter=None):
        """Delete samples for one letter, or all if letter is None."""
        if letter:
            filepath = os.path.join(self.data_dir, f"{letter.upper()}.json")
            if os.path.exists(filepath):
                os.remove(filepath)
        else:
            for fname in os.listdir(self.data_dir):
                if fname.endswith(".json"):
                    os.remove(os.path.join(self.data_dir, fname))

    # ------------------------------------------------------------------
    # Training
    # ------------------------------------------------------------------

    def train(self):
        X, y = [], []

        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
            filepath = os.path.join(self.data_dir, f"{letter}.json")
            if os.path.exists(filepath):
                with open(filepath, "r") as f:
                    samples = json.load(f)
                X.extend(samples)
                y.extend([letter] * len(samples))

        if len(set(y)) < 2:
            return {
                "success": False,
                "message": "Need samples for at least 2 different letters to train.",
            }

        X = np.array(X)
        y = np.array(y)

        self.scaler = StandardScaler()
        X_scaled = self.scaler.fit_transform(X)

        self.model = RandomForestClassifier(
            n_estimators=150,
            max_depth=20,
            random_state=42,
            n_jobs=-1,
        )
        self.model.fit(X_scaled, y)

        # Persist
        with open(os.path.join(self.model_dir, "model.pkl"), "wb") as f:
            pickle.dump(self.model, f)
        with open(os.path.join(self.model_dir, "scaler.pkl"), "wb") as f:
            pickle.dump(self.scaler, f)

        accuracy = self.model.score(X_scaled, y)
        n_letters = len(set(y))
        return {
            "success": True,
            "message": (
                f"Model trained on {len(X)} samples across {n_letters} letters. "
                f"Training accuracy: {accuracy:.1%}"
            ),
            "accuracy": float(accuracy),
            "n_samples": int(len(X)),
            "n_letters": int(n_letters),
        }

    # ------------------------------------------------------------------
    # Prediction
    # ------------------------------------------------------------------

    def predict(self, landmarks):
        if self.model is None or self.scaler is None:
            return None, 0.0

        normalized = self.normalize_landmarks(landmarks)
        X = np.array([normalized])
        X_scaled = self.scaler.transform(X)

        prediction = self.model.predict(X_scaled)[0]
        proba = self.model.predict_proba(X_scaled)[0]
        confidence = float(max(proba))
        return prediction, confidence

    # ------------------------------------------------------------------
    # Model persistence
    # ------------------------------------------------------------------

    def load_model(self):
        model_path = os.path.join(self.model_dir, "model.pkl")
        scaler_path = os.path.join(self.model_dir, "scaler.pkl")

        if os.path.exists(model_path) and os.path.exists(scaler_path):
            try:
                with open(model_path, "rb") as f:
                    self.model = pickle.load(f)
                with open(scaler_path, "rb") as f:
                    self.scaler = pickle.load(f)
                return True
            except Exception:
                self.model = None
                self.scaler = None
        return False
