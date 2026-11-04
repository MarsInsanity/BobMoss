package org.darkmoss.rg552bootswitch;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;

/**
 * "SpruceOS" on the RG552's Android: the way back to dArkMoss and spruce on the TF1 card.
 *
 * spruce's "Boot to Android" saves the start of the TF1 card's boot loader into an unused area of
 * the card and blanks it, so the RG552 falls through to Android. This app runs the same
 * rg552-bootswitch script (bundled as an asset) as root to put it back, then reboots.
 *
 * One screen, driven by the A button (or a tap): it checks the card on start, then A boots into
 * spruce, or scans again when the card is not ready. B (or Back) leaves.
 *
 * Root is needed for raw access to the card. su is fed the commands on stdin, which works with
 * Magisk, SuperSU and the userdebug su alike.
 */
public class MainActivity extends Activity {

    private static final String TAG = "SpruceOS";
    private static final String SCRIPT_ASSET = "rg552-bootswitch.sh";
    private static final String FONT_ASSET = "fonts/spruce.ttf";

    // Linux input codes of the RG552's face buttons: the one labelled A reports BTN_EAST and B
    // BTN_SOUTH (rk3399-rg552-linux.dts). Android's generic key layout turns BTN_EAST into
    // BUTTON_B, so on the built-in pad the label is read from the scan code instead.
    private static final int BTN_SOUTH = 304;
    private static final int BTN_EAST = 305;

    private enum State { CHECKING, READY, NOT_BOOTABLE, NO_ROOT, BOOTING, FAILED }

    private final Handler ui = new Handler(Looper.getMainLooper());
    private SpruceView view;
    private State state = State.CHECKING;
    // "android": the card's loader is saved and blanked, so it has to be put back first.
    // "linux": the card boots dArkMoss as it is, so a reboot is enough.
    private String cardState = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Typeface font;
        try {
            font = Typeface.createFromAsset(getAssets(), FONT_ASSET);
        } catch (RuntimeException e) {
            font = Typeface.DEFAULT_BOLD;
        }
        view = new SpruceView(this, font);
        view.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                confirm();
            }
        });
        setContentView(view);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        view.requestFocus();
        check();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Back from inserting a card: look again without waiting for A.
        if (state == State.NOT_BOOTABLE) {
            check();
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            hideSystemBars();
        }
    }

    @SuppressWarnings("deprecation")
    private void hideSystemBars() {
        view.setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN);
    }

    // --- Controller -----------------------------------------------------------------------------

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        Log.d(TAG, "key " + KeyEvent.keyCodeToString(keyCode) + " scan " + event.getScanCode()
                + (isBuiltInPad(event) ? " (built-in)" : ""));
        if (isConfirm(event)) {
            if (event.getRepeatCount() == 0) {
                confirm();
            }
            return true;
        }
        if (isBack(event)) {
            if (event.getRepeatCount() == 0 && state != State.BOOTING) {
                finish();
            }
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        // Handled on the way down; swallow the release so no fallback key (BUTTON_B's BACK,
        // BUTTON_A's DPAD_CENTER) acts on it a second time.
        if (isConfirm(event) || isBack(event)) {
            return true;
        }
        return super.onKeyUp(keyCode, event);
    }

    /**
     * The A button, whichever key code this firmware's layout gives it: the RG552's button
     * labelled A (by its scan code), BUTTON_A on any other controller, and Enter or the D-pad's
     * centre. Where the layout is the generic one, the built-in B also reads as BUTTON_A and so
     * confirms too; better that than an A button that does nothing.
     */
    private static boolean isConfirm(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_BUTTON_A:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_SPACE:
                return true;
            default:
                return isBuiltInPad(e) && e.getScanCode() == BTN_EAST;
        }
    }

    private static boolean isBack(KeyEvent e) {
        if (isConfirm(e)) {
            return false;
        }
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_BUTTON_B:
            case KeyEvent.KEYCODE_BACK:
            case KeyEvent.KEYCODE_ESCAPE:
                return true;
            default:
                return isBuiltInPad(e) && e.getScanCode() == BTN_SOUTH;
        }
    }

    private static boolean isBuiltInPad(KeyEvent e) {
        InputDevice dev = e.getDevice();
        if (dev == null || (dev.getSources() & (InputDevice.SOURCE_GAMEPAD | InputDevice.SOURCE_JOYSTICK)) == 0) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= 29) {
            return !dev.isExternal();
        }
        try {
            return !(Boolean) InputDevice.class.getMethod("isExternal").invoke(dev);
        } catch (Exception ex) {
            return false;
        }
    }

    // --- Screens --------------------------------------------------------------------------------

    private void show(State s, int message, String detail) {
        state = s;
        view.setMessage(getString(message), detail);
    }

    private void confirm() {
        switch (state) {
            case READY:
                boot();
                break;
            case NOT_BOOTABLE:
            case NO_ROOT:
            case FAILED:
                check();
                break;
            default:
                break; // checking or already booting
        }
    }

    private void check() {
        show(State.CHECKING, R.string.checking, null);
        new Thread(new Runnable() {
            @Override
            public void run() {
                final Result r = runScript("status");
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        String card = r.lastLine();
                        if (!r.rootOk) {
                            show(State.NO_ROOT, R.string.no_root, null);
                        } else if ("android".equals(card) || "linux".equals(card)) {
                            cardState = card;
                            show(State.READY, R.string.ready, null);
                        } else {
                            show(State.NOT_BOOTABLE, R.string.not_bootable, null);
                        }
                    }
                });
            }
        }).start();
    }

    private void boot() {
        show(State.BOOTING, R.string.booting, null);
        final boolean restore = "android".equals(cardState);
        new Thread(new Runnable() {
            @Override
            public void run() {
                if (restore) {
                    final Result r = runScript("linux");
                    if (!r.rootOk || r.exitCode != 0) {
                        ui.post(new Runnable() {
                            @Override
                            public void run() {
                                if (!r.rootOk) {
                                    show(State.NO_ROOT, R.string.no_root, null);
                                } else {
                                    // The script's own reason (dd's error included), for a bug report.
                                    show(State.FAILED, R.string.failed,
                                            r.lastLine().replaceFirst("^rg552-bootswitch: ", ""));
                                }
                            }
                        });
                        return;
                    }
                }
                Result r = runRoot("sync; svc power reboot 2>/dev/null || reboot");
                if (!r.rootOk) {
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            show(State.NO_ROOT, R.string.no_root, null);
                        }
                    });
                }
            }
        }).start();
    }

    // --- Root ------------------------------------------------------------------------------------

    private static final class Result {
        boolean rootOk;
        int exitCode = -1;
        final StringBuilder output = new StringBuilder();

        String lastLine() {
            String[] lines = output.toString().trim().split("\n");
            return lines.length == 0 ? "" : lines[lines.length - 1].trim();
        }
    }

    /** Copies the bundled script to the app's files dir and returns its path. */
    private File installScript() throws Exception {
        File out = new File(getFilesDir(), SCRIPT_ASSET);
        InputStream in = getAssets().open(SCRIPT_ASSET);
        OutputStream os = new FileOutputStream(out);
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            os.write(buf, 0, n);
        }
        os.close();
        in.close();
        out.setReadable(true, false);
        return out;
    }

    private Result runScript(String action) {
        try {
            File script = installScript();
            return runRoot("sh '" + script.getAbsolutePath() + "' " + action);
        } catch (Exception e) {
            Log.w(TAG, "script", e);
            return new Result();
        }
    }

    private Result runRoot(String commands) {
        Result r = new Result();
        Process p;
        try {
            p = Runtime.getRuntime().exec("su");
        } catch (Exception e) {
            Log.w(TAG, "su: " + e.getMessage());
            return r;
        }
        try {
            Writer w = new OutputStreamWriter(p.getOutputStream());
            // A positive sentinel tells "no root" (su refused, or not uid 0) apart from a
            // script that ran and failed.
            w.write("if [ \"$(id -u)\" != 0 ]; then exit 126; fi\n");
            w.write("echo __ROOT_OK__\n");
            w.write(commands + " 2>&1\n");
            w.write("exit $?\n");
            w.flush();
            w.close();
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = br.readLine()) != null) {
                if (line.contains("__ROOT_OK__")) {
                    r.rootOk = true;
                    continue;
                }
                r.output.append(line).append('\n');
                Log.i(TAG, line);
            }
            BufferedReader be = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            while ((line = be.readLine()) != null) {
                Log.w(TAG, line);
            }
            r.exitCode = p.waitFor();
        } catch (Exception e) {
            Log.w(TAG, "su", e);
        }
        return r;
    }
}
