/* bvw-player.vala
 *
 * Copyright (C) 2008 Víctor Jáquez <vjaquez@igalia.com>
 *
 * License Header
 *
 */

namespace Bvw {
	public errordomain Error {
		// Plugins
		AUDIO_PLUGIN,
		NO_PLUGIN_FOR_FILE,
		VIDEO_PLUGIN,
		AUDIO_BUSY,
		// File
		BROKEN_FILE,
		FILE_GENERIC,
		FILE_PERMISSION,
		FILE_ENCRYPTED,
		FILE_NOT_FOUND,
		// Devices
		DVD_ENCRYPTED,
		INVALID_DEVICE,
		DEVICE_BUSY,
		// Network
		UNKNOWN_HOST,
		NETWORK_UNREACHABLE,
		CONNECTION_REFUSED,
		// Generic
		UNVALID_LOCATION,
		GENERIC,
		CODEC_NOT_HANDLED,
		AUDIO_ONLY,
		CANNOT_CAPTURE,
		READ_ERROR,
		PLUGIN_LOAD,
		EMPTY_FILE
	}

	public enum UseType {
		VIDEO,
		AUDIO,
		CAPTURE,
		METADATA
	}

	public enum VisualsQuality {
		SMALL = 0,
		NORMAL,
		LARGE,
		EXTRA_LARGE,
		NUM_QUALITIES
	}

	public const int SMALL_STREAM_WIDTH = 200;
	public const int SMALL_STREAM_HEIGHT = 120;

	public interface Player: GLib.Object {
		// Actions
		public abstract bool open (string mrl) throws Error;
		public abstract bool play () throws Error;
		public abstract void pause ();
		public abstract bool is_playing ();
		public abstract void stop ();
		public abstract void close ();

		// Seeking and lenght
		public abstract bool seekable { get; set; }
		public abstract bool seek (double position) throws Error;
		public abstract bool seek_time (int64 time) throws Error;
		public abstract bool can_direct_seek ();
		public abstract double position { get; }
		public abstract int64 current_time { get; }
		public abstract int64 stream_length { get; }

		//****
		// widget adapters
		//
		public abstract void get_media_size (out int width, out int height);
		// returns true if there's a Xoverlay to expose
		// bacon-video-widtet-gst-0.10.c:bacon_video_widget_configure_event:632
		// bacon-video-widtet-gst-0.10.c:bacon_video_widget_expose_event:743
		public abstract bool x_overlay_expose ();
		// update_interface_implementation (finds gst interfaces)
		// bacon-video-widtet-gst-0.10.c:bacon_video_widget_expose_event:657
		public abstract void x_overlay_update ();
		public abstract void set_xwindow_id (ulong xwindow_id);
		// returns true if there's a GstNavigation interface
		// bacon-video-widtet-gst-0.10.c:bacon_video_widget_motion_notify:774
		public abstract bool set_mouse_event (string event, int button,
											  double x, double y);
		public abstract bool has_video { get; }
		public abstract bool has_audio { get; }
		public abstract bool show_vfx { get; }

		// Audio volume
		public abstract bool can_set_volume ();
		public abstract double volume { get; set; }

		// Properties
		public abstract int connection_speed { get; set; }

		// Signals
		public signal void error (string message,
								  bool playback_stopped, bool fatal);
		public signal void eos ();
		public signal void tick (int64 current_time, int64 stream_length,
								 double current_position, bool seekable);
		public signal void buffering (uint progress);
	}
}