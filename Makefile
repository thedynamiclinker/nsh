PACKAGE := thedynamiclinker/nsh
DEPS := thedynamiclinker/LD
PROGRAMS := bin/new-world
ALIASES := nsh=new-world NSH=new-world nhs=new-world NHS=new-world \
           shn=new-world SHN=new-world snh=new-world SNH=new-world @=new-world SH=new-world
DATA := $(wildcard share/new-world/* share/speech/bin/*) $(wildcard share/dict/*/*.md)

# A standalone checkout can bootstrap the common package targets.
PREFIX ?= /usr/local
GIT_ROOT ?= https://github.com
PORTS_SOURCE ?= $(abspath ../..)
PORTS_CACHE ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)/new-world
LORD_PACKAGE := $(firstword $(wildcard $(PORTS_SOURCE)/thedynamiclinker/lord/package.mk $(PREFIX)/lib/new-world/package.mk))
ifeq ($(LORD_PACKAGE)$(filter-out help clean,$(MAKECMDGOALS)),)
.DEFAULT_GOAL := help
.PHONY: help clean
help:
	@printf '%s\n' 'make install | develop | uninstall | clean [PREFIX=/usr/local]'
clean:
	@:
else
ifeq ($(LORD_PACKAGE),)
LORD_PACKAGE := $(PORTS_CACHE)/thedynamiclinker/lord/package.mk
$(LORD_PACKAGE):
	@set -eu; parent="$(PORTS_CACHE)/thedynamiclinker"; mkdir -p "$$parent"; \
	    lock="$$parent/lord.lock"; attempts=0; \
	    until mkdir "$$lock" 2>/dev/null; do \
	        test ! -f "$@" || exit 0; attempts=$$((attempts + 1)); \
	        test "$$attempts" -lt 60 || { echo "port: waiting for $$lock" >&2; exit 2; }; \
	        sleep 1; \
	    done; \
	    stage=; trap 'test -z "$$stage" || rm -rf "$$stage"; rmdir "$$lock"' 0; \
	    test ! -f "$@" || exit 0; test ! -e "$$parent/lord"; test ! -L "$$parent/lord"; \
	    stage=$$(mktemp -d "$$parent/.lord.XXXXXXXX"); \
	    git clone -- "$(GIT_ROOT)/thedynamiclinker/lord" "$$stage/source"; \
	    test -f "$$stage/source/package.mk"; mv "$$stage/source" "$$parent/lord"
endif
include $(LORD_PACKAGE)
endif

.PHONY: check
check:
	+@python3 tests/check.py "$(MAKE)"
