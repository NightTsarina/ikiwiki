# List here all source files with translatable strings.
POTFILES=$(sort $(shell find ../IkiWiki -type f -name \*.pm)) \
	../ikiwiki.in ../IkiWiki.pm ../auto.setup

POFILES=$(wildcard *.po)
MOFILES=$(POFILES:.po=.mo)

# Translated underlays can only be generated if po4a is available.
TRANSLATED_UNDERLAYS=$(shell if perl -e 'use Locale::Po4a::Common' 2>/dev/null; then echo ../underlays/locale; fi)

all: ikiwiki.pot mo $(TRANSLATED_UNDERLAYS)

mo: $(MOFILES)

install: all
	# Normal mo files for program translation.
	for file in $(MOFILES); do \
		lang=`echo $$file | sed 's/\.mo//'`; \
		install -d $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/; \
		install -m 0644 $$file $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/ikiwiki.mo; \
	done
	
	# Underlay translation via po files that go in special per-language
	# underlays.
	for file in `cd underlays && find . -type f -name \*.po`; do \
		lang=`echo $$file | sed -e 's/.po$$//' -e 's/.*\\.//'`; \
		dir=`dirname "$(DESTDIR)$(PREFIX)/share/ikiwiki/po/$$lang/$$file"`; \
		install -d $$dir; \
		install -m 0644 underlays/$$file $$dir; \
	done

ikiwiki.pot: $(POTFILES)
	@if perl -e '($$ver)=`xgettext -V | head -n 1`=~/.*\s+([0-9]+\.[0-9]+)/; die "gettext $$ver too old, not updating the pot file\n" if $$ver < 0.16'; then \
		echo "Rebuilding the pot file"; \
		xgettext --from-code=UTF-8 $(POTFILES) -o ikiwiki.pot -Lperl --add-comments=translators; \
	fi

clean:
	rm -f $(MOFILES) messages messages.mo *_stamp
	rm -rf html underlays/.ikiwiki $(TRANSLATED_UNDERLAYS)
	find underlays -name \*.mdwn -or -name \*.pot | xargs rm -f

%.mo: %.po
	@if ! msgfmt -o $@ $<; then echo "unable to run msgfmt"; fi

%.po: ikiwiki.pot
	@echo -n "Merging ikiwiki.pot and $@"
# Typically all that changes is a date or line number. I'd prefer not to
# commit such changes, so detect and ignore them.
	@if ! msgmerge $@ ikiwiki.pot -o $@.new 2>&1; then \
		echo "unable to run msgmerge"; \
	else \
		if [ "`diff $@ $@.new | grep '[<>]' | grep -v '[<>] #:' | wc -l`" -ne 2 ]; then \
			mv -f $@.new $@; \
		else \
			rm -f $@.new; \
		fi; \
		msgfmt --statistics $@ 2>&1; \
	fi

check:
	@for file in $(POFILES); do \
		lang=`echo $$file | sed 's/\.po//'`; \
		printf "$$lang: "; \
		msgfmt -o /dev/null -c -v --statistics $$lang.po;\
	done

underlays_copy_stamp:
	# copy all the files we want to translate into a srcdir
	for file in `cd ..; find underlays -follow -name \*.mdwn`; do \
		install -d $$(dirname $$file); \
		cp -aL ../$$file $$file 2>/dev/null || \
		install -m 644 ../$$file $$file; \
	done
	install -d underlays/directives/ikiwiki/directive
	for file in `cd ..; find doc/ikiwiki/directive/ -maxdepth 1 -type f`; do \
		cp -a ../$$file underlays/directives/ikiwiki/directive ||  \
		install -m 644 ../$$file underlays/directives/ikiwiki/directive; \
	done
	install -d underlays/empty
	touch $@

underlays: ../ikiwiki.out underlays_copy_stamp
	../ikiwiki.out -libdir .. -setup underlay.setup -refresh

../ikiwiki.out: ../Makefile
	make -C .. ikiwiki.out

../Makefile: ../Makefile.PL
	cd .. && ./Makefile.PL

$(TRANSLATED_UNDERLAYS): po2wiki_stamp
po2wiki_stamp: po2wiki underlays_copy_stamp
	PERL5LIB=.. ./po2wiki underlay.setup
	touch $@

.PHONY: underlays
