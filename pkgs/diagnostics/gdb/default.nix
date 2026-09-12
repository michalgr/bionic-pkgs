# pkgs/diagnostics/gdb/default.nix
# GNU Debugger (GDB) & gdbserver cross-compiled for Android 14+ (Bionic libc).

{
  lib,
  stdenv,
  fetchurl,
  pkg-config,
  texinfo,
  perl,
  buildPackages,
  readline,
  zstd,
  xz,
  zlib,
  gmp,
  mpfr,
  expat,
  ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gdb";
  version = "17.2";

  src = fetchurl {
    url = "mirror://gnu/gdb/gdb-${finalAttrs.version}.tar.xz";
    hash = "sha256-R4f0S96vY+T1i/yT70O6Tee9X5M8j3073L54V7N6S+Y=";
  };

  # Build out-of-tree to prevent source tree pollution during Autotools build
  preConfigure = ''
    mkdir _build
    cd _build
  '';
  configureScript = "../configure";

  depsBuildBuild = [
    buildPackages.stdenv.cc
  ];

  nativeBuildInputs = [
    pkg-config
    texinfo
    perl
    buildPackages.stdenv.cc
  ];

  buildInputs = [
    readline
    zstd
    xz
    zlib
    gmp
    mpfr
    expat
    ncurses
  ];

  env = {
    # Resolve Gnulib fortify collisions with Bionic <bits/fortify/stdio.h>
    NIX_CFLAGS_COMPILE = "-D__USE_FORTIFY_LEVEL=0";
  };

  postPatch = ''
    # 1. Template Deduction Failure on Overloaded ::open (gdbsupport/eintr.h)
    if [ -f gdbsupport/eintr.h ]; then
      substituteInPlace gdbsupport/eintr.h \
        --replace-warn 'return gdb::handle_eintr (-1, ::open, pathname, flags);' \
                       'int ret; do { errno = 0; ret = ::open(pathname, flags); } while (ret == -1 && errno == EINTR); return ret;' \
        --replace-warn 'return gdb::handle_eintr (-1, ::open, pathname, flags, mode);' \
                       'int ret; do { errno = 0; ret = ::open(pathname, flags, mode); } while (ret == -1 && errno == EINTR); return ret;'
    fi

    # 2. Hardcoded /bin/sh and /tmp (gdbsupport/pathstuff.cc & gdb/compile/compile.c)
    if [ -f gdbsupport/pathstuff.cc ]; then
      substituteInPlace gdbsupport/pathstuff.cc \
        --replace-warn 'return "/tmp";' 'return "/data/local/tmp";' \
        --replace-warn 'ret = "/bin/sh";' 'ret = "/system/bin/sh";' \
        --replace-warn '"/bin/sh"' '"/system/bin/sh"'
    fi

    if [ -f gdb/compile/compile.c ]; then
      substituteInPlace gdb/compile/compile.c \
        --replace-warn '#define TMP_PREFIX "/tmp/gdbobj-"' '#define TMP_PREFIX "/data/local/tmp/gdbobj-"'
    fi

    # 3. False-Positive Signal Disposition Warnings (gdbsupport/signals-state-save-restore.cc)
    if [ -f gdbsupport/signals-state-save-restore.cc ]; then
      substituteInPlace gdbsupport/signals-state-save-restore.cc \
        --replace-warn 'for (sig = 1; sig < NSIG; ++sig)' '#ifndef __ANDROID__' \
        --replace-warn 'signal (sig, dummy_handler);' 'signal (sig, dummy_handler); #endif' || true
      sed -i '/save_signals_state/,/}/ s/for (int sig = 1; sig < NSIG; ++sig)/#ifndef __ANDROID__\n  for (int sig = 1; sig < NSIG; ++sig)/' gdbsupport/signals-state-save-restore.cc || true
      sed -i '/save_signals_state/,/}/ s/^\( *\)signal (sig, dummy_handler);/\1signal (sig, dummy_handler);\n#endif/' gdbsupport/signals-state-save-restore.cc || true
    fi

    # 4. Job Control setpgid (gdbsupport/job-control.cc)
    if [ -f gdbsupport/job-control.cc ]; then
      substituteInPlace gdbsupport/job-control.cc \
        --replace-warn 'retval = setpgid (getpid (), getpid ());' 'retval = setpgid (0, 0);' \
        --replace-warn 'setpgid (getpid (), getpid ())' 'setpgid (0, 0)'
    fi

    # 5. Dynamic Page Size Compatibility on 64-bit Bionic (gdb/nat/linux-btrace.c)
    if [ -f gdb/nat/linux-btrace.c ]; then
      sed -i '1s/^/#include <unistd.h>\n#ifndef PAGE_SIZE\n#define PAGE_SIZE ((size_t) sysconf(_SC_PAGESIZE))\n#endif\n/' gdb/nat/linux-btrace.c
    fi

    # 6. Default Shared Library Search Path (gdb/solib.c)
    if [ -f gdb/solib.c ]; then
      substituteInPlace gdb/solib.c \
        --replace-warn 'char *solib_search_path = NULL;' \
                       'char *solib_search_path = (char *) "${
                         if stdenv.hostPlatform.is64bit then
                           "/system/lib64:/system/vendor/lib64"
                         else
                           "/system/lib:/system/vendor/lib"
                       }";'
    fi

    # 7. gdbserver Auxv Detection (gdbserver/configure)
    if [ -f gdbserver/configure ]; then
      substituteInPlace gdbserver/configure \
        --replace-warn '*-*-android*)' '*-*-disabled_android*)'
    fi

    # 8. x86_64-android Register Assertion (gdb/amd64-linux-nat.c)
    if [ -f gdb/amd64-linux-nat.c ]; then
      substituteInPlace gdb/amd64-linux-nat.c \
        --replace-warn 'gdb_static_assert (FS < ELF_NGREG);' '#ifndef __ANDROID__\ngdb_static_assert (FS < ELF_NGREG);\n#endif' \
        --replace-warn 'gdb_static_assert (GS < ELF_NGREG);' '#ifndef __ANDROID__\ngdb_static_assert (GS < ELF_NGREG);\n#endif'
    fi
  '';

  configureFlags = [
    "--enable-gdbserver"
    "--enable-inprocess-agent"
    "--with-system-readline"
    "--with-system-zlib"
    "--with-zstd"
    "--with-expat"
    "--with-gmp"
    "--with-mpfr"
    "--with-curses"
    "--disable-werror"
    "--disable-nls"

    # Autotools Cache Variables to bypass cross-compilation runtime checks
    "ac_cv_func_getpwent=no"
    "ac_cv_func_getpwnam=no"
    "gl_cv_func_gettimeofday_clobber=no"
    "gl_cv_func_gettimeofday_posix_signature=yes"
    "gl_cv_func_realpath_works=yes"
    "gl_cv_func_lstat_dereferences_slashed_symlink=yes"
    "gl_cv_func_memchr_works=yes"
    "gl_cv_func_stat_file_slash=yes"
    "gl_cv_func_frexp_no_libm=no"
    "gl_cv_func_strerror_0_works=yes"
    "gl_cv_func_working_strerror=yes"
    "gl_cv_func_getcwd_path_max=yes"
  ];

  enableParallelBuilding = true;

  meta = {
    description = "GNU Debugger (GDB) & companion gdbserver cross-compiled for Android 14+ (Bionic libc)";
    homepage = "https://www.gnu.org/software/gdb/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "gdb";
    needsLibcxx = true;
  };
})
