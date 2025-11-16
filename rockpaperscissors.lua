local module = {}

local SPAWN_DELAY = 0.1
local DEFAULT_SPEED = 45
local WIN_SPEED = 100
local PADDING = 24
local TEXT_GAP = 6
local SIDEBAR_WIDTH = 400
local SIDEBAR_GAP = 8
local SHIELD_COLOR = { 0.3, 0.6, 1.0, 0.9 }
local SHIELD_LINE_WIDTH = 2
local SURVIVOR_PATH = "players/survivors.txt"

local BEATS = {
  Rock = "Scissors",
  Paper = "Rock",
  Scissors = "Paper",
}

local orderedKinds = { "Paper", "Rock", "Scissors" }
local spawnWeights = {
  { kind = "Rock", weight = 0.4 },
  { kind = "Paper", weight = 0.3 },
  { kind = "Scissors", weight = 0.3 },
}

local function getKillSpeedMultiplier(entity)
  local kills = (entity and entity.kills) or 0
  if kills <= 0 then
    return 1
  end
  return 1 + 0.1 * kills
end

local function getSpeedBonusMultiplier(entity)
  return (entity and entity.speedBonus) or 1
end

local CLASS_SHORTHAND = {
  Paper = "P",
  Rock = "R",
  Scissors = "C",
}

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
local playerStats = {}
local leaderboardScroll = 0
local leaderboardActiveTab = 1
local leaderboardTabBounds = {}
local leaderboardMaxScroll = 0
local debugPaused = false

local function chooseSpawnKind()
  local roll = love.math.random()
  local cumulative = 0
  for _, entry in ipairs(spawnWeights) do
    cumulative = cumulative + entry.weight
    if roll <= cumulative then
      return entry.kind
    end
  end
  return spawnWeights[#spawnWeights].kind
end

local function resetGameState()
  spawnQueue = {}
  spawnedEntities = {}
  aliveLookup = {}
  aliveCounts = { Paper = 0, Rock = 0, Scissors = 0 }
  nextSpawnIndex = 1
  timeUntilNextSpawn = nil
  resultsRecorded = false
  spawnCompleteAnnounced = false
  leaderboardScroll = 0
  leaderboardActiveTab = 1
  leaderboardTabBounds = {}
  leaderboardMaxScroll = 0
  debugPaused = false
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
  local availableWidth = windowWidth - minX - SIDEBAR_WIDTH - SIDEBAR_GAP - PADDING
  local availableHeight = windowHeight - minY - PADDING
  local desiredSize = 700
  local playfieldSize = math.min(desiredSize, availableWidth, availableHeight)
  local maxX = minX + playfieldSize
  local maxY = minY + playfieldSize
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
  entity.baseSpeed = speed or entity.baseSpeed or 0
  local effectiveSpeed = entity.baseSpeed
  if effectiveSpeed and effectiveSpeed > 0 then
    effectiveSpeed = effectiveSpeed * getKillSpeedMultiplier(entity) * getSpeedBonusMultiplier(entity)
  end

  entity.speed = effectiveSpeed or 0
  if not effectiveSpeed or effectiveSpeed <= 0 then
    entity.vx, entity.vy = 0, 0
    return
  end

  if not spawnCompleteAnnounced then
    local magnitude = math.sqrt(entity.vx * entity.vx + entity.vy * entity.vy)
    if magnitude == 0 then
      local angle = love.math.random() * 2 * math.pi
      entity.vx = math.cos(angle) * effectiveSpeed
      entity.vy = math.sin(angle) * effectiveSpeed
    else
      entity.vx = entity.vx / magnitude * effectiveSpeed
      entity.vy = entity.vy / magnitude * effectiveSpeed
    end
  end
end

local function addShield(entity, amount)
  if not entity or not amount or amount == 0 then
    return
  end
  entity.shield = math.max(0, (entity.shield or 0) + amount)
end

local function boostSpeed(entity, percent)
  if not entity or not percent or percent == 0 then
    return
  end
  entity.speedBonus = (entity.speedBonus or 1) * (1 + percent)
  setEntitySpeed(entity, entity.baseSpeed or DEFAULT_SPEED)
end

local function shrinkEntityByPercent(entity, percent)
  if not entity or not percent or percent <= 0 then
    return
  end
  entity.scale = entity.scale * (1 - percent)
  entity.width = entity.image:getWidth() * entity.scale
  entity.height = entity.image:getHeight() * entity.scale
  local minX, minY, maxX, maxY = getPlayfieldBounds()
  entity.x = math.max(minX, math.min(entity.x, maxX - entity.width))
  entity.y = math.max(minY, math.min(entity.y, maxY - entity.height))
end

local function consumeShield(entity)
  if entity and not entity.dead and (entity.shield or 0) > 0 then
    entity.shield = entity.shield - 1
    return true
  end
  return false
end

local function getEntityCenter(entity)
  return entity.x + entity.width / 2, entity.y + entity.height / 2
end

local function findClosestEntityOfKind(entity, kind)
  local closest
  local bestDistSq
  local ex, ey = getEntityCenter(entity)

  for _, candidate in ipairs(spawnedEntities) do
    if candidate ~= entity and not candidate.dead and candidate.kind == kind then
      local cx, cy = getEntityCenter(candidate)
      local dx = cx - ex
      local dy = cy - ey
      local distSq = dx * dx + dy * dy
      if not bestDistSq or distSq < bestDistSq then
        bestDistSq = distSq
        closest = candidate
      end
    end
  end

  return closest
end

local function steerScissors(entity)
  if entity.kind ~= "Scissors" or not spawnCompleteAnnounced then
    return
  end

  if not entity.speed or entity.speed <= 0 then
    return
  end

  local centerX, centerY = getEntityCenter(entity)
  local dirX, dirY = 0, 0

  local paperTarget = findClosestEntityOfKind(entity, "Paper")
  if paperTarget then
    local targetX, targetY = getEntityCenter(paperTarget)
    local dx = targetX - centerX
    local dy = targetY - centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
      dirX = dirX + dx / dist
      dirY = dirY + dy / dist
      entity.targetEntity = paperTarget
    end
  end

  local rockThreat = findClosestEntityOfKind(entity, "Rock")
  if rockThreat then
    local threatX, threatY = getEntityCenter(rockThreat)
    local dx = centerX - threatX
    local dy = centerY - threatY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
      dirX = dirX + dx / dist
      dirY = dirY + dy / dist
    end
  end

  local magnitude = math.sqrt(dirX * dirX + dirY * dirY)
  if magnitude > 0 then
    entity.vx = dirX / magnitude * entity.speed
    entity.vy = dirY / magnitude * entity.speed
  end
end

local function drawShield(entity)
  if not entity or not entity.shield or entity.shield <= 0 then
    return
  end

  local centerX = entity.x + entity.width / 2
  local centerY = entity.y + entity.height / 2
  local radius = math.max(entity.width, entity.height) / 2 + 6
  local prevLineWidth = love.graphics.getLineWidth()
  local prevR, prevG, prevB, prevA = love.graphics.getColor()

  love.graphics.setColor(SHIELD_COLOR)
  love.graphics.setLineWidth(SHIELD_LINE_WIDTH)
  love.graphics.circle("line", centerX, centerY, radius)
  love.graphics.setLineWidth(prevLineWidth)
  love.graphics.setColor(prevR, prevG, prevB, prevA)
end

local function getActiveLeaderboardEntries()
  local entries = {}
  for _, entity in ipairs(spawnedEntities) do
    entries[#entries + 1] = {
      name = entity.playerName,
      kind = entity.kind,
      kills = entity.kills or 0,
      shield = entity.shield or 0,
    }
  end

  table.sort(entries, function(a, b)
    if a.kills == b.kills then
      return a.name < b.name
    end
    return a.kills > b.kills
  end)

  return entries
end

local function drawSidebarLeaderboard(minY, maxY)
  local panelWidth = SIDEBAR_WIDTH
  local panelX = windowWidth - PADDING - panelWidth
  local panelY = minY
  local panelHeight = maxY - minY

  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", panelX, panelY, panelWidth, panelHeight)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("line", panelX, panelY, panelWidth, panelHeight)

  local title = "Current Players"
  love.graphics.print(title, panelX + 10, panelY + 10)

  local entries = getActiveLeaderboardEntries()
  local textHeight = infoFont:getHeight()
  local rowHeight = textHeight + 6
  local y = panelY + 16 + textHeight
  local tableX = panelX + 12
  local tableWidth = panelWidth - 24
  local panelBottom = panelY + panelHeight - 12

  if #entries == 0 then
    love.graphics.print("No active fighters", panelX + 10, y)
    return
  end

  local function widthForChars(chars)
    if chars <= 0 then
      return 0
    end
    return infoFont:getWidth(string.rep("W", chars))
  end

  local classColumnWidth = widthForChars(3)
  local killsColumnWidth = widthForChars(3)
  local shieldColumnWidth = widthForChars(3)
  local nameColumnWidth = tableWidth - (classColumnWidth + killsColumnWidth + shieldColumnWidth)
  if nameColumnWidth < widthForChars(8) then
    nameColumnWidth = widthForChars(8)
  end

  local columnWidths = {
    nameColumnWidth,
    classColumnWidth,
    killsColumnWidth,
    shieldColumnWidth,
  }
  local columnAlignments = { "left", "center", "center", "center" }
  local columnOffsets = {}
  local offset = tableX
  for index, width in ipairs(columnWidths) do
    columnOffsets[index] = offset
    offset = offset + width
  end

  local function drawRow(columns, color)
    if y + rowHeight > panelBottom then
      return false
    end
    love.graphics.setColor(color or { 1, 1, 1, 1 })
    for i = 1, #columns do
      love.graphics.printf(columns[i], columnOffsets[i], y, columnWidths[i], columnAlignments[i])
    end
    y = y + rowHeight
    return true
  end

  local function fillDash(width)
    local dash = "-"
    local str = dash
    while infoFont:getWidth(str) < width do
      str = str .. dash
    end
    return str
  end

  drawRow({ "Name", "Class", "Kills", "Shield" }, { 1, 1, 1, 1 })
  drawRow({ fillDash(nameColumnWidth), fillDash(classColumnWidth), fillDash(killsColumnWidth), fillDash(shieldColumnWidth) }, { 0.8, 0.8, 0.8, 1 })

  for _, entry in ipairs(entries) do
    local shieldText = tostring(math.max(0, entry.shield or 0))
    local classText = CLASS_SHORTHAND[entry.kind] or "?"
    local displayName = entry.name
    while infoFont:getWidth(displayName) > nameColumnWidth do
      if #displayName <= 1 then
        break
      end
      displayName = displayName:sub(1, -2)
    end
    if displayName ~= entry.name then
      if infoFont:getWidth(displayName .. "...") <= nameColumnWidth then
        displayName = displayName .. "..."
      else
        displayName = displayName:sub(1, -2) .. "..."
      end
    end
    if not drawRow({ displayName, classText, tostring(entry.kills), shieldText }, { 0.85, 0.93, 1, 1 }) then
      break
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
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

local function applyAttackBonuses(attacker, defender)
  if not attacker or attacker.dead then
    return
  end

  addShield(attacker, 1)
  boostSpeed(attacker, 0.05)

  if attacker.kind == "Rock" and defender.kind == "Scissors" then
    addShield(attacker, 2)
  elseif attacker.kind == "Paper" and defender.kind == "Rock" then
    boostSpeed(attacker, 0.30)
  elseif attacker.kind == "Scissors" and defender.kind == "Paper" then
    boostSpeed(attacker, 0.10)
    shrinkEntityByPercent(attacker, 0.05)
    local roll = love.math.random()
    if roll <= 0.5 then
      addShield(attacker, 2)
    elseif roll <= 0.8 then
      addShield(attacker, 1)
    else
      addShield(attacker, 3)
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
  entity.scale = entity.scale * 1.2
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
              applyAttackBonuses(a, b)
              if consumeShield(b) then
                separateEntities(a, b)
              else
                b.dead = true
                a.kills = a.kills + 1
                growEntity(a)
                emitDeathEvent(b)
                if playerStats[a.playerName] then
                  playerStats[a.playerName].kills = playerStats[a.playerName].kills + 1
                end
                aliveCounts[b.kind] = math.max(0, aliveCounts[b.kind] - 1)
              end
            elseif BEATS[b.kind] == a.kind then
              applyAttackBonuses(b, a)
              if consumeShield(a) then
                separateEntities(a, b)
              else
                a.dead = true
                b.kills = b.kills + 1
                growEntity(b)
                emitDeathEvent(a)
                if playerStats[b.playerName] then
                  playerStats[b.playerName].kills = playerStats[b.playerName].kills + 1
                end
                aliveCounts[a.kind] = math.max(0, aliveCounts[a.kind] - 1)
                break
              end
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

  if not playerStats[entry.playerName] then
    playerStats[entry.playerName] = { name = entry.playerName, kind = entry.kind, kills = 0 }
  else
    playerStats[entry.playerName].kind = entry.kind
  end

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
    baseSpeed = DEFAULT_SPEED,
    speedBonus = 1,
    shield = 1,
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
  playerStats = {}
  leaderboardScroll = 0
  leaderboardActiveTab = 1
  leaderboardTabBounds = {}
  leaderboardMaxScroll = 0

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
    local kind = chooseSpawnKind()
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
  leaderboardScroll = 0
  playerStats = {}
  leaderboardActiveTab = 1
  leaderboardTabBounds = {}
  leaderboardMaxScroll = 0
end

function module.update(dt)
  if debugPaused then
    return
  end

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
      if entity.kind == "Scissors" then
        steerScissors(entity)
      end
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

  local hasWinner = not timeUntilNextSpawn and #spawnedEntities > 0 and #activeTypes == 1
  if hasWinner then
    local winner = activeTypes[1]
    countersText = string.format("%s | %s wins! Press R to reset", countersText, winner)
  end

  love.graphics.print(countersText, PADDING, PADDING)

  love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)

  local twoLeft = not timeUntilNextSpawn and #activeTypes == 2
  if not hasWinner then
    leaderboardTabBounds = {}
    leaderboardMaxScroll = 0
    leaderboardScroll = 0
    for _, entity in ipairs(spawnedEntities) do
      local image = entity.image
      local killsSuffix = entity.kills > 0 and (" " .. entity.kills) or ""
      local label = entity.playerName .. killsSuffix
      local labelX = entity.x + (entity.width - infoFont:getWidth(label)) / 2
      love.graphics.print(label, labelX, entity.y - infoFont:getHeight() - 4)
      love.graphics.draw(image, entity.x, entity.y, 0, entity.scale, entity.scale)
      drawShield(entity)
    end
  end

  drawSidebarLeaderboard(minY, maxY)

  if twoLeft and not hasWinner then
    love.graphics.setFont(infoFont)
    local alert = "Only two left!!"
    love.graphics.print(alert, PADDING, PADDING + lineSpacing)
  end

  if hasWinner then
    local winner = activeTypes[1]

    local statsList = {}
    for _, data in pairs(playerStats) do
      if data.kills > 0 then
        statsList[#statsList + 1] = data
      end
    end
    table.sort(statsList, function(a, b)
      if a.kills == b.kills then
        return a.name < b.name
      end
      return a.kills > b.kills
    end)

    local winnersList = {}
    for _, data in pairs(playerStats) do
      if data.kind == winner then
        winnersList[#winnersList + 1] = data
      end
    end
    table.sort(winnersList, function(a, b)
      if a.kills == b.kills then
        return a.name < b.name
      end
      return a.kills > b.kills
    end)

    local tabs = {
      { label = "Top Killers", data = statsList },
      { label = "Winners Leaderboard", data = winnersList },
    }

    leaderboardActiveTab = math.max(1, math.min(leaderboardActiveTab, #tabs))

    local fontHeight = infoFont:getHeight()
    local tabHeight = fontHeight + 12
    local headerHeight = fontHeight + 8
    local rowHeight = fontHeight + 6
    local padding = 12
    local viewportWidth = math.min(500, windowWidth - 2 * PADDING)

    local activeTab = tabs[leaderboardActiveTab]
    local data = activeTab.data
    local contentRows = math.max(1, #data)
    local bottomPadding = rowHeight
    local contentHeight = headerHeight + contentRows * rowHeight + bottomPadding
    local viewportHeight = math.min(windowHeight * 0.7, contentHeight + tabHeight + padding * 2)
    local viewportX = (windowWidth - viewportWidth) / 2
    local viewportY = (windowHeight - viewportHeight) / 2

    leaderboardMaxScroll = math.max(0, contentHeight - (viewportHeight - tabHeight - padding))
    leaderboardScroll = math.max(0, math.min(leaderboardScroll, leaderboardMaxScroll))

    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", viewportX, viewportY, viewportWidth, viewportHeight)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", viewportX, viewportY, viewportWidth, viewportHeight)

    leaderboardTabBounds = {}
    local tabWidth = viewportWidth / #tabs
    for index, tab in ipairs(tabs) do
      local tabX = viewportX + (index - 1) * tabWidth
      local tabY = viewportY
      if index == leaderboardActiveTab then
        love.graphics.setColor(0.2, 0.5, 0.2, 0.9)
      else
        love.graphics.setColor(0.2, 0.2, 0.2, 0.7)
      end
      love.graphics.rectangle("fill", tabX, tabY, tabWidth, tabHeight)
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("line", tabX, tabY, tabWidth, tabHeight)
      love.graphics.printf(tab.label, tabX, tabY + (tabHeight - fontHeight) / 2, tabWidth, "center")
      leaderboardTabBounds[index] = { x = tabX, y = tabY, w = tabWidth, h = tabHeight }
    end

    local contentTop = viewportY + tabHeight + padding
    local scissorX = viewportX
    local scissorY = contentTop
    local scissorHeight = viewportHeight - (contentTop - viewportY) - padding
    love.graphics.setScissor(scissorX, scissorY, viewportWidth, scissorHeight)

    local function drawTable(entries)
      local textHeight = infoFont:getHeight()
      local rowHeight = textHeight + 6
      local y = contentTop + headerHeight - leaderboardScroll
      local tableX = viewportX + 12
      local tableWidth = viewportWidth - 24
      local nameWidth = tableWidth * 0.45
      local classWidth = tableWidth * 0.2
      local killsWidth = tableWidth - nameWidth - classWidth

      local columnWidths = { nameWidth, classWidth, killsWidth }
      local columnOffsets = { tableX, tableX + nameWidth, tableX + nameWidth + classWidth }
      local columnAlignments = { "left", "center", "center" }

      local function drawRow(columns, color)
        love.graphics.setColor(color or { 1, 1, 1, 1 })
        if y + rowHeight > scissorY + scissorHeight then
          return false
        end
        for i = 1, #columns do
          love.graphics.printf(columns[i], columnOffsets[i], y, columnWidths[i], columnAlignments[i])
        end
        y = y + rowHeight
        return true
      end

      drawRow({ "Name", "Class", "Kills" }, { 1, 1, 1, 1 })
      drawRow({ "----", "-----", "-----" }, { 0.8, 0.8, 0.8, 1 })

      if #entries == 0 then
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("No entries yet.", tableX, y, tableWidth, "left")
        return
      end

      for _, entry in ipairs(entries) do
        local classText = CLASS_SHORTHAND[entry.kind] or "?"
        if not drawRow({ entry.name, classText, tostring(entry.kills) }, { 0.85, 0.93, 1, 1 }) then
          break
        end
      end
    end

    drawTable(data)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
  else
    leaderboardTabBounds = {}
    leaderboardMaxScroll = 0
    leaderboardScroll = 0
  end
end

function module.keypressed(key)
  if key == "r" then
    module.start()
    return
  end

  if key == "k" then
    debugPaused = not debugPaused
    return
  end

  if spawnCompleteAnnounced and #getActiveTypes() == 1 then
    if key == "tab" or key == "right" then
      leaderboardActiveTab = leaderboardActiveTab + 1
      if leaderboardActiveTab > 2 then
        leaderboardActiveTab = 1
      end
      leaderboardScroll = 0
    elseif key == "left" then
      leaderboardActiveTab = leaderboardActiveTab - 1
      if leaderboardActiveTab < 1 then
        leaderboardActiveTab = 2
      end
      leaderboardScroll = 0
    end
  end
end

function module.wheelmoved(_, y)
  if not spawnCompleteAnnounced or leaderboardMaxScroll <= 0 then
    return
  end
  leaderboardScroll = math.max(0, math.min(leaderboardScroll - y * 24, leaderboardMaxScroll))
end

function module.mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  if not spawnCompleteAnnounced or #getActiveTypes() ~= 1 then
    return
  end

  for index, bounds in ipairs(leaderboardTabBounds) do
    if bounds and x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h then
      leaderboardActiveTab = index
      leaderboardScroll = 0
      break
    end
  end
end

return module
