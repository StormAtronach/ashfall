
local https = require "ssl.https"
local config = require("mer.ashfall.config").config

local this = {}

function this.getVersion()
    local metadata = toml.loadMetadata("Ashfall") --[[@as MWSE.Metadata]]
    return metadata.package.version
end

local currentVersion, latestVersion
local showConfirmUpdate
local showConfirmDisableNotifications
local function showUpdateMessageBox()
    local msg = string.format('A new version of Ashfall is now available!')
    ---@type tes3ui.showMessageMenu.params.button[]
    local buttons = {
        {
            text = string.format('Download Ashfall %s', latestVersion),
            callback = showConfirmUpdate
        }, {
            text = "Disable Update Notifications",
            callback = showConfirmDisableNotifications
        }
    }

    tes3ui.showMessageMenu {
        message = msg,
        buttons = buttons,
        cancels = true
    }
end

showConfirmUpdate = function()
    ---@type tes3ui.showMessageMenu.params.button[]
    local buttons = {
        {
            text = tes3.findGMST(tes3.gmst.sYes).value,
            callback = function()
                os.execute(
                    "start https://github.com/jhaakma/ashfall/releases/latest/download/Ashfall.7z")
                os.execute(
                    "start https://github.com/jhaakma/ashfall/releases/latest")
                os.exit()
            end
        }
    }
    tes3ui.showMessageMenu {
        message = "Exit Morrowind and download latest Ashfall?",
        buttons = buttons,
        cancels = true,
        cancelCallback = showUpdateMessageBox
    }
end

showConfirmDisableNotifications = function()
    local message = "Disable update notifications?"
    ---@type tes3ui.showMessageMenu.params.button[]
    local buttons = {
        {
            text = tes3.findGMST(tes3.gmst.sYes).value,
            callback = function()
                config.checkForUpdates = false
                config.save()
                tes3ui.showMessageMenu{
                    message = "Update notifications disabled. You can enable them again in the Development Options in the MCM.",
                    buttons = {
                        { text = tes3.findGMST(tes3.gmst.sOK).value}
                    }
                }
            end
        }
    }
    tes3ui.showMessageMenu{ message = message, buttons = buttons, cancels = true, cancelCallback = showUpdateMessageBox }
end

local hasChecked = false
function this.checkForUpdates()
    if not config.checkForUpdates then return end
    if hasChecked then return end
    hasChecked = true
    -- The update check is a *synchronous* HTTPS request (ssl.https has no async form). Running
    -- it inline here (during `initialized`) blocked startup until it returned or timed out.
    -- Defer it to a one-shot real-time timer so launch isn't gated on the network; it still
    -- runs once per session, just off the critical path.
    timer.start{
        type = timer.real,
        duration = 5,
        iterations = 1,
        callback = function()
            currentVersion = "v" .. this.getVersion()
            local body, code = https.request(
                'http://api.github.com/repos/jhaakma/ashfall/tags')

            if code == 200 then
                local tags = json.decode(body)
                latestVersion = tags and tags[1] and tags[1].name
                if latestVersion and latestVersion ~= currentVersion then
                    timer.frame.delayOneFrame(showUpdateMessageBox)
                end
            end
        end,
    }
end

return this