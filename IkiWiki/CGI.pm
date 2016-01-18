#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use IkiWiki;
use IkiWiki::UserInfo;
use open qw{:utf8 :std};
use Encode;

sub printheader ($) {
	my $session=shift;
	
	if (($ENV{HTTPS} && lc $ENV{HTTPS} ne "off") || $config{sslcookie}) {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-httponly => 1, -secure => 1));
	}
	else {
		print $session->header(-charset => 'utf-8',
			-cookie => $session->cookie(-httponly => 1));
	}
}

sub prepform {
	my $form=shift;
	my $buttons=shift;
	my $session=shift;
	my $cgi=shift;

	if (exists $hooks{formbuilder}) {
		run_hooks(formbuilder => sub {
			shift->(form => $form, cgi => $cgi, session => $session,
				buttons => $buttons);
		});
	}

	return $form;
}

sub showform ($$$$;@) {
	my $form=prepform(@_);
	shift;
	my $buttons=shift;
	my $session=shift;
	my $cgi=shift;

	printheader($session);
	print cgitemplate($cgi, $form->title,
		$form->render(submit => $buttons), @_);
}

sub cgitemplate ($$$;@) {
	my $cgi=shift;
	my $title=shift;
	my $content=shift;
	my %params=@_;
	
	my $template=template("page.tmpl");

	my $topurl = $config{url};
	if (defined $cgi && ! $config{w3mmode} && ! $config{reverse_proxy}) {
		$topurl = $cgi->url;
	}

	my $page="";
	if (exists $params{page}) {
		$page=delete $params{page};
		$params{forcebaseurl}=urlto($page);
	}
	run_hooks(pagetemplate => sub {
		shift->(
			page => $page,
			destpage => $page,
			template => $template,
		);
	});
	templateactions($template, "");

	my $baseurl = baseurl();

	$template->param(
		dynamic => 1,
		title => $title,
		wikiname => $config{wikiname},
		content => $content,
		baseurl => $baseurl,
		html5 => $config{html5},
		%params,
	);
	
	return $template->output;
}

sub redirect ($$) {
	my $q=shift;
	eval q{use URI};

	my $topurl;
	if (defined $q && ! $config{w3mmode} && ! $config{reverse_proxy}) {
		$topurl = $q->url;
	}

	my $url=URI->new(urlabs(shift, $topurl));
	if (! $config{w3mmode}) {
		print $q->redirect($url);
	}
	else {
		print "Content-type: text/plain\n";
		print "W3m-control: GOTO $url\n\n";
	}
}

sub decode_cgi_utf8 ($) {
	# decode_form_utf8 method is needed for 5.01
	if ($] < 5.01) {
		my $cgi = shift;
		foreach my $f ($cgi->param) {
			$cgi->param($f, map { decode_utf8 $_ }
				@{$cgi->param_fetch($f)});
		}
	}
}

sub safe_decode_utf8 ($) {
    my $octets = shift;
    if (!Encode::is_utf8($octets)) {
        return decode_utf8($octets);
    }
    else {
        return $octets;
    }
}

sub decode_form_utf8 ($) {
	if ($] >= 5.01) {
		my $form = shift;
		foreach my $f ($form->field) {
			my @value=map { safe_decode_utf8($_) } $form->field($f);
			$form->field(name  => $f,
			             value => \@value,
		                     force => 1,
			);
		}
	}
}

# Check if the user is signed in. If not, redirect to the signin form and
# save their place to return to later.
sub needsignin ($$) {
	my $q=shift;
	my $session=shift;

	if (! defined $session->param("name") ||
	    ! userinfo_get($session->param("name"), "regdate")) {
		$session->param(postsignin => $q->query_string);
		cgi_signin($q, $session);
		cgi_savesession($session);
		exit;
	}
}

sub cgi_signin ($$;$) {
	my $q=shift;
	my $session=shift;
	my $returnhtml=shift;

	decode_cgi_utf8($q);
	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "signin",
		name => "signin",
		charset => "utf-8",
		method => 'POST',
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => cgiurl(),
		header => 0,
		template => {type => 'div'},
		stylesheet => 1,
	);
	my $buttons=["Login"];
	
	$form->field(name => "do", type => "hidden", value => "signin",
		force => 1);
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);

	if ($form->submitted) {
		$form->validate;
	}

	if ($returnhtml) {
		$form=prepform($form, $buttons, $session, $q);
		return $form->render(submit => $buttons);
	}

	showform($form, $buttons, $session, $q);
}

sub cgi_postsignin ($$) {
	my $q=shift;
	my $session=shift;
	
	# Continue with whatever was being done before the signin process.
	if (defined $session->param("postsignin")) {
		my $postsignin=CGI->new($session->param("postsignin"));
		$session->clear("postsignin");
		cgi($postsignin, $session);
		cgi_savesession($session);
		exit;
	}
	else {
		if ($config{sslcookie} && ! $q->https()) {
			error(gettext("probable misconfiguration: sslcookie is set, but you are attempting to login via http, not https"));
		}
		else {
			error(gettext("login failed, perhaps you need to turn on cookies?"));
		}
	}
}

sub cgi_prefs ($$) {
	my $q=shift;
	my $session=shift;

	needsignin($q, $session);
	decode_cgi_utf8($q);
	
	# The session id is stored on the form and checked to
	# guard against CSRF.
	my $sid=$q->param('sid');
	if (! defined $sid) {
		$q->delete_all;
	}
	elsif ($sid ne $session->id) {
		error(gettext("Your login session has expired."));
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;
	my $form = CGI::FormBuilder->new(
		title => "preferences",
		name => "preferences",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		validate => {
			email => 'EMAIL',
		},
		required => 'NONE',
		javascript => 0,
		params => $q,
		action => cgiurl(),
		template => {type => 'div'},
		stylesheet => 1,
		fieldsets => [
			[login => gettext("Login")],
			[preferences => gettext("Preferences")],
			[admin => gettext("Admin")]
		],
	);
	my $buttons=["Save Preferences", "Logout", "Cancel"];
	
	decode_form_utf8($form);
	run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $q, session => $session,
		        buttons => $buttons);
	});
	decode_form_utf8($form);
	
	$form->field(name => "do", type => "hidden", value => "prefs",
		force => 1);
	$form->field(name => "sid", type => "hidden", value => $session->id,
		force => 1);
	$form->field(name => "email", size => 50, fieldset => "preferences");
	
	my $user_name=$session->param("name");

	if (! $form->submitted) {
		$form->field(name => "email", force => 1,
			value => userinfo_get($user_name, "email"));
	}
	
	if ($form->submitted eq 'Logout') {
		$session->delete();
		redirect($q, baseurl(undef));
		return;
	}
	elsif ($form->submitted eq 'Cancel') {
		redirect($q, baseurl(undef));
		return;
	}
	elsif ($form->submitted eq 'Save Preferences' && $form->validate) {
		if (defined $form->field('email')) {
			userinfo_set($user_name, 'email', $form->field('email')) ||
				error("failed to set email");
		}

		$form->text(gettext("Preferences saved."));
	}
	
	showform($form, $buttons, $session, $q,
		prefsurl => "", # avoid showing the preferences link
	);
}

sub cgi_custom_failure ($$$) {
	my $q=shift;
	my $httpstatus=shift;
	my $message=shift;

	print $q->header(
		-status => $httpstatus,
		-charset => 'utf-8',
	);
	print $message;

	# Internet Explod^Hrer won't show custom 404 responses
	# unless they're >= 512 bytes
	print ' ' x 512;

	exit;
}

sub check_banned ($$) {
	my $q=shift;
	my $session=shift;

	my $banned=0;
	my $name=$session->param("name");
	my $cloak=cloak($name) if defined $name;
	if (defined $name && 
	    grep { $name eq $_ || $cloak eq $_ } @{$config{banned_users}}) {
		$banned=1;
	}

	foreach my $b (@{$config{banned_users}}) {
		if (pagespec_match("", $b,
			ip => $session->remote_addr(),
			name => defined $name ? $name : "")
		   || pagespec_match("", $b,
		   	ip => cloak($session->remote_addr()),
			name => defined $cloak ? $cloak : "")) {
			$banned=1;
			last;
		}
	}

	if ($banned) {
		$session->delete();
		cgi_savesession($session);
		cgi_custom_failure(
			$q, "403 Forbidden",
			gettext("You are banned."));
	}
}

sub cgi_getsession ($) {
	my $q=shift;

	eval q{use CGI::Session; use HTML::Entities};
	error($@) if $@;
	CGI::Session->name("ikiwiki_session_".encode_entities($config{wikiname}));
	
	my $oldmask=umask(077);
	my $session = eval {
		CGI::Session->new("driver:DB_File", $q,
			{ FileName => "$config{wikistatedir}/sessions.db" })
	};
	if (! $session || $@) {
		my $error = $@;
		error($error." ".CGI::Session->errstr());
	}
	
	umask($oldmask);

	return $session;
}

# To guard against CSRF, the user's session id (sid)
# can be stored on a form. This function will check
# (for logged in users) that the sid on the form matches
# the session id in the cookie.
sub checksessionexpiry ($$) {
	my $q=shift;
	my $session = shift;

	if (defined $session->param("name")) {
		my $sid=$q->param('sid');
		if (! defined $sid || $sid ne $session->id) {
			error(gettext("Your login session has expired."));
		}
	}
}

sub cgi_savesession ($) {
	my $session=shift;

	# Force session flush with safe umask.
	my $oldmask=umask(077);
	$session->flush;
	umask($oldmask);
}

sub cgi (;$$) {
	my $q=shift;
	my $session=shift;

	eval q{use CGI};
	error($@) if $@;
	no warnings "once";
	$CGI::DISABLE_UPLOADS=$config{cgi_disable_uploads};
	use warnings;

	if (! $q) {
		binmode(STDIN);
		$q=CGI->new;
		binmode(STDIN, ":utf8");
	
		run_hooks(cgi => sub { shift->($q) });
	}

	my $do=$q->param('do');
	if (! defined $do || ! length $do) {
		my $error = $q->cgi_error;
		if ($error) {
			error("Request not processed: $error");
		}
		else {
			error("\"do\" parameter missing");
		}
	}

	# Need to lock the wiki before getting a session.
	lockwiki();
	loadindex();
	
	if (! $session) {
		$session=cgi_getsession($q);
	}
	
	# Auth hooks can sign a user in.
	if ($do ne 'signin' && ! defined $session->param("name")) {
		run_hooks(auth => sub {
			shift->($q, $session)
		});
		if (defined $session->param("name")) {
			# Make sure whatever user was authed is in the
			# userinfo db.
			if (! userinfo_get($session->param("name"), "regdate")) {
				userinfo_setall($session->param("name"), {
					email => defined $session->param("email") ? $session->param("email") : "",
					password => "",
					regdate => time,
				}) || error("failed adding user");
			}
		}
	}
	
	check_banned($q, $session);
	
	run_hooks(sessioncgi => sub { shift->($q, $session) });

	if ($do eq 'signin') {
		cgi_signin($q, $session);
		cgi_savesession($session);
	}
	elsif ($do eq 'prefs') {
		cgi_prefs($q, $session);
	}
	elsif (defined $session->param("postsignin") || $do eq 'postsignin') {
		cgi_postsignin($q, $session);
	}
	else {
		error("unknown do parameter");
	}
}

# Does not need to be called directly; all errors will go through here.
sub cgierror ($) {
	my $message=shift;

	print "Content-type: text/html\n\n";
	print cgitemplate(undef, gettext("Error"),
		"<p class=\"error\">".gettext("Error").": $message</p>");
	die $@;
}

1
