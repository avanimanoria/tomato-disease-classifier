import json
from pathlib import Path

import numpy as np
import pytest

tf = pytest.importorskip("tensorflow")

from src import export_tflite
from src.config_loader import path_of
from src.dataset_loader import load_train_dataset
from src.inference import CONFIDENCE_NOTE, predict_image
from src.model import strip_augmentation
from tests.conftest import CLASSES, smooth_random_image

ROOT = Path(__file__).resolve().parent.parent


def tiny_model(num_classes=3):
    """Small stand-in model with the same structure conventions (augmentation block + softmax head).
    Used ONLY to test plumbing; it is untrained and meaningless as a classifier."""
    k = tf.keras
    inp = k.Input((224, 224, 3), name="image")
    x = k.Sequential([k.layers.RandomFlip("horizontal")], name="augmentation")(inp)
    x = k.layers.Rescaling(1 / 127.5, offset=-1)(x)
    x = k.layers.Conv2D(4, 3, strides=4, activation="relu")(x)
    x = k.layers.GlobalAveragePooling2D()(x)
    out = k.layers.Dense(num_classes, activation="softmax")(x)
    return k.Model(inp, out)


@pytest.fixture
def img(tmp_path):
    p = tmp_path / "leaf.png"
    smooth_random_image(5, 300).save(p)
    return p


def test_inference_output_is_json_serializable_and_not_severity(project, img):
    r = predict_image(project, img, model=tiny_model(), class_names=CLASSES, save_json=True)
    json.dumps(r)  # must not raise
    assert r["predicted_class"] in CLASSES and 0 <= r["confidence"] <= 1
    assert abs(sum(r["class_probabilities"].values()) - 1) < 1e-4
    assert r["note"] == CONFIDENCE_NOTE
    assert CONFIDENCE_NOTE == ("Confidence indicates classifier certainty for this image; it does not measure "
                               "infected leaf area or disease severity.")
    assert not any("severity" in k.lower() for k in r)
    assert Path(r["prediction_json"]).exists() and "predictions" in r["prediction_json"]


def test_low_confidence_warning_and_annotated_image(project, img):
    project["model"]["low_confidence_threshold"] = 0.999
    r = predict_image(project, img, model=tiny_model(), class_names=CLASSES, save_json=False, save_annotated=True)
    assert r["low_confidence_warning"] and "unreliable" in r["low_confidence_warning"]
    assert Path(r["annotated_image"]).exists()


def test_inference_is_deterministic_no_augmentation(project, img):
    m = tiny_model()
    a = predict_image(project, img, model=m, class_names=CLASSES, save_json=False)["class_probabilities"]
    b = predict_image(project, img, model=m, class_names=CLASSES, save_json=False)["class_probabilities"]
    assert a == b


def test_class_names_saved_in_tensorflow_loader_order(split_project):
    loaded = load_train_dataset(split_project, batch_size=4)
    saved = json.loads((path_of(split_project, "models_dir") / "class_names.json").read_text())
    assert saved == loaded.class_names == sorted(CLASSES)


def test_tflite_export_uses_validation_images_only_and_matches_keras(split_project, tmp_path):
    imgs = export_tflite.select_validation_images(split_project, n=6)
    val_dir = path_of(split_project, "val_dir").resolve()
    assert imgs and all(val_dir in p.resolve().parents for p in imgs)
    src = (ROOT / "src/export_tflite.py").read_text()
    assert "test_locked" not in src and "locked_test_dir" not in src
    # conversion works on the stripped (augmentation-free) model and agrees with Keras
    m = tiny_model()
    inf = strip_augmentation(m)
    assert "augmentation" not in [l.name for l in inf.layers]
    f = tmp_path / "t.tflite"
    f.write_bytes(export_tflite.convert(inf, quantize=False))
    x = np.random.RandomState(0).rand(3, 224, 224, 3).astype("float32") * 255
    np.testing.assert_allclose(export_tflite.tflite_predict(f, x), np.asarray(m(x, training=False)), atol=1e-4)
    q = tmp_path / "q.tflite"
    q.write_bytes(export_tflite.convert(inf, quantize=True))
    assert q.stat().st_size > 0
