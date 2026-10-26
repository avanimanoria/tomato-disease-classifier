# Training summary

## Dataset

- Train images: 3146 — {'early_blight': 699, 'healthy': 1112, 'late_blight': 1335}
- Validation images: 674 — {'early_blight': 149, 'healthy': 239, 'late_blight': 286}
- Class order (TensorFlow loader): ['early_blight', 'healthy', 'late_blight']
- Class weights used: True

## Model

- Architecture: MobileNetV3Small (ImageNet-pretrained base, preprocessing inside the model)
- Parameters: 1,013,363 total, 74,243 trainable (~4.05 MB float32; saved .keras file 5.25 MB)
- Training duration: 567.2 s

## Validation performance

- Stage 1 best: loss 0.1283, accuracy 0.9659, macro F1 0.9592
- Stage 2 best: n/a
- Selected model: **stage1** (rule: lowest validation loss)

## Warnings

- Validation metrics are measured on data that influenced model selection (early stopping, checkpointing); they are optimistic relative to the locked test set.
- Limited data: small datasets give unstable estimates; curated leaf photos differ from real field/drone images.

No locked test-set metrics were used during model training or selection.
