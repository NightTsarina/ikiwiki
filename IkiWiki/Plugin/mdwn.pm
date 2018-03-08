#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "checkconfig", id => "mdwn", call => \&checkconfig);
	hook(type => "getsetup", id => "mdwn", call => \&getsetup);
	hook(type => "htmlize", id => "mdwn", call => \&htmlize, longname => "Markdown");
	hook(type => "htmlize", id => "md", call => \&htmlize, longname => "Markdown (popular file extension)", nocreate => 1);
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
		mdwn_footnotes => {
			type => "boolean",
			example => 1,
			description => "enable footnotes in Markdown (where supported)?",
			safe => 1,
			rebuild => 1,
		},
		mdwn_alpha_lists => {
			type => "boolean",
			example => 0,
			description => "interpret line like 'A. First item' as ordered list when using Discount?",
			advanced => 1,
			safe => 1,
			rebuild => 1,
		},
}

sub checkconfig () {
	$config{mdwn_footnotes} = 1 unless defined $config{mdwn_footnotes};
	$config{mdwn_alpha_lists} = 0 unless defined $config{mdwn_alpha_lists};
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
					my %flags=( use_metadata => 0 );

					if ($config{mdwn_footnotes}) {
						$flags{disable_footnotes}=1;
					}

					Text::MultiMarkdown::markdown(shift, \%flags);
				}
			}
		}
		if (! defined $markdown_sub &&
		    (! exists $config{nodiscount} || ! $config{nodiscount})) {
			eval q{use Text::Markdown::Discount};
			if (! $@) {
				my $markdown = \&Text::Markdown::Discount::markdown;
				my $always_flags = 0;

				# Disable Pandoc-style % Title, % Author, % Date
				# Use the meta plugin instead
				$always_flags |= Text::Markdown::Discount::MKD_NOHEADER();

				# Disable Unicodification of quote marks, em dashes...
				# Use the typography plugin instead
				$always_flags |= Text::Markdown::Discount::MKD_NOPANTS();

				# Workaround for discount's eliding of <style> blocks.
				# https://rt.cpan.org/Ticket/Display.html?id=74016
				if (Text::Markdown::Discount->can('MKD_NOSTYLE')) {
					$always_flags |= Text::Markdown::Discount::MKD_NOSTYLE();
				}
				elsif ($markdown->('<style>x</style>', 0) !~ '<style>' &&
					$markdown->('<style>x</style>', 0x00400000) =~ m{<style>x</style>}) {
					$always_flags |= 0x00400000;
				}

				# Enable fenced code blocks in libmarkdown >= 2.2.0
				# https://bugs.debian.org/888055
				if (Text::Markdown::Discount->can('MKD_FENCEDCODE')) {
					$always_flags |= Text::Markdown::Discount::MKD_FENCEDCODE();
				}
				elsif ($markdown->("~~~\nx\n~~~", 0) !~ m{<pre\b} &&
					$markdown->("~~~\nx\n~~~", 0x02000000) =~ m{<pre\b}) {
					$always_flags |= 0x02000000;
				}

				# PHP Markdown Extra-style term\n: definition -> <dl>
				if (Text::Markdown::Discount->can('MKD_DLEXTRA')) {
					$always_flags |= Text::Markdown::Discount::MKD_DLEXTRA();
				}
				elsif ($markdown->("term\n: def\n", 0) !~ m{<dl>} &&
					$markdown->("term\n: def\n", 0x01000000) =~ m{<dl>}) {
					$always_flags |= 0x01000000;
				}

				# Allow dashes and underscores in tag names
				if (Text::Markdown::Discount->can('MKD_GITHUBTAGS')) {
					$always_flags |= Text::Markdown::Discount::MKD_GITHUBTAGS();
				}
				elsif ($markdown->('<foo_bar>', 0) !~ m{<foo_bar} &&
					$markdown->('<foo_bar>', 0x08000000) =~ m{<foo_bar\b}) {
					$always_flags |= 0x08000000;
				}

				$markdown_sub=sub {
					my $t=shift;

					# Workaround for discount binding bug
					# https://rt.cpan.org/Ticket/Display.html?id=73657
					return "" if $t=~/^\s*$/;

					my $flags=$always_flags;

					if ($config{mdwn_footnotes}) {
						$flags |= Text::Markdown::Discount::MKD_EXTRA_FOOTNOTE();
					}

					unless ($config{mdwn_alpha_lists}) {
						$flags |= Text::Markdown::Discount::MKD_NOALPHALIST();
					}

					return Text::Markdown::Discount::markdown($t, $flags);
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
