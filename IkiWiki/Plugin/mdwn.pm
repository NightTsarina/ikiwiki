#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "mdwn", call => \&getsetup);
	hook(type => "htmlize", id => "mdwn", call => \&htmlize, longname => "Markdown");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
			section => "format",
		},
		multimarkdown => {
			type => "boolean",
			example => 0,
			description => "enable multimarkdown features?",
			safe => 1,
			rebuild => 1,
		},
		nodiscount => {
			type => "boolean",
			example => 0,
			description => "disable use of markdown discount?",
			safe => 1,
			rebuild => 1,
		},
}

my $markdown_sub;
sub htmlize (@) {
	my %params=@_;
	my $content = $params{content};

	if (! defined $markdown_sub) {
		# Markdown is forked and splintered upstream and can be
		# available in a variety of forms. Support them all.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';

		if (exists $config{multimarkdown} && $config{multimarkdown}) {
			eval q{use Text::MultiMarkdown};
			if ($@) {
				debug(gettext("multimarkdown is enabled, but Text::MultiMarkdown is not installed"));
			}
			else {
				$markdown_sub=sub {
					Text::MultiMarkdown::markdown(shift, {use_metadata => 0});
				}
			}
		}
		if (! defined $markdown_sub &&
		    (! exists $config{nodiscount} || ! $config{nodiscount})) {
			eval q{use Text::Markdown::Discount};
			if (! $@) {
				$markdown_sub=sub {
					my $t=shift;
					# Workaround for discount binding bug
					# https://rt.cpan.org/Ticket/Display.html?id=73657
					return "" if $t=~/^\s*$/;
					# Workaround for discount's eliding
					# of <style> blocks.
					# https://rt.cpan.org/Ticket/Display.html?id=74016
					$t=~s/<style/<elyts/ig;
					my $r=Text::Markdown::Discount::markdown($t);
					$r=~s/<elyts/<style/ig;
					return $r;
				}
			}
		}
		if (! defined $markdown_sub) {
			eval q{use Text::Markdown};
			if (! $@) {
				if (Text::Markdown->can('markdown')) {
					$markdown_sub=\&Text::Markdown::markdown;
				}
				else {
					$markdown_sub=\&Text::Markdown::Markdown;
				}
			}
			else {
				eval q{use Markdown};
				if (! $@) {
					$markdown_sub=\&Markdown::Markdown;
				}
				else {
					my $error = $@;
					do "/usr/bin/markdown" ||
						error(sprintf(gettext("failed to load Markdown.pm perl module (%s) or /usr/bin/markdown (%s)"), $error, $!));
					$markdown_sub=\&Markdown::Markdown;
				}
			}
		}
		
		require Encode;
	}
	
	# Workaround for perl bug (#376329)
	$content=Encode::encode_utf8($content);
	eval {$content=&$markdown_sub($content)};
	if ($@) {
		eval {$content=&$markdown_sub($content)};
		print STDERR $@ if $@;
	}
	$content=Encode::decode_utf8($content);

	return $content;
}

1
