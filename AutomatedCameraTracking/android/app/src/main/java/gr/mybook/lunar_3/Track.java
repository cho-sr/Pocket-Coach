package gr.mybook.lunar_3;

import android.graphics.RectF;

public class Track {
    public enum State {
        TENTATIVE,
        TRACKED,
        PREDICTED,
        LOST,
        REMOVED
    }

    private final int id;
    private final KalmanTrackFilter kalmanFilter = new KalmanTrackFilter();
    private RectF latestBox;
    private float latestScore;
    private State state = State.TENTATIVE;
    private int hitCount;
    private int age;
    private int missingFrames;
    private long lastUpdateMs;
    private boolean lockedTarget;
    private float[] appearanceFeature;
    private boolean reactivatedFromMemory;

    public Track(int id, DetectionResult detection, long nowMs) {
        this.id = id;
        this.latestBox = detection.getBoundingBox();
        this.latestScore = detection.getScore();
        this.lastUpdateMs = nowMs;
        this.appearanceFeature = detection.getColorHistogram();
        kalmanFilter.initialize(latestBox);
        hitCount = 1;
        age = 1;
    }

    public void predict(float dtSeconds, long nowMs) {
        age++;
        missingFrames++;
        kalmanFilter.predict(dtSeconds);
        latestBox = kalmanFilter.getPredictedBox();
        if (missingFrames > 0 && state != State.TENTATIVE) {
            state = State.PREDICTED;
        }
        lastUpdateMs = nowMs;
        reactivatedFromMemory = false;
    }

    public void update(DetectionResult detection, long nowMs, int minConfirmHits) {
        latestScore = detection.getScore();
        kalmanFilter.correct(detection.getBoundingBox(), latestScore);
        latestBox = kalmanFilter.getPredictedBox();
        appearanceFeature = blendFeature(appearanceFeature, detection.getColorHistogram(), 0.25f);
        hitCount++;
        missingFrames = 0;
        lastUpdateMs = nowMs;
        state = hitCount >= minConfirmHits ? State.TRACKED : State.TENTATIVE;
        reactivatedFromMemory = false;
    }

    public void markLost() {
        if (state != State.REMOVED) {
            state = State.LOST;
        }
    }

    public void markRemoved() {
        state = State.REMOVED;
    }

    public RectF getBoundingBox() {
        return new RectF(latestBox);
    }

    public float getCenterX() {
        return (latestBox.left + latestBox.right) * 0.5f;
    }

    public float getCenterY() {
        return (latestBox.top + latestBox.bottom) * 0.5f;
    }

    public float getScore() {
        return latestScore;
    }

    public int getId() {
        return id;
    }

    public State getState() {
        return state;
    }

    public int getMissingFrames() {
        return missingFrames;
    }

    public int getHitCount() {
        return hitCount;
    }

    public long getLastUpdateMs() {
        return lastUpdateMs;
    }

    public boolean isConfirmed() {
        return state == State.TRACKED || state == State.PREDICTED || state == State.LOST;
    }

    public boolean isLockedTarget() {
        return lockedTarget;
    }

    public void setLockedTarget(boolean lockedTarget) {
        this.lockedTarget = lockedTarget;
    }

    public float[] getAppearanceFeature() {
        return appearanceFeature == null ? new float[0] : appearanceFeature.clone();
    }

    public boolean wasReactivatedFromMemory() {
        return reactivatedFromMemory;
    }

    public TrackMemoryEntry toMemoryEntry(boolean priorityTarget, int frameWidth, int frameHeight) {
        return new TrackMemoryEntry(
                id,
                latestBox,
                appearanceFeature,
                lastUpdateMs,
                priorityTarget,
                inferExitSide(latestBox, frameWidth, frameHeight),
                latestScore);
    }

    public static Track reactivate(TrackMemoryEntry memoryEntry, DetectionResult detection, long nowMs) {
        Track track = new Track(memoryEntry.getTrackId(), detection, nowMs);
        track.hitCount = Math.max(3, track.hitCount);
        track.state = State.TRACKED;
        track.appearanceFeature = track.blendFeature(memoryEntry.getAppearanceFeature(), detection.getColorHistogram(), 0.35f);
        track.reactivatedFromMemory = true;
        return track;
    }

    private TrackMemoryEntry.ExitSide inferExitSide(RectF box, int frameWidth, int frameHeight) {
        float centerX = (box.left + box.right) * 0.5f;
        float centerY = (box.top + box.bottom) * 0.5f;
        float normalizedX = centerX / Math.max(1f, frameWidth);
        float normalizedY = centerY / Math.max(1f, frameHeight);
        if (normalizedX <= 0.18f) {
            return TrackMemoryEntry.ExitSide.LEFT;
        }
        if (normalizedX >= 0.82f) {
            return TrackMemoryEntry.ExitSide.RIGHT;
        }
        if (normalizedY <= 0.18f) {
            return TrackMemoryEntry.ExitSide.TOP;
        }
        if (normalizedY >= 0.82f) {
            return TrackMemoryEntry.ExitSide.BOTTOM;
        }
        return TrackMemoryEntry.ExitSide.UNKNOWN;
    }

    private float[] blendFeature(float[] current, float[] incoming, float alpha) {
        if (incoming == null || incoming.length == 0) {
            return current;
        }
        if (current == null || current.length != incoming.length) {
            return incoming.clone();
        }
        float[] blended = new float[current.length];
        for (int i = 0; i < current.length; i++) {
            blended[i] = current[i] * (1f - alpha) + incoming[i] * alpha;
        }
        return blended;
    }
}
