#!/usr/bin/perl
# Sort::Naturally-powered title_natural sort order for IkiWiki
package IkiWiki::Plugin::sortnaturally;

use IkiWiki 3.00;
no warnings;

sub import {
	hook(type => "getsetup", id => "sortnaturally", call => \&getsetup);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	eval q{use Sort::Naturally};
	error $@ if $@;
}

package IkiWiki::SortSpec;

sub cmp_title_natural {
	Sort::Naturally::ncmp(IkiWiki::pagetitle(IkiWiki::basename($_[0])),
		IkiWiki::pagetitle(IkiWiki::basename($_[1])))
}

1;
