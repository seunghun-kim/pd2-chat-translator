ChatTranslator = ChatTranslator or {}
ChatTranslator._target_language = "en"

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

function ChatTranslator.ApplyTranslation(lines, index, scroll_panel, language, message)
    if not lines or not index or not scroll_panel or not language or not message then
        return
    end

    local line_element = lines[index]
    local line = line_element[1]
    local line_bg = line_element[2]
    local name = line_element[4]
    local color = line_element[6]

    local len = utf8.len(name .. " (from " .. language .. ")") + 1

    line:set_text(name .. " (from " .. language .. "): " .. message)

    local total_len = utf8.len(line:text())

    line:set_range_color(0, len, color)
    line:set_range_color(len, total_len, Color.white)

    line:set_w(scroll_panel:w() - line:left())

    local _, _, w, h = line:text_rect()

    line:set_h(h)
    line_bg:set_w(w + line:left() + 2)
    line_bg:set_h(ChatGui.line_height * line:number_of_lines())
end

function ChatTranslator.RequestTranslation(lines, index, scroll_panel, message)
    local url_encoded_message = ChatTranslator.EncodeUrl(message)
    if not url_encoded_message then
        return
    end

    local url =
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" ..
        ChatTranslator._target_language .. "&dt=t&q=" .. url_encoded_message

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
            if not source_language or source_language == ChatTranslator._target_language then
                return
            end

            local translated_message = tostring(decoded_data[1][1][1])
            if not translated_message then
                return
            end

            ChatTranslator.ApplyTranslation(lines, index, scroll_panel, source_language, translated_message)
        end
    )
end

function ChatTranslator.Hooks()
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
            table.insert(
                self._lines,
                {
                    line,
                    line_bg,
                    icon_bitmap,
                    name,
                    message,
                    color,
                    translated = false
                }
            )
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
                    local translated = self._lines[i][7]

                    if not translated and line_bg:inside(x, y) then
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
                        local translated = self._lines[i][7]

                        if not translated and line_bg:inside(x, y) then
                            ChatTranslator.RequestTranslation(self._lines, i, output_panel, message)
                            self._lines[i][7] = true
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
    end
end

ChatTranslator.Hooks()
