package gr.mybook.lunar_3;

import android.graphics.RectF;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public class TargetReacquisitionManager {
    private static final float MIN_REACTIVATION_SCORE = 0.58f;
    private static final float PRIORITY_MIN_REACTIVATION_SCORE = 0.48f;

    private final TrackMemoryPool memoryPool = new TrackMemoryPool();

    public List<Track> reactivateTracks(List<DetectionResult> detections,
                                        long nowMs,
                                        Integer preferredTrackId,
                                        int frameWidth,
                                        int frameHeight) {
        List<TrackMemoryEntry> memoryEntries = memoryPool.getEntries(nowMs);
        if (memoryEntries.isEmpty()) {
            return Collections.emptyList();
        }

        List<Track> reactivated = new ArrayList<Track>();
        List<MatchCandidate> candidates = new ArrayList<MatchCandidate>();
        for (DetectionResult detection : detections) {
            if (detection.isMatched()) {
                continue;
            }
            for (TrackMemoryEntry memoryEntry : memoryEntries) {
                float score = computeReactivationScore(memoryEntry, detection, nowMs, preferredTrackId, frameWidth, frameHeight);
                float minScore = memoryEntry.getTrackId() == safeValue(preferredTrackId)
                        ? PRIORITY_MIN_REACTIVATION_SCORE
                        : MIN_REACTIVATION_SCORE;
                if (score >= minScore) {
                    candidates.add(new MatchCandidate(memoryEntry, detection, score));
                }
            }
        }

        Collections.sort(candidates, new Comparator<MatchCandidate>() {
            @Override
            public int compare(MatchCandidate left, MatchCandidate right) {
                return Float.compare(right.score, left.score);
            }
        });

        List<Integer> claimedIds = new ArrayList<Integer>();
        for (MatchCandidate candidate : candidates) {
            if (candidate.detection.isMatched() || claimedIds.contains(candidate.memoryEntry.getTrackId())) {
                continue;
            }
            Track reactivatedTrack = Track.reactivate(candidate.memoryEntry, candidate.detection, nowMs);
            reactivated.add(reactivatedTrack);
            candidate.detection.setMatched(true);
            claimedIds.add(candidate.memoryEntry.getTrackId());
            memoryPool.removeByTrackId(candidate.memoryEntry.getTrackId());
        }
        return reactivated;
    }

    public void rememberRemovedTracks(List<Track> removedTracks,
                                      long nowMs,
                                      Integer preferredTrackId,
                                      int frameWidth,
                                      int frameHeight) {
        for (Track track : removedTracks) {
            boolean priority = track.isLockedTarget()
                    || (preferredTrackId != null && track.getId() == preferredTrackId.intValue());
            memoryPool.remember(track.toMemoryEntry(priority, frameWidth, frameHeight), nowMs);
        }
    }

    private float computeReactivationScore(TrackMemoryEntry memoryEntry,
                                           DetectionResult detection,
                                           long nowMs,
                                           Integer preferredTrackId,
                                           int frameWidth,
                                           int frameHeight) {
        float appearanceScore = computeAppearanceSimilarity(memoryEntry.getAppearanceFeature(), detection.getColorHistogram());
        float sideScore = computeEntrySideScore(memoryEntry.getExitSide(), detection.getBoundingBox(), frameWidth, frameHeight);
        float sizeScore = computeSizeScore(memoryEntry.getLastBoundingBox(), detection.getBoundingBox());
        float ageScore = computeAgeScore(nowMs - memoryEntry.getLastSeenMs(), memoryEntry.isPriorityTarget());
        float priorityBoost = memoryEntry.getTrackId() == safeValue(preferredTrackId) ? 0.15f : 0f;

        return appearanceScore * 0.50f
                + sideScore * 0.20f
                + sizeScore * 0.15f
                + ageScore * 0.15f
                + priorityBoost;
    }

    private float computeAppearanceSimilarity(float[] a, float[] b) {
        if (a == null || b == null || a.length == 0 || b.length == 0 || a.length != b.length) {
            return 0f;
        }
        float intersection = 0f;
        for (int i = 0; i < a.length; i++) {
            intersection += Math.min(a[i], b[i]);
        }
        return intersection;
    }

    private float computeEntrySideScore(TrackMemoryEntry.ExitSide exitSide,
                                        RectF detectionBox,
                                        int frameWidth,
                                        int frameHeight) {
        float centerX = (detectionBox.left + detectionBox.right) * 0.5f;
        float centerY = (detectionBox.top + detectionBox.bottom) * 0.5f;
        float normalizedX = centerX / Math.max(1f, frameWidth);
        float normalizedY = centerY / Math.max(1f, frameHeight);
        switch (exitSide) {
            case LEFT:
                return clamp(1f - normalizedX, 0f, 1f);
            case RIGHT:
                return clamp(normalizedX, 0f, 1f);
            case TOP:
                return clamp(1f - normalizedY, 0f, 1f);
            case BOTTOM:
                return clamp(normalizedY, 0f, 1f);
            case UNKNOWN:
            default:
                return 0.5f;
        }
    }

    private float computeSizeScore(RectF previous, RectF current) {
        float previousArea = Math.max(1f, previous.width() * previous.height());
        float currentArea = Math.max(1f, current.width() * current.height());
        float ratio = Math.min(previousArea, currentArea) / Math.max(previousArea, currentArea);
        return clamp(ratio, 0f, 1f);
    }

    private float computeAgeScore(long ageMs, boolean priorityTarget) {
        float maxAge = priorityTarget ? 12000f : 6500f;
        return clamp(1f - (ageMs / maxAge), 0f, 1f);
    }

    private int safeValue(Integer value) {
        return value == null ? Integer.MIN_VALUE : value.intValue();
    }

    private float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }

    private static class MatchCandidate {
        final TrackMemoryEntry memoryEntry;
        final DetectionResult detection;
        final float score;

        MatchCandidate(TrackMemoryEntry memoryEntry, DetectionResult detection, float score) {
            this.memoryEntry = memoryEntry;
            this.detection = detection;
            this.score = score;
        }
    }
}
