local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

type CommandInfo = {
    Name: string,
    Description: string?,
    Callback: (...any) -> (),
    Arguments: {[string]: string | {string}}?
}

local OUT_ERROR_COLOR = Color3.fromRGB(255, 22, 0)
local OUT_WARN_COLOR = Color3.fromRGB(255, 199, 50)
local OUT_INFO_COLOR = Color3.fromRGB(198, 255, 244)

local CommandPrefix = ";"

local require do
    local oldRequire = require
    local SEPERATOR = "/"
    local EXTENSION = ".lua"
    local ORIGIN = string.format("https://raw.githubusercontent.com/%s/OuiOui/%s/cmds",
        "weeeeee8", -- user
        "main" -- branch
    )
    local cache = {}
    require = function(path: string | Instance): any
        if type(path) == "string" then
            if cache[path] then
                return cache[path]
            end
            local ok, content = pcall(game.HttpGet, game, ORIGIN..path..EXTENSION)
            if not ok then
                error(string.format("Unable to fetch request to (%s)", path..EXTENSION), 2)
            else
                local _path = string.split(path, SEPERATOR)
                local name = _path[#_path]:sub(1, #_path[#_path]-EXTENSION)
                local src = loadstring(content, name)
                src = src()
                cache[path] = src
                return src
            end
        elseif typeof(path) == "Instance" then
            return oldRequire(path)
        else
            error("Invalid type of import, expect string or Instance, got " .. typeof(path), 2)
        end
    end

    getgenv().require = require
end

local function sendOutMessageToChat(text: string, color: Color3?, textSize: number?)
    assert(#text > 0, "Argument 1 must be a non-empty string")
    local config = {
        Text = text,
        Color = color or OUT_INFO_COLOR,
        Font = Enum.Font.SourceSansSemibold,
        TextSize = textSize or 18,
    }
    StarterGui:SetCore('ChatMakeSystemMessage', config)
end
getgenv().MakeChatSystemMessage = {
    Out = sendOutMessageToChat,
    Colors = {OUT_ERROR_COLOR, OUT_WARN_COLOR, OUT_INFO_COLOR}
}


local ArgumentParser = {} do
    local OPTIONAL = "opt"
    local PLAYER_TYPE = "plr"

    function ArgumentParser.new(args: {[string]: string | {string}})
        local types = {}
        for _, k in next, args do
            table.insert(types, k)
        end
        return setmetatable({args = args, types = types})
    end

    function ArgumentParser:Validate(out: any, index: number)
        local type = type(out)
        if self.types[index] == OPTIONAL then
            return true
        elseif (type == "number" or type == "boolean") then
            return type == self.types[index], ("Invalid type, expected %s, got %s"):format(self.types[index], type)
        elseif type == "string" then
            if self.types[index] == PLAYER_TYPE then
                return true, "Player"
            end
            return true
        end
    end
end

local Command = {} do
    local ParsedCommand = {}
    function ParsedCommand.new(command: {}, args: {string}, callback: (...any) -> ())
        return setmetatable({
            Command = command,
            Arguments = args,
            Callback = callback,
        })
    end

    function ParsedCommand:Parse()
        local newArgs = {}
        local oldArgs = self.Arguments
        for i = 1, #oldArgs do
            local arg = oldArgs[i]
            local out = select(2, pcall(HttpService.JSONDecode, HttpService, arg)) or tonumber(arg) or tostring(arg)
            if self.Command.Parser then
                local ok, typeOrErr = self.Command.Parser:Validate(out, i)
                if ok then
                    if typeOrErr == "Player" then
                        local player = Players:FindFirstChild(arg)
                        if not player then
                            return false, "Could not find the player " .. arg
                        end
                        out = player
                    end
                else
                    return false, typeOrErr
                end
            end
            newArgs[i] = out
        end
        self.Arguments = newArgs
        return true
    end

    function ParsedCommand:Run()
        local ok, errOrOut = pcall(self.Callback, table.unpack(self.Arguments))
        if ok then
            return true, errOrOut or "Command successfully ran."
        else
            return false, errOrOut
        end
    end

    function Command.new(name: string, desc: string?, callback: (...any) -> (), autotCompletePriority: number, args: {[string]: string | {string}}?)
        local self = {
            Name = name,
            Description = desc,
            Callback = callback,
            Priority = autotCompletePriority,
            Parser = if args then ArgumentParser.new(args) else nil,
        }

        return setmetatable(self, {__index = Command})
    end

    function Command:FromArguments(args: {string})
        return ParsedCommand.new(self, args, self.Callback)
    end
end

local CommandStorageAPI = {} do
    local COMMANDS = {}
    function CommandStorageAPI.PostCommand(commandInfo: CommandInfo)
        print(unpack(commandInfo))
        COMMANDS[commandInfo.Name] = Command.new(commandInfo.Name, commandInfo.Description, commandInfo.Callback, commandInfo.Priority, commandInfo.ArgumentTypes)
    end

    function CommandStorageAPI.RemoveCommand(name: string)
        if COMMANDS[name] then
            COMMANDS[name]:Destroy()
            COMMANDS[name] = nil
        end
    end
    function CommandStorageAPI.GetCommand(name: string)
        return COMMANDS[name]
    end
    function CommandStorageAPI.GetCommands()
        return COMMANDS
    end
    getgenv().CommandsAPIService = CommandStorageAPI
end

local Dispatcher = {} do
    local SEPERATOR = ","
    function Dispatcher:Evaluate(text: string)
        if #text >= 100_000 then
            return false, "Input is too long"
        end

        local arguments = string.split(text, SEPERATOR)
        local commandName = table.remove(arguments, 1)
        local commandObject = CommandStorageAPI.GetCommand(commandName)
        if commandObject then
            local command = commandObject:FromArguments(arguments)
            local success, errorText = command:Parse()
            if success then
                return command
            else
                return false, errorText
            end
        else
            return false, string.format("%s is not a valid command, please use the help command to see all built-in commmands.", commandName)
        end
    end

    function Dispatcher:Run(...)
        local args = table.pack(...)
        local text = args[1]
        for i = 2, args.n do
            text = text .. SEPERATOR .. tostring(args[i])
        end
        local command, errText = self:Evaluate(text)
        if not command then
            sendOutMessageToChat(errText, OUT_ERROR_COLOR)
            return
        end

        local ok, out = command:Run()
        sendOutMessageToChat(out, if ok then OUT_WARN_COLOR else OUT_ERROR_COLOR)
    end
end

local Player = Players.LocalPlayer
local function hasPrefix(text: string)
    return text:sub(1, 1) == CommandPrefix and text:sub(2, 2) ~= CommandPrefix
end

local function onPlayerChatted(message: string)
    if message:sub(1, 1) == "/" then
        local contents = string.split(message, " ")
        local _ = table.remove(contents, 1)
        if hasPrefix(contents[1]) then
            contents[1] = contents[1]:sub(2, #contents[1]) -- remove the prefix
            Dispatcher:Run(table.unpack(contents))
        end
    elseif hasPrefix(message) then
        message = message:sub(2, #message)
        local contents = string.split(message, " ")
        Dispatcher:Run(table.unpack(contents))
    end
end
Player.Chatted:Connect(onPlayerChatted)

-- import built in commands
require('/builtIn')