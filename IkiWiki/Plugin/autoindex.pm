#!/usr/bin/perl
package IkiWiki::Plugin::autoindex;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

sub import {
	hook(type => "getsetup", id => "autoindex", call => \&getsetup);
	hook(type => "refresh", id => "autoindex", call => \&refresh);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
		},
}

sub genindex ($) {
	my $page=shift;
	my $file=newpagefile($page, $config{default_pageext});

	add_autofile($file, "autoindex", sub {
			my $message = sprintf(gettext("creating index page %s"),
				$page);
			debug($message);

			my $template = template("autoindex.tmpl");
			$template->param(page => $page);
			writefile($file, $config{srcdir}, $template->output);

			if ($config{rcs}) {
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

	# FIXME: some of this is probably redundant with add_autofile now, and
	# the rest should perhaps be added to the autofile machinery

	my %deleted;
	if (ref $wikistate{autoindex}{deleted}) {
		%deleted=%{$wikistate{autoindex}{deleted}};
	}
        elsif (ref $pagestate{index}{autoindex}{deleted}) {
		# compatability code
		%deleted=%{$pagestate{index}{autoindex}{deleted}};
		delete $pagestate{index}{autoindex};
	}

	if (keys %deleted) {
		foreach my $dir (keys %deleted) {
			# remove deleted page state if the deleted page is re-added,
			# or if all its subpages are deleted
			if ($deleted{$dir} && (exists $pages{$dir} ||
			                       ! grep /^$dir\/.*/, keys %pages)) {
				delete $deleted{$dir};
			}
		}
		$wikistate{autoindex}{deleted}=\%deleted;
	}

	my @needed;
	foreach my $dir (keys %dirs) {
		if (! exists $pages{$dir} && ! $deleted{$dir} &&
		    grep /^$dir\/.*/, keys %pages) {
		    	if (exists $IkiWiki::pagemtime{$dir}) {
				# This page must have just been deleted, so
				# don't re-add it. And remember it was
				# deleted.
				if (! ref $wikistate{autoindex}{deleted}) {
					$wikistate{autoindex}{deleted}={};
				}
				${$wikistate{autoindex}{deleted}}{$dir}=1;
			}
			else {
				push @needed, $dir;
			}
		}
	}
	
	if (@needed) {
		foreach my $page (@needed) {
			genindex($page);
		}
	}
}

1
