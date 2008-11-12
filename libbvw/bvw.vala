/* bvw.vala
 *
 * Copyright (C) 2008 Víctor Jáquez
 *
 * License Header
 *
 */

using Gdk;
using Gtk;

namespace Bvw
{
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
  
  public interface Player: GLib.Object
  {
    // Actions
    public abstract bool open (string mrl) throws Error;
    public abstract bool play () throws Error;
    public abstract void pause ();
    public abstract bool is_playing ();
    public abstract void stop ();
    public abstract void close ();

    // Seeking and lenght
    public abstract bool is_seekable ();
    public abstract bool seek (double position) throws Error;
    public abstract bool seek_time (int64 time) throws Error;
    public abstract bool can_direct_seek ();
    public abstract double position { get; }
    public abstract int64 current_time { get; }
    public abstract int64 stream_length { get; }

    // Audio volume
    public abstract bool can_set_volume ();
    public abstract double volume { get; set; }

    // Properties
    public abstract string logo { set; }
    public abstract Gdk.Pixbuf logo_pixbuf { set; }
    public abstract bool logo_mode { get; set; }
    public abstract bool fullscreen { set; }
    public abstract bool show_cursor { get; set; }
    public abstract bool auto_resize { get; set; }
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