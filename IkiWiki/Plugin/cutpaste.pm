#!/usr/bin/perl
package IkiWiki::Plugin::cutpaste;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "cutpaste", call => \&getsetup);
	hook(type => "needsbuild", id => "cutpaste", call => \&needsbuild);
	hook(type => "preprocess", id => "cut", call => \&preprocess_cut, scan => 1);
	hook(type => "preprocess", id => "copy", call => \&preprocess_copy, scan => 1);
	hook(type => "preprocess", id => "paste", call => \&preprocess_paste);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{cutpaste}) {
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, will be re-added if
				# the cut/copy directive is still present
				# on rebuild.
				delete $pagestate{$page}{cutpaste};
			}
		}
	}
	return $needsbuild;
}

sub preprocess_cut (@) {
	my %params=@_;

	foreach my $param (qw{id text}) {
		if (! exists $params{$param}) {
			error sprintf(gettext('%s parameter is required'), $param);
		}
	}

	$pagestate{$params{page}}{cutpaste}{$params{id}} = $params{text};

	return "" if defined wantarray;
}

sub preprocess_copy (@) {
	my %params=@_;

	foreach my $param (qw{id text}) {
		if (! exists $params{$param}) {
			error sprintf(gettext('%s parameter is required'), $param);
		}
	}

	$pagestate{$params{page}}{cutpaste}{$params{id}} = $params{text};

	return IkiWiki::preprocess($params{page}, $params{destpage}, $params{text})
		if defined wantarray;
}

sub preprocess_paste (@) {
	my %params=@_;

	foreach my $param (qw{id}) {
		if (! exists $params{$param}) {
			error sprintf(gettext('%s parameter is required'), $param);
		}
	}

	if (! exists $pagestate{$params{page}}{cutpaste}) {
		error gettext('no text was copied in this page');
	}
	if (! exists $pagestate{$params{page}}{cutpaste}{$params{id}}) {
		error sprintf(gettext('no text was copied in this page with id %s'), $params{id});
	}

	return IkiWiki::preprocess($params{page}, $params{destpage},
		$pagestate{$params{page}}{cutpaste}{$params{id}});
}

1;
