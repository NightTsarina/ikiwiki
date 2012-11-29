#!/usr/bin/perl
# Ikiwiki metadata plugin.
package IkiWiki::Plugin::meta;

use warnings;
use strict;
use IkiWiki 3.00;

my %metaheaders;

sub import {
	hook(type => "getsetup", id => "meta", call => \&getsetup);
	hook(type => "needsbuild", id => "meta", call => \&needsbuild);
	hook(type => "preprocess", id => "meta", call => \&preprocess, scan => 1);
	hook(type => "pagetemplate", id => "meta", call => \&pagetemplate);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "core",
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;
	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{meta}) {
			if (exists $pagesources{$page} &&
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild
				delete $pagestate{$page}{meta};
			}
		}
	}
	return $needsbuild;
}

sub scrub ($$$) {
	if (IkiWiki::Plugin::htmlscrubber->can("sanitize")) {
		return IkiWiki::Plugin::htmlscrubber::sanitize(
			content => shift, page => shift, destpage => shift);
	}
	else {
		return shift;
	}
}

sub safeurl ($) {
	my $url=shift;
	if (exists $IkiWiki::Plugin::htmlscrubber::{safe_url_regexp} &&
	    defined $IkiWiki::Plugin::htmlscrubber::safe_url_regexp) {
		return $url=~/$IkiWiki::Plugin::htmlscrubber::safe_url_regexp/;
	}
	else {
		return 1;
	}
}

sub htmlize ($$$) {
	my $page = shift;
	my $destpage = shift;

	return IkiWiki::htmlize($page, $destpage, pagetype($pagesources{$page}),
		IkiWiki::linkify($page, $destpage,
		IkiWiki::preprocess($page, $destpage, shift)));
}

sub preprocess (@) {
	return "" unless @_;
	my %params=@_;
	my $key=shift;
	my $value=$params{$key};
	delete $params{$key};
	my $page=$params{page};
	delete $params{page};
	my $destpage=$params{destpage};
	delete $params{destpage};
	delete $params{preview};

	eval q{use HTML::Entities};
	# Always decode, even if encoding later, since it might not be
	# fully encoded.
	$value=decode_entities($value);

	# Metadata collection that needs to happen during the scan pass.
	if ($key eq 'title') {
		$pagestate{$page}{meta}{title}=$value;
		if (exists $params{sortas}) {
			$pagestate{$page}{meta}{titlesort}=$params{sortas};
		}
		else {
			delete $pagestate{$page}{meta}{titlesort};
		}
		return "";
	}
	elsif ($key eq 'description') {
		$pagestate{$page}{meta}{description}=$value;
		# fallthrough
	}
	elsif ($key eq 'guid') {
		$pagestate{$page}{meta}{guid}=$value;
		# fallthrough
	}
	elsif ($key eq 'license') {
		push @{$metaheaders{$page}}, '<link rel="license" href="#page_license" />';
		$pagestate{$page}{meta}{license}=$value;
		return "";
	}
	elsif ($key eq 'copyright') {
		push @{$metaheaders{$page}}, '<link rel="copyright" href="#page_copyright" />';
		$pagestate{$page}{meta}{copyright}=$value;
		return "";
	}
	elsif ($key eq 'link' && ! %params) {
		# hidden WikiLink
		add_link($page, $value);
		return "";
	}
	elsif ($key eq 'author') {
		$pagestate{$page}{meta}{author}=$value;
		if (exists $params{sortas}) {
			$pagestate{$page}{meta}{authorsort}=$params{sortas};
		}
		else {
			delete $pagestate{$page}{meta}{authorsort};
		}
		# fallthorough
	}
	elsif ($key eq 'authorurl') {
		$pagestate{$page}{meta}{authorurl}=$value if safeurl($value);
		# fallthrough
	}
	elsif ($key eq 'permalink') {
		$pagestate{$page}{meta}{permalink}=$value if safeurl($value);
		# fallthrough
	}
	elsif ($key eq 'date') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$IkiWiki::pagectime{$page}=$time if defined $time;
		}
	}
	elsif ($key eq 'updated') {
		eval q{use Date::Parse};
		if (! $@) {
			my $time = str2time($value);
			$pagestate{$page}{meta}{updated}=$time if defined $time;
		}
	}

	if (! defined wantarray) {
		# avoid collecting duplicate data during scan pass
		return;
	}

	# Metadata handling that happens only during preprocessing pass.
	if ($key eq 'permalink') {
		if (safeurl($value)) {
			push @{$metaheaders{$page}}, scrub('<link rel="bookmark" href="'.encode_entities($value).'" />', $page, $destpage);
		}
	}
	elsif ($key eq 'stylesheet') {
		my $rel=exists $params{rel} ? $params{rel} : "alternate stylesheet";
		my $title=exists $params{title} ? $params{title} : $value;
		# adding .css to the value prevents using any old web
		# editable page as a stylesheet
		my $stylesheet=bestlink($page, $value.".css");
		if (! length $stylesheet) {
			error gettext("stylesheet not found")
		}
		push @{$metaheaders{$page}}, scrub('<link href="'.urlto($stylesheet, $page).
			'" rel="'.encode_entities($rel).
			'" title="'.encode_entities($title).
			"\" type=\"text/css\" />", $page, $destpage);
	}
	elsif ($key eq 'script') {
		my $defer=exists $params{defer} ? ' defer="defer"' : '';
		my $async=exists $params{async} ? ' async="async"' : '';
		my $js=bestlink($page, $value.".js");
		if (! length $js) {
			error gettext("script not found");
		}
		push @{$metaheaders{$page}}, scrub('<script src="'.urlto($js, $page).
			'"' . $defer . $async . ' type="text/javascript"></script>',
			$page, $destpage);
	}
	elsif ($key eq 'openid') {
		my $delegate=0; # both by default
		if (exists $params{delegate}) {
			$delegate = 1 if lc $params{delegate} eq 'openid';
			$delegate = 2 if lc $params{delegate} eq 'openid2';
		}
		if (exists $params{server} && safeurl($params{server})) {
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($params{server}).
				'" rel="openid.server" />' if $delegate ne 2;
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($params{server}).
				'" rel="openid2.provider" />' if $delegate ne 1;
		}
		if (safeurl($value)) {
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($value).
				'" rel="openid.delegate" />' if $delegate ne 2;
			push @{$metaheaders{$page}}, '<link href="'.encode_entities($value).
				'" rel="openid2.local_id" />' if $delegate ne 1;
		}
		if (exists $params{"xrds-location"} && safeurl($params{"xrds-location"})) {
			# force url absolute
			eval q{use URI};
			error($@) if $@;
			my $url=URI->new_abs($params{"xrds-location"}, $config{url});
			push @{$metaheaders{$page}}, '<meta http-equiv="X-XRDS-Location" '.
				'content="'.encode_entities($url).'" />';
		}
	}
	elsif ($key eq 'foaf') {
		if (safeurl($value)) {
			push @{$metaheaders{$page}}, '<link rel="meta" '.
				'type="application/rdf+xml" title="FOAF" '.
				'href="'.encode_entities($value).'" />';
		}
	}
	elsif ($key eq 'redir') {
		return "" if $page ne $destpage;
		my $safe=0;
		if ($value !~ /^\w+:\/\//) {
			my ($redir_page, $redir_anchor) = split /\#/, $value;

			my $link=bestlink($page, $redir_page);
			if (! length $link) {
				error gettext("redir page not found")
			}
			add_depends($page, $link, deptype("presence"));

			$value=urlto($link, $page);
			$value.='#'.$redir_anchor if defined $redir_anchor;
			$safe=1;

			# redir cycle detection
			$pagestate{$page}{meta}{redir}=$link;
			my $at=$page;
			my %seen;
			while (exists $pagestate{$at}{meta}{redir}) {
				if ($seen{$at}) {
					error gettext("redir cycle is not allowed")
				}
				$seen{$at}=1;
				$at=$pagestate{$at}{meta}{redir};
			}
		}
		else {
			$value=encode_entities($value);
		}
		my $delay=int(exists $params{delay} ? $params{delay} : 0);
		my $redir="<meta http-equiv=\"refresh\" content=\"$delay; URL=$value\" />";
		if (! $safe) {
			$redir=scrub($redir, $page, $destpage);
		}
		push @{$metaheaders{$page}}, $redir;
	}
	elsif ($key eq 'link') {
		if (%params) {
			push @{$metaheaders{$page}}, scrub("<link href=\"".encode_entities($value)."\" ".
				join(" ", map {
					encode_entities($_)."=\"".encode_entities(decode_entities($params{$_}))."\""
				} keys %params).
				" />\n", $page, $destpage);
		}
	}
	elsif ($key eq 'robots') {
		push @{$metaheaders{$page}}, '<meta name="robots"'.
			' content="'.encode_entities($value).'" />';
	}
	elsif ($key eq 'description' || $key eq 'author') {
		push @{$metaheaders{$page}}, '<meta name="'.$key.
			'" content="'.encode_entities($value).'" />';
	}
	elsif ($key eq 'name') {
		push @{$metaheaders{$page}}, scrub('<meta name="'.
			encode_entities($value).
			join(' ', map { "$_=\"$params{$_}\"" } keys %params).
			' />', $page, $destpage);
	}
	elsif ($key eq 'keywords') {
		# Make sure the keyword string is safe: only allow alphanumeric
		# characters, space and comma and strip the rest.
		$value =~ s/[^[:alnum:], ]+//g;
		push @{$metaheaders{$page}}, '<meta name="keywords"'.
			' content="'.encode_entities($value).'" />';
	}
	else {
		push @{$metaheaders{$page}}, scrub('<meta name="'.
			encode_entities($key).'" content="'.
			encode_entities($value).'" />', $page, $destpage);
	}

	return "";
}

sub pagetemplate (@) {
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (exists $metaheaders{$page} && $template->query(name => "meta")) {
		# avoid duplicate meta lines
		my %seen;
		$template->param(meta => join("\n", grep { (! $seen{$_}) && ($seen{$_}=1) } @{$metaheaders{$page}}));
	}
	if (exists $pagestate{$page}{meta}{title} && $template->query(name => "title")) {
		eval q{use HTML::Entities};
		$template->param(title => HTML::Entities::encode_numeric($pagestate{$page}{meta}{title}));
		$template->param(title_overridden => 1);
	}

	foreach my $field (qw{authorurl}) {
		eval q{use HTML::Entities};
		$template->param($field => HTML::Entities::encode_entities($pagestate{$page}{meta}{$field}))
			if exists $pagestate{$page}{meta}{$field} && $template->query(name => $field);
	}

	foreach my $field (qw{permalink}) {
		if (exists $pagestate{$page}{meta}{$field} && $template->query(name => $field)) {
			eval q{use HTML::Entities};
			$template->param($field => HTML::Entities::encode_entities(IkiWiki::urlabs($pagestate{$page}{meta}{$field}, $config{url})));
		}
	}

	foreach my $field (qw{description author}) {
		eval q{use HTML::Entities};
		$template->param($field => HTML::Entities::encode_numeric($pagestate{$page}{meta}{$field}))
			if exists $pagestate{$page}{meta}{$field} && $template->query(name => $field);
	}

	foreach my $field (qw{license copyright}) {
		if (exists $pagestate{$page}{meta}{$field} && $template->query(name => $field) &&
		    ($page eq $destpage || ! exists $pagestate{$destpage}{meta}{$field} ||
		     $pagestate{$page}{meta}{$field} ne $pagestate{$destpage}{meta}{$field})) {
			$template->param($field => htmlize($page, $destpage, $pagestate{$page}{meta}{$field}));
		}
	}
}

sub get_sort_key {
	my $page = shift;
	my $meta = shift;

	# e.g. titlesort (also makes sense for author)
	my $key = $pagestate{$page}{meta}{$meta . "sort"};
	return $key if defined $key;

	# e.g. title
	$key = $pagestate{$page}{meta}{$meta};
	return $key if defined $key;

	# fall back to closer-to-core things
	if ($meta eq 'title') {
		return pagetitle(IkiWiki::basename($page));
	}
	elsif ($meta eq 'date') {
		return $IkiWiki::pagectime{$page};
	}
	elsif ($meta eq 'updated') {
		return $IkiWiki::pagemtime{$page};
	}
	else {
		return '';
	}
}

sub match {
	my $field=shift;
	my $page=shift;
	
	# turn glob into a safe regexp
	my $re=IkiWiki::glob2re(shift);

	my $val;
	if (exists $pagestate{$page}{meta}{$field}) {
		$val=$pagestate{$page}{meta}{$field};
	}
	elsif ($field eq 'title') {
		$val = pagetitle($page);
	}

	if (defined $val) {
		if ($val=~$re) {
			return IkiWiki::SuccessReason->new("$re matches $field of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
		}
		else {
			return IkiWiki::FailReason->new("$re does not match $field of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
		}
	}
	else {
		return IkiWiki::FailReason->new("$page does not have a $field", $page => $IkiWiki::DEPEND_CONTENT);
	}
}

package IkiWiki::PageSpec;

sub match_title ($$;@) {
	IkiWiki::Plugin::meta::match("title", @_);
}

sub match_author ($$;@) {
	IkiWiki::Plugin::meta::match("author", @_);
}

sub match_authorurl ($$;@) {
	IkiWiki::Plugin::meta::match("authorurl", @_);
}

sub match_license ($$;@) {
	IkiWiki::Plugin::meta::match("license", @_);
}

sub match_copyright ($$;@) {
	IkiWiki::Plugin::meta::match("copyright", @_);
}

sub match_guid ($$;@) {
	IkiWiki::Plugin::meta::match("guid", @_);
}

package IkiWiki::SortSpec;

sub cmp_meta {
	my $meta = shift;
	error(gettext("sort=meta requires a parameter")) unless defined $meta;

	if ($meta eq 'updated' || $meta eq 'date') {
		return IkiWiki::Plugin::meta::get_sort_key($a, $meta)
			<=>
			IkiWiki::Plugin::meta::get_sort_key($b, $meta);
	}

	return IkiWiki::Plugin::meta::get_sort_key($a, $meta)
		cmp
		IkiWiki::Plugin::meta::get_sort_key($b, $meta);
}

# A prototype of how sort=title could behave in 4.0 or something
sub cmp_meta_title {
	$_[0] = 'title';
	return cmp_meta(@_);
}

1
