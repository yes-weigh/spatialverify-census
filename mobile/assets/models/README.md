# YOLOv8 TensorFlow Lite Model

Place your `yolov8n.tflite` model file in this directory.

## Obtaining the model

Export from Ultralytics YOLOv8:

```bash
pip install ultralytics
yolo export model=yolov8n.pt format=tflite imgsz=640
```

For infrastructure-specific detection, fine-tune YOLOv8 on your dataset first, then export.

## Custom labels

Update `labels.txt` with your class names matching the model output order.
