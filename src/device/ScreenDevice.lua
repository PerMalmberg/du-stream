---@module "Device"

---@class ScreenDevice
---@field Send fun(data:string)
---@field Read fun():string
---@field Clear fun()
---@field IsController fun():boolean
---@field BlockSize fun():integer
---@field New fun(screenLink:table):Device

local ScreenDevice = {}
ScreenDevice.__index = ScreenDevice

---Creates a new screen interface
---@param screenLink {getScriptOutput:stringf, clearScriptOutput:voidf, setScriptInput:fun(string)}
---@return Device
function ScreenDevice.New(screenLink)
    local s = {}

    ---@param data string
    function s.Send(data)
        screenLink.setScriptInput(data)
    end

    ---@return string
    function s.Read()
        local data = screenLink.getScriptOutput()
        screenLink.clearScriptOutput()
        return data
    end

    function s.Clear()
        screenLink.clearScriptOutput()
    end

    ---@return boolean
    function s.IsController()
        -- We're running on the controller when we have a link to a screen
        return true
    end

    function s.BlockSize()
        return 1024
    end

    return setmetatable(s, ScreenDevice)
end

return ScreenDevice
