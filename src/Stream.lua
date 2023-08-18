local _ = require("serializer")
local byte = string.byte
local concat = table.concat

---@module "interface.Device"

---@alias CommQueue { queue:string[], waitingForReply:boolean, seq:integer }
---@alias ScreenLink {setScriptInput:fun(string), clearScriptOutput:fun(), getScriptOutput:fun():string}
---@alias Renderer {setOutput:fun(string), getInput:fun():string}

---@class Stream
---@field New fun(device:Device, parent:DataReceiver, timeout:number):Stream
---@field Tick fun()
---@field Write fun(data:table|string)
---@field WaitingToSend fun():boolean

--[[
    Data format:
    #new_message|checksum|remaining_chunks|seq|cmd|payload

    Where:
    - new_message is 0 or 1 where 0 means continuation of a message, and 1 means a new message.
    - checksum is HEX representation of the XOR checksum of the data
    - remaining_chunks is an integer indicating how many chunks remains to complete the message. 0 means the last chuck.
    - seq is a single digit seqence number, used to ensure we don't read the same data twice. It wraps around at 9.
    - cmd is a two digit integer indicating what to do with the data
    - payload is the actual payload, if any
]]
local HEADER_SIZE = 1 -- #
    + 1               -- new_message
    + 1               -- |
    + 2               -- checksum
    + 1               -- |
    + 3               -- remaining_chucks
    + 1               -- |
    + 1               -- seq
    + 1               -- |
    + 2               -- cmd
    + 1               -- |

local BLOCK_HEADER_FORMAT = "#%0.1d|%0.2x|%0.3d|%0.1d|%0.2d|%s"
local BLOCK_HEADER_PATTERN = "^#(%d)|(%x%x)|(%d+)|(%d)|(%d+)|(.*)$"

---@enum StreamCommand
local Command = {
    Reset = 0,
    Poll = 1,
    Ack = 2,
    Data = 3,
}

---Represents a stream between two entities.
local Stream = {}
Stream.__index = Stream

---Create a new Stream
---@param device Device
---@param parent DataReceiver
---@param timeout number The amount of time to wait for a reply before considering the connection broken.
---@return Stream
function Stream.New(device, parent, timeout)
    local s = {}
    local DATA_SIZE = device.BlockSize() - HEADER_SIZE -- Game allows only a certain amount of bytes in buffers

    ---@diagnostic disable-next-line: undefined-global
    local getTime = getTime or system.getUtcTime

    device.Clear()

    local input = { queue = {}, waitingForReply = false, seq = -1, payloadChecksum = 0 }
    local output = { queue = {}, waitingForReply = false, seq = 0 }
    local lastReceived = getTime()

    ---@param data string
    ---@return string # Two character HEX value
    local function xor(data)
        local x = 0
        for i = 1, data:len() do
            x = x ~ byte(data, i)
        end

        return x
    end

    ---Assembles the package
    ---@param payload string
    local function assemblePackage(payload)
        input.queue[#input.queue + 1] = payload
    end

    ---Completes a transmission
    ---@param remaining number
    local function completeTransmission(remaining)
        if remaining == 0 then
            local complete = concat(input.queue)

            if xor(complete) == input.payloadChecksum then
                local deserialized = deserialize(complete)
                parent.OnData(deserialized)
            end

            -- Last part, begin new data
            input.queue = {}
        end
    end

    local function sameInput(seq)
        if seq == input.seq then
            return true
        end

        input.seq = seq
        return false
    end

    ---Creates a block
    ---@param newMessage boolean
    ---@param blockCount integer
    ---@param commQueue CommQueue
    ---@param cmd StreamCommand
    ---@param payload string?
    ---@return string
    local function createBlock(newMessage, blockCount, commQueue, cmd, payload, checksum)
        checksum = checksum or 0

        commQueue.seq = (commQueue.seq + 1)
        if commQueue.seq > 9 then
            commQueue.seq = 0
        end

        payload = payload or ""
        local b = string.format(BLOCK_HEADER_FORMAT, (newMessage and 1 or 0), checksum, blockCount, commQueue.seq, cmd,
            payload)

        return b
    end

    ---Reads incoming data
    ---@return boolean #New message
    ---@return StreamCommand|nil #Command
    ---@return number #Packet chunks remaning
    ---@return string #Payload
    ---@return integer #Checksum
    local function readData()
        local r = device.Read()

        local new, checksum, remaining, seq, cmd, payload = r:match(BLOCK_HEADER_PATTERN)

        payload = payload or ""
        local validPacket = remaining and cmd and new and checksum
        if validPacket then
            cmd = tonumber(cmd)
            new = tonumber(new)
            remaining = tonumber(remaining)
            checksum = tonumber("0x" .. checksum)
            validPacket = cmd and remaining and new and checksum
        end

        if not validPacket then
            return true, nil, 0, "", 0
        end

        -- Since we can't clear the input when running in RenderScript, we have to rely on the sequence number to prevent duplicate data.
        if sameInput(seq) then
            return true, nil, 0, "", 0
        end

        return new == 1, cmd, remaining, payload, checksum
    end

    local function resetQueues()
        output.queue = {}
        output.waitingForReply = false
        input.queue = {}
        input.waitingForReply = false
    end

    ---Call this function once every frame (i.e. in Update)
    function s.Tick()
        local new, cmd, remaining, payload, checksum = readData()

        -- Did we get any input?
        if cmd then
            if new then
                input.payloadChecksum = checksum
            end

            parent.OnTimeout(false, s)
            lastReceived = getTime()

            if new then
                input.queue = {}
            end

            if device.IsController() then
                if cmd == Command.Data then
                    assemblePackage(payload)
                    completeTransmission(remaining)
                end
                -- No need to handle ACK, it's just a trigger to move on.
                output.waitingForReply = false
            else
                local sendAck = false

                if cmd == Command.Poll or cmd == Command.Data then
                    if cmd == Command.Data then
                        assemblePackage(payload)
                        completeTransmission(remaining)
                    end

                    -- Send either ACK or actual data as a reply
                    if #output.queue > 0 then
                        device.Send(table.remove(output.queue, 1))
                    else
                        sendAck = true
                    end
                elseif cmd == Command.Reset then
                    resetQueues()
                    sendAck = true
                end

                if sendAck then
                    device.Send(createBlock(true, 0, output, Command.Ack))
                end
            end
        end

        if getTime() - lastReceived >= timeout then
            parent.OnTimeout(true, s)
            input.payloadChecksum = 0
            lastReceived = getTime() -- Reset to trigger again
            resetQueues()
        end

        if device.IsController() and not output.waitingForReply then
            if #output.queue == 0 then
                device.Send(createBlock(true, 0, output, Command.Poll))
            else
                device.Send(table.remove(output.queue, 1))
            end
            output.waitingForReply = true
        end
    end

    ---Write the data to the stream
    ---@param dataToSend table|string
    function s.Write(dataToSend)
        local data = serialize(dataToSend) ---@type string
        local checksum = xor(data)
        local blockCount = math.ceil(data:len() / DATA_SIZE)

        if blockCount > 999 then
            error("Too large data")
        end

        local new = true

        while data:len() > 0 do
            blockCount = blockCount - 1
            local part = data:sub(1, DATA_SIZE)
            data = data:sub(DATA_SIZE + 1)
            output.queue[#output.queue + 1] = createBlock(new, blockCount, output, Command.Data, part, checksum)
            new = false
            checksum = 0
        end
    end

    ---Returns true if there is data waiting to be sent. Good for holding off additional write.
    ---@return boolean
    function s.WaitingToSend() return #output.queue > 0 end

    setmetatable(s, Stream)

    parent.RegisterStream(s)

    return s
end

return Stream
