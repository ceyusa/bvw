NULL =

AM_CPPFLAGS = 				\
	$(GTK_CFLAGS) 			\
	$(GST_CFLAGS) 			\
	-include $(CONFIG_HEADER)	\
	$(NULL)

BUILT_SOURCES = bvw.vala.stamp

lib_LTLIBRARIES = libbvw-1.0.la

libbvw_1_0_la_VALASOURCES =	\
	bvw-player.vala		\
	bvw-player-gst.vala	\
	bvw-widget.vala		\
	bvw-widget-gtk.vala	\
	$(NULL)

libbvw_1_0_la_SOURCES = 			\
	bvw.vala.stamp				\
	$(libbvw_1_0_la_VALASOURCES:.vala=.c)	\
	$(NULL)

bvwincludedir = $(includedir)/bvw-1.0
bvwinclude_HEADERS = 	\
	libbvw-1.0.h	\
	$(NULL)

valac_common = 				\
	--ccode				\
	--quiet				\
	--pkg gio-2.0			\
	--pkg gtk+-2.0			\
	--pkg gdk-2.0			\
	--pkg gdk-pixbuf-2.0		\
	--pkg gdk-x11-2.0		\
	--pkg gconf-2.0			\
	--pkg gstreamer-0.10		\
	--pkg gstreamer-interfaces-0.10	\
	--pkg gstreamer-pbutils-0.10	\
	--pkg gstreamer-audio-0.10	\
	--basedir $(top_srcdir)		\
	$(NULL)

bvw-1.0.vapi bvw.vala.stamp: $(libbvw_1_0_la_VALASOURCES)
	$(VALAC) $(valac_common)  	\
	--library=libbvw-1.0 		\
	--header=libbvw-1.0.h 		\
	$^
	touch $@

libbvw_1_0_la_LIBADD =	\
	$(GTK_LIBS) 	\
	$(GST_LIBS) 	\
	$(NULL)

vapidir = $(datadir)/vala/vapi

dist_vapi_DATA = libbvw-1.0.vapi

EXTRA_DIST =				\
	$(libbvw_1_0_la_VALASOURCES)	\
	libbvw-1.0.vapi			\
	libbvw.vala.stamp		\
	$(NULL)
