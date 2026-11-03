/* emozi-x11.c: Xlib helpers for Emozi.
 *
 * - Global hotkey: XGrabKey on the root window plus a GDK event filter.
 * - Window activation: _NET_ACTIVE_WINDOW client messages (EWMH).
 * - Typing: temporarily map unused keycodes to Unicode keysyms and fake
 *   key presses with XTest (the same technique as xdotool). Each codepoint of
 *   a sequence gets its *own* keycode, and mappings are only restored after
 *   an idle period, so slow clients that re-read the keymap late still see
 *   the right keysyms.
 */
#include "emozi-x11.h"

#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/XKBlib.h>
#include <X11/extensions/XTest.h>

#define RESTORE_DELAY_MS 2000

static Display *
get_xdisplay (void)
{
  GdkDisplay *display = gdk_display_get_default ();
  if (display == NULL || !GDK_IS_X11_DISPLAY (display))
    return NULL;
  return GDK_DISPLAY_XDISPLAY (display);
}

gboolean
emozi_x11_is_active (void)
{
  return get_xdisplay () != NULL;
}

guint32
emozi_x11_get_server_time (GdkWindow *window)
{
  if (window == NULL || !GDK_IS_X11_WINDOW (window))
    return GDK_CURRENT_TIME;
  return gdk_x11_get_server_time (window);
}

/* ------------------------------------------------------------------ */
/* Active window                                                       */

gulong
emozi_x11_get_active_window (void)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL)
    return 0;

  GdkDisplay *display = gdk_display_get_default ();
  Atom prop = XInternAtom (dpy, "_NET_ACTIVE_WINDOW", False);
  Atom actual_type;
  int actual_format;
  unsigned long nitems, bytes_after;
  unsigned char *data = NULL;
  gulong result = 0;

  gdk_x11_display_error_trap_push (display);
  int status = XGetWindowProperty (dpy, DefaultRootWindow (dpy), prop, 0, 1, False,
                                   XA_WINDOW, &actual_type, &actual_format,
                                   &nitems, &bytes_after, &data);
  gdk_x11_display_error_trap_pop_ignored (display);

  if (status == Success && data != NULL && actual_type == XA_WINDOW &&
      actual_format == 32 && nitems == 1)
    result = (gulong) *(Window *) data;

  if (data != NULL)
    XFree (data);
  return result;
}

gboolean
emozi_x11_get_window_rect (gulong xid, GdkRectangle *rect)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL || xid == 0)
    return FALSE;

  GdkDisplay *display = gdk_display_get_default ();
  XWindowAttributes attrs;
  Window child;
  int x = 0, y = 0;

  gdk_x11_display_error_trap_push (display);
  Status ok = XGetWindowAttributes (dpy, (Window) xid, &attrs);
  if (ok)
    XTranslateCoordinates (dpy, (Window) xid, DefaultRootWindow (dpy), 0, 0, &x, &y, &child);
  int err = gdk_x11_display_error_trap_pop (display);

  if (!ok || err != 0)
    return FALSE;

  rect->x = x;
  rect->y = y;
  rect->width = attrs.width;
  rect->height = attrs.height;
  return TRUE;
}

void
emozi_x11_activate_window (gulong xid, guint32 timestamp)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL || xid == 0)
    return;

  GdkDisplay *display = gdk_display_get_default ();
  XEvent ev = { 0 };
  ev.xclient.type = ClientMessage;
  ev.xclient.window = (Window) xid;
  ev.xclient.message_type = XInternAtom (dpy, "_NET_ACTIVE_WINDOW", False);
  ev.xclient.format = 32;
  ev.xclient.data.l[0] = 2; /* source indication: pager (bypasses focus-stealing prevention) */
  ev.xclient.data.l[1] = timestamp;
  ev.xclient.data.l[2] = 0;

  gdk_x11_display_error_trap_push (display);
  XSendEvent (dpy, DefaultRootWindow (dpy), False,
              SubstructureRedirectMask | SubstructureNotifyMask, &ev);
  XFlush (dpy);
  gdk_x11_display_error_trap_pop_ignored (display);
}

/* ------------------------------------------------------------------ */
/* Global hotkey                                                       */

/* Grab with every combination of these "lock" modifiers so the hotkey works
 * regardless of CapsLock / NumLock state. */
static const guint ignored_masks[] = { 0, LockMask, Mod2Mask, LockMask | Mod2Mask };
#define RELEVANT_MODS (ShiftMask | ControlMask | Mod1Mask | Mod3Mask | Mod4Mask | Mod5Mask)

static struct {
  gboolean           grabbed;
  KeyCode            keycode;
  guint              mods;
  gboolean           down;
  EmoziX11HotkeyFunc func;
  gpointer           user_data;
  gboolean           filter_installed;
} hotkey;

static GdkFilterReturn
hotkey_filter (GdkXEvent *gdk_xevent, GdkEvent *event, gpointer data)
{
  XEvent *xev = (XEvent *) gdk_xevent;

  if (!hotkey.grabbed || (xev->type != KeyPress && xev->type != KeyRelease))
    return GDK_FILTER_CONTINUE;
  if (xev->xkey.keycode != hotkey.keycode)
    return GDK_FILTER_CONTINUE;

  if (xev->type == KeyRelease)
    {
      hotkey.down = FALSE;
      return GDK_FILTER_REMOVE;
    }

  if ((xev->xkey.state & RELEVANT_MODS) != hotkey.mods)
    return GDK_FILTER_CONTINUE;

  /* With detectable auto-repeat, holding the key yields repeated presses
   * without releases; only react to the first one. */
  if (hotkey.down)
    return GDK_FILTER_REMOVE;
  hotkey.down = TRUE;

  if (hotkey.func != NULL)
    hotkey.func ((guint32) xev->xkey.time, hotkey.user_data);
  return GDK_FILTER_REMOVE;
}

void
emozi_x11_hotkey_ungrab (void)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL || !hotkey.grabbed)
    return;

  GdkDisplay *display = gdk_display_get_default ();
  gdk_x11_display_error_trap_push (display);
  for (guint i = 0; i < G_N_ELEMENTS (ignored_masks); i++)
    XUngrabKey (dpy, hotkey.keycode, hotkey.mods | ignored_masks[i], DefaultRootWindow (dpy));
  XSync (dpy, False);
  gdk_x11_display_error_trap_pop_ignored (display);

  hotkey.grabbed = FALSE;
  hotkey.down = FALSE;
}

gboolean
emozi_x11_hotkey_grab (const char         *accelerator,
                       EmoziX11HotkeyFunc  func,
                       gpointer            user_data,
                       GError            **error)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL)
    {
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                           "Global shortcuts via XGrabKey need an X11 session");
      return FALSE;
    }

  GdkDisplay *display = gdk_display_get_default ();
  guint keyval = 0;
  GdkModifierType gdk_mods = 0;
  gtk_accelerator_parse (accelerator, &keyval, &gdk_mods);
  if (keyval == 0)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                   "“%s” is not a valid shortcut", accelerator);
      return FALSE;
    }

  /* Translate virtual modifiers (Super, Hyper, Meta) to real ones (Mod4…). */
  gdk_keymap_map_virtual_modifiers (gdk_keymap_get_for_display (display), &gdk_mods);
  guint mods = gdk_mods & RELEVANT_MODS;

  KeyCode keycode = XKeysymToKeycode (dpy, (KeySym) keyval);
  if (keycode == 0)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                   "The key in “%s” is not on the current keyboard layout", accelerator);
      return FALSE;
    }

  emozi_x11_hotkey_ungrab ();

  if (!hotkey.filter_installed)
    {
      XkbSetDetectableAutoRepeat (dpy, True, NULL);
      gdk_window_add_filter (gdk_get_default_root_window (), hotkey_filter, NULL);
      hotkey.filter_installed = TRUE;
    }

  gdk_x11_display_error_trap_push (display);
  for (guint i = 0; i < G_N_ELEMENTS (ignored_masks); i++)
    XGrabKey (dpy, keycode, mods | ignored_masks[i], DefaultRootWindow (dpy),
              False, GrabModeAsync, GrabModeAsync);
  XSync (dpy, False);
  int err = gdk_x11_display_error_trap_pop (display);

  hotkey.keycode = keycode;
  hotkey.mods = mods;
  hotkey.grabbed = TRUE;

  if (err != 0)
    {
      emozi_x11_hotkey_ungrab ();
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_EXISTS,
                   "The shortcut “%s” is already used by another application", accelerator);
      return FALSE;
    }

  hotkey.func = func;
  hotkey.user_data = user_data;
  hotkey.down = FALSE;
  return TRUE;
}

/* ------------------------------------------------------------------ */
/* Typing                                                              */

static GArray *pending_keycodes; /* KeyCodes we remapped and must restore */
static guint restore_source;

static void
restore_keycodes_now (void)
{
  Display *dpy = get_xdisplay ();

  if (restore_source != 0)
    {
      g_source_remove (restore_source);
      restore_source = 0;
    }
  if (dpy == NULL || pending_keycodes == NULL || pending_keycodes->len == 0)
    return;

  GdkDisplay *display = gdk_display_get_default ();
  KeySym nosym[8] = { NoSymbol, NoSymbol, NoSymbol, NoSymbol,
                      NoSymbol, NoSymbol, NoSymbol, NoSymbol };

  gdk_x11_display_error_trap_push (display);
  for (guint i = 0; i < pending_keycodes->len; i++)
    XChangeKeyboardMapping (dpy, g_array_index (pending_keycodes, KeyCode, i), 1, nosym, 1);
  XSync (dpy, False);
  gdk_x11_display_error_trap_pop_ignored (display);

  g_array_set_size (pending_keycodes, 0);
}

static gboolean
restore_timeout_cb (gpointer data)
{
  restore_source = 0;
  restore_keycodes_now ();
  return G_SOURCE_REMOVE;
}

static KeySym
keysym_for_codepoint (gunichar c)
{
  /* Latin-1 keysyms are identical to their codepoints; everything else
   * uses the Unicode keysym range. */
  if ((c >= 0x20 && c <= 0x7e) || (c >= 0xa0 && c <= 0xff))
    return (KeySym) c;
  return (KeySym) (0x01000000 | c);
}

gboolean
emozi_x11_type_text (const char *text, GError **error)
{
  Display *dpy = get_xdisplay ();
  if (dpy == NULL)
    {
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                           "Typing needs an X11 session");
      return FALSE;
    }

  int ev_base, err_base, major, minor;
  if (!XTestQueryExtension (dpy, &ev_base, &err_base, &major, &minor))
    {
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                           "The X server does not support the XTEST extension");
      return FALSE;
    }

  if (pending_keycodes == NULL)
    pending_keycodes = g_array_new (FALSE, FALSE, sizeof (KeyCode));

  GArray *cps = g_array_new (FALSE, FALSE, sizeof (gunichar));
  for (const char *p = text; *p; p = g_utf8_next_char (p))
    {
      gunichar c = g_utf8_get_char (p);
      g_array_append_val (cps, c);
    }

  GdkDisplay *display = gdk_display_get_default ();
  gboolean ok = TRUE;
  guint done = 0;
  gboolean retried = FALSE;

  while (done < cps->len)
    {
      int min_kc, max_kc, per = 0;
      XDisplayKeycodes (dpy, &min_kc, &max_kc);
      KeySym *map = XGetKeyboardMapping (dpy, (KeyCode) min_kc, max_kc - min_kc + 1, &per);
      if (map == NULL || per <= 0)
        {
          ok = FALSE;
          break;
        }

      /* Collect keycodes with no keysyms at all (unused by the layout). */
      GArray *free_kcs = g_array_new (FALSE, FALSE, sizeof (KeyCode));
      for (int kc = min_kc; kc <= max_kc; kc++)
        {
          gboolean empty = TRUE;
          for (int j = 0; j < per; j++)
            if (map[(kc - min_kc) * per + j] != NoSymbol)
              {
                empty = FALSE;
                break;
              }
          if (empty)
            {
              KeyCode k = (KeyCode) kc;
              g_array_append_val (free_kcs, k);
            }
        }
      XFree (map);

      if (free_kcs->len == 0)
        {
          g_array_free (free_kcs, TRUE);
          if (!retried && pending_keycodes->len > 0)
            {
              /* All spare keycodes hold earlier mappings; give clients a
               * moment, then reclaim them. */
              g_usleep (100 * 1000);
              restore_keycodes_now ();
              retried = TRUE;
              continue;
            }
          ok = FALSE;
          break;
        }

      guint chunk = MIN (free_kcs->len, cps->len - done);
      KeySym *syms = g_new (KeySym, per);

      gdk_x11_display_error_trap_push (display);
      for (guint i = 0; i < chunk; i++)
        {
          KeyCode kc = g_array_index (free_kcs, KeyCode, i);
          KeySym ks = keysym_for_codepoint (g_array_index (cps, gunichar, done + i));
          for (int j = 0; j < per; j++)
            syms[j] = ks;
          XChangeKeyboardMapping (dpy, kc, per, syms, 1);
          g_array_append_val (pending_keycodes, kc);
        }
      XSync (dpy, False);

      for (guint i = 0; i < chunk; i++)
        {
          KeyCode kc = g_array_index (free_kcs, KeyCode, i);
          XTestFakeKeyEvent (dpy, kc, True, CurrentTime);
          XTestFakeKeyEvent (dpy, kc, False, CurrentTime);
        }
      XSync (dpy, False);
      int err = gdk_x11_display_error_trap_pop (display);

      g_free (syms);
      g_array_free (free_kcs, TRUE);

      if (err != 0)
        {
          ok = FALSE;
          break;
        }
      done += chunk;

      if (done < cps->len)
        {
          /* Out of spare keycodes mid-sequence (very rare): let clients
           * process what we sent before reusing keycodes. */
          g_usleep (100 * 1000);
          restore_keycodes_now ();
        }
    }

  g_array_free (cps, TRUE);

  if (restore_source != 0)
    g_source_remove (restore_source);
  restore_source = g_timeout_add (RESTORE_DELAY_MS, restore_timeout_cb, NULL);

  if (!ok)
    g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                         "Could not synthesize key events (no spare keycodes?)");
  return ok;
}
