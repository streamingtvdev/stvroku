' ********************************************************************
' * StreamingTV BETA: LoginScreen
' * Default: Player Setup (QR + device id + PIN -> streamingtvroku.pages.dev)
' * Secondary: StreamingTV Login (Provider link-device code)
' * Authored at 1920x1080; Roku scales for 720p / 1080p / 4K.
' ********************************************************************

sub init()
    m.loginBg = m.top.findNode("loginBg")
    m.brandTitle = m.top.findNode("brandTitle")
    m.brandSub = m.top.findNode("brandSub")
    
    m.playerSetupPanel = m.top.findNode("playerSetupPanel")
    m.streamTvPanel = m.top.findNode("streamTvPanel")
    
    m.setupQrPoster = m.top.findNode("setupQrPoster")
    m.setupQrFallback = m.top.findNode("setupQrFallback")
    m.setupUrlLabel = m.top.findNode("setupUrlLabel")
    m.setupMacLabel = m.top.findNode("setupMacLabel")
    m.setupPinLabel = m.top.findNode("setupPinLabel")
    m.setupStatusLabel = m.top.findNode("setupStatusLabel")
    m.btnNewPin = m.top.findNode("btnNewPin")
    m.btnStreamTv = m.top.findNode("btnStreamTv")
    
    m.linkCodeLabel = m.top.findNode("linkCodeLabel")
    m.linkStatusLabel = m.top.findNode("linkStatusLabel")
    m.btnLinkNew = m.top.findNode("btnLinkNew")
    m.btnLinkBack = m.top.findNode("btnLinkBack")
    
    m.pollTimer = m.top.findNode("pollTimer")
    m.expiryTimer = m.top.findNode("expiryTimer")
    
    m.screen = "setup" ' setup | link
    m.focusIndex = 0    ' setup: 0=NEW CODE, 1=STREAMINGTV LOGIN | link: 0=NEW CODE, 1=BACK
    m.macAddress = DeviceMacAddress()
    m.deviceUuid = DeviceUuid()
    m.apiBase = "https://api.pirateking.cloud"
    m.requestInFlight = false
    m.setupPin = ""
    m.deviceCode = ""
    m.setupContext = "setup"
    
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.observeField("response", "OnApiResponse")
    m.pollTimer.observeField("fire", "OnPollTimerFired")
    m.expiryTimer.observeField("fire", "OnExpiryTimerFired")
    
    UpdateFocusStyles()
    StartPlayerSetup()
end sub

sub OnThemeChanged()
    theme = m.top.theme
    if theme <> invalid
        m.loginBg.color = theme.backgroundColor
        m.setupPinLabel.color = theme.accentPrimary
        if m.linkCodeLabel <> invalid then m.linkCodeLabel.color = theme.accentPrimary
        if m.setupUrlLabel <> invalid then m.setupUrlLabel.color = theme.accentFocused
        if m.brandTitle <> invalid and theme.brandName <> "" then m.brandTitle.text = theme.brandName
        UpdateFocusStyles()
    end if
end sub

sub FireApi(action as String, args as Object, context as String)
    m.requestInFlight = true
    m.apiTask.context = context
    m.apiTask.action = action
    m.apiTask.args = args
    m.apiTask.control = "RUN"
end sub

' ====================================================================
' Focus + panels
' ====================================================================

sub UpdateFocusStyles()
    theme = m.top.theme
    if theme = invalid then theme = GetDefaultTheme()
    
    if m.screen = "setup"
        if m.focusIndex = 0
            m.btnNewPin.color = theme.accentFocused
            m.btnStreamTv.color = theme.accentPrimary
        else
            m.btnNewPin.color = theme.cardColor
            m.btnStreamTv.color = theme.accentFocused
        end if
    else
        if m.focusIndex = 0
            m.btnLinkNew.color = theme.accentFocused
            m.btnLinkBack.color = theme.cardColor
        else
            m.btnLinkNew.color = theme.cardColor
            m.btnLinkBack.color = theme.accentFocused
        end if
    end if
end sub

sub ShowSetupScreen()
    m.screen = "setup"
    m.focusIndex = 0
    m.playerSetupPanel.visible = true
    m.streamTvPanel.visible = false
    UpdateFocusStyles()
    if m.setupPin = "" then StartPlayerSetup()
end sub

sub ShowLinkScreen()
    m.screen = "link"
    m.focusIndex = 0
    m.playerSetupPanel.visible = false
    m.streamTvPanel.visible = true
    UpdateFocusStyles()
    RequestNewDeviceCode()
end sub

' ====================================================================
' Player Setup (MAC + PIN + QR)
' ====================================================================

sub StartPlayerSetup()
    m.setupContext = "setup"
    m.pollTimer.control = "stop"
    m.expiryTimer.control = "stop"
    m.setupPin = Player_GeneratePin()
    
    macText = FormatMacForDisplay(m.macAddress)
    pinText = FormatPinForDisplay(m.setupPin)
    m.setupMacLabel.text = macText
    m.setupPinLabel.text = pinText
    m.setupStatusLabel.text = "Waiting for playlist details on the website..."
    
    url = SetupUrl(m.macAddress, m.setupPin)
    m.setupUrlLabel.text = "streamingtvroku.pages.dev"
    m.setupQrPoster.uri = QrImageUrl(url)
    m.setupQrFallback.text = "Scan or open" + Chr(10) + "streamingtvroku.pages.dev"
    
    FireApi("player_bind", {
        apiBase: m.apiBase,
        mac: m.macAddress,
        pin: m.setupPin
    }, "player_bind")
end sub

' ====================================================================
' StreamingTV link-device code (Provider portal)
' ====================================================================

sub RequestNewDeviceCode()
    m.setupContext = "link"
    m.pollTimer.control = "stop"
    m.expiryTimer.control = "stop"
    m.deviceCode = ""
    m.linkCodeLabel.text = "------"
    m.linkStatusLabel.text = "Requesting code..."
    FireApi("device_request_code", {
        apiBase: m.apiBase,
        macAddress: m.macAddress,
        deviceUuid: m.deviceUuid
    }, "request_code")
end sub

sub OnPollTimerFired()
    if m.requestInFlight then return
    
    if m.setupContext = "setup"
        FireApi("player_fetch_payload", {
            apiBase: m.apiBase,
            mac: m.macAddress,
            pin: m.setupPin
        }, "player_payload")
        return
    end if
    
    if m.deviceCode = "" then return
    FireApi("device_poll_status", {
        apiBase: m.apiBase,
        code: m.deviceCode,
        macAddress: m.macAddress
    }, "poll_status")
end sub

sub OnApiResponse()
    resp = m.apiTask.response
    m.requestInFlight = false
    if resp = invalid then return
    
    ctx = resp.context
    data = resp.data
    
    if ctx = "request_code"
        if resp.success and data <> invalid
            if data.alreadyPaired
                ActivatePairedSession(data.token, data.username, data.serverUrl)
                return
            end if
            m.deviceCode = data.code
            m.linkCodeLabel.text = FormatPinForDisplay(m.deviceCode)
            m.linkStatusLabel.text = "On your phone or computer open your StreamingTV account, choose Link Device (your Provider can help), then enter this code."
            m.pollTimer.control = "start"
            m.expiryTimer.control = "start"
        else
            m.linkCodeLabel.text = "ERROR"
            m.linkStatusLabel.text = "Could not reach the service. Press NEW CODE to retry."
        end if
        
    else if ctx = "poll_status"
        if data <> invalid and data.paired and data.token <> ""
            ActivatePairedSession(data.token, data.username, data.serverUrl)
        end if
        
    else if ctx = "fetch_config"
        ApplyBrandConfigData(data)
        m.top.loginSuccess = true
        
    else if ctx = "player_bind"
        if resp.success and data <> invalid and data.success
            m.setupStatusLabel.text = "Waiting for playlist details on the website..."
            m.pollTimer.control = "start"
            m.expiryTimer.control = "start"
        else
            m.setupStatusLabel.text = "Could not start setup. Press NEW CODE to retry."
        end if
        
    else if ctx = "player_payload"
        if data <> invalid and data.ready and data.payload <> invalid
            ApplyEncryptedPayload(data.payload)
        else if data <> invalid and data.success
            m.setupStatusLabel.text = "Waiting for playlist details on the website..."
        else
            m.setupStatusLabel.text = "Connection problem. Retrying..."
        end if
    end if
end sub

sub ApplyEncryptedPayload(payload as Object)
    cipherB64 = ""
    ivB64 = ""
    if payload.DoesExist("ciphertext") then cipherB64 = payload.ciphertext
    if payload.DoesExist("iv") then ivB64 = payload.iv
    
    plain = AesCbcDecrypt(m.setupPin, m.macAddress, ivB64, cipherB64)
    if plain = ""
        m.setupStatusLabel.text = "Could not read setup data. Press NEW CODE and try again."
        return
    end if
    
    creds = SafeJsonParse(plain)
    if creds = invalid
        m.setupStatusLabel.text = "Setup data was invalid. Press NEW CODE and try again."
        return
    end if
    
    active = invalid
    if type(creds) = "roArray"
        for each c in creds
            if c <> invalid and type(c) = "roAssociativeArray"
                enabled = true
                if c.DoesExist("enabled") then enabled = c.enabled
                if enabled
                    active = c
                    exit for
                end if
            end if
        end for
        if active = invalid and creds.Count() > 0 then active = creds[0]
    else if type(creds) = "roAssociativeArray"
        active = creds
    end if
    
    if active = invalid
        m.setupStatusLabel.text = "Setup data was invalid. Press NEW CODE and try again."
        return
    end if
    
    kind = "xc"
    if active.DoesExist("kind") then kind = LCase(active.kind)
    serverUrl = ""
    if active.DoesExist("server_url") then serverUrl = AnyToStr(active.server_url)
    m3uUrl = ""
    if active.DoesExist("m3u_url") then m3uUrl = AnyToStr(active.m3u_url)
    username = ""
    if active.DoesExist("username") then username = AnyToStr(active.username)
    password = ""
    if active.DoesExist("password") then password = AnyToStr(active.password)
    
    if kind = "m3u" and serverUrl = "" then serverUrl = m3uUrl
    if serverUrl = ""
        m.setupStatusLabel.text = "No server URL in setup data. Press NEW CODE and try again."
        return
    end if
    
    Storage_SetAuth("server_url", CleanServerUrl(serverUrl))
    Storage_SetAuth("username", username)
    Storage_SetAuth("password", password)
    Storage_SetAuth("login_mode", "xc")
    Storage_SetAuth("device_token", "")
    Storage_SetAuth("mac_address", m.macAddress)
    Storage_SetAuth("setup_pin", m.setupPin)
    
    m.pollTimer.control = "stop"
    m.expiryTimer.control = "stop"
    m.setupStatusLabel.text = "Playlist received! Opening..."
    m.top.loginSuccess = true
end sub

sub ActivatePairedSession(token as Dynamic, username as Dynamic, serverUrl as Dynamic)
    m.setupContext = "link"
    m.pollTimer.control = "stop"
    m.expiryTimer.control = "stop"
    m.linkStatusLabel.text = "Device linked! Configuring..."
    
    tok = AnyToStr(token)
    srv = m.apiBase
    srvIn = AnyToStr(serverUrl)
    if srvIn <> "" then srv = CleanServerUrl(srvIn)
    uname = AnyToStr(username)
    if uname = "" then uname = tok
    
    Storage_SetAuth("device_token", tok)
    Storage_SetAuth("server_url", srv)
    Storage_SetAuth("login_mode", "paired")
    Storage_SetAuth("username", uname)
    Storage_SetAuth("password", tok)
    Storage_SetAuth("mac_address", m.macAddress)
    
    FireApi("device_get_config", {
        apiBase: m.apiBase,
        token: tok
    }, "fetch_config")
end sub

sub OnExpiryTimerFired()
    m.pollTimer.control = "stop"
    if m.setupContext = "setup"
        m.setupStatusLabel.text = "Timed out. Press NEW CODE to try again."
    else
        m.linkStatusLabel.text = "Code expired. Press NEW CODE to get a new one."
        m.linkCodeLabel.text = "EXPIRED"
    end if
end sub

function FormatMacForDisplay(mac as String) as String
    clean = mac
    if Len(clean) = 12
        return Mid(clean, 1, 2) + ":" + Mid(clean, 3, 2) + ":" + Mid(clean, 5, 2) + ":" + Mid(clean, 7, 2) + ":" + Mid(clean, 9, 2) + ":" + Mid(clean, 11, 2)
    end if
    return clean
end function

function FormatPinForDisplay(pin as String) as String
    if Len(pin) >= 6 then return Left(pin, 3) + " " + Right(pin, Len(pin) - 3)
    return pin
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    if key = "left" or key = "right"
        m.focusIndex = 1 - m.focusIndex
        UpdateFocusStyles()
        return true
    else if key = "OK"
        if m.screen = "setup"
            if m.focusIndex = 0
                StartPlayerSetup()
            else
                ShowLinkScreen()
            end if
        else
            if m.focusIndex = 0
                RequestNewDeviceCode()
            else
                ShowSetupScreen()
            end if
        end if
        return true
    else if key = "back"
        if m.screen = "link"
            ShowSetupScreen()
            return true
        end if
        return true
    end if
    
    return false
end function
