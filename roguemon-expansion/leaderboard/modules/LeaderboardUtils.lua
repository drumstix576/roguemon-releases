local self = {}

function self.isLeaderboardEnabled()
  return Roguemon.OptionsManager.isEnabled("Enable Leaderboard") or false
end

local function openUrl(url)
  local isWindows = package.config:sub(1, 1) == "\\"
  if isWindows then
    os.execute(string.format('start "" "%s"', url))
  else
    os.execute(string.format('xdg-open "%s" &', url))
  end
end

local function saveCredentials(credentialKey)
  if credentialKey and credentialKey ~= "" then
    -- Decode base64 to get "username:devicetoken"
    local decoded = Roguemon.Core.Utils.base64_decode(credentialKey)
    if decoded and decoded:find(":") then
      local username, deviceToken = decoded:match("^(.+):(.+)$")
      Roguemon.Leaderboard.FileIOManager.saveUserInfo(username, deviceToken)
      Utils.printDebug("[Leaderboard] Credentials saved; re-initializing leaderboard")
      Roguemon.Leaderboard.init()
    end
  end
end

function self.addPopup(message)
  local padding = 16
  local buttonW = 80
  local rowH = 24
  local contentW = 400
  local labelH = 60

  local height = padding + labelH + rowH + padding
  local width = padding + contentW + padding

  local form = forms.newform(width, height, "Roguemon Leaderboard")

  if forms.setproperty then
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)
  end

  forms.label(form, message, padding, padding, contentW, labelH)

  forms.button(form, "Close", function()
    forms.destroy(form)
  end, padding + contentW - buttonW, padding + labelH, buttonW, rowH - 4)

  return form
end

function self.showUserInfoForm()
  local padding = 16
  local buttonW = 140
  local rowH = 30

  local contentW = 360
  local formW = contentW + padding * 2

  local y = padding

  -- Estimated heights
  local welcomeH = 40
  local infoH = 40
  local labelH = 20

  local formH =
    padding + -- top
    welcomeH +
    rowH +
    padding +
    infoH +
    labelH +
    rowH +
    padding +
    rowH +
    padding

  local form = forms.newform(formW, formH, "Roguemon Leaderboard Setup")

  if forms.setproperty then
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)
  end

  -- Welcome text
  local message =
    "Welcome to the Roguemon Leaderboard!\n" ..
    "Please visit roguemon.gg to create your account."

  forms.label(form, message, padding, y, contentW, welcomeH)

  y = y + welcomeH + 4

  -- Visit button
  forms.button(form, "Visit roguemon.gg", function()
    openUrl("https://roguemon.gg")
  end, 125, y, buttonW, rowH)

  y = y + rowH + padding

  -- Second message
  local message2 =
    "Once you have your credential key, you may enter it below.\n" ..
    "Otherwise, you may disable the leaderboard."

  forms.label(form, message2, padding, y, contentW, infoH)

  y = y + infoH

  -- Credential label
  forms.label(form, "Credential Key", padding, y, contentW, labelH)

  y = y + labelH

  -- Textbox
  local credentialKeyTextbox =
    forms.textbox(form, "", contentW, rowH, nil, padding, y)

  y = y + rowH + padding
  local x = 50

  -- Save button
  forms.button(form, "Save Credentials", function()
    local credentialKey = forms.gettext(credentialKeyTextbox)
    saveCredentials(credentialKey)
    forms.destroy(form)
  end, x, y, buttonW, rowH)

  x = x + buttonW + padding
  -- Disable button
  forms.button(form, "Disable Leaderboard", function()
    Roguemon.OptionsManager.toggle("Enable Leaderboard")
    forms.destroy(form)
  end, x, y, buttonW, rowH)

  return form
end

function self.showUserInfoForm2()
  local padding = 16
  local buttonW = 120
  local rowH = 30
  local labelH = 20
  local messageH = 40
  local contentW = 360
  local formW = padding + contentW + padding
  local formH = padding + messageH + padding + labelH + padding + rowH + padding + rowH + padding

  local form = forms.newform(formW, formH, "Roguemon Leaderboard Setup")

  if forms.setproperty then
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)
  end

  local message = "Welcome to the Roguemon Leaderboard!\nPlease visit roguemon.gg to create your account."

  forms.label(form, message, padding, padding, contentW, messageH)

  forms.button(form, "Visit roguemon.gg", function()
    openUrl("https://roguemon.gg")
  end, padding + buttonW , padding + messageH - 10, buttonW, rowH)

  local message2 = "Once you have your credential key, you may enter it in the box below!\nOtherwise, you may disable the leaderboard below."
  forms.label(form, message2, padding, padding + messageH + padding, contentW, labelH)

  local y = padding + messageH + messageH + padding

  -- Credential Key label
  forms.label(form, "Credential Key", padding, y, contentW, labelH)
  local credentialKeyTextbox = forms.textbox(form, "", contentW, rowH, nil, padding, y + labelH + 2)

  y = y + labelH + padding + rowH + padding

  -- Buttons
  forms.button(form, "Save Credentials", function()
    local credentialKey = forms.gettext(credentialKeyTextbox)
    saveCredentials(credentialKey)
    forms.destroy(form)
  end, padding, y, buttonW, rowH)

  forms.button(form, "Disable Leaderboard", function()
    Roguemon.OptionsManager.toggle("Enable Leaderboard")
    forms.destroy(form)
  end, padding + buttonW + padding, y, buttonW, rowH)

  return form
end

local lastFrame = 0

function self.checkFrameContinuity()
  local currentFrame = emu.framecount()

  if currentFrame < lastFrame then
    return false
  end

  lastFrame = currentFrame
  return true
end

return self
