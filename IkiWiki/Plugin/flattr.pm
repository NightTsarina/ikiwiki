#!/usr/bin/perl
package IkiWiki::Plugin::flattr;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "flattr", call => \&getsetup);
	hook(type => "preprocess", id => "flattr", call => \&preprocess);
	hook(type => "format", id => "flattr", call => \&format);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		flattr_userid => {
			type => "string",
			example => 'joeyh',
			description => "userid or user name to use by default for Flattr buttons",
			advanced => 0,
			safe => 1,
			rebuild => undef,
		},
}

my %flattr_pages;

sub preprocess (@) {
	my %params=@_;

	$flattr_pages{$params{destpage}}=1;

	my $url=$params{url};
	if (! defined $url) {
		$url=urlto($params{page}, "", 1);
	}

	my @fields;
	foreach my $field (qw{language uid button hidden category tags}) {
		if (exists $params{$field}) {
			push @fields, "$field:$params{$field}";
		}
	}
	
	return '<a class="FlattrButton" href="'.$url.'"'.
       		(exists $params{title} ? ' title="'.$params{title}.'"' : '').
		' rev="flattr;'.join(';', @fields).';"'.
		'>'.
		(exists $params{description} ? $params{description} : '').
		'</a>';
}

sub format (@) {
	my %params=@_;

	# Add flattr's javascript to pages with flattr buttons.
	if ($flattr_pages{$params{page}}) {
		if (! ($params{content}=~s!^(<body[^>]*>)!$1.flattrjs()!em)) {
			# no <body> tag, probably in preview mode
			$params{content}=flattrjs().$params{content};
		}
	}
	return $params{content};
}

my $js_cached;
sub flattrjs {
	return $js_cached if defined $js_cached;

	my $js_url='https://api.flattr.com/js/0.5.0/load.js?mode=auto';
	if (defined $config{flattr_userid}) {
		my $userid=$config{flattr_userid};
		$userid=~s/[^-A-Za-z0-9_]//g; # sanitize for inclusion in javascript
		$js_url.="&uid=$userid";
	}

	# This is Flattr's standard javascript snippet to include their
	# external javascript file, asynchronously.
	return $js_cached=<<"EOF";
<script type="text/javascript">
<!--//--><![CDATA[//><!--
(function() {
	var s = document.createElement('script'), t = document.getElementsByTagName('script')[0];
	s.type = 'text/javascript';
	s.async = true;
	s.src = '$js_url';
	t.parentNode.insertBefore(s, t);
})();//--><!]]>
</script>
EOF
}

1
