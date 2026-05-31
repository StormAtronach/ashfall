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

-- The survival tick runs at TICK_DURATION (~10Hz). The heavy world-reference scans
-- (fireEffect/hazardEffects iterate the fuelConsumer/flame/heatSource controllers with
-- per-ref distance tests; frostBreath iterates every active-cell actor) only sample the
-- *current* heat / refresh cosmetic breath, so they run on their own slower timer
-- (HEAVY_SCAN_INTERVAL) rather than every tick. Temperature still integrates every tick
-- from the last sampled fireTemp/hazardTemp.
local TICK_DURATION = 0.1
local HEAVY_SCAN_INTERVAL = 0.5


local function callUpdates()
    if not tes3.player then return end

    statsEffect.calculate()
    -- --temp effects
    raceEffects.calculateRaceEffects()
    torch.calculateTorchTemp()
    conditions.updateConditions() --1fps

    local hoursPassed = getHoursPassed()
    local interval = getInterval(hoursPassed)
    common.data.lastTimeScriptsUpdated = hoursPassed
    --Needs:
    for _, script in pairs(needs) do
        script.calculate(interval)
    end
    event.trigger("Ashfall:UpdateNeedsUI")
    -- Don't fire Ashfall:UpdateHUD here: temperatureController.calculate (next line) fires it
    -- itself, post-temp-update. Firing it here too caused a redundant ~2x/tick HUD relayout,
    -- and the pre-update fire showed last tick's temperature.
    temperatureController.calculate(interval)
end

-- Heavy world-reference scans, run on their own slower clock (see HEAVY_SCAN_INTERVAL).
-- Decoupled from callUpdates: these only write fireTemp/hazardTemp/cosmetic breath, which
-- the tick samples — there's no per-tick ordering dependency.
local function doHeavyScans()
    if not tes3.player then return end
    fireEffect.calculateFireEffect()
    hazardEffects.calculateHazards()
    frostBreath.doFrostBreath()
end
-- The survival stack used to run on `enterFrame` (~60Hz, and even while paused
-- in menus). It's now driven by a simulate timer (~10Hz, paused in menus). The
-- needs/temperature math is interval-driven by game hours, so a lower tick rate
-- accumulates identically; the non-interval temp effects (fire/torch/etc.) only
-- recompute the current state, which can't change while the game is paused.
-- Timers are cancelled right before each `loaded`, so re-starting here on every
-- load does not stack.
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

-- The simulate timer doesn't tick during a vanilla rest/wait (menu mode), so the
-- needs that would have accumulated over those hours are applied once at the rest
-- boundary via the Ashfall:RestFinished event (see the needs controllers). Without
-- this, the first tick after the rest would see the whole rest as a single interval
-- and double-apply those needs at the normal rate. Re-baseline the interval clock so
-- that catch-up tick is a no-op. (The real timer keeps ticking through the rest, so
-- lastTimeTimerScriptsUpdated is left untouched.)
event.register("Ashfall:RestFinished", function()
    common.data.lastTimeScriptsUpdated = getHoursPassed()
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