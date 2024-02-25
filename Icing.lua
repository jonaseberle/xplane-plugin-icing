--[[
    Show and control aircraft ice accretion

    It's also a little oppinionated example how one can use a public callback without polluting the global
    namespace in FlyWithLua.

    Author: flightwusel
    License: use for anything. Acknowledge me if you feel like it.
]]

local const = {
    colors = {
        default = 0xFF6F4725,
        text = 0xFFFFFFFF,
        warning = 0xffaaccff,
        danger = 0xff6666ff,
    },
}
local settings_wnd = nil

-- some boilerplate code for "global objects"
local scriptName = debug.getinfo(1, 'S').source:match('([^/\\]*)[.]lua$')
local currentObjectId
local function beginObjectId()
    -- that's the file name plus the caller's line number.
    currentObjectId = scriptName .. '_' .. debug.getinfo(2, 'l').currentline
    return currentObjectId
end

-- example for a pseudo "class" only needed locally
local function Log()
    local function dump(o, indentLevel)
        local indentLevel = indentLevel or 0
        local indentTablesSpaces = 2
        if type(o) == 'table' then
            local s = string.rep(' ', indentLevel * indentTablesSpaces) .. '{ \n'
            for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"' .. k .. '"' end
                s = s .. string.rep(' ', (indentLevel + 1)  * indentTablesSpaces) .. k .. ': ' .. dump(v, indentLevel + 1) .. '\n'
            end
            return s .. string.rep(' ', indentLevel * indentTablesSpaces) .. '} '
        else
            return tostring(o)
        end
    end

    local function msg(msg, level)
        local msg = msg or ''
        local level = level or ''
        local debugInfo = debug.getinfo(2, 'Snl') -- caller context
        local line = debugInfo.currentline
        local filePath = debugInfo.source
        local fileName = filePath:match('[^/\\]*[.]lua$')
        local functionName = debugInfo.name
        logMsg(
            string.format(
                '%s+%d%s%s %s',
                fileName,
                line,
                functionName and ':' .. functionName .. '()' or '',
                level,
                dump(msg)
            )
        )
    end

    return {
        -- exposed ("public") methods:
        msg = msg,
        err = function(errMsg)
            msg(errMsg, '[ERROR] ')
        end,
    }
end

local function addMacroAndCommand(cmdRef, title, eval)
    Log().msg(
        string.format(
            "Adding macro '%s' (cmdRef '%s')",
            title,
            cmdRef
        )
    )
    create_command(cmdRef, title, eval, '', '')
    add_macro(title, eval)
end


local function pairsAlphabetical(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end

-- example for a global "object" that exposes a public method:
_G[beginObjectId()] = ( -- that works as a one-liner because table.insert(table, key, value) evaluates ‹key› before ‹value›.
    -- pseudo "class"
    function(log)
        if not SUPPORTS_FLOATING_WINDOWS then
            -- to make sure the script doesn't stop old FlyWithLua versions
            log.err('imgui not supported by your FlyWithLua version')
            return
        end

        local _values = {}

        local isKeepDeiced = false
        local isClamp = true

        -- ‹currentObjectId› is what you expect it to be here. If you need it in functions called later,
        -- copy it into a local variable:
        local thisId = currentObjectId

        addMacroAndCommand(
            scriptName .. '/ToggleSettings',
            scriptName .. ': Toggle settings window',
            thisId .. '.toggleSettingsWindow()'
        )
        do_often(thisId .. '.doOften()')

        local function valColor(val)
            return val < 3. and const.colors.text
                or val < 10. and const.colors.warning
                or const.colors.danger
        end

        local function _numProps()
            local i
            for i = 0, 15, 1 do
                if get('sim/aircraft/prop/acf_prop_type', i) == 0 then
                    return i
                end
            end
            return 16
        end
        local numProps = _numProps()
        local numEngines = get('sim/aircraft/engine/acf_num_engines')

        local dataRefs = {
            ['sim/flightmodel/failures/stat_ice'] = { ['type'] = 'f', ['desc'] = 'static port - pilot side' },
            ['sim/flightmodel/failures/stat_ice2'] = { ['type'] = 'f', ['desc'] = 'static port - copilot side' },
            ['sim/flightmodel/failures/stat_ice_stby'] = { ['type'] = 'f', ['desc'] = 'static port - standby instruments' },
            ['sim/flightmodel/failures/pitot_ice'] = { ['type'] = 'f', ['desc'] = 'pitot tube - pilot' },
            ['sim/flightmodel/failures/pitot_ice2'] = { ['type'] = 'f', ['desc'] = 'pitot tube - copilot' },
            ['sim/flightmodel/failures/pitot_ice_stby'] = { ['type'] = 'f', ['desc'] = 'pitot tube - standby instruments' },
            ['sim/flightmodel/failures/aoa_ice'] = { ['type'] = 'f', ['desc'] = 'AoA – pilot' },
            ['sim/flightmodel/failures/aoa_ice2'] = { ['type'] = 'f', ['desc'] = 'AoA – copilot' },
            ['sim/flightmodel/failures/frm_ice'] = { ['type'] = 'f', ['desc'] = 'wings/airframe - left wing' },
            ['sim/flightmodel/failures/frm_ice2'] = { ['type'] = 'f', ['desc'] = 'wings/airframe - right wing' },
            ['sim/flightmodel/failures/tail_ice'] = { ['type'] = 'f', ['desc'] = 'tailplane (hstab and vstab) - left side' },
            ['sim/flightmodel/failures/tail_ice2'] = { ['type'] = 'f', ['desc'] = 'tailplane (hstab and vstab) - right side' },
            --['sim/flightmodel/failures/inlet_ice'] = { ['type'] = 'f', ['desc'] = 'air inlets - first engine' },
            ['sim/flightmodel/failures/inlet_ice_per_engine'] = { ['type'] = 'vf', ['size'] = numEngines, ['desc'] = 'air inlets' },
            --['sim/flightmodel/failures/prop_ice'] = { ['type'] = 'f', ['desc'] = 'prop - first prop' },
            ['sim/flightmodel/failures/prop_ice_per_engine'] = { ['type'] = 'vf', ['size'] = numProps, ['desc'] = 'props' },
            --['sim/flightmodel/failures/window_ice'] = { ['type'] = 'f', ['desc'] = 'pilot windshield' },
            ['sim/flightmodel/failures/window_ice_per_window'] = { ['type'] = 'vf', ['size'] = 4, ['desc'] = 'windshields and side windows' },
        }
        local showDataRefs = {
            'sim/flightmodel/failures/stat_ice',
            'sim/flightmodel/failures/stat_ice2',
            'sim/flightmodel/failures/stat_ice_stby',
            'sim/flightmodel/failures/pitot_ice',
            'sim/flightmodel/failures/pitot_ice2',
            'sim/flightmodel/failures/pitot_ice_stby',
            'sim/flightmodel/failures/aoa_ice',
            'sim/flightmodel/failures/aoa_ice2',
            'sim/flightmodel/failures/frm_ice',
            'sim/flightmodel/failures/frm_ice2',
            'sim/flightmodel/failures/tail_ice',
            'sim/flightmodel/failures/tail_ice2',
            'sim/flightmodel/failures/inlet_ice_per_engine',
            'sim/flightmodel/failures/prop_ice_per_engine',
            'sim/flightmodel/failures/window_ice_per_window',
        }

        -- ImGui callback functions need to be plain function name strings and can't be in a table ?!
        _G[thisId .. '_imgui_builder_callback'] = function(wnd, x, y)
            -- imGui
            -- https://pixtur.github.io/mkdocs-for-imgui/site/api-imgui/ImGui--Dear-ImGui-end-user/
            -- Lua Bindings https://github.com/X-Friese/FlyWithLua/blob/master/src/imgui/imgui_iterator.inl

            if imgui.Checkbox('Keep deiced', isKeepDeiced) then
                isKeepDeiced = not isKeepDeiced
            end

            if not isKeepDeiced and imgui.Checkbox('Clamp to < 100%', isClamp) then
                isClamp = not isClamp
            end

            imgui.PushItemWidth(-1.)
            imgui.PushTextWrapPos(imgui.GetWindowWidth() - 24)
            local changed
            local newVal
            local frame_rate_period = get('sim/operation/misc/frame_rate_period')
            for _, dataRef in ipairs(showDataRefs) do
                local dataRefConfig = dataRefs[dataRef]
                imgui.TextUnformatted(dataRefConfig.desc)
                if dataRefConfig.type == 'f' then
                    local val = get(dataRef) * 100.
                    local change_perS = (val - (_values[dataRef] or 0)) / frame_rate_period
                    imgui.PushStyleColor(imgui.constant.Col.Text, valColor(val))
                    changed, newVal = imgui.SliderFloat(
                        '##' .. dataRef,
                        val,
                        0.,
                        120.,
                        val > 0. and '%.2f %% ' .. (change_perS ~= 0 and string.format('(%+.2f %%%%/s)', change_perS) or '') or ''
                    )
                    imgui.PopStyleColor()
                    if changed then
                        set(dataRef, newVal / 100.)
                    end
                    _values[dataRef] = val
                elseif dataRefConfig.type == 'vf' then
                    for i = 0, dataRefConfig.size - 1, 1 do
                        local val = get(dataRef, i) * 100.
                        local change_perS = (val - (_values[dataRef .. i] or 0)) / frame_rate_period
                        imgui.PushStyleColor(imgui.constant.Col.Text, valColor(val))
                        changed, newVal = imgui.SliderFloat(
                            '##' .. dataRef .. i,
                            val,
                            0.,
                            120.,
                            val > 0. and '%.2f %% ' .. (change_perS ~= 0 and string.format('(%+.2f %%%%/s)', change_perS) or '') or ''
                        )
                        imgui.PopStyleColor()
                        if changed then
                            set_array(dataRef, i, newVal / 100.)
                        end
                        _values[dataRef .. i] = val
                    end
                end
            end
            imgui.PopTextWrapPos()
            imgui.PopItemWidth()
        end

        -- ImGui callback functions need to be plain function name strings and can't be in a table ?!
        _G[thisId .. '_imgui_close_callback'] = function()
            settings_wnd = nil
        end

        return {
            -- exposed ("public") methods:
            toggleSettingsWindow = function()
                if settings_wnd ~= nil then
                    float_wnd_destroy(settings_wnd)
                    return
                end

                settings_wnd = float_wnd_create(230, 830, 1, true)
                float_wnd_set_onclose(settings_wnd, thisId .. '_imgui_close_callback')
                float_wnd_set_title(settings_wnd, scriptName)
                float_wnd_set_imgui_builder(settings_wnd, thisId .. '_imgui_builder_callback')
            end,
            doOften = function()
                if isKeepDeiced then
                    for dataRef, dataRefConfig in pairs(dataRefs) do
                        if dataRefConfig.type == 'f' then
                            set(dataRef, 0.)
                        elseif dataRefConfig.type == 'vf' then
                            local i
                            for i = 0, dataRefConfig.size - 1, 1 do
                                set_array(dataRef, i, 0.)
                            end
                        end
                    end
                elseif isClamp then
                    for dataRef, dataRefConfig in pairs(dataRefs) do
                        if dataRefConfig.type == 'f' then
                            if get(dataRef) > 1. then
                                set(dataRef, 1.)
                            end
                        elseif dataRefConfig.type == 'vf' then
                            for i = 0, dataRefConfig.size - 1, 1 do
                                if get(dataRef, i) > 1. then
                                    set_array(dataRef, i, 1.)
                                end
                            end
                        end
                    end
                end
            end,
        }
    end
)(
    -- "constructor-injecting" a dependency. Just for style.
    Log()
)

