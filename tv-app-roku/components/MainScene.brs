' ********************************************************************
' * StreamingTV BETA: MainScene Controller
' * Screen navigation, branding, player launch, and playlist-edit codes.
' * Star (*) short-press = tab menu.  Star long-press = edit playlist code.
' ********************************************************************

sub init()
    m.bgRect = m.top.findNode("bgRect")
    m.headerBar = m.top.findNode("headerBar")
    m.brandLogoPoster = m.top.findNode("brandLogoPoster")
    m.brandTitleLabel = m.top.findNode("brandTitleLabel")
    m.clockLabel = m.top.findNode("clockLabel")
    m.clockTimer = m.top.findNode("clockTimer")
    
    m.tabLiveBg = m.top.findNode("tabLiveBg")
    m.tabMoviesBg = m.top.findNode("tabMoviesBg")
    m.tabSeriesBg = m.top.findNode("tabSeriesBg")
    m.tabSettingsBg = m.top.findNode("tabSettingsBg")
    
    m.tabLiveLabel = m.top.findNode("tabLiveLabel")
    m.tabMoviesLabel = m.top.findNode("tabMoviesLabel")
    m.tabSeriesLabel = m.top.findNode("tabSeriesLabel")
    m.tabSettingsLabel = m.top.findNode("tabSettingsLabel")
    
    m.screenContainer = m.top.findNode("screenContainer")
    m.playerContainer = m.top.findNode("playerContainer")
    m.tabMenuOverlay = m.top.findNode("tabMenuOverlay")
    m.tabMenuList = m.top.findNode("tabMenuList")
    
    m.editCodeOverlay = m.top.findNode("editCodeOverlay")
    m.editMacLabel = m.top.findNode("editMacLabel")
    m.editCodeLabel = m.top.findNode("editCodeLabel")
    m.editUrlLabel = m.top.findNode("editUrlLabel")
    m.editCodeStatus = m.top.findNode("editCodeStatus")
    m.editQrPoster = m.top.findNode("editQrPoster")
    m.optionsHoldTimer = m.top.findNode("optionsHoldTimer")
    m.editPollTimer = m.top.findNode("editPollTimer")
    m.editPollTimer.observeField("fire", "OnEditPollTimerFired")
    
    m.currentTab = 0
    m.activeScreen = invalid
    m.playerScreen = invalid
    m.theme = GetDefaultTheme()
    m.optionsHeld = false
    m.editPin = ""
    m.editPollInFlight = false
    m.apiBase = "https://api.pirateking.cloud"
    
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.observeField("response", "OnApiResponse")
    m.bgConfigTask = invalid
    
    tabContent = CreateObject("roSGNode", "ContentNode")
    for each t in ["LIVE TV", "MOVIES", "SERIES", "SETTINGS"]
        item = tabContent.CreateChild("ContentNode")
        item.title = t
    end for
    m.tabMenuList.content = tabContent
    m.tabMenuList.observeField("itemSelected", "OnTabMenuSelected")
    
    m.optionsHoldTimer.observeField("fire", "OnOptionsHoldFired")
    
    m.clockTimer.observeField("fire", "OnClockTick")
    m.clockTimer.control = "start"
    OnClockTick()
    
    LoadCachedTheme()
    CheckAuthAndInitialize()
end sub

sub OnClockTick()
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    hours = dt.GetHours()
    mins = dt.GetMinutes()
    ampm = "AM"
    if hours >= 12
        ampm = "PM"
        if hours > 12 then hours = hours - 12
    end if
    if hours = 0 then hours = 12
    minStr = Str(mins).Trim()
    if Len(minStr) = 1 then minStr = "0" + minStr
    m.clockLabel.text = Str(hours).Trim() + ":" + minStr + " " + ampm
end sub

sub LoadCachedTheme()
    cachedBrandName = Storage_GetAuth("provider_brand_name", "")
    cachedLogo = Storage_GetAuth("provider_logo", "")
    cachedAccent = Storage_GetAuth("provider_accent_color", "")
    
    if cachedBrandName <> ""
        m.theme.brandName = cachedBrandName
        m.theme.isCustomBranded = true
    end if
    if cachedLogo <> ""
        m.theme.brandLogo = cachedLogo
    end if
    if cachedAccent <> ""
        if Left(cachedAccent, 1) = "#" then cachedAccent = Mid(cachedAccent, 2)
        if Len(cachedAccent) = 6
            m.theme.accentPrimary = "0x" + UCase(cachedAccent) + "FF"
            m.theme.accentSecondary = "0x" + UCase(cachedAccent) + "FF"
            m.theme.accentFocused = "0x" + UCase(cachedAccent) + "FF"
        end if
    end if
    ApplyThemeToUI()
end sub

sub ApplyThemeToUI()
    m.bgRect.color = m.theme.backgroundColor
    m.brandTitleLabel.text = m.theme.brandName
    if m.theme.brandLogo <> ""
        m.brandLogoPoster.uri = m.theme.brandLogo
        m.brandLogoPoster.visible = true
    end if
    betaBadge = m.top.findNode("betaBadge")
    if betaBadge <> invalid then betaBadge.color = m.theme.accentPrimary
    if m.editCodeLabel <> invalid then m.editCodeLabel.color = m.theme.accentPrimary
    if m.editUrlLabel <> invalid then m.editUrlLabel.color = m.theme.accentFocused
    UpdateTabStyles()
    if m.activeScreen <> invalid and m.activeScreen.DoesExist("theme")
        m.activeScreen.theme = m.theme
    end if
end sub

sub UpdateTabStyles()
    tabs = [
        { bg: m.tabLiveBg, lbl: m.tabLiveLabel },
        { bg: m.tabMoviesBg, lbl: m.tabMoviesLabel },
        { bg: m.tabSeriesBg, lbl: m.tabSeriesLabel },
        { bg: m.tabSettingsBg, lbl: m.tabSettingsLabel }
    ]
    
    for i = 0 to 3
        if i = m.currentTab
            tabs[i].bg.color = m.theme.accentPrimary
            tabs[i].lbl.color = "0xFFFFFFFF"
        else
            tabs[i].bg.color = m.theme.cardColor
            tabs[i].lbl.color = m.theme.textColorSecondary
        end if
    end for
end sub

sub CheckAuthAndInitialize()
    loginMode = Storage_GetAuth("login_mode", "")
    serverUrl = Storage_GetAuth("server_url", "")
    token = Storage_GetAuth("device_token", "")
    user = Storage_GetAuth("username", "")
    pass = Storage_GetAuth("password", "")
    
    if (loginMode = "xc" and serverUrl <> "" and user <> "" and pass <> "") or (loginMode = "paired" and token <> "")
        m.headerBar.visible = true
        if loginMode = "paired" and token <> ""
            RefreshConfigInBackground(token)
        end if
        SwitchTab(0)
    else
        m.headerBar.visible = false
        ShowLoginScreen()
    end if
end sub

sub RefreshConfigInBackground(token as String)
    if m.bgConfigTask = invalid
        m.bgConfigTask = CreateObject("roSGNode", "ApiTask")
        m.bgConfigTask.observeField("response", "OnBgConfigResponse")
    end if
    m.bgConfigTask.context = "bg_config"
    m.bgConfigTask.action = "device_get_config"
    m.bgConfigTask.args = {
        apiBase: m.apiBase,
        token: token
    }
    m.bgConfigTask.control = "RUN"
end sub

sub OnBgConfigResponse()
    resp = m.bgConfigTask.response
    if resp = invalid then return
    if resp.success and resp.data <> invalid
        ApplyBrandConfigData(resp.data)
        LoadCachedTheme()
    end if
end sub

sub ShowLoginScreen()
    ClearActiveScreen()
    login = CreateObject("roSGNode", "LoginScreen")
    login.theme = m.theme
    login.observeField("loginSuccess", "OnLoginSuccess")
    m.screenContainer.appendChild(login)
    m.activeScreen = login
    login.setFocus(true)
end sub

sub OnLoginSuccess()
    LoadCachedTheme()
    m.headerBar.visible = true
    SwitchTab(0)
end sub

sub SwitchTab(tabIndex as Integer)
    m.currentTab = tabIndex
    UpdateTabStyles()
    ClearActiveScreen()
    
    if tabIndex = 0
        live = CreateObject("roSGNode", "LiveScreen")
        live.theme = m.theme
        live.observeField("playFullscreen", "OnPlayFullscreen")
        m.screenContainer.appendChild(live)
        m.activeScreen = live
        live.setFocus(true)
    else if tabIndex = 1
        vod = CreateObject("roSGNode", "VodScreen")
        vod.theme = m.theme
        vod.vodType = "movies"
        vod.observeField("playMedia", "OnPlayVodMedia")
        m.screenContainer.appendChild(vod)
        m.activeScreen = vod
        vod.setFocus(true)
    else if tabIndex = 2
        vod = CreateObject("roSGNode", "VodScreen")
        vod.theme = m.theme
        vod.vodType = "series"
        vod.observeField("playMedia", "OnPlayVodMedia")
        m.screenContainer.appendChild(vod)
        m.activeScreen = vod
        vod.setFocus(true)
    else if tabIndex = 3
        settings = CreateObject("roSGNode", "SettingsScreen")
        settings.theme = m.theme
        settings.observeField("logoutRequested", "OnLogoutRequested")
        m.screenContainer.appendChild(settings)
        m.activeScreen = settings
        settings.setFocus(true)
    end if
end sub

sub OnPlayFullscreen(event as Object)
    channelData = event.getData()
    if channelData = invalid then return
    LaunchPlayerScreen(channelData, true)
end sub

sub OnPlayVodMedia(event as Object)
    mediaData = event.getData()
    if mediaData = invalid then return
    LaunchPlayerScreen(mediaData, false)
end sub

sub LaunchPlayerScreen(mediaData as Object, isLive as Boolean)
    if m.playerScreen <> invalid
        m.playerContainer.removeChild(m.playerScreen)
        m.playerScreen = invalid
    end if
    
    m.headerBar.visible = false
    m.screenContainer.visible = false
    m.playerContainer.visible = true
    
    player = CreateObject("roSGNode", "PlayerScreen")
    player.theme = m.theme
    player.isLiveStream = isLive
    player.mediaData = mediaData
    player.observeField("closePlayer", "OnClosePlayer")
    m.playerContainer.appendChild(player)
    m.playerScreen = player
    player.setFocus(true)
end sub

sub OnClosePlayer()
    if m.playerScreen <> invalid
        m.playerContainer.removeChild(m.playerScreen)
        m.playerScreen = invalid
    end if
    
    m.playerContainer.visible = false
    m.headerBar.visible = true
    m.screenContainer.visible = true
    
    if m.activeScreen <> invalid
        m.activeScreen.setFocus(true)
    end if
end sub

sub OnLogoutRequested()
    Storage_ClearAllAuth()
    m.theme = GetDefaultTheme()
    ApplyThemeToUI()
    m.headerBar.visible = false
    ShowLoginScreen()
end sub

sub ClearActiveScreen()
    if m.activeScreen <> invalid
        m.screenContainer.removeChild(m.activeScreen)
        m.activeScreen = invalid
    end if
end sub

' ====================================================================
' Tab menu (star short-press) and playlist edit code (star long-press)
' ====================================================================

sub ToggleTabMenu()
    if m.tabMenuOverlay.visible
        CloseTabMenu()
    else
        if m.playerScreen <> invalid then return
        if not m.headerBar.visible then return
        m.tabMenuOverlay.visible = true
        m.tabMenuList.jumpToItem = m.currentTab
        m.tabMenuList.setFocus(true)
    end if
end sub

sub CloseTabMenu()
    m.tabMenuOverlay.visible = false
    if m.activeScreen <> invalid
        m.activeScreen.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub OnTabMenuSelected()
    idx = m.tabMenuList.itemSelected
    CloseTabMenu()
    if idx >= 0 and idx <= 3
        SwitchTab(idx)
    end if
end sub

sub OnOptionsHoldFired()
    ' Timer fired while star was still down = long-press
    m.optionsHeld = true
    ShowEditCodeOverlay()
end sub

sub ShowEditCodeOverlay()
    if m.playerScreen <> invalid then return
    if not m.headerBar.visible then return
    
    m.editCodeOverlay.visible = true
    mac = DeviceMacAddress()
    m.editMacLabel.text = FormatMacForDisplay(mac)
    m.editCodeLabel.text = "------"
    m.editCodeStatus.text = "Generating secure code..."
    if m.editUrlLabel <> invalid then m.editUrlLabel.text = "streamingtvroku.pages.dev"
    
    m.editPin = Player_GeneratePin()
    Storage_SetAuth("setup_pin", m.editPin)
    
    url = SetupUrl(mac, m.editPin)
    if m.editQrPoster <> invalid then m.editQrPoster.uri = QrImageUrl(url)
    
    m.editPollInFlight = false
    m.editPollTimer.control = "stop"
    
    if m.apiTask = invalid
        m.apiTask = CreateObject("roSGNode", "ApiTask")
        m.apiTask.observeField("response", "OnApiResponse")
    end if
    
    m.apiTask.context = "edit_code"
    m.apiTask.action = "player_bind"
    m.apiTask.args = {
        apiBase: m.apiBase,
        mac: mac,
        pin: m.editPin
    }
    m.apiTask.control = "RUN"
end sub

sub OnEditPollTimerFired()
    if not m.editCodeOverlay.visible then return
    if m.editPin = "" then return
    if m.editPollInFlight then return
    
    m.editPollInFlight = true
    mac = DeviceMacAddress()
    m.apiTask.context = "edit_poll"
    m.apiTask.action = "player_fetch_payload"
    m.apiTask.args = {
        apiBase: m.apiBase,
        mac: mac,
        pin: m.editPin
    }
    m.apiTask.control = "RUN"
end sub

sub OnApiResponse()
    resp = m.apiTask.response
    if resp = invalid then return
    
    if resp.context = "edit_code"
        if resp.success and resp.data <> invalid and resp.data.success
            pin = ""
            if m.editPin <> invalid then pin = m.editPin
            if Len(pin) >= 6
                m.editCodeLabel.text = Left(pin, 3) + " " + Right(pin, Len(pin) - 3)
            else
                m.editCodeLabel.text = pin
            end if
            m.editCodeStatus.text = "Scan the QR or open streamingtvroku.pages.dev and enter the device ID and PIN."
            m.editPollTimer.control = "start"
        else
            m.editCodeStatus.text = "Could not create an edit code. Try again in a moment."
        end if
    else if resp.context = "edit_poll"
        m.editPollInFlight = false
        if resp.success and resp.data <> invalid
            data = resp.data
            if data.ready and data.payload <> invalid
                m.editPollTimer.control = "stop"
                ApplyEditedPayload(data.payload)
            end if
        end if
    end if
end sub

sub ApplyEditedPayload(payload as Object)
    cipherB64 = ""
    ivB64 = ""
    if payload.DoesExist("ciphertext") then cipherB64 = payload.ciphertext
    if payload.DoesExist("iv") then ivB64 = payload.iv
    
    mac = DeviceMacAddress()
    plain = AesCbcDecrypt(m.editPin, mac, ivB64, cipherB64)
    if plain = ""
        m.editCodeStatus.text = "Could not read setup data. Press NEW CODE and try again."
        return
    end if
    
    creds = SafeJsonParse(plain)
    if creds = invalid
        m.editCodeStatus.text = "Setup data was invalid. Press NEW CODE and try again."
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
        m.editCodeStatus.text = "Setup data was invalid. Press NEW CODE and try again."
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
        m.editCodeStatus.text = "No server URL in setup data. Press NEW CODE and try again."
        return
    end if
    
    Storage_SetAuth("server_url", CleanServerUrl(serverUrl))
    Storage_SetAuth("username", username)
    Storage_SetAuth("password", password)
    Storage_SetAuth("login_mode", "xc")
    Storage_SetAuth("device_token", "")
    Storage_SetAuth("mac_address", mac)
    Storage_SetAuth("setup_pin", m.editPin)
    
    m.editCodeStatus.text = "Playlists updated! Reloading..."
    CloseEditCodeOverlay()
    SwitchTab(m.currentTab)
end sub

function FormatMacForDisplay(mac as String) as String
    clean = mac
    if Len(clean) = 12
        return Mid(clean, 1, 2) + ":" + Mid(clean, 3, 2) + ":" + Mid(clean, 5, 2) + ":" + Mid(clean, 7, 2) + ":" + Mid(clean, 9, 2) + ":" + Mid(clean, 11, 2)
    end if
    return clean
end function

sub CloseEditCodeOverlay()
    m.editPollTimer.control = "stop"
    m.editPollInFlight = false
    m.editCodeOverlay.visible = false
    if m.activeScreen <> invalid
        m.activeScreen.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    ' Star / Options: short-press = tab menu, hold = playlist edit code
    if key = "options"
        if press
            m.optionsHeld = false
            m.optionsHoldTimer.control = "stop"
            m.optionsHoldTimer.control = "start"
            return true
        else
            m.optionsHoldTimer.control = "stop"
            if m.optionsHeld
                m.optionsHeld = false
                return true
            end if
            ' short-press release
            if m.editCodeOverlay.visible
                CloseEditCodeOverlay()
                return true
            end if
            ToggleTabMenu()
            return true
        end if
    end if
    
    if not press then return false
    
    if m.playerScreen <> invalid
        return false
    end if
    
    if m.editCodeOverlay.visible
        if key = "back"
            CloseEditCodeOverlay()
            return true
        end if
        return true
    end if
    
    if m.tabMenuOverlay.visible
        if key = "back" or key = "options"
            CloseTabMenu()
            return true
        end if
        return false
    end if
    
    if key = "rewind"
        if not m.headerBar.visible then return false
        newTab = m.currentTab - 1
        if newTab < 0 then newTab = 3
        SwitchTab(newTab)
        return true
    else if key = "fastforward"
        if not m.headerBar.visible then return false
        newTab = m.currentTab + 1
        if newTab > 3 then newTab = 0
        SwitchTab(newTab)
        return true
    end if
    
    return false
end function
