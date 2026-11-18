/*************************************************************************************

    Grid physics library, www.github.com/paboyle/Grid

    Source file: ./lib/qcd/action/fermion/SharedOperatorFields.h

    Fork-local (vmos1/Grid-aux-fields, branch pure-hmc), not upstream Grid.

*************************************************************************************/
/*  END LEGAL */
#pragma once

// Operators that hold identical copies of gauge-derived fields share one copy.
//
// HASEN_GRID_SHARE_OP_FIELDS=1 (read once, at the first operator construction; default OFF):
//
//   * WilsonFermion<WilsonImplD|WilsonImplF>: the doubled links Umu, UmuEven, UmuOdd are shared
//     by operators with the same grids, boundary phases, twists, Dirichlet setup and anisotropy.
//     They depend on the gauge field and those parameters only, never on the mass.
//   * CompactWilsonCloverFermion<Impl, CompactCloverHelpers<Impl>> (the standard clover, periodic
//     or antiperiodic time): the off-diagonal halves TriangleEven, TriangleOdd are shared by
//     operators that share links and have the same csw_r, csw_t, cF and anisotropy. The mass
//     enters only the diagonal (CloverHelpers.h, Clover += diag_mass, which adds on the diagonal
//     only). Never for the exponential clover (its mass enters every entry) or open boundaries
//     (ModifyBoundaries puts the mass into the triangle at the time boundary).
//   * The same compact clover: the full-volume Diagonal, Triangle, DiagonalInv, TriangleInv are
//     read only inside the import (to fill the half-checkerboard fields), so all operators of one
//     Impl and full grid use one set as import scratch. Full-volume Mooee and MooeeInv then apply
//     the half-checkerboard fields to each parity (site-local, the same numbers).
//
// Off: every operator owns all its fields, exactly as before.
//
// Validity. A shared set is written by whichever operator imports into it. Every write gives the
// set a new version (a process-wide counter) and the writing operator records it; an operator's
// shared fields are current iff the set still carries the version that operator recorded. Code
// that skips an import must check SharedFieldsCurrent() (import_guard.h does). The epoch names
// the gauge field the content came from (fast_import.h sets it from its field-strength cache; -1
// means unknown, e.g. after a stock ImportGauge), so that importing the same field into a second
// operator can skip rewriting the set.
//
// Any operator that shares a set must be imported (ImportGauge, or the fast import) before each
// use, as every Grid pseudofermion action does. The non-compact WilsonCloverFermion and
// WilsonTMFermion of the two Impls share links too when the switch is on.

#include <cstdint>
#include <cstdlib>
#include <memory>
#include <utility>
#include <vector>

NAMESPACE_BEGIN(Grid);

inline bool ShareOpFieldsEnabled(void)
{
  static const bool on = [] {
    const char *e = std::getenv("HASEN_GRID_SHARE_OP_FIELDS");
    return e != nullptr && e[0] == '1';
  }();
  return on;
}

inline uint64_t NextSharedFieldVersion(void)
{
  static uint64_t v = 0;
  return ++v;
}

struct SharedFieldTag {
  uint64_t version = 0;  // new on every write
  int64_t  epoch   = -1; // gauge field the content came from; -1 unknown
};

// Live sets, one registry per (Store, Key) type. An entry dies with the last operator using it.
template <class Store, class Key>
class SharedFieldPool {
public:
  template <class Make>
  static std::shared_ptr<Store> Get(const Key &key, Make make)
  {
    auto &entries = Entries();
    for (auto &e : entries) {
      if (e.first == key) {
        if (auto s = e.second.lock()) return s;
        std::shared_ptr<Store> s(make());
        e.second = s;
        return s;
      }
    }
    std::shared_ptr<Store> s(make());
    entries.emplace_back(key, std::weak_ptr<Store>(s));
    return s;
  }

private:
  static std::vector<std::pair<Key, std::weak_ptr<Store>>> &Entries(void)
  {
    static std::vector<std::pair<Key, std::weak_ptr<Store>>> e;
    return e;
  }
};

NAMESPACE_END(Grid);
