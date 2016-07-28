#!/usr/bin/perl
use warnings;
use strict;
use Cwd qw(getcwd);
use Test::More;
use IkiWiki;

ok(! system("rm -rf t/tmp"));
ok(mkdir "t/tmp");
ok(! system("cp -R t/tinyblog t/tmp/in"));
ok(mkdir "t/tmp/in/post" or -d "t/tmp/in/post");

my $installed = $ENV{INSTALLED_TESTS};

my @command;
if ($installed) {
	@command = qw(ikiwiki);
}
else {
	ok(! system("make -s ikiwiki.out"));
	@command = ("perl", "-I".getcwd, qw(./ikiwiki.out
		--underlaydir=underlays/basewiki
		--set underlaydirbase=underlays
		--templatedir=templates));
}

my $comment;

$comment = <<EOF;
[[!comment username="neil"
  date="1969-07-20T20:17:40Z"
  content="I landed"]]
EOF
#ok(eval { writefile("post/comment_3._comment", "t/tmp/in", $comment); 1 });
writefile("post/comment_3._comment", "t/tmp/in", $comment);

$comment = <<EOF;
[[!comment username="christopher"
  date="1969-02-12T07:00:00Z"
  content="I explored"]]
EOF
writefile("post/comment_2._comment", "t/tmp/in", $comment);

$comment = <<EOF;
[[!comment username="william"
  date="1969-01-14T12:00:00Z"
  content="I conquered"]]
EOF
writefile("post/comment_1._comment", "t/tmp/in", $comment);

# Give the files mtimes in the wrong order
ok(utime(111111111, 111111111, "t/tmp/in/post/comment_3._comment"));
ok(utime(222222222, 222222222, "t/tmp/in/post/comment_2._comment"));
ok(utime(333333333, 333333333, "t/tmp/in/post/comment_1._comment"));

# Build the wiki
ok(! system(@command, qw(--verbose --plugin comments --url=http://example.com --cgiurl=http://example.com/ikiwiki.cgi --rss --atom --set comments_pagespec=* t/tmp/in t/tmp/out)));

# Check that the comments are in the right order

sub slurp {
    open my $fh, "<", shift or return undef;
    local $/;
    my $content = <$fh>;
    close $fh or return undef;
    return $content;
}

my $content = slurp("t/tmp/out/post/index.html");
ok(defined $content);
ok($content =~ m/I conquered.*I explored.*I landed/s);

done_testing();
