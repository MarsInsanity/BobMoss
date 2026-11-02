package org.darkmoss.rg552bootswitch;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;

/**
 * Android half of the RG552 boot switch.
 *
 * dArkMoss's "Boot to Android" app saves the start of the TF1 card's boot
 * loader into an unused area of the card and blanks it, so the RG552 falls
 * through to Android. This app runs the same rg552-bootswitch script (bundled
 * as an asset) with root to copy it back, then reboots into dArkMoss.
 *
 * Root is needed for raw access to the card. su is fed the commands on stdin,
 * which works with Magisk, SuperSU and the userdebug su alike.
 */
public class MainActivity extends Activity {

    private static final String SCRIPT_ASSET = "rg552-bootswitch.sh";

    private TextView statusView;
    private TextView logView;
    private Button bootLinuxButton;
    private Button refreshButton;
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        int pad = dp(24);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("RG552 Boot Switch");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView help = new TextView(this);
        help.setText("Puts the dArkMoss (spruce) boot loader back on the card in TF1 and "
                + "reboots into it. Needs root. To come back to Android later, use "
                + "\"Boot to Android\" in spruce.");
        help.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        help.setPadding(0, dp(8), 0, dp(16));
        root.addView(help);

        statusView = new TextView(this);
        statusView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        statusView.setText("Checking the card...");
        root.addView(statusView);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.START);
        buttons.setPadding(0, dp(16), 0, dp(16));

        bootLinuxButton = new Button(this);
        bootLinuxButton.setText("Boot dArkMoss");
        bootLinuxButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        bootLinuxButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                confirmBootLinux();
            }
        });
        buttons.addView(bootLinuxButton);

        refreshButton = new Button(this);
        refreshButton.setText("Check again");
        refreshButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        refreshButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                refreshStatus();
            }
        });
        buttons.addView(refreshButton);
        root.addView(buttons);

        logView = new TextView(this);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(logView);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
        bootLinuxButton.requestFocus();
        refreshStatus();
    }

    private int dp(int v) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()));
    }

    private void setBusy(final boolean busy) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                bootLinuxButton.setEnabled(!busy);
                refreshButton.setEnabled(!busy);
            }
        });
    }

    private void log(final String line) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                logView.append(line + "\n");
            }
        });
    }

    private void setStatus(final String text) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                statusView.setText(text);
            }
        });
    }

    private void refreshStatus() {
        setBusy(true);
        new Thread(new Runnable() {
            @Override
            public void run() {
                Result r = runAsRoot("status");
                String state = r.lastLine();
                if (!r.rootOk) {
                    setStatus("No root access. See the log below.");
                    explainNoRoot();
                } else if ("android".equals(state)) {
                    setStatus("The TF1 card holds a saved dArkMoss boot loader. Ready to switch.");
                } else if ("linux".equals(state)) {
                    setStatus("The card in TF1 already boots dArkMoss. Rebooting will start it.");
                } else {
                    setStatus("No dArkMoss card found in TF1.");
                }
                setBusy(false);
            }
        }).start();
    }

    private void confirmBootLinux() {
        new AlertDialog.Builder(this)
                .setTitle("Boot dArkMoss?")
                .setMessage("The device will restore the dArkMoss boot loader on the TF1 card and "
                        + "reboot into it now.")
                .setPositiveButton("Reboot", new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface dialog, int which) {
                        bootLinux();
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void bootLinux() {
        setBusy(true);
        new Thread(new Runnable() {
            @Override
            public void run() {
                log("$ rg552-bootswitch linux");
                Result r = runAsRoot("linux");
                if (!r.rootOk) {
                    setStatus("No root access. See the log below.");
                    explainNoRoot();
                    setBusy(false);
                    return;
                }
                if (r.exitCode != 0) {
                    setStatus("Could not restore the boot loader. Nothing was rebooted.");
                    setBusy(false);
                    return;
                }
                setStatus("Done. Rebooting into dArkMoss...");
                log("$ reboot");
                runRootCommands("sync; svc power reboot 2>/dev/null || reboot");
            }
        }).start();
    }

    private void explainNoRoot() {
        log("");
        log("This app needs root (Magisk or the firmware's own su) to write to the card.");
        log("Without root, from a PC with adb (the RG552's Android allows adb root on");
        log("userdebug builds):");
        log("  adb root");
        log("  adb push rg552-bootswitch.sh /data/local/tmp/");
        log("  adb shell sh /data/local/tmp/rg552-bootswitch.sh linux");
        log("  adb reboot");
        log("Or put the card in a Linux/macOS PC and follow rg552-bootswitch/README.txt");
        log("on its BOOT partition.");
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

    private static final class Result {
        boolean rootOk;
        int exitCode = -1;
        final StringBuilder output = new StringBuilder();

        String lastLine() {
            String[] lines = output.toString().trim().split("\n");
            return lines.length == 0 ? "" : lines[lines.length - 1].trim();
        }
    }

    private Result runAsRoot(String action) {
        try {
            File script = installScript();
            return runRootCommands("sh '" + script.getAbsolutePath() + "' " + action);
        } catch (Exception e) {
            Result r = new Result();
            log("error: " + e);
            return r;
        }
    }

    private Result runRootCommands(String commands) {
        Result r = new Result();
        Process p;
        try {
            p = Runtime.getRuntime().exec("su");
        } catch (Exception e) {
            log("su: " + e.getMessage());
            return r;
        }
        try {
            Writer w = new OutputStreamWriter(p.getOutputStream());
            // A positive sentinel tells "no root" (su refused, or not uid 0)
            // apart from a script that ran and failed.
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
                log(line);
            }
            BufferedReader be = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            while ((line = be.readLine()) != null) {
                log(line);
            }
            r.exitCode = p.waitFor();
        } catch (Exception e) {
            log("error: " + e);
        }
        return r;
    }
}
