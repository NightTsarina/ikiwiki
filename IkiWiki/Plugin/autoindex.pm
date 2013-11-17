#!/usr/bin/perl
package IkiWiki::Plugin::autoindex;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "checkconfig", id => "autoindex", call => \&checkconfig);
	hook(type => "getsetup", id => "autoindex", call => \&getsetup);
	hook(type => "refresh", id => "autoindex", call => \&refresh);
	IkiWiki::loadplugin("transient");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
		autoindex_commit => {
			type => "boolean",
			example => 1,
			default => 1,
			description => "commit autocreated index pages",
			safe => 1,
			rebuild => 0,
		},
}

sub checkconfig () {
	if (! defined $config{autoindex_commit}) {
		$config{autoindex_commit} = 1;
	}
	if (! $config{autoindex_commit}) {
		$config{only_committed_changes}=0;
	}
}

sub genindex ($) {
	my $page=shift;
	my $file=newpagefile($page, $config{default_pageext});

	add_autofile($file, "autoindex", sub {
			my $message = sprintf(gettext("creating index page %s"),
				$page);
			debug($message);

			my $dir = $config{srcdir};
			if (! $config{autoindex_commit}) {
				$dir = $IkiWiki::Plugin::transient::transientdir;
			}

			my $template = template("autoindex.tmpl");
			$template->param(page => $page);
			writefile($file, $dir, $template->output);

			if ($config{rcs} && $config{autoindex_commit}) {
				IkiWiki::disable_commit_hook();
				IkiWiki::rcs_add($file);
				IkiWiki::rcs_commit_staged(message => $message);
				IkiWiki::enable_commit_hook();
			}
		});
}

sub refresh () {
	eval q{use File::Find};
	error($@) if $@;
	eval q{use Cwd};
	error($@) if $@;
	my $origdir=getcwd();

	my (%pages, %dirs);
	foreach my $dir ($config{srcdir}, @{$config{underlaydirs}}, $config{underlaydir}) {
		next if $dir eq $IkiWiki::Plugin::transient::transientdir;
		chdir($dir) || next;

		find({
			no_chdir => 1,
			wanted => sub {
				my $file=decode_utf8($_);
				$file=~s/^\.\/?//;
				return unless length $file;
				if (IkiWiki::file_pruned($file)) {
					$File::Find::prune=1;
				}
				elsif (! -l $_) {
					my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
					return unless defined $f;
					return if $f =~ /\._([^.]+)$/; # skip internal page
					if (! -d _) {
						$pages{pagename($f)}=1;
					}
					elsif ($dir eq $config{srcdir}) {
						$dirs{$f}=1;
					}
				}
			}
		}, '.');

		chdir($origdir) || die "chdir $origdir: $!";
	}

	# Compatibility code.
	#
	# {deleted} contains pages that have been deleted at some point.
	# This plugin used to delete from the hash sometimes, but no longer
	# does; in [[todo/autoindex_should_use_add__95__autofile]] Joey
	# thought the old behaviour was probably a bug.
	#
	# The effect of listing a page in {deleted} was to avoid re-creating
	# it; we migrate these pages to {autofile} which has the same effect.
	# However, {autofile} contains source filenames whereas {deleted}
	# contains page names.
	my %deleted;
	if (ref $wikistate{autoindex}{deleted}) {
		%deleted=%{$wikistate{autoindex}{deleted}};
		delete $wikistate{autoindex}{deleted};
	}
        elsif (ref $pagestate{index}{autoindex}{deleted}) {
		# an even older version
		%deleted=%{$pagestate{index}{autoindex}{deleted}};
		delete $pagestate{index}{autoindex};
	}

	if (keys %deleted) {
		foreach my $dir (keys %deleted) {
			my $file=newpagefile($dir, $config{default_pageext});
			$wikistate{autoindex}{autofile}{$file} = 1;
		}
	}

	foreach my $dir (keys %dirs) {
		if (! exists $pages{$dir} && grep /^$dir\/.*/, keys %pages) {
			genindex($dir);
		}
	}
}

1
