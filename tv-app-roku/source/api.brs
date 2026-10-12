' ********************************************************************
' * StreamingTV: HTTP Client & API Gateway
' * Mode A (Xtream Codes / M3U player) and Mode B (Platform Device Link)
' * All of these run ONLY from ApiTask (worker thread), never render thread.
' ********************************************************************

function CreateHttpTransfer(url as String) as Object
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("User-Agent", "StreamingTV/" + AppVersion() + " (Roku)")
    xfer.AddHeader("Accept", "application/json, */*")
    xfer.AddHeader("Accept-Encoding", "identity")
    return xfer
end function

' GET body via roUrlEvent. GetToString()/PostFromString() return the HTTP
' status code (Integer) on some firmware — never use them.
function HttpGetBody(url as String, headers = invalid as Dynamic) as String
    xfer = CreateHttpTransfer(url)
    if headers <> invalid and type(headers) = "roAssociativeArray"
        for each hk in headers
            xfer.AddHeader(hk, headers[hk])
        end for
    end if
    port = CreateObject("roMessagePort")
    xfer.SetPort(port)
    if xfer.AsyncGetToString()
        msg = Wait(45000, port)
        if type(msg) = "roUrlEvent"
            body = msg.GetString()
            if body = invalid then return ""
            return body
        end if
    end if
    return ""
end function

function HttpPostJson(url as String, jsonBody as String, headers = invalid as Dynamic) as String
    xfer = CreateHttpTransfer(url)
    xfer.AddHeader("Content-Type", "application/json")
    if headers <> invalid and type(headers) = "roAssociativeArray"
        for each hk in headers
            xfer.AddHeader(hk, headers[hk])
        end for
    end if
    port = CreateObject("roMessagePort")
    xfer.SetPort(port)
    if xfer.AsyncPostFromString(jsonBody)
        msg = Wait(45000, port)
        if type(msg) = "roUrlEvent"
            body = msg.GetString()
            if body = invalid then return ""
            return body
        end if
    end if
    return ""
end function

function SafeJsonParse(jsonStr as Dynamic) as Dynamic
    if jsonStr = invalid then return invalid
    t = type(jsonStr)
    if t = "String" or t = "roString"
        if jsonStr = "" then return invalid
        return ParseJson(jsonStr)
    end if
    if t = "roAssociativeArray" or t = "roArray" then return jsonStr
    return invalid
end function

function DeviceMacAddress() as String
    ' roDeviceInfo has no GetMACAddress(). Use a stable device id, shown as a
    ' 12-char MAC-style token so it is easy to type on the website.
    devInfo = CreateObject("roDeviceInfo")
    uid = devInfo.GetRIDA()
    if uid = invalid or uid = "" then uid = devInfo.GetModel() + devInfo.GetVersion().version
    clean = UCase(uid.Replace(":", "").Replace("-", "").Replace(" ", ""))
    if Len(clean) >= 12 then return Left(clean, 12)
    return clean
end function

function DeviceUuid() as String
    return "ROKU" + DeviceMacAddress()
end function

function CleanServerUrl(url as String) as String
    clean = url.Trim()
    if Right(clean, 1) = "/" then clean = Left(clean, Len(clean) - 1)
    if LCase(Left(clean, 4)) <> "http" then clean = "http://" + clean
    return clean
end function

' ====================================================================
' Mode A: Xtream Codes (XC) / M3U
' ====================================================================

function XC_Login(serverUrl as String, username as String, password as String) as Object
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim()
    data = SafeJsonParse(HttpGetBody(endpoint))
    result = {
        success: false,
        userInfo: invalid,
        serverInfo: invalid,
        errorMessage: "Failed to connect to media server."
    }
    if data <> invalid and type(data) = "roAssociativeArray"
        if data.DoesExist("user_info")
            uInfo = data.user_info
            if uInfo.DoesExist("auth") and (uInfo.auth = 1 or uInfo.auth = "1")
                result.success = true
                result.userInfo = uInfo
                result.serverInfo = data.server_info
                result.errorMessage = ""
                return result
            else if uInfo.DoesExist("status") and uInfo.status = "Active"
                result.success = true
                result.userInfo = uInfo
                result.serverInfo = data.server_info
                result.errorMessage = ""
                return result
            else
                result.errorMessage = "Account inactive or expired."
            end if
        else
            result.errorMessage = "Invalid credentials or response format."
        end if
    end if
    return result
end function

function XC_GetLiveCategories(serverUrl as String, username as String, password as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_live_categories"
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetLiveStreams(serverUrl as String, username as String, password as String, categoryId = "" as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_live_streams"
    if categoryId <> "" and categoryId <> "all"
        endpoint = endpoint + "&category_id=" + categoryId
    end if
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetShortEpg(serverUrl as String, username as String, password as String, streamId as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_short_epg&stream_id=" + streamId
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetVodCategories(serverUrl as String, username as String, password as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_vod_categories"
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetVodStreams(serverUrl as String, username as String, password as String, categoryId = "" as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_vod_streams"
    if categoryId <> "" and categoryId <> "all"
        endpoint = endpoint + "&category_id=" + categoryId
    end if
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetSeriesCategories(serverUrl as String, username as String, password as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_series_categories"
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetSeries(serverUrl as String, username as String, password as String, categoryId = "" as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_series"
    if categoryId <> "" and categoryId <> "all"
        endpoint = endpoint + "&category_id=" + categoryId
    end if
    return SafeJsonParse(HttpGetBody(endpoint))
end function

function XC_GetSeriesInfo(serverUrl as String, username as String, password as String, seriesId as String) as Dynamic
    clean = CleanServerUrl(serverUrl)
    endpoint = clean + "/player_api.php?username=" + username.Trim() + "&password=" + password.Trim() + "&action=get_series_info&series_id=" + seriesId
    return SafeJsonParse(HttpGetBody(endpoint))
end function

' ====================================================================
' Mode B: Platform Device Link (Provider portal) + Player Setup
' ====================================================================

function Device_RequestCode(apiBase as String, macAddress = "" as String, deviceUuid = "" as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/device/new-code"
    devInfo = CreateObject("roDeviceInfo")
    clientId = deviceUuid
    if clientId = "" then clientId = DeviceUuid()
    mac = macAddress
    if mac = "" then mac = DeviceMacAddress()
    body = FormatJson({
        device_uuid: clientId,
        device_id: clientId,
        mac_address: mac,
        device_name: "StreamingTV Roku (" + devInfo.GetModel() + ")",
        device_model: devInfo.GetModel(),
        platform: "roku",
        app_version: AppVersion()
    })
    data = SafeJsonParse(HttpPostJson(endpoint, body))
    result = { success: false, code: "", expiresSec: 600, alreadyPaired: false, token: "", username: "", serverUrl: clean }
    if data <> invalid and type(data) = "roAssociativeArray"
        if data.DoesExist("status") and data.status = "active" and data.DoesExist("token")
            result.success = true
            result.alreadyPaired = true
            result.token = data.token
            if data.DoesExist("username") and data.username <> invalid
                result.username = data.username
            end if
            return result
        end if
        if data.DoesExist("code")
            result.success = true
            result.code = data.code
            if data.DoesExist("expires_in") then result.expiresSec = data.expires_in
        end if
    end if
    return result
end function

function Device_PollStatus(apiBase as String, deviceCode as String, macAddress = "" as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/device/status?code=" + deviceCode.Trim()
    data = SafeJsonParse(HttpGetBody(endpoint))
    if data = invalid or type(data) <> "roAssociativeArray" or not data.DoesExist("status")
        endpoint2 = clean + "/api/device/new-code/status?code=" + deviceCode.Trim()
        data = SafeJsonParse(HttpGetBody(endpoint2))
    end if
    result = { paired: false, token: "", username: "", serverUrl: clean, mac: macAddress }
    if data <> invalid and type(data) = "roAssociativeArray"
        if data.DoesExist("status") and (data.status = "paired" or data.status = "active")
            result.paired = true
            if data.DoesExist("token") and data.token <> invalid
                result.token = data.token
            else
                result.token = ""
            end if
            if data.DoesExist("username") and data.username <> invalid
                result.username = data.username
            end if
            if data.DoesExist("server_url") and data.server_url <> ""
                result.serverUrl = CleanServerUrl(data.server_url)
            end if
        end if
    end if
    return result
end function

function Device_GetConfig(apiBase as String, token as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/device/config"
    headers = {
        "Authorization": "Bearer " + token.Trim(),
        "X-Device-Token": token.Trim()
    }
    data = SafeJsonParse(HttpGetBody(endpoint, headers))
    if data <> invalid and type(data) = "roAssociativeArray"
        return data
    end if
    return {}
end function

' ====================================================================
' Player Setup (XC / M3U) — MAC + PIN, E2EE payload
' ====================================================================

function Player_GeneratePin() as String
    n = Int(Rnd(0) * 1000000)
    if n < 0 then n = -n
    return Right("000000" + Str(n).Trim(), 6)
end function

function Player_Bind(apiBase as String, mac as String, pinCode as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/player/bind"
    body = FormatJson({
        mac_address: mac,
        pin_hash: Sha256Hex(pinCode + ":" + mac),
        device_uuid: DeviceUuid()
    })
    data = SafeJsonParse(HttpPostJson(endpoint, body))
    result = { success: false, error: "" }
    if data <> invalid and type(data) = "roAssociativeArray" and data.DoesExist("status")
        result.success = true
    else
        result.error = "Could not start setup."
    end if
    return result
end function

function Player_FetchPayload(apiBase as String, mac as String, pinCode as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/player/payload?mac=" + mac + "&pin_hash=" + Sha256Hex(pinCode + ":" + mac)
    data = SafeJsonParse(HttpGetBody(endpoint))
    result = { success: false, ready: false, error: "", payload: invalid }
    if data = invalid or type(data) <> "roAssociativeArray"
        result.error = "Could not reach setup service."
        return result
    end if
    result.success = true
    status = ""
    if data.DoesExist("status") then status = data.status
    if status = "ready"
        result.ready = true
        result.payload = data
    end if
    return result
end function

function Player_Unbind(apiBase as String, mac as String, pinCode as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/player/unbind"
    body = FormatJson({ mac_address: mac, pin: pinCode })
    data = SafeJsonParse(HttpPostJson(endpoint, body))
    result = { success: false }
    if data <> invalid and type(data) = "roAssociativeArray" and data.DoesExist("status")
        result.success = true
    end if
    return result
end function

function Device_Logout(apiBase as String, token as String) as Object
    clean = CleanServerUrl(apiBase)
    endpoint = clean + "/api/device/logout"
    headers = {
        "Authorization": "Bearer " + token.Trim(),
        "X-Device-Token": token.Trim()
    }
    body = FormatJson({ token: token })
    data = SafeJsonParse(HttpPostJson(endpoint, body, headers))
    result = { success: false }
    if data <> invalid and type(data) = "roAssociativeArray" and data.DoesExist("status")
        result.success = true
    end if
    return result
end function

function SetupUrl(mac as String, pin as String) as String
    return "https://streamingtvroku.pages.dev/?mac=" + mac + "&code=" + pin
end function

function QrImageUrl(dataUrl as String) as String
    ' Remote QR PNG. Poster loads this; text on screen is the fallback.
    return "https://api.qrserver.com/v1/create-qr-code/?size=320x320&margin=8&data=" + dataUrl
end function
