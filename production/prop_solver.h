#pragma once
// Wrapper for Wilson-clover propagator solves with Grid's ConjugateGradient on
// M†M (pure Grid; the hybrid tree of 2026 could switch to an external inverter).
//
// Use:
//   WCF Dw(...); MdagMLinearOperator<WCF, LatticeFermion> HermOp(Dw);
//   PropSolver<WCF> solver(Dw, HermOp, U_smeared,
//                              mass, csw, cg_tol, cg_max);
//   solver.solve(src, x);  // src is the unaugmented source — NOT Mdag·src.
//
// The solver internally does Dw.Mdag(src, b); CG(HermOp, b, x).

#include <Grid/Grid.h>
#include <Grid/qcd/action/fermion/WilsonCloverFermion.h>
#include <Grid/qcd/action/fermion/CloverHelpers.h>


namespace Grid {

template <class WCF>
class PropSolver {
public:
  PropSolver(WCF &Dw,
                 MdagMLinearOperator<WCF, LatticeFermion> &HermOp,
                 const LatticeGaugeField &Usm,
                 RealD mass, RealD csw,
                 RealD tol, int max_iter,
                 bool anti_periodic_t = true)
    : Dw_(Dw), HermOp_(HermOp), grid_(Usm.Grid()), CG_(tol, max_iter)
  {
  }

  void solve(const LatticeFermion &src, LatticeFermion &x) {
    LatticeFermion b(grid_);
    Dw_.Mdag(src, b);
    x = Zero();
    CG_(HermOp_, b, x);
  }

  // Multi-source: solve M·x_i = src_i for i = 0..N-1, all on the same gauge,
  // as a sequential loop over solve().
  void solve_multi(const std::vector<LatticeFermion> &src,
                   std::vector<LatticeFermion> &x) {
    int N = (int)src.size();
    GRID_ASSERT(N > 0);
    GRID_ASSERT((int)x.size() == N);

    // Grid fallback: sequential loop.
    for (int i = 0; i < N; ++i) solve(src[i], x[i]);
  }

private:
  WCF &Dw_;
  MdagMLinearOperator<WCF, LatticeFermion> &HermOp_;
  GridBase *grid_;
  ConjugateGradient<LatticeFermion> CG_;
};

}  // namespace Grid
