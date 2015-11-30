#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw();
use File::Find;
use Test::More;

plan(skip_all => 'running installed') if $ENV{INSTALLED_TESTS};

plan(skip_all => "XML::Parser not available")
	unless eval q{use XML::Parser (); 1;};

use IkiWiki;

ok(system("make >/dev/null") == 0);

chdir("html") || die "chdir: $!";

sub wanted {
	my $file = $_;
	return if -d $file;
	$file =~ s{^\./}{};
	return if $file !~ m/\.html$/;
	if (eval {
		XML::Parser->new()->parsefile($file);
		1;
	}) {
		pass($file);
	}
	elsif ($file =~ m{^(?:
			# user-contributed, contains explicit <br>
			plugins/contrib/gallery |
			# use templatebody when branchable.com has been upgraded
			templates/ |
			# malformed content in <pre> not escaped by discount
			tips/convert_mediawiki_to_ikiwiki
			# user-contributed, content is anyone's guess
			users/ |
			)}x) {
		TODO: {
			local $TODO = $@;
			fail($file);
		}
	}
}

find({
	no_chdir => 1,
	wanted => \&wanted,
}, '.');

done_testing;
