local _ = require("serializer")

---@module "interface.Device"

---@alias CommQueue { queue:string[], waitingForReply:boolean, seq:integer }
---@alias ScreenLink {setScriptInput:fun(string), clearScriptOutput:fun(), getScriptOutput:fun():string}
---@alias Renderer {setOutput:fun(string), getInput:fun():string}
---@alias StreamData {output:CommQueue, input:CommQueue, lastReceived:number}

---@class Stream
---@field New fun(device:Device, parent:DataReceiver, timeout:number):Stream
---@field Tick fun()
---@field Write fun(data:table|string)
---@field WaitingToSend fun():boolean

--[[
    Data format:
    #remaining_chucks|seq|cmd|payload

    Where:
    - remaining_chunks is a 2-digit integer indicating how many chunks remains to complete the message. 0 means the last chuck.
    - seq is a single digit seqence number, used to ensure we don't read the same data twice. It wraps around at 9.
    - cmd is a two digit integer indicating what to do with the data
    - payload is the actual payload, if any
]]
local headerSize = 1 -- #
    + 2              -- remaining_chucks
    + 1              -- |
    + 1              -- seq
    + 1              -- |
    + 2              -- cmd
    + 1              -- |

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
    local blockSize = device.BlockSize() - headerSize -- Game allows max 1024 bytes in buffers

    ---@diagnostic disable-next-line: undefined-global
    local getTime = getTime or system.getUtcTime

    device.Clear()

    ---@type StreamData
    local streamData = {
        input = { queue = {}, waitingForReply = false, seq = 0 },
        output = { queue = {}, waitingForReply = false, seq = 0 },
        lastReceived = getTime()
    }

    local input = streamData.input
    local output = streamData.output

    ---Assembles the package
    ---@param payload string
    local function assemblePackage(payload)
        local queue = input.queue

        if #queue == 0 then
            table.insert(queue, "")
        end
        queue[#queue] = queue[#queue] .. payload
    end

    ---Completes a transmission
    ---@param count number
    local function completeTransmission(count)
        if count == 0 then
            local queue = input.queue

            local deserialized = deserialize(queue[#queue])

            parent.OnData(deserialized)
            -- Last part, begin new data
            queue[1] = ""
        end
    end

    local function sameInput(commQueue, seq)
        if seq == commQueue.seq then
            return true
        end

        commQueue.seq = seq
        return false
    end

    ---Creates a block
    ---@param blockCount integer
    ---@param commQueue CommQueue
    ---@param cmd StreamCommand
    ---@param payload string?
    ---@return string
    local function createBlock(blockCount, commQueue, cmd, payload)
        commQueue.seq = (commQueue.seq + 1)
        if commQueue.seq > 9 then
            commQueue.seq = 0
        end

        payload = payload or ""
        local b = string.format("#%0.2d|%0.1d|%0.2d|%s", blockCount, commQueue.seq, cmd, payload)
        return b
    end

    ---Reads incoming data
    ---@return StreamCommand|nil #Command
    ---@return number #Packet count
    ---@return string #Payload
    local function readData()
        local r = device.Read()

        local count, seq, cmd, payload = r:match("^#(%d+)|(%d)|(%d+)|(.*)$")

        payload = payload or ""
        local validPacket = count and cmd
        if validPacket then
            cmd = tonumber(cmd)
            count = tonumber(count) or 0
            validPacket = validPacket and cmd and count
        end

        if not validPacket then
            return nil, 0, ""
        end

        -- Since we can't clear the input when running in RenderScript, we have to rely on the sequence number to prevent duplicate data.
        if sameInput(input, seq) then
            return nil, 0, ""
        end

        return cmd, count, payload
    end

    ---Call this function once every frame (i.e. in Update)
    function s.Tick()
        local cmd, count, payload = readData()

        -- Did we get any input?
        if cmd then
            parent.OnTimeout(false, s)
            streamData.lastReceived = getTime()

            if device.IsController() then
                if cmd == Command.Data then
                    assemblePackage(payload)
                    completeTransmission(count)
                end
                -- No need to handle ACK, it's just a trigger to move on.
                output.waitingForReply = false
            else
                local sendAck = false

                if cmd == Command.Poll or cmd == Command.Data then
                    if cmd == Command.Data then
                        assemblePackage(payload)
                        completeTransmission(count)
                    end

                    -- Send either ACK or actual data as a reply
                    if #output.queue > 0 then
                        device.Send(table.remove(output.queue, 1))
                    else
                        sendAck = true
                    end
                elseif cmd == Command.Reset then
                    output.queue = {}
                    output.waitingForReply = false
                    input.queue = {}
                    input.waitingForReply = false
                    sendAck = true
                end

                if sendAck then
                    device.Send(createBlock(0, output, Command.Ack))
                end
            end
        end

        if getTime() - streamData.lastReceived >= timeout then
            parent.OnTimeout(true, s)
            streamData.lastReceived = getTime() -- Reset to trigger again
            output.queue = {}
            output.waitingForReply = false
        end

        if device.IsController() and not output.waitingForReply then
            if #output.queue == 0 then
                device.Send(createBlock(0, output, Command.Poll))
                output.waitingForReply = true
            else
                device.Send(table.remove(output.queue, 1))
                output.waitingForReply = true
            end
        end
    end

    ---Write the data to the stream
    ---@param dataToSend table|string
    function s.Write(dataToSend)
        local data = serialize(dataToSend)
        local blockCount = math.ceil(data:len() / blockSize) - 1

        while data:len() > blockSize - headerSize do
            local part = data:sub(1, blockSize)
            data = data:sub(blockSize + 1)
            table.insert(output.queue, createBlock(blockCount, output, Command.Data, part))
            blockCount = blockCount - 1
        end

        if data:len() > 0 then
            table.insert(output.queue, createBlock(blockCount, output, Command.Data, data))
        end
    end

    ---Returns true if there is data waiting to be sent. Good for holding off additional write.
    ---@return boolean
    function s.WaitingToSend() return #output.queue > 0 end

    return setmetatable(s, Stream)
end

return Stream
