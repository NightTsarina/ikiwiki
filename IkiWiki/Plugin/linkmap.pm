#!/usr/bin/perl
package IkiWiki::Plugin::linkmap;

use warnings;
use strict;
use IkiWiki 3.00;
use IPC::Open2;

sub import {
	hook(type => "getsetup", id => "linkmap", call => \&getsetup);
	hook(type => "preprocess", id => "linkmap", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

my $mapnum=0;

sub preprocess (@) {
	my %params=@_;

	$params{pages}="*" unless defined $params{pages};
	
	$mapnum++;
	my $connected=IkiWiki::yesno($params{connected});

	# Get all the items to map.
	my %mapitems = map { $_ => urlto($_, $params{destpage}) }
		pagespec_match_list($params{page}, $params{pages},
			# update when a page is added or removed, or its
			# links change
			deptype => deptype("presence", "links"));

	my $dest=$params{page}."/linkmap.png";

	# Use ikiwiki's function to create the file, this makes sure needed
	# subdirs are there and does some sanity checking.
	will_render($params{page}, $dest);
	writefile($dest, $config{destdir}, "");

	# Run dot to create the graphic and get the map data.
	my $pid;
	my $sigpipe=0;
	$SIG{PIPE}=sub { $sigpipe=1 };
	$pid=open2(*IN, *OUT, "dot -Tpng -o '$config{destdir}/$dest' -Tcmapx");
	
	# open2 doesn't respect "use open ':utf8'"
	binmode (IN, ':utf8'); 
	binmode (OUT, ':utf8'); 

	print OUT "digraph linkmap$mapnum {\n";
	print OUT "concentrate=true;\n";
	print OUT "charset=\"utf-8\";\n";
	print OUT "ratio=compress;\nsize=\"".($params{width}+0).", ".($params{height}+0)."\";\n"
		if defined $params{width} and defined $params{height};
	my %shown;
	my $show=sub {
		my $item=shift;
		if (! $shown{$item}) {
			print OUT "\"$item\" [shape=box,href=\"$mapitems{$item}\"];\n";
			$shown{$item}=1;
		}
	};
	foreach my $item (keys %mapitems) {
		$show->($item) unless $connected;
		foreach my $link (map { bestlink($item, $_) } @{$links{$item}}) {
			next unless length $link and $mapitems{$link};
			foreach my $endpoint ($item, $link) {
				$show->($endpoint);
			}
			print OUT "\"$item\" -> \"$link\";\n";
		}
	}
	print OUT "}\n";
	close OUT || error gettext("failed to run dot");

	local $/=undef;
	my $ret="<img src=\"".urlto($dest, $params{destpage}).
	       "\" alt=\"".gettext("linkmap").
	       "\" usemap=\"#linkmap$mapnum\" />\n".
	        <IN>;
	close IN || error gettext("failed to run dot");
	
	waitpid $pid, 0;
	if ($?) {
		error gettext("failed to run dot");
	}
	$SIG{PIPE}="DEFAULT";
	error gettext("failed to run dot") if $sigpipe;

	return $ret;
}

1
