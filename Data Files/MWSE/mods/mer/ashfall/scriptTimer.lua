--[[ Timer function for weather updates]]--
local common = require("mer.ashfall.common.common")
local temperatureController = require("mer.ashfall.temperatureController")

local weather = require("mer.ashfall.tempEffects.weather")
local wetness = require("mer.ashfall.tempEffects.wetness")
local conditions = require("mer.ashfall.conditions.conditionController")
local torch = require("mer.ashfall.tempEffects.torch")
local raceEffects = require("mer.ashfall.tempEffects.raceEffects")
local fireEffect = require("mer.ashfall.tempEffects.fireEffect")
local magicEffects = require("mer.ashfall.tempEffects.magicEffects")
local hazardEffects = require("mer.ashfall.tempEffects.hazardEffects")
local sunEffect = require("mer.ashfall.tempEffects.sunEffect")
local frostBreath = require("mer.ashfall.effects.frostBreath")
local statsEffect = require("mer.ashfall.needs.statsEffect")

--Needs
local needs = {
    thirst = require("mer.ashfall.needs.thirstController"),
    hunger = require("mer.ashfall.needs.hungerController"),
    tiredness = require("mer.ashfall.needs.sleepController"),
    sickness = require("mer.ashfall.needs.sicknessController"),
}


local function getHoursPassed()
    return ( tes3.worldController.daysPassed.value * 24 ) + tes3.worldController.hour.value
end

local function getInterval(hoursPassed)
    common.data.lastTimeScriptsUpdated = common.data.lastTimeScriptsUpdated or hoursPassed
    local interval = math.abs(hoursPassed - common.data.lastTimeScriptsUpdated)
    --limit to 8 hours in case some crazy time leap
    interval = math.clamp(interval, 0.0, 8.0)
    return interval
end

local function getTimerInterval(hoursPassed)
    common.data.lastTimeTimerScriptsUpdated = common.data.lastTimeTimerScriptsUpdated or hoursPassed
    local interval = math.abs(hoursPassed - common.data.lastTimeTimerScriptsUpdated)
    --limit to 8 hours in case some crazy time leap
    interval = math.clamp(interval, 0.0, 8.0)
    return interval
end

--Heavy world-reference scans (fireEffect/hazardEffects/frostBreath) only sample current
--state, so they run on their own slower HEAVY_SCAN_INTERVAL rather than every tick.
local TICK_DURATION = 0.1
local HEAVY_SCAN_INTERVAL = 0.5


local function callUpdates()
    if not tes3.player then return end

    statsEffect.calculate()
    --temp effects
    raceEffects.calculateRaceEffects()
    torch.calculateTorchTemp()
    conditions.updateConditions()

    local hoursPassed = getHoursPassed()
    local interval = getInterval(hoursPassed)
    common.data.lastTimeScriptsUpdated = hoursPassed
    --Needs:
    for _, script in pairs(needs) do
        script.calculate(interval)
    end
    event.trigger("Ashfall:UpdateNeedsUI")
    --Don't fire Ashfall:UpdateHUD here: temperatureController.calculate fires it itself
    --post-temp-update, so firing here would be redundant and show last tick's temperature.
    temperatureController.calculate(interval)
end

--Heavy world-reference scans, run on their own slower HEAVY_SCAN_INTERVAL clock. Decoupled
--from callUpdates: they only write state the tick samples, with no ordering dependency.
local function doHeavyScans()
    if not tes3.player then return end
    fireEffect.calculateFireEffect()
    hazardEffects.calculateHazards()
    frostBreath.doFrostBreath()
end
--Driven by a simulate timer (pauses in menus). Needs/temperature math is interval-driven
--by game hours so the tick rate doesn't affect accumulation; non-interval temp effects only
--recompute current state, which can't change while paused.
event.register("loaded", function()
    timer.start{
        type = timer.simulate,
        duration = TICK_DURATION,
        iterations = -1,
        persist = false,
        callback = callUpdates,
    }
    --Heavy world-reference scans on their own slower simulate clock (also pauses in menus).
    timer.start{
        type = timer.simulate,
        duration = HEAVY_SCAN_INTERVAL,
        iterations = -1,
        persist = false,
        callback = doHeavyScans,
    }
end)

--[[
    Both simulate timers above pause during a vanilla rest/wait, which would otherwise
    freeze needs/temperature for the whole rest. enterFrame keeps firing in menu mode, so
    for the duration of a rest we drive the full stack there instead. Interval is still
    game-hours based, so accumulation matches normal play; fps doesn't matter in the menu.
    Heavy scans run first so fireTemp etc. are fresh before the temperature recompute.
]]
local function restMenuUpdate()
    if not tes3.player then return end
    if not (common.helper.getIsSleeping() or common.helper.getIsWaiting()) then
        --Rest/wait ended: stop driving on enterFrame; the simulate timers take over again.
        event.unregister("enterFrame", restMenuUpdate)
        return
    end
    doHeavyScans()
    callUpdates()
end

--Start driving the moment a rest/wait begins (the player is already flagged sleeping/
--waiting at this point, so restMenuUpdate won't immediately tear itself down).
event.register("calcRestInterrupt", function()
    if not event.isRegistered("enterFrame", restMenuUpdate) then
        event.register("enterFrame", restMenuUpdate)
    end
end)

--Backstop teardown when the rest menu closes (no-op if already unregistered).
event.register("menuExit", function()
    event.unregister("enterFrame", restMenuUpdate)
end)

event.register("loaded", function()
    timer.start{
        type = timer.real,
        duration = 0.2,
        iterations = -1,
        callback = function()
            local hoursPassed = getHoursPassed()
            local interval = getTimerInterval(hoursPassed)
            common.data.lastTimeTimerScriptsUpdated = hoursPassed

            magicEffects.calculateMagicEffects(interval)
            weather.calculateWeatherEffect(interval)
            sunEffect.calculate(interval)
            wetness.calculateWetTemp(interval)
            needs.hunger.processMealBuffs(interval)
            tes3.player.data.Ashfall.valuesInitialised = true

        end
    }
end)