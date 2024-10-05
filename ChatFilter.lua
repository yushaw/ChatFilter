-- 在文件开头添加
ChatFilterDB = ChatFilterDB or {}

local ChatFilter = {}
ChatFilter.version = "2.3"
ChatFilter.keywords = {}
ChatFilter.frame = nil
ChatFilter.scrollFrame = nil
ChatFilter.content = nil
ChatFilter.autoScroll = true
ChatFilter.latestButton = nil
ChatFilter.maxLines = 100  -- 最大显示行数
ChatFilter.lastMessages = {}  -- 用于存储每个发言者的最后一条消息
ChatFilter.enabled = false  -- 总开关状态

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
    print("Chat Filter插件已加载。版本: " .. self.version)
end

-- 加载关键词
function ChatFilter:LoadKeywords()
    if ChatFilterDB.keywords and #ChatFilterDB.keywords > 0 then
        self.keywords = ChatFilterDB.keywords
        print("已加载保存的关键词")
    else
        -- 默认关键词
        self.keywords = {
            {
                {{"10H", "10人"}, {"dz", "盗贼"}}
            },
            {
                {{"25H", "25人"}, {"战斗贼", "破甲"}}
            },
        }
        print("使用默认关键词")
    end
end

-- 创建过滤框体
function ChatFilter:CreateFilterFrame()
    -- 主框体
    self.frame = CreateFrame("Frame", "ChatFilterFrame", UIParent, "BasicFrameTemplateWithInset")
    self.frame:SetSize(400, 500)  -- 增加宽度和高度
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", self.frame.StopMovingOrSizing)
    self.frame.title = self.frame:CreateFontString(nil, "OVERLAY")
    self.frame.title:SetFontObject("GameFontHighlight")
    self.frame.title:SetPoint("LEFT", self.frame.TitleBg, "LEFT", 5, 0)
    self.frame.title:SetText("聊天过滤")

    -- 更新关闭按钮的处理
    self.frame.CloseButton:SetScript("OnClick", function()
        self:OnFrameClosed()
        self.frame:Hide()
    end)

    -- 滚动框体
    self.scrollFrame = CreateFrame("ScrollFrame", nil, self.frame, "UIPanelScrollFrameTemplate")
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -30)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -30, 28)

    -- 内容框体
    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetSize(354, 1)  -- 调整内容宽度
    self.scrollFrame:SetScrollChild(self.content)

    -- 添加滚动事件
    self.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        ChatFilter:UpdateScrollState()
    end)
    self.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        local new = current - (delta * 20)
        new = math.max(0, math.min(new, max))
        self:SetVerticalScroll(new)
        ChatFilter:UpdateScrollState()
    end)

    -- 添加"跳转到最新"按钮
    self.latestButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.latestButton:SetSize(100, 22)
    self.latestButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 6)
    self.latestButton:SetText("跳转到最新")
    self.latestButton:SetScript("OnClick", function()
        ChatFilter:ScrollToBottom()
    end)

    -- 添加修改关键词按钮
    self.editKeywordsButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.editKeywordsButton:SetSize(120, 22)
    self.editKeywordsButton:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -30, -4)
    self.editKeywordsButton:SetText("修改关键词")
    self.editKeywordsButton:SetScript("OnClick", function()
        self:ShowKeywordEditFrame()
    end)

    self.frame:Hide()
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
        else
            self:OnChatMessage(event, ...)
        end
    end)
end

-- 处理聊天消息
function ChatFilter:OnChatMessage(event, message, sender, _, _, _, _, _, _, _, _, _, guid)
    if not self.enabled then return end  -- 如果总开关关闭，直接返回
    if self:ContainsKeyword(message) then
        -- 如果可能，缓存发送者的职业信息
        if guid then
            local _, class = GetPlayerInfoByGUID(guid)
            if class then
                self:CacheClass(sender, class)
            end
        end
        self:DisplayFilteredMessage(event, message, sender)
    end
end

-- 检查消息是否包含关键词（支持复杂的逻辑关系）
function ChatFilter:ContainsKeyword(message)
    message = message:lower()  -- 将消息转换为小写
    for _, keywordSet in ipairs(self.keywords) do
        local setMatch = true
        for _, andGroup in ipairs(keywordSet[1]) do
            local groupMatch = false
            for _, keyword in ipairs(andGroup) do
                if string.find(message, keyword:lower()) then
                    groupMatch = true
                    break
                end
            end
            if not groupMatch then
                setMatch = false
                break
            end
        end
        if setMatch then
            return keywordSet
        end
    end
    return false
end

-- 获取职业颜色
function ChatFilter:GetClassColor(name)
    local class
    -- 尝试获取玩家的职业
    if UnitExists(name) then
        _, class = UnitClass(name)
    else
        -- 如果无法直接获取，尝试从缓存中获取
        class = self:GetCachedClass(name)
    end

    if class and CLASS_COLORS[class] then
        return unpack(CLASS_COLORS[class])
    end
    return 1, 1, 1  -- 默认白色
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
    self.frame:Show()

    local keywordSet = self:ContainsKeyword(message)
    local currentTime = date("%H:%M")

    -- 检查是否是重复消息
    if self.lastMessages[sender] and self.lastMessages[sender].message == message then
        -- 更新现有消息的时间戳
        self.lastMessages[sender].time = currentTime
        self.lastMessages[sender].timeString:SetText(currentTime)
        return
    end

    -- 创建一个框架来容纳整行内容
    local line = CreateFrame("Frame", nil, self.content)
    line:SetSize(self.content:GetWidth(), 20) -- 设置一个合适的高度
    line:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.content:GetHeight())

    -- 创建整合了玩家名字和消息内容的 FontString
    local fullMessage = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fullMessage:SetPoint("TOPLEFT", line, "TOPLEFT")
    fullMessage:SetPoint("RIGHT", line, "RIGHT", -50, 0)  -- 为时间戳留出空间
    fullMessage:SetJustifyH("LEFT")

    -- 获取职业颜色
    local r, g, b = self:GetClassColor(sender)
    
    -- 构建彩色的玩家名字
    local coloredName = string.format("|cFF%02X%02X%02X%s|r", r*255, g*255, b*255, sender)

    -- 高亮关键词（不区分大小写）
    local highlightedMessage = message
    for _, andGroup in ipairs(keywordSet[1]) do
        for _, keyword in ipairs(andGroup) do
            local pattern = keyword:gsub("(%a)", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
            highlightedMessage = highlightedMessage:gsub(pattern, "|cFFFFFF00%1|r")
        end
    end

    -- 设置完整的消息文本，使用白色作为默认文字颜色
    fullMessage:SetText(coloredName .. ": |cFFFFFFFF" .. highlightedMessage .. "|r")

    -- 创建时间戳 FontString
    local timeString = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeString:SetPoint("RIGHT", line, "RIGHT", -5, 0)
    timeString:SetText(currentTime)
    timeString:SetTextColor(0.5, 0.5, 0.5)  -- 灰色

    -- 使玩家名字可点击
    local playerNameButton = CreateFrame("Button", nil, line)
    playerNameButton:SetSize(fullMessage:GetStringWidth(coloredName), fullMessage:GetHeight())
    playerNameButton:SetPoint("TOPLEFT", fullMessage, "TOPLEFT")
    playerNameButton:SetScript("OnClick", function()
        ChatFrame1EditBox:Show()
        ChatFrame1EditBox:SetText("/w " .. sender .. " ")
        ChatFrame1EditBox:SetFocus()
    end)

    -- 调整行高以适应内容
    line:SetHeight(math.max(fullMessage:GetStringHeight(), timeString:GetStringHeight()))

    -- 存储最后一条消息
    self.lastMessages[sender] = {
        line = line,
        message = message,
        time = currentTime,
        timeString = timeString
    }

    -- 限制显示的行数
    local children = {self.content:GetChildren()}
    if #children > self.maxLines then
        local oldestLine = children[1]
        oldestLine:Hide()
        oldestLine:SetParent(nil)
        -- 从 lastMessages 中移除对应的消息
        for s, m in pairs(self.lastMessages) do
            if m.line == oldestLine then
                self.lastMessages[s] = nil
                break
            end
        end
    end

    -- 调整内容框体的高度
    local contentHeight = 0
    for _, child in ipairs({self.content:GetChildren()}) do
        contentHeight = contentHeight + child:GetHeight()
    end
    self.content:SetHeight(contentHeight)

    -- 更新滚动状态
    self:UpdateScrollState()

    -- 根据 autoScroll 决定是否滚动到底部
    if self.autoScroll then
        self:ScrollToBottom()
    end
end

-- 滚动到底部
function ChatFilter:ScrollToBottom()
    C_Timer.After(0.05, function()  -- 添加一个短暂的延迟
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange())
        self.autoScroll = true
        self:UpdateScrollState()
    end)
end

-- 更新滚动状态
function ChatFilter:UpdateScrollState()
    local scrollFrame = self.scrollFrame
    local currentScroll = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    self.autoScroll = (currentScroll >= maxScroll - 1)  -- 添加一个小的容差
    
    -- 更新"跳转到最新"按钮的可见性
    if self.autoScroll then
        self.latestButton:Hide()
    else
        self.latestButton:Show()
    end
end

-- 切换框体显示/隐藏的函数
function ChatFilter:ToggleFrame()
    self.enabled = not self.enabled
    if self.enabled then
        self.frame:Show()
        print("Chat Filter 已启用")
    else
        self.frame:Hide()
        print("Chat Filter 已禁用")
    end
end

-- 处理框体的关闭
function ChatFilter:OnFrameClosed()
    self.enabled = false
    print("Chat Filter 已禁用")
end

-- 显示关键词编辑框架
function ChatFilter:ShowKeywordEditFrame()
    if self.keywordEditFrame then
        self.keywordEditFrame:Show()
        return
    end

    local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 400)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("编辑关键词")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    scrollFrame:SetScrollChild(editBox)

    -- 填充当前的关键词
    local keywordText = ""
    for i, keywordSet in ipairs(self.keywords) do
        if i > 1 then keywordText = keywordText .. "\n" end
        keywordText = keywordText .. self:KeywordSetToString(keywordSet[1])
    end
    editBox:SetText(keywordText)

    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetSize(100, 22)
    saveButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    saveButton:SetText("保存")
    saveButton:SetScript("OnClick", function()
        self:SaveKeywords(editBox:GetText())
        frame:Hide()
    end)

    self.keywordEditFrame = frame
end

-- 保存关键词
function ChatFilter:SaveKeywords(text)
    self.keywords = {}
    for line in text:gmatch("[^\r\n]+") do
        local keywords = {}
        for andGroup in line:gmatch("([^;]+)") do
            local orGroup = {}
            for keyword in andGroup:gmatch("([^,]+)") do
                table.insert(orGroup, keyword:trim())
            end
            table.insert(keywords, orGroup)
        end
        table.insert(self.keywords, {keywords})
    end
    ChatFilterDB.keywords = self.keywords
    print("关键词已更新并保存")
end

-- 添加关键词组合
function ChatFilter:AddKeywordSet(keywords)
    table.insert(self.keywords, {keywords})
    ChatFilterDB.keywords = self.keywords
    print("已添加关键词组合: " .. self:KeywordSetToString(keywords))
end

-- 移除关键词组合
function ChatFilter:RemoveKeywordSet(keywords)
    for i, keywordSet in ipairs(self.keywords) do
        if self:CompareKeywordSets(keywordSet[1], keywords) then
            table.remove(self.keywords, i)
            ChatFilterDB.keywords = self.keywords
            print("已移除关键词组合: " .. self:KeywordSetToString(keywords))
            return
        end
    end
    print("未找到关键词组合: " .. self:KeywordSetToString(keywords))
end

-- 添加一个新的函数来处理 ADDON_LOADED 事件
function ChatFilter:OnAddonLoaded(addonName)
    if addonName == "ChatFilter" then
        self:Init()
    end
end

-- 比较两个关键词组合是否相同
function ChatFilter:CompareKeywordSets(set1, set2)
    if #set1 ~= #set2 then return false end
    for i, group1 in ipairs(set1) do
        local group2 = set2[i]
        if #group1 ~= #group2 then return false end
        table.sort(group1)
        table.sort(group2)
        for j, keyword1 in ipairs(group1) do
            if keyword1 ~= group2[j] then return false end
        end
    end
    return true
end

-- 将关键词组合转换为字符串（用于显示）
function ChatFilter:KeywordSetToString(keywords)
    local parts = {}
    for _, group in ipairs(keywords) do
        table.insert(parts, "(" .. table.concat(group, " 或 ") .. ")")
    end
    return table.concat(parts, " 且 ")
end

-- 显示所有关键词组合
function ChatFilter:ShowKeywordSets()
    print("当前关键词组合列表:")
    for i, keywordSet in ipairs(self.keywords) do
        print(i .. ". " .. self:KeywordSetToString(keywordSet[1]))
    end
end

-- 添加斜杠命令
SLASH_CHATFILTER1 = "/cf"
SlashCmdList["CHATFILTER"] = function(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    if command == "toggle" then
        ChatFilter:ToggleFrame()
    elseif command == "edit" then
        ChatFilter:ShowKeywordEditFrame()
    elseif command == "add" and arg ~= "" then
        local keywords = {}
        for andGroup in arg:gmatch("([^;]+)") do
            local orGroup = {}
            for keyword in andGroup:gmatch("([^,]+)") do
                table.insert(orGroup, keyword:trim())
            end
            table.insert(keywords, orGroup)
        end
        ChatFilter:AddKeywordSet(keywords)
    elseif command == "remove" and arg ~= "" then
        local keywords = {}
        for andGroup in arg:gmatch("([^;]+)") do
            local orGroup = {}
            for keyword in andGroup:gmatch("([^,]+)") do
                table.insert(orGroup, keyword:trim())
            end
            table.insert(keywords, orGroup)
        end
        ChatFilter:RemoveKeywordSet(keywords)
    elseif command == "list" then
        ChatFilter:ShowKeywordSets()
    else
        print("Chat Filter 命令:")
        print("/cf toggle - 开启/关闭 Chat Filter")
        print("/cf edit - 打开关键词编辑窗口")
        print("/cf add <关键词组1>;<关键词组2>... - 添加关键词组合")
        print("/cf remove <关键词组1>;<关键词组2>... - 移除关键词组合")
        print("/cf list - 显示所有关键词组合")
        print("注意: 每个关键词组内用逗号分隔，不同组之间用分号分隔")
    end
end