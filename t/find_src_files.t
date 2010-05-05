#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 20;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}="t/tmp/srcdir";
$config{underlaydir}="t/tmp/underlaydir";
IkiWiki::checkconfig();

sub cleanup {
	ok(! system("rm -rf t/tmp"));
}

sub setup_underlay {
	foreach my $file (@_) {
		writefile($file, $config{underlaydir}, "test content");
	}
	return @_;
}

sub setup_srcdir {
	foreach my $file (@_) {
		writefile($file, $config{srcdir}, "test content");
	}
	return @_;
}

sub test_src_files {
	my %expected=map { $_ => 1 } @{shift()}; # the input list may have dups
	my $desc=shift;

	close STDERR; # find_src_files prints warnings about bad files

	my ($files, $pages)=IkiWiki::find_src_files();
	is_deeply([sort @$files], [sort keys %expected], $desc);
}

cleanup();

my @list=setup_underlay(qw{index.mdwn sandbox.mdwn smiley.png ikiwiki.mdwn ikiwiki/directive.mdwn ikiwiki/directive/foo.mdwn});
push @list, setup_srcdir(qw{index.mdwn foo.mwdn icon.jpeg blog/archive/1/2/3/foo.mdwn blog/archive/1/2/4/bar.mdwn blog/archive.mdwn});
test_src_files(\@list, "simple test");

setup_srcdir(".badfile");
test_src_files(\@list, "srcdir dotfile is skipped");

setup_underlay(".badfile");
test_src_files(\@list, "underlay dotfile is skipped");

setup_srcdir(".ikiwiki/index");
test_src_files(\@list, "srcdir dotdir is skipped");

setup_underlay(".ikiwiki/index");
test_src_files(\@list, "underlay dotdir is skipped");

setup_srcdir("foo>.mdwn");
test_src_files(\@list, "illegal srcdir filename skipped");

setup_underlay("foo>.mdwn");
test_src_files(\@list, "illegal underlay filename skipped");

system("mkdir -p $config{srcdir}/empty");
test_src_files(\@list, "empty srcdir directory ignored");

system("mkdir -p $config{underlaydir}/empty");
test_src_files(\@list, "empty underlay directory ignored");

setup_underlay("bad.mdwn");
system("ln -sf /etc/passwd $config{srcdir}/bad.mdwn");
test_src_files(\@list, "underlaydir override attack foiled");

system("ln -sf /etc/passwd $config{srcdir}/symlink.mdwn");
test_src_files(\@list, "file symlink in srcdir skipped");

system("ln -sf /etc/passwd $config{underlaydir}/symlink.mdwn");
test_src_files(\@list, "file symlink in underlaydir skipped");

system("ln -sf /etc/ $config{srcdir}/symdir");
test_src_files(\@list, "dir symlink in srcdir skipped");

system("ln -sf /etc/ $config{underlaydir}/symdir");
test_src_files(\@list, "dir symlink in underlaydir skipped");

system("ln -sf /etc/ $config{srcdir}/blog/symdir");
test_src_files(\@list, "deep dir symlink in srcdir skipped");

system("ln -sf /etc/ $config{underlaydir}/ikiwiki/symdir");
test_src_files(\@list, "deep dir symlink in underlaydir skipped");




cleanup();
