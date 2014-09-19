#!/usr/bin/perl
use warnings;
use strict;
use ExtUtils::MakeMaker;

# Add a few more targets.
sub MY::postamble {
q{
all:: extra_build
clean:: extra_clean
install:: extra_install
pure_install:: extra_install

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

# Parameterized programs used by Makefile.
FIND?=find
SED?=sed

# Additional configurable path variables.
W3M_CGI_BIN?=$(PREFIX)/lib/w3m/cgi-bin
SYSCONFDIR?=/etc/ikiwiki
MANDIR?=$(PREFIX)/share/man

tflag=$(shell if [ -n "$$NOTAINT" ] && [ "$$NOTAINT" != 1 ]; then printf -- "-T"; fi)
extramodules=$(shell if [ "$$PROFILE" = 1 ]; then printf -- "-d:NYTProf"; fi)
outprogs=ikiwiki.out ikiwiki-transition.out ikiwiki-calendar.out
scripts=ikiwiki-update-wikilist ikiwiki-makerepo
sysconfdir_scripts=ikiwiki-mass-rebuild ikiwiki-update-wikilist

PROBABLE_INST_LIB=$(shell \\
	if [ "$(INSTALLDIRS)" = "perl" ]; then \\
		echo $(INSTALLPRIVLIB); \\
	elif [ "$(INSTALLDIRS)" = "site" ]; then \\
		echo $(INSTALLSITELIB); \\
	elif [ "$(INSTALLDIRS)" = "vendor" ]; then \\
		echo $(INSTALLVENDORLIB); \\
	fi \\
)

%.out: %.in
	./pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB) < $< > $@
	chmod +x $@

ikiwiki.setup:
	HOME=/home/me $(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in -dumpsetup ikiwiki.setup

extra_build: $(outprogs) ikiwiki.setup docwiki sysconfdir
	./mdwn2man ikiwiki 1 doc/usage.mdwn > ikiwiki.man
	./mdwn2man ikiwiki-mass-rebuild 8 doc/ikiwiki-mass-rebuild.mdwn > ikiwiki-mass-rebuild.man
	./mdwn2man ikiwiki-makerepo 1 doc/ikiwiki-makerepo.mdwn > ikiwiki-makerepo.man
	./mdwn2man ikiwiki-transition 1 doc/ikiwiki-transition.mdwn > ikiwiki-transition.man
	./mdwn2man ikiwiki-update-wikilist 1 doc/ikiwiki-update-wikilist.mdwn > ikiwiki-update-wikilist.man
	./mdwn2man ikiwiki-calendar 1 doc/ikiwiki-calendar.mdwn > ikiwiki-calendar.man
	$(MAKE) -C po
	$(PERL) -pi.bkp -e "s/Version:.*/Version: $(VER)/" ikiwiki.spec
	rm -f ikiwiki.spec.bkp
	
docwiki:
	$(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in -setup docwiki.setup -refresh

sysconfdir:
	$(PERL) -pi -e "s|\"/etc/ikiwiki|\"$(SYSCONFDIR)|g" $(sysconfdir_scripts)
	
extra_clean:
	$(PERL) -Iblib/lib $(extramodules) $(tflag) ikiwiki.in -setup docwiki.setup -clean
	rm -f *.man $(outprogs) ikiwiki.setup plugins/*.pyc
	$(MAKE) -C po clean

# Joey uses this before committing.
myclean: clean
	git checkout po ikiwiki.spec

underlay_install:
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki
	for dir in `cd underlays && $(FIND) . -follow -type d`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `$(FIND) underlays/$$dir -follow -maxdepth 1 -type f ! -name jquery.js ! -name jquery-ui.css ! -name jquery-ui.js ! -name jquery.tmpl.js`; do \
			cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir 2>/dev/null || \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		done; \
	done

	# The directive docs become their own special underlay.
	install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive
	for file in doc/ikiwiki/directive/*; do \
		if [ -f "$$file" ]; then \
			cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive 2>/dev/null || \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/directives/ikiwiki/directive; \
		fi \
	done

	# Themes have their base.css (if present) and then
	# style.css appended to the normal one.
	for theme in themes/*; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$theme; \
		for file in $$theme/*; do \
			if echo "$$file" | grep -q style.css; then \
				(cat doc/style.css; cat $$theme/base.css 2>/dev/null; cat $$file) > $(DESTDIR)$(PREFIX)/share/ikiwiki/$$theme/style.css; \
			elif echo "$$file" | grep -q base.css; then \
				:; \
			elif [ -f "$$file" ]; then \
				cp -pRL $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$file 2>/dev/null || \
				install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$file; \
			fi \
		done; \
	done

extra_install: underlay_install
	# Install example sites.
	for dir in `cd doc/examples; $(FIND) . -type d ! -regex '.*discussion.*'`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$dir; \
	done
	for file in `cd doc/examples; $(FIND) . -type f ! -regex '.*discussion.*'`; do \
		cp -pRL doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file 2>/dev/null || \
		install -m 644 doc/examples/$$file $(DESTDIR)$(PREFIX)/share/ikiwiki/examples/$$file; \
	done

	for dir in `$(FIND) templates -follow -type d`; do \
		install -d $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		for file in `$(FIND) $$dir -follow -maxdepth 1 -type f`; do \
			install -m 644 $$file $(DESTDIR)$(PREFIX)/share/ikiwiki/$$dir; \
		done; \
	done
	
	install -d $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins
	for file in `$(FIND) plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* -name \*.py`; do \
		install -m 644 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done
	for file in `$(FIND) plugins -maxdepth 1 -type f ! -path plugins/.\* ! -name \*demo\* ! -name \*.py ! -name \*.pyc`; do \
		install -m 755 $$file $(DESTDIR)$(PREFIX)/lib/ikiwiki/plugins; \
	done

	install -d $(DESTDIR)$(MANDIR)/man1
	install -m 644 ikiwiki.man $(DESTDIR)$(MANDIR)/man1/ikiwiki.1
	install -m 644 ikiwiki-makerepo.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-makerepo.1
	install -m 644 ikiwiki-transition.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-transition.1
	install -m 644 ikiwiki-update-wikilist.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-update-wikilist.1
	install -m 644 ikiwiki-calendar.man $(DESTDIR)$(MANDIR)/man1/ikiwiki-calendar.1
	
	install -d $(DESTDIR)$(MANDIR)/man8
	install -m 644 ikiwiki-mass-rebuild.man $(DESTDIR)$(MANDIR)/man8/ikiwiki-mass-rebuild.8
	
	install -d $(DESTDIR)$(PREFIX)/sbin
	install ikiwiki-mass-rebuild $(DESTDIR)$(PREFIX)/sbin

	install -d $(DESTDIR)$(W3M_CGI_BIN)
	install ikiwiki-w3m.cgi $(DESTDIR)$(W3M_CGI_BIN)

	install -d $(DESTDIR)$(PREFIX)/bin
	for prog in $(outprogs) $(scripts); do \
		install $$prog $(DESTDIR)$(PREFIX)/bin/$$(echo $$prog | $(SED) 's/\.out//'); \
	done

	$(MAKE) -C po install DESTDIR=$(DESTDIR) PREFIX=$(PREFIX)
	
	# These might fail if a regular user is installing into a home
	# directory.
	-install -d $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 wikilist $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 auto.setup $(DESTDIR)$(SYSCONFDIR)
	-install -m 0644 auto-blog.setup $(DESTDIR)$(SYSCONFDIR)

# The git/hg plugins want to chdir; so does Devel::Cover. Skip those tests
# to stop them hurting each other.
coverage:
	cover -delete
	$(MAKE) test PERL5OPT=-MDevel::Cover PERL5LIB=. TEST_FILES="$(filter-out t/git.t t/mercurial.t,$(wildcard t/*.t))"
	cover
}
}

WriteMakefile(
	NAME		=> 'IkiWiki',
	PREFIX		=> "/usr/local",
	PM_FILTER	=> './pm_filter $(PREFIX) $(VER) $(PROBABLE_INST_LIB)',
	MAN1PODS	=> {},
	PREREQ_PM	=> {
		'XML::Simple'		=> "0",
		'Text::Markdown'	=> "0",
		'Date::Parse'		=> "0",
		'HTML::Template'	=> "0",
		'HTML::Scrubber'	=> "0",
		'CGI::FormBuilder'	=> "3.02.02",
		'CGI::Session'		=> "0",
		'Mail::Sendmail'	=> "0",
		'HTML::Parser'		=> "0",
		'URI'			=> "0",
		'Data::Dumper'		=> "2.11",
		'YAML::XS'		=> "0",
	},
);
