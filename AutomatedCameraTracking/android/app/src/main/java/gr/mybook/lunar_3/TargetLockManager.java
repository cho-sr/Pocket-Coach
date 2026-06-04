package gr.mybook.lunar_3;

import java.util.List;

public class TargetLockManager {
    private static final long MAX_PREDICTION_HOLD_MS = 1200L;
    private static final long MAX_HARD_LOST_MS = 1800L;

    private Integer lockedTrackId;
    private boolean manualLockEnabled;

    public Track selectTarget(List<Track> tracks, int frameWidth, int frameHeight, long nowMs) {
        clearLockFlags(tracks);

        Track lockedTrack = findTrackById(tracks, lockedTrackId);
        if (lockedTrack != null && lockedTrack.getState() != Track.State.REMOVED) {
            long ageMs = nowMs - lockedTrack.getLastUpdateMs();
            if (lockedTrack.getMissingFrames() == 0 || ageMs <= MAX_PREDICTION_HOLD_MS) {
                lockedTrack.setLockedTarget(true);
                return lockedTrack;
            }
            if (ageMs > MAX_HARD_LOST_MS && !manualLockEnabled) {
                lockedTrackId = null;
            }
        }

        if (manualLockEnabled) {
            return null;
        }

        Track best = null;
        float bestScore = Float.NEGATIVE_INFINITY;
        float frameCenterX = frameWidth * 0.5f;
        float frameCenterY = frameHeight * 0.5f;
        for (Track track : tracks) {
            if (!track.isConfirmed() || track.getState() == Track.State.LOST) {
                continue;
            }
            float dx = Math.abs(track.getCenterX() - frameCenterX) / Math.max(1f, frameWidth);
            float dy = Math.abs(track.getCenterY() - frameCenterY) / Math.max(1f, frameHeight);
            float score = track.getScore() - dx * 1.6f - dy * 0.3f;
            if (score > bestScore) {
                bestScore = score;
                best = track;
            }
        }

        if (best != null) {
            lockedTrackId = best.getId();
            best.setLockedTarget(true);
        }
        return best;
    }

    public void lockToTrack(int trackId) {
        lockedTrackId = trackId;
        manualLockEnabled = true;
    }

    public void clearManualLock() {
        manualLockEnabled = false;
        lockedTrackId = null;
    }

    public boolean isManualLockEnabled() {
        return manualLockEnabled;
    }

    public Integer getLockedTrackId() {
        return lockedTrackId;
    }

    private void clearLockFlags(List<Track> tracks) {
        for (Track track : tracks) {
            track.setLockedTarget(false);
        }
    }

    private Track findTrackById(List<Track> tracks, Integer id) {
        if (id == null) {
            return null;
        }
        for (Track track : tracks) {
            if (track.getId() == id.intValue()) {
                return track;
            }
        }
        return null;
    }
}