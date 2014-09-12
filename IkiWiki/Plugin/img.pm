#!/usr/bin/perl
# Ikiwiki enhanced image handling plugin
# Christian Mock cm@tahina.priv.at 20061002
package IkiWiki::Plugin::img;

use warnings;
use strict;
use IkiWiki 3.00;

my %imgdefaults;

sub import {
	hook(type => "getsetup", id => "img", call => \&getsetup);
	hook(type => "preprocess", id => "img", call => \&preprocess, scan => 1);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preprocess (@) {
	my ($image) = $_[0] =~ /$config{wiki_file_regexp}/; # untaint
	my %params=@_;

	if (! defined $image) {
		error("bad image filename");
	}

	if (exists $imgdefaults{$params{page}}) {
		foreach my $key (keys %{$imgdefaults{$params{page}}}) {
			if (! exists $params{$key}) {
				$params{$key}=$imgdefaults{$params{page}}->{$key};
			}
		}
	}

	if (! exists $params{size} || ! length $params{size}) {
		$params{size}='full';
	}

	if ($image eq 'defaults') {
		$imgdefaults{$params{page}} = \%params;
		return '';
	}

	add_link($params{page}, $image);
	add_depends($params{page}, $image);

	# optimisation: detect scan mode, and avoid generating the image
	if (! defined wantarray) {
		return;
	}

	my $file = bestlink($params{page}, $image);
	my $srcfile = srcfile($file, 1);
	if (! length $file || ! defined $srcfile) {
		return htmllink($params{page}, $params{destpage}, $image);
	}

	my $dir = $params{page};
	my $base = IkiWiki::basename($file);
	my $issvg = $base=~s/\.svg$/.png/i;
	my $ispdf = $base=~s/\.pdf$/.png/i;
	my $pagenumber = exists($params{pagenumber}) ? int($params{pagenumber}) : 0;
	if ($pagenumber != 0) {
		$base = "p$pagenumber-$base";
	}

	eval q{use Image::Magick};
	error gettext("Image::Magick is not installed") if $@;
	my $im = Image::Magick->new();
	my $imglink;
	my $imgdatalink;
	my $r = $im->Read("$srcfile\[$pagenumber]");
	error sprintf(gettext("failed to read %s: %s"), $file, $r) if $r;

	if (! defined $im->Get("width") || ! defined $im->Get("height")) {
		error sprintf(gettext("failed to get dimensions of %s"), $file);
	}

	my ($dwidth, $dheight);

	if ($params{size} eq 'full') {
		$dwidth = $im->Get("width");
		$dheight = $im->Get("height");
	} else {
		my ($w, $h) = ($params{size} =~ /^(\d*)x(\d*)$/);
		error sprintf(gettext('wrong size format "%s" (should be WxH)'), $params{size})
			unless (defined $w && defined $h &&
			        (length $w || length $h));

		if ($im->Get("width") == 0 || $im->Get("height") == 0) {
			($dwidth, $dheight)=(0, 0);
		} elsif (! length $w || (length $h && $im->Get("height")*$w > $h * $im->Get("width"))) {
			# using height because only height is given or ...
			# because original image is more portrait than $w/$h
			# ... slimness of $im > $h/w
			# ... $im->Get("height")/$im->Get("width") > $h/$w
			# ... $im->Get("height")*$w > $h * $im->Get("width")

			$dheight=$h;
			$dwidth=$h / $im->Get("height") * $im->Get("width");
		} else { # (! length $h) or $w is what determines the resized size
			$dwidth=$w;
			$dheight=$w / $im->Get("width") * $im->Get("height");
		}
	}

	if ($dwidth < $im->Get("width") || $ispdf) {
		# resize down, or resize to pixels at all

		my $outfile = "$config{destdir}/$dir/$params{size}-$base";
		$imglink = "$dir/$params{size}-$base";

		will_render($params{page}, $imglink);

		if (-e $outfile && (-M $srcfile >= -M $outfile)) {
			$im = Image::Magick->new;
			$r = $im->Read($outfile);
			error sprintf(gettext("failed to read %s: %s"), $outfile, $r) if $r;
		}
		else {
			$r = $im->Resize(geometry => "${dwidth}x${dheight}");
			error sprintf(gettext("failed to resize: %s"), $r) if $r;

			$im->set(($issvg || $ispdf) ? (magick => 'png') : ());
			my @blob = $im->ImageToBlob();
			# don't actually write resized file in preview mode;
			# rely on width and height settings
			if (! $params{preview}) {
				writefile($imglink, $config{destdir}, $blob[0], 1);
			}
			else {
				eval q{use MIME::Base64};
				error($@) if $@;
				$imgdatalink = "data:image/".$im->Get("magick").";base64,".encode_base64($blob[0]);
			}
		}

		# always get the true size of the resized image (it could be
		# that imagemagick did its calculations differently)
		$dwidth  = $im->Get("width");
		$dheight = $im->Get("height");
	} else {
		$imglink = $file;
	}
	
	if (! defined($dwidth) || ! defined($dheight)) {
		error sprintf(gettext("failed to determine size of image %s"), $file)
	}

	my ($fileurl, $imgurl);
	my $urltobase = $params{preview} ? undef : $params{destpage};
	$fileurl=urlto($file, $urltobase);
	$imgurl=$imgdatalink ? $imgdatalink : urlto($imglink, $urltobase);

	if (! exists $params{class}) {
		$params{class}="img";
	}

	my $attrs='';
	foreach my $attr (qw{alt title class id hspace vspace}) {
		if (exists $params{$attr}) {
			$attrs.=" $attr=\"$params{$attr}\"";
		}
	}
	
	my $imgtag='<img src="'.$imgurl.
		'" width="'.$dwidth.
		'" height="'.$dheight.'"'.
		$attrs.
		(exists $params{align} && ! exists $params{caption} ? ' align="'.$params{align}.'"' : '').
		' />';

	my $link;
	if (! defined $params{link}) {
		$link=$fileurl;
	}
	elsif ($params{link} =~ /^\w+:\/\//) {
		$link=$params{link};
	}

	if (defined $link) {
		$imgtag='<a href="'.$link.'">'.$imgtag.'</a>';
	}
	else {
		my $b = bestlink($params{page}, $params{link});
	
		if (length $b) {
			add_depends($params{page}, $b, deptype("presence"));
			$imgtag=htmllink($params{page}, $params{destpage},
				$params{link}, linktext => $imgtag,
				noimageinline => 1,
			);
		}
	}

	if (exists $params{caption}) {
		return '<table class="img'.
			(exists $params{align} ? " align-$params{align}" : "").
			'">'.
			'<caption>'.$params{caption}.'</caption>'.
			'<tr><td>'.$imgtag.'</td></tr>'.
			'</table>';
	}
	else {
		return $imgtag;
	}
}

1
