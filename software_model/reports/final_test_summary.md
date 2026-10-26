# Final locked-test evaluation (held-out internal test performance)

Generated: 2026-10-08T20:06:37+00:00  
Model: `C:\Users\avani manoria\OneDrive\Desktop\tomato_disease_classifier\models\best_model.keras`  
Test images: 674

- Loss: 0.0849
- Accuracy: 97.03%
- Macro F1: 0.9649
- Weighted F1: 0.9697

| Class | Precision | Recall | F1 | Support |
|---|---|---|---|---|
| early_blight | 0.992 | 0.880 | 0.933 | 150 |
| healthy | 0.975 | 1.000 | 0.988 | 238 |
| late_blight | 0.956 | 0.993 | 0.974 | 286 |
| **macro avg** | 0.975 | 0.958 | 0.965 | 674 |
| **weighted avg** | 0.971 | 0.970 | 0.970 | 674 |

Confusion matrix (rows = true, cols = predicted; order ['early_blight', 'healthy', 'late_blight']):

```
[[132   5  13]
 [  0 238   0]
 [  1   1 284]]
```

Inference time on this machine (single image): mean 364.9 ms, median 344.0 ms (not Raspberry Pi timings).

The model achieved the reported score on a locked internal test set. This result does not establish field or drone deployment performance unless the test images were independently collected under representative field/drone conditions.

No confidence intervals are reported: none were computed and none are implied.
