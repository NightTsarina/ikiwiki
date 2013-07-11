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

	eval q{use Image::Magick};
	error gettext("Image::Magick is not installed") if $@;
	my $im = Image::Magick->new($issvg ? (magick => "png") : ());
	my $imglink;
	my $r = $im->Read($srcfile);
	error sprintf(gettext("failed to read %s: %s"), $file, $r) if $r;
	
	my ($dwidth, $dheight);

	if ($params{size} ne 'full') {
		my ($w, $h) = ($params{size} =~ /^(\d*)x(\d*)$/);
		error sprintf(gettext('wrong size format "%s" (should be WxH)'), $params{size})
			unless (defined $w && defined $h &&
			        (length $w || length $h));
		
		if ((length $w && $w > $im->Get("width")) ||
		    (length $h && $h > $im->Get("height"))) {
		    	# resizing larger
			$imglink = $file;

			# don't generate larger image, just set display size
			if (length $w && length $h) {
				($dwidth, $dheight)=($w, $h);
			}
			# avoid division by zero on 0x0 image
			elsif ($im->Get("width") == 0 || $im->Get("height") == 0) {
				($dwidth, $dheight)=(0, 0);
			}
			# calculate unspecified size from the other one, preserving
			# aspect ratio
			elsif (length $w) {
				$dwidth=$w;
				$dheight=$w / $im->Get("width") * $im->Get("height");
			}
			elsif (length $h) {
				$dheight=$h;
				$dwidth=$h / $im->Get("height") * $im->Get("width");
			}
		}
		else {
			# resizing smaller
			my $outfile = "$config{destdir}/$dir/${w}x${h}-$base";
			$imglink = "$dir/${w}x${h}-$base";
		
			will_render($params{page}, $imglink);

			if (-e $outfile && (-M $srcfile >= -M $outfile)) {
				$im = Image::Magick->new;
				$r = $im->Read($outfile);
				error sprintf(gettext("failed to read %s: %s"), $outfile, $r) if $r;
			}
			else {
				$r = $im->Resize(geometry => "${w}x${h}");
				error sprintf(gettext("failed to resize: %s"), $r) if $r;

				# don't actually write resized file in preview mode;
				# rely on width and height settings
				if (! $params{preview}) {
					my @blob = $im->ImageToBlob();
					writefile($imglink, $config{destdir}, $blob[0], 1);
				}
				else {
					$imglink = $file;
				}
			}

			# always get the true size of the resized image
			$dwidth  = $im->Get("width"); 
			$dheight = $im->Get("height");
		}
	}
	else {
		$imglink = $file;
		$dwidth = $im->Get("width");
		$dheight = $im->Get("height");
	}
	
	if (! defined($dwidth) || ! defined($dheight)) {
		error sprintf(gettext("failed to determine size of image %s"), $file)
	}

	my ($fileurl, $imgurl);
	if (! $params{preview}) {
		$fileurl=urlto($file, $params{destpage});
		$imgurl=urlto($imglink, $params{destpage});
	}
	else {
		$fileurl=urlto($file);
		$imgurl=urlto($imglink);
	}

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
