/*************************************************************************************

    Grid physics library, www.github.com/paboyle/Grid

    Source file: ./lib/qcd/action/fermion/CompactWilsonCloverFermion.h

    Copyright (C) 2020 - 2022

    Author: Daniel Richtmann <daniel.richtmann@gmail.com>
    Author: Nils Meyer <nils.meyer@ur.de>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

    See the full license in the file "LICENSE" in the top level distribution directory
    *************************************************************************************/
/*  END LEGAL */

#pragma once

#include <Grid/qcd/action/fermion/WilsonCloverTypes.h>
#include <Grid/qcd/action/fermion/WilsonCloverHelpers.h>
#include <Grid/qcd/action/fermion/CloverHelpers.h>

NAMESPACE_BEGIN(Grid);

// see Grid/qcd/action/fermion/WilsonCloverFermion.h for description
//
// Modifications done here:
//
// Original: clover term = 12x12 matrix per site
//
// But: Only two diagonal 6x6 hermitian blocks are non-zero (also true for original, verified by running)
// Sufficient to store/transfer only the real parts of the diagonal and one triangular part
// 2 * (6 + 15 * 2) = 72 real or 36 complex words to be stored/transfered
//
// Here: Above but diagonal as complex numbers, i.e., need to store/transfer
// 2 * (6 * 2 + 15 * 2) = 84 real or 42 complex words
//
// Words per site and improvement compared to original (combined with the input and output spinors):
//
// - Original: 2*12 + 12*12 = 168 words -> 1.00 x less
// - Minimal:  2*12 + 36    =  60 words -> 2.80 x less
// - Here:     2*12 + 42    =  66 words -> 2.55 x less
//
// These improvements directly translate to wall-clock time
//
// Data layout:
//
// - diagonal and triangle part as separate lattice fields,
//   this was faster than as 1 combined field on all tested machines
// - diagonal: as expected
// - triangle: store upper right triangle in row major order
// - graphical:
//        0  1  2  3  4
//           5  6  7  8
//              9 10 11 = upper right triangle indices
//                12 13
//                   14
//     0
//        1
//           2
//              3       = diagonal indices
//                 4
//                    5
//     0
//     1  5
//     2  6  9          = lower left triangle indices
//     3  7 10 12
//     4  8 11 13 14
//
// Impact on total memory consumption:
// - Original: (2 * 1 + 8 * 1/2) 12x12 matrices = 6 12x12 matrices = 864 complex words per site
// - Here:     (2 * 1 + 4 * 1/2) diagonal parts = 4 diagonal parts =  24 complex words per site
//           + (2 * 1 + 4 * 1/2) triangle parts = 4 triangle parts =  60 complex words per site
//                                                                 =  84 complex words per site

// Shared fields (SharedOperatorFields.h). The full-volume clover fields: import scratch, one set
// per Impl and full grid when shared. The off-diagonal halves: one set per link set, csw and
// anisotropy when shared (standard clover only).
template<class Impl>
struct CompactCloverFullStore {
  typedef typename CompactWilsonCloverTypes<Impl>::CloverDiagonalField CloverDiagonalField;
  typedef typename CompactWilsonCloverTypes<Impl>::CloverTriangleField CloverTriangleField;
  CloverDiagonalField Diagonal, DiagonalInv;
  CloverTriangleField Triangle, TriangleInv;
  CompactCloverFullStore(GridBase *F) : Diagonal(F), DiagonalInv(F), Triangle(F), TriangleInv(F) {}
};

template<class Impl>
struct CompactCloverTriangleStore {
  typedef typename CompactWilsonCloverTypes<Impl>::CloverTriangleField CloverTriangleField;
  CloverTriangleField TriangleEven, TriangleOdd;
  SharedFieldTag tag;
  std::shared_ptr<void> links;  // keeps the link set of the key alive
  CompactCloverTriangleStore(GridBase *H, std::shared_ptr<void> l) : TriangleEven(H), TriangleOdd(H), links(l) {}
};

struct CompactCloverFullKey {
  GridBase *F = nullptr;
  bool operator==(const CompactCloverFullKey &o) const { return F == o.F; }
};

struct CompactCloverTriangleKey {
  const void *links = nullptr;
  GridBase *H = nullptr;
  double csw_r = 0.0, csw_t = 0.0, cF = 0.0;
  bool aniso = false;
  int t_direction = 0;
  double xi_0 = 0.0, nu = 0.0;
  bool operator==(const CompactCloverTriangleKey &o) const {
    return links == o.links && H == o.H && csw_r == o.csw_r && csw_t == o.csw_t && cF == o.cF &&
           aniso == o.aniso && t_direction == o.t_direction && xi_0 == o.xi_0 && nu == o.nu;
  }
};

template<class Impl, class CloverHelpers>
class CompactWilsonCloverFermion : public WilsonFermion<Impl>,
                                   public WilsonCloverHelpers<Impl>,
                                   public CompactWilsonCloverHelpers<Impl> {
  /////////////////////////////////////////////
  // Sizes
  /////////////////////////////////////////////

public:

  INHERIT_COMPACT_CLOVER_SIZES(Impl);

  /////////////////////////////////////////////
  // Type definitions
  /////////////////////////////////////////////

public:

  INHERIT_IMPL_TYPES(Impl);
  INHERIT_CLOVER_TYPES(Impl);
  INHERIT_COMPACT_CLOVER_TYPES(Impl);

  typedef WilsonFermion<Impl>              WilsonBase;
  typedef WilsonCloverHelpers<Impl>        Helpers;
  typedef CompactWilsonCloverHelpers<Impl> CompactHelpers;

  /////////////////////////////////////////////
  // Constructors
  /////////////////////////////////////////////

public:

  CompactWilsonCloverFermion(GaugeField& _Umu,
			    GridCartesian& Fgrid,
			    GridRedBlackCartesian& Hgrid,
			    const RealD _mass,
			    const RealD _csw_r = 0.0,
			    const RealD _csw_t = 0.0,
			    const RealD _cF = 1.0,
			    const WilsonAnisotropyCoefficients& clover_anisotropy = WilsonAnisotropyCoefficients(),
			    const ImplParams& impl_p = ImplParams());

  /////////////////////////////////////////////
  // Member functions (implementing interface)
  /////////////////////////////////////////////

public:

  virtual void Instantiatable() {};
  int          ConstEE()     override { return 0; };
  int          isTrivialEE() override { return 0; };

  void Dhop(const FermionField& in, FermionField& out, int dag) override;

  void DhopOE(const FermionField& in, FermionField& out, int dag) override;

  void DhopEO(const FermionField& in, FermionField& out, int dag) override;

  void DhopDir(const FermionField& in, FermionField& out, int dir, int disp) override;

  void DhopDirAll(const FermionField& in, std::vector<FermionField>& out) /* override */;

  void M(const FermionField& in, FermionField& out) override;

  void Mdag(const FermionField& in, FermionField& out) override;

  void Meooe(const FermionField& in, FermionField& out) override;

  void MeooeDag(const FermionField& in, FermionField& out) override;

  void Mooee(const FermionField& in, FermionField& out) override;

  void MooeeDag(const FermionField& in, FermionField& out) override;

  void MooeeInv(const FermionField& in, FermionField& out) override;

  void MooeeInvDag(const FermionField& in, FermionField& out) override;

  void Mdir(const FermionField& in, FermionField& out, int dir, int disp) override;

  void MdirAll(const FermionField& in, std::vector<FermionField>& out) override;

  void MDeriv(GaugeField& force, const FermionField& X, const FermionField& Y, int dag) override;

  void MooDeriv(GaugeField& mat, const FermionField& U, const FermionField& V, int dag) override;

  void MeeDeriv(GaugeField& mat, const FermionField& U, const FermionField& V, int dag) override;

  /////////////////////////////////////////////
  // Member functions (internals)
  /////////////////////////////////////////////

  void MooeeInternal(const FermionField&        in,
                     FermionField&              out,
                     const CloverDiagonalField& diagonal,
                     const CloverTriangleField& triangle);

  // Full-volume Mooee/MooeeInv when the full-volume fields are shared scratch: each parity
  // through the half-checkerboard fields (site-local, the same numbers).
  void MooeeFullByParity(const FermionField& in, FermionField& out, bool inverse);

  /////////////////////////////////////////////
  // Helpers
  /////////////////////////////////////////////

  void ImportGauge(const GaugeField& _Umu) override;

  /////////////////////////////////////////////
  // Helpers
  /////////////////////////////////////////////

private:

  template<class Field>
  const MaskField* getCorrectMaskField(const Field &in) const {
    if(in.Grid()->_isCheckerBoarded) {
      if(in.Checkerboard() == Odd) {
        return &this->BoundaryMaskOdd;
      } else {
        return &this->BoundaryMaskEven;
      }
    } else {
      return &this->BoundaryMask;
    }
  }

  template<class Field>
  void ApplyBoundaryMask(Field& f) {
    const MaskField* m = getCorrectMaskField(f); GRID_ASSERT(m != nullptr);
    GRID_ASSERT(m != nullptr);
    CompactHelpers::ApplyBoundaryMask(f, *m);
  }

  /////////////////////////////////////////////
  // Member Data
  /////////////////////////////////////////////

public:

  RealD csw_r;
  RealD csw_t;
  RealD cF;

  bool fixedBoundaries;

  // The full-volume fields live in _full and the off-diagonal halves in _tri: this operator's
  // own, or shared with HASEN_GRID_SHARE_OP_FIELDS=1 (SharedOperatorFields.h). The flags must
  // stay declared before the stores, and the stores before the references.
  bool _fullShared = false;
  bool _triShared = false;
  std::shared_ptr<CompactCloverFullStore<Impl>> _full;
  std::shared_ptr<CompactCloverTriangleStore<Impl>> _tri;
  uint64_t _triSeen = 0;

  CloverDiagonalField &Diagonal;    CloverDiagonalField DiagonalEven,    DiagonalOdd;
  CloverDiagonalField &DiagonalInv; CloverDiagonalField DiagonalInvEven, DiagonalInvOdd;

  CloverTriangleField &Triangle;    CloverTriangleField &TriangleEven,   &TriangleOdd;
  CloverTriangleField &TriangleInv; CloverTriangleField TriangleInvEven, TriangleInvOdd;

  bool FullShared(void) const { return _fullShared; }
  bool TriangleShared(void) const { return _triShared; }
  SharedFieldTag &TriangleTag(void) { return _tri->tag; }
  void MarkTriangleWritten(int64_t epoch) {
    _tri->tag.version = NextSharedFieldVersion();
    _tri->tag.epoch = epoch;
    _triSeen = _tri->tag.version;
  }
  void MarkTriangleSeen(void) { _triSeen = _tri->tag.version; }
  // False iff another operator has written the shared links or off-diagonal halves since this
  // one's import (hides WilsonFermion's, which checks the links only).
  bool SharedFieldsCurrent(void) const {
    return WilsonBase::SharedFieldsCurrent() && _triSeen == _tri->tag.version;
  }

  static std::shared_ptr<CompactCloverFullStore<Impl>> MakeFullStore(GridBase *F, bool &shared);
  std::shared_ptr<CompactCloverTriangleStore<Impl>> MakeTriangleStore(GridBase *H, RealD csw_r, RealD csw_t, RealD cF,
                                                                     const WilsonAnisotropyCoefficients &anis,
                                                                     bool fixedBC, bool &shared);

  FermionField Tmp;

  MaskField BoundaryMask, BoundaryMaskEven, BoundaryMaskOdd;
};

NAMESPACE_END(Grid);
