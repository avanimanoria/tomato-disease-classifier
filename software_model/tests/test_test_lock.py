import inspect
import shutil
from pathlib import Path

import pytest

import src.dataset_loader as dl
from src import evaluate
from src.config_loader import load_config, path_of
from src.split_dataset import split_dir, verify_test_lock

ROOT = Path(__file__).resolve().parent.parent


def test_lock_manifest_created_and_verifies(split_project):
    import json
    lock = json.loads(path_of(split_project, "test_lock_manifest").read_text())
    assert lock["total_test_images"] > 0 and lock["manifest_checksum"] and lock["random_seed"] == 42
    assert all(len(e["sha256_hash"]) == 64 and e["source_group"] for e in lock["entries"])
    res = verify_test_lock(split_project)
    assert res["passed"], res["failures"]


def test_verification_catches_changed_test_image_hash(split_project):
    victim = next(split_dir(split_project, "test_locked").rglob("*.png"))
    victim.write_bytes(victim.read_bytes() + b"tamper")
    res = verify_test_lock(split_project)
    assert not res["passed"] and any("SHA-256" in f for f in res["failures"])


def test_verification_catches_missing_file_and_tampered_manifest(split_project):
    next(split_dir(split_project, "test_locked").rglob("*.png")).unlink()
    assert any("missing" in f for f in verify_test_lock(split_project)["failures"])


def test_verification_catches_test_file_copied_into_train(split_project):
    test_file = next(split_dir(split_project, "test_locked").rglob("*.png"))
    shutil.copy(test_file, split_dir(split_project, "train") / test_file.parent.name / "leaked.png")
    res = verify_test_lock(split_project)
    assert not res["passed"] and any("byte-identical" in f for f in res["failures"])


def test_training_refuses_when_lock_fails(split_project):
    from src.train import run_training
    victim = next(split_dir(split_project, "test_locked").rglob("*.png"))
    victim.write_bytes(b"changed")
    with pytest.raises(RuntimeError, match="Test-lock verification FAILED"):
        run_training(split_project)


def test_training_code_never_references_the_locked_test_folder():
    forbidden = ("test_locked", "locked_test_dir", "load_locked_test")
    for f in (ROOT / "src/train.py", ROOT / "scripts/train_model.py"):
        text = f.read_text()
        assert not any(w in text for w in forbidden), f
    for fn in (dl.load_train_dataset, dl.load_val_dataset, dl.load_train_val):
        assert not any(w in inspect.getsource(fn) for w in forbidden), fn.__name__
    with pytest.raises(PermissionError):
        dl._assert_not_locked(Path(ROOT / "data/processed/test_locked"), load_config())


def test_locked_loader_requires_explicit_confirmation(split_project):
    with pytest.raises(PermissionError):
        dl.load_locked_test_dataset(split_project, final_evaluation_confirmed=False)


def test_final_evaluation_refused_without_flag(monkeypatch, capsys):
    def boom(*a, **k):
        raise AssertionError("locked test set must not be loaded without --final-evaluation")
    monkeypatch.setattr(dl, "load_locked_test_dataset", boom)
    rc = evaluate.main(["--split", "test_locked"])
    out = capsys.readouterr().out
    assert rc == 2 and "reserved for FINAL performance measurement" in out and "--final-evaluation" in out
