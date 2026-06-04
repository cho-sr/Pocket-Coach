package gr.mybook.lunar_3;

import android.Manifest;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.YuvImage;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.media.Image;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.google.common.util.concurrent.ListenableFuture;
import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.hoho.android.usbserial.driver.UsbSerialProber;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import androidx.camera.video.VideoCapture;
import androidx.camera.video.Recorder;
import androidx.camera.video.Recording;
import androidx.camera.video.VideoRecordEvent;
import androidx.camera.video.QualitySelector;
import androidx.camera.video.Quality;
import androidx.camera.video.MediaStoreOutputOptions;
import androidx.core.util.Consumer;
import android.provider.MediaStore;
import android.content.ContentValues;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "CameraTracking";
    private static final String ACTION_USB_PERMISSION = "gr.mybook.lunar_3.USB_PERMISSION";
    private static final int REQUEST_CAMERA_PERMISSION = 1001;
    private static final long PAN_SEND_INTERVAL_MS = 80L;

    private PreviewView previewView;
    private TrackingOverlayView overlayView;
    private TextView statusText;
    private TextView performanceText;
    private ExecutorService cameraExecutor;
    private ObjectDetectorHelper detectorHelper;
    private TrackingPipelineCoordinator trackingCoordinator;

    private UsbManager usbManager;
    private UsbSerialPort usbSerialPort;
    private PendingIntent usbPermissionIntent;

    private VideoCapture<Recorder> videoCapture;
    private Recording activeRecording = null;
    private boolean isRecording = false;
    private TextView recordButton;

    private long lastFrameTimestampNs = 0L;
    private float smoothedFps = 0f;
    private int lastSentPanAngle = Integer.MIN_VALUE;
    private int currentPanAngle = 90; // Default center angle
    private static final float DEADY_ZONE_RATIO = 0.08f; // 8% deadzone threshold
    private static final float KP = 3.5f; // Proportional control weight
    private long lastPanSendAt = 0L;
    private long usbReadyAtMs = 0L;
    private long nextUsbReconnectAtMs = 0L;

    private final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (ACTION_USB_PERMISSION.equals(action)) {
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                if (granted && device != null) {
                    openUsbSerial(device);
                } else {
                    setStatusText("USB permission denied");
                }
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
                connectUsbSerial();
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                closeUsbSerial();
                setStatusText("USB disconnected");
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        enableImmersiveMode();

        previewView = new PreviewView(this);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        overlayView = new TrackingOverlayView(this, new OnTrackTapListener() {
            @Override
            public void onTrackTapped(int trackId) {
                trackingCoordinator.lockToTrack(trackId);
                Toast.makeText(MainActivity.this, "Locked target #" + trackId, Toast.LENGTH_SHORT).show();
            }

            @Override
            public void onEmptyAreaTapped() {
                trackingCoordinator.clearManualLock();
                Toast.makeText(MainActivity.this, "Manual lock cleared", Toast.LENGTH_SHORT).show();
            }
        });

        // Glassmorphism dashcard styling for performanceText
        android.graphics.drawable.GradientDrawable perfBg = new android.graphics.drawable.GradientDrawable();
        perfBg.setColor(0xD90A0E1A); // 85% opacity dark navy-blue
        perfBg.setCornerRadius(dpToPx(10));
        perfBg.setStroke(dpToPx(1), 0x8000FFCC); // 50% opacity neon mint border

        performanceText = new TextView(this);
        performanceText.setTextColor(0xff00ffcc);
        performanceText.setTypeface(android.graphics.Typeface.MONOSPACE);
        performanceText.setBackground(perfBg);
        performanceText.setPadding(dpToPx(14), dpToPx(8), dpToPx(14), dpToPx(8));
        performanceText.setText("FPS: -- | Latency: -- ms");

        // Separate styling for statusText
        android.graphics.drawable.GradientDrawable statusBg = new android.graphics.drawable.GradientDrawable();
        statusBg.setColor(0xD90A0E1A);
        statusBg.setCornerRadius(dpToPx(10));
        statusBg.setStroke(dpToPx(1), 0x80FFFFFF); // 50% opacity white border

        statusText = new TextView(this);
        statusText.setTextColor(0xffffffff);
        statusText.setTypeface(android.graphics.Typeface.SANS_SERIF);
        statusText.setBackground(statusBg);
        statusText.setPadding(dpToPx(16), dpToPx(12), dpToPx(16), dpToPx(12));
        statusText.setLineSpacing(0f, 1.2f);
        statusText.setText("Starting tracking...");
        updateUsbLed(false);

        FrameLayout root = new FrameLayout(this);
        root.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(overlayView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));

        FrameLayout.LayoutParams perfParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.START);
        int perfMargin = dpToPx(16);
        perfParams.setMargins(perfMargin, perfMargin, perfMargin, perfMargin);
        root.addView(performanceText, perfParams);

        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.START | Gravity.CENTER_VERTICAL);
        int statusMargin = dpToPx(24);
        statusParams.setMargins(statusMargin, statusMargin, statusMargin, statusMargin);
        root.addView(statusText, statusParams);

        // Add Video Record Button (HUD Style circular view)
        recordButton = new TextView(this);
        recordButton.setGravity(Gravity.CENTER);
        recordButton.setText("REC");
        recordButton.setTextColor(0xFFFF3B30); // Neon Red
        recordButton.setTextSize(14f);
        recordButton.setTypeface(android.graphics.Typeface.create(android.graphics.Typeface.SANS_SERIF, android.graphics.Typeface.BOLD));
        updateRecordButtonUI(false);

        FrameLayout.LayoutParams recParams = new FrameLayout.LayoutParams(
                dpToPx(70),
                dpToPx(70),
                Gravity.BOTTOM | Gravity.END
        );
        int recMargin = dpToPx(32);
        recParams.setMargins(recMargin, recMargin, recMargin, recMargin);
        root.addView(recordButton, recParams);

        recordButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                toggleRecording();
            }
        });

        setContentView(root);

        cameraExecutor = Executors.newSingleThreadExecutor();
        detectorHelper = new ObjectDetectorHelper(this, "mobilenet_v2_ssd.tflite");
        trackingCoordinator = new TrackingPipelineCoordinator();
        setupUsbSerial();

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA}, REQUEST_CAMERA_PERMISSION);
        }
    }

    private int dpToPx(int dp) {
        return Math.round(dp * getResources().getDisplayMetrics().density);
    }

    private android.graphics.drawable.GradientDrawable createLedDrawable(boolean connected) {
        android.graphics.drawable.GradientDrawable led = new android.graphics.drawable.GradientDrawable();
        led.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        int size = dpToPx(10);
        led.setSize(size, size);
        led.setColor(connected ? 0xFF00FF66 : 0xFFFF3B30); // Neon Green / Neon Red
        return led;
    }

    private void updateUsbLed(final boolean connected) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (statusText != null) {
                    statusText.setCompoundDrawablePadding(dpToPx(10));
                    statusText.setCompoundDrawablesWithIntrinsicBounds(createLedDrawable(connected), null, null, null);
                }
            }
        });
    }

    private void enableImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat controller =
                WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        if (controller == null) {
            return;
        }
        controller.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        controller.hide(WindowInsetsCompat.Type.systemBars());
    }

    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> providerFuture = ProcessCameraProvider.getInstance(this);
        providerFuture.addListener(new Runnable() {
            @Override
            public void run() {
                try {
                    bindCamera(providerFuture.get());
                } catch (ExecutionException | InterruptedException e) {
                    Log.e(TAG, "CameraX start failed", e);
                    setStatusText("Camera start failed: " + e.getMessage());
                }
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void bindCamera(ProcessCameraProvider provider) {
        Preview preview = new Preview.Builder().build();
        preview.setSurfaceProvider(previewView.getSurfaceProvider());

        ImageAnalysis analysis = new ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build();

        // Initialize Video Recorder with FHD Quality
        Recorder recorder = new Recorder.Builder()
                .setQualitySelector(QualitySelector.from(Quality.FHD))
                .build();
        videoCapture = VideoCapture.withOutput(recorder);

        analysis.setAnalyzer(cameraExecutor, new ImageAnalysis.Analyzer() {
            @Override
            public void analyze(@NonNull ImageProxy imageProxy) {
                long frameStartNs = System.nanoTime();
                Bitmap frame = null;
                try {
                    frame = imageProxyToBitmap(imageProxy);
                    List<DetectionResult> detections = detectorHelper.detectPersons(frame);
                    TrackingSnapshot snapshot = trackingCoordinator.process(
                            detections,
                            frame.getWidth(),
                            frame.getHeight(),
                            System.currentTimeMillis());
                    sendPanAngle(snapshot.getPanAngle());
                    updateOverlay(snapshot, frame.getWidth(), frame.getHeight());
                    updateTrackingStatus(snapshot, detections.size(), frame.getWidth());
                } catch (Exception e) {
                    Log.e(TAG, "Frame analysis failed", e);
                    setStatusText("Tracking error: " + e.getClass().getSimpleName());
                    updateOverlay(null, 0, 0);
                } finally {
                    long frameEndNs = System.nanoTime();
                    updatePerformance(frameEndNs, (frameEndNs - frameStartNs) / 1000000f);
                    if (frame != null) {
                        frame.recycle();
                    }
                    imageProxy.close();
                }
            }
        });

        provider.unbindAll();
        // Bind Preview, ImageAnalysis, and VideoCapture concurrently
        provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis, videoCapture);
        setStatusText("Camera ready. Tap a player to lock.");
    }

    private void setupUsbSerial() {
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        Intent permissionIntent = new Intent(ACTION_USB_PERMISSION);
        permissionIntent.setPackage(getPackageName());
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags |= PendingIntent.FLAG_MUTABLE;
        }
        usbPermissionIntent = PendingIntent.getBroadcast(this, 0, permissionIntent, flags);

        IntentFilter filter = new IntentFilter(ACTION_USB_PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(usbReceiver, filter);
        }
        connectUsbSerial();
    }

    private void connectUsbSerial() {
        if (usbManager == null) {
            return;
        }
        List<UsbSerialDriver> drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager);
        if (drivers.isEmpty()) {
            setStatusText("No USB serial device found");
            return;
        }
        UsbDevice device = drivers.get(0).getDevice();
        if (!usbManager.hasPermission(device)) {
            usbManager.requestPermission(device, usbPermissionIntent);
            return;
        }
        openUsbSerial(device);
    }

    private void openUsbSerial(UsbDevice device) {
        try {
            List<UsbSerialDriver> drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager);
            UsbSerialDriver selectedDriver = null;
            for (UsbSerialDriver driver : drivers) {
                if (driver.getDevice().equals(device)) {
                    selectedDriver = driver;
                    break;
                }
            }
            if (selectedDriver == null || selectedDriver.getPorts().isEmpty()) {
                setStatusText("No USB serial driver for this device");
                return;
            }
            UsbDeviceConnection connection = usbManager.openDevice(selectedDriver.getDevice());
            if (connection == null) {
                setStatusText("USB open failed");
                return;
            }

            closeUsbSerial();
            usbSerialPort = selectedDriver.getPorts().get(0);
            usbSerialPort.open(connection);
            usbSerialPort.setParameters(9600, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE);
            usbSerialPort.setDTR(true);
            usbSerialPort.setRTS(true);
            usbReadyAtMs = System.currentTimeMillis() + 2200L;
            nextUsbReconnectAtMs = 0L;
            lastSentPanAngle = Integer.MIN_VALUE;
            setStatusText("USB connected at 9600 baud");
        } catch (Exception e) {
            Log.e(TAG, "USB connection failed", e);
            setStatusText("USB error: " + e.getMessage());
        }
    }

    private void sendPanAngle(int angle) {
        long now = System.currentTimeMillis();
        if (usbSerialPort == null) {
            if (now >= nextUsbReconnectAtMs) {
                nextUsbReconnectAtMs = now + 2000L;
                connectUsbSerial();
            }
            return;
        }
        if (now < usbReadyAtMs) {
            return;
        }
        if (angle == lastSentPanAngle && now - lastPanSendAt < PAN_SEND_INTERVAL_MS) {
            return;
        }
        String command = "PAN:" + angle + "\n";
        try {
            usbSerialPort.write(command.getBytes(StandardCharsets.US_ASCII), 1000);
            lastSentPanAngle = angle;
            lastPanSendAt = now;
        } catch (Exception e) {
            Log.e(TAG, "USB write failed", e);
            closeUsbSerial();
            nextUsbReconnectAtMs = now + 1200L;
            setStatusText("USB write failed - reconnecting");
        }
    }

    private void closeUsbSerial() {
        if (usbSerialPort == null) {
            return;
        }
        try {
            usbSerialPort.close();
        } catch (Exception ignored) {
        }
        usbSerialPort = null;
        usbReadyAtMs = 0L;
    }

    private void updateOverlay(final TrackingSnapshot snapshot, final int frameWidth, final int frameHeight) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                overlayView.setSnapshot(snapshot, frameWidth, frameHeight);
            }
        });
    }

    private void updatePerformance(final long frameEndNs, final float latencyMs) {
        if (lastFrameTimestampNs != 0L) {
            float instantFps = 1000000000f / (frameEndNs - lastFrameTimestampNs);
            smoothedFps = smoothedFps == 0f ? instantFps : smoothedFps * 0.85f + instantFps * 0.15f;
        }
        lastFrameTimestampNs = frameEndNs;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                performanceText.setText(String.format(Locale.US, "FPS: %.1f | Latency: %.1f ms", smoothedFps, latencyMs));
            }
        });
    }

    private void updateTrackingStatus(final TrackingSnapshot snapshot, final int detectionCount, final int frameWidth) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (snapshot == null || snapshot.getTarget() == null) {
                    statusText.setText(String.format(Locale.US,
                            "Detections: %d | Tracks: %d\nLocked: %s | Pan: %d",
                            detectionCount,
                            countVisibleTracks(snapshot),
                            snapshot != null && snapshot.isManualLockEnabled() ? "manual" : "none",
                            snapshot == null ? lastSentPanAngle : snapshot.getPanAngle()));
                    updateUsbLed(usbSerialPort != null);
                    return;
                }

                Track target = snapshot.getTarget();
                float targetPercent = target.getCenterX() * 100f / Math.max(1, frameWidth);
                statusText.setText(String.format(Locale.US,
                        "%s | ID: %d\nTarget %.1f%% | Pan: %d | Tracks: %d | %s",
                        snapshot.getStatus(),
                        target.getId(),
                        targetPercent,
                        snapshot.getPanAngle(),
                        countVisibleTracks(snapshot),
                        snapshot.isManualLockEnabled() ? "manual" : "auto"));
                updateUsbLed(usbSerialPort != null);
            }
        });
    }

    private static boolean shouldDrawTrack(Track track) {
        if (track == null || track.getState() == Track.State.REMOVED || track.getState() == Track.State.LOST) {
            return false;
        }
        if (track.isLockedTarget()) {
            return true;
        }
        if (track.getState() == Track.State.TRACKED) {
            return true;
        }
        if (track.getState() == Track.State.TENTATIVE) {
            return track.getScore() >= 0.35f;
        }
        return track.getState() == Track.State.PREDICTED
                && track.getMissingFrames() <= 4
                && track.getHitCount() >= 2;
    }

    private static int countVisibleTracks(TrackingSnapshot snapshot) {
        if (snapshot == null) {
            return 0;
        }
        int count = 0;
        for (Track track : snapshot.getTracks()) {
            if (shouldDrawTrack(track)) {
                count++;
            }
        }
        return count;
    }

    private void setStatusText(final String message) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                statusText.setText(message);
                updateUsbLed(usbSerialPort != null);
                Toast.makeText(MainActivity.this, message, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private Bitmap imageProxyToBitmap(ImageProxy imageProxy) {
        ByteBuffer buffer = imageProxy.getPlanes()[0].getBuffer();
        buffer.rewind();
        int width = imageProxy.getWidth();
        int height = imageProxy.getHeight();
        
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        bitmap.copyPixelsFromBuffer(buffer);
        
        int rotation = imageProxy.getImageInfo().getRotationDegrees();
        if (rotation == 0) {
            return bitmap;
        }
        Matrix matrix = new Matrix();
        matrix.postRotate(rotation);
        return Bitmap.createBitmap(bitmap, 0, 0, width, height, matrix, true);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_CAMERA_PERMISSION && grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            setStatusText("Camera permission is required");
        }
    }

    private interface OnTrackTapListener {
        void onTrackTapped(int trackId);
        void onEmptyAreaTapped();
    }

    private static class TrackingOverlayView extends View {
        private final Paint targetBoxPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint otherBoxPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint predictedPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint detectionPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint labelPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint labelBgPaint = new Paint();
        private final Paint crosshairPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint pulsePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ripplePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        private final OnTrackTapListener tapListener;
        private TrackingSnapshot snapshot;
        private int frameWidth;
        private int frameHeight;

        // Ripple Animation Properties
        private float rippleX = -1f;
        private float rippleY = -1f;
        private long rippleStartTime = 0L;
        private static final long RIPPLE_DURATION = 350L;

        TrackingOverlayView(Context context, OnTrackTapListener tapListener) {
            super(context);
            this.tapListener = tapListener;
            setClickable(true);

            // Neon Green for locked target
            targetBoxPaint.setColor(0xFF00FF66);
            targetBoxPaint.setStyle(Paint.Style.STROKE);
            targetBoxPaint.setStrokeWidth(5f);

            // Ice Blue for standard detections
            otherBoxPaint.setColor(0xFF00E5FF);
            otherBoxPaint.setStyle(Paint.Style.STROKE);
            otherBoxPaint.setStrokeWidth(4f);

            // Vivid Orange for predicted state
            predictedPaint.setColor(0xFFFF9100);
            predictedPaint.setStyle(Paint.Style.STROKE);
            predictedPaint.setStrokeWidth(5f);

            // Semi-transparent white for general detector boxes
            detectionPaint.setColor(0x66FFFFFF);
            detectionPaint.setStyle(Paint.Style.STROKE);
            detectionPaint.setStrokeWidth(3f);

            labelPaint.setColor(Color.WHITE);
            labelPaint.setTextSize(32f);
            labelPaint.setTypeface(android.graphics.Typeface.create(android.graphics.Typeface.SANS_SERIF, android.graphics.Typeface.BOLD));
            labelPaint.setStyle(Paint.Style.FILL);

            labelBgPaint.setColor(0x99000000);
            labelBgPaint.setStyle(Paint.Style.FILL);

            crosshairPaint.setColor(0xCC00FF66);
            crosshairPaint.setStyle(Paint.Style.STROKE);
            crosshairPaint.setStrokeWidth(3f);

            pulsePaint.setColor(0xAA00FF66);
            pulsePaint.setStyle(Paint.Style.STROKE);
            pulsePaint.setStrokeWidth(4f);

            ripplePaint.setColor(0xBB00FFCC);
            ripplePaint.setStyle(Paint.Style.STROKE);
            ripplePaint.setStrokeWidth(5f);
        }

        void setSnapshot(TrackingSnapshot snapshot, int frameWidth, int frameHeight) {
            this.snapshot = snapshot;
            this.frameWidth = frameWidth;
            this.frameHeight = frameHeight;
            invalidate();
        }

        private void drawCornerBrackets(Canvas canvas, RectF rect, Paint paint, float bracketLength) {
            float width = rect.width();
            float height = rect.height();
            float len = Math.min(bracketLength, Math.min(width, height) / 3f);

            // Top-Left
            canvas.drawLine(rect.left, rect.top, rect.left + len, rect.top, paint);
            canvas.drawLine(rect.left, rect.top, rect.left, rect.top + len, paint);

            // Top-Right
            canvas.drawLine(rect.right, rect.top, rect.right - len, rect.top, paint);
            canvas.drawLine(rect.right, rect.top, rect.right, rect.top + len, paint);

            // Bottom-Left
            canvas.drawLine(rect.left, rect.bottom, rect.left + len, rect.bottom, paint);
            canvas.drawLine(rect.left, rect.bottom, rect.left, rect.bottom - len, paint);

            // Bottom-Right
            canvas.drawLine(rect.right, rect.bottom, rect.right - len, rect.bottom, paint);
            canvas.drawLine(rect.right, rect.bottom, rect.right, rect.bottom - len, paint);
        }

        private void drawLabelWithBackground(Canvas canvas, String text, float x, float y) {
            Rect textBounds = new Rect();
            labelPaint.getTextBounds(text, 0, text.length(), textBounds);
            float bgPadding = 8f;
            RectF bgRect = new RectF(
                    x - bgPadding,
                    y - textBounds.height() - bgPadding,
                    x + textBounds.width() + bgPadding,
                    y + bgPadding
            );
            canvas.drawRoundRect(bgRect, 6f, 6f, labelBgPaint);
            canvas.drawText(text, x, y, labelPaint);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (snapshot == null || frameWidth <= 0 || frameHeight <= 0) {
                return;
            }

            float viewWidth = getWidth();
            float viewHeight = getHeight();
            float scale = Math.max(viewWidth / frameWidth, viewHeight / frameHeight);
            float dx = (viewWidth - frameWidth * scale) * 0.5f;
            float dy = (viewHeight - frameHeight * scale) * 0.5f;

            List<Track> tracks = new ArrayList<Track>(snapshot.getTracks());
            boolean hasVisibleTrack = false;
            for (Track track : tracks) {
                if (shouldDrawTrack(track)) {
                    hasVisibleTrack = true;
                    break;
                }
            }

            if (!hasVisibleTrack) {
                for (DetectionResult detection : snapshot.getDetections()) {
                    RectF mappedDetection = mapRect(detection.getBoundingBox(), scale, dx, dy);
                    drawCornerBrackets(canvas, mappedDetection, detectionPaint, 30f);
                    drawLabelWithBackground(
                            canvas,
                            String.format(Locale.US, "DET %.0f%%", detection.getScore() * 100f),
                            mappedDetection.left + 5f,
                            Math.max(42f, mappedDetection.top - 12f)
                    );
                }
            }

            long currentTime = System.currentTimeMillis();

            for (Track track : tracks) {
                if (!shouldDrawTrack(track)) {
                    continue;
                }
                RectF mapped = mapRect(track.getBoundingBox(), scale, dx, dy);
                Paint paint = track.isLockedTarget()
                        ? (snapshot.isPredictionOnly() ? predictedPaint : targetBoxPaint)
                        : otherBoxPaint;

                // Draw corners brackets instead of full rectangle
                drawCornerBrackets(canvas, mapped, paint, 35f);

                // Add text overlay with dark pill background
                String label = track.isLockedTarget()
                        ? String.format(Locale.US, "TARGET #%d %.0f%%", track.getId(), track.getScore() * 100f)
                        : String.format(Locale.US, "TRACK #%d", track.getId());
                drawLabelWithBackground(canvas, label, mapped.left + 5f, Math.max(42f, mapped.top - 12f));

                // If locked, add custom HUD elements
                if (track.isLockedTarget()) {
                    // 1. Crosshair at center
                    float cx = mapped.centerX();
                    float cy = mapped.centerY();
                    float crossSize = 18f;
                    canvas.drawLine(cx - crossSize, cy, cx + crossSize, cy, crosshairPaint);
                    canvas.drawLine(cx, cy - crossSize, cx, cy + crossSize, crosshairPaint);

                    // 2. Pulse radar ring
                    float progress = (float) (currentTime % 1200) / 1200f; // 1.2s period loop
                    float baseRadius = Math.min(mapped.width(), mapped.height()) * 0.5f;
                    float pulseRadius = baseRadius + (baseRadius * 0.4f * progress);
                    pulsePaint.setAlpha((int) (220 * (1f - progress)));
                    canvas.drawCircle(cx, cy, pulseRadius, pulsePaint);
                }
            }

            // Draw Tap Ripple Effect
            long rippleElapsed = currentTime - rippleStartTime;
            if (rippleElapsed >= 0 && rippleElapsed < RIPPLE_DURATION && rippleX >= 0) {
                float progress = (float) rippleElapsed / RIPPLE_DURATION;
                float radius = 100f * progress;
                ripplePaint.setAlpha((int) (200 * (1f - progress)));
                canvas.drawCircle(rippleX, rippleY, radius, ripplePaint);
            }

            // Always request next frame to keep animations running smoothly
            postInvalidateOnAnimation();
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (event.getAction() == MotionEvent.ACTION_UP && snapshot != null) {
                float viewWidth = getWidth();
                float viewHeight = getHeight();
                float scale = Math.max(viewWidth / frameWidth, viewHeight / frameHeight);
                float dx = (viewWidth - frameWidth * scale) * 0.5f;
                float dy = (viewHeight - frameHeight * scale) * 0.5f;

                Track tappedTrack = null;
                for (Track track : snapshot.getTracks()) {
                    if (!shouldDrawTrack(track)) {
                        continue;
                    }
                    RectF mapped = mapRect(track.getBoundingBox(), scale, dx, dy);
                    if (mapped.contains(event.getX(), event.getY())) {
                        tappedTrack = track;
                        break;
                    }
                }

                // Register ripple effect origin
                rippleX = event.getX();
                rippleY = event.getY();
                rippleStartTime = System.currentTimeMillis();

                if (tappedTrack != null) {
                    tapListener.onTrackTapped(tappedTrack.getId());
                } else {
                    tapListener.onEmptyAreaTapped();
                }
                invalidate();
                return true;
            }
            return super.onTouchEvent(event);
        }

        private RectF mapRect(RectF source, float scale, float dx, float dy) {
            return new RectF(
                    source.left * scale + dx,
                    source.top * scale + dy,
                    source.right * scale + dx,
                    source.bottom * scale + dy);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        enableImmersiveMode();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            enableImmersiveMode();
        }
    }

    private void toggleRecording() {
        if (videoCapture == null) {
            Toast.makeText(this, "Camera not ready yet", Toast.LENGTH_SHORT).show();
            return;
        }
        if (isRecording) {
            stopRecording();
        } else {
            startRecording();
        }
    }

    private void startRecording() {
        if (videoCapture == null) return;

        String name = "CameraTracking_" + System.currentTimeMillis();
        ContentValues contentValues = new ContentValues();
        contentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        contentValues.put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentValues.put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/CameraTracking");
        }

        MediaStoreOutputOptions options = new MediaStoreOutputOptions.Builder(
                getContentResolver(),
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
                .setContentValues(contentValues)
                .build();

        try {
            // Audio recording is disabled to bypass android mic permissions dynamically
            activeRecording = videoCapture.getOutput()
                    .prepareRecording(this, options)
                    .start(ContextCompat.getMainExecutor(this), new Consumer<VideoRecordEvent>() {
                        @Override
                        public void accept(VideoRecordEvent event) {
                            if (event instanceof VideoRecordEvent.Start) {
                                isRecording = true;
                                updateRecordButtonUI(true);
                                Toast.makeText(MainActivity.this, "Recording started 🔴", Toast.LENGTH_SHORT).show();
                            } else if (event instanceof VideoRecordEvent.Finalize) {
                                VideoRecordEvent.Finalize finalizeEvent = (VideoRecordEvent.Finalize) event;
                                isRecording = false;
                                updateRecordButtonUI(false);
                                activeRecording = null;

                                if (!finalizeEvent.hasError()) {
                                    Toast.makeText(MainActivity.this, "Video saved: Movies/CameraTracking", Toast.LENGTH_LONG).show();
                                } else {
                                    Log.e(TAG, "Video record finalize error: " + finalizeEvent.getError());
                                    Toast.makeText(MainActivity.this, "Recording failed", Toast.LENGTH_SHORT).show();
                                }
                            }
                        }
                    });
        } catch (Exception e) {
            Log.e(TAG, "Failed to initiate video capture", e);
            Toast.makeText(this, "Failed to start recording: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }

    private void stopRecording() {
        if (activeRecording != null) {
            activeRecording.stop();
            activeRecording = null;
        }
    }

    private void updateRecordButtonUI(boolean recording) {
        android.graphics.drawable.GradientDrawable btnBg = new android.graphics.drawable.GradientDrawable();
        btnBg.setShape(android.graphics.drawable.GradientDrawable.OVAL);

        if (recording) {
            btnBg.setColor(0xCCFF3B30); // 80% opacity neon red
            btnBg.setStroke(dpToPx(2), 0xFFFFFFFF); // White border
            recordButton.setText("STOP");
            recordButton.setTextColor(0xFFFFFFFF);
        } else {
            btnBg.setColor(0x990A0E1A); // Translucent dark dashboard color
            btnBg.setStroke(dpToPx(2), 0xFFFF3B30); // Neon Red border
            recordButton.setText("REC");
            recordButton.setTextColor(0xFFFF3B30);
        }

        recordButton.setBackground(btnBg);
    }

    @Override
    protected void onDestroy() {
        stopRecording();
        sendPanAngle(90);
        closeUsbSerial();
        try {
            unregisterReceiver(usbReceiver);
        } catch (Exception ignored) {
        }
        if (detectorHelper != null) {
            detectorHelper.close();
        }
        if (cameraExecutor != null) {
            cameraExecutor.shutdown();
        }
        super.onDestroy();
    }
}








