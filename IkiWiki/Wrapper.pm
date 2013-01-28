#!/usr/bin/perl

package IkiWiki;

use warnings;
use strict;
use File::Spec;
use Data::Dumper;
use IkiWiki;

sub gen_wrappers () {
	debug(gettext("generating wrappers.."));
	my %origconfig=(%config);
	foreach my $wrapper (@{$config{wrappers}}) {
		%config=(%origconfig, %{$wrapper});
		$config{verbose}=$config{setupverbose}
			if exists $config{setupverbose};
		$config{syslog}=$config{setupsyslog}
			if exists $config{setupsyslog};
		delete @config{qw(setupsyslog setupverbose wrappers genwrappers rebuild)};
		checkconfig();
		if (! $config{cgi} && ! $config{post_commit} &&
		    ! $config{test_receive}) {
			$config{post_commit}=1;
		}
		gen_wrapper();
	}
	%config=(%origconfig);
}

our $program_to_wrap = $0;
sub gen_wrapper () {
	$config{srcdir}=File::Spec->rel2abs($config{srcdir});
	$config{destdir}=File::Spec->rel2abs($config{destdir});
	my $this=File::Spec->rel2abs($program_to_wrap);
	if (! -x $this) {
		error(sprintf(gettext("%s doesn't seem to be executable"), $this));
	}

	if ($config{setup}) {
		error(gettext("cannot create a wrapper that uses a setup file"));
	}
	my $wrapper=possibly_foolish_untaint($config{wrapper});
	if (! defined $wrapper || ! length $wrapper) {
		error(gettext("wrapper filename not specified"));
	}
	delete $config{wrapper};
	
	my @envsave;
	push @envsave, qw{REMOTE_ADDR QUERY_STRING REQUEST_METHOD REQUEST_URI
	               CONTENT_TYPE CONTENT_LENGTH GATEWAY_INTERFACE
		       HTTP_COOKIE REMOTE_USER HTTPS REDIRECT_STATUS
		       HTTP_HOST SERVER_PORT HTTPS HTTP_ACCEPT
		       REDIRECT_URL} if $config{cgi};
	my $envsave="";
	foreach my $var (@envsave) {
		$envsave.=<<"EOF";
	if ((s=getenv("$var")))
		addenv("$var", s);
EOF
	}
	
	my @wrapper_hooks;
	run_hooks(genwrapper => sub { push @wrapper_hooks, shift->() });

	my $check_commit_hook="";
	my $pre_exec="";
	if ($config{post_commit}) {
		# Optimise checking !commit_hook_enabled() , 
		# so that ikiwiki does not have to be started if the
		# hook is disabled.
		#
		# Note that perl's flock may be implemented using fcntl
		# or lockf on some systems. If so, and if there is no
		# interop between the locking systems, the true C flock will
		# always succeed, and this optimisation won't work.
		# The perl code will later correctly check the lock,
		# so the right thing will still happen, though without
		# the benefit of this optimisation.
		$check_commit_hook=<<"EOF";
	{
		int fd=open("$config{wikistatedir}/commitlock", O_CREAT | O_RDWR, 0666);
		if (fd != -1) {
			if (flock(fd, LOCK_SH | LOCK_NB) != 0)
				exit(0);
			close(fd);
		}
	}
EOF
	}
	elsif ($config{cgi}) {
		# Avoid more than one ikiwiki cgi running at a time by
		# taking a cgi lock. Since ikiwiki uses several MB of
		# memory, a pile up of processes could cause thrashing
		# otherwise. The fd of the lock is stored in
		# IKIWIKI_CGILOCK_FD so unlockwiki can close it.
		#
		# A lot of cgi wrapper processes can potentially build
		# up and clog an otherwise unloaded web server. To
		# partially avoid this, when a GET comes in and the lock
		# is already held, rather than blocking a html page is
		# constructed that retries. This is enabled by setting
		# cgi_overload_delay.
		if (defined $config{cgi_overload_delay} &&
		    $config{cgi_overload_delay} =~/^[0-9]+/) {
			my $i=int($config{cgi_overload_delay});
			$pre_exec.="#define CGI_OVERLOAD_DELAY $i\n"
				if $i > 0;
			my $msg=gettext("Please wait");
			$msg=~s/"/\\"/g;
			$pre_exec.='#define CGI_PLEASE_WAIT_TITLE "'.$msg."\"\n";
			if (defined $config{cgi_overload_message} && length $config{cgi_overload_message}) {
				$msg=$config{cgi_overload_message};
				$msg=~s/"/\\"/g;
			}
			$pre_exec.='#define CGI_PLEASE_WAIT_BODY "'.$msg."\"\n";
		}
		$pre_exec.=<<"EOF";
	lockfd=open("$config{wikistatedir}/cgilock", O_CREAT | O_RDWR, 0666);
	if (lockfd != -1) {
#ifdef CGI_OVERLOAD_DELAY
		char *request_method = getenv("REQUEST_METHOD");
		if (request_method && strcmp(request_method, "GET") == 0) {
			if (lockf(lockfd, F_TLOCK, 0) == 0) {
				set_cgilock_fd(lockfd);
			}
			else {
				printf("Content-Type: text/html\\nRefresh: %i; URL=%s\\n\\n<html><head><title>%s</title><head><body><p>%s</p></body></html>",
					CGI_OVERLOAD_DELAY,
					getenv("REQUEST_URI"),
					CGI_PLEASE_WAIT_TITLE,
					CGI_PLEASE_WAIT_BODY);
				exit(0);
			}
		}
		else if (lockf(lockfd, F_LOCK, 0) == 0) {
			set_cgilock_fd(lockfd);
		}
#else
		if (lockf(lockfd, F_LOCK, 0) == 0) {
			set_cgilock_fd(lockfd);
		}
#endif
	}
EOF
	}

	my $set_background_command='';
	if (defined $config{wrapper_background_command} &&
	    length $config{wrapper_background_command}) {
	    	my $background_command=delete $config{wrapper_background_command};
		$set_background_command=~s/"/\\"/g;
		$set_background_command='#define BACKGROUND_COMMAND "'.$background_command.'"';
	}

	$Data::Dumper::Indent=0; # no newlines
	my $configstring=Data::Dumper->Dump([\%config], ['*config']);
	$configstring=~s/\\/\\\\/g;
	$configstring=~s/"/\\"/g;
	$configstring=~s/\n/\\n/g;
	
	writefile(basename("$wrapper.c"), dirname($wrapper), <<"EOF");
/* A wrapper for ikiwiki, can be safely made suid. */
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>

extern char **environ;
char *newenviron[$#envsave+7];
int i=0;

void addenv(char *var, char *val) {
	char *s=malloc(strlen(var)+1+strlen(val)+1);
	if (!s)
		perror("malloc");
	sprintf(s, "%s=%s", var, val);
	newenviron[i++]=s;
}

set_cgilock_fd (int lockfd) {
	char *fd_s=malloc(8);
	sprintf(fd_s, "%i", lockfd);
	setenv("IKIWIKI_CGILOCK_FD", fd_s, 1);
}

int main (int argc, char **argv) {
	int lockfd=-1;
	char *s;

$check_commit_hook
@wrapper_hooks
$envsave
	newenviron[i++]="HOME=$ENV{HOME}";
	newenviron[i++]="PATH=$ENV{PATH}";
	newenviron[i++]="WRAPPED_OPTIONS=$configstring";

#ifdef __TINYC__
	/* old tcc versions do not support modifying environ directly */
	if (clearenv() != 0) {
		perror("clearenv");
		exit(1);
	}
	for (; i>0; i--)
		putenv(newenviron[i-1]);
#else
	newenviron[i]=NULL;
	environ=newenviron;
#endif

	if (setregid(getegid(), -1) != 0 &&
	    setregid(getegid(), -1) != 0) {
		perror("failed to drop real gid");
		exit(1);
	}
	if (setreuid(geteuid(), -1) != 0 &&
	    setreuid(geteuid(), -1) != 0) {
		perror("failed to drop real uid");
		exit(1);
	}

$pre_exec

$set_background_command
#ifdef BACKGROUND_COMMAND
	if (lockfd != -1) {
		close(lockfd);
	}

	pid_t pid=fork();
	if (pid == -1) {
		perror("fork");
		exit(1);
	}
	else if (pid == 0) {
		execl("$this", "$this", NULL);
		perror("exec $this");
		exit(1);		
	}
	else {
		waitpid(pid, NULL, 0);

		if (daemon(1, 0) == 0) {
			system(BACKGROUND_COMMAND);
			exit(0);
		}
		else {
			perror("daemon");
			exit(1);
		}
	}
#else
	execl("$this", "$this", NULL);
	perror("exec $this");
	exit(1);
#endif
}
EOF

	my @cc=exists $ENV{CC} ? possibly_foolish_untaint($ENV{CC}) : 'cc';
	push @cc, split(' ', possibly_foolish_untaint($ENV{CFLAGS})) if exists $ENV{CFLAGS};
	if (system(@cc, "$wrapper.c", "-o", "$wrapper.new") != 0) {
		#translators: The parameter is a C filename.
		error(sprintf(gettext("failed to compile %s"), "$wrapper.c"));
	}
	unlink("$wrapper.c");
	if (defined $config{wrappergroup}) {
		my $gid=(getgrnam($config{wrappergroup}))[2];
		if (! defined $gid) {
			error(sprintf("bad wrappergroup"));
		}
		if (! chown(-1, $gid, "$wrapper.new")) {
			error("chown $wrapper.new: $!");
		}
	}
	if (defined $config{wrappermode} &&
	    ! chmod(oct($config{wrappermode}), "$wrapper.new")) {
		error("chmod $wrapper.new: $!");
	}
	if (! rename("$wrapper.new", $wrapper)) {
		error("rename $wrapper.new $wrapper: $!");
	}
	#translators: The parameter is a filename.
	debug(sprintf(gettext("successfully generated %s"), $wrapper));
}

1
