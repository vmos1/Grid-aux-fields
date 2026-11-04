#pragma once
// Composite Field type for DTXQCD HMC (v2 roster).
//
// Bundles the gauge field U together with the six v2 auxiliary fields
// (sigma, pi, d, n -- each 6x6 color-flavor traceless Hermitian; s, p
// singlet scalars) so the HMC Integrator (templated on one
// FieldImplementation / one Field) can drive them with one shared
// momentum P of the same composite type.
//
// v1 -> v2 change: drop tensor field t; add singlet scalars s, p.
// Aux field storage shapes also change (color-flavor matrices replace
// Pauli triplets) -- see DTXQCDAuxFieldTypes.h for layout.

#include <Grid/qcd/action/dtxqcd/DTXQCDAuxFieldTypes.h>

NAMESPACE_BEGIN(Grid);

struct DTXQCDField {
  LatticeGaugeField   U;      // gauge links
  LatticeDtxqcdSigma  sigma;  // sigma^{ij}_{ab} CF traceless Hermitian
  LatticeDtxqcdPi     pi;     // pi^{ij}_{ab}    CF traceless Hermitian (gamma5)
  LatticeDtxqcdD      d;      // d^{ij}_{ab}     CF traceless Hermitian (off-diagonal, gamma5)
  LatticeDtxqcdN      n;      // n^{ij}_{ab}     CF traceless Hermitian (off-diagonal)
  LatticeDtxqcdS      s;      // s(x)            real singlet scalar
  LatticeDtxqcdP      p;      // p(x)            real singlet scalar (gamma5)

  DTXQCDField(GridBase *grid)
      : U(grid), sigma(grid), pi(grid), d(grid), n(grid), s(grid), p(grid) {}

  GridBase *Grid() const { return U.Grid(); }

  DTXQCDField &operator=(const DTXQCDField &rhs) {
    U = rhs.U;
    sigma = rhs.sigma;
    pi = rhs.pi;
    d = rhs.d;
    n = rhs.n;
    s = rhs.s;
    p = rhs.p;
    return *this;
  }

  DTXQCDField &operator=(const Zero &z) {
    U = Zero();
    sigma = Zero();
    pi = Zero();
    d = Zero();
    n = Zero();
    s = Zero();
    p = Zero();
    return *this;
  }

  DTXQCDField &operator+=(const DTXQCDField &rhs) {
    U += rhs.U;
    sigma += rhs.sigma;
    pi += rhs.pi;
    d += rhs.d;
    n += rhs.n;
    s += rhs.s;
    p += rhs.p;
    return *this;
  }

  DTXQCDField &operator-=(const DTXQCDField &rhs) {
    U -= rhs.U;
    sigma -= rhs.sigma;
    pi -= rhs.pi;
    d -= rhs.d;
    n -= rhs.n;
    s -= rhs.s;
    p -= rhs.p;
    return *this;
  }

  DTXQCDField &operator*=(double ep) {
    U = U * ep;
    sigma = sigma * ep;
    pi = pi * ep;
    d = d * ep;
    n = n * ep;
    s = s * ep;
    p = p * ep;
    return *this;
  }
};

inline DTXQCDField operator+(const DTXQCDField &a, const DTXQCDField &b) {
  DTXQCDField r(a.Grid()); r = a; r += b; return r;
}
inline DTXQCDField operator-(const DTXQCDField &a, const DTXQCDField &b) {
  DTXQCDField r(a.Grid()); r = a; r -= b; return r;
}
inline DTXQCDField operator*(const DTXQCDField &a, double ep) {
  DTXQCDField r(a.Grid()); r = a; r *= ep; return r;
}
inline DTXQCDField operator*(double ep, const DTXQCDField &a) { return a * ep; }

inline RealD norm2(const DTXQCDField &F) {
  return norm2(F.U) + norm2(F.sigma) + norm2(F.pi)
       + norm2(F.d) + norm2(F.n)
       + norm2(F.s) + norm2(F.p);
}

// DTXQCD_FAST_MAXNORM (default 1): Grid's maxLocalNorm2 scans localNorm2 with
// a serial host loop over every local site, one LocalIndexToLocalCoor and one
// peekLocalSite (a host view open) per site: ~2 ms per field at 16^3x48.  The
// integrator calls it on the force and on the level total of every momentum
// update, here on all seven fields of the composite (~1000 updates per
// trajectory).  DtxqcdMaxLocalNorm2 takes the same localNorm2, opens it on the
// host once and scans every lane of every outer site.  A maximum does not
// depend on the scan order: the same value.  =0 calls Grid's maxLocalNorm2.
inline bool DtxqcdFastMaxNormOn() {
  static const bool on = []() {
    const char *e = std::getenv("DTXQCD_FAST_MAXNORM");
    return !(e && *e && std::atoi(e) == 0);
  }();
  return on;
}

template <class vobj>
inline RealD DtxqcdMaxLocalNorm2(const Lattice<vobj> &arg) {
  if (!DtxqcdFastMaxNormOn()) return maxLocalNorm2(arg);
  typedef typename vobj::tensor_reduced vscalar;  // iScalar<...<vector>>
  typedef typename vscalar::scalar_type scalar_type;
  constexpr int Nsimd = vscalar::Nsimd();
  Lattice<vscalar> inner = localNorm2(arg);
  GridBase *grid = arg.Grid();
  const uint64_t osites = grid->oSites();
  RealD max = 0.0;
  {
    autoView(inner_v, inner, CpuRead);
    for (uint64_t o = 0; o < osites; ++o) {
      const scalar_type *v = (const scalar_type *)&inner_v[o];
      for (int l = 0; l < Nsimd; ++l) {
        const RealD r = real(v[l]);
        if ((o == 0 && l == 0) || r > max) max = r;
      }
    }
  }
  grid->GlobalMax(max);
  return max;
}

inline RealD maxLocalNorm2(const DTXQCDField &F) {
  RealD m = DtxqcdMaxLocalNorm2(F.U);
  m = std::max(m, DtxqcdMaxLocalNorm2(F.sigma));
  m = std::max(m, DtxqcdMaxLocalNorm2(F.pi));
  m = std::max(m, DtxqcdMaxLocalNorm2(F.d));
  m = std::max(m, DtxqcdMaxLocalNorm2(F.n));
  m = std::max(m, DtxqcdMaxLocalNorm2(F.s));
  m = std::max(m, DtxqcdMaxLocalNorm2(F.p));
  return m;
}

NAMESPACE_END(Grid);
