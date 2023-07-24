---@class RenderScriptDevice
---@field Send fun(data:string)
---@field Read fun():string
---@field Clear fun()
---@field IsController fun():boolean
---@field BlockSize fun():integer
---@field New fun(screenLink:table):Device

local RenderScriptDevice = {}
RenderScriptDevice.__index = RenderScriptDevice

---Creates a new screen device
---@return Device
function RenderScriptDevice.New()
    local s = {}

    function s.Send(data)
        ---@diagnostic disable-next-line: undefined-global
        setOutput(data)
    end

    ---@return string
    function s.Read()
        ---@diagnostic disable-next-line: undefined-global
        return getInput()
    end

    function s.Clear()

    end

    ---@return boolean
    function s.IsController()
        return false
    end

    function s.BlockSize()
        return 1024
    end

    return setmetatable(s, RenderScriptDevice)
end

return RenderScriptDevice
