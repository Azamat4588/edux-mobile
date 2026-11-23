package uz.edux.gateway

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Oddiy ko'rinish elementlari (ilova kutubxonasiz, kod bilan chiziladi). */
object Ui {
    val BRAND = Color.parseColor("#0F6E6E")
    val MUTED = Color.parseColor("#5B6577")
    val DANGER = Color.parseColor("#B42318")
    val SUCCESS = Color.parseColor("#067647")
    val INK = Color.parseColor("#101828")

    fun dp(context: Context, value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    fun text(context: Context, value: String, size: Float = 15f, color: Int = INK, bold: Boolean = false): TextView =
        TextView(context).apply {
            text = value
            textSize = size
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(context, 4), 0, dp(context, 4))
        }

    fun card(context: Context): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(context, 16), dp(context, 14), dp(context, 16), dp(context, 14))
        background = GradientDrawable().apply {
            setColor(Color.WHITE)
            cornerRadius = dp(context, 14).toFloat()
            setStroke(dp(context, 1), Color.parseColor("#E4E7EC"))
        }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(context, 12) }
    }

    fun button(context: Context, label: String, primary: Boolean = true, action: () -> Unit): Button = Button(context).apply {
        text = label
        isAllCaps = false
        setTextColor(if (primary) Color.WHITE else BRAND)
        background = GradientDrawable().apply {
            setColor(if (primary) BRAND else Color.TRANSPARENT)
            cornerRadius = dp(context, 10).toFloat()
            if (!primary) setStroke(dp(context, 1), BRAND)
        }
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(context, 8) }
    }

    fun chip(context: Context, label: String, selected: Boolean, action: () -> Unit): Button = Button(context).apply {
        text = label
        isAllCaps = false
        textSize = 13f
        setTextColor(if (selected) Color.WHITE else BRAND)
        background = GradientDrawable().apply {
            setColor(if (selected) BRAND else Color.TRANSPARENT)
            cornerRadius = dp(context, 18).toFloat()
            setStroke(dp(context, 1), BRAND)
        }
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { setMargins(dp(context, 3), 0, dp(context, 3), 0) }
    }
}
