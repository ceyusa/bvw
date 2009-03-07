/* gst-player.vala
 *
 * Copyright (C) 2008 Víctor Jáquez <vjaquez@igalia.com>
 *
 * License Header
 *
 */

using Gst;
using GConf;

namespace Bvw {
	public class PlayerGst: GLib.Object, Player {
		private string mrl = null;
		private bool vis_changed;
		private bool got_redirect;
		private Gst.MessageType ignore_messages_mask;
		private Gst.Element _playbin = null;
		private Gst.Bus bus;
		private Gst.DebugCategory logger;
		private GConf.Client gc;

		construct {
			logger.init ("bvw", 0, "Bacon Video Widget");
			string version = Gst.version_string ();
			logger.debug ("Initialised %s", version);
			Gst.pb_utils_init ();
		}

		public PlayerGst (int width, int height, UseType type) throws Error {
			Gst.Element audio_sink;
			Gst.Element video_sink;

			this._playbin = Gst.ElementFactory.make ("playbin2", "play");

			if (this._playbin == null) {
				this.ref_sink ();
				this = null;
				throw new Error.PLUGIN_LOAD
				("Failed to create a GStreamer playbin object. " +
				 "Please check your GStreamer installation.");
			}

			this.bus = this._playbin.get_bus ();
			this.bus.add_signal_watch ();
			this.bus.message += bus_message_cb;

			this.gc = GConf.Client.get_default ();
			this.gc.notify_add ("/apps/bvw", gconf_notify_cb);

			if (type == Bvw.UseType.VIDEO || type == Bvw.UseType.AUDIO) {
				audio_sink = Gst.ElementFactory.make ("gconfaudiosink",
													  "audio-sink");
				if (audio_sink == null) {
					warning ("Could not create element 'gconfaudiosink'");
					// Try to fallback on autoaudiosink
					audio_sink = Gst.ElementFactory.make ("autoaudiosink",
														  "audio-sink");
				} else {
					// set the profile property on the gconfaudiosink to
					// "music and movies"
					if (((ObjectClass) audio_sink.get_type ().class_peek ()).find_property ("profile") != null) {
						audio_sink.set ("profile", 1, null);
					}
				}
			} else {
				audio_sink = Gst.ElementFactory.make ("fakesink",
													  "audio-fake-sink");
			}

			if (type == Bvw.UseType.VIDEO) {
				if (width > 0 && width < SMALL_STREAM_WIDTH &&
					height > 0 && height < SMALL_STREAM_HEIGHT) {
					this.logger.info ("forcing ximagesink, image size only %dx%d",
									  width, height);
					video_sink = Gst.ElementFactory.make ("ximagesink",
														  "video-sink");
				} else {
					video_sink = Gst.ElementFactory.make ("gconfvideosink",
														  "video-sink");
					if (video_sink == null) {
						warning ("Could not create element 'gconfvideosink'");
						// Try to fallback on ximagesink
						video_sink = Gst.ElementFactory.make ("ximagesink",
															  "video-sink");
					}
				}
			} else {
				video_sink = Gst.ElementFactory.make ("fakesink",
													  "video-fake-sink");
				if (video_sink != null) {
					video_sink.set ("sync", true, null);
				}

				if (video_sink != null) {
					Gst.StateChangeReturn ret;

					// need to set bus explicity as it's not in a bin yet and
					// poll_for_state_change () needs one to catch error
					// messages
					video_sink.set_bus (this.bus);
					// state change NULL => READY should always be synchronous
					ret = video_sink.set_state (Gst.State.READY);
					if (ret == Gst.StateChangeReturn.FAILURE) {
						video_sink.set_state (Gst.State.NULL);
						video_sink.unref ();

						// Try again with ximagesink
						video_sink = Gst.ElementFactory.make ("fakesink",
															  "video-fake-sink");
						video_sink.set_bus (this.bus);
						ret = video_sink.set_state (Gst.State.READY);
						if (ret == Gst.StateChangeReturn.FAILURE) {
							Gst.Message err_msg;

							err_msg = this.bus.poll (Gst.MessageType.ERROR, 0);
							if (err_msg == null) {
								warning ("Should have gotten an error message, please file a bug.");
								throw new Error.VIDEO_PLUGIN ("Failed to open video output. It may no be available. Please select another video output in the Multmedia Systems Selector.");
							}
						}
					}
				}
			}
		}

		// @todo
		private void setup_vis () {
		}

		public bool open (string mrl) throws Error {
			// So we aren't closed yet...
			if (this.mrl != null) {
				this.close ();
			}

			// this allows non-URI type of files in the thumbnailer and so on
			File file = GLib.File.new_for_commandline_arg (mrl);

			// Only use the URI when FUSE isn't available for a file
			string path = file.get_path ();

			if (path != null) {
				try {
					this.mrl = GLib.Filename.to_uri (path, null);
				} catch {
					this.mrl = mrl;
				}
			} else {
				this.mrl = mrl;
			}

			this.got_redirect = false;
			this.media_has_video = false;
			this.media_has_audio = false;
			this._stream_length = 0;
			this.ignore_messages_mask = 0;

			// We hide the video window for now. Will show when video of vfx comes up
			//if (bvw->priv->video_window) {
			//  gdk_window_hide (bvw->priv->video_window);
			// We also take the whole widget until we know video size
			//  gdk_window_move_resize (bvw->priv->video_window, 0, 0,
			//                          GTK_WIDGET (bvw)->allocation.width,
			//                          GTK_WIDGET (bvw)->allocation.height);
			//}

			if (this.vis_changed == true) {
				this.setup_vis ();
			}

			if (this.mrl.str ("#subtitle:") != null) {
				string subtitle_uri;
				string[2] uris;

				uris = this.mrl.split ("#subtitle:", 2);

				if (uris[1][0] == '/') {
					subtitle_uri = "file://%s".printf (uris[1]);
				} else {
					if (uris[1].chr (-1, ':') != null) {
						subtitle_uri = uris[1];
					} else {
						string cur_dir = GLib.Environment.get_current_dir ();
						if (cur_dir == null) {
							throw new Error.GENERIC ("Failed to retrieve working directory");
						}
						subtitle_uri = "file://%s/%s".printf (cur_dir, uris[1]);
					}
				}

				// this.play.uri = this.mrl;
			} else {
				// this.play.uri = this.mrl;
				// this.play.suburi = subtitle_uri;
			}

			return true;
		}

		public bool play () throws Error {
			return true;
		}

		public void pause () {
		}

		public bool is_playing () {
			return true;
		}

		public void stop () {
		}

		public void close () {
		}

		public Gst.Element playbin {
			get { return this._playbin; }
		}

		public bool seekable { get; set; }

		public bool seek (double position) throws Error {
			return true;
		}

		public bool seek_time (int64 time) throws Error {
			return true;
		}

		public bool can_direct_seek () {
			return true;
		}

		private double _position;
		public double position { get { return _position; } }

		private int64 _current_time;
		public int64 current_time { get { return _current_time; } }

		private int64 _stream_length;
		public int64 stream_length { get { return _stream_length; }  }

		public void get_media_size (out int width, out int height) {
		}

		public bool x_overlay_expose () {
			return true;
		}

		public void x_overlay_update () {
		}

		public void set_xwindow_id (ulong xwindow_id) {
		}

		public bool set_mouse_event (string event, int button,
									 double x, double y) {
			return true;
		}

		public bool media_has_video;
		public bool has_video { get { return media_has_video; } }

		public bool media_has_audio;
		public bool has_audio { get { return media_has_audio; } }

		public bool _show_vfx = false;
		public bool show_vfx { get { return _show_vfx; } }

		public bool can_set_volume () {
			return true;
		}

		public double volume { get; set; }

		public int connection_speed { get; set; }

		private void bus_message_cb (Gst.Bus bus, Gst.Message message) {
			if ((this.ignore_messages_mask & message.type) != 0) {
				this.logger.log ("Ignoring %s message from element %p " +
								 "as resquested: %p",
								 message.type.to_string (), message.src,
								 message);
				return;
			}

			if (message.type != Gst.MessageType.STATE_CHANGED) {
				string src_name = message.src.get_name ();
				this.logger.log ("Handing %s message from element %s",
								 message.type.to_string (), src_name);
			}

			switch (message.type) {
			case Gst.MessageType.ERROR:
				this.error_msg (message);
				break;
			case Gst.MessageType.WARNING:
				this.logger.warning ("Warning message %p", message);
				break;
			case Gst.MessageType.TAG:
				break;
			case Gst.MessageType.EOS:
				break;
			case Gst.MessageType.BUFFERING:
				break;
			case Gst.MessageType.APPLICATION:
				break;
			case Gst.MessageType.STATE_CHANGED:
				break;
			case Gst.MessageType.ELEMENT:
				break;
			case Gst.MessageType.DURATION:
				break;
			case Gst.MessageType.CLOCK_PROVIDE:
			case Gst.MessageType.CLOCK_LOST:
			case Gst.MessageType.NEW_CLOCK:
			case Gst.MessageType.STATE_DIRTY:
				break;
			default:
				this.logger.log ("Unhandled message %p", message);
				break;
			}
		}

		private void error_msg (Gst.Message msg) {
			Error err = null;
			string dbg = null;

			Gst.debug_bin_to_dot_file (this._playbin as Gst.Bin,
									   Gst.DebugGraphDetails.ALL,
									   "bvw-error");

			msg.parse_error (out err, out dbg);
			if (err != null) {
				this.logger.error ("message = %s", err.message);
				this.logger.error ("domain  = %d (%s)", err.domain,
								   err.domain.to_string ());
				this.logger.error ("code    = %d", err.code);
				this.logger.error ("debug   = %s", dbg);
				this.logger.error ("source  = %p", msg.src);
				this.logger.error ("uri     = %s", this.mrl);

				message ("Error: %s\n%s\n", err.message, dbg);
			}
		}

		private void gconf_notify_cb (GConf.Client client, uint cnxn_id,
									  GConf.Entry entry) {
			if (entry.key == "/apps/bvw/network-buffer-threshold") {
				this._playbin.set ("queue-threshold",
								   (uint64) Gst.SECOND * entry.value.get_float (),
								   null);
			} else if (entry.key == "/apps/bvw/buffer-size") {
				this._playbin.set ("queue-size",
								   (uint64) Gst.SECOND * entry.value.get_float (),
								   null);
			}
		}
	}
}