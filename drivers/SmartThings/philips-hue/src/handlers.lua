local cosock = require "cosock"
local Fields = require "hue.fields"
local HueApi = require "hue.api"
local log = require "log"

local capabilities = require "st.capabilities"
local utils = require "st.utils"

local handlers = {}

---@param driver HueDriver
---@param device HueDevice
local function do_switch_action(driver, device, args)
  local on = args.command == "on"
  local id = device:get_field(Fields.PARENT_DEVICE_ID)
  local bridge_device = driver:get_device_info(id)

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with DNI " .. device.device_network_id)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local resp, err = hue_api:set_light_on_state(light_id, on)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing on/off action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueDevice
local function do_switch_level_action(driver, device, args)
  local level = args.args.level
  local bridge_device = driver:get_device_info(device:get_field(Fields.PARENT_DEVICE_ID))

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with DNI " .. device.device_network_id)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local min_dim = (device:get_field(Fields.MIN_DIMMING) or 2.0)
  local resp, err = hue_api:set_light_level(light_id, level, min_dim)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing switch level action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueDevice
local function do_color_action(driver, device, args)
  local hue, sat = args.args.color.hue, args.args.color.saturation
  local bridge_device = driver:get_device_info(device:get_field(Fields.PARENT_DEVICE_ID))

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with DNI " .. device.device_network_id)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local x, y, _ = utils.safe_hsv_to_xy(hue, sat)

  x = x / 65536 -- safe_hsv_to_xy uses values from 0x0000 to 0xFFFF, Hue wants [0, 1]
  y = y / 65536 -- safe_hsv_to_xy uses values from 0x0000 to 0xFFFF, Hue wants [0, 1]

  local resp, err = hue_api:set_light_color_xy(light_id, { x = x, y = y })

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing color action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

function handlers.kelvin_to_mirek(kelvin) return 1000000 / kelvin end

function handlers.mirek_to_kelvin(mirek) return 1000000 / mirek end

---@param driver HueDriver
---@param device HueDevice
local function do_color_temp_action(driver, device, args)
  local kelvin = args.args.temperature
  local bridge_device = driver:get_device_info(device:get_field(Fields.PARENT_DEVICE_ID))

  if not bridge_device then
    log.warn("Couldn't get a bridge for light with DNI " .. device.device_network_id)
    return
  end

  local light_id = device:get_field(Fields.RESOURCE_ID)
  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)

  if not (light_id or hue_api) then
    log.warn("Could not get a proper light resource ID or API instance for ", device.label)
    return
  end

  local clamped_kelvin = utils.clamp_value(
    kelvin, HueApi.MIN_TEMP_KELVIN, HueApi.MAX_TEMP_KELVIN
  )
  local mirek = math.floor(handlers.kelvin_to_mirek(clamped_kelvin))

  local resp, err = hue_api:set_light_color_temp(light_id, mirek)

  if not resp or (resp.errors and #resp.errors == 0) then
    if err ~= nil then
      log.error("Error performing color temp action: " .. err)
    elseif resp and #resp.errors > 0 then
      for _, error in ipairs(resp.errors) do
        log.error("Error returned in Hue response: " .. error.description)
      end
    end
  end
end

---@param driver HueDriver
---@param device HueDevice
function handlers.switch_on_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueDevice
function handlers.switch_off_handler(driver, device, args)
  do_switch_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueDevice
function handlers.switch_level_handler(driver, device, args)
  do_switch_level_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueDevice
function handlers.set_color_handler(driver, device, args)
  do_color_action(driver, device, args)
end

---@param driver HueDriver
---@param device HueDevice
function handlers.set_color_temp_handler(driver, device, args)
  do_color_temp_action(driver, device, args)
end

---@param driver HueDriver
---@param light_device HueDevice
local function do_refresh_light(driver, light_device)
  local light_resource_id = light_device:get_field(Fields.RESOURCE_ID)
  local bridge_device = driver:get_device_info(light_device:get_field(Fields.PARENT_DEVICE_ID))

  if not bridge_device then
    log.warn("Couldn't get Hue bridge for light " .. light_device.label)
    return
  end

  if not bridge_device:get_field(Fields._INIT) then
    log.warn("Bridge for light not yet initialized, can't refresh yet.")
    driver._lights_pending_refresh[light_device.id] = light_device
    return
  end

  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)
  local success = false
  local count = 0
  local num_attempts = 3
  repeat
    local light_resp, err = hue_api:get_light_by_id(light_resource_id)
    count = count + 1
    if err ~= nil then
      log.error(err)
    elseif light_resp ~= nil then
      if #light_resp.errors > 0 then
        for _, err in ipairs(light_resp.errors) do
          log.error("Error in Hue API response: " .. err.description)
        end
      else
        for _, light_info in ipairs(light_resp.data) do
          if light_info.id == light_resource_id then
            driver.emit_light_status_events(light_device, light_info)
            success = true
          end
        end
      end
    end
  until success or count >= num_attempts
end

---@param driver HueDriver
---@param bridge_device HueDevice
local function do_refresh_all_for_bridge(driver, bridge_device)
  local child_devices = bridge_device:get_child_list() --[=[@as HueDevice[]]=]
  for _, device in ipairs(child_devices) do
    local device_type = device:get_field(Fields.DEVICE_TYPE)
    if device_type == "light" then
      do_refresh_light(driver, device)
    end
  end
end

---@param driver HueDriver
---@param device HueDevice
function handlers.refresh_handler(driver, device, cmd)
  if device:get_field(Fields.DEVICE_TYPE) == "bridge" then
    do_refresh_all_for_bridge(driver, device)
  elseif device:get_field(Fields.DEVICE_TYPE) == "light" then
    do_refresh_light(driver, device)
  end
end

return handlers
