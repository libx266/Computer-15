local Sr = require "Bot.Repositories.SettingsRepository"


local UrlHandler = function(url) 
    return string.gsub(url, "%s", "%%20")
end

local HttpGet = function(url)
    url = UrlHandler(url)
    local resp = http.get(url)
    return resp.readAll()
end

local token = Sr.GetToken()
local endpoint = "https://api.telegram.org/bot"..token.."/"


return 
{
    SendMessage = function(telegram_chat_id, text)
        return HttpGet(endpoint.."sendMessage?chat_id="..telegram_chat_id.."&text="..text)
    end,
    GetUpdates = function(offset_id)
        return HttpGet(endpoint.."getUpdates?offset="..offset_id)
    end
}




