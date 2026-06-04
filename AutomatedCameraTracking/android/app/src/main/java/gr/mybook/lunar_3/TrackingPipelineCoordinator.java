package gr.mybook.lunar_3;

import java.util.List;

public class TrackingPipelineCoordinator {
    private final ByteTrackTracker tracker = new ByteTrackTracker();
    private final TargetLockManager targetLockManager = new TargetLockManager();
    private final MotionController motionController = new MotionController();

    public TrackingSnapshot process(List<DetectionResult> detections, int frameWidth, int frameHeight, long nowMs) {
        Integer preferredTrackId = targetLockManager.getLockedTrackId();
        List<Track> tracks = tracker.update(detections, nowMs, frameWidth, frameHeight, preferredTrackId);
        Track target = targetLockManager.selectTarget(tracks, frameWidth, frameHeight, nowMs);

        int panAngle = motionController.holdCurrent();
        boolean predictionOnly = false;
        boolean reacquired = false;
        String status = targetLockManager.isManualLockEnabled() ? "Manual lock: waiting" : "No target";
        if (target != null) {
            predictionOnly = target.getMissingFrames() > 0;
            reacquired = target.wasReactivatedFromMemory();
            panAngle = motionController.updateForTarget(target.getCenterX(), frameWidth, predictionOnly);
            if (reacquired) {
                status = String.format("Target #%d reacquired", target.getId());
            } else {
                status = predictionOnly
                        ? String.format("Target #%d predicted", target.getId())
                        : String.format("Target #%d tracked", target.getId());
            }
        }

        return new TrackingSnapshot(
                tracks,
                detections,
                target,
                panAngle,
                predictionOnly,
                reacquired,
                status,
                targetLockManager.getLockedTrackId(),
                targetLockManager.isManualLockEnabled());
    }

    public void lockToTrack(int trackId) {
        targetLockManager.lockToTrack(trackId);
    }

    public void clearManualLock() {
        targetLockManager.clearManualLock();
    }
}
