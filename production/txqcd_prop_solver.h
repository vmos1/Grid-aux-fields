#pragma once
// Propagator solver for the TXQCD measurement codes: solves M_TXQCD · x = src on
// the full volume with Grid's own conjugate gradient on M†M (the operator carries
// the diagonal Δ insertion: flavor / spin / color / tensor).
//
// API mirroring prop_solver.h::PropSolver:
//   TxqcdPropSolver solver(Mop, mass, csw, Usm, tol, max_iter);
//   solver.solve(src, x);
//
// (The hybrid tree of 2026 had a defect-correction variant preconditioned by an
//  external clover inverter; this pure-Grid tree keeps only the Grid CG path.)

#include <Grid/Grid.h>
#include <Grid/qcd/action/fermion/WilsonCloverFermion.h>
#include <Grid/qcd/action/fermion/CloverHelpers.h>
#include <Grid/qcd/action/txqcd/TXQCDWilsonCloverOp.h>
#include <Grid/qcd/action/txqcd/AuxFieldTypes.h>
#include <array>
#include <memory>
#include <vector>


namespace Grid {

class TxqcdPropSolver {
public:
  TxqcdPropSolver(TXQCDWilsonCloverOp &Mop,
                       const std::array<RealD, TxqcdNf> &mass,
                       RealD csw,
                       const LatticeGaugeField &Usm,
                       RealD tol, int max_iter,
                       bool anti_periodic_t = true)
      : Mop_(Mop), mass_(mass), csw_(csw),
        Usm_(Usm), tol_(tol), max_iter_(max_iter)
  {
  }

  // Solve M_TXQCD · x = src.  Caller does NOT need to apply Mdag first.
  void solve(const TXQCDFermionNf &src, TXQCDFermionNf &x) {
    solve_grid_cg(src, x);
  }

private:
  TXQCDWilsonCloverOp &Mop_;
  std::array<RealD, TxqcdNf> mass_;
  RealD csw_;
  const LatticeGaugeField &Usm_;
  RealD tol_;
  int max_iter_;

  std::array<int, TxqcdNf> mass_to_idx_;


  // Full-volume Grid TxqcdCG that solves M†M·x = M†·src.
  void solve_grid_cg(const TXQCDFermionNf &src, TXQCDFermionNf &x) {
    GridBase *g = src.Grid();
    TXQCDFermionNf b(g), r(g), p(g), Mp(g), MdMp(g);
    Mop_.Mdag(src, b);
    x = Zero();
    r = b;
    p = r;
    RealD rsq = norm2(r);
    RealD bsq = std::max(norm2(b), 1e-30);
    RealD tol2 = tol_ * tol_ * bsq;
    for (int it = 0; it < max_iter_; ++it) {
      Mop_.M(p, Mp);
      Mop_.Mdag(Mp, MdMp);
      ComplexD pAp = innerProduct(p, MdMp);
      ComplexD alpha = ComplexD(rsq, 0.0) / pAp;
      axpy(x, alpha, p);
      axpy(r, -alpha, MdMp);
      RealD rsq_new = norm2(r);
      if (rsq_new < tol2) break;
      RealD beta_cg = rsq_new / rsq;
      for (int a = 0; a < TxqcdNf; ++a) p.f[a] = r.f[a] + beta_cg * p.f[a];
      rsq = rsq_new;
    }
  }
};

}  // namespace Grid
