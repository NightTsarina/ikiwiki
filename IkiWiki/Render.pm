#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;

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
	
	run_hooks(indexhtml => sub {
		shift->(page => $page, destpage => $page, content => $content);
	});

	my $templatefile;
	run_hooks(templatefile => sub {
		return if defined $templatefile;
		my $file=shift->(page => $page);
		if (defined $file && defined template_file($file)) {
			$templatefile=$file;
		}
	});
	my $template;
	if (defined $templatefile) {
		$template=template_depends($templatefile, $page,
			blind_cache => 1);
	}
	else {
		# no explicit depends as special case
		$template=template('page.tmpl', 
			blind_cache => 1);
	}

	my $actions=0;
	if (length $config{cgiurl}) {
		if (IkiWiki->can("cgi_editpage")) {
			$template->param(editurl => cgiurl(do => "edit", page => $page));
			$actions++;
		}
	}
	if (defined $config{historyurl} && length $config{historyurl}) {
		my $u=$config{historyurl};
		my $p=uri_escape_utf8($pagesources{$page}, '^A-Za-z0-9\-\._~/');
		$u=~s/\[\[file\]\]/$p/g;
		$template->param(historyurl => $u);
		$actions++;
	}
	if ($config{discussion}) {
		if ($page !~ /.*\/\Q$config{discussionpage}\E$/i &&
		   (length $config{cgiurl} ||
		    exists $links{$page."/".$config{discussionpage}})) {
			$template->param(discussionlink => htmllink($page, $page, $config{discussionpage}, noimageinline => 1, forcesubpage => 1));
			$actions++;
		}
	}
	if ($actions) {
		$template->param(have_actions => 1);
	}
	templateactions($template, $page);

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
		ctime => displaytime($pagectime{$page}, undef, 1),
		baseurl => baseurl($page),
		html5 => $config{html5},
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
		delete $typedlinks{$page};

		# Preprocess in scan-only mode.
		preprocess($page, $page, $content, 1);

		run_hooks(scan => sub {
			shift->(
				page => $page,
				content => $content,
			);
		});
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

sub prune ($;$) {
	my $file=shift;
	my $up_to=shift;

	unlink($file);
	my $dir=dirname($file);
	while ((! defined $up_to || $dir =~ m{^\Q$up_to\E\/}) && rmdir($dir)) {
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

# Finds all files in the srcdir, and the underlaydirs.
# Returns the files, and their corresponding pages.
#
# When run in only_underlay mode, adds only the underlay files to
# the files and pages passed in.
sub find_src_files (;$$$) {
	my $only_underlay=shift;
	my @files;
	if (defined $_[0]) {
		@files=@{shift()};
	}
	my %pages;
	if (defined $_[0]) {
		%pages=%{shift()};
	}

	eval q{use File::Find};
	error($@) if $@;

	eval q{use Cwd};
	die $@ if $@;
	my $origdir=getcwd();
	my $abssrcdir=Cwd::abs_path($config{srcdir});
	
	@IkiWiki::underlayfiles=();

	my ($page, $underlay);
	my $helper=sub {
		my $file=decode_utf8($_);

		return if -l $file || -d _;
		$file=~s/^\.\///;
		return if ! length $file;
		$page = pagename($file);
		if (! exists $pagesources{$page} &&
		    file_pruned($file)) {
			$File::Find::prune=1;
			return;
		}

		my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
		if (! defined $f) {
			warn(sprintf(gettext("skipping bad filename %s"), $file)."\n");
			return;
		}
	
		if ($underlay) {
			# avoid underlaydir override attacks; see security.mdwn
			if (! -l "$abssrcdir/$f" && ! -e _) {
				if (! $pages{$page}) {
					push @files, $f;
					push @IkiWiki::underlayfiles, $f;
					$pages{$page}=1;
				}
			}
		}
		else {
			push @files, $f;
			if ($pages{$page}) {
				debug(sprintf(gettext("%s has multiple possible source pages"), $page));
			}
			$pages{$page}=1;
		}
	};

	unless ($only_underlay) {
		chdir($config{srcdir}) || die "chdir $config{srcdir}: $!";
		find({
			no_chdir => 1,
			wanted => $helper,
		}, '.');
		chdir($origdir) || die "chdir $origdir: $!";
	}

	$underlay=1;
	foreach (@{$config{underlaydirs}}, $config{underlaydir}) {
		if (chdir($_)) {
			find({
				no_chdir => 1,
				wanted => $helper,
			}, '.');
			chdir($origdir) || die "chdir: $!";
		}
	};

	return \@files, \%pages;
}

# Given a hash of files that have changed, and a hash of files that were
# deleted, should return the same results as find_src_files, with the same
# sanity checks. But a lot faster!
sub process_changed_files ($$) {
	my $changed_raw=shift;
	my $deleted_raw=shift;

	my @files;
	my %pages;

	foreach my $file (keys %$changed_raw) {
		my $page = pagename($file);
		next if ! exists $pagesources{$page} && file_pruned($file);
		my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
		if (! defined $f) {
			warn(sprintf(gettext("skipping bad filename %s"), $file)."\n");
			next;
		}
		push @files, $f;
		if ($pages{$page}) {
			debug(sprintf(gettext("%s has multiple possible source pages"), $page));
		}
		$pages{$page}=1;
	}

	# So far, we only have the changed files. Now add in all the old
	# files that were not changed or deleted, excluding ones that came
	# from the underlay.
	my %old_underlay;
	foreach my $f (@IkiWiki::underlayfiles) {
		$old_underlay{$f}=1;
	}
	foreach my $page (keys %pagesources) {
		my $f=$pagesources{$page};
		unless ($old_underlay{$f} || exists $pages{$page} || exists $deleted_raw->{$f}) {
			$pages{$page}=1;
			push @files, $f;
		}
	}

	# add in the underlay
	find_src_files(1, \@files, \%pages);
}

sub find_new_files ($) {
	my $files=shift;
	my @new;
	my @internal_new;

	my $times_noted;

	foreach my $file (@$files) {
		my $page=pagename($file);

		if ($config{rcs} && $config{gettime} &&
		    -e "$config{srcdir}/$file") {
			if (! $times_noted) {
				debug(sprintf(gettext("querying %s for file creation and modification times.."), $config{rcs}));
				$times_noted=1;
			}

			eval {
				my $ctime=rcs_getctime($file);
				if ($ctime > 0) {
					$pagectime{$page}=$ctime;
				}
			};
			if ($@) {
				print STDERR $@;
			}
			my $mtime;
			eval {
				$mtime=rcs_getmtime($file);
			};
			if ($@) {
				print STDERR $@;
			}
			elsif ($mtime > 0) {
				utime($mtime, $mtime, "$config{srcdir}/$file");
			}
		}

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

	foreach my $page (keys %pagesources) {
		if (! $pages->{$page}) {
			if (isinternal($page)) {
				push @internal_del, $pagesources{$page};
			}
			else {
				push @del, $pagesources{$page};
			}
			$links{$page}=[];
			delete $typedlinks{$page};
			$renderedfiles{$page}=[];
			$pagemtime{$page}=0;
		}
	}

	return \@del, \@internal_del;
}

sub remove_del (@) {
	foreach my $file (@_) {
		my $page=pagename($file);
		if (! isinternal($page)) {
			debug(sprintf(gettext("removing obsolete %s"), $page));
		}
	
		foreach my $old (@{$oldrenderedfiles{$page}}) {
			prune($config{destdir}."/".$old, $config{destdir});
		}

		foreach my $source (keys %destsources) {
			if ($destsources{$source} eq $page) {
				delete $destsources{$source};
			}
		}
	
		delete $pagecase{lc $page};
		$delpagesources{$page}=$pagesources{$page};
		delete $pagesources{$page};
	}
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
				my $content = readfile($srcfile);

				# Preprocess internal page in scan-only mode.
				preprocess($page, $page, $content, 1);

				run_hooks(scan => sub {
					shift->(
						page => $page,
						content => $content,
					);
				});

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
				prune($config{destdir}."/".$file, $config{destdir});
			}
		}
	}
}

sub link_types_changed ($$) {
	# each is of the form { type => { link => 1 } }
	my $new = shift;
	my $old = shift;

	return 0 if !defined $new && !defined $old;
	return 1 if (!defined $new && %$old) || (!defined $old && %$new);

	while (my ($type, $links) = each %$new) {
		foreach my $link (keys %$links) {
			return 1 unless exists $old->{$type}{$link};
		}
	}

	while (my ($type, $links) = each %$old) {
		foreach my $link (keys %$links) {
			return 1 unless exists $new->{$type}{$link};
		}
	}

	return 0;
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

		# we currently assume that changing the type of a link doesn't
		# change backlinks
		if (!exists $linkchangers{lc($page)}) {
			if (link_types_changed($typedlinks{$page}, $oldtypedlinks{$page})) {
				$linkchangers{lc($page)}=1;
			}
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

	foreach my $p ("templates/page.tmpl", keys %{$depends_simple{""}}) {
		if ($rendered{$p} || grep { $_ eq $p } @$del) {
			foreach my $f (@$files) {
				next if $rendered{$f};
				render($f, sprintf(gettext("building %s, which depends on %s"), $f, $p));
			}
			return 0;
		}
	}
	 
	foreach my $f (@$files) {
		next if $rendered{$f};
		my $p=pagename($f);
		my $reason = undef;

		if (exists $depends_simple{$p} && ! defined $reason) {
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
				next unless defined $sub;

				# only consider internal files
				# if the page explicitly depends
				# on such files
				my $internal_dep=$dep =~ /(?:internal|comment|comment_pending)\(/;

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
							$reason=$page;
							return 1;
						}
					}
					return undef;
				};

				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_CONTENT) {
					last if $in->(\@changed, $IkiWiki::DEPEND_CONTENT);
					last if $internal_dep && (
						$in->($internal_new, $IkiWiki::DEPEND_CONTENT) ||
						$in->($internal_del, $IkiWiki::DEPEND_CONTENT) ||
						$in->($internal_changed, $IkiWiki::DEPEND_CONTENT)
					);
				}
				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_PRESENCE) {
					last if $in->(\@exists_changed, $IkiWiki::DEPEND_PRESENCE);
					last if $internal_dep && (
						$in->($internal_new, $IkiWiki::DEPEND_PRESENCE) ||
						$in->($internal_del, $IkiWiki::DEPEND_PRESENCE)
					);
				}
				if ($depends{$p}{$dep} & $IkiWiki::DEPEND_LINKS) {
					last if $in->(\@changed, $IkiWiki::DEPEND_LINKS);
					last if $internal_dep && (
						$in->($internal_new, $IkiWiki::DEPEND_LINKS) ||
						$in->($internal_del, $IkiWiki::DEPEND_LINKS) ||
						$in->($internal_changed, $IkiWiki::DEPEND_LINKS)
					);
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

sub gen_autofile ($$$) {
	my $autofile=shift;
	my $pages=shift;
	my $del=shift;

	if (file_pruned($autofile)) {
		return;
	}

	my ($file)="$config{srcdir}/$autofile" =~ /$config{wiki_file_regexp}/; # untaint
	if (! defined $file) {
		return;
	}

	# Remember autofiles that were tried, and never try them again later.
	if (exists $wikistate{$autofiles{$autofile}{plugin}}{autofile}{$autofile}) {
		return;
	}
	$wikistate{$autofiles{$autofile}{plugin}}{autofile}{$autofile}=1;

	if (srcfile($autofile, 1) || file_pruned($autofile)) {
		return;
	}
	
	if (-l $file || -d _ || -e _) {
		return;
	}

	my $page = pagename($file);
	if ($pages->{$page}) {
		return;
	}

	if (grep { $_ eq $autofile } @$del) {
		return;
	}

	$autofiles{$autofile}{generator}->();
	$pages->{$page}=1;
	return 1;
}

sub want_find_changes {
	$config{only_committed_changes} &&
	exists $IkiWiki::hooks{rcs}{rcs_find_changes} &&
	exists $IkiWiki::hooks{rcs}{rcs_get_current_rev}
}

sub refresh () {
	srcdir_check();
	run_hooks(refresh => sub { shift->() });
	my ($files, $pages, $new, $internal_new, $del, $internal_del, $changed, $internal_changed);
	if (! $config{rebuild} && want_find_changes() && defined $IkiWiki::lastrev) {
		my ($changed_raw, $del_raw);
		($changed_raw, $del_raw, $IkiWiki::lastrev) = $IkiWiki::hooks{rcs}{rcs_find_changes}{call}->($IkiWiki::lastrev);
		($files, $pages)=process_changed_files($changed_raw, $del_raw);
	}
	else {
		($files, $pages)=find_src_files();
	}
	if (want_find_changes()) {
		if (! defined($IkiWiki::lastrev)) {
			$IkiWiki::lastrev=$IkiWiki::hooks{rcs}{rcs_get_current_rev}{call}->();
		}
	}
	($new, $internal_new)=find_new_files($files);
	($del, $internal_del)=find_del_files($pages);
	($changed, $internal_changed)=find_changed($files);
	my %existingfiles;
	run_hooks(needsbuild => sub {
		my $ret=shift->($changed, [@$del, @$internal_del]);
		if (ref $ret eq 'ARRAY' && $ret != $changed) {
			if (! %existingfiles) {
				foreach my $f (@$files) {
					$existingfiles{$f}=1;
				}
			}
			@$changed=grep $existingfiles{$_}, @$ret;
		}
	});
	my $oldlink_targets=calculate_old_links($changed, $del);

	foreach my $file (@$changed) {
		scan($file);
	}

	foreach my $autofile (keys %autofiles) {
		if (gen_autofile($autofile, $pages, $del)) {
			push @{$files}, $autofile;
			push @{$new}, $autofile if find_new_files([$autofile]);
			push @{$changed}, $autofile if find_changed([$autofile]);
			
			scan($autofile);
		}
	}

	calculate_links();
	
	remove_del(@$del, @$internal_del);

	foreach my $file (@$changed) {
		render($file, sprintf(gettext("building %s"), $file));
	}
	foreach my $file (@$internal_new, @$internal_del, @$internal_changed) {
		derender_internal($file);
	}

	run_hooks(build_affected => sub {
		my %affected = shift->();
		while (my ($page, $message) = each %affected) {
			next unless exists $pagesources{$page};
			render($pagesources{$page}, $message);
		}
	});

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

	if (@$del || @$internal_del) {
		run_hooks(delete => sub { shift->(@$del, @$internal_del) });
	}
	if (%rendered) {
		run_hooks(rendered => sub { shift->(keys %rendered) });
		run_hooks(change => sub { shift->(keys %rendered) }); # back-compat
	}
	my %all_changed = map { $_ => 1 }
		@$new, @$changed, @$del,
		@$internal_new, @$internal_changed, @$internal_del;
	run_hooks(changes => sub { shift->(keys %all_changed) });
}

sub clean_rendered {
	lockwiki();
	loadindex();
	remove_unrendered();
	foreach my $page (keys %oldrenderedfiles) {
		foreach my $file (@{$oldrenderedfiles{$page}}) {
			prune($config{destdir}."/".$file, $config{destdir});
		}
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
