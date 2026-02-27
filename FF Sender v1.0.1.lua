script_author('stasyan')
script_name('FFSender')
script_version('1.1.0')
script_version_number(0)
script_description([[
Скрипт для выдачи оффлайн форм
Поддержка персональных токенов из INI файла
Автообновление через GitHub
]])

-- === НАЧАЛО БЛОКА АВТООБНОВЛЕНИЯ ===

-- Настройки (ЗАМЕНИТЕ НА СВОИ!)
local UPDATE_JSON_URL = "https://raw.githubusercontent.com/ВАШ_АККАУНТ/ВАШ_РЕПОЗИТОРИЙ/main/version.json"
local UPDATE_MANUAL_URL = "https://github.com/ВАШ_АККАУНТ/ВАШ_РЕПОЗИТОРИЙ/releases"

-- Функция автообновления
function checkForUpdates(json_url, prefix, manual_url)
    local dlstatus = require('moonloader').download_status
    local json_path = getWorkingDirectory() .. '\\' .. thisScript().name .. '-version.json'

    if doesFileExist(json_path) then
        os.remove(json_path)
    end

    downloadUrlToFile(json_url, json_path,
        function(id, status, p1, p2)
            if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                if doesFileExist(json_path) then
                    local file = io.open(json_path, 'r')
                    if file then
                        local content = file:read('*a')
                        file:close()
                        os.remove(json_path)

                        local success, data = pcall(function() return decodeJson(content) end)
                        if success and data and data.updateurl and data.latest then
                            if data.latest ~= thisScript().version then
                                lua_thread.create(function()
                                    local msgColor = -1
                                    sampAddChatMessage(prefix .. "Обнаружена новая версия (" .. data.latest .. "). Попытка обновления...", msgColor)
                                    wait(250)

                                    downloadUrlToFile(data.updateurl, thisScript().path,
                                        function(dlId, dlStatus, dlP1, dlP2)
                                            if dlStatus == dlstatus.STATUS_DOWNLOADINGDATA then
                                                print(string.format(prefix .. "Загружено %d из %d.", dlP1, dlP2))
                                            elseif dlStatus == dlstatus.STATUS_ENDDOWNLOADDATA then
                                                print(prefix .. "Загрузка завершена.")
                                                sampAddChatMessage(prefix .. "Обновление успешно! Скрипт будет перезагружен.", msgColor)
                                                lua_thread.create(function()
                                                    wait(500)
                                                    thisScript():reload()
                                                end)
                                            elseif dlStatus == dlstatus.STATUSEX_ENDDOWNLOAD then
                                                print(prefix .. "Файл обновления сохранен.")
                                            end
                                        end
                                    )
                                end)
                            else
                                print(prefix .. "У вас актуальная версия (" .. thisScript().version .. ").")
                            end
                        else
                            print(prefix .. "Ошибка чтения JSON. Проверьте файл обновления.")
                        end
                    end
                else
                    print(prefix .. "Не удалось загрузить файл с информацией об обновлении.")
                end
            elseif status == dlstatus.STATUSEX_QUEUE then
                print(prefix .. "Постановка в очередь на проверку обновлений...")
            elseif status == dlstatus.STATUSEX_LOADING then
                -- Можно ничего не делать
            elseif status == dlstatus.STATUSEX_TIMEOUT or status == dlstatus.STATUSEX_ABORTED then
                print(prefix .. "Ошибка подключения к серверу обновлений.")
                if manual_url then
                    print(prefix .. "Проверьте обновления вручную: " .. manual_url)
                end
            end
        end
    )
end
-- === КОНЕЦ БЛОКА АВТООБНОВЛЕНИЯ ===

local SERVER = "Faraway"

-- Подключаем библиотеки
local en = require("encoding")
local effil = require("effil")
local imgui = require("mimgui")
local sampev = require("samp.events")
local url = require 'socket.url'
local inicfg = require('inicfg')

en.default = 'CP1251'
local u8 = en.UTF8
local de = function(str) return u8:decode(str) end

-- Имя файла для конфига (будет сохранен в moonloader/config/)
local INI_FILE = "FF Sender.ini"

-- Функция для загрузки настроек из INI
local function loadSettings()
    -- Дефолтные настройки
    local default_config = {
        Settings = {
            Token = "",
            ServerId = "26",
            ApiUrl = "https://simply-accurate-nilgai.cloudpub.ru:443/api"
        }
    }
    
    -- Загружаем конфиг (всегда возвращает таблицу)
    local config = inicfg.load(default_config, INI_FILE)
    
    -- Проверяем наличие токена
    if config.Settings.Token == "" then
        -- Сохраняем файл с дефолтными значениями
        inicfg.save(config, INI_FILE)
        
        -- Получаем полный путь для информационного сообщения
        local working_dir = getWorkingDirectory()
        local full_path = working_dir .. "\\config\\" .. INI_FILE
        
        sampAddChatMessage("{FF0000}[FF Sender] ❌ Не указан токен в файле!", -1)
        sampAddChatMessage("{FFFF00}[FF Sender] 📁 Файл создан: " .. full_path, -1)
        sampAddChatMessage("{FFFF00}[FF Sender] 📝 Получите токен через /givetoken в боте VK", -1)
        return nil
    end
    
    return config.Settings
end

-- Загружаем настройки
local settings = loadSettings()
if not settings then
    error("No token specified")
end

local SERVER_ID = settings.ServerId or "26"
local API_KEY = settings.Token  -- Токен пользователя из INI
local API_URL = settings.ApiUrl or "https://simply-accurate-nilgai.cloudpub.ru:443/api"

local COMMAND_COOLDOWN = {
    all = 2000,
    ["/apunishoff"] = 21000,
    ["/unapunishoff"] = 3000,
    ["/makeadminoff"] = 11000,
}

local punishPatterns = {
    'A: {mn} забанил в оффлайне игрока (.+). Причина:.*',
    'A: {mn} посадил в оффлайне игрока (.+) в КПЗ на .+ минут. Причина:.*',
    'A: {mn} установил в оффлайне .+ минут молчанки игроку (.+). Причина:.*',
    'A: {mn}%[%d+%] в оффлайне выдал варн и забанил игрока (.+) %(%d+/%d+%), причина:.*',
    'A: {mn} в оффлайне снял варн с (.+) %(осталось: %d+%), причина: .+',
    'A: {mn} снял %d+ варн у игрока (.+), причина: .+',
    'A: {mn} выпустил в оффлайне с ТСР/КПЗ (.+), причина: .+',
    'A: {mn}%[%d+%] заглушил игрока (.+)%[%d+%] на .+ минут. Причина:.*',
    'A: {mn} в оффлайне выдал варн игроку (.+) %(%d+/%d+%), причина: .+',
    'A: {mn}%[%d+%] посадил игрока (.+)%[%d+%] в деморган на .+ минут. Причина:.*',
    'A: {mn} установил в оффлайне .+ минут деморгана (.+). Причина:.*',
    'A: {mn} разбанил игрока (.+),',
    'A: {mn} выпустил в оффлайне с деморгана (.+), причина: .+',
    'A: {mn} выпустил в оффлайне с ТСР/КПЗ (.+), причина: .+',
    'A: {mn} снял заглушку в оффлайне с игрока (.+), причина: .+',
    'Вы выдали анти%-варн талоны игроку .+',
    'Вы дали .+ скин%(id: %d+%) в инвентарь',
    'A: {mn}%[%d+%] выдал предупреждение игроку (.+)%[%d+%] %[%d+/%d+%] Причина:.*',
    'Вы установили игроку .+ репутацию администратора: %d+ .+',
    'Вы выдали игроку .+%[ID: .*%] талоны антимута, количество: %d+ шт.',
    'Вы выдали игроку .+%[ID: .*%] талоны антитюрьмы, количество: %d+ шт.',
    'Вы в оффлайне выдали игроку .* талоны антимута, количество: %d+шт.*',
    'Вы в оффлайне выдали игроку .* талоны антитюрьмы, количество: %d+шт.*',
    'Вы в оффлайне выдали игроку .* талоны антидеморгана, количество: %d+шт.*',
    'Вы выдали игроку .+%[ID: .*%] талоны антидеморгана, количество: %d+ шт.',
    '%[A%] {mn}%[%d+%] передал %d+ доната в оффлайне, игроку .+',
    '%[A%] {mn}%[%d+%] передал %d+ доната, игроку.+',
    '%[A%] {mn}%[%d+%] назначил .+%[%d+%] %d+ репутации!',
    'Вы в оффлайне выдали игроку .+ скин: ID %d+ %(получит его при входе в игру%)',
    'Успешно изменено!',
    'Вы очистили список жильцов в доме!',
    'Вы очистили заместителя в бизнесе!',
    'Игрок не в тюрьме строгого режима!',
    'У игрока нет мута!',
    'У игрока нет варнов.',
    'A: {mn} в оффлайне выдал бан на использование транспорта (.+) на .+ дней. Причина:.*',
    'A: {mn} выпустил игрока (.+), причина: .+'
}

local errorMessages = {
    { 'Игрок не в деморгане!', 'игрок не в деморгане' },
    { 'У игрока нет варнов', 'игрок не имеет варнов' },
    { 'У игрока нет мута!', 'игрок не имеет мут, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'Игрок не находится в ТСР/КПЗ!', 'Игрок не находится в ТСР/КПЗ' },
    { 'Этот игрок уже в ТСР!', 'игрок уже сидит в ТСР, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'Этот игрок уже в КПЗ!', 'игрок уже сидит в КПЗ, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'Максимальный уровень тюрьмы %- 6, минимальный %- 0%(выпустить%)', 'Ошибка в форме: Максимальный уровень тюрьмы - 6, минимальный - 0(выпустить)' },
    { 'У игрока уже есть молчанка.', 'игрок уже имеет мут по другой причине, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'У этого игрока уже есть бан чата!', 'игрок уже имеет мут по другой причине, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'Этот игрок уже в ДЕМОРГАНЕ!', 'игрок уже сидит в деморгане по другой причине, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { 'Игрок уже в деморгане.', 'игрок уже сидит в деморгане по другой причине, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!' },
    { "Игрок .* не забанен", "игрок не забанен" },
    { "Игрок онлайн", "игрок находится в игре, отправьте форму в игре." },
    { "%[Ошибка%]%s*{ffffff}Игрок с ником '.*' не найден базе данных.", "Такого ника не существует, ОТПРАВЬТЕ ФОРМУ ПОВТОРНО!!"},
    { "%[Ошибка%]%s*{ffffff}Игрок уже имеет блокировку с сроком выше указанного.", "Игрок уже заблокирован на более длительный срок."}
}

local DEBUG_MODE = true

local print = function(...)
    if DEBUG_MODE then
        return print(...)
    else
        return
    end
end

local asyncHttp = (function()
    local self = {}
    local requestQueue = {}

    local function requestRunner()
        return effil.thread(loadstring([[return function(url, args)
            local https = require("ssl.https")
            local ltn12 = require("ltn12")
            
            local function fetch_with_redirects(initial_url, max_redirects)
                max_redirects = max_redirects or 5
                local current_url = initial_url
                local response_body = {}
                local response, status, headers
                
                for i = 1, max_redirects do
                    response_body = {}
                    response, status, headers = https.request({
                        url = current_url,
                        sink = ltn12.sink.table(response_body),
                        redirect = false,
                        protocol = "tlsv1_2",
                    })
                    
                    if status ~= 301 and status ~= 302 and status ~= 303 and status ~= 307 and status ~= 308 then
                        break
                    end
                    
                    if headers and headers.location then
                        local new_url = headers.location
                        print("Following redirect to: " .. new_url)
                        current_url = new_url
                    else
                        break
                    end
                end
                
                return table.concat(response_body), status
            end
            
            local ok, result, response_code = pcall(fetch_with_redirects, url, 5)
            
            if ok and result then
                return { true, result, response_code }
            else
                return { false, result or "Request failed", response_code or "Unknown error" }
            end
        end]])())
    end

    local function threadHandle(runner, url, args, resolve, reject)
        local t = runner(url, args)
        local result = t:get(0)
        while not result do
            result = t:get(0)
            wait(0)
        end
    
        local status = t:status()
        if status == "completed" then
            local ok, response, response_code = result[1], result[2], result[3]
            if ok and response then
                resolve(response)
            else
                reject("HTTP error: " .. (response_code or "Unknown") .. " | " .. (response or "No response"))
            end
        elseif status == "canceled" then
            reject("Request canceled")
        end
    end

    local webThread = lua_thread.create_suspended(function()
        while true do
            if #requestQueue > 0 then
                local request = table.remove(requestQueue, 1)
                threadHandle(request.runner, request.url, request.args, request.resolve, request.reject)
            end
            wait(1)
        end
    end)

    local function enqueueRequest(url, args, resolve, reject)
        table.insert(requestQueue, {
            runner = requestRunner(),
            url = url,
            args = args,
            resolve = resolve or function() end,
            reject = reject or function() end,
        })
    end

    local function executeImmediate(url, args, resolve, reject)
        local runner = requestRunner()
        lua_thread.create(function()
            threadHandle(runner, url, args, resolve or function() end, reject or function() end)
        end)
    end

    function self.get(useImmediate, url, resolve, reject)
        if useImmediate then
            executeImmediate(url, nil, resolve, reject)
        else
            enqueueRequest(url, nil, resolve, reject)
        end
    end

    function self.post(useImmediate, url, data, resolve, reject)
        if useImmediate then
            executeImmediate(url, data, resolve, reject)
        else
            enqueueRequest(url, data, resolve, reject)
        end
    end

    function self.thread(var)
        if var == true then
            if webThread:status() ~= "yielded" then
                webThread:run()
            end
        elseif var == false then
            if webThread:status() == "yielded" then
                webThread:terminate()
            end
        else
            error("Invalid argument type. Expected boolean, got " .. type(var))
        end
    end

    return self
end)()

local utils = {}
utils.addChat = function(a)
    if a then local a_type = type(a) if a_type == 'number' then a = tostring(a) elseif a_type ~= 'string' then return end else return end
    sampAddChatMessage('{ffa500}'..thisScript().name..'{ffffff}: '..de(a), -1)
end

-- Приветственное сообщение с информацией о токене
utils.addChat("✅ Скрипт загружен, токен: " .. API_KEY:sub(1, 10) .. "...")

-- !!! ВАЖНО: Инициализация глобальных переменных для imgui !!!
local imgui_windows = {
    main = imgui.new.bool(false)
}

local state = {
    active = false,
    forms = {},
    currentForm = nil,
    goNext = false
}

local giveFormsThread = lua_thread.create_suspended(function()
    state.active = true
    state.currentForm = nil
    state.goNext = false

    utils.addChat("Запускаю отправку форм...")

    for index, data in pairs(state.forms) do
        local cmd = (data.fullForm:match("^(/%S+)")):lower()

        sampAddChatMessage(de("Отправляю форму: " .. data.fullForm), -1)
        sampSendChat(de(data.fullForm))
        state.currentForm = data

        local waitTime = COMMAND_COOLDOWN[cmd] or COMMAND_COOLDOWN.all
        
        -- Ждем с таймаутом
        local startTime = os.clock()
        while state.active and not state.goNext do 
            wait(0)
            if os.clock() - startTime > 30 then
                print("Превышен таймаут ожидания для команды, продолжаем...")
                sendErrorToAPI(state.currentForm.id, "Timeout waiting for server response")
                break
            end
        end
        state.goNext = false
        wait(waitTime)
    end

    state.active = false
    state.forms = {}
    utils.addChat("Формы отправлены.")
end)

function main()
    repeat wait(0) until isSampAvailable()
    while not isSampLoaded() do wait(0) end

    -- ===== ВЫЗОВ АВТООБНОВЛЕНИЯ =====
    checkForUpdates(UPDATE_JSON_URL, "[" .. string.upper(thisScript().name) .. "]: ", UPDATE_MANUAL_URL)
    -- =================================

    asyncHttp.thread(true)
    getForms()

    utils.addChat("Загружен. Команда: {99ff99}/ff")

    sampRegisterChatCommand("ff", function()
        imgui_windows.main[0] = not imgui_windows.main[0]
    end)

    wait(-1)
end

function getForms()
    state.forms = {}

    local function sort()
        local punishmentFormsCmds = {
            ["/banoff"] = true,
            ["/warnoff"] = true,
            ["/apunishoff"] = true,
            ["/jailoff"] = true,
            ["/muteoff"] = true,
            ["/banipoff"] = true,
            ["/driverbanoff"] = true
        }

        local unpunishmentFormsCmds = {
            ["/unjailoff"] = true,
            ["/unapunishoff"] = true,
            ["/unmuteoff"] = true,
            ["/unban"] = true,
            ["/unbanip"] = true,
            ["/unwarnoff"] = true
        }

        local tokenFormsCmds = {
            ["/giveantiwarnoff"] = true,
            ["/givemydonateoff"] = true,
            ["/givedemotalonoff"] = true,
            ["/giveantimuteoff"] = true,
            ["/giveantijailoff"] = true,
            ["/clearhouse"] = true,
            ["/clearbiz"] = true,
            ["/makeadminoff"] = true
        }

        table.sort(state.forms, function(a, b)
            local cmdA = (a.fullForm:match("^(/%S+)")):lower()
            local cmdB = (b.fullForm:match("^(/%S+)")):lower()
        
            local function getPriority(cmd)
                if punishmentFormsCmds[cmd] then
                    return 1
                elseif unpunishmentFormsCmds[cmd] then
                    return 2
                elseif tokenFormsCmds[cmd] then
                    return 3
                end
                return 4
            end
        
            return getPriority(cmdA) < getPriority(cmdB)
        end)
    end

    -- Используем токен из INI для авторизации
    local url_str = (API_URL .. "/forms?key=" .. API_KEY .. "&serverId=" .. SERVER_ID):gsub("%s", "%%20")
    print("Request URL: " .. url_str)

    asyncHttp.get(false, url_str, function(response)
        print("Response GET: " .. response)

        local suc, data = pcall(decodeJson, (response))

        if not suc then
            utils.addChat("Ошибка декодирования json данных")
            return
        end

        if data.forms ~= nil and #data.forms > 0 then
            state.forms = data.forms
            sort()
            utils.addChat("Формы загружены. Всего: " .. #data.forms)
        else
            state.forms = {}
            utils.addChat("Формы не найдены.")
        end

    end, function(error)
        print("Error GET:" .. error)
        utils.addChat("Ошибка загрузки форм: " .. error)
    end)
end

function deleteForm(formId)
    local url_str = (API_URL .. "/forms/delete/" .. (formId) .. "?key=" .. API_KEY .. "&serverId=" .. SERVER_ID):gsub("%s", "%%20")

    asyncHttp.get(false, url_str, function(response)
        print("Response GET: " .. response)
        utils.addChat("Форма была успешно удалена!")
    end, function(error)
        print("Error GET:" .. error)
        utils.addChat("Произошла ошибка при удалении формы. Перезагружаю формы...")
        getForms()
    end)
end

function sendAcceptToAPI(formId)
    local url_str = (API_URL .. "/forms/accept/" .. (formId) .. "?key=" .. API_KEY .. "&serverId=" .. SERVER_ID)
    asyncHttp.get(false, url_str, function(response)
        print("Response GET: " .. response)
    end, function(error)
        print("Error GET:" .. error)
    end)
end

function sendErrorToAPI(formId, errorMessage)
    local url_str = (API_URL .. "/forms/error/" .. formId .. "?key=" .. API_KEY .. "&serverId=" .. SERVER_ID .. "&error=" .. url.escape(errorMessage))
    asyncHttp.get(false, url_str, function(response)
        print("Response GET: " .. response)
    end, function(error)
        print("Error GET:" .. error)
    end)
end

function sampev.onServerMessage(color, text)
    if not state.active then return end

    if text == de"[Ошибка] {ffffff}Подождите, не так часто!" then
        lua_thread.create(function()
            wait(2000)
            sampSendChat(de(state.currentForm.fullForm))
        end)
        return
    end

    text = u8(text)

    local mn = u8(sampGetPlayerNickname(
        select(2, sampGetPlayerIdByCharHandle(1))
    ))

    for _, p in ipairs(punishPatterns) do
        if p:find("{mn}") then
            p = p:gsub("{mn}", mn)
        end
        if text:find(p) then
            sendAcceptToAPI(state.currentForm.id)
            state.goNext = true
            return
        end
    end

    for i = 1, #errorMessages do
        local p = errorMessages[i]
        if text:find(p[1]) then
            sendErrorToAPI(state.currentForm.id, p[2])
            state.goNext = true
            return
        end
    end
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if not state.active or not state.currentForm then return end

    -- Декодируем текст
    title = u8(title)
    button1 = u8(button1)
    button2 = u8(button2)
    
    -- Извлекаем ник из полной команды, если нужно
    local player_name = state.currentForm.player
    if (not player_name or player_name == "Unknown" or player_name == "null") and state.currentForm.fullForm then
        -- Пробуем извлечь ник из команды /unban
        local match = state.currentForm.fullForm:match("^/unban%s+([^%s]+)")
        if match then
            player_name = match
        end
    end
    
    -- Проверяем, что это диалог разбана
    if button1 == "Разбан" or button1:find("Разбан") then
        
        -- Проверяем наличие ника в заголовке
        if player_name then
            if title:find(player_name) then
                sampSendDialogResponse(id, 1, -1, "")
                
                -- Ждем немного и отмечаем как выполненное
                lua_thread.create(function()
                    wait(2000)
                    sendAcceptToAPI(state.currentForm.id)
                    state.goNext = true
                end)
                return false
            else
                -- Пробуем без нижнего подчеркивания
                local player_name_without_underscore = player_name:gsub("_", " ")
                if title:find(player_name_without_underscore) then
                    sampSendDialogResponse(id, 1, -1, "")
                    
                    lua_thread.create(function()
                        wait(2000)
                        sendAcceptToAPI(state.currentForm.id)
                        state.goNext = true
                    end)
                    return false
                end
            end
        end
    end
end

-- Инициализация шрифтов и стилей
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil

    do
        imgui.SwitchContext()
        imgui.GetStyle().WindowPadding = imgui.ImVec2(5, 5)
        imgui.GetStyle().FramePadding = imgui.ImVec2(5, 5)
        imgui.GetStyle().ItemSpacing = imgui.ImVec2(5, 5)
        imgui.GetStyle().ItemInnerSpacing = imgui.ImVec2(2, 2)
        imgui.GetStyle().TouchExtraPadding = imgui.ImVec2(0, 0)
        imgui.GetStyle().IndentSpacing = 0
        imgui.GetStyle().ScrollbarSize = 10
        imgui.GetStyle().GrabMinSize = 10
    
        imgui.GetStyle().WindowBorderSize = 1
        imgui.GetStyle().ChildBorderSize = 1
        imgui.GetStyle().PopupBorderSize = 1
        imgui.GetStyle().FrameBorderSize = 0
        imgui.GetStyle().TabBorderSize = 1
    
        imgui.GetStyle().WindowRounding = 5
        imgui.GetStyle().ChildRounding = 5
        imgui.GetStyle().FrameRounding = 5
        imgui.GetStyle().PopupRounding = 5
        imgui.GetStyle().ScrollbarRounding = 5
        imgui.GetStyle().GrabRounding = 5
        imgui.GetStyle().TabRounding = 5
    
        imgui.GetStyle().WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
        imgui.GetStyle().ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
        imgui.GetStyle().SelectableTextAlign = imgui.ImVec2(0.5, 0.5)
        
        imgui.GetStyle().Colors[imgui.Col.Text]                   = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
        imgui.GetStyle().Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Border]                 = imgui.ImVec4(0.25, 0.25, 0.26, 0.54)
        imgui.GetStyle().Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
        imgui.GetStyle().Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.25, 0.25, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.25, 0.25, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.00, 0.00, 0.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.41, 0.41, 0.41, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.51, 0.51, 0.51, 1.00)
        imgui.GetStyle().Colors[imgui.Col.CheckMark]              = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(1.00, 1.00, 1.00, 0.30)
        imgui.GetStyle().Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(1.00, 1.00, 1.00, 0.30)
        imgui.GetStyle().Colors[imgui.Col.Button]                 = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.21, 0.20, 0.20, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.41, 0.41, 0.41, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Header]                 = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
        imgui.GetStyle().Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.47, 0.47, 0.47, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Separator]              = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(1.00, 1.00, 1.00, 0.25)
        imgui.GetStyle().Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(1.00, 1.00, 1.00, 0.67)
        imgui.GetStyle().Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(1.00, 1.00, 1.00, 0.95)
        imgui.GetStyle().Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.12, 0.12, 0.12, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.28, 0.28, 0.28, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabUnfocused]           = imgui.ImVec4(0.07, 0.10, 0.15, 0.97)
        imgui.GetStyle().Colors[imgui.Col.TabUnfocusedActive]     = imgui.ImVec4(0.14, 0.26, 0.42, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.61, 0.61, 0.61, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(1.00, 0.43, 0.35, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.90, 0.70, 0.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(1.00, 0.60, 0.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(1.00, 0.00, 0.00, 0.35)
        imgui.GetStyle().Colors[imgui.Col.DragDropTarget]         = imgui.ImVec4(1.00, 1.00, 1.00, 0.90)
        imgui.GetStyle().Colors[imgui.Col.NavHighlight]           = imgui.ImVec4(0.26, 0.59, 0.98, 1.00)
        imgui.GetStyle().Colors[imgui.Col.NavWindowingHighlight]  = imgui.ImVec4(1.00, 1.00, 1.00, 0.70)
        imgui.GetStyle().Colors[imgui.Col.NavWindowingDimBg]      = imgui.ImVec4(0.80, 0.80, 0.80, 0.20)
        imgui.GetStyle().Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.00, 0.00, 0.00, 0.70)
    end
end)

local notifications = {}
local windowWidth, windowHeight = 1000, 480

imgui.OnFrame(function() return imgui_windows.main[0] end, function()
    local screenWidth, screenHeight = getScreenResolution()

    imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(screenWidth/2-windowWidth/2, screenHeight/2-windowHeight/2), imgui.Cond.FirstUseEver)
    imgui.Begin('##main_windos', imgui_windows.main, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize)

    local wW = imgui.GetWindowWidth()

    imgui.customTitleBar(imgui_windows.main, nil, wW)
    imgui.Separator()

    if imgui.Button('Загрузить Формы', imgui.ImVec2(wW/2-10, 50)) then
        getForms()
    end
    imgui.SameLine()
    if imgui.Button('Выдать Формы', imgui.ImVec2(-1, 50)) then
        if #state.forms > 0 then
            if not state.active then
                giveFormsThread:run()
            end
        else
            utils.addChat("Нет форм для выдачи")
        end
    end

    __i__displayForms()
    imgui.showNotifications(2)

    imgui.End()
end)

function __i__displayForms()
    imgui.Columns(4, "formList", false) 
    imgui.Text("ID")
    imgui.NextColumn()
    imgui.Text("Кто запросил")
    imgui.NextColumn()
    imgui.Text("Форма")
    imgui.NextColumn()
    imgui.Text("")
    imgui.NextColumn()
    imgui.Separator()

    for index, data in pairs(state.forms) do
        imgui.Text(tostring(data.id))
        imgui.NextColumn()
        imgui.Text(data.requesterName)
        imgui.NextColumn()
        imgui.Text(data.fullForm)
        imgui.NextColumn()

        if imgui.Button("Удалить" .. "##" .. data.id, imgui.ImVec2(0, 0)) then 
            if not state.active then
                deleteForm(data.id)
                table.remove(state.forms, index)
            else
                utils.addChat("Нельзя удалять формы во время отправки")
            end
        end
        imgui.Hint("Удалить форму", true)

        imgui.NextColumn()
        imgui.Separator()
    end
end

-- Вспомогательные функции для интерфейса
function imgui.customTitleBar(param, resetFunc, windowWidth)

    local imStyle = imgui.GetStyle()

    imgui.SetCursorPosY(imStyle.ItemSpacing.y+5)
    if imgui.Link(SERVER, ("Сервер на котором Вы используете Admin Forms")) then
        imgui.addNotification("посхалко")
    end

    imgui.SameLine()
    imgui.SetCursorPosX((windowWidth - 170 - imStyle.ItemSpacing.x + imgui.CalcTextSize(script.this.name).x)/2 - imgui.CalcTextSize(script.this.name).x/2)
    imgui.TextColoredRGB(script.this.name)

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 170 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 110 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)
    if imgui.Button("Меню".."##popup_menu_button", imgui.ImVec2(50, 25)) then
        imgui.OpenPopup("upWindowPupupMenu")
    end

    imgui.SameLine()

    imgui.SetCursorPosX(windowWidth - 50 - imStyle.ItemSpacing.x)
    imgui.SetCursorPosY(imStyle.ItemSpacing.y)

    if param == nil then

        local style = imgui.GetStyle()
        local buttonColor = style.Colors[imgui.Col.Button]
        local textColor = style.Colors[imgui.Col.TextDisabled]
        local modifiedColor = imgui.ImVec4(buttonColor.x, buttonColor.y, buttonColor.z, buttonColor.w / 2)

        imgui.PushStyleColor(imgui.Col.Button, modifiedColor)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, modifiedColor)
        imgui.PushStyleColor(imgui.Col.ButtonActive, modifiedColor)
        imgui.PushStyleColor(imgui.Col.Text, textColor)

    end

    if imgui.Button("Закрыть".."##close_button", imgui.ImVec2(50, 25)) then
        if param ~= nil then param[0] = false end
    end

    if param == nil then
        imgui.PopStyleColor(4)
    end

    if imgui.BeginPopup("upWindowPupupMenu") then
        
        imgui.TextColoredRGB("Доп. Функции:")
        imgui.Separator()

        imgui.Separator()
        if imgui.Selectable(("Перезагрузить скрипт").."##reloadScriptButton", false) then
            thisScript():reload()
        end

        imgui.Separator()

        imgui.TextDisabled(
            "Версия: " .. script.this.version .. " (" .. script.this.version_num .. ")"
        )
    
        imgui.EndPopup()
    end
end

function imgui.Link(label, description)
    local size, p, p2 = imgui.CalcTextSize(label), imgui.GetCursorScreenPos(), imgui.GetCursorPos()
    local result = imgui.InvisibleButton(label, size)
    imgui.SetCursorPos(p2)

    if imgui.IsItemHovered() then
        if description then
            imgui.BeginTooltip()
            imgui.PushTextWrapPos(600)
            imgui.TextUnformatted(description)
            imgui.PopTextWrapPos()
            imgui.EndTooltip()
        end
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
        imgui.GetWindowDrawList():AddLine(imgui.ImVec2(p.x, p.y + size.y), imgui.ImVec2(p.x + size.x, p.y + size.y), imgui.GetColorU32(imgui.Col.CheckMark))
    else
        imgui.TextColored(imgui.ImVec4(0.27, 0.53, 0.87, 1.00), label)
    end

    return result
end

function imgui.addNotification(text)
    table.insert(notifications, {
        text = text,
        startTime = os.clock()
    })
end

function imgui.showNotifications(duration)
    local currentTime = os.clock()
    local activeNotifications = #notifications

    if activeNotifications ~= 0 then
        imgui.BeginTooltip()
    end
    for i = #notifications, 1, -1 do
        local notification = notifications[i]
        if currentTime - notification.startTime < duration then
            imgui.Text(notification.text)
            activeNotifications = activeNotifications + 1
            if i > 1 then
                imgui.Separator()
            end
        else
            table.remove(notifications, i)
        end
    end

    if activeNotifications ~= 0 then
        imgui.EndTooltip()
    end
end

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec4 = imgui.ImVec4

    local explode_argb = function(argb)
        local a = bit.band(bit.rshift(argb, 24), 0xFF)
        local r = bit.band(bit.rshift(argb, 16), 0xFF)
        local g = bit.band(bit.rshift(argb, 8), 0xFF)
        local b = bit.band(argb, 0xFF)
        return a, r, g, b
    end

    local getcolor = function(color)
        if color:sub(1, 6):upper() == 'SSSSSS' then
            local r, g, b = colors[1].x, colors[1].y, colors[1].z
            local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
            return ImVec4(r, g, b, a / 255)
        end
        local color = type(color) == 'string' and tonumber(color, 16) or color
        if type(color) ~= 'number' then return end
        local r, g, b, a = explode_argb(color)
        return imgui.ImVec4(r/255, g/255, b/255, a/255)
    end

    local render_text = function(text_)
        for w in text_:gmatch('[^\r\n]+') do
            local text, colors_, m = {}, {}, 1
            w = w:gsub('{(......)}', '{%1FF}')
            while w:find('{........}') do
                local n, k = w:find('{........}')
                local color = getcolor(w:sub(n + 1, k - 1))
                if color then
                    text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                    colors_[#colors_ + 1] = color
                    m = n
                end
                w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
            end
            if text[0] then
                for i = 0, #text do
                    imgui.TextColored(colors_[i] or colors[1], (text[i]))
                    imgui.SameLine(nil, 0)
                end
                imgui.NewLine()
            else imgui.Text((w)) end
        end
    end

    render_text(text)
end

function imgui.Hint(text, active)
    if not active then
        active = not imgui.IsItemActive()
    end

    if imgui.IsItemHovered() and active then
        imgui.SetTooltip(text)
    end
end