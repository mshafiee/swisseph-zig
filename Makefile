ZIG ?= zig
BUILD ?= $(ZIG) build
ZIG_OPTIMIZE ?= ReleaseFast
PREFIX ?= /usr/local
DIST := dist
UNAME_S := $(shell uname -s 2>/dev/null || echo Linux)
UNAME_M := $(shell uname -m 2>/dev/null || echo x86_64)
ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    HOST_TRIPLE := aarch64-macos
  else
    HOST_TRIPLE := x86_64-macos
  endif
else ifeq ($(findstring BSD,$(UNAME_S)),BSD)
  ifeq ($(UNAME_M),aarch64)
    HOST_TRIPLE := aarch64-freebsd
  else
    HOST_TRIPLE := x86_64-freebsd
  endif
else
  ifeq ($(UNAME_M),aarch64)
    HOST_TRIPLE := aarch64-linux-gnu
  else
    HOST_TRIPLE := x86_64-linux-gnu
  endif
endif
TRIPLES_ALL := x86_64-linux-gnu aarch64-linux-gnu x86_64-freebsd aarch64-freebsd x86_64-macos aarch64-macos x86_64-windows wasm32-freestanding wasm32-wasi

.DEFAULT_GOAL := native
.PHONY: help all build native linux freebsd macos windows wasm wasm-test dist test lint format fmt clean distclean install release _collect-triple

help:
	@echo "swisseph-zig — Zig Makefile"
	@echo "  make / make native   — host $(HOST_TRIPLE) → dist/$(HOST_TRIPLE)/"
	@echo "  make all / dist      — all 9 targets"
	@echo "  make linux|freebsd|macos|windows|wasm"
	@echo "  make test            — zig build test"
	@echo "  make wasm-test       — wasm artifacts + node --test test/wasm/"
	@echo "  make lint            — zig fmt --check"
	@echo "  make format / fmt    — zig fmt"
	@echo "  make clean / distclean / install / release"

native: build
build:
	@$(BUILD) --prefix zig-out/$(HOST_TRIPLE) -Doptimize=$(ZIG_OPTIMIZE)
	@$(MAKE) _collect-triple TRIPLE=$(HOST_TRIPLE)

all: dist
dist: linux freebsd macos windows wasm
linux:
	@$(MAKE) dist/x86_64-linux-gnu
	@$(MAKE) dist/aarch64-linux-gnu
freebsd:
	@$(MAKE) dist/x86_64-freebsd
	@$(MAKE) dist/aarch64-freebsd
macos:
	@$(MAKE) dist/x86_64-macos
	@$(MAKE) dist/aarch64-macos
windows:
	@$(MAKE) dist/x86_64-windows
wasm:
	@$(MAKE) dist/wasm32-freestanding
	@$(MAKE) dist/wasm32-wasi

dist/%:
	@echo "==> Building $(@F) ($(ZIG_OPTIMIZE))"
	@mkdir -p $(DIST)/$(@F)/lib $(DIST)/$(@F)/bin $(DIST)/$(@F)/include
	@$(BUILD) --prefix zig-out/$(@F) -Dtarget=$(@F) -Doptimize=$(ZIG_OPTIMIZE)
	@for f in zig-out/$(@F)/lib/libswe.*; do [ -e "$$f" ] && cp -f "$$f" $(DIST)/$(@F)/lib/ || true; done
	@[ -e zig-out/$(@F)/lib/swe.lib ] && cp -f zig-out/$(@F)/lib/swe.lib $(DIST)/$(@F)/lib/libswe.lib || true
	@[ -e zig-out/$(@F)/bin/swe.dll ] && cp -f zig-out/$(@F)/bin/swe.dll $(DIST)/$(@F)/lib/libswe.dll || true
	@[ -d zig-out/$(@F)/include ] && cp -r zig-out/$(@F)/include/* $(DIST)/$(@F)/include/ 2>/dev/null || true
	@for b in swetest swevents swemini obama swephgen4; do \
	  case "$(@F)" in \
	    wasm32-freestanding) ;; \
	    *windows*) [ -e zig-out/$(@F)/bin/$$b.exe ] && cp -f zig-out/$(@F)/bin/$$b.exe $(DIST)/$(@F)/bin/ 2>/dev/null || true; ;; \
	    *) [ -e zig-out/$(@F)/bin/$$b ] && cp -f zig-out/$(@F)/bin/$$b $(DIST)/$(@F)/bin/ 2>/dev/null || true; ;; \
	  esac; \
	done
	@case "$(@F)" in \
	  wasm32-freestanding) $(BUILD) wasm && node scripts/gen-wasm-ts.mjs && cp -f zig-out/wasm/swe.wasm test/wasm/swe-bridge.d.ts $(DIST)/$(@F)/ ;; \
	esac
	@echo "  -> $(DIST)/$(@F)/ { lib/, bin/, include/ }"

test:
	@$(BUILD) test

# WASM end-to-end: native pure golden + both runnable wasm artifacts, then the
# zero-dependency Node harness (bit-exact VFS-vs-disk comparisons).
# The golden is deliberately Debug: optimized native codegen may fuse FMA on
# x86_64/ARM while wasm has no FMA instruction, breaking bit-exactness for
# reasons unrelated to the VFS. Debug is the contraction-free reference.
wasm-test:
	@$(BUILD) swe-golden -Doptimize=Debug -Dpure=true
	@$(BUILD) wasm-test
	@$(BUILD) wasm
	@node scripts/gen-wasm-ts.mjs --check
	@node test/wasm/run-all.mjs

lint:
	@$(ZIG) fmt --check src/ examples/ test/

format:
fmt:
	@$(ZIG) fmt src/ examples/ test/

clean:
	@rm -rf zig-out dist
distclean: clean
	@rm -rf .zig-cache

install: native
	@mkdir -p $(PREFIX)/lib $(PREFIX)/bin $(PREFIX)/include
	@cp -f $(DIST)/$(HOST_TRIPLE)/lib/* $(PREFIX)/lib/ 2>/dev/null || true
	@cp -f $(DIST)/$(HOST_TRIPLE)/bin/* $(PREFIX)/bin/ 2>/dev/null || true
	@cp -rf $(DIST)/$(HOST_TRIPLE)/include/* $(PREFIX)/include/ 2>/dev/null || true

release: distclean format all test lint
	@echo "release: all targets built, tests passed, lint clean"
	@ls -R dist 2>/dev/null | head -80

_collect-triple:
	@mkdir -p $(DIST)/$(TRIPLE)/lib $(DIST)/$(TRIPLE)/bin $(DIST)/$(TRIPLE)/include
	@for f in zig-out/$(TRIPLE)/lib/libswe.*; do [ -e "$$f" ] && cp -f "$$f" $(DIST)/$(TRIPLE)/lib/ || true; done
	@if [ -d zig-out/$(TRIPLE)/include ]; then cp -r zig-out/$(TRIPLE)/include/* $(DIST)/$(TRIPLE)/include/ 2>/dev/null || true; fi
	@for b in swetest swevents swemini obama swephgen4; do \
	  [ -e zig-out/$(TRIPLE)/bin/$$b ] && cp -f zig-out/$(TRIPLE)/bin/$$b $(DIST)/$(TRIPLE)/bin/ 2>/dev/null || true; \
	done
