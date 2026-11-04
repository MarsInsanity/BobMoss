package org.darkmoss.rg552bootswitch;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Build;
import android.text.Layout;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.style.ReplacementSpan;
import android.view.View;

/**
 * The app's one screen, laid out like spruce's own: spruce's tree centred, the message under it, on
 * the SPRUCE theme's grey in its font and colours. "{A}" in a message is drawn as spruce's A button
 * (the key cap of spruce/imgs/displayAcknowledge.png). Sizes follow the screen's short side, so it
 * looks the same on the RG552's 1920x1152 panel as on any other screen.
 */
final class SpruceView extends View {

    // spruceOS Themes/SPRUCE: background, text, highlight.
    static final int BG = 0xFF282828;
    static final int TEXT = 0xFFEBDBB2;
    static final int HIGHLIGHT = 0xFFFBF1C7;

    private static final char CHIP = '￼';

    // spruce's tree (spruce/imgs/tree_sm_close_crop.png) traced to straight edges, in its own units:
    // 88 wide, 152.5 tall. tools/make-icons.py draws the icon from the same outline.
    private static final float TREE_W = 88f;
    private static final float TREE_H = 152.5f;
    private static final float[][] TREE = {
        {40, 0, 88, 48, 79, 57, 48, 26, 40, 34, 88, 82, 79.5f, 90.5f, 48.5f, 59.5f, 40.5f, 67.5f,
            88, 115, 88, 116, 79.5f, 124.5f, 48.5f, 93.5f, 17.5f, 124.5f, 0, 107, 17, 90,
            0.5f, 73.5f, 17.5f, 56.5f, 0.5f, 39.5f},
        {40, 118.5f, 57, 118.5f, 57, 152.5f, 40, 152.5f},
    };

    private final Path tree = new Path();
    private final Paint treePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint textPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint detailPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final Typeface font;

    private CharSequence message = "";
    private String detail;
    private StaticLayout messageLayout;
    private StaticLayout detailLayout;
    private int laidOutWidth = -1;
    private float laidOutSize = -1;

    SpruceView(Context context, Typeface font) {
        super(context);
        this.font = font;
        for (float[] poly : TREE) {
            tree.moveTo(poly[0], poly[1]);
            for (int i = 2; i < poly.length; i += 2) {
                tree.lineTo(poly[i], poly[i + 1]);
            }
            tree.close();
        }
        treePaint.setColor(HIGHLIGHT);
        treePaint.setStyle(Paint.Style.FILL);
        textPaint.setColor(TEXT);
        textPaint.setTypeface(font);
        detailPaint.setColor(TEXT);
        detailPaint.setAlpha(0xB0);
        detailPaint.setTypeface(font);
        setBackgroundColor(BG);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    /** Shows {@code text} ("{A}" becomes the A button) and, under it, an optional smaller line. */
    void setMessage(String text, String detail) {
        SpannableStringBuilder sb = new SpannableStringBuilder();
        String plain = text;
        int at;
        while ((at = plain.indexOf("{A}")) >= 0) {
            sb.append(plain, 0, at);
            int start = sb.length();
            sb.append(CHIP);
            sb.setSpan(new ButtonSpan(), start, start + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            plain = plain.substring(at + 3);
        }
        sb.append(plain);
        this.message = sb;
        this.detail = detail;
        setContentDescription(text.replace("{A}", "A") + (detail == null ? "" : ". " + detail));
        laidOutWidth = -1;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        int w = getWidth();
        int h = getHeight();
        if (w == 0 || h == 0) {
            return;
        }
        float base = Math.min(w, h);
        float treeH = 0.24f * base;
        float scale = treeH / TREE_H;
        float treeW = TREE_W * scale;
        float textSize = 0.036f * base;
        float gap = 0.05f * base;
        int textWidth = Math.round(0.8f * w);

        if (laidOutWidth != textWidth || laidOutSize != textSize) {
            textPaint.setTextSize(textSize);
            detailPaint.setTextSize(0.026f * base);
            messageLayout = layout(message, textPaint, textWidth);
            detailLayout = detail == null || detail.isEmpty() ? null : layout(detail, detailPaint, textWidth);
            laidOutWidth = textWidth;
            laidOutSize = textSize;
        }

        float detailGap = 0.025f * base;
        float total = treeH + gap + messageLayout.getHeight()
                + (detailLayout == null ? 0 : detailGap + detailLayout.getHeight());
        float top = (h - total) / 2f;

        canvas.save();
        canvas.translate((w - treeW) / 2f, top);
        canvas.scale(scale, scale);
        canvas.drawPath(tree, treePaint);
        canvas.restore();

        float y = top + treeH + gap;
        canvas.save();
        canvas.translate((w - textWidth) / 2f, y);
        messageLayout.draw(canvas);
        canvas.restore();

        if (detailLayout != null) {
            canvas.save();
            canvas.translate((w - textWidth) / 2f, y + messageLayout.getHeight() + detailGap);
            detailLayout.draw(canvas);
            canvas.restore();
        }
    }

    @SuppressWarnings("deprecation")
    private static StaticLayout layout(CharSequence text, TextPaint paint, int width) {
        if (Build.VERSION.SDK_INT >= 23) {
            return StaticLayout.Builder.obtain(text, 0, text.length(), paint, width)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER)
                    .setLineSpacing(0f, 1.25f)
                    .setIncludePad(false)
                    .build();
        }
        return new StaticLayout(text, paint, width, Layout.Alignment.ALIGN_CENTER, 1.25f, 0f, false);
    }

    /**
     * spruce's A button: a key cap in the text colour, the letter cut out of it in the background
     * colour, a little taller than a capital, centred on the line's capitals.
     */
    private final class ButtonSpan extends ReplacementSpan {
        private final Paint cap = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint letter = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Rect bounds = new Rect();
        private final RectF key = new RectF();

        ButtonSpan() {
            cap.setColor(TEXT);
            letter.setColor(BG);
            letter.setTypeface(font);
            letter.setTextAlign(Paint.Align.CENTER);
        }

        private float size(Paint paint) {
            return paint.getTextSize() * 0.95f;
        }

        private float pad(Paint paint) {
            return paint.getTextSize() * 0.12f;
        }

        @Override
        public int getSize(Paint paint, CharSequence text, int start, int end, Paint.FontMetricsInt fm) {
            if (fm != null) {
                Paint.FontMetricsInt m = paint.getFontMetricsInt();
                fm.ascent = m.ascent;
                fm.descent = m.descent;
                fm.top = m.top;
                fm.bottom = m.bottom;
                fm.leading = m.leading;
            }
            return Math.round(size(paint) + 2 * pad(paint));
        }

        @Override
        public void draw(Canvas canvas, CharSequence text, int start, int end, float x, int top, int y,
                int bottom, Paint paint) {
            float s = size(paint);
            paint.getTextBounds("A", 0, 1, bounds);
            float middle = y - (-bounds.top) / 2f;
            key.set(x + pad(paint), middle - s / 2f, x + pad(paint) + s, middle + s / 2f);
            canvas.drawRoundRect(key, s * 0.2f, s * 0.2f, cap);
            letter.setTextSize(s * 0.78f);
            letter.getTextBounds("A", 0, 1, bounds);
            canvas.drawText("A", key.centerX(), key.centerY() + (-bounds.top) / 2f, letter);
        }
    }
}
