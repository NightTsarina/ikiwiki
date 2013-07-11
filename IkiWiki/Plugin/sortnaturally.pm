#!/usr/bin/perl
# Sort::Naturally-powered title_natural sort order for IkiWiki
package IkiWiki::Plugin::sortnaturally;

use IkiWiki 3.00;
no warnings;

sub import {
	hook(type => "getsetup", id => "sortnaturally", call => \&getsetup);
	hook(type => "checkconfig", id => "sortnaturally", call => \&checkconfig);
}

sub getsetup {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub checkconfig () {
	eval q{use Sort::Naturally};
	error $@ if $@;
}

package IkiWiki::SortSpec;

sub cmp_title_natural {
	Sort::Naturally::ncmp(IkiWiki::pagetitle(IkiWiki::basename($a)),
		IkiWiki::pagetitle(IkiWiki::basename($b)))
}

sub cmp_path_natural {
	Sort::Naturally::ncmp(IkiWiki::pagetitle($a),
		IkiWiki::pagetitle($b))
}

1;
