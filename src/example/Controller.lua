local RxTx = require("device/RxTx")
local Stream = require("Stream")

local Controller = {}
Controller.__index = Controller

function Controller.New()
    local s = {}
    local rx = library.getLinkByClass("ReceiverUnit")
    local stream ---@type Stream
    local count = 0

    if not rx then
        system.print("No receiver")
    end

    local tx = library.getLinkByClass("EmitterUnit")

    if not tx then
        system.print("No emitter")
    end

    if not (rx and tx) then
        unit.exit()
    end

    local rxtx = RxTx.New(tx, rx, "fubar", true)

    function s.OnData(data)
        system.print("Received from worker: " .. data)
    end

    function s.OnTimeout(timeout, stream)
        if timeout then
            system.print("Timed out!")
        end
    end

    function s.RegisterStream(stream)

    end

    function s.Tick()
        if not stream.WaitingToSend() then
            stream.Write(tostring(count))
            count = count + 1
        end
        stream.Tick()
    end

    stream = Stream.New(rxtx, s, 1)

    return setmetatable(s, Controller)
end

local controller = Controller.New()

system:onEvent("onUpdate", function()
    controller.Tick()
end)
