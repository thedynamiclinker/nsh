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
ifeq ($(LORD_PACKAGE),)
LORD_PACKAGE := $(PORTS_CACHE)/thedynamiclinker/lord/package.mk
$(LORD_PACKAGE):
	@set -eu; parent="$(PORTS_CACHE)/thedynamiclinker"; mkdir -p "$$parent"; \
	    stage=$$(mktemp -d "$$parent/.lord.XXXXXXXX"); trap 'rm -rf "$$stage"' 0; \
	    git clone -- "$(GIT_ROOT)/thedynamiclinker/lord" "$$stage/source"; \
	    test -f "$$stage/source/package.mk"; \
	    mv -T "$$stage/source" "$$parent/lord" || test -f "$@"
endif
include $(LORD_PACKAGE)
