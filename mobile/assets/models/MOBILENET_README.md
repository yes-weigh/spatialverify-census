# MobileNet v2 Feature Vector Model

Place `mobilenet_v2_feature_vector.tflite` in this directory.

## Export from TensorFlow Hub

```python
import tensorflow as tf
import tensorflow_hub as hub

model = hub.load("https://tfhub.dev/google/tf2-preview/mobilenet_v2/feature_vector/4")
converter = tf.lite.TFLiteConverter.from_saved_model(model)
tflite_model = converter.convert()

with open("mobilenet_v2_feature_vector.tflite", "wb") as f:
    f.write(tflite_model)
```

Output: 1280-dimensional L2-normalized embedding vector.

## CLIP alternative

For CLIP embeddings (512-dim), export a CLIP mobile TFLite model and update
`EmbeddingService.embeddingDim` and backend `EMBEDDING_DIMENSION` to match.
