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

    function s.BlockSize()
        return 1024
    end

    return setmetatable(s, FakeRenderScriptDevice)
end

local DummyReceiver = {}
DummyReceiver.__index = DummyReceiver

function DummyReceiver.New()
    local s = {
        isTimedOut = false,
        data = "",
        echo = false
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

    function s.EnableEcho()
        s.echo = true
    end

    function s.RegisterStream(stream)

    end

    return setmetatable(s, DummyReceiver)
end

local function makeObjects(controlTimeOut, workerTimeout)
    controlTimeOut = controlTimeOut or 1
    workerTimeout = workerTimeout or 1

    -- Controller side
    local fakeScreen = FakeScreen.New()
    local screenDevice = ScreenDevice.New(fakeScreen)

    local controller = DummyReceiver.New()
    local controllerStream = Stream.New(screenDevice, controller, controlTimeOut)

    -- Screen side
    local worker = DummyReceiver.New()
    local screenStream = Stream.New(FakeRenderScriptDevice.New(), worker, workerTimeout)

    return controller, controllerStream, worker, screenStream, function(onlyController)
        controllerStream.Tick()
        if not onlyController then
            screenStream.Tick()
        end
    end
end

local function generateData(len)
    -- Making these functions local spees things up by ~100 times
    local char = string.char
    local rnd = math.random
    local data = {}
    for _ = 1, len do
        data[#data + 1] = char(rnd(32, 126))
    end
    return table.concat(data)
end

describe("Stream", function()
    it("Can send data to screen", function()
        local controller, controllerStream, worker, screenStream, tick = makeObjects()
        controllerStream.Write("1234567890")
        for i = 1, 5, 1 do
            controllerStream.Tick()
            screenStream.Tick()
        end

        assert.are_equal("1234567890", worker.Data())
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)

    it("Can receive data from screen", function()
        local controller, controllerStream, worker, screenStream, tick = makeObjects()

        screenStream.Write("1234567890")
        for i = 1, 5, 1 do
            tick()
        end

        assert.are_equal("1234567890", controller.Data())
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)

    it("Can send and receive data from screen with latency from the screen, reversed update order", function()
        local controller, controllerStream, worker, screenStream, tick = makeObjects()

        local msg =
        [[||||a much longer message than just some simple text with some digits 1233131212 and funny characters in it | 432422| # 222.
                    Lets see if it works? We can surely hope, can't we? What if we add some more funny characters to make it even longer?
                    )/%(&(%&¤&#¤&&¤/%&(¤(&/¤()&/(%%/((&/¤%/%#/#¤¤&¤&¤)))))))|||||| and then even more keyboard bashing. nghengwtangwnihe wnergeioger
                    gerjlgeraeragegerghearhgrwahgöoegjeargjnelaöighjnaewögerawg  geg ergeag jera jgaerj öae gäae gäaerj gäpear ägajeijg re.

        Maybe we should use a fuzzer?

        Meh, lets mach the keyboard more to reach the blocksize for screens.

        klgealkgwrngweroäg eöl gmöl ty34Y q455&YT 34 T¤#%q 6¤q6T"#¤Ty 3Y54qU576()/&43(57Q#¤3Qyt34¤Y35YU564wUI(%//&W¤%74#¤t&%#6y¤%Q q455
        Y¤%6456¤%64%6 ¤%7 W¤764W 4W% 4W7¤7 ¤w/ ¤7¤(&/¤()&¤/)8790=)=&((%#7¤74%ÅÄÖ ¤Y QY&#y#Q _;(&¤47) ><f>F<f>fsfsFGAgaGaGaghERAy¤%724&/24/5(75638/45w7¤8#(6ERurherh¤%&76#%67(74684(537#¤%&&¤&&##%!%#¤%?=)(/&%¤#¤%&%¤¤
        `?=)(/&%¤#¤%&/(()?=)(/&"#¤/)&(%/¤&#"|||||||]]

        controllerStream.Write(msg)
        for i = 1, 500, 1 do
            -- Tick screen every third simulate asynchronicity
            tick(i % 3 ~= 0)
        end

        assert.are_equal(msg, worker.Data())
        assert.are_equal("", controller.Data())

        screenStream.Write(msg)
        for i = 1, 500, 1 do
            -- Tick screen every third simulate asynchronicity
            tick(i % 3 ~= 0)
        end

        assert.are_equal(msg, controller.Data())
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)

    it("Can handle a timeout", function()
        local controller, controllerStream, worker, screenStream, tick = makeObjects(0.5, 0.5)

        local msg =
        "a much longer message than just some simple text with some digits 1233131212 and funny characters in it | 432422| # 222. Lets see if it works."


        local start = system.getUtcTime()

        -- No timeout while just sending polls
        while system.getUtcTime() - start < 1 do
            tick()
        end

        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())

        -- No timeout when sending data
        start = system.getUtcTime()
        while system.getUtcTime() - start < 1 do
            controllerStream.Write(msg)
            tick()
        end

        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())

        -- Timeout when not receiveing replies
        start = system.getUtcTime()
        while system.getUtcTime() - start < 1 do
            tick(true)
        end

        assert.is_true(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())

        -- Resume comms
        start = system.getUtcTime()

        while system.getUtcTime() - start < 1 do
            tick()
        end

        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)

    it("Can send structured data", function()
        local controller, controllerStream, worker, screenStream, tick = makeObjects(0.5, 0.5)

        controllerStream.Write({ abc = { def = { v = 123 } } })
        screenStream.Write({ foo = "bar" })
        for i = 1, 5, 1 do
            tick()
        end

        assert.are_equal("bar", controller.Data().foo)
        assert.are_equal(123, worker.Data().abc.def.v)
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
    end)

    local function testLength(len)
        print("Testing length " .. len)
        local controller, controllerStream, worker, screenStream, tick = makeObjects()
        local data = generateData(len)
        controllerStream.Write(data)
        repeat
            tick()
            local waiting = controllerStream.WaitingToSend() or screenStream.WaitingToSend()
        until not waiting

        assert.are_equal(data, worker.Data())
        assert.is_false(controller.IsTimedOut())
        assert.is_false(worker.IsTimedOut())
        print("...pass")
    end

    it("Can send alot of data of lengths", function()
        math.randomseed(42) -- Make it repeatable
        for len = 1, 1000 do
            testLength(len)
        end

        for len = 1000, 100000, 1000 do
            testLength(len)
        end
    end)

    it("Fails on too large data", function()
        assert.has_error(function()
            testLength(1024 * 1000)
        end, "Too large data")
    end)
end)
