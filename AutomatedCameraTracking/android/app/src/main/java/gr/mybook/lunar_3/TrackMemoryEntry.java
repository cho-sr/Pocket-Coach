package gr.mybook.lunar_3;

import android.graphics.RectF;

public class TrackMemoryEntry {
    public enum ExitSide {
        LEFT,
        RIGHT,
        TOP,
        BOTTOM,
        UNKNOWN
    }

    private final int trackId;
    private final RectF lastBoundingBox;
    private final float[] appearanceFeature;
    private final long lastSeenMs;
    private final boolean priorityTarget;
    private final ExitSide exitSide;
    private final float lastScore;

    public TrackMemoryEntry(int trackId,
                            RectF lastBoundingBox,
                            float[] appearanceFeature,
                            long lastSeenMs,
                            boolean priorityTarget,
                            ExitSide exitSide,
                            float lastScore) {
        this.trackId = trackId;
        this.lastBoundingBox = new RectF(lastBoundingBox);
        this.appearanceFeature = appearanceFeature == null ? new float[0] : appearanceFeature.clone();
        this.lastSeenMs = lastSeenMs;
        this.priorityTarget = priorityTarget;
        this.exitSide = exitSide == null ? ExitSide.UNKNOWN : exitSide;
        this.lastScore = lastScore;
    }

    public int getTrackId() {
        return trackId;
    }

    public RectF getLastBoundingBox() {
        return new RectF(lastBoundingBox);
    }

    public float[] getAppearanceFeature() {
        return appearanceFeature.clone();
    }

    public long getLastSeenMs() {
        return lastSeenMs;
    }

    public boolean isPriorityTarget() {
        return priorityTarget;
    }

    public ExitSide getExitSide() {
        return exitSide;
    }

    public float getLastScore() {
        return lastScore;
    }
}
