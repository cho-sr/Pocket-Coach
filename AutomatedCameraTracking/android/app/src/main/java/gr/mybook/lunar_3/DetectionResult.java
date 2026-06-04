package gr.mybook.lunar_3;

import android.graphics.RectF;

public class DetectionResult {
    private final RectF boundingBox;
    private final float score;
    private final float[] colorHistogram;
    private boolean matched;

    public DetectionResult(RectF boundingBox, float score, float[] colorHistogram) {
        this.boundingBox = new RectF(boundingBox);
        this.score = score;
        this.colorHistogram = colorHistogram == null ? new float[0] : colorHistogram.clone();
        this.matched = false;
    }

    public RectF getBoundingBox() {
        return new RectF(boundingBox);
    }

    public float getScore() {
        return score;
    }

    public float[] getColorHistogram() {
        return colorHistogram.clone();
    }

    public float getCenterX() {
        return (boundingBox.left + boundingBox.right) * 0.5f;
    }

    public float getCenterY() {
        return (boundingBox.top + boundingBox.bottom) * 0.5f;
    }

    public boolean isMatched() {
        return matched;
    }

    public void setMatched(boolean matched) {
        this.matched = matched;
    }
}