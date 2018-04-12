# NAME

ikiwiki - a wiki compiler

# SYNOPSIS

ikiwiki [options] source destination

ikiwiki --setup setupfile [options]

# DESCRIPTION

`ikiwiki` is a wiki compiler. It builds static HTML pages for a wiki, from
`source` in the [[ikiwiki/Markdown]] language (or others), and writes it out to
`destination`.

Note that most options can be shortened to single letters, boolean
flags such as --verbose can be negated with --no-verbose, and
options such as --verbose can also be spelled like -verbose.

# MODE OPTIONS

These options control the mode that ikiwiki operates in.

* --refresh

  Refresh the wiki, updating any changed pages. This is the default
  behavior if no other mode action is specified (but note that --setup is
  a mode action, and has different default behavior).

* --rebuild

  Force a rebuild of all pages.

* --setup setupfile

  Load options from the given setup file. If no other mode action is specified,
  generate wrappers and rebuild the wiki, as if --rebuild --wrappers were used.
  If you only want to build any changed pages, you can use --refresh with
  --setup.

* --changesetup setupfile

  Reads the setup file, adds any configuration changes specified by other
  options, and writes the new configuration back to the setup file. Also
  updates any configured wrappers. In this mode, the wiki is not fully
  rebuilt, unless you also add --rebuild.

  Example, to enable some plugins:

	ikiwiki --changesetup ~/ikiwiki.setup --plugin goodstuff --plugin calendar

* --dumpsetup setupfile

  Causes ikiwiki to write to the specified setup file, dumping out
  its current configuration.

* --wrappers

  If used with --setup --refresh, this makes it also update any configured
  wrappers.

* --clean

  This makes ikiwiki clean up by removing any files it generated in the
  `destination` directory, as well as any configured wrappers, and the
  `.ikiwiki` state directory. This is mostly useful if you're running
  ikiwiki in a Makefile to build documentation and want a corresponding
  `clean` target.

* --cgi

  Enable [[CGI]] mode. In cgi mode ikiwiki runs as a cgi script, and
  supports editing pages, signing in, and registration.

  To use ikiwiki as a [[CGI]] program you need to use --wrapper or --setup
  to generate a wrapper. The wrapper will generally need to run suid 6755 to
  the user who owns the `source` and `destination` directories.

* --wrapper [file]

  Generate a wrapper binary that is hardcoded to do action specified by
  the other options, using the specified input files and `destination`
  directory. The filename to use for the wrapper is optional.

  The wrapper is designed to be safely made suid and be run by untrusted
  users, as a [[post-commit]] hook, or as a [[CGI]].

  Note that the generated wrapper will ignore all command line parameters.

* --aggregate

  If the [[plugins/aggregate]] plugin is enabled, this makes ikiwiki poll
  configured feeds and save new posts to the srcdir.

  Note that to rebuild previously aggregated posts, use the --rebuild option
  along with this one. --rebuild will also force feeds to be polled even if
  they were polled recently.

* --render file

  Renders a single file, outputting the resulting html. Does not save state,
  so this cannot be used for building whole wikis, but it is useful for
  previewing an edited file at the command line. Generally used in conjunction
  with --setup to load in a wiki's setup:

	ikiwiki --setup ~/ikiwiki.setup --render foo.mdwn

* --post-commit

  Run in post-commit mode, the same as if called by a [[post-commit]] hook.
  This is probably only useful when using ikiwiki with a web server on one host
  and a repository on another, to allow the repository's real post-commit
  hook to ssh to the web server host and manually run ikiwiki to update
  the web site.

* --version

  Print ikiwiki's version number.

# CONFIG OPTIONS

These options configure the wiki. Note that [[plugins]] can add additional
configuration options of their own. All of these options and more besides can
also be configured using a setup file.

* --wikiname name

  The name of the wiki, default is "wiki".

* --templatedir dir

  Specify the directory that [[templates|templates]] are stored in.
  Default is `/usr/share/ikiwiki/templates`, or another location as configured at
  build time. If the templatedir is changed, missing templates will still
  be searched for in the default location as a fallback. Templates can also be
  placed in the "templates/" subdirectory of the srcdir.

  Note that if you choose to copy and modify ikiwiki's templates, you will need
  to be careful to keep them up to date when upgrading to new versions of
  ikiwiki. Old versions of templates do not always work with new ikiwiki
  versions.

* --underlaydir dir

  Specify the directory that is used to underlay the source directory.
  Source files will be taken from here unless overridden by a file in the
  source directory. Default is `/usr/share/ikiwiki/basewiki` or another
  location as configured at build time.

* --wrappermode mode

  Specify a mode to chmod the wrapper to after creating it.

* --wrappergroup group

  Specify what unix group the wrapper should be owned by. This can be
  useful if the wrapper needs to be owned by a group other than the default.
  For example, if a project has a repository with multiple committers with
  access controlled by a group, it makes sense for the ikiwiki wrappers
  to run setgid to that group.

* --rcs=svn|git|.., --no-rcs

  Enable or disable use of a [[revision_control_system|rcs]].

  The `source` directory will be assumed to be a working copy, or clone, or
  whatever the revision control system you select uses.

  In [[CGI]] mode, with a revision control system enabled, pages edited via
  the web will be committed.

  No revision control is enabled by default.

* --svnrepo /svn/wiki

  Specify the location of the svn repository for the wiki.

* --svnpath trunk

  Specify the path inside your svn repository where the wiki is located.
  This defaults to `trunk`; change it if your wiki is at some other path
  inside the repository. If your wiki is rooted at the top of the repository,
  set svnpath to "".

* --rss, --norss

  If rss is set, ikiwiki will default to generating RSS feeds for pages
  that inline a [[blog]].

* --allowrss

  If allowrss is set, and rss is not set, ikiwiki will not default to
  generating RSS feeds, but setting `rss=yes` in the inline directive can
  override this default and generate a feed.

* --atom, --noatom

  If atom is set, ikiwiki will default to generating Atom feeds for pages
  that inline a [[blog]].

* --allowatom

  If allowatom is set, and rss is not set, ikiwiki will not default to
  generating Atom feeds, but setting `atom=yes` in the inline directive can
  override this default and generate a feed.

* --pingurl URL

  Set this to the URL of an XML-RPC service to ping when an RSS feed is
  updated. For example, to ping Technorati, use the URL
  http://rpc.technorati.com/rpc/ping

  This parameter can be specified multiple times to specify more than one
  URL to ping.

* --url URL

  Specifies the URL to the wiki. This is a required parameter in [[CGI]] mode.

* --cgiurl http://example.org/ikiwiki.cgi

  Specifies the URL to the ikiwiki [[CGI]] script wrapper. Required when
  building the wiki for links to the cgi script to be generated.

* --historyurl URL

  Specifies the URL to link to for page history browsing. In the URL,
  "\[[file]]" is replaced with the file to browse. It's common to use
  [[ViewVC]] for this.

* --adminemail you@example.org

  Specifies the email address that ikiwiki should use for sending email.

* --diffurl URL

  Specifies the URL to link to for a diff of changes to a page. In the URL,
  "\[[file]]" is replaced with the file to browse, "\[[r1]]" is the old
  revision of the page, and "\[[r2]]" is the new revision. It's common to use
  [[ViewVC]] for this.

* --exclude regexp

  Specifies a rexexp of source files to exclude from processing.
  May be specified multiple times to add to exclude list.

* --include regexp

  Specifies a rexexp of source files, that would normally be excluded,
  but that you wish to include in processing.
  May be specified multiple times to add to include list.

* --adminuser name

  Specifies a username of a user (or, if openid is enabled, an openid) 
  who has the powers of a wiki admin. Currently allows locking of any page,
  and [[banning|banned_users]] users, as well as powers granted by
  enabled plugins (such as [[moderating comments|plugins/moderatedcomments]] 
  and [[plugins/websetup]]. May be specified multiple times for multiple
  admins.

  For an openid user specify the full URL of the login, including "http://".

* --plugin name

  Enables the use of the specified [[plugin|plugins]] in the wiki. 
  Note that plugin names are case sensitive.

* --disable-plugin name

  Disables use of a plugin. For example "--disable-plugin htmlscrubber"
  to do away with HTML sanitization.

* --libdir directory

  Makes ikiwiki look in the specified directory first, before the regular
  locations when loading library files and plugins. For example, if you set
  libdir to "/home/you/.ikiwiki/", you can install a foo.pm plugin as
  "/home/you/.ikiwiki/IkiWiki/Plugin/foo.pm".

* --discussion, --no-discussion

  Enables or disables "Discussion" links from being added to the header of
  every page. The links are enabled by default.

* --numbacklinks n

  Controls how many backlinks should be displayed at the bottom of a page.
  Excess backlinks will be hidden in a popup. Default is 10. Set to 0 to
  disable this feature.

* --userdir subdir

  Optionally, allows links to users of the wiki to link to pages inside a
  subdirectory of the wiki. The default is to link to pages in the toplevel
  directory of the wiki.

* --htmlext html

  Configures the extension used for generated html files. Default is "html".

* --timeformat format

  Specify how to display the time or date. The format string is passed to the
  strftime(3) function.

* --verbose, --no-verbose

  Be verbose about what is being done.

* --syslog, --no-syslog

  Log to syslog(3).

* --usedirs, --no-usedirs

  Toggle creating output files named page/index.html (default) instead of page.html.

* --prefix-directives, --no-prefix-directives

  Toggle new '!'-prefixed syntax for preprocessor directives.  ikiwiki currently
  defaults to --prefix-directives.

* --w3mmode, --no-w3mmode

  Enable [[w3mmode]], which allows w3m to use ikiwiki as a local CGI script,
  without a web server.

* --sslcookie

  Only send cookies over an SSL connection. This should prevent them being
  intercepted. If you enable this option then you must run at least the 
  CGI portion of ikiwiki over SSL.

* --gettime, --no-gettime

  Extract creation and modification times for each new page from the
  the revision control's log. This is done automatically when building a
  wiki for the first time, so you normally do not need to use this option.

* --set var=value
  
  This allows setting an arbitrary configuration variable, the same as if it
  were set via a setup file. Since most commonly used options can be
  configured using command-line switches, you will rarely need to use this.

* --set-yaml var=value

  This is like --set, but it allows setting configuration variables that
  use complex data structures, by passing in a YAML document.

# EXAMPLES

* ikiwiki --setup my.setup

  Completely (re)build the wiki using the specified setup file.

* ikiwiki --setup my.setup --refresh

  Refresh the wiki, using settings from my.setup, and avoid
  rebuilding any pages that have not changed. This is faster.

* ikiwiki --setup my.setup --refresh --wrappers

  Refresh the wiki, including regenerating all wrapper programs,
  but do not rebuild all pages. Useful if you have changed something
  in the setup file that does not need a full wiki rebuild to update
  all pages, but that you want to immediately take effect.

* ikiwiki --rebuild srcdir destdir

  Use srcdir as source and build HTML in destdir, without using a
  setup file.

* ikiwiki srcdir destdir

  Use srcdir as source to update changed pages' HTML in destdir,
  without using a setup file.

# ENVIRONMENT

* CC

  This controls what C compiler is used to build wrappers. Default is 'cc'.

* CFLAGS

  This can be used to pass options to the C compiler when building wrappers.

# SEE ALSO

* [[ikiwiki-mass-rebuild]](8)
* [[ikiwiki-update-wikilist]](1)
* [[ikiwiki-transition]](1)

# AUTHOR

Joey Hess <joey@ikiwiki.info>

Warning: Automatically converted into a man page by mdwn2man. Edit with care
