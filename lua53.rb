class Lua53 < Formula
  homepage "http://www.lua.org/"
  url "http://www.lua.org/ftp/lua-5.3.0.tar.gz"
  mirror "https://raw.githubusercontent.com/DomT4/LibreMirror/master/Lua/lua-5.3.0.tar.gz"
  sha1 "1c46d1c78c44039939e820126b86a6ae12dadfba"

  bottle do
    root_url "https://homebrew.bintray.com/bottles-versions"
    sha1 "c0a8cc59d9463554e2ec2e9be89c79c08adb1243" => :yosemite
    sha1 "b02fae800022488758c4866d3c6b5dabeefb2502" => :mavericks
    sha1 "1b54e5d0dfb81aace3bc6086b01a1fd4eee290ec" => :mountain_lion
  end

  fails_with :llvm do
    build 2326
    cause "Lua itself compiles with LLVM, but may fail when other software tries to link."
  end

  option :universal
  option "with-completion", "Enables advanced readline support"
  option "with-default-names", "Don't version-suffix the Lua installation. Conflicts with Homebrew/Lua"

  # Be sure to build a dylib, or else runtime modules will pull in another static copy of liblua = crashy
  # See: https://github.com/Homebrew/homebrew/pull/5043
  patch :DATA

  # completion provided by advanced readline power patch
  # See http://lua-users.org/wiki/LuaPowerPatches
  if build.with? "completion"
    patch do
      url "http://luajit.org/patches/lua-5.2.0-advanced_readline.patch"
      sha1 "ca405dbd126bc018980a26c2c766dfb0f82e919e"
    end
  end

  def install
    ENV.universal_binary if build.universal?

    # Use our CC/CFLAGS to compile.
    inreplace "src/Makefile" do |s|
      s.remove_make_var! "CC"
      s.change_make_var! "CFLAGS", "#{ENV.cflags} -DLUA_COMPAT_ALL $(SYSCFLAGS) $(MYCFLAGS)"
      s.change_make_var! "MYLDFLAGS", ENV.ldflags
    end

    # Fix path in the config header
    inreplace "src/luaconf.h", "/usr/local", HOMEBREW_PREFIX

    # We ship our own pkg-config file as Lua no longer provide them upstream.
    system "make", "macosx", "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}", "INSTALL_INC=#{include}/lua-5.3"
    system "make", "install", "INSTALL_TOP=#{prefix}", "INSTALL_MAN=#{man1}", "INSTALL_INC=#{include}/lua-5.3"
    (lib+"pkgconfig/lua.pc").write pc_file

    # Allows side-by-side-by-side-by-side Lua installations
    if build.without? "default-names"
      mv "#{bin}/lua", "#{bin}/lua-5.3"
      mv "#{bin}/luac", "#{bin}/luac-5.3"
      mv "#{man1}/lua.1", "#{man1}/lua-5.3.1"
      mv "#{man1}/luac.1", "#{man1}/luac-5.3.1"
      mv "#{lib}/pkgconfig/lua.pc", "#{lib}/pkgconfig/lua5.3.pc"

      ln_s "#{lib}/pkgconfig/lua5.3.pc", "#{lib}/pkgconfig/lua-5.3.pc"
      ln_s "#{include}/lua-5.3", "#{include}/lua5.3"
      ln_s "#{bin}/lua-5.3", "#{bin}/lua5.3"
      ln_s "#{bin}/luac-5.3", "#{bin}/luac5.3"

      # Patches the pkg-config file to find the correct lib names
      inreplace lib/"pkgconfig/lua5.3.pc", "Libs: -L${libdir} -llua -lm", "Libs: -L${libdir} -llua5.3 -lm"
    end
  end

  def pc_file; <<-EOS.undent
    V= 5.3
    R= 5.3.0
    prefix=#{HOMEBREW_PREFIX}
    INSTALL_BIN= ${prefix}/bin
    INSTALL_INC= ${prefix}/include/lua-5.3
    INSTALL_LIB= ${prefix}/lib
    INSTALL_MAN= ${prefix}/share/man/man1
    INSTALL_LMOD= ${prefix}/share/lua/${V}
    INSTALL_CMOD= ${prefix}/lib/lua/${V}
    exec_prefix=${prefix}
    libdir=${exec_prefix}/lib
    includedir=${prefix}/include/lua-5.3

    Name: Lua
    Description: An Extensible Extension Language
    Version: 5.3.0
    Requires:
    Libs: -L${libdir} -llua -lm
    Cflags: -I${includedir}
    EOS
  end

  test do
    system "#{bin}/lua-5.3", "-e", "print ('Ducks are cool')"
  end
end

__END__
diff --git a/Makefile b/Makefile
index 7fa91c8..a825198 100644
--- a/Makefile
+++ b/Makefile
@@ -41,7 +41,7 @@ PLATS= aix bsd c89 freebsd generic linux macosx mingw posix solaris
 # What to install.
 TO_BIN= lua luac
 TO_INC= lua.h luaconf.h lualib.h lauxlib.h lua.hpp
-TO_LIB= liblua.a
+TO_LIB= liblua.5.3.0.dylib
 TO_MAN= lua.1 luac.1

 # Lua version and release.
@@ -63,6 +63,7 @@ install: dummy
	cd src && $(INSTALL_DATA) $(TO_INC) $(INSTALL_INC)
	cd src && $(INSTALL_DATA) $(TO_LIB) $(INSTALL_LIB)
	cd doc && $(INSTALL_DATA) $(TO_MAN) $(INSTALL_MAN)
+	ln -s -f liblua.5.3.0.dylib $(INSTALL_LIB)/liblua.5.3.dylib

 uninstall:
	cd src && cd $(INSTALL_BIN) && $(RM) $(TO_BIN)
diff --git a/src/Makefile b/src/Makefile
index 2e7a412..d0c4898 100644
--- a/src/Makefile
+++ b/src/Makefile
@@ -28,7 +28,7 @@ MYOBJS=

 PLATS= aix bsd c89 freebsd generic linux macosx mingw posix solaris

-LUA_A=	liblua.a
+LUA_A=	liblua.5.3.0.dylib
 CORE_O=	lapi.o lcode.o lctype.o ldebug.o ldo.o ldump.o lfunc.o lgc.o llex.o \
	lmem.o lobject.o lopcodes.o lparser.o lstate.o lstring.o ltable.o \
	ltm.o lundump.o lvm.o lzio.o
@@ -56,11 +56,12 @@ o:	$(ALL_O)
 a:	$(ALL_A)

 $(LUA_A): $(BASE_O)
-	$(AR) $@ $(BASE_O)
-	$(RANLIB) $@
+	$(CC) -dynamiclib -install_name HOMEBREW_PREFIX/lib/liblua.5.3.dylib \
+		-compatibility_version 5.3 -current_version 5.3.0 \
+		-o liblua.5.3.0.dylib $^

 $(LUA_T): $(LUA_O) $(LUA_A)
-	$(CC) -o $@ $(LDFLAGS) $(LUA_O) $(LUA_A) $(LIBS)
+	$(CC) -fno-common $(MYLDFLAGS) -o $@ $(LUA_O) $(LUA_A) -L. -llua.5.3.0 $(LIBS)

 $(LUAC_T): $(LUAC_O) $(LUA_A)
	$(CC) -o $@ $(LDFLAGS) $(LUAC_O) $(LUA_A) $(LIBS)
@@ -110,7 +111,7 @@ linux:
	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_LINUX" SYSLIBS="-Wl,-E -ldl -lreadline"

 macosx:
-	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX" SYSLIBS="-lreadline" CC=cc
+	$(MAKE) $(ALL) SYSCFLAGS="-DLUA_USE_MACOSX -fno-common" SYSLIBS="-lreadline" CC=cc

 mingw:
	$(MAKE) "LUA_A=lua53.dll" "LUA_T=lua.exe" \
