#pragma once
// LOCAL STUB (2026-10-27, Perlmutter reference build; not part of the collaborator's
// commits). dtxqcd-v2 commit b2c28d7a made DTXQCDWilsonCloverFermionEO.h include this
// header and call DtxqcdFusedAuxClover::Enabled() / ApplyFusedAuxCrossClover(...), but
// the file was never committed to the repository (absent on dtxqcd-v2, dtxqcd and
// develop). The fused kernel is an optional optimisation of M(): with it disabled the
// operator takes the legacy six-kernel path AddDiagAndCrossAndClover, "the assembly
// validated in Test_dtxqcd_gamma5_herm_full". This stub keeps it disabled and aborts
// loudly if anything tries to call the fused apply. Replace with the real file once
// the collaborator provides it.
#include <Grid/Grid.h>

NAMESPACE_BEGIN(Grid);

struct DtxqcdFusedAuxClover {
  // The real header presumably reads an environment knob; here the fused path is
  // never available.
  static bool Enabled() { return false; }
};

template <class... Args>
inline void ApplyFusedAuxCrossClover(Args &&...) {
  std::cerr << "ApplyFusedAuxCrossClover: fused aux+clover kernel is not available in this build "
               "(DTXQCDFusedAuxClover.h is a local stub)" << std::endl;
  GRID_ASSERT(0);
}

NAMESPACE_END(Grid);
