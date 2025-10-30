local module = {}

local SPAWN_DELAY = 0.1
local DEFAULT_SPEED = 45
local WIN_SPEED = 100
local PADDING = 24
local TEXT_GAP = 6
local SURVIVOR_PATH = "players/survivors.txt"

local BEATS = {
  Rock = "Scissors",
  Paper = "Rock",
  Scissors = "Paper",
}

local orderedKinds = { "Paper", "Rock", "Scissors" }

local infoFont
local victoryFont
local windowWidth, windowHeight
local spawnQueue = {}
local spawnedEntities = {}
local nextSpawnIndex = 1
local timeUntilNextSpawn
local aliveCounts = { Paper = 0, Rock = 0, Scissors = 0 }
local playerNames = {}
local textures = {}
local scales = {}
local resultsRecorded = false
local aliveLookup = {}
local spawnCompleteAnnounced = false

local function resetGameState()
  spawnQueue = {}
  spawnedEntities = {}
  aliveLookup = {}
  aliveCounts = { Paper = 0, Rock = 0, Scissors = 0 }
  nextSpawnIndex = 1
  timeUntilNextSpawn = nil
  resultsRecorded = false
  spawnCompleteAnnounced = false
end

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
  local countersHeight = infoFont:getHeight()
  local lineSpacing = countersHeight + TEXT_GAP
  local minX = PADDING
  local minY = PADDING + countersHeight + TEXT_GAP + 16
  local maxX = windowWidth - PADDING
  local maxY = windowHeight - PADDING
  return minX, minY, maxX, maxY, countersHeight, lineSpacing
end

local function addAliveRecord(entity, centerX, centerY)
  aliveLookup[entity.playerName] = {
    entity = entity,
    spawnX = centerX,
    spawnY = centerY,
  }
end

local function removeAliveRecord(entity)
  if entity and entity.playerName then
    aliveLookup[entity.playerName] = nil
  end
end

local function setEntitySpeed(entity, speed)
  entity.speed = speed
  if speed <= 0 then
    entity.vx, entity.vy = 0, 0
    return
  end

  if not spawnCompleteAnnounced then
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

local function emitDeathEvent(entity)
  if entity and entity.playerName then
    print(string.format("DeathEvent %s (%s)", entity.playerName, entity.kind or "Unknown"))
    removeAliveRecord(entity)
  end
end

local function chooseRandomEnemyTarget(entity)
  local preferred, fallback = {}, {}
  for _, record in pairs(aliveLookup) do
    local candidate = record.entity
    if candidate ~= entity and candidate and not candidate.dead then
      if candidate.kind ~= entity.kind then
        preferred[#preferred + 1] = candidate
      else
        fallback[#fallback + 1] = candidate
      end
    end
  end

  local pool = (#preferred > 0) and preferred or fallback
  if #pool == 0 then
    return nil
  end
  return pool[love.math.random(#pool)]
end

local function ensureTargetForEntity(entity)
  if not spawnCompleteAnnounced then
    return
  end

  if entity.speed and entity.speed <= 0 then
    entity.vx, entity.vy = 0, 0
    entity.targetEntity = nil
    return
  end

  if entity.targetEntity then
    local target = entity.targetEntity
    if target.dead or target.kind == entity.kind or not aliveLookup[target.playerName] then
      entity.targetEntity = nil
    end
  end

  if not entity.targetEntity then
    entity.targetEntity = chooseRandomEnemyTarget(entity)
  end

  if entity.targetEntity then
    local target = entity.targetEntity
    local centerX = entity.x + entity.width / 2
    local centerY = entity.y + entity.height / 2
    local targetCenterX = target.x + target.width / 2
    local targetCenterY = target.y + target.height / 2
    local dx = targetCenterX - centerX
    local dy = targetCenterY - centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    if entity.speed and entity.speed > 0 and dist > 0 then
      entity.vx = dx / dist * entity.speed
      entity.vy = dy / dist * entity.speed
    else
      entity.vx, entity.vy = 0, 0
    end
  else
    entity.vx, entity.vy = 0, 0
  end
end

local function refreshTargetsForAll()
  if not spawnCompleteAnnounced then
    return
  end
  for _, entity in ipairs(spawnedEntities) do
    entity.targetEntity = nil
    ensureTargetForEntity(entity)
  end
end

local function growEntity(entity)
  entity.scale = entity.scale * 1.1
  entity.width = entity.image:getWidth() * entity.scale
  entity.height = entity.image:getHeight() * entity.scale

  local minX, minY, maxX, maxY = getPlayfieldBounds()

  entity.x = math.max(minX, math.min(entity.x, maxX - entity.width))
  entity.y = math.max(minY, math.min(entity.y, maxY - entity.height))
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
              a.kills = a.kills + 1
              growEntity(a)
              emitDeathEvent(b)
              aliveCounts[b.kind] = math.max(0, aliveCounts[b.kind] - 1)
            elseif BEATS[b.kind] == a.kind then
              a.dead = true
              b.kills = b.kills + 1
              growEntity(b)
              emitDeathEvent(a)
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
          entity.targetEntity = nil
        else
          setEntitySpeed(entity, DEFAULT_SPEED)
        end
      else
        setEntitySpeed(entity, DEFAULT_SPEED)
      end
    end
    return
  end

  if #activeTypes <= 1 then
    for _, entity in ipairs(spawnedEntities) do
      setEntitySpeed(entity, 0)
      entity.targetEntity = nil
    end
  else
    for _, entity in ipairs(spawnedEntities) do
      setEntitySpeed(entity, DEFAULT_SPEED)
    end
  end
end

local function announceSpawningComplete()
  if spawnCompleteAnnounced then
    return
  end
  print("spawning done")
  spawnCompleteAnnounced = true
  adjustEntitySpeeds()
  refreshTargetsForAll()
end

local function loadPlayerNames()
  playerNames = {}

  if love.filesystem.getInfo("players/players.txt") then
    local contents = love.filesystem.read("players/players.txt")
    if contents then
      for line in contents:gmatch("[^\r\n]+") do
        local cleaned = line:match("^%s*(.-)%s*$")
        if cleaned ~= "" then
          playerNames[#playerNames + 1] = cleaned
        end
      end
    end
  end

  if #playerNames == 0 then
    playerNames = { "PaperPilot", "RockRanger", "ScissorScout" }
  end
end

local function shufflePlayers()
  for i = #playerNames, 2, -1 do
    local j = love.math.random(i)
    playerNames[i], playerNames[j] = playerNames[j], playerNames[i]
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
  local centerX = x + scaledWidth / 2
  local centerY = y + scaledHeight / 2

  local entity = {
    playerName = entry.playerName,
    kind = entry.kind,
    image = image,
    x = x,
    y = y,
    scale = scale,
    width = scaledWidth,
    height = scaledHeight,
    vx = math.cos(angle) * DEFAULT_SPEED,
    vy = math.sin(angle) * DEFAULT_SPEED,
    kills = 0,
    spawnX = centerX,
    spawnY = centerY,
    targetEntity = nil,
    speed = DEFAULT_SPEED,
  }

  spawnedEntities[#spawnedEntities + 1] = entity
  aliveCounts[entry.kind] = aliveCounts[entry.kind] + 1
  addAliveRecord(entity, centerX, centerY)
end

local function recordSurvivors()
  if resultsRecorded then
    return
  end

  local file, err = io.open(SURVIVOR_PATH, "w")
  if not file then
    print(("Unable to write survivors.txt: %s"):format(err or "unknown error"))
    resultsRecorded = true
    return
  end

  if #spawnedEntities > 0 then
    local survivors = {}
    for _, entity in ipairs(spawnedEntities) do
      survivors[#survivors + 1] = entity
    end

    table.sort(survivors, function(a, b)
      if a.kills == b.kills then
        return a.playerName < b.playerName
      end
      return a.kills > b.kills
    end)

    for _, entity in ipairs(survivors) do
      file:write(string.format("%s %d\n", entity.playerName, entity.kills))
    end
  end

  file:close()
  resultsRecorded = true
end

function module.load()
  infoFont = love.graphics.newFont(18)
  victoryFont = love.graphics.newFont(32)

  love.math.setRandomSeed(os.time())

  textures = {
    Paper = love.graphics.newImage("assets/paper.png"),
    Rock = love.graphics.newImage("assets/rock.png"),
    Scissors = love.graphics.newImage("assets/scissors.png"),
  }

  resetGameState()
end

function module.start()
  love.math.setRandomSeed(os.time())
  resetGameState()

  windowWidth, windowHeight = love.graphics.getDimensions()
  local maxSpriteWidth = windowWidth * 0.05
  local maxSpriteHeight = windowHeight * 0.05

  scales = {}
  for kind, image in pairs(textures) do
    scales[kind] = math.min(
      maxSpriteWidth / image:getWidth(),
      maxSpriteHeight / image:getHeight()
    )
  end

  loadPlayerNames()
  shufflePlayers()

  spawnQueue = {}
  for index, playerName in ipairs(playerNames) do
    local kind = orderedKinds[((index - 1) % #orderedKinds) + 1]
    spawnQueue[#spawnQueue + 1] = {
      playerName = playerName,
      kind = kind,
      image = textures[kind],
      scale = scales[kind],
    }
  end

  nextSpawnIndex = 1
  timeUntilNextSpawn = (#spawnQueue > 0) and SPAWN_DELAY or nil

  local survivorFile = io.open(SURVIVOR_PATH, "w")
  if survivorFile then
    survivorFile:close()
  end
end

function module.stop()
  resetGameState()
end

function module.update(dt)
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
        announceSpawningComplete()
      end
    end
    return
  end

  announceSpawningComplete()

  adjustEntitySpeeds()

  windowWidth, windowHeight = love.graphics.getDimensions()
  local minX, minY, maxX, maxY = getPlayfieldBounds()

  if spawnCompleteAnnounced then
    for _, entity in ipairs(spawnedEntities) do
      ensureTargetForEntity(entity)
    end
  end

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

    if spawnCompleteAnnounced and entity.targetEntity then
      local centerX = entity.x + entity.width / 2
      local centerY = entity.y + entity.height / 2
      local target = entity.targetEntity
      local targetCenterX = target.x + target.width / 2
      local targetCenterY = target.y + target.height / 2
      local dx = targetCenterX - centerX
      local dy = targetCenterY - centerY
      local dist = math.sqrt(dx * dx + dy * dy)
      local reachThreshold = (math.max(entity.width, entity.height) + math.max(target.width, target.height)) / 2 + 4
      if dist <= reachThreshold then
        entity.targetEntity = nil
        ensureTargetForEntity(entity)
      end
    end
  end

  handleEntityCollisions()
  removeDeadEntities()
  adjustEntitySpeeds()

  local activeTypes = getActiveTypes()
  if (not resultsRecorded) and #activeTypes <= 1 then
    recordSurvivors()
  end
end

function module.draw()
  windowWidth, windowHeight = love.graphics.getDimensions()

  love.graphics.setFont(infoFont)
  love.graphics.setColor(1, 1, 1)

  local minX, minY, maxX, maxY, _, lineSpacing = getPlayfieldBounds()
  local activeTypes = getActiveTypes()

  local countersText = string.format(
    "Paper: %d | Rock: %d | Scissors: %d",
    aliveCounts.Paper,
    aliveCounts.Rock,
    aliveCounts.Scissors
  )
  love.graphics.print(countersText, PADDING, PADDING)

  love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)

  for _, entity in ipairs(spawnedEntities) do
    local image = entity.image
    local killsSuffix = entity.kills > 0 and (" " .. entity.kills) or ""
    local label = entity.playerName .. killsSuffix
    local labelX = entity.x + (entity.width - infoFont:getWidth(label)) / 2
    love.graphics.print(label, labelX, entity.y - infoFont:getHeight() - 4)
    love.graphics.draw(image, entity.x, entity.y, 0, entity.scale, entity.scale)
  end

  local twoLeft = not timeUntilNextSpawn and #activeTypes == 2
  local hasWinner = not timeUntilNextSpawn and #spawnedEntities > 0 and #activeTypes == 1
  if twoLeft then
    love.graphics.setFont(infoFont)
    local alert = "Only two left!!"
    love.graphics.print(alert, PADDING, PADDING + lineSpacing)
  end

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

function module.keypressed(key)
  if key == "r" then
    module.start()
  end
end

return module
