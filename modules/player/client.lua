gg.player = gg.player or {}

gg.player.teleport = function(coord)
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(0)
    end
    RequestCollisionAtCoord(coord.x, coord.y, coord.z)
    SetEntityCoords(ped, coord.x, coord.y, coord.z, false, false, false, true)
    SetEntityHeading(ped, coord.w)
    while not HasCollisionLoadedAroundEntity(ped) do
        Wait(0)
    end
    DoScreenFadeIn(500)
end

local TabletProp
gg.player.ToggleTablet = function(toggle)
    if toggle then
        if not DoesEntityExist(TabletProp) then
            local PlayerPed =  PlayerPedId()
            local PlayerCoords = GetEntityCoords(PlayerPed)
            gg.util.loadAnimDict("amb@code_human_in_bus_passenger_idles@female@tablet@idle_a")
            TaskPlayAnim(PlayerPed, 'amb@code_human_in_bus_passenger_idles@female@tablet@idle_a', 'idle_a', 2.0, 2.0, -1, 51, 0, false, false, false)
            TabletProp = CreateObject(GetHashKey("prop_cs_tablet"), PlayerCoords.x, PlayerCoords.y, PlayerCoords.z,  true,  true, true)
            AttachEntityToEntity(TabletProp, PlayerPed, GetPedBoneIndex(PlayerPed, 28422), -0.05, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        end
    else
        ClearPedTasks(PlayerPedId())
        if DoesEntityExist(TabletProp) then
            DeleteEntity(TabletProp)
        end
    end

    return true
end

local CLOTHING = {
  componentIds = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
  propIds = { 0, 1, 2, 6, 7 },

  modelMale = `mp_m_freemode_01`,
  modelFemale = `mp_f_freemode_01`,

  componentKeyToId = {
    face = 0,
    mask = 1,
    hair = 2,
    arms = 3,
    pants = 4,
    bag = 5,
    shoes = 6,
    accessory = 7,
    undershirt = 8,
    kevlar = 9,
    badge = 10,
    jacket = 11,
  },

  propKeyToId = {
    hat = 0,
    glasses = 1,
    ear = 2,
    watch = 6,
    bracelet = 7,
  },

  state = {
    isApplied = false,
    cachedComponents = {},
    cachedProps = {},
  }
}

gg.player.setClothing = function(cfgClothing)
  local ped = PlayerPedId()
  local state = CLOTHING.state

  local function isMale()
    local model = GetEntityModel(ped)
    if model == CLOTHING.modelMale then return true end
    if model == CLOTHING.modelFemale then return false end
    return IsPedMale(ped)
  end

  local function getValues(entry)
    if not entry then return nil, nil end
    local drawable = entry.drawable
    if drawable == nil then drawable = entry.drawableId end
    local texture = entry.texture
    if texture == nil then texture = entry.textureId end
    return drawable, texture
  end

  local function cacheCurrent()
    local components = {}
    for i = 1, #CLOTHING.componentIds do
      local id = CLOTHING.componentIds[i]
      components[id] = {
        id = id,
        drawable = GetPedDrawableVariation(ped, id),
        texture = GetPedTextureVariation(ped, id),
      }
    end

    local props = {}
    for i = 1, #CLOTHING.propIds do
      local id = CLOTHING.propIds[i]
      props[id] = {
        id = id,
        drawable = GetPedPropIndex(ped, id),
        texture = GetPedPropTextureIndex(ped, id),
      }
    end

    state.cachedComponents = components
    state.cachedProps = props
  end

  local function restoreCached()
    local components = state.cachedComponents
    if components and next(components) then
      for _, v in pairs(components) do
        SetPedComponentVariation(ped, v.id, v.drawable, v.texture, 0)
      end
    end

    local props = state.cachedProps
    if props and next(props) then
      for _, v in pairs(props) do
        if v.drawable == nil or v.drawable < 0 then
          ClearPedProp(ped, v.id)
        else
          SetPedPropIndex(ped, v.id, v.drawable, v.texture or 0, true)
        end
      end
    end
  end

  local function applyComponents(components)
    if not components or not next(components) then return end

    for key, componentId in pairs(CLOTHING.componentKeyToId) do
      if not componentId then goto _ end
      local entry = components[key] or components[componentId] or components[tostring(componentId)]
      local drawable, texture = getValues(entry)
      if drawable ~= nil and texture ~= nil then
        SetPedComponentVariation(ped, componentId, drawable, texture, 0)
      end
      ::_::
    end
  end

  local function applyProps(props)
    if not props or not next(props) then return end

    for key, propId in pairs(CLOTHING.propKeyToId) do
      if not propId then goto _ end
      
      local entry = props[key] or props[propId] or props[tostring(propId)]
      local drawable, texture = getValues(entry)

      if drawable ~= nil then
        if drawable < 0 then
          ClearPedProp(ped, propId)
        else
          SetPedPropIndex(ped, propId, drawable, texture or 0, true)
        end
      end
      
      ::_::
    end
  end

  if state.isApplied then
    restoreCached()
    state.isApplied = false
    state.cachedComponents = {}
    state.cachedProps = {}
    return
  end

  local outfit = cfgClothing and (isMale() and cfgClothing.male or cfgClothing.female)
  if not outfit then return end

  state.isApplied = true
  cacheCurrent()
  applyComponents(outfit.components)
  applyProps(outfit.props)
end
