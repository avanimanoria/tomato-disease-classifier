"""Model construction (MobileNetV3Small default, MobileNetV2 fallback). Preprocessing is INSIDE the model, so
every consumer (training, evaluation, inference, TFLite) feeds raw RGB pixels in [0, 255]."""
from __future__ import annotations

import time
from typing import Any, Dict, Tuple

import numpy as np


def _tf():
    import tensorflow as tf
    return tf


def build_augmentation():
    layers = _tf().keras.layers
    parts = [layers.RandomFlip("horizontal"), layers.RandomRotation(0.08), layers.RandomZoom(0.10),
             layers.RandomContrast(0.10)]
    if hasattr(layers, "RandomBrightness"):
        parts.append(layers.RandomBrightness(0.08, value_range=(0, 255)))
    return _tf().keras.Sequential(parts, name="augmentation")  # active ONLY when training=True


def build_model(cfg: Dict[str, Any], num_classes: int):
    """Returns (model, base_model). Raises RuntimeError if ImageNet weights cannot be loaded (no silent
    fallback to random initialisation)."""
    tf = _tf()
    keras, layers = tf.keras, tf.keras.layers
    mcfg = cfg["model"]
    if mcfg["pretrained_weights"] != "imagenet":
        raise RuntimeError("model.pretrained_weights must be 'imagenet'; training from random weights is not allowed.")
    h, w, c = int(cfg["image"]["height"]), int(cfg["image"]["width"]), int(cfg["image"]["channels"])
    arch = mcfg["architecture"]
    try:
        if arch == "MobileNetV3Small":
            # include_preprocessing=True: the network rescales raw [0,255] pixels itself
            # (this is exactly what keras.applications.mobilenet_v3.preprocess_input expects / does).
            base = keras.applications.MobileNetV3Small(input_shape=(h, w, c), include_top=False, weights="imagenet",
                                                       include_preprocessing=True)
        else:
            base = keras.applications.MobileNetV2(input_shape=(h, w, c), include_top=False, weights="imagenet")
    except Exception as exc:
        raise RuntimeError(
            f"Could not load pretrained ImageNet weights for {arch}: {exc}\n"
            "Refusing to continue with random weights. Check your internet connection (weights are downloaded "
            "from storage.googleapis.com on first use) or place the weights in ~/.keras/models/.") from exc
    base.trainable = False

    inputs = keras.Input(shape=(h, w, c), name="image")
    x = build_augmentation()(inputs)
    if arch == "MobileNetV2":  # equals mobilenet_v2.preprocess_input: scale to [-1, 1]
        x = layers.Rescaling(1.0 / 127.5, offset=-1.0, name="mobilenetv2_preprocess")(x)
    x = base(x, training=False)  # keep BatchNorm in inference mode
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(float(mcfg["dropout_1"]))(x)
    x = layers.Dense(int(mcfg["dense_units"]), activation="relu")(x)
    x = layers.Dropout(float(mcfg["dropout_2"]))(x)
    outputs = layers.Dense(num_classes, activation="softmax", name="predictions")(x)
    return keras.Model(inputs, outputs, name=f"tomato_{arch.lower()}"), base


def find_base_model(model):
    keras = _tf().keras
    for layer in model.layers:
        if isinstance(layer, keras.Model) and layer.name != "augmentation":
            return layer
    raise ValueError("No nested base model found.")


def compile_model(model, learning_rate: float):
    keras = _tf().keras
    model.compile(optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return model


def set_fine_tune_layers(model, last_n: int) -> Tuple[int, int]:
    """Unfreeze only the last `last_n` layers of the base; BatchNorm layers always stay frozen."""
    keras = _tf().keras
    base = find_base_model(model)
    base.trainable = True
    for layer in base.layers[:-last_n]:
        layer.trainable = False
    for layer in base.layers:
        if isinstance(layer, keras.layers.BatchNormalization):
            layer.trainable = False
    n_trainable = sum(1 for l in base.layers if l.trainable and l.weights)
    return n_trainable, len(base.layers)


def count_params(model) -> Dict[str, int]:
    trainable = int(sum(np.prod(v.shape) for v in model.trainable_weights))
    total = int(model.count_params())
    return {"total": total, "trainable": trainable, "non_trainable": total - trainable,
            "approx_float32_size_mb": round(total * 4 / 1e6, 2)}


def strip_augmentation(model):
    """Inference-only copy (no random layers) of a linear functional model; shares weights. Used for TFLite."""
    keras = _tf().keras
    inp = keras.Input(shape=model.input_shape[1:], name="image")
    x = inp
    for layer in model.layers:
        if isinstance(layer, keras.layers.InputLayer) or layer.name == "augmentation":
            continue
        x = layer(x)
    return keras.Model(inp, x, name=model.name + "_inference")


def predict_dataset(model, loaded) -> Tuple[np.ndarray, np.ndarray, float]:
    """Run the model over a LoadedDataset. Returns (y_true, probs, seconds_total)."""
    ys, ps = [], []
    t0 = time.perf_counter()
    for x, y in loaded.ds:
        ps.append(model.predict(x, verbose=0))
        ys.append(y.numpy())
    return np.concatenate(ys), np.concatenate(ps), time.perf_counter() - t0
