local RxTx = require("device/RxTx")
local Stream = require("Stream")

local Worker = {}
Worker.__index = Worker

function Worker.New()
    local s = {}
    local rx = library.getLinkByClass("ReceiverUnit")
    local stream ---@type Stream

    if not rx then
        system.print("No receiver")
    end

    local tx = library.getLinkByClass("EmitterUnit")

    if not tx then
        system.print("No emitter")
    end

    local screen = library.getLinkByClass("ScreenUnit")

    if not screen then
        system.print("No screen")
    end

    if not (rx and tx and screen) then
        unit.exit()
    end

    screen.activate()

    local rxtx = RxTx.New(tx, rx, "fubar", false)

    function s.OnData(data)
        screen.setCenteredText(data)
        stream.Write("from screen")
    end

    function s.OnTimeout(timeout, stream)
        if timeout then
            screen.setCenteredText("Timed out!")
        end
    end

    function s.RegisterStream(stream)

    end

    function s.Tick()
        stream.Tick()
    end

    stream = Stream.New(rxtx, s, 1)

    return setmetatable(s, Worker)
end

local worker = Worker.New()

system:onEvent("onUpdate", function()
    worker.Tick()
end)
