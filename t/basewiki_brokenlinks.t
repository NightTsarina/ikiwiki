#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw(getcwd);
use Test::More;

my $installed = $ENV{INSTALLED_TESTS};

ok(! system("rm -rf t/tmp; mkdir t/tmp"));

my @command;
if ($installed) {
	@command = qw(env LC_ALL=C ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	ok(! system("make underlay_install DESTDIR=`pwd`/t/tmp/install PREFIX=/usr >/dev/null"));
	@command = (qw(env LC_ALL=C perl), "-I".getcwd, qw(./ikiwiki.out
		--underlaydir=t/tmp/install/usr/share/ikiwiki/basewiki
		--set underlaydirbase=t/tmp/install/usr/share/ikiwiki
		--templatedir=templates));
}

foreach my $plugin ("", "listdirectives") {
	ok(! system(@command, qw(--rebuild --plugin brokenlinks),
			# always enabled because pages link to it conditionally,
			# which brokenlinks cannot handle properly
			qw(--plugin smiley),
			($plugin ? ("--plugin", $plugin) : ()),
			qw(t/basewiki_brokenlinks t/tmp/out)));
	my $result=`grep 'no broken links' t/tmp/out/index.html`;
	ok(length($result));
	if (! length $result) {
		print STDERR "\n\nbroken links found".($plugin ? " (with $plugin)" : "")."\n";
		system("grep '<li>' t/tmp/out/index.html >&2");
		print STDERR "\n\n";
	}
	ok(-e "t/tmp/out/style.css"); # linked to..
	ok(! system("rm -rf t/tmp/out t/basewiki_brokenlinks/.ikiwiki"));
}
ok(! system("rm -rf t/tmp"));

done_testing();
