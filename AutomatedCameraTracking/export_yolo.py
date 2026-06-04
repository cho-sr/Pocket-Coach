from ultralytics import YOLO
import shutil
import os

print("Loading YOLO11n model...")
model = YOLO('yolo11n.pt')

print("Exporting to TFLite (INT8 quantization)...")
# Export the model to TFLite format with INT8 quantization
export_path = model.export(format='tflite', int8=True)
print(f"Export finished. Path: {export_path}")

# Ultralytics usually saves the int8 tflite model inside a directory or directly.
# Let's find the .tflite file and copy it to the assets folder.
assets_dir = r"c:\a\Nam Kung\AutomatedCameraTracking\android\app\src\main\assets"
os.makedirs(assets_dir, exist_ok=True)

# Look for yolo11n_int8.tflite
search_dirs = [".", "yolo11n_saved_model"]
found_file = None

for root, dirs, files in os.walk("."):
    for file in files:
        if file.endswith("int8.tflite") and "yolo11n" in file:
            found_file = os.path.join(root, file)
            break

if found_file:
    dest_path = os.path.join(assets_dir, "yolo11n_int8.tflite")
    shutil.copy2(found_file, dest_path)
    print(f"Model successfully copied to {dest_path}")
else:
    print("Error: Could not find the exported int8 tflite model.")
