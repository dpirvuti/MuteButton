startupPeriod=5000
blinkLEDgpio=2
startupBlinkPeriod=200

touchPad=3
swSensorPin=12
ledPin=13

wifiConfigurationSSID='WS_'..node.chipid()
wifiConfigurationPWD='12345678'
scanPeriod=5000


state=0
--[[
   0 before init
   10 boot delay
   20 configure
   30 running
]]
touchInput=nil
startupTmr=nil
wifiConfiguration=nil
wifiRunning=nil
sms=nil

udpSocket={}
mcastPort=1
mcastAddress="0.0.0.0"


failedRPCBlinkCount=0
failedRPCBlink = tmr.create()
failedRPCBlink:register(200, tmr.ALARM_AUTO,
    function (t)
        failedRPCBlinkCount= failedRPCBlinkCount +1
        gpio.write(ledPin, failedRPCBlinkCount%2)
    end)

rpcTimeoutTimer = tmr.create()
rpcTimeoutTimer:register(5000,tmr.ALARM_SEMI,
    function (t)
        local running, mode = failedRPCBlink:state()
        if running ==true then
            failedRPCBlink:stop()
        end
        failedRPCBlink:start()
    end)



function onTouch()
    print("pad touched")
    touchInput:stop()
    touchInput=nil
    if state == 10 then
        exitBootDelay()
        enterConfiguration()
    end
end

function initTouch()
    touchInput = (require "touchInput").new()
    touchInput:init(touchPad, onTouch)
    touchInput:config()
end

function enterBootDelay()
    state = 10
    initTouch()
    gpio.config({gpio=blinkLEDgpio,dir=gpio.OUT})
    crtTickCount = 0
    startupTmr = tmr.create()
    startupTmr:register(startupBlinkPeriod, tmr.ALARM_AUTO,
        function (t)
            crtTickCount = crtTickCount +1
            gpio.write(blinkLEDgpio,crtTickCount %2)
            if startupBlinkPeriod * crtTickCount > startupPeriod then
                wifiConfiguration = (require "wifiConfiguration").new()
                local config = wifiConfiguration:readConfiguration()
                exitBootDelay()
                if config ~=nil and config.ssid ~=nil  and config.pswd ~=nil then
                    enterRunning(config)
                else
                    enterConfiguration()
                end
            end
        end)
    startupTmr:start()
end

function exitBootDelay()
    if startupTmr ~= nil then
        startupTmr:unregister()
        startupTmr = nil
    end
end

function enterConfiguration()
    state = 20
    print("Entering configuration mode")
    gpio.write(blinkLEDgpio,1)

    wifiConfiguration = (require "wifiConfiguration").new()
    wifiConfiguration:start(wifiConfigurationSSID, wifiConfigurationPWD, scanPeriod)
    print('Clearing configuration')
    -- wifiConfiguration:clearConfiguration()
end

function exitConfiguration()
    wifiConfiguration:stop()
end

function rpc(cmd)
    local status, err =  pcall (function ()
        -- init mcast
        net.multicastLeave("any",mcastAddress)
        net.multicastJoin("any",mcastAddress)
        --start/restart timer
        local running, mode  = rpcTimeoutTimer:state()
        print('120', running, mode)
        if running == true then
            rpcTimeoutTimer:stop()
        end
        rpcTimeoutTimer:start()

        udpSocket:send(mcastPort, mcastAddress , '{"nodeId":"'.. node.chipid()..'", "cmd":"'..cmd..'"}')
        print('on request sent complete')
    end)
    if not status then
        print("RPC error:", status, err)
        -- todo: handle 'not connected'
    end
end


function enterRunning(config)
    state=30
    print("Entering run mode")
    gpio.write(blinkLEDgpio,0)

    gpio.config({ gpio=swSensorPin, dir=gpio.IN, pull=gpio.PULL_UP },
            { gpio={ledPin}, dir=gpio.OUT});

    mcastPort=tonumber(config.port)
    mcastAddress=config.address

    print("MCAST:" .. tostring(mcastAddress) .. ":" ..tostring(mcastPort))
    --start switch monitoring
    gpio.trig(swSensorPin, gpio.INTR_DOWN , function(pin, level)
        print("swSensorPin triggered - ".. tostring(level))
        crtTime,highCrtTime = node.uptime();
        swActivationTime = (crtTime/1000) + highCrtTime*60*35*1000
        print(swActivationTime - lastSwActivationTime)
        if level == 0 and math.abs(swActivationTime - lastSwActivationTime) > 200  then
            --send toggle
            rpc("toggle")
            print('trigger sent')
        end
        lastSwActivationTime = swActivationTime
    end)


    wifiRunning = (require "wifiRunning").new()
    startWifi(config.ssid, config.pswd)



end

crtTime, highCrtTime =node.uptime();
lastSwActivationTime = (crtTime/1000) + highCrtTime*60*35*1000




function startWifi(ssid, pswd)

    wifiRunning:start(ssid, pswd,
        function(ip,netmask, gw )
            print('on activate:', ip)
            wifiConfiguration = nil

            net.multicastJoin("any",mcastAddress)
            local status, err =  pcall (function ()
                -- init mcast
                udpSocket = net.createUDPSocket()
                udpSocket:listen(mcastPort,'0.0.0.0')
                udpSocket:on("receive", function(s, data, port, ip)
                    print(string.format("received '%s' from %s:%d", data, ip, port), s)

                    local running, mode = failedRPCBlink:state()
                    print('192', running, mode)
                    if running == true then
                        failedRPCBlink:stop()
                    end
                    running, mode = rpcTimeoutTimer:state()
                    print('197', running, mode)
                    if running == true then
                        rpcTimeoutTimer:stop()
                    end


                    port, ip = s:getaddr()
                    print(string.format("S local UDP socket address / port: %s:%d", ip, port))

                    local status, err =  pcall (function ()
                        local state = sjson.decode(data)
                        if state.cmd == 'state' and state.nodeId == node.chipid() then
                            if state.value == 0 then
                                gpio.write(ledPin, 1)
                            else
                                gpio.write(ledPin, 0)
                            end
                            print("gpio set to: " .. tostring(state.value))
                        end
                    end)
                    if not status then
                        print("msg parse error:", status, err)
                    end
                end)
            end)
            if not status then
                print("mcast init error:", status, err)
            end

            rpc("query")
        end,
        function()
            print('on deactivate')

            wifiRunning:stop();
            if wifiConfiguration == nil then
                print('wifiConfiguration is null, resetting')
                wifiRunning:reset()
            else
                --switch configuration
                local config = wifiConfiguration:readConfiguration()
                if wifiConfiguration.primaryConfig ==true then
                    if config.ssid2 =='' or config.ssid2 ==nil then
                        print('No secondary config found, using primary')
                        startWifi(config.ssid, config.pswd)
                    else
                        print('using secondary config')
                        wifiConfiguration.primaryConfig =false
                        startWifi(config.ssid2, config.pswd2)
                    end
                else
                    print('using primary config')
                    wifiConfiguration.primaryConfig =true
                    startWifi(config.ssid, config.pswd)
                end
            end
        end)
end

-- data aquisition
enterBootDelay()


