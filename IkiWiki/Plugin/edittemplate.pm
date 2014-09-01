#!/usr/bin/perl
package IkiWiki::Plugin::edittemplate;

use warnings;
use strict;
use IkiWiki 3.00;
use HTML::Template;
use Encode;

sub import {
	hook(type => "getsetup", id => "edittemplate",
		call => \&getsetup);
	hook(type => "needsbuild", id => "edittemplate",
		call => \&needsbuild);
	hook(type => "preprocess", id => "edittemplate",
		call => \&preprocess);
	hook(type => "formbuilder", id => "edittemplate",
		call => \&formbuilder);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "web",
		},
}

sub needsbuild (@) {
	my $needsbuild=shift;

	foreach my $page (keys %pagestate) {
		if (exists $pagestate{$page}{edittemplate}) {
			if (exists $pagesources{$page} && 
			    grep { $_ eq $pagesources{$page} } @$needsbuild) {
				# remove state, it will be re-added
				# if the preprocessor directive is still
				# there during the rebuild
				delete $pagestate{$page}{edittemplate};
			}
		}
	}

	return $needsbuild;
}

sub preprocess (@) {
        my %params=@_;

	return "" if $params{page} ne $params{destpage};

	if (! exists $params{template} || ! length($params{template})) {
		error gettext("template not specified")
	}
	if (! exists $params{match} || ! length($params{match})) {
		error gettext("match not specified")
	}

	my $link=linkpage($params{template});
	add_depends($params{page}, $link, deptype("presence"));
	my $bestlink=bestlink($params{page}, $link);
	if (! length $bestlink) {
		add_depends($params{page}, "templates/$link", deptype("presence"));
		$link="/templates/".$link;
		$bestlink=bestlink($params{page}, $link);
	}
	$pagestate{$params{page}}{edittemplate}{$params{match}}=$bestlink;

	return "" if ($params{silent} && IkiWiki::yesno($params{silent})) &&
		length $bestlink;
	return sprintf(gettext("edittemplate %s registered for %s"),
		htmllink($params{page}, $params{destpage}, $link),
	       	$params{match});
}

sub formbuilder (@) {
	my %params=@_;
	my $form=$params{form};

	return if $form->field("do") ne "create" ||
		(defined $form->field("editcontent") && length $form->field("editcontent"));
	
	my $page=$form->field("page");
	
	# The tricky bit here is that $page is probably just the base
	# page name, without any subdir, but the pagespec for a template
	# probably does include the subdir (ie, "bugs/*"). We don't know
	# what subdir the user will pick to put the page in. So, try them
	# all, starting with the one that was made default.
	my @page_locs=$page;
	foreach my $field ($form->field) {
		if ($field eq 'page') {
			@page_locs=$field->def_value;

			# FormBuilder is on the bad crack. See #551499
			my @options=map { ref $_ ? @$_ : $_ } $field->options;

			push @page_locs, @options;
		}
	}
	foreach my $p (@page_locs) {
		foreach my $registering_page (keys %pagestate) {
			if (exists $pagestate{$registering_page}{edittemplate}) {
				foreach my $pagespec (sort keys %{$pagestate{$registering_page}{edittemplate}}) {
					if (pagespec_match($p, $pagespec, location => $registering_page)) {
						my $template=$pagestate{$registering_page}{edittemplate}{$pagespec};
						$form->field(name => "editcontent",
							 value =>  filltemplate($template, $page));
						my $type=pagetype($pagesources{$template})
								if $pagesources{$template};
						$form->field(name => "type",
							 value => $type)
								if defined $type;
						return;
					}
				}
			}
		}
	}
}

sub filltemplate ($$) {
	my $template_page=shift;
	my $page=shift;

	my $template;
	eval {
		# force page name absolute so it doesn't look in templates/
		$template=template("/".$template_page);
	};
	if ($@) {
		# gettext can clobber $@
		my $error = $@;
		# Indicate that the earlier preprocessor directive set 
		# up a template that doesn't work.
		return "[[!edittemplate ".gettext("failed to process template:")." $error]]";
	}

	$template->param(name => $page);

	if ($template->query(name => 'uuid')) {
		my $uuid;
		if (open(my $fh, "<", "/proc/sys/kernel/random/uuid")) {
			$uuid = <$fh>;
			chomp $uuid;
			close $fh;
		}
		else {
			eval {
				require UUID::Tiny;
				$uuid = UUID::Tiny::create_uuid_as_string(UUID::Tiny::UUID_V4());
			};
		}
		$template->param(uuid => $uuid);
	}

	my $time = time();
	$template->param(time => IkiWiki::formattime($time, "%Y-%m-%d %H:%M:%S"));

	return $template->output;
}

1
