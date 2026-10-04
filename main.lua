require "import"
import "android.widget.*"
import "android.view.*"
import "android.app.*"
import "android.graphics.Typeface"
import "android.graphics.Color"
import "android.os.Build"
import "android.os.Looper"
import "android.os.Handler"
import "android.media.ToneGenerator"
import "android.media.AudioManager"
import "android.content.Context"
import "android.os.Vibrator"
import "android.net.Uri"
import "android.content.Intent"
import "android.text.InputType"
import "android.content.DialogInterface"
import "java.net.URLEncoder"
import "com.androlua.Http"

local updater = require "updater"
local context = service or activity or this
local mainHandler = Handler(Looper.getMainLooper())

-- Accessibility Screen Reader Helper
local function speakText(text)
  pcall(function()
    if service then
      service.speak(text)
    elseif activity then
      activity.getAccessibilityManager().announceForAccessibility(text)
    end
  end)
end

-- Persistent Preferences Setup
local preferences = context.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
local editor = preferences.edit()

-- Global Settings Flags
local isToneEnabled = preferences.getBoolean("ToneGeneratorState", true)
local isVibrationEnabled = preferences.getBoolean("VibrationState", true)

-- Helpers for Audio and Vibration
local toneGenerator = nil
pcall(function()
  toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
end)

local function playBeep()
  if isToneEnabled and toneGenerator then
    pcall(function()
      toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
    end)
  end
end

local function triggerVibration()
  if isVibrationEnabled then
    pcall(function()
      local vibrator = context.getSystemService(Context.VIBRATOR_SERVICE)
      if vibrator and vibrator.hasVibrator() then
        if Build.VERSION.SDK_INT >= 26 then
          import "android.os.VibrationEffect"
          vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
        else
          vibrator.vibrate(50)
        end
      end
    end)
  end
end

-- Helper for Safe Window Type
local function setSafeWindowType(dialog)
  pcall(function()
    if service then
      if Build.VERSION.SDK_INT >= 26 then
        dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
      else
        dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
      end
    end
  end)
end

-- ============================================
-- FEEDBACK DIALOG & MODULE
-- ============================================

local function showSuccessDialog(parentDlg)
  local layout = LinearLayout(context)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(60, 60, 60, 60)
  layout.setGravity(Gravity.CENTER)
  layout.setBackgroundColor(Color.parseColor("#121212"))
  
  local msgText = TextView(context)
  msgText.setText("Feedback sent successfully!")
  msgText.setTextSize(18)
  msgText.setTextColor(Color.parseColor("#4CAF50"))
  msgText.setGravity(Gravity.CENTER)
  msgText.setPadding(0, 0, 0, 40)
  layout.addView(msgText)
  
  local btnOk = Button(context)
  btnOk.setText("OK")
  btnOk.setBackgroundColor(Color.parseColor("#2196F3"))
  btnOk.setTextColor(Color.WHITE)
  local pOk = LinearLayout.LayoutParams(-1, -2)
  btnOk.setLayoutParams(pOk)
  layout.addView(btnOk)
  
  local successDlg = LuaDialog(context)
  successDlg.View = layout
  setSafeWindowType(successDlg)
  
  btnOk.setOnClickListener(View.OnClickListener{
    onClick = function()
      playBeep()
      triggerVibration()
      successDlg.dismiss()
      if parentDlg then parentDlg.dismiss() end
    end
  })
  
  successDlg.show()
end

local function openFeedbackDialog()
  local dlg = nil
  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    backgroundColor = Color.parseColor("#121212"),
    padding = "16dp",
    {
      ScrollView,
      layout_width = "fill",
      layout_height = "fill",
      fillViewport = true,
      {
        LinearLayout,
        id = "container",
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "wrap",
      }
    }
  }

  dlg = LuaDialog(context)
  dlg.View = loadlayout(layout)
  setSafeWindowType(dlg)

  local tTitle = TextView(context)
  tTitle.setText("Sent feedback to developer")
  tTitle.setTextSize(20)
  tTitle.setTextColor(Color.WHITE)
  tTitle.setPadding(10, 10, 10, 10)
  container.addView(tTitle)

  local tProj = TextView(context)
  tProj.setText("Project Name")
  tProj.setTextColor(Color.WHITE)
  container.addView(tProj)

  local editProject = EditText(context)
  editProject.setText("Computer Shortcuts")
  editProject.setFocusable(false)
  editProject.setClickable(false)
  editProject.setEnabled(false)
  editProject.setTextColor(Color.parseColor("#757575"))
  container.addView(editProject)

  local tName = TextView(context)
  tName.setText("Enter your name (Required)")
  tName.setTextColor(Color.WHITE)
  container.addView(tName)

  local editName = EditText(context)
  editName.setTextColor(Color.WHITE)
  container.addView(editName)

  local tWa = TextView(context)
  tWa.setText("Enter your WhatsApp number (Optional)")
  tWa.setTextColor(Color.WHITE)
  container.addView(tWa)

  local editWa = EditText(context)
  editWa.setInputType(InputType.TYPE_CLASS_PHONE)
  editWa.setTextColor(Color.WHITE)
  container.addView(editWa)

  local tMsg = TextView(context)
  tMsg.setText("Write your feedback message")
  tMsg.setTextColor(Color.WHITE)
  container.addView(tMsg)

  local editMsg = EditText(context)
  editMsg.setTextColor(Color.WHITE)
  container.addView(editMsg)

  local bCent = Button(context)
  bCent.setText("Send")
  bCent.setOnClickListener(View.OnClickListener{
    onClick = function()
      playBeep()
      triggerVibration()

      local projectName = tostring(editProject.getText() or "Computer Shortcuts")
      local name = tostring(editName.getText() or "")
      local wa = tostring(editWa.getText() or "")
      local msg = tostring(editMsg.getText() or "")

      if name:match("^%s*$") then
        speakText("Please enter your name")
        return
      end

      if msg:match("^%s*$") then
        speakText("Please enter feedback message")
        return
      end

      local pd = ProgressDialog(context)
      pd.setMessage("Sending please wait...")
      pd.setCancelable(false)
      setSafeWindowType(pd)
      pd.show()
      speakText("Sending please wait")

      local BOT_TOKEN = "8801600206:AAGhOLhnkWD-QFTS_-gKgnOGTmQ29bW7434"
      local CHAT_ID = "8254707942"
      local VERCEL_URL = "https://send-feedback-dusky.vercel.app/api"

      local fullText = "New Feedback Received:\nProject: " .. projectName .. "\nName: " .. name
      if wa ~= "" then
        fullText = fullText .. "\nWhatsApp: " .. wa
      end
      fullText = fullText .. "\nFeedback: " .. msg

      local encodedToken = URLEncoder.encode(BOT_TOKEN, "UTF-8")
      local encodedChatId = URLEncoder.encode(CHAT_ID, "UTF-8")
      local encodedText = URLEncoder.encode(fullText, "UTF-8")

      local postData = "bot_token=" .. encodedToken .. "&chat_id=" .. encodedChatId .. "&text=" .. encodedText

      Http.post(VERCEL_URL, postData, function(code, content)
        pcall(function() pd.dismiss() end)
        if tonumber(code) == 200 then
          speakText("Feedback sent successfully")
          editMsg.setText("")
          showSuccessDialog(dlg)
        else
          local errCode = tostring(code or "Unknown")
          speakText("Failed to send. Error code " .. errCode)
          Toast.makeText(context, "Error (" .. errCode .. "): " .. tostring(content), Toast.LENGTH_LONG).show()
        end
      end)
    end
  })
  container.addView(bCent)

  dlg.show()
end

-- ============================================
-- 11 CATEGORIES DATABASE
-- ============================================

local categories = {
  {
    name = "NVDA Navigations",
    keys = {
      {key = "1. NVDA + N", desc = "Open NVDA main menu"},
      {key = "2. NVDA + Q", desc = "Exit NVDA"},
      {key = "3. NVDA + Control + F", desc = "Find text on screen"},
      {key = "4. NVDA + F3", desc = "Find next occurrence"},
      {key = "5. NVDA + Shift + F3", desc = "Find previous occurrence"},
      {key = "6. NVDA + Down Arrow", desc = "Start continuous reading"},
      {key = "7. NVDA + Up Arrow", desc = "Stop continuous reading"},
      {key = "8. NVDA + Tab", desc = "Announce focused control"},
      {key = "9. NVDA + T", desc = "Read active window title"},
      {key = "10. NVDA + Shift + B", desc = "Announce battery status"}
    }
  },
  {
    name = "JAWS Navigations",
    keys = {
      {key = "1. Insert + J", desc = "Open JAWS main window"},
      {key = "2. Insert + F4", desc = "Exit JAWS"},
      {key = "3. Insert + Down", desc = "Say all / Read document"},
      {key = "4. Insert + Up", desc = "Stop reading"}
    }
  }
}

-- ============================================
-- MAIN MENU & SETTINGS
-- ============================================

local function showMainMenu()
  local mainLayoutView = LinearLayout(context)
  mainLayoutView.setOrientation(LinearLayout.VERTICAL)
  mainLayoutView.setPadding(20, 20, 20, 20)

  local mainTitle = TextView(context)
  mainTitle.setText("COMPUTER SHORTCUTS")
  mainTitle.setTextSize(18)
  mainTitle.setGravity(Gravity.CENTER)
  mainTitle.setTextColor(Color.parseColor("#FF6B35"))
  mainTitle.setTypeface(Typeface.DEFAULT_BOLD)
  mainLayoutView.addView(mainTitle)

  local subTitle = TextView(context)
  subTitle.setText("Created By Mahadeesh")
  subTitle.setTextSize(12)
  subTitle.setGravity(Gravity.CENTER)
  subTitle.setTextColor(Color.parseColor("#008800"))
  subTitle.setPadding(0, 0, 0, 15)
  mainLayoutView.addView(subTitle)

  local btnFeedback = Button(context)
  btnFeedback.setText("Send Feedback")
  btnFeedback.setOnClickListener(View.OnClickListener{
    onClick = function()
      playBeep()
      triggerVibration()
      openFeedbackDialog()
    end
  })
  mainLayoutView.addView(btnFeedback)

  local mainDl = AlertDialog.Builder(context)
  mainDl.setView(mainLayoutView)
  local mainDialog = mainDl.create()
  setSafeWindowType(mainDialog)
  mainDialog.show()
end

-- Start Check Update & Launch UI
pcall(function()
  updater.checkUpdate(function()
    showMainMenu()
  end)
end)