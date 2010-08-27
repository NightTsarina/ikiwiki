#!/usr/bin/perl
# Sidebar plugin.
# by Tuomo Valkonen <tuomov at iki dot fi>

package IkiWiki::Plugin::sidebar;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "sidebar", call => \&getsetup);
	hook(type => "preprocess", id => "sidebar", call => \&preprocess);
	hook(type => "pagetemplate", id => "sidebar", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		global_sidebars => {
			type => "boolean",
			example => 1,
			description => "show sidebar page on all pages?",
			safe => 1,
			rebuild => 1,
		},
}

my %pagesidebar;

sub preprocess (@) {
	my %params=@_;

	my $page=$params{page};
	return "" unless $page eq $params{destpage};
	
	if (! defined $params{content}) {
		$pagesidebar{$page}=undef;
	}
	else {
		my $file = $pagesources{$page};
		my $type = pagetype($file);

		$pagesidebar{$page}=
			IkiWiki::htmlize($page, $page, $type,
			IkiWiki::linkify($page, $page,
			IkiWiki::preprocess($page, $page, $params{content})));
	}

	return "";
}

my $oldfile;
my $oldcontent;

sub sidebar_content ($) {
	my $page=shift;
	
	return delete $pagesidebar{$page} if defined $pagesidebar{$page};

	return if ! exists $pagesidebar{$page} && 
		defined $config{global_sidebars} && ! $config{global_sidebars};

	my $sidebar_page=bestlink($page, "sidebar") || return;
	my $sidebar_file=$pagesources{$sidebar_page} || return;
	my $sidebar_type=pagetype($sidebar_file);
	
	if (defined $sidebar_type) {
		# FIXME: This isn't quite right; it won't take into account
		# adding a new sidebar page. So adding such a page
		# currently requires a wiki rebuild.
		add_depends($page, $sidebar_page);

		my $content;
		if (defined $oldfile && $sidebar_file eq $oldfile) {
			$content=$oldcontent;
		}
		else {
			$content=readfile(srcfile($sidebar_file));
			$oldcontent=$content;
			$oldfile=$sidebar_file;
		}

		return unless length $content;
		return IkiWiki::htmlize($sidebar_page, $page, $sidebar_type,
		       IkiWiki::linkify($sidebar_page, $page,
		       IkiWiki::preprocess($sidebar_page, $page,
		       IkiWiki::filter($sidebar_page, $page, $content))));
	}

}

sub pagetemplate (@) {
	my %params=@_;

	my $template=$params{template};
	if ($params{destpage} eq $params{page} &&
	    $template->query(name => "sidebar")) {
		my $content=sidebar_content($params{destpage});
		if (defined $content && length $content) {
		        $template->param(sidebar => $content);
		}
	}
}

1
