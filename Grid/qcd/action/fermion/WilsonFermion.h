/*************************************************************************************

Grid physics library, www.github.com/paboyle/Grid

Source file: ./lib/qcd/action/fermion/WilsonFermion.h

Copyright (C) 2015

Author: Peter Boyle <pabobyle@ph.ed.ac.uk>
Author: Peter Boyle <paboyle@ph.ed.ac.uk>
Author: paboyle <paboyle@ph.ed.ac.uk>

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

See the full license in the file "LICENSE" in the top level distribution
directory
*************************************************************************************/
			   /*  END LEGAL */
#pragma once

#include <Grid/qcd/action/fermion/SharedOperatorFields.h>

NAMESPACE_BEGIN(Grid);

class WilsonFermionStatic {
public:
  static int HandOptDslash;  // these are a temporary hack
  static int MortonOrder;
  static const std::vector<int> directions;
  static const std::vector<int> displacements;
  static const int npoint = 8;
};

 struct WilsonAnisotropyCoefficients: Serializable
 {
  GRID_SERIALIZABLE_CLASS_MEMBERS(WilsonAnisotropyCoefficients,
  bool, isAnisotropic,
  int, t_direction,
  double, xi_0,
  double, nu);

  WilsonAnisotropyCoefficients():
    isAnisotropic(false),
    t_direction(Nd-1),
    xi_0(1.0),
    nu(1.0){}
};

// Shared doubled links (SharedOperatorFields.h): which Impls may share, the set, and its key.
template <class Impl> struct ShareableWilsonImpl : std::false_type {};
template <> struct ShareableWilsonImpl<WilsonImplD> : std::true_type {};
template <> struct ShareableWilsonImpl<WilsonImplF> : std::true_type {};

template <class Impl>
struct WilsonLinkStore {
  typedef typename Impl::DoubledGaugeField DoubledGaugeField;
  DoubledGaugeField Umu;
  DoubledGaugeField UmuEven;
  DoubledGaugeField UmuOdd;
  SharedFieldTag tag;
  WilsonLinkStore(GridBase *F, GridBase *H) : Umu(F), UmuEven(H), UmuOdd(H) {}
};

struct WilsonLinkKey {
  GridBase *F = nullptr;
  GridBase *H = nullptr;
  std::vector<ComplexD> phases;
  std::vector<RealD> twist;
  std::vector<int> dirichlet;
  int partialDirichlet = 0;
  bool aniso = false;
  int t_direction = 0;
  double xi_0 = 0.0, nu = 0.0;
  bool operator==(const WilsonLinkKey &o) const {
    return F == o.F && H == o.H && phases == o.phases && twist == o.twist && dirichlet == o.dirichlet &&
           partialDirichlet == o.partialDirichlet && aniso == o.aniso && t_direction == o.t_direction &&
           xi_0 == o.xi_0 && nu == o.nu;
  }
};

template <class Impl>
class WilsonFermion : public WilsonKernels<Impl>, public WilsonFermionStatic
{
public:
  INHERIT_IMPL_TYPES(Impl);
  typedef WilsonKernels<Impl> Kernels;

  ///////////////////////////////////////////////////////////////
  // Implement the abstract base
  ///////////////////////////////////////////////////////////////
  GridBase *GaugeGrid(void) { return _grid; }
  GridBase *GaugeRedBlackGrid(void) { return _cbgrid; }
  GridBase *FermionGrid(void) { return _grid; }
  GridBase *FermionRedBlackGrid(void) { return _cbgrid; }

  FermionField _tmp;
  FermionField &tmp(void) { return _tmp; }

  //////////////////////////////////////////////////////////////////
  // override multiply; cut number routines if pass dagger argument
  // and also make interface more uniformly consistent
  //////////////////////////////////////////////////////////////////
  virtual void  M(const FermionField &in, FermionField &out);
  virtual void  Mdag(const FermionField &in, FermionField &out);

  /////////////////////////////////////////////////////////
  // half checkerboard operations
  // could remain virtual so we  can derive Clover from Wilson base
  /////////////////////////////////////////////////////////
  void Meooe(const FermionField &in, FermionField &out);
  void MeooeDag(const FermionField &in, FermionField &out);

  // allow override for twisted mass and clover
  virtual void Mooee(const FermionField &in, FermionField &out);
  virtual void MooeeDag(const FermionField &in, FermionField &out);
  virtual void MooeeInv(const FermionField &in, FermionField &out);
  virtual void MooeeInvDag(const FermionField &in, FermionField &out);

  virtual void  MomentumSpacePropagator(FermionField &out,const FermionField &in,RealD _mass,std::vector<double> twist) ;

  ////////////////////////
  // Derivative interface
  ////////////////////////
  // Interface calls an internal routine
  void DhopDeriv(GaugeField &mat,const FermionField &U,const FermionField &V,int dag);
  void DhopDerivOE(GaugeField &mat,const FermionField &U,const FermionField &V,int dag);
  void DhopDerivEO(GaugeField &mat,const FermionField &U,const FermionField &V,int dag);

  ///////////////////////////////////////////////////////////////
  // non-hermitian hopping term; half cb or both
  ///////////////////////////////////////////////////////////////
  void Dhop(const FermionField &in, FermionField &out, int dag);
  void DhopOE(const FermionField &in, FermionField &out, int dag);
  void DhopEO(const FermionField &in, FermionField &out, int dag);

  ///////////////////////////////////////////////////////////////
  // Multigrid assistance; force term uses too
  ///////////////////////////////////////////////////////////////
  void Mdir(const FermionField &in, FermionField &out, int dir, int disp);
  void MdirAll(const FermionField &in, std::vector<FermionField> &out);
  void DhopDir(const FermionField &in, FermionField &out, int dir, int disp);
  void DhopDirAll(const FermionField &in, std::vector<FermionField> &out);
  void DhopDirCalc(const FermionField &in, FermionField &out, int dirdisp,int gamma, int dag);

  ///////////////////////////////////////////////////////////////
  // Extra methods added by derived
  ///////////////////////////////////////////////////////////////
  void DerivInternal(StencilImpl &st, DoubledGaugeField &U, GaugeField &mat,
                     const FermionField &A, const FermionField &B, int dag);

  void DhopInternal(StencilImpl &st,
		    DoubledGaugeField &U,
                    const FermionField &in, FermionField &out, int dag);

  void DhopInternalSerial(StencilImpl &st,
			  DoubledGaugeField &U,
			  const FermionField &in, FermionField &out, int dag);

  void DhopInternalOverlappedComms(StencilImpl &st,
				   DoubledGaugeField &U,
				   const FermionField &in, FermionField &out, int dag);

  // Constructor
  WilsonFermion(GaugeField &_Umu, GridCartesian &Fgrid,
                GridRedBlackCartesian &Hgrid, RealD _mass,
                const ImplParams &p = ImplParams(),
                const WilsonAnisotropyCoefficients &anis = WilsonAnisotropyCoefficients() );

  // DoubleStore impl dependent
  void ImportGauge(const GaugeField &_Umu);

  ///////////////////////////////////////////////////////////////
  // Data members require to support the functionality
  ///////////////////////////////////////////////////////////////

  //    protected:
public:
  virtual RealD Mass(void) { return mass; }
  virtual int   isTrivialEE(void) { return 1; };
  RealD mass;
  RealD diag_mass;

  GridBase *_grid;
  GridBase *_cbgrid;

  // Defines the stencils for even and odd
  StencilImpl Stencil;
  StencilImpl StencilEven;
  StencilImpl StencilOdd;
  void SloppyComms(int sloppy)
  {
    Stencil.SetSloppyComms(sloppy);
    StencilEven.SetSloppyComms(sloppy);
    StencilOdd.SetSloppyComms(sloppy);
  }

  // Copy of the gauge field , with even and odd subsets. They live in _links, owned by this
  // operator or, with HASEN_GRID_SHARE_OP_FIELDS=1, shared (SharedOperatorFields.h). _links
  // must stay declared before the three references, and _linksShared before _links (the _links
  // initializer sets it).
  bool _linksShared = false;
  std::shared_ptr<WilsonLinkStore<Impl>> _links;
  uint64_t _linksSeen = 0;
  DoubledGaugeField &Umu;
  DoubledGaugeField &UmuEven;
  DoubledGaugeField &UmuOdd;

  bool LinksShared(void) const { return _linksShared; }
  SharedFieldTag &LinksTag(void) { return _links->tag; }
  // A write to the links: new version, recorded by this operator; epoch -1 = unknown field.
  void MarkLinksWritten(int64_t epoch) {
    _links->tag.version = NextSharedFieldVersion();
    _links->tag.epoch = epoch;
    _linksSeen = _links->tag.version;
  }
  // This operator's import found the links already holding its field: record the version.
  void MarkLinksSeen(void) { _linksSeen = _links->tag.version; }
  // False iff another operator has written the shared links since this one's import.
  bool SharedFieldsCurrent(void) const { return _linksSeen == _links->tag.version; }
  static std::shared_ptr<WilsonLinkStore<Impl>> MakeLinkStore(GridBase *F, GridBase *H, const ImplParams &p,
                                                               const WilsonAnisotropyCoefficients &anis,
                                                               bool &shared);

  WilsonAnisotropyCoefficients anisotropyCoeff;

  ///////////////////////////////////////////////////////////////
  // Conserved current utilities
  ///////////////////////////////////////////////////////////////
  void ContractConservedCurrent(PropagatorField &q_in_1,
                                PropagatorField &q_in_2,
                                PropagatorField &q_out,
                                PropagatorField &phys_src,
                                Current curr_type,
                                unsigned int mu);
  void SeqConservedCurrent(PropagatorField &q_in,
                           PropagatorField &q_out,
                           PropagatorField &phys_src,
                           Current curr_type,
                           unsigned int mu,
                           unsigned int tmin,
			   unsigned int tmax,
			   ComplexField &lattice_cmplx);
};

typedef WilsonFermion<WilsonImplF> WilsonFermionF;
typedef WilsonFermion<WilsonImplD> WilsonFermionD;

NAMESPACE_END(Grid);
