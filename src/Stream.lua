local _ = require("serializer")
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
    #new_message|remaining_chunks|seq|cmd|payload

    Where:
    - new_message is 0 or 1 where 0 means continuation of a message, and 1 means a new message.
    - remaining_chunks is an integer indicating how many chunks remains to complete the message. 0 means the last chuck.
    - seq is a single digit seqence number, used to ensure we don't read the same data twice. It wraps around at 9.
    - cmd is a two digit integer indicating what to do with the data
    - payload is the actual payload, if any
]]
local HEADER_SIZE = 1 -- #
    + 1               -- new_message
    + 1               -- |
    + 3               -- remaining_chucks
    + 1               -- |
    + 1               -- seq
    + 1               -- |
    + 2               -- cmd
    + 1               -- |

local BLOCK_HEADER_FORMAT = "#%0.1d|%0.3d|%0.1d|%0.2d|%s"
local BLOCK_HEADER_PATTERN = "^#(%d)|(%d+)|(%d)|(%d+)|(.*)$"

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

    local input = { queue = {}, waitingForReply = false, seq = -1, expectedChunks = -1 }
    local output = { queue = {}, waitingForReply = false, seq = 0 }
    local lastReceived = getTime()

    ---Assembles the package
    ---@param payload string
    local function assemblePackage(payload)
        input.queue[#input.queue + 1] = payload
    end

    ---Completes a transmission
    ---@param remaining number
    local function completeTransmission(remaining)
        if remaining == 0 then
            if input.expectedChunks == #input.queue then
                local complete = concat(input.queue)

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
    local function createBlock(newMessage, blockCount, commQueue, cmd, payload)
        commQueue.seq = (commQueue.seq + 1)
        if commQueue.seq > 9 then
            commQueue.seq = 0
        end

        payload = payload or ""
        local b = string.format(BLOCK_HEADER_FORMAT, (newMessage and 1 or 0), blockCount, commQueue.seq, cmd,
            payload)
        return b
    end

    ---Reads incoming data
    ---@return boolean #New message
    ---@return StreamCommand|nil #Command
    ---@return number #Packet chunks remaning
    ---@return string #Payload
    local function readData()
        local r = device.Read()

        local new, remanining, seq, cmd, payload = r:match(BLOCK_HEADER_PATTERN)

        payload = payload or ""
        local validPacket = remanining and cmd and new
        if validPacket then
            cmd = tonumber(cmd)
            remanining = tonumber(remanining) or 0
            new = tonumber(new)
            validPacket = cmd and remanining and new
        end

        if not validPacket then
            return true, nil, 0, ""
        end

        -- Since we can't clear the input when running in RenderScript, we have to rely on the sequence number to prevent duplicate data.
        if sameInput(seq) then
            return true, nil, 0, ""
        end

        return new == 1, cmd, remanining, payload
    end

    local function resetQueues()
        output.queue = {}
        output.waitingForReply = false
        input.queue = {}
        input.waitingForReply = false
    end

    ---Call this function once every frame (i.e. in Update)
    function s.Tick()
        local new, cmd, remaining, payload = readData()

        -- Did we get any input?
        if cmd then
            if new then
                -- Depending on timing between the controller and worker, there might be data to read from is the last part of a message
                -- but we don't have the previous parts. Deserializing only the last part (which has remaining = 0 and thus passes the checks) results in an error.
                -- As such we keep track of the number of chucks each message consists of and ensure that we only process the complete message.
                input.expectedChunks = remaining + 1
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
            input.expectedChunks = -1
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
        local blockCount = math.ceil(data:len() / DATA_SIZE)

        if blockCount > 999 then
            error("Too large data")
        end

        local new = true

        while data:len() > 0 do
            blockCount = blockCount - 1
            local part = data:sub(1, DATA_SIZE)
            data = data:sub(DATA_SIZE + 1)
            output.queue[#output.queue + 1] = createBlock(new, blockCount, output, Command.Data, part)
            new = false
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
