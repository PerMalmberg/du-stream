local env = require("environment")
env.Prepare()

local Stream = require("Stream")
local ScreenDevice = require("device/ScreenDevice")

local toScreen = ""
local toController = ""

local FakeScreen = {}
FakeScreen.__index = FakeScreen

function FakeScreen.New()
    local s = {}

    function s.setScriptInput(inp)
        toScreen = inp
    end

    function s.getScriptOutput()
        return toController
    end

    function s.clearScriptOutput()
        toController = ""
    end

    return setmetatable(s, FakeScreen)
end

local FakeRenderScriptDevice = {}
FakeRenderScriptDevice.__index = FakeRenderScriptDevice

---Creates a new screen device
---@return Device
function FakeRenderScriptDevice.New()
    local s = {}

    function s.Send(data)
        toController = data
    end

    ---@return string
    function s.Read()
        return toScreen
    end

    function s.Clear()

    end

    ---@return boolean
    function s.IsController()
        return false
    end

    return setmetatable(s, FakeRenderScriptDevice)
end

local DummyReceiver = {}
DummyReceiver.__index = DummyReceiver

function DummyReceiver.New()
    local s = {
        isTimedOut = false,
        data = nil
    }

    function s.OnData(data)
        s.data = data
    end

    function s.OnTimeout(isTimedOut, stream)
        s.isTimedOut = isTimedOut
    end

    function s.IsTimedOut()
        return s.isTimedOut
    end

    ---@return any
    function s.Data()
        return s.data
    end

    return setmetatable(s, DummyReceiver)
end

describe("Stream", function()
    it("Can send data to screen", function()
        -- Controller side
        local fakeScreen = FakeScreen.New()
        local screenDevice = ScreenDevice.New(fakeScreen)

        local controller = DummyReceiver.New()
        local controllerStream = Stream.New(screenDevice, controller, 1)

        -- Screen side
        local worker = DummyReceiver.New()
        local screenStream = Stream.New(FakeRenderScriptDevice.New(), worker, 1)


        controllerStream.Write("1234567890")
        for i = 1, 5, 1 do
            controllerStream.Tick()
            screenStream.Tick()
        end

        assert.are_equal("1234567890", worker.Data())
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)
end)
