/* bvw-widget-gtk.vala
 *
 * Copyright (C) 2008 Víctor Jáquez <vjaquez@igalia.com>
 *
 * License Header
 *
 */

using Gtk;

namespace Bvw {
	private struct PrefSize {
		public int width;
		public int height;
	}

	public class WidgetGtk : Gtk.EventBox, Widget {
		private Gdk.Window video_window;
		private Gtk.Allocation video_window_allocation;

		private Gdk.Pixbuf logo_pixbuf = null;
		private bool _logo_mode = false;

		private PrefSize pref_size;

		public Player player { get; construct; }

		construct {
			this.set_flags (Gtk.WidgetFlags.CAN_FOCUS);
			this.unset_flags (Gtk.WidgetFlags.DOUBLE_BUFFERED);
		}

		public WidgetGtk (Player player) {
			this.player = player;
			this.set_visible_window (true);
		}

		// Widget interface
		public void set_logo (string filename) {
			try {
				logo_pixbuf = new Gdk.Pixbuf.from_file (filename);
			} catch (GLib.Error err) {
				warning ("An error ocurred trying to open logo %s: %s",
						 filename, err.message);
			}
		}

		public void set_logo_pixbuf (Gdk.Pixbuf logo) {
			logo_pixbuf = logo;
		}

		// @todo
		public void set_fullscreen (bool fullscreen) {
		}

		public bool logo_mode {
			get {
				return this._logo_mode;
			}

			set {
				value = value != false;
				if (this._logo_mode != value) {
					this._logo_mode = value;

					if (this.video_window != null) {
						if (this._logo_mode == true) {
							this.video_window.hide ();
							this.set_flags (Gtk.WidgetFlags.DOUBLE_BUFFERED);
						} else {
							this.video_window.show ();
							this.unset_flags (Gtk.WidgetFlags.DOUBLE_BUFFERED);
						}

						// @todo
						//this.player.notify ("seekable");

						this.queue_draw ();
					}
				}
			}
		}

		public bool show_cursor { get; set; }
		public bool auto_resize { get; set; }

		public void get_media_size (out int width, out int height) {
			if (this._logo_mode) {
				if (this.logo_pixbuf != null) {
					width = this.logo_pixbuf.get_width ();
					height = this.logo_pixbuf.get_height ();
				} else {
					width = 0;
					height = 0;
				}
			} else {
				this.player.get_media_size (out width, out height);
			}
		}

		public override void size_request (out Gtk.Requisition requisition) {
			requisition.width = 240;
			requisition.height = 180;
		}

		public override void size_allocate (Gdk.Rectangle allocation) {
			this.allocation = (Gtk.Allocation) allocation;

			if ((this.get_flags () & Gtk.WidgetFlags.REALIZED) != 0) {
				float width, height, ratio;
				int w, h;

				this.window.move_resize (allocation.x, allocation.y,
										 allocation.width, allocation.height);

				this.get_media_size (out w, out h);
				if (w == 0 || h == 0) {
					w = allocation.width;
					h = allocation.height;
				}

				width = w;
				height = h;

				if ((float) allocation.width / width >
					(float) allocation.height / height) {
					ratio = (float) allocation.height / height;
				} else {
					ratio = (float) allocation.width / width;
				}

				width *= ratio;
				height *= ratio;

				this.video_window_allocation.width = (int) width;
				this.video_window_allocation.height = (int) height;
				this.video_window_allocation.x =
				(int) (allocation.width - width) / 2;
				this.video_window_allocation.y =
				(int) (allocation.height - height) / 2;
				this.video_window.move_resize
				((int) (allocation.width - width) / 2,
				 (int) (allocation.height - height) / 2,
				 (int) width, (int) height);
				this.queue_draw ();
			}
		}

		private new bool configure_event (Gtk.Widget widget,
										  Gdk.EventConfigure event) {
			// @todo
			this.player.x_overlay_expose ();
			return false;
		}

		private void setup_vis () {
			this.player.setup_vis ();

			if (this.player.has_audio && this.player.has_video
				&& this.video_window != null) {
				if (this.player.show_vfx) {
					this.video_window.show ();
					this.unset_flags (Gtk.WidgetFlags.DOUBLE_BUFFERED);
				} else {
					this.video_window.hide ();
					this.set_flags (Gtk.WidgetFlags.DOUBLE_BUFFERED);
				}

				this.queue_draw ();
			}
		}

		private void size_changed_cb (Gdk.Screen screen) {
			this.setup_vis ();
		}

		private bool cb_unset_size () {
			this.queue_resize_no_redraw ();
			return false;
		}

		private void cb_set_preferred_size (Gtk.Widget widget,
											out Gtk.Requisition requisition) {
			requisition.width = this.pref_size.width;
			requisition.height = this.pref_size.height;

			this.size_request.disconnect (this.cb_set_preferred_size);

			Idle.add (this.cb_unset_size);
		}

		private void set_preferred_size (int width, int height) {
			this.pref_size = PrefSize ();

			this.pref_size.width = width;
			this.pref_size.height = height;

			this.size_request.connect (this.cb_set_preferred_size);

			this.queue_resize ();
		}

		public override void realize () {
			var attributes = Gdk.WindowAttr ();
			int attributes_mask, w, h;
			Gdk.Color colour;

			int event_mask = this.get_events ()
			| Gdk.EventMask.POINTER_MOTION_MASK
			| Gdk.EventMask.KEY_PRESS_MASK;

			this.set_events (event_mask);

			base.realize ();

			// Creating our video window
			attributes.window_type = Gdk.WindowType.CHILD;
			attributes.x = 0;
			attributes.y = 0;
			attributes.width = this.allocation.width;
			attributes.height = this.allocation.height;
			attributes.wclass = Gdk.WindowClass.INPUT_OUTPUT;
			attributes.event_mask = this.get_events ();
			attributes.event_mask |= Gdk.EventMask.EXPOSURE_MASK
			| Gdk.EventMask.POINTER_MOTION_MASK
			| Gdk.EventMask.BUTTON_PRESS_MASK
			| Gdk.EventMask.KEY_PRESS_MASK;
			attributes_mask = Gdk.WindowAttributesType.X
			| Gdk.WindowAttributesType.Y;
			this.video_window = new Gdk.Window (this.get_parent_window (),
												attributes, attributes_mask);
			this.video_window.set_user_data (this);

			Gdk.Color.parse ("black", out colour);
			this.get_colormap ().alloc_color (colour, true, true);
			this.window.set_background (colour);
			this.style = this.style.attach (this.window);

			this.set_flags (Gtk.WidgetFlags.REALIZED);

			// Connect to configure event on the top level window
			this.get_toplevel ().configure_event.connect (this.configure_event);

			// get screen size changes
			this.get_screen ().size_changed.connect (this.size_changed_cb);

			// nice hack to show the logo fullsize, while still being resizable
			this.get_media_size (out w, out h);
			this.set_preferred_size (w, h);

			// @todo
			//   this.player.missing_plugins_setup ();
			//   this.bacon_resize = new Bvw.Resize (this);
		}

		public override void unrealize () {
			// @todo
			// this.bacon_resize = null;
			this.video_window.set_user_data (null);
			this.video_window.destroy ();
			this.video_window = null;

			base.unrealize ();
		}

		public override void show () {
			if (this.window != null) {
				this.window.show ();
			}

			if (this.video_window != null) {
				this.video_window.show ();
			}

			base.show ();
		}

		public override void hide () {
			if (this.window != null) {
				this.window.hide ();
			}

			if (this.video_window != null) {
				this.video_window.hide ();
			}

			base.hide ();
		}

		public override bool expose_event (Gdk.EventExpose event) {
			bool draw_logo;

			// fixme event != null
			if (event.count > 0) {
				return true;
			}

			// @todo:
			// find/update the xoverlay in the player
			this.player.xwindow_id = Gdk.x11_drawable_get_xid (this.window);

			// start with a nice black canvas
			this.window.draw_rectangle (this.style.black_gc, true, 0, 0,
										this.allocation.width,
										this.allocation.height);

			// if there's only audio and no visualisation,
			// draw the logo as well
			draw_logo = this.player.has_audio
			&& !this.player.has_video
			&& !this.player.show_vfx;

			if (this._logo_mode == true || draw_logo == true) {
				if (this.logo_pixbuf != null) {
					int s_width, s_height, w_width, w_height;

					var rect = Gdk.Rectangle ();
					rect.x = rect.y = 0;
					rect.width = this.allocation.width;
					rect.height = this.allocation.height;

					Gdk.Region region = Gdk.Region.rectangle (rect);
					this.window.begin_paint_region (region);
					region = null;

					this.window.clear_area (0, 0,
											this.allocation.width,
											this.allocation.height);

					s_width = this.logo_pixbuf.get_width ();
					s_height = this.logo_pixbuf.get_height ();
					w_width = this.allocation.width;
					w_height = this.allocation.height;

					float ratio;

					if ((float) w_width / s_width >
						(float) w_height / s_height) {
						ratio = (float) w_height / s_height;
					} else {
						ratio = (float) w_width / s_width;
					}

					s_width *= (int) ratio;
					s_height *= (int) ratio;

					if (s_width <= 1 || s_height <= 1) {
						this.window.end_paint ();
						return true;
					}

					Gdk.Pixbuf logo = this.logo_pixbuf.scale_simple
					(s_width, s_height, Gdk.InterpType.BILINEAR);

					this.window.draw_pixbuf (this.style.fg_gc[0], logo, 0, 0,
											 (w_width - s_width) / 2,
											 (w_height - s_height) / 2,
											 s_width, s_height,
											 Gdk.RgbDither.NONE, 0, 0);

					this.window.end_paint ();
				} else if (this.window != null) {
					this.window.clear_area (0, 0,
											this.allocation.width,
											this.allocation.height);
				}
			} else {
				if (!this.player.x_overlay_expose ()) {
					this.window.clear_area (0, 0,
											this.allocation.width,
											this.allocation.height);
				}
			}

			return true;
		}

		public override bool motion_notify_event (Gdk.EventMotion event) {
			bool res = false;

			if (!this._logo_mode) {
				res = this.player.set_mouse_event ("mouse-move", 0,
												   event.x, event.y);
			}

			// res |= base.motion_notify_event (event);
			return res;
		}

		public override bool button_press_event (Gdk.EventButton event) {
			bool res = false;

			if (!this._logo_mode) {
				res = this.player.set_mouse_event ("mouse-button-press",
												   (int) event.button,
												   event.x, event.y);
			}

			// res |= base.button_press_event (event);
			return res;
		}

		public override bool button_release_event (Gdk.EventButton event) {
			bool res = false;

			if (!this._logo_mode) {
				res = this.player.set_mouse_event ("mouse-button-release",
												   (int) event.button,
												   event.x, event.y);
			}

			// res |= base.button_release_event (event);
			return res;
		}
	}
}
