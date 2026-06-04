package gr.mybook.lunar_3;

import android.graphics.RectF;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;

public class ByteTrackTracker {
    private static final float HIGH_SCORE_THRESHOLD = 0.30f;
    private static final float LOW_SCORE_THRESHOLD = 0.20f;
    private static final float NEW_TRACK_THRESHOLD = 0.30f;
    private static final float HIGH_MATCH_IOU = 0.24f;
    private static final float LOW_MATCH_IOU = 0.16f;
    private static final int MIN_CONFIRM_HITS = 1;
    private static final int TENTATIVE_MAX_MISSING_FRAMES = 2;
    private static final int MAX_MISSING_FRAMES = 18;
    private static final float APPEARANCE_WEIGHT = 0.30f;

    private final List<Track> tracks = new ArrayList<Track>();
    private final TargetReacquisitionManager reacquisitionManager = new TargetReacquisitionManager();
    private final List<Track> recentlyRemovedTracks = new ArrayList<Track>();
    private int nextTrackId = 1;
    private long lastUpdateMs = 0L;

    public List<Track> update(List<DetectionResult> detections,
                              long nowMs,
                              int frameWidth,
                              int frameHeight,
                              Integer preferredTrackId) {
        float dtSeconds = lastUpdateMs == 0L ? (1f / 30f) : Math.max(0.016f, (nowMs - lastUpdateMs) / 1000f);
        lastUpdateMs = nowMs;
        recentlyRemovedTracks.clear();

        for (Track track : tracks) {
            track.predict(dtSeconds, nowMs);
        }

        List<DetectionResult> high = new ArrayList<DetectionResult>();
        List<DetectionResult> low = new ArrayList<DetectionResult>();
        for (DetectionResult detection : detections) {
            detection.setMatched(false);
            if (detection.getScore() >= HIGH_SCORE_THRESHOLD) {
                high.add(detection);
            } else if (detection.getScore() >= LOW_SCORE_THRESHOLD) {
                low.add(detection);
            }
        }

        List<Track> unmatchedTracks = matchDetections(new ArrayList<Track>(tracks), high, nowMs, HIGH_MATCH_IOU);
        matchDetections(unmatchedTracks, low, nowMs, LOW_MATCH_IOU);

        List<Track> reactivatedTracks = reacquisitionManager.reactivateTracks(high, nowMs, preferredTrackId, frameWidth, frameHeight);
        if (!reactivatedTracks.isEmpty()) {
            tracks.addAll(reactivatedTracks);
        }

        for (DetectionResult detection : high) {
            if (!detection.isMatched() && detection.getScore() >= NEW_TRACK_THRESHOLD) {
                tracks.add(new Track(nextTrackId++, detection, nowMs));
            }
        }

        for (Track track : tracks) {
            if (track.getState() == Track.State.TENTATIVE && track.getMissingFrames() > TENTATIVE_MAX_MISSING_FRAMES) {
                track.markRemoved();
            } else if (track.getMissingFrames() > MAX_MISSING_FRAMES) {
                track.markRemoved();
            } else if (track.getMissingFrames() > 0 && track.getState() != Track.State.TENTATIVE) {
                track.markLost();
            }
        }

        Iterator<Track> iterator = tracks.iterator();
        while (iterator.hasNext()) {
            Track track = iterator.next();
            if (track.getState() == Track.State.REMOVED) {
                recentlyRemovedTracks.add(track);
                iterator.remove();
            }
        }

        reacquisitionManager.rememberRemovedTracks(recentlyRemovedTracks, nowMs, preferredTrackId, frameWidth, frameHeight);

        List<Track> snapshot = new ArrayList<Track>(tracks);
        Collections.sort(snapshot, new Comparator<Track>() {
            @Override
            public int compare(Track left, Track right) {
                return left.getId() - right.getId();
            }
        });
        return snapshot;
    }

    private List<Track> matchDetections(List<Track> candidateTracks, List<DetectionResult> detections, long nowMs, float minIou) {
        List<MatchCandidate> candidates = new ArrayList<MatchCandidate>();
        for (Track track : candidateTracks) {
            if (track.getState() == Track.State.REMOVED) {
                continue;
            }
            for (DetectionResult detection : detections) {
                if (detection.isMatched()) {
                    continue;
                }
                float iou = computeIou(track.getBoundingBox(), detection.getBoundingBox());
                if (iou < minIou) {
                    continue;
                }
                float appearance = computeAppearanceSimilarity(track.getAppearanceFeature(), detection.getColorHistogram());
                float totalScore = iou * (1f - APPEARANCE_WEIGHT) + appearance * APPEARANCE_WEIGHT;
                candidates.add(new MatchCandidate(track, detection, totalScore));
            }
        }

        Collections.sort(candidates, new Comparator<MatchCandidate>() {
            @Override
            public int compare(MatchCandidate left, MatchCandidate right) {
                return Float.compare(right.totalScore, left.totalScore);
            }
        });

        List<Track> unmatchedTracks = new ArrayList<Track>(candidateTracks);
        for (MatchCandidate candidate : candidates) {
            if (!unmatchedTracks.contains(candidate.track) || candidate.detection.isMatched()) {
                continue;
            }
            candidate.track.update(candidate.detection, nowMs, MIN_CONFIRM_HITS);
            candidate.detection.setMatched(true);
            unmatchedTracks.remove(candidate.track);
        }
        return unmatchedTracks;
    }

    private float computeIou(RectF a, RectF b) {
        float left = Math.max(a.left, b.left);
        float top = Math.max(a.top, b.top);
        float right = Math.min(a.right, b.right);
        float bottom = Math.min(a.bottom, b.bottom);
        float intersection = Math.max(0f, right - left) * Math.max(0f, bottom - top);
        if (intersection <= 0f) {
            return 0f;
        }
        float union = a.width() * a.height() + b.width() * b.height() - intersection;
        if (union <= 0f) {
            return 0f;
        }
        return intersection / union;
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

    private static class MatchCandidate {
        final Track track;
        final DetectionResult detection;
        final float totalScore;

        MatchCandidate(Track track, DetectionResult detection, float totalScore) {
            this.track = track;
            this.detection = detection;
            this.totalScore = totalScore;
        }
    }
}

