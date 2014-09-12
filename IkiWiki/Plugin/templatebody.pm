#!/usr/bin/perl
# Define self-documenting templates as wiki pages without HTML::Template
# markup leaking into IkiWiki's output.
# Copyright © 2013-2014 Simon McVittie. GPL-2+, see debian/copyright
package IkiWiki::Plugin::templatebody;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "templatebody", call => \&getsetup);
	hook(type => "preprocess", id => "templatebody", call => \&preprocess,
		scan => 1);
	hook(type => "readtemplate", id => "templatebody",
		call => \&readtemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "core",
		},
}

# This doesn't persist between runs: we're going to read and scan the
# template file regardless, so there's no point in saving it to the index.
# Example contents:
# ("templates/note" => "<div class=\"notebox\">\n<TMPL_VAR text>\n</div>")
my %templates;

sub preprocess (@) {
	my %params=@_;

	# [[!templatebody "<div>hello</div>"]] results in
	# preprocess("<div>hello</div>" => undef, page => ...)
	my $content = $_[0];
	if (length $_[1]) {
		error(gettext("first parameter must be the content"));
	}

	$templates{$params{page}} = $content;

	return "";
}

sub readtemplate {
	my %params = @_;
	my $tpage = $params{page};
	my $content = $params{content};
	my $filename = $params{filename};

	# pass-through if it's a .tmpl attachment or otherwise unsuitable
	return $content unless defined $tpage;
	return $content if $tpage =~ /\.tmpl$/;
	my $src = $pagesources{$tpage};
	return $content unless defined $src;
	return $content unless defined pagetype($src);

	# We might be using the template for [[!template]], which has to run
	# during the scan stage so that templates can include scannable
	# directives which are expanded in the resulting page. Calls to
	# IkiWiki::scan are in arbitrary order, so the template might
	# not have been scanned yet. Make sure.
	require IkiWiki::Render;
	IkiWiki::scan($src);

	# Having scanned it, we know whether it had a [[!templatebody]].
	if (exists $templates{$tpage}) {
		return $templates{$tpage};
	}

	# If not, return the whole thing. (Eventually, after implementing
	# a transition, this can become an error.)
	return $content;
}

1
