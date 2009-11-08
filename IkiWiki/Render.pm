#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use Encode;

my (%backlinks, %rendered);
our %brokenlinks;
my $links_calculated=0;

sub calculate_links () {
	return if $links_calculated;
	%backlinks=%brokenlinks=();
	foreach my $page (keys %links) {
		foreach my $link (@{$links{$page}}) {
			my $bestlink=bestlink($page, $link);
			if (length $bestlink) {
				$backlinks{$bestlink}{$page}=1
					if $bestlink ne $page;
			}
			else {
				push @{$brokenlinks{$link}}, $page;
			}
		}
	}
	$links_calculated=1;
}

sub backlink_pages ($) {
	my $page=shift;

	calculate_links();

	return keys %{$backlinks{$page}};
}

sub backlinks ($) {
	my $page=shift;

	my @links;
	foreach my $p (backlink_pages($page)) {
		my $href=urlto($p, $page);
                
		# Trim common dir prefixes from both pages.
		my $p_trimmed=$p;
		my $page_trimmed=$page;
		my $dir;
		1 while (($dir)=$page_trimmed=~m!^([^/]+/)!) &&
		        defined $dir &&
		        $p_trimmed=~s/^\Q$dir\E// &&
		        $page_trimmed=~s/^\Q$dir\E//;
			       
		push @links, { url => $href, page => pagetitle($p_trimmed) };
	}
	return @links;
}

sub genpage ($$) {
	my $page=shift;
	my $content=shift;
	
	run_hooks(postscan => sub {
		shift->(page => $page, content => $content);
	});

	my $templatefile;
	run_hooks(templatefile => sub {
		return if defined $templatefile;
		my $file=shift->(page => $page);
		if (defined $file && defined template_file($file)) {
			$templatefile=$file;
		}
	});
	my $template=template(defined $templatefile ? $templatefile : 'page.tmpl', blind_cache => 1);
	my $actions=0;

	if (length $config{cgiurl}) {
		$template->param(editurl => cgiurl(do => "edit", page => $page))
			if IkiWiki->can("cgi_editpage");
		$template->param(prefsurl => cgiurl(do => "prefs"))
			if exists $hooks{auth};
		$actions++;
	}
		
	if (defined $config{historyurl} && length $config{historyurl}) {
		my $u=$config{historyurl};
		$u=~s/\[\[file\]\]/$pagesources{$page}/g;
		$template->param(historyurl => $u);
		$actions++;
	}
	if ($config{discussion}) {
		if ($page !~ /.*\/\Q$config{discussionpage}\E$/ &&
		   (length $config{cgiurl} ||
		    exists $links{$page."/".$config{discussionpage}})) {
			$template->param(discussionlink => htmllink($page, $page, $config{discussionpage}, noimageinline => 1, forcesubpage => 1));
			$actions++;
		}
	}

	if ($actions) {
		$template->param(have_actions => 1);
	}

	my @backlinks=sort { $a->{page} cmp $b->{page} } backlinks($page);
	my ($backlinks, $more_backlinks);
	if (@backlinks <= $config{numbacklinks} || ! $config{numbacklinks}) {
		$backlinks=\@backlinks;
		$more_backlinks=[];
	}
	else {
		$backlinks=[@backlinks[0..$config{numbacklinks}-1]];
		$more_backlinks=[@backlinks[$config{numbacklinks}..$#backlinks]];
	}

	$template->param(
		title => $page eq 'index' 
			? $config{wikiname} 
			: pagetitle(basename($page)),
		wikiname => $config{wikiname},
		content => $content,
		backlinks => $backlinks,
		more_backlinks => $more_backlinks,
		mtime => displaytime($pagemtime{$page}),
		ctime => displaytime($pagectime{$page}),
		baseurl => baseurl($page),
	);

	run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page, template => $template);
	});
	
	$content=$template->output;
	
	run_hooks(format => sub {
		$content=shift->(
			page => $page,
			content => $content,
		);
	});

	return $content;
}

sub scan ($) {
	my $file=shift;

	debug(sprintf(gettext("scanning %s"), $file));

	my $type=pagetype($file);
	if (defined $type) {
		my $srcfile=srcfile($file);
		my $content=readfile($srcfile);
		my $page=pagename($file);
		will_render($page, htmlpage($page), 1);

		if ($config{discussion}) {
			# Discussion links are a special case since they're
			# not in the text of the page, but on its template.
			$links{$page}=[ $page."/".lc($config{discussionpage}) ];
		}
		else {
			$links{$page}=[];
		}

		run_hooks(scan => sub {
			shift->(
				page => $page,
				content => $content,
			);
		});

		# Preprocess in scan-only mode.
		preprocess($page, $page, $content, 1);
	}
	else {
		will_render($file, $file, 1);
	}
}

sub fast_file_copy (@) {
	my $srcfile=shift;
	my $destfile=shift;
	my $srcfd=shift;
	my $destfd=shift;
	my $cleanup=shift;

	my $blksize = 16384;
	my ($len, $buf, $written);
	while ($len = sysread $srcfd, $buf, $blksize) {
		if (! defined $len) {
			next if $! =~ /^Interrupted/;
			error("failed to read $srcfile: $!", $cleanup);
		}
		my $offset = 0;
		while ($len) {
			defined($written = syswrite $destfd, $buf, $len, $offset)
				or error("failed to write $destfile: $!", $cleanup);
			$len -= $written;
			$offset += $written;
		}
	}
}

sub render ($$) {
	my $file=shift;
	return if $rendered{$file};
	debug(shift);
	$rendered{$file}=1;
	
	my $type=pagetype($file);
	my $srcfile=srcfile($file);
	if (defined $type) {
		my $page=pagename($file);
		delete $depends{$page};
		delete $depends_simple{$page};
		will_render($page, htmlpage($page), 1);
		return if $type=~/^_/;
		
		my $content=htmlize($page, $page, $type,
			linkify($page, $page,
			preprocess($page, $page,
			filter($page, $page,
			readfile($srcfile)))));
		
		my $output=htmlpage($page);
		writefile($output, $config{destdir}, genpage($page, $content));
	}
	else {
		delete $depends{$file};
		delete $depends_simple{$file};
		will_render($file, $file, 1);
		
		if ($config{hardlink}) {
			# only hardlink if owned by same user
			my @stat=stat($srcfile);
			if ($stat[4] == $>) {
				prep_writefile($file, $config{destdir});
				unlink($config{destdir}."/".$file);
				if (link($srcfile, $config{destdir}."/".$file)) {
					return;
				}
			}
			# if hardlink fails, fall back to copying
		}
		
		my $srcfd=readfile($srcfile, 1, 1);
		writefile($file, $config{destdir}, undef, 1, sub {
			fast_file_copy($srcfile, $file, $srcfd, @_);
		});
	}
}

sub prune ($) {
	my $file=shift;

	unlink($file);
	my $dir=dirname($file);
	while (rmdir($dir)) {
		$dir=dirname($dir);
	}
}

sub srcdir_check () {
	# security check, avoid following symlinks in the srcdir path by default
	my $test=$config{srcdir};
	while (length $test) {
		if (-l $test && ! $config{allow_symlinks_before_srcdir}) {
			error(sprintf(gettext("symlink found in srcdir path (%s) -- set allow_symlinks_before_srcdir to allow this"), $test));
		}
		unless ($test=~s/\/+$//) {
			$test=dirname($test);
		}
	}
	
}

sub find_src_files () {
	my @files;
	my %pages;
	eval q{use File::Find};
	error($@) if $@;
	find({
		no_chdir => 1,
		wanted => sub {
			my $file=decode_utf8($_);
			$file=~s/^\Q$config{srcdir}\E\/?//;
			return if -l $_ || -d _ || ! length $file;
			my $page = pagename($file);
			if (! exists $pagesources{$page} &&
			    file_pruned($file)) {
				$File::Find::prune=1;
				return;
			}

			my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
			if (! defined $f) {
				warn(sprintf(gettext("skipping bad filename %s"), $file)."\n");
			}
			else {
				push @files, $f;
				if ($pages{$page}) {
					debug(sprintf(gettext("%s has multiple possible source pages"), $page));
				}
				$pages{$page}=1;
			}
		},
	}, $config{srcdir});
	foreach my $dir (@{$config{underlaydirs}}, $config{underlaydir}) {
		find({
			no_chdir => 1,
			wanted => sub {
				my $file=decode_utf8($_);
				$file=~s/^\Q$dir\E\/?//;
				return if -l $_ || -d _ || ! length $file;
				my $page=pagename($file);
				if (! exists $pagesources{$page} &&
				    file_pruned($file)) {
					$File::Find::prune=1;
					return;
				}

				my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
				if (! defined $f) {
					warn(sprintf(gettext("skipping bad filename %s"), $file)."\n");
				}
				else {
					# avoid underlaydir override
					# attacks; see security.mdwn
					if (! -l "$config{srcdir}/$f" && 
					    ! -e _) {
						if (! $pages{$page}) {
							push @files, $f;
							$pages{$page}=1;
						}
					}
				}
			},
		}, $dir);
	};
	return \@files, \%pages;
}

sub find_new_files ($) {
	my $files=shift;
	my @new;
	my @internal_new;

	foreach my $file (@$files) {
		my $page=pagename($file);
		if (exists $pagesources{$page} && $pagesources{$page} ne $file) {
			# the page has changed its type
			$forcerebuild{$page}=1;
		}
		$pagesources{$page}=$file;
		if (! $pagemtime{$page}) {
			if (isinternal($page)) {
				push @internal_new, $file;
			}
			else {
				push @new, $file;
				if ($config{getctime} && -e "$config{srcdir}/$file") {
					eval {
						my $time=rcs_getctime("$config{srcdir}/$file");
						$pagectime{$page}=$time;
					};
					if ($@) {
						print STDERR $@;
					}
				}
			}
			$pagecase{lc $page}=$page;
			if (! exists $pagectime{$page}) {
				$pagectime{$page}=(srcfile_stat($file))[10];
			}
		}
	}

	return \@new, \@internal_new;
}

sub find_del_files ($) {
	my $pages=shift;
	my @del;
	my @internal_del;

	foreach my $page (keys %pagemtime) {
		if (! $pages->{$page}) {
			if (isinternal($page)) {
				push @internal_del, $pagesources{$page};
			}
			else {
				debug(sprintf(gettext("removing old page %s"), $page));
				push @del, $pagesources{$page};
			}
			$links{$page}=[];
			$renderedfiles{$page}=[];
			$pagemtime{$page}=0;
			foreach my $old (@{$oldrenderedfiles{$page}}) {
				prune($config{destdir}."/".$old);
			}
			delete $pagesources{$page};
			foreach my $source (keys %destsources) {
				if ($destsources{$source} eq $page) {
					delete $destsources{$source};
				}
			}
		}
	}

	return \@del, \@internal_del;
}

sub find_changed ($) {
	my $files=shift;
	my @changed;
	my @internal_changed;
	foreach my $file (@$files) {
		my $page=pagename($file);
		my ($srcfile, @stat)=srcfile_stat($file);
		if (! exists $pagemtime{$page} ||
		    $stat[9] > $pagemtime{$page} ||
	    	    $forcerebuild{$page}) {
			$pagemtime{$page}=$stat[9];

			if (isinternal($page)) {
				# Preprocess internal page in scan-only mode.
				preprocess($page, $page, readfile($srcfile), 1);
				push @internal_changed, $file;
			}
			else {
				push @changed, $file;
			}
		}
	}
	return \@changed, \@internal_changed;
}

sub calculate_old_links ($$) {
	my ($changed, $del)=@_;
	my %oldlink_targets;
	foreach my $file (@$changed, @$del) {
		my $page=pagename($file);
		if (exists $oldlinks{$page}) {
			foreach my $l (@{$oldlinks{$page}}) {
				$oldlink_targets{$page}{$l}=bestlink($page, $l);
			}
		}
	}
	return \%oldlink_targets;
}

sub derender_internal ($) {
	my $file=shift;
	my $page=pagename($file);
	delete $depends{$page};
	delete $depends_simple{$page};
	foreach my $old (@{$renderedfiles{$page}}) {
		delete $destsources{$old};
	}
	$renderedfiles{$page}=[];
}

sub render_linkers ($) {
	my $f=shift;
	my $p=pagename($f);
	foreach my $page (keys %{$backlinks{$p}}) {
		my $file=$pagesources{$page};
		render($file, sprintf(gettext("building %s, which links to %s"), $file, $p));
	}
}

sub remove_unrendered () {
	foreach my $src (keys %rendered) {
		my $page=pagename($src);
		foreach my $file (@{$oldrenderedfiles{$page}}) {
			if (! grep { $_ eq $file } @{$renderedfiles{$page}}) {
				debug(sprintf(gettext("removing %s, no longer built by %s"), $file, $page));
				prune($config{destdir}."/".$file);
			}
		}
	}
}

sub calculate_changed_links ($$$) {
	my ($changed, $del, $oldlink_targets)=@_;

	my (%backlinkchanged, %linkchangers);

	foreach my $file (@$changed, @$del) {
		my $page=pagename($file);

		if (exists $links{$page}) {
			foreach my $l (@{$links{$page}}) {
				my $target=bestlink($page, $l);
				if (! exists $oldlink_targets->{$page}{$l} ||
				    $target ne $oldlink_targets->{$page}{$l}) {
					$backlinkchanged{$target}=1;
					$linkchangers{lc($page)}=1;
				}
				delete $oldlink_targets->{$page}{$l};
			}
		}
		if (exists $oldlink_targets->{$page} &&
		    %{$oldlink_targets->{$page}}) {
			foreach my $target (values %{$oldlink_targets->{$page}}) {
				$backlinkchanged{$target}=1;
			}
			$linkchangers{lc($page)}=1;
		}
	}

	return \%backlinkchanged, \%linkchangers;
}

sub render_dependent ($$$$$$$) {
	my ($files, $new, $internal_new, $del, $internal_del,
		$internal_changed, $linkchangers)=@_;

	my @changed=(keys %rendered, @$del);
	my @exists_changed=(@$new, @$del);
	
	my %lc_changed = map { lc(pagename($_)) => 1 } @changed;
	my %lc_exists_changed = map { lc(pagename($_)) => 1 } @exists_changed;
	 
	foreach my $f (@$files) {
		next if $rendered{$f};
		my $p=pagename($f);
		my $reason = undef;
	
		if (exists $depends_simple{$p}) {
			foreach my $d (keys %{$depends_simple{$p}}) {
				if (($depends_simple{$p}{$d} & $IkiWiki::DEPEND_CONTENT &&
				     $lc_changed{$d})
				    ||
				    ($depends_simple{$p}{$d} & $IkiWiki::DEPEND_PRESENCE &&
				     $lc_exists_changed{$d})
			     	    ||
				    ($depends_simple{$p}{$d} & $IkiWiki::DEPEND_LINKS &&
				     $linkchangers->{$d})
		     		) {
					$reason = $d;
					last;
				}
			}
		}
	
		if (exists $depends{$p} && ! defined $reason) {
			foreach my $dep (keys %{$depends{$p}}) {
				my $sub=pagespec_translate($dep);
				next if $@ || ! defined $sub;

				# only consider internal files
				# if the page explicitly depends
				# on such files
				my $internal_dep=$dep =~ /internal\(/;

				my $in=sub {
					my $list=shift;
					my $type=shift;
					foreach my $file (@$list) {
						next if $file eq $f;
						my $page=pagename($file);
						if ($sub->($page, location => $p)) {
							if ($type == $IkiWiki::DEPEND_LINKS) {
								next unless $linkchangers->{lc($page)};
							}
							return $page;
						}
					}
					return undef;
				};

				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_CONTENT) {
					last if $reason =
						$in->(\@changed, $IkiWiki::DEPEND_CONTENT);
					last if $internal_dep && ($reason =
						$in->($internal_new, $IkiWiki::DEPEND_CONTENT) ||
						$in->($internal_del, $IkiWiki::DEPEND_CONTENT) ||
						$in->($internal_changed, $IkiWiki::DEPEND_CONTENT));
				}
				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_PRESENCE) {
					last if $reason = 
						$in->(\@exists_changed, $IkiWiki::DEPEND_PRESENCE);
					last if $internal_dep && ($reason =
						$in->($internal_new, $IkiWiki::DEPEND_PRESENCE) ||
						$in->($internal_del, $IkiWiki::DEPEND_PRESENCE));
				}
				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_LINKS) {
					last if $reason =
						$in->(\@changed, $IkiWiki::DEPEND_LINKS);
					last if $internal_dep && ($reason =
						$in->($internal_new, $IkiWiki::DEPEND_LINKS) ||
						$in->($internal_del, $IkiWiki::DEPEND_LINKS) ||
						$in->($internal_changed, $IkiWiki::DEPEND_LINKS));
				}
			}
		}
	
		if (defined $reason) {
			render($f, sprintf(gettext("building %s, which depends on %s"), $f, $reason));
			return 1;
		}
	}

	return 0;
}

sub render_backlinks ($) {
	my $backlinkchanged=shift;
	foreach my $link (keys %$backlinkchanged) {
		my $linkfile=$pagesources{$link};
		if (defined $linkfile) {
			render($linkfile, sprintf(gettext("building %s, to update its backlinks"), $linkfile));
		}
	}
}

sub refresh () {
	srcdir_check();
	run_hooks(refresh => sub { shift->() });
	my ($files, $pages)=find_src_files();
	my ($new, $internal_new)=find_new_files($files);
	my ($del, $internal_del)=find_del_files($pages);
	my ($changed, $internal_changed)=find_changed($files);
	run_hooks(needsbuild => sub { shift->($changed) });
	my $oldlink_targets=calculate_old_links($changed, $del);

	foreach my $file (@$changed) {
		scan($file);
	}

	calculate_links();

	foreach my $file (@$changed) {
		render($file, sprintf(gettext("building %s"), $file));
	}
	foreach my $file (@$internal_new, @$internal_del, @$internal_changed) {
		derender_internal($file);
	}

	my ($backlinkchanged, $linkchangers)=calculate_changed_links($changed,
		$del, $oldlink_targets);

	foreach my $file (@$new, @$del) {
		render_linkers($file);
	}
	
	if (@$changed || @$internal_changed ||
	    @$del || @$internal_del || @$internal_new) {
		1 while render_dependent($files, $new, $internal_new,
			$del, $internal_del, $internal_changed,
			$linkchangers);
	}

	render_backlinks($backlinkchanged);
	remove_unrendered();

	if (@$del) {
		run_hooks(delete => sub { shift->(@$del) });
	}
	if (%rendered) {
		run_hooks(change => sub { shift->(keys %rendered) });
	}
}

sub commandline_render () {
	lockwiki();
	loadindex();
	unlockwiki();

	my $srcfile=possibly_foolish_untaint($config{render});
	my $file=$srcfile;
	$file=~s/\Q$config{srcdir}\E\/?//;

	my $type=pagetype($file);
	die sprintf(gettext("ikiwiki: cannot build %s"), $srcfile)."\n" unless defined $type;
	my $content=readfile($srcfile);
	my $page=pagename($file);
	$pagesources{$page}=$file;
	$content=filter($page, $page, $content);
	$content=preprocess($page, $page, $content);
	$content=linkify($page, $page, $content);
	$content=htmlize($page, $page, $type, $content);
	$pagemtime{$page}=(stat($srcfile))[9];
	$pagectime{$page}=$pagemtime{$page} if ! exists $pagectime{$page};

	print genpage($page, $content);
	exit 0;
}

1
