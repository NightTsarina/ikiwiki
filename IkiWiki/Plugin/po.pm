#!/usr/bin/perl
# .po as a wiki page type
# Licensed under GPL v2 or greater
# Copyright (C) 2008-2009 intrigeri <intrigeri@boum.org>
# inspired by the GPL'd po4a-translate,
# which is Copyright 2002, 2003, 2004 by Martin Quinson (mquinson#debian.org)
package IkiWiki::Plugin::po;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;
eval q{use Locale::Po4a::Common qw(nowrapi18n !/.*/)};
if ($@) {
	print STDERR gettext("warning: Old po4a detected! Recommend upgrade to 0.35.")."\n";
	eval q{use Locale::Po4a::Common qw(!/.*/)};
	die $@ if $@;
}
use Locale::Po4a::Chooser;
use Locale::Po4a::Po;
use File::Basename;
use File::Copy;
use File::Spec;
use File::Temp;
use Memoize;
use UNIVERSAL;

my ($master_language_code, $master_language_name);
my %translations;
my @origneedsbuild;
my %origsubs;
my @slavelanguages; # language codes ordered as in config po_slave_languages
my %slavelanguages; # language code to name lookup
my $language_code_pattern = '[a-zA-Z]+(?:_[a-zA-Z]+)?';

memoize("istranslatable");
memoize("_istranslation");
memoize("percenttranslated");

sub import {
	hook(type => "getsetup", id => "po", call => \&getsetup);
	hook(type => "checkconfig", id => "po", call => \&checkconfig,
		last => 1);
	hook(type => "needsbuild", id => "po", call => \&needsbuild);
	hook(type => "scan", id => "po", call => \&scan, last => 1);
	hook(type => "filter", id => "po", call => \&filter);
	hook(type => "htmlize", id => "po", call => \&htmlize);
	hook(type => "pagetemplate", id => "po", call => \&pagetemplate, last => 1);
	hook(type => "rename", id => "po", call => \&renamepages, first => 1);
	hook(type => "delete", id => "po", call => \&mydelete);
	hook(type => "change", id => "po", call => \&change);
	hook(type => "checkcontent", id => "po", call => \&checkcontent);
	hook(type => "canremove", id => "po", call => \&canremove);
	hook(type => "canrename", id => "po", call => \&canrename);
	hook(type => "editcontent", id => "po", call => \&editcontent);
	hook(type => "formbuilder_setup", id => "po", call => \&formbuilder_setup, last => 1);
	hook(type => "formbuilder", id => "po", call => \&formbuilder);

	if (! %origsubs) {
		$origsubs{'bestlink'}=\&IkiWiki::bestlink;
		inject(name => "IkiWiki::bestlink", call => \&mybestlink);
		$origsubs{'beautify_urlpath'}=\&IkiWiki::beautify_urlpath;
		inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);
		$origsubs{'targetpage'}=\&IkiWiki::targetpage;
		inject(name => "IkiWiki::targetpage", call => \&mytargetpage);
		$origsubs{'urlto'}=\&IkiWiki::urlto;
		inject(name => "IkiWiki::urlto", call => \&myurlto);
		$origsubs{'cgiurl'}=\&IkiWiki::cgiurl;
		inject(name => "IkiWiki::cgiurl", call => \&mycgiurl);
		if (IkiWiki->can('rootpage')) {
			$origsubs{'rootpage'}=\&IkiWiki::rootpage;
			inject(name => "IkiWiki::rootpage", call => \&myrootpage)
				if defined $origsubs{'rootpage'};
		}
		$origsubs{'isselflink'}=\&IkiWiki::isselflink;
		inject(name => "IkiWiki::isselflink", call => \&myisselflink);
	}
}


# ,----
# | Table of contents
# `----

# 1. Hooks
# 2. Injected functions
# 3. Blackboxes for private data
# 4. Helper functions
# 5. PageSpecs


# ,----
# | Hooks
# `----

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
			section => "format",
		},
		po_master_language => {
			type => "string",
			example => "en|English",
			description => "master language (non-PO files)",
			safe => 1,
			rebuild => 1,
		},
		po_slave_languages => {
			type => "string",
			example => [
				'fr|Français',
				'es|Español',
				'de|Deutsch'
			],
			description => "slave languages (translated via PO files) format: ll|Langname",
			safe => 1,
			rebuild => 1,
		},
		po_translatable_pages => {
			type => "pagespec",
			example => "* and !*/Discussion",
			description => "PageSpec controlling which pages are translatable",
			link => "ikiwiki/PageSpec",
			safe => 1,
			rebuild => 1,
		},
		po_link_to => {
			type => "string",
			example => "current",
			description => "internal linking behavior (default/current/negotiated)",
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (exists $config{po_master_language}) {
		if (! ref $config{po_master_language}) {
			($master_language_code, $master_language_name)=
				splitlangpair($config{po_master_language});
		}
		else {
			$master_language_code=$config{po_master_language}{code};
			$master_language_name=$config{po_master_language}{name};
			$config{po_master_language}=joinlangpair($master_language_code, $master_language_name);
		}
	}
	if (! defined $master_language_code) {
		$master_language_code='en';
	}
	if (! defined $master_language_name) {
		$master_language_name='English';
	}

	if (ref $config{po_slave_languages} eq 'ARRAY') {
		foreach my $pair (@{$config{po_slave_languages}}) {
			my ($code, $name)=splitlangpair($pair);
			if (defined $code && ! exists $slavelanguages{$code}) {
				push @slavelanguages, $code;
				$slavelanguages{$code} = $name;
			}
		}
	}
	elsif (ref $config{po_slave_languages} eq 'HASH') {
		%slavelanguages=%{$config{po_slave_languages}};
		@slavelanguages = sort {
			$config{po_slave_languages}->{$a} cmp $config{po_slave_languages}->{$b};
		} keys %slavelanguages;
		$config{po_slave_languages}=[
			map { joinlangpair($_, $slavelanguages{$_}) } @slavelanguages
		]
	}

	delete $slavelanguages{$master_language_code};

	map {
		islanguagecode($_)
			or error(sprintf(gettext("%s is not a valid language code"), $_));
	} ($master_language_code, @slavelanguages);

	if (! exists $config{po_translatable_pages} ||
	    ! defined $config{po_translatable_pages}) {
		$config{po_translatable_pages}="";
	}
	if (! exists $config{po_link_to} ||
	    ! defined $config{po_link_to}) {
		$config{po_link_to}='default';
	}
	elsif ($config{po_link_to} !~ /^(default|current|negotiated)$/) {
		warn(sprintf(gettext('%s is not a valid value for po_link_to, falling back to po_link_to=default'),
			     $config{po_link_to}));
		$config{po_link_to}='default';
	}
	elsif ($config{po_link_to} eq "negotiated" && ! $config{usedirs}) {
		warn(gettext('po_link_to=negotiated requires usedirs to be enabled, falling back to po_link_to=default'));
		$config{po_link_to}='default';
	}

	push @{$config{wiki_file_prune_regexps}}, qr/\.pot$/;

	# Translated versions of the underlays are added if available.
	foreach my $underlay ("basewiki",
	                      map { m/^\Q$config{underlaydirbase}\E\/*(.*)/ }
	                          reverse @{$config{underlaydirs}}) {
		next if $underlay=~/^locale\//;

		# Underlays containing the po files for slave languages.
		foreach my $ll (@slavelanguages) {
			add_underlay("po/$ll/$underlay")
				if -d "$config{underlaydirbase}/po/$ll/$underlay";
		}
	
		if ($master_language_code ne 'en') {
			# Add underlay containing translated source files
			# for the master language.
			add_underlay("locale/$master_language_code/$underlay")
				if -d "$config{underlaydirbase}/locale/$master_language_code/$underlay";
		}
	}
}

sub needsbuild () {
	my $needsbuild=shift;

	# backup @needsbuild content so that change() can know whether
	# a given master page was rendered because its source file was changed
	@origneedsbuild=(@$needsbuild);

	flushmemoizecache();
	buildtranslationscache();

	# make existing translations depend on the corresponding master page
	foreach my $master (keys %translations) {
		map add_depends($_, $master), values %{otherlanguages_pages($master)};
	}

	return $needsbuild;
}

sub scan (@) {
	my %params=@_;
	my $page=$params{page};
	my $content=$params{content};
	my $run_by_po=$params{run_by_po};

	# Massage the recorded state of internal links so that:
	# - it matches the actually generated links, rather than the links as
	#   written in the pages' source
	# - backlinks are consistent in all cases

	# A second scan pass is made over translation pages, so as an
	# optimization, we only do so on the second pass in this case,
	# i.e. when this hook is called by itself.
	if ($run_by_po && istranslation($page)) {
		# replace the occurence of $destpage in $links{$page}
		my @orig_links = @{$links{$page}};
		$links{$page} = [];
		foreach my $destpage (@orig_links) {
			if (istranslatedto($destpage, lang($page))) {
				add_link($page, $destpage . '.' . lang($page));
			}
			else {
				add_link($page, $destpage);
			}
		}
	}
	# No second scan pass is done for a non-translation page, so
	# links massaging must happen on first pass in this case.
	elsif (! $run_by_po && ! istranslatable($page) && ! istranslation($page)) {
		foreach my $destpage (@{$links{$page}}) {
			if (istranslatable($destpage)) {
				# make sure any destpage's translations has
				# $page in its backlinks
				foreach my $link (values %{otherlanguages_pages($destpage)}) {
					add_link($page, $link);
				}
			}
		}
	}

	# Re-run the preprocess hooks in scan mode, then the scan hooks,
	# over the po-to-markup converted content
	return if $run_by_po; # avoid looping endlessly
	return unless istranslation($page);
	$content = po_to_markup($page, $content);
	require IkiWiki;
	IkiWiki::preprocess($page, $page, $content, 1);
	IkiWiki::run_hooks(scan => sub {
		shift->(
			page => $page,
			content => $content,
			run_by_po => 1,
		);
	});
}

# We use filter to convert PO to the master page's format,
# since the rest of ikiwiki should not work on PO files.
sub filter (@) {
	my %params = @_;

	my $page = $params{page};
	my $destpage = $params{destpage};
	my $content = $params{content};
	if (istranslation($page) && ! alreadyfiltered($page, $destpage)) {
		$content = po_to_markup($page, $content);
		setalreadyfiltered($page, $destpage);
	}
	return $content;
}

sub htmlize (@) {
	my %params=@_;

	my $page = $params{page};
	my $content = $params{content};

	# ignore PO files this plugin did not create
	return $content unless istranslation($page);

	# force content to be htmlize'd as if it was the same type as the master page
	return IkiWiki::htmlize($page, $page,
		pagetype(srcfile($pagesources{masterpage($page)})),
		$content);
}

sub pagetemplate (@) {
	my %params=@_;
	my $page=$params{page};
	my $destpage=$params{destpage};
	my $template=$params{template};

	my ($masterpage, $lang) = istranslation($page);

	if (istranslation($page) && $template->query(name => "percenttranslated")) {
		$template->param(percenttranslated => percenttranslated($page));
	}
	if ($template->query(name => "istranslation")) {
		$template->param(istranslation => scalar istranslation($page));
	}
	if ($template->query(name => "istranslatable")) {
		$template->param(istranslatable => istranslatable($page));
	}
	if ($template->query(name => "HOMEPAGEURL")) {
		$template->param(homepageurl => homepageurl($page));
	}
	if ($template->query(name => "otherlanguages")) {
		$template->param(otherlanguages => [otherlanguagesloop($page)]);
		map add_depends($page, $_), (values %{otherlanguages_pages($page)});
	}
	if ($config{discussion} && istranslation($page)) {
		if ($page !~ /.*\/\Q$config{discussionpage}\E$/i &&
		   (length $config{cgiurl} ||
		    exists $links{$masterpage."/".lc($config{discussionpage})})) {
			$template->param('discussionlink' => htmllink(
				$page,
				$destpage,
				$masterpage . '/' . $config{discussionpage},
				noimageinline => 1,
				forcesubpage => 0,
				linktext => $config{discussionpage},
		));
		}
	}
	# Remove broken parentlink to ./index.html on home page's translations.
	# It works because this hook has the "last" parameter set, to ensure it
	# runs after parentlinks' own pagetemplate hook.
	if ($template->param('parentlinks')
	    && istranslation($page)
	    && $masterpage eq "index") {
		$template->param('parentlinks' => []);
	}
	if (ishomepage($page) && $template->query(name => "title")
	    && !$template->param("title_overridden")) {
		$template->param(title => $config{wikiname});
	}
}

# Add the renamed page translations to the list of to-be-renamed pages.
sub renamepages (@) {
	my %params = @_;

	my %torename = %{$params{torename}};
	my $session = $params{session};

	# Save the page(s) the user asked to rename, so that our
	# canrename hook can tell the difference between:
	#  - a translation being renamed as a consequence of its master page
	#    being renamed
	#  - a user trying to directly rename a translation
	# This is why this hook has to be run first, before the list of pages
	# to rename is modified by other plugins.
	my @orig_torename;
	@orig_torename=@{$session->param("po_orig_torename")}
		if defined $session->param("po_orig_torename");
	push @orig_torename, $torename{src};
	$session->param(po_orig_torename => \@orig_torename);
	IkiWiki::cgi_savesession($session);

	return () unless istranslatable($torename{src});

	my @ret;
	my %otherpages=%{otherlanguages_pages($torename{src})};
	while (my ($lang, $otherpage) = each %otherpages) {
		push @ret, {
			src => $otherpage,
			srcfile => $pagesources{$otherpage},
			dest => otherlanguage_page($torename{dest}, $lang),
			destfile => $torename{dest}.".".$lang.".po",
			required => 0,
		};
	}
	return @ret;
}

sub mydelete (@) {
	my @deleted=@_;

	map { deletetranslations($_) } grep istranslatablefile($_), @deleted;
}

sub change (@) {
	my @rendered=@_;

	my $updated_po_files=0;

	# Refresh/create POT and PO files as needed.
	foreach my $file (grep {istranslatablefile($_)} @rendered) {
		my $masterfile=srcfile($file);
		my $page=pagename($file);
		my $updated_pot_file=0;

		# Avoid touching underlay files.
		next if $masterfile ne "$config{srcdir}/$file";

		# Only refresh POT file if it does not exist, or if
		# the source was changed: don't if only the HTML was
		# refreshed, e.g. because of a dependency.
		if ((grep { $_ eq $pagesources{$page} } @origneedsbuild) ||
		    ! -e potfile($masterfile)) {
			refreshpot($masterfile);
			$updated_pot_file=1;
		}
		my @pofiles;
		foreach my $po (pofiles($masterfile)) {
			next if ! $updated_pot_file && -e $po;
			next if grep { $po=~/\Q$_\E/ } @{$config{underlaydirs}};
			push @pofiles, $po;
		}
		if (@pofiles) {
			refreshpofiles($masterfile, @pofiles);
			map { s/^\Q$config{srcdir}\E\/*//; IkiWiki::rcs_add($_) } @pofiles if $config{rcs};
			$updated_po_files=1;
		}
	}

	if ($updated_po_files) {
		commit_and_refresh(
			gettext("updated PO files"));
	}
}

sub checkcontent (@) {
	my %params=@_;

	if (istranslation($params{page})) {
		my $res = isvalidpo($params{content});
		if ($res) {
			return undef;
		}
		else {
			return "$res";
		}
	}
	return undef;
}

sub canremove (@) {
	my %params = @_;

	if (istranslation($params{page})) {
		return gettext("Can not remove a translation. If the master page is removed, ".
			       "however, its translations will be removed as well.");
	}
	return undef;
}

sub canrename (@) {
	my %params = @_;
	my $session = $params{session};

	if (istranslation($params{src})) {
		my $masterpage = masterpage($params{src});
		# Tell the difference between:
		#  - a translation being renamed as a consequence of its master page
		#    being renamed, which is allowed
		#  - a user trying to directly rename a translation, which is forbidden
		# by looking for the master page in the list of to-be-renamed pages we
		# saved early in the renaming process.
		my $orig_torename = $session->param("po_orig_torename");
		unless (grep { $_ eq $masterpage } @{$orig_torename}) {
			return gettext("Can not rename a translation. If the master page is renamed, ".
				       "however, its translations will be renamed as well.");
		}
	}
	return undef;
}

# As we're previewing or saving a page, the content may have
# changed, so tell the next filter() invocation it must not be lazy.
sub editcontent () {
	my %params=@_;

	unsetalreadyfiltered($params{page}, $params{page});
	return $params{content};
}

sub formbuilder_setup (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	return unless defined $form->field("do");

	if ($form->field("do") eq "create") {
		# Warn the user: new pages must be written in master language.
		my $template=template("pocreatepage.tmpl");
		$template->param(LANG => $master_language_name);
		$form->tmpl_param(message => $template->output);
	}
	elsif ($form->field("do") eq "edit") {
		# Remove the rename/remove buttons on slave pages.
		# This has to be done after the rename/remove plugins have added
		# their buttons, which is why this hook must be run last.
		# The canrename/canremove hooks already ensure this is forbidden
		# at the backend level, so this is only UI sugar.
		if (istranslation($form->field("page"))) {
			map {
				for (my $i = 0; $i < @{$params{buttons}}; $i++) {
					if (@{$params{buttons}}[$i] eq $_) {
						delete  @{$params{buttons}}[$i];
						last;
					}
				}
			} qw(Rename Remove);
		}
	}
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	return unless defined $form->field("do");

	# Do not allow to create pages of type po: they are automatically created.
	# The main reason to do so is to bypass the "favor the type of linking page
	# on page creation" logic, which is unsuitable when a broken link is clicked
	# on a slave (PO) page.
	# This cannot be done in the formbuilder_setup hook as the list of types is
	# computed later.
	if ($form->field("do") eq "create") {
		foreach my $field ($form->field) {
			next unless "$field" eq "type";
			next unless $field->type eq 'select';
			my $orig_value = $field->value;
			# remove po from the list of types
			my @types = grep { $_->[0] ne 'po' } $field->options;
			$field->options(\@types) if @types;
			# favor the type of linking page's masterpage
			if ($orig_value eq 'po') {
				my ($from, $type);
				if (defined $form->field('from')) {
					($from)=$form->field('from')=~/$config{wiki_file_regexp}/;
					$from = masterpage($from);
				}
				if (defined $from && exists $pagesources{$from}) {
					$type=pagetype($pagesources{$from});
				}
				$type=$config{default_pageext} unless defined $type;
				$field->value($type) ;
			}
		}
	}
}

# ,----
# | Injected functions
# `----

# Implement po_link_to 'current' and 'negotiated' settings.
sub mybestlink ($$) {
	my $page=shift;
	my $link=shift;

	return $origsubs{'bestlink'}->($page, $link)
		if defined $config{po_link_to} && $config{po_link_to} eq "default";

	my $res=$origsubs{'bestlink'}->(masterpage($page), $link);
	my @caller = caller(1);
	if (length $res
	    && istranslatedto($res, lang($page))
	    && istranslation($page)
	    &&  !(exists $caller[3] && defined $caller[3]
		  && ($caller[3] eq "IkiWiki::PageSpec::match_link"))) {
		return $res . "." . lang($page);
	}
	return $res;
}

sub mybeautify_urlpath ($) {
	my $url=shift;

	my $res=$origsubs{'beautify_urlpath'}->($url);
	if (defined $config{po_link_to} && $config{po_link_to} eq "negotiated") {
		$res =~ s!/\Qindex.$master_language_code.$config{htmlext}\E$!/!;
		$res =~ s!/\Qindex.$config{htmlext}\E$!/!;
		map {
			$res =~ s!/\Qindex.$_.$config{htmlext}\E$!/!;
		} @slavelanguages;
	}
	return $res;
}

sub mytargetpage ($$;$) {
	my $page=shift;
	my $ext=shift;
	my $filename=shift;

	if (istranslation($page) || istranslatable($page)) {
		my ($masterpage, $lang) = (masterpage($page), lang($page));
		if (defined $filename) {
			return $masterpage . "/" . $filename . "." . $lang . "." . $ext;
		}
		elsif (! $config{usedirs} || $masterpage eq 'index') {
			return $masterpage . "." . $lang . "." . $ext;
		}
		else {
			return $masterpage . "/index." . $lang . "." . $ext;
		}
	}
	return $origsubs{'targetpage'}->($page, $ext, $filename);
}

sub myurlto ($;$$) {
	my $to=shift;
	my $from=shift;
	my $absolute=shift;

	# workaround hard-coded /index.$config{htmlext} in IkiWiki::urlto()
	if (! length $to
	    && $config{po_link_to} eq "current"
	    && istranslatable('index')) {
		if (defined $from) {
			return IkiWiki::beautify_urlpath(IkiWiki::baseurl($from) . "index." . lang($from) . ".$config{htmlext}");
		}
		else {
			return $origsubs{'urlto'}->($to,$from,$absolute);
		}
	}
	# avoid using our injected beautify_urlpath if run by cgi_editpage,
	# so that one is redirected to the just-edited page rather than to the
	# negociated translation; to prevent unnecessary fiddling with caller/inject,
	# we only do so when our beautify_urlpath would actually do what we want to
	# avoid, i.e. when po_link_to = negotiated.
	# also avoid doing so when run by cgi_goto, so that the links on recentchanges
	# page actually lead to the exact page they pretend to.
	if ($config{po_link_to} eq "negotiated") {
		my @caller = caller(1);
		my $use_orig = 0;
		$use_orig = 1 if (exists $caller[3] && defined $caller[3]
				 && ($caller[3] eq "IkiWiki::cgi_editpage" ||
				     $caller[3] eq "IkiWiki::Plugin::goto::cgi_goto")
				 );
		inject(name => "IkiWiki::beautify_urlpath", call => $origsubs{'beautify_urlpath'})
			if $use_orig;
		my $res = $origsubs{'urlto'}->($to,$from,$absolute);
		inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath)
			if $use_orig;
		return $res;
	}
	else {
		return $origsubs{'urlto'}->($to,$from,$absolute)
	}
}

sub mycgiurl (@) {
	my %params=@_;

	# slave pages have no subpages
	if (istranslation($params{'from'})) {
		$params{'from'} = masterpage($params{'from'});
	}
	return $origsubs{'cgiurl'}->(%params);
}

sub myrootpage (@) {
	my %params=@_;

	my $rootpage;
	if (exists $params{rootpage}) {
		$rootpage=$origsubs{'bestlink'}->($params{page}, $params{rootpage});
		if (!length $rootpage) {
			$rootpage=$params{rootpage};
		}
	}
	else {
		$rootpage=masterpage($params{page});
	}
	return $rootpage;
}

sub myisselflink ($$) {
	my $page=shift;
	my $link=shift;

	return 1 if $origsubs{'isselflink'}->($page, $link);
	if (istranslation($page)) {
		return $origsubs{'isselflink'}->(masterpage($page), $link);
	}
	return;
}

# ,----
# | Blackboxes for private data
# `----

{
	my %filtered;

	sub alreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		return exists $filtered{$page}{$destpage}
			 && $filtered{$page}{$destpage} eq 1;
	}

	sub setalreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		$filtered{$page}{$destpage}=1;
	}

	sub unsetalreadyfiltered($$) {
		my $page=shift;
		my $destpage=shift;

		if (exists $filtered{$page}{$destpage}) {
			delete $filtered{$page}{$destpage};
		}
	}

	sub resetalreadyfiltered() {
		undef %filtered;
	}
}

# ,----
# | Helper functions
# `----

sub maybe_add_leading_slash ($;$) {
	my $str=shift;
	my $add=shift;
	$add=1 unless defined $add;
	return '/' . $str if $add;
	return $str;
}

sub istranslatablefile ($) {
	my $file=shift;

	return 0 unless defined $file;
	my $type=pagetype($file);
	return 0 if ! defined $type || $type eq 'po';
	return 0 if $file =~ /\.pot$/;
	return 0 if ! defined $config{po_translatable_pages};
	return 1 if pagespec_match(pagename($file), $config{po_translatable_pages});
	return;
}

sub istranslatable ($) {
	my $page=shift;

	$page=~s#^/##;
	return 1 if istranslatablefile($pagesources{$page});
	return;
}

sub istranslatedto ($$) {
	my $page=shift;
	my $destlang = shift;

	$page=~s#^/##;
	return 0 unless istranslatable($page);
	exists $pagesources{otherlanguage_page($page, $destlang)};
}

sub _istranslation ($) {
	my $page=shift;

	$page='' unless defined $page && length $page;
	my $hasleadingslash = ($page=~s#^/##);
	my $file=$pagesources{$page};
	return 0 unless defined $file
			 && defined pagetype($file)
			 && pagetype($file) eq 'po';
	return 0 if $file =~ /\.pot$/;

	my ($masterpage, $lang) = ($page =~ /(.*)[.]($language_code_pattern)$/);
	return 0 unless defined $masterpage && defined $lang
			 && length $masterpage && length $lang
			 && defined $pagesources{$masterpage}
			 && defined $slavelanguages{$lang};

	return (maybe_add_leading_slash($masterpage, $hasleadingslash), $lang)
		if istranslatable($masterpage);
}

sub istranslation ($) {
	my $page=shift;

	if (1 < (my ($masterpage, $lang) = _istranslation($page))) {
		my $hasleadingslash = ($masterpage=~s#^/##);
		$translations{$masterpage}{$lang}=$page unless exists $translations{$masterpage}{$lang};
		return (maybe_add_leading_slash($masterpage, $hasleadingslash), $lang);
	}
	return "";
}

sub masterpage ($) {
	my $page=shift;

	if ( 1 < (my ($masterpage, $lang) = _istranslation($page))) {
		return $masterpage;
	}
	return $page;
}

sub lang ($) {
	my $page=shift;

	if (1 < (my ($masterpage, $lang) = _istranslation($page))) {
		return $lang;
	}
	return $master_language_code;
}

sub islanguagecode ($) {
	my $code=shift;

	return $code =~ /^$language_code_pattern$/;
}

sub otherlanguage_page ($$) {
	my $page=shift;
	my $code=shift;

	return masterpage($page) if $code eq $master_language_code;
	return masterpage($page) . '.' . $code;
}

# Returns the list of other languages codes: the master language comes first,
# then the codes are ordered the same way as in po_slave_languages, if it is
# an array, or in the language name lexical order, if it is a hash.
sub otherlanguages_codes ($) {
	my $page=shift;

	my @ret;
	return \@ret unless istranslation($page) || istranslatable($page);
	my $curlang=lang($page);
	foreach my $lang
		($master_language_code, @slavelanguages) {
		next if $lang eq $curlang;
		if ($lang eq $master_language_code ||
		    istranslatedto(masterpage($page), $lang)) {
			push @ret, $lang;
		}
	}
	return \@ret;
}

sub otherlanguages_pages ($) {
	my $page=shift;

	my %ret;
	map {
		$ret{$_} = otherlanguage_page($page, $_)
	} @{otherlanguages_codes($page)};

	return \%ret;
}

sub potfile ($) {
	my $masterfile=shift;

	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	$dir='' if $dir eq './';
	return File::Spec->catpath('', $dir, $name . ".pot");
}

sub pofile ($$) {
	my $masterfile=shift;
	my $lang=shift;

	(my $name, my $dir, my $suffix) = fileparse($masterfile, qr/\.[^.]*/);
	$dir='' if $dir eq './';
	return File::Spec->catpath('', $dir, $name . "." . $lang . ".po");
}

sub pofiles ($) {
	my $masterfile=shift;

	return map pofile($masterfile, $_), @slavelanguages;
}

sub refreshpot ($) {
	my $masterfile=shift;

	my $potfile=potfile($masterfile);
	my $doc=Locale::Po4a::Chooser::new(po4a_type($masterfile),
					   po4a_options($masterfile));
	$doc->{TT}{utf_mode} = 1;
	$doc->{TT}{file_in_charset} = 'UTF-8';
	$doc->{TT}{file_out_charset} = 'UTF-8';
	$doc->read($masterfile);
	# let's cheat a bit to force porefs option to be passed to
	# Locale::Po4a::Po; this is undocument use of internal
	# Locale::Po4a::TransTractor's data, compulsory since this module
	# prevents us from using the porefs option.
	$doc->{TT}{po_out}=Locale::Po4a::Po->new({ 'porefs' => 'none' });
	$doc->{TT}{po_out}->set_charset('UTF-8');
	# do the actual work
	$doc->parse;
	IkiWiki::prep_writefile(basename($potfile),dirname($potfile));
	$doc->writepo($potfile);
}

sub refreshpofiles ($@) {
	my $masterfile=shift;
	my @pofiles=@_;

	my $potfile=potfile($masterfile);
	if (! -e $potfile) {
		error("po(refreshpofiles) ".sprintf(gettext("POT file (%s) does not exist"), $potfile));
	}

	foreach my $pofile (@pofiles) {
		IkiWiki::prep_writefile(basename($pofile),dirname($pofile));

		if (! -e $pofile) {
			# If the po file exists in an underlay, copy it
			# from there.
			my ($pobase)=$pofile=~/^\Q$config{srcdir}\E\/?(.*)$/;
			foreach my $dir (@{$config{underlaydirs}}) {
				if (-e "$dir/$pobase") {
					File::Copy::syscopy("$dir/$pobase",$pofile)
						or error("po(refreshpofiles) ".
							 sprintf(gettext("failed to copy underlay PO file to %s"),
								 $pofile));
				}
			}
		}

		if (-e $pofile) {
			system("msgmerge", "--previous", "-q", "-U", "--backup=none", $pofile, $potfile) == 0
				or error("po(refreshpofiles) ".
					 sprintf(gettext("failed to update %s"),
						 $pofile));
		}
		else {
			File::Copy::syscopy($potfile,$pofile)
				or error("po(refreshpofiles) ".
					 sprintf(gettext("failed to copy the POT file to %s"),
						 $pofile));
		}
	}
}

sub buildtranslationscache() {
	# use istranslation's side-effect
	map istranslation($_), (keys %pagesources);
}

sub resettranslationscache() {
	undef %translations;
}

sub flushmemoizecache() {
	Memoize::flush_cache("istranslatable");
	Memoize::flush_cache("_istranslation");
	Memoize::flush_cache("percenttranslated");
}

sub urlto_with_orig_beautiful_urlpath($$) {
	my $to=shift;
	my $from=shift;

	inject(name => "IkiWiki::beautify_urlpath", call => $origsubs{'beautify_urlpath'});
	my $res=urlto($to, $from);
	inject(name => "IkiWiki::beautify_urlpath", call => \&mybeautify_urlpath);

	return $res;
}

sub percenttranslated ($) {
	my $page=shift;

	$page=~s/^\///;
	return gettext("N/A") unless istranslation($page);
	my $file=srcfile($pagesources{$page});
	my $masterfile = srcfile($pagesources{masterpage($page)});
	my $doc=Locale::Po4a::Chooser::new(po4a_type($masterfile),
					   po4a_options($masterfile));
	$doc->process(
		'po_in_name'	=> [ $file ],
		'file_in_name'	=> [ $masterfile ],
		'file_in_charset'  => 'UTF-8',
		'file_out_charset' => 'UTF-8',
	) or error("po(percenttranslated) ".
		   sprintf(gettext("failed to translate %s"), $page));
	my ($percent,$hit,$queries) = $doc->stats();
	$percent =~ s/\.[0-9]+$//;
	return $percent;
}

sub languagename ($) {
	my $code=shift;

	return $master_language_name
		if $code eq $master_language_code;
	return $slavelanguages{$code}
		if defined $slavelanguages{$code};
	return;
}

sub otherlanguagesloop ($) {
	my $page=shift;

	my @ret;
	if (istranslation($page)) {
		push @ret, {
			url => urlto_with_orig_beautiful_urlpath(masterpage($page), $page),
			code => $master_language_code,
			language => $master_language_name,
			master => 1,
		};
	}
	foreach my $lang (@{otherlanguages_codes($page)}) {
		next if $lang eq $master_language_code;
		my $otherpage = otherlanguage_page($page, $lang);
		push @ret, {
			url => urlto_with_orig_beautiful_urlpath($otherpage, $page),
			code => $lang,
			language => languagename($lang),
			percent => percenttranslated($otherpage),
		}
	}
	return @ret;
}

sub homepageurl (;$) {
	my $page=shift;

	return urlto('', $page);
}

sub ishomepage ($) {
	my $page = shift;

	return 1 if $page eq 'index';
	map { return 1 if $page eq 'index.'.$_ } @slavelanguages;
	return undef;
}

sub deletetranslations ($) {
	my $deletedmasterfile=shift;

	my $deletedmasterpage=pagename($deletedmasterfile);
	my @todelete;
	map {
		my $file = newpagefile($deletedmasterpage.'.'.$_, 'po');
		my $absfile = "$config{srcdir}/$file";
		if (-e $absfile && ! -l $absfile && ! -d $absfile) {
			push @todelete, $file;
		}
	} @slavelanguages;

	map {
		if ($config{rcs}) {
			IkiWiki::rcs_remove($_);
		}
		else {
			IkiWiki::prune("$config{srcdir}/$_");
		}
	} @todelete;

	if (@todelete) {
		commit_and_refresh(
			gettext("removed obsolete PO files"));
	}
}

sub commit_and_refresh ($) {
	my $msg = shift;

	if ($config{rcs}) {
		IkiWiki::disable_commit_hook();
		IkiWiki::rcs_commit_staged(
			message => $msg,
		);
		IkiWiki::enable_commit_hook();
		IkiWiki::rcs_update();
	}
	# Reinitialize module's private variables.
	resetalreadyfiltered();
	resettranslationscache();
	flushmemoizecache();
	# Trigger a wiki refresh.
	require IkiWiki::Render;
	# without preliminary saveindex/loadindex, refresh()
	# complains about a lot of uninitialized variables
	IkiWiki::saveindex();
	IkiWiki::loadindex();
	IkiWiki::refresh();
	IkiWiki::saveindex();
}

sub po_to_markup ($$) {
	my ($page, $content) = (shift, shift);

	$content = '' unless defined $content;
	$content = decode_utf8(encode_utf8($content));
	# CRLF line terminators make poor Locale::Po4a feel bad
	$content=~s/\r\n/\n/g;

	# There are incompatibilities between some File::Temp versions
	# (including 0.18, bundled with Lenny's perl-modules package)
	# and others (e.g. 0.20, previously present in the archive as
	# a standalone package): under certain circumstances, some
	# return a relative filename, whereas others return an absolute one;
	# we here use this module in a way that is at least compatible
	# with 0.18 and 0.20. Beware, hit'n'run refactorers!
	my $infile = new File::Temp(TEMPLATE => "ikiwiki-po-filter-in.XXXXXXXXXX",
				    DIR => File::Spec->tmpdir,
				    UNLINK => 1)->filename;
	my $outfile = new File::Temp(TEMPLATE => "ikiwiki-po-filter-out.XXXXXXXXXX",
				     DIR => File::Spec->tmpdir,
				     UNLINK => 1)->filename;

	my $fail = sub ($) {
		my $msg = "po(po_to_markup) - $page : " . shift;
		error($msg, sub { unlink $infile, $outfile});
	};

	writefile(basename($infile), File::Spec->tmpdir, $content)
		or return $fail->(sprintf(gettext("failed to write %s"), $infile));

	my $masterfile = srcfile($pagesources{masterpage($page)});
	my $doc=Locale::Po4a::Chooser::new(po4a_type($masterfile),
					   po4a_options($masterfile));
	$doc->process(
		'po_in_name'	=> [ $infile ],
		'file_in_name'	=> [ $masterfile ],
		'file_in_charset'  => 'UTF-8',
		'file_out_charset' => 'UTF-8',
	) or return $fail->(gettext("failed to translate"));
	$doc->write($outfile)
		or return $fail->(sprintf(gettext("failed to write %s"), $outfile));

	$content = readfile($outfile);

	# Unlinking should happen automatically, thanks to File::Temp,
	# but it does not work here, probably because of the way writefile()
	# and Locale::Po4a::write() work.
	unlink $infile, $outfile;

	return $content;
}

# returns a SuccessReason or FailReason object
sub isvalidpo ($) {
	my $content = shift;

	# NB: we don't use po_to_markup here, since Po4a parser does
	# not mind invalid PO content
	$content = '' unless defined $content;
	$content = decode_utf8(encode_utf8($content));

	# There are incompatibilities between some File::Temp versions
	# (including 0.18, bundled with Lenny's perl-modules package)
	# and others (e.g. 0.20, previously present in the archive as
	# a standalone package): under certain circumstances, some
	# return a relative filename, whereas others return an absolute one;
	# we here use this module in a way that is at least compatible
	# with 0.18 and 0.20. Beware, hit'n'run refactorers!
	my $infile = new File::Temp(TEMPLATE => "ikiwiki-po-isvalidpo.XXXXXXXXXX",
				    DIR => File::Spec->tmpdir,
				    UNLINK => 1)->filename;

	my $fail = sub ($) {
		my $msg = '[po/isvalidpo] ' . shift;
		unlink $infile;
		return IkiWiki::FailReason->new("$msg");
	};

	writefile(basename($infile), File::Spec->tmpdir, $content)
		or return $fail->(sprintf(gettext("failed to write %s"), $infile));

	my $res = (system("msgfmt", "--check", $infile, "-o", "/dev/null") == 0);

	# Unlinking should happen automatically, thanks to File::Temp,
	# but it does not work here, probably because of the way writefile()
	# and Locale::Po4a::write() work.
	unlink $infile;

	if ($res) {
		return IkiWiki::SuccessReason->new("valid gettext data");
	}
	return IkiWiki::FailReason->new(gettext("invalid gettext data, go back ".
					"to previous page to continue edit"));
}

sub po4a_type ($) {
	my $file = shift;

	my $pagetype = pagetype($file);
	if ($pagetype eq 'html') {
		return 'xhtml';
	}
	return 'text';
}

sub po4a_options($) {
	my $file = shift;

	my %options;
	my $pagetype = pagetype($file);

	if ($pagetype eq 'html') {
		# how to disable options is not consistent across po4a modules
		$options{includessi} = '';
		$options{includeexternal} = 0;
		$options{ontagerror} = 'warn';
	}
	elsif ($pagetype eq 'mdwn') {
		$options{markdown} = 1;
	}
	else {
		$options{markdown} = 0;
	}

	return %options;
}

sub splitlangpair ($) {
	my $pair=shift;

	my ($code, $name) = ( $pair =~ /^($language_code_pattern)\|(.+)$/ );
	if (! defined $code || ! defined $name ||
	    ! length $code || ! length $name) {
		# not a fatal error to avoid breaking if used with web setup
		warn sprintf(gettext("%s has invalid syntax: must use CODE|NAME"),
			$pair);
	}

	return $code, $name;
}

sub joinlangpair ($$) {
	my $code=shift;
	my $name=shift;

	return "$code|$name";
}

# ,----
# | PageSpecs
# `----

package IkiWiki::PageSpec;

sub match_istranslation ($;@) {
	my $page=shift;

	if (IkiWiki::Plugin::po::istranslation($page)) {
		return IkiWiki::SuccessReason->new("is a translation page");
	}
	else {
		return IkiWiki::FailReason->new("is not a translation page");
	}
}

sub match_istranslatable ($;@) {
	my $page=shift;

	if (IkiWiki::Plugin::po::istranslatable($page)) {
		return IkiWiki::SuccessReason->new("is set as translatable in po_translatable_pages");
	}
	else {
		return IkiWiki::FailReason->new("is not set as translatable in po_translatable_pages");
	}
}

sub match_lang ($$;@) {
	my $page=shift;
	my $wanted=shift;

	my $regexp=IkiWiki::glob2re($wanted);
	my $lang=IkiWiki::Plugin::po::lang($page);
	if ($lang !~ $regexp) {
		return IkiWiki::FailReason->new("file language is $lang, not $wanted");
	}
	else {
		return IkiWiki::SuccessReason->new("file language is $wanted");
	}
}

sub match_currentlang ($$;@) {
	my $page=shift;
	shift;
	my %params=@_;

	return IkiWiki::FailReason->new("no location provided") unless exists $params{location};

	my $currentlang=IkiWiki::Plugin::po::lang($params{location});
	my $lang=IkiWiki::Plugin::po::lang($page);

	if ($lang eq $currentlang) {
		return IkiWiki::SuccessReason->new("file language is the same as current one, i.e. $currentlang");
	}
	else {
		return IkiWiki::FailReason->new("file language is $lang, whereas current language is $currentlang");
	}
}

sub match_needstranslation ($$;@) {
	my $page=shift;
	my $wanted=shift;

	if (defined $wanted && $wanted ne "") {
		if ($wanted !~ /^\d+$/) {
			return IkiWiki::FailReason->new("parameter is not an integer");
		}
		elsif ($wanted > 100) {
			return IkiWiki::FailReason->new("parameter is greater than 100");
		}
	}
	else {
		$wanted=100;
	}

	my $percenttranslated=IkiWiki::Plugin::po::percenttranslated($page);
	if ($percenttranslated eq 'N/A') {
		return IkiWiki::FailReason->new("file is not a translatable page");
	}
	elsif ($percenttranslated < $wanted) {
		return IkiWiki::SuccessReason->new("file has $percenttranslated translated");
	}
	else {
		return IkiWiki::FailReason->new("file is translated enough");
	}
}

1
