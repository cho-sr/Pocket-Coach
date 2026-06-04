package gr.mybook.lunar_3;

public class MotionController {
    private static final int CENTER_ANGLE = 90;
    private static final int MIN_ANGLE = 35;
    private static final int MAX_ANGLE = 145;
    private static final float DEAD_ZONE = 0.10f;
    private static final float MAX_NORMALIZED_ERROR = 0.45f;
    private static final float KP = 14f;
    private static final float KD = 5f;
    private static final float MAX_STEP_PER_UPDATE = 1.2f;

    private float smoothedError;
    private float previousError;
    private float currentAngle = CENTER_ANGLE;

    public int updateForTarget(float targetCenterX, int frameWidth, boolean predictionOnly) {
        float frameCenterX = frameWidth * 0.5f;
        float normalizedError = (frameCenterX - targetCenterX) / Math.max(1f, frameWidth);
        smoothedError = smoothedError * 0.80f + normalizedError * 0.20f;
        if (Math.abs(smoothedError) < DEAD_ZONE) {
            previousError = smoothedError;
            return Math.round(currentAngle);
        }

        float clampedError = clamp(smoothedError, -MAX_NORMALIZED_ERROR, MAX_NORMALIZED_ERROR);
        float derivative = clampedError - previousError;
        float gainScale = predictionOnly ? 0.45f : 1.0f;
        float delta = (KP * clampedError + KD * derivative) * gainScale;
        delta = clamp(delta, -MAX_STEP_PER_UPDATE, MAX_STEP_PER_UPDATE);
        currentAngle = clamp(currentAngle + delta, MIN_ANGLE, MAX_ANGLE);
        previousError = clampedError;
        return Math.round(currentAngle);
    }

    public int holdCurrent() {
        return Math.round(currentAngle);
    }

    private float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }
}