#!/usr/bin/perl
package IkiWiki::Plugin::wmd;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	add_underlay("wmd");
	hook(type => "getsetup", id => "wmd", call => \&getsetup);
	hook(type => "formbuilder_setup", id => "wmd", call => \&formbuilder_setup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 0,
			section => "web",
		},
}

sub formbuilder_setup (@) {
	my %params=@_;
	my $form=$params{form};

	return if ! defined $form->field("do");
	
	return unless $form->field("do") eq "edit" ||
			$form->field("do") eq "create" ||
			$form->field("do") eq "comment";

	$form->tmpl_param("wmd_preview", "<div class=\"wmd-preview\"></div>\n".
		include_javascript(undef));
}

sub include_javascript ($) {
	my $from=shift;

	my $wmdjs=urlto("wmd/wmd.js", $from);
	return <<"EOF"
<script type="text/javascript">
wmd_options = {
	output: "Markdown"
};
</script>
<script src="$wmdjs" type="text/javascript"></script>
EOF
}

1
