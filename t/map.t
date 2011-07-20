#!/usr/bin/perl
package IkiWiki;

use warnings;
use strict;
use HTML::TreeBuilder;
use Test::More;

BEGIN { use_ok("IkiWiki"); }
BEGIN { use_ok("IkiWiki::Render"); }
BEGIN { use_ok("IkiWiki::Plugin::map"); }
BEGIN { use_ok("IkiWiki::Plugin::mdwn"); }

ok(! system("rm -rf t/tmp; mkdir t/tmp"));

$config{verbose} = 1;
$config{srcdir} = 't/tmp';
$config{underlaydir} = 't/tmp';
$config{underlaydirbase} = '.';
$config{templatedir} = 'templates';
$config{usedirs} = 1;
$config{htmlext} = 'html';
$config{wiki_file_chars} = "-[:alnum:]+/.:_";
$config{userdir} = "users";
$config{tagbase} = "tags";
$config{default_pageext} = "mdwn";
$config{wiki_file_prune_regexps} = [qr/^\./];
$config{autoindex_commit} = 0;

is(checkconfig(), 1);

%oldrenderedfiles=%pagectime=();
%pagesources=%pagemtime=%oldlinks=%links=%depends=%typedlinks=%oldtypedlinks=
%destsources=%renderedfiles=%pagecase=%pagestate=();

my @pages = qw(
alpha
alpha/1
alpha/1/i
alpha/1/ii
alpha/1/iii
alpha/1/iv
alpha/2
alpha/2/a
alpha/2/b
alpha/3
beta
);

foreach my $page (@pages) {
	# we use a non-default extension for these, so they're distinguishable
	# from programmatically-created pages
	$pagesources{$page} = "$page.mdwn";
	$destsources{$page} = "$page.mdwn";
	$pagemtime{$page} = $pagectime{$page} = 1000000;
	writefile("$page.mdwn", "t/tmp", "your ad here");
}

sub node {
	my $name = shift;
	my $kids = shift;
	my %stuff = @_;

	return { %stuff, name => $name, kids => $kids };
}

sub check_nodes {
	my $ul = shift;
	my $expected = shift;

	is($ul->tag, 'ul');

	# expected is a list of hashes
	# ul is a list of li
	foreach my $li ($ul->content_list) {
		my @kids = $li->content_list;

		is($li->tag, 'li');

		my $expectation = shift @$expected;

		is($kids[0]->tag, 'a');
		my $a = $kids[0];

		if ($expectation->{parent}) {
			is($a->attr('class'), 'mapparent');
		}
		else {
			is($a->attr('class'), 'mapitem');
		}

		is_deeply([$a->content_list], [$expectation->{name}]);

		if (@{$expectation->{kids}}) {
			is($kids[1]->tag, 'ul');
			is(scalar @kids, 2);

			check_nodes($kids[1], $expectation->{kids});
		}
		else {
			is_deeply([@kids], [$a]);
		}
	}
}

sub check {
	my $pagespec = shift;
	my $expected = shift;

	my $html = IkiWiki::Plugin::map::preprocess(pages => $pagespec,
		page => 'map',
		destpage => 'map');
	my $tree = HTML::TreeBuilder->new;
	$tree->implicit_tags(0);
	$tree->unbroken_text(1);
	$tree->strict_end(1);
	$tree->strict_names(1);
	$tree->strict_comment(1);
	$tree->empty_element_tags(1);
	$tree->parse_content($html);
	my $fragment = $tree->disembowel;
	print $fragment->dump;

	is($fragment->tag, 'div');
	is($fragment->attr('class'), 'map');

	check_nodes(($fragment->content_list)[0], $expected);

	$fragment->delete;
	print "<!-- -->\n";
}

check('alpha', [node('alpha', [])]);

check('alpha/*',
	[
		node('1', [
			node('i', []),
			node('ii', []),
			node('iii', []),
			node('iv', []),
		]),
		node('2', [
			node('a', []),
			node('b', []),
		]),
		node('3', []),
	]);

check('alpha or alpha/*',
	[
		node('alpha', [
			node('1', [
				node('i', []),
				node('ii', []),
				node('iii', []),
				node('iv', []),
			]),
			node('2', [
				node('a', []),
				node('b', []),
			]),
			node('3', []),
		]),
	]);

check('alpha or alpha/1 or beta',
	[
		node('alpha', [
			node('1', []),
		]),
		node('beta', []),
	]);

done_testing;

1;
