export PERL5LIB=$(CURDIR)/../../..
ikiwiki = $(CURDIR)/../../../ikiwiki.in

all:
	rm -fr git html
	mkdir -p git
	echo "/doc/.ikiwiki/" > git/.gitignore
	mkdir -p git/doc
	mkdir -p git/doc/writable
	cd git && git init
	cp index.mdwn git/doc/index.mdwn
	cp -a $(CURDIR)/../../../doc/wikiicons git/doc/
	cp -a $(CURDIR)/../../../doc/recentchanges.mdwn git/doc/
	echo "This is the first test page" > git/doc/writable/one.mdwn
	echo "This is the second test page" > git/doc/writable/two.mdwn
	cd git && git add . && git commit -m 'Initial commit'
	$(ikiwiki) --setup ikiwiki.setup
	echo "This is the first test page, it was first" > git/doc/writable/one.mdwn
	cd git && git add . && git commit -m 'First web commit'
	$(ikiwiki) --setup ikiwiki.setup
	echo "This is the second test page, it came second" > git/doc/writable/two.mdwn
	cd git && git add . && git commit -m 'Second web commit'
	$(ikiwiki) --setup ikiwiki.setup
	cd git && git mv doc/writable/one.mdwn doc/one.mdwn
	cd git && git mv doc/writable/two.mdwn two.mdwn
	cd git && git commit -m Rename
	$(ikiwiki) --setup ikiwiki.setup
	w3m html/index.html
