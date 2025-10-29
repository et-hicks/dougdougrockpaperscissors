local SPAWN_DELAY = 0.5
local DEFAULT_SPEED = 25
local WIN_SPEED = 50
local PADDING = 24
local TEXT_GAP = 6

local BEATS = {
  Rock = "Scissors",
  Paper = "Rock",
  Scissors = "Paper",
}

local infoFont
local victoryFont
local windowWidth, windowHeight
local spawnQueue
local spawnedEntities
local nextSpawnIndex
local timeUntilNextSpawn
local aliveCounts = { Paper = 0, Rock = 0, Scissors = 0 }
local orderedKinds = { "Paper", "Rock", "Scissors" }

local function getActiveTypes()
  local active = {}
  for _, kind in ipairs(orderedKinds) do
    if aliveCounts[kind] and aliveCounts[kind] > 0 then
      active[#active + 1] = kind
    end
  end
  return active
end

local function getPlayfieldBounds()
  local infoHeight = infoFont:getHeight()
  local lineSpacing = infoHeight + TEXT_GAP
  local minX = PADDING
  local minY = PADDING + 2 * lineSpacing + infoHeight + 4
  local maxX = windowWidth - PADDING
  local maxY = windowHeight - PADDING
  return minX, minY, maxX, maxY, infoHeight, lineSpacing
end

local function setEntitySpeed(entity, speed)
  if speed <= 0 then
    entity.vx, entity.vy = 0, 0
    return
  end

  local magnitude = math.sqrt(entity.vx * entity.vx + entity.vy * entity.vy)
  if magnitude == 0 then
    local angle = love.math.random() * 2 * math.pi
    entity.vx = math.cos(angle) * speed
    entity.vy = math.sin(angle) * speed
  else
    entity.vx = entity.vx / magnitude * speed
    entity.vy = entity.vy / magnitude * speed
  end
end

local function isColliding(a, b)
  return a.x < b.x + b.width
    and b.x < a.x + a.width
    and a.y < b.y + b.height
    and b.y < a.y + a.height
end

local function separateEntities(a, b)
  local ax1, ay1 = a.x, a.y
  local ax2, ay2 = a.x + a.width, a.y + a.height
  local bx1, by1 = b.x, b.y
  local bx2, by2 = b.x + b.width, b.y + b.height

  local overlapX = math.min(ax2, bx2) - math.max(ax1, bx1)
  local overlapY = math.min(ay2, by2) - math.max(ay1, by1)

  if overlapX <= 0 or overlapY <= 0 then
    return
  end

  if overlapX < overlapY then
    local shift = overlapX / 2
    if ax1 < bx1 then
      a.x = a.x - shift
      b.x = b.x + shift
    else
      a.x = a.x + shift
      b.x = b.x - shift
    end
  else
    local shift = overlapY / 2
    if ay1 < by1 then
      a.y = a.y - shift
      b.y = b.y + shift
    else
      a.y = a.y + shift
      b.y = b.y - shift
    end
  end
end

local function handleEntityCollisions()
  for i = 1, #spawnedEntities do
    local a = spawnedEntities[i]
    if not a.dead then
      for j = i + 1, #spawnedEntities do
        local b = spawnedEntities[j]
        if not b.dead and isColliding(a, b) then
          if a.kind == b.kind then
            separateEntities(a, b)
            a.vx, b.vx = b.vx, a.vx
            a.vy, b.vy = b.vy, a.vy
          else
            if BEATS[a.kind] == b.kind then
              b.dead = true
              aliveCounts[b.kind] = math.max(0, aliveCounts[b.kind] - 1)
            elseif BEATS[b.kind] == a.kind then
              a.dead = true
              aliveCounts[a.kind] = math.max(0, aliveCounts[a.kind] - 1)
              break
            else
              separateEntities(a, b)
            end
          end
        end
      end
    end
  end
end

local function removeDeadEntities()
  for index = #spawnedEntities, 1, -1 do
    if spawnedEntities[index].dead then
      table.remove(spawnedEntities, index)
    end
  end
end

local function adjustEntitySpeeds()
  local activeTypes = getActiveTypes()

  if #activeTypes == 2 then
    local first, second = activeTypes[1], activeTypes[2]
    local winning, losing

    if BEATS[first] == second then
      winning, losing = first, second
    elseif BEATS[second] == first then
      winning, losing = second, first
    end

    for _, entity in ipairs(spawnedEntities) do
      if winning and losing then
        if entity.kind == winning then
          setEntitySpeed(entity, WIN_SPEED)
        elseif entity.kind == losing then
          setEntitySpeed(entity, 0)
        else
          setEntitySpeed(entity, DEFAULT_SPEED)
        end
      else
        setEntitySpeed(entity, DEFAULT_SPEED)
      end
    end
  elseif #activeTypes == 1 then
    for _, entity in ipairs(spawnedEntities) do
      setEntitySpeed(entity, 0)
    end
  else
    for _, entity in ipairs(spawnedEntities) do
      setEntitySpeed(entity, DEFAULT_SPEED)
    end
  end
end

local function spawnEntity(entry)
  local image = entry.image
  local imageWidth = image:getWidth()
  local imageHeight = image:getHeight()
  local scale = entry.scale
  local scaledWidth = imageWidth * scale
  local scaledHeight = imageHeight * scale

  local minX, minY, maxX, maxY = getPlayfieldBounds()
  local maxSpawnX = math.max(minX, maxX - scaledWidth)
  local maxSpawnY = math.max(minY, maxY - scaledHeight)

  local x = minX + love.math.random() * (maxSpawnX - minX)
  local y = minY + love.math.random() * (maxSpawnY - minY)
  local angle = love.math.random() * 2 * math.pi

  local entity = {
    name = entry.name,
    kind = entry.kind,
    image = image,
    x = x,
    y = y,
    scale = scale,
    width = scaledWidth,
    height = scaledHeight,
    vx = math.cos(angle) * DEFAULT_SPEED,
    vy = math.sin(angle) * DEFAULT_SPEED,
  }

  spawnedEntities[#spawnedEntities + 1] = entity
  aliveCounts[entry.kind] = aliveCounts[entry.kind] + 1
end

function love.load()
  love.graphics.setBackgroundColor(0.1, 0.1, 0.12)

  infoFont = love.graphics.newFont(18)
  victoryFont = love.graphics.newFont(32)

  love.math.setRandomSeed(os.time())

  windowWidth, windowHeight = love.graphics.getDimensions()
  local maxSpriteWidth = windowWidth * 0.05
  local maxSpriteHeight = windowHeight * 0.05

  local textures = {
    Paper = love.graphics.newImage("assets/paper.png"),
    Rock = love.graphics.newImage("assets/rock.png"),
    Scissors = love.graphics.newImage("assets/scissors.png"),
  }

  local scales = {}
  for kind, image in pairs(textures) do
    scales[kind] = math.min(
      maxSpriteWidth / image:getWidth(),
      maxSpriteHeight / image:getHeight()
    )
  end

  spawnQueue = {}
  local function enqueue(kind, count)
    for _ = 1, count do
      spawnQueue[#spawnQueue + 1] = {
        name = kind,
        kind = kind,
        image = textures[kind],
        scale = scales[kind],
      }
    end
  end

  enqueue("Paper", 3)
  enqueue("Rock", 3)
  enqueue("Scissors", 3)

  spawnedEntities = {}
  aliveCounts = { Paper = 0, Rock = 0, Scissors = 0 }
  nextSpawnIndex = 1
  timeUntilNextSpawn = SPAWN_DELAY
end

function love.update(dt)
  if timeUntilNextSpawn then
    timeUntilNextSpawn = timeUntilNextSpawn - dt

    if timeUntilNextSpawn <= 0 and nextSpawnIndex <= #spawnQueue then
      local entry = spawnQueue[nextSpawnIndex]
      spawnEntity(entry)

      nextSpawnIndex = nextSpawnIndex + 1

      if nextSpawnIndex <= #spawnQueue then
        timeUntilNextSpawn = SPAWN_DELAY
      else
        timeUntilNextSpawn = nil
      end
    end
  else
    local minX, minY, maxX, maxY = getPlayfieldBounds()

    for _, entity in ipairs(spawnedEntities) do
      entity.x = entity.x + entity.vx * dt
      entity.y = entity.y + entity.vy * dt

      if entity.x <= minX then
        entity.x = minX
        entity.vx = math.abs(entity.vx)
      elseif entity.x + entity.width >= maxX then
        entity.x = maxX - entity.width
        entity.vx = -math.abs(entity.vx)
      end

      if entity.y <= minY then
        entity.y = minY
        entity.vy = math.abs(entity.vy)
      elseif entity.y + entity.height >= maxY then
        entity.y = maxY - entity.height
        entity.vy = -math.abs(entity.vy)
      end
    end

    handleEntityCollisions()
    removeDeadEntities()
    adjustEntitySpeeds()
  end
end

function love.draw()
  love.graphics.setFont(infoFont)
  love.graphics.setColor(1, 1, 1)

  local _, _, _, _, _, lineSpacing = getPlayfieldBounds()
  local activeTypes = getActiveTypes()

  local timerText
  if timeUntilNextSpawn then
    timerText = string.format("Time until next spawn: %.1f s", math.max(0, timeUntilNextSpawn))
  else
    timerText = "All entities have spawned."
  end

  local nextName
  if nextSpawnIndex <= #spawnQueue then
    nextName = spawnQueue[nextSpawnIndex].name
  else
    nextName = "None"
  end

  love.graphics.print(timerText, PADDING, PADDING)
  love.graphics.print("Next up: " .. nextName, PADDING, PADDING + lineSpacing)

  local countersText = string.format(
    "Paper: %d | Rock: %d | Scissors: %d",
    aliveCounts.Paper,
    aliveCounts.Rock,
    aliveCounts.Scissors
  )
  love.graphics.print(countersText, PADDING, PADDING + 2 * lineSpacing)

  local minX, minY, maxX, maxY = getPlayfieldBounds()
  love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)

  for _, entity in ipairs(spawnedEntities) do
    local image = entity.image
    local label = entity.name
    local labelX = entity.x + (entity.width - infoFont:getWidth(label)) / 2
    love.graphics.print(label, labelX, entity.y - infoFont:getHeight() - 4)
    love.graphics.draw(image, entity.x, entity.y, 0, entity.scale, entity.scale)
  end

  local hasWinner = not timeUntilNextSpawn and #activeTypes == 1
  if hasWinner then
    local winner = activeTypes[1]
    local centerX = minX + (maxX - minX) / 2
    local centerY = minY + (maxY - minY) / 2

    love.graphics.setFont(victoryFont)
    local message = string.format("%s wins!!", winner)
    local messageWidth = victoryFont:getWidth(message)
    local messageHeight = victoryFont:getHeight()
    love.graphics.print(message, centerX - messageWidth / 2, centerY - messageHeight - 10)

    love.graphics.setFont(infoFont)
    local buttonText = "Press R to reset"
    local buttonPaddingX = 16
    local buttonPaddingY = 8
    local buttonWidth = infoFont:getWidth(buttonText) + buttonPaddingX * 2
    local buttonHeight = infoFont:getHeight() + buttonPaddingY * 2
    local buttonX = centerX - buttonWidth / 2
    local buttonY = centerY + 10

    love.graphics.rectangle("line", buttonX, buttonY, buttonWidth, buttonHeight)
    love.graphics.print(buttonText, buttonX + buttonPaddingX, buttonY + buttonPaddingY)
  end
end

function love.keypressed(key)
  if key == "r" then
    love.load()
  end
end
