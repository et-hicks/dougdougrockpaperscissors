local rockpaperscissors = require("rockpaperscissors")
local brothers = require("brothers")

local state = "menu"

local menuButtons = {
  { label = "Play Rock Paper Scissors", action = "play_rps" },
  { label = "Play the Brothers", action = "play_brothers" },
  { label = "Options", action = "options" },
}

local pauseButtons = {
  { label = "Resume", action = "resume" },
  { label = "Main Menu", action = "main_menu" },
  { label = "Options", action = "options" },
}

local titleFont
local menuFont
local overlayColor = { 0, 0, 0, 0.6 }

local function layoutButtons(buttons)
  local windowWidth, windowHeight = love.graphics.getDimensions()
  local buttonWidth = 260
  local buttonHeight = 60
  local startY = windowHeight * 0.4
  local spacing = 20

  for index, button in ipairs(buttons) do
    local bx = (windowWidth - buttonWidth) / 2
    local by = startY + (index - 1) * (buttonHeight + spacing)
    button.x, button.y = bx, by
    button.w, button.h = buttonWidth, buttonHeight
  end
end

local function drawButtonSet(buttons, title, withOverlay)
  if withOverlay then
    local windowWidth, windowHeight = love.graphics.getDimensions()
    love.graphics.setColor(overlayColor)
    love.graphics.rectangle("fill", 0, 0, windowWidth, windowHeight)
    love.graphics.setColor(1, 1, 1)
  end

  love.graphics.setFont(titleFont)
  local windowWidth, windowHeight = love.graphics.getDimensions()
  local titleWidth = titleFont:getWidth(title)
  local titleX = (windowWidth - titleWidth) / 2
  local titleY = windowHeight * 0.2
  love.graphics.print(title, titleX, titleY)

  love.graphics.setFont(menuFont)
  layoutButtons(buttons)
  for _, button in ipairs(buttons) do
    love.graphics.rectangle("line", button.x, button.y, button.w, button.h)
    love.graphics.printf(
      button.label,
      button.x,
      button.y + (button.h - menuFont:getHeight()) / 2,
      button.w,
      "center"
    )
  end
end

local function startRockPaperScissors()
  rockpaperscissors.start()
  state = "playing_rps"
end

local function startBrothersMode()
  brothers.start()
  state = "playing_brothers"
end

function love.load()
  love.graphics.setBackgroundColor(0.1, 0.1, 0.12)

  titleFont = love.graphics.newFont(32)
  menuFont = love.graphics.newFont(18)

  rockpaperscissors.load()
  brothers.load()
end

function love.update(dt)
  if state == "playing_rps" then
    rockpaperscissors.update(dt)
  elseif state == "playing_brothers" then
    brothers.update(dt)
  end
end

function love.draw()
  if state == "menu" then
    drawButtonSet(menuButtons, "Welcome to Rock Paper Scissors")
    return
  end

  if state == "playing_rps" then
    rockpaperscissors.draw()
    return
  end

  if state == "paused_rps" then
    rockpaperscissors.draw()
    drawButtonSet(pauseButtons, "Paused", true)
    return
  end

  if state == "playing_brothers" then
    brothers.draw()
    return
  end
end

local function handleMenuClick(buttons, x, y, handler)
  layoutButtons(buttons)
  for _, button in ipairs(buttons) do
    if button.x and x >= button.x and x <= button.x + button.w and y >= button.y and y <= button.y + button.h then
      handler(button.action)
      break
    end
  end
end

function love.mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  if state == "menu" then
    handleMenuClick(menuButtons, x, y, function(action)
      if action == "play_rps" then
        startRockPaperScissors()
      elseif action == "play_brothers" then
        startBrothersMode()
      elseif action == "options" then
        print("Options menu not implemented yet.")
      end
    end)
  elseif state == "paused_rps" then
    handleMenuClick(pauseButtons, x, y, function(action)
      if action == "resume" then
        state = "playing_rps"
      elseif action == "main_menu" then
        rockpaperscissors.stop()
        state = "menu"
      elseif action == "options" then
        print("Options menu not implemented yet.")
      end
    end)
  end
end

function love.keypressed(key)
  if key == "escape" then
    if state == "playing_rps" then
      state = "paused_rps"
    elseif state == "paused_rps" then
      state = "playing_rps"
    elseif state == "playing_brothers" then
      brothers.stop()
      state = "menu"
    end
    return
  end

  if state == "playing_rps" then
    rockpaperscissors.keypressed(key)
  end
end
