local _, addon = ...

-- House lists arrive asynchronously. Never teleport from the response callback:
-- the protected action must execute from the player's next button click.
addon.Housing = {}
local Housing = addon.Housing
local houses = {}
local mapFactions = { [2352] = "Alliance", [2351] = "Horde" }

function Housing.CanReturn(faction)
 local house = houses[faction]
 return house ~= nil and C_HousingNeighborhood and C_HousingNeighborhood.CanReturnAfterVisitingHouse
  and C_HousingNeighborhood.CanReturnAfterVisitingHouse()
  and C_Housing.GetCurrentNeighborhoodGUID() == house.neighborhoodGUID or false
end

function Housing.IsAvailable(faction)
 return C_Housing and C_Housing.TeleportHome and C_Housing.ReturnAfterVisitingHouse
  and houses[faction] ~= nil or false
end

function Housing.ConfigureButton(button, faction)
 if InCombatLockdown() then return end
 button:SetAttribute("type1", nil)
 if not Housing.IsAvailable(faction) then return end
 if Housing.CanReturn(faction) then
  button:SetAttribute("type1", "returnhome")
 else
  local house = houses[faction]
  button:SetAttribute("house-neighborhood-guid1", house.neighborhoodGUID)
  button:SetAttribute("house-guid1", house.houseGUID)
  button:SetAttribute("house-plot-id1", house.plotID)
  button:SetAttribute("type1", "teleporthome")
 end
end

if C_Housing and C_Housing.GetPlayerOwnedHouses then
 local frame = CreateFrame("Frame")
 frame:RegisterEvent("PLAYER_ENTERING_WORLD")
 frame:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
 frame:SetScript("OnEvent", function(_, event, houseInfos)
  if event == "PLAYER_ENTERING_WORLD" then
   C_Housing.GetPlayerOwnedHouses()
  else
   houses = {}
   for _, house in ipairs(houseInfos or {}) do
    if house.neighborhoodGUID and house.houseGUID and house.plotID then
     local faction = mapFactions[C_Housing.GetUIMapIDForNeighborhood(house.neighborhoodGUID)]
     if faction then houses[faction] = house end
    end
   end
   if addon.MapPanel.Refresh then addon.MapPanel.Refresh() end
  end
 end)
end
