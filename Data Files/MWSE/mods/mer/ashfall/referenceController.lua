
local staticConfigs = require('mer.ashfall.config.staticConfigs')
local this = {}

---@class Ashfall.ReferenceController
---@field references table<tes3reference, true>
---@field requirements fun(self: Ashfall.ReferenceController, ref: tes3reference): any
---@field requirementsAreStatic boolean? When true, iteration skips the per-ref requirements() re-check and uses ref:isValid() instead (membership is invariant per ref).
local ReferenceController = {
    new = function(self, o)
        o = o or {}   -- create object if user does not provide one
        o.references = {}
        setmetatable(o, self)
        self.__index = self
        return o
    end,

    addReference = function(self, ref)
        self.references[ref] = true
    end,

    removeReference = function(self, ref)
            self.references[ref] = nil
    end,

    isReference = function(self, ref)
        return self:requirements(ref)
    end,

    iterate = function(self, callback)
        local static = self.requirementsAreStatic
        for ref in pairs(self.references) do
            --For a static controller a ref's membership can never change, so skip the
            --(potentially expensive, e.g. getObjectByName/isActivator) requirements()
            --re-check and just confirm the ref still points to live memory.
            --objectInvalidated already prunes deleted refs; ref:isValid() is the cheap
            --crash-safe backstop. Dynamic controllers re-run requirements() as before.
            local valid
            if static then
                valid = ref:isValid()
            else
                valid = self:requirements(ref)
            end
            if valid then
                if ref.sceneNode then
                    callback(ref)
                end
            else
                --no longer valid, remove from ref list
                self.references[ref] = nil
            end
        end
    end,
}

---@type table<string, Ashfall.ReferenceController>
this.controllers = {
    campfire = ReferenceController:new{
        requirementsAreStatic = true, --SWITCH_FIRE node is structural
        requirements = function(_, ref)
            return ref.sceneNode
                and ref.sceneNode:getObjectByName("SWITCH_FIRE")
        end
    },

    weakFire = ReferenceController:new{
        requirementsAreStatic = true, --SWITCH_CANDLELIGHT node is structural
        requirements = function(_, ref)
            return ref.sceneNode
                and ref.sceneNode:getObjectByName("SWITCH_CANDLELIGHT")
        end
    },

    stewBuffedActor = ReferenceController:new{
        requirements = function(_, ref)
            return ref.supportsLuaData
                and ref.data
                and ref.data.stewBuffTimeLeft
        end
    },

    teaBuffedActor = ReferenceController:new{
        requirements = function(_, ref)
            return ref.supportsLuaData
                and ref.data
                and ref.data.teaBuffTimeLeft
        end
    },

    hazard = ReferenceController:new{
        requirementsAreStatic = true, --keyed on object id, which never changes
        requirements = function(_, ref)
            return staticConfigs.heatSourceValues[ref.object.id:lower()]
        end
    },

    waterContainer = ReferenceController:new{
        requirementsAreStatic = true, --keyed on object id, which never changes
        requirements = function(_, ref)
            return staticConfigs.bottleList[ref.object.id:lower()]
        end
    },

    utensil = ReferenceController:new{
        requirementsAreStatic = true, --POT_WATER node is structural
        requirements = function(_, ref)
            return ref.sceneNode and ref.sceneNode:getObjectByName("POT_WATER")
        end
    },
    kettle = ReferenceController:new{
        requirementsAreStatic = true, --SWITCH_KETTLE_STEAM node is structural
        requirements = function(_, ref)
            return ref.sceneNode and ref.sceneNode:getObjectByName("SWITCH_KETTLE_STEAM")
        end
    },
    fryingPan = ReferenceController:new{
        requirementsAreStatic = true, --keyed on object id, which never changes
        requirements = function(_, ref)
            local grillConfig = staticConfigs.grills[ref.object.id:lower()]
            return grillConfig and grillConfig.fryingPan
        end
    },
    grillableFood = ReferenceController:new{
        ---@param ref tes3reference
        requirements = function(_, ref)
            local validCell = true
            if tes3.player and ref.cell then
                local interiorCell = ref.cell.isInterior == true
                if interiorCell then
                    --interior: same as player
                    validCell = ref.cell == tes3.player.cell
                else
                    --exterior: player also in exterior
                    validCell = tes3.player.cell.isInterior ~= true
                end
            end
            return validCell and staticConfigs.foodConfig.getGrillValues(ref.object)
        end
    },
    waterFilter = ReferenceController:new{
        requirementsAreStatic = true, --FILTER_WATER node is structural
        requirements = function(_, ref)
            local isWaterFilter = ref.sceneNode
                and ref.sceneNode:getObjectByName("FILTER_WATER")
            return isWaterFilter
        end
    }
}

local function onRefPlaced(e)
    for _, controller in pairs(this.controllers) do
        if controller:requirements(e.reference) then
            controller:addReference(e.reference)
        end
    end
end
event.register(tes3.event.referenceActivated, onRefPlaced)
event.register("Ashfall:registerReference", onRefPlaced)

event.register(tes3.event.loaded, function(e)
    for _, cell in pairs(tes3.getActiveCells()) do
        for ref in cell:iterateReferences() do
            onRefPlaced{ reference = ref }
        end
    end
end)

local function onObjectInvalidated(e)
    local ref = e.object
    for _, controller in pairs(this.controllers) do
        if controller.references[ref] then
            controller:removeReference(ref)
        end
    end
end
event.register("objectInvalidated", onObjectInvalidated)

---@param e { id: string, requirements: fun(self: Ashfall.ReferenceController, ref: tes3reference): boolean, requirementsAreStatic: boolean? }
function this.registerReferenceController(e)
    assert(e.id, "No id provided")
    assert(e.requirements, "No reference requirements provided")
    assert(this.controllers[e.id] == nil, "Reference controller already registered")
    this.controllers[e.id] = ReferenceController:new{
        requirements = e.requirements,
        requirementsAreStatic = e.requirementsAreStatic,
    }
    return this.controllers[e.id]
end
event.register("Ashfall:RegisterReferenceController", this.registerReferenceController)

function this.iterateReferences(refType, callback)
    local controller = this.controllers[refType]
    local references = controller.references --[[@as table<tes3reference, true>]]
    local static = controller.requirementsAreStatic
    for ref in pairs(references) do
        --Static controllers skip the requirements() re-check and use the cheap
        --ref:isValid() liveness guard (see ReferenceController.requirementsAreStatic).
        local valid
        if static then
            valid = ref:isValid()
        else
            valid = controller:requirements(ref)
        end
        if valid then
            if ref.sceneNode then
                callback(ref)
            end
        else
            --no longer valid, remove from ref list
            references[ref] = nil
        end
    end
end

---@param refType string
---@param reference tes3reference
---@return boolean
function this.isReference(refType, reference)
    return this.controllers[refType]:isReference(reference)
end

return this