#pragma once
// Multi-shift CG for the DTXQCD doubled fermion type.
//
// Solves (M^dag M + sigma_s I) psi_s = src for all shifts s in one Krylov
// pass.  Standard shifted-CG recurrence, ported from Grid's
// ConjugateGradientMultiShift but specialized to DTXQCDFermionDoubled (which
// does not conform to LinearOperatorBase<Field>).  Direct sibling of
// TXQCDMultiShiftCG -- same algorithm, just operating on the doubled
// (upper, lower) × Nf flavor structure.
//
// Caller provides:
//   - any operator Mop with M(in, out) and Mdag(in, out) on DTXQCDFermionDoubled
//     (typically DTXQCDMpcOp),
//   - poles[s] (>= 0, sorted ascending with poles[0] the smallest),
//   - per-shift tolerances tol[s],
//   - src, and an output vector psi of length nshift preallocated on the grid.
//
// On return, psi[s] ~= (M^dag M + poles[s])^{-1} src.

#include <Grid/qcd/action/dtxqcd/DTXQCDFermionDoubled.h>

NAMESPACE_BEGIN(Grid);

namespace dtxqcd_msshift_detail {

// Helpers operating on DTXQCDFermionDoubled per (block, flavor).
inline void Zero_(DTXQCDFermionDoubled &x) {
  for (int a = 0; a < DtxqcdNf; ++a) {
    x.upper.f[a] = Zero();
    x.lower.f[a] = Zero();
  }
}

// y = scale * y + add  (axpy with scale on LHS)
inline void Scale_Add(DTXQCDFermionDoubled &y, RealD scale,
                      const DTXQCDFermionDoubled &add) {
  for (int a = 0; a < DtxqcdNf; ++a) {
    y.upper.f[a] = scale * y.upper.f[a] + add.upper.f[a];
    y.lower.f[a] = scale * y.lower.f[a] + add.lower.f[a];
  }
}

// y += a * x
inline void Axpy(DTXQCDFermionDoubled &y, RealD a,
                 const DTXQCDFermionDoubled &x) {
  for (int aa = 0; aa < DtxqcdNf; ++aa) {
    y.upper.f[aa] = y.upper.f[aa] + a * x.upper.f[aa];
    y.lower.f[aa] = y.lower.f[aa] + a * x.lower.f[aa];
  }
}

// y = coef * src
inline void Set_Scaled(DTXQCDFermionDoubled &y, RealD coef,
                       const DTXQCDFermionDoubled &src) {
  for (int a = 0; a < DtxqcdNf; ++a) {
    y.upper.f[a] = coef * src.upper.f[a];
    y.lower.f[a] = coef * src.lower.f[a];
  }
}

// DTXQCD_FUSED_SHIFT_UPDATE (default 1): the vector updates of the multishift
// loops (p and ps[s] before the operator apply, psi[s] after it) were one Grid
// expression per vector per fermion: ~90 kernels per iteration at 12 shifts,
// each launched and synchronised on its own.  FusedShiftUpdate collects them
// and runs one kernel that evaluates, per site lane, the same Grid expressions
// on the same coalesced site objects as those expression kernels (Scale_Add
// a*y + x, the ps update a*x + b*y, Axpy y + a*x), so the same bits.  =0
// keeps the per-vector expressions.
inline bool FusedShiftUpdateOn() {
  static const bool on = []() {
    const char *e = std::getenv("DTXQCD_FUSED_SHIFT_UPDATE");
    return !(e && *e && std::atoi(e) == 0);
  }();
  return on;
}

enum FusedKind { kScaleAdd = 0, kShiftPs = 1, kAxpy = 2 };

inline LatticeFermion &FermOf(DTXQCDFermionDoubled &f, int k) {
  return (k < DtxqcdNf) ? f.upper.f[k] : f.lower.f[k - DtxqcdNf];
}
inline const LatticeFermion &FermOf(const DTXQCDFermionDoubled &f, int k) {
  return (k < DtxqcdNf) ? f.upper.f[k] : f.lower.f[k - DtxqcdNf];
}

constexpr int kFusedMax = 32;              // updates per kernel
constexpr int kFusedNFerm = 2 * DtxqcdNf;
typedef LatticeFermion::vector_object FusedVobj;

// Kernel arguments, captured by value (~2.7 KB).
struct FusedShiftArgs {
  FusedVobj *y[kFusedMax][kFusedNFerm];
  FusedVobj *x[kFusedMax][kFusedNFerm];
  RealD a[kFusedMax], b[kFusedMax];
  int kind[kFusedMax];
  int n;
};

class FusedShiftUpdate {
 public:
  static constexpr int kMax = kFusedMax;
  static constexpr int kNFerm = kFusedNFerm;
  typedef FusedVobj Vobj;

  // y = a*y + x (kScaleAdd), a*x + b*y (kShiftPs), y + a*x (kAxpy)
  void Add(DTXQCDFermionDoubled &y, const DTXQCDFermionDoubled &x,
           FusedKind kind, RealD a, RealD b = 0.0) {
    GRID_ASSERT(n_ < kMax);
    y_[n_] = &y;
    x_[n_] = &x;
    kind_[n_] = kind;
    a_[n_] = a;
    b_[n_] = b;
    ++n_;
  }

  void Run() {
    if (n_ == 0) return;
    FusedShiftArgs A;
    std::vector<LatticeView<Vobj>> views;
    views.reserve(2 * kMax * kNFerm);
    // One read view per distinct x field (r is shared by all ps updates).
    std::vector<const DTXQCDFermionDoubled *> xs;
    std::vector<int> xslot;
    for (int j = 0; j < n_; ++j) {
      int slot = -1;
      for (size_t i = 0; i < xs.size(); ++i)
        if (xs[i] == x_[j]) slot = (int)i;
      if (slot < 0) {
        slot = (int)xs.size();
        xs.push_back(x_[j]);
        for (int k = 0; k < kNFerm; ++k)
          views.push_back(FermOf(*x_[j], k).View(AcceleratorRead));
      }
      xslot.push_back(slot);
    }
    const size_t nx = views.size();
    for (int j = 0; j < n_; ++j) {
      for (int k = 0; k < kNFerm; ++k) {
        views.push_back(FermOf(*y_[j], k).View(AcceleratorWrite));
        A.y[j][k] = &views.back()[0];
        A.x[j][k] = &views[(size_t)xslot[j] * kNFerm + k][0];
      }
      A.a[j] = a_[j];
      A.b[j] = b_[j];
      A.kind[j] = kind_[j];
    }
    A.n = n_;
    GRID_ASSERT(views.size() == nx + (size_t)n_ * kNFerm);
    const uint64_t osites = y_[0]->Grid()->oSites();
    accelerator_for(idx, osites * kNFerm, Vobj::Nsimd(), {
      const uint64_t ss = idx / kNFerm;
      const int k = (int)(idx % kNFerm);
      for (int j = 0; j < A.n; ++j) {
        auto yy = coalescedRead(A.y[j][k][ss]);
        auto xx = coalescedRead(A.x[j][k][ss]);
        if (A.kind[j] == kScaleAdd)     coalescedWrite(A.y[j][k][ss], A.a[j] * yy + xx);
        else if (A.kind[j] == kShiftPs) coalescedWrite(A.y[j][k][ss], A.a[j] * xx + A.b[j] * yy);
        else                            coalescedWrite(A.y[j][k][ss], yy + A.a[j] * xx);
      }
    });
    for (auto &v : views) v.ViewClose();
    for (int j = 0; j < n_; ++j)
      for (int k = 0; k < kNFerm; ++k)
        FermOf(*y_[j], k).Checkerboard() = FermOf(*x_[j], k).Checkerboard();
    n_ = 0;
  }

 private:
  DTXQCDFermionDoubled *y_[kMax];
  const DTXQCDFermionDoubled *x_[kMax];
  FusedKind kind_[kMax];
  RealD a_[kMax], b_[kMax];
  int n_ = 0;
};

}  // namespace dtxqcd_msshift_detail

template <class DTXQCDMop>
inline void DTXQCDMultiShiftCG(DTXQCDMop &Mop,
                                const std::vector<RealD> &poles,
                                const std::vector<RealD> &tol,
                                const DTXQCDFermionDoubled &src,
                                std::vector<DTXQCDFermionDoubled> &psi,
                                int MaxIter) {
  using namespace dtxqcd_msshift_detail;

  const int nshift = static_cast<int>(poles.size());
  GRID_ASSERT(static_cast<int>(psi.size()) == nshift);
  GRID_ASSERT(static_cast<int>(tol.size()) == nshift);

  GridBase *grid = src.Grid();
  DTXQCDFermionDoubled r(grid), p(grid), mmp(grid), tmp(grid);
  std::vector<DTXQCDFermionDoubled> ps;
  ps.reserve(nshift);
  for (int s = 0; s < nshift; ++s) ps.emplace_back(grid);

  std::vector<RealD> alpha(nshift, 1.0);
  std::vector<RealD> bs(nshift);
  std::vector<RealD> rsq_target(nshift);
  std::vector<std::array<RealD, 2>> z(nshift);
  std::vector<int> converged(nshift, 0);

  for (int s = 0; s < nshift; ++s) GRID_ASSERT(poles[s] >= poles[0]);

  RealD cp = norm2(src);
  if (cp == 0.0) {
    for (int s = 0; s < nshift; ++s) Zero_(psi[s]);
    return;
  }

  for (int s = 0; s < nshift; ++s) {
    rsq_target[s] = cp * tol[s] * tol[s];
    ps[s] = src;
    Zero_(psi[s]);
  }
  r = src;
  p = src;

  // mmp = (M^dag M + poles[0]) p ; d = p^H mmp + poles[0] * ||p||^2
  Mop.M(p, tmp);
  Mop.Mdag(tmp, mmp);
  // d = Re<p, mmp> before the shift is added; rn = |p|^2, one global sum.
  ComplexD dc;
  RealD rn;
  DtxqcdInnerAndNorm2(p, mmp, dc, rn);
  RealD d = real(dc);
  Axpy(mmp, poles[0], p);
  d += rn * poles[0];

  RealD b = -cp / d;

  int iz = 0;
  z[0][0] = 1.0; z[0][1] = 1.0;
  bs[0] = b;
  for (int s = 1; s < nshift; ++s) {
    z[s][0] = 1.0; z[s][1] = 1.0;
    z[s][iz] = 1.0 / (1.0 - b * (poles[s] - poles[0]));
    bs[s] = b * z[s][iz];
  }

  Axpy(r, b, mmp);
  RealD c = norm2(r);

  // psi[s] = -bs[s] * alpha[s] * src
  for (int s = 0; s < nshift; ++s) {
    Set_Scaled(psi[s], -bs[s] * alpha[s], src);
  }

  // DTXQCD_CG_TIMING=1: one line per solve, total vs the DP operator.
  // Timing only.
  static const bool cg_timing = []() {
    const char *e = std::getenv("DTXQCD_CG_TIMING");
    return e && *e && std::atoi(e) != 0;
  }();
  const double t_solve0 = cg_timing ? usecond() : 0;
  double t_op = 0;
  auto print_cg_timing = [&](int k) {
    if (!cg_timing) return;
    std::cout << GridLogMessage << "[DTXQCD-CG timing] double-prec multishift (s): iters=" << k
              << " nshift=" << nshift << " total=" << (usecond() - t_solve0) / 1e6
              << " op=" << t_op / 1e6 << std::endl;
  };

  for (int k = 1; k <= MaxIter; ++k) {
    RealD aa = c / cp;

    if (FusedShiftUpdateOn()) {
      FusedShiftUpdate fu;
      fu.Add(p, r, kScaleAdd, aa);
      for (int s = 0; s < nshift; ++s) {
        if (converged[s]) continue;
        if (s == 0) {
          fu.Add(ps[s], r, kScaleAdd, aa);
        } else {
          RealD as = aa * z[s][iz] * bs[s] / (z[s][1 - iz] * b);
          RealD zc = z[s][iz];
          fu.Add(ps[s], r, kShiftPs, zc, as);
        }
      }
      fu.Run();
    } else {
    Scale_Add(p, aa, r);

    for (int s = 0; s < nshift; ++s) {
      if (converged[s]) continue;
      if (s == 0) {
        Scale_Add(ps[s], aa, r);
      } else {
        RealD as = aa * z[s][iz] * bs[s] / (z[s][1 - iz] * b);
        RealD zc = z[s][iz];
        // ps[s] = zc * r + as * ps[s]
        for (int aa_idx = 0; aa_idx < DtxqcdNf; ++aa_idx) {
          ps[s].upper.f[aa_idx] = zc * r.upper.f[aa_idx]
                                + as * ps[s].upper.f[aa_idx];
          ps[s].lower.f[aa_idx] = zc * r.lower.f[aa_idx]
                                + as * ps[s].lower.f[aa_idx];
        }
      }
    }
    }

    RealD cp_prev = c;
    double t_op0 = 0;
    if (cg_timing) { accelerator_barrier(); t_op0 = usecond(); }
    Mop.M(p, tmp);
    Mop.Mdag(tmp, mmp);
    if (cg_timing) { accelerator_barrier(); t_op += usecond() - t_op0; }
    DtxqcdInnerAndNorm2(p, mmp, dc, rn);
    d = real(dc);
    Axpy(mmp, poles[0], p);
    d += rn * poles[0];

    RealD bp = b;
    b = -cp_prev / d;

    Axpy(r, b, mmp);
    RealD c_new = norm2(r);
    cp = cp_prev;
    c = c_new;

    bs[0] = b;
    iz = 1 - iz;
    for (int s = 1; s < nshift; ++s) {
      if (converged[s]) continue;
      RealD z0 = z[s][1 - iz];
      RealD z1 = z[s][iz];
      z[s][iz] = z0 * z1 * bp /
                 (b * aa * (z1 - z0) + z1 * bp * (1.0 - (poles[s] - poles[0]) * b));
      bs[s] = b * z[s][iz] / z0;
    }

    if (FusedShiftUpdateOn()) {
      FusedShiftUpdate fu;
      for (int s = 0; s < nshift; ++s) {
        if (converged[s]) continue;
        fu.Add(psi[s], ps[s], kAxpy, -bs[s] * alpha[s]);
      }
      fu.Run();
    } else {
      for (int s = 0; s < nshift; ++s) {
        if (converged[s]) continue;
        Axpy(psi[s], -bs[s] * alpha[s], ps[s]);
      }
    }

    int all_converged = 1;
    for (int s = 0; s < nshift; ++s) {
      if (converged[s]) continue;
      RealD css = c * z[s][iz] * z[s][iz];
      if (css < rsq_target[s]) {
        converged[s] = 1;
      } else {
        all_converged = 0;
      }
    }
    if (all_converged) {
      std::cout << GridLogMessage << "[DTXQCDMultiShiftCG] converged iter=" << k
                << " nshift=" << nshift << std::endl;
      print_cg_timing(k);
      return;
    }
  }
  std::cout << GridLogMessage
            << "[DTXQCDMultiShiftCG] did not converge in " << MaxIter
            << " iterations (c=" << c << ")" << std::endl;
  print_cg_timing(MaxIter);
}

NAMESPACE_END(Grid);
