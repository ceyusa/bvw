/* test.vala
 *
 * Copyright (C) 2008 Víctor Jáquez
 *
 * License Header
 *
 */

using Bvw;
using Gst;

public class PlayerTest {
	 static int main (string[] args) {
		  Gst.init (ref args);
		  Gtk.init (ref args);

		  Gtk.Window win;
		  Bvw.Player player;
		  Bvw.Widget video_widget;

		  try {
			   player = new Bvw.PlayerGst (10, 10, Bvw.UseType.VIDEO);
		  } catch (Bvw.Error ex) {
			   printerr ("Error: %s\n", ex.message);
			   return -1;
		  }

		  win = new Gtk.Window (Gtk.WindowType.TOPLEVEL);
		  win.set_title ("Bacon Video Widget Test");
		  win.destroy += Gtk.main_quit;

		  video_widget = new Bvw.WidgetGtk (player);
		  video_widget.set_logo ("./gnome_logo.gif");
		  video_widget.logo_mode = true;

		  win.add (video_widget as Gtk.Widget);

		  win.show_all ();

		  Gtk.main ();
		  return 0;
	 }
}
