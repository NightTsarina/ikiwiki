#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
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

					my $flags=0;

					# Disable Pandoc-style % Title, % Author, % Date
					# Use the meta plugin instead
					$flags |= Text::Markdown::Discount::MKD_NOHEADER();

					# Disable Unicodification of quote marks, em dashes...
					# Use the typography plugin instead
					$flags |= Text::Markdown::Discount::MKD_NOPANTS();

					# Workaround for discount's eliding
					# of <style> blocks.
					# https://rt.cpan.org/Ticket/Display.html?id=74016
					if (Text::Markdown::Discount->can("MKD_NOSTYLE")) {
						$flags |= Text::Markdown::Discount::MKD_NOSTYLE();
					}
					else {
						# This is correct for the libmarkdown.so.2 ABI
						$flags |= 0x00400000;
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
