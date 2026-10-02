Name:           me_cleaner
Version:        1.2
Release:        1%{?dist}
Summary:        Tool for partial deblobbing of Intel ME/TXE firmware images

License:        GPL-3.0-or-later
URL:            https://github.com/corna/me_cleaner
Source0:        me_cleaner-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
Requires:       python3

%description
me_cleaner is a Python script able to modify an Intel ME firmware image with
the final purpose of reducing its ability to interact with the system.

Starting from Nehalem (ME version 6), the Intel ME firmware cannot be
completely removed without the PC shutting off forcefully after 30 minutes.
me_cleaner disables Intel ME during normal operation by removing non-vital
modules and setting the HAP (High Assurance Platform) or AltMeDisable bit.

%prep
%autosetup -p1 -n %{name}-%{version}

%build
%py3_build

%install
%py3_install
ln -s me_cleaner.py %{buildroot}%{_bindir}/me_cleaner
install -D -p -m 0644 man/me_cleaner.1 %{buildroot}%{_mandir}/man1/me_cleaner.1
ln -s me_cleaner.1 %{buildroot}%{_mandir}/man1/me_cleaner.py.1

%check
%{buildroot}%{_bindir}/me_cleaner --version
%{buildroot}%{_bindir}/me_cleaner.py --version

%files
%license COPYING
%doc README.md
%{_bindir}/me_cleaner
%{_bindir}/me_cleaner.py
%{python3_sitelib}/me_cleaner-%{version}-*.egg-info
%{_mandir}/man1/me_cleaner.1*
%{_mandir}/man1/me_cleaner.py.1*

%changelog
* Fri Oct 02 2026 akbar_npj <akbar.npj@protonmail.com> - 1.2-1
- Initial RPM package for Fedora Asahi Remix
