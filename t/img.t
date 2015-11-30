#!/usr/bin/perl
#
# unit test that creates test images (png, svg, multi-page pdf), runs ikiwiki
# on them, checks the resulting images for plausibility based on their image
# sizes, and checks if they vanish when not required in the build process any
# more
#
# if you have trouble here, be aware that there are three debian packages that
# can provide Image::Magick: perlmagick, libimage-magick-perl and
# graphicsmagick-libmagick-dev-compat
#
package IkiWiki;

use warnings;
use strict;
use Test::More;
plan(skip_all => "Image::Magick not available")
	unless eval q{use Image::Magick};

use IkiWiki;

my $installed = $ENV{INSTALLED_TESTS};

my @command;
if ($installed) {
	@command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = qw(perl -I. ./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates);
}

push @command, qw(--set usedirs=0 --plugin img t/tmp/in t/tmp/out --verbose);

my $magick = new Image::Magick;
my $SVGS_WORK = defined $magick->QueryFormat("svg");

ok(! system("rm -rf t/tmp; mkdir -p t/tmp/in"));

ok(! system("cp t/img/redsquare.png t/tmp/in/redsquare.png"));
# colons in filenames are a corner case for img
ok(! system("cp t/img/redsquare.png t/tmp/in/hello:world.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c:d.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c:d:e:f:g:h:i:j.png"));

if ($SVGS_WORK) {
	writefile("emptysquare.svg", "t/tmp/in",
		'<svg width="30" height="30"><rect x="0" y="0" width="30" height="30" fill="blue"/></svg>');
}

# using different image sizes for different pages, so the pagenumber selection can be tested easily
ok(! system("cp t/img/twopages.pdf t/tmp/in/twopages.pdf"));

my $maybe_svg_img = "";
if ($SVGS_WORK) {
	$maybe_svg_img = "[[!img emptysquare.svg size=10x]]";
}

writefile("imgconversions.mdwn", "t/tmp/in", <<EOF
[[!img redsquare.png]]
[[!img redsquare.png size=10x]]
[[!img redsquare.png size=30x50]] expecting 30x30
[[!img hello:world.png size=x8]] expecting 8x8
[[!img a:b:c.png size=x4]]
[[!img a:b:c:d:e:f:g:h:i:j.png size=x6]]
$maybe_svg_img
[[!img twopages.pdf size=12x]]
[[!img twopages.pdf size=16x pagenumber=1]]
EOF
);
ok(utime(333333333, 333333333, "t/tmp/in/imgconversions.mdwn"));

ok(! system(@command));

sub size($) {
	my $filename = shift;
	my $im = Image::Magick->new();
	my $r = $im->Read(":$filename");
	return "no image" if $r;
	my $w = $im->Get("width");
	my $h = $im->Get("height");
	return "${w}x${h}";
}

my $outpath = "t/tmp/out/imgconversions";
my $outhtml = readfile("$outpath.html");

is(size("$outpath/10x-redsquare.png"), "10x10");
ok(! -e "$outpath/30x-redsquare.png");
ok($outhtml =~ /width="30" height="30".*expecting 30x30/);

if ($SVGS_WORK) {
	# if this fails, you need libmagickcore-6.q16-2-extra installed
	is(size("$outpath/10x-emptysquare.png"), "10x10");
}

is(size("$outpath/12x-twopages.png"), "12x12");
is(size("$outpath/16x-p1-twopages.png"), "16x2");
ok($outhtml =~ /width="8" height="8".*expecting 8x8/);
is(size("$outpath/x8-hello:world.png"), "8x8");
is(size("$outpath/x4-a:b:c.png"), "4x4");
is(size("$outpath/x6-a:b:c:d:e:f:g:h:i:j.png"), "6x6");

# now let's remove them again

if (1) { # for easier testing
	writefile("imgconversions.mdwn", "t/tmp/in", "nothing to see here");

	ok(! system(@command, "--refresh"));

	ok(! -e "$outpath/10x-simple.png");
	ok(! -e "$outpath/10x-simple-svg.png");
	ok(! -e "$outpath/10x-simple-pdf.png");
	ok(! -e "$outpath/10x-p1-simple-pdf.png");
	ok(! -e "$outpath/x8-hello:world.png");
	ok(! -e "$outpath/x4-a:b:c.png");
	ok(! -e "$outpath/x6-a:b:c:d:e:f:g:h:i:j.png");

	# cleanup
	ok(! system("rm -rf t/tmp"));
}
done_testing;

1;
