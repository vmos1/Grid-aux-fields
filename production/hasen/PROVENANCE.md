# Provenance of the pure-Grid HMC project code

Source of record: repository `grid-lqcd-workflow` (vmos1), branch
`hasenbusch-tune-compact`, commit `0229c9e` (2026-10-26), directory
`5_studies/hasenbusch_tune/`. Every file below was copied byte-identical from that
commit, then only the include lines listed under "Rewrites" were changed.

## File map (source under `5_studies/hasenbusch_tune/`, destination in this tree)

| Source | Destination |
|---|---|
| `include/Grid/qcd/action/pseudofermion/TwoFlavourSchurCloverAction.h` | `Grid/qcd/action/pseudofermion/TwoFlavourSchurCloverAction.h` |
| `include/Grid/qcd/action/pseudofermion/TwoFlavourSchurCloverRatioAction.h` | `Grid/qcd/action/pseudofermion/TwoFlavourSchurCloverRatioAction.h` |
| `include/Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalAction.h` | `Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalAction.h` |
| `include/Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalActionMP.h` | `Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalActionMP.h` |
| `include/Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalActionEven.h` | `Grid/qcd/action/pseudofermion/OneFlavourSchurCloverRationalActionEven.h` |
| `include/Grid/qcd/action/pseudofermion/QCDLogDetCompactCloverEOAction.h` | `Grid/qcd/action/pseudofermion/QCDLogDetCompactCloverEOAction.h` |
| `src/clover_force/fused_clover_force.h` | `Grid/qcd/action/pseudofermion/hasen/fused_clover_force.h` |
| `src/clover_force/clover_cmunu.h` | `Grid/qcd/action/pseudofermion/hasen/clover_cmunu.h` |
| `src/gauge_import/import_guard.h` | `Grid/qcd/action/pseudofermion/hasen/import_guard.h` |
| `src/gauge_import/fast_import.h` | `Grid/qcd/action/pseudofermion/hasen/fast_import.h` |
| `src/gen_qcd_hasenbusch_tune_compact_schur.cc` | `production/hasen/gen_qcd_hasenbusch_tune_compact_schur.cc` |
| `include/params.h` | `production/hasen/params.h` |
| `src/grid_mg/` (whole directory, incl. its own `PROVENANCE.md`) | `production/hasen/src/grid_mg/` |
| `src/clover_force/test_fused_clover_force.cc`, `test_cmunu_stencil.cc` | `production/hasen/tests/` |
| `src/gauge_import/test_fast_import.cc` | `production/hasen/tests/` |
| `perlmutter/{smoke16,traj48,traj48_batch,forces48,forces16}_puregrid.sh`, `gate16_levels_m9.sh`, `gate16_stiffness_m10.sh`, `run_test_grid_mg.sh`, `build_test_grid_mg.sh`, `build_test_fused_clover.sh` | `production/hasen/perlmutter/` (verbatim; paths still point at the `grid_qcd` workspace, adapted copies live beside the build scripts) |
| `data_extraction_scripts/compare_smoke_logs.py` | `production/hasen/tools/` |

## Rewrites (the only edits)

The four helper headers used to live outside Grid and were found through `-I src`.
They now live inside the tree, so every include of them was changed, in the six action
headers, the four helpers, the driver and the three tests:

```
"clover_force/fused_clover_force.h"  ->  <Grid/qcd/action/pseudofermion/hasen/fused_clover_force.h>
"clover_force/clover_cmunu.h"        ->  <Grid/qcd/action/pseudofermion/hasen/clover_cmunu.h>
"gauge_import/import_guard.h"        ->  <Grid/qcd/action/pseudofermion/hasen/import_guard.h>
"gauge_import/fast_import.h"         ->  <Grid/qcd/action/pseudofermion/hasen/fast_import.h>
```

The driver's `"params.h"` and `"grid_mg/..."` includes are unchanged and resolve through
`-I production/hasen -I production/hasen/src`.

## Lineage of the six action headers

Originally copied from the Grid-TXQCD fork at its commit `b2c7d9d2` (2026-07-22) and
edited since in `grid-lqcd-workflow` (fused clover force, gauge-import guard, rational
extras, strange log-det parity, strange interval fix). Their `include/PROVENANCE.md` in
`grid-lqcd-workflow` holds the per-file history. From this commit on, this tree is the
upstream of record for them.

## Grid core

The Grid tree is stock `paboyle/Grid` commit `3d3eff86` (develop, 2026-06-11) plus the
eight `core:` commits that precede this one, which are the patch series
`grid-lqcd-workflow/1_build_grid/patches/stock-grid-3d3eff86/01..08` applied in order.
Verified 2026-10-26: the `Grid/` sources of this tree are byte-identical to the staged
tree that built the production binary `gen_qcd_hasenbusch_tune_compact_schur_stock_m8`.
