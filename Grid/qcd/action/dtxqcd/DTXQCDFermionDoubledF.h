#pragma once
// Single-precision doubled fermion type for DTXQCD mixed-precision solves.
//
// Bit-for-structure twin of DTXQCDFermionDoubled (see DTXQCDFermionDoubled.h)
// built on the single-precision LatticeFermionF instead of LatticeFermion.
// Used ONLY as the inner-iteration field of the reliable-update mixed-
// precision multishift CG (DTXQCDMultiShiftCGMixedPrec.h): all double-
// precision search directions / solutions / residual corrections stay in
// DTXQCDFermionDoubled; the matrix multiply per iteration runs at SP on this
// type via DTXQCDMpcOpF.
//
// Arithmetic, innerProduct, and norm2 mirror the DP definitions exactly
// (componentwise over the (upper, lower) x Nf flavor structure).

#include <Grid/qcd/action/dtxqcd/DTXQCDFermionDoubled.h>

NAMESPACE_BEGIN(Grid);

// Single-precision Nf-flavor doublet (mirror of DTXQCDFermionNf on
// LatticeFermionF).
struct DTXQCDFermionNfF {
  std::array<LatticeFermionF, DtxqcdNf> f;

  template <std::size_t... Is>
  static std::array<LatticeFermionF, DtxqcdNf> MakeArray(
      GridBase *grid, std::index_sequence<Is...>) {
    return std::array<LatticeFermionF, DtxqcdNf>{
        {(static_cast<void>(Is), LatticeFermionF(grid))...}};
  }

  DTXQCDFermionNfF(GridBase *grid)
      : f(MakeArray(grid, std::make_index_sequence<DtxqcdNf>{})) {}

  GridBase *Grid() const { return f[0].Grid(); }

  DTXQCDFermionNfF &operator=(const Zero &) {
    for (auto &ff : f) ff = Zero();
    return *this;
  }
  DTXQCDFermionNfF &operator=(const DTXQCDFermionNfF &rhs) {
    for (int a = 0; a < DtxqcdNf; ++a) f[a] = rhs.f[a];
    return *this;
  }
};

inline ComplexD innerProduct(const DTXQCDFermionNfF &x,
                             const DTXQCDFermionNfF &y) {
  ComplexD acc = 0.0;
  for (int a = 0; a < DtxqcdNf; ++a) acc += innerProduct(x.f[a], y.f[a]);
  return acc;
}
inline RealD norm2(const DTXQCDFermionNfF &x) {
  RealD n = 0.0;
  for (int a = 0; a < DtxqcdNf; ++a) n += norm2(x.f[a]);
  return n;
}

// Single-precision doubled fermion (mirror of DTXQCDFermionDoubled).
struct DTXQCDFermionDoubledF {
  DTXQCDFermionNfF upper;
  DTXQCDFermionNfF lower;

  DTXQCDFermionDoubledF(GridBase *grid) : upper(grid), lower(grid) {}

  GridBase *Grid() const { return upper.Grid(); }

  DTXQCDFermionDoubledF &operator=(const Zero &) {
    for (int a = 0; a < DtxqcdNf; ++a) {
      upper.f[a] = Zero();
      lower.f[a] = Zero();
    }
    return *this;
  }
  DTXQCDFermionDoubledF &operator=(const DTXQCDFermionDoubledF &rhs) {
    for (int a = 0; a < DtxqcdNf; ++a) {
      upper.f[a] = rhs.upper.f[a];
      lower.f[a] = rhs.lower.f[a];
    }
    return *this;
  }
};

inline ComplexD innerProduct(const DTXQCDFermionDoubledF &a,
                             const DTXQCDFermionDoubledF &b) {
  return innerProduct(a.upper, b.upper) + innerProduct(a.lower, b.lower);
}

inline RealD norm2(const DTXQCDFermionDoubledF &a) {
  return norm2(a.upper) + norm2(a.lower);
}

// -------- precision conversion (DP <-> SP) for the doubled field --------
//
// Each LatticeFermion <-> LatticeFermionF conversion goes through Grid's
// generic precisionChange (component-wise; SIMD-layout-aware).  Checkerboard
// is propagated so the result stays a valid CB fermion.

inline void DtxqcdPrecisionChange(DTXQCDFermionDoubledF &out,
                                  const DTXQCDFermionDoubled &in) {
  for (int a = 0; a < DtxqcdNf; ++a) {
    precisionChange(out.upper.f[a], in.upper.f[a]);
    precisionChange(out.lower.f[a], in.lower.f[a]);
    out.upper.f[a].Checkerboard() = in.upper.f[a].Checkerboard();
    out.lower.f[a].Checkerboard() = in.lower.f[a].Checkerboard();
  }
}

inline void DtxqcdPrecisionChange(DTXQCDFermionDoubled &out,
                                  const DTXQCDFermionDoubledF &in) {
  for (int a = 0; a < DtxqcdNf; ++a) {
    precisionChange(out.upper.f[a], in.upper.f[a]);
    precisionChange(out.lower.f[a], in.lower.f[a]);
    out.upper.f[a].Checkerboard() = in.upper.f[a].Checkerboard();
    out.lower.f[a].Checkerboard() = in.lower.f[a].Checkerboard();
  }
}

// DTXQCD_PC_WORKSPACE (default 1): the two-argument precisionChange above
// rebuilds its site/lane map on the host, and allocates, copies and frees a
// device copy of it, on every call (Lattice_transfer.h); at 16^3x48 that is
// ~0.11 ms per LatticeFermion, ~20x the copy.  Grid's own mixed-precision CGs
// build the map once per solve.  DtxqcdPrecisionMaps holds that pair for one
// (DP grid, SP grid) and the overloads below use it.  Same map, same copyLane
// kernel: bit-identical to =0, which keeps the per-call maps.  A field on any
// other grid takes the per-call path (the map checks grid identity).
inline bool DtxqcdPcWorkspaceOn() {
  static const bool on = []() {
    const char *e = std::getenv("DTXQCD_PC_WORKSPACE");
    return !(e && *e && std::atoi(e) == 0);
  }();
  return on;
}

struct DtxqcdPrecisionMaps {
  GridBase *grid_d;
  GridBase *grid_f;
  std::unique_ptr<precisionChangeWorkspace> to_f;  // DP -> SP (out on grid_f)
  std::unique_ptr<precisionChangeWorkspace> to_d;  // SP -> DP (out on grid_d)
  DtxqcdPrecisionMaps(GridBase *gd, GridBase *gf) : grid_d(gd), grid_f(gf) {
    if (DtxqcdPcWorkspaceOn()) {
      to_f.reset(new precisionChangeWorkspace(grid_f, grid_d));
      to_d.reset(new precisionChangeWorkspace(grid_d, grid_f));
    }
  }
};

// DTXQCD_PC_LANE_KERNEL (default 1): the copy itself.  Grid's workspace
// precisionChange runs one thread per output site looping over its lanes
// (~32 us per LatticeFermion at 16^3x48, ~6x the bytes moved).  This kernel
// runs one thread per (output site, vector word, lane) with the same map and
// the same per-element conversion as Grid's copyLane (otmp = itmp), so the
// same bits.  =0 calls Grid's precisionChange with the workspace.
inline bool DtxqcdPcLaneKernelOn() {
  static const bool on = []() {
    const char *e = std::getenv("DTXQCD_PC_LANE_KERNEL");
    return !(e && *e && std::atoi(e) == 0);
  }();
  return on;
}

template <class VobjOut, class VobjIn>
inline void DtxqcdPrecisionChangeLanes(Lattice<VobjOut> &out,
                                       const Lattice<VobjIn> &in,
                                       const precisionChangeWorkspace &wk) {
  if (!DtxqcdPcLaneKernelOn()) {
    precisionChange(out, in, wk);
    return;
  }
  typedef typename VobjOut::vector_type ovector_type;
  typedef typename VobjIn::vector_type  ivector_type;
  typedef typename VobjOut::scalar_type oscalar_type;
  typedef typename VobjIn::scalar_type  iscalar_type;
  constexpr int Nsimd_out = VobjOut::Nsimd();
  constexpr int words = sizeof(VobjOut) / sizeof(ovector_type);
  static_assert(words == sizeof(VobjIn) / sizeof(ivector_type),
                "DtxqcdPrecisionChangeLanes: word counts differ");
  out.Checkerboard() = in.Checkerboard();
  wk.checkGrids(out.Grid(), in.Grid());
  const std::pair<Integer, Integer> *fmap = wk.getMap();
  autoView(out_v, out, AcceleratorWrite);
  autoView(in_v, in, AcceleratorRead);
  accelerator_for(idx, out.Grid()->oSites() * words, Nsimd_out, {
    const uint64_t oo = idx / words;
    const int w = (int)(idx % words);
    const int lane = acceleratorSIMTlane(Nsimd_out);
    const std::pair<Integer, Integer> m = fmap[oo * Nsimd_out + lane];
    const ivector_type *ip = (const ivector_type *)&in_v[m.first];
    ovector_type *op = (ovector_type *)&out_v[oo];
    iscalar_type itmp = ip[w].getlane(m.second);
    oscalar_type otmp = itmp;  // the precision change, as in copyLane
    op[w].putlane(otmp, lane);
  });
}

inline void DtxqcdPrecisionChange(DTXQCDFermionDoubledF &out,
                                  const DTXQCDFermionDoubled &in,
                                  const DtxqcdPrecisionMaps &maps) {
  if (!maps.to_f || out.Grid() != maps.grid_f || in.Grid() != maps.grid_d) {
    DtxqcdPrecisionChange(out, in);
    return;
  }
  for (int a = 0; a < DtxqcdNf; ++a) {
    DtxqcdPrecisionChangeLanes(out.upper.f[a], in.upper.f[a], *maps.to_f);
    DtxqcdPrecisionChangeLanes(out.lower.f[a], in.lower.f[a], *maps.to_f);
    out.upper.f[a].Checkerboard() = in.upper.f[a].Checkerboard();
    out.lower.f[a].Checkerboard() = in.lower.f[a].Checkerboard();
  }
}

inline void DtxqcdPrecisionChange(DTXQCDFermionDoubled &out,
                                  const DTXQCDFermionDoubledF &in,
                                  const DtxqcdPrecisionMaps &maps) {
  if (!maps.to_d || out.Grid() != maps.grid_d || in.Grid() != maps.grid_f) {
    DtxqcdPrecisionChange(out, in);
    return;
  }
  for (int a = 0; a < DtxqcdNf; ++a) {
    DtxqcdPrecisionChangeLanes(out.upper.f[a], in.upper.f[a], *maps.to_d);
    DtxqcdPrecisionChangeLanes(out.lower.f[a], in.lower.f[a], *maps.to_d);
    out.upper.f[a].Checkerboard() = in.upper.f[a].Checkerboard();
    out.lower.f[a].Checkerboard() = in.lower.f[a].Checkerboard();
  }
}

NAMESPACE_END(Grid);
