#!/usr/bin/perl
package IkiWiki::Plugin::highlight;

# This has been tested with highlight 2.16 and highlight 3.2+svn19.
# In particular version 3.2 won't work. It detects the different
# versions by the presence of the the highlight::DataDir class.

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;

my $data_dir;

sub import {
	hook(type => "getsetup", id => "highlight",  call => \&getsetup);
	hook(type => "checkconfig", id => "highlight", call => \&checkconfig);
	# this hook is used by the format plugin
	hook(type => "htmlizeformat", id => "highlight", 
		call => \&htmlizeformat, last => 1);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
			section => "format",
		},
		tohighlight => {
			type => "string",
			example => ".c .h .cpp .pl .py Makefile:make",
			description => "types of source files to syntax highlight",
			safe => 1,
			rebuild => 1,
		},
		filetypes_conf => {
			type => "string",
			example => "/etc/highlight/filetypes.conf",
			description => "location of highlight's filetypes.conf",
			safe => 0,
			rebuild => undef,
		},
		langdefdir => {
			type => "string",
			example => "/usr/share/highlight/langDefs",
			description => "location of highlight's langDefs directory",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
	eval q{use highlight};
	if (highlight::DataDir->can('new')) {
		$data_dir=new highlight::DataDir();
		$data_dir->searchDataDir("");
	} else {
		$data_dir=undef;
	}

	if (! exists $config{filetypes_conf}) {
		$config{filetypes_conf}= 
		     ($data_dir ? $data_dir->getConfDir() : "/etc/highlight/")
			  . "filetypes.conf";
	}
	if (! exists $config{langdefdir}) {
		$config{langdefdir}=
		     ($data_dir ? $data_dir->getLangPath("")
		      : "/usr/share/highlight/langDefs");

	}
	if (exists $config{tohighlight} && read_filetypes()) {
		foreach my $file (split ' ', $config{tohighlight}) {
			my @opts = $file=~s/^\.// ?
				(keepextension => 1) :
				(noextension => 1);
			my $ext = $file=~s/:(.*)// ? $1 : $file;
		
			my $langfile=ext2langfile($ext);
			if (! defined $langfile) {
				error(sprintf(gettext(
					"tohighlight contains unknown file type '%s'"),
					$ext));
			}
	
			hook(
				type => "htmlize",
				id => $file,
				call => sub {
					my %params=@_;
				       	highlight($langfile, $file, $params{content});
				},
				longname => sprintf(gettext("Source code: %s"), $file),
				@opts,
			);
		}
	}
}

sub htmlizeformat {
	my $format=lc shift;
	my $langfile=ext2langfile($format);

	if (! defined $langfile) {
		return;
	}

	return Encode::decode_utf8(highlight($langfile, $format, shift));
}

my %ext2lang;
my $filetypes_read=0;
my %highlighters;

# Parse highlight's config file to get extension => language mappings.
sub read_filetypes () {
	my $f;
	if (!open($f, $config{filetypes_conf})) {
		warn($config{filetypes_conf}.": ".$!);
		return 0;
	};

	local $/=undef;
	my $config=<$f>;
	close $f;

	# highlight >= 3.2 format (bind-style)
	while ($config=~m/Lang\s*=\s*\"([^"]+)\"[,\s]+Extensions\s*=\s*{([^}]+)}/sg) {
		my $lang=$1;
		foreach my $bit (split ',', $2) {
			$bit=~s/.*"(.*)".*/$1/s;
			$ext2lang{$bit}=$lang;
		}
	}

	# highlight < 3.2 format
	if (! keys %ext2lang) {
		foreach (split("\n", $config)) {
			if (/^\$ext\((.*)\)=(.*)$/) {
				$ext2lang{$_}=$1 foreach $1, split ' ', $2;
			}
		}
	}

	return $filetypes_read=1;
}


# Given a filename extension, determines the language definition to
# use to highlight it.
sub ext2langfile ($) {
	my $ext=shift;

	my $langfile="$config{langdefdir}/$ext.lang";
	return $langfile if exists $highlighters{$langfile};

	read_filetypes() unless $filetypes_read;
	if (exists $ext2lang{$ext}) {
		return "$config{langdefdir}/$ext2lang{$ext}.lang";
	}
	# If a language only has one common extension, it will not
	# be listed in filetypes, so check the langfile.
	elsif (-e $langfile) {
		return $langfile;
	}
	else {
		return undef;
	}
}

# Interface to the highlight C library.
sub highlight ($$) {
	my $langfile=shift;
	my $extorfile=shift;
	my $input=shift;

	eval q{use highlight};
	if ($@) {
		print STDERR gettext("warning: highlight perl module not available; falling back to pass through");
		return $input;
	}

	my $gen;
	if (! exists $highlighters{$langfile}) {
		$gen = highlight::CodeGenerator::getInstance($highlight::XHTML);
		$gen->setFragmentCode(1); # generate html fragment
		$gen->setHTMLEnclosePreTag(1); # include stylish <pre>
		if ($data_dir){
			# new style, requires a real theme, but has no effect
			$gen->initTheme($data_dir->getThemePath("seashell.theme"));
		} else {
			# old style, anything works.
			$gen->initTheme("/dev/null");
		}
		$gen->loadLanguage($langfile); # must come after initTheme
		$gen->setEncoding("utf-8");
		$highlighters{$langfile}=$gen;
	}
	else {		
		$gen=$highlighters{$langfile};
	}

	return "<div class=\"highlight-$extorfile\">".$gen->generateString($input)."</div>";
}

1
