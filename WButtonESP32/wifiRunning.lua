-- stop the wifi configuration and wifi subsystem
local function stop(self)
    wifi.stop()
end

local function ping(self)
end

local function reset(self, obj)
    local resetTimer = tmr.create()
    resetTimer:alarm(500, tmr.ALARM_AUTO,
    function (t)
        node.restart()
    end)
    return  {  }
end


-- read a file,
local function readFile(filename)
    if file.open(filename) then
        local data = file.read(16000)
        file.close()
        return data
    end
    return nil
end

-- string startswith
local function startsWith(str, startStr)
    return string.sub(str,1, #startStr) == startStr
 end


local function start(self, ssidParam, pwdParam, onActivate, onDeactivate)
    print("Connecting to:", ssidParam)
    wifi.mode(wifi.STATION)
    wifi.sta.config({ssid=ssidParam, pwd=pwdParam, auto=false}, false)
    wifi.sta.on("connected", function(event, info)
        print ('Connected, waiting for IP', info.ssid, info.bssid, info.channel,info.auth)
    end )
    wifi.sta.on("got_ip", function(event, info)
        print('Activated, got IP', info.ip, info.netmask, info.gw )
        pcall( function()
            onActivate(info.ip,info.netmask, info.gw )

            local parentSelf = self
            self.httpserver = require("httpserver")
            self.httpserver.createServer(80, function (req, res)
                if req == nil then return end
                -- print("+R", '|' .. req.method ..'|', '|'..req.url ..'|', node.heap())
                local postRequestParams = ''
                req.onheader = function(self, name, value)
                    --print(self.httpReqMap)
                    --print("+H", name, value)
                  end
                req.ondata = function(self, chunk)
                    -- print("+B", chunk and #chunk, node.heap(), chunk)
                    if not chunk and req then
                        -- data is captured
                        if req.method == 'GET' then
                            local filename= nil
                            if req.url == '/' or req.url == '/?' then
                                filename = 'rIndex.html'
                            elseif startsWith(req.url, '/static/') then
                                filename = string.sub(req.url, 9)
                            end
                            -- print('requested file:' , filename)
                            if filename  then
                                -- remove query string
                                if string.find(filename,"?") then
                                    filename = string.sub(filename,1,string.find(filename,"?")-1)
                                end
                                -- print('replying with file:' , filename)
                                pcall (function ()
                                    res:send(nil, 200)
                                    -- res:send_header("Connection", "close")
                                    res:send(readFile(filename))
                                    res:send("\n")
                                end)
                            else
                                -- print('file not found', filename)
                                pcall (function ()
                                    res:send(nil, 200)
                                    res:send("\n")
                                end)
                            end
                        elseif req.method == 'POST' then
                            if startsWith(req.url, '/service/') then
                                --invoke service
                                local servicename = string.sub(req.url, 10)
                                -- print('invoked service:',  tostring(servicename) , parentSelf)
                                -- print('\tparams:' , tostring(postRequestParams))
                                local status, err =  pcall (function ()
                                    local ret =nil
                                    if postRequestParams == nil or postRequestParams =="" then
                                        ret = parentSelf[servicename](parentSelf)
                                    else
                                        ret = parentSelf[servicename](parentSelf,sjson.decode(postRequestParams))
                                    end

                                    -- reply
                                    res:send(nil, 200)
                                    -- res:send_header("Connection", "close")
                                    -- print("result <<<<<<<<< ", ret, sjson.encode(ret))
                                    if ret then
                                        res:send(sjson.encode(ret))
                                        ret=nil;
                                    end
                                    res:send("\n")
                                end)
                                if not status then
                                    print("Http error:", status, err)
                                end
                            else
                                pcall (function ()
                                    res:send(nil, 200)
                                    res:send("\n")
                                end)
                            end
                        end
                        pcall (function ()
                            res:finish()
                        end)
                    else
                        postRequestParams = postRequestParams .. tostring(chunk)
                    end
                end
            end)

        end)
     end)
     wifi.sta.on("disconnected", function(event, info)
        print('WIFI disconnected', info.reason)
        pcall( function()
            onDeactivate(info.reason)
        end)
     end)
    wifi.start()
end


return {
    ['new'] = function()
        return {
            ['start'] = start ;
            ['stop'] = stop;
            ['startsWith']=startsWith ;
            ['readFile']=readFile;
            ['reset']=reset;
            ['ping']=ping;
        }
        end
    }
