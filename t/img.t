#!/usr/bin/perl
#
# unit test that creates test images (png, svg, multi-page pdf), runs ikiwiki
# on them, checks the resulting images for plausibility based on their image
# sizes, and checks if they vanish when not required in the build process any
# more
#
package IkiWiki;

use warnings;
use strict;
use Test::More;

BEGIN { use_ok("IkiWiki"); }

ok(! system("rm -rf t/tmp; mkdir -p t/tmp/in"));

ok(! system("convert canvas:red -scale 20x20 t/tmp/in/simple.png"));
ok(! system("convert t/tmp/in/simple.png -extent 20x10 t/tmp/in/long.png"));
ok(! system("convert t/tmp/in/simple.png t/tmp/in/simple-svg.svg"));
# using different image sizes for different pages, so the pagenumber selection can be tested easily
ok(! system("convert t/tmp/in/simple.png t/tmp/in/long.png t/tmp/in/simple-pdf.pdf"));

writefile("imgconversions.mdwn", "t/tmp/in", <<EOF
[[!img simple.png]]
[[!img simple.png size=10x]]
[[!img simple-svg.svg size=10x]]
[[!img simple-pdf.pdf size=10x]]
[[!img simple-pdf.pdf size=10x pagenumber=1]]
EOF
);

ok(! system("make -s ikiwiki.out"));

my $command = "perl -I. ./ikiwiki.out -set usedirs=0 -plugin img t/tmp/in t/tmp/out -verbose";

ok(! system($command));

my $outpath = "t/tmp/out/imgconversions";
ok(`identify $outpath/10x-simple.png` =~ "PNG 10x10 ");
ok(`identify $outpath/10x-simple-svg.png` =~ "PNG 10x10 ");
ok(`identify $outpath/10x-simple-pdf.png` =~ "PNG 10x10 ");
ok(`identify $outpath/10x-p1-simple-pdf.png` =~ "PNG 10x5 ");

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
