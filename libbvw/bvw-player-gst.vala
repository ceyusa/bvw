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
	private class MissingPlugins : GLib.Object {
		// list of Gst.Messages
		public GLib.List<Gst.Message> list = new GLib.List<Gst.Message> ();

		private const string[] blacklisted_elements = { "ffdemux_flv" };

		delegate string MsgToStrFunc (Gst.Message msg);

		private string[] get_foo (MsgToStrFunc func) {
			string[] arr = new string[list.length () + 1];
			int i = 0;

			foreach (Gst.Message msg in list) {
				arr[i++] = func (msg);
			}
			arr[i] = null;
			return arr;
		}

		public string[] get_details () {
			return get_foo (Gst.missing_plugin_message_get_installer_detail);
		}

		public string[] get_descriptions () {
			return get_foo (Gst.missing_plugin_message_get_description);
		}

		public uint length () {
			return list.length ();
		}

		public void add (Gst.Message msg) {
			list.prepend (msg);
		}

		public void blacklist () {
			foreach (string element in blacklisted_elements) {
				Gst.PluginFeature feature =
				Gst.Registry.get_default ().find_feature
				(element, typeof (Gst.ElementFactory));

				if (feature != null) {
					feature.set_rank (Gst.Rank.NONE);
				}
			}
		}

	}

	public class PlayerGst: GLib.Object, Player {
		Gst.XOverlay xoverlay = null;    // protect with lock
		Gst.ColorBalance balance = null; // protect with lock
		uint col_update_id = 0;          // protect with lock
		GLib.Mutex @lock;

		private string mrl = null;
		private bool got_redirect;
		private Gst.MessageType ignore_messages_mask;
		private Gst.Element _play = null;
		private Gst.Bus bus;
		private Gst.DebugCategory logger;
		private GConf.Client gc;

		// Visual effects
		private bool vis_changed;
		private Gst.Element audio_capsfilter;

		// other stuff
		private bool uses_fakesink = false;

		// for easy codec installation
		private MissingPlugins missing_plugins;
		private bool plugin_install_in_progress = false;

		private string media_device = null;

		private static weak GLib.Thread gui_thread;

		construct {
			logger.init ("bvw", 0, "Bacon Video Widget");
			logger.debug ("Initialised %s", Gst.version_string ());
			Gst.pb_utils_init ();
		}

		public PlayerGst (int width, int height, UseType type) throws Error {
			this.missing_plugins = new MissingPlugins ();
			this.missing_plugins.blacklist ();

			// gconf setting in backend
			this.gc = GConf.Client.get_default ();
			this.gc.notify_add ("/apps/bvw", gconf_notify_cb);

			this.setup_pipeline (width, height, type);

			// audio out, if any
			try {
				GConf.Value confvalue = this.gc.get_without_default
				("/apps/bvw/audio_output_type");
				if (type != Bvw.UseType.METADATA
					&& type != Bvw.UseType.CAPTURE) {
					this.audio_out_type =
					(Bvw.AudioOutType) confvalue.get_int ();
				}
			} catch {
				this.audio_out_type = Bvw.AudioOutType.STEREO;
			}

			// tv/conn (not used yet)
			try {
				GConf.Value confvalue = this.gc.get_without_default
				("/apps/bvw/connection_speed");
				this.connection_speed = confvalue.get_int ();
			} catch (GLib.Error err) {
				this.connection_speed = this._connection_speed;
			}

			try {
				GConf.Value confvalue = this.gc.get_without_default
				("/apps/bvw/buffer-size");
				this._play.set ("queue-size",
								Gst.SECOND * confvalue.get_float ());
			} finally {
			}

			try {
				GConf.Value confvalue = this.gc.get_without_default
				("/app/bvw/network-buffer-threshold");
				this._play.set ("queue-threshold",
								Gst.SECOND * confvalue.get_float ());
			} finally {
			}

			// assume we're always called from te main Gtk+ GUI thread
			this.gui_thread = GLib.Thread.self ();
		}

		~PlayerGst () {
			if (this.bus != null) {
				this.bus.set_flushing (true);
				this.bus.sync_message["element"] -= this.element_msg_sync;
			}
			if (this.col_update_id != 0) {
				GLib.Source.remove (this.col_update_id);
				this.col_update_id = 0;
			}
		}

		private Gst.ColorBalanceChannel? get_color_balance_channel (Bvw.VideoProperty type) {
			unowned GLib.List<Gst.ColorBalanceChannel> channels =
			this.balance.list_channels ();

			foreach (Gst.ColorBalanceChannel c in channels) {
				if (type == Bvw.VideoProperty.BRIGHTNESS
					&& c.label == "BRIGHTNESS")
					return c;
				else if (type == Bvw.VideoProperty.CONTRAST
						 && c.label == "CONTRAST")
					return c;
				else if (type == Bvw.VideoProperty.SATURATION
						 && c.label == "SATURATION")
					return c;
				else if (type == Bvw.VideoProperty.HUE
						 && c.label == "HUE")
					return c;
			}

			return null;
		}

		public int get_video_property (Bvw.VideoProperty type) {
			this.lock.lock ();

			int ret = 0;

			if (this.balance != null
				&& this.balance is Gst.ColorBalance) {
				Gst.ColorBalanceChannel found_channel =
					this.get_color_balance_channel (type);
				if (found_channel != null
					&& found_channel is Gst.ColorBalanceChannel) {
					int cur = this.balance.get_value (found_channel);
					this.logger.debug ("channel %s: cur=%d, min=%d, max=%d",
									   found_channel.label, cur,
									   found_channel.min_value,
									   found_channel.max_value);
					ret = (int) GLib.Math.floor (0.5 +
												 ((double) cur - found_channel.min_value) * 65535 /
												 ((double) found_channel.max_value - found_channel.min_value));
					this.logger.debug ("channel %s: returning value %d",
									   found_channel.label, ret);

					this.lock.unlock ();
					return ret;
				} else {
					ret = -1;
				}
			}

			if (ret == 0) {
				try {
					ret = this.gc.get_int (video_props[type]);
				} finally {
					this.logger.debug ("nothing found for type %d, returning value %d from gconf key %s",
									   type, ret, video_props[type]);
				}
			}

			this.lock.unlock ();
			return ret;
		}

		public void set_video_property (Bvw.VideoProperty type, int value) {
			this.logger.debug ("set video property type %d to value %d",
							   type, value);

			if (!(value <= 65535 && value >= 0))
				return;

			if (this.balance != null
				&& this.balance is Gst.ColorBalance) {
				Gst.ColorBalanceChannel found_channel = this.get_color_balance_channel (type);
				if (found_channel != null
					&& found_channel is Gst.ColorBalanceChannel) {
					int i_value;

					i_value = (int) GLib.Math.floor (0.5 + value * ((double) (found_channel.max_value - found_channel.min_value) / 65535 + found_channel.min_value));

					this.logger.debug ("channel %s: set to %d/65535",
									   found_channel.label, value);

					this.balance.set_value (found_channel, i_value);

					this.logger.debug ("channel %s: val=%d, min=%d, max=%d",
									   found_channel.label, i_value,
									   found_channel.min_value,
									   found_channel.max_value);
				}
			}

			try {
				this.gc.set_int (video_props[type], value);
			} finally {
				this.logger.debug ("setting value %d on gconf key %s",
								   value, video_props[type]);
			}
		}

		private const string[] video_props = {
			"/app/bvw/brightness",
			"/app/bvw/contrast",
			"/app/bvw/saturation",
			"/app/bvw/hue"
		};

		private bool update_brightness_and_contrast () {
			GLib.return_val_if_fail (GLib.Thread.self () == this.gui_thread,
									 false);

			// Setup brightness and contrast
			this.logger.log ("updating brightness and contrast from GConf settings");
			for (uint i = 0; i < video_props.length; i++) {
				try {
					GConf.Value confvalue =
						this.gc.get_without_default (video_props[i]);
					this.set_video_property ((Bvw.VideoProperty) i,
											 confvalue.get_int ());
				} finally {
				}

			}

			return false;
		}

		private bool find_colorbalance_element (void* item, Gst.Value ret) {
			Gst.Element element = (Gst.Element) item;
			this.logger.debug ("Checking element %s ...", element.get_name ());

			if (!(element is Gst.ColorBalance))
				return true;

			this.logger.debug ("Element %s is a color balance",
							   element.get_name ());
			// TODO: howto find the GstColorBalanceType in this interface?
			// if (GST_COLOR_BALANCE_TYPE (GST_COLOR_BALANCE_GET_CLASS (element)) == GST_COLOR_BALANCE_HARDWARE)
			this.balance = (Gst.ColorBalance) element;
			return false;
		}

		private void update_interface_implementations () {
			Gst.Element video_sink = null;
			Gst.Element element;

			this._play.get ("video-sink", ref video_sink);
			assert (video_sink != null);

			// we tray to get an element supporting XOverlay interface
			if (video_sink is Gst.Bin) {
				this.logger.debug ("Retrieving xoverlay from bin ...");
				element = ((Gst.Bin) video_sink).get_by_interface (typeof (Gst.XOverlay));
			} else {
				element = video_sink;
			}

			if (video_sink is Gst.XOverlay) {
				this.logger.debug ("Found xoverlay: %s", video_sink.get_name ());
				this.xoverlay = (Gst.XOverlay) element;
			} else {
				this.logger.debug ("No xoverlay found");
				this.xoverlay = null;
			}

			// Find best color balance element (using custom iterator so
			// we can prefer hardware implementations to software ones)

			// FIXME: this doesn't work reliably yet, must of the time
			// the fold function doesn't even get called, while sometimes
			// it does...
			Gst.Iterator iter = ((Gst.Bin) this._play).iterate_all_by_interface (typeof (Gst.ColorBalance));

			Gst.Value value = Gst.Value ();
			iter.fold (find_colorbalance_element, value);

			if (this.balance == null && this.xoverlay is Gst.ColorBalance) {
				this.balance = this.xoverlay as Gst.ColorBalance;
				this.logger.debug ("Colorbalance backup found: %s",
								   this.balance.get_name ());
			} else {
				this.logger.debug ("No colorbalance found");
			}

			// Setup brightness and contrast from configured values (do it
			// delayed if we're within a stream thread, otherwise gconf/orbit/
			// whatever may iterate or otherwise mess with the default main
			// context and cause all kind of nasty issues)
			if (GLib.Thread.self () == this.gui_thread) {
				this.update_brightness_and_contrast ();
			} else {
				// caller will have acquired this.lock already
				if (this.col_update_id != 0)
					GLib.Source.remove (this.col_update_id);

				this.col_update_id = GLib.Idle.add (this.update_brightness_and_contrast);
			}
		}

		private void element_msg_sync (Gst.Bus bus, Gst.Message msg) {
			assert (msg.type == Gst.MessageType.ELEMENT);

			if (msg.structure == null)
				return;

			if (msg.structure.has_name ("prepare-xwindow-id")) {
				this.logger.debug ("Handling sync prepare-xwindow-id message");

				this.lock.lock ();
				this.update_interface_implementations ();
				this.lock.unlock ();

				GLib.return_if_fail (this.xoverlay != null);
				GLib.return_if_fail (this._xid != -1);

				this.xoverlay.set_xwindow_id (this._xid);
			}
		}

		private void got_new_video_sink_bin_element (Gst.Bin video_sink,
													 Gst.Element element) {
			this.lock.lock ();
			this.update_interface_implementations ();
			this.lock.unlock ();
		}

		private void setup_pipeline (int width,
									 int height,
									 UseType type) throws Error {
			Gst.Element audio_sink;
			Gst.Element video_sink;

			this._play = Gst.ElementFactory.make ("playbin2", "play");

			if (this._play == null) {
				this.ref_sink ();
				this = null;
				throw new Error.PLUGIN_LOAD
				("Failed to create a GStreamer playbin object. " +
				 "Please check your GStreamer installation.");
			}

			this.bus = this._play.get_bus ();
			this.bus.add_signal_watch ();
			this.bus.message += bus_message_cb;

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
						video_sink = null;

						// Try again with ximagesink
						video_sink = Gst.ElementFactory.make ("fakesink",
															  "video-fake-sink");
						video_sink.set_bus (this.bus);
						ret = video_sink.set_state (Gst.State.READY);
						if (ret == Gst.StateChangeReturn.FAILURE) {
							Gst.Message err_msg;

							err_msg = this.bus.poll (Gst.MessageType.ERROR, 0);
							if (err_msg == null) {
								warning ("Should have gotten an error message, " +
										 "please file a bug.");
								video_sink.set_state (Gst.State.NULL);
// 								this.ref ();
// 								this.ref_sink ();
// 								this = null;
								throw new
								Error.VIDEO_PLUGIN ("Failed to open video output. " +
													"It may no be available. " +
													"Please select another video " +
													"output in the Multmedia Systems Selector.");
							} else {
								video_sink.set_state (Gst.State.NULL);
								this.ref ();
								this.ref_sink ();
								this = null;
								throw this.error_from_gst_error (err_msg);
							}
						}
					} else {
						video_sink.set_state (Gst.State.NULL);
// 						this.ref ();
// 						this.ref_sink ();
// 						this = null;
						throw new
						Error.VIDEO_PLUGIN ("Failed to open video output. " +
											"It may no be available. " +
											"Please select another video " +
											"output in the Multmedia Systems Selector.");
					}
				}
			}

			if (audio_sink != null) {
				// need to set bus explicity as it's not in a bin yet and
				// we need one to catch error messages
				Gst.Bus bus = new Gst.Bus ();
				audio_sink.set_bus (bus);

				// state change NULL => READY should always be synchronous
				Gst.StateChangeReturn ret = audio_sink.set_state (Gst.State.READY);
				audio_sink.set_bus (null);

				if (ret == Gst.StateChangeReturn.FAILURE) {
					// doesn't work, drop this audio sink
					audio_sink.set_state (Gst.State.NULL);
					audio_sink = null;
					if (type != Bvw.UseType.AUDIO)
						audio_sink = Gst.ElementFactory.make ("fakesink",
															  "audio-sink");
					if (audio_sink == null) {
						Gst.Message err_msg = bus.poll (Gst.MessageType.ERROR, 0);
						if (err_msg == null) {
							warning ("Should have gotten an error message, please file a bug.");
							throw new Error.AUDIO_PLUGIN
								("Failed to open audio output. You may not have " +
								 "permission to open the sound device, or the sound " +
								 "server may not be running. " +
								 "Please select aonther audio output in the Multimedia " +
								 "System Selector.");
						} else if (err_msg != null) {
							audio_sink.set_state (Gst.State.NULL);
// 							this.ref ();
// 							this.ref_sink ();
// 							this = null;
						}
						audio_sink.set_state (Gst.State.NULL);
						throw this.error_from_gst_error (err_msg);
					}

					// make fakesink sync to the clock like a real sink
					audio_sink.set ("sync", true);
					this.logger.debug ("audio sink doesn't work, using fakesink instead");
					this.uses_fakesink = true;
				}
			} else {
// 				this.ref ();
// 				this.ref_sink ();
// 				this = null;
				throw new Error.AUDIO_PLUGIN
					("Could not find the audio output. " +
					 "You may need to install additional GStreamer plugins, or " +
					 "select another audio output in the Multimedia Systems " +
					 "Selector.");
			}

			// set back to NULL to close device again in order to avoid
			// interrupts being generated after startup while there's nothing
			// to play yet.
			audio_sink.set_state (Gst.State.NULL);

			do {
				this.audio_capsfilter = Gst.ElementFactory.make ("capsfilter",
																 "audiofilter");
				Gst.Element bin = new Gst.Bin ("audiosinkbin");
				(bin as Gst.Bin).add_many (this.audio_capsfilter, audio_sink);
				this.audio_capsfilter.link_pads ("src", audio_sink, "sink");

				Gst.Pad pad = this.audio_capsfilter.get_pad ("sink");
				bin.add_pad (new Gst.GhostPad ("sink", pad));

				audio_sink = bin;
			} while (false);

			// now tell playbin
			this._play.set ("video-sink", video_sink, null);
			this._play.set ("audio-sink", audio_sink, null);

			// this.vis_plugins_list = null;
			this._play.notify["source"] += this.playbin_source_notify_cb;
			this._play.notify["stream-info"] += this.playbin_stream_info_notify_cb;

			if (type == Bvw.UseType.VIDEO) {
				Gst.StateChangeReturn ret = video_sink.get_state (null, null, 5 * Gst.SECOND);
				if (ret != Gst.StateChangeReturn.SUCCESS) {
					this.logger.warning ("Timeout setting videosink to READY");
					throw new Error.VIDEO_PLUGIN
						("Failed to open video output. It may not be available. " +
						 "Please select another video output in the Multimedia Systems Selector.");
				}

				this.update_interface_implementations ();
			}

			// we want to catch "prepare-xwindow-id" element messages synchronously
			this.bus.set_sync_handler (this.bus.sync_signal_handler);

			this.bus.sync_message["element"] += this.element_msg_sync;

			if (video_sink is Gst.Bin) {
				// video sink bins like gconfvideosink might remove their children and
				// create new ones when set to NULL state, and they are currently set
				// to NULL state whenever playbin re-creates its internal video bin
				// (it sets all elements to NULL state befor gst_bin_remove ()ing them)
				((Gst.Bin) video_sink).element_added += this.got_new_video_sink_bin_element;
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

				// this._play.uri = this.mrl;
			} else {
				// this._play.uri = this.mrl;
				// this._play.suburi = subtitle_uri;
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
			get { return this._play; }
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

		private ulong _xid = -1;
		public ulong xwindow_id {
			set {
				if (value != _xid) {
					_xid = value;

					if (this.xoverlay == null) {
						this.lock.lock ();
						this.update_interface_implementations ();
						this.lock.unlock ();

						if (this.xoverlay != null
							&& this.xoverlay is Gst.XOverlay)
							this.xoverlay.set_xwindow_id (_xid);
					}
				}
			}
		}

		private int _connection_speed = 11;
		public int connection_speed {
			get { return _connection_speed; }
			set {
				if (value != this._connection_speed) {
					this._connection_speed = value;
					this.gc.set_int ("/apps/bvw/connection_speed", value);
				}

				if (this._play != null
					&& ((ObjectClass) this._play.get_type ().class_peek ()).find_property ("connection-speed") != null) {
					uint kbps = this.connection_speed_enum_to_kbps (value);

					this.logger.log ("Setting connection speed %d (= %d kbps)", value, kbps);
					this._play.set ("connection-speed", kbps);
				}
			}
		}

		private const uint[] speed_table = { 14400, 19200, 28800, 33600,
											 34400, 56000, 112000, 256000,
											 384000, 512000, 1536000, 10752000 };

		private uint connection_speed_enum_to_kbps (int speed) {
			GLib.return_val_if_fail (speed >= 0
									 && (uint) speed < speed_table.length, 0);

			return (speed_table[speed] / 1000)
				+ (((speed_table[speed] % 1000) != 0) ? 1 : 0);
		}

		private AudioOutType speakersetup = Bvw.AudioOutType.UNDEF;
		public AudioOutType audio_out_type {
			get { return this.speakersetup; }
			set {
				if (value == this.speakersetup)
					return;
				else if (value == Bvw.AudioOutType.AC3PASSTHRU)
					return;

				this.speakersetup = value;
				this.gc.set_int ("/apps/bvw/audio_output_type", value);

				this.set_audio_filter ();
			}
		}

		private int get_num_audio_channels () {
			int channels;

			switch (this.speakersetup) {
			case Bvw.AudioOutType.STEREO:
				channels = 2;
				break;
			case Bvw.AudioOutType.CHANNEL4:
				channels = 4;
				break;
			case Bvw.AudioOutType.CHANNEL5:
				channels = 5;
				break;
			case Bvw.AudioOutType.CHANNEL41:
				// So alsa has this as 5.1 but empty center speaker.
				// We don't really do that yet. ;-). So we'll take the
				// placebo approach.
			case Bvw.AudioOutType.CHANNEL51:
				channels = 6;
				break;
			case Bvw.AudioOutType.AC3PASSTHRU:
			default:
				GLib.return_val_if_reached (-1);
			}

			return channels;
		}

		private Gst.Caps fixate_to_num (Gst.Caps in_caps, int channels) {
			Gst.Structure s;

			Gst.Caps out_caps = in_caps.copy ();
			uint count = out_caps.get_size ();
			for (uint n = 0; n < count; n++) {
				s = out_caps.get_structure (n);
				if (s.get_value ("channels") == null)
					continue;

				// get_channel cout (or list of ~)
				s.fixate_field_nearest_int ("channels", channels);
			}

			return out_caps;
		}

		private void set_audio_filter () {
			// reset old
			this.audio_capsfilter.set ("caps", null);

			// construct possible caps to filter down to our chosen caps.
			// Start with what the audio sink supports, but limit the allowed
			// channel count to our speaker output configuration.
			Gst.Caps caps = this.audio_capsfilter.get_pad ("src").get_caps ();

			int channels = this.get_num_audio_channels ();
			if (channels == -1)
				return;

			Gst.Caps res = this.fixate_to_num (caps, channels);

			if (res != null && res.is_empty ()) {
				res = null;
			}

			this.audio_capsfilter.set ("caps", res);

			// reset
			this.audio_capsfilter.get_pad ("src").set_caps (null);
		}

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

			Gst.debug_bin_to_dot_file (this._play as Gst.Bin,
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
				this._play.set ("queue-threshold",
								(uint64) Gst.SECOND * entry.value.get_float (),
								   null);
			} else if (entry.key == "/apps/bvw/buffer-size") {
				this._play.set ("queue-size",
								(uint64) Gst.SECOND * entry.value.get_float (),
								   null);
			}
		}

		private void set_device_on_element (Gst.Element element) {
			if (((ObjectClass) element.get_type ().class_peek ()).find_property ("device") != null) {
				this.logger.debug ("Setting device to '%s'", this.media_device);
				element.set ("device", this.media_device, null);
			}
		}

		private void playbin_source_notify_cb (GLib.Object play,
											   GLib.ParamSpec p) {
			// CHECKME: do we really need these taglist frees here (tpm)?
// 			if (this.tagcache != null)
// 				this.tagcache = null;
// 			if (this.audiotags != null)
// 				this.audiotags = null;
// 			if (this.videotags != null)
// 				this.videotags = null;

			GLib.Object source = null;
			play.get ("source", ref source);

			if (source != null) {
				this.logger.debug ("Got source of type %s", source.get_type ().name ());
				this.set_device_on_element (source as Gst.Element);
			}
		}

		private void playbin_stream_info_notify_cb (GLib.Object obj,
													GLib.ParamSpec p) {
			// we're being called from the streaming thread, son don't do
			// anything here
			this.logger.log ("stream info changed");
			Gst.Message msg =
				new Gst.Message.application (this._play,
											 new Gst.Structure.empty ("notify-streaminfo"));
			this._play.post_message (msg);
		}

		private Error error_from_gst_error (Gst.Message err_msg) {
 			string src_typename = null;
 			GLib.Error e = null;
 			Error ret = null;

 			if (err_msg.src != null)
 				src_typename = err_msg.src.get_type ().name ();

 			err_msg.parse_error (out e, null);

 			if ((e.domain == Gst.resource_error_quark ()
 				 && e.code == Gst.ResourceError.NOT_FOUND)
 				|| (e.domain == Gst.resource_error_quark ()
 					&& e.code == Gst.ResourceError.OPEN_READ)) {
 				if (e.code == Gst.ResourceError.NOT_FOUND) {
 					if (err_msg.src is Gst.BaseAudioSink) {
 						ret = new Error.AUDIO_PLUGIN
 							("The requested audio output was not found. " +
 							 "Please select another audio output in the Multimedia " +
 							 "Systems Selector.");
 					} else {
 						ret = new Error.FILE_NOT_FOUND
 							("Location not found.");
 					}
 				} else {
 					ret = new Error.FILE_PERMISSION
 						("Could not open location; " +
 						 "you might not have permission to open the file.");
 				}
 			} else if (e.domain == Gst.resource_error_quark ()
 					   && e.code == Gst.ResourceError.BUSY) {
 				if (err_msg.src is Gst.BaseAudioSink) {
 					ret = new Error.AUDIO_BUSY
 					("The audio output is in use by another application. " +
 					 "Please select another audio output in the Multimedia Systems Selector. " +
 					 "You may want to consider using a sound server.");
 				} else {
 					ret = new Error.VIDEO_PLUGIN
 					("The video output is in use by another application. " +
 					 "Please close other video applications, or select " +
 					 "another video output in the Multimedia Systems Selector.");
 				}
  			} else if (e.domain == Gst.resource_error_quark ()) {
  				ret =  new Error.FILE_GENERIC (e.message);
  			} else if ((e.domain == Gst.core_error_quark ()
  						&& e.code == Gst.CoreError.MISSING_PLUGIN)
  					   || (e.domain == Gst.stream_error_quark ()
  						   && e.code == Gst.StreamError.CODEC_NOT_FOUND)) {
  				if (this.missing_plugins.length () > 0) {
					string msg = null;
					string[] descs = this.missing_plugins.get_descriptions ();
					uint num = this.missing_plugins.length ();

					if (e.domain == Gst.core_error_quark ()
						&& e.code == Gst.CoreError.MISSING_PLUGIN) {
						msg = "The playback of this movie requires a %s plugin which is not installed".printf (descs[0]);
					} else {
						string desc_list = string.joinv ("\n", descs);
						msg = "The playback of this movie requires the following decodesr which are not installed: \n\n%s".printf (desc_list);
					}

					ret = new Error.CODEC_NOT_HANDLED (msg);
  				} else {
  					this.logger.log ("no missing plugin messages, " +
  									 "posting generic error");
  					ret = new Error.CODEC_NOT_HANDLED (e.message);
  				}
  			} else if ((e.domain == Gst.stream_error_quark ()
  						&& e.code == Gst.StreamError.WRONG_TYPE)
  					   || (e.domain == Gst.stream_error_quark ()
  						   && e.code == Gst.StreamError.NOT_IMPLEMENTED)) {
  				if (src_typename != null) {
  					ret = new Error.CODEC_NOT_HANDLED
  					("%s: %s,", src_typename, e.message);
  				} else {
  					ret = new Error.CODEC_NOT_HANDLED (e.message);
  				}
  			} else if ((e.domain == Gst.stream_error_quark ()
  						&& e.code == Gst.StreamError.FAILED)
  					   && src_typename == "GstTypeFind") {
  				ret = new Error.READ_ERROR
  				("Cannot play this file over the network. " +
  				 "Try downloading it to disk first.");
  			} else {
  				// generic error, no code; take message
  				ret = new Error.GENERIC (e.message);
 			}

 			this.missing_plugins = null;
			return ret;
		}
	}
}
