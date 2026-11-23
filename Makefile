PREFIX ?= /usr/local
BINDIR := $(DESTDIR)$(PREFIX)/bin

.PHONY: install
install:
	install -d "$(BINDIR)"
	install -m 755 bin/nsh bin/NSH "$(BINDIR)"
	ln -sfn nsh "$(BINDIR)/nhs"
