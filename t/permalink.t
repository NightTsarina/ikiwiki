#!/usr/bin/perl
use warnings;
use strict;
use Test::More 'no_plan';

ok(! system("rm -rf t/tmp"));
ok(! system("mkdir t/tmp"));
ok(! system("make -s ikiwiki.out"));
ok(! system("perl -I. ./ikiwiki.out -plugin inline -url=http://example.com -cgiurl=http://example.com/ikiwiki.cgi -rss -atom -underlaydir=underlays/basewiki -set underlaydirbase=underlays -templatedir=templates t/tinyblog t/tmp/out"));
# This guid should never, ever change, for any reason whatsoever!
my $guid="http://example.com/post/";
ok(length `egrep '<guid.*>$guid</guid>' t/tmp/out/index.rss`);
ok(length `egrep '<id>$guid</id>' t/tmp/out/index.atom`);
ok(! system("rm -rf t/tmp t/tinyblog/.ikiwiki"));
