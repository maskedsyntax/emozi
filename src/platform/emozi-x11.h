/* emozi-x11.h: small Xlib helpers (global hotkey, window activation,
 * synthetic Unicode typing) used from Vala via emozi-x11.vapi. */
#pragma once

#include <gtk/gtk.h>

G_BEGIN_DECLS

typedef void (*EmoziX11HotkeyFunc) (guint32 timestamp, gpointer user_data);

gboolean emozi_x11_is_active          (void);
guint32  emozi_x11_get_server_time    (GdkWindow *window);
gulong   emozi_x11_get_active_window  (void);
gboolean emozi_x11_get_window_rect    (gulong xid, GdkRectangle *rect);
void     emozi_x11_activate_window    (gulong xid, guint32 timestamp);

gboolean emozi_x11_hotkey_grab        (const char         *accelerator,
                                       EmoziX11HotkeyFunc  func,
                                       gpointer            user_data,
                                       GError            **error);
void     emozi_x11_hotkey_ungrab      (void);

gboolean emozi_x11_type_text          (const char *text, GError **error);

G_END_DECLS
