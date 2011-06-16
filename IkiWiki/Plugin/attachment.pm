#!/usr/bin/perl
package IkiWiki::Plugin::attachment;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	add_underlay("attachment");
	add_underlay("javascript");
	add_underlay("jquery");
	hook(type => "getsetup", id => "attachment", call => \&getsetup);
	hook(type => "checkconfig", id => "attachment", call => \&checkconfig);
	hook(type => "formbuilder_setup", id => "attachment", call => \&formbuilder_setup);
	hook(type => "formbuilder", id => "attachment", call => \&formbuilder, last => 1);
	IkiWiki::loadplugin("filecheck");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
		allowed_attachments => {
			type => "pagespec",
			example => "virusfree() and mimetype(image/*) and maxsize(50kb)",
			description => "enhanced PageSpec specifying what attachments are allowed",
			link => "ikiwiki/PageSpec/attachment",
			safe => 1,
			rebuild => 0,
		},
		virus_checker => {
			type => "string",
			example => "clamdscan -",
			description => "virus checker program (reads STDIN, returns nonzero if virus found)",
			safe => 0, # executed
			rebuild => 0,
		},
}

sub check_canattach ($$;$) {
	my $session=shift;
	my $dest=shift; # where it's going to be put, under the srcdir
	my $file=shift; # the path to the attachment currently

	# Don't allow an attachment to be uploaded with the same name as an
	# existing page.
	if (exists $IkiWiki::pagesources{$dest} &&
	    $IkiWiki::pagesources{$dest} ne $dest) {
		error(sprintf(gettext("there is already a page named %s"), $dest));
	}

	# Use a special pagespec to test that the attachment is valid.
	my $allowed=1;
	if (defined $config{allowed_attachments} &&
	    length $config{allowed_attachments}) {
		$allowed=pagespec_match($dest,
			$config{allowed_attachments},
			file => $file,
			user => $session->param("name"),
			ip => $session->remote_addr(),
		);
	}

	if (! $allowed) {
		error(gettext("prohibited by allowed_attachments")." ($allowed)");
	}
	else {
		return 1;
	}
}

sub checkconfig () {
	$config{cgi_disable_uploads}=0;
}

sub formbuilder_setup (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	if (defined $form->field("do") && ($form->field("do") eq "edit" ||
	    $form->field("do") eq "create")) {
		# Add attachment field, set type to multipart.
		$form->enctype(&CGI::MULTIPART);
		$form->field(name => 'attachment', type => 'file');
		# These buttons are not put in the usual place, so
		# are not added to the normal formbuilder button list.
		$form->tmpl_param("field-upload" => '<input name="_submit" type="submit" value="Upload Attachment" />');
		$form->tmpl_param("field-link" => '<input name="_submit" type="submit" value="Insert Links" />');

		# Add all the javascript used by the attachments interface.
		require IkiWiki::Plugin::toggle;
		my $js=IkiWiki::Plugin::toggle::include_javascript($params{page});
		$js.='<link rel="stylesheet" href="'.urlto("ikiwiki/jquery-ui.min.css", $params{page}).'" id="theme">'."\n";
		my @jsfiles=qw{jquery.min jquery-ui.min
			jquery.tmpl.min jquery.iframe-transport
			jquery.fileupload jquery.fileupload-ui
		};
		foreach my $file (@jsfiles) {
			$js.='<script src="'.urlto("ikiwiki/$file.js", $params{page}).
			     '" type="text/javascript" charset="utf-8"></script>'."\n";
		}
		$form->tmpl_param("javascript" => $js);

		# Start with the attachments interface toggled invisible,
		# but if it was used, keep it open.
		if ($form->submitted ne "Upload Attachment" &&
		    (! defined $q->param("attachment_select") ||
		    ! length $q->param("attachment_select"))) {
			$form->tmpl_param("attachments-class" => "toggleable");
		}
		else {
			$form->tmpl_param("attachments-class" => "toggleable-open");
		}
		
		# Save attachments in holding area before previewing so
		# they can be seen in the preview.
		if ($form->submitted eq "Preview") {
			attachments_save($form, $params{session});
		}
	}
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};
	my $q=$params{cgi};

	return if ! defined $form->field("do") || ($form->field("do") ne "edit" && $form->field("do") ne "create") ;

	my $filename=Encode::decode_utf8($q->param('attachment'));
	if (defined $filename && length $filename) {
		attachment_store($filename, $form, $q, $params{session});
	}

	if ($form->submitted eq "Save Page") {
		attachments_save($form, $params{session});
	}

	if ($form->submitted eq "Insert Links") {
		my $page=quotemeta(Encode::decode_utf8($q->param("page")));
		my $add="";
		foreach my $f ($q->param("attachment_select")) {
			$f=Encode::decode_utf8($f);
			$f=~s/^$page\///;
			if (IkiWiki::isinlinableimage($f) &&
			    UNIVERSAL::can("IkiWiki::Plugin::img", "import")) {
				$add.='[[!img '.$f.' align="right" size="" alt=""]]';
			}
			else {
				$add.="[[$f]]";
			}
			$add.="\n";
		}
		$form->field(name => 'editcontent',
			value => $form->field('editcontent')."\n\n".$add,
			force => 1) if length $add;
	}
	
	# Generate the attachment list only after having added any new
	# attachments.
	$form->tmpl_param("attachment_list" => [attachment_list($form->field('page'))]);
}

sub attachment_holding_location {
	my $page=attachment_location(shift);

	my $dir=$config{wikistatedir}."/attachments/".
		IkiWiki::possibly_foolish_untaint(linkpage($page));
	$dir=~s/\/$//;
	return $dir;
}

sub is_held_attachment {
	my $attachment=shift;

	my $f=attachment_holding_location($attachment);
	if (-f $f) {
		return $f
	}
	else {
		return undef;
	}
}

# Stores the attachment in a holding area, not yet in the wiki proper.
sub attachment_store {
	my $filename=shift;
	my $form=shift;
	my $q=shift;
	my $session=shift;
	
	# This is an (apparently undocumented) way to get the name
	# of the temp file that CGI writes the upload to.
	my $tempfile=$q->tmpFileName($filename);
	if (! defined $tempfile || ! length $tempfile) {
		# perl 5.8 needs an alternative, awful method
		if ($q =~ /HASH/ && exists $q->{'.tmpfiles'}) {
			foreach my $key (keys(%{$q->{'.tmpfiles'}})) {
				$tempfile=$q->tmpFileName(\$key);
				last if defined $tempfile && length $tempfile;
			}
		}
		if (! defined $tempfile || ! length $tempfile) {
			error("CGI::tmpFileName failed to return the uploaded file name");
		}
	}

	$filename=IkiWiki::basename($filename);
	$filename=~s/.*\\+(.+)/$1/; # hello, windows
	$filename=IkiWiki::possibly_foolish_untaint(linkpage($filename));
	my $dest=attachment_holding_location($form->field('page'));
	
	# Check that the user is allowed to edit the attachment.
	my $final_filename=
		linkpage(IkiWiki::possibly_foolish_untaint(
			attachment_location($form->field('page')))).
		$filename;
	eval {
		if (IkiWiki::file_pruned($final_filename)) {
			error(gettext("bad attachment filename"));
		}
		IkiWiki::check_canedit($final_filename, $q, $session);
		# And that the attachment itself is acceptable.
		check_canattach($session, $final_filename, $tempfile);
	};
	if ($@) {
		json_response($q, $dest."/".$filename, $@);
		error $@;
	}

	# Move the attachment into holding directory.
	# Try to use a fast rename; fall back to copying.
	IkiWiki::prep_writefile($filename, $dest);
	unlink($dest."/".$filename);
	if (rename($tempfile, $dest."/".$filename)) {
		# The temp file has tight permissions; loosen up.
		chmod(0666 & ~umask, $dest."/".$filename);
	}
	else {
		my $fh=$q->upload('attachment');
		if (! defined $fh || ! ref $fh) {
			# needed by old CGI versions
			$fh=$q->param('attachment');
			if (! defined $fh || ! ref $fh) {
				# even that doesn't always work,
				# fall back to opening the tempfile
				$fh=undef;
				open($fh, "<", $tempfile) || error("failed to open \"$tempfile\": $!");
			}
		}
		binmode($fh);
		require IkiWiki::Render; 
		writefile($filename, $dest, undef, 1, sub {
			IkiWiki::fast_file_copy($tempfile, $filename, $fh, @_);
		});
	}

	json_response($q, $dest."/".$filename, stored_msg());
}

# Save all stored attachments for a page.
sub attachments_save {
	my $form=shift;
	my $session=shift;

	# Move attachments out of holding directory.
	my @attachments;
	my $dir=attachment_holding_location($form->field('page'));
	foreach my $filename (glob("$dir/*")) {
		next unless -f $filename;
		my $dest=$config{srcdir}."/".
			linkpage(IkiWiki::possibly_foolish_untaint(
				attachment_location($form->field('page')))).
			IkiWiki::basename($filename);
		unlink($dest);
		rename($filename, $dest);
		push @attachments, $dest;
	}
	return unless @attachments;
	require IkiWiki::Render;
	IkiWiki::prune($dir);

	# Check the attachments in and trigger a wiki refresh.
	if ($config{rcs}) {
		IkiWiki::rcs_add($_) foreach @attachments;
		IkiWiki::disable_commit_hook();
		IkiWiki::rcs_commit_staged(
			message => gettext("attachment upload"),
			session => $session,
		);
		IkiWiki::enable_commit_hook();
		IkiWiki::rcs_update();
	}
	IkiWiki::refresh();
	IkiWiki::saveindex();
}

sub attachment_location ($) {
	my $page=shift;
	
	# Put the attachment in a subdir of the page it's attached
	# to, unless that page is an "index" page.
	$page=~s/(^|\/)index//;
	$page.="/" if length $page;
	
	return $page;
}

sub attachment_list ($) {
	my $page=shift;
	my $loc=attachment_location($page);

	my $std=sub {
		my $file=shift;
		my $mtime=shift;
		my $date=shift;
		my $size=shift;

		name => $file,
		size => IkiWiki::Plugin::filecheck::humansize($size),
		mtime => $date,
		mtime_raw => $mtime,
	};

	# attachments already in the wiki
	my %attachments;
	foreach my $f (values %pagesources) {
		if (! defined pagetype($f) &&
		    $f=~m/^\Q$loc\E[^\/]+$/) {
			$attachments{$f}={
				$std->($f, $IkiWiki::pagemtime{$f}, displaytime($IkiWiki::pagemtime{$f}), (stat($f))[7]),
				link => htmllink($page, $page, $f, noimageinline => 1),
			};
		}
	}
	
	# attachments in holding directory
	my $dir=attachment_holding_location($page);
	my $heldmsg=gettext("this attachment is not yet saved");
	foreach my $file (glob("$dir/*")) {
		next unless -f $file;
		my $base=IkiWiki::basename($file);
		my $f=$loc.$base;
		$attachments{$f}={
			$std->($f, (stat($file))[9]*2, stored_msg(), (stat(_))[7]),
			link => $base,
		}
	}

	# Sort newer attachments to the end of the list.
	return sort { $a->{mtime_raw} <=> $b->{mtime_raw} || $a->{link} cmp $b->{link} }
		values %attachments;
}

sub stored_msg {
	gettext("just uploaded");
}

sub json_response ($$$) {
	my $q=shift;
	my $filename=shift;
	my $stored_msg=shift;

	# for the jquery file upload widget
	if ($q->Accept("application/json") >= 1.0 &&
	    grep { /application\/json/i } $q->Accept) {
		eval q{use JSON};
		error $@ if $@;
		print "Content-type: application/json\n\n";
		my $size=-s $filename;
		print to_json([
			{
				name => IkiWiki::basename($filename),
				size => $size,
				humansize => IkiWiki::Plugin::filecheck::humansize($size),
				stored_msg => $stored_msg,
				
			}
		]);
		exit 0;
	}
}

1
