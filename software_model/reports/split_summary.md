# Split summary

Generated: 2026-10-08T19:28:34+00:00  
Seed: **42**  
Status: **completed** (leakage result: **PASS**)  
Dry run: False

## Class counts by split

| Split | early_blight | healthy | late_blight | Groups |
|---|---|---|---|---|
| train | 699 | 1112 | 1335 | 1238 |
| val | 149 | 239 | 286 | 527 |
| test_locked | 150 | 238 | 286 | 531 |

- Fallback-group images: 1580 (group metadata verified: NO)
- Exact duplicates between splits: 0
- Near duplicates between splits: 0
- Max class-distribution deviation from target: 0.07 percentage points

> WARNING: Source-group metadata is not verified. This split prevents exact/near-duplicate overlap where detected, but cannot guarantee independence by plant, field, or capture session. Final test performance should be called preliminary internal performance.

## Deviation from target ratios

| Split | Class | Target | Actual | Deviation (pp) |
|---|---|---|---|---|
| train | early_blight | 0.70 | 0.700 | +0.04 |
| train | healthy | 0.70 | 0.700 | -0.02 |
| train | late_blight | 0.70 | 0.700 | +0.01 |
| val | early_blight | 0.15 | 0.149 | -0.07 |
| val | healthy | 0.15 | 0.150 | +0.04 |
| val | late_blight | 0.15 | 0.150 | -0.00 |
| test_locked | early_blight | 0.15 | 0.150 | +0.03 |
| test_locked | healthy | 0.15 | 0.150 | -0.02 |
| test_locked | late_blight | 0.15 | 0.150 | -0.00 |

## Source groups per split

- **train** (1238): fallback_0175150e95fb, fallback_0236bd455d6b, fallback_02a112db3ac2, fallback_03dc4df4067b, fallback_03e4852484e3, fallback_03f17efdee14, fallback_040136b2863f, fallback_046430e1180c, fallback_0551434cf769, fallback_0552dc683ba1, fallback_056b8fde9a6e, fallback_05e9c8edb388, fallback_06d4735dcf53, fallback_06db116f0966, fallback_0883694ea35f, fallback_08d5e3891eab, fallback_0966d3c9f37b, fallback_0a01709fadfd, fallback_0a4dc9e761bd, fallback_0a805dc9138a, fallback_0aa15c8429e8, fallback_0b6874127546, fallback_0c00b5604d3c, fallback_0c00ec9a62b6, fallback_0cb81828c0db, fallback_0e12701eeab4, fallback_0e63dd94a92d, fallback_0eed2b25484a, fallback_10244b5e0342, fallback_103a441d339e, fallback_10ae5524f32d, fallback_1135eddfc6b1, fallback_124680b44607, fallback_125cf1e0f630, fallback_1263fb9f9ae2, fallback_1298251a576e, fallback_13936ee6076a, fallback_1426f6b24afc, fallback_144351b9f178, fallback_14c46ddb2ffa, fallback_1562e078c9d4, fallback_161fc4cc5127, fallback_16554a1ea27c, fallback_165c8006faa9, fallback_17454ee1c5df, fallback_1764c9f7e549, fallback_179e92fdd598, fallback_18b2ef5871cb, fallback_198f4efb5c3a, fallback_19ee0fa5940b, ... (+1188 more; full list in split_summary.json)
- **val** (527): fallback_0034396dcc3c, fallback_007c63534d78, fallback_00dd20b47648, fallback_00e3b7ad48ff, fallback_00fce86d0da3, fallback_0298c9602d9c, fallback_04edb678d8c7, fallback_050d599f89c9, fallback_05d8ca73964b, fallback_0631486c71dd, fallback_0675c3ccf462, fallback_06b57f1a7872, fallback_06c48cc70e2e, fallback_06de4c8253f0, fallback_06e49505675f, fallback_074714059017, fallback_07865d6e4df0, fallback_0791f48e1ed2, fallback_0928e36bd1d1, fallback_094ace1db99f, fallback_09d90b58bdee, fallback_09e22765671f, fallback_0a2dac0ead36, fallback_0a8c0a2fb2c7, fallback_0a9ca0f9edb1, fallback_0b2233c55599, fallback_0b5c2cefc319, fallback_0c6a2424f5ef, fallback_0c6e5052c3a0, fallback_0d394343d0b1, fallback_0e5bc2c8473f, fallback_0ef89f4ce821, fallback_0f191fe6f676, fallback_0f8dc5300fa6, fallback_0ffd53ab220f, fallback_10c0db23c9ed, fallback_10de051d2186, fallback_124405d57e3d, fallback_12852b3616bc, fallback_12edd83a78be, fallback_13151d1648ca, fallback_1426bb12d6c8, fallback_1519c0976a05, fallback_15d87a429a90, fallback_15f2bf71b179, fallback_16085fa897f2, fallback_1844e220e128, fallback_189c1a940dc9, fallback_18d571048f2d, fallback_1a00f29acc1d, ... (+477 more; full list in split_summary.json)
- **test_locked** (531): fallback_00a8b9473320, fallback_023e834cdce5, fallback_02672fa00b47, fallback_0270cad8b289, fallback_029336be0a41, fallback_0653a5a10c42, fallback_06e657cc1621, fallback_09a93a2ed587, fallback_0a0137685246, fallback_0a95afc1d400, fallback_0ac24c375609, fallback_0ad6385d6c2b, fallback_0b79b5272c2f, fallback_0c23b1156649, fallback_0ca9bcb7fbb8, fallback_0d50bfcc902d, fallback_0e82831d8182, fallback_0f99bccd27a5, fallback_0fa0465419a2, fallback_1037c01dc188, fallback_103836fbcd68, fallback_103b3ccfcb61, fallback_10f1ecac1df7, fallback_115f774cc4ae, fallback_11aae724ce7c, fallback_11e5bfb41056, fallback_11e782aa3c5c, fallback_12139d4d53e0, fallback_128c9233a6cb, fallback_13de9a9c451b, fallback_141d8e405925, fallback_14a574962e84, fallback_1645b615eba0, fallback_172c63c60335, fallback_187b5e1f454a, fallback_18d56b5e738c, fallback_18f79c41dff5, fallback_18fd4d0253a1, fallback_19b88c52b436, fallback_1abe39348219, fallback_1bd5aecc896c, fallback_1e464fb98b2b, fallback_20ba084eeb30, fallback_20ce85eb6650, fallback_221a67e83d58, fallback_22200d56379a, fallback_226dcd25316b, fallback_226e997aa6e1, fallback_24b017477d68, fallback_25c5152cc614, ... (+481 more; full list in split_summary.json)

## Failures

- none

## Warnings / notes

- 6 image(s) are label-conflict candidates and were EXCLUDED from the split (see reports/split_conflict_review.csv). Resolve them manually in data/raw and rebuild the manifest.
