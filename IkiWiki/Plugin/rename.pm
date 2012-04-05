#!/usr/bin/perl
package IkiWiki::Plugin::rename;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "rename", call => \&getsetup);
	hook(type => "formbuilder_setup", id => "rename", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "rename", call => \&formbuilder);
	hook(type => "sessioncgi", id => "rename", call => \&sessioncgi);
	hook(type => "rename", id => "rename", call => \&rename_subpages);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
}

sub check_canrename ($$$$$$) {
	my $src=shift;
	my $srcfile=shift;
	my $dest=shift;
	my $destfile=shift;
	my $q=shift;
	my $session=shift;

	my $attachment=! defined pagetype($pagesources{$src});

	# Must be a known source file.
	if (! exists $pagesources{$src}) {
		error(sprintf(gettext("%s does not exist"),
			htmllink("", "", $src, noimageinline => 1)));
	}
	
	# Must exist on disk, and be a regular file.
	if (! -e "$config{srcdir}/$srcfile") {
		error(sprintf(gettext("%s is not in the srcdir, so it cannot be renamed"), $srcfile));
	}
	elsif (-l "$config{srcdir}/$srcfile" && ! -f _) {
		error(sprintf(gettext("%s is not a file"), $srcfile));
	}

	# Must be editable.
	IkiWiki::check_canedit($src, $q, $session);
	if ($attachment) {
		if (IkiWiki::Plugin::attachment->can("check_canattach")) {
			IkiWiki::Plugin::attachment::check_canattach($session, $src, "$config{srcdir}/$srcfile");
		}
		else {
			error("renaming of attachments is not allowed");
		}
	}
	
	# Dest checks can be omitted by passing undef.
	if (defined $dest) {
		if ($srcfile eq $destfile) {
			error(gettext("no change to the file name was specified"));
		}

		# Must be a legal filename.
		if (IkiWiki::file_pruned($destfile)) {
			error(sprintf(gettext("illegal name")));
		}

		# Must not be a known source file.
		if ($src ne $dest && exists $pagesources{$dest}) {
			error(sprintf(gettext("%s already exists"),
				htmllink("", "", $dest, noimageinline => 1)));
		}
	
		# Must not exist on disk already.
		if (-l "$config{srcdir}/$destfile" || -e _) {
			error(sprintf(gettext("%s already exists on disk"), $destfile));
		}
	
		# Must be editable.
		IkiWiki::check_canedit($dest, $q, $session);
		if ($attachment) {
			# Note that $srcfile is used here, not $destfile,
			# because it wants the current file, to check it.
			IkiWiki::Plugin::attachment::check_canattach($session, $dest, "$config{srcdir}/$srcfile");
		}
	}

	my $canrename;
	IkiWiki::run_hooks(canrename => sub {
		return if defined $canrename;
		my $ret=shift->(cgi => $q, session => $session,
			src => $src, srcfile => $srcfile,
			dest => $dest, destfile => $destfile);
		if (defined $ret) {
			if ($ret eq "") {
				$canrename=1;
			}
			elsif (ref $ret eq 'CODE') {
				$ret->();
				$canrename=0;
			}
			elsif (defined $ret) {
				error($ret);
				$canrename=0;
			}
		}
	});
	return defined $canrename ? $canrename : 1;
}

sub rename_form ($$$) {
	my $q=shift;
	my $session=shift;
	my $page=shift;

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $f = CGI::FormBuilder->new(
		name => "rename",
		title => sprintf(gettext("rename %s"), pagetitle($page)),
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		params => $q,
		action => IkiWiki::cgiurl(),
		stylesheet => 1,
		fields => [qw{do page new_name attachment}],
	);
	
	$f->field(name => "do", type => "hidden", value => "rename", force => 1);
	$f->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$f->field(name => "page", type => "hidden", value => $page, force => 1);
	$f->field(name => "new_name", value => pagetitle($page, 1), size => 60);
	if (!$q->param("attachment")) {
		# insert the standard extensions
		my @page_types;
		if (exists $IkiWiki::hooks{htmlize}) {
			foreach my $key (grep { !/^_/ } keys %{$IkiWiki::hooks{htmlize}}) {
				push @page_types, [$key, $IkiWiki::hooks{htmlize}{$key}{longname} || $key];
			}
		}
		@page_types=sort @page_types;
	
		# make sure the current extension is in the list
		my ($ext) = $pagesources{$page}=~/\.([^.]+)$/;
		if (! $IkiWiki::hooks{htmlize}{$ext}) {
			unshift(@page_types, [$ext, $ext]);
		}
	
		$f->field(name => "type", type => 'select',
			options => \@page_types,
			value => $ext, force => 1);
		
		foreach my $p (keys %pagesources) {
			if ($pagesources{$p}=~m/^\Q$page\E\//) {
				$f->field(name => "subpages",
					label => "",
					type => "checkbox",
					options => [ [ 1 => gettext("Also rename SubPages and attachments") ] ],
					value => 1,
					force => 1);
				last;
			}
		}
	}
	$f->field(name => "attachment", type => "hidden");

	return $f, ["Rename", "Cancel"];
}

sub rename_start ($$$$) {
	my $q=shift;
	my $session=shift;
	my $attachment=shift;
	my $page=shift;

	# Special case for renaming held attachments; normal checks
	# don't apply.
	my $held=$attachment &&
		IkiWiki::Plugin::attachment->can("is_held_attachment") &&
		IkiWiki::Plugin::attachment::is_held_attachment($page);
	if (! $held) {
		check_canrename($page, $pagesources{$page}, undef, undef,
			$q, $session);
	}

   	# Save current form state to allow returning to it later
	# without losing any edits.
	# (But don't save what button was submitted, to avoid
	# looping back to here.)
	# Note: "_submit" is CGI::FormBuilder internals.
	$q->param(-name => "_submit", -value => "");
	$session->param(postrename => scalar $q->Vars);
	IkiWiki::cgi_savesession($session);
	
	if (defined $attachment) {
		$q->param(-name => "attachment", -value => $attachment);
	}
	my ($f, $buttons)=rename_form($q, $session, $page);
	IkiWiki::showform($f, $buttons, $session, $q);
	exit 0;
}

sub postrename ($$$;$$) {
	my $cgi=shift;
	my $session=shift;
	my $src=shift;
	my $dest=shift;
	my $attachment=shift;

	# Load saved form state and return to edit page.
	my $postrename=CGI->new($session->param("postrename"));
	$session->clear("postrename");
	IkiWiki::cgi_savesession($session);
	if (! defined $postrename) {
		redirect($cgi, urlto(defined $dest ? $dest : $src));
	}

	if (defined $dest) {
		if (! $attachment) {
			# They renamed the page they were editing. This requires
			# fixups to the edit form state.
			# Tweak the edit form to be editing the new page.
			$postrename->param("page", $dest);
		}

		# Update edit form content to fix any links present
		# on it.
		$postrename->param("editcontent",
			renamepage_hook($dest, $src, $dest,
				 $postrename->param("editcontent")));

		# Get a new edit token; old was likely invalidated.
		$postrename->param("rcsinfo",
			IkiWiki::rcs_prepedit($pagesources{$dest}));
	}

	IkiWiki::cgi_editpage($postrename, $session);
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};

	if (defined $form->field("do") && ($form->field("do") eq "edit" ||
	    $form->field("do") eq "create")) {
    		IkiWiki::decode_form_utf8($form);
		my $q=$params{cgi};
		my $session=$params{session};

		if ($form->submitted eq "Rename" && $form->field("do") eq "edit") {
			rename_start($q, $session, 0, $form->field("page"));
		}
		elsif ($form->submitted eq "Rename Attachment") {
			my @selected=map { Encode::decode_utf8($_) } $q->param("attachment_select");
			if (@selected > 1) {
				error(gettext("Only one attachment can be renamed at a time."));
			}
			elsif (! @selected) {
				error(gettext("Please select the attachment to rename."))
			}
			rename_start($q, $session, 1, $selected[0]);
		}
	}
}

my $renamesummary;

sub formbuilder_setup (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && ($form->field("do") eq "edit" ||
	    $form->field("do") eq "create")) {
		# Rename button for the page, and also for attachments.
		push @{$params{buttons}}, "Rename" if $form->field("do") eq "edit";
		$form->tmpl_param("field-rename" => '<input name="_submit" type="submit" value="Rename Attachment" />');

		if (defined $renamesummary) {
			$form->tmpl_param(message => $renamesummary);
		}
	}
}

sub sessioncgi ($$) {
        my $q=shift;

	if ($q->param("do") eq 'rename') {
        	my $session=shift;
		my ($form, $buttons)=rename_form($q, $session, Encode::decode_utf8($q->param("page")));
		IkiWiki::decode_form_utf8($form);
		my $src=$form->field("page");

		if ($form->submitted eq 'Cancel') {
			postrename($q, $session, $src);
		}
		elsif ($form->submitted eq 'Rename' && $form->validate) {
			IkiWiki::checksessionexpiry($q, $session, $q->param('sid'));

			# These untaints are safe because of the checks
			# performed in check_canrename later.
			my $srcfile=IkiWiki::possibly_foolish_untaint($pagesources{$src})
				if exists $pagesources{$src};
			my $dest=IkiWiki::possibly_foolish_untaint(titlepage($form->field("new_name")));
			my $destfile=$dest;
			if (! $q->param("attachment")) {
				my $type=$q->param('type');
				if (defined $type && length $type && $IkiWiki::hooks{htmlize}{$type}) {
					$type=IkiWiki::possibly_foolish_untaint($type);
				}
				else {
					my ($ext)=$srcfile=~/\.([^.]+)$/;
					$type=$ext;
				}
				
				$destfile=newpagefile($dest, $type);
			}
		
			# Special case for renaming held attachments.
			my $held=$q->param("attachment") &&
				IkiWiki::Plugin::attachment->can("is_held_attachment") &&
				IkiWiki::Plugin::attachment::is_held_attachment($src);
			if ($held) {
				rename($held, IkiWiki::Plugin::attachment::attachment_holding_location($dest));
				postrename($q, $session, $src, $dest, $q->param("attachment"))
					unless defined $srcfile;
			}
			
			# Queue of rename actions to perfom.
			my @torename;
			push @torename, {
				src => $src,
			       	srcfile => $srcfile,
				dest => $dest,
			       	destfile => $destfile,
				required => 1,
			};

			@torename=rename_hook(
				torename => \@torename,
				done => {},
				cgi => $q,
				session => $session,
			);

			require IkiWiki::Render;
			IkiWiki::disable_commit_hook() if $config{rcs};
			my %origpagesources=%pagesources;

			# First file renaming.
			foreach my $rename (@torename) {
				if ($rename->{required}) {
					do_rename($rename, $q, $session);
				}
				else {
					eval {do_rename($rename, $q, $session)};
					if ($@) {
						$rename->{error}=$@;
						next;
					}
				}

				# Temporarily tweak pagesources to point to
				# the renamed file, in case fixlinks needs
				# to edit it.
				$pagesources{$rename->{src}}=$rename->{destfile};
			}
			IkiWiki::rcs_commit_staged(
				message => sprintf(gettext("rename %s to %s"), $srcfile, $destfile),
				session => $session,
			) if $config{rcs};

			# Then link fixups.
			foreach my $rename (@torename) {
				next if $rename->{src} eq $rename->{dest};
				next if $rename->{error};
				foreach my $p (fixlinks($rename, $session)) {
					# map old page names to new
					foreach my $r (@torename) {
						next if $rename->{error};
						if ($r->{src} eq $p) {
							$p=$r->{dest};
							last;
						}
					}
					push @{$rename->{fixedlinks}}, $p;
				}
			}

			# Then refresh.
			%pagesources=%origpagesources;
			if ($config{rcs}) {
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
			IkiWiki::refresh();
			IkiWiki::saveindex();

			# Find pages with remaining, broken links.
			foreach my $rename (@torename) {
				next if $rename->{src} eq $rename->{dest};
				
				foreach my $page (keys %links) {
					my $broken=0;
					foreach my $link (@{$links{$page}}) {
						my $bestlink=bestlink($page, $link);
						if ($bestlink eq $rename->{src}) {
							push @{$rename->{brokenlinks}}, $page;
							last;
						}
					}
				}
			}

			# Generate a summary, that will be shown at the top
			# of the edit template.
			$renamesummary="";
			foreach my $rename (@torename) {
				my $template=template("renamesummary.tmpl");
				$template->param(src => $rename->{srcfile});
				$template->param(dest => $rename->{destfile});
				$template->param(error => $rename->{error});
				if ($rename->{src} ne $rename->{dest}) {
					$template->param(brokenlinks_checked => 1);
					$template->param(brokenlinks => linklist($rename->{dest}, $rename->{brokenlinks}));
					$template->param(fixedlinks => linklist($rename->{dest}, $rename->{fixedlinks}));
				}
				$renamesummary.=$template->output;
			}

			postrename($q, $session, $src, $dest, $q->param("attachment"));
		}
		else {
			IkiWiki::showform($form, $buttons, $session, $q);
		}

		exit 0;
	}
}

# Add subpages to the list of pages to be renamed, if needed.
sub rename_subpages (@) {
	my %params = @_;

	my %torename = %{$params{torename}};
	my $q = $params{cgi};
	my $src = $torename{src};
	my $srcfile = $torename{src};
	my $dest = $torename{dest};
	my $destfile = $torename{dest};

	return () unless ($q->param("subpages") && $src ne $dest);

	my @ret;
	foreach my $p (keys %pagesources) {
		next unless $pagesources{$p}=~m/^\Q$src\E\//;
		# If indexpages is enabled, the srcfile should not be confused
		# with a subpage.
		next if $pagesources{$p} eq $srcfile;

		my $d=$pagesources{$p};
		$d=~s/^\Q$src\E\//$dest\//;
		push @ret, {
			src => $p,
			srcfile => $pagesources{$p},
			dest => pagename($d),
			destfile => $d,
			required => 0,
		};
	}
	return @ret;
}

sub linklist {
	# generates a list of links in a form suitable for FormBuilder
	my $dest=shift;
	my $list=shift;
	# converts a list of pages into a list of links
	# in a form suitable for FormBuilder.

	[map {
		{
			page => htmllink($dest, $dest, $_,
					noimageinline => 1,
					linktext => pagetitle($_),
				)
		}
	} @{$list}]
}

sub renamepage_hook ($$$$) {
	my ($page, $src, $dest, $content)=@_;

	IkiWiki::run_hooks(renamepage => sub {
		$content=shift->(
			page => $page,
			oldpage => $src,
			newpage => $dest,
			content => $content,
		);
	});

	return $content;
}

sub rename_hook {
	my %params = @_;

	my @torename=@{$params{torename}};
	my %done=%{$params{done}};
	my $q=$params{cgi};
	my $session=$params{session};

	return () unless @torename;

	my @nextset;
	foreach my $torename (@torename) {
		unless (exists $done{$torename->{src}} && $done{$torename->{src}}) {
			IkiWiki::run_hooks(rename => sub {
				push @nextset, shift->(
					torename => $torename,
					cgi => $q,
					session => $session,
				);
			});
			$done{$torename->{src}}=1;
		}
	}

	push @torename, rename_hook(
		torename => \@nextset,
		done => \%done,
		cgi => $q,
		session => $session,
	);

	# dedup
	my %seen;
	return grep { ! $seen{$_->{src}}++ } @torename;
}

sub do_rename ($$$) {
	my $rename=shift;
	my $q=shift;
	my $session=shift;

	# First, check if this rename is allowed.
	check_canrename($rename->{src},
		$rename->{srcfile},
		$rename->{dest},
		$rename->{destfile},
		$q, $session);

	# Ensure that the dest directory exists and is ok.
	IkiWiki::prep_writefile($rename->{destfile}, $config{srcdir});

	if ($config{rcs}) {
		IkiWiki::rcs_rename($rename->{srcfile}, $rename->{destfile});
	}
	else {
		if (! rename($config{srcdir}."/".$rename->{srcfile},
		             $config{srcdir}."/".$rename->{destfile})) {
			error("rename: $!");
		}
	}

}

sub fixlinks ($$$) {
	my $rename=shift;
	my $session=shift;

	my @fixedlinks;

	foreach my $page (keys %links) {
		my $needfix=0;
		foreach my $link (@{$links{$page}}) {
			my $bestlink=bestlink($page, $link);
			if ($bestlink eq $rename->{src}) {
				$needfix=1;
				last;
			}
		}
		if ($needfix) {
			my $file=$pagesources{$page};
			next unless -e $config{srcdir}."/".$file;
			my $oldcontent=readfile($config{srcdir}."/".$file);
			my $content=renamepage_hook($page, $rename->{src}, $rename->{dest}, $oldcontent);
			if ($oldcontent ne $content) {
				my $token=IkiWiki::rcs_prepedit($file);
				eval { writefile($file, $config{srcdir}, $content) };
				next if $@;
				my $conflict=IkiWiki::rcs_commit(
					file => $file,
					message => sprintf(gettext("update for rename of %s to %s"), $rename->{srcfile}, $rename->{destfile}),
					token => $token,
					session => $session,
				);
				push @fixedlinks, $page if ! defined $conflict;
			}
		}
	}

	return @fixedlinks;
}

1
