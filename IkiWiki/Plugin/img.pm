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
		img_allowed_formats => {
			type => "string",
			default => [qw(jpeg png gif svg)],
			description => "Image formats to process (jpeg, png, gif, svg, pdf or 'everything' to accept all)",
			# ImageMagick has had arbitrary code execution flaws,
			# and the whole delegates mechanism is scary from
			# that perspective
			safe => 0,
			rebuild => 0,
		},
}

sub allowed {
	my $format = shift;
	my $allowed = $config{img_allowed_formats};
	$allowed = ['jpeg', 'png', 'gif', 'svg'] unless defined $allowed && @$allowed;

	foreach my $a (@$allowed) {
		return 1 if lc($a) eq $format || lc($a) eq 'everything';
	}

	return 0;
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
	my $extension;
	my $format;

	if ($base =~ m/\.([a-z0-9]+)$/is) {
		$extension = $1;
	}
	else {
		error gettext("Unable to detect image type from extension");
	}

	# Never interpret well-known file extensions as any other format,
	# in case the wiki configuration unwisely allows attaching
	# arbitrary files named *.jpg, etc.
	my $magic;
	my $offset = 0;
	open(my $in, '<', $srcfile) or error sprintf(gettext("failed to read %s: %s"), $file, $!);
	binmode($in);

	if ($extension =~ m/^(jpeg|jpg)$/is) {
		$format = 'jpeg';
		$magic = "\377\330\377";
	}
	elsif ($extension =~ m/^(png)$/is) {
		$format = 'png';
		$magic = "\211PNG\r\n\032\n";
	}
	elsif ($extension =~ m/^(gif)$/is) {
		$format = 'gif';
		$magic = "GIF8";
	}
	elsif ($extension =~ m/^(svg)$/is) {
		$format = 'svg';
	}
	elsif ($extension =~ m/^(pdf)$/is) {
		$format = 'pdf';
		$magic = "%PDF-";
	}
	else {
		# allow ImageMagick to auto-detect (potentially dangerous)
		my $im = Image::Magick->new();
		my $r = $im->Ping(file => $in);
		if ($r) {
			$format = lc $r;
		}
		else {
			error sprintf(gettext("failed to determine format of %s"), $file);
		}
	}

	error sprintf(gettext("%s image processing disabled in img_allowed_formats configuration"), $format ? $format : "\"$extension\"") unless allowed($format ? $format : "everything");

	# Try harder to protect ImageMagick from itself
	if (defined $magic) {
		my $content;
		read($in, $content, length $magic) or error sprintf(gettext("failed to read %s: %s"), $file, $!);
		if ($magic ne $content) {
			error sprintf(gettext("\"%s\" does not seem to be a valid %s file"), $file, $format);
		}
	}

	my $ispdf = $base=~s/\.pdf$/.png/i;
	my $pagenumber = exists($params{pagenumber}) ? int($params{pagenumber}) : 0;
	if ($pagenumber != 0) {
		$base = "p$pagenumber-$base";
	}

	my $imglink;
	my $imgdatalink;
	my ($dwidth, $dheight);

	my ($w, $h);
	if ($params{size} ne 'full') {
		($w, $h) = ($params{size} =~ /^(\d*)x(\d*)$/);
	}

	if ($format eq 'svg') {
		# svg images are not scaled using ImageMagick because the
		# pipeline is complex. Instead, the image size is simply
		# set to the provided values.
		#
		# Aspect ratio will be preserved automatically when
		# only a width or only a height is specified.
		# When both are specified, aspect ratio will not be
		# preserved.
		$imglink = $file;
		$dwidth = $w if length $w;
		$dheight = $h if length $h;
	}
	else {
		eval q{use Image::Magick};
		error gettext("Image::Magick is not installed") if $@;
		my $im = Image::Magick->new();
		my $r = $im->Read("$format:$srcfile\[$pagenumber]");
		error sprintf(gettext("failed to read %s: %s"), $file, $r) if $r;

		if ($config{deterministic}) {
			$im->Set('date:create' => 0);
			$im->Set('date:modify' => 0);
			$im->Set('option'      => 'png:exclude-chunk=time');
		}

		if (! defined $im->Get("width") || ! defined $im->Get("height")) {
			error sprintf(gettext("failed to get dimensions of %s"), $file);
		}

		if (! length $w && ! length $h) {
			$dwidth = $im->Get("width");
			$dheight = $im->Get("height");
		} else {
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

				$im->set($ispdf ? (magick => 'png') : ());
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
	
	my $imgtag='<img src="'.$imgurl.'"';
	$imgtag.=' width="'.$dwidth.'"' if defined $dwidth;
	$imgtag.=' height="'.$dheight.'"' if defined $dheight;
	$imgtag.= $attrs.
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
