package gr.mybook.lunar_3;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.RectF;
import android.util.Log;

import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.Tensor;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.nnapi.NnApiDelegate;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public class ObjectDetectorHelper {
    private static final String TAG = "ObjectDetectorHelper";
    private static final float CONFIDENCE_THRESHOLD = 0.30f;
    private static final float NMS_IOU_THRESHOLD = 0.50f;
    private static final int MAX_RESULTS = 40;
    private static final int MAX_NMS_CANDIDATES = 300;
    private static final int HISTOGRAM_BINS = 12;

    private final Interpreter interpreter;
    private NnApiDelegate nnApiDelegate;
    private final ByteBuffer inputBuffer;
    private final int inputWidth;
    private final int inputHeight;
    private final int[] pixels;
    private final boolean quantizedInput;
    private final int[] outputShape;

    public ObjectDetectorHelper(Context context, String modelAssetName) {
        try {
            MappedByteBuffer modelBuffer = loadModelFile(context, modelAssetName);
            Interpreter createdInterpreter = null;

            // 1. Try NPU (NNAPI) acceleration first
            try {
                Interpreter.Options npuOptions = new Interpreter.Options();
                npuOptions.setNumThreads(4);
                
                NnApiDelegate.Options nnapiOptions = new NnApiDelegate.Options();
                nnapiOptions.setExecutionPreference(NnApiDelegate.Options.EXECUTION_PREFERENCE_SUSTAINED_SPEED);
                nnApiDelegate = new NnApiDelegate(nnapiOptions);
                npuOptions.addDelegate(nnApiDelegate);
                
                createdInterpreter = new Interpreter(modelBuffer, npuOptions);
                Log.i(TAG, "NPU (NNAPI) delegate enabled successfully");
            } catch (Exception npuError) {
                if (nnApiDelegate != null) {
                    nnApiDelegate.close();
                    nnApiDelegate = null;
                }
                Log.w(TAG, "NPU (NNAPI) delegate initialization failed, falling back to CPU...", npuError);
            }

            // 2. Fallback to pure CPU if hardware accelerator failed
            if (createdInterpreter == null) {
                Interpreter.Options cpuOptions = new Interpreter.Options();
                cpuOptions.setNumThreads(4);
                createdInterpreter = new Interpreter(modelBuffer, cpuOptions);
                Log.i(TAG, "Using CPU fallback mode");
            }

            interpreter = createdInterpreter;

            Tensor inputTensor = interpreter.getInputTensor(0);
            int[] inputShape = inputTensor.shape();
            inputHeight = inputShape[1];
            inputWidth = inputShape[2];
            quantizedInput = inputTensor.dataType() == DataType.UINT8;
            int bytesPerChannel = quantizedInput ? 1 : 4;
            inputBuffer = ByteBuffer.allocateDirect(1 * inputWidth * inputHeight * 3 * bytesPerChannel);
            inputBuffer.order(ByteOrder.nativeOrder());
            pixels = new int[inputWidth * inputHeight];

            outputShape = interpreter.getOutputTensor(0).shape();
            Log.i(TAG, "Loaded " + modelAssetName + " input=" + shapeToString(inputShape)
                    + " output=" + shapeToString(outputShape)
                    + " inputType=" + inputTensor.dataType());
        } catch (IOException e) {
            throw new IllegalStateException("Failed to load TFLite model from assets: " + modelAssetName, e);
        }
    }

    private float[][][] outputBuffer;

    public List<DetectionResult> detectPersons(Bitmap sourceBitmap) {
        Bitmap inputBitmap = Bitmap.createScaledBitmap(sourceBitmap, inputWidth, inputHeight, true);
        convertBitmapToInput(inputBitmap);

        // MobileNetV2 SSD expects multiple outputs: boxes, classes, scores, count
        // 1. Boxes: [1, num_boxes, 4] -> normalized [top, left, bottom, right]
        // 2. Classes: [1, num_boxes] -> class indices
        // 3. Scores: [1, num_boxes] -> confidence scores
        // 4. Count: [1] -> total valid detections count
        int numBoxes = outputShape[1]; // Usually 10 or 100
        
        float[][][] outputBoxes = new float[1][numBoxes][4];
        float[][] outputClasses = new float[1][numBoxes];
        float[][] outputScores = new float[1][numBoxes];
        float[] numDetections = new float[1];

        Object[] inputs = {inputBuffer};
        java.util.Map<Integer, Object> outputs = new java.util.HashMap<Integer, Object>();
        outputs.put(0, outputBoxes);
        outputs.put(1, outputClasses);
        outputs.put(2, outputScores);
        outputs.put(3, numDetections);

        interpreter.runForMultipleInputsOutputs(inputs, outputs);

        List<DetectionResult> results = new ArrayList<DetectionResult>();
        int count = Math.min(numBoxes, (int) numDetections[0]);

        for (int i = 0; i < count; i++) {
            float score = outputScores[0][i];
            if (score < CONFIDENCE_THRESHOLD) {
                continue;
            }

            int classId = (int) outputClasses[0][i];
            // In COCO dataset, 0 or 1 is typically 'person'. We allow both to prevent mapping mismatches.
            if (classId == 0 || classId == 1) {
                float top = outputBoxes[0][i][0];
                float left = outputBoxes[0][i][1];
                float bottom = outputBoxes[0][i][2];
                float right = outputBoxes[0][i][3];

                // Rescale normalized coordinates (0.0 to 1.0) back to camera source bitmap pixels
                float x1 = clamp(left * sourceBitmap.getWidth(), 0f, sourceBitmap.getWidth() - 1f);
                float y1 = clamp(top * sourceBitmap.getHeight(), 0f, sourceBitmap.getHeight() - 1f);
                float x2 = clamp(right * sourceBitmap.getWidth(), x1 + 1f, sourceBitmap.getWidth());
                float y2 = clamp(bottom * sourceBitmap.getHeight(), y1 + 1f, sourceBitmap.getHeight());

                RectF box = new RectF(x1, y1, x2, y2);
                float[] histogram = extractColorHistogram(sourceBitmap, box);
                results.add(new DetectionResult(box, score, histogram));
            }
        }
        return results;
    }

    private float[] extractColorHistogram(Bitmap bitmap, RectF box) {
        int left = clampInt(Math.round(box.left), 0, bitmap.getWidth() - 1);
        int top = clampInt(Math.round(box.top), 0, bitmap.getHeight() - 1);
        int right = clampInt(Math.round(box.right), left + 1, bitmap.getWidth());
        int bottom = clampInt(Math.round(box.bottom), top + 1, bitmap.getHeight());
        int width = Math.max(1, right - left);
        int height = Math.max(1, bottom - top);

        int roiTop = top + Math.round(height * 0.20f);
        int roiBottom = top + Math.round(height * 0.65f);
        roiTop = clampInt(roiTop, top, bottom - 1);
        roiBottom = clampInt(roiBottom, roiTop + 1, bottom);

        float[] histogram = new float[HISTOGRAM_BINS];
        float[] hsv = new float[3];
        int samples = 0;
        int stepX = Math.max(1, width / 20);
        int stepY = Math.max(1, (roiBottom - roiTop) / 20);

        // Optimization: Read required pixels in a batch instead of calling getPixel() in a loop
        int roiWidth = right - left;
        int roiHeight = roiBottom - roiTop;
        if (roiWidth <= 0 || roiHeight <= 0) {
            return histogram;
        }
        
        int[] pixels = new int[roiWidth * roiHeight];
        bitmap.getPixels(pixels, 0, roiWidth, left, roiTop, roiWidth, roiHeight);

        for (int y = 0; y < roiHeight; y += stepY) {
            for (int x = 0; x < roiWidth; x += stepX) {
                int color = pixels[y * roiWidth + x];
                Color.colorToHSV(color, hsv);
                if (hsv[1] < 0.20f || hsv[2] < 0.15f) {
                    continue;
                }
                int bin = Math.min(HISTOGRAM_BINS - 1, (int) (hsv[0] / 360f * HISTOGRAM_BINS));
                histogram[bin] += 1f;
                samples++;
            }
        }

        if (samples == 0) {
            return histogram;
        }
        for (int i = 0; i < histogram.length; i++) {
            histogram[i] /= samples;
        }
        return histogram;
    }

    private void convertBitmapToInput(Bitmap bitmap) {
        inputBuffer.rewind();
        bitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight);
        for (int pixel : pixels) {
            int r = (pixel >> 16) & 0xff;
            int g = (pixel >> 8) & 0xff;
            int b = pixel & 0xff;
            if (quantizedInput) {
                inputBuffer.put((byte) r);
                inputBuffer.put((byte) g);
                inputBuffer.put((byte) b);
            } else {
                inputBuffer.putFloat(r / 255f);
                inputBuffer.putFloat(g / 255f);
                inputBuffer.putFloat(b / 255f);
            }
        }
        inputBuffer.rewind();
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

    private MappedByteBuffer loadModelFile(Context context, String modelAssetName) throws IOException {
        AssetFileDescriptor fileDescriptor = context.getAssets().openFd(modelAssetName);
        FileInputStream inputStream = new FileInputStream(fileDescriptor.getFileDescriptor());
        FileChannel fileChannel = inputStream.getChannel();
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, fileDescriptor.getStartOffset(), fileDescriptor.getDeclaredLength());
    }

    private String shapeToString(int[] shape) {
        StringBuilder builder = new StringBuilder("[");
        for (int i = 0; i < shape.length; i++) {
            if (i > 0) {
                builder.append(",");
            }
            builder.append(shape[i]);
        }
        builder.append("]");
        return builder.toString();
    }

    private float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }

    private int clampInt(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    public void close() {
        interpreter.close();
        if (nnApiDelegate != null) {
            nnApiDelegate.close();
            nnApiDelegate = null;
        }
    }
}





