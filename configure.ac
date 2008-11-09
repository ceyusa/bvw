m4_define (bvw_version_major, 0)
m4_define (bvw_version_minor, 1)
m4_define (bvw_version_micro, 0)

AC_INIT([gdata-vala], 
		      [bvw_version_major.bvw_version_minor.bvw_version_micro], 
		      [vjaquez@igalia.com])

AC_CONFIG_SRCDIR([libbvw/bvw.vala])
AC_CONFIG_HEADERS(config.h)
AM_INIT_AUTOMAKE([dist-bzip2 no-dist-gzip])
AM_MAINTAINER_MODE

AC_PROG_CC
AM_PROG_CC_C_O
AC_DISABLE_STATIC
AC_PROG_LIBTOOL

AC_PATH_PROG(VALAC, valac, valac)
AC_SUBST(VALAC)

AH_TEMPLATE([GETTEXT_PACKAGE], [Package name for gettext])
GETTEXT_PACKAGE=gdata-vala
AC_DEFINE_UNQUOTED(GETTEXT_PACKAGE, "$GETTEXT_PACKAGE")
AC_SUBST(GETTEXT_PACKAGE)
AM_GLIB_GNU_GETTEXT
IT_PROG_INTLTOOL([0.35.0])

AC_SUBST(CFLAGS)
AC_SUBST(CPPFLAGS)
AC_SUBST(LDFLAGS)

# Requirements
GLIB_REQS=2.12.0
GTK_REQS=2.12.0
VALA_REQS=0.5.0

GST_MAJORMINOR=0.10
GST_REQS=0.10.12
GSTPLUG_REQS=0.10.12

PKG_CHECK_MODULES(MISSING_PLUGINS, gstreamer-plugins-base-0.10, 
	[MISSING_PLUGINS_LIBS="$MISSING_PLUGINS_LIBS -lgstpbutils-0.10"
		AC_DEFINE([ENABLE_MISSING_PLUGIN_INSTALLATION], 1, 
			[Whether we can and want to do installation of missing plugins])
	])

MM="gstreamer-0.10 >= $GST_REQS gstreamer-base-0.10 >= $GST_REQS gstreamer-plugins-base-0.10 >= $GSTPLUG_REQS gstreamer-tag-0.10 >= $GSTPLUG_REQS gconf-2.0"

PKG_CHECK_MODULES(GST, $MM)

GST_LIBS="$GST_LIBS -lgstbase-$GST_MAJORMINOR -lgstinterfaces-$GST_MAJORMINOR -lgstvideo-$GST_MAJORMINOR -lgstaudio-$GST_MAJORMINOR -lgstpbutils-$GST_MAJORMINOR -lgsttag-$GST_MAJORMINOR"
AC_SUBST(GST_LIBS)

EXTRA_BACKEND_LIBS="-lgstinterfaces-$GST_MAJORMINOR -lgstvideo-$GST_MAJORMINOR -lgstaudio-$GST_MAJORMINOR -lgstpbutils-$GST_MAJORMINOR"

dnl Check for required plugins
gst010_toolsdir=`$PKG_CONFIG --variable=toolsdir gstreamer-0.10`
gst010_inspect="$gst010_toolsdir/gst-inspect-0.10"

dnl Give error and exit if we don't have the gst_inspect tool
AC_MSG_CHECKING([GStreamer 0.10 inspection tool])
if test -r "$gst010_inspect"; then
	AC_MSG_RESULT([yes])
else
	AC_MSG_RESULT([no])
	AC_MSG_ERROR([
		Cannot find required GStreamer-0.10 tool 'gst-inspect-0.10'.
		It should be part of gstreamer-0_10-utils. Please install it.
		])
fi

dnl Check for elements from gst-plugins-base
for base_element in playbin ffmpegcolorspace videoscale
do
	AC_MSG_CHECKING([GStreamer 0.10 $base_element plugin])
	if $gst010_inspect $base_element >/dev/null 2>/dev/null; then
		AC_MSG_RESULT([yes])
	else
		AC_MSG_RESULT([no])
		AC_MSG_ERROR([
			Cannot find required GStreamer-0.10 plugin '$base_element'.
			It should be part of gst-plugins-base. Please install it.
		])
	fi
done

dnl Check for elements from gst-plugins-good
for good_element in gconfaudiosink gconfvideosink goom
do
	AC_MSG_CHECKING([GStreamer 0.10 $good_element plugin])
	if $gst010_inspect $good_element >/dev/null 2>/dev/null; then
		AC_MSG_RESULT([yes])
	else
		AC_MSG_RESULT([no])
		AC_MSG_ERROR([
			Cannot find required GStreamer-0.10 plugin '$good_element'.
			It should be part of gst-plugins-good. Please install it.
		])
	fi
done


dnl Pkg-config checks

PKG_CHECK_MODULES([DEPENDENCY],[
                  glib-2.0 >= $GLIB_REQS
                  gtk+-2.0 >= $GTK_REQS
                  gconf-2.0])

PKG_CHECK_MODULES(MM, $MM)

PKG_CHECK_MODULES([GTK],[gtk+-2.0 gthread-2.0])
GTK_LIBS="$GTK_LIBS $EXTRA_BACKEND_LIBS"
AC_SUBST(GTK_LIBS)

AC_SUBST([EXTRA_BACKEND_LIBS])

if test "$GCC" = "yes" ; then
	CFLAGS="\
	-Wall \
	-Wchar-subscripts -Wmissing-declarations -Wmissing-prototypes \
	-Wnested-externs -Wpointer-arith \
	-Wcast-align -Wsign-compare \
	-fno-strict-aliasing \
	$CFLAGS"
fi

AC_SUBST([AM_CPPFLAGS])
AC_SUBST([AM_CFLAGS])
AC_SUBST([AM_CXXFLAGS])
AC_SUBST([AM_LDFLAGS])

AC_CONFIG_FILES([
	Makefile
	libbvw/Makefile
	po/Makefile.in
])

AC_OUTPUT
