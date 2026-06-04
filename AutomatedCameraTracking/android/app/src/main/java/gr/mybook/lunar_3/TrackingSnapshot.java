package gr.mybook.lunar_3;

import java.util.ArrayList;
import java.util.List;

public class TrackingSnapshot {
    private final List<Track> tracks;
    private final List<DetectionResult> detections;
    private final Track target;
    private final int panAngle;
    private final boolean predictionOnly;
    private final boolean reacquired;
    private final String status;
    private final Integer lockedTrackId;
    private final boolean manualLockEnabled;

    public TrackingSnapshot(List<Track> tracks,
                            List<DetectionResult> detections,
                            Track target,
                            int panAngle,
                            boolean predictionOnly,
                            boolean reacquired,
                            String status,
                            Integer lockedTrackId,
                            boolean manualLockEnabled) {
        this.tracks = new ArrayList<Track>(tracks);
        this.detections = new ArrayList<DetectionResult>(detections);
        this.target = target;
        this.panAngle = panAngle;
        this.predictionOnly = predictionOnly;
        this.reacquired = reacquired;
        this.status = status;
        this.lockedTrackId = lockedTrackId;
        this.manualLockEnabled = manualLockEnabled;
    }

    public List<Track> getTracks() {
        return new ArrayList<Track>(tracks);
    }

    public List<DetectionResult> getDetections() {
        return new ArrayList<DetectionResult>(detections);
    }

    public Track getTarget() {
        return target;
    }

    public int getPanAngle() {
        return panAngle;
    }

    public boolean isPredictionOnly() {
        return predictionOnly;
    }

    public boolean isReacquired() {
        return reacquired;
    }

    public String getStatus() {
        return status;
    }

    public Integer getLockedTrackId() {
        return lockedTrackId;
    }

    public boolean isManualLockEnabled() {
        return manualLockEnabled;
    }
}
