
-- scan all AP
local function scanAP(self)
     -- print('scanning')
        -- Scan and print all found APs, including hidden ones
        pcall(function()
            wifi.sta.scan({ hidden = 1 }, function(err,arr)
                if err then
                    print ("Scan failed:", err)
                else
                    --[[
                        print(string.format("%-26s","SSID"),"Channel BSSID              RSSI Auth Bandwidth")
                        for i,ap in ipairs(arr) do
                            print(string.format("%-32s",ap.ssid),ap.channel,ap.bssid,ap.rssi,ap.auth,ap.bandwidth)
                        end
                        print("-- Total APs: ", #arr)
                        ]]
                    self.scanResult = arr
                end
            end)
        end)
end
-- return the result of the scan -  UI use
local function listAP(self)
    return self.scanResult or  {}
end

-- stop the wifi configuration and wifi subsystem
local function stop(self)
    if self.scanTmr then
        self.scanTmr:unregister()
        self.scanTmr = nil
    end
    wifi.stop()
    self.httpserver = nil
    package.loaded["httpserver"] = nil
end

-- remove default configuration file
local function clearConfiguration(self)
    file.remove(self._wifiConf)
end

--save config to default file
local function saveConfiguration(self, config)
    local fd = file.open(self._wifiConf, "w")
    if fd then
        fd.write(sjson.encode(config))
        fd.close();
        fd = nil
        return config
    end
    return {}
end

--load config from default file
local function readConfiguration(self)
    if file.exists(self._wifiConf) then
        local fd = file.open("wifi.conf", "r")
        if fd then
            local configJson = fd.read();
            fd.close();
            fd = nil
            return sjson.decode(configJson)
        end
    end
    return {}
end

-- read a file, max 4k
local function readFile(filename)
    if file.open(filename) then
        local data = file.read(8192)
        file.close()
        return data
    end
    return nil
end

-- string startswith
local function startsWith(str, start)
    return str:sub(1, #start) == start
 end

 -- ssid, pswd, scan period to use when the client connects
local function start(self, ssidParam, pwdParam, scanPeriod)
    wifi.mode(wifi.STATIONAP)
    wifi.ap.config({ssid=ssidParam, pwd=pwdParam}, false)
    wifi.start()
    -- scan only on client connect
    wifi.ap.on("sta_connected", function(event, info)
        print("client connected:", info.mac, info.id , 'client count:', self.clientCount)

        if self.clientCount == 0 then
            self.scanTmr=tmr.create()
            self.scanTmr:alarm(scanPeriod or 5000, tmr.ALARM_AUTO, function()
                self:scanAP()
            end)
        end
        self.clientCount =  self.clientCount +1
    end)
    wifi.ap.on("sta_disconnected", function(event, info)
        if self.clientCount >0 then
            self.clientCount =  self.clientCount -1
        end
        print("client disconnected:", info.mac, info.id , 'client count:', self.clientCount)
        if self.clientCount ==0  then
            self.scanTmr:unregister()
            self.scanTmr = nil
        end
    end)


    local parentSelf = self
    self.httpserver = require("httpserver")
    self.httpserver.createServer(80, function (req, res)
        -- print("+R", '|' .. req.method ..'|', '|'..req.url ..'|', node.heap())
        local postRequestParams = ''
        req.onheader = function(self, name, value)
            --print(self.httpReqMap)
            --print("+H", name, value)
          end
        req.ondata = function(self, chunk)
            -- print("+B", chunk and #chunk, node.heap(), chunk)
            if not chunk then
                -- data is captured
                if req.method == 'GET' then
                    local filename= nil
                    if req.url == '/' or req.url == '/?' then
                        filename = 'wcIndex.html'
                    elseif startsWith(req.url, '/static/') then
                        filename = string.sub(req.url, 9)
                    end
                    print('>>>>>> file:' , filename)
                    if filename  then
                        -- remove query string
                        if string.find(filename,"?") then
                            filename = string.sub(filename,1,string.find(filename,"?")-1)
                        end

                        print('sending file:' , filename)
                        pcall (function ()
                            res:send(nil, 200)
                            -- res:send_header("Connection", "close")
                            res:send(readFile(filename))
                            res:send("\n")
                        end)
                    else
                        print('file not found', filename)
                        pcall (function ()
                            res:send(nil, 200)
                            res:send("\n")
                        end)
                    end
                elseif req.method == 'POST' then
                    if startsWith(req.url, '/service/') then
                        --invoke service
                        local servicename = string.sub(req.url, 10)
                        print('service >>>>>', '|'.. tostring(servicename) .. '|')
                        print('params >>>>>> ' , '|'.. tostring(postRequestParams).. '|')
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
                            end
                            res:send("\n")
                            if servicename == 'saveConfiguration' then
                                -- schedule restart
                                tmr.create():alarm(1500, tmr.ALARM_SINGLE, function (t) node.restart() end)
                            end
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

end

return {
    ['new'] = function()
        return { primaryConfig=true; clientCount=0; ['_wifiConf']="wifi.conf"; ['start'] = start ; ['scanAP']=scanAP; ['listAP'] = listAP ; ['stop'] = stop ; ['switchAuth'] = switchAuth ; ['saveConfiguration']=saveConfiguration ; ['readConfiguration']=readConfiguration ; ['clearConfiguration']=clearConfiguration }
        end
    }
