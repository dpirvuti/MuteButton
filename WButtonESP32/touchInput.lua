local function init(self, padNum, onTouch, onUnTouch)
  self.padState = 0
  self.pad = padNum
  self.onTouchCB = onTouch
  self.onUnTouchCB = onUnTouch
  self.tp = touch.create({
    pad = padNum,
    cb = function (pads)
      if self.padState == 0 then
        self.padState = 1
        self.tp:setTriggerMode(touch.TOUCH_TRIGGER_ABOVE)
        if self.onTouchCB then  self.onTouchCB()  end
      else
        self.padState = 0
        self.tp:setTriggerMode(touch.TOUCH_TRIGGER_BELOW)
        if self.onUnTouchCB then self.onUnTouchCB() end
      end
    end,
    intrInitAtStart = false,
    thresTrigger = touch.TOUCH_TRIGGER_BELOW,
    lvolt = touch.TOUCH_LVOLT_0V5,
    hvolt = touch.TOUCH_HVOLT_2V7,
    atten = touch.TOUCH_HVOLT_ATTEN_1V
  })
end

local function stop(self)
    self.tp:intrDisable()
   -- missing tp:unregister from meta array
    self.tp:__gc()
end

local function config(self )
  local raw = self.tp:read()
  -- set threshold to 20% of baseline read state
  local thres = raw[self.pad] - math.floor(raw[self.pad] * 0.2)
  self.tp:setThres(self.pad, thres)
  print("Touch pad is at " .. raw[self.pad] .. " when not touched")
  print("Will trigger at thres: " .. thres)
  self.tp:intrEnable()
end

return {
    ['new'] = function()
      return {  ['init'] = init ; ['config'] = config ; ['stop'] = stop }
     end
  }
