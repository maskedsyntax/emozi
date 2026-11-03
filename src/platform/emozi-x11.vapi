[CCode (cheader_filename = "emozi-x11.h", lower_case_cprefix = "emozi_x11_")]
namespace Emozi.X11 {
    [CCode (cname = "EmoziX11HotkeyFunc", has_target = true)]
    public delegate void HotkeyFunc (uint32 timestamp);

    public bool is_active ();
    public uint32 get_server_time (Gdk.Window? window);
    public ulong get_active_window ();
    public bool get_window_rect (ulong xid, out Gdk.Rectangle rect);
    public void activate_window (ulong xid, uint32 timestamp);
    public bool hotkey_grab (string accelerator, HotkeyFunc func) throws GLib.Error;
    public void hotkey_ungrab ();
    public bool type_text (string text) throws GLib.Error;
}
