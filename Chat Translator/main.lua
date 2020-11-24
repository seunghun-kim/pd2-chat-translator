ChatTranslator = ChatTranslator or {}
ChatTranslator.default_settings = {
    language = "en",
    keyword = "tl",
    mouse_pointer = true
}

ChatTranslator._mod_path = ModPath
ChatTranslator._languages_file = ChatTranslator._mod_path .. "languages.json"
ChatTranslator._save_path = SavePath
ChatTranslator._save_file = ChatTranslator._save_path .. "chat_translator.json"

function ChatTranslator:Setup()
    if not self.settings then
        self:Load()
        self.LoadLanguages()
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

function ChatTranslator.ApplyTranslation(line_data, panel, language, message)
    line_data[8] = true
    line_data[10] = language
    line_data[11] = message

    ChatTranslator.ToggleTranslation(line_data, panel)
end

function ChatTranslator.ToggleTranslation(line_data, panel)
    local line = line_data[1]
    local line_bg = line_data[2]
    local name = line_data[4]
    local message = line_data[5]
    local color = line_data[6]
    local translated = line_data[8]
    local language = line_data[10]
    local translated_message = line_data[11]

    if not translated then
        return
    end

    line_data[9] = not line_data[9]
    local show_translation = line_data[9]

    local displayed_name = nil
    local displayed_message = nil
    if show_translation then
        displayed_name = name .. " (" .. language .. ")"
        displayed_message = translated_message
    else
        displayed_name = name
        displayed_message = message
    end

    local len = utf8.len(displayed_name) + 1
    line:set_text(displayed_name .. ": " .. displayed_message)

    local total_len = utf8.len(line:text())

    line:set_range_color(0, len, color)
    line:set_range_color(len, total_len, Color.white)

    line:set_w(panel:w() - line:left())

    local _, _, w, h = line:text_rect()

    line:set_h(h)
    line_bg:set_w(w + line:left() + 2)
    line_bg:set_h(ChatGui.line_height * line:number_of_lines())
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

            callback(translated_message, source_language, language)
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
            function(message)
                return ChatTranslator._ChatManager_send_message(object, channel_id, sender, message)
            end
        )
    end
    return true
end

function ChatTranslator.SetupHooks()
    if RequiredScript == "lib/managers/chatmanager" then
        function ChatGui:receive_message(name, message, color, icon)
            if not alive(self._panel) or not managers.network:session() then
                return
            end

            local output_panel = self._panel:child("output_panel")
            local scroll_panel = output_panel:child("scroll_panel")
            local local_peer = managers.network:session():local_peer()
            local peers = managers.network:session():peers()
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
                    color = Color.black:with_alpha(0.5)
                }
            )

            line_bg:set_h(h)
            line:set_kern(line:kern())
            local line_data = {
                line,
                line_bg,
                icon_bitmap,
                name,
                message,
                color,
                translation_requested = false,
                translated = false,
                show_translation = false,
                language = nil,
                translated_message = nil
            }
            table.insert(self._lines, line_data)
            self:_layout_output_panel()

            if not self._focus then
                output_panel:stop()
                output_panel:animate(callback(self, self, "_animate_show_component"), output_panel:alpha())
                output_panel:animate(callback(self, self, "_animate_fade_output"))
                self:start_notify_new_message()
            end
        end

        function ChatGui:mouse_moved(x, y)
            if not self._enabled then
                return false, false
            end

            if self:moved_scroll_bar(x, y) then
                return true, "grab"
            end

            local chat_button_panel = self._hud_panel:child("chat_button_panel")

            if chat_button_panel and chat_button_panel:visible() then
                local chat_button = chat_button_panel:child("chat_button")

                if chat_button:inside(x, y) then
                    if not self._chat_button_highlight then
                        self._chat_button_highlight = true

                        managers.menu_component:post_event("highlight")
                        chat_button:set_color(tweak_data.screen_colors.button_stage_2)
                    end

                    return true, "link"
                elseif self._chat_button_highlight then
                    self._chat_button_highlight = false

                    chat_button:set_color(tweak_data.screen_colors.button_stage_3)
                end
            end

            if self._is_crimenet_chat and not self._crimenet_chat_state then
                return false, false
            end

            local inside = self._input_panel:inside(x, y)

            self._input_panel:child("focus_indicator"):set_visible(inside or self._focus)

            if self._panel:child("scroll_bar"):visible() and self._panel:child("scroll_bar"):inside(x, y) then
                return true, "hand"
            elseif
                self._panel:child("scroll_down_indicator_arrow"):visible() and
                    self._panel:child("scroll_down_indicator_arrow"):inside(x, y) or
                    self._panel:child("scroll_up_indicator_arrow"):visible() and
                        self._panel:child("scroll_up_indicator_arrow"):inside(x, y)
             then
                return true, "link"
            end

            if self._focus then
                inside = not inside
            end

            if self._panel:child("output_panel"):inside(x, y) then
                for i = #self._lines, 1, -1 do
                    local line_bg = self._lines[i][2]

                    if line_bg:inside(x, y) then
                        return true, "link"
                    end
                end
            end

            return inside or self._focus, inside and "link" or "arrow"
        end

        function ChatGui:mouse_pressed(button, x, y)
            if not self._enabled then
                return
            end

            local chat_button_panel = self._hud_panel:child("chat_button_panel")

            if button == Idstring("0") and chat_button_panel and chat_button_panel:visible() then
                local chat_button = chat_button_panel:child("chat_button")

                if chat_button:inside(x, y) then
                    self:toggle_crimenet_chat()

                    return true
                end
            end

            if self._is_crimenet_chat and not self._crimenet_chat_state then
                return false, false
            end

            local inside = self._input_panel:inside(x, y)

            if inside then
                self:_on_focus()

                return true
            end

            local output_panel = self._panel:child("output_panel")
            if output_panel:inside(x, y) then
                if button == Idstring("mouse wheel down") then
                    if self:mouse_wheel_down(x, y) then
                        self:set_scroll_indicators()
                        self:_on_focus()

                        return true
                    end
                elseif button == Idstring("mouse wheel up") then
                    if self:mouse_wheel_up(x, y) then
                        self:set_scroll_indicators()
                        self:_on_focus()

                        return true
                    end
                elseif button == Idstring("0") and self:check_grab_scroll_panel(x, y) then
                    self:set_scroll_indicators()
                    self:_on_focus()

                    return true
                elseif button == Idstring("0") then
                    self:_on_focus()
                    for i = #self._lines, 1, -1 do
                        local line_bg = self._lines[i][2]
                        local message = self._lines[i][5]
                        local translation_requested = self._lines[i][7]
                        local translated = self._lines[i][8]

                        if line_bg:inside(x, y) then
                            if not translation_requested and not translated then
                                ChatTranslator.RequestTranslation(
                                    ChatTranslator.settings.language,
                                    message,
                                    function(message, language, source_language)
                                        if language ~= source_language then
                                            return ChatTranslator.ApplyTranslation(
                                                self._lines[i],
                                                output_panel,
                                                language,
                                                message
                                            )
                                        end
                                    end
                                )
                                self._lines[i][7] = true
                            elseif translated then
                                ChatTranslator.ToggleTranslation(self._lines[i], output_panel)
                            end
                            return true
                        end
                    end

                    return true
                end
            elseif button == Idstring("0") and self:check_grab_scroll_bar(x, y) then
                self:set_scroll_indicators()
                self:_on_focus()

                return true
            end

            return self:_loose_focus()
        end

        ChatTranslator._ChatManager_send_message = ChatManager.send_message
        function ChatManager:send_message(channel_id, sender, message)
            if not ChatTranslator.ProcessInput(self, channel_id, sender, message) then
                ChatTranslator._ChatManager_send_message(self, channel_id, sender, message)
            end
        end
    elseif RequiredScript == "lib/managers/hud/hudchat" then
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
                icon_bitmap,
                name,
                message,
                color,
                translation_requested = false,
                translated = false,
                show_translation = false,
                language = nil,
                translated_message = nil
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

        function HUDChat:mouse_moved(x, y)
            local output_panel = self._panel:child("output_panel")
            if output_panel:inside(x, y) then
                for i = #self._lines, 1, -1 do
                    local line_bg = self._lines[i][2]

                    if line_bg:inside(x, y) then
                        managers.mouse_pointer:set_pointer_image("link")
                        return
                    end
                end
            end

            managers.mouse_pointer:set_pointer_image("arrow")
        end

        function HUDChat:mouse_pressed(button, x, y)
            local output_panel = self._panel:child("output_panel")
            if output_panel:inside(x, y) then
                if button == Idstring("0") then
                    for i = #self._lines, 1, -1 do
                        local line_bg = self._lines[i][2]
                        local message = self._lines[i][5]
                        local translation_requested = self._lines[i][7]
                        local translated = self._lines[i][8]
                        local bottom = line_bg:bottom() + output_panel:bottom() + 112
                        local top = line_bg:top() + output_panel:bottom() + 112

                        if line_bg:inside(x, y) then
                            if not translation_requested and not translated then
                                ChatTranslator.RequestTranslation(
                                    ChatTranslator.settings.language,
                                    message,
                                    function(message, language, source_language)
                                        if language ~= source_language then
                                            return ChatTranslator.ApplyTranslation(
                                                self._lines[i],
                                                output_panel,
                                                language,
                                                message
                                            )
                                        end
                                    end
                                )
                                self._lines[i][7] = true
                            elseif translated then
                                ChatTranslator.ToggleTranslation(self._lines[i], output_panel)
                            end
                            return true
                        end
                    end
                elseif button == Idstring("mouse wheel down") then
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

        Hooks:PostHook(
            HUDChat,
            "_on_focus",
            "ChatTranslator_HUDChat__on_focus",
            function(self)
                if ChatTranslator.settings.mouse_pointer then
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
                        id = "hudchat"
                    }
                    managers.mouse_pointer:use_mouse(data)
                end
            end
        )

        Hooks:PostHook(
            HUDChat,
            "_loose_focus",
            "ChatTranslator_HUDChat__loose_focus",
            function()
                managers.mouse_pointer:remove_mouse("hudchat")
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
                            [ChatTranslator.languages.name_ids[i]] = ChatTranslator.languages.names[i]
                        }
                    )
                end
                loc:load_localization_file(ChatTranslator._mod_path .. "loc/english.txt")
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
            "MenuManagerPopulateCustomMenus",
            "ChatTranslator_MenuManagerPopulateCustomMenus",
            function(menu_manager, nodes)
                function MenuCallbackHandler:chat_translator_language_callback(item)
                    ChatTranslator.settings.language = ChatTranslator.languages.codes[item:value()]
                end

                function MenuCallbackHandler:chat_translator_mouse_pointer_callback(item)
                    ChatTranslator.settings.mouse_pointer = (item:value() == "on")
                end

                function MenuCallbackHandler:chat_translator_back_callback(item)
                    ChatTranslator:Save()
                end

                function MenuCallbackHandler:chat_translator_default_callback(item)
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
                        priority = 2
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
                        priority = 1
                    }
                )
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
    end
end

ChatTranslator:Setup()
