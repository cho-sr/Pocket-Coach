package gr.mybook.lunar_3;

import android.graphics.RectF;

public class KalmanTrackFilter {
    private float cx;
    private float cy;
    private float width;
    private float height;
    private float vx;
    private float vy;
    private float vw;
    private float vh;
    private boolean initialized;

    public void initialize(RectF box) {
        cx = (box.left + box.right) * 0.5f;
        cy = (box.top + box.bottom) * 0.5f;
        width = box.width();
        height = box.height();
        vx = 0f;
        vy = 0f;
        vw = 0f;
        vh = 0f;
        initialized = true;
    }

    public void predict(float dtSeconds) {
        if (!initialized) {
            return;
        }
        cx += vx * dtSeconds;
        cy += vy * dtSeconds;
        width = Math.max(8f, width + vw * dtSeconds);
        height = Math.max(8f, height + vh * dtSeconds);
    }

    public void correct(RectF measuredBox, float measurementWeight) {
        if (!initialized) {
            initialize(measuredBox);
            return;
        }
        float measuredCx = (measuredBox.left + measuredBox.right) * 0.5f;
        float measuredCy = (measuredBox.top + measuredBox.bottom) * 0.5f;
        float measuredWidth = measuredBox.width();
        float measuredHeight = measuredBox.height();
        float alpha = clamp(measurementWeight, 0.2f, 0.85f);

        float newCx = blend(cx, measuredCx, alpha);
        float newCy = blend(cy, measuredCy, alpha);
        float newWidth = Math.max(8f, blend(width, measuredWidth, alpha));
        float newHeight = Math.max(8f, blend(height, measuredHeight, alpha));

        vx = blend(vx, newCx - cx, 0.45f);
        vy = blend(vy, newCy - cy, 0.45f);
        vw = blend(vw, newWidth - width, 0.30f);
        vh = blend(vh, newHeight - height, 0.30f);

        cx = newCx;
        cy = newCy;
        width = newWidth;
        height = newHeight;
    }

    public RectF getPredictedBox() {
        float halfW = width * 0.5f;
        float halfH = height * 0.5f;
        return new RectF(cx - halfW, cy - halfH, cx + halfW, cy + halfH);
    }

    private float blend(float previous, float measured, float alpha) {
        return previous * (1f - alpha) + measured * alpha;
    }

    private float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }
}