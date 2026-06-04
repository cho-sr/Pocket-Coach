package gr.mybook.lunar_3;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class TrackMemoryPool {
    private static final long NORMAL_RETENTION_MS = 6500L;
    private static final long PRIORITY_RETENTION_MS = 12000L;

    private final List<TrackMemoryEntry> entries = new ArrayList<TrackMemoryEntry>();

    public void remember(TrackMemoryEntry entry, long nowMs) {
        prune(nowMs);
        removeByTrackId(entry.getTrackId());
        entries.add(entry);
    }

    public List<TrackMemoryEntry> getEntries(long nowMs) {
        prune(nowMs);
        return new ArrayList<TrackMemoryEntry>(entries);
    }

    public void removeByTrackId(int trackId) {
        Iterator<TrackMemoryEntry> iterator = entries.iterator();
        while (iterator.hasNext()) {
            if (iterator.next().getTrackId() == trackId) {
                iterator.remove();
            }
        }
    }

    private void prune(long nowMs) {
        Iterator<TrackMemoryEntry> iterator = entries.iterator();
        while (iterator.hasNext()) {
            TrackMemoryEntry entry = iterator.next();
            long retentionMs = entry.isPriorityTarget() ? PRIORITY_RETENTION_MS : NORMAL_RETENTION_MS;
            if (nowMs - entry.getLastSeenMs() > retentionMs) {
                iterator.remove();
            }
        }
    }
}
