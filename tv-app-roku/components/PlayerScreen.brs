' ********************************************************************
' * StreamingTV BETA: PlayerScreen Controller
' * Fullscreen Video node with OSD & D-pad channel zapping.
' ********************************************************************

sub init()
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.bufferingGroup = m.top.findNode("bufferingGroup")
    m.bufferingLabel = m.top.findNode("bufferingLabel")
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorDetailLabel = m.top.findNode("errorDetailLabel")
    
    m.osdGroup = m.top.findNode("osdGroup")
    m.osdBg = m.top.findNode("osdBg")
    m.chnoBadge = m.top.findNode("chnoBadge")
    m.chnoLabel = m.top.findNode("chnoLabel")
    m.channelLogo = m.top.findNode("channelLogo")
    m.channelName = m.top.findNode("channelName")
    m.qualityBadge = m.top.findNode("qualityBadge")
    m.qualityLabel = m.top.findNode("qualityLabel")
    m.programTitle = m.top.findNode("programTitle")
    m.programTime = m.top.findNode("programTime")
    m.osdTimer = m.top.findNode("osdTimer")
    
    m.channelIndex = 0
    m.allChannels = []
    m.currentStreamUrl = ""
    m.serverUrl = Storage_GetAuth("server_url", "")
    m.username = Storage_GetAuth("username", "")
    m.password = Storage_GetAuth("password", "")
    
    m.videoPlayer.observeField("state", "OnPlayerStateChanged")
    m.osdTimer.observeField("fire", "OnOsdTimerFired")
    
    m.epgTask = CreateObject("roSGNode", "ApiTask")
    m.epgTask.observeField("response", "OnEpgResponse")
    
    OnThemeChanged()
end sub

sub OnThemeChanged()
    theme = m.top.theme
    if theme <> invalid
        if m.chnoBadge <> invalid then m.chnoBadge.color = theme.accentPrimary
        if m.qualityBadge <> invalid then m.qualityBadge.color = theme.accentPrimary
        if m.bufferingLabel <> invalid then m.bufferingLabel.color = theme.accentPrimary
    end if
end sub

sub OnMediaDataChanged()
    data = m.top.mediaData
    if data = invalid then return
    
    if data.DoesExist("allChannels") and type(data.allChannels) = "roArray"
        m.allChannels = data.allChannels
    else
        m.allChannels = []
    end if
    
    if data.DoesExist("channelIndex")
        m.channelIndex = data.channelIndex
    else
        m.channelIndex = 0
    end if
    
    if data.DoesExist("streamUrl")
        TuneStream(data.streamUrl, data.channel)
    end if
end sub

sub TuneStream(streamUrl as String, channelInfo as Object)
    m.currentStreamUrl = streamUrl
    m.errorGroup.visible = false
    m.bufferingGroup.visible = true
    
    content = CreateObject("roSGNode", "ContentNode")
    content.url = streamUrl
    if m.top.isLiveStream
        content.streamFormat = "hls"
        content.live = true
    else
        fmt = "mp4"
        lowerUrl = LCase(streamUrl)
        if InStr(1, lowerUrl, ".mkv") > 0 then fmt = "mkv"
        content.streamFormat = fmt
        content.live = false
    end if
    
    m.videoPlayer.content = content
    m.videoPlayer.control = "play"
    
    UpdateOsdInfo(channelInfo)
    ShowOsd()
end sub

sub UpdateOsdInfo(channelInfo as Object)
    if channelInfo = invalid then return
    
    m.channelName.text = channelInfo.name
    m.chnoLabel.text = Str(m.channelIndex + 1).Trim()
    
    if channelInfo.DoesExist("stream_icon") and channelInfo.stream_icon <> ""
        m.channelLogo.uri = channelInfo.stream_icon
    else
        m.channelLogo.uri = "pkg:/images/channel_placeholder.png"
    end if
    
    chLower = LCase(channelInfo.name)
    if InStr(1, chLower, "4k") > 0 or InStr(1, chLower, "uhd") > 0
        m.qualityLabel.text = "4K"
    else if InStr(1, chLower, "fhd") > 0 or InStr(1, chLower, "1080") > 0
        m.qualityLabel.text = "FHD"
    else if InStr(1, chLower, "720") > 0 or InStr(1, chLower, "hd") > 0
        m.qualityLabel.text = "HD"
    else
        m.qualityLabel.text = "LIVE"
    end if
    
    m.programTitle.text = channelInfo.name
    m.programTime.text = "Live Stream"
    
    sid = ""
    if channelInfo.DoesExist("stream_id") then sid = AnyToStr(channelInfo.stream_id)
    if sid <> ""
        m.epgTask.context = "epg"
        m.epgTask.action = "get_short_epg"
        m.epgTask.args = {
            serverUrl: m.serverUrl,
            username: m.username,
            password: m.password,
            streamId: sid
        }
        m.epgTask.control = "RUN"
    end if
end sub

sub OnEpgResponse()
    resp = m.epgTask.response
    if resp = invalid then return
    if not resp.success then return
    epgData = resp.data
    if epgData = invalid or type(epgData) <> "roAssociativeArray" then return
    if not epgData.DoesExist("epg_listings") then return
    listings = epgData.epg_listings
    if type(listings) = "roArray" and listings.Count() > 0
        cur = listings[0]
        if cur.DoesExist("title") then m.programTitle.text = EpgText(cur.title)
        if cur.DoesExist("start") and cur.DoesExist("end")
            m.programTime.text = FormatUnixTime(cur.start) + " - " + FormatUnixTime(cur.end)
        end if
    end if
end sub

sub ShowOsd()
    m.osdGroup.visible = true
    m.osdTimer.control = "stop"
    m.osdTimer.control = "start"
end sub

sub OnOsdTimerFired()
    m.osdGroup.visible = false
end sub

sub OnPlayerStateChanged()
    state = m.videoPlayer.state
    if state = "buffering"
        m.bufferingGroup.visible = true
        m.errorGroup.visible = false
    else if state = "playing"
        m.bufferingGroup.visible = false
        m.errorGroup.visible = false
    else if state = "error"
        m.bufferingGroup.visible = false
        m.errorGroup.visible = true
        errCode = Str(m.videoPlayer.errorCode).Trim()
        errMsg = m.videoPlayer.errorMsg
        m.errorDetailLabel.text = "Error (" + errCode + "): " + errMsg + ". Press Back to exit."
    else if state = "finished"
        if not m.top.isLiveStream
            m.videoPlayer.control = "stop"
            m.top.closePlayer = true
        end if
    end if
end sub

sub ZapChannel(direction as Integer)
    if not m.top.isLiveStream or m.allChannels.Count() = 0 then return
    
    newIndex = m.channelIndex + direction
    if newIndex < 0
        newIndex = m.allChannels.Count() - 1
    else if newIndex >= m.allChannels.Count()
        newIndex = 0
    end if
    
    m.channelIndex = newIndex
    ch = m.allChannels[newIndex]
    sid = ""
    if ch.DoesExist("stream_id") then sid = AnyToStr(ch.stream_id)
    if sid = "" then return
    
    cleanBase = CleanServerUrl(m.serverUrl)
    newUrl = cleanBase + "/live/" + m.username.Trim() + "/" + m.password.Trim() + "/" + sid + ".m3u8"
    
    TuneStream(newUrl, ch)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    
    if key = "back"
        m.videoPlayer.control = "stop"
        m.top.closePlayer = true
        return true
    else if key = "up"
        ZapChannel(-1)
        return true
    else if key = "down"
        ZapChannel(1)
        return true
    else if key = "OK" or key = "info"
        if m.osdGroup.visible
            m.osdGroup.visible = false
            m.osdTimer.control = "stop"
        else
            ShowOsd()
        end if
        return true
    else if key = "play"
        if m.videoPlayer.state = "playing"
            m.videoPlayer.control = "pause"
        else if m.videoPlayer.state = "paused"
            m.videoPlayer.control = "resume"
        end if
        return true
    end if
    
    return false
end function
