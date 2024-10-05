-- 在文件开头添加
ChatFilterDB = ChatFilterDB or {}

local ChatFilter = {
    version = "3.1",
    keywords = {},
    frame = nil,
    scrollFrame = nil,
    content = nil,
    autoScroll = true,
    latestButton = nil,
    maxLines = 100,  -- 最大显示行数
    lastMessages = {},  -- 用于存储每个发言者的最后一条消息
    enabled = false,  -- 总开关状态
    debugMode = true,  -- 调试模式
}

-- 职业颜色映射
local CLASS_COLORS = {
    ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
    ["DEMONHUNTER"] = {0.64, 0.19, 0.79},
    ["DRUID"] = {1.00, 0.49, 0.04},
    ["HUNTER"] = {0.67, 0.83, 0.45},
    ["MAGE"] = {0.41, 0.80, 0.94},
    ["MONK"] = {0.00, 1.00, 0.59},
    ["PALADIN"] = {0.96, 0.55, 0.73},
    ["PRIEST"] = {1.00, 1.00, 1.00},
    ["ROGUE"] = {1.00, 0.96, 0.41},
    ["SHAMAN"] = {0.00, 0.44, 0.87},
    ["WARLOCK"] = {0.58, 0.51, 0.79},
    ["WARRIOR"] = {0.78, 0.61, 0.43},
}

-- 初始化函数
function ChatFilter:Init()
    self:LoadKeywords()
    self:CreateFilterFrame()
    self:RegisterEvents()
    self.enabled = ChatFilterDB.enabled or false

    -- 清理缓存的消息，只保留最近的100条
    if ChatFilterDB.recentMessages then
        local messagesToKeep = math.min(100, #ChatFilterDB.recentMessages)
        for i = #ChatFilterDB.recentMessages, messagesToKeep + 1, -1 do
            table.remove(ChatFilterDB.recentMessages, i)
        end
    else
        ChatFilterDB.recentMessages = {}
    end

    if self.enabled then
        self.frame:Show()
        self:RefreshFilteredMessages()
    end
    self:DebugPrint("Chat Filter插件已加载。版本: " .. self.version)
    self:DebugKeywords()
end

-- 加载关键词
function ChatFilter:LoadKeywords()
    if ChatFilterDB.keywords and #ChatFilterDB.keywords > 0 then
        self.keywords = ChatFilterDB.keywords
        self:DebugPrint("已加载保存的关键词")
    else
        -- 默认关键词
        self.keywords = {
            {{"10H", "10人"}, {"dz", "盗贼"}},
            {{"25H", "25人"}, {"战斗", "破甲"}}
        }
        ChatFilterDB.keywords = self.keywords
        self:DebugPrint("使用默认关键词")
    end
    self:ShowKeywordSets()
end

-- 创建过滤框体
function ChatFilter:CreateFilterFrame()
    if self.frame then return end
    
    -- 主框体
    self.frame = CreateFrame("Frame", "ChatFilterFrame", UIParent, "BasicFrameTemplateWithInset")
    self.frame:SetSize(400, 500)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)

    -- 标题
    self.frame.title = self.frame:CreateFontString(nil, "OVERLAY")
    self.frame.title:SetFontObject("GameFontHighlight")
    self.frame.title:SetPoint("LEFT", self.frame.TitleBg, "LEFT", 5, 0)
    self.frame.title:SetText("聊天过滤")

    -- 关闭按钮
    self.frame.CloseButton:SetScript("OnClick", function()
        self:OnFrameClosed()
        self.frame:Hide()
    end)

    -- 滚动框体
    self.scrollFrame = CreateFrame("ScrollFrame", nil, self.frame)
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -30)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 28)

    -- 内容框体
    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetSize(self.scrollFrame:GetWidth(), 1) -- 初始高度为1
    self.scrollFrame:SetScrollChild(self.content)

    self.content:SetScript("OnSizeChanged", function(_, width, height)
    end)


    -- 滚动事件
    self.scrollFrame:EnableMouseWheel(true)
    self.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        local new = current - (delta * 20)
        new = math.max(0, math.min(new, max))
        self:SetVerticalScroll(new)
        ChatFilter:UpdateScrollState()
    end)

    -- "跳转到最新"按钮
    self.latestButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.latestButton:SetSize(100, 22)
    self.latestButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 6)
    self.latestButton:SetText("跳转到最新")
    self.latestButton:SetScript("OnClick", function()
        ChatFilter:ScrollToBottom()
    end)

    -- "清除所有记录"按钮
    self.clearButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.clearButton:SetSize(100, 22)
    self.clearButton:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 8, 6)
    self.clearButton:SetText("清除所有")
    self.clearButton:SetScript("OnClick", function()
        ChatFilter:ClearAllRecords()
    end)

    self.frame:Hide()
end

-- 更新 ScrollToBottom 函数
function ChatFilter:ScrollToBottom()
    C_Timer.After(0.05, function()
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange())
        self.autoScroll = true
        self:UpdateScrollState()
    end)
end

-- 更新 UpdateScrollState 函数
function ChatFilter:UpdateScrollState()
    local scrollFrame = self.scrollFrame
    local currentScroll = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    self.autoScroll = (currentScroll >= maxScroll - 1)
    
    if self.autoScroll then
        self.latestButton:Hide()
    else
        self.latestButton:Show()
    end
end

-- 新增: 清除所有记录的函数
function ChatFilter:ClearAllRecords()
    -- 清空内容框体
    for _, child in ipairs({self.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    self.content:SetHeight(1)

    -- 重置最后消息记录
    self.lastMessages = {}

    -- 清空保存的消息
    ChatFilterDB.recentMessages = {}

    -- 更新滚动状态
    self:UpdateScrollState()

    -- 提示用户
    print("已清除所有筛选记录。")
end

-- 注册事件
function ChatFilter:RegisterEvents()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    frame:RegisterEvent("CHAT_MSG_YELL")
    frame:RegisterEvent("CHAT_MSG_SAY")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            self:OnAddonLoaded(...)
        elseif self.enabled then
            self:OnChatMessage(event, ...)
        end
    end)
end

-- 处理聊天消息
function ChatFilter:OnChatMessage(event, message, sender, _, _, _, _, _, _, _, _, _, guid)
    if not self.enabled then return end

    self:CleanOldMessages()  -- 清理旧消息

    table.insert(ChatFilterDB.recentMessages, 1, {
        event = event,
        message = message,
        sender = sender,
        time = time()
    })
    
    if #ChatFilterDB.recentMessages > 3000 then
        table.remove(ChatFilterDB.recentMessages)
    end

    for _, keywordSet in ipairs(self.keywords) do
        if self:ContainsKeyword(message, keywordSet) then
            if guid then
                local _, class = GetPlayerInfoByGUID(guid)
                if class then
                    self:CacheClass(sender, class)
                end
            end
            self:DisplayFilteredMessage(event, message, sender)
            break
        end
    end
end

-- 检查消息是否包含关键词
function ChatFilter:ContainsKeyword(message, keywordSet)
    message = string.lower(message)
    local setMatch = true
    for _, andGroup in ipairs(keywordSet) do
        local groupMatch = false
        for _, keyword in ipairs(andGroup) do
            if string.find(message, string.lower(keyword)) then
                groupMatch = true
                break
            end
        end
        if not groupMatch then
            setMatch = false
            break
        end
    end
    return setMatch
end

-- 获取职业颜色
function ChatFilter:GetClassColor(name)
    local class = self:GetCachedClass(name) or (UnitExists(name) and select(2, UnitClass(name)))
    return unpack(CLASS_COLORS[class] or {1, 1, 1})
end

-- 缓存玩家职业信息
ChatFilter.classCache = {}

function ChatFilter:CacheClass(name, class)
    self.classCache[name] = class
end

function ChatFilter:GetCachedClass(name)
    return self.classCache[name]
end

-- 显示过滤后的消息
function ChatFilter:DisplayFilteredMessage(event, message, sender)
    if not self.frame or not self.frame:IsShown() or not self.content then 
        return 
    end

    local currentTime = date("%H:%M")

    -- 检查是否是重复消息
    if self.lastMessages[sender] then
        if self.lastMessages[sender].message == message then
            -- 更新现有消息的时间戳
            self.lastMessages[sender].time = currentTime
            self.lastMessages[sender].timeString:SetText(currentTime)
            
            self:ReorderMessages()
            return
        else
            -- 如果是同一个发送者的不同消息，移除旧消息
            self.lastMessages[sender].line:Hide()
            self.lastMessages[sender].line:SetParent(nil)
            self.lastMessages[sender] = nil
        end
    end

    local line = CreateFrame("Frame", nil, self.content)
    line:SetWidth(self.content:GetWidth())

    local fullMessage = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fullMessage:SetPoint("TOPLEFT", line, "TOPLEFT", 5, -5)
    fullMessage:SetPoint("RIGHT", line, "RIGHT", -55, 0)
    fullMessage:SetJustifyH("LEFT")
    fullMessage:SetSpacing(2)  -- 添加行间距

    local r, g, b = self:GetClassColor(sender)
    local coloredName = string.format("|cFF%02X%02X%02X%s|r", r*255, g*255, b*255, sender)

    local highlightedMessage = self:HighlightKeywords(message)

    fullMessage:SetText(coloredName .. ": |cFFFFFFFF" .. highlightedMessage .. "|r")

    local timeString = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeString:SetPoint("TOPRIGHT", line, "TOPRIGHT", -5, -5)
    timeString:SetText(currentTime)
    timeString:SetTextColor(0.5, 0.5, 0.5)

    -- 计算并设置行高
    fullMessage:SetWidth(line:GetWidth() - 60)  -- 减去时间戳的宽度和一些边距
    local messageHeight = fullMessage:GetStringHeight() + 10  -- 添加一些垂直边距
    line:SetHeight(messageHeight)

    self.lastMessages[sender] = {
        line = line,
        message = message,
        time = currentTime,
        timeString = timeString
    }

    self:ReorderMessages()
    self:UpdateScrollState()

    if self.autoScroll then
        self:ScrollToBottom()
    end
end

-- 添加新函数来重新排列消息
function ChatFilter:ReorderMessages()
    local messages = {}
    for _, msg in pairs(self.lastMessages) do
        table.insert(messages, msg)
    end

    table.sort(messages, function(a, b) return a.time < b.time end)

    local contentHeight = 0
    for i, msg in ipairs(messages) do
        contentHeight = contentHeight + msg.line:GetHeight()
    end

    local scrollFrameHeight = self.scrollFrame:GetHeight()
    local yOffset = 0

    -- 如果内容高度小于滚动框体高度，从顶部开始显示消息
    if contentHeight < scrollFrameHeight then
        yOffset = 0
    else
        yOffset = -(contentHeight - scrollFrameHeight)
    end

    for i, msg in ipairs(messages) do
        msg.line:ClearAllPoints()
        msg.line:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, yOffset)
        msg.line:SetPoint("RIGHT", self.content, "RIGHT")
        msg.line:Show()
        yOffset = yOffset - msg.line:GetHeight()
    end

    self.content:SetHeight(math.max(contentHeight, scrollFrameHeight))

    while #messages > self.maxLines do
        local oldestMsg = table.remove(messages, 1)
        oldestMsg.line:Hide()
        oldestMsg.line:SetParent(nil)
        for sender, msg in pairs(self.lastMessages) do
            if msg == oldestMsg then
                self.lastMessages[sender] = nil
                break
            end
        end
    end

    self:UpdateScrollPosition()
end

function ChatFilter:UpdateScrollPosition()
    local scrollFrame = self.scrollFrame
    local contentHeight = self.content:GetHeight()
    local frameHeight = scrollFrame:GetHeight()
    local maxScroll = math.max(contentHeight - frameHeight, 0)

    if self.autoScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    else
        local currentScroll = scrollFrame:GetVerticalScroll()
        scrollFrame:SetVerticalScroll(math.min(currentScroll, maxScroll))
    end
end

-- 添加调试打印函数
function ChatFilter:DebugPrint(message)
    if self.debugMode then
        print("ChatFilter Debug: " .. message)
    end
end

-- 高亮关键词
function ChatFilter:HighlightKeywords(message)
    local highlightedMessage = message
    for _, keywordSet in ipairs(self.keywords) do
        if self:ContainsKeyword(message, keywordSet) then
            for _, andGroup in ipairs(keywordSet) do
                for _, keyword in ipairs(andGroup) do
                    local pattern = keyword:gsub("(%a)", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
                    highlightedMessage = highlightedMessage:gsub(pattern, "|cFFFFFF00%1|r")
                end
            end
            break
        end
    end
    return highlightedMessage
end

-- 滚动到底部
function ChatFilter:ScrollToBottom()
    self.autoScroll = true
    self:UpdateScrollPosition()
end

-- 更新滚动状态
function ChatFilter:UpdateScrollState()
    if not self.scrollFrame then
        return
    end

    local currentScroll = self.scrollFrame:GetVerticalScroll()
    local maxScroll = math.max(self.content:GetHeight() - self.scrollFrame:GetHeight(), 0)
    self.autoScroll = (currentScroll >= maxScroll - 1)
    
    if self.autoScroll then
        self.latestButton:Hide()
    else
        self.latestButton:Show()
    end
end

-- 切换框体显示/隐藏的函数
function ChatFilter:ToggleFrame()
    if not self.frame then
        self:CreateFilterFrame()
    end
    
    self.enabled = not self.enabled
    ChatFilterDB.enabled = self.enabled
    if self.enabled then
        self.frame:Show()
        self:RefreshFilteredMessages()
        self:DebugPrint("Chat Filter 已启用")
    else
        self.frame:Hide()
        self:DebugPrint("Chat Filter 已禁用")
    end
end

-- 处理框体的关闭
function ChatFilter:OnFrameClosed()
    self.enabled = false
    ChatFilterDB.enabled = false
    self:DebugPrint("Chat Filter 已禁用")
end

-- 刷新过滤消息
function ChatFilter:RefreshFilteredMessages()
    if not self.content then return end

    for _, child in ipairs({self.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    self.lastMessages = {}
    self.content:SetHeight(1)

    if ChatFilterDB.recentMessages then
        local displayedSenders = {}
        for i = #ChatFilterDB.recentMessages, 1, -1 do
            local messageInfo = ChatFilterDB.recentMessages[i]
            if not displayedSenders[messageInfo.sender] then
                for _, keywordSet in ipairs(self.keywords) do
                    if self:ContainsKeyword(messageInfo.message, keywordSet) then
                        self:DisplayFilteredMessage(messageInfo.event, messageInfo.message, messageInfo.sender)
                        displayedSenders[messageInfo.sender] = true
                        break
                    end
                end
            end
            if #self.lastMessages >= self.maxLines then
                break
            end
        end
    end

    self:ReorderMessages()
end

-- 添加一个新函数来清理旧消息
function ChatFilter:CleanOldMessages()
    local currentTime = time()
    local oneDayAgo = currentTime - (24 * 60 * 60)  -- 24小时前的时间戳
    
    local i = 1
    while i <= #ChatFilterDB.recentMessages do
        if ChatFilterDB.recentMessages[i].time < oneDayAgo then
            table.remove(ChatFilterDB.recentMessages, i)
        else
            i = i + 1
        end
    end
end

-- 将关键词组合转换为字符串（用于显示）
function ChatFilter:KeywordSetToString(keywordSet)
    local parts = {}
    for _, andGroup in ipairs(keywordSet) do
        table.insert(parts, "(" .. table.concat(andGroup, " 或 ") .. ")")
    end
    return table.concat(parts, " 且 ")
end

-- 显示所有关键词组合
function ChatFilter:ShowKeywordSets()
    self:DebugPrint("当前关键词组合列表:")
    if #self.keywords == 0 then
        self:DebugPrint("无关键词")
    else
        for i, keywordSet in ipairs(self.keywords) do
            self:DebugPrint(i .. ". " .. self:KeywordSetToString(keywordSet))
        end
    end
end

-- 添加关键词组合
function ChatFilter:AddKeywordSet(keywords)
    table.insert(self.keywords, keywords)
    ChatFilterDB.keywords = self.keywords
    self:DebugPrint("已添加关键词组合: " .. self:KeywordSetToString(keywords))
    self:ShowKeywordSets()
    self:RefreshFilteredMessages()
end

-- 移除关键词组合
function ChatFilter:RemoveKeywordSet(index)
    if index > 0 and index <= #self.keywords then
        local removed = table.remove(self.keywords, index)
        ChatFilterDB.keywords = self.keywords
        self:DebugPrint("已移除关键词组合: " .. self:KeywordSetToString(removed))
        self:ShowKeywordSets()
        self:RefreshFilteredMessages()
    else
        self:DebugPrint("无效的索引: " .. tostring(index))
    end
end

-- 处理插件加载
function ChatFilter:OnAddonLoaded(addonName)
    if addonName == "ChatFilter" then
        ChatFilterDB.recentMessages = ChatFilterDB.recentMessages or {}
        self:Init()
    end
end

-- 调试打印函数
function ChatFilter:DebugPrint(...)
    if self.debugMode then
        print(...)
    end
end

-- 显示调试信息
function ChatFilter:DebugKeywords()
    self:DebugPrint("当前内存中的关键词列表:")
    self:ShowKeywordSets()
    
    self:DebugPrint("ChatFilterDB中的关键词列表:")
    if not ChatFilterDB.keywords or #ChatFilterDB.keywords == 0 then
        self:DebugPrint("ChatFilterDB中无关键词")
    else
        for i, keywordSet in ipairs(ChatFilterDB.keywords) do
            self:DebugPrint(i .. ". " .. self:KeywordSetToString(keywordSet))
        end
    end
end

-- 添加 trim 函数
function string.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- 添加斜杠命令
SLASH_CHATFILTER1 = "/cf"
SlashCmdList["CHATFILTER"] = function(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    if command == "toggle" then
        ChatFilter:ToggleFrame()
    elseif command == "list" then
        ChatFilter:ShowKeywordSets()
    elseif command == "add" and arg ~= "" then
        local keywords = {}
        for andGroup in arg:gmatch("([^;]+)") do
            local orGroup = {}
            for keyword in andGroup:gmatch("([^,]+)") do
                table.insert(orGroup, string.trim(keyword))
            end
            table.insert(keywords, orGroup)
        end
        ChatFilter:AddKeywordSet(keywords)
    elseif command == "remove" and arg ~= "" then
        local index = tonumber(arg)
        if index then
            ChatFilter:RemoveKeywordSet(index)
        else
            print("请提供有效的索引号")
        end
    elseif command == "debug" then
        ChatFilter.debugMode = not ChatFilter.debugMode
        print("Chat Filter 调试模式: " .. (ChatFilter.debugMode and "开启" or "关闭"))
    else
        print("Chat Filter 命令:")
        print("/cf toggle - 开启/关闭 Chat Filter")
        print("/cf list - 显示所有关键词组合")
        print("/cf add <关键词组1>;<关键词组2>... - 添加关键词组合")
        print("/cf remove <索引> - 移除指定索引的关键词组合")
        print("/cf debug - 切换调试模式")
        print("注意: 每个关键词组内用逗号分隔，不同组之间用分号分隔")
    end
end

-- 初始化插件
ChatFilter:Init()