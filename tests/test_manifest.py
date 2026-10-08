import pandas as pd
from PIL import Image

from src.manifest import MANIFEST_COLUMNS, SOURCE_TYPE_FALLBACK, SOURCE_TYPE_FOLDER, SOURCE_TYPE_MANUAL, SOURCE_TYPE_TOKEN, build_manifest
from tests.conftest import CLASSES, make_cfg, populate, smooth_random_image
from pathlib import Path


def test_label_comes_from_folder_and_columns_are_complete(project):
    df = build_manifest(project)
    assert list(df.columns)[:len(MANIFEST_COLUMNS)] == MANIFEST_COLUMNS
    assert len(df) == 3 * 8 * 5 and df["is_valid_image"].all()
    for _, r in df.iterrows():
        assert r["relative_path"].split("/")[2] == r["class_label"]
    assert set(df["class_label"]) == set(CLASSES)
    assert (df["source_type"] == SOURCE_TYPE_FOLDER).all()
    assert df["source_group"].str.startswith(tuple(c + "/" for c in CLASSES)).all()


def test_invalid_files_are_flagged_not_hidden(project):
    root = Path(project["_root"]) / "data/raw/healthy"
    (root / "corrupt.jpg").write_bytes(b"this is not an image")
    (root / "empty.png").write_bytes(b"")
    Image.new("RGB", (8, 8)).save(root / "tiny.png")
    (root / "notes.txt").write_text("hello")
    Image.new("L", (64, 64), 128).save(root / "gray.png")
    df = build_manifest(project).set_index("filename")
    assert not df.loc["corrupt.jpg", "is_valid_image"] and "corrupt" in df.loc["corrupt.jpg", "invalid_reason"]
    assert df.loc["empty.png", "invalid_reason"] == "zero_byte_file"
    assert "too_small" in df.loc["tiny.png", "invalid_reason"]
    assert "unsupported_extension" in df.loc["notes.txt", "invalid_reason"]
    assert df.loc["gray.png", "is_valid_image"] and df.loc["gray.png", "image_mode"] == "L"
    assert (root / "corrupt.jpg").exists()  # raw data is never deleted


def test_fallback_and_filename_token_groups(tmp_path):
    cfg = make_cfg(tmp_path)
    populate(cfg, {"healthy": 1}, imgs_per_group=3, flat=True)
    smooth_random_image(999).save(tmp_path / "data/raw/healthy/plant12_leaf3.png")
    df = build_manifest(cfg).set_index("filename")
    assert df.loc["plant12_leaf3.png", "source_type"] == SOURCE_TYPE_TOKEN
    assert df.loc["plant12_leaf3.png", "source_group"] == "healthy/plant12"
    fb = df[df["source_type"] == SOURCE_TYPE_FALLBACK]
    assert len(fb) == 3 and fb["source_group"].str.startswith("fallback_").all()


def test_manual_metadata_survives_regeneration(project):
    from src.config_loader import path_of
    df = build_manifest(project)
    mp = path_of(project, "manifest_path")
    edited = pd.read_csv(mp, dtype=str, keep_default_na=False)
    edited.loc[0, ["source_group", "plant_id", "notes", "capture_date"]] = ["my_real_plant_7", "P7", "checked by hand", "2025-03-01"]
    edited.to_csv(mp, index=False)
    again = build_manifest(project)
    row = again[again["relative_path"] == edited.loc[0, "relative_path"]].iloc[0]
    assert row["source_group"] == "my_real_plant_7" and row["plant_id"] == "P7"
    assert row["notes"] == "checked by hand" and row["capture_date"] == "2025-03-01"
    assert row["source_type"] == SOURCE_TYPE_MANUAL


def test_unrelated_sibling_datasets_excluded(tmp_path):
    from src.config_loader import path_of
    import json
    cfg = make_cfg(tmp_path)
    populate(cfg, {"early_blight": 1, "healthy": 1, "late_blight": 1}, imgs_per_group=2, flat=True)
    
    # Create unrelated sibling datasets under data/raw
    sibling1 = tmp_path / "data/raw/Tomato Disease Dataset/images/GrayMold"
    sibling1.mkdir(parents=True, exist_ok=True)
    smooth_random_image(101).save(sibling1 / "gray1.png")
    
    sibling2 = tmp_path / "data/raw/TomatoDB_CV/Raw Images"
    sibling2.mkdir(parents=True, exist_ok=True)
    smooth_random_image(102).save(sibling2 / "raw1.png")
    
    df = build_manifest(cfg)
    assert len(df) == 6  # only the 3 classes * 2 images
    assert set(df["class_label"]) == {"early_blight", "healthy", "late_blight"}
    assert "Tomato Disease Dataset" not in df["class_label"].values
    assert "TomatoDB_CV" not in df["class_label"].values


def test_leaf_map_grouping_and_fallback(tmp_path):
    import json
    from src.manifest import SOURCE_TYPE_LEAF_MAP
    cfg = make_cfg(tmp_path)
    meta_dir = tmp_path / "data/metadata"
    meta_dir.mkdir(parents=True, exist_ok=True)
    leaf_map_content = {
        "rs_erly.b 8389": ["Tomato___Early_blight:::146.0"]
    }
    (meta_dir / "leaf_map.json").write_text(json.dumps(leaf_map_content))
    
    # Mapped image
    mapped_file = tmp_path / "data/raw/early_blight/uuid123___RS_Erly.B 8389.png"
    smooth_random_image(201).save(mapped_file)
    
    # Unmapped image
    unmapped_file = tmp_path / "data/raw/early_blight/uuid456___GH_HL 9999.png"
    smooth_random_image(202).save(unmapped_file)
    
    df = build_manifest(cfg).set_index("filename")
    
    mapped_row = df.loc["uuid123___RS_Erly.B 8389.png"]
    assert mapped_row["source_type"] == SOURCE_TYPE_LEAF_MAP
    assert mapped_row["source_group"] == "plant_village/early_blight/leaf_146.0"
    assert mapped_row["leaf_id"] == "146.0"
    assert mapped_row["plant_id"] == ""
    
    unmapped_row = df.loc["uuid456___GH_HL 9999.png"]
    assert unmapped_row["source_type"] == SOURCE_TYPE_FALLBACK
    assert unmapped_row["source_group"].startswith("fallback_")
    assert unmapped_row["leaf_id"] == ""
    assert unmapped_row["plant_id"] == ""

