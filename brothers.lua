local module = {}

local PADDING = 24
local SPEED = 240
local GRAVITY = 800
local RECT_WIDTH = 80
local RECT_HEIGHT = 40
local BASE_HEIGHT = RECT_HEIGHT

local rect
local lineY
local jumpTimer = 0
local jumpHoldAccum = 0
local jumpWasHeld = false
local JUMP_ACCEL = 100
local JUMP_START_VELOCITY = -280
local JUMP_DURATION = 0.2

function module.load()
  rect = nil
  lineY = nil
  jumpTimer = 0
  jumpHoldAccum = 0
  jumpWasHeld = false
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
    squished = false,
  }
  jumpTimer = 0
  jumpHoldAccum = 0
  jumpWasHeld = false
end

function module.stop()
  rect = nil
  lineY = nil
  jumpTimer = 0
  jumpHoldAccum = 0
  jumpWasHeld = false
end

function module.update(dt)
  if not rect then
    return
  end

  local windowWidth, windowHeight = love.graphics.getDimensions()
  lineY = windowHeight * 0.6

  local floorY = lineY - rect.height
  local onGround = math.abs(rect.y - floorY) <= 0.5 and math.abs(rect.vy) < 0.1

  local jumpHeld = love.keyboard.isDown("w") or love.keyboard.isDown("up") or love.keyboard.isDown("space")

  if jumpHeld then
    jumpHoldAccum = jumpHoldAccum + dt
  end

  if jumpHeld and not jumpWasHeld and onGround then
    jumpTimer = JUMP_DURATION
    rect.vy = JUMP_START_VELOCITY
  end

  if jumpTimer > 0 and jumpHeld then
    rect.vy = rect.vy - JUMP_ACCEL * dt
    jumpTimer = math.max(0, jumpTimer - dt)
  else
    jumpTimer = 0
  end

  rect.vy = rect.vy + GRAVITY * dt
  rect.y = rect.y + rect.vy * dt

  floorY = lineY - rect.height
  if rect.y > floorY then
    rect.y = floorY
    rect.vy = 0
    jumpTimer = 0
  end

  local moveLeft = love.keyboard.isDown("left") or love.keyboard.isDown("a")
  local moveRight = love.keyboard.isDown("right") or love.keyboard.isDown("d")
  if moveLeft and not moveRight then
    rect.x = rect.x - SPEED * dt
  elseif moveRight and not moveLeft then
    rect.x = rect.x + SPEED * dt
  end

  local downHeld = love.keyboard.isDown("down") or love.keyboard.isDown("s")
  if downHeld and onGround then
    if not rect.squished then
      rect.height = BASE_HEIGHT / 2
      rect.squished = true
      rect.y = lineY - rect.height
    end
  elseif rect.squished then
    rect.height = BASE_HEIGHT
    rect.squished = false
    rect.y = math.min(rect.y, lineY - rect.height)
  end

  rect.x = math.max(PADDING, math.min(rect.x, windowWidth - PADDING - rect.width))

  if jumpWasHeld and not jumpHeld then
    jumpHoldAccum = 0
  end

  jumpWasHeld = jumpHeld
end

function module.draw()
  if not rect then
    return
  end

  local windowWidth = love.graphics.getWidth()

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", 0, lineY, windowWidth, 4)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height)

  love.graphics.print(string.format("Jump hold time: %.2f", jumpHoldAccum), PADDING, PADDING)
end

return module
