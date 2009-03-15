AC_INIT([bvw], [0.1.0], [vjaquez@igalia.com])

AC_CONFIG_SRCDIR([libbvw/bvw-widget.vala])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([foreign dist-bzip2 no-dist-gzip])
AC_CONFIG_MACRO_DIR([m4])
AM_MAINTAINER_MODE

AC_PROG_CC
AC_PROG_LIBTOOL

SHAVE_INIT([m4], [enable])

AC_PATH_PROG(VALAC, [valac], [no])
if test "x$VALA" == "xno"; then
   AC_MSG_ERROR([Cannot find the "valac" compiler in your PATH])
fi

# Requirements
GLIB_REQS=2.12.0
GTK_REQS=2.12.0
VALA_REQS=0.5.0

GST_MAJORMINOR=0.10
GST_REQS=0.10.12
GSTPLUG_REQS=0.10.12

PKG_CHECK_MODULES([VALA], [vala-1.0 >= $VALA_REQS])

PKG_CHECK_MODULES([GST], [
	gstreamer-0.10 >= $GST_REQS
	gstreamer-base-0.10 >= $GST_REQS
	gstreamer-plugins-base-0.10 >= $GSTPLUG_REQS
	gstreamer-pbutils-0.10 >= $GST_REQS 
	gstreamer-audio-0.10 >= $GST_REQS
	gconf-2.0])

PKG_CHECK_MODULES([GTK], [
	glib-2.0 >= $GLIB_REQS
	gtk+-2.0 >= $GTK_REQS,
	gthread-2.0])

AC_CONFIG_FILES([
	m4/shave
	m4/shave-libtool
	Makefile
	libbvw/Makefile
	test/Makefile
])

AC_OUTPUT
