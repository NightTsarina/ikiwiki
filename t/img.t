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
	unless eval q{use Image::Magick; 1};

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

$magick->Read("t/img/twopages.pdf");
my $PDFS_WORK = defined $magick->Get("width");

ok(! system("rm -rf t/tmp; mkdir -p t/tmp/in"));

ok(! system("cp t/img/redsquare.png t/tmp/in/redsquare.png"));
ok(! system("cp t/img/redsquare.jpg t/tmp/in/redsquare.jpg"));
ok(! system("cp t/img/redsquare.jpg t/tmp/in/redsquare.jpeg"));
# colons in filenames are a corner case for img
ok(! system("cp t/img/redsquare.png t/tmp/in/hello:world.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c:d.png"));
ok(! system("cp t/img/redsquare.png t/tmp/in/a:b:c:d:e:f:g:h:i:j.png"));

writefile("bluesquare.svg", "t/tmp/in",
	'<svg width="30" height="30"><rect x="0" y="0" width="30" height="30" fill="blue"/></svg>');
ok(! system("cp t/tmp/in/bluesquare.svg t/tmp/in/really-svg.png"));
ok(! system("cp t/tmp/in/bluesquare.svg t/tmp/in/really-svg.bmp"));
ok(! system("cp t/tmp/in/bluesquare.svg t/tmp/in/really-svg.pdf"));

# using different image sizes for different pages, so the pagenumber selection can be tested easily
ok(! system("cp t/img/twopages.pdf t/tmp/in/twopages.pdf"));
ok(! system("cp t/img/twopages.pdf t/tmp/in/really-pdf.jpeg"));
ok(! system("cp t/img/twopages.pdf t/tmp/in/really-pdf.jpg"));
ok(! system("cp t/img/twopages.pdf t/tmp/in/really-pdf.png"));
ok(! system("cp t/img/twopages.pdf t/tmp/in/really-pdf.svg"));

my $maybe_pdf_img = "";
if ($PDFS_WORK) {
	$maybe_pdf_img = <<EOF;
[[!img twopages.pdf size=12x]]
[[!img twopages.pdf size=16x pagenumber=1]]
EOF
}

writefile("imgconversions.mdwn", "t/tmp/in", <<EOF
[[!img redsquare.png]]
[[!img redsquare.jpg size=11x]]
[[!img redsquare.jpeg size=12x]]
[[!img redsquare.png size=10x]]
[[!img redsquare.png size=30x50]] expecting 30x30
[[!img hello:world.png size=x8]] expecting 8x8
[[!img a:b:c.png size=x4]]
[[!img a:b:c:d:e:f:g:h:i:j.png size=x6]]
[[!img bluesquare.svg size=42x]] expecting 42x
[[!img bluesquare.svg size=x43]] expecting x43
[[!img bluesquare.svg size=42x43]] expecting 42x43 because aspect rario not preserved
$maybe_pdf_img

# bad ideas
[[!img really-svg.png size=666x]]
[[!img really-svg.bmp size=666x]]
[[!img really-svg.pdf size=666x]]
[[!img really-pdf.jpeg size=666x]]
[[!img really-pdf.jpg size=666x]]
[[!img really-pdf.png size=666x]]
[[!img really-pdf.svg size=666x]]
EOF
);
ok(utime(333333333, 333333333, "t/tmp/in/imgconversions.mdwn"));

ok(! system(@command, '--set-yaml', 'img_allowed_formats=[jpeg, png, svg, pdf]'));

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
ok($outhtml =~ /width="42".*expecting 42x/);
ok($outhtml =~ /height="43".*expecting x43/);
ok($outhtml =~ /width="42" height="43".*expecting 42x43/);

SKIP: {
	skip "PDF support not installed (try ghostscript)", 2
		unless $PDFS_WORK;
	is(size("$outpath/12x-twopages.png"), "12x12");
	is(size("$outpath/16x-p1-twopages.png"), "16x2");
}

ok($outhtml =~ /width="8" height="8".*expecting 8x8/);
is(size("$outpath/x8-hello:world.png"), "8x8");
is(size("$outpath/x4-a:b:c.png"), "4x4");
is(size("$outpath/x6-a:b:c:d:e:f:g:h:i:j.png"), "6x6");

is(size("$outpath/11x-redsquare.jpg"), "11x11");
is(size("$outpath/12x-redsquare.jpeg"), "12x12");
like($outhtml, qr{src="(\./)?imgconversions/11x-redsquare\.jpg" width="11" height="11"});
like($outhtml, qr{src="(\./)?imgconversions/12x-redsquare\.jpeg" width="12" height="12"});

# We do not misinterpret images
my $quot = qr/(?:"|&quot;)/;
like($outhtml, qr/${quot}really-svg\.png${quot} does not seem to be a valid png file/);
ok(! -e "$outpath/666x-really-svg.png");
ok(! -e "$outpath/666x-really-svg.bmp");
like($outhtml, qr/${quot}really-pdf\.jpeg${quot} does not seem to be a valid jpeg file/);
ok(! -e "$outpath/666x-really-pdf.jpeg");
like($outhtml, qr/${quot}really-pdf\.jpg${quot} does not seem to be a valid jpeg file/);
ok(! -e "$outpath/666x-really-pdf.jpg");
like($outhtml, qr/${quot}really-pdf\.png${quot} does not seem to be a valid png file/);
ok(! -e "$outpath/666x-really-pdf.png");

# disable support for uncommon formats and try again
ok(! system(@command, "--rebuild"));
ok(! -e "$outpath/10x-bluesquare.png");
ok(! -e "$outpath/12x-twopages.png");
ok(! -e "$outpath/16x-p1-twopages.png");

# now let's remove them again

if (1) { # for easier testing
	writefile("imgconversions.mdwn", "t/tmp/in", "nothing to see here");

	ok(! system(@command, "--refresh"));

	ok(! -e "$outpath/10x-redsquare.png");
	ok(! -e "$outpath/10x-bluesquare.png");
	ok(! -e "$outpath/12x-twopages.png");
	ok(! -e "$outpath/16x-p1-twopages.png");
	ok(! -e "$outpath/x8-hello:world.png");
	ok(! -e "$outpath/x4-a:b:c.png");
	ok(! -e "$outpath/x6-a:b:c:d:e:f:g:h:i:j.png");

	# cleanup
	ok(! system("rm -rf t/tmp"));
}
done_testing;

1;
