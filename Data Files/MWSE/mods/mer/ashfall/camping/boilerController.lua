
local thirstController = require "mer.ashfall.needs.thirstController"
--[[
    --Handles the heating and cooling of objects that can boil water
]]
local LiquidContainer = require("mer.ashfall.liquid.LiquidContainer")
local common = require ("mer.ashfall.common.common")
local logger = common.createLogger("boilerController")
local HeatUtil = require("mer.ashfall.heat.HeatUtil")
local patinaController = require("mer.ashfall.camping.patinaController")
local BOILER_UPDATE_INTERVAL = 0.001
local ReferenceController = require("mer.ashfall.referenceController")

ReferenceController.registerReferenceController{
    id = "boiler",
    --Allocation-free validation. Equivalent to building a LiquidContainer and
    --checking waterAmount, but without the per-tick table churn: matches the same
    --gating as LiquidContainer.createFromReference/new (supportsLuaData + a
    --recognised vessel in bottleList + water present).
    requirements = function(_, ref)
        if not ref.supportsLuaData then return false end
        local data = ref.data
        if not data or (data.waterAmount or 0) <= 0 then return false end
        local id = data.utensilId or ref.baseObject.id
        return common.staticConfigs.bottleList[id:lower()] ~= nil
    end
}

local function addUtensilPatina(campfire,interval)
    if not patinaController.enabled then return end
    if campfire.sceneNode and campfire.data.utensilId then
        logger:trace("Attempting to add Patina to %s", campfire.data.utensilId)
        local node = campfire.sceneNode:getObjectByName("ATTACH_HANGER")
            or campfire.sceneNode:getObjectByName("HANG_UTENSIL")
        local patinaAmount = campfire.data.utensilPatinaAmount or 0
        local newAmount = math.clamp(patinaAmount + interval * 1, 0, 100)
        local didAddPatina = patinaController.addPatina(node, newAmount)
        if didAddPatina then
            campfire.data.utensilPatinaAmount = newAmount
            logger:trace("addUtensilPatina: Added patina to %s node, new amount: %s", node, campfire.data.utensilPatinaAmount)
        else
            logger:trace("addUtensilPatina: Mesh incompatible with patina mechanic, did not apply")
        end
    end
end

local function doUpdate(boilerRef)
    local timestamp = tes3.getSimulationTimestamp()
    local liquidContainer = LiquidContainer.createFromReference(boilerRef)
    if not liquidContainer then return end
    if liquidContainer.waterAmount == 0 then return end

    liquidContainer.data.lastWaterUpdated = liquidContainer.data.lastWaterUpdated or timestamp
    local timeSinceLastUpdate = timestamp - liquidContainer.data.lastWaterUpdated

    if timeSinceLastUpdate < 0 then
        logger:error("BOILER liquidContainer.data.lastWaterUpdated(%.4f) is ahead of timestamp(%.4f).",
            liquidContainer.data.lastWaterUpdated, timestamp)
        --something fucky happened
        liquidContainer.data.lastWaterUpdated = timestamp
    end

    local hasFilledPot = liquidContainer.waterAmount > 0
    if hasFilledPot then
        logger:trace("Updating heat for %s", liquidContainer)
        addUtensilPatina(liquidContainer.reference,timeSinceLastUpdate)

        HeatUtil.updateWaterHeat(liquidContainer)
        if liquidContainer:isBoiling() then
            --boil dirty water away
            if liquidContainer:getLiquidType() == "dirty" then
                liquidContainer.waterType = nil
            end
        end
        --Only refresh the tooltip if the player is actually looking at this boiler.
        if tes3.getPlayerTarget() == liquidContainer.reference then
            tes3ui.refreshTooltip()
        end
    else
        logger:trace("BOILER no filled pot, setting waterUpdated to nil")
        liquidContainer.data.lastWaterUpdated = nil
    end
end

event.register("loaded", function()
    timer.start{
        duration = common.helper.getUpdateIntervalInSeconds(),
        iterations = -1,
        callback = function()
            ReferenceController.iterateReferences("boiler", doUpdate)
        end,
    }
end)
