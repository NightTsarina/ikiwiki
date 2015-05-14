#!/usr/bin/perl
# Copyright © 2006-2008 Joey Hess <joey@ikiwiki.info>
# Copyright © 2008 Simon McVittie <http://smcv.pseudorandom.co.uk/>
# Licensed under the GNU GPL, version 2, or any later version published by the
# Free Software Foundation
package IkiWiki::Plugin::comments;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

use constant PREVIEW => "Preview";
use constant POST_COMMENT => "Post comment";
use constant CANCEL => "Cancel";

my $postcomment;
my %commentstate;

sub import {
	hook(type => "checkconfig", id => 'comments',  call => \&checkconfig);
	hook(type => "getsetup", id => 'comments',  call => \&getsetup);
	hook(type => "preprocess", id => 'comment', call => \&preprocess,
		scan => 1);
	hook(type => "preprocess", id => 'commentmoderation', call => \&preprocess_moderation);
	# here for backwards compatability with old comments
	hook(type => "preprocess", id => '_comment', call => \&preprocess);
	hook(type => "sessioncgi", id => 'comment', call => \&sessioncgi);
	hook(type => "htmlize", id => "_comment", call => \&htmlize);
	hook(type => "htmlize", id => "_comment_pending",
		call => \&htmlize_pending);
	hook(type => "pagetemplate", id => "comments", call => \&pagetemplate);
	hook(type => "formbuilder_setup", id => "comments",
		call => \&formbuilder_setup);
	# Load goto to fix up user page links for logged-in commenters
	IkiWiki::loadplugin("goto");
	IkiWiki::loadplugin("inline");
	IkiWiki::loadplugin("transient");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "web",
		},
		comments_pagespec => {
			type => 'pagespec',
			example => 'blog/* and !*/Discussion',
			description => 'PageSpec of pages where comments are allowed',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 1,
		},
		comments_closed_pagespec => {
			type => 'pagespec',
			example => 'blog/controversial or blog/flamewar',
			description => 'PageSpec of pages where posting new comments is not allowed',
			link => 'ikiwiki/PageSpec',
			safe => 1,
			rebuild => 1,
		},
		comments_pagename => {
			type => 'string',
			default => 'comment_',
			description => 'Base name for comments, e.g. "comment_" for pages like "sandbox/comment_12"',
			safe => 0, # manual page moving required
			rebuild => undef,
		},
		comments_allowdirectives => {
			type => 'boolean',
			example => 0,
			description => 'Interpret directives in comments?',
			safe => 1,
			rebuild => 0,
		},
		comments_allowauthor => {
			type => 'boolean',
			example => 0,
			description => 'Allow anonymous commenters to set an author name?',
			safe => 1,
			rebuild => 0,
		},
		comments_commit => {
			type => 'boolean',
			example => 1,
			description => 'commit comments to the VCS',
			# old uncommitted comments are likely to cause
			# confusion if this is changed
			safe => 0,
			rebuild => 0,
		},
		comments_allowformats => {
			type => 'string',
			default => '',
			example => 'mdwn txt',
			description => 'Restrict formats for comments to (no restriction if empty)',
			safe => 1,
			rebuild => 0,
		},

}

sub checkconfig () {
	$config{comments_commit} = 1
		unless defined $config{comments_commit};
	if (! $config{comments_commit}) {
		$config{only_committed_changes}=0;
	}
	$config{comments_pagespec} = ''
		unless defined $config{comments_pagespec};
	$config{comments_closed_pagespec} = ''
		unless defined $config{comments_closed_pagespec};
	$config{comments_pagename} = 'comment_'
		unless defined $config{comments_pagename};
	$config{comments_allowformats} = ''
		unless defined $config{comments_allowformats};
}

sub htmlize {
	my %params = @_;
	return $params{content};
}

sub htmlize_pending {
	my %params = @_;
	return sprintf(gettext("this comment needs %s"),
		'<a href="'.
		IkiWiki::cgiurl(do => "commentmoderation").'">'.
		gettext("moderation").'</a>');
}

# FIXME: copied verbatim from meta
sub safeurl ($) {
	my $url=shift;
	if (exists $IkiWiki::Plugin::htmlscrubber::{safe_url_regexp} &&
	    defined $IkiWiki::Plugin::htmlscrubber::safe_url_regexp) {
		return $url=~/$IkiWiki::Plugin::htmlscrubber::safe_url_regexp/;
	}
	else {
		return 1;
	}
}

sub isallowed ($) {
    my $format = shift;
    return ! $config{comments_allowformats} || $config{comments_allowformats} =~ /\b$format\b/;
}

sub preprocess {
	my %params = @_;
	my $page = $params{page};

	my $format = $params{format};
	if (defined $format && (! exists $IkiWiki::hooks{htmlize}{$format} ||
				! isallowed($format))) {
		error(sprintf(gettext("unsupported page format %s"), $format));
	}

	my $content = $params{content};
	if (! defined $content) {
		error(gettext("comment must have content"));
	}
	$content =~ s/\\"/"/g;

	if (defined wantarray) {
		if ($config{comments_allowdirectives}) {
			$content = IkiWiki::preprocess($page, $params{destpage},
				$content);
		}

		# no need to bother with htmlize if it's just HTML
		$content = IkiWiki::htmlize($page, $params{destpage}, $format, $content)
			if defined $format;

		IkiWiki::run_hooks(sanitize => sub {
			$content = shift->(
				page => $page,
				destpage => $params{destpage},
				content => $content,
			);
		});
	}
	else {
		IkiWiki::preprocess($page, $params{destpage}, $content, 1);
	}

	# set metadata, possibly overriding [[!meta]] directives from the
	# comment itself

	my $commentuser;
	my $commentip;
	my $commentauthor;
	my $commentauthorurl;
	my $commentopenid;
	if (defined $params{username}) {
		$commentuser = $params{username};

		my $oiduser = eval { IkiWiki::openiduser($commentuser) };
		if (defined $oiduser) {
			# looks like an OpenID
			$commentauthorurl = $commentuser;
			$commentauthor = (defined $params{nickname} && length $params{nickname}) ? $params{nickname} : $oiduser;
			$commentopenid = $commentuser;
		}
		else {
			my $emailuser = IkiWiki::emailuser($commentuser);
			if (defined $emailuser) {
				$commentuser=$emailuser;
			}

			if (length $config{cgiurl}) {
				$commentauthorurl = IkiWiki::cgiurl(
					do => 'goto',
					page => IkiWiki::userpage($commentuser)
				);
			}

			$commentauthor = $commentuser;
		}
	}
	else {
		if (defined $params{ip}) {
			$commentip = $params{ip};
		}
		$commentauthor = gettext("Anonymous");
	}

	if ($config{comments_allowauthor}) {
		if (defined $params{claimedauthor}) {
			$commentauthor = $params{claimedauthor};
		}

		if (defined $params{url}) {
			my $url=$params{url};

			eval q{use URI::Heuristic}; 
			if (! $@) {
				$url=URI::Heuristic::uf_uristr($url);
			}

			if (safeurl($url)) {
				$commentauthorurl = $url;
			}
		}
	}

	$commentstate{$page}{commentuser} = $commentuser;
	$commentstate{$page}{commentopenid} = $commentopenid;
	$commentstate{$page}{commentip} = $commentip;
	$commentstate{$page}{commentauthor} = $commentauthor;
	$commentstate{$page}{commentauthorurl} = $commentauthorurl;
	$commentstate{$page}{commentauthoravatar} = $params{avatar};
	if (! defined $pagestate{$page}{meta}{author}) {
		$pagestate{$page}{meta}{author} = $commentauthor;
	}
	if (! defined $pagestate{$page}{meta}{authorurl}) {
		$pagestate{$page}{meta}{authorurl} = $commentauthorurl;
	}

	if (defined $params{subject}) {
		# decode title the same way meta does
		eval q{use HTML::Entities};
		$pagestate{$page}{meta}{title} = decode_entities($params{subject});
	}

	if ($params{page} =~ m/\/\Q$config{comments_pagename}\E\d+_/) {
		$pagestate{$page}{meta}{permalink} = urlto(IkiWiki::dirname($params{page})).
			"#".page_to_id($params{page});
	}

	eval q{use Date::Parse};
	if (! $@) {
		my $time = str2time($params{date});
		$IkiWiki::pagectime{$page} = $time if defined $time;
	}

	return $content;
}

sub preprocess_moderation {
	my %params = @_;

	$params{desc}=gettext("Comment Moderation")
		unless defined $params{desc};

	if (length $config{cgiurl}) {
		return '<a href="'.
			IkiWiki::cgiurl(do => 'commentmoderation').
			'">'.$params{desc}.'</a>';
	}
	else {
		return $params{desc};
	}
}

sub sessioncgi ($$) {
	my $cgi=shift;
	my $session=shift;

	my $do = $cgi->param('do');
	if ($do eq 'comment') {
		editcomment($cgi, $session);
	}
	elsif ($do eq 'commentmoderation') {
		commentmoderation($cgi, $session);
	}
	elsif ($do eq 'commentsignin') {
		IkiWiki::cgi_signin($cgi, $session);
		exit;
	}
}

# Mostly cargo-culted from IkiWiki::plugin::editpage
sub editcomment ($$) {
	my $cgi=shift;
	my $session=shift;

	IkiWiki::decode_cgi_utf8($cgi);

	eval q{use CGI::FormBuilder};
	error($@) if $@;

	my @buttons = (POST_COMMENT, PREVIEW, CANCEL);
	my $form = CGI::FormBuilder->new(
		fields => [qw{do sid page subject editcontent type author
			email url subscribe anonsubscribe}],
		charset => 'utf-8',
		method => 'POST',
		required => [qw{editcontent}],
		javascript => 0,
		params => $cgi,
		action => IkiWiki::cgiurl(),
		header => 0,
		table => 0,
		template => { template('editcomment.tmpl') },
	);

	IkiWiki::decode_form_utf8($form);
	IkiWiki::run_hooks(formbuilder_setup => sub {
			shift->(title => "comment", form => $form, cgi => $cgi,
				session => $session, buttons => \@buttons);
		});
	IkiWiki::decode_form_utf8($form);

	my $type = $form->param('type');
	if (defined $type && length $type && $IkiWiki::hooks{htmlize}{$type}) {
		$type = IkiWiki::possibly_foolish_untaint($type);
	}
	else {
		$type = $config{default_pageext};
	}


	my @page_types;
	if (exists $IkiWiki::hooks{htmlize}) {
		foreach my $key (grep { !/^_/ && isallowed($_) } keys %{$IkiWiki::hooks{htmlize}}) {
			push @page_types, [$key, $IkiWiki::hooks{htmlize}{$key}{longname} || $key];
		}
	}
	@page_types=sort @page_types;

	$form->field(name => 'do', type => 'hidden');
	$form->field(name => 'sid', type => 'hidden', value => $session->id,
		force => 1);
	$form->field(name => 'page', type => 'hidden');
	$form->field(name => 'subject', type => 'text', size => 72);
	$form->field(name => 'editcontent', type => 'textarea', rows => 10);
	$form->field(name => "type", value => $type, force => 1,
		type => 'select', options => \@page_types);

	my $username=$session->param('name');
	$form->tmpl_param(username => $username);
		
	$form->field(name => "subscribe", type => 'hidden');
	$form->field(name => "anonsubscribe", type => 'hidden');
	if (IkiWiki::Plugin::notifyemail->can("subscribe")) {
		if (defined $username) {
			$form->field(name => "subscribe", type => "checkbox",
				options => [gettext("email replies to me")]);
		}
		elsif (IkiWiki::Plugin::passwordauth->can("anonuser")) {
			$form->field(name => "anonsubscribe", type => "checkbox",
				options => [gettext("email replies to me")]);
		}
	}

	if ($config{comments_allowauthor} and
	    ! defined $session->param('name')) {
		$form->tmpl_param(allowauthor => 1);
		$form->field(name => 'author', type => 'text', size => '40');
		$form->field(name => 'email', type => 'text', size => '40');
		$form->field(name => 'url', type => 'text', size => '40');
	}
	else {
		$form->tmpl_param(allowauthor => 0);
		$form->field(name => 'author', type => 'hidden', value => '',
			force => 1);
		$form->field(name => 'email', type => 'hidden', value => '',
			force => 1);
		$form->field(name => 'url', type => 'hidden', value => '',
			force => 1);
	}

	if (! defined $session->param('name')) {
		# Make signinurl work and return here.
		$form->tmpl_param(signinurl => IkiWiki::cgiurl(do => 'commentsignin'));
		$session->param(postsignin => $ENV{QUERY_STRING});
		IkiWiki::cgi_savesession($session);
	}

	# The untaint is OK (as in editpage) because we're about to pass
	# it to file_pruned and wiki_file_regexp anyway.
	my ($page) = $form->field('page')=~/$config{wiki_file_regexp}/;
	$page = IkiWiki::possibly_foolish_untaint($page);
	if (! defined $page || ! length $page ||
		IkiWiki::file_pruned($page)) {
		error(gettext("bad page name"));
	}

	$form->title(sprintf(gettext("commenting on %s"),
			IkiWiki::pagetitle(IkiWiki::basename($page))));

	$form->tmpl_param('helponformattinglink',
		htmllink($page, $page, 'ikiwiki/formatting',
			noimageinline => 1,
			linktext => 'FormattingHelp'),
			allowdirectives => $config{allow_directives});

	if ($form->submitted eq CANCEL) {
		# bounce back to the page they wanted to comment on, and exit.
		IkiWiki::redirect($cgi, urlto($page));
		exit;
	}

	if (not exists $pagesources{$page}) {
		error(sprintf(gettext(
			"page '%s' doesn't exist, so you can't comment"),
			$page));
	}

	# There's no UI to get here, but someone might construct the URL,
	# leading to a comment that exists in the repository but isn't
	# shown
	if (!pagespec_match($page, $config{comments_pagespec},
		location => $page)) {
		error(sprintf(gettext(
			"comments on page '%s' are not allowed"),
			$page));
	}

	if (pagespec_match($page, $config{comments_closed_pagespec},
		location => $page)) {
		error(sprintf(gettext(
			"comments on page '%s' are closed"),
			$page));
	}

	# Set a flag to indicate that we're posting a comment,
	# so that postcomment() can tell it should match.
	$postcomment=1;
	IkiWiki::check_canedit($page, $cgi, $session);
	$postcomment=0;

	my $content = "[[!comment format=$type\n";

	if (defined $session->param('name')) {
		my $username = $session->param('name');
		$username =~ s/"/&quot;/g;
		$content .= " username=\"$username\"\n";
	}

	if (defined $session->param('nickname')) {
		my $nickname = $session->param('nickname');
		$nickname =~ s/"/&quot;/g;
		$content .= " nickname=\"$nickname\"\n";
	}

	if (!(defined $session->param('name') || defined $session->param('nickname')) &&
		defined $session->remote_addr()) {
		$content .= " ip=\"".$session->remote_addr()."\"\n";
	}

	if ($config{comments_allowauthor}) {
		my $author = $form->field('author');
		if (defined $author && length $author) {
			$author =~ s/"/&quot;/g;
			$content .= " claimedauthor=\"$author\"\n";
		}
		my $url = $form->field('url');
		if (defined $url && length $url) {
			$url =~ s/"/&quot;/g;
			$content .= " url=\"$url\"\n";
		}
	}

	my $avatar=getavatar($session->param('name'));
	if (defined $avatar && length $avatar) {
		$avatar =~ s/"/&quot;/g;
		$content .= " avatar=\"$avatar\"\n";
	}

	my $subject = $form->field('subject');
	if (defined $subject && length $subject) {
		$subject =~ s/"/&quot;/g;
	}
	else {
		$subject = "comment ".(num_comments($page, $config{srcdir}) + 1);
	}
	$content .= " subject=\"$subject\"\n";
	$content .= " date=\"" . commentdate() . "\"\n";

	my $editcontent = $form->field('editcontent');
	$editcontent="" if ! defined $editcontent;
	$editcontent =~ s/\r\n/\n/g;
	$editcontent =~ s/\r/\n/g;
	$editcontent =~ s/"/\\"/g;
	$content .= " content=\"\"\"\n$editcontent\n\"\"\"]]\n";

	my $location=unique_comment_location($page, $content, $config{srcdir});

	# This is essentially a simplified version of editpage:
	# - the user does not control the page that's created, only the parent
	# - it's always a create operation, never an edit
	# - this means that conflicts should never happen
	# - this means that if they do, rocks fall and everyone dies

	if ($form->submitted eq PREVIEW) {
		my $preview=previewcomment($content, $location, $page, time);
		IkiWiki::run_hooks(format => sub {
			$preview = shift->(page => $page,
				content => $preview);
		});
		$form->tmpl_param(page_preview => $preview);
	}
	else {
		$form->tmpl_param(page_preview => "");
	}

	if ($form->submitted eq POST_COMMENT && $form->validate) {
		IkiWiki::checksessionexpiry($cgi, $session);

		if (IkiWiki::Plugin::notifyemail->can("subscribe")) {
			my $subspec="comment($page)";
			if (defined $username &&
			    length $form->field("subscribe")) {
				IkiWiki::Plugin::notifyemail::subscribe(
					$username, $subspec);
			}
			elsif (length $form->field("email") &&
			       length $form->field("anonsubscribe")) {
				IkiWiki::Plugin::notifyemail::anonsubscribe(
					$form->field("email"), $subspec);
			}
		}
		
		$postcomment=1;
		my $ok=IkiWiki::check_content(content => $form->field('editcontent'),
			subject => $form->field('subject'),
			$config{comments_allowauthor} ? (
				author => $form->field('author'),
				url => $form->field('url'),
			) : (),
			page => $location,
			cgi => $cgi,
			session => $session,
			nonfatal => 1,
		);
		$postcomment=0;

		if (! $ok) {
			$location=unique_comment_location($page, $content, $IkiWiki::Plugin::transient::transientdir, "._comment_pending");
			writefile("$location._comment_pending", $IkiWiki::Plugin::transient::transientdir, $content);

			# Refresh so anything that deals with pending
			# comments can be updated.
			require IkiWiki::Render;
			IkiWiki::refresh();
			IkiWiki::saveindex();

			IkiWiki::printheader($session);
			print IkiWiki::cgitemplate($cgi, gettext(gettext("comment stored for moderation")),
				"<p>".
				gettext("Your comment will be posted after moderator review").
				"</p>");
			exit;
		}

		# FIXME: could probably do some sort of graceful retry
		# on error? Would require significant unwinding though
		my $file = "$location._comment";
		writefile($file, $config{srcdir}, $content);

		my $conflict;

		if ($config{rcs} and $config{comments_commit}) {
			my $message = gettext("Added a comment");
			if (defined $form->field('subject') &&
				length $form->field('subject')) {
				$message = sprintf(
					gettext("Added a comment: %s"),
					$form->field('subject'));
			}

			IkiWiki::rcs_add($file);
			IkiWiki::disable_commit_hook();
			$conflict = IkiWiki::rcs_commit_staged(
				message => $message,
				session => $session,
			);
			IkiWiki::enable_commit_hook();
			IkiWiki::rcs_update();
		}

		# Now we need a refresh
		require IkiWiki::Render;
		IkiWiki::refresh();
		IkiWiki::saveindex();

		# this should never happen, unless a committer deliberately
		# breaks it or something
		error($conflict) if defined $conflict;

		# Jump to the new comment on the page.
		# The trailing question mark tries to avoid broken
		# caches and get the most recent version of the page.
		IkiWiki::redirect($cgi, urlto($page).
			"?updated#".page_to_id($location));

	}
	else {
		IkiWiki::showform($form, \@buttons, $session, $cgi,
			page => $page);
	}

	exit;
}

sub commentdate () {
	strftime_utf8('%Y-%m-%dT%H:%M:%SZ', gmtime);
}

sub getavatar ($) {
	my $user=shift;
	return undef unless defined $user;

	my $avatar;
	eval q{use Libravatar::URL};
	if (! $@) {
		my $oiduser = eval { IkiWiki::openiduser($user) };
		my $https=defined $config{url} && $config{url}=~/^https:/;

		if (defined $oiduser) {
			eval {
				$avatar = libravatar_url(openid => $user, https => $https);
			}
		}
		if (! defined $avatar &&
		    (my $email = IkiWiki::userinfo_get($user, 'email'))) {
			eval {
				$avatar = libravatar_url(email => $email, https => $https);
			}
		}
	}
	return $avatar;
}


sub commentmoderation ($$) {
	my $cgi=shift;
	my $session=shift;

	IkiWiki::needsignin($cgi, $session);
	if (! IkiWiki::is_admin($session->param("name"))) {
		error(gettext("you are not logged in as an admin"));
	}

	IkiWiki::decode_cgi_utf8($cgi);
	
	if (defined $cgi->param('sid')) {
		IkiWiki::checksessionexpiry($cgi, $session);

		my $rejectalldefer=$cgi->param('rejectalldefer');

		my %vars=$cgi->Vars;
		my $added=0;
		foreach my $id (keys %vars) {
			if ($id =~ /(.*)\._comment(?:_pending)?$/) {
				$id=decode_utf8($id);
				my $action=$cgi->param($id);
				next if $action eq 'Defer' && ! $rejectalldefer;

				# Make sure that the id is of a legal
				# pending comment.
				my ($f) = $id =~ /$config{wiki_file_regexp}/;
				if (! defined $f || ! length $f ||
				    IkiWiki::file_pruned($f)) {
					error("illegal file");
				}

				my $page=IkiWiki::dirname($f);
				my $filedir=$IkiWiki::Plugin::transient::transientdir;
				my $file="$filedir/$f";
				if (! -e $file) {
					# old location
					$file="$config{srcdir}/$f";
					$filedir=$config{srcdir};
					if (! -e $file) {
						# older location
						$file="$config{wikistatedir}/comments_pending/".$f;
						$filedir="$config{wikistatedir}/comments_pending";
					}
				}

				if ($action eq 'Accept') {
					my $content=eval { readfile($file) };
					next if $@; # file vanished since form was displayed
					my $dest=unique_comment_location($page, $content, $config{srcdir})."._comment";
					writefile($dest, $config{srcdir}, $content);
					if ($config{rcs} and $config{comments_commit}) {
						IkiWiki::rcs_add($dest);
					}
					$added++;
				}

				require IkiWiki::Render;
				IkiWiki::prune($file, $filedir);
			}
		}

		if ($added) {
			my $conflict;
			if ($config{rcs} and $config{comments_commit}) {
				my $message = gettext("Comment moderation");
				IkiWiki::disable_commit_hook();
				$conflict=IkiWiki::rcs_commit_staged(
					message => $message,
					session => $session,
				);
				IkiWiki::enable_commit_hook();
				IkiWiki::rcs_update();
			}
		
			# Now we need a refresh
			require IkiWiki::Render;
			IkiWiki::refresh();
			IkiWiki::saveindex();
		
			error($conflict) if defined $conflict;
		}
	}

	my @comments=map {
		my ($id, $dir, $ctime)=@{$_};
		my $content=readfile("$dir/$id");
		my $preview=previewcomment($content, $id,
			$id, $ctime);
		{
			id => $id,
			view => $preview,
		}
	} sort { $b->[2] <=> $a->[2] } comments_pending();

	my $template=template("commentmoderation.tmpl");
	$template->param(
		sid => $session->id,
		comments => \@comments,
		cgiurl => IkiWiki::cgiurl(),
	);
	IkiWiki::printheader($session);
	my $out=$template->output;
	IkiWiki::run_hooks(format => sub {
		$out = shift->(page => "", content => $out);
	});
	print IkiWiki::cgitemplate($cgi, gettext("comment moderation"), $out);
	exit;
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	if ($form->title eq "preferences" &&
	    IkiWiki::is_admin($params{session}->param("name"))) {
		push @{$params{buttons}}, "Comment Moderation";
		if ($form->submitted && $form->submitted eq "Comment Moderation") {
			commentmoderation($params{cgi}, $params{session});
		}
	}
}

sub comments_pending () {
	my @ret;

	eval q{use File::Find};
	error($@) if $@;
	eval q{use Cwd};
	error($@) if $@;
	my $origdir=getcwd();

	my $find_comments=sub {
		my $dir=shift;
		my $extension=shift;
		return unless -d $dir;

		chdir($dir) || die "chdir $dir: $!";

		find({
			no_chdir => 1,
			wanted => sub {
				my $file=decode_utf8($_);
				$file=~s/^\.\///;
				return if ! length $file || IkiWiki::file_pruned($file)
					|| -l $_ || -d _ || $file !~ /\Q$extension\E$/;
				my ($f) = $file =~ /$config{wiki_file_regexp}/; # untaint
				if (defined $f) {
					my $ctime=(stat($_))[10];
					push @ret, [$f, $dir, $ctime];
				}
			}
		}, ".");

		chdir($origdir) || die "chdir $origdir: $!";
	};
	
	$find_comments->($IkiWiki::Plugin::transient::transientdir, "._comment_pending");
	# old location
	$find_comments->($config{srcdir}, "._comment_pending");
	# old location
	$find_comments->("$config{wikistatedir}/comments_pending/",
		"._comment");

	return @ret;
}

sub previewcomment ($$$) {
	my $content=shift;
	my $location=shift;
	my $page=shift;
	my $time=shift;

	# Previewing a comment should implicitly enable comment posting mode.
	my $oldpostcomment=$postcomment;
	$postcomment=1;

	my $preview = IkiWiki::htmlize($location, $page, '_comment',
			IkiWiki::linkify($location, $page,
			IkiWiki::preprocess($location, $page,
			IkiWiki::filter($location, $page, $content), 0, 1)));

	my $template = template("comment.tmpl");
	$template->param(content => $preview);
	$template->param(ctime => displaytime($time, undef, 1));
	$template->param(html5 => $config{html5});

	IkiWiki::run_hooks(pagetemplate => sub {
		shift->(page => $location,
			destpage => $page,
			template => $template);
	});

	$template->param(have_actions => 0);

	$postcomment=$oldpostcomment;

	return $template->output;
}

sub commentsshown ($) {
	my $page=shift;

	return pagespec_match($page, $config{comments_pagespec},
		location => $page);
}

sub commentsopen ($) {
	my $page = shift;

	return length $config{cgiurl} > 0 &&
	       (! length $config{comments_closed_pagespec} ||
	        ! pagespec_match($page, $config{comments_closed_pagespec},
	                         location => $page));
}

sub pagetemplate (@) {
	my %params = @_;

	my $page = $params{page};
	my $template = $params{template};
	my $shown = ($template->query(name => 'commentslink') ||
	             $template->query(name => 'commentsurl') ||
	             $template->query(name => 'atomcommentsurl') ||
	             $template->query(name => 'comments')) &&
	            commentsshown($page);

	if ($template->query(name => 'comments')) {
		my $comments = undef;
		if ($shown) {
			$comments = IkiWiki::preprocess_inline(
				pages => "comment($page) and !comment($page/*)",
				template => 'comment',
				show => 0,
				reverse => 'yes',
				page => $page,
				destpage => $params{destpage},
				feedfile => 'comments',
				emptyfeeds => 'no',
			);
		}

		if (defined $comments && length $comments) {
			$template->param(comments => $comments);
		}

		if ($shown && commentsopen($page)) {
			$template->param(addcommenturl => addcommenturl($page));
		}
	}

	if ($shown) {
		if ($template->query(name => 'commentsurl')) {
			$template->param(commentsurl =>
				urlto($page).'#comments');
		}

		if ($template->query(name => 'atomcommentsurl') && $config{usedirs}) {
			# This will 404 until there are some comments, but I
			# think that's probably OK...
			$template->param(atomcommentsurl =>
				urlto($page).'comments.atom');
		}

		if ($template->query(name => 'commentslink')) {
			my $num=num_comments($page, $config{srcdir});
			my $link;
			if ($num > 0) {
				$link = htmllink($page, $params{destpage}, $page,
					linktext => sprintf(ngettext("%i comment", "%i comments", $num), $num),
					anchor => "comments",
					noimageinline => 1
				);
			}
			elsif (commentsopen($page)) {
				$link = "<a href=\"".addcommenturl($page)."\">".
					#translators: Here "Comment" is a verb;
					#translators: the user clicks on it to
					#translators: post a comment.
					gettext("Comment").
					"</a>";
			}
			$template->param(commentslink => $link)
				if defined $link;
		}
	}

	# everything below this point is only relevant to the comments
	# themselves
	if (!exists $commentstate{$page}) {
		return;
	}
	
	if ($template->query(name => 'commentid')) {
		$template->param(commentid => page_to_id($page));
	}

	if ($template->query(name => 'commentuser')) {
		$template->param(commentuser =>
			$commentstate{$page}{commentuser});
	}

	if ($template->query(name => 'commentopenid')) {
		$template->param(commentopenid =>
			$commentstate{$page}{commentopenid});
	}

	if ($template->query(name => 'commentip')) {
		$template->param(commentip =>
			$commentstate{$page}{commentip});
	}

	if ($template->query(name => 'commentauthor')) {
		$template->param(commentauthor =>
			$commentstate{$page}{commentauthor});
	}

	if ($template->query(name => 'commentauthorurl')) {
		$template->param(commentauthorurl =>
			$commentstate{$page}{commentauthorurl});
	}

	if ($template->query(name => 'commentauthoravatar')) {
		$template->param(commentauthoravatar =>
			$commentstate{$page}{commentauthoravatar});
	}

	if ($template->query(name => 'removeurl') &&
	    IkiWiki::Plugin::remove->can("check_canremove") &&
	    length $config{cgiurl}) {
		$template->param(removeurl => IkiWiki::cgiurl(do => 'remove',
			page => $page));
		$template->param(have_actions => 1);
	}
}

sub addcommenturl ($) {
	my $page=shift;

	return IkiWiki::cgiurl(do => 'comment', page => $page);
}

sub num_comments ($$) {
	my $page=shift;
	my $dir=shift;

	my @comments=glob("$dir/$page/$config{comments_pagename}*._comment");
	return int @comments;
}

sub unique_comment_location ($$$;$) {
	my $page=shift;
	eval q{use Digest::MD5 'md5_hex'};
	error($@) if $@;
	my $content_md5=md5_hex(Encode::encode_utf8(shift));
	my $dir=shift;
	my $ext=shift || "._comment";

	my $location;
	my $i = num_comments($page, $dir);
	do {
		$i++;
		$location = "$page/$config{comments_pagename}${i}_${content_md5}";
	} while (-e "$dir/$location$ext");

	return $location;
}

sub page_to_id ($) {
	# Converts a comment page name into a unique, legal html id
	# attribute value, that can be used as an anchor to link to the
	# comment.
	my $page=shift;

	eval q{use Digest::MD5 'md5_hex'};
	error($@) if $@;

	return "comment-".md5_hex(Encode::encode_utf8(($page)));
}
	
package IkiWiki::PageSpec;

sub match_postcomment ($$;@) {
	my $page = shift;
	my $glob = shift;

	if (! $postcomment) {
		return IkiWiki::FailReason->new("not posting a comment");
	}
	return match_glob($page, $glob, @_);
}

sub match_comment ($$;@) {
	my $page = shift;
	my $glob = shift;

	if (! $postcomment) {
		# To see if it's a comment, check the source file type.
		# Deal with comments that were just deleted.
		my $source=exists $IkiWiki::pagesources{$page} ?
			$IkiWiki::pagesources{$page} :
			$IkiWiki::delpagesources{$page};
		my $type=defined $source ? IkiWiki::pagetype($source) : undef;
		if (! defined $type || $type ne "_comment") {
			return IkiWiki::FailReason->new("$page is not a comment");
		}
	}

	return match_glob($page, "$glob/*", internal => 1, @_);
}

sub match_comment_pending ($$;@) {
	my $page = shift;
	my $glob = shift;
	
	my $source=exists $IkiWiki::pagesources{$page} ?
		$IkiWiki::pagesources{$page} :
		$IkiWiki::delpagesources{$page};
	my $type=defined $source ? IkiWiki::pagetype($source) : undef;
	if (! defined $type || $type ne "_comment_pending") {
		return IkiWiki::FailReason->new("$page is not a pending comment");
	}

	return match_glob($page, "$glob/*", internal => 1, @_);
}

1
