Name:           ikiwiki
Version: 3.20091024
Release:        1%{?dist}
Summary:        A wiki compiler

Group:          Applications/Internet
License:        GPLv2+
URL:            http://ikiwiki.info/
Source0:        http://ftp.debian.org/debian/pool/main/i/%{name}/%{name}_%{version}.tar.gz
Patch0:         ikiwiki-3.00-libexecdir.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

BuildRequires:  perl(Text::Markdown)
BuildRequires:  perl(Mail::Sendmail)
BuildRequires:  perl(HTML::Scrubber)
BuildRequires:  perl(XML::Simple)
BuildRequires:  perl(Date::Parse)
BuildRequires:  perl(Date::Format)
BuildRequires:  perl(HTML::Template)
BuildRequires:  perl(CGI::FormBuilder)
BuildRequires:  perl(CGI::Session)
BuildRequires:  perl(File::MimeInfo)
BuildRequires:  gettext
BuildRequires:  po4a

Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

Requires:       perl(Text::Markdown)
Requires:       perl(Mail::Sendmail)
Requires:       perl(HTML::Scrubber)
Requires:       perl(XML::Simple)
Requires:       perl(CGI::FormBuilder)
Requires:       perl(CGI::Session)
Requires:       perl(Digest::SHA1)

Requires:       python-docutils

%define cgi_bin %{_libexecdir}/w3m/cgi-bin


%description
Ikiwiki is a wiki compiler. It converts wiki pages into HTML pages
suitable for publishing on a website. Ikiwiki stores pages and history
in a revision control system such as Subversion or Git. There are many
other features, including support for blogging, as well as a large
array of plugins.


%prep
%setup0 -q -n %{name}
%patch0 -p1 -b .libexecdir

# Filter unwanted Provides:
%{__cat} << \EOF > %{name}-prov
#!/bin/sh
%{__perl_provides} $* |\
  %{__sed} -e '/perl(IkiWiki.*)/d'
EOF

%define __perl_provides %{_builddir}/%{name}/%{name}-prov
%{__chmod} +x %{__perl_provides}

# Filter Requires, all used by plugins
# - Monotone: see bz 450267
%{__cat} << \EOF > %{name}-req
#!/bin/sh
%{__perl_requires} $* |\
  %{__sed} -e '/perl(IkiWiki.*)/d' \
           -e '/perl(Monotone)/d'
EOF

%define __perl_requires %{_builddir}/%{name}/%{name}-req
%{__chmod} +x %{__perl_requires}

# goes into the -w3m subpackage
%{__cat} << \EOF > README.fedora
See http://ikiwiki.info/w3mmode/ for more information.
EOF


%build
%{__perl} Makefile.PL INSTALLDIRS=vendor PREFIX=%{_prefix}
# parallel builds currently don't work
%{__make} 


%install
%{__rm} -rf %{buildroot}
%{__make} pure_install DESTDIR=%{buildroot} W3M_CGI_BIN=%{cgi_bin}
%find_lang %{name}

# move external plugins
%{__mkdir_p} %{buildroot}%{_libexecdir}/ikiwiki/plugins
%{__mv} %{buildroot}%{_prefix}/lib/ikiwiki/plugins/* \
        %{buildroot}%{_libexecdir}/ikiwiki/plugins

# remove shebang
%{__sed} -e '1{/^#!/d}' -i \
        %{buildroot}%{_sysconfdir}/ikiwiki/auto.setup \
        %{buildroot}%{_sysconfdir}/ikiwiki/auto-blog.setup \
        %{buildroot}%{_libexecdir}/ikiwiki/plugins/proxy.py


%clean
%{__rm} -rf %{buildroot}


%files -f %{name}.lang
%defattr(-,root,root,-)
%{_bindir}/ikiwiki*
%{_sbindir}/ikiwiki*
%{_mandir}/man1/ikiwiki*
%{_mandir}/man8/ikiwiki*
%{_datadir}/ikiwiki
%dir %{_sysconfdir}/ikiwiki
%config(noreplace) %{_sysconfdir}/ikiwiki/*
# contains a packlist only
%exclude %{perl_vendorarch}
%{perl_vendorlib}/IkiWiki*
%exclude %{perl_vendorlib}/IkiWiki*/Plugin/skeleton.pm.example
%{_libexecdir}/ikiwiki
%doc README debian/changelog debian/NEWS html
%doc IkiWiki/Plugin/skeleton.pm.example


%package w3m
Summary:        Ikiwiki w3m cgi meta-wrapper
Group:          Applications/Internet
Requires:       w3m
Requires:       %{name} = %{version}-%{release}

%description w3m
Enable usage of all of ikiwiki's web features (page editing, etc) in
the w3m web browser without a web server. w3m supports local CGI
scripts, and ikiwiki can be set up to run that way using the
meta-wrapper in this package.


%files w3m
%defattr(-,root,root,-)
%doc README.fedora
%{cgi_bin}/ikiwiki-w3m.cgi


%changelog
* Thu Oct  8 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.14159265-1
- Update to 3.14159265.

* Tue Sep  1 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.1415926-1
- Update to 3.1415926 (fixes CVE-2009-2944, see bz 520543).

* Wed Aug 12 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.141592-1
- Update to 3.141592.
- po4a is needed now.

* Fri Jul 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.1415-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_12_Mass_Rebuild

* Fri Jul 17 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.1415-1
- Update to 3.1415.

* Thu Jun 11 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.14-1
- Update to 3.14.

* Fri May 15 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.12-1
- Update to 3.12.

* Tue May  5 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.11-1
- Update to 3.11.

* Sat Apr 25 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.10-1
- Update to 3.10.

* Tue Apr  7 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.09-1
- Update to 3.09.

* Fri Mar 27 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.08-1
- Update to 3.08.

* Mon Mar  9 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.07-1
- Update to 3.07.

* Thu Mar  5 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.06-1
- Update to 3.06.

* Tue Feb 24 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 3.04-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Wed Feb 18 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.04-1
- Update to 3.04.

* Mon Feb  9 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.03-1
- Update to 3.03.

* Sat Jan 10 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.01-1
- Update to 3.01.

* Fri Jan  2 2009 Thomas Moschny <thomas.moschny@gmx.de> - 3.00-1
- Update to 3.00.

* Fri Jan  2 2009 Thomas Moschny <thomas.moschny@gmx.de> - 2.72-1
- Update to 2.72.
- Patch for mtn plugin has been applied upstream.
- Encoding of ikiwiki.vim has been changed to utf-8 upstream.
- Use new W3M_CGI_BIN option in %%install.

* Tue Dec 16 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.70-3
- Patch for monotone plugin: Prevent broken pipe message.
- Cosmetic changes to satisfy rpmlint.

* Mon Dec 01 2008 Ignacio Vazquez-Abrams <ivazqueznet+rpm@gmail.com> - 2.70-2
- Rebuild for Python 2.6

* Thu Nov 20 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.70-1
- Update to 2.70.
- Install and enable the external rst plugin.
- Stop filtering perl(RPC::XML*) requires.

* Fri Oct 10 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.66-1
- Update to 2.66.

* Fri Sep 19 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.64-1
- Update to 2.64.

* Thu Sep 11 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.63-1
- Update to 2.63.

* Sat Aug 30 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.62.1-1
- Update to 2.62.1. Add /etc/ikiwiki.

* Thu Aug  7 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.56-1
- Update to 2.56.
- Stop filtering perl(Net::Amazon::S3), has been approved (bz436481).

* Thu Jul 31 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.55-1
- Update to 2.55.

* Thu Jul 24 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.54-1
- Update to 2.54.
- Move example plugin file to doc.

* Sat Jul 12 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.53-1
- Update to 2.53.

* Thu Jul 10 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.52-1
- Update to 2.52.

* Sun Jul  6 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.51-1
- Update to 2.51.
- Save iconv output to a temporary file.

* Sun Jun 15 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.50-1
- Update to 2.50.
- Move ikiwiki-w3m.cgi into a subpackage.
- Add ikiwiki's own documentation.
- Remove duplicate requirement perl(File::MimeInfo).
- Minor cleanups.

* Mon Jun  2 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.48-1
- Update to 2.48.

* Wed May 28 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.47-1
- Update to 2.47.

* Tue May 13 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.46-1
- Update to 2.46.

* Sat May 10 2008 Thomas Moschny <thomas.moschny@gmx.de> - 2.45-1
- New package.
