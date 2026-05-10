local self = {}

function self.isLeaderboardEnabled()
  return Roguemon.OptionsManager.isEnabled("Enable Leaderboard") or false
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
