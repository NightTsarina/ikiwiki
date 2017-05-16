#!/usr/bin/perl
# Ikiwiki text colouring plugin
# Paweł‚ Tęcza <ptecza@net.icm.edu.pl>
package IkiWiki::Plugin::color;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "preprocess", id => "color", call => \&preprocess);
	hook(type => "format",     id => "color", call => \&format);
	hook(type => "getsetup",   id => "color", call => \&getsetup);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preserve_style ($$$) {
	my $foreground = shift;
	my $background = shift;
	my $text       = shift;

	$foreground = defined $foreground ? lc($foreground) : '';
	$background = defined $background ? lc($background) : '';
	$text       = '' unless (defined $text);

	# Validate colors. Only color name or color code are valid.
	$foreground = '' unless ($foreground &&
				($foreground =~ /^[a-z]+$/ || $foreground =~ /^#[0-9a-f]{3,6}$/));
	$background = '' unless ($background &&
				($background =~ /^[a-z]+$/ || $background =~ /^#[0-9a-f]{3,6}$/));

	my $preserved = '';
	$preserved .= '<span class="color"><span value="';
	$preserved .= 'color: '.$foreground if ($foreground);
	$preserved .= '; ' if ($foreground && $background);
	$preserved .= 'background-color: '.$background if ($background);
	$preserved .= '"></span>'.$text.'</span>';
	
	return $preserved;

}

sub replace_preserved_style ($) {
	my $content = shift;

	$content =~ s!<span class="color">\s*<span value="((color: ([a-z]+|\#[0-9a-f]{3,6})?)?((; )?(background-color: ([a-z]+|\#[0-9a-f]{3,6})?)?)?)">\s*</span>!<span class="color" style="$1">!g;

	return $content;
}

sub preprocess (@) {
	my %params = @_;

	return preserve_style($params{foreground}, $params{background},
		# Preprocess the text to expand any preprocessor directives
		# embedded inside it.
		IkiWiki::preprocess($params{page}, $params{destpage},
			$params{text}));
}

sub format (@) {
	my %params = @_;

	$params{content} = replace_preserved_style($params{content});
	return $params{content};	
}

1
