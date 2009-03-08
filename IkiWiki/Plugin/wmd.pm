#!/usr/bin/perl
package IkiWiki::Plugin::wmd;

use warnings;
use strict;
use IkiWiki 3.00;
use POSIX;
use Encode;

sub import {
	add_underlay("wmd");
	hook(type => "getsetup", id => "wmd", call => \&getsetup);
	hook(type => "formbuilder_setup", id => "wmd", call => \&formbuilder_setup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
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
		include_javascript(undef, 1));
}

sub include_javascript ($;$) {
	my $page=shift;
	my $absolute=shift;

	my $wmdjs=urlto("wmd/wmd.js", $page, $absolute);
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
