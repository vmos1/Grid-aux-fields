# Out-of-tree build of the production programs against an existing Grid build,
# via its grid-config.  Default build directory is ../build (Perlmutter in-tree
# build of this fork); override on the command line:
#   make GRID_BUILD_DIR=../build-gpu gen_dtxqcd_cfgs
# Pure Grid: there is no QUDA backend in this tree.
GRID_BUILD_DIR ?= ../build
GRID_CONFIG = $(GRID_BUILD_DIR)/grid-config
CXX      = $(shell $(GRID_CONFIG) --cxx)
# Laptop build (homebrew OpenSSL/HDF5/etc.) needs the brew include/lib paths
# that the system configure missed but Grid/util/Sha.h needs.  Harmless on
# Linux production builds (the directories don't exist there).
BREW_PREFIX ?= /opt/homebrew/opt
# The source tree and the build directory come BEFORE grid-config's flags: those
# carry -I<install prefix>/include, and an older `make install` there would
# otherwise shadow the tree's headers (the aux-field include in ActionCore.h).
CXXFLAGS = -I.. -I$(GRID_BUILD_DIR)/Grid $(shell $(GRID_CONFIG) --cxxflags) -I$(BREW_PREFIX)/openssl@3/include
LDFLAGS  = -L$(GRID_BUILD_DIR)/Grid $(shell $(GRID_CONFIG) --ldflags) -L$(BREW_PREFIX)/openssl@3/lib
LIBS     = $(shell $(GRID_CONFIG) --libs)

PROGRAMS = gen_dtxqcd_cfgs gen_txqcd_cfgs gen_txqcd_cfgs_2plus1 gen_txqcd_cfgs_nf2 gen_qcd_cfgs gen_qcd_cfgs_2plus1 \
           meas_conn_txqcd meas_conn_qcd meas_conn_dtxqcd meas_conn_weakfield meas_conn_weakfield_nf2 \
           meas_disco_txqcd meas_disco_qcd \
           meas_aux_txqcd meas_aux_dtxqcd meas_baryon_dtxqcd compare compute_plaq compute_vev \
           eigspec_diag eigspec_diag_nf2 \
           bench_gauge_force bench_txqcd_gauge_force

all: $(PROGRAMS)

# gen_txqcd_cfgs is compiled at TXQCD_Nf=3 with diag mass {m_l, m_l, m_s}.
# Other production binaries default to TXQCD_Nf=2 (or are Nf-agnostic).
gen_txqcd_cfgs: gen_txqcd_cfgs.cc params.h eig_diag.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=3 -o $@ $< $(LDFLAGS) $(LIBS)

# gen_txqcd_cfgs_2plus1 is the previous Nf=2 TXQCD light + Nf=1 QCD strange
# action structure (pre-b04af352), kept for direct comparison against the
# Nf=3 form on the same chroma-imported config.
gen_txqcd_cfgs_2plus1: gen_txqcd_cfgs_2plus1.cc params.h eig_diag.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=2 -o $@ $< $(LDFLAGS) $(LIBS)

# gen_txqcd_cfgs_nf2: Nf=2 light-only diagnostic — gen_txqcd_cfgs_2plus1 with the
# strange Nf=1 monomials removed.  Isolates the strange quark's role.  Nf=2.
gen_txqcd_cfgs_nf2: gen_txqcd_cfgs_nf2.cc params.h eig_diag.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=2 -o $@ $< $(LDFLAGS) $(LIBS)

# meas_conn_weakfield uses TXQCDFermionNf — also Nf=3.
meas_conn_weakfield: meas_conn_weakfield.cc params.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=3 -o $@ $< $(LDFLAGS) $(LIBS)

# Nf=2 build of the same source for the Nf=2+1 connected-pion comparison.
meas_conn_weakfield_nf2: meas_conn_weakfield.cc params.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=2 -o $@ $< $(LDFLAGS) $(LIBS)

# eigspec_diag uses TXQCDFermionNf — Nf=3 default.
eigspec_diag: eigspec_diag.cc params.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=3 -o $@ $< $(LDFLAGS) $(LIBS)

# Nf=2 build for the Nf=2+1 vs Nf=3 spectrum comparison.
eigspec_diag_nf2: eigspec_diag.cc params.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=2 -o $@ $< $(LDFLAGS) $(LIBS)

# Nf=3 variants of the production meas binaries — built for measurement on
# the gen_txqcd_cfgs (Nf=3) cfgs (e.g. _nf3_weakfield_md10).  Default catch-all
# below builds the Nf=2 versions of the same sources.
meas_conn_txqcd_nf3: meas_conn_txqcd.cc params.h meas_helper.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=3 -o $@ $< $(LDFLAGS) $(LIBS)

meas_disco_txqcd_nf3: meas_disco_txqcd.cc params.h meas_helper.h
	$(CXX) $(CXXFLAGS) -DTXQCD_Nf=3 -o $@ $< $(LDFLAGS) $(LIBS)

# Catch-all.  eig_diag.h + meas_helper.h listed as prereqs so header-only
# edits (e.g. EIG_DIAG tuning) force a rebuild of gen_qcd_cfgs* and the
# meas_* binaries that include them.  (Over-broad for binaries that don't
# include these headers, but a header edit is rare and a spurious rebuild
# is harmless.)
%: %.cc params.h eig_diag.h meas_helper.h
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS) $(LIBS)

clean:
	rm -f $(PROGRAMS)

.PHONY: all clean
