/* bvw-widget.vala
 *
 * Copyright (C) 2008 Víctor Jáquez <vjaquez@igalia.com>
 *
 * License Header
 *
 */

using Gdk;

namespace Bvw {
	public interface Widget: GLib.Object {
		public abstract void set_logo (string filename);
		public abstract void set_logo_pixbuf (Gdk.Pixbuf logo);
		public abstract void set_fullscreen (bool fullscreen);

		public abstract bool logo_mode { get; set; }
		public abstract bool show_cursor { get; set; }
		public abstract bool auto_resize { get; set; }
  }
}