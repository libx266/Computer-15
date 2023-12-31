local Morse = require "Modules.Morse"
local config = require "config"
Morse.ChangePreset(config.MorsePreset)
require "const"
local Hash = require "Modules.Hash"

local function split(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end


local function receive()
    local message = Morse.Receive(config.ReceiveTimeout, config.ReceiveSide)
    if #message > 1 then
        local message_partial = split(message, " ")
        if #message_partial > 1 then
            local target_address = message_partial[1]
            local sender_address = message_partial[2]

            if target_address == config.LocalAddress and sender_address == MP_CODE_RECEIVED then
                return {Status = MP_STATUS_TRANSMITTED_ACCEPT}
            end
            
            if #message_partial == 2 then
                return {Status = MP_STATUS_INVALID, Data = message}
            end

            local received_hash = message_partial[3]

            table.remove(message_partial, 1)
            table.remove(message_partial, 1)
            table.remove(message_partial, 1)

            local data = table.concat(message_partial, " ")

            if #target_address ~= MP_SYSTEM_ADDRESS_LENGTH or #sender_address ~= MP_SYSTEM_ADDRESS_LENGTH or #received_hash ~= MP_SYSTEM_HASH_LENGTH then
                return {Status = MP_STATUS_INVALID, Data = message }
            end

            if target_address == config.LocalAddress then
                local computed_hash = Hash(data)
                
                if computed_hash == received_hash then
                    return { Status = MP_STATUS_RECEIVED, Data = data, SenderAddress = sender_address}
                else
                    return {Status = MP_STATUS_TRANSMITTED_CORRUPT, Data = data, SenderAddress = sender_address, ReceivedHash = received_hash, ComputedHash = computed_hash}
                end
            else
                return { Status = MP_STATUS_ALIEN, Data = data, SenderAddress = sender_address, TargetAddress = target_address}
            end
        else
            return {Status = MP_STATUS_INVALID, Data = message}
        end
    else
        return {Status = MP_STATUS_EMPTY}
    end
end

local function transfer(address, message)
    
    for i = 0, config.ReceiveTimeout * 0.5, MIN_TIMEOUT do
        local signal = redstone.getInput(config.ReceiveSide)
        if signal then
            return MP_STATUS_TRANSMITTED_OVERLOAD
        end
        os.sleep(MIN_TIMEOUT)
    end

    if #address ~= MP_SYSTEM_ADDRESS_LENGTH then
        return MP_STATUS_INVALID
    end

    local hash = Hash(message)
    local msg = address.." "..config.LocalAddress.." "..hash.." "..message
    Morse.Transmit(msg, config.ReceiveSide)
    return MP_STATUS_TRANSMITTED
end

local function accepted_transfer(address, message)
    local status = transfer(address, message)
    if status == MP_STATUS_TRANSMITTED then
        os.sleep(config.ReceiveTimeout)
        local response = receive()
        print("get transfer response: "..textutils.serialize(response))
        if response.Status == MP_STATUS_TRANSMITTED_ACCEPT then
            return {Status = MP_STATUS_TRANSMITTED_ACCEPT, Response = response}
        elseif response.Status == MP_STATUS_EMPTY then
            return { Status = MP_STATUS_TRANSMITTED_TIMEOUT}
        else 
            return {Status = MP_STATUS_TRANSMITTED_DENY, Response = response}
        end
        
        return {Status = response.Status}
    end
    return {Status = status}
end

local function trust_fransfer(address, message, attempts)
    if attempts == nil then
        attempts = MP_SYSTEM_TRANSFER_ATTEMPTS
    end
    local obj = {
        Address = address,
        Data = message,
        Attempt = MP_SYSTEM_TRANSFER_ATTEMPTS - attempts + 1
    }
    print("transfer message: "..textutils.serialize(obj))
    local response = accepted_transfer(address, message)
    if response.Status ~= MP_STATUS_TRANSMITTED_ACCEPT and attempts > 1 then
        if response.Status == MP_STATUS_TRANSMITTED_OVERLOAD then
            print("line overloaded, waiting..")
            os.sleep(config.ReceiveTimeout * MP_SYSTEM_NETWORK_BUSY_TIMEOUT_SCALE)
        end
        return trust_fransfer(address, message, attempts - 1)
    end
    return response

end



return
{
    Receive = receive,

    Ping = function (address) 
        local response = trust_fransfer(address, MP_CODE_PING)
        return response.Status
    end,

    TransferTcp = function(address, message)
        return trust_fransfer(address, message)
    end,

    TransferUdp = function (address, message)
        return transfer(address, message)
    end,

    Listen = function (messages_handler)
        while not redstone.getInput(config.TerminateSide) do
            local message = receive()
            print("listen message: "..textutils.serialize(message))
            if message.Status == MP_STATUS_RECEIVED then
                Morse.Transmit(message.SenderAddress.." "..MP_CODE_RECEIVED, config.ReceiveSide)
            end
            messages_handler(message)
            os.sleep(config.ReceiveTimeout)
        end
    end
}