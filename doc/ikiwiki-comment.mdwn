# NAME

ikiwiki-comment - posts a comment

# SYNOPSIS

ikiwiki-comment page.mdwn

# DESCRIPTION

`ikiwiki-comment` creates a comment for the specified wiki page file,
and opens your editor to edit it.

Once you're done, it's up to you to add the comment to whatever version
control system is being used by the wiki, and do any necessary pushing to
publish it.

Note that since ikiwiki-comment is not passed the configuration of
the wiki it's acting on, it doesn't know what types of markup are
available. Instead, it always removes one level of extensions from the
file, so when run on a page.mdwn file, it puts the comment in page/

The username field is set to the unix account name you're using.
You may want to edit it to match the username you use elsewhere
on the wiki.

# AUTHOR

Joey Hess <joey@ikiwiki.info>

Warning: this page is automatically made into ikiwiki-comments's man page, edit with care
