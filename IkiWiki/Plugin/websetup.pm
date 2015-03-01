#!/usr/bin/perl
package IkiWiki::Plugin::websetup;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "websetup", call => \&getsetup);
	hook(type => "checkconfig", id => "websetup", call => \&checkconfig);
	hook(type => "sessioncgi", id => "websetup", call => \&sessioncgi);
	hook(type => "formbuilder_setup", id => "websetup", 
	     call => \&formbuilder_setup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
		websetup_force_plugins => {
			type => "string",
			example => [],
			description => "list of plugins that cannot be enabled/disabled via the web interface",
			safe => 0,
			rebuild => 0,
		},
		websetup_unsafe => {
			type => "string",
			example => [],
			description => "list of additional setup field keys to treat as unsafe",
			safe => 0,
			rebuild => 0,
		},
		websetup_show_unsafe => {
			type => "boolean",
			example => 1,
			description => "show unsafe settings, read-only, in web interface?",
			safe => 0,
			rebuild => 0,
		},
}

sub checkconfig () {
	if (! exists $config{websetup_show_unsafe}) {
		$config{websetup_show_unsafe}=1;
	}
}

sub formatexample ($$) {
	my $example=shift;
	my $value=shift;

	if (defined $value && length $value) {
		return "";
	}
	elsif (defined $example && ! ref $example && length $example) {
		return "<br/ ><small>Example: <tt>$example</tt></small>";
	}
	else {
		return "";
	}
}

sub issafe ($) {
	my $key=shift;

	return ! grep { $_ eq $key } @{$config{websetup_unsafe}};
}

sub showfields ($$$@) {
	my $form=shift;
	my $plugin=shift;
	my $enabled=shift;

	my @show;
	my %plugininfo;
	while (@_) {
		my $key=shift;
		my %info=%{shift()};
		
		if ($key eq 'plugin') {
			%plugininfo=%info;
			next;
		}

		# skip internal settings
		next if defined $info{type} && $info{type} eq "internal";
		# XXX hashes not handled yet
		next if ref $config{$key} && ref $config{$key} eq 'HASH' || ref $info{example} eq 'HASH';
		# maybe skip unsafe settings
		next if ! ($config{websetup_show_unsafe} && $config{websetup_advanced}) &&
			(! $info{safe} || ! issafe($key));
		# maybe skip advanced settings
		next if $info{advanced} && ! $config{websetup_advanced};
		# these are handled specially, so don't show
		next if $key eq 'add_plugins' || $key eq 'disable_plugins';

		push @show, $key, \%info;
	}

	my $section=defined $plugin
		? sprintf(gettext("%s plugin:"), $plugininfo{section})." ".$plugin
		: "main";
	my %enabledfields;
	my $shownfields=0;
	
	my $plugin_forced=defined $plugin && (! $plugininfo{safe} ||
		(exists $config{websetup_force_plugins} && grep { $_ eq $plugin } @{$config{websetup_force_plugins}}));
	if ($plugin_forced && ! $enabled) {
		# plugin is forced disabled, so skip its settings
		@show=();
	}

	my $section_fieldset;
	if (defined $plugin) {
		# Define the combined fieldset for the plugin's section.
		# This ensures that this fieldset comes first.
		$section_fieldset=sprintf(gettext("%s plugins"), $plugininfo{section});
		$form->field(name => "placeholder.$plugininfo{section}",
			type => "hidden",
			fieldset => $section_fieldset);
	}

	# show plugin toggle
	if (defined $plugin && (! $plugin_forced || $config{websetup_advanced})) {
		my $name="enable.$plugin";
		$form->field(
			name => $name,
			label => "",
			type => "checkbox",
			fieldset => $section,
			options => [ [ 1 => sprintf(gettext("enable %s?"), $plugin) ]]
		);
		if (! $form->submitted) {
			$form->field(name => $name, value => $enabled);
		}
		if ($plugin_forced) {
			$form->field(name => $name, disabled => 1);
		}
		else {
			$enabledfields{$name}=[$name, \%plugininfo];
		}
	}

	# show plugin settings
	while (@show) {
		my $key=shift @show;
		my %info=%{shift @show};

		my $description=$info{description};
		if (exists $info{htmldescription}) {
			$description=$info{htmldescription};
		}
		elsif (exists $info{link} && length $info{link}) {
			if ($info{link} =~ /^\w+:\/\//) {
				$description="<a href=\"$info{link}\">$description</a>";
			}
			else {
				$description=htmllink("", "", $info{link}, noimageinline => 1, linktext => $description);
			}
		}

		# multiple plugins can have the same field
		my $name=defined $plugin ? $plugin.".".$key : $section.".".$key;

		my $value=$config{$key};
		if (! defined $value) {
			$value="";
		}

		if (ref $value eq 'ARRAY' || ref $info{example} eq 'ARRAY') {
			$value=[(ref $value eq 'ARRAY' ? map { Encode::encode_utf8($_) }  @{$value} : "")];
			push @$value, "", "" if $info{safe} && issafe($key); # blank items for expansion
		}
		else {
			$value=Encode::encode_utf8($value);
		}

		if ($info{type} eq "string") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 60,
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "pagespec") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 60,
				validate => \&IkiWiki::pagespec_valid,
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "integer") {
			$form->field(
				name => $name,
				label => $description,
				comment => formatexample($info{example}, $value),
				type => "text",
				value => $value,
				size => 5,
				validate => '/^[0-9]+$/',
				fieldset => $section,
			);
		}
		elsif ($info{type} eq "boolean") {
			$form->field(
				name => $name,
				label => "",
				type => "checkbox",
				options => [ [ 1 => $description ] ],
				fieldset => $section,
			);
			if (! $form->submitted ||
			    ($info{advanced} && $form->submitted eq 'Advanced Mode')) {
				$form->field(name => $name, value => $value);
			}
		}
		
		if (! $info{safe} || ! issafe($key)) {
			$form->field(name => $name, disabled => 1);
		}
		else {
			$enabledfields{$name}=[$key, \%info];
		}
		$shownfields++;
	}
	
	# if no fields were shown for the plugin, drop it into a combined
	# fieldset for its section
	if (defined $plugin && (! $plugin_forced || $config{websetup_advanced}) &&
	    ! $shownfields) {
		$form->field(name => "enable.$plugin", fieldset => $section_fieldset);
	}

	return %enabledfields;
}

sub enable_plugin ($) {
	my $plugin=shift;

	$config{disable_plugins}=[grep { $_ ne $plugin } @{$config{disable_plugins}}];
	push @{$config{add_plugins}}, $plugin;
}

sub disable_plugin ($) {
	my $plugin=shift;

	$config{add_plugins}=[grep { $_ ne $plugin } @{$config{add_plugins}}];
	push @{$config{disable_plugins}}, $plugin;
}

sub showform ($$) {
	my $cgi=shift;
	my $session=shift;

	IkiWiki::needsignin($cgi, $session);

	if (! defined $session->param("name") || 
	    ! IkiWiki::is_admin($session->param("name"))) {
		error(gettext("you are not logged in as an admin"));
	}

	if (! exists $config{setupfile}) {
		error(gettext("setup file for this wiki is not known"));
	}

	eval q{use CGI::FormBuilder};
	error($@) if $@;

	my $form = CGI::FormBuilder->new(
		title => "setup",
		name => "setup",
		header => 0,
		charset => "utf-8",
		method => 'POST',
		javascript => 0,
		reset => 1,
		params => $cgi,
		fieldsets => [
			[main => gettext("main")], 
		],
		action => IkiWiki::cgiurl(),
		template => {type => 'div'},
		stylesheet => 1,
	);
	
	$form->field(name => "do", type => "hidden", value => "setup",
		force => 1);
	$form->field(name => "rebuild_asked", type => "hidden");
	$form->field(name => "showadvanced", type => "hidden");

	if ($form->submitted eq 'Basic Mode') {
		$form->field(name => "showadvanced", type => "hidden", 
			value => 0, force => 1);
	}
	elsif ($form->submitted eq 'Advanced Mode') {
		$form->field(name => "showadvanced", type => "hidden", 
			value => 1, force => 1);
	}
	my $advancedtoggle;
	if ($form->field("showadvanced")) {
		$config{websetup_advanced}=1;
		$advancedtoggle="Basic Mode";
	}
	else {
		$config{websetup_advanced}=0;
		$advancedtoggle="Advanced Mode";
	}

	my $buttons=["Save Setup", $advancedtoggle, "Cancel"];

	IkiWiki::decode_form_utf8($form);
	IkiWiki::run_hooks(formbuilder_setup => sub {
		shift->(form => $form, cgi => $cgi, session => $session,
			buttons => $buttons);
	});

	my %fields=showfields($form, undef, undef, IkiWiki::getsetup());
	
	# record all currently enabled plugins before all are loaded
	my %enabled_plugins=%IkiWiki::loaded_plugins;

	# per-plugin setup
	require IkiWiki::Setup;
	foreach my $pair (IkiWiki::Setup::getsetup()) {
		my $plugin=$pair->[0];
		my $setup=$pair->[1];

		my %shown=showfields($form, $plugin, $enabled_plugins{$plugin}, @{$setup});
		if (%shown) {
			$fields{$_}=$shown{$_} foreach keys %shown;
		}
	}

	IkiWiki::decode_form_utf8($form);
	
	if ($form->submitted eq "Cancel") {
		IkiWiki::redirect($cgi, IkiWiki::baseurl(undef));
		return;
	}
	elsif (($form->submitted eq 'Save Setup' || $form->submitted eq 'Rebuild Wiki') && $form->validate) {
		# Push values from form into %config, avoiding unnecessary
		# changes, and keeping track of which changes need a
		# rebuild.
		my %rebuild;
		foreach my $field (keys %fields) {
			my %info=%{$fields{$field}->[1]};
			my $key=$fields{$field}->[0];
			my @value=$form->field($field);
			if (! @value) {
				@value=0;
			}
		
			if (! $info{safe} || ! issafe($key)) {
	 			error("unsafe field $key"); # should never happen
			}
		
			if (exists $info{rebuild} &&
			    ($info{rebuild} || ! defined $info{rebuild})) {
				$rebuild{$field}=$info{rebuild};
			}
					
			if ($field=~/^enable\.(.*)/) {
				my $plugin=$1;
				$value[0]=0 if ! length $value[0];
				if ($value[0] != exists $enabled_plugins{$plugin}) {
					if ($value[0]) {
						enable_plugin($plugin);
					}
					else {
						disable_plugin($plugin);

					}
				}
				else {
					delete $rebuild{$field};
				}
				next;
			}

			if (ref $config{$key} eq "ARRAY" || ref $info{example} eq "ARRAY") {
				@value=sort grep { length $_ } @value;
				my @oldvalue=sort grep { length $_ }
					(defined $config{$key} ? @{$config{$key}} : ());
				my $same=(@oldvalue) == (@value);
				for (my $x=0; $same && $x < @value; $x++) {
					$same=0 if $value[$x] ne $oldvalue[$x];
				}
				if ($same) {
					delete $rebuild{$field};
				}
				else {
					$config{$key}=\@value;
				}
			}
			elsif (ref $config{$key} || ref $info{example}) {
				error("complex field $key"); # should never happen
			}
			else {
				if (defined $config{$key} && $config{$key} eq $value[0]) {
					delete $rebuild{$field};
				}
				elsif (! defined $config{$key} && ! length $value[0]) {
					delete $rebuild{$field};
				}
				elsif ((! defined $config{$key} || ! $config{$key}) &&
				       ! $value[0] && $info{type} eq "boolean") {
					delete $rebuild{$field};
				}
				else {
					$config{$key}=$value[0];
				}
			}
		}
		
		if (%rebuild && ! $form->field("rebuild_asked")) {
			my $required=0;
			foreach my $field ($form->field) {
				$required=1 if $rebuild{$field};
				next if exists $rebuild{$field};
				$form->field(name => $field, type => "hidden");
			}
			if ($required) {
				$form->text(gettext("The configuration changes shown below require a wiki rebuild to take effect."));
				$buttons=["Rebuild Wiki", "Cancel"];
			}
			else {
				$form->text(gettext("For the configuration changes shown below to fully take effect, you may need to rebuild the wiki."));
				$buttons=["Rebuild Wiki", "Save Setup", "Cancel"];
			}
			$form->field(name => "rebuild_asked", value => 1, force => 1);
			$form->reset(0); # doesn't really make sense here
		}
		else {
			my $oldsetup=readfile($config{setupfile});
			IkiWiki::Setup::dump($config{setupfile});

			IkiWiki::saveindex();
			IkiWiki::unlockwiki();

			# Print the top part of a standard cgitemplate,
			# then show the rebuild or refresh, live.
			my $divider="\0";
			my $html=IkiWiki::cgitemplate($cgi, "setup", $divider);
			IkiWiki::printheader($session);
			my ($head, $tail)=split($divider, $html, 2);
			print $head."<pre>\n";

			my @command;
			if ($form->submitted eq 'Rebuild Wiki') {
				@command=("ikiwiki", "--setup", $config{setupfile},
                                        "--rebuild", "-v");
			}
			else {
				@command=("ikiwiki", "--setup", $config{setupfile},
					"--refresh", "--wrappers", "-v");
			}

			close STDERR;
			open(STDERR, ">&STDOUT");
			my $ret=system(@command);
			print "\n<\/pre>";
			if ($ret != 0) {
				print '<p class="error">'.
					sprintf(gettext("Error: %s exited nonzero (%s). Discarding setup changes."),
						join(" ", @command), $ret).
					'</p>';
				open(OUT, ">", $config{setupfile}) || error("$config{setupfile}: $!");
				print OUT Encode::encode_utf8($oldsetup);
				close OUT;
			}

			print $tail;
			exit 0;
		}
	}

	IkiWiki::showform($form, $buttons, $session, $cgi);
}

sub sessioncgi ($$) {
	my $cgi=shift;
	my $session=shift;

	if ($cgi->param("do") eq "setup") {
		showform($cgi, $session);
		exit;
	}
}

sub formbuilder_setup (@) {
	my %params=@_;

	my $form=$params{form};
	if ($form->title eq "preferences" &&
	    IkiWiki::is_admin($params{session}->param("name"))) {
		push @{$params{buttons}}, "Setup";
		if ($form->submitted && $form->submitted eq "Setup") {
			showform($params{cgi}, $params{session});
			exit;
		}
	}
}

1
