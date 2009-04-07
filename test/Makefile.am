NULL =

AM_CPPFLAGS = 				\
	$(GTK_CFLAGS) 			\
	$(GST_CFLAGS) 			\
	-include $(CONFIG_HEADER)	\
	-I $(top_srcdir)/libbvw		\
	$(NULL)

bin_PROGRAMS =	\
	test	\
	$(NULL)

BUILT_SOURCES = test.vala.stamp

test_VALASOURCES =	\
	test.vala
	$(NULL)

test_SOURCES = 				\
	test.vala.stamp			\
	$(test_VALASOURCES:.vala=.c)	\
	$(NULL)

valac_common =				\
	--quiet				\
	--ccode				\
	--vapidir ../libbvw		\
	--pkg libbvw-1.0		\
	--pkg gtk+-2.0			\
	--pkg gstreamer-0.10		\
	$(NULL)

test.vala.stamp: $(test_VALASOURCES)
	$(VALAC) $(valac_common) $^
	touch $@

test_LDADD =			\
	$(GTK_LIBS)		\
	$(GST_LIBS)		\
	../libbvw/libbvw-1.0.la	\
	$(NULL)

EXTRA_DIST = 			\
	$(test_VALASOURCES)	\
	test.vala.stamp 	\
	$(NULL)

