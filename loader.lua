local HttpService = game:GetService("HttpService")

local scripts = {
    [4777817887] = "https://raw.githubusercontent.com/azurion-dev/Azure/refs/heads/main/games/blade-ball/azure.lua"
}

local url = scripts[game.GameId]

if not url then
    warn("Universe ID não configurado:", game.GameId)
    return
end

local success, result = pcall(function()
    return game:HttpGet(url)
end)

if not success then
    warn("Erro ao buscar script:", result)
    return
end

local loader, err = loadstring(result)

if not loader then
    warn("Erro ao compilar script:", err)
    return
end

loader()
