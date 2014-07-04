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

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("Image::Magick"); }

ok(! system("rm -rf t/tmp; mkdir -p t/tmp/in"));

ok(! system("cp t/img/redsquare.png t/tmp/in/redsquare.png"));
writefile("emptysquare.svg", "t/tmp/in", '<svg width="10" height="10"/>');
# using different image sizes for different pages, so the pagenumber selection can be tested easily
ok(! system("cp t/img/twopages.pdf t/tmp/in/twopages.pdf"));

writefile("imgconversions.mdwn", "t/tmp/in", <<EOF
[[!img redsquare.png]]
[[!img redsquare.png size=10x]]
[[!img emptysquare.svg size=10x]]
[[!img twopages.pdf size=12x]]
[[!img twopages.pdf size=16x pagenumber=1]]
EOF
);

ok(! system("make -s ikiwiki.out"));

my $command = "perl -I. ./ikiwiki.out -set usedirs=0 -plugin img t/tmp/in t/tmp/out -verbose";

ok(! system($command));

sub size($) {
	my $filename = shift;
	my $im = Image::Magick->new();
	$im->Read($filename);
	my $w = $im->Get("width");
	my $h = $im->Get("height");
	return "${w}x${h}";
}

my $outpath = "t/tmp/out/imgconversions";
is(size("$outpath/10x-redsquare.png"), "10x10");
# if this fails, you need libmagickcore-6.q16-2-extra installed
is(size("$outpath/10x-emptysquare.png"), "10x10");
is(size("$outpath/12x-twopages.png"), "12x12");
is(size("$outpath/16x-p1-twopages.png"), "16x2");

# now let's remove them again

writefile("imgconversions.mdwn", "t/tmp/in", "nothing to see here");

ok(! system("$command --refresh"));

ok(! -e "$outpath/10x-simple.png");
ok(! -e "$outpath/10x-simple-svg.png");
ok(! -e "$outpath/10x-simple-pdf.png");
ok(! -e "$outpath/10x-p1-simple-pdf.png");

# cleanup
ok(! system("rm -rf t/tmp"));
done_testing;

1;
