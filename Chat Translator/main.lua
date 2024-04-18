ChatTranslator = ChatTranslator or {}
ChatTranslator.CHAT_TYPE = {CHATGUI = 1, HUDCHAT = 2}
ChatTranslator.HUD = {
    DEFAULT = 1,
    WOLFHUD = 2,
    VOIDUI = 3,
    VANILLAHUD = 4
}
ChatTranslator.default_settings = {
    language = "en",
    keyword = "tl",
    hud = ChatTranslator.HUD.DEFAULT,
    extend_chat = true,
    mouse_pointer = true,
    auto_translate = true,
    auto_translate_excludes = {}
}

ChatTranslator._mod_path = ModPath
ChatTranslator._languages_file = ChatTranslator._mod_path .. "languages.json"
ChatTranslator._save_path = SavePath
ChatTranslator._save_file = ChatTranslator._save_path .. "chat_translator.json"

local function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deep_copy(orig_key)] = deep_copy(orig_value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function ChatTranslator:Setup()
    if not self.settings then
        self:Load()
        self.LoadLanguages()
    end

    if ChatTranslator.HUD.VANILLAHUD then
        HSAS = HSAS or {}
    end

    self.SetupHooks()
end

function ChatTranslator:Load()
    self.settings = deep_copy(self.default_settings)
    local file = io.open(self._save_file, "r")
    if file then
        local data = file:read("*a")
        if data then
            local decoded_data = json.decode(data)

            if decoded_data then
                for key, value in pairs(self.settings) do
                    if decoded_data[key] ~= nil then
                        self.settings[key] = decoded_data[key]
                    end
                end
            end
        end
        file:close()
    end
end

function ChatTranslator:Save()
    local file = io.open(self._save_file, "w+")
    if file then
        file:write(json.encode(self.settings))
        file:close()
    end
end

function ChatTranslator.LoadLanguages()
    ChatTranslator.languages = {
        codes = {},
        name_ids = {},
        names = {}
    }

    local file = io.open(ChatTranslator._languages_file, "r")
    if file then
        local data = file:read("*a")
        if data then
            local decoded_data = json.decode(data)

            if decoded_data then
                local list = {}
                for key, value in pairs(decoded_data) do
                    table.insert(list, {code = key, name = value.name})
                end

                table.sort(
                    list,
                    function(entry1, entry2)
                        return entry1.name < entry2.name
                    end
                )

                for i, value in ipairs(list) do
                    table.insert(ChatTranslator.languages.codes, value.code)
                    table.insert(ChatTranslator.languages.name_ids, "chat_translator_" .. value.name)
                    table.insert(ChatTranslator.languages.names, value.name)
                end
            end
        end
        file:close()
    end
end

function ChatTranslator.EncodeUrl(message)
    if message == nil then
        return nil
    end

    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end

    message = message:gsub("\n", "\r\n")
    message = message:gsub("([^%w _%%%-%.~])", char_to_hex)
    message = message:gsub(" ", "+")
    return message
end

function ChatTranslator.RequestTranslation(language, message, callback)
    local url_encoded_message = ChatTranslator.EncodeUrl(message)
    if not url_encoded_message then
        return
    end

    local url =
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" ..
        language .. "&dt=t&q=" .. url_encoded_message

    dohttpreq(
        url,
        function(data)
            if not data then
                return
            end

            local decoded_data = json.decode(data)
            if
                not decoded_data or not decoded_data[1] or not decoded_data[1][1] or not decoded_data[1][1][1] or
                    not decoded_data[2]
             then
                return
            end

            local source_language = tostring(decoded_data[2])
            if not source_language then
                return
            end

            local translated_message = tostring(decoded_data[1][1][1])
            if not translated_message then
                return
            end

            if source_language ~= language then
                callback(source_language, translated_message)
            end
        end
    )
end

function ChatTranslator.ProcessInput(object, channel_id, sender, message)
    if message:find(ChatTranslator.settings.keyword) ~= 1 then
        return false
    end

    message = message:gsub(ChatTranslator.settings.keyword, "", 1)
    if message:len() == 0 then
        return true
    end

    if message:find(" ") ~= 1 then
        return false
    end

    message = message:gsub(" ", "", 1)
    if message:len() == 0 then
        return true
    end

    if message:len() >= 4 then
        local target_language = message:sub(1, 2)
        if message:find(" ") ~= 3 then
            return true
        end

        message = message:sub(4)

        ChatTranslator.RequestTranslation(
            target_language,
            message,
            function(language, message)
                return ChatTranslator._ChatManager_send_message(object, channel_id, sender, message)
            end
        )
    end
    return true
end

function ChatTranslator.UpdateButtons()
    local chat_extendable = ChatTranslator.settings.hud == ChatTranslator.HUD.DEFAULT

    local mouse_pointer_enableable = ChatTranslator.settings.hud ~= ChatTranslator.HUD.VOIDUI

    if not chat_extendable then
        ChatTranslator.settings.extend_chat = false
    end

    if not mouse_pointer_enableable then
        ChatTranslator.settings.mouse_pointer = false
    end

    for _, item in pairs(MenuHelper:GetMenu("chat_translator")._items_list) do
        if item:name() == "chat_translator_extend_chat" then
            item:set_value(ChatTranslator.settings.extend_chat and "on" or "off")
            item:set_enabled(chat_extendable)
        elseif item:name() == "chat_translator_mouse_pointer" then
            item:set_value(ChatTranslator.settings.mouse_pointer and "on" or "off")
            item:set_enabled(mouse_pointer_enableable)
        end
    end
end

function ChatTranslator:Warn()
    local dialog_data = {
        title = managers.localization:text("dialog_warning_title"),
        text = managers.localization:text("chat_translator_warning_hud_missing")
    }

    local ok_button = {
        text = managers.localization:text("dialog_ok")
    }

    dialog_data.button_list = {
        ok_button
    }

    managers.system_menu:show(dialog_data)
end

function ChatTranslator:CheckHUDCompatibility()
    if self.settings.hud == ChatTranslator.HUD.WOLFHUD and not WolfHUD then
        ChatTranslator:Warn()
    elseif self.settings.hud == ChatTranslator.HUD.VOIDUI and (not VoidUI or not VoidUI.options.enable_chat) then
        ChatTranslator:Warn()
    elseif self.settings.hud == ChatTranslator.HUD.VANILLAHUD then
        if (not VHUDPlus or not VHUDPlus:getSetting({"HUDChat", "ENABLED"}, true)) then
            ChatTranslator:Warn()
        end
    end
end

function ChatTranslator:mouse_moved(x, y)
    local output_panel = self._panel:child("output_panel")
    if not output_panel:inside(x, y) then
        managers.mouse_pointer:set_pointer_image("arrow")
        return false
    end

    if
        not self._chat_type == ChatTranslator.CHAT_TYPE.CHATGUI and
            ChatTranslator.settings.hud == ChatTranslator.HUD.VOIDUI
     then
        local inside = false
        for i = #self._lines, 1, -1 do
            local panel = self._lines[i].panel
            if inside == false then
                inside = panel:inside(x, y)
            end
            panel:set_alpha(panel:inside(x, y) and 1 or 0.5)
        end
    end

    for i = #self._translatable_messages, 1, -1 do
        local message = self._translatable_messages[i]

        if message:inside(x, y) then
            managers.mouse_pointer:set_pointer_image("link")
            return true
        end
    end

    managers.mouse_pointer:set_pointer_image("arrow")
    return false
end

function ChatTranslator:mouse_pressed(button, x, y)
    local output_panel = self._panel:child("output_panel")
    if not output_panel:inside(x, y) or button ~= Idstring("0") then
        return false
    end

    for i = #self._translatable_messages, 1, -1 do
        local message = self._translatable_messages[i]

        if message:inside(x, y) then
            message:ToggleTranslation()
            self:_on_focus()
            return true
        end
    end

    return false
end

ChatTranslatorMessage = ChatTranslatorMessage or class()

function ChatTranslatorMessage:init(chat, line, name, message, color, icon)
    self._chat = chat
    self._line = line
    self._name = name
    self._message = message
    self._color = color
    self._icon = icon
    self._show_translation = false

    if
        self._chat._chat_type == ChatTranslator.CHAT_TYPE.HUDCHAT and
            ChatTranslator.settings.hud == ChatTranslator.HUD.VOIDUI
     then
        self._time_stamp =
            VoidUI.options.chattime == 2 and "[" .. os.date("!%X", managers.game_play_central:get_heist_timer()) .. "] " or
            "[" .. os.date("%X") .. "] "
    end
end

function ChatTranslatorMessage:inside(x, y)
    if
        ChatTranslator.settings.hud == ChatTranslator.HUD.DEFAULT or
            self._chat._chat_type == ChatTranslator.CHAT_TYPE.CHATGUI
     then
        return self._line[2]:inside(x, y)
    else
        return self._line.panel:inside(x, y)
    end
end

function ChatTranslatorMessage:RequestTranslation(auto_translating)
    auto_translating = auto_translating or false

    if self._translation_requested then
        return
    end

    self._translation_requested = true

    ChatTranslator.RequestTranslation(
        ChatTranslator.settings.language,
        self._message,
        function(language, message)
            return self:ApplyTranslation(language, message, auto_translating)
        end
    )
end

function ChatTranslatorMessage:ApplyTranslation(language, message, auto_translating)
    self._translated = true

    self._language = language
    self._translated_message = message

    if (not auto_translating) or (auto_translating and ChatTranslator.settings.auto_translate and (not table.contains(ChatTranslator.settings.auto_translate_excludes, self._language))) then
        self:ToggleTranslation()
    end
end

function ChatTranslatorMessage:ToggleTranslation()
    if not self._translated then
        self:RequestTranslation()
        return
    end

    self._show_translation = not self._show_translation

    local display_name = nil
    local display_message = nil
    if self._show_translation then
        display_name = self._name .. " (" .. self._language .. ")"
        display_message = self._translated_message
    else
        display_name = self._name
        display_message = self._message
    end

    if
        ChatTranslator.settings.hud == ChatTranslator.HUD.DEFAULT or
            self._chat._chat_type == ChatTranslator.CHAT_TYPE.CHATGUI
     then
        local line = self._line[1]
        local line_bg = self._line[2]

        local len = utf8.len(display_name) + 1
        line:set_text(display_name .. ": " .. display_message)

        local total_len = utf8.len(line:text())

        line:set_range_color(0, len, self._color)
        line:set_range_color(len, total_len, Color.white)

        line:set_w(self._chat._panel:child("output_panel"):w() - line:left())

        local _, _, w, h = line:text_rect()

        line:set_h(h)
        line_bg:set_w(w + line:left() + 2)
        line_bg:set_h(self._chat.line_height * line:number_of_lines())
    elseif
        ChatTranslator.settings.hud == ChatTranslator.HUD.WOLFHUD or
            ChatTranslator.settings.hud == ChatTranslator.HUD.VANILLAHUD
     then
        local msg_panel = self._line.panel
        local message_text = msg_panel:child("msg")
        local msg_panel_bg = msg_panel:child("bg")

        message_text:set_text(display_name .. ": " .. display_message)
        local no_lines = message_text:number_of_lines()

        message_text:set_range_color(0, utf8.len(display_name) + 1, self._color)
        message_text:set_h(self._chat.LINE_HEIGHT * no_lines)
        message_text:set_kern(message_text:kern())
        msg_panel:set_h(self._chat.LINE_HEIGHT * no_lines)
        msg_panel_bg:set_h(self._chat.LINE_HEIGHT * no_lines)
        if not self._chat.COLORED_BG then
            local x_offset = HUDChat.COLORED_BG and 2 or 0
            local time_text = msg_panel:child("time")
            local _, _, w, _ = time_text:text_rect()
            x_offset = x_offset + w + 2
            local icon_bitmap = msg_panel:child("icon")
            if icon_bitmap then
                x_offset = x_offset + icon_bitmap:w() + 1
            end

            local _, _, msg_w, _ = message_text:text_rect()

            msg_panel_bg:set_width(x_offset + msg_w + 2)
        end
    elseif ChatTranslator.settings.hud == ChatTranslator.HUD.VOIDUI then
        local name = self._line.name
        local peer =
            (managers.network and managers.network:session() and
            managers.network:session():local_peer():name() == self._name and
            managers.network:session():local_peer()) or
            (managers.network and managers.network:session() and managers.network:session():peer_by_name(self._name))
        local character = self._line.character
        local full_message =
            display_name ..
            (VoidUI.options.show_charactername and peer and peer:character() and character or "") ..
                ": " .. display_message
        if self._name == managers.localization:to_upper_text("menu_system_message") then
            name = display_message
            full_message = display_message
        else
            name = display_name
        end

        if VoidUI.options.chattime > 1 and self._time_stamp then
            full_message = self._time_stamp .. full_message
            name = self._time_stamp .. name
        end
        local len = utf8.len(name) + (VoidUI.options.show_charactername and utf8.len(character) or 0) + 1

        local output_panel = self._chat._panel:child("output_panel")
        local panel = self._line.panel
        local line = panel:child("line")
        local line_shadow = panel:child("line_shadow")

        line:set_text(full_message)
        line_shadow:set_text(full_message)

        line_shadow:set_w(output_panel:w() - line:left())

        local total_len = utf8.len(line:text())
        local lines_count = line:number_of_lines()
        self._chat._lines_count = self._chat._lines_count + lines_count
        line:set_range_color(0, len, self._color)
        line:set_range_color(len, total_len, Color.white)
        panel:set_h(self._chat.line_height * self._chat._scale * lines_count)
        line:set_h(panel:h())
        line_shadow:set_h(panel:h())
    end

    if
        self._chat._chat_type == ChatTranslator.CHAT_TYPE.HUDCHAT and
            ChatTranslator.settings.hud == ChatTranslator.HUD.VOIDUI
     then
        self._chat:_layout_custom_output_panel()
    else
        self._chat:_layout_output_panel()
    end
end

function ChatTranslator.SetupHooks()
    if RequiredScript == "lib/managers/chatmanager" then
        Hooks:PostHook(
            ChatGui,
            "init",
            "ChatTranslator_ChatGui_init",
            function(self)
                self._chat_type = ChatTranslator.CHAT_TYPE.CHATGUI
                self._translatable_messages = {}
            end
        )

        Hooks:PostHook(
            ChatGui,
            "receive_message",
            "ChatTranslator_ChatGui_receive_message",
            function(self, name, message, color, icon)
                local line = self._lines[#self._lines]

                local translatable_message = ChatTranslatorMessage:new(self, line, name, message, color, icon)

                if ChatTranslator.settings.auto_translate then
                    translatable_message:RequestTranslation(true)
                end

                table.insert(self._translatable_messages, translatable_message)
            end
        )

        ChatTranslator._ChatGui_mouse_moved = ChatGui.mouse_moved
        function ChatGui:mouse_moved(x, y)
            local inside, arrow = ChatTranslator._ChatGui_mouse_moved(self, x, y)
            if not inside and ChatTranslator.mouse_moved(self, x, y) then
                return true, "link"
            end

            return inside, arrow
        end

        Hooks:PreHook(ChatGui, "mouse_pressed", "ChatTranslator_ChatGui_mouse_pressed", ChatTranslator.mouse_pressed)

        ChatTranslator._ChatManager_send_message = ChatManager.send_message
        function ChatManager:send_message(channel_id, sender, message)
            if not ChatTranslator.ProcessInput(self, channel_id, sender, message) then
                ChatTranslator._ChatManager_send_message(self, channel_id, sender, message)
            end
        end
    elseif RequiredScript == "lib/managers/hud/hudchat" then
        if ChatTranslator.settings.hud == ChatTranslator.HUD.DEFAULT then
            function HUDChat:init(ws, hud)
                self._ws = ws
                self._hud_panel = hud.panel

                self:set_channel_id(ChatManager.GAME)

                self._output_width = 300
                self._panel_width = 500
                self._lines = {}
                self._max_lines = 10
                self._esc_callback = callback(self, self, "esc_key_callback")
                self._enter_callback = callback(self, self, "enter_key_callback")
                self._typing_callback = 0
                self._skip_first = false
                self._panel =
                    self._hud_panel:panel(
                    {
                        name = "chat_panel",
                        h = 500,
                        halign = "left",
                        x = 0,
                        valign = "bottom",
                        w = self._panel_width
                    }
                )

                self._panel:set_bottom(self._panel:parent():h() - 112)

                local output_panel =
                    self._panel:panel(
                    {
                        name = "output_panel",
                        h = 10,
                        x = 0,
                        layer = 1,
                        w = self._output_width
                    }
                )

                output_panel:gradient(
                    {
                        blend_mode = "sub",
                        name = "output_bg",
                        valign = "grow",
                        layer = -1,
                        gradient_points = {
                            0,
                            Color.white:with_alpha(0),
                            0.2,
                            Color.white:with_alpha(0.25),
                            1,
                            Color.white:with_alpha(0)
                        }
                    }
                )

                local scroll_panel =
                    output_panel:panel(
                    {
                        name = "scroll_panel",
                        x = 0,
                        h = 10,
                        w = self._output_width
                    }
                )

                self:_create_input_panel()
                self:_layout_input_panel()
                self:_layout_output_panel()
            end

            function HUDChat:receive_message(name, message, color, icon)
                local output_panel = self._panel:child("output_panel")
                local scroll_panel = output_panel:child("scroll_panel")
                local len = utf8.len(name) + 1
                local x = 0
                local icon_bitmap = nil

                if icon then
                    local icon_texture, icon_texture_rect = tweak_data.hud_icons:get_icon_data(icon)
                    icon_bitmap =
                        scroll_panel:bitmap(
                        {
                            y = 1,
                            texture = icon_texture,
                            texture_rect = icon_texture_rect,
                            color = color
                        }
                    )
                    x = icon_bitmap:right()
                end

                local line =
                    scroll_panel:text(
                    {
                        halign = "left",
                        vertical = "top",
                        hvertical = "top",
                        wrap = true,
                        align = "left",
                        blend_mode = "normal",
                        word_wrap = true,
                        y = 0,
                        layer = 0,
                        text = name .. ": " .. message,
                        font = tweak_data.menu.pd2_small_font,
                        font_size = tweak_data.menu.pd2_small_font_size,
                        x = x,
                        w = scroll_panel:w() - x,
                        color = color
                    }
                )
                local total_len = utf8.len(line:text())

                line:set_range_color(0, len, color)
                line:set_range_color(len, total_len, Color.white)

                local _, _, w, h = line:text_rect()

                line:set_h(h)

                local line_bg =
                    scroll_panel:rect(
                    {
                        hvertical = "top",
                        halign = "left",
                        layer = -1,
                        color = Color.black:with_alpha(0)
                    }
                )

                line_bg:set_h(h)

                local line_data = {
                    line,
                    line_bg,
                    icon_bitmap
                }
                table.insert(self._lines, line_data)
                line:set_kern(line:kern())
                self:_layout_output_panel()

                if not self._focus then
                    output_panel:stop()
                    output_panel:animate(callback(self, self, "_animate_show_component"), output_panel:alpha())
                    output_panel:animate(callback(self, self, "_animate_fade_output"))
                end
            end

            function HUDChat:_layout_output_panel()
                local output_panel = self._panel:child("output_panel")
                local scroll_panel = output_panel:child("scroll_panel")

                scroll_panel:set_w(self._output_width)
                output_panel:set_w(self._output_width)

                local line_height = ChatGui.line_height
                local max_lines = self._max_lines
                local lines = 0

                for i = #self._lines, 1, -1 do
                    local line = self._lines[i][1]
                    local line_bg = self._lines[i][2]
                    local icon = self._lines[i][3]

                    line:set_w(scroll_panel:w() - line:left())

                    local _, _, w, h = line:text_rect()

                    line:set_h(h)
                    line_bg:set_w(w + line:left() + 2)
                    line_bg:set_h(line_height * line:number_of_lines())

                    lines = lines + line:number_of_lines()
                end

                local scroll_at_bottom = scroll_panel:bottom() == output_panel:h()

                output_panel:set_h(math.round(line_height * math.min(max_lines, lines)))
                scroll_panel:set_h(math.round(line_height * lines))

                local y = 0

                for i = #self._lines, 1, -1 do
                    local line = self._lines[i][1]
                    local line_bg = self._lines[i][2]
                    local icon = self._lines[i][3]
                    local _, _, w, h = line:text_rect()

                    line:set_bottom(scroll_panel:h() - y)
                    line_bg:set_bottom(line:bottom())

                    if icon then
                        icon:set_left(icon:left())
                        icon:set_top(line:top() + 1)
                        line:set_left(icon:right())
                    else
                        line:set_left(line:left())
                    end

                    y = y + line_height * line:number_of_lines()
                end

                output_panel:set_bottom(math.round(self._input_panel:top()))

                if lines <= max_lines or scroll_at_bottom then
                    scroll_panel:set_bottom(output_panel:h())
                end
            end

            if ChatTranslator.settings.extend_chat then
                function HUDChat:mouse_pressed(button, x, y)
                    local output_panel = self._panel:child("output_panel")
                    if output_panel:inside(x, y) then
                        if button == Idstring("mouse wheel down") then
                            return self:scroll_down()
                        elseif button == Idstring("mouse wheel up") then
                            return self:scroll_up()
                        end
                    end

                    return false
                end

                function HUDChat:scroll_up()
                    local output_panel = self._panel:child("output_panel")
                    local scroll_panel = output_panel:child("scroll_panel")

                    if output_panel:h() < scroll_panel:h() then
                        if scroll_panel:top() == 0 then
                            self._one_scroll_dn_delay = true
                        end

                        scroll_panel:set_top(math.min(0, scroll_panel:top() + ChatGui.line_height))

                        return true
                    end
                end

                function HUDChat:scroll_down()
                    local output_panel = self._panel:child("output_panel")
                    local scroll_panel = output_panel:child("scroll_panel")

                    if output_panel:h() < scroll_panel:h() then
                        if scroll_panel:bottom() == output_panel:h() then
                            self._one_scroll_up_delay = true
                        end

                        scroll_panel:set_bottom(math.max(scroll_panel:bottom() - ChatGui.line_height, output_panel:h()))

                        return true
                    end
                end
            end
        end

        Hooks:PostHook(
            HUDChat,
            "receive_message",
            "ChatTranslator_HUDChat_receive_message",
            function(self, name, message, color, icon)
                local line = nil
                if
                    ChatTranslator.settings.hud == ChatTranslator.HUD.DEFAULT or
                        ChatTranslator.settings.hud == ChatTranslator.HUD.VOIDUI
                 then
                    line = self._lines[#self._lines]
                else
                    line = self._messages[#self._messages]
                end

                local translatable_message = ChatTranslatorMessage:new(self, line, name, message, color, icon)

                if ChatTranslator.settings.auto_translate then
                    translatable_message:RequestTranslation(true)
                end

                table.insert(self._translatable_messages, translatable_message)
            end
        )

        Hooks:PostHook(
            HUDChat,
            "init",
            "ChatTranslator_HUDChat_init",
            function(self)
                self._chat_type = ChatTranslator.CHAT_TYPE.HUDCHAT
                self._translatable_messages = {}
            end
        )

        if HUDChat.mouse_moved then
            Hooks:PostHook(
                HUDChat,
                "mouse_moved",
                "ChatTranslator_HUDChat_mouse_moved",
                (ChatTranslator.settings.hud ~= ChatTranslator.HUD.VOIDUI) and ChatTranslator.mouse_moved or
                    function(self, _, x, y)
                        x =
                            x -
                            (managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel:w() -
                                self._hud_panel:w()) /
                                2
                        y =
                            y -
                            (managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel:h() -
                                self._hud_panel:h()) /
                                2
                        ChatTranslator.mouse_moved(self, x, y)
                    end
            )
        else
            HUDChat.mouse_moved = ChatTranslator.mouse_moved
        end

        if HUDChat.mouse_pressed then
            Hooks:PreHook(
                HUDChat,
                "mouse_pressed",
                "ChatTranslator_HUDChat_mouse_pressed",
                (ChatTranslator.settings.hud ~= ChatTranslator.HUD.VOIDUI) and ChatTranslator.mouse_pressed or
                    function(self, _, button, x, y)
                        x =
                            x -
                            (managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel:w() -
                                self._hud_panel:w()) /
                                2
                        y =
                            y -
                            (managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2).panel:h() -
                                self._hud_panel:h()) /
                                2
                        ChatTranslator.mouse_pressed(self, button, x, y)
                    end
            )
        else
            HUDChat.mouse_pressed = ChatTranslator.mouse_pressed
        end

        Hooks:PostHook(
            HUDChat,
            "_on_focus",
            "ChatTranslator_HUDChat__on_focus",
            function(self)
                if ChatTranslator.settings.mouse_pointer and not self._mouse_pointer_active then
                    local data = {
                        mouse_move = function(_, x, y)
                            return self:mouse_moved(managers.mouse_pointer:convert_mouse_pos(x, y))
                        end,
                        mouse_press = function(_, button, x, y)
                            return self:mouse_pressed(button, managers.mouse_pointer:convert_mouse_pos(x, y))
                        end,
                        mouse_release = function()
                        end,
                        mouse_click = function()
                        end,
                        mouse_double_click = function()
                        end,
                        id = "chat_translator_hudchat"
                    }
                    managers.mouse_pointer:use_mouse(data)
                    self._mouse_pointer_active = true
                end
            end
        )

        Hooks:PostHook(
            HUDChat,
            "_loose_focus",
            "ChatTranslator_HUDChat__loose_focus",
            function(self)
                if self._mouse_pointer_active then
                    managers.mouse_pointer:remove_mouse("chat_translator_hudchat")
                    self._mouse_pointer_active = false
                end
            end
        )

        Hooks:PostHook(
            HUDChat,
            "remove",
            "ChatTranslator_HUDChat_remove",
            function(self)
                if self._mouse_pointer_active then
                    managers.mouse_pointer:remove_mouse("chat_translator_hudchat")
                    self._mouse_pointer_active = false
                end
            end
        )
    elseif RequiredScript == "lib/managers/hudmanagerpd2" then
        Hooks:PreHook(
            HUDManager,
            "setup_endscreen_hud",
            "ChatTranslator_HUDManager_setup_endscreen_hud",
            function(self)
                if self._hud_chat_ingame._mouse_pointer_active then
                    managers.mouse_pointer:remove_mouse("chat_translator_hudchat")
                    self._hud_chat_ingame._mouse_pointer_active = false
                end
            end
        )
    elseif RequiredScript == "lib/managers/menumanager" then
        Hooks:Add(
            "LocalizationManagerPostInit",
            "ChatTranslator_LocalizationManagerPostInit",
            function(loc)
                for i = 1, #ChatTranslator.languages.name_ids do
                    loc:add_localized_strings(
                        {
                            [ChatTranslator.languages.name_ids[i]] = ChatTranslator.languages.names[i] ..
                                " (" .. ChatTranslator.languages.codes[i] .. ")"
                        }
                    )
                end

                for _, filename in pairs(file.GetFiles(ChatTranslator._mod_path .. "loc")) do
                    local language = filename:match("^(.*).json$")
                    if language and Idstring(language) and Idstring(language):key() == SystemInfo:language():key() then
                        loc:load_localization_file(ChatTranslator._mod_path .. "loc/" .. filename)
                        return
                    end
                end

                loc:load_localization_file(ChatTranslator._mod_path .. "loc/english.json")
            end
        )

        Hooks:Add(
            "MenuManagerSetupCustomMenus",
            "ChatTranslator_MenuManagerSetupCustomMenus",
            function(menu_manager, nodes)
                MenuHelper:NewMenu("chat_translator")
            end
        )
        
        Hooks:Add(
            "MenuManagerSetupCustomMenus",
            "ChatTranslatorAutoTranslateExcludes_MenuManagerSetupCustomMenus",
            function(menu_manager, nodes)
                MenuHelper:NewMenu("chat_translator_auto_translate_excludes")
            end
        )

        Hooks:Add(
            "MenuManagerPopulateCustomMenus",
            "ChatTranslator_MenuManagerPopulateCustomMenus",
            function(menu_manager, nodes)
                function MenuCallbackHandler:chat_translator_language_callback(item)
                    ChatTranslator.settings.language = ChatTranslator.languages.codes[item:value()]
                end

                function MenuCallbackHandler:chat_translator_hud_callback(item)
                    ChatTranslator.settings.hud = item:value()

                    ChatTranslator.UpdateButtons()
                end

                function MenuCallbackHandler:chat_translator_mouse_pointer_callback(item)
                    ChatTranslator.settings.mouse_pointer = (item:value() == "on")
                end

                function MenuCallbackHandler:chat_translator_extend_chat_callback(item)
                    ChatTranslator.settings.extend_chat = (item:value() == "on")
                end

                function MenuCallbackHandler:chat_translator_auto_translate_callback(item)
                    ChatTranslator.settings.auto_translate = (item:value() == "on")
                end

                function MenuCallbackHandler:chat_translator_back_callback(item)
                    ChatTranslator:CheckHUDCompatibility()
                    ChatTranslator:Save()
                end

                local language_index = nil
                for i, value in ipairs(ChatTranslator.languages.codes) do
                    if value == ChatTranslator.settings.language then
                        language_index = i
                    end
                end

                MenuHelper:AddMultipleChoice(
                    {
                        id = "chat_translator_language",
                        title = "chat_translator_language_title",
                        description = "chat_translator_language_desc",
                        callback = "chat_translator_language_callback",
                        items = ChatTranslator.languages.name_ids,
                        value = language_index or 1,
                        menu_id = "chat_translator",
                        priority = 6
                    }
                )

                MenuHelper:AddMultipleChoice(
                    {
                        id = "chat_translator_hud",
                        title = "chat_translator_hud_title",
                        description = "chat_translator_hud_desc",
                        callback = "chat_translator_hud_callback",
                        items = {
                            "chat_translator_hud_default",
                            "chat_translator_hud_wolfhud",
                            "chat_translator_hud_voidui",
                            "chat_translator_hud_vanillahud"
                        },
                        value = ChatTranslator.settings.hud,
                        menu_id = "chat_translator",
                        priority = 5
                    }
                )

                MenuHelper:AddDivider(
                    {
                        id = "chat_translator_divider_1",
                        size = 16,
                        menu_id = "chat_translator",
                        priority = 4
                    }
                )

                MenuHelper:AddToggle(
                    {
                        id = "chat_translator_mouse_pointer",
                        title = "chat_translator_mouse_pointer_title",
                        desc = "chat_translator_mouse_pointer_desc",
                        callback = "chat_translator_mouse_pointer_callback",
                        value = ChatTranslator.settings.mouse_pointer,
                        menu_id = "chat_translator",
                        priority = 3
                    }
                )

                MenuHelper:AddToggle(
                    {
                        id = "chat_translator_extend_chat",
                        title = "chat_translator_extend_chat_title",
                        desc = "chat_translator_extend_chat_desc",
                        callback = "chat_translator_extend_chat_callback",
                        value = ChatTranslator.settings.extend_chat,
                        menu_id = "chat_translator",
                        priority = 2
                    }
                )

                MenuHelper:AddToggle(
                    {
                        id = "chat_translator_auto_translate",
                        title = "chat_translator_auto_translate_title",
                        desc = "chat_translator_auto_translate_desc",
                        callback = "chat_translator_auto_translate_callback",
                        value = ChatTranslator.settings.auto_translate,
                        menu_id = "chat_translator",
                        priority = 1
                    }
                )

                ChatTranslator.UpdateButtons()
            end
        )

        Hooks:Add(
            "MenuManagerPopulateCustomMenus",
            "ChatTranslatorAutoTranslateExcludes_MenuManagerPopulateCustomMenus",
            function(menu_manager, nodes)
                function MenuCallbackHandler:chat_translator_auto_translate_excludes_callback(item)
                    local language = item:name():gsub("chat_translator_auto_translate_exclude_", "")
                    local is_on = (item:value() == "on")

                    -- find if the language is in the excludes list
                    local found = false
                    for i, value in ipairs(ChatTranslator.settings.auto_translate_excludes) do
                        if value == language then
                            found = true
                            break
                        end
                    end

                    if is_on and not found then
                        table.insert(ChatTranslator.settings.auto_translate_excludes, language)
                    elseif not is_on and found then
                        for i, value in ipairs(ChatTranslator.settings.auto_translate_excludes) do
                            if value == language then
                                table.remove(ChatTranslator.settings.auto_translate_excludes, i)
                                break
                            end
                        end
                    end
                end

                -- Auto translate excludes. List all languages with checkboxes.
                for i, lang_code in ipairs(ChatTranslator.languages.codes) do
                    MenuHelper:AddToggle(
                        {
                            id = "chat_translator_auto_translate_exclude_" .. lang_code,
                            title = ChatTranslator.languages.name_ids[i],
                            desc = "chat_translator_auto_translate_excludes_desc",
                            callback = "chat_translator_auto_translate_excludes_callback",
                            value = table.contains(ChatTranslator.settings.auto_translate_excludes, lang_code),
                            menu_id = "chat_translator_auto_translate_excludes",
                            priority = #ChatTranslator.languages.codes - i
                        }
                    )
                end
            end
        )


        Hooks:Add(
            "MenuManagerBuildCustomMenus",
            "ChatTranslator_MenuManagerBuildCustomMenus",
            function(menu_manager, nodes)
                nodes.chat_translator =
                    MenuHelper:BuildMenu("chat_translator", {back_callback = "chat_translator_back_callback"})
                MenuHelper:AddMenuItem(
                    nodes.blt_options,
                    "chat_translator",
                    "chat_translator_title",
                    "chat_translator_desc"
                )
            end
        )
        Hooks:Add(
            "MenuManagerBuildCustomMenus",
            "ChatTranslatorAutoTranslateExcludes_MenuManagerBuildCustomMenus",
            function(menu_manager, nodes)
                nodes.chat_translator_auto_translate_excludes =
                    MenuHelper:BuildMenu("chat_translator_auto_translate_excludes")
                MenuHelper:AddMenuItem(
                    nodes.chat_translator,
                    "chat_translator_auto_translate_excludes",
                    "chat_translator_auto_translate_excludes_title",
                    "chat_translator_auto_translate_excludes_desc"
                )
            end
        )
    end
end

ChatTranslator:Setup()
