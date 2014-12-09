#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use File::Path qw(make_path remove_tree);

BEGIN { use_ok("IkiWiki"); }

make_path("t/tmp/libdir");
make_path("t/tmp/libdirs");
make_path("t/tmp/libdirs/1");
make_path("t/tmp/libdirs/2");

writefile("IkiWiki/Plugin/test_plugin_in_libdir.pm", "t/tmp/libdir", "#");
writefile("IkiWiki/Plugin/test_plugin_in_libdir_1.pm", "t/tmp/libdirs/1", "#");
writefile("IkiWiki/Plugin/test_plugin_in_libdir_2.pm", "t/tmp/libdirs/2", "#");
writefile("plugins/ext_plugin_in_libdir", "t/tmp/libdir", "#!/bin/true");
writefile("plugins/ext_plugin_in_libdir_1", "t/tmp/libdirs/1", "#!/bin/true");
writefile("plugins/ext_plugin_in_libdir_2", "t/tmp/libdirs/2", "#!/bin/true");
ok(chmod 0755, "t/tmp/libdir/plugins/ext_plugin_in_libdir");
ok(chmod 0755, "t/tmp/libdirs/1/plugins/ext_plugin_in_libdir_1");
ok(chmod 0755, "t/tmp/libdirs/2/plugins/ext_plugin_in_libdir_2");

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
$config{libdir}="t/tmp/libdir";
$config{libdirs}=["t/tmp/libdirs/1", "t/tmp/libdirs/2"];

my @plugins = IkiWiki::listplugins();

ok(grep { m/^test_plugin_in_libdir$/ } @plugins);
ok(grep { m/^test_plugin_in_libdir_1$/ } @plugins);
ok(grep { m/^test_plugin_in_libdir_2$/ } @plugins);

ok(grep { m/^ext_plugin_in_libdir$/ } @plugins);
ok(grep { m/^ext_plugin_in_libdir_1$/ } @plugins);
ok(grep { m/^ext_plugin_in_libdir_2$/ } @plugins);

remove_tree("t/tmp/libdir");
remove_tree("t/tmp/libdirs");

done_testing;
