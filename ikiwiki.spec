Name:           ikiwiki
Version: 3.20141017
Release:        1%{?dist}
Summary:        A wiki compiler

Group:          Applications/Internet
License:        GPLv2+
URL:            http://ikiwiki.info/
Source0:	http://ftp.debian.org/debian/pool/main/i/%{name}/%{name}_%{version}.tar.gz
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
BuildRequires:  perl(YAML::XS)
BuildRequires:  gettext
BuildRequires:  po4a

Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

Requires:       perl(Text::Markdown)
Requires:       perl(Mail::Sendmail)
Requires:       perl(HTML::Scrubber)
Requires:       perl(XML::Simple)
Requires:       perl(CGI::FormBuilder)
Requires:       perl(CGI::Session)

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
%{_libdir}/ikiwiki
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
