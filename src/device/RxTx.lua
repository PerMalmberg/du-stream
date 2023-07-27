---@alias onReceiveFunc fun(_:table, channel:string, message:string)
---@alias EmitterLink {send:fun(channel:string, message:string), setChannelList:fun(table)}
---@alias ReceiverLink {setChannelList:fun(channels:channelList), onEvent:fun(_:table, event:string, f:onReceiveFunc)}

---@class RxTx
---@field Send fun(data:string)
---@field Read fun():string
---@field Clear fun()
---@field SetChannel fun(string)
---@field BlockSize integer
---@field New fun(emitter:EmitterLink, receiver:ReceiverLink, channel:string, isController:boolean):Device

---@alias channelList string[]

local RxTx = {}
RxTx.__index = RxTx

---Create a transmit/receive interface
---@param emitter EmitterLink The emitter link
---@param receiver ReceiverLink The receiver link
---@param channel string The channel to communicate on
---@param isController boolean If true, this device is considered the controller.
---@return Device
function RxTx.New(emitter, receiver, channel, isController)
    local s = {}

    -- Setup channels for two-way communication
    local sendChannel = channel .. (isController and "-ctrl" or "-worker")
    local recChannel = channel .. (isController and "-worker" or "-ctrl")

    local inQueue = {} ---@type string[]

    receiver.setChannelList({ recChannel })

    ---@diagnostic disable-next-line: undefined-field
    receiver:onEvent("onReceived", function(_, chan, message)
        -- Restore quotation marks
        message = message:gsub("&#34;", "\"")
        inQueue[#inQueue + 1] = message
    end)

    ---@param data string
    function s.Send(data)
        -- Can't send quotation marks through the emitter so replace it with HTML code for it.
        data = data:gsub("\"", "&#34;")
        emitter.send(sendChannel, data)
    end

    ---@return string
    function s.Read()
        return table.remove(inQueue, 1) or ""
    end

    function s.Clear()
        -- NOP
    end

    ---@return boolean
    function s.IsController()
        return isController
    end

    function s.BlockSize()
        return 512
    end

    return setmetatable(s, RxTx)
end

return RxTx
