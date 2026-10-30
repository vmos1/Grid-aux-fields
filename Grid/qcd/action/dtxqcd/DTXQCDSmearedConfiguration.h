#pragma once
// Stout-smeared configuration for the DTXQCD composite field.
//
// Direct analogue of TXQCDSmearedConfiguration: wraps Grid's
// SmearedConfiguration<PeriodicGimplR> to apply stout smearing to the gauge-link
// component of DTXQCDField while passing the auxiliary fields
// (sigma, pi, d, n, s, p) through unchanged.  The analytic stout force chain
// rule is applied only to the gauge force; aux forces are untouched (the aux
// fields do not enter the stout map).
//
// Usage (mirrors TXQCD):
//   Smear_Stout<PeriodicGimplR> Stout(rho);
//   DTXQCDSmearedConfiguration SmearPolicy(&Grid, Nsmear, Stout);
//   PF.is_smeared = true;  LogDet.is_smeared = true;  Gauge.is_smeared = true;
//   // pass SmearPolicy to the integrator instead of NoSmearing
//
// Nsmear == 0 is an identity (the gauge passes through unchanged), so the same
// policy can drive both smeared production and unsmeared csw=0 scout runs.
//
// DTXQCD_LAZY_SMEAR=1 (default 0): set_Field only records the thin field and
// marks the smeared copy out of date; the stout chain runs on the first read
// (get_U(true), get_SmearedU, smeared_force).  The integrator calls set_Field
// after every U update of the innermost level (640 per trajectory at the
// production point) while the smeared field is read only by the fermion
// monomials and the actions (~23 per trajectory).  Bit-identical to the eager
// path as long as nothing changes the thin field between set_Field and the
// next read without calling set_Field again; the end-of-trajectory Project(U)
// in Integrator::integrate follows the last fermion force, which has already
// read (and so refreshed) the smeared field, exactly as in the eager path.

#include <Grid/qcd/smearing/GaugeConfiguration.h>
#include <Grid/qcd/action/dtxqcd/DTXQCDCompositeImpl.h>

NAMESPACE_BEGIN(Grid);

class DTXQCDSmearedConfiguration
    : public ConfigurationBase<DTXQCDField> {
 public:
  DTXQCDSmearedConfiguration(GridCartesian *UGrid, unsigned int Nsmear,
                             Smear_Stout<PeriodicGimplR> &Stout)
      : Nsmear_(Nsmear),
        gauge_smearing_(UGrid, Nsmear, Stout),
        SmearedField_(UGrid),
        ThinLinks_(nullptr) {
    if (Lazy())
      std::cout << GridLogMessage
                << "DTXQCD_LAZY_SMEAR=1: stout smearing deferred to the first read"
                << std::endl;
  }

  void set_Field(DTXQCDField &U) override {
    ThinLinks_ = &U;
    if (Lazy()) {
      stale_ = true;
      return;
    }
    Smear();
  }

  void smeared_force(DTXQCDField &dSdU) override {
    // Stout chain rule on the gauge force only; aux force components untouched.
    Refresh();
    gauge_smearing_.smeared_force(dSdU.U);
  }

  DTXQCDField &get_SmearedU() override {
    Refresh();
    return SmearedField_;
  }

  DTXQCDField &get_U(bool smeared = false) override {
    if (smeared) {
      Refresh();
      return SmearedField_;
    }
    return *ThinLinks_;
  }

 private:
  static bool Lazy() {
    static const bool on = []() {
      const char *e = std::getenv("DTXQCD_LAZY_SMEAR");
      return e && *e && std::atoi(e) != 0;
    }();
    return on;
  }

  // The eager set_Field body: stout chain on the gauge links, aux copied through.
  void Smear() {
    gauge_smearing_.set_Field(ThinLinks_->U);
    SmearedField_ = *ThinLinks_;             // copies gauge + all aux
    if (Nsmear_ > 0)
      SmearedField_.U = gauge_smearing_.get_SmearedU();
  }

  void Refresh() {
    if (stale_) {
      Smear();
      stale_ = false;
    }
  }

  unsigned int Nsmear_;
  SmearedConfiguration<PeriodicGimplR> gauge_smearing_;
  DTXQCDField SmearedField_;
  DTXQCDField *ThinLinks_;
  bool stale_ = false;
};

NAMESPACE_END(Grid);
