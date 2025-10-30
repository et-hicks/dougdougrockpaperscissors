local module = {}

local PADDING = 24
local SPEED = 220
local GRAVITY = 10
local RECT_WIDTH = 80
local RECT_HEIGHT = 40

local rect
local lineY

function module.load()
  rect = nil
  lineY = nil
end

function module.start()
  local windowWidth, windowHeight = love.graphics.getDimensions()
  lineY = windowHeight * 0.6
  rect = {
    width = RECT_WIDTH,
    height = RECT_HEIGHT,
    x = (windowWidth - RECT_WIDTH) / 2,
    y = lineY - RECT_HEIGHT,
    vy = 0,
  }
end

function module.stop()
  rect = nil
  lineY = nil
end

function module.update(dt)
  if not rect then
    return
  end

  local windowWidth, windowHeight = love.graphics.getDimensions()
  lineY = windowHeight * 0.6

  rect.vy = rect.vy + GRAVITY * dt
  rect.y = rect.y + rect.vy * dt

  local floorY = lineY - rect.height
  if rect.y > floorY then
    rect.y = floorY
    rect.vy = 0
  end

  local moveLeft = love.keyboard.isDown("left") or love.keyboard.isDown("d")
  local moveRight = love.keyboard.isDown("right") or love.keyboard.isDown("a")
  if moveLeft and not moveRight then
    rect.x = rect.x - SPEED * dt
  elseif moveRight and not moveLeft then
    rect.x = rect.x + SPEED * dt
  end

  rect.x = math.max(PADDING, math.min(rect.x, windowWidth - PADDING - rect.width))
end

function module.draw()
  if not rect then
    return
  end

  local windowWidth = love.graphics.getWidth()

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", 0, lineY, windowWidth, 4)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height)
end

return module
