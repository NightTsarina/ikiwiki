#!/usr/bin/perl
# graphviz plugin for ikiwiki: render graphviz source as an image.
# Josh Triplett
package IkiWiki::Plugin::graphviz;

use warnings;
use strict;
use IkiWiki 3.00;
use IPC::Open2;

sub import {
	hook(type => "getsetup", id => "graphviz", call => \&getsetup);
	hook(type => "preprocess", id => "graph", call => \&graph);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

my %graphviz_programs = (
	"dot" => 1, "neato" => 1, "fdp" => 1, "twopi" => 1, "circo" => 1
);

my $graphnum=0;

sub render_graph (\%) {
	my %params = %{(shift)};

	$graphnum++;
	my $src = "$params{type} graph$graphnum {\n";
	$src .= "charset=\"utf-8\";\n";
	$src .= "ratio=compress;\nsize=\"".($params{width}+0).", ".($params{height}+0)."\";\n"
		if defined $params{width} and defined $params{height};
	$src .= $params{src};
	$src .= "}\n";

	# Use the sha1 of the graphviz code as part of its filename.
	eval q{use Digest::SHA};
	error($@) if $@;
	my $base=$params{page}."/graph-".
		IkiWiki::possibly_foolish_untaint(Digest::SHA::sha1_hex($src));
	my $dest=$base.".png";
	will_render($params{page}, $dest);

	# The imagemap data is stored as a separate file.
	my $imagemap=$base.".imagemap";
	will_render($params{page}, $imagemap);
	
	my $map;
	if (! -e "$config{destdir}/$dest" || ! -e "$config{destdir}/$imagemap") {
		# Use ikiwiki's function to create the image file, this makes
		# sure needed subdirs are there and does some sanity checking.
		writefile($dest, $config{destdir}, "");
		
		my $pid;
		my $sigpipe=0;
		$SIG{PIPE}=sub { $sigpipe=1 };
		$pid=open2(*IN, *OUT, "$params{prog} -Tpng -o '$config{destdir}/$dest' -Tcmapx");

		# open2 doesn't respect "use open ':utf8'"
		binmode (IN, ':utf8');
		binmode (OUT, ':utf8');

		print OUT $src;
		close OUT;

		local $/ = undef;
		$map=<IN>;
		close IN;
		writefile($imagemap, $config{destdir}, $map);

		waitpid $pid, 0;
		$SIG{PIPE}="DEFAULT";
		error gettext("failed to run graphviz") if ($sigpipe || $?);

	}
	else {
		$map=readfile("$config{destdir}/$imagemap");
	}

	return "<img src=\"".urlto($dest, $params{destpage}).
		"\" usemap=\"#graph$graphnum\" />\n".
		$map;
}

sub graph (@) {
	my %params=@_;
	$params{src} = "" unless defined $params{src};
	$params{type} = "digraph" unless defined $params{type};
	$params{prog} = "dot" unless defined $params{prog};
	error gettext("prog not a valid graphviz program") unless $graphviz_programs{$params{prog}};

	return render_graph(%params);
}

1
