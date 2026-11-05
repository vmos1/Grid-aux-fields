#pragma once
// Doubled fermion type for DTXQCD: pair of DTXQCDFermionNf (Nf=2 doublets)
// for the upper and lower components of the Cstar doubled Dirac spinor.
//
// Arithmetic is defined componentwise.  innerProduct and norm2 sum over
// the upper and lower parts, matching the natural inner product on the
// 2 x Nf x 4 x Nc x V doubled vector space.

#include <Grid/qcd/action/dtxqcd/DTXQCDDeltaOp.h>

NAMESPACE_BEGIN(Grid);

struct DTXQCDFermionDoubled {
  DTXQCDFermionNf upper;
  DTXQCDFermionNf lower;

  DTXQCDFermionDoubled(GridBase *grid) : upper(grid), lower(grid) {}

  GridBase *Grid() const { return upper.Grid(); }

  DTXQCDFermionDoubled &operator=(const Zero &) {
    for (int a = 0; a < DtxqcdNf; ++a) {
      upper.f[a] = Zero();
      lower.f[a] = Zero();
    }
    return *this;
  }
  DTXQCDFermionDoubled &operator=(const DTXQCDFermionDoubled &rhs) {
    for (int a = 0; a < DtxqcdNf; ++a) {
      upper.f[a] = rhs.upper.f[a];
      lower.f[a] = rhs.lower.f[a];
    }
    return *this;
  }
};

// DTXQCD_FUSED_REDUCE (default 1): one global sum per doubled-vector
// reduction instead of one per fermion.  Grid's innerProduct is
// rankInnerProduct (rank-local) followed by GlobalSumP2P, a fixed-order sum
// over the ranks templated on the summed object; a struct of the per-fermion
// rank values with an elementwise + is therefore summed element by element in
// that same order.  The global per-fermion values are then combined exactly as
// the per-fermion code does (0.0 += upper f[0], f[1]; 0.0 += lower ...;
// upper + lower), so the bits are the same.  =0: one global sum per fermion.
inline bool DtxqcdFusedReduceOn() {
  static const bool on = []() {
    const char *e = std::getenv("DTXQCD_FUSED_REDUCE");
    return !(e && *e && std::atoi(e) == 0);
  }();
  return on;
}

template <int N>
struct DtxqcdComplexSums {
  ComplexD v[N];
  DtxqcdComplexSums operator+(const DtxqcdComplexSums &o) const {
    DtxqcdComplexSums r;
    for (int i = 0; i < N; ++i) r.v[i] = v[i] + o.v[i];
    return r;
  }
};

// Rank-local inner products of the 2*Nf fermions into v[off..off+2*Nf-1]:
// upper f[0..Nf-1], then lower f[0..Nf-1].
template <int N>
inline void DtxqcdRankInnerProducts(const DTXQCDFermionDoubled &a,
                                    const DTXQCDFermionDoubled &b,
                                    DtxqcdComplexSums<N> &s, int off) {
  for (int k = 0; k < DtxqcdNf; ++k) {
    s.v[off + k]            = rankInnerProduct(a.upper.f[k], b.upper.f[k]);
    s.v[off + DtxqcdNf + k] = rankInnerProduct(a.lower.f[k], b.lower.f[k]);
  }
}

// The combinations of innerProduct / norm2 over DTXQCDFermionNf below.
template <int N>
inline ComplexD DtxqcdCombineInner(const DtxqcdComplexSums<N> &s, int off) {
  ComplexD up = 0.0, lo = 0.0;
  for (int k = 0; k < DtxqcdNf; ++k) up += s.v[off + k];
  for (int k = 0; k < DtxqcdNf; ++k) lo += s.v[off + DtxqcdNf + k];
  return up + lo;
}
template <int N>
inline RealD DtxqcdCombineNorm2(const DtxqcdComplexSums<N> &s, int off) {
  RealD up = 0.0, lo = 0.0;
  for (int k = 0; k < DtxqcdNf; ++k) up += real(s.v[off + k]);
  for (int k = 0; k < DtxqcdNf; ++k) lo += real(s.v[off + DtxqcdNf + k]);
  return up + lo;
}

inline ComplexD innerProduct(const DTXQCDFermionDoubled &a,
                             const DTXQCDFermionDoubled &b) {
  if (!DtxqcdFusedReduceOn())
    return innerProduct(a.upper, b.upper) + innerProduct(a.lower, b.lower);
  DtxqcdComplexSums<2 * DtxqcdNf> s;
  DtxqcdRankInnerProducts(a, b, s, 0);
  a.Grid()->GlobalSumP2P(s);
  return DtxqcdCombineInner(s, 0);
}

inline RealD norm2(const DTXQCDFermionDoubled &a) {
  if (!DtxqcdFusedReduceOn()) return norm2(a.upper) + norm2(a.lower);
  DtxqcdComplexSums<2 * DtxqcdNf> s;
  DtxqcdRankInnerProducts(a, a, s, 0);
  a.Grid()->GlobalSumP2P(s);
  return DtxqcdCombineNorm2(s, 0);
}

// ip = innerProduct(p, q) and n2 = norm2(p) with one global sum (the CG
// computes both from the same p).
inline void DtxqcdInnerAndNorm2(const DTXQCDFermionDoubled &p,
                                const DTXQCDFermionDoubled &q,
                                ComplexD &ip, RealD &n2) {
  if (!DtxqcdFusedReduceOn()) {
    ip = innerProduct(p, q);
    n2 = norm2(p);
    return;
  }
  DtxqcdComplexSums<4 * DtxqcdNf> s;
  DtxqcdRankInnerProducts(p, q, s, 0);
  DtxqcdRankInnerProducts(p, p, s, 2 * DtxqcdNf);
  p.Grid()->GlobalSumP2P(s);
  ip = DtxqcdCombineInner(s, 0);
  n2 = DtxqcdCombineNorm2(s, 2 * DtxqcdNf);
}

NAMESPACE_END(Grid);
